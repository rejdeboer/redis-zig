const std = @import("std");
const RedisEntry = @import("parser.zig").RedisEntry;

/// Magic string that is at the top of every RDB file and the RDB version number
const REDIS_HEADER: []const u8 = "REDIS0011";
const REDIS_VERSION: []const u8 = "redis-ver6.0.16";

const METADATA_START: u8 = 0xFA;
const DATABASE_START: u8 = 0xFE;
const EOF_FLAG: u8 = 0xFF;

pub fn store_snapshot(allocator: std.mem.Allocator, path: []const u8, file_name: []const u8, storage: std.StringHashMap(RedisEntry)) !void {
    const file_path = try std.mem.concat(allocator, u8, .{ path, file_name });
    defer allocator.free(file_path);

    var file: std.fs.File = undefined;
    defer file.close();
    if (std.fs.path.isAbsolute(path)) {
        file = try std.fs.createFileAbsolute(file_path, .{ .read = true });
    } else {
        file = try std.fs.cwd().createFile(file_path, .{ .read = true });
    }

    // _ = file.write
}
