const std = @import("std");
const net = std.net;

// Note: This client is not thread-safe
pub const Redis = struct {
    stream: net.Stream,
    buffer: [1024]u8,

    const Self = @This();

    pub fn connect(host: []const u8, port: u16) !Self {
        const address = try net.Address.parseIp4(host, port);
        const stream = try net.tcpConnectToAddress(address);

        return Self{
            .stream = stream,
            .buffer = undefined,
        };
    }

    pub fn ping(self: *Self) !bool {
        const writer = self.stream.writer();
        try writer.writeAll("+PING\r\n");
        const reader = self.stream.reader();
        const bytes_read = try reader.read(&self.buffer);
        const msg = self.buffer[0..bytes_read];
        return std.mem.eql(u8, "+PONG\r\n", msg);
    }

    // pub fn echo(self: *Self, message: []const u8) !bool {}
    //
    // pub fn get(self: *Self, comptime T: type, key: []const u8) ?T {
    //     return undefined;
    // }
    //
    // pub fn set(self: *Self, comptime T: type, key: []const u8, value: T) !void {
    //     return error.Todo;
    // }

    pub fn send(self: *Self, command: []const u8) ![]const u8 {
        const writer = self.stream.writer();
        try writer.writeAll(command);
        const reader = self.stream.reader();
        const bytes_read = try reader.read(&self.buffer);
        return self.buffer[0..bytes_read];
    }

    pub fn close(self: Self) void {
        self.stream.close();
    }
};
