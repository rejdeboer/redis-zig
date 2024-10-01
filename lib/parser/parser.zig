const std = @import("std");
const net = std.net;

pub const Command = union(enum) {
    ping: ?[]const u8,
    echo: []const u8,
    set: struct {
        key: []const u8,
        value: []const u8,
    },
    get: []const u8,
};

pub const ParsingError = error{Unexpected};

pub const Parser = struct {
    reader: *const net.Stream.Reader,
    buf: [1024]u8,

    const Self = @This();

    pub fn init(reader: *const net.Stream.Reader) Self {
        return Parser{ .reader = reader, .buf = undefined };
    }

    pub fn parse(self: *Self, comptime T: type) ParsingError!T {
        return switch (@typeInfo(T)) {
            .Pointer => {
                const line = try self.read_line();
                return switch (line[0]) {
                    '$' => try self.read_line(),
                    '+' => line[1..],
                    else => ParsingError.Unexpected,
                };
            },
            else => |err_type| {
                std.log.err("unexpected type: {}", .{err_type});
                return ParsingError.Unexpected;
            },
        };
    }

    fn read_line(self: *Self) ParsingError![]const u8 {
        const line = self.reader.*.readUntilDelimiterOrEof(&self.buf, '\r') catch {
            return ParsingError.Unexpected;
        };
        self.reader.*.skipBytes(1, .{}) catch {
            return ParsingError.Unexpected;
        };
        if (line == null or line.?.len == 0) {
            std.log.err("reached early EOF", .{});
            return ParsingError.Unexpected;
        }
        return line.?;
    }
};

pub fn parse_command(message: []const u8) ParsingError!Command {
    var tokens = std.mem.tokenizeSequence(u8, message, "\r\n");
    const command_length = try parse_list_length(tokens.next().?);

    try expect_char(tokens.next().?, '$');
    const command = tokens.next().?;

    if (std.ascii.eqlIgnoreCase("PING", command)) {
        if (command_length > 1) {
            try expect_char(tokens.next().?, '$');
            return Command{ .ping = tokens.next().? };
        }
        return Command{ .ping = null };
    } else if (std.ascii.eqlIgnoreCase("ECHO", command)) {
        try expect_char(tokens.next().?, '$');
        return Command{ .echo = tokens.next().? };
    } else if (std.ascii.eqlIgnoreCase("GET", command)) {
        try expect_char(tokens.next().?, '$');
        return Command{ .get = tokens.next().? };
    } else if (std.ascii.eqlIgnoreCase("SET", command)) {
        try expect_char(tokens.next().?, '$');
        const key = tokens.next().?;
        try expect_char(tokens.next().?, '$');
        return Command{ .set = .{ .key = key, .value = tokens.next().? } };
    }

    return ParsingError.Unexpected;
}

fn parse_list_length(line: []const u8) !u32 {
    try expect_char(line, '*');
    return std.fmt.parseInt(u32, line[1..], 10) catch {
        return ParsingError.Unexpected;
    };
}

fn expect_char(line: []const u8, char: u8) !void {
    if (char != line[0]) {
        std.log.err("parsing error: expected {}, received {}", .{ char, line[0] });
        return ParsingError.Unexpected;
    }
}
