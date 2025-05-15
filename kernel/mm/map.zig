const std = @import("std");
const types = @import("types.zig");
const main = @import("../main.zig");

const PageTableEntry = types.PageTableEntry;
pub const PageTable = types.PageTable;
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

fn walk(page_table: *PageTable, va: u64, alloc: bool) Error!*PageTableEntry {
    var current = page_table;
    inline for (.{ PGD_SHIFT, PUD_SHIFT, PMD_SHIFT }) |shift| {
        do: {
            const index = getLevelIndex(va, shift);
            const entry = &current[index];

            if (entry.valid) {
                if (entry.not_block) { // Table descriptor
                    current = @ptrFromInt(entry.phys_addr << 12);
                    break :do;
                }
                return Error.BlockEntryExists;
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

    return &current[getLevelIndex(va, PTE_SHIFT)];
}

pub fn mapPages(
    page_table: *PageTable,
    va: u64,
    size: usize,
    pa: u64,
    flags: struct { user: bool, read_only: bool, el0_exec: bool, el1_exec: bool, mair_index: u3 },
) !void {
    var current_va = va;
    var current_pa = pa;

    while (current_va < va + size) {
        const pte = try walk(page_table, current_va, true);

        pte.* = .{
            .valid = true,
            .not_block = true, // Page descriptor
            .mair_index = flags.mair_index,
            .user_access = flags.user,
            .read_only = flags.read_only,
            .access = true,
            .phys_addr = @truncate(current_pa >> 12),
            .privileged_non_executable = !flags.el1_exec,
            .unprivileged_non_executable = !flags.el0_exec,
        };

        current_va += 4096;
        current_pa += 4096;
    }
}
