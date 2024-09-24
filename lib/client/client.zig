const std = @import("std");
const net = std.net;

// Note: This client is not thread-safe
pub const Redis = struct {
    stream: net.Stream,
    buffer: [1024]u8,

    pub fn connect(host: []const u8, port: u16) !Redis {
        const address = try net.Address.parseIp4(host, port);
        const stream = try net.tcpConnectToAddress(address);

        return Redis{
            .stream = stream,
            .buffer = undefined,
        };
    }

    pub fn ping(self: *Redis) !bool {
        const writer = self.stream.writer();
        try writer.writeAll("+PING\r\n");
        const reader = self.stream.reader();
        const bytes_read = try reader.read(&self.buffer);
        const msg = self.buffer[0..bytes_read];
        return std.mem.eql(u8, "+PONG\r\n", msg);
    }

    pub fn close(self: Redis) void {
        self.stream.close();
    }
};
