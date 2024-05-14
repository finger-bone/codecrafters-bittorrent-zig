const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const allocator = std.heap.page_allocator;
const decode = @import("decode.zig").decode;
const showInfo = @import("info.zig").showInfo;
const peers = @import("peer.zig").peers;

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        try stdout.print("Usage: your_bittorrent.zig <command> <args>\n", .{});
        std.process.exit(1);
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "decode")) {
        try decode(args);
    } else if (std.mem.eql(u8, command, "info")) {
        try showInfo(args);
    } else if (std.mem.eql(u8, command, "peers")) {
        try peers(args);
    }
}
