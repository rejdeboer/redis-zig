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

    pub fn write_length(self: *Self) std.fmt.BufPrintError!void {
        var digits: usize = 0;
        const size = self.size;
        while (self.size > 0) {
            digits += 1;
            self.size /= 10;
        }
        // * and \r\n
        const list_encoding_length = digits + 3;
        while (self.index > 0) {
            self.index -= 1;
            self.buf[self.index + list_encoding_length] = self.buf[self.index];
        }
        _ = try std.fmt.bufPrint(self.buf, "*{d}\r\n", .{size});
    }
};

pub fn encode(buf: []u8, comptime T: type, value: T) std.fmt.BufPrintError!usize {
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
    try std.testing.expect(std.mem.eql(u8, "#t\r\n", &buf));
}

test "bool false" {
    var buf: [4]u8 = undefined;
    const len = try encode_bool(&buf, false);
    try std.testing.expect(len == 4);
    try std.testing.expect(std.mem.eql(u8, "#f\r\n", &buf));
}

test "int" {
    var buf: [4]u8 = undefined;
    const len = try encode_int(&buf, 1);
    try std.testing.expect(len == 4);
    try std.testing.expect(std.mem.eql(u8, ":1\r\n", &buf));
}

test "float" {
    var buf: [7]u8 = undefined;
    const len = try encode_float(&buf, 1.23);
    try std.testing.expect(len == 7);
    try std.testing.expect(std.mem.eql(u8, ",1.23\r\n", &buf));
}

test "list single" {
    var buf: [14]u8 = undefined;
    var encoder = ListEncoder.init(&buf);
    try encoder.add([]const u8, "TEST");
    try std.testing.expect(encoder.size == 1);
    try std.testing.expect(encoder.index == 10);
    try encoder.write_length();
    try std.testing.expect(std.mem.eql(u8, "*1\r\n$4\r\nTEST\r\n", &buf));
}
