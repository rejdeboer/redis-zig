const std = @import("std");

pub const Command = union(enum) {
    ping: ?[]const u8,
    echo: []const u8,
    set: struct {
        key: []const u8,
        value: []const u8,
    },
    get: []const u8,
    err: ParsingError,
};

pub const ParsingError = error{Unexpected};

pub fn parse(message: []const u8) Command {
    var tokens = std.mem.tokenizeSequence(u8, message, "\r\n");
    const command_length = try parse_list_length(tokens.next().?);

    try expect_char(tokens.next(), '$');
    const command = tokens.next();

    if (std.ascii.eqlIgnoreCase("PING", command)) {
        if (command_length > 1) {
            try expect_char(tokens.next(), '$');
            return Command{ .ping = tokens.next() };
        }
        return Command{ .ping = null };
    } else if (std.ascii.eqlIgnoreCase("ECHO", command)) {
        try expect_char(tokens.next(), '$');
        return Command{ .echo = tokens.next() };
    }
    return ParsingError.Unexpected;
}

fn parse_list_length(line: []const u8) !u32 {
    try expect_char(line, '*');
    return std.fmt.parseInt(u32, line[1..], 10) orelse ParsingError.Unexpected;
}

fn expect_char(line: []const u8, char: u8) !void {
    if (char != line[0]) {
        std.log.info("parsing error: expected {}, received {}", .{ char, line[0] });
        return ParsingError.Unexpected;
    }
}
