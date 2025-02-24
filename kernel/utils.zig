const std = @import("std");
const allocator = @import("allocator.zig");
const uart = @import("uart.zig");

const SimpleAllocator = allocator.SimpleAllocator;
const MiniUARTWriter = uart.MiniUARTWriter;

pub fn parse_hex(buf: []const u8) u32 {
    return std.fmt.parseInt(u32, buf, 16) catch 0;
}

pub fn align_up(value: usize, size: usize) usize {
    return (value + size - 1) & ~(size - 1);
}

fn number_to_hex_string(number: u32, buffer: []u8) usize {
    if (number == 0) {
        buffer[0] = '0';
        return 1;
    }

    const hex = "0123456789ABCDEF";
    var len: usize = 0;
    var num = number;

    while (num != 0) {
        buffer[len] = hex[num & 0xF];
        num >>= 4;
        len += 1;
    }

    // Reverse the string
    for (0..len / 2) |j| {
        const tmp = buffer[j];
        buffer[j] = buffer[len - j - 1];
        buffer[len - j - 1] = tmp;
    }

    return len;
}
