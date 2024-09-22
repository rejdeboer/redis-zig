const server = @import("server.zig");

pub fn main() !void {
    const settings = server.Settings{
        .host = "127.0.0.1",
        .port = 6379,
    };
    try server.start(settings);
}
