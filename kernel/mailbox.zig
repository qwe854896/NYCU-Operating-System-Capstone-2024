// Reference: https://github.com/raspberrypi/firmware/wiki/Mailbox-property-interface

const std = @import("std");
const mmio = @import("mmio.zig");

const Register = mmio.Register;

const base_address = mmio.base_address + 0xb880;

const mailbox_read = Register.init(base_address);
const mailbox_status = Register.init(base_address + 0x18);
const mailbox_write = Register.init(base_address + 0x20);

const mailbox_empty = 0x40000000;
const mailbox_full = 0x80000000;

const request_code = 0x00000000;
const request_succeed = 0x80000000;
const request_failed = 0x80000001;
const tag_request_code = 0x00000000;
const end_tag = 0x00000000;

const get_board_revision = 0x00010002;
const get_arm_memory = 0x00010005;

const MailboxError = error{
    RequestFailed,
};

fn mailbox_call(mailbox: []u32) bool {
    // Combine the message address (upper 28 bits) with channel number (lower 4 bits)
    const addr = @as(u32, @intCast(@intFromPtr(mailbox.ptr))) & ~@as(u32, 0xF);
    const message = addr | 8;

    // Check if Mailbox 0 status register’s full flag is set.
    while ((mailbox_status.readRaw() & mailbox_full) != 0) {
        asm volatile ("nop");
    }

    // If not, then you can write to Mailbox 1 Read/Write register.
    mailbox_write.writeRaw(message);

    // Check if Mailbox 0 status register’s empty flag is set.
    while ((mailbox_status.readRaw() & mailbox_empty) != 0) {
        asm volatile ("nop");
    }

    // If not, then you can read from Mailbox 0 Read/Write register.
    const resp = mailbox_read.readRaw();

    // Check if the value is the same as you wrote in step 1.
    return resp == message;
}

pub fn getBoardRevision() MailboxError!u32 {
    var mailbox: [7]u32 align(16) = undefined;

    mailbox[0] = 7 * 4; // buffer size in bytes
    mailbox[1] = request_code;
    mailbox[2] = get_board_revision; // tag identifier
    mailbox[3] = 4; // maximum of request and response value buffer's length
    mailbox[4] = tag_request_code;
    mailbox[5] = 0; // value buffer
    mailbox[6] = end_tag;

    if (!mailbox_call(mailbox[0..])) {
        return MailboxError.RequestFailed;
    }

    return mailbox[5];
}

pub fn getArmMemory() MailboxError!struct { u32, u32 } {
    var mailbox: [8]u32 align(16) = undefined;

    mailbox[0] = 8 * 4; // buffer size in bytes
    mailbox[1] = request_code;
    mailbox[2] = get_arm_memory; // tag identifier
    mailbox[3] = 8; // maximum of request and response value buffer's length
    mailbox[4] = tag_request_code;
    mailbox[5] = 0; // value buffer
    mailbox[6] = 0; // value buffer
    mailbox[7] = end_tag;

    if (!mailbox_call(mailbox[0..])) {
        return MailboxError.RequestFailed;
    }

    return .{ mailbox[5], mailbox[6] };
}
