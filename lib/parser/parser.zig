const std = @import("std");
const net = std.net;

pub const Command = union(enum) {
    ping: ?[]const u8,
    echo: []const u8,
    set: SetCommand,
    get: []const u8,
};

pub const RedisValue = union(enum) {
    string: []const u8,
    int: i32,
    float: f32,
    boolean: bool,
};

pub const RedisEntry = struct {
    value: RedisValue,
    expiry_ms: ?i64,
};

const SetCommand = struct {
    key: []const u8,
    entry: RedisEntry,
};

pub const ParsingError = error{Unexpected};

pub const Parser = struct {
    reader: *const net.Stream.Reader,
    buf: [1024]u8,
    gpa: ?*const std.mem.Allocator,

    const Self = @This();

    /// Note: If you intend to parse commands, you should pass an allocator
    pub fn init(reader: *const net.Stream.Reader, gpa: ?*const std.mem.Allocator) Self {
        return Parser{ .reader = reader, .buf = undefined, .gpa = gpa };
    }

    pub fn parse(self: *Self, comptime T: type, should_allocate: bool) ParsingError!T {
        return switch (@typeInfo(T)) {
            .Pointer => {
                const line = try self.read_line(false);
                return switch (line[0]) {
                    '$' => try self.read_line(should_allocate),
                    '+', '-' => line[1..],
                    else => ParsingError.Unexpected,
                };
            },
            .Int => {
                const line = try self.read_line(false);
                return switch (line[0]) {
                    '*', ':' => std.fmt.parseInt(T, line[1..], 10) catch {
                        return ParsingError.Unexpected;
                    },
                    else => ParsingError.Unexpected,
                };
            },
            else => |err_type| {
                std.log.err("unexpected type: {}", .{err_type});
                return ParsingError.Unexpected;
            },
        };
    }

    pub fn parse_command(self: *Self) ParsingError!Command {
        const command_length = try self.parse(u32, false);
        const command = try self.parse([]const u8, false);

        if (std.ascii.eqlIgnoreCase("PING", command)) {
            if (command_length > 1) {
                return Command{ .ping = try self.parse([]const u8, false) };
            }
            return Command{ .ping = null };
        } else if (std.ascii.eqlIgnoreCase("ECHO", command)) {
            return Command{ .echo = try self.parse([]const u8, false) };
        } else if (std.ascii.eqlIgnoreCase("GET", command)) {
            return Command{ .get = try self.parse([]const u8, false) };
        } else if (std.ascii.eqlIgnoreCase("SET", command)) {
            return Command{ .set = try self.parse_set_command(command_length) };
        }

        return ParsingError.Unexpected;
    }

    fn parse_set_command(self: *Self, command_length: u32) ParsingError!SetCommand {
        const key = try self.parse([]const u8, true);

        const line = try self.read_line(false);
        const value = switch (line[0]) {
            '*', ':' => RedisValue{ .int = std.fmt.parseInt(i32, line[1..], 10) catch return ParsingError.Unexpected },
            '$' => RedisValue{ .string = try self.read_line(true) },
            // TODO: Allocate the simple string
            '+' => RedisValue{ .string = line[1..] },
            else => |c| {
                std.log.err("unexpected SET value type: {}", .{c});
                return ParsingError.Unexpected;
            },
        };

        // NOTE: Parse SET options
        var expiry_ms: ?i64 = null;
        var options_count = command_length - 3;
        while (options_count > 0) {
            const option = try self.parse([]const u8, false);
            options_count -= 1;

            // TODO: Implement GET, NX and XX here
            if (std.ascii.eqlIgnoreCase("GET", option)) {
                continue;
            } else if (std.ascii.eqlIgnoreCase("XX", option)) {
                continue;
            } else if (std.ascii.eqlIgnoreCase("NX", option)) {
                continue;
            }

            options_count -= 1;
            if (std.ascii.eqlIgnoreCase("EX", option)) {
                const expiry = std.fmt.parseInt(i64, try self.parse([]const u8, false), 10) catch return ParsingError.Unexpected;
                expiry_ms = std.time.milliTimestamp() + (expiry * 1000);
            } else if (std.ascii.eqlIgnoreCase("PX", option)) {
                const expiry = std.fmt.parseInt(i64, try self.parse([]const u8, false), 10) catch return ParsingError.Unexpected;
                expiry_ms = std.time.milliTimestamp() + expiry;
            } else if (std.ascii.eqlIgnoreCase("EXAT", option)) {
                const expiry = std.fmt.parseInt(i64, try self.parse([]const u8, false), 10) catch return ParsingError.Unexpected;
                expiry_ms = expiry * 1000;
            } else if (std.ascii.eqlIgnoreCase("PXAT", option)) {
                const expiry = std.fmt.parseInt(i64, try self.parse([]const u8, false), 10) catch return ParsingError.Unexpected;
                expiry_ms = expiry;
            }
        }

        return SetCommand{ .key = key, .entry = RedisEntry{ .expiry_ms = expiry_ms, .value = value } };
    }

    fn read_line(self: *Self, should_allocate: bool) ParsingError![]const u8 {
        if (if (should_allocate) self.reader.*.readUntilDelimiterOrEofAlloc(self.gpa.?.*, '\r', 4096) else self.reader.*.readUntilDelimiterOrEof(&self.buf, '\r')) |line| {
            self.reader.*.skipBytes(1, .{}) catch {
                return ParsingError.Unexpected;
            };
            if (line == null or line.?.len == 0) {
                std.log.err("reached unexpected EOF", .{});
                return ParsingError.Unexpected;
            }
            return line.?;
        } else |_| {
            return ParsingError.Unexpected;
        }
    }
};
