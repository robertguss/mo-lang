//! Mo.Sim: the deterministic scheduler `mo test` runs processes on (design-v0/03,
//! processes and failure; 08, the milestone). One thread and one fixed order: no green
//! threads, and no clock that moves by itself. A test's sends are delivered before its
//! next statement runs (bytecode `settle`); `ask` runs the target's waiting messages,
//! then its own. `update` is a transaction: a crash discards that message's state
//! writes and its buffered sends and emits, the supervisor restarts the process from
//! its initial state, and the crash is kept with its complete report.
//! A seeded run (`mo test --sim N`, design-v0/05 tier 3) keeps every rule above and lets
//! the seed choose what the fixed order fixes: which waiting process takes its next
//! message, whether a statement's sends are delivered before the next statement or after
//! it, and how far the clock moves before each update (0 to 10 ms). Its deliveries are
//! kept in order, so a failure prints the interleaving that found it.
//! With faults, a seeded run's fixtures can fail or be slow, each call by the seed's
//! draw (`fault`), and an `ask` whose target waited past its deadline is a Timeout.
//! Every test and property run of a program with a `never`, seeded or not, keeps each
//! distinct value of a type a never reads with `T.all` that the run held in a binding, a
//! field, a message, or state (`observe`), and checks every never over them when the run
//! ends (`checkNevers`). A never reads values at rest (step 27): a field write records the
//! struct only when the next statement does not write the same place again.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const contracts = @import("contracts.zig");
const net_mod = @import("net.zig");
const server_mod = @import("server.zig");
const sources_mod = @import("sources.zig");
const stdlib = @import("stdlib.zig");
const turns_mod = @import("turns.zig");
const vm_mod = @import("vm.zig");
const events_mod = @import("events.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Parcel = vm_mod.Parcel;
const Error = vm_mod.Error;
const none = bytecode.none;

/// A child line with no max_restarts: three restarts within five seconds.
pub const default_max_restarts: u32 = 3;
pub const default_window_ms: i64 = 5_000;
/// Deliveries one settle makes before the processes count as never settling.
pub const settle_limit: u32 = 1_000_000;
/// `Proc.supervisor` of a process a test started directly: the test runner.
pub const test_runner: u32 = none;
/// The most a seeded run's clock moves before one update.
pub const max_tick_ms: i64 = 10;
/// Mixed into the seed for the fault draws, so they are a stream apart from the schedule.
const fault_stream: u64 = 0x6661_756c_7473;
/// Under `mo run`, the messages a process's log keeps for a crash report: the last ones.
pub const log_kept = 16;
/// Region bytes a process may leave behind past twice what its last full compaction kept
/// before its region is compacted whole (settleRegion).
pub const full_budget: usize = 4 << 20;
/// The most address space a process's region grows to (settleRegion).
pub const max_region: usize = 16 << 30;

pub const Fault = enum { timeout, missing, closed };

/// `line`: the supervisor whose child line gave the policy, or none (a crash report names it).
pub const Policy = struct { restart: bytecode.Restart, max_restarts: u32, window_ms: i64, line: u32 = none };

/// A call a process's update waits in on a peer: a listener's next client (`accept`) or a
/// connection's next line (`read_line`), by handle, and the call as a report names it.
pub const Wait = struct { listener: bool, handle: u32, call: []const u8 };

/// A send an update holds (`holder`'s outbox) to `to`, which a wait can hear from only after it.
const Held = struct { holder: u32, to: u32, message: Value };

/// A message in a mailbox or an outbox. Under `mo run` it came in a parcel (Sim.packs),
/// which the mailbox, and then the process's log, owns.
/// `deadline`: an ask's, on the runtime's clock (Sim.deadlineNow), which the update that takes
/// it sees as `reply_by`; null for a send.
const Entry = struct { message: Value, seq: u64, parcel: ?*Parcel = null, deadline: ?i64 = null };
/// `delay`: a send with `delay:` (step 24), in milliseconds; 0 for a plain send.
const Outgoing = struct { to: u32, message: Value, parcel: ?*Parcel = null, delay: i64 = 0 };
/// A delayed send the runtime holds until `at` on the runtime's clock (Sim.deadlineNow): `order`
/// keeps two due at once in the order they were sent.
pub const Later = struct { at: i64, order: u64, from: u32, to: u32, message: Value, parcel: ?*Parcel };
/// One step of a seeded run's trace: a message put in a mailbox, by the test
/// (`from` is `test_runner`) or by a process whose update committed, or taken out of it.
pub const Step = struct { from: u32, to: u32, message: Value, took: bool };

pub const Proc = struct {
    /// Index in `Program.processes`.
    process: u32,
    args: []const Value,
    state: Value,
    /// Index in `Sim.supervisors`, or `test_runner`.
    supervisor: u32,
    policy: Policy,
    mailbox: std.ArrayList(Entry) = .empty,
    head: usize = 0,
    /// Every message since the last (re)start, the running one included; under `mo run`,
    /// the last `log_kept`, and the parcels they came in.
    log: std.ArrayList(Value) = .empty,
    log_parcels: std.ArrayList(*Parcel) = .empty,
    /// Under `mo run`, the parcel holding its start arguments and first state, which they
    /// and every state after may point into for as long as the run lasts.
    start: ?*Parcel = null,
    /// When each restart inside the current window happened.
    restarts: std.ArrayList(i64) = .empty,
    up: bool = true,
    /// Its update is on the stack.
    busy: bool = false,
    /// Sends and emits of the running update, delivered only when it commits.
    outbox: std.ArrayList(Outgoing) = .empty,
    emits: std.ArrayList(Value) = .empty,
    /// Under Mo.Server, the wall clock when its running update began: `clock.now` is
    /// frozen per update.
    now: i64 = 0,
    /// Under `mo run`, a sweep ended it (turns.zig): its id waits for the next process its scheduler starts.
    ended: bool = false,
    /// The running update's `reply_by`: its message's ask deadline, or when it was taken for a
    /// message that came with none (step 22).
    reply_by: i64 = 0,
    /// The running update's `reply_to`: the seq of the message it took, which is the asker's
    /// name (step 31).
    reply_seq: u64 = 0,
    /// The running update ran a `defer_reply`: its arm kept the asker, so the commit answers
    /// nothing and the seq joins `kept`.
    deferring: bool = false,
    /// The asks this process holds unanswered, oldest first (step 31): a crash or a restart
    /// answers every one of them Down. An answer, and a deadline that has passed, take one out.
    kept: std.ArrayList(u64) = .empty,
    /// `reply.answer(v)` calls of the running update: an answer commits with the update, as a
    /// send does, so an update that crashes after one answers Down instead.
    answers: std.ArrayList(PendingAnswer) = .empty,
    /// Its update waits in an ask to this process, or none; or in a call on a peer.
    asking: u32 = none,
    wait: ?Wait = null,
    /// A wait elsewhere found that this update's ask can end only after a send it holds: the
    /// ask crashes the update with this report when it returns.
    doomed: ?contracts.Report = null,
    /// Restarts since it started, never trimmed to the window: the surface's count (step 23).
    restarted: u64 = 0,
    /// The surface holds its deliveries (step 23): no round takes its next message.
    paused: bool = false,
    /// The running update's time in calls that wait, and the call it waited longest in, for its
    /// `updated` event (events.zig).
    waited_us: u64 = 0,
    longest_us: u64 = 0,
    longest: []const u8 = "",
    /// The call its update waits in now, for the surface (surface.zig); "" when none.
    waiting: []const u8 = "",

    pub fn queued(p: *const Proc) usize {
        return p.mailbox.items.len - p.head;
    }
};

/// An `answer` the running update made, delivered when it commits (step 31).
pub const PendingAnswer = struct { seq: u64, value: Value };
/// A reply that reached an inline ask before it woke: the value, packed when the run packs.
pub const Answered = struct { value: Value, parcel: ?*Parcel = null };

pub const Supervisor = struct { index: u32 };

pub const Sim = struct {
    gpa: std.mem.Allocator,
    vm: *Vm,
    /// The run's seed, named in every crash report.
    seed: u64,
    /// The test the run belongs to: the sender of every message sent from outside a process.
    test_name: []const u8,
    /// `clock.now`: frozen for a whole update; in the fixed order, for the whole run.
    now: i64 = vm_mod.fixture_time,
    procs: std.ArrayList(Proc) = .empty,
    supervisors: std.ArrayList(Supervisor) = .empty,
    /// The process whose update is running, innermost.
    running: ?u32 = null,
    /// Without turns.zig: the replies that came for asks still waiting, by the ask's seq, and
    /// the seqs of the asks that wait. An answer to a seq nobody waits for is dropped, which is
    /// what a deadline that has passed leaves behind (step 31).
    answered: std.AutoHashMapUnmanaged(u64, ?Answered) = .empty,
    waiting: std.AutoHashMapUnmanaged(u64, void) = .empty,
    next_seq: u64 = 0,
    /// Every process crash, in order, each report complete.
    crashes: std.ArrayList(contracts.Report) = .empty,
    /// A supervisor gave up: `Vm.report` says which, and the run stops.
    gave_up: bool = false,
    /// Events emitted by committed updates and by the test, in order.
    events: std.ArrayList(Value) = .empty,
    /// The scheduler's choices in a seeded run; null in the fixed order.
    schedule: ?std.Random.DefaultPrng = null,
    /// Every message of a seeded run as it was sent and as it was taken, in order.
    trace: std.ArrayList(Step) = .empty,
    /// The visiting order of one settle round, kept between settles.
    order: std.ArrayList(u32) = .empty,
    /// The fault draws of a seeded run, apart from the schedule's, so the same seed
    /// without faults delivers in the same order; null when no fixture fails.
    faults: ?std.Random.DefaultPrng = null,
    /// The chance, in percent, that a fixture call fails, and again that one that
    /// answers is slow.
    fault_percent: u32 = 0,
    /// Faults drawn so far: failures and slow calls.
    injected: u32 = 0,
    /// Every fixture call that could fail, counted whether or not faults are on, and the
    /// count from which none fails (`--until`, runner.zig); null when faults never stop.
    draws: u64 = 0,
    fault_stop: ?u64 = null,
    /// Milliseconds fixture calls have waited in all, and the part the clock has not
    /// moved by yet (it moves before the next update).
    waited: i64 = 0,
    lag: i64 = 0,
    /// A test or property run of a program with a never (the runner sets it): the distinct
    /// values of each type a never reads with `T.all`, by its index among them
    /// (bytecode.Program.recorded_as), in the order the run first held them.
    records: bool = false,
    produced: std.AutoHashMapUnmanaged(u32, std.ArrayList(Value)) = .empty,
    /// Under `mo run`, the real platform: main is the root supervisor, `clock.now` is the
    /// wall clock frozen per update, a process crash is reported on stderr as it happens,
    /// and a run that goes on delivering is a server, not a livelock.
    server: ?*server_mod.Server = null,
    /// Under `mo run` with processes: each process's updates run on a fiber of its own on its
    /// scheduler's thread, a scheduler per core (turns.zig). Asks, settles, and the end of main go
    /// through it; with more than one scheduler `vm` and `running` are the lock holder's.
    turns: ?*turns_mod.Turns = null,
    /// The in-memory network every `Net.fixture()` of the run shares (net.zig).
    fixture: net_mod.Fixture = .{},
    /// The files of each `Fs.fixture()` in the run, which keep what the test writes.
    files: stdlib.FixtureFs = .{},
    /// What each `Out.fixture()` of the run was given, one text per call.
    outs: std.ArrayList(std.ArrayList([]const u8)) = .empty,
    /// Under `mo run`, every vm allocates in a region of its own, so a value that goes from
    /// one vm to another goes packed (Vm.pack): a message, a reply, and a process's start
    /// arguments and first state. After each update the process's region keeps only what
    /// its state reaches (settleRegion).
    packs: bool = false,
    /// Sends held in every outbox: while none is, no wait looks for one.
    held: usize = 0,
    /// Delayed sends not yet due, a heap by due time (step 24), and the count that orders them.
    later: std.ArrayList(Later) = .empty,
    later_sent: u64 = 0,
    /// main called exit and returned (step 29): no delayed send is kept, and nothing is waited for.
    exiting: bool = false,
    /// The loops the runtime owns: listeners served and connections read into processes.
    sources: sources_mod.Sources = .{},
    /// What the processes did, most recent last (events.zig, step 23).
    ring: events_mod.Ring = .{},
    /// The last crash reports, which the surface reads, kept apart from the ring (step 32).
    kept_crashes: events_mod.Crashes = .{},
    /// The process `mo run --surface` starts to serve the surface, which the surface does not list
    /// and the ring does not record (step 23): its index in `Program.processes`, or none.
    hidden_process: u32 = none,
    /// Under `mo run`, main's region, which the surface counts.
    main_region: ?*const @import("region.zig").Region = null,

    /// The fixed order: start order, every send delivered before the next statement, and
    /// a clock that does not move.
    pub fn init(vm: *Vm, seed: u64, test_name: []const u8) Sim {
        return .{ .gpa = vm.gpa, .vm = vm, .seed = seed, .test_name = test_name, .ring = .{ .gpa = vm.gpa }, .kept_crashes = .{ .gpa = vm.gpa } };
    }

    /// A seeded run: the same rules, with the scheduler's choices drawn from `seed`, and
    /// fixtures that fail at `fault_percent`.
    pub fn seeded(vm: *Vm, seed: u64, test_name: []const u8, fault_percent: u32) Sim {
        return .{
            .gpa = vm.gpa,
            .vm = vm,
            .seed = seed,
            .test_name = test_name,
            .schedule = .init(seed),
            .faults = if (fault_percent > 0) .init(seed ^ fault_stream) else null,
            .fault_percent = fault_percent,
            .ring = .{ .gpa = vm.gpa },
            .kept_crashes = .{ .gpa = vm.gpa },
        };
    }

    /// `v`, of checker type `t`, is held by a binding, a field, a message, or state: it and
    /// every value inside it of a type a never reads with `T.all` are kept once each.
    pub fn observe(sim: *Sim, v: Value, t: u32) Error!void {
        const p = sim.vm.program;
        const k = &p.checked;
        const r = k.pool.resolve(t);
        if (!p.may_hold[r]) return;
        // What the run keeps is a second holder: a later write in place must not reach it.
        sim.vm.disownIn(v);
        if (p.recorded_as[r] != none) try sim.keep(p.recorded_as[r], v);
        const ty = k.pool.get(r);
        switch (ty.tag) {
            .alias => try sim.observe(v, ty.b),
            .list => if (v == .list) for (v.list) |x| try sim.observe(x, ty.a),
            .set => if (v == .set) for (v.set.entries) |x| try sim.observe(x, ty.a),
            .map => if (v == .map) {
                // Keys and values alternate in a map's entries.
                var i: usize = 0;
                while (i + 1 < v.map.entries.len) : (i += 2) {
                    try sim.observe(v.map.entries[i], ty.a);
                    try sim.observe(v.map.entries[i + 1], ty.b);
                }
            },
            .option => if (v == .variant and v.variant.fields.len == 1) try sim.observe(v.variant.fields[0], ty.a),
            .result => if (v == .variant and v.variant.fields.len == 1) {
                try sim.observe(v.variant.fields[0], if (std.mem.eql(u8, v.variant.name, "Ok")) ty.a else ty.b);
            },
            .tuple => if (v == .tuple and v.tuple.len == ty.b) for (k.pool.elems(ty), v.tuple) |e, x| try sim.observe(x, e),
            .decl, .state, .message => {
                const d = k.decls[ty.a];
                switch (v) {
                    .record => |rec| try sim.observeFields(rec.fields, k.fields[d.fields.start..d.fields.end]),
                    .variant => |var_| for (k.variants[d.variants.start..d.variants.end]) |def| {
                        if (std.mem.eql(u8, def.name, var_.name)) break try sim.observeFields(var_.fields, k.fields[def.fields.start..def.fields.end]);
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    fn observeFields(sim: *Sim, values: []const Value, defs: []const @import("check.zig").Field) Error!void {
        if (values.len != defs.len) return;
        for (values, defs) |x, def| try sim.observe(x, def.type);
    }

    fn keep(sim: *Sim, index: u32, v: Value) Error!void {
        const kept = try sim.produced.getOrPut(sim.gpa, index);
        if (!kept.found_existing) kept.value_ptr.* = .empty;
        for (kept.value_ptr.items) |x| if (vm_mod.equal(x, v)) return;
        try kept.value_ptr.append(sim.gpa, v);
    }

    /// `T.all` in a never: every distinct value of recorded type `index` the run held.
    pub fn all(sim: *const Sim, index: u32) []const Value {
        return if (sim.produced.get(index)) |kept| kept.items else &.{};
    }

    /// Every never, over the values the run held; the first that is true crashes the run.
    pub fn checkNevers(sim: *Sim) Error!void {
        if (!sim.records) return;
        // What a never's own body holds is not the run's.
        sim.records = false;
        defer sim.records = true;
        for (sim.vm.program.nevers) |n| _ = try sim.vm.call(n.function, &.{});
    }

    /// A fixture call's fate in a seeded run with faults. With the run's chance it fails:
    /// half the time with `other` at once when the call has another way to fail (Missing
    /// for a call that names a path, Closed for a connection's), else Timeout after waiting
    /// its whole deadline. With the same chance a call that answers is slow, and waits up
    /// to its deadline. What calls wait moves the clock before the next update and counts
    /// against an ask in flight. Null: the call answers as the fixture does.
    pub fn fault(sim: *Sim, other: ?Fault, within: i64) ?Fault {
        const draw = sim.draws;
        sim.draws += 1;
        if (sim.fault_stop) |stop| if (draw >= stop) return null;
        const rng = if (sim.faults) |*r| r.random() else return null;
        if (rng.uintLessThan(u32, 100) < sim.fault_percent) {
            sim.injected += 1;
            if (other) |o| if (rng.boolean()) return o;
            sim.wait(within);
            return .timeout;
        }
        if (within > 0 and rng.uintLessThan(u32, 100) < sim.fault_percent) {
            sim.injected += 1;
            sim.wait(rng.intRangeAtMost(i64, 1, within));
        }
        return null;
    }

    /// A fixture call waited `ms`: the clock moves before the next update, and an ask in
    /// flight counts it.
    pub fn wait(sim: *Sim, ms: i64) void {
        sim.waited += ms;
        sim.lag += ms;
    }

    /// The clock deadlines are points on (step 22): under `mo run` the runtime's monotonic clock,
    /// and in a test the run's, which only fixture waits move.
    pub fn deadlineNow(sim: *const Sim) i64 {
        if (sim.turns) |t| return t.now();
        return sim.waited;
    }

    /// The events' clock, in microseconds (events.zig): under Mo.Server the awake clock, and in a
    /// test the run's own, `clock.now` and what fixture calls waited that it has not moved by yet.
    pub fn eventNow(sim: *const Sim) i64 {
        if (sim.server) |s| return s.monoUs();
        return (sim.now + sim.lag) * 1000;
    }

    /// An event, at the events' clock, naming the processes it is about as they are now.
    pub fn record(sim: *Sim, e: events_mod.Event) void {
        if (sim.ring.cap == 0) return;
        if (e.process != events_mod.nobody and e.process < sim.procs.items.len and sim.hidden(e.process)) return;
        var x = e;
        x.at = sim.eventNow();
        if (x.process != events_mod.nobody and x.process_name.len == 0) x.process_name = sim.nameOf(x.process);
        if (x.other != events_mod.nobody and x.other_name.len == 0) x.other_name = sim.nameOf(x.other);
        sim.ring.record(x);
    }

    /// A call that waits begins: the events' clock now, and the call the running update waits in.
    pub fn beginWait(sim: *Sim, call: []const u8) i64 {
        if (sim.running) |id| sim.procs.items[id].waiting = call;
        return sim.eventNow();
    }

    /// Process `id` serves the surface, which does not show it (step 23).
    pub fn hidden(sim: *const Sim, id: u32) bool {
        return sim.hidden_process != none and sim.procs.items[id].process == sim.hidden_process;
    }

    /// A call that waits, begun at `since` on the events' clock, gave `result`: its time counts
    /// toward the running update's waits, and a `Timeout` is an event. `target`: an ask's.
    pub fn waitedIn(sim: *Sim, call: []const u8, since: i64, result: Value, target: u32) void {
        const took: u64 = @intCast(@max(sim.eventNow() - since, 0));
        if (sim.running) |id| {
            const p = &sim.procs.items[id];
            p.waiting = "";
            p.waited_us += took;
            if (took >= p.longest_us) {
                p.longest_us = took;
                p.longest = call;
            }
        }
        if (isTimeout(result)) sim.record(.{ .kind = .timed_out, .process = sim.running orelse events_mod.nobody, .call = call, .other = target });
    }

    fn isTimeout(v: Value) bool {
        if (v != .variant or !std.mem.eql(u8, v.variant.name, "Error") or v.variant.fields.len != 1) return false;
        const e = v.variant.fields[0];
        return e == .variant and std.mem.eql(u8, e.variant.name, "Timeout");
    }

    /// `reply_by` in the running update.
    pub fn replyBy(sim: *const Sim) i64 {
        const id = sim.running orelse return sim.deadlineNow();
        return sim.procs.items[id].reply_by;
    }

    /// `reply_to` in the running update: the asker of the message it took (step 31). The value
    /// is the seq alone; the deadline stays with the asker, so an answer past it is dropped.
    pub fn replyTo(sim: *const Sim) u64 {
        return sim.procs.items[sim.running.?].reply_seq;
    }

    /// The running arm kept its asker: the commit answers nothing (step 31).
    pub fn deferReply(sim: *Sim) void {
        sim.procs.items[sim.running.?].deferring = true;
    }

    /// `reply.answer(v)`: the answer waits for the update's commit, as a send does. An answer
    /// to an ask this process does not hold, one it already answered or one whose asker is
    /// gone, is dropped.
    pub fn answerReply(sim: *Sim, seq: u64, value: Value) Error!void {
        const me = sim.running orelse return;
        const p = &sim.procs.items[me];
        if (std.mem.indexOfScalar(u64, p.kept.items, seq) == null) return;
        for (p.answers.items) |a| if (a.seq == seq) return;
        try p.answers.append(sim.gpa, .{ .seq = seq, .value = value });
    }

    /// An answer on its way to the asker of message `seq`: null is Down. Nothing waiting for it
    /// means its deadline passed and the asker was released with Timeout, so it is dropped
    /// (chapter 3, "What timeout means": the message still arrived exactly once).
    fn routeAnswer(sim: *Sim, seq: u64, value: ?Value) Error!void {
        if (sim.turns) |t| {
            if (!t.awaits(seq)) return;
            const parcel = if (value) |v| try sim.outgoing(v) else null;
            return t.answer(seq, if (parcel) |x| x.value else value, parcel);
        }
        if (!sim.waiting.contains(seq)) return;
        const packed_ = if (value) |v| try sim.outgoing(v) else null;
        const got: ?Answered = if (value) |v| .{ .value = if (packed_) |x| x.value else v, .parcel = packed_ } else null;
        try sim.answered.put(sim.gpa, seq, got);
    }

    /// Every ask `id` holds goes Down: its process crashed, restarted, or ended (step 31).
    fn downKept(sim: *Sim, id: u32) Error!void {
        const p = &sim.procs.items[id];
        if (p.kept.items.len == 0) return;
        const seqs = try sim.gpa.dupe(u64, p.kept.items);
        p.kept.clearRetainingCapacity();
        for (seqs) |seq| try sim.routeAnswer(seq, null);
    }

    /// `clock.now`, frozen when the running update began: under Mo.Server the wall clock, and in a
    /// test the simulator's, `Time.fixture()` moved by every fixture wait and delayed send the run
    /// has made and, under --sim, by the seed's ticks (step 28).
    pub fn clockNow(sim: *const Sim) i64 {
        if (sim.running) |id| return sim.procs.items[id].now;
        return if (sim.server) |s| s.now() else sim.now + sim.lag;
    }

    pub fn firstCrash(sim: *const Sim) ?contracts.Report {
        return if (sim.crashes.items.len > 0) sim.crashes.items[0] else null;
    }

    pub fn nameOf(sim: *const Sim, id: u32) []const u8 {
        return sim.vm.program.processes[sim.procs.items[id].process].name;
    }

    // ---- ending finished processes in a test (step 24)

    /// Under Mo.Sim, a test's processes that have finished and that nothing can reach end when the
    /// surface reads the processes (surface.zig), by the rule a sweep keeps under `mo run`
    /// (turns.zig, sweep): so a test sees a worker a registry forgot end. An ended id is not given
    /// to a later process, so a seed's ids stay the same every run.
    pub fn sweepEnded(sim: *Sim) Error!void {
        if (sim.turns != null) return;
        const gpa = std.heap.smp_allocator;
        const procs = sim.procs.items;
        var m: Marker = .{ .marks = try gpa.alloc(bool, procs.len) };
        defer gpa.free(m.marks);
        defer m.work.deinit(gpa);
        @memset(m.marks, false);
        // One vm runs the test and every update on its stack.
        for (sim.vm.handle_frames.items) |locals| try m.values(locals);
        for (procs) |p| {
            if (p.ended or finishedInTest(p)) continue;
            try m.values(p.args);
            if (p.up) try m.value(p.state);
            for (p.mailbox.items[p.head..]) |e| try m.value(e.message);
            for (p.outbox.items) |o| {
                try m.id(o.to);
                try m.value(o.message);
            }
        }
        for (sim.sources.list.items) |s| if (!s.done) try m.id(s.to);
        for (sim.later.items) |l| {
            try m.id(l.to);
            try m.value(l.message);
        }
        while (m.work.pop()) |id| {
            try m.values(procs[id].args);
            if (procs[id].up) try m.value(procs[id].state);
        }
        for (procs, 0..) |*p, id| {
            if (p.ended or !finishedInTest(p.*) or m.marks[id]) continue;
            sim.record(.{ .kind = .ended, .process = @intCast(id) });
            p.log.clearRetainingCapacity();
            p.mailbox.clearRetainingCapacity();
            p.head = 0;
            p.args = &.{};
            p.state = .none;
            p.up = false;
            p.ended = true;
        }
    }

    /// Began by a start call, nothing waiting for it, and no update of it on a stack.
    fn finishedInTest(p: Proc) bool {
        return p.supervisor == test_runner and !p.busy and p.queued() == 0;
    }

    /// The processes whose handles a sweep has found, and the found ones whose start arguments and
    /// state it has yet to read.
    const Marker = struct {
        marks: []bool,
        work: std.ArrayList(u32) = .empty,

        fn id(m: *Marker, to: u32) Error!void {
            if (to >= m.marks.len or m.marks[to]) return;
            m.marks[to] = true;
            try m.work.append(std.heap.smp_allocator, to);
        }

        fn values(m: *Marker, vs: []const Value) Error!void {
            for (vs) |v| try m.value(v);
        }

        /// Every handle inside `v`, as turns.zig's markValue finds them.
        fn value(m: *Marker, v: Value) Error!void {
            switch (v) {
                .handle => |to| try m.id(to),
                .tuple => |xs| try m.values(xs),
                .variant => |x| try m.values(x.fields),
                .record => |r| try m.values(r.fields),
                .list => |xs| try m.values(xs),
                .set => |s| try m.values(s.entries),
                .map => |s| try m.values(s.entries),
                else => {},
            }
        }
    };

    // ---- starting

    /// `Name.start(args)` in a test or main: the test runner or main supervises it as the first
    /// child line that names the process says, its `restart:` included (step 29: a `:never` child
    /// started this way was restarted), and with :always when no line names it.
    pub fn start(sim: *Sim, process: u32, args: []const Value) Error!u32 {
        // Under `mo run`, main starting processes faster than a statement settles them hands
        // out their turns first, so the ones that finished end (turns.zig, sweep).
        if (sim.turns) |t| if (t.holder() == turns_mod.main_turn and t.quiet >= t.sweep_at) try t.settle(sim);
        return sim.startUnder(process, args, test_runner, try sim.lineFor(process));
    }

    fn lineFor(sim: *Sim, process: u32) Error!Policy {
        for (sim.vm.program.supervisors, 0..) |s, line| for (s.children) |c| {
            if (c.process != process) continue;
            const max = if (c.max_restarts == none) default_max_restarts else c.max_restarts;
            return .{ .restart = c.restart, .max_restarts = max, .window_ms = try sim.window(c), .line = @intCast(line) };
        };
        return .{ .restart = .always, .max_restarts = default_max_restarts, .window_ms = default_window_ms };
    }

    /// Starts supervisors[index]: each child in order, with the arguments its line passes.
    /// Gives the children, in child order.
    pub fn startSupervisor(sim: *Sim, index: u32, args: []const Value) Error![]const u32 {
        const s = sim.vm.program.supervisors[index];
        const sid: u32 = @intCast(sim.supervisors.items.len);
        try sim.supervisors.append(sim.gpa, .{ .index = index });
        const ids = try sim.gpa.alloc(u32, s.children.len);
        for (s.children, ids) |c, *id| {
            const child_args = (try sim.vm.call(c.args, args)).tuple;
            const max = if (c.max_restarts == none) default_max_restarts else c.max_restarts;
            id.* = try sim.startUnder(c.process, child_args, sid, .{ .restart = c.restart, .max_restarts = max, .window_ms = try sim.window(c), .line = index });
        }
        return ids;
    }

    fn window(sim: *Sim, c: bytecode.Child) Error!i64 {
        if (c.per == none) return default_window_ms;
        return (try sim.vm.call(c.per, &.{})).duration;
    }

    /// A state that cannot be built crashes whoever called start: the process never began.
    fn startUnder(sim: *Sim, process: u32, args: []const Value, supervisor: u32, policy: Policy) Error!u32 {
        const state = try sim.vm.call(sim.vm.program.processes[process].init, args);
        // Under `mo run` the process is placed on a scheduler and takes the id of the last process that
        // ended there, if one waits (turns.zig, step 30).
        const placing = if (sim.turns) |t| t.place() else null;
        const id: u32 = if (placing) |pl| pl.id orelse @intCast(sim.procs.items.len) else @intCast(sim.procs.items.len);
        var proc: Proc = .{ .process = process, .args = args, .state = state, .supervisor = supervisor, .policy = policy };
        if (id < sim.procs.items.len) {
            // An ended process's lists keep their room for the one that takes its id.
            const old = &sim.procs.items[id];
            inline for (.{ "mailbox", "log", "log_parcels", "restarts", "outbox", "emits" }) |list| {
                @field(proc, list) = @field(old, list);
                @field(proc, list).clearRetainingCapacity();
            }
        }
        if (sim.packs) {
            // Packed together, what the state shares with the arguments is copied once.
            const both = try vm_mod.rawAlloc(sim.vm.heap, Value, args.len + 1);
            @memcpy(both[0..args.len], args);
            both[args.len] = state;
            const parcel = try sim.vm.pack(.{ .tuple = both });
            proc.start = parcel;
            proc.args = parcel.value.tuple[0..args.len];
            proc.state = parcel.value.tuple[args.len];
        }
        if (id < sim.procs.items.len) sim.procs.items[id] = proc else try sim.procs.append(sim.gpa, proc);
        if (sim.turns) |t| try t.placed(id, placing.?.sched, supervisor == test_runner);
        // Its placement, in its start (step 30).
        sim.record(.{ .kind = .started, .process = id, .scheduler = if (placing) |pl| pl.sched else 0 });
        return id;
    }

    /// A message on its way out of this vm: packed under `mo run`.
    fn outgoing(sim: *Sim, message: Value) Error!?*Parcel {
        return if (sim.packs) try sim.vm.pack(message) else null;
    }

    // ---- messages

    /// A message that will not arrive (step 29): its target is down, or the program exited while it
    /// was delayed. A `Dropped` event names the sender (`test_runner` for main or a test), the
    /// target, the message, and why.
    fn dropped(sim: *Sim, from: u32, to: u32, message: Value, why: []const u8) void {
        sim.record(.{
            .kind = .dropped,
            .process = to,
            .other = if (from == test_runner) events_mod.nobody else from,
            .message = if (message == .variant) message.variant.name else "",
            .name = why,
        });
    }

    /// `h.send(message)`: never blocks. From inside an update the message waits in the
    /// sender's outbox until the update commits. A target that is down drops it, with an event.
    pub fn send(sim: *Sim, to: u32, message: Value) Error!void {
        if (!sim.procs.items[to].up) return sim.dropped(sim.running orelse test_runner, to, message, "down");
        try sim.roomFor(to, message);
        const parcel = try sim.outgoing(message);
        const sent = if (parcel) |p| p.value else message;
        if (sim.running) |from| {
            try sim.procs.items[from].outbox.append(sim.gpa, .{ .to = to, .message = sent, .parcel = parcel });
            sim.held += 1;
        } else _ = try sim.enqueue(test_runner, to, sent, parcel);
    }

    /// `h.send(message, delay: d)` (step 24): the message goes in `to`'s mailbox no earlier than `d`
    /// after the sending update ends, on the runtime's clock; from a test or main, `d` after now. It
    /// waits for its time outside the mailbox, so a later plain send may arrive first. A crash drops
    /// it with the update's other sends, and a target that is down when it is due drops it.
    pub fn sendLater(sim: *Sim, to: u32, message: Value, delay: i64) Error!void {
        if (delay <= 0) return sim.send(to, message);
        if (!sim.procs.items[to].up) return sim.dropped(sim.running orelse test_runner, to, message, "down");
        const parcel = try sim.outgoing(message);
        const sent = if (parcel) |p| p.value else message;
        if (sim.running) |from| {
            try sim.procs.items[from].outbox.append(sim.gpa, .{ .to = to, .message = sent, .parcel = parcel, .delay = delay });
            sim.held += 1;
        } else try sim.pushLater(test_runner, to, sent, parcel, sim.deadlineNow() + delay);
    }

    /// main called exit and returned (step 29): every delayed send still pending is dropped with an
    /// event, and one sent from here on is dropped as it is sent, so the program ends at once.
    pub fn exitNow(sim: *Sim) void {
        sim.exiting = true;
        for (sim.later.items) |l| {
            sim.dropped(l.from, l.to, l.message, "exited");
            if (l.parcel) |x| x.free();
        }
        sim.later.clearRetainingCapacity();
    }

    fn pushLater(sim: *Sim, from: u32, to: u32, message: Value, parcel: ?*Parcel, at: i64) Error!void {
        if (sim.exiting) {
            sim.dropped(from, to, message, "exited");
            if (parcel) |x| x.free();
            return;
        }
        const gpa = std.heap.smp_allocator;
        try sim.later.append(gpa, .{ .at = at, .order = sim.later_sent, .from = from, .to = to, .message = message, .parcel = parcel });
        sim.later_sent += 1;
        const items = sim.later.items;
        var i = items.len - 1;
        while (i > 0) {
            const parent = (i - 1) / 2;
            if (!sooner(items[i], items[parent])) break;
            std.mem.swap(Later, &items[i], &items[parent]);
            i = parent;
        }
        // A new earliest: the scheduler that moves them looks again (turns.zig).
        if (i == 0) if (sim.turns) |t| t.laterChanged();
    }

    fn sooner(a: Later, b: Later) bool {
        return a.at < b.at or (a.at == b.at and a.order < b.order);
    }

    fn popLater(sim: *Sim) Later {
        const items = sim.later.items;
        const first = items[0];
        const last = sim.later.pop().?;
        if (sim.later.items.len == 0) return first;
        const heap = sim.later.items;
        heap[0] = last;
        var i: usize = 0;
        while (true) {
            const l = 2 * i + 1;
            const r = l + 1;
            var least = i;
            if (l < heap.len and sooner(heap[l], heap[least])) least = l;
            if (r < heap.len and sooner(heap[r], heap[least])) least = r;
            if (least == i) break;
            std.mem.swap(Later, &heap[i], &heap[least]);
            i = least;
        }
        return first;
    }

    /// When the earliest delayed send is due, on the runtime's clock.
    pub fn nextLater(sim: *const Sim) ?i64 {
        return if (sim.later.items.len > 0) sim.later.items[0].at else null;
    }

    /// Every delayed send whose time has come goes in its target's mailbox, in the order they were
    /// due; one to a target that is down, or whose mailbox is full, is dropped, and a full mailbox is
    /// an `Overflowed` event naming the sender, who is no longer in the update that sent it. True
    /// when one went in.
    pub fn dueLater(sim: *Sim) Error!bool {
        var moved = false;
        while (sim.later.items.len > 0 and sim.later.items[0].at <= sim.deadlineNow()) {
            const l = sim.popLater();
            const target = sim.procs.items[l.to];
            if (!target.up or target.ended) {
                sim.dropped(l.from, l.to, l.message, "down");
                if (l.parcel) |x| x.free();
                continue;
            }
            if (target.queued() >= sim.vm.program.processes[target.process].mailbox) {
                sim.record(.{ .kind = .overflowed, .process = l.to, .other = if (l.from == test_runner) events_mod.nobody else l.from });
                if (l.parcel) |x| x.free();
                continue;
            }
            _ = try sim.enqueue(l.from, l.to, l.message, l.parcel);
            moved = true;
        }
        return moved;
    }

    /// `h.ask(message, within: d)`: the target's waiting messages run, then this one, and
    /// the reply is the value of its arm. `Timeout` when the target's fixtures are slower
    /// than `d`, or its fixture calls waited longer than `d` while it answered; `Down` when
    /// the target is down or crashed before replying. A Timeout's message still arrives.
    pub fn ask(sim: *Sim, to: u32, message: Value, within: i64) Error!Value {
        defer sim.endAsk();
        try sim.askOn(to);
        const since = sim.beginWait("ask");
        const reply = if (sim.turns) |t| try t.ask(sim, to, message, within) else try sim.askInline(to, message, within);
        sim.waitedIn("ask", since, reply, to);
        try sim.checkDoomed();
        return reply;
    }

    fn askInline(sim: *Sim, to: u32, message: Value, within: i64) Error!Value {
        if (!sim.procs.items[to].up) return sim.askError("Down");
        // A target whose update is on the stack is waiting on this very call: the ask waited its whole
        // deadline, and simulated time passed with it (step 29).
        if (sim.procs.items[to].busy) {
            sim.wait(@max(within, 0));
            return sim.askError("Timeout");
        }
        const waited = sim.waited;
        // Delayed sends whose time has come are in their mailboxes before this message (step 24).
        _ = try sim.dueLater();
        try sim.roomFor(to, message);
        const seq = try sim.enqueue(sim.running orelse test_runner, to, message, null);
        const target = &sim.procs.items[to];
        target.mailbox.items[target.mailbox.items.len - 1].deadline = waited + within;
        // The surface holds its deliveries (step 23): the message waits, and the ask is Timeout.
        if (target.paused) {
            sim.wait(@max(within, 0));
            return sim.askError("Timeout");
        }
        // Under faults the seed decides how long the message waits to be taken, so a target that
        // reads reply_by may find nothing left of it (step 22).
        const p0 = sim.vm.program.processes[target.process];
        if (p0.reads_reply_by or p0.reads_reply_to) _ = sim.fault(null, within);
        var delivered: u32 = 0;
        // Set once the arm that took the message kept the asker instead of answering it (step 31):
        // from then on the ask waits for an `answer` from a later update, as it would under mo run.
        var kept = false;
        defer if (kept) {
            if (sim.answered.fetchRemove(seq)) |kv| if (kv.value) |got| if (got.parcel) |x| x.free();
            _ = sim.waiting.remove(seq);
        };
        const reply = while (true) {
            if (kept) {
                if (sim.answered.fetchRemove(seq)) |kv| {
                    const got = kv.value orelse return sim.askError("Down");
                    if (got.parcel) |x| {
                        defer x.free();
                        break try sim.vm.unpack(x);
                    }
                    break got.value;
                }
                if (!sim.procs.items[to].up) return sim.askError("Down");
                if (sim.waited - waited > within) return sim.askError("Timeout");
                // Nothing left to run: simulated time moves to the next delayed send, which is
                // what a flush on a timer is, and the ask times out when that is past its deadline.
                if (!try sim.deliverRound(&delivered)) {
                    const at = sim.nextLater() orelse return sim.askError("Timeout");
                    const ahead = @max(at - sim.deadlineNow(), 0);
                    if (sim.waited - waited + ahead > within) return sim.askError("Timeout");
                    sim.wait(ahead);
                }
                continue;
            }
            // While a test's ask waits, every other process takes a message too, a round at a time
            // in start order or the seed's, so a test polling one process starves none (step 24).
            // An update's ask delivers only its target's, as before.
            if (sim.running == null) try sim.othersRound(to, &delivered);
            const p = &sim.procs.items[to];
            // A restart empties the mailbox, this message with it.
            if (!p.up or p.queued() == 0 or p.mailbox.items[p.head].seq > seq) return sim.askError("Down");
            const d = try sim.deliver(to);
            if (d.seq != seq) continue;
            if (!d.deferred) break d.reply orelse return sim.askError("Down");
            kept = true;
            try sim.waiting.put(sim.gpa, seq, {});
        };
        // A fixture call's wait moves the clock (step 22): the ask is Timeout once the target's waits
        // pass its deadline, or when its slowest fixture is slower than it. A target whose calls
        // wait on reply_by never passes it, since none of them waits longer than what remains.
        if (sim.delayOf(to) > within or sim.waited - waited > within) return sim.askError("Timeout");
        return sim.vm.variant("Ok", &.{reply});
    }

    /// Between two statements of a test: delivers every waiting message. A seeded run
    /// may leave them waiting until a later statement, an `ask`, or the test's end.
    pub fn settle(sim: *Sim) Error!void {
        if (sim.turns) |t| return t.settle(sim);
        if (sim.schedule) |*rng| if (rng.random().boolean()) return;
        return sim.drain(false);
    }

    /// The test's body is done: every waiting message is delivered, whatever the seed;
    /// then every never is checked against what the run held.
    pub fn finish(sim: *Sim) Error!void {
        if (sim.turns) |t| return t.finish(sim);
        try sim.drain(true);
        try sim.checkNevers();
    }

    /// Delivers waiting messages, one per process per round, until every mailbox is
    /// empty. A round visits processes in start order, or in an order the seed shuffles,
    /// so no waiting process is passed over for more than one round.
    /// `to_later`: at a test's end, simulated time passes to each delayed send in turn once nothing
    /// else waits (step 24); between two statements it does not, so time moves to a delayed send only
    /// while a test waits in a fixture call or an ask (step 29).
    fn drain(sim: *Sim, to_later: bool) Error!void {
        var delivered: u32 = 0;
        while (true) {
            while (try sim.round(&sim.order, &delivered)) {}
            if (!to_later) return;
            const at = sim.nextLater() orelse return;
            sim.wait(@max(at - sim.deadlineNow(), 0));
        }
    }

    /// One round of delivering waiting messages, for a fixture call that waits for a process
    /// to answer it (http.zig, `send`): true when it delivered one. `delivered` counts the
    /// messages across the call's rounds, which end at settle_limit as a settle's do.
    pub fn deliverRound(sim: *Sim, delivered: *u32) Error!bool {
        // The call may be inside an update a settle delivered: the round keeps its own order.
        var order: std.ArrayList(u32) = .empty;
        defer order.deinit(sim.gpa);
        return sim.round(&order, delivered);
    }

    /// One message to each waiting process that is up and not on the stack, in start order
    /// or in an order the seed shuffles; true when one was delivered.
    fn round(sim: *Sim, order: *std.ArrayList(u32), delivered: *u32) Error!bool {
        // What the runtime's loops took goes in first (sources.zig); under mo run, turns.zig.
        var progressed = if (sim.server == null) try sources_mod.pumpFixture(sim) else false;
        // Delayed sends whose time has come go in next (step 24).
        if (sim.turns == null and try sim.dueLater()) progressed = true;
        order.clearRetainingCapacity();
        for (0..sim.procs.items.len) |id| try order.append(sim.gpa, @intCast(id));
        if (sim.schedule) |*rng| rng.random().shuffle(u32, order.items);
        // A process an update starts waits for the next round.
        for (order.items) |id| {
            const p = &sim.procs.items[id];
            if (!p.up or p.busy or p.paused or p.queued() == 0) continue;
            _ = try sim.deliver(id);
            progressed = true;
            delivered.* += 1;
            if (delivered.* == settle_limit and sim.server == null) {
                sim.vm.report = .{ .kind = .other, .clause = "the processes did not settle: a million messages delivered and mailboxes still waiting", .within = sim.test_name, .at = 0 };
                return error.Crash;
            }
        }
        return progressed;
    }

    /// One message to each waiting process but `skip` that is up and not on a stack, in start order
    /// or an order the seed shuffles, after the delayed sends now due: the round a test's ask gives
    /// the other processes before its target's next message (step 24). The runtime's loops are not
    /// pumped here: the round delivers what already waits.
    fn othersRound(sim: *Sim, skip: u32, delivered: *u32) Error!void {
        _ = try sim.dueLater();
        var order: std.ArrayList(u32) = .empty;
        defer order.deinit(sim.gpa);
        for (0..sim.procs.items.len) |id| if (id != skip) try order.append(sim.gpa, @intCast(id));
        if (sim.schedule) |*rng| rng.random().shuffle(u32, order.items);
        for (order.items) |id| {
            const p = &sim.procs.items[id];
            if (!p.up or p.busy or p.paused or p.queued() == 0) continue;
            _ = try sim.deliver(id);
            delivered.* += 1;
            if (delivered.* == settle_limit) {
                sim.vm.report = .{ .kind = .other, .clause = "the processes did not settle while an ask waited: a million messages delivered and mailboxes still waiting", .within = sim.test_name, .at = 0 };
                return error.Crash;
            }
        }
    }

    /// `events.emit(e)`: inside an update it waits for the commit, like a send.
    pub fn emit(sim: *Sim, event: Value) Error!void {
        if (sim.running) |id| {
            try sim.procs.items[id].emits.append(sim.gpa, event);
        } else try sim.events.append(sim.gpa, event);
    }

    /// Puts a message in `to`'s mailbox, which takes its parcel.
    pub fn enqueue(sim: *Sim, from: u32, to: u32, message: Value, parcel: ?*Parcel) Error!u64 {
        const seq = sim.next_seq;
        sim.next_seq += 1;
        try sim.procs.items[to].mailbox.append(sim.gpa, .{ .message = message, .seq = seq, .parcel = parcel });
        if (sim.turns) |t| try t.markRunnable(to);
        if (sim.schedule != null) try sim.trace.append(sim.gpa, .{ .from = from, .to = to, .message = message, .took = false });
        return seq;
    }

    /// A mailbox at its bound crashes the sender, and the report names both (d33).
    pub fn roomFor(sim: *Sim, to: u32, message: Value) Error!void {
        const target = sim.procs.items[to];
        var waiting = target.queued();
        if (sim.running) |from| {
            for (sim.procs.items[from].outbox.items) |o| waiting += @intFromBool(o.to == to and o.delay == 0);
        }
        const bound = sim.vm.program.processes[target.process].mailbox;
        if (waiting < bound) return;
        const from_name = if (sim.running) |from| sim.nameOf(from) else if (sim.server != null) "main" else try std.fmt.allocPrint(sim.gpa, "the test \"{s}\"", .{sim.test_name});
        sim.record(.{ .kind = .overflowed, .process = to, .other = sim.running orelse events_mod.nobody });
        const values = try sim.gpa.alloc(contracts.Involved, 1);
        values[0] = .{ .name = "message", .value = try sim.vm.render(message) };
        sim.vm.report = .{
            .kind = .mailbox,
            .clause = try std.fmt.allocPrint(sim.gpa, "{s} sent to {s}, whose mailbox is full at its bound of {d}", .{ from_name, sim.nameOf(to), bound }),
            .within = from_name,
            .at = 0,
            .values = values,
        };
        return error.Crash;
    }

    pub fn askError(sim: *Sim, name: []const u8) Error!Value {
        return sim.vm.variant("Error", &.{try sim.vm.variant(name, &.{})});
    }

    /// The slowest fixture the process was started with.
    fn delayOf(sim: *const Sim, id: u32) i64 {
        var delay: i64 = 0;
        for (sim.procs.items[id].args) |a| if (a == .cap) {
            delay = @max(delay, a.cap.delay);
        };
        return delay;
    }

    // ---- one message

    /// `deferred`: the arm kept the asker, so no reply came with the commit (step 31).
    pub const Delivered = struct { seq: u64, reply: ?Value, deferred: bool = false };

    /// Runs the next message in the mailbox of `id` as one transaction. A null reply
    /// means the process crashed on it.
    pub fn deliver(sim: *Sim, id: u32) Error!Delivered {
        const vm = sim.vm;
        var p = &sim.procs.items[id];
        const entry = p.mailbox.items[p.head];
        p.head += 1;
        if (p.head == p.mailbox.items.len) {
            p.mailbox.clearRetainingCapacity();
            p.head = 0;
        } else if (p.head >= 64 and 2 * p.head >= p.mailbox.items.len) {
            // A mailbox that never empties does not grow: what was taken is dropped.
            const waiting = p.mailbox.items.len - p.head;
            std.mem.copyForwards(Entry, p.mailbox.items[0..waiting], p.mailbox.items[p.head..]);
            p.mailbox.shrinkRetainingCapacity(waiting);
            p.head = 0;
        }
        try sim.logMessage(p, entry);
        p.reply_by = entry.deadline orelse sim.deadlineNow();
        p.reply_seq = entry.seq;
        p.deferring = false;
        if (sim.schedule) |*rng| {
            sim.now += sim.lag + rng.random().intRangeAtMost(i64, 0, max_tick_ms);
            sim.lag = 0;
            try sim.trace.append(sim.gpa, .{ .from = id, .to = id, .message = entry.message, .took = true });
        }
        p.now = if (sim.server) |s| s.now() else sim.now + sim.lag;
        // The clock's move before the update is not the update's time.
        const since = sim.eventNow();
        p.waited_us = 0;
        p.longest_us = 0;
        p.longest = "";
        const before = p.state;
        const base = vm.stack.items.len;
        // Under `mo run`, everything the update allocates is past this mark: the message
        // copied out of its parcel first. What it overwrites below the mark is undone on a
        // crash, and not overwritten at all when an invariant reads old(state).
        const mark = vm.mark();
        const regioned = vm.region != null;
        const message = if (entry.parcel) |parcel| try vm.unpack(parcel) else entry.message;
        // Without a region nothing tells an older buffer from a newer one: every write is kept
        // for a crash, and an invariant that reads old(state) sees nothing written in place.
        const reads_old = vm.program.processes[p.process].reads_old;
        if (regioned) {
            vm.undo_mark = mark;
            vm.frozen_below = if (reads_old) mark else 0;
        } else {
            vm.undo_mark = std.math.maxInt(usize);
            vm.frozen_below = if (reads_old) std.math.maxInt(usize) else 0;
        }
        defer {
            vm.undo_mark = 0;
            vm.frozen_below = 0;
        }
        const outer = sim.running;
        sim.running = id;
        p.busy = true;
        // Under `mo run` the process stays busy until its region has settled, which another scheduler
        // must not read in the middle of (turns.zig, step 30).
        defer if (sim.turns != null) {
            sim.procs.items[id].busy = false;
        };
        const result = sim.update(id, message, before);
        // An update may start processes, so the pointer is taken again.
        p = &sim.procs.items[id];
        if (sim.turns == null) p.busy = false;
        sim.running = outer;
        const after = result catch |err| switch (err) {
            error.Crash => {
                vm.stack.shrinkRetainingCapacity(base);
                vm.rollBack();
                for (p.outbox.items) |o| if (o.parcel) |x| x.free();
                sim.held -= p.outbox.items.len;
                p.outbox.clearRetainingCapacity();
                p.emits.clearRetainingCapacity();
                p.wait = null;
                p.asking = none;
                p.doomed = null;
                p.answers.clearRetainingCapacity();
                if (sim.gave_up) return error.Crash;
                try sim.crashed(id, before);
                try sim.routeAnswer(entry.seq, null);
                if (regioned) try sim.settleRegion(id, mark);
                return .{ .seq = entry.seq, .reply = null };
            },
            else => return err,
        };
        vm.undo.clearRetainingCapacity();
        p.state = after.tuple[1];
        sim.record(.{
            .kind = .updated,
            .process = id,
            .name = if (entry.message == .variant) entry.message.variant.name else "",
            .took_us = @intCast(@max(sim.eventNow() - since, 0)),
            .waited_us = p.waited_us,
            .call = p.longest,
        });
        sim.held -= p.outbox.items.len;
        for (p.outbox.items) |o| {
            if (!sim.procs.items[o.to].up) {
                sim.dropped(id, o.to, o.message, "down");
                if (o.parcel) |x| x.free();
            } else if (o.delay > 0) {
                // No earlier than its delay after the update ends (step 24).
                try sim.pushLater(id, o.to, o.message, o.parcel, sim.deadlineNow() + o.delay);
            } else _ = try sim.enqueue(id, o.to, o.message, o.parcel);
        }
        p.outbox.clearRetainingCapacity();
        try sim.events.appendSlice(sim.gpa, p.emits.items);
        p.emits.clearRetainingCapacity();
        const reply = after.tuple[0];
        // An answer the update made commits with it, and is dropped when nothing waits for it.
        for (p.answers.items) |a| {
            const at = std.mem.indexOfScalar(u64, p.kept.items, a.seq);
            if (at) |k| _ = p.kept.orderedRemove(k);
            try sim.routeAnswer(a.seq, a.value);
        }
        p.answers.clearRetainingCapacity();
        // The arm kept its asker instead of answering: the process holds the ask until it
        // answers it, crashes, or restarts (step 31).
        const deferring = p.deferring;
        if (deferring) {
            try p.kept.append(sim.gpa, entry.seq);
        } else try sim.routeAnswer(entry.seq, reply);
        if (regioned) try sim.settleRegion(id, mark);
        return .{ .seq = entry.seq, .reply = reply, .deferred = deferring };
    }

    /// After an update under `mo run`: what it allocated that the new state does not reach
    /// is freed, message, reply, and outgoing messages included, since those left packed.
    /// Once the region holds more than twice what its last full compaction kept, it is
    /// compacted whole, which frees what earlier updates overwrote.
    fn settleRegion(sim: *Sim, id: u32, mark: usize) Error!void {
        const vm = sim.vm;
        var roots = [1]Value{sim.procs.items[id].state};
        // Only this process's region and its scheduler's scratch region are touched, so with more than
        // one scheduler the compaction runs without the runtime's lock (turns.zig, step 30).
        if (sim.turns) |t| {
            const held = t.beginMo();
            defer t.endMo(held);
            try compactRegion(vm, mark, &roots, true);
        } else try compactRegion(vm, mark, &roots, false);
        sim.procs.items[id].state = roots[0];
    }

    fn compactRegion(vm: *Vm, mark: usize, roots: *[1]Value, processes: bool) Error!void {
        const r = vm.region.?;
        if (r.top > mark) try vm.compact(mark, roots);
        if (r.top - r.base > 2 * vm.full_kept + full_budget) {
            try vm.compact(r.base, roots);
            vm.full_kept = r.top - r.base;
            // A process region keeps what its state reaches in a quarter of its reservation at
            // most; past that it moves into one four times as large (step 21). main's never moves.
            if (processes and 4 * vm.full_kept > r.end - r.base) {
                const old_size = r.end - r.base;
                const want = @min(4 * old_size, turns_mod.big_region);
                const size = if (turns_mod.regions_reserved.load(.monotonic) + want > turns_mod.region_budget + old_size) @min(want, max_region) else want;
                try vm.relocate(size, roots);
                const new_size = r.end - r.base;
                if (new_size >= old_size) {
                    _ = turns_mod.regions_reserved.fetchAdd(new_size - old_size, .monotonic);
                } else _ = turns_mod.regions_reserved.fetchSub(old_size - new_size, .monotonic);
                vm.full_kept = r.top - r.base;
            }
        }
        // What the update freed, in its process's region and in the scratch region a compaction copied
        // through, goes back to the system beyond a MiB of each (step 28).
        const slack = @import("region.zig").Region.release_keep;
        const reg = vm.region.?;
        if (reg.high > reg.top + 4 * slack) reg.releasePast(reg.top + slack);
        if (vm.scratch) |s| if (@max(s.high, s.top) > s.base + 4 * slack) s.releasePast(s.base + slack);
    }

    /// The message a process takes goes in its log; under `mo run` the log keeps the last
    /// `log_kept`, each in its parcel, and frees the rest.
    fn logMessage(sim: *Sim, p: *Proc, entry: Entry) Error!void {
        if (entry.parcel) |parcel| {
            if (p.log_parcels.items.len == log_kept) {
                p.log_parcels.orderedRemove(0).free();
                _ = p.log.orderedRemove(0);
            }
            try p.log_parcels.append(sim.gpa, parcel);
        }
        try p.log.append(sim.gpa, entry.message);
    }

    /// One update, then every invariant against the state before it. Gives (reply, state).
    fn update(sim: *Sim, id: u32, message: Value, before: Value) Error!Value {
        const vm = sim.vm;
        const proc = sim.procs.items[id];
        const p = vm.program.processes[proc.process];
        const n = proc.args.len;
        const args = try vm_mod.rawAlloc(vm.heap, Value, n + 2);
        @memcpy(args[0..n], proc.args);
        args[n] = before;
        args[n + 1] = message;
        // The update's own code: with more than one scheduler it runs without the runtime's lock, which
        // every instruction and row that reaches the runtime takes again (turns.zig, step 30).
        const held = if (sim.turns) |t| t.beginMo() else turns_mod.Held{};
        defer if (sim.turns) |t| t.endMo(held);
        const out = try vm.call(p.update, args);
        args[n] = out.tuple[1];
        args[n + 1] = before;
        for (p.invariants) |inv| {
            if ((try vm.call(inv.function, args)).bool) continue;
            const c = vm.program.clauses[inv.clause];
            const values = try vm.reportGpa().alloc(contracts.Involved, 1);
            values[0] = .{ .name = "state", .value = try vm.renderReport(out.tuple[1]) };
            vm.report = .{ .kind = .invariant, .clause = c.text, .within = c.within, .at = c.at, .values = values };
            return error.Crash;
        }
        return out;
    }

    // ---- held sends (step 19)

    /// The running update is about to wait in `w.call` on a peer. When that update, or one
    /// waiting on it through asks, holds a send to a process started with a connection this
    /// wait can hear from only through that process, the wait could end only after the update
    /// does, since its sends are held until then: the update that holds the send crashes, at
    /// once when it is this one, else when its ask returns.
    pub fn waitOn(sim: *Sim, w: Wait) Error!void {
        const me = sim.running orelse return;
        sim.procs.items[me].wait = w;
        if (sim.held == 0) return;
        const found = try sim.heldFor(me, w) orelse return;
        const report = try sim.heldReport(found, me, w);
        if (found.holder != me) return sim.doom(found.holder, report);
        sim.vm.report = report;
        return error.Crash;
    }

    pub fn endWait(sim: *Sim) void {
        if (sim.running) |me| sim.procs.items[me].wait = null;
    }

    /// The running update is about to wait in an ask to `to`. Followed through the asks it waits
    /// in, when the target waits on a peer that a send this update, or one waiting on it, holds
    /// is what it hears from, the same holds as for waitOn.
    fn askOn(sim: *Sim, to: u32) Error!void {
        const me = sim.running orelse return;
        sim.procs.items[me].asking = to;
        if (sim.held == 0) return;
        var x = to;
        const w = for (0..sim.procs.items.len) |_| {
            const q = sim.procs.items[x];
            if (!q.busy) return;
            if (q.wait) |w| break w;
            if (q.asking == none) return;
            x = q.asking;
        } else return;
        const found = try sim.heldFor(x, w) orelse return;
        // The waiter's own send was found when its wait began.
        if (found.holder == x) return;
        const report = try sim.heldReport(found, x, w);
        if (found.holder != me) return sim.doom(found.holder, report);
        sim.vm.report = report;
        return error.Crash;
    }

    fn endAsk(sim: *Sim) void {
        if (sim.running) |me| sim.procs.items[me].asking = none;
    }

    /// The first send, of `waiter`'s update and then of each update waiting on it through asks,
    /// to a process started with a connection a wait on `w` hears from only through it.
    fn heldFor(sim: *Sim, waiter: u32, w: Wait) Error!?Held {
        const gpa = std.heap.smp_allocator;
        var queue: std.ArrayList(u32) = .empty;
        defer queue.deinit(gpa);
        try queue.append(gpa, waiter);
        var i: usize = 0;
        while (i < queue.items.len) : (i += 1) {
            const x = queue.items[i];
            for (sim.procs.items[x].outbox.items) |o| {
                if (sim.ties(o.to, w)) return .{ .holder = x, .to = o.to, .message = o.message };
            }
            for (sim.procs.items, 0..) |p, id| {
                if (!p.busy or p.asking != x or std.mem.indexOfScalar(u32, queue.items, @intCast(id)) != null) continue;
                try queue.append(gpa, @intCast(id));
            }
        }
        return null;
    }

    /// Process `to` was started with a connection a wait on `w` hears from only through it: one
    /// still open that the listener `w` names accepted, or the connection `w` names. An
    /// exchange counts while it is unanswered.
    fn ties(sim: *const Sim, to: u32, w: Wait) bool {
        for (sim.procs.items[to].args) |a| {
            if (a != .cap) continue;
            const conn = switch (a.cap.kind) {
                .conn => a.cap.handle,
                .exchange => sim.unanswered(a.cap.handle) orelse continue,
                else => continue,
            };
            const open, const from = sim.connection(conn);
            if (open and (if (w.listener) from == w.handle else conn == w.handle)) return true;
        }
        return false;
    }

    fn unanswered(sim: *const Sim, exchange: u32) ?u32 {
        const e = if (sim.server) |s| s.sockets.exchanges.items[exchange] else sim.fixture.exchanges.items[exchange];
        return if (e.answered) null else e.conn;
    }

    /// Whether connection `h` is open, and the listener that accepted it.
    fn connection(sim: *const Sim, h: u32) struct { bool, u32 } {
        if (sim.server) |s| {
            const c = s.sockets.conns.items[h];
            return .{ !c.closed, c.listener };
        }
        const c = sim.fixture.conns.items[h];
        return .{ !c.closed, c.listener };
    }

    fn heldReport(sim: *Sim, h: Held, waiter: u32, w: Wait) Error!contracts.Report {
        const holder = sim.nameOf(h.holder);
        const target = sim.nameOf(h.to);
        const call = if (h.holder == waiter) w.call else try std.fmt.allocPrint(sim.gpa, "ask, and {s} waits in {s},", .{ sim.nameOf(waiter), w.call });
        const with = if (w.listener) "a connection from that listener that it cannot answer until then" else "that connection, which it cannot write to until then";
        const values = try sim.gpa.alloc(contracts.Involved, 1);
        values[0] = .{ .name = "message", .value = try sim.vm.render(h.message) };
        return .{
            .kind = .held,
            .clause = try std.fmt.allocPrint(sim.gpa, "{s} waits in {s} while it holds a send to {s} #{d}, and sends are held until its update ends: {s} #{d} was started with {s}", .{ holder, call, target, h.to, target, h.to, with }),
            .within = holder,
            .at = 0,
            .values = values,
        };
    }

    /// `holder`'s update waits in an ask: the ask crashes it when it returns, and under
    /// Mo.Server it returns at once.
    fn doom(sim: *Sim, holder: u32, report: contracts.Report) void {
        const p = &sim.procs.items[holder];
        if (p.doomed == null) p.doomed = report;
        if (sim.turns) |t| t.wakeAll();
    }

    fn checkDoomed(sim: *Sim) Error!void {
        const me = sim.running orelse return;
        const report = sim.procs.items[me].doomed orelse return;
        sim.procs.items[me].doomed = null;
        sim.vm.report = report;
        return error.Crash;
    }

    // ---- failure

    /// Keeps the crash with its complete report, then does what the child line says.
    /// :always and :on_crash restart alike: an update never ends a process but by crashing.
    /// Under Mo.Server the report is written to stderr and kept cut in `kept_crashes`, and nothing
    /// else of it stays: what it rendered is freed below (step 33), since a large process's state
    /// cost its size again at every restart. Under Mo.Sim the run keeps every report whole.
    fn crashed(sim: *Sim, id: u32, before: Value) Error!void {
        const vm = sim.vm;
        const gpa = vm.reportGpa();
        var report = vm.report.?;
        var p = &sim.procs.items[id];
        const log = try gpa.alloc([]const u8, p.log.items.len);
        for (p.log.items, log) |m, *o| o.* = try vm.renderReport(m);
        report.process = .{ .process = sim.nameOf(id), .seed = sim.seed, .log = log, .state = try vm.renderReport(before) };
        if (p.policy.restart == .never and p.policy.line != none) report.process.?.not_restarted = vm.program.supervisors[p.policy.line].name;
        if (sim.server == null) try sim.crashes.append(sim.gpa, report);
        // The ring's event reads its texts from the store by number (events.zig, Crashes.filled).
        const number = if (sim.hidden(id)) 0 else sim.kept_crashes.record(.{
            .kind = .crashed,
            .at = sim.eventNow(),
            .process = id,
            .process_name = sim.nameOf(id),
            .seed = sim.seed,
            .clause = report.clause,
            .message = if (log.len > 0) log[log.len - 1] else "",
            .state = report.process.?.state,
        });
        sim.record(.{ .kind = .crashed, .process = id, .seed = sim.seed, .count = number });
        if (sim.server) |s| {
            s.processCrashed(report);
            // A connection closes when the process holding it stops, restarted or not.
            s.sockets.closeHeld(p.args);
        } else sim.fixture.closeHeld(p.args);
        // Under Mo.Server a report that gives up is main's crash, written when the run ends; any
        // other is done with here.
        defer if (sim.server != null and !sim.gave_up) {
            vm.report = null;
            vm.freeReports();
        };
        try sim.downKept(id);
        p = &sim.procs.items[id];
        if (sim.turns) |t| t.wakeAll();
        if (p.policy.restart == .never) {
            // It stays down (step 29): what waits for it is dropped, each with an event, and an ask
            // among it is Down.
            p.up = false;
            if (sim.turns) |t| for (p.mailbox.items[p.head..]) |e| try t.answer(e.seq, null, null);
            for (p.mailbox.items[p.head..]) |e| {
                sim.dropped(test_runner, id, e.message, "down");
                if (e.parcel) |x| x.free();
            }
            p.mailbox.clearRetainingCapacity();
            p.head = 0;
            return;
        }
        // Restarts are counted in simulated time under mo test, and wall-clock time under mo run.
        const at = if (sim.server) |s| s.now() else sim.now;
        var kept: usize = 0;
        for (p.restarts.items) |t| if (t > at - p.policy.window_ms) {
            p.restarts.items[kept] = t;
            kept += 1;
        };
        p.restarts.shrinkRetainingCapacity(kept);
        if (kept >= p.policy.max_restarts) return sim.giveUp(id, report);
        try p.restarts.append(sim.gpa, at);
        p.restarted += 1;
        // An ask whose message the restart drops is Down.
        if (sim.turns) |t| for (p.mailbox.items[p.head..]) |e| try t.answer(e.seq, null, null);
        for (p.mailbox.items[p.head..]) |e| if (e.parcel) |x| x.free();
        p.mailbox.clearRetainingCapacity();
        p.head = 0;
        p.log.clearRetainingCapacity();
        for (p.log_parcels.items) |x| x.free();
        p.log_parcels.clearRetainingCapacity();
        const state = vm.call(vm.program.processes[p.process].init, p.args) catch |err| switch (err) {
            error.Crash => return sim.giveUp(id, vm.report.?),
            else => return err,
        };
        p = &sim.procs.items[id];
        p.state = state;
        sim.record(.{ .kind = .restarted, .process = id, .count = p.restarted });
    }

    /// The child crashed more than max_restarts times within the window: its supervisor
    /// crashes, every child of that supervisor goes down, and the run stops.
    fn giveUp(sim: *Sim, id: u32, last: contracts.Report) Error {
        const vm = sim.vm;
        const p = sim.procs.items[id];
        const sup_name = if (p.supervisor == test_runner) (if (sim.server != null) "main" else "the test runner") else vm.program.supervisors[sim.supervisors.items[p.supervisor].index].name;
        for (sim.procs.items) |*q| {
            if (q.supervisor != p.supervisor) continue;
            q.up = false;
            if (sim.server) |s| s.sockets.closeHeld(q.args) else sim.fixture.closeHeld(q.args);
        }
        sim.gave_up = true;
        const values = try sim.gpa.alloc(contracts.Involved, 1);
        values[0] = .{ .name = "last crash", .value = last.clause };
        vm.report = .{
            .kind = .supervisor,
            .clause = try std.fmt.allocPrint(sim.gpa, "{s} gave up: {s} crashed more than {d} times within {d}.ms", .{ sup_name, sim.nameOf(id), p.policy.max_restarts, p.policy.window_ms }),
            .within = sup_name,
            .at = last.at,
            .values = values,
            .process = last.process,
        };
        return error.Crash;
    }
};

// ---- tests

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const caps = @import("caps.zig");
const diag = @import("diag.zig");
const runner = @import("runner.zig");

fn compile(arena: std.mem.Allocator, src: []const u8) !*bytecode.Program {
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    const checked = try check.check(arena, tree, &diags);
    try caps.check(arena, checked, &diags);
    for (diags.items) |d| std.debug.print("{s} at {d}: {s}\n", .{ d.code, d.at, d.what });
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);
    const program = try arena.create(bytecode.Program);
    program.* = try bytecode.lower(arena, checked);
    return program;
}

/// Runs one test of a program and keeps its Vm and Sim to look at.
const later_src =
    \\module T.Later
    \\process Ticker()
    \\  state
    \\    ticks: UInt32
    \\    left: UInt32
    \\  end
    \\
    \\  message Boom(me: Handle(Ticker))
    \\  message Tick
    \\
    \\  fn update(state, message)
    \\    case message
    \\      Boom(me):
    \\        me.send(Tick, delay: 10.ms)
    \\        state.left -= 1
    \\      Tick:
    \\        state.ticks += 1
    \\    end
    \\  end
    \\end
    \\supervisor Tickers
    \\  child Ticker, restart: :always
    \\end
;

test "between two statements simulated time does not pass to a delayed send; at the test's end it does" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, later_src);
    var machine: Vm = .init(arena, program, 7);
    var s: Sim = .init(&machine, 7, "later");
    machine.sim = &s;
    const id = try s.start(0, &.{});

    // An hour away: a settle between two statements delivers what waits and leaves it pending (step 29).
    try s.sendLater(id, try machine.variant("Tick", &.{}), 3_600_000);
    try s.settle();
    try std.testing.expectEqual(@as(usize, 1), s.later.items.len);
    try std.testing.expectEqual(@as(i64, 0), s.waited);
    try std.testing.expectEqual(@as(i128, 0), s.procs.items[id].state.record.fields[0].int);

    // The test's end passes the hour and delivers it.
    try s.finish();
    try std.testing.expectEqual(@as(usize, 0), s.later.items.len);
    try std.testing.expectEqual(@as(i128, 1), s.procs.items[id].state.record.fields[0].int);
}

test "a delayed send waits outside the mailbox until its time; a crashing update drops the one it held, and a target that is down drops it when it is due" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, later_src);
    var machine: Vm = .init(arena, program, 7);
    var s: Sim = .init(&machine, 7, "later");
    machine.sim = &s;
    const id = try s.start(0, &.{});
    const tick = try machine.variant("Tick", &.{});

    try s.sendLater(id, tick, 50);
    try std.testing.expectEqual(@as(usize, 0), s.procs.items[id].queued());
    s.wait(49);
    try std.testing.expect(!try s.dueLater());
    s.wait(1);
    try std.testing.expect(try s.dueLater());
    try std.testing.expectEqual(@as(usize, 1), s.procs.items[id].queued());
    _ = try s.deliver(id);
    try std.testing.expectEqual(@as(i128, 1), s.procs.items[id].state.record.fields[0].int);

    // Boom holds a delayed Tick, then underflows: the crash drops the Tick with the update.
    try s.send(id, try machine.variant("Boom", &.{.{ .handle = id }}));
    const crashed = try s.deliver(id);
    try std.testing.expect(crashed.reply == null);
    try std.testing.expectEqual(@as(usize, 1), s.crashes.items.len);
    try std.testing.expectEqual(@as(usize, 0), s.later.items.len);

    // Due to a process that is down by then: dropped.
    try s.sendLater(id, tick, 10);
    s.procs.items[id].up = false;
    s.wait(10);
    try std.testing.expect(!try s.dueLater());
    try std.testing.expectEqual(@as(usize, 0), s.later.items.len);
}

const Harness = struct {
    machine: Vm,
    sim: Sim,

    fn begin(h: *Harness, arena: std.mem.Allocator, program: *const bytecode.Program, name: []const u8) void {
        h.machine = .init(arena, program, 7);
        h.sim = .init(&h.machine, 7, name);
        h.machine.sim = &h.sim;
    }

    fn run(h: *Harness, arena: std.mem.Allocator, program: *const bytecode.Program, name: []const u8) Error!void {
        h.begin(arena, program, name);
        const t = for (program.tests) |t| {
            if (std.mem.eql(u8, t.name, name)) break t;
        } else unreachable;
        _ = try h.machine.call(t.function, &.{});
    }
};

const tally_src =
    \\module T.Sched
    \\process Tally(fs: Fs)
    \\  state
    \\    votes: UInt32
    \\    seen: List(UInt32)
    \\  end
    \\  message Vote(n: UInt32)
    \\  message Total : UInt32
    \\  fn update(state, message)
    \\    case message
    \\      Vote(n):
    \\        state.votes += 1
    \\        state.seen = state.seen.push(n)
    \\      Total: state.votes
    \\    end
    \\  end
    \\end
    \\supervisor Tallies(fs: Fs)
    \\  child Tally(fs), restart: :always
    \\end
    \\test "in order"
    \\  tally = Tally.start(Fs.fixture())
    \\  for n in [4, 5, 6]
    \\    tally.send(Vote(n: n))
    \\  end
    \\  assert tally.ask(Total, within: 100.ms) is Ok(3)
    \\end
    \\test "slow"
    \\  tally = Tally.start(Fs.fixture(delay: 1.minute))
    \\  tally.send(Vote(n: 1))
    \\  assert tally.ask(Total, within: 100.ms) is Error(Timeout)
    \\  assert tally.ask(Total, within: 2.minute) is Ok(1)
    \\end
;

test "messages arrive in order, one update each; ask replies after the waiting ones" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tally_src);
    var h: Harness = undefined;
    try h.run(arena, program, "in order");
    try std.testing.expectEqual(@as(usize, 1), h.sim.procs.items.len);
    const tally = h.sim.procs.items[0];
    try std.testing.expectEqual(@as(usize, 0), tally.queued());
    // Three votes and the ask, each its own update.
    try std.testing.expectEqual(@as(usize, 4), tally.log.items.len);
    const seen = tally.state.record.fields[1].list;
    try std.testing.expectEqual(@as(usize, 3), seen.len);
    for (seen, [_]i128{ 4, 5, 6 }) |v, want| try std.testing.expectEqual(want, v.int);
    try std.testing.expectEqual(@as(usize, 0), h.sim.crashes.items.len);
}

test "a seeded run makes the same choices for the same seed, and its clock moves at most 10 ms an update" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tally_src);
    var nows: [2]i64 = undefined;
    for (&nows) |*now| {
        var machine: Vm = .init(arena, program, 7);
        var s: Sim = .seeded(&machine, 99, "in order", 0);
        machine.sim = &s;
        _ = try machine.call(program.tests[0].function, &.{});
        try s.finish();
        // Three votes and the ask, each sent then taken, in the order sent: one mailbox is FIFO.
        try std.testing.expectEqual(@as(usize, 8), s.trace.items.len);
        const last = s.trace.items[7];
        try std.testing.expect(last.took);
        try std.testing.expectEqualStrings("Total", last.message.variant.name);
        try std.testing.expect(s.now >= vm_mod.fixture_time and s.now <= vm_mod.fixture_time + 4 * max_tick_ms);
        now.* = s.now;
    }
    try std.testing.expectEqual(nows[0], nows[1]);
}

const loader_src =
    \\module T.Faults
    \\process Loader(fs: Fs)
    \\  state
    \\    loads: UInt32
    \\    timeouts: UInt32
    \\  end
    \\  message Load
    \\  message Loads : UInt32
    \\  fn update(state, message)
    \\    case message
    \\      Load:
    \\        state.loads += 1
    \\        if fs.read("/etc/app.conf", within: 50.ms) is Error(Timeout)
    \\          state.timeouts += 1
    \\        end
    \\      Loads: state.loads
    \\    end
    \\  end
    \\end
    \\supervisor Loaders(fs: Fs)
    \\  child Loader(fs), restart: :always
    \\end
    \\test "a load is counted"
    \\  loader = Loader.start(Fs.fixture())
    \\  loader.send(Load)
    \\  assert loader.ask(Loads, within: 1.minute) is Ok(1)
    \\end
;

test "under faults a fixture call fails, and an ask whose target waited past its deadline is a Timeout" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, loader_src);
    var timed_out: u32 = 0;
    for (0..32) |seed| {
        var machine: Vm = .init(arena, program, 7);
        // Every call fails: Missing at once, or Timeout after its 50 ms.
        var s: Sim = .seeded(&machine, seed, "a load is counted", 100);
        machine.sim = &s;
        const loader = try s.start(0, &.{.{ .cap = .{ .kind = .fs } }});
        try s.send(loader, try machine.variant("Load", &.{}));
        const reply = try s.ask(loader, try machine.variant("Loads", &.{}), 40);
        try std.testing.expectEqual(@as(u32, 1), s.injected);
        const state = s.procs.items[loader].state.record.fields;
        // The Load arrived either way, and so did the ask's own message.
        try std.testing.expectEqual(@as(i128, 1), state[0].int);
        try std.testing.expectEqual(@as(usize, 2), s.procs.items[loader].log.items.len);
        const timeout = state[1].int == 1;
        try std.testing.expectEqualStrings(if (timeout) "Error" else "Ok", reply.variant.name);
        try std.testing.expectEqual(@as(i64, if (timeout) 50 else 0), s.waited);
        // The Loads update ran after the wait: the clock moved past it.
        try std.testing.expect(s.now >= vm_mod.fixture_time + s.waited);
        timed_out += @intFromBool(timeout);
    }
    try std.testing.expect(timed_out > 0 and timed_out < 32);
}

test "an ask past the target's fixture delay is a Timeout, and the message still arrives" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tally_src);
    var h: Harness = undefined;
    try h.run(arena, program, "slow");
    try std.testing.expectEqual(@as(i128, 1), h.sim.procs.items[0].state.record.fields[0].int);
}

const tx_src =
    \\module T.Tx
    \\process Meter() mailbox: 2
    \\  state
    \\    n: UInt8
    \\  end
    \\  invariant "n never goes backwards"
    \\    state.n >= old(state.n)
    \\  end
    \\  message Add(k: UInt8)
    \\  message Back
    \\  message Read : UInt8
    \\  fn update(state, message)
    \\    case message
    \\      Add(k):
    \\        state.n += k
    \\      Back:
    \\        state.n -= 1
    \\      Read: state.n
    \\    end
    \\  end
    \\end
    \\process Relay(meter: Handle(Meter), events: Events)
    \\  state
    \\    sent: UInt32
    \\  end
    \\  message Poke
    \\  message Flood
    \\  fn update(state, message)
    \\    case message
    \\      Poke:
    \\        meter.send(Add(k: 1))
    \\        events.emit(state.sent)
    \\        state.sent -= 1
    \\      Flood:
    \\        meter.send(Add(k: 1))
    \\        meter.send(Add(k: 1))
    \\        meter.send(Add(k: 1))
    \\    end
    \\  end
    \\end
    \\supervisor Meters(meter: Handle(Meter), events: Events)
    \\  child Meter, restart: :always
    \\  child Relay(meter, events), restart: :always
    \\end
    \\test "undone"
    \\  meter = Meter.start()
    \\  relay = Relay.start(meter, Events.fixture())
    \\  meter.send(Add(k: 5))
    \\  relay.send(Poke)
    \\end
    \\test "backwards"
    \\  meter = Meter.start()
    \\  meter.send(Add(k: 5))
    \\  meter.send(Back)
    \\end
    \\test "flooded by a test"
    \\  meter = Meter.start()
    \\  for k in [1, 2, 3]
    \\    meter.send(Add(k: k))
    \\  end
    \\end
    \\test "flooded by a process"
    \\  meter = Meter.start()
    \\  relay = Relay.start(meter, Events.fixture())
    \\  relay.send(Flood)
    \\end
    \\test rejects "going backwards trips the invariant"
    \\  meter = Meter.start()
    \\  meter.send(Add(k: 5))
    \\  meter.send(Back)
    \\end
;

test "update is a transaction: a crash drops its state writes, sends, and emits, and the process restarts" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tx_src);
    var h: Harness = undefined;
    try h.run(arena, program, "undone");
    const meter = h.sim.procs.items[0];
    const relay = h.sim.procs.items[1];
    // The meter took the test's Add(5) and never the relay's Add(1).
    try std.testing.expectEqual(@as(i128, 5), meter.state.record.fields[0].int);
    try std.testing.expectEqual(@as(usize, 1), meter.log.items.len);
    try std.testing.expectEqual(@as(usize, 0), h.sim.events.items.len);
    try std.testing.expect(relay.up);
    try std.testing.expectEqual(@as(i128, 0), relay.state.record.fields[0].int);
    try std.testing.expectEqual(@as(usize, 1), relay.restarts.items.len);
    try std.testing.expectEqual(@as(usize, 0), relay.log.items.len);
    const crash = h.sim.crashes.items[0];
    try std.testing.expectEqual(contracts.Kind.overflow, crash.kind);
    try std.testing.expectEqualStrings("Relay", crash.process.?.process);
    try std.testing.expectEqualStrings("Poke", crash.process.?.log[0]);
    try std.testing.expectEqualStrings("Relay(sent: 0)", crash.process.?.state);
    try std.testing.expectEqual(@as(u64, 7), crash.process.?.seed);
}

test "an invariant is false when broken, reads old(state), and trips a test rejects" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tx_src);
    var h: Harness = undefined;
    try h.run(arena, program, "backwards");
    const crash = h.sim.crashes.items[0];
    try std.testing.expectEqual(contracts.Kind.invariant, crash.kind);
    try std.testing.expectEqualStrings("invariant \"n never goes backwards\"", crash.clause);
    try std.testing.expectEqualStrings("Meter", crash.within);
    try std.testing.expectEqualStrings("Meter(n: 4)", crash.values[0].value);
    try std.testing.expectEqualStrings("Meter(n: 5)", crash.process.?.state);
    try std.testing.expectEqual(@as(usize, 2), crash.process.?.log.len);
    try std.testing.expectEqualStrings("Back", crash.process.?.log[1]);
    // Restarted from its initial state, not from the state that broke the invariant.
    try std.testing.expectEqual(@as(i128, 0), h.sim.procs.items[0].state.record.fields[0].int);

    const r = try runner.run(arena, program, .{});
    try std.testing.expectEqual(runner.Outcome.failed, r.results[1].outcome);
    try std.testing.expectEqual(runner.Outcome.tripped_as_expected, r.results[4].outcome);
    try std.testing.expectEqual(contracts.Kind.invariant, r.results[4].report.?.kind);
}

test "a mailbox at its bound crashes the sender, a test or a process, and names both" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tx_src);
    var h: Harness = undefined;
    // All three sends are one statement, so none is delivered before the third.
    try std.testing.expectError(error.Crash, h.run(arena, program, "flooded by a test"));
    try std.testing.expectEqual(contracts.Kind.mailbox, h.machine.report.?.kind);
    try std.testing.expectEqualStrings("the test \"flooded by a test\" sent to Meter, whose mailbox is full at its bound of 2", h.machine.report.?.clause);
    try std.testing.expectEqualStrings("Add(3)", h.machine.report.?.values[0].value);
    try std.testing.expectEqual(@as(usize, 2), h.sim.procs.items[0].queued());

    try h.run(arena, program, "flooded by a process");
    const crash = h.sim.crashes.items[0];
    try std.testing.expectEqual(contracts.Kind.mailbox, crash.kind);
    try std.testing.expectEqualStrings("Relay sent to Meter, whose mailbox is full at its bound of 2", crash.clause);
    // The receiver did not crash, and the two sends that fit went with the sender's update.
    try std.testing.expectEqual(@as(usize, 1), h.sim.crashes.items.len);
    try std.testing.expectEqual(@as(usize, 0), h.sim.procs.items[0].log.items.len);
}

const echo_src =
    \\module T.Echo
    \\process Echo(conn: Conn)
    \\  state
    \\    lines: UInt32
    \\  end
    \\  message Serve : UInt32
    \\  fn update(state, message)
    \\    case message
    \\      Serve:
    \\        state.lines += serve(conn)
    \\        state.lines
    \\    end
    \\  end
    \\end
    \\supervisor Echoes(conn: Conn)
    \\  child Echo(conn), restart: :always
    \\end
    \\fn serve(conn: Conn) : UInt32
    \\  var lines = 0
    \\  for _ in 0..100
    \\    case echo_once(conn)
    \\      Ok(true):
    \\        lines += 1
    \\      Ok(false):
    \\        break
    \\      Error(_):
    \\        break
    \\    end
    \\  end
    \\  lines
    \\end
    \\fn echo_once(conn: Conn) : Result(Bool, NetError)
    \\  line = try conn.read_line(within: 1.minute)
    \\  case line
    \\    Some(text):
    \\      try conn.write("#{text}\n", within: 1.minute)
    \\      Ok(true)
    \\    None: Ok(false)
    \\  end
    \\end
    \\fn round_trip(net: Net, sent: List(String)) : Result(List(String), NetError)
    \\  listener = try net.listen(0, within: 1.minute)
    \\  client = try net.connect("localhost", listener.port, within: 1.minute)
    \\  conn = try listener.accept(within: 1.minute)
    \\  worker = Echo.start(conn)
    \\  for line in sent
    \\    try client.write("#{line}\n", within: 1.minute)
    \\  end
    \\  if worker.ask(Serve, within: 10.minute) is Error(_)
    \\    return Error(Timeout)
    \\  end
    \\  var heard = sent.take(0)
    \\  for _ in sent
    \\    case try client.read_line(within: 1.minute)
    \\      Some(text):
    \\        heard = heard.push(text)
    \\      None:
    \\        return Error(Closed)
    \\    end
    \\  end
    \\  Ok(heard)
    \\end
    \\fn echoed?(heard: Result(List(String), NetError), sent: List(String)) : Bool
    \\  case heard
    \\    Ok(lines): lines == sent
    \\    Error(_): true
    \\  end
    \\end
    \\
;

test "a server process echoes a fixture client's lines, and under faults each round trip is whole or fails and says so" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const exact = try compile(arena, echo_src ++
        \\test "every line comes back"
        \\  sent = ["hello", "wide world", ""]
        \\  assert round_trip(Net.fixture(), sent) == Ok(sent)
        \\end
    );
    const fixed = try runner.run(arena, exact, .{});
    try std.testing.expectEqual(runner.Outcome.passed, fixed.results[0].outcome);

    const tolerant = try compile(arena, echo_src ++
        \\test "every line comes back, unless the connection fails and says so"
        \\  sent = ["hello", "wide world", ""]
        \\  assert echoed?(round_trip(Net.fixture(), sent), sent)
        \\end
    );
    const r = try runner.run(arena, tolerant, .{ .sim_runs = 100, .sim_seed = 11, .fault_percent = 20 });
    try std.testing.expectEqual(runner.Outcome.passed, r.results[0].outcome);
    try std.testing.expectEqual(@as(u32, 1), r.summary.held_under_faults);
    // The exact test is a design smell under faults: it holds only where nothing fails.
    const smell = try runner.run(arena, exact, .{ .sim_runs = 100, .sim_seed = 11, .fault_percent = 20 });
    try std.testing.expectEqual(@as(u32, 1), smell.summary.fault_free_only);
}

const sup_src =
    \\module T.Sup
    \\process Beat()
    \\  state
    \\    n: UInt8
    \\  end
    \\  message Up
    \\  message Drop
    \\  message Count : UInt8
    \\  fn update(state, message)
    \\    case message
    \\      Up:
    \\        state.n += 1
    \\      Drop:
    \\        state.n -= 1
    \\      Count: state.n
    \\    end
    \\  end
    \\end
    \\process Reader(fs: Fs)
    \\  state
    \\    reads: UInt8
    \\  end
    \\  message Slip
    \\  message Reads : UInt8
    \\  fn update(state, message)
    \\    case message
    \\      Slip:
    \\        state.reads -= 1
    \\      Reads: state.reads
    \\    end
    \\  end
    \\end
    \\supervisor Pulse(fs: Fs)
    \\  child Beat, restart: :always, max_restarts: 2 per 1.minute
    \\  child Reader(fs), restart: :never
    \\end
    \\test "two restarts are allowed"
    \\  beat = Beat.start()
    \\  beat.send(Drop)
    \\  beat.send(Drop)
    \\  beat.send(Up)
    \\end
    \\test "the third crash is one too many"
    \\  beat = Beat.start()
    \\  beat.send(Drop)
    \\  beat.send(Drop)
    \\  beat.send(Drop)
    \\  beat.send(Up)
    \\end
;

test "a fixture Fs keeps what a test writes, shared by every Fs narrowed from it; an Out.fixture keeps each write; a faulted write changes nothing" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Fixtures
        \\process Writer(fs: Fs)
        \\  state
        \\    tries: UInt32
        \\  end
        \\  message Note : Bool
        \\  fn update(state, message)
        \\    case message
        \\      Note:
        \\        state.tries += 1
        \\        ok(fs.append("x.log", "1\n", within: 1.minute))
        \\    end
        \\  end
        \\end
        \\supervisor Writers(fs: Fs)
        \\  child Writer(fs), restart: :always
        \\end
        \\fn ok(r: Result(T, FsError)) : Bool
        \\  r is Ok(_)
        \\end
        \\fn log(out: Out, fs: Fs) : Bool
        \\  out.write("a")
        \\  out.write_line("b")
        \\  out.flush
        \\  ok(fs.append("x.log", "1\n", within: 1.minute))
        \\end
        \\test "writes read back"
        \\  fs = Fs.fixture()
        \\  data = fs.scoped("data")
        \\  assert ok(data.write("a.log", "one\n", within: 1.minute))
        \\  assert ok(data.append("a.log", "two\n", within: 1.minute))
        \\  assert fs.read("data/a.log", within: 1.minute) == Ok("one\ntwo\n")
        \\  assert data.read_lines("a.log", within: 1.minute) == Ok(["one", "two"])
        \\  assert fs.list(within: 1.minute) == Ok(["data"])
        \\  assert ok(data.rename("a.log", "b.log", within: 1.minute))
        \\  assert data.list(within: 1.minute) == Ok(["b.log"])
        \\  assert data.mkdir("old", within: 1.minute) is Ok(_)
        \\  assert data.mkdir("old", within: 1.minute) is Ok(_)
        \\  assert data.list(within: 1.minute) == Ok(["b.log", "old"])
        \\  assert data.scoped("old").list(within: 1.minute) == Ok([])
        \\  assert data.mkdir("b.log", within: 1.minute) is Error(Missing("b.log"))
        \\  assert data.size("b.log", within: 1.minute) == Ok(8)
        \\  assert data.remove("a.log", within: 1.minute) is Error(Missing("a.log"))
        \\  assert data.write("../x", "no", within: 1.minute) is Error(Missing("../x"))
        \\  assert Fs.fixture().read("data/b.log", within: 1.minute) is Error(Missing(_))
        \\  assert Fs.fixture(delay: 2.minute).write("a", "b", within: 1.minute) is Error(Timeout)
        \\end
        \\test "an Out fixture keeps each write"
        \\  out = Out.fixture()
        \\  fs = Fs.fixture()
        \\  assert log(out, fs)
        \\  assert out.written == ["a", "b\n"]
        \\  assert fs.read("x.log", within: 1.minute) == Ok("1\n")
        \\end
        \\test "a writer appends"
        \\  writer = Writer.start(Fs.fixture())
        \\  assert writer.ask(Note, within: 1.minute) is Ok(_)
        \\end
    );
    const r = try runner.run(arena, program, .{});
    try std.testing.expectEqual(runner.Outcome.passed, r.results[0].outcome);
    try std.testing.expectEqual(runner.Outcome.passed, r.results[1].outcome);
    try std.testing.expectEqual(runner.Outcome.passed, r.results[2].outcome);

    // A write through a read-only Fs is refused at run time too. The checker follows the narrowing
    // through an if since step 25, so no program here hides one from it: the Fs is narrowed here
    // and handed in as the start argument.
    {
        var machine: Vm = .init(arena, program, 7);
        var s: Sim = .init(&machine, 1, "a writer appends");
        machine.sim = &s;
        const fs = try stdlib.fixtureFs(&machine, 0);
        const read_only = try stdlib.fixtureNarrow(&machine, fs.cap, "read_only", "");
        const writer = try s.start(0, &.{read_only});
        _ = s.ask(writer, try machine.variant("Note", &.{}), 60_000) catch {};
        try std.testing.expectEqual(@as(usize, 1), s.crashes.items.len);
        try std.testing.expectEqualStrings("fs.append(\"x.log\") writes through an Fs narrowed to read_only, which only reads", s.crashes.items[0].clause);
        try std.testing.expectEqual(@as(usize, 0), s.files.systems.items[0].count());
    }

    // Every fixture call fails in these runs: the append is Missing or Timeout, and the file
    // system keeps nothing of it.
    for (0..8) |seed| {
        var machine: Vm = .init(arena, program, 7);
        var s: Sim = .seeded(&machine, seed, "a writer appends", 100);
        machine.sim = &s;
        const fs = try stdlib.fixtureFs(&machine, 0);
        const writer = try s.start(0, &.{fs});
        const reply = try s.ask(writer, try machine.variant("Note", &.{}), 60_000);
        try std.testing.expect(!reply.variant.fields[0].bool);
        try std.testing.expectEqual(@as(usize, 0), s.files.systems.items[0].count());
    }
}

test "the test runner supervises a process it starts with :always and the child line's max_restarts" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, sup_src);
    var h: Harness = undefined;
    try h.run(arena, program, "two restarts are allowed");
    const beat = h.sim.procs.items[0];
    try std.testing.expectEqual(@as(usize, 2), h.sim.crashes.items.len);
    try std.testing.expectEqual(@as(usize, 2), beat.restarts.items.len);
    try std.testing.expectEqual(@as(i128, 1), beat.state.record.fields[0].int);
    try std.testing.expectEqual(@as(i64, 60_000), beat.policy.window_ms);

    try std.testing.expectError(error.Crash, h.run(arena, program, "the third crash is one too many"));
    try std.testing.expect(h.sim.gave_up);
    const report = h.machine.report.?;
    try std.testing.expectEqual(contracts.Kind.supervisor, report.kind);
    try std.testing.expectEqualStrings("the test runner gave up: Beat crashed more than 2 times within 60000.ms", report.clause);
    try std.testing.expectEqualStrings("state.n -= 1", report.values[0].value);
    try std.testing.expectEqualStrings("Drop", report.process.?.log[0]);
    try std.testing.expect(!h.sim.procs.items[0].up);

    // Through the runner: a crash fails a test, and a supervisor that gave up reports itself.
    const r = try runner.run(arena, program, .{});
    try std.testing.expectEqual(contracts.Kind.overflow, r.results[0].report.?.kind);
    try std.testing.expectEqual(contracts.Kind.supervisor, r.results[1].report.?.kind);
    try std.testing.expectEqual(@as(u32, 2), r.summary.failures);
}

test "a supervisor starts its children with the arguments its lines pass, and follows each line" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, sup_src);
    var h: Harness = undefined;
    h.begin(arena, program, "Pulse");
    const fs: Value = .{ .cap = .{ .kind = .fs, .delay = 3 } };
    _ = try h.sim.startSupervisor(0, &.{fs});
    try std.testing.expectEqual(@as(usize, 2), h.sim.procs.items.len);
    try std.testing.expectEqualStrings("Reader", h.sim.nameOf(1));
    try std.testing.expect(vm_mod.equal(fs, h.sim.procs.items[1].args[0]));

    // restart: :never leaves the child down, its report says so, an ask to it is Down, and a send
    // to it is dropped with an event (step 29).
    try h.sim.send(1, try h.machine.variant("Slip", &.{}));
    try h.sim.settle();
    try std.testing.expect(!h.sim.procs.items[1].up);
    try std.testing.expectEqualStrings("Pulse", h.sim.crashes.items[h.sim.crashes.items.len - 1].process.?.not_restarted);
    const down = try h.sim.ask(1, try h.machine.variant("Reads", &.{}), 100);
    try std.testing.expectEqualStrings("Down", down.variant.fields[0].variant.name);
    try h.sim.send(1, try h.machine.variant("Slip", &.{}));
    const last = h.sim.ring.get(h.sim.ring.len - 1);
    try std.testing.expectEqual(events_mod.Kind.dropped, last.kind);
    try std.testing.expectEqual(@as(u32, 1), last.process);
    try std.testing.expectEqualStrings("Slip", last.message);
    try std.testing.expectEqualStrings("down", last.name);

    // Beat's line allows two restarts in a minute; the third crash takes Pulse down.
    for (0..2) |_| {
        try h.sim.send(0, try h.machine.variant("Drop", &.{}));
        try h.sim.settle();
    }
    try h.sim.send(0, try h.machine.variant("Drop", &.{}));
    try std.testing.expectError(error.Crash, h.sim.settle());
    try std.testing.expectEqualStrings("Pulse gave up: Beat crashed more than 2 times within 60000.ms", h.machine.report.?.clause);
    try std.testing.expect(!h.sim.procs.items[0].up);
}

const held_src =
    \\module T.Held
    \\process Worker(exchange: Exchange)
    \\  state
    \\    answered: Bool
    \\  end
    \\  message Answer
    \\  fn update(state, message)
    \\    case message
    \\      Answer:
    \\        state.answered = exchange.reply(Response(status: 200, body: "hi"), within: 1.minute) is Ok(_)
    \\    end
    \\  end
    \\end
    \\process Acceptor(listener: HttpListener)
    \\  state
    \\    accepted: UInt64
    \\  end
    \\  message Serve : UInt64
    \\  fn update(state, message)
    \\    case message
    \\      Serve:
    \\        if listener.accept(within: 1.minute) is Ok(_)
    \\          state.accepted += 1
    \\        end
    \\        state.accepted
    \\    end
    \\  end
    \\end
    \\process Relay(listener: HttpListener, acceptor: Handle(Acceptor))
    \\  state
    \\    asked: Bool
    \\  end
    \\  message Go
    \\  fn update(state, message)
    \\    case message
    \\      Go:
    \\        if listener.accept(within: 1.minute) is Ok(exchange)
    \\          worker = Worker.start(exchange)
    \\          worker.send(Answer)
    \\        end
    \\        state.asked = acceptor.ask(Serve, within: 1.minute) is Ok(_)
    \\    end
    \\  end
    \\end
    \\supervisor Held(listener: HttpListener, exchange: Exchange, acceptor: Handle(Acceptor))
    \\  child Worker(exchange), restart: :always
    \\  child Acceptor(listener), restart: :always
    \\  child Relay(listener, acceptor), restart: :always
    \\end
    \\fn fetched(http: Http, relay: Handle(Relay), port: UInt16) : Result(Response, HttpError)
    \\  relay.send(Go)
    \\  http.send(Request(method: "GET", path: "/"), host: "localhost", port: port, within: 1.minute)
    \\end
    \\test rejects "an ask to a process that waits on a client the asker's held send keeps waiting"
    \\  http = Http.fixture()
    \\  assert http.listen(0, within: 1.ms) is Ok(listener)
    \\  relay = Relay.start(listener, Acceptor.start(listener))
    \\  assert fetched(http, relay, listener.port) is Error(_)
    \\end
;

test "an update that waits on what only a send it holds could bring crashes, and one whose ask waits on such a wait crashes when the ask returns" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, held_src);
    const r = try runner.run(arena, program, .{});
    try std.testing.expectEqual(runner.Outcome.tripped_as_expected, r.results[0].outcome);
    const report = r.results[0].report.?;
    try std.testing.expectEqual(contracts.Kind.held, report.kind);
    // The Acceptor waits in accept for a client; the Relay asked it while holding Answer for
    // the Worker it gave the first exchange, so the Relay's ask is what crashes.
    try std.testing.expectEqualStrings("Relay waits in ask, and Acceptor waits in HttpListener.accept, while it holds a send to Worker #2, and sends are held until its update ends: Worker #2 was started with a connection from that listener that it cannot answer until then", report.clause);
    try std.testing.expectEqualStrings("Answer", report.values[0].value);
    try std.testing.expectEqualStrings("Relay", report.process.?.process);
}

test "under --faults, a connection the runtime reads finds itself Closed or waits out its idle time, by the seed" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Faults
        \\process Ends()
        \\  state
        \\    bytes: UInt64
        \\    closed: UInt64
        \\    idled: UInt64
        \\  end
        \\  message Line(text: String)
        \\  message LineTooLong
        \\  message Closed
        \\  message Idle
        \\  fn update(state, message)
        \\    case message
        \\      Line(text):
        \\        state.bytes += text.size
        \\      LineTooLong:
        \\        state.bytes += 0
        \\      Closed:
        \\        state.closed += 1
        \\      Idle:
        \\        state.idled += 1
        \\    end
        \\  end
        \\end
        \\supervisor Top
        \\  child Ends, restart: :always
        \\end
    );
    const Run = struct {
        fn ends(a: std.mem.Allocator, p: *const bytecode.Program, seed: u64, percent: u32) ![3]i128 {
            var machine: Vm = .init(a, p, seed);
            var sim: Sim = .seeded(&machine, seed, "faults", percent);
            machine.sim = &sim;
            // Two lines wait on connection 0, which connection 1 wrote and left open; no fixture
            // call draws a fault before the runtime reads them.
            try sim.fixture.conns.append(a, .{ .peer = 1 });
            try sim.fixture.conns.append(a, .{ .peer = 0 });
            try sim.fixture.conns.items[0].inbound.appendSlice(a, "ab\ncd\n");
            const id = try sim.start(0, &.{});
            _ = try sources_mod.row(&machine, .lines, &.{ .{ .cap = .{ .kind = .conn, .handle = 0 } }, .{ .handle = id }, .{ .duration = 60_000 } });
            try sim.finish();
            const f = sim.procs.items[id].state.record.fields;
            return .{ f[0].int, f[1].int, f[2].int };
        }
    };
    // Without faults both lines arrive, and nothing ends the connection.
    const clean = try Run.ends(arena, program, 1, 0);
    try std.testing.expectEqual([3]i128{ 4, 0, 0 }, clean);
    // With every draw a fault, the first delivery is an end instead: Closed or Idle, by the seed.
    var closed: i128 = 0;
    var idled: i128 = 0;
    for (1..41) |seed| {
        const got = try Run.ends(arena, program, seed, 100);
        try std.testing.expectEqual(@as(i128, 0), got[0]);
        try std.testing.expectEqual(@as(i128, 1), got[1] + got[2]);
        closed += got[1];
        idled += got[2];
    }
    try std.testing.expect(closed > 0 and idled > 0);
}
