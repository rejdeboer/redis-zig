const std = @import("std");
const net = std.net;

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_alloc.deinit() == .ok);
    const gpa = gpa_alloc.allocator();

    const stdout = std.io.getStdOut().writer();

    const address = try net.Address.resolveIp("127.0.0.1", 6379);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        const connection = try listener.accept();

        try stdout.print("accepted new connection", .{});
        defer connection.stream.close();

        const client_reader = connection.stream.reader();
        const client_writer = connection.writer();
        while (true) {
            const msg = try client_reader.readUntilDelimiterOrEofAlloc(gpa, '\n', 65536) orelse break;
            defer gpa.free(msg);

            std.log.info("Recieved message: \"{}\"", .{std.zig.fmtEscapes(msg)});

            try client_writer.writeAll("+PONG\r\n");
        }
    }
}
