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
    _ = try parse_list_length(tokens.next());
}

fn parse_list_length(line: []const u8) !u32 {
    if (!std.mem.eql(u8, '*', line[0])) {
        return ParsingError.Unexpected;
    }
    return std.fmt.formatInt(u32, line[1..], 10) orelse ParsingError.Unexpected;
}
