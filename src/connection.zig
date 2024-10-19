const std = @import("std");
const posix = std.posix;
const config = @import("configuration.zig");
const mem = @import("memory.zig");

const ConnectionState = union(enum) {
    state_req,
    state_res,
};

pub const Connection = struct {
    gpa: std.mem.Allocator,
    fd: i64 = -1,
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

    pub fn init(listener_fd: i64, memory: *mem.Memory, gpa: std.mem.Allocator) !*Self {
        const conn_fd = try posix.accept(listener_fd, null, null, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);
        const conn = try gpa.create(Connection);
        conn.fd = conn_fd;
        conn.memory = memory;
        return conn;
    }

    pub fn deinit(self: *Self) void {
        self.gpa.free(self.rbuf);
        self.gpa.free(self.wbuf);
        posix.close(self.fd);
    }

    pub fn update(self: *Self) !void {
        switch (self.state) {
            .state_req => try self.handle_read(),
        }
    }

    fn handle_read(self: *Self) !void {
        var bytes_read: usize = -1;
        while (bytes_read != 0 and self.rbuf_size < self.rbuf.len) {
            const cap = self.rbuf.len - self.rbuf_size;
            bytes_read = posix.read(self.fd, &self.rbuf[self.rbuf_size], cap) catch |err| {
                switch (err) {
                    .WouldBlock => return,
                    else => return err,
                }
            };
            self.rbuf_size += bytes_read;
        }
    }
};
