const std = @import("std");
const parseFile = @import("parse.zig").parseFile;
const Torrent = @import("parse.zig").Torrent;
const stderr = std.io.getStdErr().writer();

const stdout = std.io.getStdOut().writer();

pub const HandShake = extern struct {
    protocol_length: u8 align(1) = 19,
    ident: [19]u8 align(1) = "BitTorrent protocol".*,
    reserved: [8]u8 align(1) = std.mem.zeroes([8]u8),
    info_hash: [20]u8 align(1),
    peer_id: [20]u8 align(1),
};

pub fn handshake(address: std.net.Address, torrent: Torrent) !struct { handshake: HandShake, stream: std.net.Stream } {
    const ip = std.mem.toBytes(address.in.sa.addr);
    const port = address.getPort();
    try stderr.print(
        "Connecting to {d}.{d}.{d}.{d}:{d}\n",
        .{ ip[0], ip[1], ip[2], ip[3], port },
    );

    const handshakeContent = HandShake{
        .info_hash = torrent.info_hash,
        .peer_id = "00112233445566778899".*,
    };

    const stream = try std.net.tcpConnectToAddress(address);

    try stderr.print("Connected\n", .{});

    const writer = stream.writer();
    // no endian issue because all fields are u8
    try writer.writeStruct(handshakeContent);

    const reader = stream.reader();

    const serverHandshake = try reader.readStructEndian(HandShake, .big);
    return .{
        .handshake = serverHandshake,
        .stream = stream,
    };
}

pub fn handshakeHandler(args: [][]const u8) !void {
    var it = std.mem.splitScalar(u8, args[3], ':');
    const ip = it.first();
    const port = it.next().?;

    const address = try std.net.Address.resolveIp(
        ip,
        try std.fmt.parseInt(u16, port, 10),
    );

    const file_path = args[2];
    const torrent = try parseFile(file_path);

    const res = try handshake(address, torrent);
    defer res.stream.close();

    try stdout.print("Peer ID: {s}\n", .{std.fmt.bytesToHex(res.handshake.peer_id, .lower)});
}
