const std = @import("std");
const Server = @import("server.zig").Server;
const configuration = @import("configuration.zig");

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    var settings = configuration.Settings.init(gpa) catch |err| switch (err) {
        configuration.ConfigError.HelpRequested => return,
        else => return err,
    };
    defer settings.deinit();

    var server = try Server.init(settings, gpa);
    try server.run();
}

test {
    std.testing.refAllDecls(@This());
}
