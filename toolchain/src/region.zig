//! A region: one reservation of address space, allocated by bumping `top`. `mo run` gives
//! the vm two (vm.zig): values live in one, and a compaction carries what it keeps
//! through the other. Under processes each process's vm has a values region of its own,
//! and every vm shares the one scratch region (turns.zig). A mark is an address, so "allocated since the mark" is a
//! comparison, and setting `top` back to a mark frees everything past it at once. Pages
//! are committed as they are touched, and nothing is freed one allocation at a time.
const std = @import("std");

/// Counts `MO_STATS=1` prints (main.zig, step 21): every allocation a region gave, and its bytes.
pub var allocations: u64 = 0;
pub var allocated_bytes: u64 = 0;
/// The bytes allocated past a full region, from its fallback (step 29b): memory no compaction frees.
pub var spilled_bytes: u64 = 0;

pub const Region = struct {
    base: usize,
    end: usize,
    top: usize,
    /// Past `top`, how far the region's pages may still be resident (step 28).
    high: usize = 0,
    /// Where an allocation that does not fit goes, counted in spilled_bytes, and lives until the run
    /// ends, as runtime/mo_rt.c's region_alloc does (step 29b); with none it fails.
    fallback: ?std.mem.Allocator = null,

    /// As much address space as the system gives, from 64 GiB down to 256 MiB.
    pub fn reserve() error{OutOfMemory}!Region {
        return reserveUpTo(64 << 30);
    }

    /// As much address space as the system gives, from `most` down to 256 MiB. Reserved, not
    /// committed where the system has the flag (step 29b): one that counts what a mapping may commit
    /// gave 64 GiB only as 8.
    pub fn reserveUpTo(most: usize) error{OutOfMemory}!Region {
        var flags: std.posix.MAP = .{ .TYPE = .PRIVATE, .ANONYMOUS = true };
        if (@hasField(std.posix.MAP, "NORESERVE")) flags.NORESERVE = true;
        var size: usize = most;
        while (size >= 256 << 20) : (size /= 2) {
            const mem = std.posix.mmap(null, size, .{ .READ = true, .WRITE = true }, flags, -1, 0) catch continue;
            const base = @intFromPtr(mem.ptr);
            return .{ .base = base, .end = base + mem.len, .top = base, .high = base };
        }
        return error.OutOfMemory;
    }

    pub fn release(r: *Region) void {
        const mem: [*]align(std.heap.page_size_min) u8 = @ptrFromInt(r.base);
        std.posix.munmap(mem[0 .. r.end - r.base]);
    }

    /// Everything allocated goes back to the system, and the region is empty again: its
    /// touched pages are mapped over with fresh ones, the reservation kept.
    pub fn decommit(r: *Region) void {
        r.releasePast(r.base);
        r.top = r.base;
        r.high = r.base;
    }

    /// The bytes a release keeps resident past the top.
    pub const release_keep: usize = 1 << 20;

    /// The pages touched past `keep` go back to the system and the reservation stays (step 28): a
    /// compaction lowers `top`, and the pages past it stayed resident, so a server's resident memory
    /// was the most its regions ever held. runtime/mo_rt.c's release_past is the same.
    pub fn releasePast(r: *Region, keep: usize) void {
        if (r.top > r.high) r.high = r.top;
        const page = std.heap.pageSize();
        const from = std.mem.alignForward(usize, keep, page);
        const to = @min(std.mem.alignForward(usize, r.high, page), r.end);
        if (to > from) {
            const at: [*]align(std.heap.page_size_min) u8 = @ptrFromInt(from);
            _ = std.posix.mmap(at, to - from, .{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .FIXED = true }, -1, 0) catch {};
        }
        r.high = @max(from, r.top);
    }

    /// The region's resident bytes: `mincore` over the pages it may have touched.
    pub fn resident(r: *const Region, gpa: std.mem.Allocator) u64 {
        const page = std.heap.pageSize();
        const pages = (@max(r.high, r.top) - r.base + page - 1) / page;
        if (pages == 0) return 0;
        const vec = gpa.alloc(u8, pages) catch return 0;
        defer gpa.free(vec);
        const at: [*]align(std.heap.page_size_min) u8 = @ptrFromInt(r.base);
        std.posix.mincore(at, pages * page, vec.ptr) catch return 0;
        var n: u64 = 0;
        for (vec) |b| n += b & 1;
        return n * page;
    }

    pub fn contains(r: *const Region, addr: usize) bool {
        return addr >= r.base and addr < r.end;
    }

    pub fn allocator(r: *Region) std.mem.Allocator {
        return .{ .ptr = r, .vtable = &vtable };
    }

    const vtable: std.mem.Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const r: *Region = @ptrCast(@alignCast(ctx));
        const start = alignment.forward(r.top);
        if (start + len > r.end) {
            const past = r.fallback orelse return null;
            spilled_bytes += len;
            return past.rawAlloc(len, alignment, ret_addr);
        }
        r.top = start + len;
        allocations += 1;
        allocated_bytes += len;
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

test "a full region fails, or allocates from its fallback and counts what it spilled" {
    var r = try Region.reserveUpTo(256 << 20);
    defer r.release();
    const a = r.allocator();
    _ = try a.alloc(u8, (256 << 20) - 16);
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 64));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    r.fallback = arena.allocator();
    const before = spilled_bytes;
    const past = try a.alloc(u8, 64);
    @memset(past, 7);
    try std.testing.expect(!r.contains(@intFromPtr(past.ptr)));
    try std.testing.expectEqual(before + 64, spilled_bytes);
}
