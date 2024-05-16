const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const parseFile = @import("parse.zig").parseFile;
const getPeers = @import("peer.zig").getPeers;
const Torrent = @import("parse.zig").Torrent;
const handshake = @import("handshake.zig").handshake;
const allocator = std.heap.page_allocator;
const hashSize = @import("parse.zig").hashSize;
const Handshake = @import("handshake.zig").HandShake;

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

        try stderr.print("Header: length: {d}, id: {}\n", .{ length, id });
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

pub fn downloadPiece(torrent: Torrent, file_path: []const u8, _: []const u8, piece_index: usize) !void {
    const peers = try getPeers(torrent);

    try stderr.print("Trying to download piece {d} from {d} peer\n", .{ piece_index, peers.len });

    var res: struct { handshake: Handshake, stream: std.net.Stream } = undefined;

    const maxAtempts = 5;
    var attempts: usize = 0;
    while (attempts < maxAtempts) {
        res = try handshake(peers[attempts], torrent);
        if (res != null) {
            break;
        }
        attempts += 1;
    }

    const server_handshake = res.handshake;
    const stream = res.stream;
    defer stream.close();

    try stderr.print("Handshake successful\n", .{});
    try stderr.print("Checking hash\n", .{});
    if (!std.mem.eql(u8, &server_handshake.info_hash, &torrent.info_hash)) {
        return error.HashMismatch;
    }

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

    const pieceLength: u32 = @intCast(torrent.info.piece_length);
    _ = try allocator.alloc(
        u8,
        pieceLength,
    );

    var i: u32 = 0;

    try stderr.print("Estiimated block count: {}\n", .{
        pieceLength / blockSize + (if (pieceLength % blockSize != 0)
            @as(u32, 1)
        else
            @as(u32, 0)),
    });

    var piece = try allocator.alloc(u8, pieceLength);

    while (i * blockSize < pieceLength) {
        var payload: [12]u8 = undefined;
        try PeerMessage.buildRequestPayload(
            @intCast(piece_index),
            @intCast(i * blockSize),
            if (pieceLength > blockSize * i + blockSize)
                blockSize
            else
                pieceLength - blockSize * i,
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
        i += 1;

        _ = std.mem.readInt(u32, pieceBlock.payload[0..4], .big);
        const begin = std.mem.readInt(u32, pieceBlock.payload[4..8], .big);
        @memcpy(
            piece[begin .. begin + pieceBlock.payload.len - 8],
            pieceBlock.payload[8..pieceBlock.payload.len],
        );
    }

    var file: std.fs.File = try std.fs.createFileAbsolute(file_path, .{});

    try file.writeAll(piece);

    try stdout.print(
        "Piece {d} downloaded to {s}.",
        .{ piece_index, file_path },
    );
}

pub fn downloadPieceHandler(args: [][]const u8) !void {
    const output_file_path = args[3];
    const torrent_file_path = args[4];
    const piece_index = try std.fmt.parseInt(usize, args[5], 10);

    const torrent = try parseFile(torrent_file_path);

    const piece_hash = torrent.info.pieces[piece_index * hashSize .. (piece_index + 1) * hashSize];

    try downloadPiece(torrent, output_file_path, piece_hash, piece_index);
}
