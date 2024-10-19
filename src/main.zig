const std = @import("std");
const server = @import("server.zig");
const configuration = @import("configuration.zig");

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    var settings = configuration.Settings.init(gpa);

    defer settings.deinit();

    var s = server.Server.init(settings, gpa);
    try s.start();
}
