const std = @import("std");
const net = std.net;
const posix = std.posix;
const mem = @import("memory.zig");
const config = @import("configuration.zig");
const Connection = @import("connection.zig").Connection;
const DList = @import("dlist.zig").DList;

const DEFAULT_POLL_TIMEOUT_MS: i64 = 10000;
const IDLE_TIMEOUT_MS: i64 = 5000;
const READ_TIMEOUT_MS: i64 = 500;

pub const Server = struct {
    gpa: std.mem.Allocator,
    settings: config.Settings,
    memory: mem.Memory,
    connections: std.AutoHashMap(c_int, *Connection),
    idle_list: DList = undefined,

    const Self = @This();

    pub fn init(settings: config.Settings, gpa: std.mem.Allocator) !Self {
        const memory = mem.Memory.init(gpa);
        const connections = std.AutoHashMap(c_int, *Connection).init(gpa);
        return Self{ .gpa = gpa, .settings = settings, .memory = memory, .connections = connections };
    }

    pub fn deinit(self: *Self) void {
        self.memory.deinit();
        var iterator = self.connections.valueIterator();
        while (iterator.next()) |conn| {
            conn.deinit();
        }
        self.connections.deinit();
    }

    pub fn run(self: *Self) !void {
        const address = try net.Address.resolveIp(self.settings.bind, self.settings.port);

        // Create a TCP socket
        const fd = posix.socket(address.any.family, posix.SOCK.STREAM, 0) catch {
            return std.log.err("error creating socket", .{});
        };

        // Enable REUSE_ADDR
        try posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        try posix.bind(fd, &address.any, address.getOsSockLen());
        try posix.listen(fd, 128);

        // Set file descriptor to non-blocking
        _ = try posix.fcntl(fd, posix.F.SETFL, try posix.fcntl(fd, posix.F.GETFL, 0) | posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);

        var listen_addr: net.Address = undefined;
        var addr_len: posix.socklen_t = @sizeOf(net.Address);
        try posix.getsockname(fd, &listen_addr.any, &addr_len);
        std.log.info("started server on port: {}", .{listen_addr.getPort()});

        // Initialize the timer list
        self.idle_list.init();

        var poll_args = std.ArrayList(posix.pollfd).init(self.gpa);
        defer {
            poll_args.clearAndFree();
            poll_args.deinit();
            posix.close(fd);
        }
        while (true) {
            poll_args.clearAndFree();
            try poll_args.append(posix.pollfd{ .fd = fd, .events = posix.POLL.IN, .revents = 0 });

            var iterator = self.connections.valueIterator();
            while (iterator.next()) |conn| {
                const p_byte: u8 = if (conn.*.state == .state_req) posix.POLL.IN else posix.POLL.OUT;
                try poll_args.append(posix.pollfd{ .fd = conn.*.fd, .events = p_byte | posix.POLL.ERR, .revents = 0 });
            }

            _ = try posix.poll(poll_args.items, self.get_next_timer());

            // Process active connections
            for (poll_args.items[1..]) |arg| {
                if (arg.revents > 0) {
                    var conn = self.connections.get(arg.fd).?;
                    conn.update(&self.idle_list) catch {
                        self.disconnect_client(conn);
                        continue;
                    };
                }
            }

            self.process_timers();

            // Check if listener is active and accept new connection
            if (poll_args.items[0].revents > 0) {
                const conn = try Connection.init(fd, &self.memory, &self.idle_list, self.gpa);
                try self.connections.put(conn.fd, conn);
                std.log.info("client connected: {}", .{conn.fd});
            }
        }
    }

    fn get_next_timer(self: *Self) i32 {
        if (self.idle_list.is_empty()) {
            return DEFAULT_POLL_TIMEOUT_MS;
        }

        const now = std.time.milliTimestamp();
        const conn: *Connection = @fieldParentPtr("idle_list", self.idle_list.next);
        const next = if (conn.rbuf_size > 0) conn.idle_start_ms + READ_TIMEOUT_MS else conn.idle_start_ms + IDLE_TIMEOUT_MS;

        if (next <= now) {
            return 0;
        }

        return @truncate(next - now);
    }

    fn process_timers(self: *Self) void {
        while (!self.idle_list.is_empty()) {
            const now = std.time.milliTimestamp();
            const conn: *Connection = @fieldParentPtr("idle_list", self.idle_list.next);

            // TODO: DLL is not reliable with both read and idle timeouts
            if (conn.rbuf_size > 0 and now + 1 >= conn.idle_start_ms + READ_TIMEOUT_MS) {
                return conn.timeout_read();
            } else if (now + 1 < conn.idle_start_ms + IDLE_TIMEOUT_MS) {
                return;
            }

            self.disconnect_client(conn);
        }
    }

    fn disconnect_client(self: *Self, conn: *Connection) void {
        _ = self.connections.remove(conn.fd);
        std.log.info("client disconnected: {}", .{conn.fd});
        conn.deinit();
    }
};
