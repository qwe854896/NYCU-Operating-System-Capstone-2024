const page_allocator = @import("heap/page_allocator.zig");

pub const PageAllocator = page_allocator.PageAllocator;
pub const DynamicAllocator = @import("heap/dynamic_allocator.zig").DynamicAllocator;

pub const log2_page_size = page_allocator.log2_page_size;
