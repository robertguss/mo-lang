//! The runtime surface (design-v0/03, the runtime surface; directions 37 and 40; step 23): the
//! rows of a `Runtime`, the capability `platform.runtime` holds under `mo run` and a test's
//! `Runtime.fixture()` holds under `mo test`. A read is a snapshot taken between updates: every
//! update runs on one thread (turns.zig), so no other update is inside its transaction while a row
//! runs, and a process whose update is waiting on a stack is read once that update ends, within the
//! row's deadline. `send`, `pause`, and `resume` act, each an event (events.zig), and a Runtime
//! narrowed by `read_only` refuses them with `ReadOnly`. runtime/mo_rt.c runs the same rows for a
//! built program.
const std = @import("std");
const builtin = @import("builtin");
const check = @import("check.zig");
const events = @import("events.zig");
const sim_mod = @import("sim.zig");
const sources = @import("sources.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");

const bytecode = @import("bytecode.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;
const Sim = sim_mod.Sim;

pub const Row = enum { processes, state, recent, events, crashes, sources, memory, slowest, send, pause, @"resume", read_only };

/// `Value.Cap.handle` of a Runtime narrowed by `read_only`.
pub const read_only_handle: u32 = 1;
/// The processes `memory().largest` lists, at most.
pub const largest_listed: usize = 5;

const scratch = std.heap.smp_allocator;

fn crash(vm: *Vm, clause: []const u8) Error {
    vm.report = .{ .kind = .other, .clause = clause, .within = "Runtime", .at = 0 };
    return error.Crash;
}

/// A row: `a` is the receiver, its parameters and named parameters in row order, then `within:`.
pub fn call(vm: *Vm, which: Row, a: []const Value) Error!Value {
    if (which == .read_only) return .{ .cap = .{ .kind = .runtime, .handle = read_only_handle } };
    const sim = vm.sim orelse return crash(vm, "a Runtime answers only under mo run or mo test");
    const acts = a[0].cap.handle != read_only_handle;
    const within = a[a.len - 1].duration;
    // In a test, a finished process nothing can reach is found ended here (step 24).
    if (which == .processes or which == .state or which == .memory) try sim.sweepEnded();
    return switch (which) {
        .processes => processes(vm, sim),
        .state => state(vm, sim, a[1], within),
        .recent => recent(vm, sim, a[1], a[2]),
        .events => since(vm, sim, a[1].time, a[2]),
        .crashes => crashes(vm, sim, a[1]),
        .sources => sourceList(vm, sim),
        .memory => memory(vm, sim),
        .slowest => slowest(vm, sim, a[1]),
        .send => if (acts) send(vm, sim, a[1], a[2].string) else failure(vm, "ReadOnly"),
        .pause, .@"resume" => if (acts) hold(vm, sim, a[1], which == .pause) else failure(vm, "ReadOnly"),
        .read_only => unreachable,
    };
}

// ---- the HTTP form (surface.mo)

/// The module `program.withSurface` puts first: its path, the function that serves it, and its process.
pub const module_path = "Mo.Surface";

/// `serve_surface`'s signature in a program whose first module is the surface's.
pub fn sigOf(k: *const check.Checked) ?u32 {
    if (k.modules.len == 0 or !std.mem.eql(u8, k.modules[0].path, module_path)) return null;
    for (k.sigs, 0..) |s, i| {
        if (s.kind == .module and std.mem.eql(u8, s.name, "serve_surface") and k.moduleOf(s.node) == 0) return @intCast(i);
    }
    return null;
}

/// The `Surface` process's declaration in such a program.
pub fn declOf(k: *const check.Checked) ?u32 {
    if (k.modules.len == 0 or !std.mem.eql(u8, k.modules[0].path, module_path)) return null;
    for (k.decls, 0..) |d, i| {
        if (d.kind == .process and d.module == 0 and std.mem.eql(u8, d.name, "Surface")) return @intCast(i);
    }
    return null;
}

pub const Entry = struct { function: u32, process: u32 };

/// Where `mo run --surface` starts the surface: `serve_surface`'s function and the index of the
/// `Surface` process, which the surface does not show.
pub fn entry(program: *const bytecode.Program) ?Entry {
    const sig = sigOf(&program.checked) orelse return null;
    const decl = declOf(&program.checked) orelse return null;
    for (program.processes, 0..) |p, i| {
        if (p.decl == decl) return .{ .function = program.fn_of_sig[sig], .process = @intCast(i) };
    }
    return null;
}

// ---- values

fn uint(n: anytype) Value {
    return .{ .int = @intCast(n) };
}

fn str(s: []const u8) Value {
    return .{ .string = s };
}

fn list(vm: *Vm, items: []const Value) Error!Value {
    const out = try vm_mod.rawAlloc(vm.heap, Value, items.len);
    @memcpy(out, items);
    return .{ .list = out };
}

fn record(vm: *Vm, name: []const u8, fields: []const Value) Error!Value {
    const out = try vm_mod.rawAlloc(vm.heap, Value, fields.len);
    @memcpy(out, fields);
    return .{ .record = .{ .decl = vm.program.checked.preludeStruct(name).?, .fields = out } };
}

fn failure(vm: *Vm, name: []const u8) Error!Value {
    return vm.variant("Error", &.{try vm.variant(name, &.{})});
}

fn done(vm: *Vm) Error!Value {
    return vm.variant("Ok", &.{.none});
}

/// Text made here, in the calling vm's memory.
fn text(vm: *Vm, s: []const u8) Error![]const u8 {
    const out = try vm_mod.rawAlloc(vm.heap, u8, s.len);
    @memcpy(out, s);
    return out;
}

/// A process id a row was given, when a process that has not ended has it.
fn idOf(sim: *const Sim, v: Value) ?u32 {
    if (v.int < 0 or v.int >= sim.procs.items.len) return null;
    const id: u32 = @intCast(v.int);
    if (sim.procs.items[id].ended or sim.hidden(id)) return null;
    return id;
}

/// `n` of a row, no more than there are.
fn count(v: Value, there: usize) usize {
    return @intCast(@min(@max(v.int, 0), there));
}

// ---- reads

fn processes(vm: *Vm, sim: *Sim) Error!Value {
    var out: std.ArrayList(Value) = .empty;
    defer out.deinit(scratch);
    for (sim.procs.items, 0..) |p, id| {
        if (p.ended or sim.hidden(@intCast(id))) continue;
        try out.append(scratch, try info(vm, sim, @intCast(id)));
    }
    return list(vm, out.items);
}

fn info(vm: *Vm, sim: *Sim, id: u32) Error!Value {
    const p = sim.procs.items[id];
    const waiting = if (p.busy and p.waiting.len > 0) try vm.variant("Some", &.{str(p.waiting)}) else try vm.variant("None", &.{});
    return record(vm, "ProcessInfo", &.{
        uint(id),
        str(sim.nameOf(id)),
        .{ .bool = p.up },
        uint(p.queued()),
        uint(vm.program.processes[p.process].mailbox),
        waiting,
        uint(p.restarted),
        uint(regionBytes(sim, id)),
        .{ .bool = p.paused },
    });
}

fn regionBytes(sim: *const Sim, id: u32) u64 {
    const t = sim.turns orelse return 0;
    if (id >= t.workers.items.len) return 0;
    const w = t.workers.items[id] orelse return 0;
    if (w.ended) return 0;
    const r = w.values orelse return 0;
    return r.top - r.base;
}

fn state(vm: *Vm, sim: *Sim, id_value: Value, within: i64) Error!Value {
    const id = idOf(sim, id_value) orelse return failure(vm, "NoProcess");
    // Between two updates: one waiting on a stack is read once it ends.
    if (sim.procs.items[id].busy) {
        const t = sim.turns orelse return failure(vm, "Timeout");
        if (sim.running == id or !try t.waitIdle(sim, id, within)) return failure(vm, "Timeout");
    }
    var aw: std.Io.Writer.Allocating = .init(scratch);
    defer aw.deinit();
    vm.formatValue(&aw.writer, sim.procs.items[id].state) catch return error.OutOfMemory;
    return vm.variant("Ok", &.{str(try text(vm, aw.written()))});
}

fn recent(vm: *Vm, sim: *Sim, id_value: Value, n: Value) Error!Value {
    const ring = &sim.ring;
    const want = count(n, ring.len);
    var picked: std.ArrayList(Value) = .empty;
    defer picked.deinit(scratch);
    var i = ring.len;
    while (i > 0 and picked.items.len < want) {
        i -= 1;
        const e = ring.get(i);
        if (e.process == id_value.int) try picked.append(scratch, try eventValue(vm, sim, e));
    }
    std.mem.reverse(Value, picked.items);
    return list(vm, picked.items);
}

fn since(vm: *Vm, sim: *Sim, time: i64, n: Value) Error!Value {
    const ring = &sim.ring;
    const from = ring.firstSince(ring.monoOf(time));
    const out = try vm_mod.rawAlloc(vm.heap, Value, count(n, ring.len - from));
    for (out, from..) |*o, i| o.* = try eventValue(vm, sim, ring.get(i));
    return .{ .list = out };
}

fn crashes(vm: *Vm, sim: *Sim, n: Value) Error!Value {
    const ring = &sim.ring;
    const want = count(n, ring.len);
    var picked: std.ArrayList(Value) = .empty;
    defer picked.deinit(scratch);
    var i = ring.len;
    while (i > 0 and picked.items.len < want) {
        i -= 1;
        const e = ring.get(i);
        if (e.kind == .crashed) try picked.append(scratch, try eventValue(vm, sim, e));
    }
    std.mem.reverse(Value, picked.items);
    return list(vm, picked.items);
}

/// The `n` longest updates the ring holds, longest first; of two as long, the earlier first.
fn slowest(vm: *Vm, sim: *Sim, n: Value) Error!Value {
    const ring = &sim.ring;
    var updates: std.ArrayList(events.Event) = .empty;
    defer updates.deinit(scratch);
    for (0..ring.len) |i| {
        const e = ring.get(i);
        if (e.kind == .updated) try updates.append(scratch, e);
    }
    std.sort.block(events.Event, updates.items, {}, struct {
        fn longer(_: void, x: events.Event, y: events.Event) bool {
            return x.took_us > y.took_us;
        }
    }.longer);
    const out = try vm_mod.rawAlloc(vm.heap, Value, count(n, updates.items.len));
    for (out, updates.items[0..out.len]) |*o, e| o.* = try eventValue(vm, sim, e);
    return .{ .list = out };
}

fn sourceList(vm: *Vm, sim: *Sim) Error!Value {
    var out: std.ArrayList(Value) = .empty;
    defer out.deinit(scratch);
    for (sim.sources.list.items) |s| {
        // A request being read counts in its listener's in flight.
        if (s.done or s.kind == .request or sim.hidden(s.to)) continue;
        try out.append(scratch, try record(vm, "SourceInfo", &.{
            str(sources.rowLabel(s.kind)),
            uint(s.to),
            str(sim.nameOf(s.to)),
            uint(s.inflight),
            .{ .bool = s.paused },
        }));
    }
    return list(vm, out.items);
}

fn memory(vm: *Vm, sim: *Sim) Error!Value {
    const Sized = struct { id: u32, bytes: u64 };
    var sized: std.ArrayList(Sized) = .empty;
    defer sized.deinit(scratch);
    var regions: u64 = if (sim.main_region) |r| r.top - r.base else 0;
    // The pages the regions keep resident, the scratch region's included (step 28).
    var resident_regions: u64 = if (sim.main_region) |r| r.resident(scratch) else 0;
    if (sim.turns) |t| {
        if (t.scratch) |sc| resident_regions += sc.resident(scratch);
        for (t.workers.items) |maybe| {
            const w = maybe orelse continue;
            if (w.ended) continue;
            if (w.values) |*r| resident_regions += r.resident(scratch);
        }
    }
    for (sim.procs.items, 0..) |p, id| {
        if (p.ended or sim.hidden(@intCast(id))) continue;
        const bytes = regionBytes(sim, @intCast(id));
        regions += bytes;
        try sized.append(scratch, .{ .id = @intCast(id), .bytes = bytes });
    }
    std.sort.block(Sized, sized.items, {}, struct {
        fn larger(_: void, x: Sized, y: Sized) bool {
            return x.bytes > y.bytes;
        }
    }.larger);
    const largest = try vm_mod.rawAlloc(vm.heap, Value, @min(largest_listed, sized.items.len));
    for (largest, sized.items[0..largest.len]) |*o, s| o.* = try info(vm, sim, s.id);
    return record(vm, "MemoryInfo", &.{
        uint(resident()),
        uint(regions),
        uint(resident_regions),
        uint(vm_mod.packed_bytes),
        uint(sim.ring.bytes()),
        .{ .list = largest },
    });
}

/// The program's resident memory now, in bytes; where the system does not say, the most it has been.
pub fn resident() u64 {
    if (comptime builtin.os.tag.isDarwin()) {
        var got: std.c.mach_task_basic_info = undefined;
        var n: std.c.mach_msg_type_number_t = std.c.MACH.TASK.BASIC.INFO_COUNT;
        if (std.c.task_info(std.c.mach_task_self(), std.c.MACH.TASK.BASIC.INFO, @ptrCast(&got), &n) != 0) return 0;
        return got.resident_size;
    }
    // Linux says what is resident now, as runtime/mo_rt.c reads it (step 28: the most it had been
    // hid what a replay gave back).
    if (comptime builtin.os.tag == .linux) {
        const linux = std.os.linux;
        var buf: [128]u8 = undefined;
        const opened = linux.open("/proc/self/statm", .{ .ACCMODE = .RDONLY }, 0);
        if (std.posix.errno(opened) != .SUCCESS) return 0;
        const fd: i32 = @intCast(opened);
        defer _ = linux.close(fd);
        const got = linux.read(fd, &buf, buf.len);
        if (std.posix.errno(got) != .SUCCESS) return 0;
        const n: usize = got;
        var fields = std.mem.tokenizeScalar(u8, buf[0..n], ' ');
        _ = fields.next();
        const pages = std.fmt.parseInt(u64, fields.next() orelse return 0, 10) catch return 0;
        return pages * std.heap.pageSize();
    }
    const usage = std.posix.getrusage(0);
    return @as(u64, @intCast(usage.maxrss)) * 1024;
}

/// One event as the prelude's `Event` enum spells it.
fn eventValue(vm: *Vm, sim: *const Sim, e: events.Event) Error!Value {
    const at: Value = .{ .time = sim.ring.timeOf(e) };
    const id = uint(e.process);
    const name = str(e.process_name);
    return switch (e.kind) {
        .updated => vm.variant("Updated", &.{ at, id, name, str(e.name), uint(e.took_us), uint(e.waited_us), str(e.call) }),
        .started => vm.variant("Started", &.{ at, id, name }),
        .ended => vm.variant("Ended", &.{ at, id, name }),
        .restarted => vm.variant("Restarted", &.{ at, id, name, uint(e.count) }),
        .crashed => vm.variant("Crashed", &.{ at, id, name, uint(e.seed), str(e.clause), str(e.message), str(e.state) }),
        .overflowed => vm.variant("Overflowed", &.{ at, try maybeId(vm, e.other), str(who(sim, e.other, e.other_name)), id, name }),
        .timed_out => vm.variant("TimedOut", &.{ at, try maybeId(vm, e.process), str(who(sim, e.process, e.process_name)), str(e.call) }),
        .source_paused => vm.variant("SourcePaused", &.{ at, str(e.name), id, name, uint(e.count) }),
        .source_resumed => vm.variant("SourceResumed", &.{ at, str(e.name), id, name, uint(e.count) }),
        .sent => vm.variant("Sent", &.{ at, id, name, str(e.message) }),
        .paused => vm.variant("Paused", &.{ at, id, name }),
        .resumed => vm.variant("Resumed", &.{ at, id, name }),
        .dropped => vm.variant("Dropped", &.{ at, try maybeId(vm, e.other), str(who(sim, e.other, e.other_name)), id, name, str(e.message), str(e.name) }),
    };
}

fn maybeId(vm: *Vm, id: u32) Error!Value {
    return if (id == events.nobody) vm.variant("None", &.{}) else vm.variant("Some", &.{uint(id)});
}

/// A process's name, or who acts from outside one.
fn who(sim: *const Sim, id: u32, name: []const u8) []const u8 {
    if (id != events.nobody) return name;
    return if (sim.server != null) "main" else "the test";
}

// ---- acts

fn send(vm: *Vm, sim: *Sim, id_value: Value, message_text: []const u8) Error!Value {
    const id = idOf(sim, id_value) orelse return failure(vm, "NoProcess");
    const p = sim.procs.items[id];
    if (!p.up) return failure(vm, "NoProcess");
    const process = vm.program.processes[p.process];
    var parser: Parser = .{ .vm = vm, .k = &vm.program.checked, .text = message_text };
    const message = parser.message(process.decl) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Malformed => {
            defer scratch.free(parser.why);
            return vm.variant("Error", &.{try vm.variant("Unparsed", &.{str(try text(vm, parser.why))})});
        },
    };
    if (p.queued() >= process.mailbox) return failure(vm, "MailboxFull");
    const parcel = if (sim.packs) try vm.pack(message) else null;
    _ = try sim.enqueue(sources.runtime_sender, id, if (parcel) |x| x.value else message, parcel);
    sim.record(.{ .kind = .sent, .process = id, .name = message.variant.name, .message = try sim.gpa.dupe(u8, message_text) });
    return done(vm);
}

fn hold(vm: *Vm, sim: *Sim, id_value: Value, pause: bool) Error!Value {
    const id = idOf(sim, id_value) orelse return failure(vm, "NoProcess");
    const p = &sim.procs.items[id];
    p.paused = pause;
    sim.record(.{ .kind = if (pause) .paused else .resumed, .process = id });
    if (!pause and p.queued() > 0) if (sim.turns) |t| try t.markRunnable(id);
    return done(vm);
}

/// A message a process declares, from the text a report prints it as: `Vote(n: 3)`, `Total`,
/// `Add(text: "a", at: Time.fixture() + 5.ms)`. A field of one message may also be written without
/// its name, as a report prints it. Maps, sets, capabilities, and handles are not made from text.
const Parser = struct {
    vm: *Vm,
    k: *const check.Checked,
    text: []const u8,
    at: usize = 0,
    /// Why the text is not a message, in `scratch`.
    why: []const u8 = "",

    const Fail = error{ Malformed, OutOfMemory };

    fn fail(p: *Parser, comptime fmt: []const u8, args: anytype) Fail {
        const what = std.fmt.allocPrint(scratch, fmt, args) catch return error.OutOfMemory;
        defer scratch.free(what);
        p.why = std.fmt.allocPrint(scratch, "{s}, at byte {d}", .{ what, p.at }) catch return error.OutOfMemory;
        return error.Malformed;
    }

    fn space(p: *Parser) void {
        while (p.at < p.text.len and std.ascii.isWhitespace(p.text[p.at])) p.at += 1;
    }

    fn eat(p: *Parser, s: []const u8) bool {
        p.space();
        if (!std.mem.startsWith(u8, p.text[p.at..], s)) return false;
        p.at += s.len;
        return true;
    }

    fn expect(p: *Parser, s: []const u8) Fail!void {
        if (!p.eat(s)) return p.fail("expected {s}", .{s});
    }

    fn name(p: *Parser) []const u8 {
        p.space();
        const start = p.at;
        while (p.at < p.text.len and (std.ascii.isAlphanumeric(p.text[p.at]) or p.text[p.at] == '_' or p.text[p.at] == '?')) p.at += 1;
        return p.text[start..p.at];
    }

    /// A message of process declaration `d`, and nothing after it.
    fn message(p: *Parser, d: u32) Fail!Value {
        const v = try p.variantOf(p.k.decls[d].variants, "a message this process declares");
        p.space();
        if (p.at != p.text.len) return p.fail("{s} is followed by more text", .{v.variant.name});
        return v;
    }

    fn variantOf(p: *Parser, range: anytype, what: []const u8) Fail!Value {
        const n = p.name();
        const def = for (p.k.variants[range.start..range.end]) |x| {
            if (std.mem.eql(u8, x.name, n)) break x;
        } else return p.fail("{s} is not {s}", .{ if (n.len == 0) "nothing" else n, what });
        const fields = try p.fieldsOf(p.k.fields[def.fields.start..def.fields.end], def.name);
        return p.vm.variant(def.name, fields) catch error.OutOfMemory;
    }

    fn fieldsOf(p: *Parser, fields: []const check.Field, owner: []const u8) Fail![]const Value {
        const out = try vm_mod.rawAlloc(p.vm.heap, Value, fields.len);
        if (fields.len == 0) return out;
        try p.expect("(");
        for (fields, 0..) |f, i| {
            if (i > 0) try p.expect(",");
            const save = p.at;
            const label = p.name();
            if (label.len > 0 and p.eat(":")) {
                if (!std.mem.eql(u8, label, f.name)) return p.fail("{s} takes {s} here, not {s}", .{ owner, f.name, label });
            } else p.at = save;
            out[i] = try p.value(f.type);
        }
        try p.expect(")");
        return out;
    }

    fn value(p: *Parser, t: types.Id) Fail!Value {
        const pool = &p.k.pool;
        const ty = pool.get(pool.resolve(t));
        p.space();
        switch (ty.tag) {
            .alias => return p.value(ty.b),
            .bool => {
                if (p.eat("true")) return .{ .bool = true };
                if (p.eat("false")) return .{ .bool = false };
                return p.fail("expected true or false", .{});
            },
            .int => {
                const n = try p.integer();
                const kind: types.IntKind = @enumFromInt(ty.a);
                const lo: i128, const hi: i128 = switch (kind) {
                    .i8 => .{ std.math.minInt(i8), std.math.maxInt(i8) },
                    .i16 => .{ std.math.minInt(i16), std.math.maxInt(i16) },
                    .i32 => .{ std.math.minInt(i32), std.math.maxInt(i32) },
                    .i64 => .{ std.math.minInt(i64), std.math.maxInt(i64) },
                    .u8 => .{ 0, std.math.maxInt(u8) },
                    .u16 => .{ 0, std.math.maxInt(u16) },
                    .u32 => .{ 0, std.math.maxInt(u32) },
                    .u64 => .{ 0, std.math.maxInt(u64) },
                };
                if (n < lo or n > hi) return p.fail("{d} does not fit a {s}", .{ n, @tagName(kind) });
                return .{ .int = n };
            },
            .float => {
                const start = p.at;
                while (p.at < p.text.len and std.mem.indexOfScalar(u8, "+-.0123456789eE", p.text[p.at]) != null) p.at += 1;
                const f = std.fmt.parseFloat(f64, p.text[start..p.at]) catch return p.fail("expected a number", .{});
                return .{ .float = f };
            },
            .string => return .{ .string = try p.string() },
            .duration => {
                const n = try p.integer();
                try p.expect(".ms");
                return .{ .duration = std.math.cast(i64, n) orelse return p.fail("{d}.ms is too long", .{n}) };
            },
            .time => {
                try p.expect("Time.fixture()");
                var at: i128 = vm_mod.fixture_time;
                if (p.eat("+")) {
                    at += try p.integer();
                    try p.expect(".ms");
                } else if (p.eat("-")) {
                    at -= try p.integer();
                    try p.expect(".ms");
                }
                return .{ .time = std.math.cast(i64, at) orelse return p.fail("that time is out of range", .{}) };
            },
            .list => {
                try p.expect("[");
                var items: std.ArrayList(Value) = .empty;
                defer items.deinit(scratch);
                if (!p.eat("]")) {
                    while (true) {
                        try items.append(scratch, try p.value(ty.a));
                        if (!p.eat(",")) break;
                    }
                    try p.expect("]");
                }
                return list(p.vm, items.items) catch error.OutOfMemory;
            },
            .tuple => {
                try p.expect("(");
                const elems = pool.elems(ty);
                const out = try vm_mod.rawAlloc(p.vm.heap, Value, elems.len);
                for (elems, out, 0..) |e, *o, i| {
                    if (i > 0) try p.expect(",");
                    o.* = try p.value(e);
                }
                try p.expect(")");
                return .{ .tuple = out };
            },
            .option => {
                if (p.eat("None")) return p.vm.variant("None", &.{}) catch error.OutOfMemory;
                try p.expect("Some(");
                const x = try p.value(ty.a);
                try p.expect(")");
                return p.vm.variant("Some", &.{x}) catch error.OutOfMemory;
            },
            .result => {
                if (p.eat("Ok(")) {
                    const x = try p.value(ty.a);
                    try p.expect(")");
                    return p.vm.variant("Ok", &.{x}) catch error.OutOfMemory;
                }
                try p.expect("Error(");
                const x = try p.value(ty.b);
                try p.expect(")");
                return p.vm.variant("Error", &.{x}) catch error.OutOfMemory;
            },
            .decl => {
                const d = p.k.decls[ty.a];
                switch (d.kind) {
                    .struct_ => {
                        const n = p.name();
                        if (!std.mem.eql(u8, n, d.name)) return p.fail("expected a {s}", .{d.name});
                        return .{ .record = .{ .decl = ty.a, .fields = try p.fieldsOf(p.k.fields[d.fields.start..d.fields.end], d.name) } };
                    },
                    .enum_, .prelude_enum => return p.variantOf(d.variants, "one of its variants"),
                    else => {},
                }
            },
            else => {},
        }
        var aw: std.Io.Writer.Allocating = .init(scratch);
        defer aw.deinit();
        p.k.pool.format(&aw.writer, t) catch return error.OutOfMemory;
        return p.fail("a {s} is not made from text by the surface", .{aw.written()});
    }

    fn integer(p: *Parser) Fail!i128 {
        p.space();
        const start = p.at;
        if (p.at < p.text.len and p.text[p.at] == '-') p.at += 1;
        var n: i128 = 0;
        var digits: usize = 0;
        while (p.at < p.text.len and (std.ascii.isDigit(p.text[p.at]) or p.text[p.at] == '_')) : (p.at += 1) {
            if (p.text[p.at] == '_') continue;
            n = std.math.mul(i128, n, 10) catch return p.fail("that number is too large", .{});
            n = std.math.add(i128, n, p.text[p.at] - '0') catch return p.fail("that number is too large", .{});
            digits += 1;
        }
        if (digits == 0) {
            p.at = start;
            return p.fail("expected a number", .{});
        }
        return if (p.text[start] == '-') -n else n;
    }

    /// `"text"`, as a report prints it; `\"` and `\\` stand for a quote and a backslash.
    fn string(p: *Parser) Fail![]const u8 {
        try p.expect("\"");
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(scratch);
        while (true) {
            if (p.at == p.text.len) return p.fail("the string does not end", .{});
            const ch = p.text[p.at];
            p.at += 1;
            if (ch == '"') break;
            if (ch == '\\' and p.at < p.text.len and (p.text[p.at] == '"' or p.text[p.at] == '\\')) {
                try out.append(scratch, p.text[p.at]);
                p.at += 1;
            } else try out.append(scratch, ch);
        }
        return text(p.vm, out.items) catch error.OutOfMemory;
    }
};
