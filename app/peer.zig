const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const encoding = @import("encoding.zig");
const parseFile = @import("parse.zig").parseFile;
const Torrent = @import("parse.zig").Torrent;
const allocator = std.heap.page_allocator;
const bufferSize = @import("main.zig").bufferSize;

// the encode function in std.Uri seems to have been removed...?
pub fn urlEncode(input: []const u8) ![]const u8 {
    var output = try std.heap.page_allocator.alloc(u8, input.len * 3);
    var outputIndex: usize = 0;
    for (input) |c| {
        if ((c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_' or c == '.' or c == '~')
        {
            output[outputIndex] = c;
            outputIndex += 1;
        } else {
            output[outputIndex] = '%';
            output[outputIndex + 1] = "0123456789ABCDEF"[c >> 4];
            output[outputIndex + 2] = "0123456789ABCDEF"[c & 0xF];
            outputIndex += 3;
        }
    }
    return output[0..outputIndex];
}

pub fn getPeers(torrent: Torrent) ![]std.net.Address {
    var query = std.ArrayList(u8).init(allocator);
    defer query.deinit();
    const queryWriter = query.writer();
    try queryWriter.print("?", .{});
    try queryWriter.print("info_hash={s}", .{try urlEncode(&torrent.info_hash)});
    try queryWriter.print("&peer_id={s}", .{"00112233445566778899"});
    try queryWriter.print("&port={d}", .{6881});
    try queryWriter.print("&uploaded={d}", .{0});
    try queryWriter.print("&downloaded={d}", .{0});
    try queryWriter.print("&left={d}", .{torrent.info.length});
    try queryWriter.print("&compact={d}", .{1});

    const url = try std.mem.concat(allocator, u8, &.{
        torrent.announce,
        query.items,
    });
    const uri = try std.Uri.parse(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var server_header_buffer: [bufferSize]u8 = undefined;
    var req = try client.open(std.http.Method.GET, uri, std.http.Client.RequestOptions{
        .server_header_buffer = &server_header_buffer,
    });

    defer req.deinit();

    try req.send();
    try req.wait();
    try req.finish();

    var body: [bufferSize]u8 = undefined;
    const len = try req.readAll(&body);

    const response = try encoding.decodeDict(body[0..len], 0);
    var peersWindow = std.mem.window(u8, response.payload.dict.get("peers").?.string, 6, 6);

    var res = std.ArrayList(std.net.Address).init(allocator);

    while (peersWindow.next()) |peer| {
        const ip = peer[0..4];
        const port = std.mem.bytesToValue(u16, peer[4..6]);
        try res.append(std.net.Address.initIp4(
            .{ ip[0], ip[1], ip[2], ip[3] },
            port,
        ));
    }

    return try res.toOwnedSlice();
}

pub fn peersHandler(args: [][]const u8) !void {
    const file_path = args[2];
    const torrent = try parseFile(file_path);
    const allPeers = try getPeers(torrent);
    for (allPeers) |peer| {
        const addr = std.mem.toBytes(peer.in.sa.addr);
        const port = peer.in.sa.port;
        try stdout.print("{d}.{d}.{d}.{d}:{d}\n", .{
            addr[0], addr[1], addr[2], addr[3], port,
        });
    }
}
