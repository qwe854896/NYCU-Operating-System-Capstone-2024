const std = @import("std");
const types = @import("types.zig");
const main = @import("../main.zig");
const thread = @import("../thread.zig");
const registers = @import("../arch/aarch64/registers.zig");
const context = @import("../arch/aarch64/context.zig");
const Vfs = @import("../fs/Vfs.zig");
const log = std.log.scoped(.map);

const PageTableMemoryPool = std.heap.MemoryPoolAligned(PageTable, 4096);
const PageTableEntry = types.PageTableEntry;
pub const PageTable = types.PageTable;
pub const Granularity = enum { PTE, PMD, PUD, PGD };
const getSingletonPageAllocator = main.getSingletonPageAllocator;

const GranularityInfo = struct {
    shift: u6,
    block_size: usize,
    mask: u64,

    pub fn init(g: Granularity) @This() {
        return switch (g) {
            .PTE => .{ .shift = 12, .block_size = 1 << 12, .mask = 0xFFF },
            .PMD => .{ .shift = 21, .block_size = 1 << 21, .mask = 0x1FFFFF },
            .PUD => .{ .shift = 30, .block_size = 1 << 30, .mask = 0x3FFFFFFF },
            .PGD => .{ .shift = 39, .block_size = 1 << 39, .mask = 0x7FFFFFFFFF },
        };
    }
};

// Cached page table allocation
var page_table_cache: PageTableMemoryPool = undefined;

pub fn initPageTableCache(allocator: std.mem.Allocator) void {
    page_table_cache = PageTableMemoryPool.init(allocator);
}

fn createPageTable() Error!*PageTable {
    const new_table = try page_table_cache.create();
    new_table.* = @splat(.{});
    return new_table;
}

fn destroyPageTable(table: *PageTable) void {
    page_table_cache.destroy(@alignCast(table));
}

// Global reference count storage
const RefCountHashMap = std.AutoHashMap(usize, struct { count: usize, size: usize });
var ref_counts: RefCountHashMap = undefined;

pub fn initPageFrameRefCounts(allocator: std.mem.Allocator) void {
    ref_counts = RefCountHashMap.init(allocator);
}

fn refCountGet(slice: []const u8) usize {
    const entry = ref_counts.get(@intFromPtr(slice.ptr)) orelse return 0;
    return entry.count;
}

fn refCountAdd(slice: []const u8) void {
    const entry = ref_counts.getOrPut(@intFromPtr(slice.ptr)) catch {
        @panic("Cannot allocate new page frame!");
    };
    if (entry.found_existing) {
        entry.value_ptr.count += 1;
    } else {
        entry.value_ptr.* = .{ .count = 1, .size = slice.len };
    }
}

fn refCountRelease(slice: []const u8) void {
    const entry = ref_counts.getEntry(@intFromPtr(slice.ptr)) orelse return;
    entry.value_ptr.count -= 1;

    if (entry.value_ptr.count == 0) {
        getSingletonPageAllocator().free(slice);
        _ = ref_counts.remove(@intFromPtr(slice.ptr));
    }
}

pub const Error = error{
    NoEntry,
} || std.mem.Allocator.Error;

fn getLevelIndex(va: u64, comptime shift: u6) u9 {
    return @truncate((va >> shift) & 0x1FF);
}

pub const WalkResult = struct {
    entries: [4]?*PageTableEntry,
    depth: u2,
};

fn walk(
    page_table: *PageTable,
    va: u64,
    alloc: bool,
    comptime granularity: Granularity,
) Error!WalkResult {
    const current_info = comptime GranularityInfo.init(granularity);
    var current = page_table;
    var result = WalkResult{ .entries = undefined, .depth = 0 };

    outer: {
        inline for (.{ .PGD, .PUD, .PMD }) |g| {
            const info = comptime GranularityInfo.init(g);
            if (info.shift <= current_info.shift) {
                break :outer;
            }
            const index = getLevelIndex(va, info.shift);
            const entry = &current[index];

            if (!entry.allocated) {
                if (!alloc) {
                    return Error.NoEntry;
                }
                const new_table = try createPageTable();
                entry.* = .{
                    .valid = true,
                    .allocated = true,
                    .not_block = true,
                    .phys_addr = @truncate(@intFromPtr(new_table.ptr) >> 12),
                };
            }

            current = @ptrFromInt(@as(u64, entry.phys_addr << 12) | 0xffff000000000000);
            result.entries[result.depth] = entry;

            if (!entry.not_block) {
                return result;
            }

            result.depth += 1;
        }
    }

    const entry = &current[getLevelIndex(va, current_info.shift)];
    if (!entry.allocated) {
        if (!alloc) {
            return Error.NoEntry;
        }
    }
    result.entries[result.depth] = entry;
    return result;
}

pub fn mapPages(
    page_table: *PageTable,
    va: u64,
    size: usize,
    pa: u64,
    flags: struct { valid: bool, user: bool, read_only: bool, el0_exec: bool, el1_exec: bool, mair_index: u3, policy: types.PageFaultPolicy },
    comptime granularity: Granularity,
) !u64 {
    const info = comptime GranularityInfo.init(granularity);

    if ((va | pa | size) & (info.block_size - 1) != 0)
        return error.Unaligned;

    var va_hint = va;

    while (true) {
        var current_va = va_hint;
        var current_pa = pa;

        while (current_va < va_hint + size) {
            const result = try walk(page_table, current_va, true, granularity);
            const entry = result.entries[result.depth].?;

            if (entry.allocated) {
                break;
            }

            current_va += info.block_size;
            current_pa += info.block_size;
        }

        if (current_va != va_hint + size) {
            va_hint = va_hint + size;
            continue;
        }
        break;
    }

    var current_va = va_hint;
    var current_pa = pa;

    while (current_va < va_hint + size) {
        const result = try walk(page_table, current_va, true, granularity);
        const entry = result.entries[result.depth].?;

        entry.* = .{
            .valid = false,
            .allocated = true,
            .not_block = (granularity == .PTE),
            .mair_index = flags.mair_index,
            .user_access = flags.user,
            .read_only = flags.read_only,
            .original_read_only = flags.read_only,
            .access = true,
            .phys_addr = @truncate(current_pa >> 12),
            .privileged_non_executable = !flags.el1_exec,
            .unprivileged_non_executable = !flags.el0_exec,
            .policy = flags.policy,
        };

        if (flags.valid) {
            handleTranslationFault(entry, info);
        }

        current_va += info.block_size;
        current_pa += info.block_size;
    }

    return va_hint;
}

fn virtToEntry(
    page_table: *PageTable,
    va: u64,
) Error!WalkResult {
    const result = try walk(page_table, va, false, .PTE);
    return result;
}

fn calculatePhysicalAddress(
    entry: *PageTableEntry,
    va: u64,
    comptime granularity: Granularity,
) u64 {
    const info = comptime GranularityInfo.init(granularity);
    const phys_base = @as(u64, entry.phys_addr) << 12;
    return 0xffff000000000000 | phys_base | (va & info.mask);
}

pub fn virtToPhys(
    page_table: *PageTable,
    va: u64,
) Error!u64 {
    const result = try virtToEntry(page_table, va);
    const entry = result.entries[result.depth].?;
    switch (result.depth) {
        else => unreachable,
        1 => return calculatePhysicalAddress(entry, va, .PUD),
        2 => return calculatePhysicalAddress(entry, va, .PMD),
        3 => return calculatePhysicalAddress(entry, va, .PTE),
    }
}

fn handleSegmentationFault(fault_address: u64) noreturn {
    log.err("[Segmentation fault]: 0x{X} -> Kill Process", .{fault_address});
    thread.end();
}

fn handleTranslationFault(entry: *PageTableEntry, info: GranularityInfo) void {
    entry.valid = true;
    switch (entry.policy) {
        .anonymous => {
            const new_page_frame = getSingletonPageAllocator().alloc(u8, info.block_size) catch {
                @panic("Cannot allocate new page frame for program!");
            };
            entry.phys_addr = @truncate(@intFromPtr(new_page_frame.ptr) >> 12);
            refCountAdd(new_page_frame);
            context.invalidateCache();
        },
        .program => {
            const self = thread.threadFromCurrent();

            const offset = entry.phys_addr << 12;
            _ = Vfs.lseek64(&self.program.?, offset, .seek_set) catch {
                @panic("Vfs system error!");
            };

            const new_program = getSingletonPageAllocator().alloc(u8, info.block_size) catch {
                @panic("Cannot allocate new page frame for program!");
            };
            _ = Vfs.read(&self.program.?, new_program);

            entry.phys_addr = @truncate(@intFromPtr(new_program.ptr) >> 12);

            refCountAdd(new_program);
            context.invalidateCache();
        },
        .direct => {},
    }
}

fn handleCopyOnWriteFault(entry: *PageTableEntry, info: GranularityInfo, fault_address: u64) void {
    const self = thread.threadFromCurrent();
    _ = self;
    if (!entry.original_read_only) {
        const page_frame = @as([*]u8, @ptrFromInt(@as(u64, entry.phys_addr) << 12 | 0xffff000000000000))[0..info.block_size];

        if (refCountGet(page_frame) > 1) {
            const new_page_frame = getSingletonPageAllocator().alloc(u8, info.block_size) catch {
                @panic("Cannot allocate new page frame for program!");
            };
            @memcpy(new_page_frame, page_frame);

            entry.phys_addr = @truncate(@intFromPtr(new_page_frame.ptr) >> 12);

            refCountAdd(new_page_frame);
            refCountRelease(page_frame);
        }

        entry.read_only = entry.original_read_only;
        context.invalidateCache();
    } else {
        handleSegmentationFault(fault_address);
    }
}

pub fn pageHandler() void {
    const self = thread.threadFromCurrent();
    const fault_address = registers.getFarEl1();

    const result = virtToEntry(self.pgd.?, fault_address) catch {
        handleSegmentationFault(fault_address);
    };
    const entry = result.entries[result.depth].?;
    const info = GranularityInfo.init(switch (result.depth) {
        else => unreachable,
        1 => .PUD,
        2 => .PMD,
        3 => .PTE,
    });

    // Data Fault Status Code.
    // 0b000111: Translation fault, level 3.
    // 0b001111: Permission fault, level 3.
    const status_code = registers.getEsrEl1() & 0x3f;
    const fault_type = status_code >> 2 & 0xf;

    switch (fault_type) {
        0b0001 => handleTranslationFault(entry, info),
        0b0011 => handleCopyOnWriteFault(entry, info, fault_address),
        else => {
            @panic("Unhandled page fault!");
        },
    }
}

pub fn deepCopy(page_table: *PageTable, comptime level: u2) PageTable {
    var new_page_table: PageTable = @splat(.{});
    for (page_table, 0..) |*entry, i| {
        if (!entry.allocated) continue;

        new_page_table[i] = entry.*;
        if (entry.not_block and level > 0) {
            const new_next_table = createPageTable() catch {
                @panic("Cannot allocate new page table!");
            };
            const next_table: *PageTable = @ptrFromInt(@as(u64, entry.phys_addr << 12) | 0xffff000000000000);
            new_next_table.* = deepCopy(next_table, level - 1);
            new_page_table[i].phys_addr = @truncate(@intFromPtr(new_next_table.ptr) >> 12);
        } else if (entry.valid and entry.policy != .direct) {
            new_page_table[i].read_only = true;
            entry.read_only = true;
            const page_frame: [*]u8 = @ptrFromInt(@as(u64, entry.phys_addr << 12) | 0xffff000000000000);
            refCountAdd(page_frame[0..1]); // len is not important
        }
    }
    return new_page_table;
}

pub fn deepDestroy(page_table: *PageTable, comptime level: u2) void {
    for (page_table) |*entry| {
        if (!entry.allocated) continue;

        if (entry.not_block and level > 0) {
            const next_table: *PageTable = @ptrFromInt(@as(u64, entry.phys_addr << 12) | 0xffff000000000000);
            deepDestroy(next_table, level - 1);
            destroyPageTable(next_table);
        } else if (entry.valid and entry.policy != .direct) {
            const page_frame: [*]u8 = @ptrFromInt(@as(u64, entry.phys_addr << 12) | 0xffff000000000000);
            refCountRelease(page_frame[0..1]); // len is not important
        }
    }
}
