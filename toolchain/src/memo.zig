//! Remembered calls, for `mo run`. A Mo function reaches the world only through a
//! capability it is given (chapter 3, effects), so a call that takes no capability,
//! captures none, and has no inout parameter computes its result from its arguments
//! alone: a later call with equal arguments gives the same result, and the Memo gives it
//! without running the body again. Only calls that returned are remembered, so a call
//! that trips a contract trips it every time.
//!
//! The vm watches each function's first calls and remembers the ones that cost enough
//! to be worth a lookup; a function whose arguments rarely repeat, or are too big to key
//! on, is dropped again. Arguments and results are copied out of the vm's region into the
//! Memo's own arena, which stops growing at `max_held`. Under `mo test` there is no Memo.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const vm_mod = @import("vm.zig");

const Value = vm_mod.Value;

/// Values an argument list may count to be a key; a string counts one per 16 bytes.
const key_budget: u32 = 64;
/// Values a remembered call may count, its arguments and result together.
const copy_budget: u32 = 1024;
/// Remembered calls live in one slot each of a table this big; a call whose key lands on a
/// taken slot replaces what was there.
const table_bits = 16;

pub const Memo = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    /// From the page allocator, so untouched slots are zero pages: `function` 0 is empty.
    table: []Entry,
    stats: []Stat,
    /// Value-sized units the arena holds.
    held: usize = 0,
    max_held: usize = (16 << 20) / @sizeOf(Value),
    /// A function's calls watched before deciding whether to remember it.
    watch_calls: u32 = 64,
    /// The instructions a watched call must average, its callees' included.
    min_steps: u64 = 200,

    pub const Found = union(enum) { hit: Value, miss: u64, skip };

    pub const Stat = struct {
        state: enum { watching, remembered, dropped } = .watching,
        calls: u32 = 0,
        steps: u64 = 0,
        hits: u64 = 0,
        misses: u64 = 0,
        /// Calls whose arguments were too big to key on.
        unkeyed: u64 = 0,
    };

    /// `function` is the function's index plus one.
    const Entry = struct { key: u64, function: u32, args: []const Value, captures: []const Value, result: Value };

    pub fn init(gpa: std.mem.Allocator, functions: usize) error{OutOfMemory}!Memo {
        const stats = try gpa.alloc(Stat, functions);
        @memset(stats, .{});
        const table = try std.heap.page_allocator.alloc(Entry, 1 << table_bits);
        return .{ .gpa = gpa, .arena = .init(std.heap.page_allocator), .table = table, .stats = stats };
    }

    pub fn deinit(m: *Memo) void {
        std.heap.page_allocator.free(m.table);
        m.arena.deinit();
    }

    /// Before a call to functions[fi] runs: its remembered result, or the key to keep the
    /// result under once it returns, or skip.
    pub fn lookup(m: *Memo, fi: u32, f: bytecode.Function, args: []const Value, captures: []const Value) Found {
        const s = &m.stats[fi];
        switch (s.state) {
            .dropped => return .skip,
            .watching => {
                if (s.calls < m.watch_calls) return .skip;
                if (f.inouts.len > 0 or s.steps / s.calls < m.min_steps) {
                    s.state = .dropped;
                    return .skip;
                }
                s.state = .remembered;
            },
            .remembered => {},
        }
        var h: Hasher = .{ .h = fi };
        var budget = key_budget;
        if (!hashAll(&h, args, &budget) or !hashAll(&h, captures, &budget)) {
            s.unkeyed += 1;
            if (s.unkeyed >= 64 and s.unkeyed > 4 * (s.hits + s.misses)) s.state = .dropped;
            return .skip;
        }
        const key = h.h;
        const e = &m.table[key & (m.table.len - 1)];
        if (e.function == fi + 1 and e.key == key and vm_mod.allEqual(e.args, args) and vm_mod.allEqual(e.captures, captures)) {
            s.hits += 1;
            return .{ .hit = e.result };
        }
        return .{ .miss = key };
    }

    /// After a call to functions[fi] returned `result` in `steps` instructions: a watched
    /// call counts toward the decision, and a call that missed keeps its result.
    pub fn finish(m: *Memo, fi: u32, steps: u64, key: ?u64, args: []const Value, captures: []const Value, result: Value) error{OutOfMemory}!void {
        const s = &m.stats[fi];
        if (s.state == .watching) {
            s.calls += 1;
            s.steps += steps;
            return;
        }
        const k = key orelse return;
        s.misses += 1;
        // A function whose arguments rarely repeat is not worth its lookups or its copies.
        if (s.misses >= 256 and s.hits < s.misses / 4) {
            s.state = .dropped;
            return;
        }
        if (m.held >= m.max_held) return;
        const a = m.arena.allocator();
        var budget = copy_budget;
        const kept_result = try copy(a, result, &budget) orelse return;
        const kept_args = try copySlice(a, args, &budget) orelse return;
        const kept_captures = try copySlice(a, captures, &budget) orelse return;
        m.held += copy_budget - budget;
        m.table[k & (m.table.len - 1)] = .{ .key = k, .function = fi + 1, .args = kept_args, .captures = kept_captures, .result = kept_result };
    }
};

/// A key is checked for equality on every hit, so its hash need only be quick and spread
/// well: each word is mixed in with one multiply and one rotate.
const Hasher = struct {
    h: u64,

    fn add(self: *Hasher, x: u64) void {
        self.h = std.math.rotl(u64, (self.h ^ x) *% 0x9e37_79b9_7f4a_7c15, 27);
    }

    /// A string of up to 16 bytes as two words, a longer one through Wyhash.
    fn addBytes(self: *Hasher, bytes: []const u8) void {
        if (bytes.len > 16) return self.add(std.hash.Wyhash.hash(bytes.len, bytes));
        var buf = [_]u8{0} ** 16;
        @memcpy(buf[0..bytes.len], bytes);
        self.add(std.mem.readInt(u64, buf[0..8], .little) ^ bytes.len);
        self.add(std.mem.readInt(u64, buf[8..16], .little));
    }
};

/// Hashes `v` into `h`: false for a value too big to key a call on, or one that holds a
/// capability or a handle, which makes the call not a pure one.
fn hash(h: *Hasher, v: Value, budget: *u32) bool {
    if (budget.* == 0) return false;
    budget.* -= 1;
    // The tag rides in the top bits of the first word.
    const tag = @as(u64, @intFromEnum(std.meta.activeTag(v))) << 59;
    switch (v) {
        .none => h.add(tag),
        .bool => |b| h.add(tag ^ @intFromBool(b)),
        .int => |i| {
            const bits: u128 = @bitCast(i);
            h.add(tag ^ @as(u64, @truncate(bits)));
            if (i < std.math.minInt(i64) or i > std.math.maxInt(i64)) h.add(@truncate(bits >> 64));
        },
        .float => |x| h.add(tag ^ @as(u64, @bitCast(x))),
        .time, .duration => |t| h.add(tag ^ @as(u64, @bitCast(t))),
        .string => |str| {
            const cost = std.math.cast(u32, str.len / 16) orelse return false;
            if (cost >= budget.*) return false;
            budget.* -= cost;
            h.add(tag);
            h.addBytes(str);
        },
        .list, .tuple, .map, .set => |xs| {
            h.add(tag ^ xs.len);
            return hashEach(h, xs, budget);
        },
        .record => |r| {
            h.add(tag ^ (@as(u64, r.decl) << 32) ^ r.fields.len);
            return hashEach(h, r.fields, budget);
        },
        .variant => |r| {
            h.add(tag ^ r.fields.len);
            h.addBytes(r.name);
            return hashEach(h, r.fields, budget);
        },
        .func => |f| {
            h.add(tag ^ (@as(u64, f.function) << 32) ^ f.captures.len);
            return hashEach(h, f.captures, budget);
        },
        .cap, .handle => return false,
    }
    return true;
}

fn hashAll(h: *Hasher, xs: []const Value, budget: *u32) bool {
    h.add(xs.len);
    return hashEach(h, xs, budget);
}

fn hashEach(h: *Hasher, xs: []const Value, budget: *u32) bool {
    for (xs) |x| if (!hash(h, x, budget)) return false;
    return true;
}

/// `v` copied whole into `a`, or null when it counts past the budget.
fn copy(a: std.mem.Allocator, v: Value, budget: *u32) error{OutOfMemory}!?Value {
    if (budget.* == 0) return null;
    budget.* -= 1;
    return switch (v) {
        .string => |s| blk: {
            const cost = std.math.cast(u32, s.len / 32) orelse return null;
            if (cost >= budget.*) return null;
            budget.* -= cost;
            break :blk .{ .string = try a.dupe(u8, s) };
        },
        .list => |xs| .{ .list = try copySlice(a, xs, budget) orelse return null },
        .tuple => |xs| .{ .tuple = try copySlice(a, xs, budget) orelse return null },
        .map => |xs| .{ .map = try copySlice(a, xs, budget) orelse return null },
        .set => |xs| .{ .set = try copySlice(a, xs, budget) orelse return null },
        .record => |r| .{ .record = .{ .decl = r.decl, .fields = try copySlice(a, r.fields, budget) orelse return null } },
        .variant => |r| .{ .variant = .{ .name = r.name, .fields = try copySlice(a, r.fields, budget) orelse return null } },
        .func => |f| .{ .func = .{ .function = f.function, .captures = try copySlice(a, f.captures, budget) orelse return null } },
        .cap, .handle => null,
        else => v,
    };
}

fn copySlice(a: std.mem.Allocator, xs: []const Value, budget: *u32) error{OutOfMemory}!?[]const Value {
    const out = try a.alloc(Value, xs.len);
    for (xs, out) |x, *o| o.* = try copy(a, x, budget) orelse return null;
    return out;
}
