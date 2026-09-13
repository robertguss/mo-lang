//! Capabilities, tier 1 (design-v0/03 effects, chapter 2 deadlines). A function is
//! pure unless it takes a capability parameter; capabilities flow only through
//! parameters and narrowing (`fs.scoped(...).read_only`), never inside a value and
//! never returned; a capability's `fixture` exists only in tests; a call that can
//! wait passes `within:`, and a call that cannot wait does not.
//!
//! `flows(T, into: Cap)` is checked as "no value of type T reaches a call on Cap"
//! through direct data flow: an argument whose type holds a T (a struct or enum
//! field counts, and so do tuples, Option, and Result), a string that interpolates
//! one, a construction that is given one, or a local name bound to any of those.
//! Tier 1 does not chase through collections (a List(T) is not followed) or through
//! the result of a function call; those wait for the interpreter.
//!
//! Every finding is an MO04xx record. Reads what check.zig decided: the type of each
//! node and the function each call reached.
const std = @import("std");
const ast = @import("ast.zig");
const checker = @import("check.zig");
const diag = @import("diag.zig");
const prelude = @import("prelude.zig");
const types = @import("types.zig");

const Index = ast.Index;
const Id = types.Id;

pub const Error = error{OutOfMemory};

pub const Code = enum { missing_within, needless_within, outside_params, flows_violated, bad_flows, recipe_needs, platform_escapes, no_main };

pub const catalog = std.enums.EnumArray(Code, checker.Entry).init(.{
    .missing_within = .{ .code = "MO0401", .category = .capabilities, .what = "<call> has no within: deadline; add one, such as within: 100.ms.", .why = "Every call that can wait carries a deadline (chapter 2, bounding laws), so nothing blocks forever; a timeout comes back as an ordinary error the caller handles.", .fixes = &.{} },
    .needless_within = .{ .code = "MO0402", .category = .capabilities, .what = "<call> cannot wait, so it takes no within:; remove the deadline.", .why = "Only a call that can wait takes within: (the platform marks which ones, toolchain/PRELUDE.md); a deadline on a call that cannot wait says something false.", .fixes = &.{} },
    .outside_params = .{ .code = "MO0403", .category = .capabilities, .what = "<function> has no capability parameter, so it is pure and cannot use a <Capability>; take a <Capability> parameter.", .why = "A capability is held only as a parameter and narrowed on the way down (chapter 3, effects), so a function's signature is the complete list of what it can touch.", .fixes = &.{} },
    .flows_violated = .{ .code = "MO0404", .category = .capabilities, .what = "a <Type> reaches <call> through <value>; the never <rule> forbids it.", .why = "A never with flows(T, into: Cap) promises that no value of type T reaches a call on Cap; tier 1 follows direct data flow to keep that promise.", .fixes = &.{} },
    .bad_flows = .{ .code = "MO0405", .category = .capabilities, .what = "flows names a declared or prelude type first, such as flows(CardNumber, into: Events).", .why = "flows(T, into: Cap) names a type first and a capability after into:, so the rule can be checked; a never that cannot be checked does not compile.", .fixes = &.{} },
    .recipe_needs = .{ .code = "MO0406", .category = .capabilities, .what = "<function> takes a <Capability>, but recipe <Recipe> needs <capabilities>; add <Capability> to its needs line.", .why = "A recipe's needs line is the list of capabilities its implementation may take (chapter 6), so every capability in its signatures is named there, and only capabilities are.", .fixes = &.{} },
    .platform_escapes = .{ .code = "MO0407", .category = .capabilities, .what = "<function> takes a Platform, which only main holds; take the parts it uses instead, such as an Fs or an Out.", .why = "A Platform exists only as fn main's parameter (Q18): main reads its parts and passes each one down, narrowed, so no other function can reach everything the program holds.", .fixes = &.{} },
    .no_main = .{ .code = "MO0408", .category = .capabilities, .what = "this module has no fn main(platform: Platform), so mo run has nothing to run; mo test runs its tests", .why = "mo run starts a program at fn main(platform: Platform), the one place it receives its capabilities (Q18). A module without main has nothing to run; mo test runs its tests.", .fixes = &.{} },
});

pub fn check(gpa: std.mem.Allocator, checked: checker.Checked, out: *diag.List) Error!void {
    var c: Caps = .{ .gpa = gpa, .k = &checked, .out = out };
    try c.buildUnits();
    try c.declarations();
    try c.bodies();
    try c.platformUses();
    try c.flowRules();
}

/// A run of nodes that belong to one declaration, one test, or one never.
const Unit = struct {
    kind: Kind,
    name: []const u8 = "",
    first: Index,
    last: Index,
    has_caps: bool = false,
    const Kind = enum { function, recipe_sig, test_block, never, process, supervisor, other };
};

const Caps = struct {
    gpa: std.mem.Allocator,
    k: *const checker.Checked,
    out: *diag.List,
    units: std.ArrayList(Unit) = .empty,

    fn node(c: *Caps, i: Index) ast.Node {
        return c.k.tree.nodes[i];
    }

    fn text(c: *Caps, tok: u32) []const u8 {
        return c.k.tree.tokenText(tok);
    }

    fn print(c: *Caps, comptime fmt: []const u8, args: anytype) Error![]const u8 {
        return std.fmt.allocPrint(c.gpa, fmt, args);
    }

    fn tn(c: *Caps, t: Id) Error![]const u8 {
        return c.k.pool.name(c.gpa, t);
    }

    fn report(c: *Caps, code: Code, tok: u32, what: []const u8) Error!void {
        const e = catalog.get(code);
        try c.out.append(c.gpa, .{ .code = e.code, .category = e.category, .at = c.k.tree.tokens[tok].start, .what = what, .why = e.why });
    }

    fn spanAt(c: *Caps, extra_index: u32) []const u32 {
        if (extra_index == 0) return &.{};
        const s = c.k.tree.extraData(ast.Span, extra_index);
        return c.k.tree.span(s.start, s.end);
    }

    fn items(c: *Caps) []const u32 {
        const root = c.node(0);
        return c.k.tree.span(root.lhs, root.rhs);
    }

    fn firstToken(c: *Caps, i: Index) u32 {
        var cur = i;
        while (true) {
            const n = c.node(cur);
            switch (n.kind) {
                .implies, .or_expr, .and_expr, .compare, .is_expr, .range, .add, .mul, .member, .member_call, .tuple_index, .call => cur = n.lhs,
                else => return n.main_token,
            }
        }
    }

    /// The source of an argument, up to the `,` or `)` that ends it.
    fn argText(c: *Caps, i: Index) []const u8 {
        const src = c.k.tree.source;
        const start = c.k.tree.tokens[c.firstToken(i)].start;
        var depth: u32 = 0;
        var in_string = false;
        var k: usize = start;
        while (k < src.len) : (k += 1) {
            const ch = src[k];
            if (in_string) {
                if (ch == '\\') k += 1 else if (ch == '"') in_string = false;
                continue;
            }
            switch (ch) {
                '"' => in_string = true,
                '(', '[' => depth += 1,
                ')', ']' => {
                    if (depth == 0) break;
                    depth -= 1;
                },
                ',', '\n' => if (depth == 0) break,
                else => {},
            }
        }
        return std.mem.trimEnd(u8, src[start..k], " \t\r");
    }

    fn baseTag(c: *Caps, t: Id) types.Type {
        return c.k.pool.get(c.k.pool.base(t));
    }

    /// The first capability type inside `t`, looking through lists, options, results, and tuples.
    fn capIn(c: *Caps, t: Id, depth: u8) ?Id {
        if (depth > 8) return null;
        const r = c.k.pool.base(t);
        const b = c.k.pool.get(r);
        return switch (b.tag) {
            .cap => r,
            .list, .option, .set => c.capIn(b.a, depth + 1),
            .result, .map => c.capIn(b.a, depth + 1) orelse c.capIn(b.b, depth + 1),
            .tuple => for (c.k.pool.elems(b)) |e| {
                if (c.capIn(e, depth + 1)) |x| break x;
            } else null,
            else => null,
        };
    }

    fn paramsHaveCaps(c: *Caps, r: checker.Range) bool {
        for (c.k.params[r.start..r.end]) |p| if (c.capIn(p.type, 0) != null) return true;
        return false;
    }

    fn sigOf(c: *Caps, n: Index) ?checker.FnSig {
        for (c.k.sigs) |s| if (s.node == n) return s;
        return null;
    }

    fn addUnit(c: *Caps, u: Unit) Error!void {
        if (u.last < u.first) return;
        try c.units.append(c.gpa, u);
    }

    /// Each item's nodes are created after the previous item's and before its own node,
    /// so a declaration's subtree is the run of node indices that ends at it.
    fn buildUnits(c: *Caps) Error!void {
        var prev: Index = 0;
        for (c.items()) |it| {
            const n = c.node(it);
            switch (n.kind) {
                .fn_decl => try c.fnUnit(prev + 1, it),
                .impl_decl => {
                    var p = prev;
                    for (c.spanAt(n.rhs)) |f| {
                        try c.fnUnit(p + 1, f);
                        p = f;
                    }
                    try c.addUnit(.{ .kind = .other, .first = p + 1, .last = it });
                },
                .recipe_decl => {
                    const r = c.k.tree.extraData(ast.Recipe, n.lhs);
                    var p = r.needs;
                    try c.addUnit(.{ .kind = .other, .first = prev + 1, .last = p });
                    for (c.k.tree.span(r.sigs_start, r.sigs_end)) |s| {
                        try c.addUnit(.{ .kind = .recipe_sig, .name = c.text(c.node(s).main_token), .first = p + 1, .last = s });
                        p = s;
                    }
                    for (c.k.tree.span(r.tests_start, r.tests_end)) |t| {
                        try c.addUnit(.{ .kind = .test_block, .first = p + 1, .last = t });
                        p = t;
                    }
                    try c.addUnit(.{ .kind = .other, .first = p + 1, .last = it });
                },
                .test_decl, .test_rejects, .property => try c.addUnit(.{ .kind = .test_block, .first = prev + 1, .last = it }),
                .never => try c.addUnit(.{ .kind = .never, .first = prev + 1, .last = it }),
                .process_decl, .supervisor_decl => {
                    const d = c.k.findDeclAt(it, c.text(n.main_token));
                    const has = if (d) |x| c.paramsHaveCaps(c.k.decls[x].params) else false;
                    try c.addUnit(.{ .kind = if (n.kind == .process_decl) .process else .supervisor, .name = c.text(n.main_token), .first = prev + 1, .last = it, .has_caps = has });
                },
                else => try c.addUnit(.{ .kind = .other, .first = prev + 1, .last = it }),
            }
            prev = it;
        }
    }

    fn fnUnit(c: *Caps, first: Index, f: Index) Error!void {
        const s = c.sigOf(f);
        try c.addUnit(.{ .kind = .function, .name = c.text(c.node(f).main_token), .first = first, .last = f, .has_caps = if (s) |x| c.paramsHaveCaps(x.params) else false });
    }

    // ---- declarations: no capability inside a value, none returned, recipes name theirs

    fn declarations(c: *Caps) Error!void {
        for (c.k.decls) |d| {
            if (d.node == 0) continue;
            const ranges = [_]checker.Range{d.fields};
            switch (d.kind) {
                .struct_, .process => for (ranges) |r| try c.fieldCaps(r),
                else => {},
            }
            if (d.kind == .enum_ or d.kind == .process) {
                for (c.k.variants[d.variants.start..d.variants.end]) |v| try c.fieldCaps(v.fields);
            }
        }
        for (c.k.sigs) |s| {
            if (c.capIn(s.ret, 0)) |cap| try c.report(.outside_params, c.node(s.node).main_token, try c.print("{s} returns a {s}; a capability is passed down as a parameter, never returned.", .{ s.name, try c.tn(cap) }));
        }
        // Only main takes a Platform; everything below it takes the parts it needs.
        for (c.k.sigs) |s| {
            if (s.kind == .module and std.mem.eql(u8, s.name, "main")) continue;
            try c.platformParams(s.name, s.params);
        }
        for (c.k.decls) |d| {
            if (d.node != 0 and (d.kind == .process or d.kind == .supervisor)) try c.platformParams(d.name, d.params);
        }
        for (c.items()) |it| {
            const n = c.node(it);
            if (n.kind == .recipe_decl) try c.recipeNeeds(n);
        }
    }

    fn platformParams(c: *Caps, owner: []const u8, r: checker.Range) Error!void {
        for (c.k.params[r.start..r.end]) |p| {
            if (!c.platformIn(p.type, 0)) continue;
            try c.report(.platform_escapes, c.node(p.node).main_token, try c.print("{s} takes a Platform, which only main holds; take the parts it uses instead, such as an Fs or an Out.", .{owner}));
        }
    }

    /// Whether a Platform is inside `t`, looking through lists, options, results, and tuples.
    fn platformIn(c: *Caps, t: Id, depth: u8) bool {
        if (depth > 8) return false;
        const r = c.k.pool.base(t);
        const b = c.k.pool.get(r);
        return switch (b.tag) {
            .cap => r == types.cap(.platform),
            .list, .option, .set => c.platformIn(b.a, depth + 1),
            .result, .map => c.platformIn(b.a, depth + 1) or c.platformIn(b.b, depth + 1),
            .tuple => for (c.k.pool.elems(b)) |e| {
                if (c.platformIn(e, depth + 1)) break true;
            } else false,
            else => false,
        };
    }

    /// A Platform is only ever read through a dot: `platform.fs`, `platform.exit(3)`.
    /// Passed, bound, put in a list, or interpolated, it would leave main.
    fn platformUses(c: *Caps) Error!void {
        const nodes = c.k.tree.nodes;
        const receiver = try c.gpa.alloc(bool, nodes.len);
        @memset(receiver, false);
        for (nodes) |n| if (n.kind == .member or n.kind == .member_call) {
            receiver[n.lhs] = true;
        };
        for (nodes, 0..) |n, i| {
            if (n.kind != .name_ref or receiver[i]) continue;
            if (c.k.pool.base(c.k.typeOf(@intCast(i))) != types.cap(.platform)) continue;
            const name = c.text(n.main_token);
            try c.report(.platform_escapes, n.main_token, try c.print("{s} is a Platform, which stays in main; pass on a part of it, such as {s}.fs or {s}.stdout.", .{ name, name, name }));
        }
    }

    fn fieldCaps(c: *Caps, r: checker.Range) Error!void {
        for (c.k.fields[r.start..r.end]) |f| {
            if (f.node == 0) continue;
            if (c.capIn(f.type, 0)) |cap| try c.report(.outside_params, c.node(f.node).main_token, try c.print("{s} holds a {s}; a capability travels only as a parameter, never inside a value.", .{ f.name, try c.tn(cap) }));
        }
    }

    fn recipeNeeds(c: *Caps, n: ast.Node) Error!void {
        const r = c.k.tree.extraData(ast.Recipe, n.lhs);
        const needs = c.node(r.needs);
        const names = c.k.tree.span(needs.lhs, needs.rhs);
        for (names) |tok| {
            const t = prelude.findType(c.text(tok));
            if (t == null or t.?.kind != .capability) try c.report(.recipe_needs, tok, try c.print("{s} is not a capability; needs lists capabilities such as Clock or Fs, or nothing.", .{c.text(tok)}));
        }
        for (c.k.tree.span(r.sigs_start, r.sigs_end)) |sn| {
            const s = c.sigOf(sn) orelse continue;
            for (c.k.params[s.params.start..s.params.end]) |p| {
                const cap = c.capIn(p.type, 0) orelse continue;
                const cap_name = try c.tn(cap);
                const listed = for (names) |tok| {
                    if (std.mem.eql(u8, c.text(tok), cap_name)) break true;
                } else false;
                if (listed) continue;
                const list = if (names.len == 0) "nothing" else c.k.tree.source[c.k.tree.tokens[names[0]].start..c.k.tree.tokens[names[names.len - 1]].end];
                try c.report(.recipe_needs, c.node(p.node).main_token, try c.print("{s} takes a {s}, but recipe {s} needs {s}; add {s} to its needs line.", .{ s.name, cap_name, c.text(n.main_token), list, cap_name }));
            }
        }
    }

    // ---- bodies: deadlines, fixtures, purity

    fn hasWithin(c: *Caps, n: ast.Node) bool {
        if (n.kind != .member_call and n.kind != .call) return false;
        for (c.spanAt(n.rhs)) |a| {
            const an = c.node(a);
            if (an.kind == .named_arg and std.mem.eql(u8, c.text(an.main_token), "within")) return true;
        }
        return false;
    }

    fn callLabel(c: *Caps, n: ast.Node, row: prelude.Fn) Error![]const u8 {
        const recv = c.node(n.lhs);
        if (recv.kind == .name_ref or recv.kind == .type_name_ref) return c.print("{s}.{s}", .{ c.text(recv.main_token), row.name });
        const head = row.recv[0 .. std.mem.indexOfScalar(u8, row.recv, '(') orelse row.recv.len];
        return c.print("{s}.{s}", .{ head, row.name });
    }

    fn bodies(c: *Caps) Error!void {
        for (c.units.items) |u| {
            var pure_reported = false;
            // The names bound in this unit to an Fs narrowed to read_only.
            var read_only: std.ArrayList([]const u8) = .empty;
            var i = u.first;
            while (i <= u.last) : (i += 1) {
                const n = c.node(i);
                if (n.kind == .binding or n.kind == .var_binding) {
                    const name = c.text(n.main_token);
                    var k: usize = 0;
                    while (k < read_only.items.len) {
                        if (std.mem.eql(u8, read_only.items[k], name)) _ = read_only.swapRemove(k) else k += 1;
                    }
                    if (c.readOnly(n.lhs, read_only.items)) try read_only.append(c.gpa, name);
                }
                switch (c.k.callee[i]) {
                    .prelude => |p| {
                        const row = prelude.fns[p];
                        if (writesFiles(row) and c.readOnly(n.lhs, read_only.items)) {
                            const src = c.k.tree.source;
                            const receiver = std.mem.trim(u8, src[c.k.tree.tokens[c.firstToken(n.lhs)].start..c.k.tree.tokens[n.main_token - 1].start], " \t\r\n");
                            try c.report(.flows_violated, n.main_token, try c.print("{s} writes through {s}, which was narrowed to read_only and only reads; write through the Fs it was narrowed from.", .{ try c.callLabel(n, row), receiver }));
                        }
                        if (row.only == .tests and u.kind != .test_block) {
                            const capability = if (prelude.findType(row.recv)) |t| t.kind == .capability else false;
                            const what = if (!std.mem.eql(u8, row.name, "fixture"))
                                try c.print("{s}.{s} reads what an {s}.fixture() kept, which only a test has.", .{ row.recv, row.name, row.recv })
                            else if (capability)
                                try c.print("{s}.fixture() builds a capability for tests; outside a test, take a {s} parameter instead.", .{ row.recv, row.recv })
                            else
                                try c.print("{s}.fixture() is a {s} for tests; outside a test, take a {s} parameter instead.", .{ row.recv, row.recv, row.recv });
                            try c.report(.outside_params, n.main_token, what);
                            pure_reported = true;
                        }
                        const within = c.hasWithin(n);
                        if (row.can_wait and !within) {
                            try c.report(.missing_within, n.main_token, try c.print("{s} has no within: deadline; add one, such as within: 100.ms.", .{try c.callLabel(n, row)}));
                        } else if (!row.can_wait and within) {
                            try c.report(.needless_within, n.main_token, try c.print("{s} cannot wait, so it takes no within:; remove the deadline.", .{try c.callLabel(n, row)}));
                        }
                    },
                    .user => |s| if (c.hasWithin(n)) {
                        try c.report(.needless_within, c.firstToken(i), try c.print("{s} does not wait itself, so it takes no within:; the calls inside it carry their own.", .{c.k.sigs[s].name}));
                    },
                    .none => {},
                }
                if ((u.kind == .function or u.kind == .process) and !u.has_caps and !pure_reported and isValue(n.kind)) {
                    const t = c.k.typeOf(i);
                    if (c.baseTag(t).tag == .cap) {
                        try c.report(.outside_params, c.firstToken(i), try c.print("{s} has no capability parameter, so it is pure and cannot use a {s}; take a {s} parameter.", .{ u.name, try c.tn(t), try c.tn(t) }));
                        pure_reported = true;
                    }
                }
            }
        }
    }

    /// The Fs rows that change the file system.
    fn writesFiles(row: prelude.Fn) bool {
        if (!std.mem.eql(u8, row.recv, "Fs")) return false;
        for ([_][]const u8{ "write", "append", "remove", "rename" }) |name| {
            if (std.mem.eql(u8, row.name, name)) return true;
        }
        return false;
    }

    /// Whether an Fs expression is narrowed to read_only where this unit can see it:
    /// `x.read_only`, `scoped` on one, or a name bound to one. An Fs parameter may be
    /// either, so it is not; the run refuses a write through one (stdlib.zig, server.zig).
    fn readOnly(c: *Caps, i: Index, names: []const []const u8) bool {
        const n = c.node(i);
        switch (n.kind) {
            .member, .member_call => switch (c.k.callee[i]) {
                .prelude => |p| {
                    const row = prelude.fns[p];
                    if (!std.mem.eql(u8, row.recv, "Fs")) return false;
                    if (std.mem.eql(u8, row.name, "read_only")) return true;
                    return std.mem.eql(u8, row.name, "scoped") and c.readOnly(n.lhs, names);
                },
                else => return false,
            },
            .name_ref => {
                for (names) |name| if (std.mem.eql(u8, name, c.text(n.main_token))) return true;
                return false;
            },
            else => return false,
        }
    }

    fn isValue(kind: ast.Node.Kind) bool {
        return switch (kind) {
            .name_ref, .member, .member_call, .call => true,
            else => false,
        };
    }

    // ---- flows

    fn flowRules(c: *Caps) Error!void {
        for (c.k.flows) |f| {
            const call = c.node(f);
            const args = c.spanAt(call.rhs);
            const sentence = for (c.items()) |it| {
                if (c.node(it).kind == .never and c.node(it).rhs == f) break c.text(c.node(it).lhs);
            } else "";
            var subject: ?Id = null;
            var into: ?Id = null;
            for (args) |a| {
                const an = c.node(a);
                if (an.kind == .named_arg) {
                    if (!std.mem.eql(u8, c.text(an.main_token), "into")) continue;
                    const v = c.node(an.lhs);
                    if (v.kind != .type_name_ref) continue;
                    const t = checker.primitive(c.text(v.main_token)) orelse continue;
                    if (c.k.pool.get(t).tag == .cap) into = t;
                } else if (subject == null and an.kind == .type_name_ref) {
                    subject = c.typeNamed(a, c.text(an.main_token));
                }
            }
            if (subject == null) {
                try c.report(.bad_flows, call.main_token, "flows names a declared or prelude type first, such as flows(CardNumber, into: Events).");
                continue;
            }
            const cap = into orelse {
                try c.report(.bad_flows, call.main_token, "flows names a capability after into:, such as into: Events.");
                continue;
            };
            try c.checkFlow(subject.?, cap, sentence);
        }
    }

    fn typeNamed(c: *Caps, at: Index, name: []const u8) ?Id {
        if (c.k.findDeclAt(at, name)) |d| {
            const decl = c.k.decls[d];
            return switch (decl.kind) {
                .struct_, .enum_, .alias, .opaque_ => decl.type,
                else => null,
            };
        }
        const t = checker.primitive(name) orelse return null;
        return if (c.k.pool.get(t).tag == .cap) null else t;
    }

    fn checkFlow(c: *Caps, subject: Id, cap: Id, sentence: []const u8) Error!void {
        for (c.units.items) |u| {
            var tainted: std.ArrayList([]const u8) = .empty;
            var i = u.first;
            while (i <= u.last) : (i += 1) {
                const n = c.node(i);
                switch (n.kind) {
                    .binding, .var_binding => if (try c.carries(n.lhs, subject, tainted.items, 0)) {
                        try tainted.append(c.gpa, c.text(n.main_token));
                    },
                    .member_call => {
                        if (c.k.callee[i] != .prelude) continue;
                        if (c.k.pool.base(c.k.typeOf(n.lhs)) != cap) continue;
                        for (c.spanAt(n.rhs)) |a| {
                            const an = c.node(a);
                            if (an.kind == .named_arg and std.mem.eql(u8, c.text(an.main_token), "within")) continue;
                            if (!try c.carries(a, subject, tainted.items, 0)) continue;
                            const row = prelude.fns[c.k.callee[i].prelude];
                            try c.report(.flows_violated, c.firstToken(a), try c.print("a {s} reaches {s} through {s}; the never {s} forbids it.", .{ try c.tn(subject), try c.callLabel(n, row), c.argText(a), sentence }));
                            break;
                        }
                    },
                    else => {},
                }
            }
        }
    }

    fn carries(c: *Caps, i: Index, subject: Id, tainted: []const []const u8, depth: u8) Error!bool {
        if (depth > 16) return false;
        if (c.holds(c.k.node_types[i], subject, 0)) return true;
        const n = c.node(i);
        switch (n.kind) {
            .string_interp, .tuple => for (c.k.tree.span(n.lhs, n.rhs)) |part| {
                if (c.node(part).kind != .string_part and try c.carries(part, subject, tainted, depth + 1)) return true;
            },
            .name_ref => for (tainted) |name| {
                if (std.mem.eql(u8, name, c.text(n.main_token))) return true;
            },
            .named_arg => return c.carries(n.lhs, subject, tainted, depth + 1),
            .call => if (c.node(n.lhs).kind == .type_name_ref) {
                for (c.spanAt(n.rhs)) |a| if (try c.carries(a, subject, tainted, depth + 1)) return true;
            },
            else => {},
        }
        return false;
    }

    /// Whether a value of type `t` holds a `subject` in itself or in a field.
    fn holds(c: *Caps, t: Id, subject: Id, depth: u8) bool {
        if (depth > 8) return false;
        const pool = &c.k.pool;
        const rt = pool.resolve(t);
        const rs = pool.resolve(subject);
        if (rt == rs) return true;
        const a = pool.get(rt);
        const s = pool.get(rs);
        switch (a.tag) {
            // An alias is its own type here: a String is not a CardNumber.
            .alias => return s.tag == .alias and a.a == s.a,
            .decl => {
                if (s.tag == .decl and a.a == s.a) return true;
                const d = c.k.decls[a.a];
                if (d.kind == .struct_) {
                    for (c.k.fields[d.fields.start..d.fields.end]) |f| if (c.holds(f.type, subject, depth + 1)) return true;
                } else if (d.kind == .enum_ or d.kind == .prelude_enum) {
                    for (c.k.variants[d.variants.start..d.variants.end]) |v| {
                        for (c.k.fields[v.fields.start..v.fields.end]) |f| if (c.holds(f.type, subject, depth + 1)) return true;
                    }
                }
                return false;
            },
            .tuple => {
                for (pool.elems(a)) |e| if (c.holds(e, subject, depth + 1)) return true;
                return false;
            },
            .option => return c.holds(a.a, subject, depth + 1),
            .result => return c.holds(a.a, subject, depth + 1) or c.holds(a.b, subject, depth + 1),
            // Tier 1 does not chase through collections.
            .list, .map, .set => return false,
            else => return s.tag == a.tag and s.tag != .alias and s.tag != .decl and a.a == s.a and a.tag != .unknown and a.tag != .variable,
        }
    }
};

// ---- tests

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

fn capsOf(arena: std.mem.Allocator, src: []const u8) ![]const diag.Record {
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    const checked = try checker.check(arena, tree, &diags);
    try check(arena, checked, &diags);
    return diags.items;
}

fn expectCodes(src: []const u8, codes: []const []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try capsOf(arena_state.allocator(), src);
    var ok = found.len == codes.len;
    if (ok) for (found, codes) |d, code| {
        if (!std.mem.eql(u8, d.code, code)) ok = false;
    };
    if (!ok) {
        std.debug.print("expected {d} diagnostics:", .{codes.len});
        for (codes) |code| std.debug.print(" {s}", .{code});
        std.debug.print("\nfound:\n", .{});
        for (found) |d| std.debug.print("  {s}: {s}\n", .{ d.code, d.what });
    }
    try std.testing.expect(ok);
}

test "a call that can wait needs within:, and one that cannot takes none" {
    try expectCodes(
        \\module T.Wait
        \\enum E
        \\  Missing(path: String)
        \\  Timeout
        \\end
        \\fn load(fs: Fs, clock: Clock) : Result(Time, E)
        \\  text = try fs.read("/a")
        \\  return Error(Missing(path: text)) if clock.now(within: 10.ms) == clock.now
        \\  Ok(clock.now)
        \\end
    , &.{ "MO0401", "MO0402" });
}

test "a capability comes only from a parameter: no fixture outside tests, none in a field, none returned" {
    try expectCodes(
        \\module T.Params
        \\struct Job
        \\  clock: Clock
        \\end
        \\fn make(fs: Fs) : Fs
        \\  fs
        \\end
        \\fn now() : Time
        \\  Clock.fixture().now
        \\end
        \\test "a fixture is fine here"
        \\  assert Clock.fixture().now == Clock.fixture().now
        \\end
    , &.{ "MO0403", "MO0403", "MO0403" });
}

test "a fixture outside a test names what it builds: a capability, or a value such as a Time" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try capsOf(arena_state.allocator(),
        \\module T.Fixtures
        \\fn epoch() : Time
        \\  Time.fixture()
        \\end
        \\fn clock() : Time
        \\  Clock.fixture().now
        \\end
    );
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expectEqualStrings("Time.fixture() is a Time for tests; outside a test, take a Time parameter instead.", found[0].what);
    try std.testing.expectEqualStrings("Clock.fixture() builds a capability for tests; outside a test, take a Clock parameter instead.", found[1].what);
}

test "a function without a capability parameter is pure" {
    try expectCodes(
        \\module T.Pure
        \\struct Box
        \\  fs: Fs
        \\end
        \\fn peek(b: Box) : Fs
        \\  b.fs.read_only
        \\end
    , &.{ "MO0403", "MO0403", "MO0403" });
}

test "flows: a T reaching the capability by field, interpolation, or a bound name" {
    const header =
        \\module T.Flows
        \\never "a card reaches an event"
        \\  flows(Card, into: Events)
        \\end
        \\type Card = String where value.size == 16
        \\struct Pay
        \\  card: Card
        \\  cents: UInt32
        \\end
        \\
    ;
    try expectCodes(header ++
        \\fn log(events: Events, p: Pay) : UInt32
        \\  events.emit(p.cents)
        \\  events.emit("paid #{p.cents}")
        \\  p.cents
        \\end
    , &.{});
    try expectCodes(header ++
        \\fn log(events: Events, p: Pay) : UInt32
        \\  events.emit(p)
        \\  line = "card #{p.card}"
        \\  events.emit(line)
        \\  p.cents
        \\end
    , &.{ "MO0404", "MO0404" });
    try expectCodes(
        \\module T.BadFlows
        \\never "nothing flows"
        \\  flows(Nothing, into: Clock)
        \\end
    , &.{"MO0405"});
}

test "a write through an Fs narrowed to read_only, where the function can see it, is refused" {
    try expectCodes(
        \\module T.ReadOnly
        \\fn save(fs: Fs, text: String) : Bool
        \\  var logs = fs.scoped("logs").read_only
        \\  wrote = fs.write("a.txt", text, within: 1.minute) is Ok(_)
        \\  kept = logs.scoped("old").append("b.txt", text, within: 1.minute) is Ok(_)
        \\  gone = fs.read_only.remove("c.txt", within: 1.minute) is Ok(_)
        \\  logs = fs
        \\  moved = logs.rename("a.txt", "b.txt", within: 1.minute) is Ok(_)
        \\  wrote and kept and gone and moved
        \\end
    , &.{ "MO0404", "MO0404" });
}

test "a recipe's signatures take only the capabilities its needs line names" {
    try expectCodes(
        \\module T.Recipe
        \\recipe Stamp
        \\  intent "Stamp a note with the time"
        \\  needs nothing
        \\  fn stamp(clock: Clock, note: String) : String
        \\  end
        \\  test "stamps"
        \\    assert stamp(Clock.fixture(), "a") == "a"
        \\  end
        \\end
    , &.{"MO0406"});
}

test "main reads its Platform's parts and passes them down; the Platform itself stays" {
    try expectCodes(
        \\module T.Main
        \\fn greet(out: Out, name: String) : String
        \\  out.write("hello, #{name}")
        \\  name
        \\end
        \\fn main(platform: Platform)
        \\  name = platform.env.get("USER") or "you"
        \\  said = greet(platform.stdout, name)
        \\  platform.stderr.write(said)
        \\  platform.exit(3)
        \\end
    , &.{});
    try expectCodes(
        \\module T.Leak
        \\struct Held
        \\  platform: Platform
        \\end
        \\fn leak(platform: Platform) : UInt8
        \\  0
        \\end
        \\fn main(platform: Platform)
        \\  p = platform
        \\  platform.stdout.write("#{p}", within: 1.ms)
        \\end
    , &.{ "MO0403", "MO0407", "MO0402", "MO0407", "MO0407" });
    try expectCodes(
        \\module T.Twice
        \\fn main(platform: Platform)
        \\  platform.exit(0)
        \\end
        \\fn main(platform: Platform)
        \\  platform.exit(1)
        \\end
    , &.{"MO0205"});
}
