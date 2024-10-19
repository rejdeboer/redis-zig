const std = @import("std");
const posix = std.posix;
const config = @import("configuration.zig");

const ConnectionState = union(enum) {
    state_req,
    state_res,
    state_end,
};

pub const Connection = struct {
    fd: i64 = -1,
    state: ConnectionState = .state_req,
    rbuf_size: usize = 0,
    /// Read buffer
    rbuf: [config.MAX_MESSAGE_SIZE]u8,
    wbuf_size: usize = 0,
    wbuf_sent: usize = 0,
    /// Write buffer
    wbuf: [config.MAX_MESSAGE_SIZE]u8,

    const Self = @This();

    pub fn update(self: *Self) void {
        switch (self.state) {
            .state_req => self.handle_request(),
            .state_end => unreachable,
        }
    }

    fn handle_request(self: *Self) void {
        var bytes_read: usize = -1;
        while (bytes_read != 0 and self.rbuf_size < self.rbuf.len) {
            const cap = self.rbuf.len - self.rbuf_size;
            bytes_read = posix.read(self.fd, &self.rbuf[self.rbuf_size], cap) catch |err| {
                switch (err) {
                    .WouldBlock => return,
                    else => {
                        self.state = .state_end;
                        return;
                    },
                }
            };
            self.rbuf_size += bytes_read;
        }
    }
};
