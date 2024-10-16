const std = @import("std");

pub const Settings = struct {
    port: u32 = 6379,
    bind: []const u8 = "127.0.0.1",
    dir: ?[]const u8,
    dbfilename: ?[]const u8,
};

pub fn get_configuration(gpa: *std.mem.Allocator) Settings {
    const settings = Settings{};

    var args = std.process.args();
    _ = args.skip();
    if (args.next()) |config_file_path| {
        try read_config_file(&settings, config_file_path, gpa);
    }

    return settings;
}

fn read_config_file(settings: *Settings, path: []const u8, gpa: *std.mem.Allocator) !void {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const reader = std.io.bufferedReader(file.reader()).reader();

    const buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const option_split = std.mem.split(u8, line, " ");
        if (option_split.next()) |option| {
            set_option(settings, option, option_split.rest(), gpa) catch {
                std.log.err("error parsing configuration option: {s}", .{option});
                return;
            };
        }
    }
}

fn set_option(settings: *Settings, option: []const u8, value: []const u8, gpa: *std.mem.Allocator) !void {
    if (std.mem.eql(u8, option, "port")) {
        settings.port = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, option, "bind")) {
        settings.bind = try std.mem.Allocator.dupe(gpa.*, u8, value);
    } else if (std.mem.eql(u8, option, "dir")) {
        settings.dir = try std.mem.Allocator.dupe(gpa.*, u8, value);
    } else if (std.mem.eql(u8, option, "dbfilename")) {
        settings.dbfilename = try std.mem.Allocator.dupe(gpa.*, u8, value);
    } else {
        std.log.warn("unknown configuration option: {s}", .{option});
    }
}
