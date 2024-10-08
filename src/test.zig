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

test "ping pong" {
    try start_test_server();
    var redis = try client.Redis.connect("127.0.0.1", 6379);
    defer redis.close();
    const msg = try redis.send([]const u8, "*1\r\n$4\r\nPING\r\n");
    try std.testing.expect(std.mem.eql(u8, "PONG", msg));
}

test "echo" {
    try start_test_server();
    var redis = try client.Redis.connect("127.0.0.1", 6379);
    defer redis.close();
    const msg = try redis.send([]const u8, "*2\r\n$4\r\nECHO\r\n$4\r\ntest\r\n");
    try std.testing.expect(std.mem.eql(u8, "test", msg));
}

test "set get" {
    try start_test_server();
    var redis = try client.Redis.connect("127.0.0.1", 6379);
    defer redis.close();
    const set_response = try redis.send([]const u8, "*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$3\r\nbar\r\n");
    try std.testing.expect(std.mem.eql(u8, "OK", set_response));
    const get_response = try redis.send([]const u8, "*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n");
    try std.testing.expect(std.mem.eql(u8, "bar", get_response));
}
