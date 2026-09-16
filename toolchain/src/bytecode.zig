//! The instruction set of the interpreter and the lowering from the checked tree.
//! A stack machine: every expression pushes exactly one value, and every statement
//! leaves the stack as it found it. Locals are numbered slots per function. Each
//! arithmetic instruction carries its operands' integer kind, so the vm traps on
//! overflow in every build (design-v0/02).
const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const check = @import("check.zig");
const contracts = @import("contracts.zig");
const moves_mod = @import("moves.zig");
const prelude = @import("prelude.zig");
const types = @import("types.zig");

const Index = ast.Index;
const Node = ast.Node;
const Id = types.Id;

pub const Op = enum(u8) {
    /// push constants[a]
    constant,
    pop,
    /// exchange the two top values
    swap,
    /// push locals[a]
    load,
    /// push locals[a], giving up the claim on every buffer it holds alone (vm.owned): a read
    /// that shares the value rather than moving it (moves.zig), so the next write copies
    load_shared,
    /// the value on top stays; every buffer it holds alone may now be held twice (vm.disownIn)
    disown,
    /// pop into locals[a]
    store,
    /// continue at instruction a
    jump,
    /// pop a Bool; continue at a when it is false (true)
    jump_if_false,
    jump_if_true,
    /// pop r, then l; push l op r. a is the operands' Num, b the clause an overflow reports
    add,
    sub,
    mul,
    div,
    rem,
    /// a is the Num, b the clause
    negate,
    not,
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    /// pop a values; push them as a list (a tuple)
    list,
    tuple,
    /// pop b field values; push a struct of checked decl a
    record,
    /// pop b field values; push the variant named constants[a]
    variant,
    /// pop a struct, a variant, or a tuple; push its field a
    field,
    /// push field b of the struct, variant, or tuple in locals[a]
    load_field,
    /// pop v, then a struct, variant, or tuple; push it with field a set to v
    set_field,
    /// pop a value; push whether it is the variant named constants[a]
    is_variant,
    /// pop an index, then a list; push the element
    index,
    /// pop a list; push its size
    len,
    /// pop hi, then lo; push the list lo..hi, hi excluded
    range,
    /// pop a values; push their text joined
    concat,
    /// call functions[a] with the b values on top; push its result, then the final
    /// value of each inout parameter in order
    call,
    /// as call, for trait signature a, dispatched on the first argument's type
    call_trait,
    /// pop a arguments, then a function value; call it and push its result
    call_value,
    /// pop b captured values; push a function value for functions[a]
    closure,
    /// call prelude.fns[a] on the values on top; b is the receiver's integer kind, or `none`
    prim,
    /// pop the result and return it
    ret,
    /// pop a Bool; crash with clauses[a] when it is false
    check,
    /// pop r, then l; crash with clauses[a] unless `l op r` holds, where op is b as an Op
    check_compare,
    /// look at the value on top; crash with refinements[a]'s clause unless it holds
    refine,
    /// push a generated value of type a, logged under the name constants[b]
    generate,
    /// a property's guard is false: this attempt has no verdict
    discard,
    /// stop with clauses[a]: a crash, or a skip when the clause says so
    halt,
    /// pop b arguments; start processes[a] with the test runner as its supervisor; push its Handle
    spawn,
    /// pop b arguments; start supervisors[a] with its children; push the one child's
    /// Handle, a tuple of them in child order, or no value
    start_supervisor,
    /// pop a message, then a Handle; append the message to its mailbox; push no value
    send,
    /// pop a Duration, a message, then a Handle; the message goes in its mailbox no earlier than
    /// the Duration after the sending update ends (step 24); push no value
    send_later,
    /// pop the deadline, a message, then a Handle; push Ok(reply), Error(Timeout), or Error(Down)
    ask,
    /// push the running update's reply_by, the asker's deadline on the runtime's clock (step 22)
    reply_by,
    /// push the running update's reply_to, the asker it may keep instead of answering (step 31)
    reply_to,
    /// the arm being run keeps its asker: the update commits without answering the ask, and the
    /// process holds the Reply until it answers it, crashes, or restarts (step 31)
    defer_reply,
    /// pop a value, then a Reply; answer that ask with the value when the update commits, or
    /// drop it when its deadline has passed; push no value (step 31)
    answer,
    /// pop a Deadline; push the Duration that remains of it, or -1 ms when nothing remains
    deadline_left,
    /// deliver waiting messages, in start order, until every mailbox is empty
    settle,
    /// push the distinct values of recorded type a (Program.recorded_as) the run held, as
    /// a list (a never's `T.all`)
    all,
    /// the value on top stays; a test or property run keeps every value inside it, walked
    /// by checker type a, of a type some never reads with `T.all` (sim.zig, observe)
    observe,
    /// pop a Bool, then b values; crash with clauses[a], a never's, naming the values by
    /// its generators, when the Bool is true
    trip,
    /// push the zero value of type a; crash with clauses[b] when the type has none
    zero,
    /// a loop begins: store where the vm's region stands in locals[a], and 0 in locals[b]
    mark,
    /// a loop's safe point: when it has allocated enough since the mark in locals[a], keep
    /// what the frame's locals reach and free the rest; locals[b] holds what was kept
    collect,
};

/// The numbers an arithmetic instruction works in: a sized integer kind, a contract's
/// unbounded integers, or whatever the operands are (floats, times, durations).
pub const Num = enum(u8) { i8, i16, i32, i64, u8, u16, u32, u64, unbounded, other };

pub const Inst = struct { op: Op, a: u32 = 0, b: u32 = 0 };

pub const Const = union(enum) { none, int: i128, float: f64, string: []const u8, bool: bool };

pub const Clause = struct {
    kind: contracts.Kind,
    /// The source line of the clause or the operation, or a sentence for a skip.
    text: []const u8,
    /// Byte offset in the source.
    at: u32,
    /// The function, test, or type it belongs to.
    within: []const u8,
    /// Halting here skips the test instead of failing it.
    skip: bool = false,
};

pub const Function = struct {
    name: []const u8,
    param_names: []const []const u8,
    locals: u32,
    /// The slot that holds the result, which `ensures` reads.
    result: u32,
    code: []const Inst,
    /// Slots of the inout parameters, in order; their values follow the result on return.
    inouts: []const u32,
    /// Slots a closure's captured values are copied into, in order.
    captures: []const u32,
    /// Some parameter or expression of it can hold a process's handle, so a sweep reads its
    /// frame's locals (sim.zig, sweep).
    scans_handles: bool = false,
};

pub const Refinement = struct { function: u32, clause: u32, bounds: Bounds = .{} };

pub const Range = struct { lo: i128, hi: i128 };

/// The integer bounds a `where` states, each side null when it states none: every conjunct
/// `value <op> literal` or `literal <op> value` (op one of == < <= > >=) narrows them, and
/// any other conjunct, an `or` included, narrows nothing. `any(T)` generates between them
/// when few of its base type's values pass (contracts.refined_base_candidates).
pub const Bounds = struct {
    lo: ?i128 = null,
    hi: ?i128 = null,

    pub fn of(tree: *const ast.Tree, cond: Index) Bounds {
        var b: Bounds = .{};
        b.narrow(tree, cond);
        return b;
    }

    /// The bounds clamped to an integer kind's, or null when they state none or no integer
    /// of the kind is between them.
    pub fn within(b: Bounds, kind: types.IntKind) ?Range {
        if (b.lo == null and b.hi == null) return null;
        const bits: u7 = switch (kind) {
            .i8, .u8 => 8,
            .i16, .u16 => 16,
            .i32, .u32 => 32,
            .i64, .u64 => 64,
        };
        const signed = @intFromEnum(kind) <= @intFromEnum(types.IntKind.i64);
        const min: i128 = if (signed) -(@as(i128, 1) << (bits - 1)) else 0;
        const max: i128 = (@as(i128, 1) << (if (signed) bits - 1 else bits)) - 1;
        const lo = @max(b.lo orelse min, min);
        const hi = @min(b.hi orelse max, max);
        return if (lo <= hi) .{ .lo = lo, .hi = hi } else null;
    }

    /// Both bounds at once: the higher low and the lower high.
    pub fn meet(b: *Bounds, other: Bounds) void {
        if (other.lo) |v| b.lo = if (b.lo) |w| @max(v, w) else v;
        if (other.hi) |v| b.hi = if (b.hi) |w| @min(v, w) else v;
    }

    fn narrow(b: *Bounds, tree: *const ast.Tree, cond: Index) void {
        const n = tree.nodes[cond];
        switch (n.kind) {
            .and_expr => {
                b.narrow(tree, n.lhs);
                b.narrow(tree, n.rhs);
            },
            .compare => {
                const op = tree.tokenText(n.main_token);
                if (isValue(tree, n.lhs)) {
                    if (intOf(tree, n.rhs)) |v| b.bound(op, v);
                } else if (isValue(tree, n.rhs)) {
                    if (intOf(tree, n.lhs)) |v| b.bound(flipped(op), v);
                }
            },
            else => {},
        }
    }

    fn bound(b: *Bounds, op: []const u8, v: i128) void {
        const lo: ?i128, const hi: ?i128 = if (std.mem.eql(u8, op, "=="))
            .{ v, v }
        else if (std.mem.eql(u8, op, "<"))
            .{ null, v -| 1 }
        else if (std.mem.eql(u8, op, "<="))
            .{ null, v }
        else if (std.mem.eql(u8, op, ">"))
            .{ v +| 1, null }
        else if (std.mem.eql(u8, op, ">="))
            .{ v, null }
        else
            .{ null, null };
        b.meet(.{ .lo = lo, .hi = hi });
    }

    fn flipped(op: []const u8) []const u8 {
        if (std.mem.eql(u8, op, "<")) return ">";
        if (std.mem.eql(u8, op, "<=")) return ">=";
        if (std.mem.eql(u8, op, ">")) return "<";
        if (std.mem.eql(u8, op, ">=")) return "<=";
        return op;
    }

    fn isValue(tree: *const ast.Tree, i: Index) bool {
        const n = tree.nodes[i];
        return n.kind == .name_ref and std.mem.eql(u8, tree.tokenText(n.main_token), "value");
    }

    fn intOf(tree: *const ast.Tree, i: Index) ?i128 {
        const n = tree.nodes[i];
        return switch (n.kind) {
            .int_lit => Lower.parseInt(tree.tokenText(n.main_token)),
            .negate => if (tree.nodes[n.lhs].kind == .int_lit) -Lower.parseInt(tree.tokenText(tree.nodes[n.lhs].main_token)) else null,
            else => null,
        };
    }
};

test "a where's bounds are its comparisons of value with a literal" {
    const parser = @import("parser.zig");
    const diag = @import("diag.zig");
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cases = [_]struct { src: []const u8, lo: ?i128, hi: ?i128 }{
        .{ .src = "value <= 100", .lo = null, .hi = 100 },
        .{ .src = "value >= 100 and value <= 599", .lo = 100, .hi = 599 },
        .{ .src = "0 < value and value < 10 and value.even?", .lo = 1, .hi = 9 },
        .{ .src = "value > -5 and value != 3", .lo = -4, .hi = null },
        .{ .src = "value <= 9 or value >= 90", .lo = null, .hi = null },
    };
    for (cases) |c| {
        var diags: diag.List = .empty;
        const src = try std.fmt.allocPrint(arena, "module M\ntype T = Int32 where {s}\n", .{c.src});
        const tokens = try lexer.lex(arena, src, &diags);
        const tree = try parser.parse(arena, src, tokens, &diags);
        const refined = for (tree.nodes, 0..) |n, i| {
            if (n.kind == .type_refined) break i;
        } else unreachable;
        const b = Bounds.of(&tree, tree.nodes[refined].rhs);
        try std.testing.expectEqual(c.lo, b.lo);
        try std.testing.expectEqual(c.hi, b.hi);
    }
}

pub const TestKind = enum { test_, rejects, property };

pub const Restart = enum { always, on_crash, never };

pub const Invariant = struct { function: u32, clause: u32 };

/// A process: `init` takes its parameters and gives the first state; `update` takes the
/// parameters, the state, and a message, and gives `(reply, state)`; each invariant takes
/// the parameters, the state after, and the state before, and is true when broken.
pub const Process = struct {
    name: []const u8,
    decl: u32,
    mailbox: u32,
    init: u32,
    update: u32,
    invariants: []const Invariant,
    /// An invariant reads old(state), so an update never overwrites the state before it in
    /// place (sim.zig).
    reads_old: bool = false,
    /// Its update reads reply_by, so under faults an ask to it may arrive with nothing left.
    reads_reply_by: bool = false,
    /// An arm of its update keeps its asker (step 31), so the runtimes bind reply_to.
    reads_reply_to: bool = false,
};

/// A `child` line: `args` takes the supervisor's parameters and gives the child's
/// arguments as a tuple; `per` takes nothing and gives the window, or is `none`.
pub const Child = struct {
    process: u32,
    args: u32,
    restart: Restart,
    /// `none` when the line names no max_restarts.
    max_restarts: u32,
    per: u32,
};

pub const Supervisor = struct { name: []const u8, decl: u32, children: []const Child };

pub const Test = struct { kind: TestKind, name: []const u8, function: u32, at: u32 };

/// A `never`: `function` takes nothing, walks its generators over what a test or property
/// run held, and trips `clause` naming each generated value by `names`.
pub const Never = struct { function: u32, clause: u32, names: []const []const u8 };

pub const Program = struct {
    checked: check.Checked,
    functions: []const Function,
    constants: []const Const,
    clauses: []const Clause,
    refinements: []const Refinement,
    tests: []const Test,
    /// Checked signature index → function index, or `none` (a trait's signatures).
    fn_of_sig: []const u32,
    /// Checked decl index → the refinements a value of that alias satisfies.
    alias_refinements: []const []const u32,
    processes: []const Process = &.{},
    supervisors: []const Supervisor = &.{},
    nevers: []const Never = &.{},
    /// Checker type id → its index among the types some never reads with `T.all`, whose
    /// values each test and property run keeps, or `none`.
    recorded_as: []const u32 = &.{},
    /// Checker type id → whether a value of it can hold a value of a recorded type.
    may_hold: []const bool = &.{},

    pub fn findFunction(p: *const Program, name: []const u8) ?u32 {
        for (p.checked.sigs, 0..) |s, si| {
            if (std.mem.eql(u8, s.name, name) and p.fn_of_sig[si] != none) return p.fn_of_sig[si];
        }
        return null;
    }
};

pub const none: u32 = std.math.maxInt(u32);

/// A `prim`'s b in `m = m.set(k, v)` on a var map or set: the receiver was read without
/// giving up the var's claim, so the row may write into a buffer the var owns.
pub const unique: u32 = none - 1;

pub const Error = error{OutOfMemory};

pub fn lower(gpa: std.mem.Allocator, checked: check.Checked) Error!Program {
    var l: Lower = .{ .gpa = gpa, .k = &checked, .tree = checked.tree };
    l.moves = try moves_mod.analyze(gpa, &checked);
    l.unrested = try unrestedWrites(gpa, checked.tree);
    l.fn_of_sig = try gpa.alloc(u32, checked.sigs.len);
    @memset(l.fn_of_sig, none);
    for (checked.sigs, 0..) |s, si| {
        if (s.kind != .trait) l.fn_of_sig[si] = try l.reserve();
    }
    const alias_refinements = try gpa.alloc([]const u32, checked.decls.len);
    for (checked.decls, alias_refinements) |d, *refs| {
        refs.* = if (d.kind == .alias and d.node != 0) try l.refinementsOf(l.node(d.node).lhs, d.name) else &.{};
    }
    l.process_of = try gpa.alloc(u32, checked.decls.len);
    @memset(l.process_of, none);
    for (checked.decls, 0..) |d, di| if (d.kind == .process) {
        l.process_of[di] = @intCast(l.processes.items.len);
        try l.processes.append(gpa, undefined);
    };
    l.supervisor_of = try gpa.alloc(u32, checked.decls.len);
    @memset(l.supervisor_of, none);
    for (checked.decls, 0..) |d, di| if (d.kind == .supervisor) {
        l.supervisor_of[di] = @intCast(l.supervisors.items.len);
        try l.supervisors.append(gpa, undefined);
    };
    const recorded = try recordedTypes(gpa, &checked);
    l.recorded_as = recorded.recorded_as;
    l.may_hold = recorded.may_hold;
    for (checked.sigs, 0..) |s, si| if (s.kind != .trait) try l.lowerFn(@intCast(si));
    for (l.items()) |it| {
        const n = l.node(it);
        switch (n.kind) {
            .process_decl => try l.lowerProcess(it),
            .supervisor_decl => try l.lowerSupervisor(it),
            .never => try l.lowerNever(it),
            else => {},
        }
    }
    for (l.items()) |it| {
        const n = l.node(it);
        switch (n.kind) {
            .test_decl, .test_rejects, .property => try l.lowerTest(it),
            .recipe_decl => {
                const r = l.tree.extraData(ast.Recipe, n.lhs);
                for (l.tree.span(r.tests_start, r.tests_end)) |t| try l.lowerTest(t);
            },
            else => {},
        }
    }
    return .{
        .checked = checked,
        .functions = l.functions.items,
        .constants = l.constants.items,
        .clauses = l.clauses.items,
        .refinements = l.refinements.items,
        .tests = l.tests.items,
        .fn_of_sig = l.fn_of_sig,
        .alias_refinements = alias_refinements,
        .processes = l.processes.items,
        .supervisors = l.supervisors.items,
        .nevers = l.nevers.items,
        .recorded_as = l.recorded_as,
        .may_hold = l.may_hold,
    };
}

/// What `T.all` keeps values of, told apart: a struct, an enum, an alias, or a primitive
/// value type; null for any other type, which MO0324 refuses.
fn recordKey(k: *const check.Checked, id: Id) ?u64 {
    const t = k.pool.get(k.pool.resolve(id));
    const key = (@as(u64, @intFromEnum(t.tag)) << 32) | t.a;
    return switch (t.tag) {
        .bool, .string, .time, .duration, .int, .float, .alias => key,
        .decl => switch (k.decls[t.a].kind) {
            .struct_, .enum_, .prelude_enum => key,
            else => null,
        },
        else => null,
    };
}

/// The field writes that record nothing for a never's `T.all`, since the struct is not at rest after
/// them (step 27; step 28 looks through branches): a write of a field under a place whose next
/// write, the first statement control reaches after it, assigns the same root name again. That is
/// the next statement of its body; past the end of a branch, the statement after its `if` or
/// `case`; and when the next statement is an `if` or a `case`, the first write of every branch,
/// an `if` without `else` going on to the statement after it. A condition, subject, or guard on
/// the line that names the root keeps the write at rest, since a call there could hold the struct.
/// The last write of the run records the whole struct. The C backend (emit_c.zig) reads the same set.
pub fn unrestedWrites(gpa: std.mem.Allocator, tree: ast.Tree) Error!std.AutoHashMapUnmanaged(Index, void) {
    var out: std.AutoHashMapUnmanaged(Index, void) = .empty;
    for (tree.nodes) |n| {
        switch (n.kind) {
            .fn_decl => {
                const body = tree.extraData(ast.FnBody, n.rhs);
                try unrestIn(gpa, tree, tree.span(body.start, body.end), null, &out);
            },
            .test_decl, .test_rejects => try unrestIn(gpa, tree, tree.span(n.lhs, n.rhs), null, &out),
            .for_stmt => try unrestIn(gpa, tree, spanOf(tree, n.rhs), null, &out),
            .anon_fn => {
                const data = tree.extraData(ast.AnonFn, n.lhs);
                try unrestIn(gpa, tree, tree.span(data.body_start, data.body_end), null, &out);
            },
            .comprehension => {
                const data = tree.extraData(ast.Comprehension, n.lhs);
                try unrestIn(gpa, tree, tree.span(data.body_start, data.body_end), null, &out);
            },
            .if_expr => {
                const data = tree.extraData(ast.If, n.rhs);
                try unrestIn(gpa, tree, tree.span(data.then_start, data.then_end), null, &out);
                try unrestIn(gpa, tree, tree.span(data.else_start, data.else_end), null, &out);
            },
            .case_expr => for (spanOf(tree, n.rhs)) |a| {
                const data = tree.extraData(ast.Arm, tree.nodes[a].rhs);
                try unrestIn(gpa, tree, tree.span(data.body_start, data.body_end), null, &out);
            },
            .process_decl => {
                const data = tree.extraData(ast.Process, n.lhs);
                if (data.update != 0) try unrestIn(gpa, tree, &.{tree.nodes[data.update].lhs}, null, &out);
            },
            else => {},
        }
    }
    return out;
}

/// Where control goes once a branch's statements are done: statement `at` of `stmts`, then on up.
const After = struct { stmts: []const u32, at: usize, up: ?*const After };

fn spanOf(tree: ast.Tree, extra_index: u32) []const u32 {
    if (extra_index == 0) return &.{};
    const s = tree.extraData(ast.Span, extra_index);
    return tree.span(s.start, s.end);
}

fn unrestIn(gpa: std.mem.Allocator, tree: ast.Tree, stmts: []const u32, after: ?*const After, out: *std.AutoHashMapUnmanaged(Index, void)) Error!void {
    for (stmts, 0..) |s, k| {
        const n = tree.nodes[s];
        const next: After = .{ .stmts = stmts, .at = k + 1, .up = after };
        switch (n.kind) {
            .assign => if (tree.nodes[n.lhs].kind == .member and writesNext(tree, &next, placeRoot(tree, n.lhs))) try out.put(gpa, s, {}),
            .if_stmt => {
                const data = tree.extraData(ast.If, n.rhs);
                try unrestIn(gpa, tree, tree.span(data.then_start, data.then_end), &next, out);
                try unrestIn(gpa, tree, tree.span(data.else_start, data.else_end), &next, out);
            },
            .case_stmt => for (spanOf(tree, n.rhs)) |a| {
                const data = tree.extraData(ast.Arm, tree.nodes[a].rhs);
                try unrestIn(gpa, tree, tree.span(data.body_start, data.body_end), &next, out);
            },
            else => {},
        }
    }
}

/// Whether the first statement control reaches from `from` assigns `root` again.
fn writesNext(tree: ast.Tree, from: *const After, root: []const u8) bool {
    if (from.at == from.stmts.len) return if (from.up) |up| writesNext(tree, up, root) else false;
    const s = from.stmts[from.at];
    const n = tree.nodes[s];
    const past: After = .{ .stmts = from.stmts, .at = from.at + 1, .up = from.up };
    switch (n.kind) {
        .assign => return std.mem.eql(u8, placeRoot(tree, n.lhs), root),
        .if_stmt => {
            if (lineNames(tree, n.main_token, root)) return false;
            const data = tree.extraData(ast.If, n.rhs);
            const then: After = .{ .stmts = tree.span(data.then_start, data.then_end), .at = 0, .up = &past };
            const otherwise: After = .{ .stmts = tree.span(data.else_start, data.else_end), .at = 0, .up = &past };
            return writesNext(tree, &then, root) and writesNext(tree, &otherwise, root);
        },
        .case_stmt => {
            if (lineNames(tree, n.main_token, root)) return false;
            const arms = spanOf(tree, n.rhs);
            for (arms) |a| {
                const data = tree.extraData(ast.Arm, tree.nodes[a].rhs);
                if (data.guard != 0 and lineNames(tree, tree.nodes[tree.nodes[a].lhs].main_token, root)) return false;
                const body: After = .{ .stmts = tree.span(data.body_start, data.body_end), .at = 0, .up = &past };
                if (!writesNext(tree, &body, root)) return false;
            }
            return arms.len > 0;
        },
        else => return false,
    }
}

/// Whether `root` is a name on the rest of the line from token `from`.
fn lineNames(tree: ast.Tree, from: u32, root: []const u8) bool {
    var k = from;
    while (k < tree.tokens.len and tree.tokens[k].kind != .newline and tree.tokens[k].kind != .eof) : (k += 1) {
        if (tree.tokens[k].kind == .ident and std.mem.eql(u8, tree.tokenText(k), root)) return true;
    }
    return false;
}

/// The name a place such as `copy.item.count` roots at.
fn placeRoot(tree: ast.Tree, place: Index) []const u8 {
    var at = place;
    while (tree.nodes[at].kind == .member) at = tree.nodes[at].lhs;
    return tree.tokenText(tree.nodes[at].main_token);
}

/// The map and set rows that may write into a buffer their receiver holds alone.
pub fn writesInPlace(row: prelude.Fn) bool {
    const map_row = std.mem.startsWith(u8, row.recv, "Map(") and (std.mem.eql(u8, row.name, "set") or std.mem.eql(u8, row.name, "update") or std.mem.eql(u8, row.name, "remove"));
    const set_row = std.mem.startsWith(u8, row.recv, "Set(") and (std.mem.eql(u8, row.name, "add") or std.mem.eql(u8, row.name, "remove"));
    return map_row or set_row;
}

/// Whether positional argument `position` of a row is an accumulator the row hands back
/// to its function and returns (`reduce`'s start, `fold_lines`'s), which keeps its claim.
pub fn accumulates(row: prelude.Fn, position: usize) bool {
    if (std.mem.startsWith(u8, row.recv, "List(") and std.mem.eql(u8, row.name, "reduce")) return position == 0;
    if (std.mem.eql(u8, row.recv, "Fs") and std.mem.eql(u8, row.name, "fold_lines")) return position == 1;
    return false;
}

/// What each test and property run keeps for a never's `T.all` (sim.zig, observe), by checker
/// type id: its index among the types some never reads with `T.all`, or `none`, and whether a
/// value of it can hold a value of one. The interpreter's lowering and the C backend
/// (emit_c.zig) both read it.
pub const Recorded = struct { recorded_as: []u32, may_hold: []bool };

/// Every `T.all` in the program names a type whose values each test and property run keeps;
/// then every type that can hold one of those, so its values are observed.
pub fn recordedTypes(gpa: std.mem.Allocator, k: *const check.Checked) Error!Recorded {
    const pool = &k.pool;
    const n = pool.list.items.len;
    const recorded_as = try gpa.alloc(u32, n);
    @memset(recorded_as, none);
    const may_hold = try gpa.alloc(bool, n);
    @memset(may_hold, false);
    var keys: std.ArrayList(u64) = .empty;
    for (k.callee, 0..) |callee, i| {
        if (callee != .prelude) continue;
        const row = prelude.fns[callee.prelude];
        if (row.only != .never or !std.mem.eql(u8, row.name, "all")) continue;
        const list = pool.get(k.typeOf(@intCast(i)));
        if (list.tag != .list) continue;
        const key = recordKey(k, list.a) orelse continue;
        if (std.mem.indexOfScalar(u64, keys.items, key) == null) try keys.append(gpa, key);
    }
    if (keys.items.len == 0) return .{ .recorded_as = recorded_as, .may_hold = may_hold };
    for (0..n) |id| {
        const key = recordKey(k, @intCast(id)) orelse continue;
        if (std.mem.indexOfScalar(u64, keys.items, key)) |x| recorded_as[id] = @intCast(x);
    }
    // A type holds a recorded one when a part of it does; recursive types settle.
    var changed = true;
    while (changed) {
        changed = false;
        for (0..n) |id| {
            if (may_hold[id] or (recorded_as[id] == none and !partHolds(k, may_hold, @intCast(id)))) continue;
            may_hold[id] = true;
            changed = true;
        }
    }
    return .{ .recorded_as = recorded_as, .may_hold = may_hold };
}

fn partHolds(k: *const check.Checked, h: []const bool, id: Id) bool {
    const r = k.pool.resolve(id);
    if (r != id) return h[r];
    const t = k.pool.get(r);
    return switch (t.tag) {
        .alias => h[t.b],
        .list, .option, .set => h[t.a],
        .result, .map => h[t.a] or h[t.b],
        .tuple => for (k.pool.elems(t)) |e| {
            if (h[e]) break true;
        } else false,
        .decl, .state, .message => blk: {
            const d = k.decls[t.a];
            for (k.fields[d.fields.start..d.fields.end]) |f| if (h[f.type]) break :blk true;
            for (k.variants[d.variants.start..d.variants.end]) |v| {
                for (k.fields[v.fields.start..v.fields.end]) |f| if (h[f.type]) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

const Name = struct { name: []const u8, slot: u32, mutable: bool };

const Capture = struct { name: []const u8, outer: u32, inner: u32 };

/// One function being lowered.
const Builder = struct {
    parent: ?*Builder = null,
    name: []const u8,
    code: std.ArrayList(Inst) = .empty,
    locals: u32 = 0,
    names: std.ArrayList(Name) = .empty,
    captures: std.ArrayList(Capture) = .empty,
    param_names: std.ArrayList([]const u8) = .empty,
    inouts: std.ArrayList(u32) = .empty,
    /// Jumps to the function's exit, patched when the body is done.
    exits: std.ArrayList(u32) = .empty,
    /// For each open loop, where its breaks start in `breaks`.
    loops: std.ArrayList(u32) = .empty,
    breaks: std.ArrayList(u32) = .empty,
    result: u32 = 0,
    /// Lowering a contract expression: integer arithmetic is unbounded.
    contract: bool = false,
    /// Inside an invariant: the slot of the state before the message, which `old` reads.
    old_state: u32 = none,
    /// A parameter or an expression can hold a handle (Function.scans_handles).
    handles: bool = false,
};

const Lower = struct {
    gpa: std.mem.Allocator,
    k: *const check.Checked,
    tree: ast.Tree,
    /// The field writes that record nothing, since the next write reached assigns the same place
    /// (unrestedWrites; steps 27, 28).
    unrested: std.AutoHashMapUnmanaged(Index, void) = .empty,
    functions: std.ArrayList(Function) = .empty,
    constants: std.ArrayList(Const) = .empty,
    clauses: std.ArrayList(Clause) = .empty,
    refinements: std.ArrayList(Refinement) = .empty,
    tests: std.ArrayList(Test) = .empty,
    processes: std.ArrayList(Process) = .empty,
    supervisors: std.ArrayList(Supervisor) = .empty,
    nevers: std.ArrayList(Never) = .empty,
    recorded_as: []u32 = &.{},
    may_hold: []bool = &.{},
    /// Checked decl index → index in `processes`, or `none`.
    process_of: []u32 = &.{},
    /// Checked decl index → index in `supervisors`, or `none`.
    supervisor_of: []u32 = &.{},
    fn_of_sig: []u32 = &.{},
    /// A `where` node → its index in `refinements`, lowered once.
    refinement_of: std.AutoHashMapUnmanaged(Index, u32) = .empty,
    /// An `old(...)` node → the slot its operand was stored in on entry.
    old_slots: std.AutoHashMapUnmanaged(Index, u32) = .empty,
    b: *Builder = undefined,
    /// While `m = m.set(k, v)` or `s.f = s.f.set(k, v)` is lowered: its call node, the name
    /// it assigns, and for an assignment the place on its left.
    in_place: struct { call: Index = 0, name: []const u8 = "", path: Index = 0 } = .{},
    /// Which reads hand their value on (moves.zig, step 28).
    moves: moves_mod.Moves = .{},

    // ---- small helpers

    fn node(l: *Lower, i: Index) Node {
        return l.tree.nodes[i];
    }

    fn text(l: *Lower, tok: u32) []const u8 {
        return l.tree.tokenText(tok);
    }

    fn items(l: *Lower) []const u32 {
        return l.tree.span(l.tree.nodes[0].lhs, l.tree.nodes[0].rhs);
    }

    fn spanAt(l: *Lower, extra_index: u32) []const u32 {
        if (extra_index == 0) return &.{};
        const s = l.tree.extraData(ast.Span, extra_index);
        return l.tree.span(s.start, s.end);
    }

    fn typeOf(l: *Lower, i: Index) Id {
        return l.k.typeOf(i);
    }

    fn baseType(l: *Lower, t: Id) types.Type {
        return l.k.pool.get(l.k.pool.base(t));
    }

    /// A value of type `t` is held in the function being lowered.
    fn holds(l: *Lower, t: Id) void {
        if (!l.b.handles and check.handleIn(&l.k.pool, t, 0)) l.b.handles = true;
    }

    fn numOf(l: *Lower, t: Id) Num {
        const b = l.baseType(t);
        if (b.tag != .int) return .other;
        if (l.b.contract) return .unbounded;
        return @enumFromInt(b.a);
    }

    fn intKind(l: *Lower, t: Id) u32 {
        const b = l.baseType(t);
        return if (b.tag == .int) b.a else none;
    }

    /// The value on top, of type `t`, is held where a run can see it: in a binding, a
    /// field, a message, or state. A type that cannot hold a recorded value emits nothing.
    fn observe(l: *Lower, t: Id) Error!void {
        const r = l.k.pool.resolve(t);
        if (l.may_hold[r]) _ = try l.emit(.observe, r, 0);
    }

    /// Whether a value of type `t` can hold a buffer one holder holds alone (moves.zig).
    fn owns(l: *Lower, t: Id) bool {
        return l.moves.owns(l.k, t);
    }

    /// Whether the read at `i` hands its value on (moves.zig); never inside a contract, which
    /// reads what the function goes on to use.
    fn moving(l: *Lower, i: Index) bool {
        return !l.b.contract and l.moves.has(i);
    }

    /// The value on top, of type `t`, may now be held twice: a row or a list keeps it.
    fn share(l: *Lower, t: Id) Error!void {
        if (l.owns(t)) _ = try l.emit(.disown, 0, 0);
    }

    /// A parameter in locals[at], of type `t`, holds its argument.
    fn observeLocal(l: *Lower, at: u32, t: Id) Error!void {
        if (!l.may_hold[l.k.pool.resolve(t)]) return;
        _ = try l.emit(.load, at, 0);
        try l.observe(t);
        _ = try l.emit(.pop, 0, 0);
    }

    fn firstToken(l: *Lower, i: Index) u32 {
        var cur = i;
        while (true) {
            const n = l.node(cur);
            switch (n.kind) {
                .implies, .or_expr, .and_expr, .compare, .is_expr, .range, .add, .mul, .member, .member_call, .tuple_index, .call, .assign => cur = n.lhs,
                else => return n.main_token,
            }
        }
    }

    fn emit(l: *Lower, op: Op, a: u32, b: u32) Error!u32 {
        const at: u32 = @intCast(l.b.code.items.len);
        try l.b.code.append(l.gpa, .{ .op = op, .a = a, .b = b });
        return at;
    }

    fn here(l: *Lower) u32 {
        return @intCast(l.b.code.items.len);
    }

    fn patch(l: *Lower, at: u32) void {
        l.b.code.items[at].a = l.here();
    }

    fn slot(l: *Lower) u32 {
        const s = l.b.locals;
        l.b.locals += 1;
        return s;
    }

    fn bindName(l: *Lower, name: []const u8, mutable: bool) Error!u32 {
        const s = l.slot();
        try l.b.names.append(l.gpa, .{ .name = name, .slot = s, .mutable = mutable });
        return s;
    }

    fn constant(l: *Lower, c: Const) Error!u32 {
        const at: u32 = @intCast(l.constants.items.len);
        try l.constants.append(l.gpa, c);
        return at;
    }

    fn pushConst(l: *Lower, c: Const) Error!void {
        _ = try l.emit(.constant, try l.constant(c), 0);
    }

    /// The source line from `tok` to its end: the clause a report quotes.
    fn lineFrom(l: *Lower, tok: u32) []const u8 {
        const src = l.tree.source;
        const start = l.tree.tokens[tok].start;
        const end = std.mem.indexOfScalarPos(u8, src, start, '\n') orelse src.len;
        return std.mem.trimEnd(u8, src[start..end], " \t\r");
    }

    fn clause(l: *Lower, kind: contracts.Kind, tok: u32) Error!u32 {
        const at: u32 = @intCast(l.clauses.items.len);
        try l.clauses.append(l.gpa, .{ .kind = kind, .text = l.lineFrom(tok), .at = l.tree.tokens[tok].start, .within = l.b.name });
        return at;
    }

    /// Stops the run here: a skip with a sentence, or a crash quoting the line.
    fn halt(l: *Lower, i: Index, sentence: []const u8, skip: bool) Error!void {
        const tok = l.firstToken(i);
        const at: u32 = @intCast(l.clauses.items.len);
        try l.clauses.append(l.gpa, .{ .kind = .other, .text = if (sentence.len > 0) sentence else l.lineFrom(tok), .at = l.tree.tokens[tok].start, .within = l.b.name, .skip = skip });
        _ = try l.emit(.halt, at, 0);
    }

    fn reserve(l: *Lower) Error!u32 {
        const at: u32 = @intCast(l.functions.items.len);
        try l.functions.append(l.gpa, undefined);
        return at;
    }

    fn finish(l: *Lower, b: *Builder) Error!Function {
        const captures = try l.gpa.alloc(u32, b.captures.items.len);
        for (b.captures.items, captures) |c, *s| s.* = c.inner;
        return .{
            .name = b.name,
            .param_names = b.param_names.items,
            .locals = b.locals,
            .result = b.result,
            .code = b.code.items,
            .inouts = b.inouts.items,
            .captures = captures,
            .scans_handles = b.handles,
        };
    }

    // ---- names

    /// A name in the function being lowered, captured from the enclosing ones when an
    /// anonymous function reads it.
    fn resolveIn(l: *Lower, b: *Builder, name: []const u8) Error!?Name {
        var i = b.names.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, b.names.items[i].name, name)) return b.names.items[i];
        }
        for (b.captures.items) |c| if (std.mem.eql(u8, c.name, name)) return .{ .name = name, .slot = c.inner, .mutable = false };
        const parent = b.parent orelse return null;
        const outer = try l.resolveIn(parent, name) orelse return null;
        const inner = b.locals;
        b.locals += 1;
        try b.captures.append(l.gpa, .{ .name = name, .outer = outer.slot, .inner = inner });
        return .{ .name = name, .slot = inner, .mutable = false };
    }

    fn resolve(l: *Lower, name: []const u8) Error!?Name {
        return l.resolveIn(l.b, name);
    }

    fn localVar(l: *Lower, name: []const u8) ?Name {
        var i = l.b.names.items.len;
        while (i > 0) {
            i -= 1;
            const n = l.b.names.items[i];
            if (std.mem.eql(u8, n.name, name)) return if (n.mutable) n else null;
        }
        return null;
    }

    // ---- functions and tests

    fn lowerFn(l: *Lower, si: u32) Error!void {
        const s = l.k.sigs[si];
        const n = l.node(s.node);
        const sig = l.tree.extraData(ast.Signature, n.lhs);
        var b: Builder = .{ .name = s.name };
        l.b = &b;
        const params = l.k.params[s.params.start..s.params.end];
        for (params) |p| {
            const at = try l.bindName(p.name, p.inout);
            l.holds(p.type);
            try b.param_names.append(l.gpa, p.name);
            if (p.inout) try b.inouts.append(l.gpa, at);
        }
        b.result = l.slot();
        for (params, 0..) |p, k| try l.observeLocal(@intCast(k), p.type);

        // On entry: each argument crosses into its parameter's refinement, then requires,
        // then every old(...) operand is kept for ensures.
        for (params, 0..) |p, k| {
            const refs = try l.refinementsOf(l.node(p.node).lhs, s.name);
            if (refs.len == 0) continue;
            _ = try l.emit(.load, @intCast(k), 0);
            for (refs) |r| _ = try l.emit(.refine, r, 0);
            _ = try l.emit(.pop, 0, 0);
        }
        const contract_nodes = l.tree.span(sig.contracts_start, sig.contracts_end);
        for (contract_nodes) |c| if (l.node(c).kind == .requires) try l.contract(c, .requires);
        for (contract_nodes) |c| if (l.node(c).kind == .ensures) {
            var olds: std.ArrayList(Index) = .empty;
            try l.collectOld(l.node(c).lhs, &olds);
            for (olds.items) |o| {
                b.contract = true;
                try l.expr(l.node(o).lhs);
                b.contract = false;
                const at = l.slot();
                _ = try l.emit(.store, at, 0);
                try l.old_slots.put(l.gpa, o, at);
            }
        };

        if (n.kind == .fn_decl and l.processes.items.len > 0 and l.k.mainSig() == si) {
            // main is the root supervisor: its sends are delivered before its next
            // statement runs, as a test's are (Mo.Server runs Mo.Sim's scheduler).
            const body = l.tree.extraData(ast.FnBody, n.rhs);
            const mark = b.names.items.len;
            for (l.tree.span(body.start, body.end)) |st| {
                try l.stmt(st);
                _ = try l.emit(.settle, 0, 0);
            }
            b.names.shrinkRetainingCapacity(mark);
            try l.pushConst(.none);
            _ = try l.emit(.store, b.result, 0);
        } else if (n.kind == .fn_decl) {
            const body = l.tree.extraData(ast.FnBody, n.rhs);
            try l.blockValue(l.tree.span(body.start, body.end));
            _ = try l.emit(.store, b.result, 0);
        } else {
            try l.halt(s.node, try std.fmt.allocPrint(l.gpa, "{s} is a recipe signature with no body until an agent implements the recipe", .{s.name}), true);
        }
        for (b.exits.items) |e| l.patch(e);

        // On exit, from every return: the result crosses into the return type's
        // refinement, then ensures.
        const ret_refs = try l.refinementsOf(sig.ret, s.name);
        if (ret_refs.len > 0) {
            _ = try l.emit(.load, b.result, 0);
            for (ret_refs) |r| _ = try l.emit(.refine, r, 0);
            _ = try l.emit(.pop, 0, 0);
        }
        for (contract_nodes) |c| if (l.node(c).kind == .ensures) try l.contract(c, .ensures);
        _ = try l.emit(.load, b.result, 0);
        _ = try l.emit(.ret, 0, 0);
        l.functions.items[l.fn_of_sig[si]] = try l.finish(&b);
    }

    /// A requires or ensures: its expression in unbounded integers, then a check that
    /// crashes naming the clause.
    fn contract(l: *Lower, c: Index, kind: contracts.Kind) Error!void {
        const n = l.node(c);
        const mark = l.b.names.items.len;
        l.b.contract = true;
        try l.expr(n.lhs);
        l.b.contract = false;
        _ = try l.emit(.check, try l.clause(kind, n.main_token), 0);
        l.b.names.shrinkRetainingCapacity(mark);
    }

    /// Every old(...) inside a contract expression.
    fn collectOld(l: *Lower, i: Index, out: *std.ArrayList(Index)) Error!void {
        if (i == 0) return;
        const n = l.node(i);
        switch (n.kind) {
            .old_expr => try out.append(l.gpa, i),
            .implies, .or_expr, .and_expr, .compare, .add, .mul, .range => {
                try l.collectOld(n.lhs, out);
                try l.collectOld(n.rhs, out);
            },
            .is_expr, .not_expr, .negate, .try_expr, .member, .tuple_index, .named_arg => try l.collectOld(n.lhs, out),
            .member_call, .call => {
                try l.collectOld(n.lhs, out);
                for (l.spanAt(n.rhs)) |a| try l.collectOld(a, out);
            },
            .tuple, .list, .string_interp => for (l.tree.span(n.lhs, n.rhs)) |e| try l.collectOld(e, out),
            else => {},
        }
    }

    /// The refinements a value of the type at `type_node` must satisfy: its own `where`
    /// clauses, then its alias's. `within` names the function or type for reports.
    fn refinementsOf(l: *Lower, type_node: Index, within: []const u8) Error![]const u32 {
        var out: std.ArrayList(u32) = .empty;
        var cur = type_node;
        while (cur != 0) {
            const n = l.node(cur);
            switch (n.kind) {
                .type_refined => {
                    try out.append(l.gpa, try l.refinement(cur, within));
                    cur = n.lhs;
                },
                .type_ref => {
                    const d = l.k.findDeclAt(n.lhs, l.text(l.node(n.lhs).main_token)) orelse break;
                    const decl = l.k.decls[d];
                    if (decl.kind == .alias and decl.node != 0) try out.appendSlice(l.gpa, try l.refinementsOf(l.node(decl.node).lhs, decl.name));
                    break;
                },
                else => break,
            }
        }
        return out.items;
    }

    /// A `where` clause as a function of `value` (local 0) that gives a Bool.
    fn refinement(l: *Lower, refined: Index, within: []const u8) Error!u32 {
        if (l.refinement_of.get(refined)) |r| return r;
        const n = l.node(refined);
        const saved = l.b;
        var b: Builder = .{ .name = within, .contract = true };
        const fi = try l.reserve();
        l.b = &b;
        _ = try l.bindName("value", false);
        try b.param_names.append(l.gpa, "value");
        b.result = l.slot();
        try l.expr(n.rhs);
        _ = try l.emit(.ret, 0, 0);
        const cl = try l.clause(.refinement, n.main_token);
        l.b = saved;
        l.functions.items[fi] = try l.finish(&b);
        const r: u32 = @intCast(l.refinements.items.len);
        try l.refinements.append(l.gpa, .{ .function = fi, .clause = cl, .bounds = .of(&l.tree, n.rhs) });
        try l.refinement_of.put(l.gpa, refined, r);
        return r;
    }

    /// Checks the value on top against the refinements of a struct or variant field.
    fn refineField(l: *Lower, f: check.Field, within: []const u8) Error!void {
        if (f.node == 0) return;
        for (try l.refinementsOf(l.node(f.node).lhs, within)) |r| _ = try l.emit(.refine, r, 0);
    }

    fn lowerTest(l: *Lower, it: Index) Error!void {
        const n = l.node(it);
        const quoted = l.text(n.main_token);
        var b: Builder = .{ .name = quoted[1 .. quoted.len - 1] };
        l.b = &b;
        const fi = try l.reserve();
        b.result = l.slot();
        // A test's sends are delivered before its next statement runs (Mo.Sim).
        const settles = l.processes.items.len > 0;
        if (n.kind == .property) {
            try l.property(n.lhs);
            if (settles) _ = try l.emit(.settle, 0, 0);
        } else {
            const mark = b.names.items.len;
            for (l.tree.span(n.lhs, n.rhs)) |st| {
                try l.stmt(st);
                if (settles) _ = try l.emit(.settle, 0, 0);
            }
            b.names.shrinkRetainingCapacity(mark);
        }
        try l.pushConst(.none);
        _ = try l.emit(.ret, 0, 0);
        l.functions.items[fi] = try l.finish(&b);
        try l.tests.append(l.gpa, .{
            .kind = switch (n.kind) {
                .test_rejects => .rejects,
                .property => .property,
                else => .test_,
            },
            .name = b.name,
            .function = fi,
            .at = l.tree.tokens[n.main_token].start,
        });
    }

    /// A property is one attempt: generate a value for each `any(T)`, and discard the
    /// attempt when the guard is false. The runner calls it once per seed.
    fn property(l: *Lower, comp: Index) Error!void {
        const data = l.tree.extraData(ast.Comprehension, l.node(comp).lhs);
        try l.generators(l.tree.span(data.gens_start, data.gens_end), data);
    }

    fn generators(l: *Lower, gens: []const u32, data: ast.Comprehension) Error!void {
        if (gens.len == 0) {
            var skip: ?u32 = null;
            if (data.guard != 0) {
                try l.expr(data.guard);
                skip = try l.emit(.jump_if_false, 0, 0);
            }
            try l.blockStmts(l.tree.span(data.body_start, data.body_end));
            if (skip) |j| {
                const over = try l.emit(.jump, 0, 0);
                l.patch(j);
                // A guard over generated values discards the attempt; inside a list loop it skips one item.
                if (l.b.loops.items.len == 0) _ = try l.emit(.discard, 0, 0);
                l.patch(over);
            }
            return;
        }
        const g = l.node(gens[0]);
        if (l.node(g.lhs).kind == .any_expr) {
            const elem = l.baseType(l.typeOf(g.lhs)).a;
            _ = try l.emit(.generate, elem, try l.constant(.{ .string = l.text(g.main_token) }));
            try l.observe(elem);
            _ = try l.emit(.store, try l.bindName(l.text(g.main_token), false), 0);
            return l.generators(gens[1..], data);
        }
        const loop = try l.loopBegin(g.lhs, g.main_token);
        try l.generators(gens[1..], data);
        try l.loopEnd(loop);
    }

    /// A `never`: a function of nothing that the end of every test and property run calls
    /// (sim.zig, checkNevers). One whose body walks generators (`for a in Refund.all, ...`)
    /// trips the never's clause on the first values its guard admits and its body is true
    /// for; one whose body is an expression trips when it is true. A `flows` rule is tier
    /// 1's (caps.zig) and lowers to nothing.
    fn lowerNever(l: *Lower, it: Index) Error!void {
        const n = l.node(it);
        const body = l.node(n.rhs);
        if (std.mem.indexOfScalar(Index, l.k.flows, n.rhs) != null) return;
        const quoted = l.text(n.lhs);
        var b: Builder = .{ .name = quoted[1 .. quoted.len - 1], .contract = true };
        l.b = &b;
        const fi = try l.reserve();
        b.result = l.slot();
        const cl = try l.clause(.never, n.main_token);
        var names: std.ArrayList([]const u8) = .empty;
        if (body.kind == .comprehension) {
            const data = l.tree.extraData(ast.Comprehension, body.lhs);
            const gens = l.tree.span(data.gens_start, data.gens_end);
            for (gens) |g| {
                const tok = l.node(g).main_token;
                if (l.tree.tokens[tok].kind != .underscore) try names.append(l.gpa, l.text(tok));
            }
            var binders: std.ArrayList(u32) = .empty;
            try l.neverGenerators(gens, data, cl, &binders);
        } else {
            try l.expr(n.rhs);
            _ = try l.emit(.trip, cl, 0);
        }
        try l.pushConst(.none);
        _ = try l.emit(.ret, 0, 0);
        l.functions.items[fi] = try l.finish(&b);
        try l.nevers.append(l.gpa, .{ .function = fi, .clause = cl, .names = names.items });
    }

    /// One loop per generator; innermost, the guard, then the generated values and the
    /// body's Bool for `trip`.
    fn neverGenerators(l: *Lower, gens: []const u32, data: ast.Comprehension, cl: u32, binders: *std.ArrayList(u32)) Error!void {
        if (gens.len == 0) {
            var skip: ?u32 = null;
            if (data.guard != 0) {
                try l.expr(data.guard);
                skip = try l.emit(.jump_if_false, 0, 0);
            }
            for (binders.items) |s| _ = try l.emit(.load, s, 0);
            try l.blockValue(l.tree.span(data.body_start, data.body_end));
            _ = try l.emit(.trip, cl, @intCast(binders.items.len));
            if (skip) |j| l.patch(j);
            return;
        }
        const g = l.node(gens[0]);
        const loop = try l.loopBegin(g.lhs, g.main_token);
        const named = l.tree.tokens[g.main_token].kind != .underscore;
        if (named) try binders.append(l.gpa, l.b.names.items[l.b.names.items.len - 1].slot);
        try l.neverGenerators(gens[1..], data, cl, binders);
        if (named) _ = binders.pop();
        try l.loopEnd(loop);
    }

    // ---- processes and supervisors

    fn bindParams(l: *Lower, r: check.Range) Error!void {
        for (l.k.params[r.start..r.end]) |p| {
            _ = try l.bindName(p.name, false);
            l.holds(p.type);
            try l.b.param_names.append(l.gpa, p.name);
        }
    }

    fn lowerProcess(l: *Lower, it: Index) Error!void {
        const n = l.node(it);
        const di = l.k.findDeclAt(it, l.text(n.main_token)) orelse return;
        const d = l.k.decls[di];
        if (d.node != it) return;
        const data = l.tree.extraData(ast.Process, n.lhs);

        // init: every state field from its `= expr`, or its type's zero value.
        var b: Builder = .{ .name = d.name };
        l.b = &b;
        var fi = try l.reserve();
        try l.bindParams(d.params);
        b.result = l.slot();
        for (l.k.params[d.params.start..d.params.end], 0..) |p, k| try l.observeLocal(@intCast(k), p.type);
        for (l.k.fields[d.fields.start..d.fields.end]) |f| {
            const init = l.node(f.node).rhs;
            if (init != 0) {
                try l.expr(init);
            } else {
                const cl: u32 = @intCast(l.clauses.items.len);
                const tok = l.node(f.node).main_token;
                try l.clauses.append(l.gpa, .{ .kind = .other, .text = try std.fmt.allocPrint(l.gpa, "the state field {s} has no zero value; give it = expr", .{f.name}), .at = l.tree.tokens[tok].start, .within = d.name });
                _ = try l.emit(.zero, f.type, cl);
            }
            try l.observe(f.type);
            try l.refineField(f, d.name);
        }
        _ = try l.emit(.record, di, d.fields.len());
        _ = try l.emit(.ret, 0, 0);
        l.functions.items[fi] = try l.finish(&b);
        const init_fn = fi;

        // update: `state` is a var for the whole call; the arm's value is the reply.
        const update = l.node(data.update);
        b = .{ .name = d.name };
        l.b = &b;
        fi = try l.reserve();
        try l.bindParams(d.params);
        const state_slot = try l.bindName("state", true);
        _ = try l.bindName("message", false);
        if (d.reads_reply_by) {
            const reply_by = try l.bindName("reply_by", false);
            _ = try l.emit(.reply_by, 0, 0);
            _ = try l.emit(.store, reply_by, 0);
        }
        if (d.reads_reply_to) {
            const reply_to = try l.bindName("reply_to", false);
            _ = try l.emit(.reply_to, 0, 0);
            _ = try l.emit(.store, reply_to, 0);
        }
        b.result = l.slot();
        try l.caseArms(update.lhs, true, d.reads_reply_to);
        _ = try l.emit(.store, b.result, 0);
        for (b.exits.items) |e| l.patch(e);
        _ = try l.emit(.load, b.result, 0);
        _ = try l.emit(.load, state_slot, 0);
        _ = try l.emit(.tuple, 2, 0);
        _ = try l.emit(.ret, 0, 0);
        l.functions.items[fi] = try l.finish(&b);
        const update_fn = fi;

        var invariants: std.ArrayList(Invariant) = .empty;
        var reads_old = false;
        for (l.tree.span(data.invariants_start, data.invariants_end)) |inv| {
            b = .{ .name = d.name, .contract = true };
            l.b = &b;
            fi = try l.reserve();
            try l.bindParams(d.params);
            _ = try l.bindName("state", false);
            b.old_state = l.slot();
            b.result = l.slot();
            try l.expr(l.node(inv).rhs);
            for (b.code.items) |in| switch (in.op) {
                .load, .load_field, .load_shared => reads_old = reads_old or in.a == b.old_state,
                else => {},
            };
            _ = try l.emit(.ret, 0, 0);
            const cl = try l.clause(.invariant, l.node(inv).main_token);
            l.functions.items[fi] = try l.finish(&b);
            try invariants.append(l.gpa, .{ .function = fi, .clause = cl });
        }

        l.processes.items[l.process_of[di]] = .{
            .name = d.name,
            .decl = di,
            .mailbox = if (data.mailbox == ast.none) 1_000 else @intCast(parseInt(l.text(data.mailbox))),
            .init = init_fn,
            .update = update_fn,
            .invariants = invariants.items,
            .reads_old = reads_old,
            .reads_reply_by = d.reads_reply_by,
            .reads_reply_to = d.reads_reply_to,
        };
    }

    fn lowerSupervisor(l: *Lower, it: Index) Error!void {
        const n = l.node(it);
        const di = l.k.findDeclAt(it, l.text(n.main_token)) orelse return;
        const d = l.k.decls[di];
        if (d.node != it) return;
        var children: std.ArrayList(Child) = .empty;
        for (l.spanAt(n.rhs)) |ch| {
            const cn = l.node(ch);
            const data = l.tree.extraData(ast.Child, cn.lhs);
            const pd = l.k.findDeclAt(ch, l.text(cn.main_token)) orelse continue;
            if (l.process_of[pd] == none) continue;

            var b: Builder = .{ .name = d.name };
            l.b = &b;
            const args_fn = try l.reserve();
            try l.bindParams(d.params);
            b.result = l.slot();
            const args = l.tree.span(data.args_start, data.args_end);
            for (args) |a| try l.expr(a);
            _ = try l.emit(.tuple, @intCast(args.len), 0);
            _ = try l.emit(.ret, 0, 0);
            l.functions.items[args_fn] = try l.finish(&b);

            // The window is read without the supervisor's parameters, so the test runner
            // can supervise a child it starts directly under the same numbers.
            var per_fn: u32 = none;
            if (data.per != 0) {
                b = .{ .name = d.name };
                l.b = &b;
                per_fn = try l.reserve();
                b.result = l.slot();
                try l.expr(data.per);
                _ = try l.emit(.ret, 0, 0);
                l.functions.items[per_fn] = try l.finish(&b);
            }

            const atom = l.text(data.restart);
            try children.append(l.gpa, .{
                .process = l.process_of[pd],
                .args = args_fn,
                .restart = if (std.mem.eql(u8, atom, ":never")) .never else if (std.mem.eql(u8, atom, ":on_crash")) .on_crash else .always,
                .max_restarts = if (data.max_restarts == ast.none) none else @intCast(parseInt(l.text(data.max_restarts))),
                .per = per_fn,
            });
        }
        l.supervisors.items[l.supervisor_of[di]] = .{ .name = d.name, .decl = di, .children = children.items };
    }

    // ---- statements

    fn blockStmts(l: *Lower, stmts: []const u32) Error!void {
        const mark = l.b.names.items.len;
        for (stmts) |s| try l.stmt(s);
        l.b.names.shrinkRetainingCapacity(mark);
    }

    /// The last statement of a body is its value.
    fn blockValue(l: *Lower, stmts: []const u32) Error!void {
        const mark = l.b.names.items.len;
        defer l.b.names.shrinkRetainingCapacity(mark);
        if (stmts.len == 0) return l.pushConst(.none);
        for (stmts[0 .. stmts.len - 1]) |s| try l.stmt(s);
        const last = stmts[stmts.len - 1];
        const n = l.node(last);
        switch (n.kind) {
            .expr_stmt => try l.expr(n.lhs),
            .if_stmt => try l.ifLower(last, true),
            .case_stmt => try l.caseLower(last, true),
            else => {
                try l.stmt(last);
                try l.pushConst(.none);
            },
        }
    }

    fn stmt(l: *Lower, s: Index) Error!void {
        const n = l.node(s);
        switch (n.kind) {
            .expr_stmt => {
                try l.expr(n.lhs);
                _ = try l.emit(.pop, 0, 0);
            },
            .binding => {
                const name = l.text(n.main_token);
                l.in_place = .{ .call = n.lhs, .name = name };
                try l.expr(n.lhs);
                l.in_place = .{};
                try l.observe(l.typeOf(n.lhs));
                // `x = e` on a var is an assignment; the two are the same text.
                const target = if (l.localVar(name)) |v| v.slot else try l.bindName(name, false);
                _ = try l.emit(.store, target, 0);
            },
            .var_binding => {
                try l.expr(n.lhs);
                try l.observe(l.typeOf(n.lhs));
                _ = try l.emit(.store, try l.bindName(l.text(n.main_token), true), 0);
            },
            .assign => {
                // Read before the value, whose own blocks note theirs.
                const rests = !l.unrested.contains(s);
                const op = l.text(n.main_token);
                if (op.len == 1) {
                    const lhs = l.node(n.lhs);
                    if (lhs.kind == .name_ref or lhs.kind == .member) l.in_place = .{ .call = n.rhs, .path = n.lhs };
                    try l.expr(n.rhs);
                    l.in_place = .{};
                } else {
                    try l.expr(n.lhs);
                    try l.expr(n.rhs);
                    _ = try l.emit(if (op[0] == '+') .add else .sub, @intFromEnum(l.numOf(l.typeOf(n.lhs))), try l.clause(.overflow, l.firstToken(s)));
                }
                try l.assignPlace(n.lhs, rests);
            },
            .return_stmt => {
                var skip: ?u32 = null;
                if (n.rhs != 0) {
                    try l.expr(n.rhs);
                    skip = try l.emit(.jump_if_false, 0, 0);
                }
                try l.expr(n.lhs);
                _ = try l.emit(.store, l.b.result, 0);
                try l.b.exits.append(l.gpa, try l.emit(.jump, 0, 0));
                if (skip) |j| l.patch(j);
            },
            .for_stmt => {
                const loop = try l.loopBegin(n.lhs, n.main_token);
                try l.blockStmts(l.spanAt(n.rhs));
                try l.loopEnd(loop);
            },
            .if_stmt => try l.ifLower(s, false),
            .case_stmt => try l.caseLower(s, false),
            .assert_stmt => {
                const e = l.node(n.lhs);
                const cl = try l.clause(.assert, n.main_token);
                if (e.kind == .compare) {
                    try l.expr(e.lhs);
                    try l.expr(e.rhs);
                    _ = try l.emit(.check_compare, cl, @intFromEnum(compareOp(l.text(e.main_token))));
                } else {
                    try l.expr(n.lhs);
                    _ = try l.emit(.check, cl, 0);
                }
            },
            .break_stmt => try l.b.breaks.append(l.gpa, try l.emit(.jump, 0, 0)),
            else => {
                try l.expr(s);
                _ = try l.emit(.pop, 0, 0);
            },
        }
    }

    fn compareOp(op: []const u8) Op {
        if (std.mem.eql(u8, op, "==")) return .eq;
        if (std.mem.eql(u8, op, "!=")) return .ne;
        if (std.mem.eql(u8, op, "<")) return .lt;
        if (std.mem.eql(u8, op, "<=")) return .le;
        if (std.mem.eql(u8, op, ">")) return .gt;
        return .ge;
    }

    /// Stores the value on top into a place: a name, or a field path under one. The whole value
    /// the name then holds is recorded for a never when it `rests` (unrestedWrites).
    fn assignPlace(l: *Lower, i: Index, rests: bool) Error!void {
        const n = l.node(i);
        switch (n.kind) {
            .name_ref => {
                const target = (try l.resolve(l.text(n.main_token))).?;
                if (rests) try l.observe(l.typeOf(i));
                _ = try l.emit(.store, target.slot, 0);
            },
            .member => {
                const k = l.fieldIndex(l.typeOf(n.lhs), l.text(n.main_token)) orelse return l.halt(i, "", false);
                const d = l.k.decls[l.baseType(l.typeOf(n.lhs)).a];
                try l.refineField(l.k.fields[d.fields.start + k], d.name);
                // The old struct is only rebuilt with the field set: not a read that shares it.
                try l.loadPlace(n.lhs);
                _ = try l.emit(.swap, 0, 0);
                _ = try l.emit(.set_field, k, 0);
                try l.assignPlace(n.lhs, rests);
            },
            else => try l.halt(i, "", false),
        }
    }

    const Loop = struct { list: u32, index: u32, top: u32, exit: u32, mark: u32, kept: u32 };

    fn loopBegin(l: *Lower, iter: Index, name_tok: u32) Error!Loop {
        try l.expr(iter);
        const list = l.slot();
        _ = try l.emit(.store, list, 0);
        try l.pushConst(.{ .int = 0 });
        const index = l.slot();
        _ = try l.emit(.store, index, 0);
        // Each iteration ends at a safe point (vm.zig, collect).
        const mark = l.slot();
        const kept = l.slot();
        _ = try l.emit(.mark, mark, kept);
        const top = l.here();
        _ = try l.emit(.load, index, 0);
        _ = try l.emit(.load, list, 0);
        _ = try l.emit(.len, 0, 0);
        _ = try l.emit(.lt, 0, 0);
        const exit = try l.emit(.jump_if_false, 0, 0);
        _ = try l.emit(.load, list, 0);
        _ = try l.emit(.load, index, 0);
        _ = try l.emit(.index, 0, 0);
        const iterated = l.baseType(l.typeOf(iter));
        if (iterated.tag == .list) try l.observe(iterated.a);
        const binder =if (l.tree.tokens[name_tok].kind == .underscore) l.slot() else try l.bindName(l.text(name_tok), false);
        _ = try l.emit(.store, binder, 0);
        try l.b.loops.append(l.gpa, @intCast(l.b.breaks.items.len));
        return .{ .list = list, .index = index, .top = top, .exit = exit, .mark = mark, .kept = kept };
    }

    fn loopEnd(l: *Lower, loop: Loop) Error!void {
        _ = try l.emit(.load, loop.index, 0);
        try l.pushConst(.{ .int = 1 });
        _ = try l.emit(.add, @intFromEnum(Num.u64), none);
        _ = try l.emit(.store, loop.index, 0);
        _ = try l.emit(.collect, loop.mark, loop.kept);
        _ = try l.emit(.jump, loop.top, 0);
        l.patch(loop.exit);
        const start = l.b.loops.pop().?;
        for (l.b.breaks.items[start..]) |j| l.patch(j);
        l.b.breaks.shrinkRetainingCapacity(start);
    }

    fn ifLower(l: *Lower, s: Index, value: bool) Error!void {
        const n = l.node(s);
        const data = l.tree.extraData(ast.If, n.rhs);
        const has_else = n.kind == .if_expr or data.else_end > data.else_start;
        const mark = l.b.names.items.len;
        try l.expr(n.lhs);
        const to_else = try l.emit(.jump_if_false, 0, 0);
        const then_stmts = l.tree.span(data.then_start, data.then_end);
        if (value and has_else) try l.blockValue(then_stmts) else try l.blockStmts(then_stmts);
        l.b.names.shrinkRetainingCapacity(mark);
        const to_end = try l.emit(.jump, 0, 0);
        l.patch(to_else);
        const else_stmts = l.tree.span(data.else_start, data.else_end);
        if (value and has_else) try l.blockValue(else_stmts) else try l.blockStmts(else_stmts);
        l.patch(to_end);
        if (value and !has_else) try l.pushConst(.none);
    }

    fn caseLower(l: *Lower, s: Index, value: bool) Error!void {
        return l.caseArms(s, value, false);
    }

    /// `update`: the update's own case, whose arms may keep their asker (step 31).
    fn caseArms(l: *Lower, s: Index, value: bool, update: bool) Error!void {
        const n = l.node(s);
        try l.expr(n.lhs);
        const subject = l.slot();
        _ = try l.emit(.store, subject, 0);
        var ends: std.ArrayList(u32) = .empty;
        for (l.spanAt(n.rhs)) |a| {
            const an = l.node(a);
            const data = l.tree.extraData(ast.Arm, an.rhs);
            const mark = l.b.names.items.len;
            var fails: std.ArrayList(u32) = .empty;
            try l.pattern(an.lhs, subject, &fails);
            if (data.guard != 0) {
                try l.expr(data.guard);
                try fails.append(l.gpa, try l.emit(.jump_if_false, 0, 0));
            }
            const body = l.tree.span(data.body_start, data.body_end);
            if (update and check.armDefersReply(l.tree, a)) _ = try l.emit(.defer_reply, 0, 0);
            if (value) try l.blockValue(body) else try l.blockStmts(body);
            try ends.append(l.gpa, try l.emit(.jump, 0, 0));
            for (fails.items) |f| l.patch(f);
            l.b.names.shrinkRetainingCapacity(mark);
        }
        try l.halt(s, "", false);
        for (ends.items) |e| l.patch(e);
    }

    // ---- patterns

    /// Tests the value in `subject` against pattern `p`, binding its names; every jump
    /// taken when it does not match is added to `fails`.
    fn pattern(l: *Lower, p: Index, subject: u32, fails: *std.ArrayList(u32)) Error!void {
        const n = l.node(p);
        switch (n.kind) {
            .pat_wildcard => {},
            .pat_bind => {
                _ = try l.emit(.load, subject, 0);
                try l.observe(l.typeOf(p));
                _ = try l.emit(.store, try l.bindName(l.text(n.main_token), false), 0);
            },
            .pat_literal => {
                _ = try l.emit(.load, subject, 0);
                var value = try l.literal(n.main_token);
                if (n.lhs != 0) switch (value) {
                    .int => |v| value = .{ .int = -v },
                    .float => |v| value = .{ .float = -v },
                    else => {},
                };
                try l.pushConst(value);
                _ = try l.emit(.eq, 0, 0);
                try fails.append(l.gpa, try l.emit(.jump_if_false, 0, 0));
            },
            .pat_variant => {
                try l.variantTest(subject, l.text(n.main_token), fails);
                if (n.lhs != 0) try l.subPattern(subject, 0, n.lhs, fails);
            },
            .pat_record => {
                const subject_t = l.typeOf(p);
                const t = l.baseType(subject_t);
                const is_struct = t.tag == .decl and l.k.decls[t.a].kind == .struct_;
                const name = l.text(n.main_token);
                if (!is_struct) try l.variantTest(subject, name, fails);
                for (l.tree.span(n.lhs, n.rhs)) |pf| {
                    const field = l.node(pf);
                    const k = l.variantFieldIndex(subject_t, name, l.text(field.main_token)) orelse continue;
                    try l.subPattern(subject, k, field.lhs, fails);
                }
            },
            .pat_tuple => for (l.tree.span(n.lhs, n.rhs), 0..) |e, k| try l.subPattern(subject, @intCast(k), e, fails),
            .pat_or => try l.orPattern(n, subject, fails),
            else => unreachable,
        }
    }

    /// `A | B | C`: each alternative in turn, until one matches. A later alternative stores
    /// its names into the slots the first one bound, so the body reads them whichever matched.
    fn orPattern(l: *Lower, n: ast.Node, subject: u32, fails: *std.ArrayList(u32)) Error!void {
        const alts = l.tree.span(n.lhs, n.rhs);
        const first = l.b.names.items.len;
        var first_end = first;
        var matched: std.ArrayList(u32) = .empty;
        for (alts, 0..) |alt, k| {
            const mark = l.b.names.items.len;
            const last = k + 1 == alts.len;
            var alt_fails: std.ArrayList(u32) = .empty;
            try l.pattern(alt, subject, if (last) fails else &alt_fails);
            if (k == 0) {
                first_end = l.b.names.items.len;
            } else {
                for (l.b.names.items[mark..]) |bound| for (l.b.names.items[first..first_end]) |want| {
                    if (!std.mem.eql(u8, want.name, bound.name)) continue;
                    _ = try l.emit(.load, bound.slot, 0);
                    _ = try l.emit(.store, want.slot, 0);
                };
                l.b.names.shrinkRetainingCapacity(first_end);
            }
            if (!last) {
                try matched.append(l.gpa, try l.emit(.jump, 0, 0));
                for (alt_fails.items) |f| l.patch(f);
            }
        }
        for (matched.items) |m| l.patch(m);
    }

    fn variantTest(l: *Lower, subject: u32, name: []const u8, fails: *std.ArrayList(u32)) Error!void {
        _ = try l.emit(.load, subject, 0);
        _ = try l.emit(.is_variant, try l.constant(.{ .string = name }), 0);
        try fails.append(l.gpa, try l.emit(.jump_if_false, 0, 0));
    }

    fn subPattern(l: *Lower, subject: u32, k: u32, p: Index, fails: *std.ArrayList(u32)) Error!void {
        const kind = l.node(p).kind;
        if (kind == .pat_wildcard) return;
        _ = try l.emit(.load, subject, 0);
        _ = try l.emit(.field, k, 0);
        const inner = l.slot();
        _ = try l.emit(.store, inner, 0);
        try l.pattern(p, inner, fails);
    }

    fn literal(l: *Lower, tok: u32) Error!Const {
        const raw = l.text(tok);
        return switch (l.tree.tokens[tok].kind) {
            .int => .{ .int = parseInt(raw) },
            .float => .{ .float = std.fmt.parseFloat(f64, raw) catch 0 },
            .string => .{ .string = try l.stringText(tok, l.tree.tokens[tok].start + quoteLen(raw), l.tree.tokens[tok].end - quoteLen(raw)) },
            .kw_true => .{ .bool = true },
            else => .{ .bool = false },
        };
    }

    fn parseInt(raw: []const u8) i128 {
        var v: i128 = 0;
        for (raw) |ch| if (ch != '_') {
            v = v *| 10 +| (ch - '0');
        };
        return v;
    }

    fn quoteLen(raw: []const u8) u32 {
        return if (std.mem.startsWith(u8, raw, "\"\"\"")) 3 else 1;
    }

    /// The text of the string token `tok` between byte offsets `from` and `to`, escapes
    /// decoded. In a `"""` string the newline after the opening quotes and the one
    /// before the closing line go, and every line loses the closing line's indentation.
    fn stringText(l: *Lower, tok: u32, from: u32, to: u32) Error![]const u8 {
        const src = l.tree.source;
        const t = l.tree.tokens[tok];
        const raw = src[t.start..t.end];
        const triple = quoteLen(raw) == 3;
        const body_start = t.start + quoteLen(raw);
        const body_end = t.end - quoteLen(raw);
        var indent: []const u8 = "";
        var last_newline: u32 = none;
        if (triple) {
            if (std.mem.lastIndexOfScalar(u8, src[body_start..body_end], '\n')) |nl| {
                const tail = src[body_start + nl + 1 .. body_end];
                if (std.mem.trim(u8, tail, " \t").len == 0) {
                    indent = tail;
                    last_newline = body_start + @as(u32, @intCast(nl));
                }
            }
        }
        var out: std.ArrayList(u8) = .empty;
        var i = from;
        if (triple and i == body_start and i < to and src[i] == '\n') {
            i += 1;
            i = skipIndent(src, i, to, indent);
        }
        while (i < to) {
            const ch = src[i];
            if (triple and ch == '\n') {
                if (i == last_newline) break;
                try out.append(l.gpa, '\n');
                i = skipIndent(src, i + 1, to, indent);
                continue;
            }
            if (ch == '\\' and i + 1 < to) {
                if (lexer.unicodeEscape(src[0..to], i)) |u| {
                    var utf8: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(u.value, &utf8) catch unreachable;
                    try out.appendSlice(l.gpa, utf8[0..len]);
                    i = @intCast(u.end);
                    continue;
                }
                try out.append(l.gpa, switch (src[i + 1]) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    else => src[i + 1],
                });
                i += 2;
                continue;
            }
            try out.append(l.gpa, ch);
            i += 1;
        }
        return out.items;
    }

    fn skipIndent(src: []const u8, from: u32, to: u32, indent: []const u8) u32 {
        var i = from;
        for (indent) |ch| {
            if (i >= to or src[i] != ch) break;
            i += 1;
        }
        return i;
    }

    // ---- types

    /// The position of field `name` in struct `t`, or in a process's `state`.
    fn fieldIndex(l: *Lower, t: Id, name: []const u8) ?u32 {
        const b = l.baseType(t);
        if (b.tag != .state and (b.tag != .decl or l.k.decls[b.a].kind != .struct_)) return null;
        const r = l.k.decls[b.a].fields;
        for (l.k.fields[r.start..r.end], 0..) |f, k| if (std.mem.eql(u8, f.name, name)) return @intCast(k);
        return null;
    }

    /// The position of `field` in struct `t`, or in variant `variant` of enum `t`.
    fn variantFieldIndex(l: *Lower, t: Id, variant: []const u8, field: []const u8) ?u32 {
        const b = l.baseType(t);
        if (b.tag != .decl and b.tag != .message) return null;
        const d = l.k.decls[b.a];
        if (b.tag == .decl and d.kind == .struct_) return l.fieldIndex(t, field);
        for (l.k.variants[d.variants.start..d.variants.end]) |v| {
            if (!std.mem.eql(u8, v.name, variant)) continue;
            for (l.k.fields[v.fields.start..v.fields.end], 0..) |f, k| if (std.mem.eql(u8, f.name, field)) return @intCast(k);
        }
        return null;
    }

    // ---- expressions

    fn expr(l: *Lower, i: Index) Error!void {
        const n = l.node(i);
        l.holds(l.typeOf(i));
        switch (n.kind) {
            .int_lit, .float_lit, .true_lit, .false_lit => try l.pushConst(switch (n.kind) {
                .int_lit => .{ .int = parseInt(l.text(n.main_token)) },
                .float_lit => .{ .float = std.fmt.parseFloat(f64, l.text(n.main_token)) catch 0 },
                .true_lit => .{ .bool = true },
                else => .{ .bool = false },
            }),
            .string_lit => try l.pushConst(try l.literal(n.main_token)),
            .string_interp => {
                const parts = l.tree.span(n.lhs, n.rhs);
                for (parts) |part| {
                    const pn = l.node(part);
                    if (pn.kind == .string_part) {
                        try l.pushConst(.{ .string = try l.stringText(pn.main_token, pn.lhs, pn.rhs) });
                    } else try l.expr(part);
                }
                _ = try l.emit(.concat, @intCast(parts.len), 0);
            },
            .name_ref => try l.nameRef(i),
            .type_name_ref => {
                _ = try l.emit(.variant, try l.constant(.{ .string = l.text(n.main_token) }), 0);
                try l.observe(l.typeOf(i));
            },
            .tuple, .list => {
                const elems = l.tree.span(n.lhs, n.rhs);
                for (elems) |e| {
                    try l.expr(e);
                    // In a list, an element never holds a buffer alone (vm.disownIn).
                    if (n.kind == .list) try l.share(l.typeOf(e));
                }
                _ = try l.emit(if (n.kind == .tuple) .tuple else .list, @intCast(elems.len), 0);
            },
            .not_expr => {
                try l.expr(n.lhs);
                _ = try l.emit(.not, 0, 0);
            },
            .and_expr, .implies => {
                // a and b: false unless a; a implies b: true unless a.
                try l.expr(n.lhs);
                const short = try l.emit(.jump_if_false, 0, 0);
                try l.expr(n.rhs);
                const end = try l.emit(.jump, 0, 0);
                l.patch(short);
                try l.pushConst(.{ .bool = n.kind == .implies });
                l.patch(end);
            },
            .or_expr => {
                if (l.baseType(l.typeOf(n.lhs)).tag == .option) {
                    try l.expr(n.lhs);
                    const opt = l.slot();
                    _ = try l.emit(.store, opt, 0);
                    _ = try l.emit(.load, opt, 0);
                    _ = try l.emit(.is_variant, try l.constant(.{ .string = "Some" }), 0);
                    const to_default = try l.emit(.jump_if_false, 0, 0);
                    _ = try l.emit(.load, opt, 0);
                    _ = try l.emit(.field, 0, 0);
                    const end = try l.emit(.jump, 0, 0);
                    l.patch(to_default);
                    try l.expr(n.rhs);
                    l.patch(end);
                } else {
                    try l.expr(n.lhs);
                    const short = try l.emit(.jump_if_true, 0, 0);
                    try l.expr(n.rhs);
                    const end = try l.emit(.jump, 0, 0);
                    l.patch(short);
                    try l.pushConst(.{ .bool = true });
                    l.patch(end);
                }
            },
            .compare => {
                try l.expr(n.lhs);
                try l.expr(n.rhs);
                _ = try l.emit(compareOp(l.text(n.main_token)), 0, 0);
            },
            .is_expr => {
                try l.expr(n.lhs);
                const subject = l.slot();
                _ = try l.emit(.store, subject, 0);
                var fails: std.ArrayList(u32) = .empty;
                // Names the pattern binds stay in scope after it (grammar, Session 5).
                try l.pattern(n.rhs, subject, &fails);
                try l.pushConst(.{ .bool = true });
                const end = try l.emit(.jump, 0, 0);
                for (fails.items) |f| l.patch(f);
                try l.pushConst(.{ .bool = false });
                l.patch(end);
            },
            .range => {
                try l.expr(n.lhs);
                try l.expr(n.rhs);
                _ = try l.emit(.range, 0, 0);
            },
            .add, .mul => {
                try l.expr(n.lhs);
                try l.expr(n.rhs);
                const op: Op = switch (l.text(n.main_token)[0]) {
                    '+' => .add,
                    '-' => .sub,
                    '*' => .mul,
                    '/' => .div,
                    else => .rem,
                };
                _ = try l.emit(op, @intFromEnum(l.numOf(l.typeOf(i))), try l.clause(.overflow, l.firstToken(i)));
            },
            .negate => {
                try l.expr(n.lhs);
                _ = try l.emit(.negate, @intFromEnum(l.numOf(l.typeOf(i))), try l.clause(.overflow, n.main_token));
            },
            .try_expr => {
                try l.expr(n.lhs);
                const value = l.slot();
                _ = try l.emit(.store, value, 0);
                _ = try l.emit(.load, value, 0);
                const ok = if (l.baseType(l.typeOf(n.lhs)).tag == .option) "Some" else "Ok";
                _ = try l.emit(.is_variant, try l.constant(.{ .string = ok }), 0);
                const to_error = try l.emit(.jump_if_false, 0, 0);
                _ = try l.emit(.load, value, 0);
                _ = try l.emit(.field, 0, 0);
                const end = try l.emit(.jump, 0, 0);
                l.patch(to_error);
                // An Error or a None passes up as it is: re-tagged by name, never converted.
                _ = try l.emit(.load, value, 0);
                _ = try l.emit(.store, l.b.result, 0);
                try l.b.exits.append(l.gpa, try l.emit(.jump, 0, 0));
                l.patch(end);
            },
            .member => {
                if (l.k.callee[i] != .none) return l.callNode(i, n.lhs, &.{});
                const k = l.fieldIndex(l.typeOf(n.lhs), l.text(n.main_token)) orelse return l.halt(i, try std.fmt.allocPrint(l.gpa, "{s} is a field of a type tier 2 cannot see", .{l.text(n.main_token)}), false);
                try l.projection(i, k);
            },
            .member_call => try l.callNode(i, n.lhs, l.spanAt(n.rhs)),
            .tuple_index => try l.projection(i, @intCast(parseInt(l.text(n.main_token)))),
            .call => {
                const callee = l.node(n.lhs);
                const args = l.spanAt(n.rhs);
                if (callee.kind == .type_name_ref) return l.construct(i);
                if (l.k.callee[i] != .none) return l.callNode(i, null, args);
                try l.expr(n.lhs);
                for (args) |a| try l.expr(a);
                _ = try l.emit(.call_value, @intCast(args.len), 0);
            },
            .if_expr => try l.ifLower(i, true),
            .case_expr => try l.caseLower(i, true),
            .anon_fn => try l.anonFn(i),
            .old_expr => if (l.old_slots.get(i)) |at| {
                _ = try l.emit(if (l.owns(l.typeOf(i))) .load_shared else .load, at, 0);
            } else if (l.b.old_state != none) {
                // In an invariant, `state` inside old(...) is the state before the message.
                try l.b.names.append(l.gpa, .{ .name = "state", .slot = l.b.old_state, .mutable = false });
                try l.expr(n.lhs);
                _ = l.b.names.pop();
            } else try l.expr(n.lhs),
            .result_ref => _ = try l.emit(if (l.owns(l.typeOf(i))) .load_shared else .load, l.b.result, 0),
            else => try l.halt(i, "", false),
        }
    }

    /// Field k of the value left of `i`, `x.f` or `x.0`: read from a local, or a field path
    /// under one, without sharing the rest of it, so only the field may now be held twice,
    /// unless the read hands it on (moves.zig). One instruction when the value is a local, as
    /// `acc.0` in a fold is.
    fn projection(l: *Lower, i: Index, k: u32) Error!void {
        const obj = l.node(i).lhs;
        const on = l.node(obj);
        if (on.kind == .name_ref) {
            if (try l.resolve(l.text(on.main_token))) |v| {
                _ = try l.emit(.load_field, v.slot, k);
                if (!l.moving(i)) try l.share(l.typeOf(i));
                return;
            }
        }
        const rooted = try l.loadChain(obj);
        _ = try l.emit(.field, k, 0);
        if (rooted and !l.moving(i)) try l.share(l.typeOf(i));
    }

    /// A local, or a field or tuple path under one, pushed without sharing it: true. Any other
    /// expression is lowered as it is: false.
    fn loadChain(l: *Lower, i: Index) Error!bool {
        const n = l.node(i);
        switch (n.kind) {
            .name_ref => if (try l.resolve(l.text(n.main_token))) |v| {
                _ = try l.emit(.load, v.slot, 0);
                return true;
            },
            .member => if (l.k.callee[i] == .none) {
                if (l.fieldIndex(l.typeOf(n.lhs), l.text(n.main_token))) |k| {
                    const rooted = try l.loadChain(n.lhs);
                    _ = try l.emit(.field, k, 0);
                    return rooted;
                }
            },
            .tuple_index => {
                const rooted = try l.loadChain(n.lhs);
                _ = try l.emit(.field, @intCast(parseInt(l.text(n.main_token))), 0);
                return rooted;
            },
            else => {},
        }
        try l.expr(i);
        return false;
    }

    fn nameRef(l: *Lower, i: Index) Error!void {
        const n = l.node(i);
        const name = l.text(n.main_token);
        if (try l.resolve(name)) |v| {
            _ = try l.emit(if (l.owns(l.typeOf(i)) and !l.moving(i)) .load_shared else .load, v.slot, 0);
            return;
        }
        switch (l.k.callee[i]) {
            // A bare name inside `where` is called on the refined value.
            .prelude => |row| return l.preludeCall(i, row, null, &.{}),
            else => {},
        }
        if (l.k.findFnAt(i, name)) |si| {
            _ = try l.emit(.closure, l.fn_of_sig[si], 0);
            return;
        }
        if (prelude.findValue(name) != null) {
            // t0 is the instant Time.fixture() gives.
            for (prelude.fns, 0..) |row, k| if (std.mem.eql(u8, row.recv, "Time") and std.mem.eql(u8, row.name, "fixture")) {
                _ = try l.emit(.prim, @intCast(k), none);
                return;
            };
        }
        try l.halt(i, "", false);
    }

    fn callNode(l: *Lower, i: Index, recv: ?Index, args: []const u32) Error!void {
        switch (l.k.callee[i]) {
            .user => |si| try l.userCall(si, recv, args),
            .prelude => |row| try l.preludeCall(i, row, recv, args),
            .none => try l.halt(i, "", false),
        }
    }

    fn userCall(l: *Lower, si: u32, recv: ?Index, args: []const u32) Error!void {
        const s = l.k.sigs[si];
        var arg_nodes: std.ArrayList(Index) = .empty;
        if (recv) |r| try arg_nodes.append(l.gpa, r);
        for (args) |a| if (l.node(a).kind != .named_arg) try arg_nodes.append(l.gpa, a);
        for (arg_nodes.items) |a| try l.expr(a);
        const count: u32 = @intCast(arg_nodes.items.len);
        if (s.kind == .trait) {
            _ = try l.emit(.call_trait, si, count);
        } else {
            _ = try l.emit(.call, l.fn_of_sig[si], count);
        }
        // Each inout argument takes the parameter's final value, last one on top.
        const ps = l.k.params[s.params.start..s.params.end];
        var j = @min(ps.len, arg_nodes.items.len);
        while (j > 0) {
            j -= 1;
            if (ps[j].inout) try l.assignPlace(arg_nodes.items[j], true);
        }
    }

    fn preludeCall(l: *Lower, i: Index, k: u32, recv: ?Index, args: []const u32) Error!void {
        const row = prelude.fns[k];
        if (std.mem.eql(u8, row.recv, "Process")) {
            const positional = for (args) |a| {
                if (l.node(a).kind == .named_arg) break false;
            } else true;
            if (!positional) return l.halt(i, "", false);
            for (args) |a| {
                try l.expr(a);
                try l.share(l.typeOf(a));
            }
            _ = try l.emit(.spawn, l.process_of[l.baseType(l.typeOf(i)).a], @intCast(args.len));
            return;
        }
        if (std.mem.eql(u8, row.recv, "Supervisor")) {
            const d = l.k.findDeclAt(i, l.text(l.node(recv.?).main_token)) orelse return l.halt(i, "", false);
            for (args) |a| {
                try l.expr(a);
                try l.share(l.typeOf(a));
            }
            _ = try l.emit(.start_supervisor, l.supervisor_of[d], @intCast(args.len));
            return;
        }
        if (std.mem.startsWith(u8, row.recv, "Handle")) {
            try l.expr(recv.?);
            // A message outlives the send: the process that takes it is a second holder.
            for (args) |a| if (l.node(a).kind != .named_arg) {
                try l.expr(a);
                try l.share(l.typeOf(a));
            };
            if (std.mem.eql(u8, row.name, "send")) {
                for (args) |a| {
                    const an = l.node(a);
                    if (an.kind != .named_arg or !std.mem.eql(u8, l.text(an.main_token), "delay")) continue;
                    try l.expr(an.lhs);
                    _ = try l.emit(.send_later, 0, 0);
                    return;
                }
                _ = try l.emit(.send, 0, 0);
                return;
            }
            for (args) |a| {
                const an = l.node(a);
                if (an.kind == .named_arg and std.mem.eql(u8, l.text(an.main_token), "within")) try l.withinArg(an.lhs);
            }
            _ = try l.emit(.ask, 0, 0);
            return;
        }
        if (std.mem.startsWith(u8, row.recv, "Reply")) {
            try l.expr(recv.?);
            for (args) |a| {
                try l.expr(a);
                try l.share(l.typeOf(a));
            }
            _ = try l.emit(.answer, 0, 0);
            return;
        }
        if (row.only == .never) {
            // `T.all`: the distinct values of T the run held (sim.zig).
            const list = l.k.pool.get(l.typeOf(i));
            const kept = if (list.tag == .list) l.recorded_as[l.k.pool.resolve(list.a)] else none;
            if (!std.mem.eql(u8, row.recv, "Type") or kept == none) return l.halt(i, "", false);
            _ = try l.emit(.all, kept, 0);
            return;
        }
        var kind: u32 = none;
        // A free row (min_of) has no receiver.
        if (!row.on_type and row.recv.len > 0) {
            if (recv) |r| {
                if (l.inPlace(i, r, row) or (writesInPlace(row) and l.moving(r))) {
                    try l.loadPlace(r);
                    kind = unique;
                } else {
                    // A row that only looks at a map or set shares none of its buffer.
                    if (looksOnly(row)) try l.loadPlace(r) else try l.expr(r);
                    // A list's row (`sum`) checks against its element's integer type.
                    const rt = l.baseType(l.typeOf(r));
                    kind = if (rt.tag == .list) l.intKind(rt.a) else l.intKind(l.typeOf(r));
                }
            } else {
                // A bare name inside `where`: the refined value is local 0.
                _ = try l.emit(.load, 0, 0);
            }
        }
        var position: usize = 0;
        for (args) |a| if (l.node(a).kind != .named_arg) {
            try l.expr(a);
            // A row keeps what it is given (a list's element, a map's value), except the
            // accumulator it hands back.
            if (!accumulates(row, position)) try l.share(l.typeOf(a));
            position += 1;
        };
        // Json.encode spells its argument by the argument's checked type.
        if (row.on_type and std.mem.eql(u8, row.recv, "Json") and std.mem.eql(u8, row.name, "encode")) {
            for (args) |a| if (l.node(a).kind != .named_arg) {
                kind = l.typeOf(a);
                break;
            };
        }
        for (row.named) |f| {
            for (args) |a| {
                const an = l.node(a);
                if (an.kind != .named_arg or !std.mem.eql(u8, l.text(an.main_token), f.name)) continue;
                try l.expr(an.lhs);
                try l.share(l.typeOf(an.lhs));
            }
        }
        if (row.can_wait) {
            const within = for (args) |a| {
                const an = l.node(a);
                if (an.kind == .named_arg and std.mem.eql(u8, l.text(an.main_token), "within")) break an.lhs;
            } else 0;
            if (within != 0) try l.withinArg(within) else try l.pushConst(.none);
        }
        _ = try l.emit(.prim, k, kind);
    }

    /// A `within:` argument: a Duration as it is, and a Deadline as the Duration that remains of
    /// it (step 22).
    fn withinArg(l: *Lower, arg: Index) Error!void {
        try l.expr(arg);
        if (l.k.pool.get(l.k.pool.base(l.typeOf(arg))).tag == .deadline) _ = try l.emit(.deadline_left, 0, 0);
    }

    /// Whether call `i` is the right side of `m = m.set(k, v)`, `update`, or `remove` on a
    /// var map, or `s = s.add(x)` or `remove` on a var set, or the same on a field path under
    /// a var (`state.data = state.data.set(k, v)`), and `r` reads that place: the old value
    /// is overwritten, so the row may write in place.
    fn inPlace(l: *Lower, i: Index, r: Index, row: prelude.Fn) bool {
        if (i != l.in_place.call or !writesInPlace(row)) return false;
        if (l.in_place.path != 0) return l.samePlace(r, l.in_place.path);
        const rn = l.node(r);
        return rn.kind == .name_ref and std.mem.eql(u8, l.text(rn.main_token), l.in_place.name) and l.localVar(l.in_place.name) != null;
    }

    /// Whether two expressions name the same place: one var, or one field path under it.
    fn samePlace(l: *Lower, a: Index, b: Index) bool {
        const an = l.node(a);
        const bn = l.node(b);
        if (an.kind != bn.kind or !std.mem.eql(u8, l.text(an.main_token), l.text(bn.main_token))) return false;
        return switch (an.kind) {
            .name_ref => l.localVar(l.text(an.main_token)) != null,
            .member => l.k.callee[a] == .none and l.k.callee[b] == .none and l.samePlace(an.lhs, bn.lhs),
            else => false,
        };
    }

    /// A place's value, a name or a field path under one, read without giving up a var's
    /// claim on the buffers it holds; any other expression as it is.
    fn loadPlace(l: *Lower, i: Index) Error!void {
        const n = l.node(i);
        switch (n.kind) {
            .name_ref => if (try l.resolve(l.text(n.main_token))) |v| {
                _ = try l.emit(.load, v.slot, 0);
                return;
            },
            .member => if (l.k.callee[i] == .none) {
                if (l.fieldIndex(l.typeOf(n.lhs), l.text(n.main_token))) |k| {
                    try l.loadPlace(n.lhs);
                    _ = try l.emit(.field, k, 0);
                    return;
                }
            },
            else => {},
        }
        try l.expr(i);
    }

    /// The map and set rows that give sizes, elements, or new lists, and never the buffer.
    fn looksOnly(row: prelude.Fn) bool {
        const on_map = std.mem.startsWith(u8, row.recv, "Map(") or std.mem.startsWith(u8, row.recv, "Set(");
        if (!on_map) return false;
        for ([_][]const u8{ "size", "get", "has?", "keys", "values", "entries", "to_list" }) |name| {
            if (std.mem.eql(u8, row.name, name)) return true;
        }
        return false;
    }

    fn construct(l: *Lower, i: Index) Error!void {
        const n = l.node(i);
        const name = l.text(l.node(n.lhs).main_token);
        const args = l.spanAt(n.rhs);
        for ([_][]const u8{ "Some", "Ok", "Error" }) |builtin| if (std.mem.eql(u8, name, builtin)) {
            try l.expr(args[0]);
            _ = try l.emit(.variant, try l.constant(.{ .string = name }), 1);
            return l.observe(l.typeOf(i));
        };
        const t = l.baseType(l.typeOf(i));
        if (t.tag != .decl and t.tag != .message) return l.halt(i, "", false);
        const d = l.k.decls[t.a];
        const is_struct = t.tag == .decl and d.kind == .struct_;
        const fields: check.Range = if (is_struct) d.fields else for (l.k.variants[d.variants.start..d.variants.end]) |v| {
            if (std.mem.eql(u8, v.name, name)) break v.fields;
        } else return l.halt(i, "", false);
        for (l.k.fields[fields.start..fields.end]) |f| {
            const arg = for (args) |a| {
                const an = l.node(a);
                if (an.kind == .named_arg and std.mem.eql(u8, l.text(an.main_token), f.name)) break an.lhs;
            } else 0;
            if (arg == 0 and f.optional) {
                // A stdlib struct's field left out is empty (prelude.zig).
                if (l.k.pool.get(l.k.pool.base(f.type)).tag == .map) {
                    const k = for (prelude.fns, 0..) |row, k| {
                        if (std.mem.eql(u8, row.recv, "Map") and std.mem.eql(u8, row.name, "new")) break k;
                    } else unreachable;
                    _ = try l.emit(.prim, @intCast(k), none);
                } else try l.pushConst(.{ .string = "" });
            } else if (arg == 0) try l.pushConst(.none) else {
                try l.expr(arg);
                try l.refineField(f, d.name);
            }
        }
        if (is_struct) {
            _ = try l.emit(.record, t.a, fields.len());
        } else {
            _ = try l.emit(.variant, try l.constant(.{ .string = name }), fields.len());
        }
        try l.observe(l.typeOf(i));
    }

    fn anonFn(l: *Lower, i: Index) Error!void {
        const data = l.tree.extraData(ast.AnonFn, l.node(i).lhs);
        const parent = l.b;
        var b: Builder = .{ .parent = parent, .name = parent.name };
        const fi = try l.reserve();
        l.b = &b;
        for (l.tree.span(data.params_start, data.params_end)) |tok| {
            // `_` takes its argument's slot and binds nothing (step 28).
            _ = if (l.tree.tokens[tok].kind == .underscore) l.slot() else try l.bindName(l.text(tok), false);
            try b.param_names.append(l.gpa, l.text(tok));
        }
        b.result = l.slot();
        const ft = l.k.pool.get(l.typeOf(i));
        if (ft.tag == .func) for (l.k.pool.elems(ft), 0..) |t, k| try l.observeLocal(@intCast(k), t);
        try l.blockValue(l.tree.span(data.body_start, data.body_end));
        _ = try l.emit(.ret, 0, 0);
        l.b = parent;
        l.functions.items[fi] = try l.finish(&b);
        // A captured value is a second holder while the function runs.
        for (b.captures.items) |c| _ = try l.emit(.load_shared, c.outer, 0);
        _ = try l.emit(.closure, fi, @intCast(b.captures.items.len));
    }
};
