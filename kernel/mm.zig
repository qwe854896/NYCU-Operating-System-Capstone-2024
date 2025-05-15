const registers = @import("mm/registers.zig");
pub const map = @import("mm/map.zig");

pub const tcrInit = registers.tcrInit;
pub const mairInit = registers.mairInit;
pub const enableMMU = registers.enableMMU;
