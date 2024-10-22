const std = @import("std");
const posix = std.posix;
const mem = @import("memory.zig");
const DList = @import("dlist.zig").DList;
const parsing = @import("parser.zig");

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
    memory: *mem.Memory,

    const Self = @This();

    pub fn init(listener_fd: i32, memory: *mem.Memory, server_idle_list: *DList, gpa: std.mem.Allocator) !*Self {
        const conn_fd = try posix.accept(listener_fd, null, null, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
        const self = try gpa.create(Self);
        self.fd = conn_fd;
        self.wbuf_size = 0;
        self.rbuf_size = 0;
        self.wbuf_sent = 0;
        self.idle_start_ms = std.time.milliTimestamp();
        self.memory = memory;
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
            self.wbuf_sent += posix.write(self.fd, self.wbuf[self.wbuf_sent..]) catch |err| switch (err) {
                posix.WriteError.WouldBlock => return,
                else => return err,
            };
        }
        self.wbuf_size = 0;
        self.wbuf_sent = 0;
        self.state = .state_req;
    }

    pub fn timeout_read(self: *Self) void {
        self.set_response("-INVALID ENCODING", .{});
    }

    fn handle_command(self: *Self) void {
        var parser = parsing.Parser.init(self.rbuf[0..self.rbuf_size], self.gpa);

        const command = parser.parse_command() catch |err| switch (err) {
            error.Unexpected => return self.set_response("-UNEXPECTED COMMAND\r\n", .{}),
            error.EOF => return,
        };
        switch (command) {
            .ping => |msg| {
                if (msg != null) {
                    return self.set_response("${}\r\n{s}\r\n", .{ msg.?.len, msg.? });
                }
                self.set_response("+PONG\r\n", .{});
            },
            .echo => |msg| {
                self.set_response("${}\r\n{s}\r\n", .{ msg.len, msg });
            },
            .get => |key| {
                std.log.info("getting value for key {s}", .{key});
                if (self.memory.get(key)) |entry| {
                    switch (entry.value) {
                        .string => |v| self.set_response("${}\r\n{s}\r\n", .{ v.len, v }),
                        .int => |v| self.set_response(":{}\r\n", .{v}),
                        .boolean => |v| self.set_response("#{s}\r\n", .{if (v) "t" else "f"}),
                        .float => |v| self.set_response(",{d}\r\n", .{v}),
                    }
                } else {
                    self.set_response("-KEY NOT FOUND\r\n", .{});
                }
            },
            .set => |kv| {
                self.memory.put(kv.key, kv.entry) catch {
                    std.log.err("out of memory", .{});
                    return self.set_response("-SET FAILED\r\n", .{});
                };
                self.set_response("+OK\r\n", .{});
            },
            .config_get => |_| {
                self.set_response("-TODO\r\n", .{});
            },
        }
    }

    fn set_response(self: *Self, comptime format: []const u8, args: anytype) void {
        const slice = std.fmt.bufPrint(&self.wbuf, format, args) catch unreachable;
        self.wbuf_size = slice.len;
        self.rbuf_size = 0;
        self.state = .state_res;
        self.handle_write() catch unreachable;
    }
};
