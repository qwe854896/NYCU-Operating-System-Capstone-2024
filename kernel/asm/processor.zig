// https://elixir.bootlin.com/linux/v6.14.3/source/arch/arm64/include/asm/processor.h#L147

pub const CPUContext = packed struct {
    x19: usize = 0,
    x20: usize = 0,
    x21: usize = 0,
    x22: usize = 0,
    x23: usize = 0,
    x24: usize = 0,
    x25: usize = 0,
    x26: usize = 0,
    x27: usize = 0,
    x28: usize = 0,
    fp: usize = 0,
    pc: usize = 0,
    sp: usize = 0,
};

pub const ThreadContext = packed struct {
    cpu_context: CPUContext,
};
