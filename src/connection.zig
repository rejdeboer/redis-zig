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

    pub fn init(listener_fd: i32, memory: *mem.Memory, gpa: std.mem.Allocator) !*Self {
        const conn_fd = try posix.accept(listener_fd, null, null, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
        const conn = try gpa.create(Connection);
        conn.fd = conn_fd;
        std.log.info("ETETE {}", .{conn.fd});
        conn.memory = memory;
        return conn;
    }

    pub fn deinit(self: *Self) void {
        self.gpa.free(&self.rbuf);
        self.gpa.free(&self.wbuf);
        posix.close(self.fd);
    }

    pub fn update(self: *Self) !void {
        switch (self.state) {
            .state_req => try self.handle_read(),
            .state_res => std.log.info("NICE", .{}),
        }
    }

    fn handle_read(self: *Self) !void {
        var bytes_read: usize = 1;
        while (bytes_read != 0 and self.rbuf_size < self.rbuf.len) {
            bytes_read = posix.read(self.fd, self.rbuf[self.rbuf_size..]) catch |err| {
                switch (err) {
                    posix.ReadError.WouldBlock => return,
                    else => return err,
                }
            };
            self.rbuf_size += bytes_read;
        }
        std.debug.assert(self.rbuf_size <= self.rbuf.len);
        try self.handle_command();
    }

    fn handle_command(self: *Self) !void {
        defer self.rbuf_size = 0;
        var parser = parsing.Parser.init(&self.rbuf, &self.gpa);

        const command = parser.parse_command() catch {
            return self.set_response("-UNEXPECTED COMMAND", .{});
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
        self.state = .state_res;
    }
};
