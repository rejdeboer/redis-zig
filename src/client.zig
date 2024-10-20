const std = @import("std");
const net = std.net;
const parser = @import("parser.zig");

/// Note: This client is not thread-safe
pub const Redis = struct {
    stream: net.Stream,
    buf: [4096]u8,
    buf_len: usize,

    const Self = @This();

    pub fn connect(host: []const u8, port: u16) !Self {
        const address = try net.Address.parseIp4(host, port);
        const stream = try net.tcpConnectToAddress(address);

        return Self{
            .stream = stream,
            .buf = undefined,
            .buf_len = 0,
        };
    }

    pub fn send(self: *Self, comptime T: type, command: []const u8) !T {
        defer self.buf_len = 0;
        try self.stream.writeAll(command);
        return try self.read(T);
    }

    pub fn close(self: Self) void {
        self.stream.close();
    }

    fn read(self: *Self, comptime T: type) !T {
        self.buf_len += try self.stream.read(&self.buf);
        var p = parser.Parser.init(&self.buf, self.buf_len, null);
        return p.parse(T, false) catch |err| switch (err) {
            error.EOF => self.read(T),
            else => err,
        };
    }
};
