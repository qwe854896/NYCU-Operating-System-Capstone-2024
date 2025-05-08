const sched = @import("sched.zig");
const drivers = @import("drivers");
const mailbox = drivers.mailbox;

const MailboxError = error{
    RequestFailed,
};

pub fn sysMboxCall(ch: u8, mbox: usize) bool {
    const addr = @as(u32, @intCast(mbox)) & ~@as(u32, 0xF);
    const message = addr | ch;

    while (mailbox.status.read().full) {
        sched.schedule();
    }

    mailbox.write(message);

    while (mailbox.status.read().empty) {
        sched.schedule();
    }

    const resp = mailbox.read();

    return resp == message;
}

fn mbox_call(ch: u8, mbox: []u32) bool {
    // Combine the message address (upper 28 bits) with channel number (lower 4 bits)
    const addr = @as(u32, @intCast(@intFromPtr(mbox.ptr))) & ~@as(u32, 0xF);
    const message = addr | ch;

    // Check if Mailbox 0 status register’s full flag is set.
    while (mailbox.status.read().full) {
        asm volatile ("nop");
    }

    // If not, then you can write to Mailbox 1 Read/Write register.
    mailbox.write(message);

    // Check if Mailbox 0 status register’s empty flag is set.
    while (mailbox.status.read().empty) {
        asm volatile ("nop");
    }

    // If not, then you can read from Mailbox 0 Read/Write register.
    const resp = mailbox.read();

    // Check if the value is the same as you wrote in step 1.
    return resp == message;
}

pub fn getBoardRevision() MailboxError!u32 {
    var mbox: [7]u32 align(16) = undefined;

    mbox[0] = 7 * 4; // buffer size in bytes
    mbox[1] = mailbox.request_code;
    mbox[2] = mailbox.get_board_revision; // tag identifier
    mbox[3] = 4; // maximum of request and response value buffer's length
    mbox[4] = mailbox.tag_request_code;
    mbox[5] = 0; // value buffer
    mbox[6] = mailbox.end_tag;

    if (!mbox_call(8, mbox[0..])) {
        return MailboxError.RequestFailed;
    }

    return mbox[5];
}

pub fn getArmMemory() MailboxError!struct { u32, u32 } {
    var mbox: [8]u32 align(16) = undefined;

    mbox[0] = 8 * 4; // buffer size in bytes
    mbox[1] = mailbox.request_code;
    mbox[2] = mailbox.get_arm_memory; // tag identifier
    mbox[3] = 8; // maximum of request and response value buffer's length
    mbox[4] = mailbox.tag_request_code;
    mbox[5] = 0; // value buffer
    mbox[6] = 0; // value buffer
    mbox[7] = mailbox.end_tag;

    if (!mbox_call(8, mbox[0..])) {
        return MailboxError.RequestFailed;
    }

    return .{ mbox[5], mbox[6] };
}
