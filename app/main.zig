const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const allocator = std.heap.page_allocator;
const decodeHandler = @import("encoding.zig").decodeHandler;
const infoHandler = @import("info.zig").infoHandler;
const peersHandler = @import("peer.zig").peersHandler;
const handshakeHandler = @import("handshake.zig").handshakeHandler;
const downloadPieceHandler = @import("download_piece.zig").downloadPieceHandler;

pub const bufferSize = 4096 * 4;

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        try stdout.print("Usage: your_bittorrent.zig <command> <args>\n", .{});
        std.process.exit(1);
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "decode")) {
        try stderr.print("decode\n", .{});
        try decodeHandler(args);
    } else if (std.mem.eql(u8, command, "info")) {
        try stderr.print("info\n", .{});
        try infoHandler(args);
    } else if (std.mem.eql(u8, command, "peers")) {
        try stderr.print("peers\n", .{});
        try peersHandler(args);
    } else if (std.mem.eql(u8, command, "handshake")) {
        try stderr.print("handshake\n", .{});
        try handshakeHandler(args);
    } else if (std.mem.eql(u8, command, "download_piece")) {
        try stderr.print("download_piece\n", .{});
        try downloadPieceHandler(args);
    }
}
