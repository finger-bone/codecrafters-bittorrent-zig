const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const stringify = @import("decode.zig").stringify;
const decodeDict = @import("decode.zig").decodeDict;
const encode = @import("decode.zig").encode;
const Payload = @import("decode.zig").Payload;
const allocator = std.heap.page_allocator;

pub fn showInfo(args: [][]const u8) !void {
    const file_path = args[2];
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const bufferSize = 4096 * 4096;
    const encodedStr = try file.readToEndAlloc(allocator, bufferSize);
    defer allocator.free(encodedStr);

    const result = try decodeDict(encodedStr, 0);

    const dict = result.payload.dict;

    const announce = dict.get("announce").?.string;
    const info = dict.get("info").?.dict;
    const length = info.get("length").?.int;

    var hash: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    std.crypto.hash.Sha1.hash(try encode(Payload{
        .dict = info,
    }), &hash, .{});

    try stdout.print("Tracker URL: {s}\n", .{announce});
    try stdout.print("Length: {}\n", .{length});
    try stdout.print("Info Hash: {s}\n", .{std.fmt.bytesToHex(hash, .lower)});

    const pieceLength = info.get("piece length").?.int;
    try stdout.print("Piece Length: {}\n", .{pieceLength});

    const pieces = info.get("pieces").?.string;
    try stdout.print("Pieces:\n", .{});
    var window = std.mem.window(u8, pieces, 20, 20);
    while (window.next()) |piece| {
        const h = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(piece[0..20])});
        try stdout.print("{s}\n", .{h});
    }
}
