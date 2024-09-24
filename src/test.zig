const std = @import("std");
const server = @import("server.zig");
const client = @import("client");

pub fn start_test_server() !void {
    // var rnd = std.rand.DefaultPrng.init(0);
    _ = try std.Thread.spawn(.{}, server.start, .{server.Settings{
        .host = "127.0.0.1",
        .port = 6379,
    }});
}

test "test ping pong" {
    try start_test_server();
    var redis = try client.Redis.connect("127.0.0.1", 6379);
    defer redis.close();
    try std.testing.expect(try redis.ping());
}
