const std = @import("std");
const encoding = @import("encoding.zig");
const bufferSize = @import("main.zig").bufferSize;

pub const Torrent = struct {
    announce: []const u8,
    info_hash: [20]u8,
    info: struct {
        length: i64,
        piece_length: i64,
        pieces: []const u8,
    },
    pub fn stringify(self: @This()) []const u8 {
        const allocator = std.heap.page_allocator;
        const buffer = std.mem.Buffer.init(allocator, bufferSize);
        defer buffer.deinit();

        try buffer.writer().print("{");
        try buffer.writer().print("\"announce\": \"{}\", ", .{self.announce});
        try buffer.writer().print("\"info_hash\": \"{}\", ", .{std.encoding.hex.encode(&self.info_hash)});
        try buffer.writer().print("\"info\": {{");
        try buffer.writer().print("\"length\": {}, ", .{self.info.length});
        try buffer.writer().print("\"piece_length\": {}, ", .{self.info.piece_length});
        try buffer.writer().print("\"pieces\": \"{}\"", .{self.info.pieces});
        try buffer.writer().print("}}");
        try buffer.writer().print("}");

        return buffer.toSlice();
    }
};

pub fn parseFile(file_path: []const u8) !Torrent {
    const allocator = std.heap.page_allocator;
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const encodedStr = try file.readToEndAlloc(allocator, bufferSize);
    defer allocator.free(encodedStr);

    const result = try encoding.decodeDict(encodedStr, 0);

    const dict = result.payload.dict;

    const announce = dict.get("announce").?.string;
    const info = dict.get("info").?.dict;
    const length = info.get("length").?.int;

    var info_hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(try encoding.encode(encoding.Payload{
        .dict = info,
    }), &info_hash, .{});

    const piece_length = info.get("piece length").?.int;

    const pieces = info.get("pieces").?.string;

    return Torrent{
        .announce = announce,
        .info_hash = info_hash,
        .info = .{
            .length = length,
            .piece_length = piece_length,
            .pieces = pieces,
        },
    };
}
