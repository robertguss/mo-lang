//! Turns: how Mo.Server runs processes (design-v0/03, effects and processes; steps 11, 21, 30).
//! A program runs its processes on every core (step 30): one scheduler per core, `MO_CORES` of them
//! when it is set and the machine's cores otherwise, scheduler 0 on main's thread and each other on a
//! thread of its own. A process is placed at its start and stays there for its life (placeFor): one an
//! update starts goes on its starter's scheduler, unless that one holds more than place_factor times
//! its share of the live processes, and one main starts, or one past the share, goes on the scheduler
//! with the fewest live processes (step 34). So a worker runs where the process that started it runs,
//! and a request path that never crosses costs what one scheduler costs. Each scheduler runs its processes' updates one at a time,
//! each on a fiber of its own (fiber.zig) with a Vm of its own, and nothing a process sees depends on
//! where it runs: nothing is shared, and a message is a copy. `MO_CORES=1` is one scheduler, no
//! thread, and no lock: the runtime of step 29b.
//!
//! The lock. The runtime's tables (Mo.Sim's processes and their mailboxes, the delayed sends, the
//! asks and their replies, the events, the sockets and the loops that read them) are behind one
//! mutex. A scheduler's thread holds it while it runs the runtime: handing out turns, the start of a
//! delivery and its commit, main's code, and every row that reads or changes those tables (vm.zig,
//! `lockRuntime`). It lets go while a process's Mo code runs (the update and its invariants), while the
//! process's region compacts after it, and while the scheduler waits in its poller. So updates on
//! different schedulers run at the same time, and each still begins and commits as one transaction:
//! its message is taken and its sends, its reply, and its new state are put in under the lock.
//!
//! A process gives up its scheduler's thread when it waits: in a Net call (net.zig), or in an ask
//! its target cannot answer yet. Its fiber switches back to whoever handed it the thread, keeping its
//! stack, and its scheduler switches to it again when its wait ends. So `conn.read_line(within:
//! 30.s)` reads like Go and waits like Erlang: the update's stack waits, holding no thread, and
//! every other process keeps taking messages.
//!
//! A scheduler hands its thread out: first to a process whose wait ended, then to the next of its
//! processes with a message waiting, round by round in start order. With none to hand out it spins a
//! moment, then waits in its own poller (poller.zig) for a socket one of its processes waits on, for a
//! wake another scheduler writes when it puts something in one of this one's mailboxes, or for the
//! earliest deadline; with no socket of its own armed it waits on its state word instead (idle, step
//! 34). Scheduler 0 also runs main's code, the runtime's loops (sources.zig), and the delayed
//! sends (one heap, under the lock). main's thread runs main's code whenever no update of scheduler
//! 0 does; after each of main's statements it hands the thread out until every scheduler has
//! nothing left to hand out, so main's sends are delivered before its next statement, as before. A
//! process that computes without waiting keeps its scheduler until its update ends; nothing preempts
//! it.
//!
//! A delivery borrows a fiber from its scheduler's pool and gives it back when the update ends, so a
//! process at rest holds no stack: what it costs is its region, its mailbox, and its Vm's lists.
//!
//! A process a start call began ends once it has finished and nothing can reach its handle (sweep,
//! step 19). A handle may be held on any scheduler, so a sweep waits for its turn: no update starts
//! or resumes until every update in progress has parked or ended, as when one thread swept, and the
//! marks are taken over every process. The processes found ended are handed to
//! their own schedulers, which free their parcels and regions and give their ids to the next
//! process started there, which takes over the Vm and region; the regions of more than kept_workers
//! ended ids are released.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const posix = std.posix;
const contracts = @import("contracts.zig");
const fiber_mod = @import("fiber.zig");
const net_mod = @import("net.zig");
const poller_mod = @import("poller.zig");
const region_mod = @import("region.zig");
const sources = @import("sources.zig");
const sim_mod = @import("sim.zig");
const vm_mod = @import("vm.zig");

const Region = region_mod.Region;

const Fiber = fiber_mod.Fiber;
const Poller = poller_mod.Poller;
const Waiter = poller_mod.Waiter;
const Sim = sim_mod.Sim;
const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Parcel = vm_mod.Parcel;
const Error = vm_mod.Error;

/// The address space a process's region reserves (reserveProcess): big_region while every live
/// process's region together holds under region_budget, else process_region, so 64,000 regions still
/// fit (step 21). A region moves into a larger one only between updates (Sim.settleRegion), and one
/// update's values, a replay's whole book among them, need the room while it runs (step 29b). A
/// region that fills allocates past itself from gpa (Region.fallback), memory no compaction frees and
/// the `spilled` of `MO_STATS=1` counts. runtime/mo_rt.c's reserve_process is the same.
pub const process_region: usize = 1 << 30;
pub const big_region: usize = 64 << 30;
pub const region_budget: usize = 16 << 40;
/// The address space the live processes' regions hold, counted by every scheduler.
pub var regions_reserved: std.atomic.Value(usize) = .init(0);

/// A process region's reservation: `want` bytes while the live regions, less `within` bytes about to
/// be released, stay under region_budget, else `past`; counted.
pub fn reserveProcess(want: usize, past: usize, within: usize) ?Region {
    const size = if (regions_reserved.load(.monotonic) + want > region_budget + within) past else want;
    const r = Region.reserveUpTo(size) catch return null;
    _ = regions_reserved.fetchAdd(r.end - r.base, .monotonic);
    return r;
}

/// A process region given back.
pub fn releaseProcess(r: *Region) void {
    _ = regions_reserved.fetchSub(r.end - r.base, .monotonic);
    r.release();
}

/// `Sched.holder` when the scheduler's own loop, or main's code on scheduler 0, holds its thread.
pub const main_turn: u32 = std.math.maxInt(u32);

/// The most schedulers a run has.
pub const most_cores: u32 = 64;

/// The schedulers a run has: `MO_CORES` when it is a whole number from 1, at most most_cores, else
/// the machine's cores.
pub fn coresFrom(text: ?[]const u8) u32 {
    if (text) |t| {
        const n = std.fmt.parseInt(u32, std.mem.trim(u8, t, " \t"), 10) catch 0;
        if (n >= 1) return @min(n, most_cores);
    }
    const n = std.Thread.getCpuCount() catch 1;
    return @intCast(@min(@max(n, 1), most_cores));
}

/// How placement chooses (step 34): `MO_PLACE=spread` places every process on the scheduler with the
/// fewest live processes, step 30's rule, for the comparison rows; anything else places with the
/// starter.
pub const Placing = enum { starter, spread };

pub fn placingFrom(text: ?[]const u8) Placing {
    if (text) |t| if (std.mem.eql(u8, std.mem.trim(u8, t, " \t"), "spread")) return .spread;
    return .starter;
}

/// A starter's scheduler keeps a process it starts while it holds at most this many times its share
/// of the live processes, the share being the live processes, the new one among them, over the
/// schedulers, rounded up (step 34). Past it, the new process goes where the fewest live.
pub const place_factor: u32 = 2;

/// The fewest quiet events (Turns.quiet) between two sweeps.
pub const sweep_min: u32 = 64;
/// Ended processes whose regions wait for the next processes given their ids, at most, per scheduler:
/// the last ids ended, which the next starts there take.
pub const kept_workers: usize = 64;
/// Idle fibers a scheduler's pool keeps; past this, fibers coming back are unmapped.
pub const kept_fibers: usize = 64;
/// A job that went more than this many calls deep gives back its stack's pages below the top
/// `fiber_kept_bytes` when it ends, so one deep recursion does not stay resident in the pool.
const deep_calls: u32 = 64;
const fiber_kept_bytes: usize = 1 << 20;
/// A sweep waits at most this long for every scheduler to be outside Mo code, and after a wait that
/// ran out, tries again no sooner than sweep_retry_ms later.
const stop_wait_ms: i64 = 20;
const sweep_retry_ms: i64 = 100;

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
    /// In its scheduler's ready queue.
    queued: bool = false,
    /// Where it is in its scheduler's parked list, while it is there (step 34).
    parked_at: ?u32 = null,
    /// What its update ended with, for whoever gets the thread back.
    failed: ?Error = null,
    /// Its region is released, after a sweep ended its process and more than kept_workers
    /// had ended since. The next process given its id reserves one again.
    ended: bool = false,
};

const Parked = struct { id: u32, deadline: i64 };

/// An ask's reply, in the parcel it came back in under `mo run`.
pub const Reply = struct { value: Value, parcel: ?*Parcel };

/// A descriptor another scheduler writes to so a scheduler waiting in its poller looks again: an
/// eventfd on Linux, a pipe elsewhere.
const Wake = struct {
    read_fd: posix.fd_t = -1,
    write_fd: posix.fd_t = -1,
    waiter: Waiter = .{ .fd = -1, .filter = .read },

    fn open(w: *Wake) bool {
        if (builtin.os.tag == .linux) {
            const linux = std.os.linux;
            const rc = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
            if (posix.errno(rc) != .SUCCESS) return false;
            w.read_fd = @intCast(rc);
            w.write_fd = w.read_fd;
        } else {
            var fds: [2]posix.fd_t = undefined;
            if (posix.errno(posix.system.pipe(&fds)) != .SUCCESS) return false;
            net_mod.nonblocking(fds[0]);
            net_mod.nonblocking(fds[1]);
            w.read_fd = fds[0];
            w.write_fd = fds[1];
        }
        w.waiter = .{ .fd = w.read_fd, .filter = .read };
        return true;
    }

    fn signal(w: *Wake) void {
        if (w.write_fd < 0) return;
        const one: u64 = 1;
        _ = posix.system.write(w.write_fd, std.mem.asBytes(&one), if (builtin.os.tag == .linux) 8 else 1);
    }

    fn drain(w: *Wake) void {
        var buf: [64]u8 = undefined;
        while (true) {
            const rc = posix.system.read(w.read_fd, &buf, buf.len);
            if (posix.errno(rc) != .SUCCESS or rc == 0) return;
        }
    }

    fn close(w: *Wake) void {
        if (w.read_fd >= 0) _ = posix.system.close(w.read_fd);
        if (w.write_fd >= 0 and w.write_fd != w.read_fd) _ = posix.system.close(w.write_fd);
        w.* = .{};
    }
};

/// One scheduler: a thread's processes, their ready queue, their fibers, and its poller.
pub const Sched = struct {
    index: u32,
    /// Who holds this scheduler's thread: main_turn (its loop, or main's code on scheduler 0) or a
    /// process with a fiber.
    holder: u32 = main_turn,
    /// The loop's own context (main's thread's on scheduler 0), while a fiber runs.
    main_context: fiber_mod.Context = undefined,
    /// Made when something first waits on a socket; with more than one scheduler, at the start.
    poller: ?Poller = null,
    wake: Wake = .{},
    /// Its thread: `running`, `spinning` a moment before it sleeps, `sleeping` in its poller, or
    /// `parked` on this value when no socket of its own is armed, with the lock let go (Turns.idle),
    /// or `poked`: given something since it began to wait. A scheduler that gives it something swaps in
    /// `poked` and wakes it only when what it swapped out says it sleeps, so a handoff between two busy
    /// schedulers costs no system call. One word, so a poke and a sleep cannot miss each other (step
    /// 34: with a flag and a state apart, a thread now and then slept out its second with a poke in).
    state: std.atomic.Value(u32) = .init(thread_running),
    /// When its thread last looked at its poller.
    polled_at: Io.Clock.Timestamp = .{ .raw = .zero, .clock = .awake },
    /// Its last look found nothing to hand out, and nothing has been given it since (Turns.settle).
    resting: bool = true,
    /// A sweep kept it from handing out a turn: the sweep's end wakes it.
    held_back: bool = false,
    /// Processes whose wait ended, oldest first from `ready_head`; each at most once.
    ready: std.ArrayList(u32) = .empty,
    ready_head: usize = 0,
    /// Fibers no update is on.
    fibers: std.ArrayList(*Fiber) = .empty,
    /// Its processes parked in an ask or a Net call, each with its deadline.
    parked: std.ArrayList(Parked) = .empty,
    /// No parked deadline is earlier than this; one may be later, since a wake does not raise it
    /// (step 34): the list is scanned only once this has passed.
    parked_due: i64 = std.math.maxInt(i64),
    /// Where the next round of deliveries starts.
    cursor: u32 = 0,
    /// Its process ids that may have a message waiting: set when one is put in a mailbox
    /// (Sim.enqueue), cleared when the round finds the mailbox empty.
    runnable: std.DynamicBitSetUnmanaged = .{},
    /// The scratch region its processes' vms compact through: only one update of this scheduler
    /// runs Mo code at a time, so one is enough. Scheduler 0's is the server's.
    scratch: ?*Region = null,
    own_scratch: ?Region = null,
    /// Where its processes' vms keep their lists, which only this thread touches outside the lock.
    arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator),
    /// Processes live on it, which placement counts.
    live: u32 = 0,
    /// Processes placed on it: in all, and those with their starter (step 34), for `MO_STATS=1`.
    placed: u32 = 0,
    with_starter: u32 = 0,
    /// Asks its processes made of a process on another scheduler, for `MO_STATS=1`.
    asks_across: u64 = 0,
    /// Its processes a sweep found ended, whose Vms and regions it has yet to free.
    to_end: std.ArrayList(u32) = .empty,
    /// Ids of its ended processes, the last ended last: the next start placed here takes the last.
    free_ids: std.ArrayList(u32) = .empty,
    /// The poller's last reports.
    fired: [poller_mod.batch]*Waiter = undefined,
    /// This thread's hold on the lock: how deep, and the process and vm Mo.Sim names as running while
    /// it does not hold it.
    depth: u32 = 0,
    stash_vm: *Vm = undefined,
    stash_running: ?u32 = null,
    thread: ?std.Thread = null,
    /// The counts of its thread (region.Stats), for `MO_STATS=1`.
    stats: ?*region_mod.Stats = null,

    fn pollerOf(s: *Sched) Error!*Poller {
        if (s.poller == null) s.poller = Poller.init() catch return error.OutOfMemory;
        return &s.poller.?;
    }
};

const thread_running: u32 = 0;
const thread_spinning: u32 = 1;
const thread_sleeping: u32 = 2;
const thread_parked: u32 = 3;
const thread_poked: u32 = 4;
/// How long a scheduler with nothing to do spins on the poke before it sleeps (step 34): longer than
/// an update another scheduler hands it usually takes, so an ask across schedulers meets a thread
/// awake. One with sockets armed spins as long, looking at its poller every poll_every spins; one with
/// none never calls the system while it spins, since a look at the poller costs 8 to 13 µs on macOS,
/// as much as the handoff it waits for.
const spin_ns: i96 = 200_000;
const spin_sockets_ns: i96 = 200_000;
/// A scheduler poked out of its spin looks at its armed sockets at most this often.
const poked_poll_ns: i96 = 200_000;
/// How many spins go by between two looks at the clock, and at the poller when sockets are armed.
const poll_every: u32 = 64;
/// How many times a thread tries for the runtime's lock before it waits for it in the system.
const lock_spins: u32 = 20_000;

/// Sweeps the last run made, and the ones that did not run because a scheduler stayed in Mo code
/// past stop_wait_ms, for `MO_STATS=1`.
pub var sweeps_run: u64 = 0;
pub var sweeps_missed: u64 = 0;
/// Process ids the last run gave out.
pub var ids_used: usize = 0;

/// The scheduler this thread is, under a run with more than one.
pub threadlocal var here: ?*Sched = null;

/// The last run's schedulers' counts, for `MO_STATS=1` (main.zig): `last_cores` of them.
pub var last_stats: [most_cores]region_mod.Stats = [_]region_mod.Stats{.{}} ** most_cores;
pub var last_cores: u32 = 0;
/// The last run's placement counts per scheduler, for `MO_STATS=1`: placed, with the starter, live
/// at the end, and asks made across.
pub const Placement = struct { placed: u32 = 0, with_starter: u32 = 0, live: u32 = 0, asks_across: u64 = 0 };
pub var last_placement: [most_cores]Placement = [_]Placement{.{}} ** most_cores;
/// While a run lasts, its schedulers, so a signal can print where the processes went.
pub var live_turns: ?*Turns = null;

/// Scheduler `k`'s placement counts: the running run's, read without the lock, else the last run's.
pub fn placementOf(k: usize) Placement {
    if (live_turns) |t| if (k < t.scheds.len) {
        const s = t.scheds[k];
        return .{ .placed = s.placed, .with_starter = s.with_starter, .live = s.live, .asks_across = s.asks_across };
    };
    return last_placement[k];
}
/// While a run lasts, where each scheduler's thread counts, so a signal can print them.
pub var live_stats: [most_cores]?*const region_mod.Stats = [_]?*const region_mod.Stats{null} ** most_cores;

/// How a thread held the lock before it let go, to take it again the same way.
pub const Held = struct { depth: u32 = 0 };

pub const Turns = struct {
    io: Io,
    gpa: std.mem.Allocator,
    sim: *Sim = undefined,
    /// One per core; [0] runs on main's thread.
    scheds: []*Sched = &.{},
    /// More than one scheduler: the lock is taken.
    multi: bool = false,
    /// How a process about to start is placed (`MO_PLACE`).
    placing: Placing = .starter,
    mutex: Io.Mutex = .init,
    /// Each process's scheduler, by process id.
    homes: std.ArrayList(u16) = .empty,
    /// One per process, made at its first delivery; indexed by process id.
    workers: std.ArrayList(?*Worker) = .empty,
    /// Updates on a fiber, running or waiting, on every scheduler.
    in_flight: u32 = 0,
    /// Asks waiting for their reply: the message's seq → who asked. This map, `answers`,
    /// and `parked` change with every ask, so they live in `std.heap.smp_allocator`, which
    /// frees, and not in the run's arena, which would keep each table a rehash leaves.
    awaiting: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    /// Replies that came: seq → the reply, or null when the target crashed on the message
    /// or a restart dropped it.
    answers: std.AutoHashMapUnmanaged(u64, ?Reply) = .empty,
    /// Events after which a process a start call began may have finished: its start, and
    /// each update of it that left its mailbox empty. A sweep runs when they reach
    /// `sweep_at`, twice the processes the last one left running, and at least sweep_min.
    quiet: u32 = 0,
    sweep_at: u32 = sweep_min,
    /// A sweep that could not stop the world waits until then.
    sweep_retry_at: i64 = 0,
    /// A sweep's marks, one per process id, and the marked ids whose start arguments it has
    /// yet to read.
    marks: std.ArrayList(bool) = .empty,
    worklist: std.ArrayList(u32) = .empty,
    /// The run's main vm, whose frames a sweep reads from any scheduler.
    main_vm: ?*Vm = null,
    /// The run is over: every scheduler's loop ends.
    stopping: bool = false,
    /// A scheduler's delivery failed past a crash (a supervisor gave up, or memory ran out): main
    /// ends the run with it at its next turn.
    failure: ?Error = null,
    /// A sweep waits for every update in progress to park or end (stopTurns): no update starts or
    /// resumes but on the sweeper's scheduler.
    sweeping: bool = false,
    sweeper: ?*Sched = null,
    /// Schedulers whose thread runs an update now, not parked.
    updating: u32 = 0,
    /// main waits for every other scheduler to rest (settle, finish).
    main_waits: bool = false,

    pub fn now(t: *const Turns) i64 {
        return Io.Clock.Timestamp.now(t.io, .awake).raw.toMilliseconds();
    }

    // ---- the schedulers

    /// The run's schedulers: `cores` of them, scheduler 0 on this thread compacting through
    /// `scratch`, each other through a scratch region of its own. With more than one, their threads
    /// start, and this thread holds the lock while main's code runs.
    pub fn begin(t: *Turns, sim: *Sim, main_vm: *Vm, cores: u32, placing: Placing, scratch: ?*Region) Error!void {
        t.sim = sim;
        t.placing = placing;
        t.main_vm = main_vm;
        const n = @max(cores, 1);
        t.scheds = std.heap.smp_allocator.alloc(*Sched, n) catch return error.OutOfMemory;
        for (t.scheds, 0..) |*slot, k| {
            const s = std.heap.smp_allocator.create(Sched) catch return error.OutOfMemory;
            s.* = .{ .index = @intCast(k), .stash_vm = main_vm };
            if (k == 0) {
                s.scratch = scratch;
            } else if (scratch != null) {
                s.own_scratch = Region.reserve() catch null;
                if (s.own_scratch) |*r| s.scratch = r;
            }
            slot.* = s;
        }
        t.multi = n > 1;
        last_cores = n;
        live_turns = t;
        sweeps_run = 0;
        sweeps_missed = 0;
        if (!t.multi) return;
        for (t.scheds) |s| {
            _ = try s.pollerOf();
            if (!s.wake.open()) return error.OutOfMemory;
        }
        here = t.scheds[0];
        live_stats[0] = &region_mod.stats;
        t.scheds[0].stats = &region_mod.stats;
        t.lock();
        for (t.scheds[1..]) |s| {
            s.thread = std.Thread.spawn(.{ .stack_size = 16 << 20 }, loop, .{ t, s }) catch return error.OutOfMemory;
        }
    }

    /// A scheduler's thread: hands out its turns until the run is over.
    fn loop(t: *Turns, s: *Sched) void {
        here = s;
        s.stats = &region_mod.stats;
        live_stats[s.index] = &region_mod.stats;
        t.lock();
        while (!t.stopping) {
            const worked = t.step(t.sim) catch |err| {
                t.failure = err;
                t.stir(t.scheds[0]);
                break;
            };
            if (worked) continue;
            t.rest(s);
            t.idle(t.sim, null, null);
        }
        region_mod.joined.add(region_mod.stats);
        last_stats[s.index] = region_mod.stats;
        live_stats[s.index] = null;
        t.unlock();
    }

    /// The scheduler running on this thread.
    pub fn cur(t: *Turns) *Sched {
        return if (t.multi) here.? else t.scheds[0];
    }

    /// The scheduler process `id` lives on.
    pub fn homeOf(t: *const Turns, id: u32) u32 {
        return if (id < t.homes.items.len) t.homes.items[id] else 0;
    }

    /// `holder` of the scheduler on this thread: main_turn when main's code or a loop holds it.
    pub fn holder(t: *Turns) u32 {
        return t.cur().holder;
    }

    /// The poller the runtime's loops wait in: scheduler 0's (sources.zig).
    pub fn sourcePoller(t: *Turns) Error!*Poller {
        return t.scheds[0].pollerOf();
    }

    pub fn madeSourcePoller(t: *Turns) ?*Poller {
        return if (t.scheds[0].poller) |*p| p else null;
    }

    /// Something was given to scheduler `s`: it looks again, woken when it waits in its poller.
    pub fn stir(t: *Turns, s: *Sched) void {
        s.resting = false;
        if (!t.multi or here == s) return;
        t.rouse(s);
    }

    /// Scheduler `s`'s thread is poked, and woken if it sleeps: through its wake when it sleeps in its
    /// poller, through its state when it sleeps on that (Turns.idle).
    fn rouse(t: *Turns, s: *Sched) void {
        switch (s.state.swap(thread_poked, .seq_cst)) {
            thread_sleeping => s.wake.signal(),
            thread_parked => Io.futexWake(t.io, u32, &s.state.raw, 1),
            else => {},
        }
    }

    /// Scheduler `s` found nothing to hand out.
    fn rest(t: *Turns, s: *Sched) void {
        s.resting = true;
        if (t.main_waits) t.stir(t.scheds[0]);
    }

    /// Every scheduler but main's has nothing to hand out.
    fn othersRest(t: *Turns) bool {
        if (t.sweeping) return false;
        for (t.scheds[1..]) |s| if (!s.resting or s.ready_head < s.ready.items.len or s.to_end.items.len > 0) return false;
        return true;
    }

    // ---- the lock

    /// Takes the runtime's lock, again if this thread holds it already. Nothing under one scheduler.
    pub fn lock(t: *Turns) void {
        if (!t.multi) return;
        const s = here.?;
        if (s.depth == 0) t.acquireLock(s);
        s.depth += 1;
    }

    pub fn unlock(t: *Turns) void {
        if (!t.multi) return;
        const s = here.?;
        s.depth -= 1;
        if (s.depth == 0) t.releaseLock(s);
    }

    /// A process's Mo code is about to run on this thread, or its region to compact: the lock goes,
    /// whatever its depth.
    pub fn beginMo(t: *Turns) Held {
        if (!t.multi) return .{};
        const s = here.?;
        const h: Held = .{ .depth = s.depth };
        if (s.depth > 0) {
            s.depth = 0;
            t.releaseLock(s);
        }
        return h;
    }

    /// What beginMo let run has returned: the lock is held as it was.
    pub fn endMo(t: *Turns, h: Held) void {
        if (!t.multi) return;
        const s = here.?;
        if (h.depth > 0 and s.depth == 0) t.acquireLock(s);
        s.depth = h.depth;
    }

    fn acquireLock(t: *Turns, s: *Sched) void {
        // The lock is held for a delivery's start or its commit, a few microseconds: a thread tries for
        // it a moment before it waits for it in the system.
        var k: u32 = 0;
        while (!t.mutex.tryLock()) : (k += 1) {
            if (k == lock_spins) {
                t.mutex.lockUncancelable(t.io);
                break;
            }
            std.atomic.spinLoopHint();
        }
        t.sim.vm = s.stash_vm;
        t.sim.running = s.stash_running;
    }

    fn releaseLock(t: *Turns, s: *Sched) void {
        s.stash_vm = t.sim.vm;
        s.stash_running = t.sim.running;
        t.mutex.unlock(t.io);
    }

    /// The scheduler waits outside the runtime with the lock let go (its poller, a sweep's wait, the
    /// run's end).
    fn letGo(t: *Turns, s: *Sched) Held {
        const h: Held = .{ .depth = s.depth };
        s.depth = 0;
        t.releaseLock(s);
        return h;
    }

    fn takeBack(t: *Turns, s: *Sched, h: Held) void {
        t.acquireLock(s);
        s.depth = h.depth;
    }

    /// A sweep waits for its turn: from now on no scheduler starts or resumes an update, and the sweep
    /// lets the lock go a moment at a time until every update in progress has parked or ended, as every
    /// update but the sweeper's own had when one thread swept. So no handle an update holds only on its
    /// operand stack, or a binary's in a C local, is missed. False, and the schedulers go on, when an
    /// update still ran after stop_wait_ms.
    fn stopTurns(t: *Turns, s: *Sched) bool {
        t.sweeping = true;
        t.sweeper = s;
        const limit = t.now() + stop_wait_ms;
        while (t.updating > 0) {
            if (t.now() >= limit) {
                t.startTurns();
                return false;
            }
            const h = t.letGo(s);
            Io.sleep(t.io, .fromMicroseconds(50), .awake) catch {};
            t.takeBack(s, h);
        }
        return true;
    }

    fn startTurns(t: *Turns) void {
        t.sweeping = false;
        t.sweeper = null;
        // Only the schedulers the sweep held back, or given something meanwhile, look again: waking
        // every scheduler at every sweep's end costs a thread's wake each (step 34).
        for (t.scheds) |x| if (x.held_back or !x.resting) {
            x.held_back = false;
            t.stir(x);
        };
    }

    /// A scheduler's thread goes from `from` to `to`: `updating` counts the schedulers whose thread runs
    /// an update now.
    fn counted(t: *Turns, from: u32, to: u32) void {
        if ((from == main_turn) == (to == main_turn)) return;
        if (to == main_turn) t.updating -= 1 else t.updating += 1;
    }

    // ---- placing

    /// Where a process about to start goes, and the id of the last process that ended there, if one
    /// waits: its starter's scheduler when an update starts it and that scheduler holds no more than
    /// place_factor times its share of the live processes (step 34), else the scheduler with the
    /// fewest live processes, the first of those tied.
    pub fn place(t: *Turns) struct { sched: u32, id: ?u32 } {
        const k = t.placeFor();
        const s = t.scheds[k];
        s.placed += 1;
        return .{ .sched = k, .id = s.free_ids.pop() };
    }

    fn placeFor(t: *Turns) u32 {
        if (t.multi and t.placing == .starter) {
            const s = t.cur();
            if (s.holder != main_turn) {
                var total: u32 = 1;
                for (t.scheds) |x| total += x.live;
                const n: u32 = @intCast(t.scheds.len);
                const share = (total + n - 1) / n;
                if (s.live + 1 <= place_factor * share) {
                    s.with_starter += 1;
                    return s.index;
                }
            }
        }
        var best: usize = 0;
        for (t.scheds, 0..) |s, k| if (s.live < t.scheds[best].live) {
            best = k;
        };
        return @intCast(best);
    }

    /// Process `id` started on scheduler `k`; `quiet` when a start call began it, so it may finish.
    pub fn placed(t: *Turns, id: u32, k: u32, quiet: bool) Error!void {
        while (t.homes.items.len <= id) try t.homes.append(t.gpa, 0);
        t.homes.items[id] = @intCast(k);
        t.scheds[k].live += 1;
        if (quiet) t.quiet += 1;
    }

    // ---- handing the thread over

    fn contextOf(t: *Turns, s: *Sched, id: u32) *fiber_mod.Context {
        return if (id == main_turn) &s.main_context else &t.workers.items[id].?.fiber.?.context;
    }

    /// Switches `s`'s thread to `to`, its loop or one of its processes with a fiber; returns when
    /// something switches back.
    fn switchTo(t: *Turns, s: *Sched, to: u32) void {
        const from = s.holder;
        const depth = vm_mod.call_depth;
        const lock_depth = s.depth;
        s.holder = to;
        t.counted(from, to);
        fiber_mod.switchTo(t.contextOf(s, from), t.contextOf(s, to));
        vm_mod.call_depth = depth;
        s.depth = lock_depth;
    }

    /// The holder hands the thread to process `id`, one of this scheduler's, to deliver its next
    /// message or to go on after a wait, and has it back when the update ends or waits again.
    fn handTo(t: *Turns, sim: *Sim, id: u32, job: Job) Error!void {
        const s = t.cur();
        const w = try t.worker(sim, id);
        const vm = sim.vm;
        const running = sim.running;
        w.caller = s.holder;
        w.phase = .running;
        if (job == .deliver) {
            const f = s.fibers.pop() orelse try Fiber.create(contracts.vm_stack_bytes);
            f.run = deliverOn;
            f.owner = t;
            f.arg = id;
            w.fiber = f;
            t.in_flight += 1;
        }
        t.switchTo(s, id);
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
        const s = t.scheds[t.homeOf(id)];
        while (t.workers.items.len <= id) try t.workers.append(t.gpa, null);
        if (t.workers.items[id]) |w| if (!w.ended) return w;
        const w = t.workers.items[id] orelse try t.gpa.create(Worker);
        if (t.workers.items[id] == null) {
            // Its lists stay on its scheduler's thread: under one scheduler, in the run's arena.
            const gpa = if (t.multi) s.arena.allocator() else sim.gpa;
            w.* = .{ .vm = .init(gpa, sim.vm.program, 0) };
        } else {
            // The worker of an ended process: its lists keep their room.
            w.vm.reuse();
            const vm = w.vm;
            w.* = .{ .vm = vm };
        }
        if (s.scratch) |sc| {
            w.values = reserveProcess(big_region, process_region, 0);
            if (w.values) |*r| w.vm.useRegions(r, sc);
        }
        w.vm.sim = sim;
        w.vm.server = sim.vm.server;
        // Each id is in its scheduler's ready queue at most once.
        try s.ready.ensureTotalCapacity(t.gpa, t.workers.items.len + 1);
        t.workers.items[id] = w;
        return w;
    }

    /// A fiber's job: one message delivered to process `f.arg`, then the thread and the fiber
    /// go back.
    fn deliverOn(f: *Fiber) void {
        const t: *Turns = @ptrCast(@alignCast(f.owner));
        const s = t.cur();
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
        s.fibers.append(std.heap.smp_allocator, f) catch {};
        // A loop paused at this process's bound may go on now that its mailbox drained.
        if (s.index != 0 and sim.sources.paused.items.len > 0) t.stir(t.scheds[0]);
        t.counted(id, w.caller);
        s.holder = w.caller;
        f.back = t.contextOf(s, w.caller);
    }

    fn pushReady(t: *Turns, id: u32) void {
        const s = t.scheds[t.homeOf(id)];
        const w = t.workers.items[id].?;
        if (w.queued) return;
        w.queued = true;
        if (s.ready_head > 0 and s.ready.items.len == s.ready.capacity) {
            const waiting = s.ready.items.len - s.ready_head;
            std.mem.copyForwards(u32, s.ready.items[0..waiting], s.ready.items[s.ready_head..]);
            s.ready.shrinkRetainingCapacity(waiting);
            s.ready_head = 0;
        }
        s.ready.appendAssumeCapacity(id);
        t.stir(s);
    }

    fn popReady(t: *Turns, s: *Sched) ?u32 {
        if (s.ready_head == s.ready.items.len) return null;
        const id = s.ready.items[s.ready_head];
        s.ready_head += 1;
        if (s.ready_head == s.ready.items.len) {
            s.ready.clearRetainingCapacity();
            s.ready_head = 0;
        }
        t.workers.items[id].?.queued = false;
        return id;
    }

    // ---- waiting

    /// A Net call's wait for `fd` to be ready, at most `ms`. main's code hands out turns until
    /// then; a process's update switches back to whoever handed it the thread and is switched
    /// to again when its scheduler's poller reports the socket or the deadline passes. True when
    /// ready.
    pub fn block(t: *Turns, sim: *Sim, fd: std.posix.fd_t, filter: poller_mod.Filter, ms: i64) Error!bool {
        const s = t.cur();
        const deadline = t.now() + @max(ms, 0);
        const p = try s.pollerOf();
        var w: Waiter = .{ .fd = fd, .filter = filter };
        if (s.holder == main_turn) {
            if (!p.arm(&w)) return true;
            defer p.disarm(&w);
            while (true) {
                if (w.fired) return true;
                if (t.now() >= deadline) return false;
                if (try t.step(sim)) continue;
                t.idle(sim, &w, deadline);
            }
        }
        const id = s.holder;
        w.process = id;
        if (!p.arm(&w)) return true;
        defer p.disarm(&w);
        const me = t.workers.items[id].?;
        const vm = sim.vm;
        const running = sim.running;
        // Woken early (a crash elsewhere wakes every parked process), it parks again.
        while (!w.fired and t.now() < deadline) {
            try t.parkOn(s, id, deadline);
            me.phase = .waiting;
            t.switchTo(s, me.caller);
        }
        sim.vm = vm;
        sim.running = running;
        return w.fired;
    }

    /// A process parks in an ask until the reply comes, the target goes down, or `deadline`.
    fn park(t: *Turns, sim: *Sim, deadline: i64) Error!void {
        const s = t.cur();
        const id = s.holder;
        const w = t.workers.items[id].?;
        const vm = sim.vm;
        const running = sim.running;
        try t.parkOn(s, id, deadline);
        w.phase = .waiting;
        t.switchTo(s, w.caller);
        sim.vm = vm;
        sim.running = running;
    }

    /// The update holding this thread gives it back and is handed it again once a sweep has ended:
    /// it waits in its scheduler's ready queue, which no step reads while the sweep waits.
    fn stepAside(t: *Turns, sim: *Sim) Error!void {
        const s = t.cur();
        const id = s.holder;
        const w = t.workers.items[id].?;
        const vm = sim.vm;
        const running = sim.running;
        w.phase = .waiting;
        t.pushReady(id);
        t.switchTo(s, w.caller);
        sim.vm = vm;
        sim.running = running;
    }

    /// Process `id`'s wait ended: it leaves its scheduler's parked list and is switched to next.
    fn wake(t: *Turns, id: u32) void {
        const s = t.scheds[t.homeOf(id)];
        if (t.workers.items[id].?.parked_at) |k| _ = t.unpark(s, k);
        t.pushReady(id);
    }

    /// Process `id` goes on `s`'s parked list until `deadline`.
    fn parkOn(t: *Turns, s: *Sched, id: u32, deadline: i64) Error!void {
        const w = t.workers.items[id].?;
        std.debug.assert(w.parked_at == null);
        try s.parked.append(std.heap.smp_allocator, .{ .id = id, .deadline = deadline });
        w.parked_at = @intCast(s.parked.items.len - 1);
        s.parked_due = @min(s.parked_due, deadline);
    }

    /// The process at `k` of `s`'s parked list leaves it, in constant time; its id.
    fn unpark(t: *Turns, s: *Sched, k: u32) u32 {
        const gone = s.parked.swapRemove(k);
        t.workers.items[gone.id].?.parked_at = null;
        if (k < s.parked.items.len) t.workers.items[s.parked.items[k].id].?.parked_at = k;
        if (s.parked.items.len == 0) s.parked_due = std.math.maxInt(i64);
        return gone.id;
    }

    /// A scheduler with no turn to hand out: waits in its poller until a socket something on it waits
    /// on is ready, `also` is reported, another scheduler wakes it, or the earliest deadline passes.
    fn idle(t: *Turns, sim: *Sim, also: ?*Waiter, deadline: ?i64) void {
        const s = t.cur();
        // While a sweep waits for its turn this scheduler hands nothing out (step), so it waits here
        // without the lock whatever it has ready, until the sweep's end pokes it.
        const held_back = t.sweeping and t.sweeper != s;
        if (held_back) s.held_back = true;
        if (!held_back and (s.ready_head < s.ready.items.len or s.to_end.items.len > 0)) return;
        if (also) |w| if (w.fired) return;
        if (t.failure != null or t.stopping) return;
        var until = deadline;
        if (s.index == 0) {
            if (!held_back and sources.hasWork(sim)) return;
            if (sources.nextDeadline(sim)) |d| until = if (until) |u| @min(u, d) else d;
            if (sim.nextLater()) |d| until = if (until) |u| @min(u, d) else d;
        }
        if (s.parked.items.len > 0) until = if (until) |u| @min(u, s.parked_due) else s.parked_due;
        const p = s.pollerOf() catch return;
        if (t.multi) _ = p.arm(&s.wake.waiter);
        // At least once a second, whatever the deadlines say: nothing waits past a lost report.
        const left: i64 = if (until) |u| @min(@max(u - t.now(), 0), 1000) else 1000;
        var n: usize = 0;
        if (t.multi) {
            // Nothing can be given it while it holds the lock, so a poke from here on is news.
            s.state.store(thread_spinning, .release);
            const h = t.letGo(s);
            // It spins a moment on the poke alone (step 34). One with a socket of its own armed also looks
            // at its poller now and then, without waiting: a reply that comes on a socket is as much news
            // as a poke. One with nothing armed but its wake never calls the system while it spins, since
            // a look at the poller costs as much as the handoff it waits for.
            const sockets = p.armed > 1;
            const began = Io.Clock.Timestamp.now(t.io, .awake);
            var k: u32 = 0;
            while (s.state.load(.acquire) != thread_poked) : (k += 1) {
                if (k % poll_every == poll_every - 1) {
                    if (sockets) {
                        n = p.wait(0, &s.fired);
                        if (n > 0) break;
                    }
                    const spun = began.durationTo(Io.Clock.Timestamp.now(t.io, .awake)).raw.toNanoseconds();
                    if (spun >= if (sockets) spin_sockets_ns else spin_ns) break;
                }
                std.atomic.spinLoopHint();
            }
            if (n == 0) {
                // Asleep only if no poke came, in the same exchange that says so: a poke that comes after
                // swaps the sleep out and wakes it. One with a socket armed sleeps in its poller, one with
                // none on its state, which costs less to wake than a descriptor.
                const sleep = if (sockets) thread_sleeping else thread_parked;
                if (s.state.cmpxchgStrong(thread_spinning, sleep, .seq_cst, .seq_cst) == null) {
                    if (sockets) {
                        n = p.wait(left, &s.fired);
                        s.polled_at = Io.Clock.Timestamp.now(t.io, .awake);
                    } else {
                        const d: Io.Clock.Duration = .{ .raw = .fromMilliseconds(left), .clock = .awake };
                        Io.futexWaitTimeout(t.io, u32, &s.state.raw, thread_parked, .{ .duration = d }) catch {};
                    }
                } else if (sockets and s.polled_at.durationTo(Io.Clock.Timestamp.now(t.io, .awake)).raw.toNanoseconds() >= poked_poll_ns) {
                    // Poked: its sockets are still looked at, without waiting, now and then, so a scheduler
                    // kept busy by pokes still hears them.
                    n = p.wait(0, &s.fired);
                    s.polled_at = Io.Clock.Timestamp.now(t.io, .awake);
                }
            }
            s.state.store(thread_running, .release);
            t.takeBack(s, h);
        } else n = p.wait(left, &s.fired);
        for (s.fired[0..n]) |w| {
            if (w == &s.wake.waiter) {
                s.wake.drain();
            } else if (w.process != poller_mod.nobody) {
                t.wake(w.process);
            } else if (w.source) |src| sources.fired(sim, @ptrCast(@alignCast(src)));
        }
    }

    /// One turn handed out on this thread's scheduler: to a process whose wait ended, else to the
    /// next process with a message waiting. False when there is none.
    fn step(t: *Turns, sim: *Sim) Error!bool {
        const s = t.cur();
        if (t.failure) |err| return err;
        // A sweep waits for the updates in progress to park or end: none starts or resumes meanwhile.
        if (t.sweeping and t.sweeper != s) {
            s.held_back = true;
            return false;
        }
        if (s.to_end.items.len > 0) t.endOwn(s);
        if (t.quiet >= t.sweep_at) try t.sweep(sim);
        while (s.fibers.items.len > kept_fibers) s.fibers.pop().?.destroy();
        // What the runtime's loops took becomes messages first (sources.zig), and delayed sends
        // whose time has come (step 24).
        if (s.index == 0) try sources.pumpServer(sim, t);
        _ = try sim.dueLater();
        const now_ms = t.now();
        if (now_ms >= s.parked_due) {
            // A deadline is due: the list is scanned, and the earliest left is found again.
            var due: i64 = std.math.maxInt(i64);
            var k: u32 = 0;
            while (k < s.parked.items.len) {
                const d = s.parked.items[k].deadline;
                if (d <= now_ms) {
                    t.pushReady(t.unpark(s, k));
                } else {
                    due = @min(due, d);
                    k += 1;
                }
            }
            s.parked_due = due;
        }
        while (t.popReady(s)) |id| {
            const w = t.workers.items[id].?;
            if (w.phase != .waiting or w.fiber == null) continue;
            try t.handTo(sim, id, .go_on);
            return true;
        }
        const n: u32 = @intCast(sim.procs.items.len);
        if (n == 0) return false;
        const from = s.cursor % n;
        const id = t.nextRunnable(sim, s, from, n) orelse t.nextRunnable(sim, s, 0, from) orelse return false;
        s.cursor = id + 1;
        try t.handTo(sim, id, .deliver);
        return true;
    }

    /// Sim.enqueue put a message in process `id`'s mailbox.
    pub fn markRunnable(t: *Turns, id: u32) Error!void {
        const s = t.scheds[t.homeOf(id)];
        if (id >= s.runnable.bit_length) try s.runnable.resize(t.gpa, @max(2 * s.runnable.bit_length, id + 64), false);
        s.runnable.set(id);
        t.stir(s);
    }

    /// The first of `s`'s processes in [from, to) that is up, not on a stack, and has a message
    /// waiting. A marked process whose mailbox is empty, or that is down, is unmarked on the way.
    fn nextRunnable(t: *Turns, sim: *Sim, s: *Sched, from: u32, to: u32) ?u32 {
        _ = t;
        const bits = @bitSizeOf(usize);
        var i: usize = from;
        const stop_at = @min(to, s.runnable.bit_length);
        while (i < stop_at) {
            const word = s.runnable.masks[i / bits] >> @intCast(i % bits);
            if (word == 0) {
                i = (i / bits + 1) * bits;
                continue;
            }
            i += @ctz(word);
            if (i >= stop_at) break;
            const p = &sim.procs.items[i];
            if (!p.up or p.queued() == 0) {
                s.runnable.unset(i);
            } else if (!p.busy and !p.paused) {
                return @intCast(i);
            }
            i += 1;
        }
        return null;
    }

    // ---- ending finished processes

    /// Holding the lock: ends every process that has finished. One has when a start call began it (a
    /// child line's never ends), its mailbox is empty, no update of it is on a stack, and no handle
    /// to it is where anything could use it: in a frame of main or of an update on a stack, in the
    /// start arguments of a process that has not finished, in the state of a process that is up
    /// (step 24), in a send an update holds, or in a reply not yet taken. With more than one
    /// scheduler it first waits for every update in progress to park or end (stopTurns). Its parcels
    /// are freed at once; its scheduler frees its region and gives its id to the next process started
    /// there.
    fn sweep(t: *Turns, sim: *Sim) Error!void {
        const s = t.cur();
        if (t.multi) {
            if (t.sweeping or t.now() < t.sweep_retry_at) return;
            if (!t.stopTurns(s)) {
                t.sweep_retry_at = t.now() + sweep_retry_ms;
                sweeps_missed += 1;
                return;
            }
        }
        sweeps_run += 1;
        defer if (t.multi) t.startTurns();
        const gpa = std.heap.smp_allocator;
        const procs = sim.procs.items;
        try t.marks.resize(gpa, procs.len);
        @memset(t.marks.items, false);
        t.worklist.clearRetainingCapacity();
        // main's vm: its frames stand still while anything else holds the lock.
        const main_vm = if (t.multi) t.main_vm.? else sim.vm;
        for (main_vm.handle_frames.items) |locals| try t.markValues(locals);
        for (procs, 0..) |p, id| {
            if (p.ended or finished(p)) continue;
            try t.markValues(p.args);
            // A state may keep handles (step 24); a process that is down keeps none.
            if (p.up) try t.markValue(p.state);
            // A message may carry a handle (step 20): one waiting in a mailbox or held in an
            // outbox reaches its process.
            for (p.mailbox.items[p.head..]) |e| try t.markValue(e.message);
            if (!p.busy) continue;
            const w = t.workers.items[id].?;
            for (w.vm.handle_frames.items) |locals| try t.markValues(locals);
            for (p.outbox.items) |o| {
                try t.markId(o.to);
                try t.markValue(o.message);
            }
        }
        var answers = t.answers.valueIterator();
        while (answers.next()) |reply| if (reply.*) |r| try t.markValue(r.value);
        // A source's target is where the runtime keeps sending, and a delayed send's is where the
        // runtime will (step 24).
        for (sim.sources.list.items) |src| if (!src.done) try t.markId(src.to);
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
        // Under one scheduler its Vms and regions are freed now, as before step 30.
        if (!t.multi) t.endOwn(t.scheds[0]);
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

    /// Process `id` has finished: its parcels are freed, and its scheduler is given the rest.
    fn end(t: *Turns, sim: *Sim, id: u32) Error!void {
        const t0 = Io.Clock.Timestamp.now(t.io, .awake);
        defer {
            region_mod.stats.freed += 1;
            region_mod.stats.freed_ns += @intCast(t0.durationTo(Io.Clock.Timestamp.now(t.io, .awake)).raw.toNanoseconds());
        }
        sim.record(.{ .kind = .ended, .process = id });
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
        const s = t.scheds[t.homeOf(id)];
        s.live -= 1;
        try s.to_end.append(std.heap.smp_allocator, id);
        t.stir(s);
    }

    /// On `s`'s own thread, or under one scheduler: the processes a sweep ended here give back what
    /// their Vms kept, their emptied regions wait for the next processes given their ids, and the
    /// regions of more than kept_workers ended ids are released.
    fn endOwn(t: *Turns, s: *Sched) void {
        for (s.to_end.items) |id| {
            if (id < t.workers.items.len) if (t.workers.items[id]) |w| if (!w.ended) {
                w.vm.reuse();
                if (w.values) |*r| {
                    r.decommit();
                    w.vm.useRegions(r, s.scratch.?);
                }
            };
            s.free_ids.append(std.heap.smp_allocator, id) catch {};
        }
        s.to_end.clearRetainingCapacity();
        const ids = s.free_ids.items;
        if (ids.len > kept_workers) for (ids[0 .. ids.len - kept_workers]) |id| t.release(id);
    }

    /// The region kept for ended process `id` is released.
    fn release(t: *Turns, id: u32) void {
        if (id >= t.workers.items.len) return;
        const w = t.workers.items[id] orelse return;
        if (w.ended) return;
        if (w.values) |*r| releaseProcess(r);
        w.values = null;
        w.ended = true;
    }

    // ---- what Mo.Sim asks of the scheduler under Mo.Server

    /// `h.ask(message, within: d)`, with `d` in wall-clock time. On the target's own scheduler its
    /// waiting messages are delivered first, as in Mo.Sim; while it cannot answer, main hands out
    /// turns and a process parks. `Timeout` at the deadline, or at once when the target's update is
    /// itself waiting on this call; `Down` when the target is down, crashed on the message, or
    /// dropped it restarting. A Timeout's message still arrives.
    pub fn ask(t: *Turns, sim: *Sim, to: u32, message: Value, within: i64) Error!Value {
        const s = t.cur();
        if (!sim.procs.items[to].up) return sim.askError("Down");
        try sim.roomFor(to, message);
        const parcel: ?*Parcel = if (sim.packs) try sim.vm.pack(message) else null;
        const seq = try sim.enqueue(sim.running orelse sim_mod.test_runner, to, if (parcel) |p| p.value else message, parcel);
        try t.awaiting.put(std.heap.smp_allocator, seq, s.holder);
        const deadline = t.now() + @max(within, 0);
        const target = &sim.procs.items[to];
        target.mailbox.items[target.mailbox.items.len - 1].deadline = deadline;
        const same = t.homeOf(to) == s.index;
        if (!same) s.asks_across += 1;
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
            // On one scheduler the target's update holds the thread only when it handed it here; on
            // another, it waits on this call when the asks its update waits in lead back here.
            const running = p.busy and if (same) t.workers.items[to].?.phase == .running else t.waitsOn(sim, to, s.holder);
            if (!p.up or running or t.now() >= deadline) {
                _ = t.awaiting.remove(seq);
                return sim.askError(if (p.up) "Timeout" else "Down");
            }
            if (same and t.multi and s.holder != main_turn and (if (t.sweeping) t.sweeper != s else t.quiet >= t.sweep_at)) {
                // A sweep waits, or is due, and waits for every update in progress to park or end: this
                // one steps aside at its ask rather than deliver on its own thread, so its scheduler's
                // loop may sweep, and goes on after (step 34: with its targets on its own scheduler, a
                // spawner never parked, sweeps missed, and ended processes piled up).
                try t.stepAside(sim);
            } else if (same and !p.busy and !p.paused and p.queued() > 0) {
                try t.handTo(sim, to, .deliver);
            } else if (s.holder != main_turn) {
                try t.park(sim, deadline);
            } else if (!try t.step(sim)) {
                t.idle(sim, null, deadline);
            }
        }
    }

    /// Whether process `to`'s update waits, through the asks it and its targets wait in, on process
    /// `me`'s.
    fn waitsOn(t: *Turns, sim: *Sim, to: u32, me: u32) bool {
        _ = t;
        if (me == main_turn) return false;
        var x = to;
        for (0..sim.procs.items.len) |_| {
            const q = sim.procs.items[x];
            if (!q.busy or q.asking == sim_mod.test_runner) return false;
            if (q.asking == me) return true;
            x = q.asking;
        }
        return false;
    }

    /// The surface reads process `id` between updates (surface.zig, step 23): while an update of it
    /// is on a stack, main hands out turns and a process parks, a millisecond at a time, at most
    /// `within`. True once none is.
    pub fn waitIdle(t: *Turns, sim: *Sim, id: u32, within: i64) Error!bool {
        const s = t.cur();
        const deadline = t.now() + @max(within, 0);
        while (sim.procs.items[id].busy) {
            const now_ms = t.now();
            if (now_ms >= deadline) return false;
            if (s.holder != main_turn) {
                try t.park(sim, @min(deadline, now_ms + 1));
            } else if (!try t.step(sim)) t.idle(sim, null, @min(deadline, now_ms + 1));
        }
        return true;
    }

    /// Between two of main's statements: every turn there is to hand out, without waiting for a
    /// socket or a deadline, on every scheduler.
    pub fn settle(t: *Turns, sim: *Sim) Error!void {
        while (true) {
            while (try t.step(sim)) {}
            if (!t.multi or t.othersRest()) return;
            t.main_waits = true;
            t.idle(sim, null, null);
            t.main_waits = false;
        }
    }

    /// main returned: turns go on being handed out until no message waits, no update is in
    /// progress, no runtime loop can deliver, and no delayed send is still to come (step 24). After
    /// exit, only until nothing can run without waiting (step 29).
    pub fn finish(t: *Turns, sim: *Sim) Error!void {
        while (true) {
            if (try t.step(sim)) continue;
            const others = !t.multi or t.othersRest();
            if (sim.exiting and others) return;
            if (others and t.in_flight == 0 and !sim.sources.active() and sim.later.items.len == 0) return;
            t.main_waits = true;
            t.idle(sim, null, null);
            t.main_waits = false;
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
        if (kv.value == main_turn) return t.stir(t.scheds[0]);
        if (t.workers.items[kv.value].?.parked_at != null) t.wake(kv.value);
    }

    /// A process crashed: every parked process looks at what it waits for again.
    pub fn wakeAll(t: *Turns) void {
        for (t.scheds) |s| {
            for (s.parked.items) |p| {
                t.workers.items[p.id].?.parked_at = null;
                t.pushReady(p.id);
            }
            s.parked.clearRetainingCapacity();
            s.parked_due = std.math.maxInt(i64);
        }
        if (t.multi) t.stir(t.scheds[0]);
    }

    /// Delayed sends changed: scheduler 0, which moves them, looks again (Sim.pushLater).
    pub fn laterChanged(t: *Turns) void {
        if (t.multi) t.stir(t.scheds[0]);
    }

    /// The run is over: every scheduler's thread ends. An update still waiting when it ends is left
    /// where it is.
    pub fn stop(t: *Turns, sim: *Sim) void {
        if (t.scheds.len == 0) return;
        ids_used = sim.procs.items.len;
        sources.stopServer(sim, t);
        if (t.multi) {
            t.stopping = true;
            for (t.scheds[1..]) |s| {
                s.wake.signal();
                t.rouse(s);
            }
            const main_sched = t.scheds[0];
            const h = t.letGo(main_sched);
            for (t.scheds[1..]) |s| if (s.thread) |th| th.join();
            t.takeBack(main_sched, h);
            last_stats[0] = region_mod.stats;
            live_stats[0] = null;
        }
        for (t.workers.items) |slot| {
            const w = slot orelse continue;
            if (w.ended or w.fiber != null) continue;
            if (w.values) |*r| releaseProcess(r);
            w.values = null;
            w.ended = true;
        }
        for (0..t.scheds.len) |k| last_placement[k] = placementOf(k);
        live_turns = null;
        for (t.scheds) |s| {
            for (s.fibers.items) |f| f.destroy();
            s.fibers.clearRetainingCapacity();
            if (s.poller) |*p| p.deinit();
            s.poller = null;
            s.wake.close();
            if (s.own_scratch) |*r| r.release();
            s.own_scratch = null;
            s.scratch = null;
        }
        if (t.multi) {
            t.unlock();
            here = null;
        }
    }
};
