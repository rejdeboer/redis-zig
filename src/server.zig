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

    var reader = parser.Parser.init(&connection.stream.reader(), gpa);
    const writer = connection.stream.writer();
    std.log.info("accepted new connection", .{});

    var values = std.StringHashMap([]const u8).init(gpa.*);
    defer values.deinit();

    while (true) {
        const command = reader.parse_command() catch {
            try writer.writeAll("-unexpected command");
            return;
        };
        switch (command) {
            .ping => |msg| {
                if (msg != null) {
                    try std.fmt.format(writer, "${}\r\n{s}\r\n", .{ msg.?.len, msg.? });
                }
                try writer.writeAll("+PONG\r\n");
            },
            .echo => |msg| {
                try std.fmt.format(writer, "${}\r\n{s}\r\n", .{ msg.len, msg });
            },
            .get => |key| {
                std.log.info("getting value for key {s}", .{key});
                if (values.get(key)) |value| {
                    try std.fmt.format(writer, "${}\r\n{s}\r\n", .{ value.len, value });
                } else {
                    try writer.writeAll("-todo\r\n");
                }
            },
            .set => |kv| {
                std.log.info("setting key {s} to value {s}", .{ kv.key, kv.value });
                try values.put(kv.key, kv.value);
                try writer.writeAll("+OK\r\n");
            },
        }
    }
}
