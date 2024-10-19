const std = @import("std");
const net = std.net;
const posix = std.posix;
const parser = @import("parser");
const mem = @import("memory.zig");
const config = @import("configuration.zig");
const connection = @import("connection.zig");

pub const Server = struct {
    gpa: std.mem.Allocator,
    settings: config.Settings,
    memory: mem.Memory,
    stop: bool = false,

    const Self = @This();

    pub fn init(settings: config.Settings, gpa: std.mem.Allocator) Self {
        const memory = mem.Memory.init(gpa);
        return .{ gpa, settings, memory };
    }

    pub fn deinit(self: *Self) void {
        self.memory.deinit();
    }

    pub fn start(self: *Self) !void {
        // Create a non blocking TCP socket
        const fd = posix.socket(posix.AF.INET, posix.SOCK.STREAM | posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK, 0) catch {
            return std.log.err("error creating socket", .{});
        };

        std.log.info("starting server on port: {}", .{self.settings.port});
        const address = try net.Address.resolveIp(self.settings.bind, self.settings.port);
        var rv = posix.connect(fd, address.any, address.getOsSockLen());
        if (rv > 0) {
            std.log.warn("rv > 0, is this ok?");
        }

        const connections = std.ArrayList(*connection.Connection).init(self.gpa);
        defer connections.deinit();
        var poll_args = std.ArrayList(posix.pollfd).init(self.gpa);
        defer poll_args.deinit();
        while (!self.stop) {
            poll_args.clearAndFree();
            try poll_args.append(.{ fd, posix.POLL.IN, 0 });

            for (connections.items) |conn| {
                if (conn == undefined) {
                    continue;
                }
                const p_byte = if (conn.state == .state_req) posix.POLL.IN else posix.POLL.OUT;
                poll_args.append(.{ conn.fd, p_byte | posix.POLL.ERR, 0 });
            }

            rv = posix.poll(poll_args.items, poll_args.capacity, 1000);
            if (rv < 0) {
                std.log.warn("rv < 0 in event loop, is this ok?");
            }

            // Process active connections
            for (poll_args.items[1..]) |arg| {
                if (arg.revents > 0) {
                    const conn = connections.items[arg.fd];
                    conn.update();
                    if (conn.state == .state_end) {
                        connections.items[conn.fd] = undefined;
                        posix.close(conn.fd);
                    }
                }
            }

            // Check if listener is active
            if (poll_args.items[0].revents > 0) {
                const conn = try connection.Connection.init(fd, self.gpa);
                if (connections.capacity < conn.fd) {
                    try connections.resize(conn.fd + 1);
                    connections[conn.fd] = conn;
                }
            }
        }
    }
};

fn handle_client(gpa: *const std.mem.Allocator, conn: net.Server.Connection, memory: *mem.Memory) !void {
    defer conn.stream.close();

    var reader = parser.Parser.init(&conn.stream.reader(), gpa);
    const writer = conn.stream.writer();
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
            .config_get => |_| {
                try writer.writeAll("-TODO\r\n");
            },
        }
    }
}
