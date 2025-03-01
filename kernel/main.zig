const std = @import("std");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");
const mailbox = @import("mailbox.zig");
const reboot = @import("reboot.zig");
const cpio = @import("cpio.zig");
const allocator = @import("allocator.zig");
const dtb = @import("dtb/main.zig");

const simple_allocator = allocator.simple_allocator;
const mini_uart_reader = uart.mini_uart_reader;
const mini_uart_writer = uart.mini_uart_writer;

pub const std_options: std.Options = .{
    .page_size_min = 0x1000,
    .page_size_max = 0x1000,
    .logFn = uart.miniUARTLogFn,
};

const Command = enum {
    None,
    Hello,
    Help,
    Reboot,
    ListFiles,
    GetFileContent,
    DemoSimpleAlloc,
    ExecFileContent,
};

fn parseCommand(command: []const u8) Command {
    if (std.mem.eql(u8, command, "hello")) {
        return Command.Hello;
    } else if (std.mem.eql(u8, command, "help")) {
        return Command.Help;
    } else if (std.mem.eql(u8, command, "reboot")) {
        return Command.Reboot;
    } else if (std.mem.eql(u8, command, "ls")) {
        return Command.ListFiles;
    } else if (std.mem.eql(u8, command, "cat")) {
        return Command.GetFileContent;
    } else if (std.mem.eql(u8, command, "demo")) {
        return Command.DemoSimpleAlloc;
    } else if (std.mem.eql(u8, command, "exec")) {
        return Command.ExecFileContent;
    } else {
        return Command.None;
    }
}

export fn exceptionEntry() void {
    var spsr_el1: usize = undefined;
    var elr_el1: usize = undefined;
    var esr_el1: usize = undefined;

    asm volatile (
        \\ mrs %[arg0], spsr_el1
        \\ mrs %[arg1], elr_el1
        \\ mrs %[arg2], esr_el1
        : [arg0] "=r" (spsr_el1),
          [arg1] "=r" (elr_el1),
          [arg2] "=r" (esr_el1),
    );

    std.log.info("Exception:", .{});
    std.log.info("  SPSR_EL1: 0x{X}", .{spsr_el1});
    std.log.info("  ELR_EL1: 0x{X}", .{elr_el1});
    std.log.info("  ESR_EL1: 0x{X}", .{esr_el1});
}

export fn coreTimerEntry() void {
    var cntpct_el0: usize = undefined;
    var cntfrq_el0: usize = undefined;

    asm volatile (
        \\ mrs %[arg0], cntpct_el0
        \\ mrs %[arg1], cntfrq_el0
        \\ mov x0, 2
        \\ mul x0, x0, %[arg1]
        \\ msr cntp_tval_el0, x0
        : [arg0] "=r" (cntpct_el0),
          [arg1] "=r" (cntfrq_el0),
    );

    std.log.info("Core Timer Exception!", .{});
    std.log.info("  {} seconds after booting...", .{cntpct_el0 / cntfrq_el0});
}

fn execFile(content: []const u8) void {
    const program_stack = simple_allocator.alloc(u8, 0x1000) catch {
        @panic("Out of Memory! No buffer for executing a file.");
    };
    const program_start_address: usize = @intFromPtr(content.ptr);
    const program_stack_address: usize = @intFromPtr(program_stack.ptr);
    _ = mini_uart_writer.print("User program at 0x{X} will be run with the stack address 0x{X}\n", .{ program_start_address, program_stack_address }) catch {};
    asm volatile (
        \\ mov x1, 0x0
        \\ msr spsr_el1, x1
        \\ mov x1, %[arg0]
        \\ msr elr_el1, x1
        \\ mov x1, %[arg1]
        \\ msr sp_el0, x1
        \\ eret
        :
        : [arg0] "r" (program_start_address),
          [arg1] "r" (program_stack_address),
    );
}

fn simpleShell() void {
    var buffer = simple_allocator.alloc(u8, 256) catch {
        @panic("Out of Memory! No buffer for simple shell.");
    };
    while (true) {
        _ = mini_uart_writer.write("# ") catch {};

        var recvlen = mini_uart_reader.read(buffer) catch 0;
        const command = parseCommand(buffer[0..recvlen]);

        switch (command) {
            Command.Hello => {
                _ = mini_uart_writer.write("Hello, World!\n") catch {};
            },
            Command.Help => {
                _ = mini_uart_writer.write("Commands:\n") catch {};
                _ = mini_uart_writer.write("  hello - Print 'Hello, World!'\n") catch {};
                _ = mini_uart_writer.write("  help - Print this help message\n") catch {};
                _ = mini_uart_writer.write("  reboot - Reboot the system\n") catch {};
                _ = mini_uart_writer.write("  ls - List files in the initramfs\n") catch {};
                _ = mini_uart_writer.write("  cat - Print the content of a file in the initramfs\n") catch {};
                _ = mini_uart_writer.write("  demo - Run a simple allocator demo\n") catch {};
                _ = mini_uart_writer.write("  exec - Execute a file in the initramfs\n") catch {};
            },
            Command.None => {
                _ = mini_uart_writer.write("Unknown command: ") catch {};
                _ = mini_uart_writer.write(buffer[0..recvlen]) catch {};
                _ = mini_uart_writer.write("\n") catch {};
            },
            Command.Reboot => {
                reboot.reset(100);
            },
            Command.ListFiles => {
                const fs = cpio.listFiles(simple_allocator);
                if (fs) |files| {
                    for (files) |file| {
                        _ = mini_uart_writer.print("{s}\n", .{file}) catch {};
                    }
                }
            },
            Command.GetFileContent => {
                _ = mini_uart_writer.write("Filename: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;
                const c = cpio.getFileContent(buffer[0..recvlen]);
                if (c) |content| {
                    _ = mini_uart_writer.print("{s}\n", .{content}) catch {};
                } else {
                    std.log.info("No such file", .{});
                }
            },
            Command.DemoSimpleAlloc => {
                _ = mini_uart_writer.write("Length of Allocated Memory?: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;

                const name_size = std.fmt.parseInt(u32, buffer[0..recvlen], 10) catch 0;
                const demo_buffer = simple_allocator.alloc(u8, name_size) catch {
                    continue;
                };

                _ = mini_uart_writer.write("Content: ") catch {};
                recvlen = mini_uart_reader.read(demo_buffer) catch 0;

                _ = mini_uart_writer.write("\n") catch {};
                _ = mini_uart_writer.print("Buffer Address: 0x{X}\n", .{@intFromPtr(demo_buffer.ptr)}) catch {};
                _ = mini_uart_writer.write("Buffer Content: ") catch {};
                _ = mini_uart_writer.write(demo_buffer) catch {};
                _ = mini_uart_writer.write("\n") catch {};
            },
            Command.ExecFileContent => {
                _ = mini_uart_writer.write("Filename: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;
                const c = cpio.getFileContent(buffer[0..recvlen]);
                if (c) |content| {
                    execFile(content);
                } else {
                    std.log.info("No such file", .{});
                }
            },
        }
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("!KERNEL PANIC!", .{});
    std.log.err("{s}", .{msg});

    if (error_return_trace) |trace| {
        for (trace.instruction_addresses) |address| {
            if (address == 0) {
                break;
            }
            std.log.err("0x{X}", .{address});
        }
    }

    reboot.reset(100);
    while (true) {}
}

// Main function for the kernel
export fn main(dtb_address: usize) void {
    gpio.init();
    uart.init();

    mailbox.getBoardRevision();
    mailbox.getArmMemory();

    dtb.init(simple_allocator, dtb_address);
    dtb.fdtTraverse(cpio.initRamfsCallback);

    simpleShell();
}

comptime {
    // Avoid using x0 as it stores the address of dtb
    asm (
        \\ .section .text.boot
        \\ .global _start
        \\ _start:
        \\      bl from_el2_to_el1
        \\      bl core_timer_enable
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
        \\      b main
        \\ from_el2_to_el1:
        \\      mov x1, #0x00300000 // No trap to all NEON & FP instructions
        \\      msr cpacr_el1, x1   // References: https://developer.arm.com/documentation/ka006062/latest/
        \\      adr x1, exception_vector_table
        \\      msr vbar_el1, x1
        \\      mov x1, (1 << 31)
        \\      msr hcr_el2, x1
        \\      mov x1, 0x3c5
        \\      msr spsr_el2, x1
        \\      msr elr_el2, lr
        \\      eret
        \\ .align 11 // vector table should be aligned to 0x800
        \\ .global exception_vector_table
        \\ exception_vector_table:
        \\      b exception_handler // branch to a handler function.
        \\      .align 7 // entry size is 0x80, .align will pad 0
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\
        \\      b exception_handler
        \\      .align 7
        \\      b core_timer_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\
        \\ .macro save_all
        \\      sub sp, sp, 32 * 8
        \\      stp x0, x1, [sp ,16 * 0]
        \\      stp x2, x3, [sp ,16 * 1]
        \\      stp x4, x5, [sp ,16 * 2]
        \\      stp x6, x7, [sp ,16 * 3]
        \\      stp x8, x9, [sp ,16 * 4]
        \\      stp x10, x11, [sp ,16 * 5]
        \\      stp x12, x13, [sp ,16 * 6]
        \\      stp x14, x15, [sp ,16 * 7]
        \\      stp x16, x17, [sp ,16 * 8]
        \\      stp x18, x19, [sp ,16 * 9]
        \\      stp x20, x21, [sp ,16 * 10]
        \\      stp x22, x23, [sp ,16 * 11]
        \\      stp x24, x25, [sp ,16 * 12]
        \\      stp x26, x27, [sp ,16 * 13]
        \\      stp x28, x29, [sp ,16 * 14]
        \\      str x30, [sp, 16 * 15]
        \\ .endm
        \\ .macro load_all
        \\      ldp x0, x1, [sp ,16 * 0]
        \\      ldp x2, x3, [sp ,16 * 1]
        \\      ldp x4, x5, [sp ,16 * 2]
        \\      ldp x6, x7, [sp ,16 * 3]
        \\      ldp x8, x9, [sp ,16 * 4]
        \\      ldp x10, x11, [sp ,16 * 5]
        \\      ldp x12, x13, [sp ,16 * 6]
        \\      ldp x14, x15, [sp ,16 * 7]
        \\      ldp x16, x17, [sp ,16 * 8]
        \\      ldp x18, x19, [sp ,16 * 9]
        \\      ldp x20, x21, [sp ,16 * 10]
        \\      ldp x22, x23, [sp ,16 * 11]
        \\      ldp x24, x25, [sp ,16 * 12]
        \\      ldp x26, x27, [sp ,16 * 13]
        \\      ldp x28, x29, [sp ,16 * 14]
        \\      ldr x30, [sp, 16 * 15]
        \\      add sp, sp, 32 * 8
        \\ .endm
        \\ exception_handler:
        \\      save_all
        \\      bl exceptionEntry
        \\      load_all
        \\      eret
        \\ core_timer_enable:
        \\      mov x1, 1
        \\      msr cntp_ctl_el0, x1 // enable
        \\      mrs x1, cntfrq_el0
        \\      msr cntp_tval_el0, x1 // set expired time
        \\      mov x1, 2
        \\      ldr x2, =0x40000040 // CORE0_TIMER_IRQ_CTRL
        \\      str w1, [x2] // unmask timer interrupt
        \\      ret
        \\ core_timer_handler:
        \\      save_all
        \\      bl coreTimerEntry
        \\      load_all
        \\      eret
    );
}
