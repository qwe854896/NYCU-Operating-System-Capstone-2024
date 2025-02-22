const std = @import("std");

pub fn strcmp(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }

    for (0.., a) |i, a_byte| {
        if (a_byte != b[i]) {
            return false;
        }
    }

    return true;
}

pub fn parse_hex(buf: []const u8) u32 {
    return std.fmt.parseInt(u32, buf, 16) catch 0;
}

pub fn align_up(value: usize, size: usize) usize {
    return (value + size - 1) & ~(size - 1);
}
