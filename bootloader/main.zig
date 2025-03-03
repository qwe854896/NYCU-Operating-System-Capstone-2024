const std = @import("std");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");

const KERNEL_LOAD_ADDRESS = 0x80000;
const START_BYTE: u8 = 0xAC;

// Main function for the kernel
export fn main(dtb_address: usize) usize {
    gpio.init();
    uart.init();

    // Wait for start byte
    while (uart.recv() != START_BYTE) {
        asm volatile ("nop");
    }

    // Receive the size of the kernel image
    var kernel_size: u32 = 0;
    for (0..4) |i| {
        kernel_size |= @as(u32, @intCast(uart.recv())) << @intCast(i * 8);
    }

    // Receive the kernel binary
    var dest_ptr: [*]u8 = @ptrFromInt(KERNEL_LOAD_ADDRESS);
    var dest: []u8 = dest_ptr[0..kernel_size];
    for (0..kernel_size) |i| {
        dest[i] = uart.recv();
    }

    return dtb_address; // pass to the actual kernel
}

comptime {
    // Avoid using x0 as it stores the address of dtb
    asm (
        \\ .section .text.bootloader
        \\ .global _start
        \\ _start:
        \\      ldr x1, =_start
        \\      ldr x2, =_bss_start
        \\      ldr x3, =0x80000
        \\ 1:
        \\      cmp x1, x2
        \\      b.ge 2f
        \\      ldr x4, [x3], #8
        \\      str x4, [x1], #8
        \\      b 1b
        \\ 2:
        \\      ldr x1, =_text_boot_start
        \\      br x1
        \\ .section .text.boot
        \\ .global _start_boot
        \\ _start_boot:
        \\      ldr x1, =_stack_top
        \\      mov sp, x1
        \\      ldr x1, =_bss_start
        \\      ldr x2, =_bss_end
        \\      mov x3, #0
        \\ 1:
        \\      cmp x1, x2
        \\      b.ge 2f
        \\      str x3, [x1], #8
        \\      b 1b
        \\ 2:
        \\      bl main
        \\      ldr x1, =0x80000
        \\      br x1
    );
}
