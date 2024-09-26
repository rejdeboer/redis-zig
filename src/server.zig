const std = @import("std");
const net = std.net;
const parser = @import("parser");

pub const Settings = struct {
    host: []const u8,
    port: u16,
};

pub fn start(settings: Settings) !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    const address = try net.Address.resolveIp(settings.host, settings.port);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    std.log.info("starting server on port: {}", .{settings.port});

    while (true) {
        const connection = try listener.accept();

        _ = try std.Thread.spawn(.{}, handle_client, .{ &gpa, connection });
    }
}

fn handle_client(gpa: *const std.mem.Allocator, connection: net.Server.Connection) !void {
    defer connection.stream.close();

    const reader = connection.stream.reader();
    const writer = connection.stream.writer();
    std.log.info("accepted new connection", .{});

    var buffer: [1024]u8 = undefined;
    var values = std.StringHashMap([]const u8).init(gpa.*);
    defer values.deinit();

    while (true) {
        const read_bytes = try reader.read(&buffer);
        if (read_bytes == 0) break;

        const message = buffer[0..read_bytes];
        std.log.info("received message: \"{}\"", .{message});
        const response = switch (parser.parse(message)) {
            .ping => |msg| {
                if (msg != null) {
                    return '+' ++ msg ++ "\r\n";
                }
                return "+PONG\r\n";
            },
            .echo => |msg| {
                return '+' ++ msg ++ "\r\n";
            },
            .get => |key| {
                const value = values.get(key);
                if (value) {
                    return '+' ++ value ++ "\r\n";
                }
                return "-todo";
            },
            .set => |kv| {
                values.put(kv.key, kv.value);
                return "+todo";
            },
            .err => |err| switch (err) {
                .Unexpected => "-unexpected command",
            },
        };

        try writer.writeAll(response);
        std.log.info("replied with: {s}", .{response});
    }
}
