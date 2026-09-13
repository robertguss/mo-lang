//! The bytecode interpreter: the edit-loop runtime and the executable reference
//! semantics (design-v0/07). Hosts contracts, the test runner, and Mo.Sim (sim.zig);
//! later replay and fault injection. A tripped contract or an overflow is
//! a crash with a complete report, never a value.
//!
//! Values are immutable: a list, a tuple, a struct, or a variant is a slice nothing
//! else writes, and changing a field builds a new one, so a `var` copied from another
//! name can never alias it. Two exceptions keep that promise. `push` appends in place when
//! the list ends where its buffer's last push left it, so every earlier value of the list
//! is a prefix that never sees the new element, and a list built by pushing is linear. And
//! `set`, `update`, `remove`, and `add` on a map or set that one var, or one field path
//! under a var, holds alone (`owned`) write into its buffer: nothing else can see it.
//! A map or set carries a hash index beside its entries (stdlib.zig, find).
//!
//! Values are allocated from `heap`. The runner gives each test its own arena and frees
//! it whole. `mo run` gives the vm a region (region.zig, useRegions): each frame, each
//! `for` iteration, and each step of `map`, `filter`, and `reduce` is a safe point, and
//! once enough has been allocated since it began, what its result, its locals, or its
//! accumulator reach is copied down and everything else is freed (compact). A write in
//! place can put a newer value into an older buffer, so each such slot is remembered and
//! a compaction reaches through it. Under processes each process's vm has a region of its
//! own, and values cross between vms packed (Parcel, sim.zig). `mo run` gives a program
//! without processes a Memo (memo.zig), which answers a pure call it has seen before.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const check = @import("check.zig");
const contracts = @import("contracts.zig");
const Memo = @import("memo.zig").Memo;
const net_mod = @import("net.zig");
const prelude = @import("prelude.zig");
const Region = @import("region.zig").Region;
const server_mod = @import("server.zig");
const sim_mod = @import("sim.zig");
const stdlib = @import("stdlib.zig");
const types = @import("types.zig");

const Op = bytecode.Op;
const Num = bytecode.Num;
const none = bytecode.none;

/// `Crash` carries `Vm.report`. `Skip` means the test reached something this step does
/// not run, and `Vm.report` says what. `Discard` is a property attempt whose guard is false.
pub const Error = error{ OutOfMemory, Crash, Skip, Discard };

pub const Value = union(enum) {
    /// No value: what a statement-only call gives.
    none,
    bool: bool,
    /// Every integer type, and a contract's unbounded integers, in one i128.
    int: i128,
    float: f64,
    string: []const u8,
    /// Milliseconds since the Unix epoch.
    time: i64,
    /// Milliseconds.
    duration: i64,
    list: []const Value,
    tuple: []const Value,
    /// A map's entries, each key then its value, in the order the keys were first added
    /// (design-v0/09), and the hash index beside them.
    map: Map,
    /// A set's elements, in the order they were first added, and their index.
    set: Map,
    record: Record,
    variant: Variant,
    func: Func,
    cap: Cap,
    /// A started process: its index in the run's `Sim.procs`.
    handle: u32,

    /// Entries in the order they were added, `stride` values each (a map's are 2), and once
    /// there are enough of them an open-addressing table over them, after a count of the
    /// slots in use: each slot holds an entry's ordinal plus one, 0 when empty (stdlib.zig,
    /// find). A table may hold ordinals past the entries a value sees, so a lookup always
    /// compares the key.
    pub const Map = struct { entries: []const Value, index: []const u32 = &.{} };
    pub const Record = struct { decl: u32, fields: []const Value };
    /// A variant is known by its name, so `try` re-tags an error without converting it.
    pub const Variant = struct { name: []const u8, fields: []const Value };
    pub const Func = struct { function: u32, captures: []const Value };
    /// `handle` names a real resource under Mo.Server: an Fs's scope, or an Out's stream.
    pub const Cap = struct { kind: types.CapKind, delay: i64 = 0, handle: u32 = 0 };
};

/// `Time.fixture()` and a fixture clock's frozen `now`: 2026-01-01T00:00:00Z.
pub const fixture_time: i64 = 1_767_225_600_000;

pub const Generated = struct { name: []const u8, value: Value };

/// A value copied whole into memory of its own (Vm.pack), so it outlives the region it was
/// made in: under `mo run`, a message on its way to another process's vm, a reply on its
/// way back, and a process's start arguments and first state (sim.zig).
pub const Parcel = struct {
    arena: std.heap.ArenaAllocator,
    value: Value = .none,

    pub fn free(p: *Parcel) void {
        p.arena.deinit();
        std.heap.smp_allocator.destroy(p);
    }
};

pub const Vm = struct {
    /// Reports, rendered values, and the vm's own lists: everything that is not a value.
    gpa: std.mem.Allocator,
    /// Values: `gpa`, or the region useRegions gives.
    heap: std.mem.Allocator,
    program: *const bytecode.Program,
    stack: std.ArrayList(Value) = .empty,
    /// Under `mo run`, where values live; null when they live until `gpa` is freed.
    region: ?*Region = null,
    /// What a compaction keeps passes through here on its way back into `region`.
    scratch: ?*Region = null,
    /// The lists push can grow in place: the sixteen it grew last.
    growth: [16]Growth = [_]Growth{.{}} ** 16,
    growth_next: usize = 0,
    /// Map and set buffers a `var` holds alone: an update (`m = m.set(k, v)`) made them
    /// and nothing has read the var since (a read is `load_shared`). stdlib.zig writes
    /// into these in place, so an update on a var is not a copy (design-v0/09).
    owned: [16]SliceKey = [_]SliceKey{.{ .ptr = 0, .len = 0 }} ** 16,
    owned_next: usize = 0,
    /// A compaction's copies, so a slice reached twice is copied once.
    forward: std.AutoHashMapUnmanaged(SliceKey, [*]Value) = .empty,
    /// Slots a row wrote in place with a value that may be newer than the slot (rememberWrite):
    /// a compaction from between the two finds the value only through here. In order of
    /// `at`, so a compaction looks only at those written since.
    remembered: std.ArrayList(Remembered) = .empty,
    /// Under an update (sim.zig), what each slot below `undo_mark` held before the update
    /// overwrote it, so a crash shows the state as it was. 0: no update keeps one.
    undo: std.ArrayList(Undo) = .empty,
    undo_mark: usize = 0,
    /// Buffers below this address are never overwritten in place: a process whose
    /// invariants read old(state) keeps the state before each update whole.
    frozen_below: usize = 0,
    /// What a process's region held after its last full compaction (sim.zig).
    full_kept: usize = 0,
    /// Region bytes a returning frame may leave behind before it compacts its result.
    frame_budget: usize = 1 << 20,
    /// Region bytes a loop may allocate past twice what it kept at its last compaction.
    loop_budget: usize = 256 << 10,
    /// Under `mo run`, the calls to pure functions it remembers.
    memo: ?*Memo = null,
    /// Instructions run so far; a Memo reads what a call cost from it.
    steps: u64 = 0,
    /// Set when a call fails with Crash or Skip.
    report: ?contracts.Report = null,
    rng: std.Random.DefaultPrng,
    /// The values `any(T)` produced in this run, in order, for a property's report.
    generated: std.ArrayList(Generated) = .empty,
    /// The scheduler processes run on; the runner sets it for every test.
    sim: ?*sim_mod.Sim = null,
    /// The real platform `mo run` gives main; null under `mo test`.
    server: ?*server_mod.Server = null,

    pub fn init(gpa: std.mem.Allocator, program: *const bytecode.Program, seed: u64) Vm {
        return .{ .gpa = gpa, .heap = gpa, .program = program, .rng = .init(seed) };
    }

    /// Values from here on live in `values`, freed at safe points; `scratch` is empty
    /// between compactions.
    pub fn useRegions(vm: *Vm, values: *Region, scratch: *Region) void {
        vm.region = values;
        vm.scratch = scratch;
        vm.heap = values.allocator();
    }

    const Growth = struct { ptr: usize = 0, len: usize = 0, cap: usize = 0 };

    const SliceKey = struct { ptr: usize, len: usize };

    /// `len` slots from `slot` were written in place; `at` is where the region's top stood
    /// then, or where a compaction that moved their values left it.
    const Remembered = struct { slot: usize, len: usize, at: usize };
    const Undo = struct { slot: usize, old: Value };

    fn simulator(vm: *Vm) Error!*sim_mod.Sim {
        if (vm.sim) |s| return s;
        vm.report = .{ .kind = .other, .clause = "processes run only under the test runner", .within = "", .at = 0 };
        return error.Crash;
    }

    /// Calls functions[function] with `args` and returns its result.
    pub fn call(vm: *Vm, function: u32, args: []const Value) Error!Value {
        return vm.callWith(function, args, &.{});
    }

    fn callWith(vm: *Vm, function: u32, args: []const Value, captures: []const Value) Error!Value {
        const base = vm.stack.items.len;
        try vm.exec(function, args, captures);
        const v = vm.stack.items[base];
        vm.stack.shrinkRetainingCapacity(base);
        return v;
    }

    fn checked(vm: *Vm) *const check.Checked {
        return &vm.program.checked;
    }

    fn push(vm: *Vm, v: Value) Error!void {
        if (vm.stack.items.len == vm.stack.capacity) try vm.stack.ensureTotalCapacity(vm.gpa, 2 * vm.stack.capacity + 256);
        vm.stack.appendAssumeCapacity(v);
    }

    fn pop(vm: *Vm) Value {
        vm.stack.items.len -= 1;
        return vm.stack.items.ptr[vm.stack.items.len];
    }

    /// The top `n` values, oldest first, off the stack but still in its memory until the
    /// next push.
    fn drop(vm: *Vm, n: u32) []const Value {
        const len = vm.stack.items.len;
        vm.stack.items.len = len - n;
        return vm.stack.items.ptr[len - n .. len];
    }

    /// The top `n` values, oldest first, removed from the stack.
    fn take(vm: *Vm, n: u32) Error![]Value {
        const len = vm.stack.items.len;
        const out = try vm.allocValues(n);
        @memcpy(out, vm.stack.items[len - n ..]);
        vm.stack.shrinkRetainingCapacity(len - n);
        return out;
    }

    fn constant(vm: *Vm, i: u32) Value {
        return switch (vm.program.constants[i]) {
            .none => .none,
            .int => |v| .{ .int = v },
            .float => |v| .{ .float = v },
            .string => |v| .{ .string = v },
            .bool => |v| .{ .bool = v },
        };
    }

    /// Runs functions[fi] and leaves its result on the stack, then the final value of each
    /// inout parameter, in order.
    fn exec(vm: *Vm, fi: u32, args: []const Value, captures: []const Value) Error!void {
        const f = vm.program.functions[fi];
        // A remembered call is answered without running; `remember` is the key a result
        // this call returns is kept under.
        var remember: ?u64 = null;
        if (vm.memo) |m| switch (m.lookup(fi, f, args, captures)) {
            .hit => |v| return vm.push(v),
            .miss => |key| remember = key,
            .skip => {},
        };
        const steps = vm.steps;
        const frame = vm.mark();
        const locals = try vm.allocValues(f.locals);
        @memcpy(locals[0..args.len], args);
        @memset(locals[args.len..], .none);
        for (f.captures, captures) |slot, v| locals[slot] = v;
        const base = vm.stack.items.len;
        var pc: u32 = 0;
        while (true) {
            const inst = f.code[pc];
            pc += 1;
            vm.steps += 1;
            switch (inst.op) {
                .constant => try vm.push(vm.constant(inst.a)),
                .pop => _ = vm.pop(),
                .swap => {
                    const s = vm.stack.items;
                    std.mem.swap(Value, &s[s.len - 1], &s[s.len - 2]);
                },
                .load => try vm.push(locals[inst.a]),
                .load_shared => {
                    const v = locals[inst.a];
                    vm.disownIn(v);
                    try vm.push(v);
                },
                .store => locals[inst.a] = vm.pop(),
                .jump => pc = inst.a,
                .jump_if_false => if (!vm.pop().bool) {
                    pc = inst.a;
                },
                .jump_if_true => if (vm.pop().bool) {
                    pc = inst.a;
                },
                .add, .sub, .mul, .div, .rem => {
                    const r = vm.pop();
                    const l = vm.pop();
                    try vm.push(try vm.arith(inst, l, r));
                },
                .negate => {
                    const v = vm.pop();
                    try vm.push(switch (v) {
                        .int => |x| try vm.int(inst, -x, &.{v}),
                        .float => |x| .{ .float = -x },
                        .duration => |x| .{ .duration = -x },
                        else => unreachable,
                    });
                },
                .not => try vm.push(.{ .bool = !vm.pop().bool }),
                .eq, .ne, .lt, .le, .gt, .ge => {
                    const r = vm.pop();
                    const l = vm.pop();
                    try vm.push(.{ .bool = compare(inst.op, l, r) });
                },
                .list, .tuple => {
                    const elems = try vm.take(inst.a);
                    try vm.push(if (inst.op == .list) .{ .list = elems } else .{ .tuple = elems });
                },
                .record => {
                    const v: Value = .{ .record = .{ .decl = inst.a, .fields = try vm.take(inst.b) } };
                    try vm.produced(v);
                    try vm.push(v);
                },
                .variant => try vm.push(.{ .variant = .{ .name = vm.program.constants[inst.a].string, .fields = try vm.take(inst.b) } }),
                .field => try vm.push(fieldsOf(vm.pop())[inst.a]),
                .load_field => try vm.push(fieldsOf(locals[inst.a])[inst.b]),
                .set_field => {
                    const v = vm.pop();
                    const obj = vm.pop();
                    const fields = try vm.allocValues(fieldsOf(obj).len);
                    @memcpy(fields, fieldsOf(obj));
                    fields[inst.a] = v;
                    const changed: Value = switch (obj) {
                        .record => |r| .{ .record = .{ .decl = r.decl, .fields = fields } },
                        .variant => |r| .{ .variant = .{ .name = r.name, .fields = fields } },
                        .tuple => .{ .tuple = fields },
                        else => unreachable,
                    };
                    if (changed == .record) try vm.produced(changed);
                    try vm.push(changed);
                },
                .is_variant => {
                    const v = vm.pop();
                    try vm.push(.{ .bool = v == .variant and std.mem.eql(u8, v.variant.name, vm.program.constants[inst.a].string) });
                },
                .index => {
                    const i = vm.pop().int;
                    try vm.push(vm.pop().list[@intCast(i)]);
                },
                .len => try vm.push(.{ .int = @intCast(vm.pop().list.len) }),
                .range => {
                    const hi = vm.pop().int;
                    const lo = vm.pop().int;
                    const n: usize = if (hi > lo) @intCast(hi - lo) else 0;
                    const elems = try rawAlloc(vm.heap, Value, n);
                    for (elems, 0..) |*e, k| e.* = .{ .int = lo + @as(i128, @intCast(k)) };
                    try vm.push(.{ .list = elems });
                },
                .concat => {
                    const parts = try vm.take(inst.a);
                    var aw: std.Io.Writer.Allocating = .init(vm.heap);
                    for (parts) |p| vm.formatText(&aw.writer, p) catch return error.OutOfMemory;
                    try vm.push(.{ .string = try aw.toOwnedSlice() });
                },
                // The arguments stay in the stack's memory until the callee copies them.
                .call, .call_trait => {
                    const args_now = vm.drop(inst.b);
                    const target = if (inst.op == .call) inst.a else try vm.dispatch(inst.a, args_now[0]);
                    try vm.exec(target, args_now, &.{});
                },
                .call_value => {
                    const args_now = vm.drop(inst.a);
                    const func = vm.pop().func;
                    try vm.exec(func.function, args_now, func.captures);
                },
                .closure => try vm.push(.{ .func = .{ .function = inst.a, .captures = try vm.take(inst.b) } }),
                .prim => try vm.prim(inst.a, inst.b),
                .ret => {
                    const v = vm.pop();
                    vm.stack.shrinkRetainingCapacity(base);
                    try vm.push(v);
                    for (f.inouts) |slot| try vm.push(locals[slot]);
                    // Parameters are bound once, so the first locals are still the arguments.
                    if (vm.memo) |m| try m.finish(fi, vm.steps - steps, remember, locals[0..args.len], captures, v);
                    if (vm.region) |r| if (r.top -| frame > vm.frame_budget) try vm.compact(frame, vm.stack.items[base..]);
                    return;
                },
                .mark => {
                    locals[inst.a] = .{ .int = vm.mark() };
                    locals[inst.b] = .{ .int = 0 };
                },
                .collect => if (vm.region != null) {
                    const kept = try vm.iterate(@intCast(locals[inst.a].int), locals, @intCast(locals[inst.b].int));
                    locals[inst.b] = .{ .int = kept };
                },
                .check => if (!vm.pop().bool) return vm.crash(inst.a, f, locals, &.{}),
                .check_compare => {
                    const r = vm.pop();
                    const l = vm.pop();
                    if (!compare(@enumFromInt(inst.b), l, r)) {
                        return vm.crash(inst.a, f, locals, &.{ .{ .name = "left", .value = try vm.render(l) }, .{ .name = "right", .value = try vm.render(r) } });
                    }
                },
                .refine => {
                    const v = vm.stack.items[vm.stack.items.len - 1];
                    const refinement = vm.program.refinements[inst.a];
                    if (!(try vm.call(refinement.function, &.{v})).bool) {
                        return vm.crash(refinement.clause, f, locals, &.{.{ .name = "value", .value = try vm.render(v) }});
                    }
                },
                .generate => {
                    const v = try vm.generate(inst.a, 0);
                    try vm.generated.append(vm.gpa, .{ .name = vm.program.constants[inst.b].string, .value = v });
                    try vm.push(v);
                },
                .discard => return error.Discard,
                .halt => {
                    const c = vm.program.clauses[inst.a];
                    if (c.skip) {
                        vm.report = .{ .kind = .other, .clause = c.text, .within = c.within, .at = c.at };
                        return error.Skip;
                    }
                    return vm.crash(inst.a, f, locals, &.{});
                },
                .spawn => {
                    const args_now = try vm.take(inst.b);
                    try vm.push(.{ .handle = try (try vm.simulator()).start(inst.a, args_now) });
                },
                .start_supervisor => {
                    const args_now = try vm.take(inst.b);
                    const children = try (try vm.simulator()).startSupervisor(inst.a, args_now);
                    const handles: Value = switch (children.len) {
                        0 => .none,
                        1 => .{ .handle = children[0] },
                        else => blk: {
                            const out = try vm.allocValues(children.len);
                            for (children, out) |id, *o| o.* = .{ .handle = id };
                            break :blk .{ .tuple = out };
                        },
                    };
                    try vm.push(handles);
                },
                .send => {
                    const message = vm.pop();
                    const to = vm.pop().handle;
                    try (try vm.simulator()).send(to, message);
                    try vm.push(.none);
                },
                .ask => {
                    const within = vm.pop().duration;
                    const message = vm.pop();
                    const to = vm.pop().handle;
                    try vm.push(try (try vm.simulator()).ask(to, message, within));
                },
                .settle => if (vm.sim) |s| try s.settle(),
                .all => try vm.push(.{ .list = if (vm.sim) |s| s.all(inst.a) else &.{} }),
                .trip => {
                    const broken = vm.pop().bool;
                    const values = try vm.take(inst.b);
                    if (broken) return vm.tripNever(inst.a, values);
                },
                .zero => try vm.push(try vm.zero(inst.a) orelse return vm.crash(inst.b, f, locals, &.{})),
            }
        }
    }

    /// The value a state field without `= expr` starts at (grammar, Session 5): 0, "",
    /// [], None, false, a zero Duration, and tuples and structs of those. Null when the
    /// type has none: an enum, a Time, a capability, a handle.
    fn zero(vm: *Vm, t: types.Id) Error!?Value {
        const k = vm.checked();
        const ty = k.pool.get(k.pool.base(t));
        switch (ty.tag) {
            .int => return .{ .int = 0 },
            .float => return .{ .float = 0 },
            .bool => return .{ .bool = false },
            .string => return .{ .string = "" },
            .duration => return .{ .duration = 0 },
            .list => return .{ .list = &.{} },
            .option => return try vm.variant("None", &.{}),
            .map => return .{ .map = .{ .entries = &.{} } },
            .set => return .{ .set = .{ .entries = &.{} } },
            .tuple => {
                const elems = k.pool.elems(ty);
                const out = try rawAlloc(vm.heap, Value, elems.len);
                for (elems, out) |e, *o| o.* = try vm.zero(e) orelse return null;
                return .{ .tuple = out };
            },
            .decl => {
                const d = k.decls[ty.a];
                if (d.kind != .struct_) return null;
                const defs = k.fields[d.fields.start..d.fields.end];
                const out = try rawAlloc(vm.heap, Value, defs.len);
                for (defs, out) |fd, *o| o.* = try vm.zero(fd.type) orelse return null;
                return .{ .record = .{ .decl = ty.a, .fields = out } };
            },
            else => return null,
        }
    }

    /// Calls a function value.
    pub fn invoke(vm: *Vm, func: Value.Func, args: []const Value) Error!Value {
        return vm.callWith(func.function, args, func.captures);
    }

    // ---- memory

    /// `n` values from the heap: a region's bump done here, anything else through `heap`.
    fn allocValues(vm: *Vm, n: usize) Error![]Value {
        if (vm.region) |r| {
            const start = std.mem.alignForward(usize, r.top, @alignOf(Value));
            const end = start + n * @sizeOf(Value);
            if (end <= r.end) {
                r.top = end;
                return @as([*]Value, @ptrFromInt(start))[0..n];
            }
        }
        return rawAlloc(vm.heap, Value, n);
    }

    /// Where the region's allocations stand: the mark a frame or a loop frees back to.
    pub fn mark(vm: *const Vm) usize {
        return if (vm.region) |r| r.top else 0;
    }

    /// A loop's safe point. Once it has allocated more than twice what it kept at its last
    /// compaction, plus loop_budget, everything past `from` that `roots` do not reach is
    /// freed. Gives what is kept.
    pub fn iterate(vm: *Vm, from: usize, roots: []Value, kept: usize) Error!usize {
        const r = vm.region orelse return 0;
        if (r.top -| from <= 2 * kept + vm.loop_budget) return kept;
        try vm.compact(from, roots);
        return r.top - from;
    }

    /// Copies what `roots` reach past `from` into the scratch region, frees everything past
    /// `from`, and copies it back; `roots` then hold the copies. A value points only at
    /// older values, except where a row wrote into an older buffer in place, and those slots
    /// are remembered: so what `roots` and the remembered slots below `from` reach is
    /// everything kept.
    pub fn compact(vm: *Vm, from: usize, roots: []Value) Error!void {
        const r = vm.region.?;
        const s = vm.scratch.?;
        const old_top = r.top;
        // Only slots written since the top last stood at `from` can hold a value past it. Of
        // those, a slot past `from` is freed or copied with its buffer; one below is a root.
        var first = vm.remembered.items.len;
        while (first > 0 and vm.remembered.items[first - 1].at > from) first -= 1;
        var n = first;
        for (vm.remembered.items[first..]) |e| {
            if (e.slot >= from and e.slot < old_top) continue;
            vm.remembered.items[n] = e;
            n += 1;
        }
        vm.remembered.shrinkRetainingCapacity(n);
        const below = vm.remembered.items[first..];
        s.top = s.base;
        vm.forward.clearRetainingCapacity();
        try vm.copyRoots(roots, below, .{ .lo = from, .hi = old_top, .dest = s.allocator(), .moves = true });
        r.top = from;
        vm.dropGrowth(from, old_top);
        vm.forward.clearRetainingCapacity();
        try vm.copyRoots(roots, below, .{ .lo = s.base, .hi = s.top, .dest = r.allocator(), .moves = true, .fresh = true });
        vm.dropGrowth(s.base, s.end);
        for (below) |*e| e.at = r.top;
    }

    fn copyRoots(vm: *Vm, roots: []Value, slots: []const Remembered, c: Copy) Error!void {
        for (roots) |*v| v.* = try vm.copyOut(v.*, c);
        for (slots) |e| {
            const xs: [*]Value = @ptrFromInt(e.slot);
            for (xs[0..e.len]) |*v| v.* = try vm.copyOut(v.*, c);
        }
    }

    /// A copy takes every part allocated in [lo, hi) into `dest`. `moves`: a compaction,
    /// whose copies carry on the buffers push can grow and a var owns. `fresh`: every map
    /// index in the range was built by the copy before, so it is copied as it is.
    const Copy = struct { lo: usize, hi: usize, dest: std.mem.Allocator, moves: bool = false, fresh: bool = false };

    fn inside(addr: usize, c: Copy) bool {
        return addr >= c.lo and addr < c.hi;
    }

    /// `v` with every part allocated in the copy's range copied.
    fn copyOut(vm: *Vm, v: Value, c: Copy) Error!Value {
        return switch (v) {
            .string => |s| if (s.len > 0 and inside(@intFromPtr(s.ptr), c)) .{ .string = try rawDupe(c.dest, u8, s) } else v,
            .list => |xs| .{ .list = try vm.copySlice(xs, c, true) },
            .tuple => |xs| .{ .tuple = try vm.copySlice(xs, c, false) },
            .map => |m| .{ .map = try vm.copyMap(m, 2, c) },
            .set => |m| .{ .set = try vm.copyMap(m, 1, c) },
            .record => |x| .{ .record = .{ .decl = x.decl, .fields = try vm.copySlice(x.fields, c, false) } },
            .variant => |x| .{ .variant = .{ .name = x.name, .fields = try vm.copySlice(x.fields, c, false) } },
            .func => |x| .{ .func = .{ .function = x.function, .captures = try vm.copySlice(x.captures, c, false) } },
            else => v,
        };
    }

    /// A buffer push can still grow keeps its spare room under a compaction, and push and
    /// the var that owned it keep using the copy.
    fn copySlice(vm: *Vm, xs: []const Value, c: Copy, grows: bool) Error![]const Value {
        const addr = @intFromPtr(xs.ptr);
        if (xs.len == 0 or !inside(addr, c)) return xs;
        const key: SliceKey = .{ .ptr = addr, .len = xs.len };
        if (vm.forward.get(key)) |copied| return copied[0..xs.len];
        const growth = if (grows and c.moves) vm.growthOf(addr, xs.len) else null;
        const out = try rawAlloc(c.dest, Value, if (growth) |g| g.cap else xs.len);
        try vm.forward.put(vm.gpa, key, out.ptr);
        for (xs, out[0..xs.len]) |x, *o| o.* = try vm.copyOut(x, c);
        if (growth) |g| g.ptr = @intFromPtr(out.ptr);
        if (c.moves) for (&vm.owned) |*o| {
            if (o.ptr == addr and o.len == xs.len) o.ptr = @intFromPtr(out.ptr);
        };
        return out[0..xs.len];
    }

    /// A map's entries and its index. A compaction's first copy builds again a table holding
    /// ordinals past its entries, so a table push grows in place never fills; any other copy
    /// takes the table as it is, and a lookup skips such an ordinal.
    fn copyMap(vm: *Vm, m: Value.Map, stride: usize, c: Copy) Error!Value.Map {
        const entries = try vm.copySlice(m.entries, c, true);
        if (m.index.len == 0) return .{ .entries = entries };
        const index_inside = inside(@intFromPtr(m.index.ptr), c);
        if (entries.ptr == m.entries.ptr and !index_inside) return .{ .entries = entries, .index = m.index };
        // A table whose slots in use are exactly the entries' keys has no ordinal past them.
        if (!c.moves or c.fresh or m.index[0] == entries.len / stride) return .{ .entries = entries, .index = try rawDupe(c.dest, u32, m.index) };
        return .{ .entries = entries, .index = try stdlib.buildIndex(c.dest, entries, stride, stdlib.tableSlots(m.index)) };
    }

    fn growthOf(vm: *Vm, addr: usize, len: usize) ?*Growth {
        for (&vm.growth) |*g| {
            if (g.ptr == addr and g.len == len and g.cap != 0) return g;
        }
        return null;
    }

    /// Forgets the buffers in [lo, hi), which a compaction has freed.
    fn dropGrowth(vm: *Vm, lo: usize, hi: usize) void {
        for (&vm.growth) |*g| {
            if (g.ptr >= lo and g.ptr < hi) g.* = .{};
        }
        for (&vm.owned) |*o| {
            if (o.ptr >= lo and o.ptr < hi) o.* = .{ .ptr = 0, .len = 0 };
        }
    }

    /// Whether `xs` is a map or set buffer only one `var` holds (vm.owned).
    pub fn isOwned(vm: *const Vm, xs: []const Value) bool {
        if (xs.len == 0) return false;
        for (vm.owned) |o| if (o.ptr == @intFromPtr(xs.ptr) and o.len == xs.len) return true;
        return false;
    }

    /// `xs` was just built by an update on a `var`, from a fresh buffer or one the var
    /// already owned, so nothing else holds it.
    pub fn own(vm: *Vm, xs: []const Value) void {
        if (xs.len == 0 or vm.isOwned(xs)) return;
        vm.owned[vm.owned_next] = .{ .ptr = @intFromPtr(xs.ptr), .len = xs.len };
        vm.owned_next = (vm.owned_next + 1) % vm.owned.len;
    }

    /// Something other than an update read `xs`, so it may now be held twice.
    pub fn disown(vm: *Vm, xs: []const Value) void {
        for (&vm.owned) |*o| {
            if (o.ptr == @intFromPtr(xs.ptr) and o.len == xs.len) o.* = .{ .ptr = 0, .len = 0 };
        }
    }

    /// `v` was read other than by an update of the var or field holding it: every map or
    /// set it holds, itself or in a struct's fields, may now be held twice. An owned buffer
    /// is only ever at a var or a field path under one (bytecode.zig, inPlaceSlot).
    pub fn disownIn(vm: *Vm, v: Value) void {
        switch (v) {
            .map, .set => |m| vm.disown(m.entries),
            .record => |r| for (r.fields) |f| vm.disownIn(f),
            else => {},
        }
    }

    /// A row wrote `n` slots from `slot` in place; `x` is the value when it wrote one. When
    /// what they hold may be newer than the slots, a compaction from a mark between the two
    /// would not reach it through the buffer, so the slots are remembered.
    pub fn rememberWrite(vm: *Vm, slot: usize, n: usize, x: ?Value) Error!void {
        const r = vm.region orelse return;
        if (!r.contains(slot)) return;
        if (x) |v| {
            const p = newestOf(v) orelse return;
            if (!r.contains(p) or p < slot) return;
        }
        try vm.remembered.append(vm.gpa, .{ .slot = slot, .len = n, .at = r.top });
    }

    /// Whether a row may overwrite a buffer at `buf` in place.
    pub fn overwritable(vm: *const Vm, buf: usize) bool {
        return buf >= vm.frozen_below;
    }

    /// Whether a row may move a buffer's slots in place (`remove`): an update's undo keeps
    /// single overwrites only, so a buffer from before the update is copied instead.
    pub fn movable(vm: *const Vm, buf: usize) bool {
        return buf >= vm.frozen_below and buf >= vm.undo_mark;
    }

    /// Writes `x` into a slot in place: remembered for compaction, and under an update what
    /// the slot held before, when that is older than the update and so still there on a crash.
    pub fn overwrite(vm: *Vm, slot: *Value, x: Value) Error!void {
        const addr = @intFromPtr(slot);
        if (addr < vm.undo_mark) {
            const old = slot.*;
            const p = newestOf(old);
            if (p == null or !vm.region.?.contains(p.?) or p.? < vm.undo_mark) try vm.undo.append(vm.gpa, .{ .slot = addr, .old = old });
        }
        try vm.rememberWrite(addr, 1, x);
        slot.* = x;
    }

    /// A crashed update's overwrites taken back, the last first.
    pub fn rollBack(vm: *Vm) void {
        while (vm.undo.pop()) |u| @as(*Value, @ptrFromInt(u.slot)).* = u.old;
    }

    /// `v` copied whole into a parcel of its own, which outlives every region.
    pub fn pack(vm: *Vm, v: Value) Error!*Parcel {
        const p = std.heap.smp_allocator.create(Parcel) catch return error.OutOfMemory;
        p.* = .{ .arena = .init(std.heap.smp_allocator) };
        errdefer p.free();
        vm.forward.clearRetainingCapacity();
        p.value = try vm.copyOut(v, .{ .lo = 0, .hi = std.math.maxInt(usize), .dest = p.arena.allocator() });
        return p;
    }

    /// A parcel's value copied whole onto this vm's heap, so the parcel can be freed.
    pub fn unpack(vm: *Vm, p: *const Parcel) Error!Value {
        vm.forward.clearRetainingCapacity();
        return vm.copyOut(p.value, .{ .lo = 0, .hi = std.math.maxInt(usize), .dest = vm.heap });
    }

    /// `xs.push(x)`: in place when xs ends where its buffer's last push left it and there is
    /// room, a copy with room to grow otherwise.
    pub fn pushList(vm: *Vm, xs: []const Value, x: Value) Error![]const Value {
        if (xs.len > 0) {
            if (vm.growthOf(@intFromPtr(xs.ptr), xs.len)) |g| {
                if (g.len < g.cap) {
                    const buf: [*]Value = @ptrFromInt(g.ptr);
                    try vm.rememberWrite(g.ptr + g.len * @sizeOf(Value), 1, x);
                    buf[g.len] = x;
                    g.len += 1;
                    return buf[0..g.len];
                }
            }
        }
        const cap = @max(4, 2 * xs.len);
        const out = try vm.allocValues(cap);
        @memcpy(out[0..xs.len], xs);
        out[xs.len] = x;
        vm.growth[vm.growth_next] = .{ .ptr = @intFromPtr(out.ptr), .len = xs.len + 1, .cap = cap };
        vm.growth_next = (vm.growth_next + 1) % vm.growth.len;
        return out[0 .. xs.len + 1];
    }

    /// The impl function a trait signature reaches for a value of this type.
    fn dispatch(vm: *Vm, si: u32, receiver: Value) Error!u32 {
        const k = vm.checked();
        const sig = k.sigs[si];
        if (receiver == .record) {
            for (k.impls) |im| {
                if (im.trait != sig.owner) continue;
                const t = k.pool.get(k.pool.base(im.for_type));
                if (t.tag != .decl or t.a != receiver.record.decl) continue;
                for (im.sigs.start..im.sigs.end) |s| {
                    if (std.mem.eql(u8, k.sigs[s].name, sig.name)) return vm.program.fn_of_sig[s];
                }
            }
        }
        vm.report = .{ .kind = .other, .clause = try std.fmt.allocPrint(vm.gpa, "no impl gives {s} for {s}", .{ sig.name, try vm.render(receiver) }), .within = sig.name, .at = 0 };
        return error.Crash;
    }

    // ---- crashes

    fn crash(vm: *Vm, clause_index: u32, f: bytecode.Function, locals: []const Value, extra: []const contracts.Involved) Error {
        const c = vm.program.clauses[clause_index];
        var values: std.ArrayList(contracts.Involved) = .empty;
        if (c.kind == .requires or c.kind == .ensures) {
            for (f.param_names, 0..) |name, k| try values.append(vm.gpa, .{ .name = name, .value = try vm.render(locals[k]) });
            if (c.kind == .ensures) try values.append(vm.gpa, .{ .name = "result", .value = try vm.render(locals[f.result]) });
        }
        try values.appendSlice(vm.gpa, extra);
        vm.report = .{ .kind = c.kind, .clause = c.text, .within = c.within, .at = c.at, .values = values.items };
        return error.Crash;
    }

    /// A never's body was true: the report names each value its generators gave.
    fn tripNever(vm: *Vm, clause_index: u32, values: []const Value) Error {
        const never = for (vm.program.nevers) |n| {
            if (n.clause == clause_index) break n;
        } else unreachable;
        const involved = try vm.gpa.alloc(contracts.Involved, values.len);
        for (values, never.names, involved) |v, name, *o| o.* = .{ .name = name, .value = try vm.render(v) };
        const c = vm.program.clauses[clause_index];
        vm.report = .{ .kind = c.kind, .clause = c.text, .within = c.within, .at = c.at, .values = involved };
        return error.Crash;
    }

    /// A struct value the run made, kept for a never's `T.all` (sim.zig).
    fn produced(vm: *Vm, v: Value) Error!void {
        if (vm.sim) |s| if (s.records) try s.record(v);
    }

    fn crashWith(vm: *Vm, kind: contracts.Kind, clause_index: u32, values: []const Value) Error {
        var involved: std.ArrayList(contracts.Involved) = .empty;
        const names = [_][]const u8{ "left", "right" };
        for (values, 0..) |v, k| try involved.append(vm.gpa, .{ .name = if (values.len == 1) "value" else names[k], .value = try vm.render(v) });
        if (clause_index == none) {
            vm.report = .{ .kind = kind, .clause = "an integer past its type", .within = "", .at = 0, .values = involved.items };
        } else {
            const c = vm.program.clauses[clause_index];
            vm.report = .{ .kind = kind, .clause = c.text, .within = c.within, .at = c.at, .values = involved.items };
        }
        return error.Crash;
    }

    // ---- numbers

    /// An integer result checked against its kind; out of range is an overflow crash.
    fn int(vm: *Vm, inst: bytecode.Inst, v: i128, operands: []const Value) Error!Value {
        const num: Num = @enumFromInt(inst.a);
        switch (num) {
            // Contract arithmetic is unbounded; i128 is its stand-in (contracts.zig).
            .unbounded, .other => {},
            else => {
                const kind: types.IntKind = @enumFromInt(@intFromEnum(num));
                if (v < minOf(kind) or v > maxOf(kind)) return vm.crashWith(.overflow, inst.b, operands);
            },
        }
        return .{ .int = v };
    }

    fn arith(vm: *Vm, inst: bytecode.Inst, l: Value, r: Value) Error!Value {
        const operands = [_]Value{ l, r };
        switch (l) {
            .int => |a| {
                const b = r.int;
                if ((inst.op == .div or inst.op == .rem) and b == 0) return vm.crashWith(.divide_by_zero, inst.b, &operands);
                const wide = switch (inst.op) {
                    .add => @addWithOverflow(a, b),
                    .sub => @subWithOverflow(a, b),
                    .mul => @mulWithOverflow(a, b),
                    .div => if (a == std.math.minInt(i128) and b == -1) .{ a, @as(u1, 1) } else .{ @divTrunc(a, b), @as(u1, 0) },
                    else => .{ @rem(a, b), @as(u1, 0) },
                };
                if (wide[1] != 0) return vm.crashWith(.overflow, inst.b, &operands);
                return vm.int(inst, wide[0], &operands);
            },
            .float => |a| {
                const b = r.float;
                return .{ .float = switch (inst.op) {
                    .add => a + b,
                    .sub => a - b,
                    .mul => a * b,
                    .div => a / b,
                    else => @rem(a, b),
                } };
            },
            .time => |a| switch (r) {
                .time => |b| return .{ .duration = try vm.time(inst, if (inst.op == .sub) @subWithOverflow(a, b) else @addWithOverflow(a, b), &operands) },
                else => return .{ .time = try vm.time(inst, if (inst.op == .sub) @subWithOverflow(a, r.duration) else @addWithOverflow(a, r.duration), &operands) },
            },
            .duration => |a| return .{ .duration = try vm.time(inst, if (inst.op == .sub) @subWithOverflow(a, r.duration) else @addWithOverflow(a, r.duration), &operands) },
            else => unreachable,
        }
    }

    fn time(vm: *Vm, inst: bytecode.Inst, wide: struct { i64, u1 }, operands: []const Value) Error!i64 {
        if (wide[1] != 0) return vm.crashWith(.overflow, inst.b, operands);
        return wide[0];
    }

    // ---- the prelude

    const Prim = enum {
        list_size,
        list_push,
        list_map,
        list_filter,
        list_reduce,
        list_contains,
        list_first,
        list_last,
        string_size,
        string_bytes,
        string_starts_with,
        checked_add,
        checked_sub,
        checked_mul,
        saturating_add,
        saturating_sub,
        saturating_mul,
        wrapping_add,
        wrapping_sub,
        wrapping_mul,
        ms,
        minute,
        days,
        time_fixture,
        clock_now,
        clock_fixture,
        fs_read,
        fs_narrow,
        fs_fixture,
        events_emit,
        events_fixture,
        ledger_fixture,
        ledger_call,
        charge_fixture,
        charge_refunded,
        money_cents,
        money_zero,
        platform_part,
        platform_exit,
        env_get,
        out_write,
        /// A Net, Listener, or Conn row (net.zig).
        net_row,
        net_fixture,
        process,
        never_only,
        /// A design-v0/09 row stdlib.zig runs.
        stdlib,
    };

    const prim_names = std.StaticStringMap(Prim).initComptime(.{
        .{ "List.size", .list_size },               .{ "List.push", .list_push },                 .{ "List.map", .list_map },
        .{ "List.filter", .list_filter },           .{ "List.reduce", .list_reduce },             .{ "List.contains?", .list_contains },
        .{ "List.first", .list_first },             .{ "List.last", .list_last },                 .{ "String.size", .string_size },
        .{ "String.bytes", .string_bytes },         .{ "String.starts_with?", .string_starts_with }, .{ "Int.checked_add", .checked_add },
        .{ "Int.checked_sub", .checked_sub },       .{ "Int.checked_mul", .checked_mul },         .{ "Int.saturating_add", .saturating_add },
        .{ "Int.saturating_sub", .saturating_sub }, .{ "Int.saturating_mul", .saturating_mul },   .{ "Int.wrapping_add", .wrapping_add },
        .{ "Int.wrapping_sub", .wrapping_sub },     .{ "Int.wrapping_mul", .wrapping_mul },       .{ "Int.ms", .ms },
        .{ "Int.minute", .minute },                 .{ "Int.days", .days },                       .{ "Time.fixture", .time_fixture },
        .{ "Clock.now", .clock_now },               .{ "Clock.fixture", .clock_fixture },         .{ "Fs.read", .fs_read },
        .{ "Fs.scoped", .fs_narrow },               .{ "Fs.read_only", .fs_narrow },              .{ "Fs.fixture", .fs_fixture },
        .{ "Events.emit", .events_emit },           .{ "Events.fixture", .events_fixture },       .{ "Ledger.fixture", .ledger_fixture },
        .{ "Ledger.find_charge", .ledger_call },    .{ "Ledger.save_charge", .ledger_call },      .{ "Charge.fixture", .charge_fixture },
        .{ "Charge.refunded?", .charge_refunded },  .{ "Money.cents", .money_cents },             .{ "Money.zero", .money_zero },
        .{ "Process.start", .process },             .{ "Handle.send", .process },                 .{ "Handle.ask", .process },
        .{ "Supervisor.start", .process },          .{ "Platform.net", .platform_part },          .{ "Net.listen", .net_row },
        .{ "Net.connect", .net_row },               .{ "Listener.accept", .net_row },             .{ "Listener.port", .net_row },
        .{ "Conn.read_line", .net_row },            .{ "Conn.write", .net_row },                  .{ "Conn.close", .net_row },
        .{ "Net.fixture", .net_fixture },
        .{ "Type.all", .never_only },               .{ ".flows", .never_only },                   .{ "Platform.args", .platform_part },
        .{ "Platform.env", .platform_part },        .{ "Platform.stdout", .platform_part },       .{ "Platform.stderr", .platform_part },
        .{ "Platform.fs", .platform_part },         .{ "Platform.clock", .platform_part },        .{ "Platform.exit", .platform_exit },
        .{ "Env.get", .env_get },                   .{ "Out.write", .out_write },
    });

    /// Every prelude row has an implementation, or the toolchain does not build.
    const prim_of = blk: {
        @setEvalBranchQuota(20_000);
        var table: [prelude.fns.len]Prim = undefined;
        for (prelude.fns, 0..) |f, i| {
            const head = f.recv[0 .. std.mem.indexOfScalar(u8, f.recv, '(') orelse f.recv.len];
            table[i] = prim_names.get(head ++ "." ++ f.name) orelse if (stdlib.row_of[i] != .none) .stdlib else @compileError("vm.zig has no implementation of prelude row " ++ head ++ "." ++ f.name);
        }
        break :blk table;
    };

    fn prim(vm: *Vm, row_index: u32, kind_raw: u32) Error!void {
        const row = prelude.fns[row_index];
        const count: u32 = @intCast(@as(usize, if (row.on_type) 0 else 1) + row.params.len + row.named.len + @as(usize, if (row.can_wait) 1 else 0));
        const a = try vm.take(count);
        const result: Value = switch (prim_of[row_index]) {
            .list_size => .{ .int = @intCast(a[0].list.len) },
            .list_push => .{ .list = try vm.pushList(a[0].list, a[1]) },
            // Each step is a safe point; what the steps so far built is what is kept.
            .list_map => blk: {
                const out = try rawAlloc(vm.heap, Value, a[0].list.len);
                const from = vm.mark();
                var kept: usize = 0;
                for (a[0].list, 0..) |x, i| {
                    out[i] = try vm.invoke(a[1].func, &.{x});
                    kept = try vm.iterate(from, out[0 .. i + 1], kept);
                }
                break :blk .{ .list = out };
            },
            .list_filter => blk: {
                const out = try rawAlloc(vm.heap, Value, a[0].list.len);
                const from = vm.mark();
                var kept: usize = 0;
                var n: usize = 0;
                for (a[0].list) |x| {
                    if ((try vm.invoke(a[1].func, &.{x})).bool) {
                        out[n] = x;
                        n += 1;
                    }
                    kept = try vm.iterate(from, out[0..n], kept);
                }
                break :blk .{ .list = out[0..n] };
            },
            .list_reduce => blk: {
                var acc = [1]Value{a[1]};
                const from = vm.mark();
                var kept: usize = 0;
                for (a[0].list) |x| {
                    acc[0] = try vm.invoke(a[2].func, &.{ acc[0], x });
                    kept = try vm.iterate(from, &acc, kept);
                }
                break :blk acc[0];
            },
            .list_contains => .{ .bool = for (a[0].list) |x| {
                if (equal(x, a[1])) break true;
            } else false },
            .list_first => if (a[0].list.len == 0) try vm.variant("None", &.{}) else try vm.variant("Some", &.{a[0].list[0]}),
            .list_last => if (a[0].list.len == 0) try vm.variant("None", &.{}) else try vm.variant("Some", &.{a[0].list[a[0].list.len - 1]}),
            .string_size => .{ .int = graphemes(a[0].string) },
            .string_bytes => blk: {
                const out = try rawAlloc(vm.heap, Value, a[0].string.len);
                for (a[0].string, out) |byte, *o| o.* = .{ .int = byte };
                break :blk .{ .list = out };
            },
            .string_starts_with => .{ .bool = std.mem.startsWith(u8, a[0].string, a[1].string) },
            .checked_add, .checked_sub, .checked_mul, .saturating_add, .saturating_sub, .saturating_mul, .wrapping_add, .wrapping_sub, .wrapping_mul => try vm.edge(prim_of[row_index], @enumFromInt(kind_raw), a[0].int, a[1].int),
            .ms, .minute, .days => blk: {
                const unit: i128 = switch (prim_of[row_index]) {
                    .ms => 1,
                    .minute => 60_000,
                    else => 86_400_000,
                };
                const ms = a[0].int * unit;
                if (ms > std.math.maxInt(i64) or ms < std.math.minInt(i64)) {
                    vm.report = .{ .kind = .overflow, .clause = try std.fmt.allocPrint(vm.gpa, "{d}.{s} does not fit a Duration", .{ a[0].int, row.name }), .within = "", .at = 0 };
                    return error.Crash;
                }
                break :blk .{ .duration = @intCast(ms) };
            },
            .time_fixture => .{ .time = fixture_time },
            .clock_now => .{ .time = if (vm.sim) |s| s.clockNow() else if (vm.server) |s| s.now() else fixture_time },
            .clock_fixture => .{ .cap = .{ .kind = .clock } },
            // Under mo run the file system is real (server.zig); in a test it is a fixture's,
            // in memory (stdlib.FixtureFs), and one built with delay: answers after the delay.
            .fs_read => if (vm.server) |s|
                try s.read(vm, a[0].cap, a[1].string, a[2].duration)
            else
                try stdlib.call(vm, row, .fs_read, a, kind_raw),
            .fs_narrow => if (vm.server) |s| try s.narrow(a[0].cap, row.name, if (row.params.len == 1) a[1].string else "") else try stdlib.fixtureNarrow(vm, a[0].cap, row.name, if (row.params.len == 1) a[1].string else ""),
            .fs_fixture => try stdlib.fixtureFs(vm, if (row.named.len == 1) a[0].duration else 0),
            .events_emit => blk: {
                if (vm.sim) |s| try s.emit(a[1]);
                break :blk .none;
            },
            .events_fixture => .{ .cap = .{ .kind = .events } },
            .ledger_fixture => .{ .cap = .{ .kind = .ledger } },
            // A fixture Ledger finds every id as an unrefunded charge of 10_000 captured at
            // Time.fixture(), and every save succeeds, unless a seeded run's fault says not.
            .ledger_call => if (try vm.fixtureFault(false, "", a[a.len - 1].duration)) |failed|
                failed
            else if (std.mem.eql(u8, row.name, "find_charge")) blk: {
                const decl = vm.checked().findDecl("Charge").?;
                const fields = try rawAlloc(vm.heap, Value, 4);
                fields[0] = a[1];
                fields[1] = .{ .time = fixture_time };
                fields[2] = .{ .int = 10_000 };
                fields[3] = .{ .bool = false };
                const charge: Value = .{ .record = .{ .decl = decl, .fields = fields } };
                try vm.produced(charge);
                break :blk try vm.variant("Ok", &.{charge});
            } else try vm.variant("Ok", &.{.none}),
            .charge_fixture => blk: {
                const decl = vm.checked().findDecl("Charge").?;
                const fields = try rawAlloc(vm.heap, Value, 4);
                fields[0] = .{ .string = "ch_1" };
                fields[1] = if (row.named.len == 2) a[0] else .{ .time = fixture_time };
                fields[2] = a[row.named.len - 1];
                fields[3] = .{ .bool = false };
                const charge: Value = .{ .record = .{ .decl = decl, .fields = fields } };
                try vm.produced(charge);
                break :blk charge;
            },
            .charge_refunded => a[0].record.fields[3],
            .money_cents => a[0],
            .money_zero => .{ .int = 0 },
            // A Platform exists only in main, and only `mo run` calls main, on Mo.Server (Q18).
            .platform_part, .platform_exit, .env_get => blk: {
                const s = vm.server orelse {
                    vm.report = .{ .kind = .other, .clause = try std.fmt.allocPrint(vm.gpa, "{s}.{s} runs only under mo run", .{ row.recv, row.name }), .within = row.name, .at = 0 };
                    return error.Crash;
                };
                break :blk switch (prim_of[row_index]) {
                    .platform_part => try s.part(vm, row.name),
                    .platform_exit => exit: {
                        s.exit(a[1].int);
                        break :exit .none;
                    },
                    else => try s.envGet(vm, a[1].string),
                };
            },
            .out_write => blk: {
                try stdlib.writeOut(vm, row, a[0].cap, a[1].string, false);
                break :blk .none;
            },
            .net_row => try vm.netRow(std.meta.stringToEnum(net_mod.Row, row.name).?, a),
            .net_fixture => .{ .cap = .{ .kind = .net } },
            .stdlib => try stdlib.call(vm, row, stdlib.row_of[row_index], a, kind_raw),
            // Lowered to spawn, send, and ask; never reached as a prelude call.
            .process => unreachable,
            .never_only => {
                vm.report = .{ .kind = .other, .clause = "this runs only inside a never, which tier 2 does not evaluate", .within = row.name, .at = 0 };
                return error.Crash;
            },
        };
        try vm.push(result);
    }

    /// A Net, Listener, or Conn row: real sockets under mo run, or in a test a
    /// Net.fixture()'s, in memory (net.zig).
    fn netRow(vm: *Vm, which: net_mod.Row, a: []const Value) Error!Value {
        if (vm.server) |s| return s.sockets.call(vm, which, a);
        if (vm.sim) |s| return s.fixture.call(vm, s, which, a);
        vm.report = .{ .kind = .other, .clause = "Net runs only under mo run", .within = @tagName(which), .at = 0 };
        return error.Crash;
    }

    /// A fixture call in a seeded run with faults (sim.zig): the error it fails with, or
    /// null when it answers as the fixture does. `can_miss`: the call names a path.
    pub fn fixtureFault(vm: *Vm, can_miss: bool, path: []const u8, within: i64) Error!?Value {
        const s = vm.sim orelse return null;
        return switch (s.fault(if (can_miss) .missing else null, within) orelse return null) {
            .timeout => try vm.variant("Error", &.{try vm.variant("Timeout", &.{})}),
            .missing => try vm.variant("Error", &.{try vm.variant("Missing", &.{.{ .string = path }})}),
            .closed => unreachable,
        };
    }

    pub fn variant(vm: *Vm, name: []const u8, fields: []const Value) Error!Value {
        const out = try vm.allocValues(fields.len);
        @memcpy(out, fields);
        return .{ .variant = .{ .name = name, .fields = out } };
    }

    /// checked_, saturating_, and wrapping_: the only behaviours at an integer's edge
    /// besides the crash.
    fn edge(vm: *Vm, p: Prim, kind: types.IntKind, a: i128, b: i128) Error!Value {
        const exact: i128 = switch (p) {
            .checked_add, .saturating_add, .wrapping_add => a + b,
            .checked_sub, .saturating_sub, .wrapping_sub => a - b,
            else => a * b,
        };
        const fits = exact >= minOf(kind) and exact <= maxOf(kind);
        return switch (p) {
            .checked_add, .checked_sub, .checked_mul => if (fits) vm.variant("Some", &.{.{ .int = exact }}) else vm.variant("None", &.{}),
            .saturating_add, .saturating_sub, .saturating_mul => .{ .int = std.math.clamp(exact, minOf(kind), maxOf(kind)) },
            else => .{ .int = wrap(kind, exact) },
        };
    }

    // ---- any(T)

    /// A value of type `t` from the run's seed. Integers lean on their edges, where
    /// bugs live; the rest is uniform.
    fn generate(vm: *Vm, t: types.Id, depth: u32) Error!Value {
        const k = vm.checked();
        const rand = vm.rng.random();
        const ty = k.pool.get(k.pool.resolve(t));
        switch (ty.tag) {
            .int => {
                const kind: types.IntKind = @enumFromInt(ty.a);
                return .{ .int = switch (rand.uintLessThan(u8, 10)) {
                    0 => @max(0, minOf(kind)),
                    1 => @min(1, maxOf(kind)),
                    2 => maxOf(kind),
                    3 => minOf(kind),
                    4 => maxOf(kind) - 1,
                    5, 6 => @intCast(rand.uintLessThan(u8, 101)),
                    else => wrap(kind, rand.int(u64)),
                } };
            },
            .bool => return .{ .bool = rand.boolean() },
            .float => return .{ .float = (rand.float(f64) - 0.5) * 2e6 },
            .string => {
                const len = rand.uintLessThan(usize, 13);
                const out = try vm.gpa.alloc(u8, len);
                for (out) |*ch| ch.* = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_"[rand.uintLessThan(usize, 65)];
                return .{ .string = out };
            },
            .time => return .{ .time = fixture_time + rand.intRangeAtMost(i64, -365 * 86_400_000, 365 * 86_400_000) },
            .duration => return .{ .duration = rand.intRangeAtMost(i64, 0, 100 * 86_400_000) },
            .list => {
                const len = if (depth > 3) 0 else rand.uintLessThan(usize, 7);
                const out = try vm.gpa.alloc(Value, len);
                for (out) |*e| e.* = try vm.generate(ty.a, depth + 1);
                return .{ .list = out };
            },
            .option => return if (rand.uintLessThan(u8, 4) == 0) vm.variant("None", &.{}) else vm.variant("Some", &.{try vm.generate(ty.a, depth + 1)}),
            .tuple => {
                const elems = k.pool.elems(ty);
                const out = try vm.gpa.alloc(Value, elems.len);
                for (elems, out) |e, *o| o.* = try vm.generate(e, depth + 1);
                return .{ .tuple = out };
            },
            .map, .set => {
                const stride: usize = if (ty.tag == .map) 2 else 1;
                const tries = if (depth > 3) 0 else rand.uintLessThan(usize, 7);
                var out: std.ArrayList(Value) = .empty;
                for (0..tries) |_| {
                    const key = try vm.generate(ty.a, depth + 1);
                    if (stdlib.indexOf(out.items, stride, key) != null) continue;
                    try out.append(vm.gpa, key);
                    if (stride == 2) try out.append(vm.gpa, try vm.generate(ty.b, depth + 1));
                }
                const m = try stdlib.mapOf(vm.gpa, out.items, stride);
                return if (stride == 2) .{ .map = m } else .{ .set = m };
            },
            .alias => {
                // A refined alias generates values that satisfy it; after 100 misses the
                // last one stands, and the boundary check reports it.
                const refs = vm.program.alias_refinements[ty.a];
                var attempt: u32 = 0;
                while (true) : (attempt += 1) {
                    const v = try vm.generate(ty.b, depth);
                    const holds = for (refs) |r| {
                        if (!(try vm.call(vm.program.refinements[r].function, &.{v})).bool) break false;
                    } else true;
                    if (holds or attempt == 100) return v;
                }
            },
            .decl => {
                const d = k.decls[ty.a];
                switch (d.kind) {
                    .struct_ => {
                        const defs = k.fields[d.fields.start..d.fields.end];
                        const out = try vm.gpa.alloc(Value, defs.len);
                        for (defs, out) |f, *o| o.* = try vm.generate(f.type, depth + 1);
                        return .{ .record = .{ .decl = ty.a, .fields = out } };
                    },
                    .enum_, .prelude_enum => {
                        const v = k.variants[d.variants.start + rand.uintLessThan(u32, d.variants.len())];
                        const defs = k.fields[v.fields.start..v.fields.end];
                        const out = try vm.gpa.alloc(Value, defs.len);
                        for (defs, out) |f, *o| o.* = try vm.generate(f.type, depth + 1);
                        return .{ .variant = .{ .name = v.name, .fields = out } };
                    },
                    else => {},
                }
            },
            else => {},
        }
        vm.report = .{ .kind = .other, .clause = try std.fmt.allocPrint(vm.gpa, "any({s}) does not generate values yet", .{try k.pool.name(vm.gpa, t)}), .within = "", .at = 0 };
        return error.Crash;
    }

    // ---- rendering

    /// A value as Mo source, for reports.
    pub fn render(vm: *Vm, v: Value) Error![]const u8 {
        var aw: std.Io.Writer.Allocating = .init(vm.gpa);
        vm.formatValue(&aw.writer, v) catch return error.OutOfMemory;
        return aw.written();
    }

    /// Interpolation: a string is its text, anything else as it is written in source.
    fn formatText(vm: *Vm, w: *std.Io.Writer, v: Value) std.Io.Writer.Error!void {
        if (v == .string) return w.writeAll(v.string);
        return vm.formatValue(w, v);
    }

    pub fn formatValue(vm: *Vm, w: *std.Io.Writer, v: Value) std.Io.Writer.Error!void {
        const k = vm.checked();
        switch (v) {
            .none => try w.writeAll("no value"),
            .bool => |b| try w.writeAll(if (b) "true" else "false"),
            .int => |i| try w.print("{d}", .{i}),
            .float => |f| try w.print("{d}", .{f}),
            .string => |s| try w.print("\"{s}\"", .{s}),
            .time => |t| if (t == fixture_time)
                try w.writeAll("Time.fixture()")
            else if (t > fixture_time)
                try w.print("Time.fixture() + {d}.ms", .{t - fixture_time})
            else
                try w.print("Time.fixture() - {d}.ms", .{fixture_time - t}),
            .duration => |d| try w.print("{d}.ms", .{d}),
            .list, .tuple => |elems| {
                try w.writeAll(if (v == .list) "[" else "(");
                for (elems, 0..) |e, i| {
                    if (i > 0) try w.writeAll(", ");
                    try vm.formatValue(w, e);
                }
                try w.writeAll(if (v == .list) "]" else ")");
            },
            .record => |r| {
                const d = k.decls[r.decl];
                try vm.formatFields(w, d.name, r.fields, k.fields[d.fields.start..d.fields.end]);
            },
            .variant => |r| {
                const defs: []const check.Field = for (k.variants) |kv| {
                    if (std.mem.eql(u8, kv.name, r.name) and kv.fields.len() == r.fields.len) break k.fields[kv.fields.start..kv.fields.end];
                } else &.{};
                if (r.fields.len == 1 or defs.len != r.fields.len) {
                    try w.writeAll(r.name);
                    if (r.fields.len == 0) return;
                    try w.writeAll("(");
                    for (r.fields, 0..) |e, i| {
                        if (i > 0) try w.writeAll(", ");
                        try vm.formatValue(w, e);
                    }
                    try w.writeAll(")");
                } else try vm.formatFields(w, r.name, r.fields, defs);
            },
            .map => |m| {
                const xs = m.entries;
                try w.writeAll("Map.new()");
                var at: usize = 0;
                while (at < xs.len) : (at += 2) {
                    try w.writeAll(".set(");
                    try vm.formatValue(w, xs[at]);
                    try w.writeAll(", ");
                    try vm.formatValue(w, xs[at + 1]);
                    try w.writeAll(")");
                }
            },
            .set => |m| {
                try w.writeAll("Set.new()");
                for (m.entries) |x| {
                    try w.writeAll(".add(");
                    try vm.formatValue(w, x);
                    try w.writeAll(")");
                }
            },
            .func => try w.writeAll("a function"),
            .cap => |c| try w.writeAll(switch (c.kind) {
                .clock => if (vm.server != null) "a Clock" else "Clock.fixture()",
                .fs => if (vm.server != null) "an Fs" else "Fs.fixture()",
                .events => "Events.fixture()",
                .ledger => "Ledger.fixture()",
                .platform => "the Platform",
                .env => "an Env",
                .out => if (vm.server == null) "Out.fixture()" else if (c.handle == server_mod.stderr_handle) "an Out (stderr)" else "an Out (stdout)",
                .net => if (vm.server != null) "a Net" else "Net.fixture()",
                .listener => "a Listener",
                .conn => "a Conn",
            }),
            .handle => |h| if (vm.sim) |s| try w.print("{s} #{d}", .{ s.nameOf(h), h }) else try w.print("a handle #{d}", .{h}),
        }
    }

    fn formatFields(vm: *Vm, w: *std.Io.Writer, name: []const u8, values: []const Value, defs: []const check.Field) std.Io.Writer.Error!void {
        try w.writeAll(name);
        if (values.len == 0) return;
        try w.writeAll("(");
        for (values, 0..) |e, i| {
            if (i > 0) try w.writeAll(", ");
            if (i < defs.len) try w.print("{s}: ", .{defs[i].name});
            try vm.formatValue(w, e);
        }
        try w.writeAll(")");
    }
};

/// `n` items of `T` from `a`, not yet written. Allocator.alloc in a safe build first fills
/// what it gives with 0xAA; every caller of this writes each item at once, so it skips that,
/// which a compaction's copies otherwise pay for on every buffer.
pub fn rawAlloc(a: std.mem.Allocator, comptime T: type, n: usize) error{OutOfMemory}![]T {
    if (n == 0) return @as([*]T, @ptrFromInt(@alignOf(T)))[0..0];
    const len = std.math.mul(usize, n, @sizeOf(T)) catch return error.OutOfMemory;
    const bytes = a.rawAlloc(len, .of(T), @returnAddress()) orelse return error.OutOfMemory;
    return @as([*]T, @ptrCast(@alignCast(bytes)))[0..n];
}

/// A copy of `xs` from `a`, as rawAlloc gives it.
pub fn rawDupe(a: std.mem.Allocator, comptime T: type, xs: []const T) error{OutOfMemory}![]T {
    const out = try rawAlloc(a, T, xs.len);
    @memcpy(out, xs);
    return out;
}

/// The newest address a value's own parts start at, when it has a non-empty one: a map's
/// index can be newer than its entries.
fn newestOf(v: Value) ?usize {
    const addr: usize, const len: usize = switch (v) {
        .string => |s| .{ @intFromPtr(s.ptr), s.len },
        .list, .tuple => |xs| .{ @intFromPtr(xs.ptr), xs.len },
        .map, .set => |m| return if (m.entries.len == 0) null else if (m.index.len == 0) @intFromPtr(m.entries.ptr) else @max(@intFromPtr(m.entries.ptr), @intFromPtr(m.index.ptr)),
        .record => |x| .{ @intFromPtr(x.fields.ptr), x.fields.len },
        .variant => |x| .{ @intFromPtr(x.fields.ptr), x.fields.len },
        .func => |x| .{ @intFromPtr(x.captures.ptr), x.captures.len },
        else => return null,
    };
    return if (len == 0) null else addr;
}

fn fieldsOf(v: Value) []const Value {
    return switch (v) {
        .record => |r| r.fields,
        .variant => |r| r.fields,
        .tuple, .list => |elems| elems,
        .map, .set => |m| m.entries,
        else => unreachable,
    };
}

/// Structural equality: there is no identity for values (chapter 3).
pub fn equal(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .none => true,
        .bool => |x| x == b.bool,
        .int => |x| x == b.int,
        .float => |x| x == b.float,
        .string => |x| std.mem.eql(u8, x, b.string),
        .time => |x| x == b.time,
        .duration => |x| x == b.duration,
        // Two maps or sets are equal when they hold equal entries in the same order.
        .list, .tuple => |x| allEqual(x, fieldsOf(b)),
        .map, .set => |x| allEqual(x.entries, fieldsOf(b)),
        .record => |x| x.decl == b.record.decl and allEqual(x.fields, b.record.fields),
        .variant => |x| std.mem.eql(u8, x.name, b.variant.name) and allEqual(x.fields, b.variant.fields),
        .func => |x| x.function == b.func.function and allEqual(x.captures, b.func.captures),
        .cap => |x| x.kind == b.cap.kind and x.delay == b.cap.delay and x.handle == b.cap.handle,
        .handle => |x| x == b.handle,
    };
}

pub fn allEqual(a: []const Value, b: []const Value) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (!equal(x, y)) return false;
    return true;
}

fn compare(op: Op, l: Value, r: Value) bool {
    switch (op) {
        .eq => return equal(l, r),
        .ne => return !equal(l, r),
        else => {},
    }
    const ord: std.math.Order = switch (l) {
        .float => |a| std.math.order(a, r.float),
        else => order(l, r),
    };
    return switch (op) {
        .lt => ord == .lt,
        .le => ord != .gt,
        .gt => ord == .gt,
        else => ord != .lt,
    };
}

/// The natural order (design-v0/09): numbers, strings byte by byte, times, durations, and
/// tuples of those left to right. A NaN orders after every number and level with another
/// NaN, so a sort is total.
pub fn order(l: Value, r: Value) std.math.Order {
    return switch (l) {
        .int => |a| std.math.order(a, r.int),
        .float => |a| blk: {
            const an = std.math.isNan(a);
            const bn = std.math.isNan(r.float);
            break :blk if (an or bn) std.math.order(@intFromBool(an), @intFromBool(bn)) else std.math.order(a, r.float);
        },
        .string => |a| std.mem.order(u8, a, r.string),
        .time => |a| std.math.order(a, r.time),
        .duration => |a| std.math.order(a, r.duration),
        .tuple => |xs| for (xs, r.tuple) |x, y| {
            const o = order(x, y);
            if (o != .eq) break o;
        } else .eq,
        else => unreachable,
    };
}

pub fn minOf(kind: types.IntKind) i128 {
    return switch (kind) {
        .i8 => std.math.minInt(i8),
        .i16 => std.math.minInt(i16),
        .i32 => std.math.minInt(i32),
        .i64 => std.math.minInt(i64),
        .u8, .u16, .u32, .u64 => 0,
    };
}

pub fn maxOf(kind: types.IntKind) i128 {
    return switch (kind) {
        .i8 => std.math.maxInt(i8),
        .i16 => std.math.maxInt(i16),
        .i32 => std.math.maxInt(i32),
        .i64 => std.math.maxInt(i64),
        .u8 => std.math.maxInt(u8),
        .u16 => std.math.maxInt(u16),
        .u32 => std.math.maxInt(u32),
        .u64 => std.math.maxInt(u64),
    };
}

/// The value's low bits as the kind: two's-complement wrapping.
fn wrap(kind: types.IntKind, v: i128) i128 {
    return switch (kind) {
        .i8 => @as(i8, @truncate(v)),
        .i16 => @as(i16, @truncate(v)),
        .i32 => @as(i32, @truncate(v)),
        .i64 => @as(i64, @truncate(v)),
        .u8 => @as(u8, @truncate(@as(u128, @bitCast(v)))),
        .u16 => @as(u16, @truncate(@as(u128, @bitCast(v)))),
        .u32 => @as(u32, @truncate(@as(u128, @bitCast(v)))),
        .u64 => @as(u64, @truncate(@as(u128, @bitCast(v)))),
    };
}

/// Graphemes, approximated as a code point with the combining marks after it: `café` is
/// 4 however it is encoded (stdlib.Graphemes). Full segmentation (emoji sequences) waits.
fn graphemes(s: []const u8) i128 {
    return stdlib.count(s);
}

// ---- tests

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const caps = @import("caps.zig");
const diag = @import("diag.zig");

fn compile(arena: std.mem.Allocator, src: []const u8) !bytecode.Program {
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    const checked_module = try check.check(arena, tree, &diags);
    try caps.check(arena, checked_module, &diags);
    for (diags.items) |d| std.debug.print("{s} at {d}: {s}\n", .{ d.code, d.at, d.what });
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);
    return bytecode.lower(arena, checked_module);
}

fn callNamed(vm: *Vm, name: []const u8, args: []const Value) Error!Value {
    return vm.call(vm.program.findFunction(name).?, args);
}

test "integer arithmetic traps on overflow; the named edges do not" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Edge
        \\fn bump(n: UInt8) : UInt8
        \\  n + 1
        \\end
        \\fn wrapped(n: UInt8) : UInt8
        \\  n.wrapping_add(1)
        \\end
        \\fn less(n: Int32) : Int32
        \\  -n
        \\end
    );
    var vm: Vm = .init(arena, &program, 0);
    try std.testing.expectEqual(@as(i128, 255), (try callNamed(&vm, "bump", &.{.{ .int = 254 }})).int);
    try std.testing.expectError(error.Crash, callNamed(&vm, "bump", &.{.{ .int = 255 }}));
    try std.testing.expectEqual(contracts.Kind.overflow, vm.report.?.kind);
    try std.testing.expectEqualStrings("n + 1", vm.report.?.clause);
    try std.testing.expectEqual(@as(i128, 0), (try callNamed(&vm, "wrapped", &.{.{ .int = 255 }})).int);
    try std.testing.expectEqual(@as(i128, -5), (try callNamed(&vm, "less", &.{.{ .int = 5 }})).int);
}

test "a var copy never aliases, and inout writes back on return" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Values
        \\struct Cart
        \\  items: UInt32
        \\end
        \\fn add(inout cart: Cart) : UInt32
        \\  cart.items += 1
        \\  cart.items
        \\end
        \\fn twice() : (UInt32, UInt32)
        \\  var cart = Cart(items: 0)
        \\  var copy = cart
        \\  copy.items = 7
        \\  first = add(cart)
        \\  (first + add(cart), copy.items)
        \\end
    );
    var vm: Vm = .init(arena, &program, 0);
    const pair = try callNamed(&vm, "twice", &.{});
    try std.testing.expectEqual(@as(i128, 3), pair.tuple[0].int);
    try std.testing.expectEqual(@as(i128, 7), pair.tuple[1].int);
}

test "contracts: requires on entry, ensures with old and result, refinements at the boundary" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Contracts
        \\type Percent = UInt32 where value <= 100
        \\struct Cart
        \\  items: UInt32
        \\end
        \\fn split(total: UInt32, people: UInt32) : UInt32
        \\  requires people > 0
        \\
        \\  total / people
        \\end
        \\fn add(inout cart: Cart, n: UInt32) : UInt32
        \\  ensures cart.items == old(cart.items) + n
        \\  ensures result + 1 > old(cart.items)
        \\
        \\  cart.items += n
        \\  cart.items
        \\end
        \\fn wrong(inout cart: Cart) : UInt32
        \\  ensures cart.items == old(cart.items) + 1
        \\
        \\  cart.items
        \\end
        \\fn off(p: Percent) : UInt32
        \\  p
        \\end
        \\test rejects "nobody"
        \\  split(1, 0)
        \\end
    );
    var vm: Vm = .init(arena, &program, 0);
    try std.testing.expectError(error.Crash, callNamed(&vm, "split", &.{ .{ .int = 1 }, .{ .int = 0 } }));
    try std.testing.expectEqual(contracts.Kind.requires, vm.report.?.kind);
    try std.testing.expectEqualStrings("requires people > 0", vm.report.?.clause);
    try std.testing.expectEqualStrings("0", vm.report.?.values[1].value);

    const cart_decl = program.checked.findDecl("Cart").?;
    const max: Value = .{ .record = .{ .decl = cart_decl, .fields = &.{.{ .int = std.math.maxInt(u32) }} } };
    // result + 1 passes UInt32 here, and a contract does not overflow.
    try std.testing.expectEqual(@as(i128, std.math.maxInt(u32)), (try callNamed(&vm, "add", &.{ max, .{ .int = 0 } })).int);
    try std.testing.expectError(error.Crash, callNamed(&vm, "wrong", &.{max}));
    try std.testing.expectEqual(contracts.Kind.ensures, vm.report.?.kind);
    try std.testing.expectEqualStrings("ensures cart.items == old(cart.items) + 1", vm.report.?.clause);

    try std.testing.expectEqual(@as(i128, 100), (try callNamed(&vm, "off", &.{.{ .int = 100 }})).int);
    try std.testing.expectError(error.Crash, callNamed(&vm, "off", &.{.{ .int = 101 }}));
    try std.testing.expectEqual(contracts.Kind.refinement, vm.report.?.kind);
    try std.testing.expectEqualStrings("where value <= 100", vm.report.?.clause);

    const percent = program.checked.decls[program.checked.findDecl("Percent").?].type;
    for (0..50) |_| try std.testing.expect((try vm.generate(percent, 0)).int <= 100);
}

test "under a region, push is linear, loops free what they do not keep, and compaction keeps values whole" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Region
        \\struct Pair
        \\  name: String
        \\  n: UInt32
        \\end
        \\struct Cart
        \\  items: List(String)
        \\end
        \\fn pushes(n: UInt32) : UInt64
        \\  (0..n).reduce([], fn(acc, i) acc.push(i) end).size
        \\end
        \\fn garbage(n: UInt32) : UInt64
        \\  (0..n).reduce(0, fn(acc, i) acc + "#{i}#{i}#{i}".size end)
        \\end
        \\fn pairs(n: UInt32) : List(Pair)
        \\  (0..n).reduce([], fn(acc, i) acc.push(Pair(name: "n#{i}", n: i)) end)
        \\end
        \\fn forked() : (List(UInt32), List(UInt32))
        \\  xs = [1, 2].push(3)
        \\  (xs.push(4), xs.push(5))
        \\end
        \\fn add(inout cart: Cart, name: String) : UInt64
        \\  cart.items = cart.items.push("#{name}!")
        \\  cart.items.size
        \\end
        \\fn shop() : (UInt64, List(String))
        \\  var cart = Cart(items: [])
        \\  first = add(cart, "a")
        \\  (first + add(cart, "b"), cart.items)
        \\end
        \\fn looped(n: UInt32) : String
        \\  var last = ""
        \\  for i in 0..n
        \\    last = "#{i}#{last.size}"
        \\  end
        \\  last
        \\end
    );
    var values = try Region.reserve();
    defer values.release();
    var scratch = try Region.reserve();
    defer scratch.release();
    // A budget of 0 compacts at every safe point, the hardest case for what is kept.
    for ([_]usize{ 0, 1 << 20 }) |budget| {
        values.top = values.base;
        var vm: Vm = .init(arena, &program, 0);
        vm.useRegions(&values, &scratch);
        vm.frame_budget = budget;
        vm.loop_budget = budget;
        try std.testing.expectEqual(@as(i128, 20_000), (try callNamed(&vm, "pushes", &.{.{ .int = 20_000 }})).int);

        const before = values.top;
        try std.testing.expectEqual(@as(i128, 3 * 10 + 3 * 2 * 90 + 3 * 3 * 900 + 3 * 4 * 9_000), (try callNamed(&vm, "garbage", &.{.{ .int = 10_000 }})).int);
        try std.testing.expect(values.top - before < 4 << 20);

        const ps = try callNamed(&vm, "pairs", &.{.{ .int = 3_000 }});
        try std.testing.expectEqual(@as(usize, 3_000), ps.list.len);
        for (ps.list, 0..) |p, i| {
            var buf: [16]u8 = undefined;
            try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "n{d}", .{i}), p.record.fields[0].string);
            try std.testing.expectEqual(@as(i128, @intCast(i)), p.record.fields[1].int);
        }

        const forks = (try callNamed(&vm, "forked", &.{})).tuple;
        try std.testing.expectEqual(@as(i128, 4), forks[0].list[3].int);
        try std.testing.expectEqual(@as(i128, 5), forks[1].list[3].int);
        try std.testing.expectEqual(@as(usize, 4), forks[1].list.len);

        const shopped = (try callNamed(&vm, "shop", &.{})).tuple;
        try std.testing.expectEqual(@as(i128, 3), shopped[0].int);
        try std.testing.expectEqualStrings("b!", shopped[1].list[1].string);

        try std.testing.expectEqualStrings("22", (try callNamed(&vm, "looped", &.{.{ .int = 3 }})).string);
    }
}

test "maps and sets keep their order and find through their index; a var or a field path writes in place, and a copy taken before never sees it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Maps
        \\struct Box
        \\  data: Map(String, UInt64)
        \\  seen: Set(UInt64)
        \\end
        \\fn built(n: UInt64) : Map(String, UInt64)
        \\  var m = Map.new()
        \\  for i in 0..n
        \\    m = m.set("k#{i}", i)
        \\  end
        \\  for i in 0..n
        \\    if i % 3 == 0
        \\      m = m.remove("k#{i}")
        \\    end
        \\  end
        \\  m
        \\end
        \\fn present(m: Map(String, UInt64), n: UInt64) : UInt64
        \\  (0..n).count(fn(i) m.has?("k#{i}") end)
        \\end
        \\fn boxed(n: UInt64) : (Box, Map(String, UInt64))
        \\  var box = Box(data: Map.new(), seen: Set.new())
        \\  var early = box.data
        \\  for i in 0..n
        \\    box.data = box.data.set("k#{i % 50}", i)
        \\    box.seen = box.seen.add(i % 20)
        \\    if i == 60
        \\      early = box.data
        \\    end
        \\  end
        \\  (box, early)
        \\end
    );
    var values = try Region.reserve();
    defer values.release();
    var scratch = try Region.reserve();
    defer scratch.release();
    // Without a region, then under one compacting at every safe point, and under the default.
    for ([_]?usize{ null, 0, 1 << 20 }) |budget| {
        values.top = values.base;
        var vm: Vm = .init(arena, &program, 0);
        if (budget) |b| {
            vm.useRegions(&values, &scratch);
            vm.frame_budget = b;
            vm.loop_budget = b;
        }
        const m = (try callNamed(&vm, "built", &.{.{ .int = 100 }})).map;
        try std.testing.expectEqual(@as(usize, 2 * 66), m.entries.len);
        try std.testing.expect(m.index.len >= 2 * 66);
        for (0..66) |k| {
            const i = 3 * k / 2 + 1;
            var buf: [8]u8 = undefined;
            try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "k{d}", .{i}), m.entries[2 * k].string);
            try std.testing.expectEqual(@as(i128, @intCast(i)), m.entries[2 * k + 1].int);
        }
        try std.testing.expectEqual(@as(i128, 66), (try callNamed(&vm, "present", &.{ .{ .map = m }, .{ .int = 100 } })).int);

        const pair = (try callNamed(&vm, "boxed", &.{.{ .int = 200 }})).tuple;
        const data = pair[0].record.fields[0].map.entries;
        const early = pair[1].map.entries;
        try std.testing.expectEqual(@as(usize, 100), data.len);
        try std.testing.expectEqualStrings("k10", data[20].string);
        try std.testing.expectEqual(@as(i128, 160), data[21].int);
        try std.testing.expectEqual(@as(i128, 161), data[23].int);
        try std.testing.expectEqual(@as(i128, 60), early[21].int);
        try std.testing.expectEqual(@as(i128, 11), early[23].int);
        const seen = pair[0].record.fields[1].set.entries;
        try std.testing.expectEqual(@as(usize, 20), seen.len);
        for (seen, 0..) |x, k| try std.testing.expectEqual(@as(i128, @intCast(k)), x.int);
    }
}

test "a remembered call gives what running it gives, and a call that trips still trips" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Memo
        \\fn digits(n: UInt32) : String
        \\  requires n < 100
        \\
        \\  (0..n).reduce("", fn(text, i) "#{text}#{i % 10}" end)
        \\end
        \\fn both(n: UInt32) : (String, String)
        \\  (digits(n % 7), digits(n % 7 + 1))
        \\end
        \\test rejects "a hundred digits"
        \\  digits(100)
        \\end
    );
    var memo: Memo = try .init(arena, program.functions.len);
    defer memo.deinit();
    memo.watch_calls = 2;
    memo.min_steps = 1;
    var vm: Vm = .init(arena, &program, 0);
    vm.memo = &memo;
    const all = "0123456789";
    for (0..50) |i| {
        const pair = (try callNamed(&vm, "both", &.{.{ .int = i }})).tuple;
        try std.testing.expectEqualStrings(all[0 .. i % 7], pair[0].string);
        try std.testing.expectEqualStrings(all[0 .. i % 7 + 1], pair[1].string);
    }
    try std.testing.expect(memo.stats[program.findFunction("digits").?].hits > 40);
    try std.testing.expectError(error.Crash, callNamed(&vm, "digits", &.{.{ .int = 100 }}));
    try std.testing.expectEqual(contracts.Kind.requires, vm.report.?.kind);
}

test "a negative number is a pattern, and byte_size counts bytes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Negative
        \\fn sign(r: Result(Int64, String)) : String
        \\  case r
        \\    Ok(-5): "minus five"
        \\    Ok(-9223372036854775808): "lowest"
        \\    Ok(5): "five"
        \\    Ok(_): "other"
        \\    Error(_): "error"
        \\  end
        \\end
        \\fn size_in_bytes(s: String) : UInt64
        \\  s.byte_size
        \\end
    );
    var vm: Vm = .init(arena, &program, 0);
    const cases = [_]struct { i128, []const u8 }{ .{ -5, "minus five" }, .{ 5, "five" }, .{ std.math.minInt(i64), "lowest" }, .{ -6, "other" } };
    for (cases) |c| {
        const r = try vm.variant("Ok", &.{.{ .int = c[0] }});
        try std.testing.expectEqualStrings(c[1], (try callNamed(&vm, "sign", &.{r})).string);
    }
    try std.testing.expectEqual(@as(i128, 6), (try callNamed(&vm, "size_in_bytes", &.{.{ .string = "café!" }})).int);
}

test "closures, patterns, strings, and try" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Mix
        \\enum E
        \\  Gone(path: String)
        \\  Late
        \\end
        \\fn over(xs: List(UInt32), limit: UInt32) : List(String)
        \\  xs.filter(fn(x) x > limit end).map(fn(x) "#{x}!" end)
        \\end
        \\fn name(r: Result(UInt32, E)) : String
        \\  case r
        \\    Ok(n) if n > 9: "big"
        \\    Ok(_): "small"
        \\    Error(Gone(p)): p
        \\    Error(Late): "late"
        \\  end
        \\end
        \\fn up(r: Result(UInt32, E)) : Result(UInt32, E)
        \\  n = try r
        \\  Ok(n * 2)
        \\end
    );
    var vm: Vm = .init(arena, &program, 0);
    const xs = [_]Value{ .{ .int = 3 }, .{ .int = 12 }, .{ .int = 40 } };
    const out = try callNamed(&vm, "over", &.{ .{ .list = &xs }, .{ .int = 10 } });
    try std.testing.expectEqual(@as(usize, 2), out.list.len);
    try std.testing.expectEqualStrings("40!", out.list[1].string);
    const gone = try vm.variant("Error", &.{try vm.variant("Gone", &.{.{ .string = "/tmp" }})});
    try std.testing.expectEqualStrings("/tmp", (try callNamed(&vm, "name", &.{gone})).string);
    try std.testing.expectEqualStrings("big", (try callNamed(&vm, "name", &.{try vm.variant("Ok", &.{.{ .int = 10 }})})).string);
    try std.testing.expect(equal(gone, try callNamed(&vm, "up", &.{gone})));
    const doubled = try callNamed(&vm, "up", &.{try vm.variant("Ok", &.{.{ .int = 4 }})});
    try std.testing.expectEqual(@as(i128, 8), doubled.variant.fields[0].int);
}
