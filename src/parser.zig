const std = @import("std");

pub const Command = union(enum) {
    ping: ?[]const u8,
    echo: []const u8,
    set: SetCommand,
    get: []const u8,
    config_get: []const u8,
    command_docs: void,
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

pub const ParsingError = error{ Unexpected, EOF };

pub const Parser = struct {
    buf: []const u8,
    index: usize,
    gpa: ?std.mem.Allocator,

    const Self = @This();

    /// Note: If you intend to parse commands, you should pass an allocator
    pub fn init(buf: []const u8, gpa: ?std.mem.Allocator) Self {
        return Self{ .buf = buf, .index = 0, .gpa = gpa };
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
                    '*', ':' => std.fmt.parseInt(T, line[1..], 10) catch ParsingError.Unexpected,
                    else => ParsingError.Unexpected,
                };
            },
            .Bool => {
                const line = try self.read_line(false);
                if ('#' != line[0]) {
                    return ParsingError.Unexpected;
                }
                return line[1] == 't';
            },
            .Float => {
                const line = try self.read_line(false);
                if (',' != line[0]) {
                    return ParsingError.Unexpected;
                }
                return std.fmt.parseFloat(T, line[1..]) catch ParsingError.Unexpected;
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
        } else if (std.ascii.eqlIgnoreCase("CONFIG", command)) {
            const command_type = try self.parse([]const u8, false);
            if (std.ascii.eqlIgnoreCase("GET", command_type)) {
                return Command{ .config_get = try self.parse([]const u8, false) };
            }
        } else if (std.ascii.eqlIgnoreCase("COMMAND", command)) {
            const command_type = try self.parse([]const u8, false);
            if (std.ascii.eqlIgnoreCase("DOCS", command_type)) {
                return Command{ .command_docs = {} };
            }
        }

        return ParsingError.Unexpected;
    }

    fn parse_set_command(self: *Self, command_length: u32) ParsingError!SetCommand {
        const key = try self.parse([]const u8, true);

        const line = try self.read_line(false);
        const value = switch (line[0]) {
            '*', ':' => RedisValue{ .int = std.fmt.parseInt(i32, line[1..], 10) catch return ParsingError.Unexpected },
            '$' => RedisValue{ .string = try self.read_line(true) },
            '+' => RedisValue{ .string = std.mem.Allocator.dupe(self.gpa.?, u8, line[1..]) catch return ParsingError.Unexpected },
            '#' => RedisValue{ .boolean = line[1] == 't' },
            ',' => RedisValue{ .float = std.fmt.parseFloat(f32, line[1..]) catch return ParsingError.Unexpected },
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
        const start = self.index;
        while (self.index < self.buf.len and self.buf[self.index] != '\r') {
            self.index += 1;
        }
        if (self.index >= self.buf.len) {
            return ParsingError.EOF;
        }

        const line = self.buf[start..self.index];

        // Skip the \r\n
        self.index += 2;

        if (should_allocate) {
            return self.gpa.?.dupe(u8, line) catch return ParsingError.Unexpected;
        }
        return line;
    }
};

test "integer" {
    var parser = Parser.init(":42\r\n", std.testing.allocator);
    try std.testing.expect(42 == try parser.parse(u32, false));
}

test "bool" {
    var parser = Parser.init("#t\r\n", std.testing.allocator);
    try std.testing.expect(try parser.parse(bool, false));
}

test "float" {
    var parser = Parser.init(",1.23\r\n", std.testing.allocator);
    try std.testing.expect(1.23 == try parser.parse(f32, false));
}

test "bulk string" {
    var parser = Parser.init("$4\r\ntest\r\n", std.testing.allocator);
    try std.testing.expect(std.mem.eql(u8, "test", try parser.parse([]const u8, false)));
}

test "simple string" {
    var parser = Parser.init("+test\r\n", std.testing.allocator);
    try std.testing.expect(std.mem.eql(u8, "test", try parser.parse([]const u8, false)));
}

test "error" {
    var parser = Parser.init("-test\r\n", std.testing.allocator);
    try std.testing.expect(std.mem.eql(u8, "test", try parser.parse([]const u8, false)));
}
