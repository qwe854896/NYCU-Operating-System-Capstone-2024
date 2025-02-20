const std = @import("std");

const GPIO_BASE = 0x3F200000;
const UART_BASE = 0x3F215000;

// Reference: https://www.scattered-thoughts.net/writing/mmio-in-zig/

const Register = struct {
    raw_ptr: *volatile u32, // It's important to use volatile, so reads and writes are never optimized

    pub fn init(address: usize) Register {
        return Register{ .raw_ptr = @ptrFromInt(address) };
    }

    pub fn read_raw(self: Register) u32 {
        return self.raw_ptr.*;
    }

    pub fn write_raw(self: Register, value: u32) void {
        self.raw_ptr.* = value;
    }
};

// GPIO Initialization for Mini UART
fn gpio_init() void {
    const GPFSEL1 = Register.init(GPIO_BASE + 0x04);
    const GPPUD = Register.init(GPIO_BASE + 0x94);

    // Set GPIO 14 & 15 to ALT5 (Mini UART mode)
    var reg = GPFSEL1.read_raw();
    reg &= ~@as(u32, 0b111 << 12) & ~@as(u32, 0b111 << 15); // Clear FSEL14 and FSEL15
    reg |= (0b010 << 12) | (0b010 << 15); // ALT5 for UART
    GPFSEL1.write_raw(reg);

    // Disable pull-up/down for GPIO 14 & 15
    GPPUD.write_raw(0);
}

// UART Initialization
fn uart_init() void {
    const AUX_ENABLES = Register.init(UART_BASE + 0x04);
    const AUX_MU_IER_REG = Register.init(UART_BASE + 0x44);
    const AUX_MU_IIR_REG = Register.init(UART_BASE + 0x48);
    const AUX_MU_LCR_REG = Register.init(UART_BASE + 0x4C);
    const AUX_MU_MCR_REG = Register.init(UART_BASE + 0x50);
    const AUX_MU_CNTL_REG = Register.init(UART_BASE + 0x60);
    const AUX_MU_BAUD_REG = Register.init(UART_BASE + 0x68);

    // Enable Mini UART
    AUX_ENABLES.write_raw(1);

    // Disable TX and RX during configuration
    AUX_MU_CNTL_REG.write_raw(0);

    // Disable interrupts
    AUX_MU_IER_REG.write_raw(0);

    // Set data size to 8-bit
    AUX_MU_LCR_REG.write_raw(3);

    // Disable flow control
    AUX_MU_MCR_REG.write_raw(0);

    // Set baud rate to 115200 (270 divisor)
    AUX_MU_BAUD_REG.write_raw(270);

    // Clear FIFOs and set interrupt mode
    AUX_MU_IIR_REG.write_raw(6);

    // Enable transmitter and receiver
    AUX_MU_CNTL_REG.write_raw(3);
}

// Send a byte over UART
export fn uart_send(byte: u8) void {
    const AUX_MU_LSR_REG = Register.init(UART_BASE + 0x54);
    const AUX_MU_IO_REG = Register.init(UART_BASE + 0x40);

    while ((AUX_MU_LSR_REG.read_raw() & 0x20) == 0) {
        // Wait until the transmitter is empty
        asm volatile ("nop");
    }
    AUX_MU_IO_REG.write_raw(byte);
}

// Receive a byte over UART
export fn uart_recv() u8 {
    const AUX_MU_LSR_REG = Register.init(UART_BASE + 0x54);
    const AUX_MU_IO_REG = Register.init(UART_BASE + 0x40);

    while ((AUX_MU_LSR_REG.read_raw() & 0x01) == 0) {
        // Wait until data is ready
        asm volatile ("nop");
    }
    return @intCast(AUX_MU_IO_REG.read_raw() & 0xFF);
}

comptime {
    asm (
        \\ .section .text.boot
        \\ .global _start
        \\ _start:
        \\      ldr x0, =_stack_top
        \\      mov sp, x0
        \\      ldr x1, =_bss_start
        \\      ldr x2, =_bss_end
        \\      mov x3, #0
        \\ 1:
        \\      cmp x1, x2
        \\      b.ge 2f
        \\      str x3, [x1], #8
        \\      b 1b
        \\ 2:
        \\      b main
    );
}

// Main function for the kernel
export fn main() void {
    gpio_init();
    uart_init();

    while (true) {
        const received = uart_recv();
        uart_send(received); // Echo received data
    }
}
