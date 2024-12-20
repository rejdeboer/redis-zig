const std = @import("std");
const posix = std.posix;
const Database = @import("db.zig").Database;
const DList = @import("dlist.zig").DList;
const parsing = @import("parser.zig");
const encoding = @import("encoding.zig");

/// Note: This is just for convenience, the actual implementation has a limit of 512Mb
const MAX_MESSAGE_SIZE: usize = 4096;

const ConnectionState = union(enum) {
    state_req,
    state_res,
};

pub const Connection = struct {
    gpa: std.mem.Allocator,
    fd: i32 = -1,
    state: ConnectionState = .state_req,
    rbuf_size: usize = 0,
    /// Read buffer
    rbuf: [MAX_MESSAGE_SIZE]u8,
    wbuf_size: usize = 0,
    wbuf_sent: usize = 0,
    /// Write buffer
    wbuf: [MAX_MESSAGE_SIZE]u8,
    idle_start_ms: i64,
    idle_list: DList,
    db: *Database,

    const Self = @This();

    pub fn init(listener_fd: i32, db: *Database, server_idle_list: *DList, gpa: std.mem.Allocator) !*Self {
        const conn_fd = try posix.accept(listener_fd, null, null, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
        const self = try gpa.create(Self);
        self.fd = conn_fd;
        self.wbuf_size = 0;
        self.rbuf_size = 0;
        self.wbuf_sent = 0;
        self.idle_start_ms = std.time.milliTimestamp();
        self.db = db;
        self.gpa = gpa;
        server_idle_list.prepend(&self.idle_list);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.idle_list.detach();
        posix.close(self.fd);
        self.gpa.destroy(self);
    }

    pub fn update(self: *Self, server_idle_list: *DList) !void {
        self.idle_start_ms = std.time.milliTimestamp();
        self.idle_list.detach();
        server_idle_list.prepend(&self.idle_list);
        switch (self.state) {
            .state_req => try self.handle_read(),
            .state_res => try self.handle_write(),
        }
    }

    fn handle_read(self: *Self) !void {
        var bytes_read: usize = undefined;
        // TODO: Handle the case where self.rbuf_size >= self.rbuf.len
        while (bytes_read != 0 and self.rbuf_size < self.rbuf.len) {
            bytes_read = posix.read(self.fd, self.rbuf[self.rbuf_size..]) catch |err| switch (err) {
                posix.ReadError.WouldBlock => return self.handle_command(),
                else => return err,
            };
            self.rbuf_size += bytes_read;
        }
        std.debug.assert(self.rbuf_size < self.rbuf.len);
        // 0 Bytes read means EOF, client closed connection
        return parsing.ParsingError.EOF;
    }

    pub fn handle_write(self: *Self) !void {
        while (self.wbuf_sent < self.wbuf_size) {
            self.wbuf_sent += posix.write(self.fd, self.wbuf[self.wbuf_sent..self.wbuf_size]) catch |err| switch (err) {
                posix.WriteError.WouldBlock => return,
                else => return err,
            };
        }
        self.wbuf_size = 0;
        self.wbuf_sent = 0;
        self.state = .state_req;
    }

    pub fn timeout_read(self: *Self) void {
        self.write_error("INVALID ENCODING");
    }

    fn handle_command(self: *Self) void {
        var parser = parsing.Parser.init(self.rbuf[0..self.rbuf_size], self.gpa);

        const command = parser.parse_command() catch |err| switch (err) {
            error.Unexpected => return self.write_error("UNEXPECTED COMMAND"),
            error.EOF => return,
        };
        defer self.start_writing();
        switch (command) {
            .ping => |msg| {
                if (msg) |m| {
                    return self.write_bulk_string(m);
                }
                self.write_simple_string("PONG");
            },
            .echo => |msg| {
                self.write_bulk_string(msg);
            },
            .get => |key| {
                std.log.info("getting value for key {s}", .{key});
                if (self.db.get(key)) |entry| {
                    return self.write_value(entry.value) catch {
                        std.log.err("wbuf too small", .{});
                        return self.write_error("UNEXPECTED ERROR");
                    };
                }
                return self.write_error("KEY NOT FOUND");
            },
            .set => |kv| {
                self.db.put(kv.key, kv.entry) catch {
                    std.log.err("out of memory", .{});
                    return self.write_error("SET FAILED");
                };
                self.write_simple_string("OK");
            },
            .config_get => |key| {
                self.wbuf_size = self.db.encode_config_key(&self.wbuf, key) catch {
                    std.log.err("wbuf too small", .{});
                    return self.write_error("UNEXPECTED ERROR");
                };
            },
            .save => {
                self.db.store_snapshot();
                self.write_simple_string("OK");
            },
            .command_docs => {
                var encoder = encoding.ListEncoder.init(&self.wbuf);
                encoder.write_length() catch unreachable;
                self.wbuf_size = encoder.n_bytes;
            },
        }
    }

    fn write_error(self: *Self, err: []const u8) void {
        self.wbuf_size = encoding.encode_err(&self.wbuf, err) catch unreachable;
    }

    fn write_simple_string(self: *Self, value: []const u8) void {
        self.wbuf_size = encoding.encode_simple_string(&self.wbuf, value) catch unreachable;
    }

    fn write_bulk_string(self: *Self, value: []const u8) void {
        self.wbuf_size = encoding.encode_bulk_string(&self.wbuf, value) catch unreachable;
    }

    fn write_value(self: *Self, value: parsing.RedisValue) !void {
        self.wbuf_size = switch (value) {
            .string => |v| try encoding.encode_bulk_string(&self.wbuf, v),
            .int => |v| try encoding.encode_int(&self.wbuf, v),
            .boolean => |v| try encoding.encode_bool(&self.wbuf, v),
            .float => |v| try encoding.encode_float(&self.wbuf, v),
        };
    }

    fn start_writing(self: *Self) void {
        self.rbuf_size = 0;
        self.state = .state_res;
        self.handle_write() catch unreachable;
    }
};
