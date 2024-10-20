const std = @import("std");

/// Note: This is just for convenience, the actual implementation has a limit of 512Mb
pub const MAX_MESSAGE_SIZE: usize = 4096;

pub const Settings = struct {
    port: u16 = 6379,
    bind: []const u8 = "127.0.0.1",
    maxclients: u16 = 10000,
    dir: ?[]const u8 = null,
    dbfilename: ?[]const u8 = null,

    const Self = @This();

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        if (self.dir != null) {
            gpa.free(self.dir.?);
        }
        if (self.dbfilename != null) {
            gpa.free(self.dbfilename.?);
        }
    }

    pub fn read_config_file(self: *Self, gpa: std.mem.Allocator) !void {
        var args = std.process.args();
        _ = args.skip();

        const path = args.next();
        if (path == null) {
            return;
        }

        std.log.info("reading config file with path: {s}", .{path.?});
        var file = try std.fs.cwd().openFile(path.?, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var reader = buf_reader.reader();

        var buf: [1024]u8 = undefined;
        while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            var option_split = std.mem.split(u8, line, " ");
            if (option_split.next()) |option| {
                self.set_option(option, option_split.rest(), gpa) catch |err| {
                    std.log.err("error parsing configuration option: {s}", .{option});
                    return err;
                };
            }
        }
    }

    fn set_option(self: *Self, option: []const u8, value: []const u8, gpa: std.mem.Allocator) !void {
        if (value.len == 0) {
            return;
        }

        if (std.mem.eql(u8, option, "port")) {
            self.port = try std.fmt.parseInt(u16, value, 10);
        } else if (std.mem.eql(u8, option, "bind")) {
            self.bind = try std.mem.Allocator.dupe(gpa, u8, value);
        } else if (std.mem.eql(u8, option, "maxclients")) {
            self.maxclients = try std.fmt.parseInt(u16, value, 10);
        } else if (std.mem.eql(u8, option, "dir")) {
            self.dir = try std.mem.Allocator.dupe(gpa, u8, value);
        } else if (std.mem.eql(u8, option, "dbfilename")) {
            self.dbfilename = try std.mem.Allocator.dupe(gpa, u8, value);
        } else {
            std.log.warn("unknown configuration option: {s}", .{option});
        }
    }
};
