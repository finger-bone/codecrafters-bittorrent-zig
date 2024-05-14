const std = @import("std");
const stdout = std.io.getStdOut().writer();
const decodeDict = @import("decode.zig").decodeDict;
const allocator = std.heap.page_allocator;

pub fn showInfo(args: [][]const u8) !void {
    const file_path = args[2];
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    const bufferSize = 4096 * 4096;
    const encodedStr = try file.readToEndAlloc(allocator, bufferSize);
    const result = try decodeDict(encodedStr, 0);
    const dict = result.payload.dict;
    const announce = dict.get("announce").?.string;
    const length = dict.get("info").?.dict.get("length").?.int;
    try stdout.print("Tracker URL: {s}\n", .{announce});
    try stdout.print("Length: {}\n", .{length});
}
