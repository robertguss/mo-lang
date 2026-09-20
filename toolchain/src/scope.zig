//! A stack of named entries with constant-time lookup by name.
//!
//! The lowerer (bytecode.zig) and the C emitter (emit_c.zig) both keep the names a
//! function binds in a stack that grows as bindings are made and shrinks back to a mark
//! when a block ends, with the newest binding of a name shadowing the older ones. Finding a
//! name by walking the stack backward costs one comparison per binding above it; a closure
//! resolving each of its captures through every enclosing function pays that again per
//! level. `Scope` keeps the stack as is (`items`) and beside it a map from each name to the
//! index of its newest binding, so a lookup is one hash, and each entry remembers the index
//! the name pointed at before it, so shrinking to a mark restores the map entry by entry.

const std = @import("std");

const none = std.math.maxInt(u32);

/// `T` is a struct with a `name: []const u8` field.
pub fn Scope(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The entries in binding order, oldest first.
        items: std.ArrayList(T) = .empty,
        /// For each entry, the index the name pointed at before it was bound, or `none`.
        shadowed: std.ArrayList(u32) = .empty,
        /// Each bound name → the index of its newest binding.
        index: std.StringHashMapUnmanaged(u32) = .empty,

        pub const empty: Self = .{};

        pub fn len(s: *const Self) usize {
            return s.items.items.len;
        }

        pub fn slice(s: *const Self) []const T {
            return s.items.items;
        }

        /// The newest entry bound as `name`.
        pub fn find(s: *const Self, name: []const u8) ?T {
            const at = s.index.get(name) orelse return null;
            return s.items.items[at];
        }

        /// The index of the newest entry bound as `name`.
        pub fn indexOf(s: *const Self, name: []const u8) ?u32 {
            return s.index.get(name);
        }

        pub fn last(s: *const Self) T {
            return s.items.items[s.items.items.len - 1];
        }

        pub fn append(s: *Self, gpa: std.mem.Allocator, entry: T) std.mem.Allocator.Error!void {
            const at: u32 = @intCast(s.items.items.len);
            const slot = try s.index.getOrPut(gpa, entry.name);
            const before = if (slot.found_existing) slot.value_ptr.* else none;
            slot.value_ptr.* = at;
            errdefer if (before == none) std.debug.assert(s.index.remove(entry.name)) else {
                slot.value_ptr.* = before;
            };
            try s.shadowed.append(gpa, before);
            errdefer _ = s.shadowed.pop();
            try s.items.append(gpa, entry);
        }

        /// Unbinds the entries above `mark`, newest first, so each name points at what it
        /// pointed at when the entry was bound.
        pub fn shrinkRetainingCapacity(s: *Self, mark: usize) void {
            while (s.items.items.len > mark) {
                const entry = s.items.pop().?;
                const before = s.shadowed.pop().?;
                if (before == none) {
                    std.debug.assert(s.index.remove(entry.name));
                } else {
                    s.index.getPtr(entry.name).?.* = before;
                }
            }
        }

        pub fn pop(s: *Self) ?T {
            if (s.items.items.len == 0) return null;
            const entry = s.last();
            s.shrinkRetainingCapacity(s.items.items.len - 1);
            return entry;
        }
    };
}

test "shadowing and shrinking" {
    const gpa = std.testing.allocator;
    const N = struct { name: []const u8, slot: u32 };
    var s: Scope(N) = .empty;
    defer {
        s.items.deinit(gpa);
        s.shadowed.deinit(gpa);
        s.index.deinit(gpa);
    }
    try s.append(gpa, .{ .name = "a", .slot = 0 });
    try s.append(gpa, .{ .name = "b", .slot = 1 });
    const mark = s.len();
    try s.append(gpa, .{ .name = "a", .slot = 2 });
    try s.append(gpa, .{ .name = "c", .slot = 3 });
    try std.testing.expectEqual(@as(u32, 2), s.find("a").?.slot);
    try std.testing.expectEqual(@as(u32, 3), s.find("c").?.slot);
    try std.testing.expectEqual(@as(?u32, 3), s.indexOf("c"));
    s.shrinkRetainingCapacity(mark);
    try std.testing.expectEqual(@as(u32, 0), s.find("a").?.slot);
    try std.testing.expectEqual(@as(u32, 1), s.find("b").?.slot);
    try std.testing.expect(s.find("c") == null);
    try std.testing.expectEqual(@as(u32, 1), s.pop().?.slot);
    try std.testing.expect(s.find("b") == null);
    try std.testing.expectEqual(@as(usize, 1), s.len());
    s.shrinkRetainingCapacity(0);
    try std.testing.expect(s.find("a") == null);
    try std.testing.expectEqual(@as(usize, 0), s.index.count());
}
