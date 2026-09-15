//! Turns: how Mo.Server runs processes (design-v0/03, effects and processes; steps 11, 21).
//! Every update runs on main's thread, one at a time, each on a fiber of its own (fiber.zig)
//! with a Vm of its own. So the scheduler is one thread: Mo.Sim's rules and its fixed order
//! hold (sim.zig), and nothing the vm keeps needs a lock.
//!
//! A process gives up the thread when it waits: in a Net call (net.zig), or in an ask its
//! target cannot answer yet. Its fiber switches back to whoever handed it the thread, keeping
//! its stack, and main's thread switches to it again when its wait ends. So `conn.read_line(
//! within: 30.s)` reads like Go and waits like Erlang: the update's stack waits, holding no
//! thread, and every other process keeps taking messages.
//!
//! main's thread runs main's code whenever no update does. After each of main's statements,
//! while main waits (in a Net call or an ask), and after main returns, it hands the thread
//! out: first to a process whose wait ended, then to the next process with a message waiting,
//! round by round in start order. With none to hand out it waits in the poller (poller.zig) for
//! a socket some call or runtime loop waits on, or for the earliest deadline. A process that
//! computes without waiting keeps the thread until its update ends; nothing preempts it.
//!
//! A delivery borrows a fiber from a pool and gives it back when the update ends, so a process
//! at rest holds no stack: what it costs is its region, its mailbox, and its Vm's lists.
//!
//! A process a start call began ends once it has finished and nothing can reach its handle
//! (sweep, step 19): its parcels and region are freed and its id goes to the next process
//! started, which takes over its Vm and region; the regions of more than kept_workers ended
//! ids are released.
const std = @import("std");
const Io = std.Io;
const contracts = @import("contracts.zig");
const fiber_mod = @import("fiber.zig");
const poller_mod = @import("poller.zig");
const sources = @import("sources.zig");
const sim_mod = @import("sim.zig");
const vm_mod = @import("vm.zig");

const Region = @import("region.zig").Region;

const Fiber = fiber_mod.Fiber;
const Poller = poller_mod.Poller;
const Waiter = poller_mod.Waiter;
const Sim = sim_mod.Sim;
const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Parcel = vm_mod.Parcel;
const Error = vm_mod.Error;

/// The address space a process's region reserves at first: many processes each reserve one,
/// and a region that fills allocates past itself from gpa (Region.fallback), memory no compaction
/// frees and the `spilled` of `MO_STATS=1` counts.
pub const process_region: usize = 1 << 30;

/// `Turns.holder` when main's thread runs main's code.
pub const main_turn: u32 = std.math.maxInt(u32);

/// Counts `MO_STATS=1` prints (main.zig, step 21): processes a sweep ended, and the time it took.
pub var freed: u64 = 0;
pub var freed_ns: u64 = 0;

/// The fewest quiet events (Turns.quiet) between two sweeps.
pub const sweep_min: u32 = 64;
/// Ended processes whose regions wait for the next processes given their ids, at most: the last
/// ids ended, which the next starts take.
pub const kept_workers: usize = 64;
/// Idle fibers the pool keeps; past this, fibers coming back are unmapped.
pub const kept_fibers: usize = 64;
/// A job that went more than this many calls deep gives back its stack's pages below the top
/// `fiber_kept_bytes` when it ends, so one deep recursion does not stay resident in the pool.
const deep_calls: u32 = 64;
const fiber_kept_bytes: usize = 1 << 20;

const Job = enum { deliver, go_on };

pub const Worker = struct {
    vm: Vm,
    /// Under `mo run`, where its vm allocates.
    values: ?Region = null,
    /// The fiber its update runs on, from the delivery to the update's end; null at rest.
    fiber: ?*Fiber = null,
    /// Who handed it the thread, and gets it back.
    caller: u32 = main_turn,
    /// `running`: its update holds the thread, or waits for a process it handed it to.
    phase: enum { idle, running, waiting } = .idle,
    /// In `Turns.ready`.
    queued: bool = false,
    /// What its update ended with, for whoever gets the thread back.
    failed: ?Error = null,
    /// Its region is released, after a sweep ended its process and more than kept_workers
    /// had ended since. The next process given its id reserves one again.
    ended: bool = false,
};

const Parked = struct { id: u32, deadline: i64 };

/// An ask's reply, in the parcel it came back in under `mo run`.
pub const Reply = struct { value: Value, parcel: ?*Parcel };

pub const Turns = struct {
    io: Io,
    gpa: std.mem.Allocator,
    sim: *Sim = undefined,
    holder: u32 = main_turn,
    /// main's thread's own context, while a fiber runs.
    main_context: fiber_mod.Context = undefined,
    /// Made when something first waits on a socket.
    poller: ?Poller = null,
    /// Processes whose wait ended, oldest first from `ready_head`; each at most once.
    ready: std.ArrayList(u32) = .empty,
    ready_head: usize = 0,
    /// One per process, made at its first delivery; indexed by process id.
    workers: std.ArrayList(?*Worker) = .empty,
    /// Fibers no update is on.
    fibers: std.ArrayList(*Fiber) = .empty,
    /// Updates on a fiber, running or waiting.
    in_flight: u32 = 0,
    /// Asks waiting for their reply: the message's seq → who asked. This map, `answers`,
    /// and `parked` change with every ask, so they live in `std.heap.smp_allocator`, which
    /// frees, and not in the run's arena, which would keep each table a rehash leaves.
    awaiting: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    /// Replies that came: seq → the reply, or null when the target crashed on the message
    /// or a restart dropped it.
    answers: std.AutoHashMapUnmanaged(u64, ?Reply) = .empty,
    /// Under `mo run`, the scratch region every process's vm compacts through: only one update
    /// runs Mo code at a time, so one is enough.
    scratch: ?*Region = null,
    /// Processes parked in an ask or a Net call, each with its deadline.
    parked: std.ArrayList(Parked) = .empty,
    /// Where the next round of deliveries starts.
    cursor: u32 = 0,
    /// Process ids that may have a message waiting: set when one is put in a mailbox
    /// (Sim.enqueue), cleared when the round finds the mailbox empty.
    runnable: std.DynamicBitSetUnmanaged = .{},
    /// Events after which a process a start call began may have finished: its start, and
    /// each update of it that left its mailbox empty. A sweep runs when they reach
    /// `sweep_at`, twice the processes the last one left running, and at least sweep_min.
    quiet: u32 = 0,
    sweep_at: u32 = sweep_min,
    /// A sweep's marks, one per process id, and the marked ids whose start arguments it has
    /// yet to read.
    marks: std.ArrayList(bool) = .empty,
    worklist: std.ArrayList(u32) = .empty,
    /// The poller's last reports.
    fired: [poller_mod.batch]*Waiter = undefined,

    pub fn now(t: *const Turns) i64 {
        return Io.Clock.Timestamp.now(t.io, .awake).raw.toMilliseconds();
    }

    pub fn pollerOf(t: *Turns) Error!*Poller {
        if (t.poller == null) t.poller = Poller.init() catch return error.OutOfMemory;
        return &t.poller.?;
    }

    // ---- handing the thread over

    fn contextOf(t: *Turns, id: u32) *fiber_mod.Context {
        return if (id == main_turn) &t.main_context else &t.workers.items[id].?.fiber.?.context;
    }

    /// Switches to `to`, main or a process with a fiber; returns when something switches back.
    fn switchTo(t: *Turns, to: u32) void {
        const from = t.holder;
        const depth = vm_mod.call_depth;
        t.holder = to;
        fiber_mod.switchTo(t.contextOf(from), t.contextOf(to));
        vm_mod.call_depth = depth;
    }

    /// The holder hands the thread to process `id`, to deliver its next message or to go on
    /// after a wait, and has it back when the update ends or waits again.
    fn handTo(t: *Turns, sim: *Sim, id: u32, job: Job) Error!void {
        const w = try t.worker(sim, id);
        const vm = sim.vm;
        const running = sim.running;
        w.caller = t.holder;
        w.phase = .running;
        if (job == .deliver) {
            const f = t.fibers.pop() orelse try Fiber.create(contracts.vm_stack_bytes);
            f.run = deliverOn;
            f.owner = t;
            f.arg = id;
            w.fiber = f;
            t.in_flight += 1;
        }
        t.switchTo(id);
        sim.vm = vm;
        sim.running = running;
        if (w.failed) |err| {
            w.failed = null;
            vm.report = w.vm.report;
            return err;
        }
    }

    fn worker(t: *Turns, sim: *Sim, id: u32) Error!*Worker {
        t.sim = sim;
        while (t.workers.items.len <= id) try t.workers.append(t.gpa, null);
        if (t.workers.items[id]) |w| if (!w.ended) return w;
        const w = t.workers.items[id] orelse try t.gpa.create(Worker);
        if (t.workers.items[id] == null) {
            w.* = .{ .vm = .init(sim.gpa, sim.vm.program, 0) };
        } else {
            // The worker of an ended process: its lists keep their room.
            w.vm.reuse();
            const vm = w.vm;
            w.* = .{ .vm = vm };
        }
        if (t.scratch) |s| {
            w.values = Region.reserveUpTo(process_region) catch null;
            if (w.values) |*r| w.vm.useRegions(r, s);
        }
        w.vm.sim = sim;
        w.vm.server = sim.vm.server;
        // Each id is in the ready queue at most once.
        try t.ready.ensureTotalCapacity(t.gpa, t.workers.items.len + 1);
        t.workers.items[id] = w;
        return w;
    }

    /// A fiber's job: one message delivered to process `f.arg`, then the thread and the fiber
    /// go back.
    fn deliverOn(f: *Fiber) void {
        const t: *Turns = @ptrCast(@alignCast(f.owner));
        const id = f.arg;
        const sim = t.sim;
        const w = t.workers.items[id].?;
        vm_mod.call_depth = 0;
        vm_mod.call_high = 0;
        sim.vm = &w.vm;
        _ = sim.deliver(id) catch |err| {
            w.failed = err;
        };
        const p = sim.procs.items[id];
        if (p.supervisor == sim_mod.test_runner and p.queued() == 0) t.quiet += 1;
        w.phase = .idle;
        w.fiber = null;
        t.in_flight -= 1;
        if (vm_mod.call_high > deep_calls) f.decommit(fiber_kept_bytes);
        // A pool that cannot grow loses the fiber, which is never used again.
        t.fibers.append(t.gpa, f) catch {};
        t.holder = w.caller;
        f.back = t.contextOf(w.caller);
    }

    fn pushReady(t: *Turns, id: u32) void {
        const w = t.workers.items[id].?;
        if (w.queued) return;
        w.queued = true;
        if (t.ready_head > 0 and t.ready.items.len == t.ready.capacity) {
            const waiting = t.ready.items.len - t.ready_head;
            std.mem.copyForwards(u32, t.ready.items[0..waiting], t.ready.items[t.ready_head..]);
            t.ready.shrinkRetainingCapacity(waiting);
            t.ready_head = 0;
        }
        t.ready.appendAssumeCapacity(id);
    }

    fn popReady(t: *Turns) ?u32 {
        if (t.ready_head == t.ready.items.len) return null;
        const id = t.ready.items[t.ready_head];
        t.ready_head += 1;
        if (t.ready_head == t.ready.items.len) {
            t.ready.clearRetainingCapacity();
            t.ready_head = 0;
        }
        t.workers.items[id].?.queued = false;
        return id;
    }

    // ---- waiting

    /// A Net call's wait for `fd` to be ready, at most `ms`. main's thread hands out turns until
    /// then; a process's update switches back to whoever handed it the thread and is switched
    /// to again when the poller reports the socket or the deadline passes. True when ready.
    pub fn block(t: *Turns, sim: *Sim, fd: std.posix.fd_t, filter: poller_mod.Filter, ms: i64) Error!bool {
        const deadline = t.now() + @max(ms, 0);
        const p = try t.pollerOf();
        var w: Waiter = .{ .fd = fd, .filter = filter };
        if (t.holder == main_turn) {
            if (!p.arm(&w)) return true;
            defer p.disarm(&w);
            while (true) {
                if (w.fired) return true;
                if (t.now() >= deadline) return false;
                if (try t.step(sim)) continue;
                t.idle(sim, &w, deadline);
            }
        }
        const id = t.holder;
        w.process = id;
        if (!p.arm(&w)) return true;
        defer p.disarm(&w);
        const me = t.workers.items[id].?;
        const vm = sim.vm;
        const running = sim.running;
        // Woken early (a crash elsewhere wakes every parked process), it parks again.
        while (!w.fired and t.now() < deadline) {
            try t.parked.append(std.heap.smp_allocator, .{ .id = id, .deadline = deadline });
            me.phase = .waiting;
            t.switchTo(me.caller);
        }
        sim.vm = vm;
        sim.running = running;
        return w.fired;
    }

    /// A process parks in an ask until the reply comes, the target goes down, or `deadline`.
    fn park(t: *Turns, sim: *Sim, deadline: i64) Error!void {
        const id = t.holder;
        const w = t.workers.items[id].?;
        const vm = sim.vm;
        const running = sim.running;
        try t.parked.append(std.heap.smp_allocator, .{ .id = id, .deadline = deadline });
        w.phase = .waiting;
        t.switchTo(w.caller);
        sim.vm = vm;
        sim.running = running;
    }

    /// Process `id`'s wait ended: it leaves the parked list and is switched to next.
    fn wake(t: *Turns, id: u32) void {
        for (t.parked.items, 0..) |p, k| if (p.id == id) {
            _ = t.parked.swapRemove(k);
            break;
        };
        t.pushReady(id);
    }

    /// main's thread, with no turn to hand out: waits in the poller until a socket something
    /// waits on is ready, `also` is reported, or the earliest deadline passes.
    fn idle(t: *Turns, sim: *Sim, also: ?*Waiter, deadline: ?i64) void {
        if (t.ready_head < t.ready.items.len) return;
        if (also) |w| if (w.fired) return;
        if (sources.hasWork(sim)) return;
        var until = deadline;
        if (sources.nextDeadline(sim)) |d| until = if (until) |u| @min(u, d) else d;
        if (sim.nextLater()) |d| until = if (until) |u| @min(u, d) else d;
        for (t.parked.items) |p| until = if (until) |u| @min(u, p.deadline) else p.deadline;
        const p = t.pollerOf() catch return;
        // At least once a second, whatever the deadlines say: nothing waits past a lost report.
        const left: i64 = if (until) |u| @min(@max(u - t.now(), 0), 1000) else 1000;
        const n = p.wait(left, &t.fired);
        for (t.fired[0..n]) |w| {
            if (w.process != poller_mod.nobody) {
                t.wake(w.process);
            } else if (w.source) |s| sources.fired(sim, @ptrCast(@alignCast(s)));
        }
    }

    /// One turn handed out, from main's thread: to a process whose wait ended, else to the
    /// next process with a message waiting. False when there is none.
    fn step(t: *Turns, sim: *Sim) Error!bool {
        if (t.quiet >= t.sweep_at) try t.sweep(sim);
        while (t.fibers.items.len > kept_fibers) t.fibers.pop().?.destroy();
        // What the runtime's loops took becomes messages first (sources.zig), and delayed sends
        // whose time has come (step 24).
        try sources.pumpServer(sim, t);
        _ = try sim.dueLater();
        const now_ms = t.now();
        var k: usize = 0;
        while (k < t.parked.items.len) {
            if (t.parked.items[k].deadline <= now_ms) t.pushReady(t.parked.swapRemove(k).id) else k += 1;
        }
        while (t.popReady()) |id| {
            const w = t.workers.items[id].?;
            if (w.phase != .waiting or w.fiber == null) continue;
            try t.handTo(sim, id, .go_on);
            return true;
        }
        const n: u32 = @intCast(sim.procs.items.len);
        if (n == 0) return false;
        const from = t.cursor % n;
        const id = t.nextRunnable(sim, from, n) orelse t.nextRunnable(sim, 0, from) orelse return false;
        t.cursor = id + 1;
        try t.handTo(sim, id, .deliver);
        return true;
    }

    /// Sim.enqueue put a message in process `id`'s mailbox.
    pub fn markRunnable(t: *Turns, id: u32) Error!void {
        if (id >= t.runnable.bit_length) try t.runnable.resize(t.gpa, @max(2 * t.runnable.bit_length, id + 64), false);
        t.runnable.set(id);
    }

    /// The first process in [from, to) that is up, not on a stack, and has a message waiting.
    /// A marked process whose mailbox is empty, or that is down, is unmarked on the way.
    fn nextRunnable(t: *Turns, sim: *Sim, from: u32, to: u32) ?u32 {
        const bits = @bitSizeOf(usize);
        var i: usize = from;
        const stop_at = @min(to, t.runnable.bit_length);
        while (i < stop_at) {
            const word = t.runnable.masks[i / bits] >> @intCast(i % bits);
            if (word == 0) {
                i = (i / bits + 1) * bits;
                continue;
            }
            i += @ctz(word);
            if (i >= stop_at) break;
            const p = &sim.procs.items[i];
            if (!p.up or p.queued() == 0) {
                t.runnable.unset(i);
            } else if (!p.busy and !p.paused) {
                return @intCast(i);
            }
            i += 1;
        }
        return null;
    }

    // ---- ending finished processes

    /// From main's thread, holding the turn: ends every process that has finished. One has
    /// when a start call began it (a child line's never ends), its mailbox is empty, no update
    /// of it is on a stack, and no handle to it is where anything could use it: in a frame of
    /// main or of an update on a stack, in the start arguments of a process that has not
    /// finished, in the state of a process that is up (step 24), in a send an update holds, or in
    /// a reply not yet taken. Its region and parcels
    /// are freed, and its id goes to the next process started.
    fn sweep(t: *Turns, sim: *Sim) Error!void {
        const gpa = std.heap.smp_allocator;
        const procs = sim.procs.items;
        try t.marks.resize(gpa, procs.len);
        @memset(t.marks.items, false);
        t.worklist.clearRetainingCapacity();
        // main's vm: only main's thread sweeps.
        for (sim.vm.handle_frames.items) |locals| try t.markValues(locals);
        for (procs, 0..) |p, id| {
            if (p.ended or finished(p)) continue;
            try t.markValues(p.args);
            // A state may keep handles (step 24); a process that is down keeps none.
            if (p.up) try t.markValue(p.state);
            // A message may carry a handle (step 20): one waiting in a mailbox or held in an
            // outbox reaches its process.
            for (p.mailbox.items[p.head..]) |e| try t.markValue(e.message);
            if (!p.busy) continue;
            for (t.workers.items[id].?.vm.handle_frames.items) |locals| try t.markValues(locals);
            for (p.outbox.items) |o| {
                try t.markId(o.to);
                try t.markValue(o.message);
            }
        }
        var answers = t.answers.valueIterator();
        while (answers.next()) |reply| if (reply.*) |r| try t.markValue(r.value);
        // A source's target is where the runtime keeps sending, and a delayed send's is where the
        // runtime will (step 24).
        for (sim.sources.list.items) |s| if (!s.done) try t.markId(s.to);
        for (sim.later.items) |l| {
            try t.markId(l.to);
            try t.markValue(l.message);
        }
        while (t.worklist.pop()) |id| {
            try t.markValues(procs[id].args);
            if (procs[id].up) try t.markValue(procs[id].state);
        }
        var running: u32 = 0;
        for (procs, 0..) |p, id| {
            if (p.ended or p.supervisor != sim_mod.test_runner) continue;
            if (finished(p) and !t.marks.items[id]) {
                try t.end(sim, @intCast(id));
            } else running += 1;
        }
        const ids = sim.free_ids.items;
        if (ids.len > kept_workers) for (ids[0 .. ids.len - kept_workers]) |id| t.release(id);
        t.quiet = 0;
        t.sweep_at = @max(sweep_min, 2 * running);
    }

    /// Began by a start call, nothing waiting for it, and no update of it on a stack.
    fn finished(p: sim_mod.Proc) bool {
        return p.supervisor == sim_mod.test_runner and !p.busy and p.queued() == 0;
    }

    fn markId(t: *Turns, id: u32) Error!void {
        if (id >= t.marks.items.len or t.marks.items[id]) return;
        t.marks.items[id] = true;
        try t.worklist.append(std.heap.smp_allocator, id);
    }

    fn markValues(t: *Turns, values: []const Value) Error!void {
        for (values) |v| try t.markValue(v);
    }

    /// Every handle inside `v`. A list, a set, or a map's keys or values whose first element
    /// cannot hold a handle hold none, since their elements share a type.
    fn markValue(t: *Turns, v: Value) Error!void {
        switch (v) {
            .handle => |id| try t.markId(id),
            .tuple => |xs| try t.markValues(xs),
            .variant => |x| try t.markValues(x.fields),
            // A state (step 24): no struct holds a handle, so only a state's fields are read.
            .record => |r| try t.markValues(r.fields),
            .list => |xs| if (xs.len > 0 and mayHoldHandle(xs[0])) try t.markValues(xs),
            .set => |m| if (m.entries.len > 0 and mayHoldHandle(m.entries[0])) try t.markValues(m.entries),
            .map => |m| if (m.entries.len > 1) {
                const keys = mayHoldHandle(m.entries[0]);
                const values = mayHoldHandle(m.entries[1]);
                var i: usize = 0;
                while (i + 1 < m.entries.len) : (i += 2) {
                    if (keys) try t.markValue(m.entries[i]);
                    if (values) try t.markValue(m.entries[i + 1]);
                }
            },
            else => {},
        }
    }

    fn mayHoldHandle(v: Value) bool {
        return switch (v) {
            .handle, .tuple, .variant, .list, .set, .map => true,
            else => false,
        };
    }

    /// Process `id` has finished: what it held is freed, and its emptied region waits for the
    /// next process given its id.
    fn end(t: *Turns, sim: *Sim, id: u32) Error!void {
        const t0 = Io.Clock.Timestamp.now(t.io, .awake);
        defer {
            freed += 1;
            freed_ns += @intCast(t0.durationTo(Io.Clock.Timestamp.now(t.io, .awake)).raw.toNanoseconds());
        }
        sim.record(.{ .kind = .ended, .process = id });
        if (id < t.workers.items.len) if (t.workers.items[id]) |w| if (!w.ended) {
            w.vm.reuse();
            if (w.values) |*r| {
                r.decommit();
                w.vm.useRegions(r, t.scratch.?);
            }
        };
        const p = &sim.procs.items[id];
        if (p.start) |parcel| parcel.free();
        for (p.log_parcels.items) |parcel| parcel.free();
        p.log_parcels.clearRetainingCapacity();
        p.log.clearRetainingCapacity();
        p.mailbox.clearRetainingCapacity();
        p.restarts.clearRetainingCapacity();
        p.head = 0;
        p.start = null;
        p.args = &.{};
        p.state = .none;
        p.up = false;
        p.ended = true;
        try sim.free_ids.append(sim.gpa, id);
    }

    /// The region kept for ended process `id` is released.
    fn release(t: *Turns, id: u32) void {
        if (id >= t.workers.items.len) return;
        const w = t.workers.items[id] orelse return;
        if (w.ended) return;
        if (w.values) |*r| r.release();
        w.values = null;
        w.ended = true;
    }

    // ---- what Mo.Sim asks of the scheduler under Mo.Server

    /// `h.ask(message, within: d)`, with `d` in wall-clock time. The target's waiting
    /// messages are delivered first, as in Mo.Sim; while it cannot answer, main hands out
    /// turns and a process parks. `Timeout` at the deadline, or at once when the target's
    /// update is itself waiting on this call; `Down` when the target is down, crashed on
    /// the message, or dropped it restarting. A Timeout's message still arrives.
    pub fn ask(t: *Turns, sim: *Sim, to: u32, message: Value, within: i64) Error!Value {
        if (!sim.procs.items[to].up) return sim.askError("Down");
        try sim.roomFor(to, message);
        const parcel: ?*Parcel = if (sim.packs) try sim.vm.pack(message) else null;
        const seq = try sim.enqueue(sim.running orelse sim_mod.test_runner, to, if (parcel) |p| p.value else message, parcel);
        try t.awaiting.put(std.heap.smp_allocator, seq, t.holder);
        const deadline = t.now() + @max(within, 0);
        const target = &sim.procs.items[to];
        target.mailbox.items[target.mailbox.items.len - 1].deadline = deadline;
        while (true) {
            // A wait elsewhere doomed this ask (sim.zig, held sends): Sim.ask crashes the update.
            if (sim.running) |me| if (sim.procs.items[me].doomed != null) {
                _ = t.awaiting.remove(seq);
                return sim.askError("Down");
            };
            if (t.answers.fetchRemove(seq)) |kv| {
                const got = kv.value orelse return sim.askError("Down");
                const reply = if (got.parcel) |p| blk: {
                    defer p.free();
                    break :blk try sim.vm.unpack(p);
                } else got.value;
                return sim.vm.variant("Ok", &.{reply});
            }
            const p = &sim.procs.items[to];
            const running = p.busy and t.workers.items[to].?.phase == .running;
            if (!p.up or running or t.now() >= deadline) {
                _ = t.awaiting.remove(seq);
                return sim.askError(if (p.up) "Timeout" else "Down");
            }
            if (!p.busy and !p.paused and p.queued() > 0) {
                try t.handTo(sim, to, .deliver);
            } else if (t.holder != main_turn) {
                try t.park(sim, deadline);
            } else if (!try t.step(sim)) {
                t.idle(sim, null, deadline);
            }
        }
    }

    /// The surface reads process `id` between updates (surface.zig, step 23): while an update of it
    /// is on a stack, main hands out turns and a process parks, a millisecond at a time, at most
    /// `within`. True once none is.
    pub fn waitIdle(t: *Turns, sim: *Sim, id: u32, within: i64) Error!bool {
        const deadline = t.now() + @max(within, 0);
        while (sim.procs.items[id].busy) {
            const now_ms = t.now();
            if (now_ms >= deadline) return false;
            if (t.holder != main_turn) {
                try t.park(sim, @min(deadline, now_ms + 1));
            } else if (!try t.step(sim)) t.idle(sim, null, @min(deadline, now_ms + 1));
        }
        return true;
    }

    /// Between two of main's statements: every turn there is to hand out, without waiting.
    pub fn settle(t: *Turns, sim: *Sim) Error!void {
        while (try t.step(sim)) {}
    }

    /// main returned: turns go on being handed out until no message waits, no update is in
    /// progress, no runtime loop can deliver, and no delayed send is still to come (step 24). After
    /// exit, only until nothing can run without waiting (step 29).
    pub fn finish(t: *Turns, sim: *Sim) Error!void {
        while (true) {
            if (try t.step(sim)) continue;
            if (sim.exiting) return;
            if (t.in_flight == 0 and !sim.sources.active() and sim.later.items.len == 0) return;
            t.idle(sim, null, null);
        }
    }

    /// Whether an ask still waits for the reply to message `seq`.
    pub fn awaits(t: *const Turns, seq: u64) bool {
        return t.awaiting.contains(seq);
    }

    /// An update that took message `seq` ended: with its reply, packed under `mo run`, or
    /// null when it crashed. The asker takes the parcel.
    pub fn answer(t: *Turns, seq: u64, reply: ?Value, parcel: ?*Parcel) Error!void {
        const kv = t.awaiting.fetchRemove(seq) orelse {
            if (parcel) |p| p.free();
            return;
        };
        try t.answers.put(std.heap.smp_allocator, seq, if (reply) |v| .{ .value = v, .parcel = parcel } else null);
        // main looks for its answer each time round its ask; a parked process is woken.
        if (kv.value == main_turn) return;
        for (t.parked.items) |p| if (p.id == kv.value) return t.wake(p.id);
    }

    /// A process crashed: every parked process looks at what it waits for again.
    pub fn wakeAll(t: *Turns) void {
        while (t.parked.pop()) |p| t.pushReady(p.id);
    }

    /// The run is over. An update still waiting when it ends is left where it is.
    pub fn stop(t: *Turns, sim: *Sim) void {
        sources.stopServer(sim, t);
        for (t.workers.items) |slot| {
            const w = slot orelse continue;
            if (w.ended or w.fiber != null) continue;
            if (w.values) |*r| r.release();
            w.values = null;
            w.ended = true;
        }
        for (t.fibers.items) |f| f.destroy();
        t.fibers.clearRetainingCapacity();
        if (t.poller) |*p| p.deinit();
        t.poller = null;
    }
};
