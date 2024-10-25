const std = @import("std");

pub const ListEncoder = struct {
    buf: []u8,
    index: usize = 0,
    size: usize = 0,

    const Self = @This();

    pub fn init(buf: []u8) Self {
        return Self{
            .buf = buf,
        };
    }

    pub fn add(self: *Self, comptime T: type, value: T) std.fmt.BufPrintError!void {
        self.index += try encode(self.buf[self.index..], T, value);
        self.size += 1;
    }

    // TODO: This won't work
    pub fn write_size(self: *Self) std.fmt.BufPrintError!void {
        try std.fmt.bufPrint(&self.buf, "*{d}\r\n{s}", .{ self.size, self.buf });
    }
};

pub fn encode(buf: []u8, comptime T: type, value: T) std.fmt.BufPrintError!void {
    return switch (@typeInfo(T)) {
        .Int => try encode_int(buf, value),
        .Bool => try encode_bool(buf, value),
        .Float => try encode_float(buf, value),
        .Pointer => try encode_bulk_string(buf, value),
        else => std.log.err("unexpected encoding type {any}", .{T}),
    };
}

pub fn encode_bulk_string(buf: []u8, value: []const u8) std.fmt.BufPrintError!usize {
    const res = try std.fmt.bufPrint(buf, "${d}\r\n{s}\r\n", .{ value.len, value });
    return res.len;
}

pub fn encode_simple_string(buf: []u8, value: []const u8) std.fmt.BufPrintError!usize {
    const res = try std.fmt.bufPrint(buf, "+{s}\r\n", .{value});
    return res.len;
}

pub fn encode_err(buf: []u8, value: []const u8) std.fmt.BufPrintError!usize {
    const res = try std.fmt.bufPrint(buf, "-{s}\r\n", .{value});
    return res.len;
}

pub fn encode_int(buf: []u8, value: i32) std.fmt.BufPrintError!usize {
    const res = try std.fmt.bufPrint(buf, ":{d}\r\n", .{value});
    return res.len;
}

pub fn encode_float(buf: []u8, value: f32) std.fmt.BufPrintError!usize {
    const res = try std.fmt.bufPrint(buf, ",{d}\r\n", .{value});
    return res.len;
}

pub fn encode_bool(buf: []u8, value: bool) std.fmt.BufPrintError!usize {
    const res = try std.fmt.bufPrint(buf, "#{s}\r\n", .{if (value) "t" else "f"});
    return res.len;
}

test "bool true" {
    var buf: [4]u8 = undefined;
    const len = try encode_bool(&buf, true);
    try std.testing.expect(len == 4);
    try std.testing.expect(std.mem.eql(u8, "#t\r\n", buf[0..len]));
}
