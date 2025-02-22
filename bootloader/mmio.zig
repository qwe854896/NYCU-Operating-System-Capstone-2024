// Reference: https://www.scattered-thoughts.net/writing/mmio-in-zig/

pub const MMIO_BASE = 0x3F000000;

pub const Register = struct {
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
