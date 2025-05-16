const std = @import("std");
const types = @import("types.zig");
const main = @import("../main.zig");
const thread = @import("../thread.zig");
const registers = @import("../arch/aarch64/registers.zig");
const initrd = @import("../fs/initrd.zig");
const log = std.log.scoped(.map);

const PageTableEntry = types.PageTableEntry;
pub const PageTable = types.PageTable;
pub const Granularity = enum { PTE, PMD, PUD };
const getSingletonPageAllocator = main.getSingletonPageAllocator;

const PGD_SHIFT = 39;
const PUD_SHIFT = 30;
const PMD_SHIFT = 21;
const PTE_SHIFT = 12;

pub const Error = error{
    BlockEntryExists,
    NoEntry,
} || std.mem.Allocator.Error;

fn getLevelIndex(va: u64, comptime shift: u6) u9 {
    return @truncate((va >> shift) & 0x1FF);
}

fn walk(
    page_table: *PageTable,
    va: u64,
    alloc: bool,
    comptime granularity: Granularity,
) Error!*PageTableEntry {
    var current = page_table;

    // Process upper levels based on granularity
    inline for (switch (granularity) {
        .PUD => &.{PGD_SHIFT},
        .PMD => &.{ PGD_SHIFT, PUD_SHIFT },
        .PTE => &.{ PGD_SHIFT, PUD_SHIFT, PMD_SHIFT },
    }) |shift| {
        do: {
            const index = getLevelIndex(va, shift);
            const entry = &current[index];

            if (entry.valid) {
                if (!entry.not_block) return Error.BlockEntryExists;
                current = @ptrFromInt(@as(u64, entry.phys_addr << 12) | 0xffff000000000000);
                break :do;
            }

            if (!alloc) return Error.NoEntry;

            const new_table = try getSingletonPageAllocator().create(PageTable);
            new_table.* = @splat(@bitCast(@as(u64, 0)));

            entry.* = .{
                .valid = true,
                .not_block = true,
                .phys_addr = @truncate(@intFromPtr(new_table.ptr) >> 12),
            };

            current = @ptrCast(new_table.ptr);
        }
    }

    // Handle final level
    return &current[
        getLevelIndex(va, switch (granularity) {
            .PUD => PUD_SHIFT,
            .PMD => PMD_SHIFT,
            .PTE => PTE_SHIFT,
        })
    ];
}

pub fn mapPages(
    page_table: *PageTable,
    va: u64,
    size: usize,
    pa: u64,
    flags: struct { access: bool, user: bool, read_only: bool, el0_exec: bool, el1_exec: bool, mair_index: u3, policy: types.PageFaultPolicy },
    comptime granularity: Granularity,
) !void {
    const block_size: usize = switch (granularity) {
        .PTE => 4096,
        .PMD => 2 * 1024 * 1024,
        .PUD => 1 * 1024 * 1024 * 1024,
    };

    if ((va | pa | size) & (block_size - 1) != 0)
        return error.Unaligned;

    var current_va = va;
    var current_pa = pa;

    while (current_va < va + size) {
        const entry = try walk(page_table, current_va, true, granularity);

        // if (entry.valid)
        //     return error.AlreadyMapped;

        entry.* = .{
            .valid = true,
            .not_block = (granularity == .PTE),
            .mair_index = flags.mair_index,
            .user_access = flags.user,
            .read_only = flags.read_only,
            .access = flags.access,
            .phys_addr = @truncate(current_pa >> 12),
            .privileged_non_executable = !flags.el1_exec,
            .unprivileged_non_executable = !flags.el0_exec,
            .policy = flags.policy,
        };

        current_va += block_size;
        current_pa += block_size;
    }
}

fn virtToEntry(
    page_table: *PageTable,
    va: u64,
) Error!struct { *PageTableEntry, Granularity } {
    // Try different granularities from largest to smallest
    const entries = inline for (.{ Granularity.PUD, Granularity.PMD, Granularity.PTE }) |granularity| {
        do: {
            const entry = walk(page_table, va, false, granularity) catch {
                break :do;
            };

            if (entry.valid) {
                if (!entry.not_block or granularity == .PTE) {
                    return .{ entry, granularity };
                }
            }
        }
    } else return Error.NoEntry;

    return entries;
}

pub fn virtToPhys(
    page_table: *PageTable,
    va: u64,
) Error!u64 {
    const entry = try virtToEntry(page_table, va);
    const block_size: usize = switch (entry.@"1") {
        .PTE => 4096,
        .PMD => 2 * 1024 * 1024,
        .PUD => 1 * 1024 * 1024 * 1024,
    };
    const mask = block_size - 1;
    const phys_base = @as(u64, entry.@"0".phys_addr) << 12;
    return 0xffff000000000000 | phys_base | (va & mask);
}

pub fn pageHandler() void {
    const self = thread.threadFromCurrent();
    const fault_address = registers.getFarEl1();
    const entry_with_granularity = virtToEntry(self.pgd, fault_address) catch {
        log.err("[Segmentation fault]: 0x{X} -> Kill Process", .{fault_address});
        thread.end();
    };
    log.err("[Translation fault]: 0x{X}", .{fault_address});

    const entry = entry_with_granularity.@"0";
    const block_size: usize = switch (entry_with_granularity.@"1") {
        .PTE => 4096,
        .PMD => 2 * 1024 * 1024,
        .PUD => 1 * 1024 * 1024 * 1024,
    };

    entry.access = true;
    switch (entry.policy) {
        .anonymous => {
            const new_page_frame = getSingletonPageAllocator().alloc(u8, block_size) catch {
                @panic("Cannot allocate new page frame for program!");
            };
            entry.phys_addr = @truncate(@intFromPtr(new_page_frame.ptr) >> 12);
        },
        .program => {
            const program = initrd.getFileContent(self.program_name.?).?;
            const new_program = getSingletonPageAllocator().alloc(u8, block_size) catch {
                @panic("Cannot allocate new page frame for program!");
            };
            const offset = entry.phys_addr << 12;
            @memcpy(new_program, program[offset .. offset + block_size]);
            entry.phys_addr = @truncate(@intFromPtr(new_program.ptr) >> 12);
        },
        .direct => {},
    }
}
