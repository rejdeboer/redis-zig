const std = @import("std");
const net = std.net;

const Redis = struct {
    stream: net.Stream,

    pub fn connect(host: []const u8, port: u16) !Redis {
        const address = try net.Address.parseIp4(host, port);
        const stream = try net.tcpConnectToAddress(address);

        return Redis{
            .stream = stream,
        };
    }

    pub fn ping(self: Redis) !void {
        const writer = self.stream.writer();
        const _reader = self.stream.reader();
        try writer.writeAll("+PING\r\n");
    }

    pub fn close(self: Redis) void {
        self.stream.close();
    }
};
