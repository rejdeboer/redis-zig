const std = @import("std");
const net = std.net;

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    const stdout = std.io.getStdOut().writer();

    const address = try net.Address.resolveIp("127.0.0.1", 6379);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        const connection = try listener.accept();

        _ = try std.Thread.spawn(.{}, handle_client, .{ stdout, &gpa, connection });
    }
}

fn handle_client(stdout: anytype, gpa: *const std.mem.Allocator, connection: net.Server.Connection) !void {
    defer connection.stream.close();

    const reader = connection.stream.reader();
    const writer = connection.stream.writer();
    try stdout.print("accepted new connection", .{});

    while (true) {
        const msg = try reader.readUntilDelimiterOrEofAlloc(gpa.*, '\n', 65536) orelse break;
        defer gpa.free(msg);

        std.log.info("Received message: \"{}\"", .{std.zig.fmtEscapes(msg)});
        try writer.writeAll("+PONG\r\n");
    }
}
