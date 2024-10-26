const std = @import("std");
const parser = @import("parser.zig");
const Settings = @import("configuration.zig").Settings;
const encoding = @import("encoding.zig");
const snapshot = @import("snapshot.zig");

pub const Database = struct {
    gpa: std.mem.Allocator,
    settings: Settings,
    storage: std.StringHashMap(parser.RedisEntry),

    const Self = @This();

    pub fn init(settings: Settings, gpa: std.mem.Allocator) Self {
        return Self{ .gpa = gpa, .settings = settings, .storage = std.StringHashMap(parser.RedisEntry).init(gpa) };
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

    pub fn encode_config_key(self: *Self, buf: []u8, key: []const u8) std.fmt.BufPrintError!usize {
        var encoder = encoding.ListEncoder.init(buf);
        inline for (std.meta.fields(@TypeOf(self.settings))[1..]) |f| {
            if (std.mem.eql(u8, key, f.name)) {
                try encoder.add([]const u8, key);
                try encoder.add(f.type, @field(self.settings, f.name));
            }
        }
        try encoder.write_length();
        return encoder.n_bytes;
    }

    pub fn store_snapshot(self: *Self) void {
        snapshot.store_snapshot(self.gpa, self.settings.dir, self.settings.dbfilename, self.storage) catch |err| {
            std.log.err("error occored when storing snapshot: {any}", .{err});
        };
    }
};
