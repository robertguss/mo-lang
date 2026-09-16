//! The runtime's events (direction 40, step 23): a bounded ring of structured records of what
//! the processes did, kept by Mo.Sim under `mo test` and by Mo.Server under `mo run`, and read by
//! the runtime surface (design-v0/03, the runtime surface), by a failed seeded test's report, and
//! by `mo run --surface`. runtime/mo_rt.c keeps the same ring for a built binary.
//!
//! Recording is a copy into a slot: an event holds only numbers and names that live as long as the
//! program (a process's, a message's, a call's), except a crash's clause, message, and state, which
//! are the crash report's own text, kept by the run as the report is. The ring is `cap` events; the
//! next overwrites the oldest. `mo run --events N` and `MO_EVENTS=N` for a binary set `cap`, 4,096
//! by default; 0 keeps none.
//!
//! Time: each event's `at` is the runtime's monotonic clock in microseconds. Under Mo.Server it is
//! the awake clock, and `Ring.wall_ms` and `Ring.mono_us` pin it to the wall clock when the run
//! began, so the surface gives it as a `Time`. Under Mo.Sim it is the run's own clock (`clock.now`
//! and the waits fixture calls made), so a seed's events are the same every time it runs.
const std = @import("std");

pub const default_cap: u32 = 4096;
/// A failed seeded test prints this many of its last events after the interleaving.
pub const printed: usize = 10;
/// `process` or `other` when the event is not about a process: main, or a test.
pub const nobody: u32 = std.math.maxInt(u32);

pub const Kind = enum(u8) {
    /// An update committed: `name` the message, `took_us` its whole time, `waited_us` the time it
    /// spent in calls that wait, `call` the one call it waited longest in.
    updated,
    /// `scheduler`: the scheduler it was placed on (step 30), 0 under Mo.Sim and on one core.
    started,
    /// Under Mo.Server, a sweep ended a finished process.
    ended,
    /// `count`: the restarts so far.
    restarted,
    /// `clause`, `message` (the message it crashed on), `state` (before it), `seed`.
    crashed,
    /// `other` sent to `process`, whose mailbox was full.
    overflowed,
    /// `process` (or `nobody`) waited in `call` past its deadline; `other` is an ask's target.
    timed_out,
    /// A loop the runtime owns (`name`: `Listener.serve`, `Conn.lines`, `HttpListener.serve`)
    /// stopped or started again at `process`'s bound, with `count` requests in flight.
    source_paused,
    source_resumed,
    /// The surface delivered `name` to `process`, held its deliveries, or let them go.
    sent,
    paused,
    resumed,
    /// `other` sent `message` to `process`, and it will not arrive: `name` says why, "down" (the
    /// target is down) or "exited" (the program exited while it was delayed). Step 29.
    dropped,
};

pub const Event = struct {
    kind: Kind,
    at: i64 = 0,
    process: u32 = nobody,
    /// The process's name when the event was recorded, since ids are given again.
    process_name: []const u8 = "",
    other: u32 = nobody,
    other_name: []const u8 = "",
    name: []const u8 = "",
    call: []const u8 = "",
    took_us: u64 = 0,
    waited_us: u64 = 0,
    count: u64 = 0,
    seed: u64 = 0,
    clause: []const u8 = "",
    message: []const u8 = "",
    state: []const u8 = "",
    scheduler: u32 = 0,
};

pub const Ring = struct {
    cap: u32 = default_cap,
    /// Under Mo.Server the whole ring is reserved at the first event, from pages the system gives as
    /// they are touched; under Mo.Sim it grows in the run's arena.
    gpa: ?std.mem.Allocator = null,
    slots: []Event = &.{},
    len: usize = 0,
    /// The slot the next event goes in once the ring is full: the oldest.
    head: usize = 0,
    /// Every event ever recorded, kept or overwritten.
    total: u64 = 0,
    wall_ms: i64 = 0,
    mono_us: i64 = 0,

    pub fn record(r: *Ring, e: Event) void {
        if (r.cap == 0) return;
        if (r.len < r.cap) {
            if (r.len == r.slots.len and !r.grow()) return;
            r.slots[r.len] = e;
            r.len += 1;
        } else {
            r.slots[r.head] = e;
            r.head = (r.head + 1) % r.cap;
        }
        r.total += 1;
    }

    fn grow(r: *Ring) bool {
        if (r.gpa) |gpa| {
            const next = @min(r.cap, @max(64, 2 * r.slots.len));
            const more = gpa.alloc(Event, next) catch return false;
            @memcpy(more[0..r.len], r.slots[0..r.len]);
            r.slots = more;
            return true;
        }
        r.slots = std.heap.page_allocator.alloc(Event, r.cap) catch return false;
        return true;
    }

    /// The `i`th event kept, oldest first.
    pub fn get(r: *const Ring, i: usize) Event {
        return r.slots[(r.head + i) % r.len];
    }

    /// The first kept event at or after `i` from the oldest of those whose time is at least `at`.
    pub fn firstSince(r: *const Ring, at: i64) usize {
        var lo: usize = 0;
        var hi: usize = r.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (r.get(mid).at < at) lo = mid + 1 else hi = mid;
        }
        return lo;
    }

    /// An event's time as a `Time`: milliseconds since the epoch.
    pub fn timeOf(r: *const Ring, e: Event) i64 {
        return r.wall_ms + @divFloor(e.at - r.mono_us, 1000);
    }

    /// A `Time` as the ring's clock.
    pub fn monoOf(r: *const Ring, time: i64) i64 {
        return r.mono_us + (time - r.wall_ms) * 1000;
    }

    /// The bytes the ring holds now.
    pub fn bytes(r: *const Ring) usize {
        return r.slots.len * @sizeOf(Event);
    }
};

/// The crash reports the surface reads (step 32), kept apart from the ring so that a stream of
/// updates cannot turn one over before it is read: the last `cap` (16 by default; `mo run
/// --crashes N`, `MO_CRASHES=N` for a binary), written when the report is, whether or not the ring
/// keeps events. Each is the `Crashed` event with its own copies of the clause, the message, and
/// the state snapshot, each cut to `kept_text` bytes where a character begins, in a slot of
/// `slot_bytes` of one buffer reserved at the first crash, so 16 reports hold at most about 200 KiB
/// however large a state is; the printed report is whole. runtime/mo_rt.c keeps the same store.
pub const default_crashes: u32 = 16;
pub const kept_text: usize = 4096;
/// A cut text's ending, ` … N bytes more`, fits in this.
const ending: usize = 40;
pub const slot_bytes: usize = 3 * (kept_text + ending);

pub const Crashes = struct {
    cap: u32 = default_crashes,
    /// Under Mo.Sim the store is in the run's arena; under Mo.Server, pages the system gives as they
    /// are touched.
    gpa: ?std.mem.Allocator = null,
    slots: []Event = &.{},
    texts: []u8 = &.{},
    len: usize = 0,
    /// The slot the next report goes in: the oldest once the store is full.
    head: usize = 0,
    total: u64 = 0,

    pub fn record(c: *Crashes, e: Event) void {
        if (c.cap == 0) return;
        if (c.slots.len == 0) {
            const gpa = c.gpa orelse std.heap.page_allocator;
            c.slots = gpa.alloc(Event, c.cap) catch return;
            c.texts = gpa.alloc(u8, c.cap * slot_bytes) catch {
                gpa.free(c.slots);
                c.slots = &.{};
                return;
            };
        }
        var x = e;
        var room: []u8 = c.texts[c.head * slot_bytes ..][0..slot_bytes];
        for ([_]*[]const u8{ &x.clause, &x.message, &x.state }) |field| {
            field.* = cut(room, field.*);
            room = room[field.len..];
        }
        c.slots[c.head] = x;
        c.head = (c.head + 1) % c.cap;
        if (c.len < c.cap) c.len += 1;
        c.total += 1;
    }

    /// The `i`th report kept, newest first.
    pub fn newest(c: *const Crashes, i: usize) Event {
        return c.slots[(c.head + c.cap - 1 - i) % c.cap];
    }

    /// The bytes the store holds: its slots and the texts in them.
    pub fn bytes(c: *const Crashes) usize {
        var n = c.slots.len * @sizeOf(Event);
        for (c.slots[0..c.len]) |e| n += e.clause.len + e.message.len + e.state.len;
        return n;
    }

    pub fn deinit(c: *Crashes) void {
        if (c.slots.len > 0) {
            const gpa = c.gpa orelse std.heap.page_allocator;
            gpa.free(c.slots);
            gpa.free(c.texts);
        }
        c.* = .{ .cap = c.cap, .gpa = c.gpa };
    }
};

/// `text` copied into `room`, or its first `kept_text` bytes, cut where a character begins, and
/// how many more it had: `{items: [1, 2, … 10240 bytes more`.
fn cut(room: []u8, text: []const u8) []const u8 {
    if (text.len <= kept_text) {
        @memcpy(room[0..text.len], text);
        return room[0..text.len];
    }
    var end: usize = kept_text;
    while (end > 0 and text[end] & 0xC0 == 0x80) end -= 1;
    @memcpy(room[0..end], text[0..end]);
    const more = std.fmt.bufPrint(room[end .. kept_text + ending], " … {d} bytes more", .{text.len - end}) catch unreachable;
    return room[0 .. end + more.len];
}

/// `Keeper #0`, or who sent from outside a process.
fn who(w: *std.Io.Writer, id: u32, name: []const u8, outside: []const u8) std.Io.Writer.Error!void {
    if (id == nobody) return w.writeAll(outside);
    try w.print("{s} #{d}", .{ name, id });
}

/// One event as a failed seeded test prints it: `Keeper #0 took Save in 20 ms, 20 ms waiting,
/// longest in Fs.append`.
pub fn describe(w: *std.Io.Writer, e: Event, outside: []const u8) std.Io.Writer.Error!void {
    switch (e.kind) {
        .updated => {
            try who(w, e.process, e.process_name, outside);
            try w.print(" took {s} in {d} ms", .{ e.name, e.took_us / 1000 });
            if (e.waited_us > 0) try w.print(", {d} ms waiting, longest in {s}", .{ e.waited_us / 1000, e.call });
        },
        .started, .ended => {
            try who(w, e.process, e.process_name, outside);
            try w.writeAll(if (e.kind == .started) " started" else " ended");
        },
        .restarted => {
            try who(w, e.process, e.process_name, outside);
            try w.print(" restarted, {d} so far", .{e.count});
        },
        .crashed => {
            try who(w, e.process, e.process_name, outside);
            try w.print(" crashed on {s}: {s}", .{ e.message, e.clause });
        },
        .overflowed => {
            try who(w, e.other, e.other_name, outside);
            try w.writeAll(" sent to ");
            try who(w, e.process, e.process_name, outside);
            try w.writeAll(", whose mailbox was full");
        },
        .timed_out => {
            try who(w, e.process, e.process_name, outside);
            try w.print(" timed out in {s}", .{e.call});
            if (e.other != nobody) try w.print(" to {s} #{d}", .{ e.other_name, e.other });
        },
        .source_paused, .source_resumed => {
            try w.print("{s} into ", .{e.name});
            try who(w, e.process, e.process_name, outside);
            try w.print(" {s} with {d} in flight", .{ if (e.kind == .source_paused) "paused" else "resumed", e.count });
        },
        .sent => {
            try w.print("the surface sent {s} to ", .{e.name});
            try who(w, e.process, e.process_name, outside);
        },
        .paused, .resumed => {
            try w.print("the surface {s} ", .{if (e.kind == .paused) "paused" else "resumed"});
            try who(w, e.process, e.process_name, outside);
        },
        .dropped => {
            try who(w, e.other, e.other_name, outside);
            try w.print(" sent {s} to ", .{e.message});
            try who(w, e.process, e.process_name, outside);
            try w.print(", dropped: {s}", .{e.name});
        },
    }
}

test "the ring keeps the last cap events, oldest first, and finds a time by halves" {
    var slots: [4]Event = undefined;
    var r: Ring = .{ .cap = 4, .slots = &slots };
    for (0..10) |i| r.record(.{ .kind = .started, .at = @intCast(i * 10), .process = @intCast(i) });
    try std.testing.expectEqual(@as(usize, 4), r.len);
    try std.testing.expectEqual(@as(u64, 10), r.total);
    for (0..4) |i| try std.testing.expectEqual(@as(u32, @intCast(6 + i)), r.get(i).process);
    try std.testing.expectEqual(@as(usize, 2), r.firstSince(71));
    try std.testing.expectEqual(@as(usize, 0), r.firstSince(0));
    try std.testing.expectEqual(@as(usize, 4), r.firstSince(1000));
}

test "the crash store keeps the last cap reports, newest first, each text cut to kept_text" {
    var c: Crashes = .{ .cap = 3, .gpa = std.testing.allocator };
    defer c.deinit();
    const big = try std.testing.allocator.alloc(u8, kept_text + 100);
    defer std.testing.allocator.free(big);
    @memset(big, 'x');
    // A two-byte character straddling the cut is left out whole.
    big[kept_text - 1] = 0xC3;
    big[kept_text] = 0xA9;
    for (0..5) |i| c.record(.{ .kind = .crashed, .process = @intCast(i), .clause = "ensures", .message = "Go", .state = if (i == 4) big else "{n: 1}" });
    try std.testing.expectEqual(@as(usize, 3), c.len);
    try std.testing.expectEqual(@as(u64, 5), c.total);
    for (0..3) |i| try std.testing.expectEqual(@as(u32, @intCast(4 - i)), c.newest(i).process);
    const s = c.newest(0).state;
    try std.testing.expect(std.mem.endsWith(u8, s, " … 101 bytes more"));
    try std.testing.expectEqual(kept_text - 1, std.mem.indexOf(u8, s, " …").?);
    try std.testing.expectEqualStrings("{n: 1}", c.newest(1).state);
    try std.testing.expect(c.bytes() < 3 * @sizeOf(Event) + kept_text + 64);
}
