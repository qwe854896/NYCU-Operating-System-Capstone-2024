// Reference: https://github.com/raspberrypi/firmware/wiki/Mailbox-property-interface

const mmio = @import("mmio.zig");
const Register = mmio.Register;

const status_val = packed struct(u32) {
    _unused0: u30,
    empty: bool,
    full: bool,
};

const base_address = mmio.base_address + 0xb880;

const read_reg = Register(u32, u32).init(base_address);
const write_reg = Register(u32, u32).init(base_address + 0x20);
pub const status = Register(status_val, status_val).init(base_address + 0x18);

pub const request_code = 0x00000000;
pub const request_succeed = 0x80000000;
pub const request_failed = 0x80000001;
pub const tag_request_code = 0x00000000;
pub const end_tag = 0x00000000;

pub const get_board_revision = 0x00010002;
pub const get_arm_memory = 0x00010005;

fn read() u32 {
    return read_reg.read();
}

fn write(value: u32) void {
    write_reg.write(value);
}

const MailboxError = error{
    RequestFailed,
};

pub fn mboxCall(ch: u8, mbox: usize) bool {
    // Combine the message address (upper 28 bits) with channel number (lower 4 bits)
    const addr = @as(u32, @intCast(mbox)) & ~@as(u32, 0xF);
    const message = addr | ch;

    // Check if Mailbox 0 status register’s full flag is set.
    while (status.read().full) {
        asm volatile ("nop");
    }

    // If not, then you can write to Mailbox 1 Read/Write register.
    write(message);

    // Check if Mailbox 0 status register’s empty flag is set.
    while (status.read().empty) {
        asm volatile ("nop");
    }

    // If not, then you can read from Mailbox 0 Read/Write register.
    const resp = read();

    // Check if the value is the same as you wrote in step 1.
    return resp == message;
}

pub fn getBoardRevision() MailboxError!u32 {
    var mbox: [7]u32 align(16) = undefined;

    mbox[0] = 7 * 4; // buffer size in bytes
    mbox[1] = request_code;
    mbox[2] = get_board_revision; // tag identifier
    mbox[3] = 4; // maximum of request and response value buffer's length
    mbox[4] = tag_request_code;
    mbox[5] = 0; // value buffer
    mbox[6] = end_tag;

    if (!mboxCall(8, @intFromPtr(&mbox))) {
        return MailboxError.RequestFailed;
    }

    return mbox[5];
}

pub fn getArmMemory() MailboxError!struct { u32, u32 } {
    var mbox: [8]u32 align(16) = undefined;

    mbox[0] = 8 * 4; // buffer size in bytes
    mbox[1] = request_code;
    mbox[2] = get_arm_memory; // tag identifier
    mbox[3] = 8; // maximum of request and response value buffer's length
    mbox[4] = tag_request_code;
    mbox[5] = 0; // value buffer
    mbox[6] = 0; // value buffer
    mbox[7] = end_tag;

    if (!mboxCall(8, @intFromPtr(&mbox))) {
        return MailboxError.RequestFailed;
    }

    return .{ mbox[5], mbox[6] };
}
