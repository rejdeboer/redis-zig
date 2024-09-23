const server = @import("../server/server.zig");
const std = @import("std");

pub fn start_test_server() !void {
    // var rnd = std.rand.DefaultPrng.init(0);
    server.start(server.Settings{
        .host = "localhost",
        .port = "6379",
    });
}
