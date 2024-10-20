const std = @import("std");
const posix = std.posix;
const config = @import("configuration.zig");
const mem = @import("memory.zig");
const parsing = @import("parser");

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
    rbuf: [config.MAX_MESSAGE_SIZE]u8,
    wbuf_size: usize = 0,
    wbuf_sent: usize = 0,
    /// Write buffer
    wbuf: [config.MAX_MESSAGE_SIZE]u8,
    memory: *mem.Memory,

    const Self = @This();

    pub fn init(listener_fd: i32, memory: *mem.Memory, gpa: std.mem.Allocator) !Self {
        const conn_fd = try posix.accept(listener_fd, null, null, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
        return Self{ .fd = conn_fd, .rbuf = undefined, .wbuf = undefined, .gpa = gpa, .memory = memory };
    }

    pub fn deinit(self: *Self) void {
        posix.close(self.fd);
    }

    pub fn update(self: *Self) !void {
        switch (self.state) {
            .state_req => try self.handle_read(),
            .state_res => try self.handle_write(),
        }
    }

    fn handle_read(self: *Self) !void {
        var bytes_read: usize = 0;
        while (self.rbuf_size < self.rbuf.len) {
            bytes_read = posix.read(self.fd, self.rbuf[self.rbuf_size..]) catch |err| switch (err) {
                posix.ReadError.WouldBlock => return self.handle_command(),
                else => return err,
            };
            self.rbuf_size += bytes_read;
        }
        std.debug.assert(self.rbuf_size <= self.rbuf.len);
        self.handle_command();
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

    fn handle_command(self: *Self) void {
        var parser = parsing.Parser.init(&self.rbuf, self.rbuf_size, &self.gpa);

        const command = parser.parse_command() catch |err| switch (err) {
            error.Unexpected => return self.set_response("-UNEXPECTED COMMAND", .{}),
            // Not yet finished reading
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
