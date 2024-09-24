/// TODO: This doesn't work yet, let's keep the client simple for now
const std = @import("std");

pub fn list() []const u8 {}

pub fn encode_integer(value: comptime_int) ![]const u8 {
    // An int can only be 10 chars long, the rest is for the command flag, sign and delimiter
    var buffer = [_]u8{undefined} ** 13;
    const res = try std.fmt.bufPrint(&buffer, ":{}\r\n", .{
        value,
    });
    return res;
}

pub fn encode(comptime T: type, value: T) ![]const u8 {
    return switch (T) {
        inline comptime_int => try encode_integer(T, value),
        else => @compileError("invalid type"),
    };
}

test "encode integer" {
    std.debug.print("{s} TEST", .{try encode_integer(-5)});
    try std.testing.expect(std.mem.eql(u8, ":-5\r\n", try encode_integer(-5)));
}
