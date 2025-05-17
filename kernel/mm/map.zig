const std = @import("std");
const types = @import("types.zig");
const main = @import("../main.zig");
const thread = @import("../thread.zig");
const registers = @import("../arch/aarch64/registers.zig");
const initrd = @import("../fs/initrd.zig");
const context = @import("../arch/aarch64/context.zig");
const log = std.log.scoped(.map);

const PageTableMemoryPool = std.heap.MemoryPoolAligned(PageTable, 4096);
const PageTableEntry = types.PageTableEntry;
pub const PageTable = types.PageTable;
pub const Granularity = enum { PTE, PMD, PUD, PGD };
const getSingletonPageAllocator = main.getSingletonPageAllocator;

// Cached page table allocation
var page_table_cache: PageTableMemoryPool = undefined;

pub fn initPageTableCache(allocator: std.mem.Allocator) void {
    page_table_cache = PageTableMemoryPool.init(allocator);
}

fn allocateTable() Error!*PageTable {
    return page_table_cache.create();
}

const PGD_SHIFT = 39;
const PUD_SHIFT = 30;
const PMD_SHIFT = 21;
const PTE_SHIFT = 12;

pub const Error = error{
    NoEntry,
} || std.mem.Allocator.Error;

fn getLevelIndex(va: u64, comptime shift: u6) u9 {
    return @truncate((va >> shift) & 0x1FF);
}

pub const WalkEntries = struct {
    pgd: ?*PageTableEntry = null,
    pud: ?*PageTableEntry = null,
    pmd: ?*PageTableEntry = null,
    pte: ?*PageTableEntry = null,
};

fn walk(
    page_table: *PageTable,
    va: u64,
    alloc: bool,
    comptime granularity: Granularity,
) Error!WalkEntries {
    var current = page_table;
    var entries = WalkEntries{};

    // Process upper levels
    inline for (switch (granularity) {
        else => unreachable,
        .PUD => &.{PGD_SHIFT},
        .PMD => &.{ PGD_SHIFT, PUD_SHIFT },
        .PTE => &.{ PGD_SHIFT, PUD_SHIFT, PMD_SHIFT },
    }) |shift| {
        const index = getLevelIndex(va, shift);
        const entry = &current[index];

        if (entry.valid) {
            if (entry.not_block)
                current = @ptrFromInt(@as(u64, entry.phys_addr << 12) | 0xffff000000000000);
        } else if (alloc) {
            const new_table = try allocateTable();
            new_table.* = @splat(@bitCast(@as(u64, 0)));
            entry.* = .{
                .valid = true,
                .not_block = true,
                .phys_addr = @truncate(@intFromPtr(new_table.ptr) >> 12),
            };
            current = @ptrCast(new_table.ptr);
        } else {
            return entries;
        }

        // Store intermediate entries
        switch (shift) {
            PGD_SHIFT => entries.pgd = entry,
            PUD_SHIFT => entries.pud = entry,
            PMD_SHIFT => entries.pmd = entry,
            else => unreachable,
        }

        if (!entry.not_block) return entries;
    }

    switch (granularity) {
        else => unreachable,
        .PUD => entries.pud = &current[getLevelIndex(va, PUD_SHIFT)],
        .PMD => entries.pmd = &current[getLevelIndex(va, PMD_SHIFT)],
        .PTE => entries.pte = &current[getLevelIndex(va, PTE_SHIFT)],
    }

    return entries;
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
        else => unreachable,
    };

    if ((va | pa | size) & (block_size - 1) != 0)
        return error.Unaligned;

    var current_va = va;
    var current_pa = pa;

    while (current_va < va + size) {
        const entries = try walk(page_table, current_va, true, granularity);
        const entry = switch (granularity) {
            else => unreachable,
            .PUD => entries.pud.?,
            .PMD => entries.pmd.?,
            .PTE => entries.pte.?,
        };

        // if (entry.valid)
        //     return error.AlreadyMapped;

        entry.* = .{
            .valid = true,
            .not_block = (granularity == .PTE),
            .mair_index = flags.mair_index,
            .user_access = flags.user,
            .read_only = flags.read_only,
            .original_read_only = flags.read_only,
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
) Error!WalkEntries {
    const entries = try walk(page_table, va, false, .PTE);
    return entries;
}

fn calculatePhysicalAddress(
    entry: *PageTableEntry,
    va: u64,
    comptime granularity: Granularity,
) u64 {
    const mask = switch (granularity) {
        .PTE => 0x00000FFF,
        .PMD => 0x001FFFFF,
        .PUD => 0x3FFFFFFF,
        else => unreachable,
    };
    const phys_base = @as(u64, entry.phys_addr) << 12;
    return 0xffff000000000000 | phys_base | (va & mask);
}

pub fn virtToPhys(
    page_table: *PageTable,
    va: u64,
) Error!u64 {
    const entries = try virtToEntry(page_table, va);
    return if (entries.pte) |pte|
        calculatePhysicalAddress(pte, va, .PTE)
    else if (entries.pmd) |pmd|
        calculatePhysicalAddress(pmd, va, .PMD)
    else if (entries.pud) |pud|
        calculatePhysicalAddress(pud, va, .PUD)
    else
        error.NoEntry;
}

pub fn pageHandler() void {
    const self = thread.threadFromCurrent();
    const fault_address = registers.getFarEl1();

    const entries = virtToEntry(self.pgd, fault_address) catch {
        @panic("Cannot get page table entry!");
    };
    const entry = if (entries.pte) |pte|
        pte
    else if (entries.pmd) |pmd|
        pmd
    else if (entries.pud) |pud|
        pud
    else {
        log.err("[Segmentation fault]: 0x{X} -> Kill Process", .{fault_address});
        thread.end();
    };
    const block_size: usize = if (entries.pte != null)
        4096
    else if (entries.pmd != null)
        2 * 1024 * 1024
    else if (entries.pud != null)
        1 * 1024 * 1024 * 1024
    else
        unreachable;

    // Data Fault Status Code.
    // 0b001011: Access flag fault, level 3.
    // 0b001111: Permission fault, level 3.
    const status_code = registers.getEsrEl1() & 0x3f;
    const fault_type = status_code >> 2 & 0xf;

    switch (fault_type) {
        0b0010 => {
            log.err("[Translation fault]: 0x{X}", .{fault_address});
            entry.access = true;
            switch (entry.policy) {
                .anonymous => {
                    const new_page_frame = getSingletonPageAllocator().alloc(u8, block_size) catch {
                        @panic("Cannot allocate new page frame for program!");
                    };
                    entry.phys_addr = @truncate(@intFromPtr(new_page_frame.ptr) >> 12);

                    context.invalidateCache();
                },
                .program => {
                    const program = initrd.getFileContent(self.program_name.?).?;
                    const new_program = getSingletonPageAllocator().alloc(u8, block_size) catch {
                        @panic("Cannot allocate new page frame for program!");
                    };
                    const offset = entry.phys_addr << 12;
                    const copy_len = @min(offset + block_size, program.len) - offset;
                    @memcpy(new_program[0..copy_len], program[offset .. offset + copy_len]);
                    entry.phys_addr = @truncate(@intFromPtr(new_program.ptr) >> 12);

                    context.invalidateCache();
                },
                .direct => {},
            }
        },
        0b0011 => {
            if (!entry.original_read_only) {
                log.err("[Copy-on-write fault]: 0x{X}", .{fault_address});

                const page_frame = @as([*]u8, @ptrFromInt(@as(u64, entry.phys_addr) << 12 | 0xffff000000000000))[0..block_size];
                const new_page_frame = getSingletonPageAllocator().alloc(u8, block_size) catch {
                    @panic("Cannot allocate new page frame for program!");
                };
                @memcpy(new_page_frame, page_frame);

                entry.phys_addr = @truncate(@intFromPtr(new_page_frame.ptr) >> 12);
                entry.read_only = entry.original_read_only;

                context.invalidateCache();
            } else {
                log.err("[Segmentation fault]: 0x{X} -> Kill Process", .{fault_address});
                thread.end();
            }
        },
        else => {
            // @panic("Unhandled page fault!");
        },
    }
}

pub fn deepCopy(page_table: *PageTable, comptime granularity: Granularity) PageTable {
    var new_page_table: PageTable = undefined;
    for (page_table, 0..) |*entry, i| {
        if (entry.valid) {
            new_page_table[i] = entry.*;
            if (entry.not_block and granularity != .PTE) {
                const new_next_table = allocateTable() catch {
                    @panic("Cannot allocate new page table!");
                };
                const next_table: *PageTable = @ptrFromInt(@as(u64, entry.phys_addr << 12) | 0xffff000000000000);
                switch (granularity) {
                    .PGD => {
                        new_next_table.* = deepCopy(next_table, .PUD);
                    },
                    .PUD => {
                        new_next_table.* = deepCopy(next_table, .PMD);
                    },
                    .PMD => {
                        new_next_table.* = deepCopy(next_table, .PTE);
                    },
                    .PTE => unreachable,
                }
                new_page_table[i].phys_addr = @truncate(@intFromPtr(new_next_table.ptr) >> 12);
            } else {
                if (entry.policy != .direct) {
                    new_page_table[i].read_only = true;
                    entry.read_only = true;
                }
            }
        }
    }
    return new_page_table;
}
