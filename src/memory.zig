const std = @import("std");
const parser = @import("parser");

pub const Memory = struct {
    storage: std.StringHashMap(parser.RedisEntry),

    const Self = @This();

    pub fn init(gpa: *const std.mem.Allocator) Self {
        return Self{ .storage = std.StringHashMap(parser.RedisEntry).init(gpa.*) };
    }

    pub fn deinit(self: *Self) void {
        self.storage.deinit();
    }

    pub fn get(self: *Self, key: []const u8) ?parser.RedisEntry {
        if (self.storage.get(key)) |entry| {
            if (entry.expiry_ms != null and entry.expiry_ms.? <= std.time.milliTimestamp()) {
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
