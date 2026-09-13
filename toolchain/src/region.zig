//! A region: one reservation of address space, allocated by bumping `top`. `mo run` gives
//! the vm two (vm.zig): values live in one, and a compaction carries what it keeps
//! through the other. Under processes each process's vm has a values region of its own,
//! and every vm shares the one scratch region (turns.zig). A mark is an address, so "allocated since the mark" is a
//! comparison, and setting `top` back to a mark frees everything past it at once. Pages
//! are committed as they are touched, and nothing is freed one allocation at a time.
const std = @import("std");

pub const Region = struct {
    base: usize,
    end: usize,
    top: usize,

    /// As much address space as the system gives, from 64 GiB down to 256 MiB.
    pub fn reserve() error{OutOfMemory}!Region {
        return reserveUpTo(64 << 30);
    }

    /// As much address space as the system gives, from `most` down to 256 MiB.
    pub fn reserveUpTo(most: usize) error{OutOfMemory}!Region {
        var size: usize = most;
        while (size >= 256 << 20) : (size /= 2) {
            const mem = std.posix.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0) catch continue;
            const base = @intFromPtr(mem.ptr);
            return .{ .base = base, .end = base + mem.len, .top = base };
        }
        return error.OutOfMemory;
    }

    pub fn release(r: *Region) void {
        const mem: [*]align(std.heap.page_size_min) u8 = @ptrFromInt(r.base);
        std.posix.munmap(mem[0 .. r.end - r.base]);
    }

    pub fn contains(r: *const Region, addr: usize) bool {
        return addr >= r.base and addr < r.end;
    }

    pub fn allocator(r: *Region) std.mem.Allocator {
        return .{ .ptr = r, .vtable = &vtable };
    }

    const vtable: std.mem.Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const r: *Region = @ptrCast(@alignCast(ctx));
        const start = alignment.forward(r.top);
        if (start + len > r.end) return null;
        r.top = start + len;
        return @ptrFromInt(start);
    }

    /// The last allocation grows or shrinks in place; any other only shrinks, keeping its bytes.
    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = alignment;
        _ = ret_addr;
        const r: *Region = @ptrCast(@alignCast(ctx));
        const start = @intFromPtr(memory.ptr);
        if (start + memory.len != r.top) return new_len <= memory.len;
        if (start + new_len > r.end) return false;
        r.top = start + new_len;
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        return if (resize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
    }

    /// A mark frees; a single free does not, so no mark is ever left past `top`.
    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = ret_addr;
    }
};

test "a region bumps, grows its last allocation in place, and frees everything past a mark" {
    var r = try Region.reserve();
    defer r.release();
    const a = r.allocator();
    const first = try a.alloc(u64, 4);
    const mark = r.top;
    var grown = try a.alloc(u8, 3);
    try std.testing.expect(a.resize(grown, 100));
    grown = grown.ptr[0..100];
    try std.testing.expectEqual(mark + 100, r.top);
    r.top = mark;
    const again = try a.alloc(u8, 1);
    try std.testing.expectEqual(@intFromPtr(grown.ptr), @intFromPtr(again.ptr));
    try std.testing.expect(r.contains(@intFromPtr(first.ptr)));
}
