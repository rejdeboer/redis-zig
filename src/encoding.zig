const std = @import("std");

pub const ListEncoder = struct {
    buf: []u8,
    // NOTE: We start with index 4 to reserve a spot for the list size
    n_bytes: usize = 4,
    size: usize = 0,

    const Self = @This();

    pub fn init(buf: []u8) Self {
        return Self{
            .buf = buf,
        };
    }

    pub fn add(self: *Self, comptime T: type, value: T) std.fmt.BufPrintError!void {
        self.n_bytes += try encode(self.buf[self.n_bytes..], T, value);
        self.size += 1;
    }

    pub fn write_length(self: *Self) std.fmt.BufPrintError!void {
        var digits: usize = 0;
        var size = self.size;
        while (size > 0) {
            digits += 1;
            size /= 10;
        }
        if (digits > 1) {
            // Shift the buffer to make space for the extra digits
            const extra_digits = digits - 1;
            var i = self.n_bytes;
            while (i > 4) {
                i -= 1;
                self.buf[i + extra_digits] = self.buf[i];
            }
            self.n_bytes += extra_digits;
        }
        _ = try std.fmt.bufPrint(self.buf, "*{d}\r\n", .{self.size});
    }
};

pub fn encode(buf: []u8, comptime T: type, value: T) std.fmt.BufPrintError!usize {
    return switch (@typeInfo(T)) {
        .Int => try encode_int(buf, value),
        .Bool => try encode_bool(buf, value),
        .Float => try encode_float(buf, value),
        .Pointer => try encode_bulk_string(buf, value),
        else => {
            std.log.err("unexpected encoding type {any}", .{T});
            return 0;
        },
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
    try std.testing.expect(encoder.n_bytes == 14);
    try encoder.write_length();
    try std.testing.expect(std.mem.eql(u8, "*1\r\n$4\r\nTEST\r\n", &buf));
}

test "list multiple" {
    var buf: [22]u8 = undefined;
    var encoder = ListEncoder.init(&buf);
    try encoder.add([]const u8, "FOO");
    try encoder.add([]const u8, "BAR");
    try std.testing.expect(encoder.size == 2);
    try std.testing.expect(encoder.n_bytes == 22);
    try encoder.write_length();
    try std.testing.expect(std.mem.eql(u8, "*2\r\n$3\r\nFOO\r\n$3\r\nBAR\r\n", &buf));
}
