const std = @import("std");
const page_allocator = @import("page_allocator.zig");
const log = std.log.scoped(.chunk);
const log2_int = std.math.log2_int;
const mem = std.mem;
const assert = std.debug.assert;
const PageAllocator = page_allocator.PageAllocator;

const slab_len: usize = page_allocator.page_size;
const min_class = log2_int(usize, @sizeOf(usize));
const size_class_count = log2_int(usize, slab_len) - min_class;

const Config = struct {
    verbose_log: bool = false,
};

const magic: usize = 0x1ab4de30deadbeaf;
const Metadata = struct {
    magic: usize,
    class: usize,
};

pub fn DynamicAllocator(comptime config: Config) type {
    return struct {
        const Self = @This();
        const ConfiguredPageAllocator = PageAllocator(.{ .verbose_log = config.verbose_log });

        page_allocator: mem.Allocator,
        next_addrs: [size_class_count]usize = @splat(0),
        frees: [size_class_count]usize = @splat(0),

        pub fn init(cpa: *ConfiguredPageAllocator) Self {
            return Self{
                .page_allocator = cpa.allocator(),
            };
        }

        pub fn allocator(self: *Self) mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .free = free,
                    .resize = resize,
                    .remap = remap,
                },
            };
        }

        fn alloc(context: *anyopaque, n: usize, alignment: mem.Alignment, ra: usize) ?[*]u8 {
            assert(n > 0);
            const self: *Self = @ptrCast(@alignCast(context));

            const class = sizeClassIndex(n, alignment);
            if (class >= size_class_count) {
                return self.page_allocator.rawAlloc(n, alignment, ra);
            }

            const slot_size = slotSize(class);
            assert(slab_len % slot_size == 0);

            const top_free_ptr = self.frees[class];
            if (top_free_ptr != 0) {
                const node: *usize = @ptrFromInt(top_free_ptr);
                self.frees[class] = node.*;

                if (config.verbose_log) {
                    log.info("Allocate 0x{X} at chunk size {d}.", .{ top_free_ptr, slot_size });
                }

                return @ptrFromInt(top_free_ptr);
            }

            const next_addr = self.next_addrs[class];
            if ((next_addr % slab_len) != 0) {
                self.next_addrs[class] = next_addr + slot_size;

                if (config.verbose_log) {
                    log.info("Allocate 0x{X} at chunk size {d}.", .{ next_addr, slot_size });
                }

                return @ptrFromInt(next_addr);
            }

            const slab = self.page_allocator.rawAlloc(slab_len, .fromByteUnits(slab_len), ra) orelse return null;
            self.next_addrs[class] = @intFromPtr(slab) + @max(slot_size, @sizeOf(Metadata));
            defer self.next_addrs[class] += slot_size;

            const metadata: *Metadata = @ptrFromInt(@intFromPtr(slab));
            metadata.* = Metadata{
                .magic = magic,
                .class = class,
            };
            if (config.verbose_log) {
                log.info("Allocate 0x{X} at chunk size {d}.", .{ self.next_addrs[class], slot_size });
            }

            return @ptrFromInt(self.next_addrs[class]);
        }

        fn free(context: *anyopaque, memory: []u8, alignment: mem.Alignment, return_address: usize) void {
            _ = alignment;
            _ = return_address;

            const self: *Self = @ptrCast(@alignCast(context));

            const metadata: *Metadata = @ptrFromInt(mem.alignBackward(usize, @intFromPtr(memory.ptr), slab_len));

            if (metadata.*.magic != 0x1ab4de30deadbeaf) {
                return self.page_allocator.free(memory);
            }

            const class = metadata.*.class;

            if (config.verbose_log) {
                log.info("Free 0x{X} at chunk size {d}.", .{ @intFromPtr(memory.ptr), slotSize(class) });
            }

            const node: *usize = @alignCast(@ptrCast(memory.ptr));

            node.* = self.frees[class];
            self.frees[class] = @intFromPtr(node);
        }

        fn resize(context: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, return_address: usize) bool {
            _ = return_address;
            const self: *Self = @ptrCast(@alignCast(context));
            const metadata: *Metadata = @ptrFromInt(mem.alignBackward(usize, @intFromPtr(memory.ptr), slab_len));
            const new_class = sizeClassIndex(new_len, alignment);
            if (metadata.*.magic != magic) {
                if (new_class < size_class_count) return false;
                _ = self.page_allocator.realloc(memory, new_len) catch {
                    return false;
                };
                return true;
            }
            const class = metadata.*.class;
            return new_class == class;
        }

        fn remap(context: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
            _ = return_address;
            const self: *Self = @ptrCast(@alignCast(context));
            const metadata: *Metadata = @ptrFromInt(mem.alignBackward(usize, @intFromPtr(memory.ptr), slab_len));
            const new_class = sizeClassIndex(new_len, alignment);
            if (metadata.*.magic != magic) {
                if (new_class < size_class_count) return null;
                const ret = self.page_allocator.realloc(memory, new_len) catch {
                    return null;
                };
                return @ptrCast(@constCast(&ret));
            }
            const class = metadata.*.class;
            return if (new_class == class) memory.ptr else null;
        }

        fn sizeClassIndex(len: usize, alignment: mem.Alignment) usize {
            return @max(@bitSizeOf(usize) - @clz(len - 1), @intFromEnum(alignment), min_class) - min_class;
        }

        fn slotSize(class: usize) usize {
            return @as(usize, 1) << @intCast(class + min_class);
        }
    };
}
