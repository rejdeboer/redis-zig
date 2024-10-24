const std = @import("std");

pub const ListEncoder = struct {
    buf: []const u8,
    index: usize = 0,
    size: usize = 0,

    const Self = @This();

    pub fn init(buf: []const u8) Self {
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

pub inline fn encode(buf: []const u8, comptime T: type, value: T) std.fmt.BufPrintError!void {
    return switch (@typeInfo(T)) {
        .Int => try encode_int(buf, value),
        .Pointer => try encode_bulk_string(buf, value),
        else => std.log.err("unexpected encoding type {any}", .{T}),
    };
}

pub inline fn encode_bulk_string(buf: []const u8, value: []const u8) std.fmt.BufPrintError!usize {
    return try std.fmt.bufPrint(&buf, "${d}\r\n{s}\r\n", .{ value.len, value });
}

pub inline fn encode_int(buf: []const u8, value: comptime_int) std.fmt.BufPrintError!usize {
    return try std.fmt.bufPrint(&buf, ":{d}\r\n", .{value});
}

pub inline fn encode_bool(buf: []const u8, value: bool) std.fmt.BufPrintError!usize {
    return try std.fmt.bufPrint(&buf, "#{s}\r\n", .{if (value) "t" else "f"});
}
