const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const stringify = @import("encoding.zig").stringify;
const decodeDict = @import("encoding.zig").decodeDict;
const encode = @import("encoding.zig").encode;
const Payload = @import("encoding.zig").Payload;
const allocator = std.heap.page_allocator;
const parseFile = @import("parse.zig").parseFile;
const hashSize = @import("parse.zig").hashSize;

pub fn infoHandler(args: [][]const u8) !void {
    const file_path = args[2];
    const torrent = try parseFile(file_path);

    try stdout.print("Tracker URL: {s}\n", .{torrent.announce});
    try stdout.print("Length: {}\n", .{torrent.info.length});
    try stdout.print("Info Hash: {s}\n", .{std.fmt.bytesToHex(torrent.info_hash, .lower)});
    try stdout.print("Piece Length: {}\n", .{torrent.info.piece_length});

    try stdout.print("Pieces:\n", .{});
    var it = std.mem.window(u8, torrent.info.pieces, hashSize, hashSize);
    while (it.next()) |piece| {
        const h = try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{std.fmt.fmtSliceHexLower(piece[0..20])});
        try stdout.print("{s}\n", .{h});
    }
}
