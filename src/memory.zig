const std = @import("std");
const parser = @import("parser.zig");

pub const Memory = struct {
    gpa: std.mem.Allocator,
    storage: std.StringHashMap(parser.RedisEntry),

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator) Self {
        return Self{ .gpa = gpa, .storage = std.StringHashMap(parser.RedisEntry).init(gpa) };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.storage.iterator();
        while (iterator.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.value.string);
        }
        self.storage.deinit();
    }

    pub fn get(self: *Self, key: []const u8) ?parser.RedisEntry {
        if (self.storage.get(key)) |entry| {
            if (entry.expiry_ms != null and entry.expiry_ms.? <= std.time.milliTimestamp()) {
                self.gpa.free(entry.value.string);
                self.gpa.free(self.storage.getKey(key).?);
                _ = self.storage.remove(key);
                return null;
            }
            return entry;
        } else {
            return null;
        }
    }

    pub fn put(self: *Self, key: []const u8, value: parser.RedisEntry) !void {
        try self.storage.put(key, value);
    }
};
