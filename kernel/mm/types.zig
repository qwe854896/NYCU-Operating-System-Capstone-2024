pub const PageTableEntry = packed struct(u64) {
    valid: bool = false, // is a valid entry.
    not_block: bool = false, // yup, is a block descriptor if not set.
    mair_index: u3 = 0,
    _unused5: u1 = 0,
    user_access: bool = false, // 0 for only kernel access.
    read_only: bool = false, // 0 for read-write.
    _unused8: u2 = 0,
    access: bool = false, // a page fault is generated if not set.
    _unused11: u1 = 0,
    phys_addr: u36 = 0,
    _unused48: u5 = 0,
    privileged_non_executable: bool = false, // non-executable page frame for EL1 if set.
    unprivileged_non_executable: bool = false, // non-executable page frame for EL0 if set.
    _unused55: u9 = 0,
};

pub const PageTable = [512]PageTableEntry;
