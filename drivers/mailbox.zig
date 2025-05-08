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

pub fn read() u32 {
    return read_reg.read();
}

pub fn write(value: u32) void {
    write_reg.write(value);
}
