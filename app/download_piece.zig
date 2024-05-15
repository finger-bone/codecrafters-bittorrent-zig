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
const block_size = 16 * 1024;
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
    pub const Head = extern struct {
        length: u32 align(1),
        id: PeerMessageId align(1),
    };
    head: PeerMessage.Head,
    payload: []const u8 align(1),

    pub fn tryReceive(stream: std.net.Stream) !PeerMessage {
        const reader = stream.reader();
        const head = try reader.readStruct(PeerMessage.Head);
        var buffer: [bufferSize]u8 = undefined;
        const l = try reader.read(buffer[0..head.length]);
        if (l != head.length) {
            return error.IncompleteMessage;
        }
        const payload = buffer[0..head.length];
        return PeerMessage{ .head = head, .payload = payload };
    }

    pub fn sendMessage(stream: std.net.Stream, message: PeerMessage) !void {
        const writer = stream.writer();
        try writer.writeStruct(message.head);
        _ = try writer.write(message.payload);
    }

    pub fn buildMessage(id: PeerMessageId, payload: []const u8) !PeerMessage {
        return PeerMessage{ .head = PeerMessage.Head{ .length = @intCast(payload.len), .id = id }, .payload = payload };
    }

    pub fn buildRequestPayload(piece_index: usize, block_index: usize, piece_len: usize) []const u8 {
        const index: u32 = @intCast(piece_index);
        const begin: u32 = @intCast(block_index * block_size);
        const length: u32 = @intCast(if (begin + block_size > piece_len) piece_len - begin else block_size);
        var payload: [12]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], index, .big);
        std.mem.writeInt(u32, payload[4..8], begin, .big);
        std.mem.writeInt(u32, payload[8..12], length, .big);
        return &payload;
    }
};

pub fn downloadPiece(torrent: Torrent, file_path: []const u8, piece_hash: []const u8, piece_index: usize) !void {
    const peers = try getPeers(torrent);
    try stderr.print("Trying to download piece {d} from {d} peer\n", .{ piece_index, peers.len });

    const res = try handshake(peers[1], torrent);

    const server_handshake = res.handshake;
    const stream = res.stream;
    defer stream.close();
    if (!std.mem.eql(u8, &server_handshake.info_hash, &torrent.info_hash)) {
        return error.HashMismatch;
    }

    // receive bitfield message
    const bitfieldMessage = try PeerMessage.tryReceive(stream);
    if (bitfieldMessage.head.id != PeerMessageId.bitfield) {
        return error.UnexpectedMessage;
    }

    // send interested message with empty payload
    const interestedMessage = try PeerMessage.buildMessage(PeerMessageId.interested, &[_]u8{});
    try PeerMessage.sendMessage(stream, interestedMessage);

    // receive unchoke message
    const unchokeMessage = try PeerMessage.tryReceive(stream);
    if (unchokeMessage.head.id != PeerMessageId.unchoke) {
        return error.UnexpectedMessage;
    }

    // send request message
    var block_index: usize = 0;
    while (block_index * block_size < torrent.info.piece_length) {
        const requestPayload = PeerMessage.buildRequestPayload(
            piece_index,
            block_index,
            @intCast(torrent.info.piece_length),
        );
        const requestMessage = try PeerMessage.buildMessage(
            PeerMessageId.request,
            requestPayload,
        );

        try stderr.print("\n", .{});
        try stderr.print("Sending request message", .{});
        try stderr.print("Payload is", .{});
        try stderr.print("{d} {d} {d}", .{ requestPayload[0..4], requestPayload[4..8], requestPayload[8..12] });

        try PeerMessage.sendMessage(stream, requestMessage);

        // receive piece message
        const pieceMessage = try PeerMessage.tryReceive(stream);
        if (pieceMessage.head.id != PeerMessageId.piece) {
            return error.UnexpectedMessage;
        }

        const piece_payload = pieceMessage.payload;

        // verify piece hash
        var received_piece_hash: [
            hashSize
        ]u8 = undefined;
        std.crypto.hash.Sha1.hash(
            piece_payload,
            &received_piece_hash,
            .{},
        );
        if (!std.mem.eql(u8, &received_piece_hash, piece_hash)) {
            return error.HashMismatch;
        }

        // write piece to file
        const file = try std.fs.cwd().openFile(
            file_path,
            std.fs.File.OpenFlags{ .mode = .write_only },
        );
        defer file.close();

        const offset = piece_index * @as(usize, @intCast(torrent.info.piece_length)) + block_index * block_size;
        _ = try file.seekTo(offset);
        _ = try file.write(piece_payload);

        block_index += 1;
    }

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
