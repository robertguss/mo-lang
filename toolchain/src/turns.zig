//! Turns: how Mo.Server runs processes (design-v0/03, effects and processes; step 11).
//! Each process runs its updates on a thread of its own, with a Vm of its own, and the
//! threads take turns: the one holding the turn runs Mo code, and the others wait for it.
//! So the scheduler is still one thread in effect: Mo.Sim's rules and its fixed order hold
//! (sim.zig), and nothing the vm keeps needs a lock.
//!
//! A process gives up its turn when it waits: in a Net call (net.zig), or in an ask its
//! target cannot answer yet. It hands the turn back to whoever handed it over, waits off
//! the turn, and asks for a turn again when its wait ends. So `conn.read_line(within:
//! 30.s)` reads like Go and blocks like Erlang: the process's own stack waits, and every
//! other process keeps taking messages.
//!
//! main's thread holds the turn whenever no process does. After each of main's statements,
//! while main waits (in a Net call or an ask), and after main returns, it hands turns out:
//! first to a process whose wait ended, then to the next process with a message waiting,
//! round by round in start order. A process that computes without waiting holds the turn
//! until its update ends; nothing preempts it.
//!
//! A process a start call began ends once it has finished and nothing can reach its handle
//! (sweep, step 19): its parcels and region are freed and its id goes to the next process
//! started, which takes over its thread; the threads of more than kept_threads ended ids
//! return.
//!
//! This is a thread per process, and under std.Io.Threaded a thread per blocked call too;
//! green threads would replace both.
const std = @import("std");
const Io = std.Io;
const contracts = @import("contracts.zig");
const net = @import("net.zig");
const sim_mod = @import("sim.zig");
const vm_mod = @import("vm.zig");

const Region = @import("region.zig").Region;

const Sim = sim_mod.Sim;
const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Parcel = vm_mod.Parcel;
const Error = vm_mod.Error;

/// The address space a process's region reserves, at most: many processes each reserve one.
pub const process_region: usize = 16 << 30;

/// `Turns.holder` when main's thread holds the turn.
pub const main_turn: u32 = std.math.maxInt(u32);

/// The fewest quiet events (Turns.quiet) between two sweeps.
pub const sweep_min: u32 = 64;
/// Ended processes whose threads and regions wait for the next processes given their ids,
/// at most: the last ids ended, which the next starts take.
pub const kept_threads: usize = 64;

const Job = enum { deliver, go_on, exit };

pub const Worker = struct {
    thread: std.Thread = undefined,
    vm: Vm,
    /// Under `mo run`, where its vm allocates.
    values: ?Region = null,
    /// Set when the turn is handed to it.
    wake: Io.Event = .unset,
    /// Who handed it the turn, and gets it back.
    caller: u32 = main_turn,
    job: Job = .deliver,
    /// `running`: it holds the turn, or waits for one it handed on to come back.
    phase: enum { idle, running, waiting } = .idle,
    /// What its turn ended with, for whoever gets the turn back.
    failed: ?Error = null,
    /// Its thread has returned and its region is released, after a sweep ended its process
    /// and more than kept_threads had ended since. The next process given its id starts a
    /// thread again.
    ended: bool = false,
};

const Parked = struct { id: u32, deadline: i64 };

/// An ask's reply, in the parcel it came back in under `mo run`.
pub const Reply = struct { value: Value, parcel: ?*Parcel };

pub const Turns = struct {
    io: Io,
    gpa: std.mem.Allocator,
    mutex: Io.Mutex = .init,
    holder: u32 = main_turn,
    /// main's thread: set when the turn comes back to it, or when a process's wait ends.
    main_wake: Io.Event = .unset,
    /// Processes whose wait ended, oldest first. A process adds itself off the turn, so
    /// every use holds `mutex`; its capacity is the number of processes, so adding never
    /// allocates.
    ready: std.ArrayList(u32) = .empty,
    /// One per process, made at its first delivery; indexed by process id.
    workers: std.ArrayList(?*Worker) = .empty,
    /// Asks waiting for their reply: the message's seq → who asked. This map, `answers`,
    /// and `parked` change with every ask, so they live in `std.heap.smp_allocator`, which
    /// frees, and not in the run's arena, which would keep each table a rehash leaves.
    awaiting: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    /// Replies that came: seq → the reply, or null when the target crashed on the message
    /// or a restart dropped it.
    answers: std.AutoHashMapUnmanaged(u64, ?Reply) = .empty,
    /// Under `mo run`, the scratch region every process's vm compacts through: only the
    /// thread holding the turn runs Mo code, so one is enough.
    scratch: ?*Region = null,
    /// Processes parked in an ask, each with its deadline.
    parked: std.ArrayList(Parked) = .empty,
    /// Where the next round of deliveries starts.
    cursor: u32 = 0,
    /// Events after which a process a start call began may have finished: its start, and
    /// each update of it that left its mailbox empty. A sweep runs when they reach
    /// `sweep_at`, twice the processes the last one left running, and at least sweep_min.
    quiet: u32 = 0,
    sweep_at: u32 = sweep_min,
    /// A sweep's marks, one per process id, and the marked ids whose start arguments it has
    /// yet to read.
    marks: std.ArrayList(bool) = .empty,
    worklist: std.ArrayList(u32) = .empty,

    fn now(t: *const Turns) i64 {
        return Io.Clock.Timestamp.now(t.io, .awake).raw.toMilliseconds();
    }

    // ---- handing the turn over

    fn eventOf(t: *Turns, id: u32) *Io.Event {
        return if (id == main_turn) &t.main_wake else &t.workers.items[id].?.wake;
    }

    /// Gives the turn to `to` and wakes it. Only the holder calls this.
    fn pass(t: *Turns, to: u32, event: *Io.Event) void {
        t.mutex.lockUncancelable(t.io);
        t.holder = to;
        t.mutex.unlock(t.io);
        event.set(t.io);
    }

    /// Waits until the turn is `me`'s.
    fn awaitTurn(t: *Turns, me: u32, event: *Io.Event) void {
        while (true) {
            t.mutex.lockUncancelable(t.io);
            if (t.holder == me) {
                t.mutex.unlock(t.io);
                return;
            }
            event.reset();
            t.mutex.unlock(t.io);
            event.waitUncancelable(t.io);
        }
    }

    /// The holder hands the turn to process `id`, to deliver its next message or to go on
    /// after a wait, and has it back when the update ends or waits again.
    fn handTo(t: *Turns, sim: *Sim, id: u32, job: Job) Error!void {
        const w = try t.worker(sim, id);
        const me = t.holder;
        const mine = t.eventOf(me);
        const vm = sim.vm;
        const running = sim.running;
        w.caller = me;
        w.job = job;
        w.phase = .running;
        t.pass(id, &w.wake);
        t.awaitTurn(me, mine);
        sim.vm = vm;
        sim.running = running;
        if (w.failed) |err| {
            w.failed = null;
            vm.report = w.vm.report;
            return err;
        }
    }

    fn worker(t: *Turns, sim: *Sim, id: u32) Error!*Worker {
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
        t.mutex.lockUncancelable(t.io);
        const room = t.ready.ensureTotalCapacity(t.gpa, t.workers.items.len);
        t.mutex.unlock(t.io);
        try room;
        w.thread = std.Thread.spawn(.{ .stack_size = contracts.vm_stack_bytes }, work, .{ t, sim, id, w }) catch return error.OutOfMemory;
        t.workers.items[id] = w;
        return w;
    }

    /// A process's thread: each turn it is handed delivers one message.
    fn work(t: *Turns, sim: *Sim, id: u32, w: *Worker) void {
        while (true) {
            t.awaitTurn(id, &w.wake);
            sim.vm = &w.vm;
            const job = w.job;
            if (job == .deliver) {
                _ = sim.deliver(id) catch |err| {
                    w.failed = err;
                };
                const p = sim.procs.items[id];
                if (p.supervisor == sim_mod.test_runner and p.queued() == 0) t.quiet += 1;
            }
            w.phase = .idle;
            t.pass(w.caller, t.eventOf(w.caller));
            if (job == .exit) return;
        }
    }

    // ---- waiting

    /// A Net call's wait: its task runs, and `waker` is set when it ends. main's thread hands
    /// out turns until then; a process hands its turn back and waits off it. True when the
    /// task ended within `ms`.
    pub fn block(t: *Turns, sim: *Sim, waker: *net.Waker, ms: i64) Error!bool {
        const deadline = t.now() + @max(ms, 0);
        if (t.holder == main_turn) {
            while (true) {
                if (waker.done.isSet()) return true;
                if (t.now() >= deadline) return false;
                if (try t.step(sim)) continue;
                t.idle(&waker.done, deadline);
            }
        }
        const id = t.holder;
        const w = t.workers.items[id].?;
        const vm = sim.vm;
        const running = sim.running;
        w.phase = .waiting;
        t.pass(w.caller, t.eventOf(w.caller));
        const in_time = net.waitFor(t.io, &waker.done, deadline - t.now());
        t.mutex.lockUncancelable(t.io);
        t.ready.appendAssumeCapacity(id);
        t.mutex.unlock(t.io);
        t.main_wake.set(t.io);
        t.awaitTurn(id, &w.wake);
        sim.vm = vm;
        sim.running = running;
        return in_time;
    }

    /// A process parks in an ask until the reply comes, the target goes down, or `deadline`.
    fn park(t: *Turns, sim: *Sim, deadline: i64) Error!void {
        const id = t.holder;
        const w = t.workers.items[id].?;
        const vm = sim.vm;
        const running = sim.running;
        try t.parked.append(std.heap.smp_allocator, .{ .id = id, .deadline = deadline });
        w.phase = .waiting;
        t.pass(w.caller, t.eventOf(w.caller));
        t.awaitTurn(id, &w.wake);
        sim.vm = vm;
        sim.running = running;
    }

    fn makeReady(t: *Turns, id: u32) void {
        t.mutex.lockUncancelable(t.io);
        t.ready.appendAssumeCapacity(id);
        t.mutex.unlock(t.io);
        t.main_wake.set(t.io);
    }

    /// main's thread, with no turn to hand out: waits until a process's wait ends, `also`
    /// is set, or the earliest deadline passes.
    fn idle(t: *Turns, also: ?*Io.Event, deadline: ?i64) void {
        var until = deadline;
        for (t.parked.items) |p| until = if (until) |u| @min(u, p.deadline) else p.deadline;
        t.mutex.lockUncancelable(t.io);
        const any_ready = t.ready.items.len > 0;
        if (!any_ready) t.main_wake.reset();
        t.mutex.unlock(t.io);
        if (any_ready) return;
        if (also) |e| if (e.isSet()) return;
        const u = until orelse return t.main_wake.waitUncancelable(t.io);
        const left = u - t.now();
        if (left <= 0) return;
        t.main_wake.waitTimeout(t.io, .{ .duration = .{ .raw = .fromMilliseconds(left), .clock = .awake } }) catch {};
    }

    /// One turn handed out, from main's thread: to a process whose wait ended, else to the
    /// next process with a message waiting. False when there is none.
    fn step(t: *Turns, sim: *Sim) Error!bool {
        if (t.quiet >= t.sweep_at) try t.sweep(sim);
        const now_ms = t.now();
        var k: usize = 0;
        while (k < t.parked.items.len) {
            if (t.parked.items[k].deadline <= now_ms) t.makeReady(t.parked.swapRemove(k).id) else k += 1;
        }
        t.mutex.lockUncancelable(t.io);
        const next: ?u32 = if (t.ready.items.len > 0) t.ready.orderedRemove(0) else null;
        t.mutex.unlock(t.io);
        if (next) |id| {
            try t.handTo(sim, id, .go_on);
            return true;
        }
        const n: u32 = @intCast(sim.procs.items.len);
        for (0..n) |j| {
            const id: u32 = @intCast((t.cursor + j) % n);
            const p = &sim.procs.items[id];
            if (!p.up or p.busy or p.queued() == 0) continue;
            t.cursor = id + 1;
            try t.handTo(sim, id, .deliver);
            return true;
        }
        return false;
    }

    // ---- ending finished processes

    /// From main's thread, holding the turn: ends every process that has finished. One has
    /// when a start call began it (a child line's never ends), its mailbox is empty, no update
    /// of it is on a stack, and no handle to it is where anything could use it: in a frame of
    /// main or of an update on a stack, in the start arguments of a process that has not
    /// finished, in a send an update holds, or in a reply not yet taken. Its thread returns,
    /// its region and parcels are freed, and its id goes to the next process started.
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
        while (t.worklist.pop()) |id| try t.markValues(procs[id].args);
        var running: u32 = 0;
        for (procs, 0..) |p, id| {
            if (p.ended or p.supervisor != sim_mod.test_runner) continue;
            if (finished(p) and !t.marks.items[id]) {
                try t.end(sim, @intCast(id));
            } else running += 1;
        }
        const ids = sim.free_ids.items;
        if (ids.len > kept_threads) for (ids[0 .. ids.len - kept_threads]) |id| try t.release(sim, id);
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

    /// Process `id` has finished: what it held is freed, and its thread and emptied region
    /// wait for the next process given its id.
    fn end(t: *Turns, sim: *Sim, id: u32) Error!void {
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

    /// The thread kept for ended process `id` returns, and its region is released.
    fn release(t: *Turns, sim: *Sim, id: u32) Error!void {
        if (id >= t.workers.items.len) return;
        const w = t.workers.items[id] orelse return;
        if (w.ended) return;
        try t.handTo(sim, id, .exit);
        w.thread.join();
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
            if (!p.busy and p.queued() > 0) {
                try t.handTo(sim, to, .deliver);
            } else if (t.holder != main_turn) {
                try t.park(sim, deadline);
            } else if (!try t.step(sim)) {
                t.idle(null, deadline);
            }
        }
    }

    /// Between two of main's statements: every turn there is to hand out, without waiting.
    pub fn settle(t: *Turns, sim: *Sim) Error!void {
        while (try t.step(sim)) {}
    }

    /// main returned: turns go on being handed out until no message waits and no update is
    /// in progress.
    pub fn finish(t: *Turns, sim: *Sim) Error!void {
        while (true) {
            if (try t.step(sim)) continue;
            const pending = for (sim.procs.items) |p| {
                if (p.busy or (p.up and p.queued() > 0)) break true;
            } else false;
            if (!pending) return;
            t.idle(null, null);
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
        if (kv.value == main_turn) return t.main_wake.set(t.io);
        for (t.parked.items, 0..) |p, k| if (p.id == kv.value) {
            _ = t.parked.swapRemove(k);
            return t.makeReady(p.id);
        };
    }

    /// A process crashed: every parked ask looks at its target again.
    pub fn wakeAll(t: *Turns) void {
        while (t.parked.pop()) |p| t.makeReady(p.id);
        t.main_wake.set(t.io);
    }

    /// The run is over. A process's thread between turns ends; one still waiting off the
    /// turn is left to the end of the program.
    pub fn stop(t: *Turns, sim: *Sim) void {
        for (t.workers.items, 0..) |slot, id| {
            const w = slot orelse continue;
            if (w.ended) continue;
            if (w.phase != .idle) {
                w.thread.detach();
                continue;
            }
            t.handTo(sim, @intCast(id), .exit) catch {};
            w.thread.join();
            if (w.values) |*r| r.release();
        }
    }
};
