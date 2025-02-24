// Reference: https://github.com/raspberrypi/firmware/wiki/Mailbox-property-interface

const mmio = @import("mmio.zig");
const uart = @import("uart.zig");
const allocator = @import("allocator.zig");
const utils = @import("utils.zig");

const Register = mmio.Register;
const MiniUARTWriter = uart.MiniUARTWriter;

const MAILBOX_BASE = mmio.MMIO_BASE + 0xb880;

const MAILBOX_READ = Register.init(MAILBOX_BASE);
const MAILBOX_STATUS = Register.init(MAILBOX_BASE + 0x18);
const MAILBOX_WRITE = Register.init(MAILBOX_BASE + 0x20);

const MAILBOX_EMPTY = 0x40000000;
const MAILBOX_FULL = 0x80000000;

const REQUEST_CODE = 0x00000000;
const REQUEST_SUCCEED = 0x80000000;
const REQUEST_FAILED = 0x80000001;
const TAG_REQUEST_CODE = 0x00000000;
const END_TAG = 0x00000000;

const GET_BOARD_REVISION = 0x00010002;
const GET_ARM_MEMORY = 0x00010005;

fn mailbox_call(mailbox: []const u32) bool {
    // Combine the message address (upper 28 bits) with channel number (lower 4 bits)
    const addr = @as(u32, @intCast(@intFromPtr(mailbox.ptr))) & ~@as(u32, 0xF);
    const message = addr | 8;

    // Check if Mailbox 0 status register’s full flag is set.
    while ((MAILBOX_STATUS.read_raw() & MAILBOX_FULL) != 0) {
        asm volatile ("nop");
    }

    // If not, then you can write to Mailbox 1 Read/Write register.
    MAILBOX_WRITE.write_raw(message);

    // Check if Mailbox 0 status register’s empty flag is set.
    while ((MAILBOX_STATUS.read_raw() & MAILBOX_EMPTY) != 0) {
        asm volatile ("nop");
    }

    // If not, then you can read from Mailbox 0 Read/Write register.
    const resp = MAILBOX_READ.read_raw();

    // Check if the value is the same as you wrote in step 1.
    return resp == message;
}

pub fn get_board_revision() void {
    var mailbox: [7]u32 align(16) = undefined;

    mailbox[0] = 7 * 4; // buffer size in bytes
    mailbox[1] = REQUEST_CODE;
    mailbox[2] = GET_BOARD_REVISION; // tag identifier
    mailbox[3] = 4; // maximum of request and response value buffer's length
    mailbox[4] = TAG_REQUEST_CODE;
    mailbox[5] = 0; // value buffer
    mailbox[6] = END_TAG;

    if (mailbox_call(mailbox[0..])) {
        utils.send_hex("Board revision: 0x", mailbox[5]);
    } else {
        _ = MiniUARTWriter.write("Failed to get board revision\n") catch {};
    }
}

pub fn get_arm_memory() void {
    var mailbox: [8]u32 align(16) = undefined;

    mailbox[0] = 8 * 4; // buffer size in bytes
    mailbox[1] = REQUEST_CODE;
    mailbox[2] = GET_ARM_MEMORY; // tag identifier
    mailbox[3] = 8; // maximum of request and response value buffer's length
    mailbox[4] = TAG_REQUEST_CODE;
    mailbox[5] = 0; // value buffer
    mailbox[6] = 0; // value buffer
    mailbox[7] = END_TAG;

    if (mailbox_call(mailbox[0..])) {
        utils.send_hex("ARM Memory Base: 0x", mailbox[5]);
        utils.send_hex("ARM Memory Size: 0x", mailbox[6]);
    } else {
        _ = MiniUARTWriter.write("Failed to get arm memory\n") catch {};
    }
}
