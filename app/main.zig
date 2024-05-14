const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const allocator = std.heap.page_allocator;

const Payload = union(enum) {
    string: []const u8,
    int: i64,
};

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        try stdout.print("Usage: your_bittorrent.zig <command> <args>\n", .{});
        std.process.exit(1);
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "decode")) {
        // You can use print statements as follows for debugging, they'll be visible when running tests.
        try stderr.print("Logs from your program will appear here\n", .{});

        // Uncomment this block to pass the first stage
        const encodedStr = args[2];
        const decodedStr = decodeBencode(encodedStr) catch {
            try stdout.print("Invalid encoded value\n", .{});
            std.process.exit(1);
        };
        var string = std.ArrayList(u8).init(allocator);
        switch (decodedStr) {
            inline .string, .int => |payload| try std.json.stringify(payload, .{}, string.writer()),
        }
        const jsonStr = try string.toOwnedSlice();
        try stdout.print("{s}\n", .{jsonStr});
    }
}

fn decodeBencode(encodedValue: []const u8) !Payload {
    if (encodedValue[0] >= '0' and encodedValue[0] <= '9') {
        const firstColon = std.mem.indexOf(u8, encodedValue, ":");
        if (firstColon == null) {
            return error.InvalidArgument;
        }
        return Payload{ .string = encodedValue[firstColon.? + 1 ..] };
    } else if (encodedValue[0] == 'i') {
        //integers, i<number>e
        const e_char_maybe = std.mem.indexOf(u8, encodedValue, "e");
        if (e_char_maybe == null) {
            return error.InvalidArgument;
        }
        return Payload{
            .int = try std.fmt.parseInt(i64, encodedValue[1..e_char_maybe.?], 10),
        };
    } else {
        try stdout.print("Only strings are supported at the moment\n", .{});
        std.process.exit(1);
    }
}
