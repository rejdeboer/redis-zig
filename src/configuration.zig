const std = @import("std");
const clap = @import("clap");

pub const ConfigError = error{
    HelpRequested,
};

pub const Settings = struct {
    arena: ?std.heap.ArenaAllocator = null,
    port: u16 = 6379,
    bind: []const u8 = "127.0.0.1",
    maxclients: u16 = 10000,
    dir: ?[]const u8 = null,
    dbfilename: ?[]const u8 = null,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator) !Self {
        const params = comptime clap.parseParamsComptime(
            \\-h, --help             Display this help and exit. For a complete overview go to https://raw.githubusercontent.com/redis/redis/7.4/redis.conf.
            \\-p, --port <u16>       The listening port.
            \\-b, --bind <str>       The host to bind to.
            \\--maxclients <u16>     The maximum amount of clients that can connect simultaneously.
            \\--dir <str>            The directory where the RDB file will be stored.
            \\--dbfilename <str>     The name of the RDB file.
            \\<str>                  An optional Redis config file
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

        var arena = std.heap.ArenaAllocator.init(gpa);
        var self = Self{
            .arena = arena,
        };

        if (res.positionals.len > 0) {
            try merge_flags_and_config_file(&res.args, res.positionals[0], res.arena.allocator());
        }

        const allocator = arena.allocator();

        if (res.args.maxclients) |maxclients| {
            self.maxclients = maxclients;
        }
        if (res.args.port) |port| {
            self.port = port;
        }
        if (res.args.bind) |bind| {
            self.bind = try allocator.dupe(u8, bind);
        }
        if (res.args.dir) |dir| {
            self.dir = try allocator.dupe(u8, dir);
        }
        if (res.args.dbfilename) |dbfilename| {
            self.dbfilename = try allocator.dupe(u8, dbfilename);
        }

        return self;
    }

    pub fn deinit(self: *Settings) void {
        if (self.arena) |arena| {
            arena.deinit();
        }
    }
};

// NOTE: Command line flags have precedence over config file options
fn merge_flags_and_config_file(flags: anytype, config_file_path: []const u8, allocator: std.mem.Allocator) !void {
    std.log.info("reading config file with path: {s}", .{config_file_path});
    var file = try std.fs.cwd().openFile(config_file_path, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var option_split = std.mem.split(u8, line, " ");
        if (option_split.next()) |option| {
            merge_option(flags, option, option_split.rest(), allocator) catch |err| {
                std.log.err("error parsing configuration option: {s}", .{option});
                return err;
            };
        }
    }
}

fn merge_option(flags: anytype, option: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
    if (value.len == 0) {
        return;
    }

    inline for (std.meta.fields(@TypeOf(flags.*))) |f| {
        if (std.mem.eql(u8, option, f.name)) {
            switch (@typeInfo(f.type)) {
                // NOTE: We assume that every flag is optional
                .Optional => |opt| {
                    if (@field(flags.*, f.name) != null) {
                        return;
                    }
                    switch (@typeInfo(opt.child)) {
                        .Int => @field(flags.*, f.name) = try std.fmt.parseInt(opt.child, value, 10),
                        .Pointer => @field(flags.*, f.name) = try allocator.dupe(u8, value),
                        else => std.log.warn("unexpected optional type {any} for option {s}", .{ opt.child, option }),
                    }
                },
                else => std.log.warn("unexpected argument type {any} for option {s}", .{ f.type, option }),
            }
            return;
        }
    }
}
