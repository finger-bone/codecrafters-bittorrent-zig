const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const allocator = std.heap.page_allocator;
const decode = @import("decode.zig");

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        try stdout.print("Usage: your_bittorrent.zig <command> <args>\n", .{});
        std.process.exit(1);
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "decode")) {
        // You can use print statements as follows for debugging, they'll be visible when running tests.
        try stderr.print("Logs from your program will appear here\n", .{});

        // Uncomment this block to pass the first stage
        const encodedStr = args[2];
        const decodedResult = decode.decodeBencode(encodedStr, 0) catch {
            try stdout.print("Invalid encoded value\n", .{});
            std.process.exit(1);
        };

        const result = try decode.stringify(decodedResult.payload);
        try stdout.print("{s}\n", .{result});
    }
}
