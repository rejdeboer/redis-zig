const std = @import("std");
const net = std.net;
const posix = std.posix;
const mem = @import("memory.zig");
const config = @import("configuration.zig");
const connection = @import("connection.zig");

pub const Server = struct {
    gpa: std.mem.Allocator,
    settings: config.Settings,
    memory: mem.Memory,
    stop: bool = false,
    running: bool = false,

    const Self = @This();

    pub fn init(settings: config.Settings, gpa: std.mem.Allocator) Self {
        const memory = mem.Memory.init(gpa);
        return Self{ .gpa = gpa, .settings = settings, .memory = memory };
    }

    pub fn deinit(self: *Self) void {
        if (self.running) {
            self.stop_and_block();
        }
        self.memory.deinit();
    }

    pub fn start(self: *Self) !void {
        std.log.info("starting server on port: {}", .{self.settings.port});
        const address = try net.Address.resolveIp(self.settings.bind, self.settings.port);

        // Create a non blocking TCP socket
        const fd = posix.socket(address.any.family, posix.SOCK.STREAM, 0) catch {
            return std.log.err("error creating socket", .{});
        };

        // Enable REUSE_ADDR
        try posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        try posix.bind(fd, &address.any, address.getOsSockLen());
        try posix.listen(fd, 128);

        // Set file descriptor to non-blocking
        _ = try posix.fcntl(fd, posix.F.SETFL, try posix.fcntl(fd, posix.F.GETFL, 0) | posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);

        var connections = std.AutoHashMap(c_int, connection.Connection).init(self.gpa);
        var poll_args = std.ArrayList(posix.pollfd).init(self.gpa);
        self.running = true;
        defer {
            var iterator = connections.valueIterator();
            while (iterator.next()) |conn| {
                conn.deinit();
            }
            poll_args.clearAndFree();
            poll_args.deinit();
            connections.deinit();
            posix.close(fd);
            self.running = false;
        }
        while (!self.stop) {
            poll_args.clearAndFree();
            try poll_args.append(posix.pollfd{ .fd = fd, .events = posix.POLL.IN, .revents = 0 });

            var iterator = connections.valueIterator();
            while (iterator.next()) |conn| {
                const p_byte: u8 = if (conn.state == .state_req) posix.POLL.IN else posix.POLL.OUT;
                try poll_args.append(posix.pollfd{ .fd = conn.fd, .events = p_byte | posix.POLL.ERR, .revents = 0 });
            }

            _ = try posix.poll(poll_args.items, 1000);

            // Process active connections
            for (poll_args.items[1..]) |arg| {
                if (arg.revents > 0) {
                    var conn = connections.get(arg.fd).?;
                    conn.update() catch {
                        _ = connections.remove(arg.fd);
                        conn.deinit();
                    };
                }
            }

            // Check if listener is active and accept new connection
            if (poll_args.items[0].revents > 0) {
                const conn = try connection.Connection.init(fd, &self.memory, self.gpa);
                try connections.put(conn.fd, conn);
                std.log.info("new client connected", .{});
            }
        }
    }

    pub fn stop_and_block(self: *Self) void {
        self.stop = true;
        while (self.running) {
            std.time.sleep(1000);
        }
        std.log.info("server has been stopped", .{});
    }
};
