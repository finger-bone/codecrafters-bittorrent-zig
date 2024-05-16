const std = @import("std");
const allocator = std.heap.page_allocator;
const downloadPiece = @import("download_piece.zig").downloadPiece;
const parseFile = @import("parse.zig").parseFile;
const hashSize = @import("parse.zig").hashSize;

pub fn downloadHandler(args: [][]const u8) !void {
    const outputFilePath = args[3];
    const torrentPath = args[4];

    const torrent = try parseFile(torrentPath);
    var result = try allocator.alloc(
        u8,
        @intCast(torrent.info.length),
    );
    defer allocator.free(result);

    const totalPiece = torrent.info.pieces.len / hashSize;
    const eachPieceLength: usize = @intCast(torrent.info.piece_length);

    for (0..totalPiece) |i| {
        const pieceStart: usize = @intCast(
            eachPieceLength * i,
        );
        const pieceEnd: usize = @min(
            eachPieceLength * (i + 1),
            @as(usize, @intCast(torrent.info.length)),
        );
        const downloadedPiece = try downloadPiece(
            torrent,
            torrent.info.pieces[i * hashSize .. (i + 1) * hashSize],
            i,
        );
        defer allocator.free(downloadedPiece);
        @memcpy(result[pieceStart..pieceEnd], downloadedPiece);
    }

    const file = try std.fs.createFileAbsolute(
        outputFilePath,
        .{},
    );
    defer file.close();

    try file.writeAll(result);
}
