const std = @import("std");
const types = @import("types.zig");
const main = @import("../main.zig");

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

            const new_table = try getSingletonPageAllocator().alignedAlloc(u8, 4096, 4096);
            @memset(new_table, 0);

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
    flags: struct { user: bool, read_only: bool, el0_exec: bool, el1_exec: bool, mair_index: u3 },
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
            .access = true,
            .phys_addr = @truncate(current_pa >> 12),
            .privileged_non_executable = !flags.el1_exec,
            .unprivileged_non_executable = !flags.el0_exec,
        };

        current_va += block_size;
        current_pa += block_size;
    }
}

pub fn virtToPhys(
    page_table: *PageTable,
    va: u64,
) Error!u64 {
    // Try different granularities from largest to smallest
    const entries = inline for (.{ Granularity.PUD, Granularity.PMD, Granularity.PTE }) |granularity| {
        do: {
            const entry = walk(page_table, va, false, granularity) catch {
                break :do;
            };

            if (entry.valid) {
                if (!entry.not_block or granularity == .PTE) {
                    const block_size: usize = switch (granularity) {
                        .PTE => 4096,
                        .PMD => 2 * 1024 * 1024,
                        .PUD => 1 * 1024 * 1024 * 1024,
                    };
                    const mask = block_size - 1;

                    const phys_base = @as(u64, entry.phys_addr) << 12;

                    return 0xffff000000000000 | phys_base | (va & mask);
                }
            }
        }
    } else return Error.NoEntry;

    return entries;
}
