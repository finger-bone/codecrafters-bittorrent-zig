const decode = @import("decode.zig");

test "decode" {
    _ = try decode.decodeBencode(
        "l9:blueberryi587ee",
        0,
    );
}
