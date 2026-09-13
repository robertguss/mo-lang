//! The bytecode interpreter: the edit-loop runtime and the executable reference
//! semantics (design-v0/07). Hosts contracts, the test runner, and later the
//! simulator, replay, and fault injection. A tripped contract or an overflow is
//! a crash with a complete report, never a value.
//!
//! Values are immutable: a list, a tuple, a struct, or a variant is a slice nothing
//! else writes, and changing a field builds a new one, so a `var` copied from another
//! name can never alias it. Everything a run allocates comes from the allocator it
//! is given; the runner gives each test its own arena and frees it whole.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const check = @import("check.zig");
const contracts = @import("contracts.zig");
const prelude = @import("prelude.zig");
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
    record: Record,
    variant: Variant,
    func: Func,
    cap: Cap,

    pub const Record = struct { decl: u32, fields: []const Value };
    /// A variant is known by its name, so `try` re-tags an error without converting it.
    pub const Variant = struct { name: []const u8, fields: []const Value };
    pub const Func = struct { function: u32, captures: []const Value };
    pub const Cap = struct { kind: types.CapKind, delay: i64 = 0 };
};

/// `Time.fixture()` and a fixture clock's frozen `now`: 2026-01-01T00:00:00Z.
pub const fixture_time: i64 = 1_767_225_600_000;

pub const Generated = struct { name: []const u8, value: Value };

pub const Vm = struct {
    gpa: std.mem.Allocator,
    program: *const bytecode.Program,
    stack: std.ArrayList(Value) = .empty,
    /// Set when a call fails with Crash or Skip.
    report: ?contracts.Report = null,
    rng: std.Random.DefaultPrng,
    /// The values `any(T)` produced in this run, in order, for a property's report.
    generated: std.ArrayList(Generated) = .empty,

    pub fn init(gpa: std.mem.Allocator, program: *const bytecode.Program, seed: u64) Vm {
        return .{ .gpa = gpa, .program = program, .rng = .init(seed) };
    }

    /// Calls functions[function] with `args` and returns its result.
    pub fn call(vm: *Vm, function: u32, args: []const Value) Error!Value {
        return (try vm.exec(function, args, &.{})).value;
    }

    fn checked(vm: *Vm) *const check.Checked {
        return &vm.program.checked;
    }

    fn push(vm: *Vm, v: Value) Error!void {
        try vm.stack.append(vm.gpa, v);
    }

    fn pop(vm: *Vm) Value {
        return vm.stack.pop().?;
    }

    /// The top `n` values, oldest first, removed from the stack.
    fn take(vm: *Vm, n: u32) Error![]Value {
        const len = vm.stack.items.len;
        const out = try vm.gpa.dupe(Value, vm.stack.items[len - n ..]);
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

    const Return = struct { value: Value, locals: []const Value };

    fn exec(vm: *Vm, fi: u32, args: []const Value, captures: []const Value) Error!Return {
        const f = vm.program.functions[fi];
        const locals = try vm.gpa.alloc(Value, f.locals);
        @memset(locals, .none);
        @memcpy(locals[0..args.len], args);
        for (f.captures, captures) |slot, v| locals[slot] = v;
        const base = vm.stack.items.len;
        var pc: u32 = 0;
        while (true) {
            const inst = f.code[pc];
            pc += 1;
            switch (inst.op) {
                .constant => try vm.push(vm.constant(inst.a)),
                .pop => _ = vm.pop(),
                .swap => {
                    const s = vm.stack.items;
                    std.mem.swap(Value, &s[s.len - 1], &s[s.len - 2]);
                },
                .load => try vm.push(locals[inst.a]),
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
                .record => try vm.push(.{ .record = .{ .decl = inst.a, .fields = try vm.take(inst.b) } }),
                .variant => try vm.push(.{ .variant = .{ .name = vm.program.constants[inst.a].string, .fields = try vm.take(inst.b) } }),
                .field => try vm.push(fieldsOf(vm.pop())[inst.a]),
                .set_field => {
                    const v = vm.pop();
                    const obj = vm.pop();
                    const fields = try vm.gpa.dupe(Value, fieldsOf(obj));
                    fields[inst.a] = v;
                    try vm.push(switch (obj) {
                        .record => |r| .{ .record = .{ .decl = r.decl, .fields = fields } },
                        .variant => |r| .{ .variant = .{ .name = r.name, .fields = fields } },
                        .tuple => .{ .tuple = fields },
                        else => unreachable,
                    });
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
                    const elems = try vm.gpa.alloc(Value, n);
                    for (elems, 0..) |*e, k| e.* = .{ .int = lo + @as(i128, @intCast(k)) };
                    try vm.push(.{ .list = elems });
                },
                .concat => {
                    const parts = try vm.take(inst.a);
                    var aw: std.Io.Writer.Allocating = .init(vm.gpa);
                    for (parts) |p| vm.formatText(&aw.writer, p) catch return error.OutOfMemory;
                    try vm.push(.{ .string = aw.written() });
                },
                .call, .call_trait => {
                    const args_now = try vm.take(inst.b);
                    const target = if (inst.op == .call) inst.a else try vm.dispatch(inst.a, args_now[0]);
                    const r = try vm.exec(target, args_now, &.{});
                    try vm.push(r.value);
                    for (vm.program.functions[target].inouts) |slot| try vm.push(r.locals[slot]);
                },
                .call_value => {
                    const args_now = try vm.take(inst.a);
                    try vm.push(try vm.invoke(vm.pop().func, args_now));
                },
                .closure => try vm.push(.{ .func = .{ .function = inst.a, .captures = try vm.take(inst.b) } }),
                .prim => try vm.prim(inst.a, inst.b),
                .ret => {
                    const v = vm.pop();
                    vm.stack.shrinkRetainingCapacity(base);
                    return .{ .value = v, .locals = locals };
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
            }
        }
    }

    /// Calls a function value.
    pub fn invoke(vm: *Vm, func: Value.Func, args: []const Value) Error!Value {
        return (try vm.exec(func.function, args, func.captures)).value;
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
        process,
        never_only,
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
        .{ "Type.all", .never_only },               .{ ".flows", .never_only },
    });

    /// Every prelude row has an implementation, or the toolchain does not build.
    const prim_of = blk: {
        var table: [prelude.fns.len]Prim = undefined;
        for (prelude.fns, 0..) |f, i| {
            const head = f.recv[0 .. std.mem.indexOfScalar(u8, f.recv, '(') orelse f.recv.len];
            table[i] = prim_names.get(head ++ "." ++ f.name) orelse @compileError("vm.zig has no implementation of prelude row " ++ head ++ "." ++ f.name);
        }
        break :blk table;
    };

    fn prim(vm: *Vm, row_index: u32, kind_raw: u32) Error!void {
        const row = prelude.fns[row_index];
        const count: u32 = @intCast(@as(usize, if (row.on_type) 0 else 1) + row.params.len + row.named.len + @as(usize, if (row.can_wait) 1 else 0));
        const a = try vm.take(count);
        const result: Value = switch (prim_of[row_index]) {
            .list_size => .{ .int = @intCast(a[0].list.len) },
            .list_push => blk: {
                const out = try vm.gpa.alloc(Value, a[0].list.len + 1);
                @memcpy(out[0..a[0].list.len], a[0].list);
                out[out.len - 1] = a[1];
                break :blk .{ .list = out };
            },
            .list_map => blk: {
                const out = try vm.gpa.alloc(Value, a[0].list.len);
                for (a[0].list, out) |x, *o| o.* = try vm.invoke(a[1].func, &.{x});
                break :blk .{ .list = out };
            },
            .list_filter => blk: {
                var out: std.ArrayList(Value) = .empty;
                for (a[0].list) |x| if ((try vm.invoke(a[1].func, &.{x})).bool) try out.append(vm.gpa, x);
                break :blk .{ .list = out.items };
            },
            .list_reduce => blk: {
                var acc = a[1];
                for (a[0].list) |x| acc = try vm.invoke(a[2].func, &.{ acc, x });
                break :blk acc;
            },
            .list_contains => .{ .bool = for (a[0].list) |x| {
                if (equal(x, a[1])) break true;
            } else false },
            .list_first => if (a[0].list.len == 0) try vm.variant("None", &.{}) else try vm.variant("Some", &.{a[0].list[0]}),
            .list_last => if (a[0].list.len == 0) try vm.variant("None", &.{}) else try vm.variant("Some", &.{a[0].list[a[0].list.len - 1]}),
            .string_size => .{ .int = graphemes(a[0].string) },
            .string_bytes => blk: {
                const out = try vm.gpa.alloc(Value, a[0].string.len);
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
            .time_fixture, .clock_now => .{ .time = fixture_time },
            .clock_fixture => .{ .cap = .{ .kind = .clock } },
            // A fixture Fs is empty; one built with delay: answers after the delay.
            .fs_read => if (a[0].cap.delay > a[2].duration)
                try vm.variant("Error", &.{try vm.variant("Timeout", &.{})})
            else
                try vm.variant("Error", &.{try vm.variant("Missing", &.{.{ .string = a[1].string }})}),
            .fs_narrow => a[0],
            .fs_fixture => .{ .cap = .{ .kind = .fs, .delay = if (row.named.len == 1) a[0].duration else 0 } },
            .events_emit => .none,
            .events_fixture => .{ .cap = .{ .kind = .events } },
            .ledger_fixture => .{ .cap = .{ .kind = .ledger } },
            .ledger_call => {
                vm.report = .{ .kind = .other, .clause = "the Ledger is simulated in step 4", .within = row.name, .at = 0 };
                return error.Skip;
            },
            .charge_fixture => blk: {
                const decl = vm.checked().findDecl("Charge").?;
                const fields = try vm.gpa.alloc(Value, 4);
                fields[0] = .{ .string = "ch_1" };
                fields[1] = if (row.named.len == 2) a[0] else .{ .time = fixture_time };
                fields[2] = a[row.named.len - 1];
                fields[3] = .{ .bool = false };
                break :blk .{ .record = .{ .decl = decl, .fields = fields } };
            },
            .charge_refunded => a[0].record.fields[3],
            .money_cents => a[0],
            .money_zero => .{ .int = 0 },
            .process => {
                vm.report = .{ .kind = .other, .clause = "processes run in step 4", .within = row.name, .at = 0 };
                return error.Skip;
            },
            .never_only => {
                vm.report = .{ .kind = .other, .clause = "this runs only inside a never, which tier 2 does not evaluate", .within = row.name, .at = 0 };
                return error.Crash;
            },
        };
        try vm.push(result);
    }

    fn variant(vm: *Vm, name: []const u8, fields: []const Value) Error!Value {
        return .{ .variant = .{ .name = name, .fields = try vm.gpa.dupe(Value, fields) } };
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
            .alias => return vm.generate(ty.b, depth),
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
            .time => |t| if (t == fixture_time) try w.writeAll("Time.fixture()") else try w.print("Time.fixture() + {d}.ms", .{t - fixture_time}),
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
            .func => try w.writeAll("a function"),
            .cap => |c| try w.print("{s}.fixture()", .{switch (c.kind) {
                .clock => "Clock",
                .fs => "Fs",
                .events => "Events",
                .ledger => "Ledger",
            }}),
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

fn fieldsOf(v: Value) []const Value {
    return switch (v) {
        .record => |r| r.fields,
        .variant => |r| r.fields,
        .tuple, .list => |elems| elems,
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
        .list, .tuple => |x| allEqual(x, if (b == .list) b.list else b.tuple),
        .record => |x| x.decl == b.record.decl and allEqual(x.fields, b.record.fields),
        .variant => |x| std.mem.eql(u8, x.name, b.variant.name) and allEqual(x.fields, b.variant.fields),
        .func => |x| x.function == b.func.function and allEqual(x.captures, b.func.captures),
        .cap => |x| x.kind == b.cap.kind and x.delay == b.cap.delay,
    };
}

fn allEqual(a: []const Value, b: []const Value) bool {
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
    const order: std.math.Order = switch (l) {
        .int => |a| std.math.order(a, r.int),
        .float => |a| std.math.order(a, r.float),
        .string => |a| std.mem.order(u8, a, r.string),
        .time => |a| std.math.order(a, r.time),
        .duration => |a| std.math.order(a, r.duration),
        else => unreachable,
    };
    return switch (op) {
        .lt => order == .lt,
        .le => order != .gt,
        .gt => order == .gt,
        else => order != .lt,
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

/// Graphemes, approximated as code points that are not combining marks: `café` is 4
/// however it is encoded. Full segmentation (emoji sequences) waits for the stdlib.
fn graphemes(s: []const u8) i128 {
    const view = std.unicode.Utf8View.init(s) catch return @intCast(s.len);
    var it = view.iterator();
    var n: i128 = 0;
    while (it.nextCodepoint()) |cp| {
        const combining = (cp >= 0x300 and cp <= 0x36F) or (cp >= 0x1AB0 and cp <= 0x1AFF) or (cp >= 0x1DC0 and cp <= 0x1DFF) or (cp >= 0x20D0 and cp <= 0x20FF) or (cp >= 0xFE20 and cp <= 0xFE2F);
        if (!combining) n += 1;
    }
    return n;
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
