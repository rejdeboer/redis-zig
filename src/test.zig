const std = @import("std");
const Server = @import("server.zig").Server;
const config = @import("configuration.zig");
const client = @import("client.zig");

const LOCALHOST: []const u8 = "127.0.0.1";

// TODO: Find a way to run integration tests using threads
// pub fn start_test_server() !Server {
//     const settings = config.Settings{
//         .port = 6379,
//         .bind = LOCALHOST,
//     };
//     var server = try Server.init(settings, std.testing.allocator);
//     _ = try std.Thread.spawn(.{}, Server.run, .{&server});
//     return server;
// }

test "ping pong" {
    var redis = try client.Redis.connect(LOCALHOST, 6379);
    defer redis.close();
    const msg = try redis.send([]const u8, "*1\r\n$4\r\nPING\r\n");
    try std.testing.expect(std.mem.eql(u8, "PONG", msg));
}

test "echo" {
    var redis = try client.Redis.connect(LOCALHOST, 6379);
    defer redis.close();
    const msg = try redis.send([]const u8, "*2\r\n$4\r\nECHO\r\n$4\r\ntest\r\n");
    try std.testing.expect(std.mem.eql(u8, "test", msg));
}

test "set get string" {
    var redis = try client.Redis.connect(LOCALHOST, 6379);
    defer redis.close();
    const set_response = try redis.send([]const u8, "*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$3\r\nbar\r\n");
    try std.testing.expect(std.mem.eql(u8, "OK", set_response));
    const get_response = try redis.send([]const u8, "*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n");
    try std.testing.expect(std.mem.eql(u8, "bar", get_response));
}

test "set get bool" {
    var redis = try client.Redis.connect(LOCALHOST, 6379);
    defer redis.close();
    const set_response = try redis.send([]const u8, "*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n#t\r\n");
    try std.testing.expect(std.mem.eql(u8, "OK", set_response));
    const get_response = try redis.send(bool, "*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n");
    try std.testing.expect(get_response);
}

test "set get int" {
    var redis = try client.Redis.connect(LOCALHOST, 6379);
    defer redis.close();
    const set_response = try redis.send([]const u8, "*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n:42\r\n");
    try std.testing.expect(std.mem.eql(u8, "OK", set_response));
    const get_response = try redis.send(i32, "*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n");
    try std.testing.expect(get_response == 42);
}

test "set get float" {
    var redis = try client.Redis.connect(LOCALHOST, 6379);
    defer redis.close();
    const set_response = try redis.send([]const u8, "*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n,1.23\r\n");
    try std.testing.expect(std.mem.eql(u8, "OK", set_response));
    const get_response = try redis.send(f32, "*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n");
    try std.testing.expect(get_response == 1.23);
}

test "set get expired" {
    var redis = try client.Redis.connect(LOCALHOST, 6379);
    defer redis.close();
    const set_response = try redis.send([]const u8, "*5\r\n$3\r\nSET\r\n$3\r\nexp\r\n$3\r\nbar\r\n$2\r\nEX\r\n$1\r\n0\r\n");
    try std.testing.expect(std.mem.eql(u8, "OK", set_response));
    const get_response = try redis.send([]const u8, "*2\r\n$3\r\nGET\r\n$3\r\nexp\r\n");
    try std.testing.expect(std.mem.eql(u8, "KEY NOT FOUND", get_response));
}

test "set get not expired" {
    var redis = try client.Redis.connect(LOCALHOST, 6379);
    defer redis.close();
    const set_response = try redis.send([]const u8, "*5\r\n$3\r\nSET\r\n$3\r\nabc\r\n$3\r\nbar\r\n$2\r\nEX\r\n$3\r\n999\r\n");
    try std.testing.expect(std.mem.eql(u8, "OK", set_response));
    const get_response = try redis.send([]const u8, "*2\r\n$3\r\nGET\r\n$3\r\nabc\r\n");
    try std.testing.expect(std.mem.eql(u8, "bar", get_response));
}
