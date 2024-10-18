const std = @import("std");
const net = std.net;
const posix = std.posix;
const parser = @import("parser");
const mem = @import("memory.zig");
const config = @import("configuration.zig");

pub const ConnectionState = union(enum) {
    state_req,
    state_res,
    state_end,
};

pub const Connection = struct {
    fd: i64 = -1,
    state: ConnectionState = .state_req,
    rbuf_size: usize = 0,
    /// Read buffer
    rbuf: [4 + config.MAX_MESSAGE_SIZE]u8,
    wbuf_size: usize = 0,
    wbuf_sent: usize = 0,
    /// Write buffer
    wbuf: [4 + config.MAX_MESSAGE_SIZE]u8,

    const Self = @This();

    pub fn update(self: *Self) void {
        switch (self.state) {
            .state_req => self.handle_request(),
            .state_end => unreachable,
        }
    }

    fn handle_request(self: *Self) void {
        while (true) {
            std.debug.assert(self.rbuf_size <= self.rbuf.len);

            const cap = self.rbuf.len - self.rbuf_size;
            const bytes_read = posix.read(self.fd, &self.rbuf[self.rbuf_size], cap) catch |err| {
                switch (err) {
                    .WouldBlock => return,
                    else => {
                        self.state = .state_end;
                        return;
                    },
                }
            };

            if (bytes_read == 0) {
                if (self.rbuf_size > 0) {
                    std.log.err("unexpected EOF");
                } else {
                    std.log.info("EOF");
                }
                self.state = .state_end;
                return;
            }

            self.rbuf_size += bytes_read;
        }
    }
};

pub fn start(settings: config.Settings, gpa: std.mem.Allocator) !void {
    // Create a non blocking TCP socket
    const fd = posix.socket(posix.AF.INET, posix.SOCK.STREAM | posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK, 0) catch {
        return std.log.err("error creating socket", .{});
    };

    const address = try net.Address.resolveIp(settings.bind, settings.port);
    var rv = posix.connect(fd, address.any, address.getOsSockLen());
    if (rv > 0) {
        std.log.warn("rv > 0, is this ok?");
    }

    const connections = std.ArrayList(Connection).init(gpa);
    var poll_args = std.ArrayList(posix.pollfd).init(gpa);
    while (true) {
        poll_args.clearAndFree();
        try poll_args.append(.{
            .fd = fd,
            .events = posix.POLL.IN,
            .revents = 0,
        });

        for (connections.items) |conn| {
            if (conn == undefined) {
                continue;
            }
            poll_args.append(.{
                .fd = conn.fd,
                .events = if (conn.state == .state_req) posix.POLL.IN | posix.POLL.ERR else posix.POLL.IN | posix.POLL.ERR,
                .revents = 0,
            });
        }

        rv = posix.poll(poll_args.items.ptr, poll_args.capacity, 1000);
        if (rv < 0) {
            std.log.warn("rv < 0 in event loop, is this ok?");
        }

        for (poll_args.items[1..]) |arg| {
            if (arg.revents > 0) {
                _ = connections.items[arg.fd];
            }
        }
    }

    var listener = try address.listen(.{
        .reuse_address = true,
        .force_nonblocking = true,
    });

    defer listener.deinit();
    std.log.info("starting server on port: {}", .{settings.port});

    var memory = mem.Memory.init(gpa);
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
            .config_get => |_| {
                try writer.writeAll("-TODO\r\n");
            },
        }
    }
}
