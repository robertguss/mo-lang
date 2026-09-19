//! The checker's types: one flat pool, referred to by index (pointer-free, like the
//! tree). Compound types keep their children in `items`. Inference variables live in
//! `vars` and are bound by `unify`; `resolve` follows the bindings.
//!
//! Nominal types (structs, enums, aliases, processes) carry a decl index into
//! `decl_names`; the checker keeps the rest of each declaration beside it.
const std = @import("std");

pub const Id = u32;

pub const IntKind = enum(u8) { i8, i16, i32, i64, u8, u16, u32, u64 };

/// `platform`, `env`, and `out` are Mo.Server's (Q18): `main`'s parameter and its parts.
/// `net` is `platform.net`; a `listener` and a `conn` come from its calls (step 11). `http` is
/// `platform.http`; an `http_listener` and an `exchange` come from its calls (step 16). `tls` is
/// `platform.tls`, and a `tls_server` and a `tls_client` come from its calls (steps 36 and 37);
/// what `accept` and `connect` give is a `conn` again, so every row after the handshake is the
/// same row.
pub const CapKind = enum(u8) { clock, fs, events, ledger, platform, env, out, net, listener, conn, http, http_listener, exchange, runtime, random, tls, tls_server, tls_client, exec, program, command };

pub const Tag = enum(u8) {
    /// Error recovery and "no expectation": unifies with everything.
    unknown,
    /// No value: an assignment, a loop, a call such as `send`.
    none,
    /// `return` and `break`: control leaves, so the value fits anywhere.
    never,
    bool,
    string,
    time,
    duration,
    /// a: IntKind
    int,
    /// a: 32 or 64
    float,
    /// a: element
    list,
    /// a: value
    option,
    /// a: value, b: error
    result,
    /// Map(K, V) (design-v0/09): a: key, b: value
    map,
    /// Set(T): a: element
    set,
    /// a: start in items, b: length
    tuple,
    /// a: start in items (parameters, then the return type), b: parameter count
    func,
    /// a struct, an enum, a trait, or an opaque name: a is the decl
    decl,
    /// `type Name = T`: a is the decl, b the base type
    alias,
    /// a: CapKind
    cap,
    /// Handle(P): a is the process decl
    handle,
    /// one of P's messages: a is the process decl
    message,
    /// the `state` of P inside update and invariant: a is the process decl
    state,
    /// a type parameter of the function being checked: a is the generic index
    param,
    /// `Self` in a trait
    self_,
    /// an inference variable: a is the var index
    variable,
    /// A point on the runtime's clock that a call may wait until: an ask's `reply_by` (step 22).
    deadline,
    /// Reply(T): the asker an arm kept instead of answering, answered later (step 31). a: T
    reply,
};

pub const Type = struct { tag: Tag, a: u32 = 0, b: u32 = 0 };

pub const Var = struct {
    bound: ?Id = null,
    /// Born from an integer literal: binds only to an integer type, and becomes
    /// Int64 if nothing else constrains it.
    int_literal: bool = false,
};

// Fixed ids, added by `init` in this order.
pub const unknown: Id = 0;
pub const none: Id = 1;
pub const never: Id = 2;
pub const bool_: Id = 3;
pub const string: Id = 4;
pub const time: Id = 5;
pub const duration: Id = 6;
pub const self_: Id = 7;
const int_base: Id = 8;
pub const float32: Id = 16;
pub const float64: Id = 17;
const cap_base: Id = 18;
/// An Fs narrowed to read_only (`fs.read_only`, or `scoped` on one): a capability of kind fs
/// with `b` 1. It unifies with Fs, so it goes wherever an Fs goes, and caps.zig refuses it
/// where a write reaches it, directly or through a parameter a function writes through (MO0404).
pub const fs_read_only: Id = cap_base + @typeInfo(CapKind).@"enum".fields.len;
/// `Deadline` (design-v0/09, step 22): `reply_by`, and what `at_most` gives.
pub const deadline: Id = fs_read_only + 1;

pub fn int(kind: IntKind) Id {
    return int_base + @intFromEnum(kind);
}

pub fn cap(kind: CapKind) Id {
    return cap_base + @intFromEnum(kind);
}

pub const Pool = struct {
    gpa: std.mem.Allocator,
    list: std.ArrayList(Type) = .empty,
    items: std.ArrayList(Id) = .empty,
    vars: std.ArrayList(Var) = .empty,
    decl_names: std.ArrayList([]const u8) = .empty,

    pub fn init(gpa: std.mem.Allocator) !Pool {
        var p: Pool = .{ .gpa = gpa };
        const fixed = [_]Type{ .{ .tag = .unknown }, .{ .tag = .none }, .{ .tag = .never }, .{ .tag = .bool }, .{ .tag = .string }, .{ .tag = .time }, .{ .tag = .duration }, .{ .tag = .self_ } };
        try p.list.appendSlice(gpa, &fixed);
        for (0..8) |k| try p.list.append(gpa, .{ .tag = .int, .a = @intCast(k) });
        try p.list.append(gpa, .{ .tag = .float, .a = 32 });
        try p.list.append(gpa, .{ .tag = .float, .a = 64 });
        const caps = @typeInfo(CapKind).@"enum".fields.len;
        for (0..caps) |k| try p.list.append(gpa, .{ .tag = .cap, .a = @intCast(k) });
        try p.list.append(gpa, .{ .tag = .cap, .a = @intFromEnum(CapKind.fs), .b = 1 });
        try p.list.append(gpa, .{ .tag = .deadline });
        std.debug.assert(p.list.items.len == deadline + 1);
        return p;
    }

    pub fn get(p: *const Pool, id: Id) Type {
        return p.list.items[id];
    }

    pub fn add(p: *Pool, t: Type) !Id {
        const id: Id = @intCast(p.list.items.len);
        try p.list.append(p.gpa, t);
        return id;
    }

    pub fn addDecl(p: *Pool, decl_name: []const u8) !u32 {
        const i: u32 = @intCast(p.decl_names.items.len);
        try p.decl_names.append(p.gpa, decl_name);
        return i;
    }

    pub fn fresh(p: *Pool, int_literal: bool) !Id {
        const v: u32 = @intCast(p.vars.items.len);
        try p.vars.append(p.gpa, .{ .int_literal = int_literal });
        return p.add(.{ .tag = .variable, .a = v });
    }

    pub fn list1(p: *Pool, tag: Tag, a: Id) !Id {
        return p.add(.{ .tag = tag, .a = a });
    }

    pub fn result(p: *Pool, ok: Id, err: Id) !Id {
        return p.add(.{ .tag = .result, .a = ok, .b = err });
    }

    pub fn tuple(p: *Pool, children: []const Id) !Id {
        const start: u32 = @intCast(p.items.items.len);
        try p.items.appendSlice(p.gpa, children);
        return p.add(.{ .tag = .tuple, .a = start, .b = @intCast(children.len) });
    }

    pub fn func(p: *Pool, params: []const Id, ret: Id) !Id {
        const start: u32 = @intCast(p.items.items.len);
        try p.items.appendSlice(p.gpa, params);
        try p.items.append(p.gpa, ret);
        return p.add(.{ .tag = .func, .a = start, .b = @intCast(params.len) });
    }

    /// Children of a tuple, or a function's parameters.
    pub fn elems(p: *const Pool, t: Type) []const Id {
        return p.items.items[t.a .. t.a + t.b];
    }

    pub fn funcRet(p: *const Pool, t: Type) Id {
        return p.items.items[t.a + t.b];
    }

    /// Follows variable bindings to the first type that is not a bound variable.
    pub fn resolve(p: *const Pool, id: Id) Id {
        var cur = id;
        while (true) {
            const t = p.list.items[cur];
            if (t.tag != .variable) return cur;
            cur = p.vars.items[t.a].bound orelse return cur;
        }
    }

    /// Resolves, then looks through aliases to the base type.
    pub fn base(p: *const Pool, id: Id) Id {
        var cur = p.resolve(id);
        while (p.list.items[cur].tag == .alias) cur = p.resolve(p.list.items[cur].b);
        return cur;
    }

    pub fn isIntLiteralVar(p: *const Pool, id: Id) bool {
        const t = p.get(p.resolve(id));
        return t.tag == .variable and p.vars.items[t.a].int_literal;
    }

    pub fn isNumeric(p: *const Pool, id: Id) bool {
        const t = p.get(p.base(id));
        return switch (t.tag) {
            .int, .float, .unknown, .variable, .never => true,
            else => false,
        };
    }

    fn occurs(p: *const Pool, v: u32, id: Id) bool {
        const r = p.resolve(id);
        const t = p.get(r);
        return switch (t.tag) {
            .variable => t.a == v,
            .list, .option, .set => p.occurs(v, t.a),
            .result, .map => p.occurs(v, t.a) or p.occurs(v, t.b),
            .tuple => for (p.elems(t)) |e| {
                if (p.occurs(v, e)) break true;
            } else false,
            .func => p.occurs(v, p.funcRet(t)) or for (p.elems(t)) |e| {
                if (p.occurs(v, e)) break true;
            } else false,
            else => false,
        };
    }

    fn bindVar(p: *Pool, v: u32, to: Id) bool {
        const target = p.get(to);
        if (target.tag == .variable) {
            // Keep the integer-literal constraint on whichever variable survives.
            if (p.vars.items[v].int_literal) p.vars.items[target.a].int_literal = true;
            p.vars.items[v].bound = to;
            return true;
        }
        if (p.vars.items[v].int_literal) {
            const b = p.get(p.base(to));
            if (b.tag != .int and b.tag != .unknown and b.tag != .never) return false;
        }
        if (p.occurs(v, to)) return false;
        p.vars.items[v].bound = to;
        return true;
    }

    /// Makes `a` and `b` the same type, binding variables as needed. An alias unifies
    /// with its base in both directions: a base value crosses into a refined type at a
    /// boundary, and tier 2 checks the refinement there.
    pub fn unify(p: *Pool, a: Id, b: Id) bool {
        const ra = p.resolve(a);
        const rb = p.resolve(b);
        if (ra == rb) return true;
        const ta = p.get(ra);
        const tb = p.get(rb);
        if (ta.tag == .unknown or tb.tag == .unknown or ta.tag == .never or tb.tag == .never) return true;
        if (ta.tag == .variable) return p.bindVar(ta.a, rb);
        if (tb.tag == .variable) return p.bindVar(tb.a, ra);
        if (ta.tag == .alias and tb.tag == .alias and ta.a == tb.a) return true;
        if (ta.tag == .alias) return p.unify(ta.b, rb);
        if (tb.tag == .alias) return p.unify(ra, tb.b);
        if (ta.tag != tb.tag) return false;
        return switch (ta.tag) {
            .none, .bool, .string, .time, .duration, .self_, .deadline => true,
            .int, .float, .cap, .decl, .handle, .message, .state, .param => ta.a == tb.a,
            .list, .option, .set, .reply => p.unify(ta.a, tb.a),
            .result, .map => p.unify(ta.a, tb.a) and p.unify(ta.b, tb.b),
            .tuple => ta.b == tb.b and for (0..ta.b) |i| {
                if (!p.unify(p.items.items[ta.a + i], p.items.items[tb.a + i])) break false;
            } else true,
            .func => ta.b == tb.b and p.unify(p.funcRet(ta), p.funcRet(tb)) and for (0..ta.b) |i| {
                if (!p.unify(p.items.items[ta.a + i], p.items.items[tb.a + i])) break false;
            } else true,
            .unknown, .never, .alias, .variable => unreachable,
        };
    }

    /// Replaces every `from[i]` inside `id` with `to[i]`, rebuilding only what changes.
    pub fn subst(p: *Pool, id: Id, from: []const Id, to: []const Id) !Id {
        const r = p.resolve(id);
        for (from, to) |f, t| if (r == f) return t;
        const t = p.get(r);
        switch (t.tag) {
            .list, .option, .set, .reply => {
                const inner = try p.subst(t.a, from, to);
                return if (inner == t.a) r else p.add(.{ .tag = t.tag, .a = inner });
            },
            .result, .map => {
                const ok = try p.subst(t.a, from, to);
                const err = try p.subst(t.b, from, to);
                return if (ok == t.a and err == t.b) r else p.add(.{ .tag = t.tag, .a = ok, .b = err });
            },
            .tuple, .func => {
                var changed = false;
                const n = t.b + @as(u32, if (t.tag == .func) 1 else 0);
                var buf = try p.gpa.alloc(Id, n);
                for (0..n) |i| {
                    buf[i] = try p.subst(p.items.items[t.a + i], from, to);
                    if (buf[i] != p.items.items[t.a + i]) changed = true;
                }
                if (!changed) return r;
                return if (t.tag == .tuple) p.tuple(buf) else p.func(buf[0..t.b], buf[t.b]);
            },
            else => return r,
        }
    }

    /// Mo spelling of a type, for diagnostics.
    pub fn format(p: *const Pool, w: *std.Io.Writer, id: Id) std.Io.Writer.Error!void {
        const r = p.resolve(id);
        const t = p.get(r);
        switch (t.tag) {
            .unknown => try w.writeAll("an unknown type"),
            .none => try w.writeAll("no value"),
            .never => try w.writeAll("nothing"),
            .bool => try w.writeAll("Bool"),
            .string => try w.writeAll("String"),
            .time => try w.writeAll("Time"),
            .duration => try w.writeAll("Duration"),
            .deadline => try w.writeAll("Deadline"),
            .self_ => try w.writeAll("Self"),
            .int => try w.writeAll(switch (@as(IntKind, @enumFromInt(t.a))) {
                .i8 => "Int8",
                .i16 => "Int16",
                .i32 => "Int32",
                .i64 => "Int64",
                .u8 => "UInt8",
                .u16 => "UInt16",
                .u32 => "UInt32",
                .u64 => "UInt64",
            }),
            .float => try w.writeAll(if (t.a == 32) "Float32" else "Float64"),
            .cap => try w.writeAll(switch (@as(CapKind, @enumFromInt(t.a))) {
                .clock => "Clock",
                .fs => "Fs",
                .events => "Events",
                .ledger => "Ledger",
                .platform => "Platform",
                .env => "Env",
                .out => "Out",
                .net => "Net",
                .listener => "Listener",
                .conn => "Conn",
                .http => "Http",
                .http_listener => "HttpListener",
                .exchange => "Exchange",
                .runtime => "Runtime",
                .random => "Random",
                .tls => "Tls",
                .tls_server => "TlsServer",
                .tls_client => "TlsClient",
                .exec => "Exec",
                .program => "Program",
                .command => "Command",
            }),
            .list, .option, .set => {
                try w.writeAll(switch (t.tag) {
                    .list => "List(",
                    .option => "Option(",
                    else => "Set(",
                });
                try p.format(w, t.a);
                try w.writeAll(")");
            },
            .map => {
                try w.writeAll("Map(");
                try p.format(w, t.a);
                try w.writeAll(", ");
                try p.format(w, t.b);
                try w.writeAll(")");
            },
            .result => {
                try w.writeAll("Result(");
                try p.format(w, t.a);
                try w.writeAll(", ");
                try p.format(w, t.b);
                try w.writeAll(")");
            },
            .tuple => {
                try w.writeAll("(");
                for (p.elems(t), 0..) |e, i| {
                    if (i > 0) try w.writeAll(", ");
                    try p.format(w, e);
                }
                try w.writeAll(")");
            },
            .func => {
                try w.writeAll("fn(");
                for (p.elems(t), 0..) |e, i| {
                    if (i > 0) try w.writeAll(", ");
                    try p.format(w, e);
                }
                try w.writeAll(") ");
                try p.format(w, p.funcRet(t));
            },
            .decl, .alias => try w.writeAll(p.decl_names.items[t.a]),
            .handle => try w.print("Handle({s})", .{p.decl_names.items[t.a]}),
            .reply => {
                try w.writeAll("Reply(");
                try p.format(w, t.a);
                try w.writeAll(")");
            },
            .message => try w.print("a message of {s}", .{p.decl_names.items[t.a]}),
            .state => try w.print("the state of {s}", .{p.decl_names.items[t.a]}),
            .param => try w.writeAll("a type parameter"),
            .variable => try w.writeAll(if (p.vars.items[t.a].int_literal) "an integer" else "a type not yet known"),
        }
    }

    pub fn name(p: *const Pool, gpa: std.mem.Allocator, id: Id) ![]const u8 {
        var aw: std.Io.Writer.Allocating = .init(gpa);
        p.format(&aw.writer, id) catch return error.OutOfMemory;
        return aw.toOwnedSlice();
    }
};

test "unify binds variables and keeps an integer literal an integer" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var p = try Pool.init(arena_state.allocator());
    const lit = try p.fresh(true);
    try std.testing.expect(!p.unify(lit, string));
    try std.testing.expect(p.unify(lit, int(.u16)));
    try std.testing.expectEqual(int(.u16), p.resolve(lit));
    const xs = try p.list1(.list, try p.fresh(false));
    try std.testing.expect(p.unify(xs, try p.list1(.list, bool_)));
    try std.testing.expect(!p.unify(xs, try p.list1(.list, string)));
    try std.testing.expectEqualStrings("List(Bool)", try p.name(arena_state.allocator(), xs));
}

test "an alias unifies with its base but two aliases stay apart" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var p = try Pool.init(arena_state.allocator());
    const percent = try p.add(.{ .tag = .alias, .a = try p.addDecl("Percent"), .b = int(.u32) });
    const card = try p.add(.{ .tag = .alias, .a = try p.addDecl("CardNumber"), .b = string });
    try std.testing.expect(p.unify(percent, int(.u32)));
    try std.testing.expect(p.unify(string, card));
    try std.testing.expect(!p.unify(percent, card));
}
