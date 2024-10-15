const std = @import("std");
const net = std.net;
const parser = @import("parser");
const mem = @import("memory.zig");

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

    var memory = mem.Memory.init(&gpa);
    defer memory.deinit();

    while (true) {
        const connection = try listener.accept();

        _ = try std.Thread.spawn(.{}, handle_client, .{ &gpa, connection, &memory });
    }
}

fn handle_client(gpa: *const std.mem.Allocator, connection: net.Server.Connection, memory: *mem.Memory) !void {
    defer connection.stream.close();

    var reader = parser.Parser.init(&connection.stream.reader(), gpa);
    const writer = connection.stream.writer();
    std.log.info("accepted new connection", .{});

    while (true) {
        const command = reader.parse_command() catch {
            try writer.writeAll("-UNEXPECTED COMMAND\r\n");
            break;
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
                if (memory.get(key)) |entry| {
                    switch (entry.value) {
                        .string => |v| try std.fmt.format(writer, "${}\r\n{s}\r\n", .{ v.len, v }),
                        .int => |v| try std.fmt.format(writer, ":{}\r\n", .{v}),
                        .boolean => |v| try std.fmt.format(writer, "#{s}\r\n", .{if (v) "t" else "f"}),
                        .float => |v| try std.fmt.format(writer, ",{d}\r\n", .{v}),
                    }
                } else {
                    try writer.writeAll("-KEY NOT FOUND\r\n");
                }
            },
            .set => |kv| {
                memory.put(kv.key, kv.entry) catch {
                    std.log.err("out of memory", .{});
                    try writer.writeAll("-SET FAILED\r\n");
                    continue;
                };
                try writer.writeAll("+OK\r\n");
            },
        }
    }
}
