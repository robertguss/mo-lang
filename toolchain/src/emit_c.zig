//! The C backend (design-v0/07, build order item 2): a checked program, from its tree and
//! not its bytecode, as one C11 translation unit that links toolchain/runtime/mo_rt.c.
//! `mo build` (cbuild.zig) compiles the two with `zig cc`.
//!
//! The code is plain: one C function per Mo function, a struct a record of its fields in
//! declaration order, an enum a tagged variant, `case` a chain of tests that jump to the
//! next arm, `for` a C loop, the combinators the runtime's loops, and an anonymous function
//! a static function with its captures in an explicit environment. Every value is the
//! runtime's 16-byte MoValue (mo_rt.h). The lowering mirrors bytecode.zig construct for
//! construct, so the binary means what the interpreter means: the same evaluation order, the
//! same overflow traps, the same contract checks (behind the `mo_contracts` flag, on in every
//! binary unless it was built `--no-contracts`), and the same safe points, where the region keeps what the frame's locals
//! reach and frees the rest.
//!
//! Every Mo local of a C function is declared at its top, so a safe point can pass them all
//! as roots, as the vm passes a frame's locals. Temporaries are block-scoped. A process is a C
//! function each for its first state, its update, and each invariant, and a supervisor's child
//! line one for its arguments and one for its window, in tables the runtime's scheduler reads
//! (mo_rt.c, processes); a test's and main's statements settle as bytecode.zig's do. The Net
//! and Http rows are the runtime's: real sockets under main, their fixtures in a test binary.
const std = @import("std");
const lexer = @import("lexer.zig");
const surface_mod = @import("surface.zig");
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");
const check = @import("check.zig");
const contracts = @import("contracts.zig");
const diag = @import("diag.zig");
const moves_mod = @import("moves.zig");
const prelude = @import("prelude.zig");
const program = @import("program.zig");
const types = @import("types.zig");

const Index = ast.Index;
const Node = ast.Node;
const Id = types.Id;
const none = bytecode.none;

pub const Options = struct {
    /// A binary that runs the given file's tests and prints what `mo test` prints, not main.
    tests: bool = false,
    /// Contracts checked by default in the binary; false only for `mo build --no-contracts`.
    contracts: bool = true,
    /// `mo build --surface`: `platform.runtime` is `Some` in the binary (step 23).
    surface: bool = false,
};

pub const Error = error{OutOfMemory};

/// The runtime's own variant names, in mo_rt.h's MO_N_* order.
const fixed_names = [_][]const u8{ "Some", "None", "Ok", "Error", "Missing", "Timeout", "Syntax", "Object", "Array", "String", "Number", "Bool", "Null", "Down", "Refused", "Closed", "LineTooLong", "Busy", "Malformed", "TooLarge", "Unsupported", "NotText", "Accepted", "Line", "Idle", "NoProcess", "Unparsed", "ReadOnly", "MailboxFull", "Updated", "Started", "Ended", "Restarted", "Crashed", "Overflowed", "TimedOut", "SourcePaused", "SourceResumed", "Sent", "Paused", "Resumed" };

/// The C translation unit for `checked`, loaded as `prog`; a program build needs its main.
pub fn emit(gpa: std.mem.Allocator, checked: *const check.Checked, prog: program.Program, options: Options) Error![]const u8 {
    var e: Emitter = .{ .gpa = gpa, .k = checked, .tree = checked.tree, .prog = prog, .options = options };
    e.recorded = try bytecode.recordedTypes(gpa, checked);
    e.moves = try moves_mod.analyze(gpa, checked);
    e.unrested = try bytecode.unrestedWrites(gpa, checked.tree);
    for (fixed_names) |n| _ = try e.nameId(n);
    try e.indexProcesses();
    try e.run();
    return e.assemble();
}

fn recvHead(recv: []const u8) []const u8 {
    return recv[0 .. std.mem.indexOfScalar(u8, recv, '(') orelse recv.len];
}

const Name = struct { name: []const u8, cvar: []const u8, mutable: bool };
const Capture = struct { name: []const u8, outer: []const u8 };

const Loop = struct { id: u32, break_used: bool = false };

/// A label jumped to from before it: emitted only when something jumps there.
const Label = struct { id: u32, used: bool = false };

/// One C function being written.
const Builder = struct {
    parent: ?*Builder = null,
    /// The function, test, or type its clauses belong to.
    name: []const u8,
    cname: []const u8,
    /// Every C parameter that is a value: a root at every safe point.
    value_params: std.ArrayList([]const u8) = .empty,
    /// Mo locals, declared at the top.
    locals: std.ArrayList([]const u8) = .empty,
    names: std.ArrayList(Name) = .empty,
    captures: std.ArrayList(Capture) = .empty,
    /// Parameter names and their C variables, for a requires or ensures report.
    params: std.ArrayList(Name) = .empty,
    /// C variables of the inout parameters and their index.
    inouts: std.ArrayList(u32) = .empty,
    pre: std.ArrayList(u8) = .empty,
    code: std.ArrayList(u8) = .empty,
    temps: u32 = 0,
    exit: Label = .{ .id = 0 },
    loops: std.ArrayList(Loop) = .empty,
    has_loops: bool = false,
    /// Lowering a contract expression: integer arithmetic is unbounded.
    contract: bool = false,
    indent: u32 = 1,
    /// In an invariant: the state before the message, which `old` reads, and whether it did.
    old_state: ?[]const u8 = null,
    reads_old: bool = false,
    /// A parameter or an expression can hold a process's handle, so the function registers its
    /// locals for a sweep (bytecode.zig, Function.scans_handles).
    handles: bool = false,
};

const Refinement = struct { cname: []const u8, clause: u32, bounds: bytecode.Bounds = .{} };

const Clause = struct { kind: contracts.Kind, text: []const u8, at: u32, within: []const u8, skip: bool = false };

const Desc = struct { tag: types.Tag, name: []const u8, recorded: u32, may_hold: bool, a: u32 = 0, b: u32 = 0, items: []const u32 = &.{} };

const TestEntry = struct { kind: bytecode.TestKind, name: []const u8, cname: []const u8 };

const NeverEntry = struct { cname: []const u8, clause: u32, names: []const []const u8 };

const InvariantEntry = struct { cname: []const u8, clause: u32 };

/// mo_rt.h MoProcess.
const ProcessEntry = struct {
    name: []const u8 = "",
    decl: u32 = 0,
    mailbox: u32 = 0,
    init: []const u8 = "NULL",
    update: []const u8 = "NULL",
    invariants: []const InvariantEntry = &.{},
    reads_old: bool = false,
};

/// mo_rt.h MoChild and MoSupervisor.
const ChildEntry = struct { process: u32, args: []const u8, restart: bytecode.Restart, max_restarts: u32, per: ?[]const u8 };
const SupervisorEntry = struct { name: []const u8 = "", children: []const ChildEntry = &.{} };

/// The signature of a function the scheduler calls with its arguments in `args`.
const code_head = "const MoValue *cap, const MoValue *args";

const Emitter = struct {
    gpa: std.mem.Allocator,
    k: *const check.Checked,
    tree: ast.Tree,
    prog: program.Program,
    options: Options,
    recorded: bytecode.Recorded = undefined,
    /// Which reads hand their value on (moves.zig, step 28).
    moves: moves_mod.Moves = .{},
    /// The field writes that record nothing, since the next write reached assigns the same place
    /// (bytecode.unrestedWrites; steps 27, 28).
    unrested: std.AutoHashMapUnmanaged(Index, void) = .empty,
    b: *Builder = undefined,
    protos: std.ArrayList(u8) = .empty,
    bodies: std.ArrayList(u8) = .empty,
    names: std.ArrayList([]const u8) = .empty,
    name_ids: std.StringHashMapUnmanaged(u32) = .empty,
    clauses: std.ArrayList(Clause) = .empty,
    descs: std.ArrayList(Desc) = .empty,
    desc_of: std.AutoHashMapUnmanaged(Id, u32) = .empty,
    refinement_of: std.AutoHashMapUnmanaged(Index, Refinement) = .empty,
    refinements: u32 = 0,
    old_slots: std.AutoHashMapUnmanaged(Index, []const u8) = .empty,
    anons: u32 = 0,
    wrappers: std.AutoHashMapUnmanaged(u32, void) = .empty,
    dispatchers: std.AutoHashMapUnmanaged(u32, void) = .empty,
    tests: std.ArrayList(TestEntry) = .empty,
    nevers: std.ArrayList(NeverEntry) = .empty,
    labels: u32 = 0,
    /// While `m = m.set(k, v)` or `s.f = s.f.set(k, v)` is lowered (bytecode.zig in_place).
    in_place: struct { call: Index = 0, name: []const u8 = "", path: Index = 0 } = .{},
    /// Checked decl index → index in `processes` or `supervisors`, or `none` (bytecode.zig).
    process_of: []u32 = &.{},
    supervisor_of: []u32 = &.{},
    processes: std.ArrayList(ProcessEntry) = .empty,
    supervisors: std.ArrayList(SupervisorEntry) = .empty,

    // ---- small helpers

    fn node(e: *Emitter, i: Index) Node {
        return e.tree.nodes[i];
    }

    fn text(e: *Emitter, tok: u32) []const u8 {
        return e.tree.tokenText(tok);
    }

    fn items(e: *Emitter) []const u32 {
        return e.tree.span(e.tree.nodes[0].lhs, e.tree.nodes[0].rhs);
    }

    fn spanAt(e: *Emitter, extra_index: u32) []const u32 {
        if (extra_index == 0) return &.{};
        const s = e.tree.extraData(ast.Span, extra_index);
        return e.tree.span(s.start, s.end);
    }

    fn typeOf(e: *Emitter, i: Index) Id {
        return e.k.typeOf(i);
    }

    fn baseType(e: *Emitter, t: Id) types.Type {
        return e.k.pool.get(e.k.pool.base(t));
    }

    /// A value of type `t` is held in the function being written.
    fn holds(e: *Emitter, t: Id) void {
        if (!e.b.handles and check.handleIn(&e.k.pool, t, 0)) e.b.handles = true;
    }

    fn intKind(e: *Emitter, t: Id) u32 {
        const b = e.baseType(t);
        return if (b.tag == .int) b.a else none;
    }

    fn print(e: *Emitter, comptime fmt: []const u8, args: anytype) Error![]const u8 {
        return std.fmt.allocPrint(e.gpa, fmt, args);
    }

    fn line(e: *Emitter, comptime fmt: []const u8, args: anytype) Error!void {
        const b = e.b;
        for (0..b.indent) |_| try b.code.appendSlice(e.gpa, "    ");
        try b.code.print(e.gpa, fmt, args);
        try b.code.append(e.gpa, '\n');
    }

    /// A temporary holding `fmt`: its name.
    fn temp(e: *Emitter, comptime fmt: []const u8, args: anytype) Error![]const u8 {
        const name = try e.print("t{d}", .{e.b.temps});
        e.b.temps += 1;
        const value = try e.print(fmt, args);
        try e.line("MoValue {s} MO_U = {s};", .{ name, value });
        return name;
    }

    /// A Mo local of the function: declared at its top.
    fn local(e: *Emitter) Error![]const u8 {
        const name = try e.print("L{d}", .{e.b.value_params.items.len + e.b.locals.items.len});
        try e.b.locals.append(e.gpa, name);
        return name;
    }

    fn bindName(e: *Emitter, name: []const u8, mutable: bool) Error![]const u8 {
        const cvar = try e.local();
        try e.b.names.append(e.gpa, .{ .name = name, .cvar = cvar, .mutable = mutable });
        return cvar;
    }

    fn label(e: *Emitter) Label {
        e.labels += 1;
        return .{ .id = e.labels };
    }

    fn nameId(e: *Emitter, name: []const u8) Error!u32 {
        if (e.name_ids.get(name)) |id| return id;
        const id: u32 = @intCast(e.names.items.len);
        try e.names.append(e.gpa, name);
        try e.name_ids.put(e.gpa, name, id);
        return id;
    }

    /// `(const MoValue[]){a, b}`, or NULL for none.
    fn valuesOf(e: *Emitter, xs: []const []const u8) Error![]const u8 {
        if (xs.len == 0) return "NULL";
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(e.gpa, "(const MoValue[]){");
        for (xs, 0..) |x, i| {
            if (i > 0) try out.appendSlice(e.gpa, ", ");
            try out.appendSlice(e.gpa, x);
        }
        try out.append(e.gpa, '}');
        return out.items;
    }

    fn stringsOf(e: *Emitter, xs: []const []const u8) Error![]const u8 {
        if (xs.len == 0) return "NULL";
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(e.gpa, "(const char *const[]){");
        for (xs, 0..) |x, i| {
            if (i > 0) try out.appendSlice(e.gpa, ", ");
            try out.appendSlice(e.gpa, try cString(e.gpa, x));
        }
        try out.append(e.gpa, '}');
        return out.items;
    }

    fn firstToken(e: *Emitter, i: Index) u32 {
        var cur = i;
        while (true) {
            const n = e.node(cur);
            switch (n.kind) {
                .implies, .or_expr, .and_expr, .compare, .is_expr, .range, .add, .mul, .member, .member_call, .tuple_index, .call, .assign => cur = n.lhs,
                else => return n.main_token,
            }
        }
    }

    /// The source line from `tok` to its end: the clause a report quotes.
    fn lineFrom(e: *Emitter, tok: u32) []const u8 {
        const src = e.tree.source;
        const start = e.tree.tokens[tok].start;
        const end = std.mem.indexOfScalarPos(u8, src, start, '\n') orelse src.len;
        return std.mem.trimEnd(u8, src[start..end], " \t\r");
    }

    fn clause(e: *Emitter, kind: contracts.Kind, tok: u32) Error!u32 {
        return e.addClause(.{ .kind = kind, .text = e.lineFrom(tok), .at = e.tree.tokens[tok].start, .within = e.b.name });
    }

    fn addClause(e: *Emitter, c: Clause) Error!u32 {
        const at: u32 = @intCast(e.clauses.items.len);
        try e.clauses.append(e.gpa, c);
        return at;
    }

    /// Stops the run here: a skip with a sentence, or a crash quoting the line.
    fn halt(e: *Emitter, i: Index, sentence: []const u8, skip: bool) Error!void {
        const tok = e.firstToken(i);
        const cl = try e.addClause(.{ .kind = .other, .text = if (sentence.len > 0) sentence else e.lineFrom(tok), .at = e.tree.tokens[tok].start, .within = e.b.name, .skip = skip });
        try e.line("mo_crash({d});", .{cl});
    }

    // ---- what a test run records

    fn desc(e: *Emitter, id: Id) Error!u32 {
        const pool = &e.k.pool;
        const r = pool.resolve(id);
        if (e.desc_of.get(r)) |d| return d;
        const index: u32 = @intCast(e.descs.items.len);
        try e.descs.append(e.gpa, undefined);
        try e.desc_of.put(e.gpa, r, index);
        const t = pool.get(r);
        var d: Desc = .{
            .tag = t.tag,
            .name = try pool.name(e.gpa, r),
            .recorded = if (r < e.recorded.recorded_as.len) e.recorded.recorded_as[r] else none,
            .may_hold = r < e.recorded.may_hold.len and e.recorded.may_hold[r],
        };
        switch (t.tag) {
            .int, .float, .cap, .decl, .state, .message, .handle => d.a = t.a,
            .list, .option, .set => d.a = try e.desc(t.a),
            .result, .map => {
                d.a = try e.desc(t.a);
                d.b = try e.desc(t.b);
            },
            .tuple => {
                const elems = pool.elems(t);
                const out = try e.gpa.alloc(u32, elems.len);
                for (elems, out) |x, *o| o.* = try e.desc(x);
                d.items = out;
                d.b = @intCast(elems.len);
            },
            .alias => {
                d.a = t.a;
                d.b = try e.desc(t.b);
            },
            else => {},
        }
        e.descs.items[index] = d;
        return index;
    }

    fn mayHold(e: *Emitter, t: Id) bool {
        const r = e.k.pool.resolve(t);
        return e.options.tests and r < e.recorded.may_hold.len and e.recorded.may_hold[r];
    }

    /// The value in `v`, of type `t`, is held where a run can see it.
    fn observe(e: *Emitter, v: []const u8, t: Id) Error!void {
        if (!e.mayHold(t)) return;
        try e.line("mo_observe({s}, {d});", .{ v, try e.desc(t) });
    }

    /// Whether a value of type `t` can hold a buffer one holder holds alone (moves.zig).
    fn owns(e: *Emitter, t: Id) bool {
        return e.moves.owns(e.k, t);
    }

    /// Whether the read at `i` hands its value on (moves.zig); never inside a contract.
    fn moving(e: *Emitter, i: Index) bool {
        return !e.b.contract and e.moves.has(i);
    }

    /// `v`, of type `t`, may now be held twice: a row or a list keeps it (bytecode.zig, share).
    fn share(e: *Emitter, v: []const u8, t: Id) Error!void {
        if (e.owns(t)) try e.line("mo_disown_in({s});", .{v});
    }

    // ---- names

    /// A name in the function being written, captured from the enclosing ones when an
    /// anonymous function reads it.
    fn resolveIn(e: *Emitter, b: *Builder, name: []const u8) Error!?Name {
        var i = b.names.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, b.names.items[i].name, name)) {
                if (b.old_state) |before| b.reads_old = b.reads_old or std.mem.eql(u8, b.names.items[i].cvar, before);
                return b.names.items[i];
            }
        }
        for (b.captures.items, 0..) |c, k| if (std.mem.eql(u8, c.name, name)) return .{ .name = name, .cvar = try e.print("cap[{d}]", .{k}), .mutable = false };
        const parent = b.parent orelse return null;
        const outer = try e.resolveIn(parent, name) orelse return null;
        const k = b.captures.items.len;
        try b.captures.append(e.gpa, .{ .name = name, .outer = outer.cvar });
        return .{ .name = name, .cvar = try e.print("cap[{d}]", .{k}), .mutable = false };
    }

    fn resolve(e: *Emitter, name: []const u8) Error!?Name {
        return e.resolveIn(e.b, name);
    }

    fn localVar(e: *Emitter, name: []const u8) ?Name {
        var i = e.b.names.items.len;
        while (i > 0) {
            i -= 1;
            const n = e.b.names.items[i];
            if (std.mem.eql(u8, n.name, name)) return if (n.mutable) n else null;
        }
        return null;
    }

    // ---- functions

    /// Every process and supervisor has its index before anything that starts one is lowered.
    fn indexProcesses(e: *Emitter) Error!void {
        e.process_of = try e.gpa.alloc(u32, e.k.decls.len);
        e.supervisor_of = try e.gpa.alloc(u32, e.k.decls.len);
        @memset(e.process_of, none);
        @memset(e.supervisor_of, none);
        for (e.k.decls, 0..) |d, di| switch (d.kind) {
            .process => {
                e.process_of[di] = @intCast(e.processes.items.len);
                try e.processes.append(e.gpa, .{});
            },
            .supervisor => {
                e.supervisor_of[di] = @intCast(e.supervisors.items.len);
                try e.supervisors.append(e.gpa, .{});
            },
            else => {},
        };
    }

    fn run(e: *Emitter) Error!void {
        for (e.k.sigs, 0..) |s, si| if (s.kind != .trait) try e.lowerFn(@intCast(si));
        for (e.items()) |it| switch (e.node(it).kind) {
            .process_decl => try e.lowerProcess(it),
            .supervisor_decl => try e.lowerSupervisor(it),
            else => {},
        };
        if (e.options.tests) {
            for (e.items()) |it| if (e.node(it).kind == .never) try e.lowerNever(it);
            const base = e.prog.main().base;
            for (e.items()) |it| {
                const n = e.node(it);
                switch (n.kind) {
                    .test_decl, .test_rejects, .property => if (e.tree.tokens[n.main_token].start >= base) try e.lowerTest(it),
                    .recipe_decl => {
                        const r = e.tree.extraData(ast.Recipe, n.lhs);
                        for (e.tree.span(r.tests_start, r.tests_end)) |t| {
                            if (e.tree.tokens[e.node(t).main_token].start >= base) try e.lowerTest(t);
                        }
                    },
                    else => {},
                }
            }
        }
    }

    /// The function's text: its roots macro, its locals, its code, and its return.
    fn finish(e: *Emitter, b: *Builder, head: []const u8) Error!void {
        const gpa = e.gpa;
        var roots: std.ArrayList([]const u8) = .empty;
        try roots.appendSlice(gpa, b.value_params.items);
        try roots.appendSlice(gpa, b.locals.items);
        try roots.append(gpa, "R");
        const out = &e.bodies;
        try e.protos.print(gpa, "MO_U static MoValue {s}({s});\n", .{ b.cname, head });
        if (b.has_loops) {
            try out.print(gpa, "#define ROOTS_{s}(m, k) do {{ if (mo_loop_due(m, k)) {{ MoValue r_[] = {{", .{b.cname});
            for (roots.items, 0..) |r, i| try out.print(gpa, "{s}{s}", .{ if (i > 0) ", " else "", r });
            try out.print(gpa, "}}; mo_compact(m, r_, {d});", .{roots.items.len});
            for (roots.items, 0..) |r, i| try out.print(gpa, " {s} = r_[{d}];", .{ r, i });
            try out.appendSlice(gpa, " k = mo_heap.top - m; } } while (0)\n");
        }
        try out.print(gpa, "MO_U static MoValue {s}({s}) {{\n    size_t F_ MO_U = mo_mark();\n    MoValue R MO_U = MO_NONE_V;\n", .{ b.cname, head });
        // Every call counts its depth (contracts.depth_limit), as the vm's exec does.
        try out.print(gpa, "    if (++mo_depth > MO_DEPTH_LIMIT) mo_too_deep({s});\n", .{try cString(gpa, b.name)});
        for (b.locals.items) |l| try out.print(gpa, "    MoValue {s} MO_U = MO_NONE_V;\n", .{l});
        // A function that can hold a handle lists its locals where a sweep reads them (mo_rt.c).
        if (b.handles) {
            try out.appendSlice(gpa, "    MoValue *const H_[] = {");
            for (roots.items, 0..) |r, i| try out.print(gpa, "{s}&{s}", .{ if (i > 0) ", " else "", r });
            try out.print(gpa, "}};\n    MoHandleFrame HF_ = {{mo_handle_frames, H_, {d}}};\n    mo_handle_frames = &HF_;\n", .{roots.items.len});
        }
        try out.appendSlice(gpa, b.pre.items);
        try out.appendSlice(gpa, b.code.items);
        // A frame that allocated more than its budget keeps its result and inouts, and frees the rest.
        try out.appendSlice(gpa, "    if (mo_frame_due(F_)) {\n        MoValue r_[] = {R");
        for (b.inouts.items) |k| try out.print(gpa, ", L{d}", .{k});
        try out.print(gpa, "}};\n        mo_compact(F_, r_, {d});\n        R = r_[0];\n", .{b.inouts.items.len + 1});
        for (b.inouts.items, 1..) |k, i| try out.print(gpa, "        L{d} = r_[{d}];\n", .{ k, i });
        try out.appendSlice(gpa, "    }\n");
        for (b.inouts.items) |k| try out.print(gpa, "    *io{d} = L{d};\n", .{ k, k });
        if (b.handles) try out.appendSlice(gpa, "    mo_handle_frames = HF_.next;\n");
        try out.appendSlice(gpa, "    mo_depth--;\n    return R;\n}\n");
        if (b.has_loops) try out.print(gpa, "#undef ROOTS_{s}\n", .{b.cname});
    }

    fn exitLabel(e: *Emitter) Error!void {
        if (e.b.exit.used) try e.line("X{d}:;", .{e.b.exit.id});
    }

    fn lowerFn(e: *Emitter, si: u32) Error!void {
        const s = e.k.sigs[si];
        const n = e.node(s.node);
        const sig = e.tree.extraData(ast.Signature, n.lhs);
        var b: Builder = .{ .name = s.name, .cname = try e.print("f{d}", .{si}), .exit = e.label() };
        e.b = &b;
        const params = e.k.params[s.params.start..s.params.end];
        var head: std.ArrayList(u8) = .empty;
        for (params, 0..) |p, k| {
            if (k > 0) try head.appendSlice(e.gpa, ", ");
            const cvar = try e.print("L{d}", .{k});
            if (p.inout) {
                try head.print(e.gpa, "MoValue *io{d}", .{k});
                try b.locals.append(e.gpa, cvar);
                try b.inouts.append(e.gpa, @intCast(k));
                try b.pre.print(e.gpa, "    {s} = *io{d};\n", .{ cvar, k });
            } else {
                try head.print(e.gpa, "MoValue {s}", .{cvar});
                try b.value_params.append(e.gpa, cvar);
            }
            try b.names.append(e.gpa, .{ .name = p.name, .cvar = cvar, .mutable = p.inout });
            try b.params.append(e.gpa, .{ .name = p.name, .cvar = cvar, .mutable = p.inout });
            e.holds(p.type);
        }
        // Locals are numbered past every parameter.
        if (params.len > 0 and b.value_params.items.len + b.locals.items.len != params.len) unreachable;
        if (params.len == 0) try head.appendSlice(e.gpa, "void");
        for (params, 0..) |p, k| try e.observe(b.params.items[k].cvar, p.type);

        // On entry: each argument crosses into its parameter's refinement, then requires,
        // then every old(...) operand is kept for ensures.
        const contract_nodes = e.tree.span(sig.contracts_start, sig.contracts_end);
        try e.line("if (mo_contracts) {{", .{});
        b.indent += 1;
        for (params, 0..) |p, k| {
            for (try e.refinementsOf(e.node(p.node).lhs, s.name)) |r| try e.refine(r, b.params.items[k].cvar);
        }
        for (contract_nodes) |c| if (e.node(c).kind == .requires) try e.contract(c, .requires);
        for (contract_nodes) |c| if (e.node(c).kind == .ensures) {
            var olds: std.ArrayList(Index) = .empty;
            try e.collectOld(e.node(c).lhs, &olds);
            for (olds.items) |o| {
                b.contract = true;
                const v = try e.expr(e.node(o).lhs);
                b.contract = false;
                const slot = try e.local();
                try e.line("{s} = {s};", .{ slot, v });
                try e.old_slots.put(e.gpa, o, slot);
            }
        };
        b.indent -= 1;
        try e.line("}}", .{});

        if (n.kind == .fn_decl and e.processes.items.len > 0 and e.k.mainSig() == si) {
            // main is the root supervisor: its sends are delivered before its next statement
            // runs, as a test's are.
            const body = e.tree.extraData(ast.FnBody, n.rhs);
            const mark = b.names.items.len;
            for (e.tree.span(body.start, body.end)) |st| {
                try e.stmt(st);
                try e.line("mo_settle();", .{});
            }
            b.names.shrinkRetainingCapacity(mark);
            try e.line("R = MO_NONE_V;", .{});
        } else if (n.kind == .fn_decl) {
            const body = e.tree.extraData(ast.FnBody, n.rhs);
            const v = try e.blockValue(e.tree.span(body.start, body.end));
            try e.line("R = {s};", .{v});
        } else {
            try e.halt(s.node, try e.print("{s} is a recipe signature with no body until an agent implements the recipe", .{s.name}), true);
        }
        try e.exitLabel();

        // On exit, from every return: the result crosses into the return type's refinement,
        // then ensures.
        try e.line("if (mo_contracts) {{", .{});
        b.indent += 1;
        for (try e.refinementsOf(sig.ret, s.name)) |r| try e.refine(r, "R");
        for (contract_nodes) |c| if (e.node(c).kind == .ensures) try e.contract(c, .ensures);
        b.indent -= 1;
        try e.line("}}", .{});
        try e.finish(&b, head.items);
    }

    /// A requires or ensures: its expression in unbounded integers, then a check that
    /// crashes naming the clause, the parameters, and for ensures the result.
    fn contract(e: *Emitter, c: Index, kind: contracts.Kind) Error!void {
        const n = e.node(c);
        const mark = e.b.names.items.len;
        e.b.contract = true;
        const v = try e.expr(n.lhs);
        e.b.contract = false;
        const cl = try e.clause(kind, n.main_token);
        var names: std.ArrayList([]const u8) = .empty;
        var values: std.ArrayList([]const u8) = .empty;
        for (e.b.params.items) |p| {
            try names.append(e.gpa, p.name);
            try values.append(e.gpa, p.cvar);
        }
        if (kind == .ensures) {
            try names.append(e.gpa, "result");
            try values.append(e.gpa, "R");
        }
        try e.line("if (!{s}.as.b) mo_crash_values({d}, {d}, {s}, {s});", .{ v, cl, names.items.len, try e.stringsOf(names.items), try e.valuesOf(values.items) });
        e.b.names.shrinkRetainingCapacity(mark);
    }

    /// Every old(...) inside a contract expression.
    fn collectOld(e: *Emitter, i: Index, out: *std.ArrayList(Index)) Error!void {
        if (i == 0) return;
        const n = e.node(i);
        switch (n.kind) {
            .old_expr => try out.append(e.gpa, i),
            .implies, .or_expr, .and_expr, .compare, .add, .mul, .range => {
                try e.collectOld(n.lhs, out);
                try e.collectOld(n.rhs, out);
            },
            .is_expr, .not_expr, .negate, .try_expr, .member, .tuple_index, .named_arg => try e.collectOld(n.lhs, out),
            .member_call, .call => {
                try e.collectOld(n.lhs, out);
                for (e.spanAt(n.rhs)) |a| try e.collectOld(a, out);
            },
            .tuple, .list, .string_interp => for (e.tree.span(n.lhs, n.rhs)) |x| try e.collectOld(x, out),
            else => {},
        }
    }

    /// The refinements a value of the type at `type_node` must satisfy: its own `where`
    /// clauses, then its alias's.
    fn refinementsOf(e: *Emitter, type_node: Index, within: []const u8) Error![]const Refinement {
        var out: std.ArrayList(Refinement) = .empty;
        var cur = type_node;
        while (cur != 0) {
            const n = e.node(cur);
            switch (n.kind) {
                .type_refined => {
                    try out.append(e.gpa, try e.refinement(cur, within));
                    cur = n.lhs;
                },
                .type_ref => {
                    const d = e.k.findDeclAt(n.lhs, e.text(e.node(n.lhs).main_token)) orelse break;
                    const decl = e.k.decls[d];
                    if (decl.kind == .alias and decl.node != 0) try out.appendSlice(e.gpa, try e.refinementsOf(e.node(decl.node).lhs, decl.name));
                    break;
                },
                else => break,
            }
        }
        return out.items;
    }

    /// A `where` clause as a C function of `value` that gives a Bool.
    fn refinement(e: *Emitter, refined: Index, within: []const u8) Error!Refinement {
        if (e.refinement_of.get(refined)) |r| return r;
        const n = e.node(refined);
        const saved = e.b;
        var b: Builder = .{ .name = within, .cname = try e.print("r{d}", .{e.refinements}), .contract = true, .exit = e.label() };
        e.refinements += 1;
        e.b = &b;
        try b.value_params.append(e.gpa, "L0");
        try b.names.append(e.gpa, .{ .name = "value", .cvar = "L0", .mutable = false });
        const v = try e.expr(n.rhs);
        try e.line("R = {s};", .{v});
        try e.exitLabel();
        const cl = try e.clause(.refinement, n.main_token);
        try e.finish(&b, "MoValue L0");
        e.b = saved;
        const r: Refinement = .{ .cname = b.cname, .clause = cl, .bounds = .of(&e.tree, n.rhs) };
        try e.refinement_of.put(e.gpa, refined, r);
        return r;
    }

    /// Crashes with the refinement's clause unless the value in `v` holds.
    fn refine(e: *Emitter, r: Refinement, v: []const u8) Error!void {
        try e.line("if (!{s}({s}).as.b) mo_crash_values({d}, 1, (const char *const[]){{\"value\"}}, (const MoValue[]){{{s}}});", .{ r.cname, v, r.clause, v });
    }

    /// Checks the value in `v` against the refinements of a struct or variant field.
    fn refineField(e: *Emitter, f: check.Field, within: []const u8, v: []const u8) Error!void {
        if (f.node == 0) return;
        const refs = try e.refinementsOf(e.node(f.node).lhs, within);
        if (refs.len == 0) return;
        try e.line("if (mo_contracts) {{", .{});
        e.b.indent += 1;
        for (refs) |r| try e.refine(r, v);
        e.b.indent -= 1;
        try e.line("}}", .{});
    }

    fn lowerTest(e: *Emitter, it: Index) Error!void {
        const n = e.node(it);
        const quoted = e.text(n.main_token);
        var b: Builder = .{ .name = quoted[1 .. quoted.len - 1], .cname = try e.print("test{d}", .{e.tests.items.len}), .exit = e.label() };
        e.b = &b;
        // A test's sends are delivered before its next statement runs (Mo.Sim).
        const settles = e.processes.items.len > 0;
        if (n.kind == .property) {
            const data = e.tree.extraData(ast.Comprehension, e.node(n.lhs).lhs);
            try e.generators(e.tree.span(data.gens_start, data.gens_end), data);
            if (settles) try e.line("mo_settle();", .{});
        } else {
            const mark = b.names.items.len;
            for (e.tree.span(n.lhs, n.rhs)) |st| {
                try e.stmt(st);
                if (settles) try e.line("mo_settle();", .{});
            }
            b.names.shrinkRetainingCapacity(mark);
        }
        try e.exitLabel();
        try e.finish(&b, "void");
        try e.tests.append(e.gpa, .{
            .kind = switch (n.kind) {
                .test_rejects => .rejects,
                .property => .property,
                else => .test_,
            },
            .name = b.name,
            .cname = b.cname,
        });
    }

    /// A property is one attempt: a value for each `any(T)`, and the attempt discarded when
    /// the guard is false. The runner calls it once per attempt.
    fn generators(e: *Emitter, gens: []const u32, data: ast.Comprehension) Error!void {
        if (gens.len == 0) {
            if (data.guard != 0) {
                const g = try e.expr(data.guard);
                if (e.b.loops.items.len == 0) {
                    try e.line("if (!{s}.as.b) mo_discard();", .{g});
                    try e.blockStmts(e.tree.span(data.body_start, data.body_end));
                } else {
                    try e.line("if ({s}.as.b) {{", .{g});
                    e.b.indent += 1;
                    try e.blockStmts(e.tree.span(data.body_start, data.body_end));
                    e.b.indent -= 1;
                    try e.line("}}", .{});
                }
                return;
            }
            return e.blockStmts(e.tree.span(data.body_start, data.body_end));
        }
        const g = e.node(gens[0]);
        if (e.node(g.lhs).kind == .any_expr) {
            const elem = e.baseType(e.typeOf(g.lhs)).a;
            const v = try e.temp("mo_generate({d}, {s})", .{ try e.desc(elem), try cString(e.gpa, e.text(g.main_token)) });
            try e.observe(v, elem);
            try e.line("{s} = {s};", .{ try e.bindName(e.text(g.main_token), false), v });
            return e.generators(gens[1..], data);
        }
        const loop = try e.loopBegin(g.lhs, g.main_token);
        try e.generators(gens[1..], data);
        try e.loopEnd(loop);
    }

    /// A `never`: a function of nothing that the end of every test and property run calls. A
    /// `flows` rule is tier 1's and lowers to nothing.
    fn lowerNever(e: *Emitter, it: Index) Error!void {
        const n = e.node(it);
        const body = e.node(n.rhs);
        if (std.mem.indexOfScalar(Index, e.k.flows, n.rhs) != null) return;
        const quoted = e.text(n.lhs);
        var b: Builder = .{ .name = quoted[1 .. quoted.len - 1], .cname = try e.print("nv{d}", .{e.nevers.items.len}), .contract = true, .exit = e.label() };
        e.b = &b;
        const cl = try e.clause(.never, n.main_token);
        var names: std.ArrayList([]const u8) = .empty;
        if (body.kind == .comprehension) {
            const data = e.tree.extraData(ast.Comprehension, body.lhs);
            const gens = e.tree.span(data.gens_start, data.gens_end);
            for (gens) |g| {
                const tok = e.node(g).main_token;
                if (e.tree.tokens[tok].kind != .underscore) try names.append(e.gpa, e.text(tok));
            }
            var binders: std.ArrayList([]const u8) = .empty;
            try e.neverGenerators(gens, data, cl, &binders);
        } else {
            const v = try e.expr(n.rhs);
            try e.line("if ({s}.as.b) mo_trip({d}, 0, NULL);", .{ v, cl });
        }
        try e.exitLabel();
        try e.finish(&b, "void");
        try e.nevers.append(e.gpa, .{ .cname = b.cname, .clause = cl, .names = names.items });
    }

    fn neverGenerators(e: *Emitter, gens: []const u32, data: ast.Comprehension, cl: u32, binders: *std.ArrayList([]const u8)) Error!void {
        if (gens.len == 0) {
            if (data.guard != 0) {
                const g = try e.expr(data.guard);
                try e.line("if ({s}.as.b) {{", .{g});
                e.b.indent += 1;
            }
            const values = try e.valuesOf(binders.items);
            const v = try e.blockValue(e.tree.span(data.body_start, data.body_end));
            try e.line("if ({s}.as.b) mo_trip({d}, {d}, {s});", .{ v, cl, binders.items.len, values });
            if (data.guard != 0) {
                e.b.indent -= 1;
                try e.line("}}", .{});
            }
            return;
        }
        const g = e.node(gens[0]);
        const loop = try e.loopBegin(g.lhs, g.main_token);
        const named = e.tree.tokens[g.main_token].kind != .underscore;
        if (named) try binders.append(e.gpa, e.b.names.items[e.b.names.items.len - 1].cvar);
        try e.neverGenerators(gens[1..], data, cl, binders);
        if (named) _ = binders.pop();
        try e.loopEnd(loop);
    }

    // ---- processes and supervisors (bytecode.zig lowerProcess, lowerSupervisor)

    /// The parameters in `args`, each bound to a local.
    fn bindArgs(e: *Emitter, r: check.Range) Error![]const []const u8 {
        try e.b.pre.appendSlice(e.gpa, "    (void)cap;\n    (void)args;\n");
        const params = e.k.params[r.start..r.end];
        const cvars = try e.gpa.alloc([]const u8, params.len);
        for (params, cvars, 0..) |p, *cvar, k| {
            cvar.* = try e.bindName(p.name, false);
            e.holds(p.type);
            try e.b.pre.print(e.gpa, "    {s} = args[{d}];\n", .{ cvar.*, k });
        }
        return cvars;
    }

    /// A process: `pi` gives the first state from the parameters; `pu` takes the parameters, the
    /// state, and a message, and gives (reply, state); each `pv` takes the parameters, the state
    /// after, and the state before, and is true when broken.
    fn lowerProcess(e: *Emitter, it: Index) Error!void {
        const n = e.node(it);
        const di = e.k.findDeclAt(it, e.text(n.main_token)) orelse return;
        const d = e.k.decls[di];
        if (d.node != it) return;
        const data = e.tree.extraData(ast.Process, n.lhs);
        const pi = e.process_of[di];
        const params = e.k.params[d.params.start..d.params.end];

        // init: every state field from its `= expr`, or its type's zero value.
        var b: Builder = .{ .name = d.name, .cname = try e.print("pi{d}", .{pi}), .exit = e.label() };
        e.b = &b;
        const cvars = try e.bindArgs(d.params);
        for (params, cvars) |p, cvar| try e.observe(cvar, p.type);
        var fields: std.ArrayList([]const u8) = .empty;
        for (e.k.fields[d.fields.start..d.fields.end]) |f| {
            const init = e.node(f.node).rhs;
            const v = if (init != 0) try e.expr(init) else blk: {
                const tok = e.node(f.node).main_token;
                const cl = try e.addClause(.{ .kind = .other, .text = try e.print("the state field {s} has no zero value; give it = expr", .{f.name}), .at = e.tree.tokens[tok].start, .within = d.name });
                break :blk try e.temp("mo_zero({d}, {d})", .{ try e.desc(f.type), cl });
            };
            try e.observe(v, f.type);
            try e.refineField(f, d.name, v);
            try fields.append(e.gpa, v);
        }
        try e.line("R = mo_record({d}, {d}, {s});", .{ di, fields.items.len, try e.valuesOf(fields.items) });
        try e.exitLabel();
        try e.finish(&b, code_head);
        const init_fn = b.cname;

        // update: `state` is a var for the whole call; the arm's value is the reply.
        b = .{ .name = d.name, .cname = try e.print("pu{d}", .{pi}), .exit = e.label() };
        e.b = &b;
        _ = try e.bindArgs(d.params);
        const state = try e.bindName("state", true);
        try b.pre.print(e.gpa, "    {s} = args[{d}];\n", .{ state, params.len });
        const message = try e.bindName("message", false);
        try b.pre.print(e.gpa, "    {s} = args[{d}];\n", .{ message, params.len + 1 });
        if (d.reads_reply_by) {
            const reply_by = try e.bindName("reply_by", false);
            try b.pre.print(e.gpa, "    {s} = mo_reply_by();\n", .{reply_by});
        }
        const reply = try e.caseLower(e.node(data.update).lhs, true);
        try e.line("R = {s};", .{reply});
        try e.exitLabel();
        try e.line("R = mo_tuple(2, (const MoValue[]){{R, {s}}});", .{state});
        try e.finish(&b, code_head);
        const update_fn = b.cname;

        var invariants: std.ArrayList(InvariantEntry) = .empty;
        var reads_old = false;
        for (e.tree.span(data.invariants_start, data.invariants_end), 0..) |inv, k| {
            b = .{ .name = d.name, .cname = try e.print("pv{d}_{d}", .{ pi, k }), .contract = true, .exit = e.label() };
            e.b = &b;
            _ = try e.bindArgs(d.params);
            const after = try e.bindName("state", false);
            try b.pre.print(e.gpa, "    {s} = args[{d}];\n", .{ after, params.len });
            const before = try e.local();
            try b.pre.print(e.gpa, "    {s} = args[{d}];\n", .{ before, params.len + 1 });
            b.old_state = before;
            const v = try e.expr(e.node(inv).rhs);
            try e.line("R = {s};", .{v});
            try e.exitLabel();
            const cl = try e.clause(.invariant, e.node(inv).main_token);
            try e.finish(&b, code_head);
            reads_old = reads_old or b.reads_old;
            try invariants.append(e.gpa, .{ .cname = b.cname, .clause = cl });
        }

        e.processes.items[pi] = .{
            .name = d.name,
            .decl = di,
            .mailbox = if (data.mailbox == ast.none) 1_000 else @intCast(parseInt(e.text(data.mailbox))),
            .init = init_fn,
            .update = update_fn,
            .invariants = invariants.items,
            .reads_old = reads_old,
        };
    }

    /// A supervisor: for each child line, `sa` takes the supervisor's parameters and gives the
    /// child's arguments as a tuple, and `sw` takes nothing and gives the window.
    fn lowerSupervisor(e: *Emitter, it: Index) Error!void {
        const n = e.node(it);
        const di = e.k.findDeclAt(it, e.text(n.main_token)) orelse return;
        const d = e.k.decls[di];
        if (d.node != it) return;
        const si = e.supervisor_of[di];
        var children: std.ArrayList(ChildEntry) = .empty;
        for (e.spanAt(n.rhs)) |ch| {
            const cn = e.node(ch);
            const data = e.tree.extraData(ast.Child, cn.lhs);
            const pd = e.k.findDeclAt(ch, e.text(cn.main_token)) orelse continue;
            if (e.process_of[pd] == none) continue;
            const k = children.items.len;

            var b: Builder = .{ .name = d.name, .cname = try e.print("sa{d}_{d}", .{ si, k }), .exit = e.label() };
            e.b = &b;
            _ = try e.bindArgs(d.params);
            var args: std.ArrayList([]const u8) = .empty;
            for (e.tree.span(data.args_start, data.args_end)) |a| try args.append(e.gpa, try e.expr(a));
            try e.line("R = mo_tuple({d}, {s});", .{ args.items.len, try e.valuesOf(args.items) });
            try e.exitLabel();
            try e.finish(&b, code_head);

            // The window is read without the supervisor's parameters, so the test runner can
            // supervise a child it starts directly under the same numbers.
            var per: ?[]const u8 = null;
            if (data.per != 0) {
                var w: Builder = .{ .name = d.name, .cname = try e.print("sw{d}_{d}", .{ si, k }), .exit = e.label() };
                e.b = &w;
                try w.pre.appendSlice(e.gpa, "    (void)cap;\n    (void)args;\n");
                const v = try e.expr(data.per);
                try e.line("R = {s};", .{v});
                try e.exitLabel();
                try e.finish(&w, code_head);
                per = w.cname;
            }

            const atom = e.text(data.restart);
            try children.append(e.gpa, .{
                .process = e.process_of[pd],
                .args = b.cname,
                .restart = if (std.mem.eql(u8, atom, ":never")) .never else if (std.mem.eql(u8, atom, ":on_crash")) .on_crash else .always,
                .max_restarts = if (data.max_restarts == ast.none) none else @intCast(parseInt(e.text(data.max_restarts))),
                .per = per,
            });
        }
        e.supervisors.items[si] = .{ .name = d.name, .children = children.items };
    }

    // ---- statements

    fn blockStmts(e: *Emitter, stmts: []const u32) Error!void {
        const mark = e.b.names.items.len;
        for (stmts) |s| try e.stmt(s);
        e.b.names.shrinkRetainingCapacity(mark);
    }

    /// The last statement of a body is its value.
    fn blockValue(e: *Emitter, stmts: []const u32) Error![]const u8 {
        const mark = e.b.names.items.len;
        defer e.b.names.shrinkRetainingCapacity(mark);
        if (stmts.len == 0) return "MO_NONE_V";
        for (stmts[0 .. stmts.len - 1]) |s| try e.stmt(s);
        const last = stmts[stmts.len - 1];
        const n = e.node(last);
        return switch (n.kind) {
            .expr_stmt => try e.expr(n.lhs),
            .if_stmt => try e.ifLower(last, true),
            .case_stmt => try e.caseLower(last, true),
            else => blk: {
                try e.stmt(last);
                break :blk "MO_NONE_V";
            },
        };
    }

    fn stmt(e: *Emitter, s: Index) Error!void {
        const n = e.node(s);
        switch (n.kind) {
            .expr_stmt => _ = try e.expr(n.lhs),
            .binding => {
                const name = e.text(n.main_token);
                e.in_place = .{ .call = n.lhs, .name = name };
                const v = try e.expr(n.lhs);
                e.in_place = .{};
                try e.observe(v, e.typeOf(n.lhs));
                // `x = e` on a var is an assignment; the two are the same text.
                const target = if (e.localVar(name)) |x| x.cvar else try e.bindName(name, false);
                try e.line("{s} = {s};", .{ target, v });
            },
            .var_binding => {
                const v = try e.expr(n.lhs);
                try e.observe(v, e.typeOf(n.lhs));
                try e.line("{s} = {s};", .{ try e.bindName(e.text(n.main_token), true), v });
            },
            .assign => {
                // Read before the value, whose own blocks note theirs.
                const rests = !e.unrested.contains(s);
                const op = e.text(n.main_token);
                var v: []const u8 = undefined;
                if (op.len == 1) {
                    const lhs = e.node(n.lhs);
                    if (lhs.kind == .name_ref or lhs.kind == .member) e.in_place = .{ .call = n.rhs, .path = n.lhs };
                    v = try e.expr(n.rhs);
                    e.in_place = .{};
                } else {
                    const l = try e.expr(n.lhs);
                    const r = try e.expr(n.rhs);
                    v = try e.arith(if (op[0] == '+') "add" else "sub", e.typeOf(n.lhs), l, r, try e.clause(.overflow, e.firstToken(s)));
                }
                try e.assignPlace(n.lhs, v, rests);
            },
            .return_stmt => {
                if (n.rhs != 0) {
                    const c = try e.expr(n.rhs);
                    try e.line("if ({s}.as.b) {{", .{c});
                    e.b.indent += 1;
                }
                const v = try e.expr(n.lhs);
                try e.line("R = {s};", .{v});
                e.b.exit.used = true;
                try e.line("goto X{d};", .{e.b.exit.id});
                if (n.rhs != 0) {
                    e.b.indent -= 1;
                    try e.line("}}", .{});
                }
            },
            .for_stmt => {
                const loop = try e.loopBegin(n.lhs, n.main_token);
                try e.blockStmts(e.spanAt(n.rhs));
                try e.loopEnd(loop);
            },
            .if_stmt => _ = try e.ifLower(s, false),
            .case_stmt => _ = try e.caseLower(s, false),
            .assert_stmt => {
                const x = e.node(n.lhs);
                const cl = try e.clause(.assert, n.main_token);
                if (x.kind == .compare) {
                    const l = try e.expr(x.lhs);
                    const r = try e.expr(x.rhs);
                    try e.line("if (!mo_compare({s}, {s}, {s})) mo_crash_values({d}, 2, (const char *const[]){{\"left\", \"right\"}}, (const MoValue[]){{{s}, {s}}});", .{ compareOp(e.text(x.main_token)), l, r, cl, l, r });
                } else {
                    const v = try e.expr(n.lhs);
                    try e.line("if (!{s}.as.b) mo_crash({d});", .{ v, cl });
                }
            },
            .break_stmt => {
                const loop = &e.b.loops.items[e.b.loops.items.len - 1];
                loop.break_used = true;
                try e.line("goto B{d};", .{loop.id});
            },
            else => _ = try e.expr(s),
        }
    }

    fn compareOp(op: []const u8) []const u8 {
        if (std.mem.eql(u8, op, "==")) return "MO_EQ";
        if (std.mem.eql(u8, op, "!=")) return "MO_NE";
        if (std.mem.eql(u8, op, "<")) return "MO_LT";
        if (std.mem.eql(u8, op, "<=")) return "MO_LE";
        if (std.mem.eql(u8, op, ">")) return "MO_GT";
        return "MO_GE";
    }

    /// Stores `v` into a place: a name, or a field path under one. The whole value the name then
    /// holds is recorded for a never when it `rests` (bytecode.unrestedWrites).
    fn assignPlace(e: *Emitter, i: Index, v: []const u8, rests: bool) Error!void {
        const n = e.node(i);
        switch (n.kind) {
            .name_ref => {
                const target = (try e.resolve(e.text(n.main_token))).?;
                if (rests) try e.observe(v, e.typeOf(i));
                try e.line("{s} = {s};", .{ target.cvar, v });
            },
            .member => {
                const k = e.fieldIndex(e.typeOf(n.lhs), e.text(n.main_token)) orelse return e.halt(i, "", false);
                const d = e.k.decls[e.baseType(e.typeOf(n.lhs)).a];
                try e.refineField(e.k.fields[d.fields.start + k], d.name, v);
                // The old struct is only rebuilt with the field set: not a read that shares it.
                const old = try e.loadPlace(n.lhs);
                const changed = try e.temp("mo_set_field({s}, {d}, {s})", .{ old, k, v });
                try e.assignPlace(n.lhs, changed, rests);
            },
            else => try e.halt(i, "", false),
        }
    }

    const LoopState = struct { list: []const u8, id: u32 };

    fn loopBegin(e: *Emitter, iter: Index, name_tok: u32) Error!LoopState {
        const v = try e.expr(iter);
        const list = try e.local();
        try e.line("{s} = {s};", .{ list, v });
        const l = e.label();
        e.b.has_loops = true;
        try e.line("{{", .{});
        e.b.indent += 1;
        // Each iteration ends at a safe point (vm.zig, collect).
        try e.line("size_t m{d} = mo_mark(), k{d} = 0;", .{ l.id, l.id });
        try e.line("for (uint32_t i{d} = 0; i{d} < {s}.aux; i{d}++) {{", .{ l.id, l.id, list, l.id });
        e.b.indent += 1;
        const elem = try e.temp("{s}.as.xs[i{d}]", .{ list, l.id });
        const iterated = e.baseType(e.typeOf(iter));
        if (iterated.tag == .list) try e.observe(elem, iterated.a);
        const binder = if (e.tree.tokens[name_tok].kind == .underscore) try e.local() else try e.bindName(e.text(name_tok), false);
        try e.line("{s} = {s};", .{ binder, elem });
        try e.b.loops.append(e.gpa, .{ .id = l.id });
        return .{ .list = list, .id = l.id };
    }

    fn loopEnd(e: *Emitter, st: LoopState) Error!void {
        try e.line("ROOTS_{s}(m{d}, k{d});", .{ e.b.cname, st.id, st.id });
        e.b.indent -= 1;
        try e.line("}}", .{});
        e.b.indent -= 1;
        try e.line("}}", .{});
        const loop = e.b.loops.pop().?;
        if (loop.break_used) try e.line("B{d}:;", .{loop.id});
    }

    fn ifLower(e: *Emitter, s: Index, value: bool) Error![]const u8 {
        const n = e.node(s);
        const data = e.tree.extraData(ast.If, n.rhs);
        const has_else = n.kind == .if_expr or data.else_end > data.else_start;
        const result = if (value) try e.temp("MO_NONE_V", .{}) else "MO_NONE_V";
        const mark = e.b.names.items.len;
        const c = try e.expr(n.lhs);
        try e.line("if ({s}.as.b) {{", .{c});
        e.b.indent += 1;
        const then_stmts = e.tree.span(data.then_start, data.then_end);
        if (value and has_else) {
            const v = try e.blockValue(then_stmts);
            try e.line("{s} = {s};", .{ result, v });
        } else try e.blockStmts(then_stmts);
        e.b.names.shrinkRetainingCapacity(mark);
        e.b.indent -= 1;
        const else_stmts = e.tree.span(data.else_start, data.else_end);
        if (else_stmts.len > 0) {
            try e.line("}} else {{", .{});
            e.b.indent += 1;
            if (value and has_else) {
                const v = try e.blockValue(else_stmts);
                try e.line("{s} = {s};", .{ result, v });
            } else try e.blockStmts(else_stmts);
            e.b.indent -= 1;
        }
        try e.line("}}", .{});
        return result;
    }

    fn caseLower(e: *Emitter, s: Index, value: bool) Error![]const u8 {
        const n = e.node(s);
        const result = if (value) try e.temp("MO_NONE_V", .{}) else "MO_NONE_V";
        const v = try e.expr(n.lhs);
        const subject = try e.local();
        try e.line("{s} = {s};", .{ subject, v });
        var end = e.label();
        for (e.spanAt(n.rhs)) |a| {
            const an = e.node(a);
            const data = e.tree.extraData(ast.Arm, an.rhs);
            const mark = e.b.names.items.len;
            var fail = e.label();
            try e.pattern(an.lhs, subject, &fail);
            if (data.guard != 0) {
                const g = try e.expr(data.guard);
                fail.used = true;
                try e.line("if (!{s}.as.b) goto F{d};", .{ g, fail.id });
            }
            const body = e.tree.span(data.body_start, data.body_end);
            if (value) {
                const x = try e.blockValue(body);
                try e.line("{s} = {s};", .{ result, x });
            } else try e.blockStmts(body);
            end.used = true;
            try e.line("goto E{d};", .{end.id});
            if (fail.used) try e.line("F{d}:;", .{fail.id});
            e.b.names.shrinkRetainingCapacity(mark);
        }
        try e.halt(s, "", false);
        if (end.used) try e.line("E{d}:;", .{end.id});
        return result;
    }

    // ---- patterns

    /// Tests the value in `subject` against pattern `p`, binding its names; a value that
    /// does not match jumps to `fail`.
    fn pattern(e: *Emitter, p: Index, subject: []const u8, fail: *Label) Error!void {
        const n = e.node(p);
        switch (n.kind) {
            .pat_wildcard => {},
            .pat_bind => {
                try e.observe(subject, e.typeOf(p));
                try e.line("{s} = {s};", .{ try e.bindName(e.text(n.main_token), false), subject });
            },
            .pat_literal => {
                var value = try e.literal(n.main_token);
                if (n.lhs != 0) switch (value) {
                    .int => |x| value = .{ .int = -x },
                    .float => |x| value = .{ .float = -x },
                    else => {},
                };
                fail.used = true;
                try e.line("if (!mo_equal({s}, {s})) goto F{d};", .{ subject, try e.constant(value), fail.id });
            },
            .pat_variant => {
                try e.variantTest(subject, e.text(n.main_token), fail);
                if (n.lhs != 0) try e.subPattern(subject, 0, n.lhs, fail);
            },
            .pat_record => {
                const subject_t = e.typeOf(p);
                const t = e.baseType(subject_t);
                const is_struct = t.tag == .decl and e.k.decls[t.a].kind == .struct_;
                const name = e.text(n.main_token);
                if (!is_struct) try e.variantTest(subject, name, fail);
                for (e.tree.span(n.lhs, n.rhs)) |pf| {
                    const field = e.node(pf);
                    const k = e.variantFieldIndex(subject_t, name, e.text(field.main_token)) orelse continue;
                    try e.subPattern(subject, k, field.lhs, fail);
                }
            },
            .pat_tuple => for (e.tree.span(n.lhs, n.rhs), 0..) |x, k| try e.subPattern(subject, @intCast(k), x, fail),
            .pat_or => try e.orPattern(n, subject, fail),
            else => unreachable,
        }
    }

    /// `A | B | C`, as bytecode.zig lowers it: each alternative in turn, and a later one
    /// copies its names into the first one's.
    fn orPattern(e: *Emitter, n: ast.Node, subject: []const u8, fail: *Label) Error!void {
        const alts = e.tree.span(n.lhs, n.rhs);
        const first = e.b.names.items.len;
        var first_end = first;
        var matched = e.label();
        for (alts, 0..) |alt, k| {
            const mark = e.b.names.items.len;
            const last = k + 1 == alts.len;
            var alt_fail = e.label();
            try e.pattern(alt, subject, if (last) fail else &alt_fail);
            if (k == 0) {
                first_end = e.b.names.items.len;
            } else {
                for (e.b.names.items[mark..]) |bound| for (e.b.names.items[first..first_end]) |want| {
                    if (std.mem.eql(u8, want.name, bound.name)) try e.line("{s} = {s};", .{ want.cvar, bound.cvar });
                };
                e.b.names.shrinkRetainingCapacity(first_end);
            }
            if (!last) {
                matched.used = true;
                try e.line("goto E{d};", .{matched.id});
                if (alt_fail.used) try e.line("F{d}:;", .{alt_fail.id});
            }
        }
        if (matched.used) try e.line("E{d}:;", .{matched.id});
    }

    fn variantTest(e: *Emitter, subject: []const u8, name: []const u8, fail: *Label) Error!void {
        fail.used = true;
        try e.line("if (!mo_is({s}, {d})) goto F{d};", .{ subject, try e.nameId(name), fail.id });
    }

    fn subPattern(e: *Emitter, subject: []const u8, k: u32, p: Index, fail: *Label) Error!void {
        if (e.node(p).kind == .pat_wildcard) return;
        const inner = try e.local();
        try e.line("{s} = {s}.as.xs[{d}];", .{ inner, subject, k });
        try e.pattern(p, inner, fail);
    }

    fn literal(e: *Emitter, tok: u32) Error!bytecode.Const {
        const raw = e.text(tok);
        return switch (e.tree.tokens[tok].kind) {
            .int => .{ .int = parseInt(raw) },
            .float => .{ .float = std.fmt.parseFloat(f64, raw) catch 0 },
            .string => .{ .string = try e.stringText(tok, e.tree.tokens[tok].start + quoteLen(raw), e.tree.tokens[tok].end - quoteLen(raw)) },
            .kw_true => .{ .bool = true },
            else => .{ .bool = false },
        };
    }

    fn constant(e: *Emitter, c: bytecode.Const) Error![]const u8 {
        return switch (c) {
            .none => "MO_NONE_V",
            .bool => |b| if (b) "mo_bool(true)" else "mo_bool(false)",
            .int => |v| intConst(e.gpa, v),
            .float => |f| e.print("mo_f64_bits(UINT64_C(0x{x}))", .{@as(u64, @bitCast(f))}),
            .string => |s| e.print("mo_str({s}, {d})", .{ try cString(e.gpa, s), s.len }),
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
    /// decoded, as bytecode.zig decodes it.
    fn stringText(e: *Emitter, tok: u32, from: u32, to: u32) Error![]const u8 {
        const src = e.tree.source;
        const t = e.tree.tokens[tok];
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
                try out.append(e.gpa, '\n');
                i = skipIndent(src, i + 1, to, indent);
                continue;
            }
            if (ch == '\\' and i + 1 < to) {
                if (lexer.unicodeEscape(src[0..to], i)) |u| {
                    var utf8: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(u.value, &utf8) catch unreachable;
                    try out.appendSlice(e.gpa, utf8[0..len]);
                    i = @intCast(u.end);
                    continue;
                }
                try out.append(e.gpa, switch (src[i + 1]) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    else => src[i + 1],
                });
                i += 2;
                continue;
            }
            try out.append(e.gpa, ch);
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

    fn fieldIndex(e: *Emitter, t: Id, name: []const u8) ?u32 {
        const b = e.baseType(t);
        if (b.tag != .state and (b.tag != .decl or e.k.decls[b.a].kind != .struct_)) return null;
        const r = e.k.decls[b.a].fields;
        for (e.k.fields[r.start..r.end], 0..) |f, k| if (std.mem.eql(u8, f.name, name)) return @intCast(k);
        return null;
    }

    fn variantFieldIndex(e: *Emitter, t: Id, variant: []const u8, field: []const u8) ?u32 {
        const b = e.baseType(t);
        if (b.tag != .decl and b.tag != .message) return null;
        const d = e.k.decls[b.a];
        if (b.tag == .decl and d.kind == .struct_) return e.fieldIndex(t, field);
        for (e.k.variants[d.variants.start..d.variants.end]) |v| {
            if (!std.mem.eql(u8, v.name, variant)) continue;
            for (e.k.fields[v.fields.start..v.fields.end], 0..) |f, k| if (std.mem.eql(u8, f.name, field)) return @intCast(k);
        }
        return null;
    }

    // ---- expressions: each gives a C expression, usually a temporary

    /// `op` on two values of type `t`: a sized integer kind traps at its own edge, a
    /// contract's integers are unbounded, anything else goes through mo_arith.
    fn arith(e: *Emitter, op: []const u8, t: Id, l: []const u8, r: []const u8, cl: u32) Error![]const u8 {
        const b = e.baseType(t);
        if (b.tag == .int and !e.b.contract) return e.temp("mo_{s}_{s}({s}, {s}, {d})", .{ op, @tagName(@as(types.IntKind, @enumFromInt(b.a))), l, r, cl });
        const code = opCode(op);
        if (b.tag == .int) return e.temp("mo_arith_wide({s}, {s}, {s}, {d})", .{ code, l, r, cl });
        return e.temp("mo_arith({s}, {s}, {s}, {d})", .{ code, l, r, cl });
    }

    fn opCode(op: []const u8) []const u8 {
        if (std.mem.eql(u8, op, "add")) return "MO_OP_ADD";
        if (std.mem.eql(u8, op, "sub")) return "MO_OP_SUB";
        if (std.mem.eql(u8, op, "mul")) return "MO_OP_MUL";
        if (std.mem.eql(u8, op, "div")) return "MO_OP_DIV";
        return "MO_OP_REM";
    }

    fn expr(e: *Emitter, i: Index) Error![]const u8 {
        const n = e.node(i);
        e.holds(e.typeOf(i));
        switch (n.kind) {
            .int_lit => return e.constant(.{ .int = parseInt(e.text(n.main_token)) }),
            .float_lit => return e.constant(.{ .float = std.fmt.parseFloat(f64, e.text(n.main_token)) catch 0 }),
            .true_lit => return "mo_bool(true)",
            .false_lit => return "mo_bool(false)",
            .string_lit => return e.constant(try e.literal(n.main_token)),
            .string_interp => {
                var parts: std.ArrayList([]const u8) = .empty;
                for (e.tree.span(n.lhs, n.rhs)) |part| {
                    const pn = e.node(part);
                    if (pn.kind == .string_part) {
                        try parts.append(e.gpa, try e.constant(.{ .string = try e.stringText(pn.main_token, pn.lhs, pn.rhs) }));
                    } else try parts.append(e.gpa, try e.expr(part));
                }
                return e.temp("mo_concat({d}, {s})", .{ parts.items.len, try e.valuesOf(parts.items) });
            },
            .name_ref => return e.nameRef(i),
            .type_name_ref => {
                const v = try e.temp("mo_variant({d}, 0, NULL)", .{try e.nameId(e.text(n.main_token))});
                try e.observe(v, e.typeOf(i));
                return v;
            },
            .tuple, .list => {
                var elems: std.ArrayList([]const u8) = .empty;
                for (e.tree.span(n.lhs, n.rhs)) |x| {
                    const v = try e.expr(x);
                    // In a list, an element never holds a buffer alone (mo_disown_in).
                    if (n.kind == .list) try e.share(v, e.typeOf(x));
                    try elems.append(e.gpa, v);
                }
                return e.temp("{s}({d}, {s})", .{ if (n.kind == .tuple) "mo_tuple" else "mo_list_of", elems.items.len, try e.valuesOf(elems.items) });
            },
            .not_expr => {
                const v = try e.expr(n.lhs);
                return e.temp("mo_bool(!{s}.as.b)", .{v});
            },
            .and_expr, .implies => {
                // a and b: false unless a; a implies b: true unless a.
                const l = try e.expr(n.lhs);
                const result = try e.temp("mo_bool({s})", .{if (n.kind == .implies) "true" else "false"});
                try e.line("if ({s}.as.b) {{", .{l});
                e.b.indent += 1;
                const r = try e.expr(n.rhs);
                try e.line("{s} = {s};", .{ result, r });
                e.b.indent -= 1;
                try e.line("}}", .{});
                return result;
            },
            .or_expr => {
                if (e.baseType(e.typeOf(n.lhs)).tag == .option) {
                    const l = try e.expr(n.lhs);
                    const opt = try e.local();
                    try e.line("{s} = {s};", .{ opt, l });
                    const result = try e.temp("MO_NONE_V", .{});
                    try e.line("if (mo_is({s}, MO_N_SOME)) {{", .{opt});
                    try e.line("    {s} = {s}.as.xs[0];", .{ result, opt });
                    try e.line("}} else {{", .{});
                    e.b.indent += 1;
                    const r = try e.expr(n.rhs);
                    try e.line("{s} = {s};", .{ result, r });
                    e.b.indent -= 1;
                    try e.line("}}", .{});
                    return result;
                }
                const l = try e.expr(n.lhs);
                const result = try e.temp("mo_bool(true)", .{});
                try e.line("if (!{s}.as.b) {{", .{l});
                e.b.indent += 1;
                const r = try e.expr(n.rhs);
                try e.line("{s} = {s};", .{ result, r });
                e.b.indent -= 1;
                try e.line("}}", .{});
                return result;
            },
            .compare => {
                const l = try e.expr(n.lhs);
                const r = try e.expr(n.rhs);
                return e.compareExpr(compareOp(e.text(n.main_token)), e.typeOf(n.lhs), l, r);
            },
            .is_expr => {
                const v = try e.expr(n.lhs);
                const subject = try e.local();
                try e.line("{s} = {s};", .{ subject, v });
                const result = try e.temp("mo_bool(true)", .{});
                var fail = e.label();
                // Names the pattern binds stay in scope after it (grammar, Session 5).
                try e.pattern(n.rhs, subject, &fail);
                if (fail.used) {
                    const end = e.label();
                    try e.line("goto E{d};", .{end.id});
                    try e.line("F{d}:;", .{fail.id});
                    try e.line("{s} = mo_bool(false);", .{result});
                    try e.line("E{d}:;", .{end.id});
                }
                return result;
            },
            .range => {
                const l = try e.expr(n.lhs);
                const r = try e.expr(n.rhs);
                return e.temp("mo_range({s}, {s})", .{ l, r });
            },
            .add, .mul => {
                const l = try e.expr(n.lhs);
                const r = try e.expr(n.rhs);
                const op: []const u8 = switch (e.text(n.main_token)[0]) {
                    '+' => "add",
                    '-' => "sub",
                    '*' => "mul",
                    '/' => "div",
                    else => "rem",
                };
                return e.arith(op, e.typeOf(i), l, r, try e.clause(.overflow, e.firstToken(i)));
            },
            .negate => {
                const v = try e.expr(n.lhs);
                const cl = try e.clause(.overflow, n.main_token);
                const b = e.baseType(e.typeOf(i));
                if (b.tag == .int and !e.b.contract) return e.temp("mo_neg_{s}({s}, {d})", .{ @tagName(@as(types.IntKind, @enumFromInt(b.a))), v, cl });
                if (b.tag == .int) return e.temp("mo_neg_wide({s}, {d})", .{ v, cl });
                return e.temp("mo_neg({s}, {d})", .{ v, cl });
            },
            .try_expr => {
                const v = try e.expr(n.lhs);
                const value = try e.local();
                try e.line("{s} = {s};", .{ value, v });
                const ok = if (e.baseType(e.typeOf(n.lhs)).tag == .option) "MO_N_SOME" else "MO_N_OK";
                // An Error or a None passes up as it is: re-tagged by name, never converted.
                e.b.exit.used = true;
                try e.line("if (!mo_is({s}, {s})) {{ R = {s}; goto X{d}; }}", .{ value, ok, value, e.b.exit.id });
                return e.temp("{s}.as.xs[0]", .{value});
            },
            .member => {
                if (e.k.callee[i] != .none) return e.callNode(i, n.lhs, &.{});
                const k = e.fieldIndex(e.typeOf(n.lhs), e.text(n.main_token)) orelse {
                    try e.halt(i, try e.print("{s} is a field of a type tier 2 cannot see", .{e.text(n.main_token)}), false);
                    return "MO_NONE_V";
                };
                return e.projection(i, k);
            },
            .member_call => return e.callNode(i, n.lhs, e.spanAt(n.rhs)),
            .tuple_index => return e.projection(i, @intCast(parseInt(e.text(n.main_token)))),
            .call => {
                const callee = e.node(n.lhs);
                const args = e.spanAt(n.rhs);
                if (callee.kind == .type_name_ref) return e.construct(i);
                if (e.k.callee[i] != .none) return e.callNode(i, null, args);
                const f = try e.expr(n.lhs);
                var operands: std.ArrayList([]const u8) = .empty;
                for (args) |a| try operands.append(e.gpa, try e.expr(a));
                return e.temp("mo_invoke({s}, {s})", .{ f, try e.valuesOf(operands.items) });
            },
            .if_expr => return e.ifLower(i, true),
            .case_expr => return e.caseLower(i, true),
            .anon_fn => return e.anonFn(i),
            .old_expr => {
                if (e.old_slots.get(i)) |slot| {
                    try e.share(slot, e.typeOf(i));
                    return e.temp("{s}", .{slot});
                }
                // In an invariant, `state` inside old(...) is the state before the message.
                if (e.b.old_state) |before| {
                    try e.b.names.append(e.gpa, .{ .name = "state", .cvar = before, .mutable = false });
                    defer _ = e.b.names.pop();
                    return e.expr(n.lhs);
                }
                return e.expr(n.lhs);
            },
            .result_ref => {
                try e.share("R", e.typeOf(i));
                return e.temp("R", .{});
            },
            else => {
                try e.halt(i, "", false);
                return "MO_NONE_V";
            },
        }
    }

    /// Field k of the value left of `i`: read from a local, or a field path under one, without
    /// sharing the rest of it, so only the field may now be held twice, unless the read hands
    /// it on (moves.zig; bytecode.zig, projection).
    fn projection(e: *Emitter, i: Index, k: u32) Error![]const u8 {
        const chain = try e.loadChain(e.node(i).lhs);
        const v = try e.temp("{s}.as.xs[{d}]", .{ chain.value, k });
        if (chain.rooted and !e.moving(i)) try e.share(v, e.typeOf(i));
        return v;
    }

    const Chain = struct { value: []const u8, rooted: bool };

    /// A local, or a field or tuple path under one, read without sharing it (rooted); any other
    /// expression as it is.
    fn loadChain(e: *Emitter, i: Index) Error!Chain {
        const n = e.node(i);
        switch (n.kind) {
            .name_ref => if (try e.resolve(e.text(n.main_token))) |v| return .{ .value = v.cvar, .rooted = true },
            .member => if (e.k.callee[i] == .none) {
                if (e.fieldIndex(e.typeOf(n.lhs), e.text(n.main_token))) |k| {
                    const inner = try e.loadChain(n.lhs);
                    return .{ .value = try e.temp("{s}.as.xs[{d}]", .{ inner.value, k }), .rooted = inner.rooted };
                }
            },
            .tuple_index => {
                const inner = try e.loadChain(n.lhs);
                return .{ .value = try e.temp("{s}.as.xs[{d}]", .{ inner.value, parseInt(e.text(n.main_token)) }), .rooted = inner.rooted };
            },
            else => {},
        }
        return .{ .value = try e.expr(i), .rooted = false };
    }

    /// A comparison of two values of type `t`: a sized integer or a float compares its
    /// payload, a contract's integers compare unbounded, anything else goes through mo_compare.
    fn compareExpr(e: *Emitter, op: []const u8, t: Id, l: []const u8, r: []const u8) Error![]const u8 {
        const b = e.baseType(t);
        const c = opSymbol(op);
        if (b.tag == .int and !e.b.contract) {
            const kind: types.IntKind = @enumFromInt(b.a);
            const field = switch (kind) {
                .i8, .i16, .i32, .i64 => "i",
                else => "u",
            };
            return e.temp("mo_bool({s}.as.{s} {s} {s}.as.{s})", .{ l, field, c, r, field });
        }
        if (b.tag == .int) return e.temp("mo_bool(mo_wide({s}) {s} mo_wide({s}))", .{ l, c, r });
        if (b.tag == .float) return e.temp("mo_bool({s}.as.f {s} {s}.as.f)", .{ l, c, r });
        return e.temp("mo_bool(mo_compare({s}, {s}, {s}))", .{ op, l, r });
    }

    fn opSymbol(op: []const u8) []const u8 {
        if (std.mem.eql(u8, op, "MO_EQ")) return "==";
        if (std.mem.eql(u8, op, "MO_NE")) return "!=";
        if (std.mem.eql(u8, op, "MO_LT")) return "<";
        if (std.mem.eql(u8, op, "MO_LE")) return "<=";
        if (std.mem.eql(u8, op, "MO_GT")) return ">";
        return ">=";
    }

    fn nameRef(e: *Emitter, i: Index) Error![]const u8 {
        const n = e.node(i);
        const name = e.text(n.main_token);
        if (try e.resolve(name)) |v| {
            // A read that does not hand the value on gives up its claim on its buffers (load_shared).
            if (e.owns(e.typeOf(i)) and !e.moving(i)) try e.line("mo_disown_in({s});", .{v.cvar});
            return e.temp("{s}", .{v.cvar});
        }
        switch (e.k.callee[i]) {
            // A bare name inside `where` is called on the refined value.
            .prelude => |row| return e.preludeCall(i, row, null, &.{}),
            else => {},
        }
        if (e.k.findFnAt(i, name)) |si| return e.fnValue(si);
        if (prelude.findValue(name) != null) return e.temp("mo_r_Time_fixture(NULL, MO_KIND_NONE)", .{});
        try e.halt(i, "", false);
        return "MO_NONE_V";
    }

    /// A named function as a value: a closure over a wrapper with the uniform signature.
    fn fnValue(e: *Emitter, si: u32) Error![]const u8 {
        try e.wrappers.put(e.gpa, si, {});
        return e.temp("mo_closure(w{d}, {d}, 0, NULL)", .{ si, si });
    }

    fn callNode(e: *Emitter, i: Index, recv: ?Index, args: []const u32) Error![]const u8 {
        switch (e.k.callee[i]) {
            .user => |si| return e.userCall(si, recv, args),
            .prelude => |row| return e.preludeCall(i, row, recv, args),
            .none => {
                try e.halt(i, "", false);
                return "MO_NONE_V";
            },
        }
    }

    fn userCall(e: *Emitter, si: u32, recv: ?Index, args: []const u32) Error![]const u8 {
        const s = e.k.sigs[si];
        var arg_nodes: std.ArrayList(Index) = .empty;
        if (recv) |r| try arg_nodes.append(e.gpa, r);
        for (args) |a| if (e.node(a).kind != .named_arg) try arg_nodes.append(e.gpa, a);
        const ps = e.k.params[s.params.start..s.params.end];
        var operands: std.ArrayList([]const u8) = .empty;
        for (arg_nodes.items, 0..) |a, j| {
            const v = try e.expr(a);
            // An inout argument is passed as a place the callee writes back.
            try operands.append(e.gpa, if (j < ps.len and ps[j].inout) try e.temp("{s}", .{v}) else v);
        }
        var call: std.ArrayList(u8) = .empty;
        if (s.kind == .trait) {
            try e.dispatchers.put(e.gpa, si, {});
            try call.print(e.gpa, "d{d}(", .{si});
        } else try call.print(e.gpa, "f{d}(", .{si});
        for (operands.items, 0..) |o, j| {
            if (j > 0) try call.appendSlice(e.gpa, ", ");
            if (j < ps.len and ps[j].inout) try call.append(e.gpa, '&');
            try call.appendSlice(e.gpa, o);
        }
        try call.append(e.gpa, ')');
        const result = try e.temp("{s}", .{call.items});
        // Each inout argument takes the parameter's final value, last one first.
        var j = @min(ps.len, arg_nodes.items.len);
        while (j > 0) {
            j -= 1;
            if (ps[j].inout) try e.assignPlace(arg_nodes.items[j], operands.items[j], true);
        }
        return result;
    }

    /// The runtime function of a prelude row (mo_rt.h).
    fn rowName(e: *Emitter, row: prelude.Fn) Error![]const u8 {
        const head = recvHead(row.recv);
        var name: std.ArrayList(u8) = .empty;
        for (row.name) |ch| {
            if (ch == '?') try name.appendSlice(e.gpa, "_q") else try name.append(e.gpa, ch);
        }
        const suffix = if (std.mem.eql(u8, head, "Fs") and std.mem.eql(u8, row.name, "fixture") and row.named.len == 1)
            "_delay"
        else if (std.mem.eql(u8, head, "Charge") and std.mem.eql(u8, row.name, "fixture") and row.named.len == 2)
            "_at"
        else
            "";
        if (head.len == 0) return e.print("mo_r_{s}", .{name.items});
        return e.print("mo_r_{s}_{s}{s}", .{ head, name.items, suffix });
    }

    fn preludeCall(e: *Emitter, i: Index, row_index: u32, recv: ?Index, args: []const u32) Error![]const u8 {
        const row = prelude.fns[row_index];
        // Processes (bytecode.zig spawn, start_supervisor, send, ask).
        if (std.mem.eql(u8, row.recv, "Process")) {
            for (args) |a| if (e.node(a).kind == .named_arg) {
                try e.halt(i, "", false);
                return "MO_NONE_V";
            };
            var operands: std.ArrayList([]const u8) = .empty;
            for (args) |a| {
                const v = try e.expr(a);
                try e.share(v, e.typeOf(a));
                try operands.append(e.gpa, v);
            }
            return e.temp("mo_spawn({d}, {d}, {s})", .{ e.process_of[e.baseType(e.typeOf(i)).a], operands.items.len, try e.valuesOf(operands.items) });
        }
        if (std.mem.eql(u8, row.recv, "Supervisor")) {
            const d = e.k.findDeclAt(i, e.text(e.node(recv.?).main_token)) orelse {
                try e.halt(i, "", false);
                return "MO_NONE_V";
            };
            var operands: std.ArrayList([]const u8) = .empty;
            for (args) |a| {
                const v = try e.expr(a);
                try e.share(v, e.typeOf(a));
                try operands.append(e.gpa, v);
            }
            return e.temp("mo_start_supervisor({d}, {d}, {s})", .{ e.supervisor_of[d], operands.items.len, try e.valuesOf(operands.items) });
        }
        if (std.mem.startsWith(u8, row.recv, "Handle")) {
            const h = try e.expr(recv.?);
            var message: []const u8 = "MO_NONE_V";
            // A message outlives the send: the process that takes it is a second holder.
            for (args) |a| if (e.node(a).kind != .named_arg) {
                message = try e.expr(a);
                try e.share(message, e.typeOf(a));
            };
            if (std.mem.eql(u8, row.name, "send")) {
                for (args) |a| {
                    const an = e.node(a);
                    if (an.kind != .named_arg or !std.mem.eql(u8, e.text(an.main_token), "delay")) continue;
                    // Delivered no earlier than the delay after the sending update ends (step 24).
                    return e.temp("mo_send_later({s}, {s}, {s})", .{ h, message, try e.expr(an.lhs) });
                }
                return e.temp("mo_send({s}, {s})", .{ h, message });
            }
            var within: []const u8 = "MO_NONE_V";
            for (args) |a| {
                const an = e.node(a);
                if (an.kind == .named_arg and std.mem.eql(u8, e.text(an.main_token), "within")) within = try e.withinArg(an.lhs);
            }
            return e.temp("mo_ask({s}, {s}, {s})", .{ h, message, within });
        }
        if (row.only == .never) {
            // `T.all`: the distinct values of T the run held.
            const list = e.k.pool.get(e.typeOf(i));
            const kept = if (list.tag == .list) blk: {
                const r = e.k.pool.resolve(list.a);
                break :blk if (r < e.recorded.recorded_as.len) e.recorded.recorded_as[r] else none;
            } else none;
            if (!std.mem.eql(u8, row.recv, "Type") or kept == none) {
                try e.halt(i, "", false);
                return "MO_NONE_V";
            }
            return e.temp("mo_all({d})", .{kept});
        }
        var operands: std.ArrayList([]const u8) = .empty;
        var kind: []const u8 = "MO_KIND_NONE";
        // A free row (min_of) has no receiver.
        if (!row.on_type and row.recv.len > 0) {
            if (recv) |r| {
                if (e.inPlace(i, r, row) or (bytecode.writesInPlace(row) and e.moving(r))) {
                    try operands.append(e.gpa, try e.loadPlace(r));
                    kind = "MO_KIND_UNIQUE";
                } else {
                    // A row that only looks at a map or set shares none of its buffer.
                    try operands.append(e.gpa, if (looksOnly(row)) try e.loadPlace(r) else try e.expr(r));
                    // A list's row (`sum`) checks against its element's integer type.
                    const rt = e.baseType(e.typeOf(r));
                    const k = if (rt.tag == .list) e.intKind(rt.a) else e.intKind(e.typeOf(r));
                    if (k != none) kind = try e.print("{d}", .{k});
                }
            } else {
                // A bare name inside `where`: the refined value.
                try operands.append(e.gpa, "L0");
            }
        }
        var position: usize = 0;
        for (args) |a| if (e.node(a).kind != .named_arg) {
            const v = try e.expr(a);
            // A row keeps what it is given, except the accumulator it hands back.
            if (!bytecode.accumulates(row, position)) try e.share(v, e.typeOf(a));
            try operands.append(e.gpa, v);
            position += 1;
        };
        // Json.encode spells its argument by the argument's checked type.
        if (row.on_type and std.mem.eql(u8, row.recv, "Json") and std.mem.eql(u8, row.name, "encode")) {
            for (args) |a| if (e.node(a).kind != .named_arg) {
                kind = try e.print("{d}", .{try e.desc(e.typeOf(a))});
                break;
            };
        }
        for (row.named) |f| {
            for (args) |a| {
                const an = e.node(a);
                if (an.kind != .named_arg or !std.mem.eql(u8, e.text(an.main_token), f.name)) continue;
                const v = try e.expr(an.lhs);
                try e.share(v, e.typeOf(an.lhs));
                try operands.append(e.gpa, v);
            }
        }
        if (row.can_wait) {
            // Timed for the events (events.zig, step 23), a Timeout at once included.
            const call_label = try e.print("\"{s}.{s}\"", .{ recvHead(row.recv), row.name });
            const since = try e.temp("mo_wait_begin({s})", .{call_label});
            const within = for (args) |a| {
                const an = e.node(a);
                if (an.kind == .named_arg and std.mem.eql(u8, e.text(an.main_token), "within")) break an.lhs;
            } else 0;
            if (within != 0) {
                // A deadline with nothing left: Timeout at once, and the call is not made (step 22).
                const w = try e.withinArg(within);
                try operands.append(e.gpa, w);
                return e.temp("mo_waited({s}, {s}, {s}.as.i < 0 ? mo_timed_out_now() : {s}({s}, {s}))", .{ call_label, since, w, try e.rowName(row), try e.valuesOf(operands.items), kind });
            }
            try operands.append(e.gpa, "MO_NONE_V");
            return e.temp("mo_waited({s}, {s}, {s}({s}, {s}))", .{ call_label, since, try e.rowName(row), try e.valuesOf(operands.items), kind });
        }
        return e.temp("{s}({s}, {s})", .{ try e.rowName(row), try e.valuesOf(operands.items), kind });
    }

    /// A `within:` argument in a temporary: a Duration as it is, and a Deadline as the Duration
    /// that remains of it (step 22).
    fn withinArg(e: *Emitter, arg: Index) Error![]const u8 {
        const v = try e.expr(arg);
        if (e.k.pool.get(e.k.pool.base(e.typeOf(arg))).tag == .deadline) return e.temp("mo_deadline_left({s})", .{v});
        return e.temp("{s}", .{v});
    }

    /// Whether call `i` is the right side of `m = m.set(k, v)` (or update, remove, add) on
    /// a var map or set, or on a field path under a var, and `r` reads that place.
    fn inPlace(e: *Emitter, i: Index, r: Index, row: prelude.Fn) bool {
        if (i != e.in_place.call) return false;
        const map_row = std.mem.startsWith(u8, row.recv, "Map(") and (std.mem.eql(u8, row.name, "set") or std.mem.eql(u8, row.name, "update") or std.mem.eql(u8, row.name, "remove"));
        const set_row = std.mem.startsWith(u8, row.recv, "Set(") and (std.mem.eql(u8, row.name, "add") or std.mem.eql(u8, row.name, "remove"));
        if (!map_row and !set_row) return false;
        if (e.in_place.path != 0) return e.samePlace(r, e.in_place.path);
        const rn = e.node(r);
        return rn.kind == .name_ref and std.mem.eql(u8, e.text(rn.main_token), e.in_place.name) and e.localVar(e.in_place.name) != null;
    }

    fn samePlace(e: *Emitter, a: Index, b: Index) bool {
        const an = e.node(a);
        const bn = e.node(b);
        if (an.kind != bn.kind or !std.mem.eql(u8, e.text(an.main_token), e.text(bn.main_token))) return false;
        return switch (an.kind) {
            .name_ref => e.localVar(e.text(an.main_token)) != null,
            .member => e.k.callee[a] == .none and e.k.callee[b] == .none and e.samePlace(an.lhs, bn.lhs),
            else => false,
        };
    }

    /// A place's value, a name or a field path under one, read without giving up a var's
    /// claim on the buffers it holds; any other expression as it is.
    fn loadPlace(e: *Emitter, i: Index) Error![]const u8 {
        const n = e.node(i);
        switch (n.kind) {
            .name_ref => if (try e.resolve(e.text(n.main_token))) |v| return e.temp("{s}", .{v.cvar}),
            .member => if (e.k.callee[i] == .none) {
                if (e.fieldIndex(e.typeOf(n.lhs), e.text(n.main_token))) |k| {
                    const obj = try e.loadPlace(n.lhs);
                    return e.temp("{s}.as.xs[{d}]", .{ obj, k });
                }
            },
            else => {},
        }
        return e.expr(i);
    }

    fn looksOnly(row: prelude.Fn) bool {
        const on_map = std.mem.startsWith(u8, row.recv, "Map(") or std.mem.startsWith(u8, row.recv, "Set(");
        if (!on_map) return false;
        for ([_][]const u8{ "size", "get", "has?", "keys", "values", "entries", "to_list" }) |name| {
            if (std.mem.eql(u8, row.name, name)) return true;
        }
        return false;
    }

    fn construct(e: *Emitter, i: Index) Error![]const u8 {
        const n = e.node(i);
        const name = e.text(e.node(n.lhs).main_token);
        const args = e.spanAt(n.rhs);
        for ([_][]const u8{ "Some", "Ok", "Error" }) |builtin| if (std.mem.eql(u8, name, builtin)) {
            const x = try e.expr(args[0]);
            const v = try e.temp("mo_variant({d}, 1, {s})", .{ try e.nameId(name), try e.valuesOf(&.{x}) });
            try e.observe(v, e.typeOf(i));
            return v;
        };
        const t = e.baseType(e.typeOf(i));
        if (t.tag != .decl and t.tag != .message) {
            try e.halt(i, "", false);
            return "MO_NONE_V";
        }
        const d = e.k.decls[t.a];
        const is_struct = t.tag == .decl and d.kind == .struct_;
        const fields: check.Range = if (is_struct) d.fields else for (e.k.variants[d.variants.start..d.variants.end]) |v| {
            if (std.mem.eql(u8, v.name, name)) break v.fields;
        } else {
            try e.halt(i, "", false);
            return "MO_NONE_V";
        };
        var operands: std.ArrayList([]const u8) = .empty;
        for (e.k.fields[fields.start..fields.end]) |f| {
            const arg = for (args) |a| {
                const an = e.node(a);
                if (an.kind == .named_arg and std.mem.eql(u8, e.text(an.main_token), f.name)) break an.lhs;
            } else 0;
            if (arg == 0 and f.optional) {
                // A stdlib struct's field left out is empty (prelude.zig).
                const empty = if (e.k.pool.get(e.k.pool.base(f.type)).tag == .map) "mo_r_Map_new(NULL, MO_KIND_NONE)" else "mo_str(\"\", 0)";
                try operands.append(e.gpa, try e.temp("{s}", .{empty}));
            } else if (arg == 0) {
                try operands.append(e.gpa, "MO_NONE_V");
            } else {
                const v = try e.expr(arg);
                try e.refineField(f, d.name, v);
                try operands.append(e.gpa, v);
            }
        }
        const v = if (is_struct)
            try e.temp("mo_record({d}, {d}, {s})", .{ t.a, operands.items.len, try e.valuesOf(operands.items) })
        else
            try e.temp("mo_variant({d}, {d}, {s})", .{ try e.nameId(name), operands.items.len, try e.valuesOf(operands.items) });
        try e.observe(v, e.typeOf(i));
        return v;
    }

    fn anonFn(e: *Emitter, i: Index) Error![]const u8 {
        const data = e.tree.extraData(ast.AnonFn, e.node(i).lhs);
        const parent = e.b;
        const id = e.anons;
        e.anons += 1;
        var b: Builder = .{ .parent = parent, .name = parent.name, .cname = try e.print("a{d}", .{id}), .exit = e.label() };
        e.b = &b;
        for (e.tree.span(data.params_start, data.params_end), 0..) |tok, k| {
            const cvar = try e.bindName(e.text(tok), false);
            try b.params.append(e.gpa, .{ .name = e.text(tok), .cvar = cvar, .mutable = false });
            try b.pre.print(e.gpa, "    {s} = args[{d}];\n", .{ cvar, k });
        }
        try b.pre.appendSlice(e.gpa, "    (void)cap;\n    (void)args;\n");
        const ft = e.k.pool.get(e.typeOf(i));
        if (ft.tag == .func) for (e.k.pool.elems(ft), 0..) |t, k| {
            if (k < b.params.items.len) try e.observe(b.params.items[k].cvar, t);
        };
        const v = try e.blockValue(e.tree.span(data.body_start, data.body_end));
        try e.line("R = {s};", .{v});
        try e.exitLabel();
        try e.finish(&b, "const MoValue *cap, const MoValue *args");
        e.b = parent;
        var outer: std.ArrayList([]const u8) = .empty;
        // A captured value is a second holder while the function runs.
        for (b.captures.items) |c| {
            try e.line("mo_disown_in({s});", .{c.outer});
            try outer.append(e.gpa, c.outer);
        }
        return e.temp("mo_closure({s}, {d}, {d}, {s})", .{ b.cname, @as(u64, e.k.sigs.len) + id, outer.items.len, try e.valuesOf(outer.items) });
    }

    // ---- the translation unit

    fn assemble(e: *Emitter) Error![]const u8 {
        const gpa = e.gpa;
        const k = e.k;
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(gpa, "/* Written by mo build (toolchain/src/emit_c.zig); links toolchain/runtime/mo_rt.c. */\n#include \"mo_rt.h\"\n\n");

        // Trait dispatch and function values.
        var extra: std.ArrayList(u8) = .empty;
        var dispatchers = e.dispatchers.keyIterator();
        while (dispatchers.next()) |si_ptr| {
            const si = si_ptr.*;
            const s = k.sigs[si];
            const ps = k.params[s.params.start..s.params.end];
            var head: std.ArrayList(u8) = .empty;
            var call: std.ArrayList(u8) = .empty;
            for (ps, 0..) |p, j| {
                if (j > 0) {
                    try head.appendSlice(gpa, ", ");
                    try call.appendSlice(gpa, ", ");
                }
                try head.print(gpa, "{s} a{d}", .{ if (p.inout) "MoValue *" else "MoValue", j });
                try call.print(gpa, "a{d}", .{j});
            }
            if (ps.len == 0) try head.appendSlice(gpa, "void");
            try e.protos.print(gpa, "MO_U static MoValue d{d}({s});\n", .{ si, head.items });
            try extra.print(gpa, "MO_U static MoValue d{d}({s}) {{\n", .{ si, head.items });
            const receiver = if (ps.len > 0 and ps[0].inout) "(*a0)" else "a0";
            if (ps.len > 0) {
                try extra.print(gpa, "    if ({s}.tag == MO_RECORD) {{\n        switch ({s}.aux) {{\n", .{ receiver, receiver });
                var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
                for (k.impls) |im| {
                    if (im.trait != s.owner) continue;
                    const t = k.pool.get(k.pool.base(im.for_type));
                    if (t.tag != .decl or seen.contains(t.a)) continue;
                    for (im.sigs.start..im.sigs.end) |isi| {
                        if (!std.mem.eql(u8, k.sigs[isi].name, s.name)) continue;
                        try seen.put(gpa, t.a, {});
                        try extra.print(gpa, "        case {d}: return f{d}({s});\n", .{ t.a, isi, call.items });
                        break;
                    }
                }
                try extra.appendSlice(gpa, "        default: break;\n        }\n    }\n");
                try extra.print(gpa, "    mo_no_impl({s}, {s});\n}}\n", .{ try cString(gpa, s.name), receiver });
            } else {
                try extra.print(gpa, "    mo_no_impl({s}, MO_NONE_V);\n}}\n", .{try cString(gpa, s.name)});
            }
        }
        var wrappers = e.wrappers.keyIterator();
        while (wrappers.next()) |si_ptr| {
            const si = si_ptr.*;
            const s = k.sigs[si];
            const ps = k.params[s.params.start..s.params.end];
            try e.protos.print(gpa, "MO_U static MoValue w{d}(const MoValue *cap, const MoValue *args);\n", .{si});
            try extra.print(gpa, "MO_U static MoValue w{d}(const MoValue *cap, const MoValue *args) {{\n    (void)cap;\n    (void)args;\n", .{si});
            for (ps, 0..) |p, j| if (p.inout) try extra.print(gpa, "    MoValue io{d} = args[{d}];\n", .{ j, j });
            try extra.print(gpa, "    return f{d}(", .{si});
            for (ps, 0..) |p, j| {
                if (j > 0) try extra.appendSlice(gpa, ", ");
                if (p.inout) try extra.print(gpa, "&io{d}", .{j}) else try extra.print(gpa, "args[{d}]", .{j});
            }
            try extra.appendSlice(gpa, ");\n}\n");
        }

        // The tables: decls, variants, and the types they name, then clauses, tests, and nevers.
        var tables: std.ArrayList(u8) = .empty;
        var decl_rows: std.ArrayList(u8) = .empty;
        for (k.decls, 0..) |d, di| {
            try tables.print(gpa, "static const MoField decl_fields_{d}[] = {{", .{di});
            for (k.fields[d.fields.start..d.fields.end]) |f| try tables.print(gpa, "{{{s}, {d}}}, ", .{ try cString(gpa, f.name), try e.desc(f.type) });
            try tables.appendSlice(gpa, "{NULL, 0}};\n");
            const refs: []const Refinement = if (d.kind == .alias and d.node != 0) try e.refinementsOf(e.node(d.node).lhs, d.name) else &.{};
            try tables.print(gpa, "static const MoRefineFn decl_refines_{d}[] = {{", .{di});
            for (refs) |r| try tables.print(gpa, "{s}, ", .{r.cname});
            try tables.appendSlice(gpa, "NULL};\n");
            // What any(T) of a refined alias generates from once its base type's candidates
            // pass none, and the clause it crashes with when none of its candidates pass.
            var bounds: bytecode.Bounds = .{};
            for (refs) |r| bounds.meet(r.bounds);
            var range: ?bytecode.Range = null;
            var none_admitted: u32 = std.math.maxInt(u32);
            if (refs.len > 0) {
                var t = k.pool.get(k.pool.resolve(d.type));
                while (t.tag == .alias) t = k.pool.get(k.pool.resolve(t.b));
                if (t.tag == .int) range = bounds.within(@enumFromInt(t.a));
                none_admitted = try e.addClause(.{ .kind = .other, .text = try contracts.noneAdmitted(gpa, d.name), .at = e.clauses.items[refs[0].clause].at, .within = "" });
            }
            const r = range orelse bytecode.Range{ .lo = 0, .hi = 0 };
            try decl_rows.print(gpa, "    {{{s}, {d}, {d}, decl_fields_{d}, {d}, {d}, {d}, decl_refines_{d}, {s}, {s}, {s}, {d}}},\n", .{ try cString(gpa, d.name), @intFromEnum(d.kind), d.fields.len(), di, d.variants.start, d.variants.len(), refs.len, di, if (range != null) "true" else "false", try int128(gpa, r.lo), try int128(gpa, r.hi), none_admitted });
        }
        var variant_rows: std.ArrayList(u8) = .empty;
        for (k.variants, 0..) |v, vi| {
            try tables.print(gpa, "static const MoField variant_fields_{d}[] = {{", .{vi});
            for (k.fields[v.fields.start..v.fields.end]) |f| try tables.print(gpa, "{{{s}, {d}}}, ", .{ try cString(gpa, f.name), try e.desc(f.type) });
            try tables.appendSlice(gpa, "{NULL, 0}};\n");
            try variant_rows.print(gpa, "    {{{d}, {d}, variant_fields_{d}}},\n", .{ try e.nameId(v.name), v.fields.len(), vi });
        }
        try tables.print(gpa, "const MoDecl mo_decls[] = {{\n{s}    {{NULL, 0, 0, NULL, 0, 0, 0, NULL, false, 0, 0, 0}}\n}};\n", .{decl_rows.items});
        try tables.print(gpa, "const MoVariantDef mo_variants[] = {{\n{s}    {{0, 0, NULL}}\n}};\nconst uint32_t mo_nvariants = {d};\n", .{ variant_rows.items, k.variants.len });
        // Nothing past this point names a type the descriptors do not have yet.
        for (e.descs.items, 0..) |d, di| {
            if (d.items.len == 0) continue;
            try tables.print(gpa, "static const uint32_t type_items_{d}[] = {{", .{di});
            for (d.items) |x| try tables.print(gpa, "{d}, ", .{x});
            try tables.appendSlice(gpa, "0};\n");
        }
        try tables.appendSlice(gpa, "const MoType mo_types[] = {\n");
        var recorded: u32 = 0;
        for (e.descs.items, 0..) |d, di| {
            if (d.recorded != none) recorded = @max(recorded, d.recorded + 1);
            const items_name = if (d.items.len > 0) try e.print("type_items_{d}", .{di}) else "NULL";
            try tables.print(gpa, "    {{{d}, {s}, {s}, {s}, {d}, {d}, {s}}},\n", .{ @intFromEnum(d.tag), try cString(gpa, d.name), if (d.recorded == none) "UINT32_MAX" else try e.print("{d}", .{d.recorded}), if (d.may_hold) "true" else "false", d.a, d.b, items_name });
        }
        try tables.appendSlice(gpa, "    {0, NULL, UINT32_MAX, false, 0, 0, NULL}\n};\n");
        try tables.print(gpa, "const uint32_t mo_nrecorded = {d};\n", .{recorded});

        try tables.appendSlice(gpa, "const char *const mo_names[] = {");
        for (e.names.items) |n| try tables.print(gpa, "{s}, ", .{try cString(gpa, n)});
        try tables.print(gpa, "NULL}};\nconst uint32_t mo_nnames = {d};\n", .{e.names.items.len});

        try tables.appendSlice(gpa, "const MoClause mo_clauses[] = {\n");
        for (e.clauses.items) |c| {
            var where: []const u8 = "NULL";
            if (c.at != 0) {
                const loc = diag.locate(e.prog.files, c.at);
                const pos = diag.position(loc.source, loc.at);
                where = try cString(gpa, try e.print("{s}:{d}:{d}", .{ loc.path, pos.line, pos.column }));
            }
            try tables.print(gpa, "    {{{d}, {s}, {s}, {s}, {s}}},\n", .{ @intFromEnum(c.kind), if (c.skip) "true" else "false", try cString(gpa, c.text), try cString(gpa, c.within), where });
        }
        try tables.appendSlice(gpa, "    {0, false, NULL, NULL, NULL}\n};\n");

        try tables.appendSlice(gpa, "const MoTest mo_tests[] = {\n");
        for (e.tests.items) |t| {
            const kind = switch (t.kind) {
                .test_ => "MO_TEST",
                .rejects => "MO_TEST_REJECTS",
                .property => "MO_PROPERTY",
            };
            try tables.print(gpa, "    {{{s}, {s}, {s}}},\n", .{ kind, try cString(gpa, t.name), t.cname });
        }
        try tables.print(gpa, "    {{0, NULL, NULL}}\n}};\nconst uint32_t mo_ntests = {d};\n", .{e.tests.items.len});

        for (e.nevers.items, 0..) |nv, ni| {
            try tables.print(gpa, "static const char *const never_names_{d}[] = {{", .{ni});
            for (nv.names) |n| try tables.print(gpa, "{s}, ", .{try cString(gpa, n)});
            try tables.appendSlice(gpa, "NULL};\n");
        }
        try tables.appendSlice(gpa, "const MoNever mo_nevers[] = {\n");
        for (e.nevers.items, 0..) |nv, ni| try tables.print(gpa, "    {{{s}, {d}, {d}, never_names_{d}}},\n", .{ nv.cname, nv.clause, nv.names.len, ni });
        try tables.print(gpa, "    {{NULL, 0, 0, NULL}}\n}};\nconst uint32_t mo_nnevers = {d};\n", .{e.nevers.items.len});

        // Processes and supervisors, in bytecode.zig's order: the scheduler's tables.
        for (e.processes.items, 0..) |p, pi| {
            try tables.print(gpa, "static const MoInvariant process_invariants_{d}[] = {{", .{pi});
            for (p.invariants) |inv| try tables.print(gpa, "{{{s}, {d}}}, ", .{ inv.cname, inv.clause });
            try tables.appendSlice(gpa, "{NULL, 0}};\n");
        }
        try tables.appendSlice(gpa, "const MoProcess mo_processes[] = {\n");
        for (e.processes.items, 0..) |p, pi| {
            try tables.print(gpa, "    {{{s}, {d}, {d}, {s}, {s}, {d}, process_invariants_{d}, {s}}},\n", .{ try cString(gpa, p.name), p.decl, p.mailbox, p.init, p.update, p.invariants.len, pi, if (p.reads_old) "true" else "false" });
        }
        try tables.print(gpa, "    {{NULL, 0, 0, NULL, NULL, 0, NULL, false}}\n}};\nconst uint32_t mo_nprocesses = {d};\n", .{e.processes.items.len});
        for (e.supervisors.items, 0..) |sup, si| {
            try tables.print(gpa, "static const MoChild supervisor_children_{d}[] = {{", .{si});
            for (sup.children) |c| {
                const max = if (c.max_restarts == none) "UINT32_MAX" else try e.print("{d}", .{c.max_restarts});
                try tables.print(gpa, "{{{d}, {s}, {d}, {s}, {s}}}, ", .{ c.process, c.args, @intFromEnum(c.restart), max, c.per orelse "NULL" });
            }
            try tables.appendSlice(gpa, "{0, NULL, 0, 0, NULL}};\n");
        }
        try tables.appendSlice(gpa, "const MoSupervisor mo_supervisors[] = {\n");
        for (e.supervisors.items, 0..) |sup, si| try tables.print(gpa, "    {{{s}, {d}, supervisor_children_{d}}},\n", .{ try cString(gpa, sup.name), sup.children.len, si });
        try tables.print(gpa, "    {{NULL, 0, NULL}}\n}};\nconst uint32_t mo_nsupervisors = {d};\n", .{e.supervisors.items.len});

        const charge = k.findDecl("Charge");
        try tables.print(gpa, "const uint32_t mo_charge_decl = {s};\n", .{if (charge) |c| try e.print("{d}", .{c}) else "UINT32_MAX"});
        try tables.print(gpa, "const uint32_t mo_request_decl = {d};\nconst uint32_t mo_response_decl = {d};\n", .{ k.preludeStruct("Request").?, k.preludeStruct("Response").? });
        try tables.print(gpa, "const uint32_t mo_process_info_decl = {d};\nconst uint32_t mo_source_info_decl = {d};\nconst uint32_t mo_memory_info_decl = {d};\n", .{ k.preludeStruct("ProcessInfo").?, k.preludeStruct("SourceInfo").?, k.preludeStruct("MemoryInfo").? });
        try tables.print(gpa, "const bool mo_surface_built = {s};\n", .{if (e.options.surface) "true" else "false"});
        // The runtime surface's own process, which the surface does not show (step 23).
        const surface_process: ?usize = if (!e.options.surface) null else if (surface_mod.declOf(k)) |d| for (e.processes.items, 0..) |p, pi| {
            if (p.decl == d) break pi;
        } else null else null;
        try tables.print(gpa, "const uint32_t mo_surface_process = {s};\n", .{if (surface_process) |pi| try e.print("{d}", .{pi}) else "UINT32_MAX"});
        try tables.print(gpa, "const bool mo_contracts_built = {s};\n\n", .{if (e.options.contracts or e.options.tests) "true" else "false"});

        try out.appendSlice(gpa, e.protos.items);
        try out.append(gpa, '\n');
        try out.appendSlice(gpa, tables.items);
        try out.appendSlice(gpa, e.bodies.items);
        try out.appendSlice(gpa, extra.items);
        if (e.options.tests) {
            try out.appendSlice(gpa, "\nint main(void) {\n    return mo_run_tests();\n}\n");
        } else {
            const main_sig = k.mainSig().?;
            // MO_SURFACE=PORT serves the runtime surface before main in a binary built with --surface.
            const surface_start = if (!e.options.surface) "" else if (surface_mod.sigOf(k)) |si| try e.print("    if (mo_surface_port() >= 0) mo_surface_listening(f{d}(mo_cap(MO_CAP_RUNTIME, 0, 0), mo_cap(MO_CAP_HTTP, 0, 0), mo_i128(mo_surface_port())));\n", .{si}) else "";
            try out.print(gpa, "\nint main(int argc, char **argv) {{\n    mo_program_start(argc, argv);\n{s}    f{d}(mo_platform());\n    return mo_program_end();\n}}\n", .{ surface_start, main_sig });
        }
        return out.items;
    }
};

/// A C integer literal: canonical, so an integer has one form (mo_rt.h).
fn intConst(gpa: std.mem.Allocator, v: i128) Error![]const u8 {
    if (v == std.math.minInt(i64)) return "mo_i64(INT64_MIN)";
    if (v >= std.math.minInt(i64) and v <= std.math.maxInt(i64)) return std.fmt.allocPrint(gpa, "mo_i64(INT64_C({d}))", .{v});
    if (v > 0 and v <= std.math.maxInt(u64)) return std.fmt.allocPrint(gpa, "mo_u64(UINT64_C({d}))", .{v});
    const u: u128 = @bitCast(v);
    return std.fmt.allocPrint(gpa, "mo_i128((__int128)(((unsigned __int128)UINT64_C({d}) << 64) | UINT64_C({d})))", .{ @as(u64, @truncate(u >> 64)), @as(u64, @truncate(u)) });
}

/// A C string literal holding `s` exactly: quotes, backslashes, question marks (trigraphs),
/// and every byte outside printable ASCII escaped in octal.
/// An __int128 constant within the 64-bit integer types' range, which C has no literal for.
fn int128(gpa: std.mem.Allocator, v: i128) Error![]const u8 {
    return std.fmt.allocPrint(gpa, "{s}(__int128){d}ull", .{ if (v < 0) "-" else "", @abs(v) });
}

fn cString(gpa: std.mem.Allocator, s: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.append(gpa, '"');
    for (s) |ch| switch (ch) {
        '"' => try out.appendSlice(gpa, "\\\""),
        '\\' => try out.appendSlice(gpa, "\\\\"),
        '?' => try out.appendSlice(gpa, "\\?"),
        0x20...0x21, 0x23...0x3E, 0x40...0x5B, 0x5D...0x7E => try out.append(gpa, ch),
        else => try out.print(gpa, "\\{o:0>3}", .{ch}),
    };
    try out.append(gpa, '"');
    return out.items;
}

test "a C string literal escapes what C reads specially" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("\"a\\\"b\\\\c\\?\\?=\\012\\303\\251\"", try cString(arena, "a\"b\\c??=\né"));
    try std.testing.expectEqualStrings("mo_i64(INT64_MIN)", try intConst(arena, std.math.minInt(i64)));
    try std.testing.expectEqualStrings("mo_u64(UINT64_C(18446744073709551615))", try intConst(arena, std.math.maxInt(u64)));
}

test "a one-line if value lowers exactly as its block form, in bytecode and in C" {
    // Both sources hold every token outside the if at the same byte and on the same line: the
    // one-line form is padded with the block form's newlines and then spaces to its length. The
    // branches are constants, which record no position, so the two lowerings may differ only if
    // the forms lower differently (step 25). The value is bound, and it is a body's last line,
    // where a one-line `if` starts its line (step 26).
    const pipeline = @import("pipeline.zig");
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const places = [_][2][]const u8{
        .{ "module M\nexpose label\n\nfn label(n: UInt32) : String\n  word = ", "\n  \"#{n} #{word}\"\nend\n\ntest \"one line\"\n  assert label(1) == \"1 line\"\nend\n" },
        .{ "module M\nexpose label\n\nfn label(n: UInt32) : String\n  ", "\nend\n\ntest \"one line\"\n  assert label(1) == \"line\"\nend\n" },
    };
    const block = "if n == 1\n    \"line\"\n  else\n    \"lines\"\n  end";
    const line = "if n == 1: \"line\" else: \"lines\"";
    const newlines = std.mem.count(u8, block, "\n");
    const padded = try arena.alloc(u8, block.len);
    @memset(padded, ' ');
    @memcpy(padded[0..line.len], line);
    @memset(padded[block.len - newlines ..], '\n');
    for (places) |place| {
        var outs: [2][]const u8 = undefined;
        var lowered: [2]bytecode.Program = undefined;
        for ([_][]const u8{ block, padded }, 0..) |form, k| {
            const src = try std.mem.concat(arena, u8, &.{ place[0], form, place[1] });
            const prog = try program.single(arena, "t.mo", src);
            var diags: diag.List = .empty;
            const checked = try pipeline.buildable(arena, prog, true, &diags);
            outs[k] = try emit(arena, &checked, prog, .{ .tests = true });
            lowered[k] = try bytecode.lower(arena, checked);
        }
        try std.testing.expectEqualStrings(outs[0], outs[1]);
        try std.testing.expectEqualDeep(lowered[0].functions, lowered[1].functions);
        try std.testing.expectEqualDeep(lowered[0].clauses, lowered[1].clauses);
        try std.testing.expectEqualDeep(lowered[0].constants, lowered[1].constants);
    }
}
