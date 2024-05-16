const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const parseFile = @import("parse.zig").parseFile;
const getPeers = @import("peer.zig").getPeers;
const Torrent = @import("parse.zig").Torrent;
const handshake = @import("handshake.zig").handshake;
const allocator = std.heap.page_allocator;
const hashSize = @import("parse.zig").hashSize;

// 16 KB
const blockSize: u32 = 16 * 1024;
const bufferSize = @import("main.zig").bufferSize;

pub const PeerMessageId = enum(u8) {
    choke = 0,
    unchoke = 1,
    interested = 2,
    not_interested = 3,
    have = 4,
    bitfield = 5,
    request = 6,
    piece = 7,
    cancel = 8,
    hearbeat = 9,
};

pub const PeerMessage = struct {
    length: u32,
    id: PeerMessageId,
    payload: []const u8,

    pub fn tryReceive(stream: std.net.Stream) !PeerMessage {
        const reader = stream.reader();

        const length = try reader.readInt(u32, .big);

        const id = try reader.readByte();

        const payload = try allocator.alloc(u8, length - 1);
        const l = try reader.readAll(payload);

        try stderr.print("Received {d} bytes\n", .{l});
        try stderr.print("Expected {d} bytes\n", .{length - 1});
        return PeerMessage{ .length = length, .id = @enumFromInt(id), .payload = payload };
    }

    pub fn sendMessage(stream: std.net.Stream, message: PeerMessage) !void {
        const writer = stream.writer();
        var buffer: [bufferSize]u8 = undefined;
        std.mem.writeInt(u32, buffer[0..4], message.length, .big);
        buffer[4] = @intCast(@intFromEnum(message.id));
        try writer.writeAll(buffer[0..5]);
        try writer.writeAll(message.payload);
    }

    pub fn buildMessage(id: PeerMessageId, payload: []const u8) !PeerMessage {
        return PeerMessage{ .length = @intCast(payload.len + 1), .id = id, .payload = payload };
    }

    pub fn buildRequestPayload(index: u32, begin: u32, length: u32, payload: []u8) !void {
        std.mem.writeInt(u32, payload[0..4], index, .big);
        std.mem.writeInt(u32, payload[4..8], begin, .big);
        std.mem.writeInt(u32, payload[8..12], length, .big);
        try stderr.print(
            "Payload: {d} {d} {d}\n",
            .{
                std.mem.readInt(u32, payload[0..4], .big),
                std.mem.readInt(u32, payload[4..8], .big),
                std.mem.readInt(u32, payload[8..12], .big),
            },
        );
    }
};

pub fn downloadPiece(torrent: Torrent, piece_hash: []const u8, piece_index: usize) ![]u8 {
    try stderr.print(
        "Torrent Piece Length: {d}, Total: {d}, Piece Index: {d}\n",
        .{ torrent.info.piece_length, torrent.info.length, piece_index },
    );

    const peers = try getPeers(torrent);

    try stderr.print("Trying to download piece {d} from {d} peer\n", .{ piece_index, peers.len });

    const res = try handshake(peers[1], torrent);

    const stream = res.stream;
    defer stream.close();

    try stderr.print("Handshake successful\n", .{});
    try stderr.print("Checking hash\n", .{});

    // receive bitfield message
    try stderr.print("Try Receiving bitfield message\n", .{});
    const bitfieldMessage = try PeerMessage.tryReceive(stream);
    if (bitfieldMessage.id != PeerMessageId.bitfield) {
        return error.UnexpectedMessage;
    }
    try stderr.print("Received bitfield message\n", .{});

    // send interested message with empty payload
    try stderr.print("Sending interested message\n", .{});
    const interestedMessage = try PeerMessage.buildMessage(PeerMessageId.interested, &[_]u8{});
    try PeerMessage.sendMessage(stream, interestedMessage);
    try stderr.print("Sent interested message\n", .{});

    // receive unchoke message
    try stderr.print("Try Receiving unchoke message\n", .{});
    const unchokeMessage = try PeerMessage.tryReceive(stream);
    if (unchokeMessage.id != PeerMessageId.unchoke) {
        return error.UnexpectedMessage;
    }
    try stderr.print("Received unchoke message\n", .{});

    // send request message
    try stderr.print("Sending request message\n", .{});

    var i: u32 = 0;

    const totalLength: u32 = @intCast(torrent.info.length);
    const eachPieceLength: u32 = @intCast(torrent.info.piece_length);
    const totalPieces: u32 = @intCast(torrent.info.pieces.len / hashSize);

    const thisPieceSize = if (piece_index == totalPieces - 1) totalLength % eachPieceLength else eachPieceLength;

    var piece = try allocator.alloc(u8, thisPieceSize);

    while (i * blockSize < thisPieceSize) {
        var payload: [12]u8 = undefined;

        const blockLength = if (thisPieceSize > (blockSize * i + blockSize)) blockSize else thisPieceSize - blockSize * i;

        try stderr.print("\nBlock Index: {d}\n", .{i});
        try stderr.print("Block Length: {d}\n\n", .{blockLength});
        try PeerMessage.buildRequestPayload(
            @intCast(piece_index),
            @intCast(i * blockSize),
            @intCast(blockLength),
            &payload,
        );
        const rqst = try PeerMessage.buildMessage(PeerMessageId.request, &payload);

        try stderr.print(
            "Sending request message for piece {d} block {d}\n",
            .{ piece_index, i },
        );

        try PeerMessage.sendMessage(stream, rqst);
        const pieceBlock = try PeerMessage.tryReceive(stream);
        if (pieceBlock.id != .piece) return error.InvalidPiece;

        _ = std.mem.readInt(u32, pieceBlock.payload[0..4], .big);
        const begin = std.mem.readInt(u32, pieceBlock.payload[4..8], .big);
        @memcpy(
            piece[begin .. begin + pieceBlock.payload.len - 8],
            pieceBlock.payload[8..pieceBlock.payload.len],
        );
        i += 1;
    }

    var receivedHash: [hashSize]u8 = undefined;
    std.crypto.hash.Sha1.hash(piece, receivedHash[0..hashSize], .{});
    if (!std.mem.eql(u8, piece_hash, &receivedHash)) {
        return error.HashMismatch;
    }

    return piece;
}

pub fn downloadPieceHandler(args: [][]const u8) !void {
    const output_file_path = args[3];
    const torrent_file_path = args[4];
    const piece_index = try std.fmt.parseInt(usize, args[5], 10);

    const torrent = try parseFile(torrent_file_path);

    const piece_hash = torrent.info.pieces[piece_index * hashSize .. (piece_index + 1) * hashSize];

    const piece = try downloadPiece(torrent, piece_hash, piece_index);

    var file: std.fs.File = try std.fs.createFileAbsolute(output_file_path, .{});

    try file.writeAll(piece);

    try stdout.print(
        "Piece {d} downloaded to {s}.",
        .{ piece_index, output_file_path },
    );
}
