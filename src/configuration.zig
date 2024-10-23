const std = @import("std");
const clap = @import("clap");

pub const ConfigError = error{
    HelpRequested,
};

pub const Settings = struct {
    port: u16 = 6379,
    bind: []const u8 = "127.0.0.1",
    maxclients: u16 = 10000,
    dir: ?[]const u8 = null,
    dbfilename: ?[]const u8 = null,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator) !Self {
        var self = Self{};

        const params = comptime clap.parseParamsComptime(
            \\-h, --help             Display this help and exit.
            \\-p, --port <u16>       The listening port.
            \\-b, --bind <str>...    The host to bind to.
            \\--maxclients <u16>     The maximum amount of clients that can connect simultaneously.
            \\--dir <str>...         The directory where the RDB file will be stored.
            \\--dbfilename <str>...  The name of the RDB file.
            \\<str>...               An optional Redis config file
        );

        var diag = clap.Diagnostic{};
        var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
            .diagnostic = &diag,
            .allocator = gpa,
        }) catch |err| {
            // Report useful error and exit
            diag.report(std.io.getStdErr().writer(), err) catch {};
            return err;
        };
        defer res.deinit();

        if (res.args.help != 0) {
            try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
            return ConfigError.HelpRequested;
        }

        if (res.positionals.len > 0) {
            try self.read_config_file(res.positionals[0], gpa);
        }

        return self;
    }

    pub fn deinit(self: *Settings, gpa: std.mem.Allocator) void {
        if (self.dir != null) {
            gpa.free(self.dir.?);
        }
        if (self.dbfilename != null) {
            gpa.free(self.dbfilename.?);
        }
    }

    pub fn read_config_file(self: *Self, path: []const u8, gpa: std.mem.Allocator) !void {
        std.log.info("reading config file with path: {s}", .{path});
        var file = try std.fs.cwd().openFile(path, .{});
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
