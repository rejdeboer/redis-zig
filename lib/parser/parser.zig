const std = @import("std");
const net = std.net;

pub const Command = union(enum) {
    ping: ?[]const u8,
    echo: []const u8,
    set: struct {
        key: []const u8,
        value: []const u8,
    },
    get: []const u8,
};

pub const ParsingError = error{Unexpected};

pub const Parser = struct {
    reader: *const net.Stream.Reader,
    buf: [1024]u8,
    gpa: ?*const std.mem.Allocator,

    const Self = @This();

    // Note: If you intend to parse commands, you should pass an allocator
    pub fn init(reader: *const net.Stream.Reader, gpa: ?*const std.mem.Allocator) Self {
        return Parser{ .reader = reader, .buf = undefined, .gpa = gpa };
    }

    pub fn parse(self: *Self, comptime T: type, should_allocate: bool) ParsingError!T {
        return switch (@typeInfo(T)) {
            .Pointer => {
                const line = try self.read_line(false);
                return switch (line[0]) {
                    '$' => try self.read_line(should_allocate),
                    '+' => line[1..],
                    else => ParsingError.Unexpected,
                };
            },
            .Int => {
                const line = try self.read_line(false);
                return switch (line[0]) {
                    '*', ':' => std.fmt.parseInt(T, line[1..], 10) catch {
                        return ParsingError.Unexpected;
                    },
                    else => ParsingError.Unexpected,
                };
            },
            else => |err_type| {
                std.log.err("unexpected type: {}", .{err_type});
                return ParsingError.Unexpected;
            },
        };
    }

    pub fn parse_command(self: *Self) ParsingError!Command {
        const command_length = try self.parse(u32, false);
        const command = try self.parse([]const u8, false);

        if (std.ascii.eqlIgnoreCase("PING", command)) {
            if (command_length > 1) {
                return Command{ .ping = try self.parse([]const u8, false) };
            }
            return Command{ .ping = null };
        } else if (std.ascii.eqlIgnoreCase("ECHO", command)) {
            return Command{ .echo = try self.parse([]const u8, false) };
        } else if (std.ascii.eqlIgnoreCase("GET", command)) {
            return Command{ .get = try self.parse([]const u8, false) };
        } else if (std.ascii.eqlIgnoreCase("SET", command)) {
            const key = try self.parse([]const u8, true);
            const value = try self.parse([]const u8, false);
            std.log.info("setting key {s} to value {s}", .{ key, value });
            return Command{ .set = .{ .key = key, .value = value } };
        }

        return ParsingError.Unexpected;
    }

    fn read_line(self: *Self, should_allocate: bool) ParsingError![]const u8 {
        if (if (should_allocate) self.reader.*.readUntilDelimiterOrEofAlloc(self.gpa.?.*, '\r', 4096) else self.reader.*.readUntilDelimiterOrEof(&self.buf, '\r')) |line| {
            self.reader.*.skipBytes(1, .{}) catch {
                return ParsingError.Unexpected;
            };
            if (line == null or line.?.len == 0) {
                std.log.err("reached unexpected EOF", .{});
                return ParsingError.Unexpected;
            }
            return line.?;
        } else |_| {
            return ParsingError.Unexpected;
        }
    }
};
