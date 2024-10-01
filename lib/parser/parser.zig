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

    const Self = @This();

    pub fn init(reader: *const net.Stream.Reader) Self {
        return Parser{ .reader = reader, .buf = undefined };
    }

    pub fn parse(self: *Self, comptime T: type) ParsingError!T {
        return switch (@typeInfo(T)) {
            .Pointer => {
                const line = try self.read_line();
                return switch (line[0]) {
                    '$' => try self.read_line(),
                    '+' => line[1..],
                    else => ParsingError.Unexpected,
                };
            },
            .Int => {
                const line = try self.read_line();
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
        const command_length = try self.parse(u32);
        const command = try self.parse([]const u8);

        if (std.ascii.eqlIgnoreCase("PING", command)) {
            if (command_length > 1) {
                return Command{ .ping = try self.parse([]const u8) };
            }
            return Command{ .ping = null };
        } else if (std.ascii.eqlIgnoreCase("ECHO", command)) {
            return Command{ .echo = try self.parse([]const u8) };
        } else if (std.ascii.eqlIgnoreCase("GET", command)) {
            return Command{ .get = try self.parse([]const u8) };
        } else if (std.ascii.eqlIgnoreCase("SET", command)) {
            const key = try self.parse([]const u8);
            return Command{ .set = .{ .key = key, .value = try self.parse([]const u8) } };
        }

        return ParsingError.Unexpected;
    }

    fn read_line(self: *Self) ParsingError![]const u8 {
        const line = self.reader.*.readUntilDelimiterOrEof(&self.buf, '\r') catch {
            return ParsingError.Unexpected;
        };
        self.reader.*.skipBytes(1, .{}) catch {
            return ParsingError.Unexpected;
        };
        if (line == null or line.?.len == 0) {
            std.log.err("reached unexpected EOF", .{});
            return ParsingError.Unexpected;
        }
        return line.?;
    }
};
