const std = @import("std");
const net = std.net;
const parser = @import("parser");

// Note: This client is not thread-safe
pub const Redis = struct {
    stream: net.Stream,
    reader: parser.Parser,

    const Self = @This();

    pub fn connect(host: []const u8, port: u16) !Self {
        const address = try net.Address.parseIp4(host, port);
        const stream = try net.tcpConnectToAddress(address);

        return Self{
            .stream = stream,
            .reader = parser.Parser.init(&stream.reader(), null),
        };
    }

    pub fn send(self: *Self, comptime T: type, command: []const u8) ![]const u8 {
        const writer = self.stream.writer();
        try writer.writeAll(command);
        return try self.reader.parse(T, false);
    }

    pub fn close(self: Self) void {
        self.stream.close();
    }
};
