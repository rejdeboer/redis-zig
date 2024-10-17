const std = @import("std");

pub const Settings = struct {
    port: u16 = 6379,
    bind: []const u8 = "127.0.0.1",
    maxclients: u16 = 10000,
    dir: ?[]const u8 = null,
    dbfilename: ?[]const u8 = null,
};

pub fn get_configuration(gpa: *const std.mem.Allocator) !Settings {
    var settings: Settings = undefined;

    var args = std.process.args();
    _ = args.skip();
    if (args.next()) |config_file_path| {
        try read_config_file(&settings, config_file_path, gpa);
    }

    return settings;
}

fn read_config_file(settings: *Settings, path: []const u8, gpa: *const std.mem.Allocator) !void {
    std.log.info("reading config file with path: {s}", .{path});
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var option_split = std.mem.split(u8, line, " ");
        if (option_split.next()) |option| {
            set_option(settings, option, option_split.rest(), gpa) catch |err| {
                std.log.err("error parsing configuration option: {s}", .{option});
                return err;
            };
        }
    }
}

fn set_option(settings: *Settings, option: []const u8, value: []const u8, gpa: *const std.mem.Allocator) !void {
    if (value.len == 0) {
        return;
    }

    if (std.mem.eql(u8, option, "port")) {
        settings.port = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, option, "bind")) {
        settings.bind = try std.mem.Allocator.dupe(gpa.*, u8, value);
    } else if (std.mem.eql(u8, option, "maxclients")) {
        settings.maxclients = try std.fmt.parseInt(u16, value, 10);
    } else if (std.mem.eql(u8, option, "dir")) {
        settings.dir = try std.mem.Allocator.dupe(gpa.*, u8, value);
    } else if (std.mem.eql(u8, option, "dbfilename")) {
        settings.dbfilename = try std.mem.Allocator.dupe(gpa.*, u8, value);
    } else {
        std.log.warn("unknown configuration option: {s}", .{option});
    }
}
