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

pub const Code = enum { missing_within, needless_within, outside_params, flows_violated, bad_flows, recipe_needs, platform_escapes, no_main, authority_captured, moved, reply_kept };

pub const catalog = std.enums.EnumArray(Code, checker.Entry).init(.{
    .missing_within = .{ .code = "MO0401", .category = .capabilities, .what = "<call> has no within: deadline; add one, such as within: 100.ms.", .why = "Every call that can wait carries a deadline (chapter 2, bounding laws), so nothing blocks forever; a timeout comes back as an ordinary error the caller handles.", .fixes = &.{} },
    .needless_within = .{ .code = "MO0402", .category = .capabilities, .what = "<call> cannot wait, so it takes no within:; remove the deadline.", .why = "Only a call that can wait takes within: (the platform marks which ones, toolchain/PRELUDE.md); a deadline on a call that cannot wait says something false.", .fixes = &.{} },
    .outside_params = .{ .code = "MO0403", .category = .capabilities, .what = "<function> has no capability parameter, so it is pure and cannot use a <Capability>; take a <Capability> parameter.", .why = "A capability is held only as a parameter and narrowed on the way down (chapter 3, effects), so a function's signature is the complete list of what it can touch.", .fixes = &.{} },
    .flows_violated = .{ .code = "MO0404", .category = .capabilities, .what = "<owner> writes through <its parameter, or a message's field>, and <value> was narrowed to read_only and only reads; hand it the Fs <value> was narrowed from.", .why = "An Fs narrowed to read_only promises that nothing is written through it, so tier 1 follows it wherever this unit hands it on: into a function's parameter, a process's start argument, a supervisor's child line, or a message's field, through a name bound to it and through each branch of an if or a case, and refuses it where the call on the other side writes through what it is given; a write through it in the same unit is refused too (fs.write writes through logs, which was narrowed to read_only). The same code stands for a never with flows(T, into: Cap), which promises that no value of type T reaches a call on Cap: a <Type> reaches <call> through <value>; the never <rule> forbids it.", .fixes = &.{} },
    .bad_flows = .{ .code = "MO0405", .category = .capabilities, .what = "flows names a declared or prelude type first, such as flows(CardNumber, into: Events).", .why = "flows(T, into: Cap) names a type first and a capability after into:, so the rule can be checked; a never that cannot be checked does not compile.", .fixes = &.{} },
    .recipe_needs = .{ .code = "MO0406", .category = .capabilities, .what = "<function> takes a <Capability>, but recipe <Recipe> needs <capabilities>; add <Capability> to its needs line.", .why = "A recipe's needs line is the list of capabilities its implementation may take (chapter 6), so every capability in its signatures is named there, and only capabilities are.", .fixes = &.{} },
    .platform_escapes = .{ .code = "MO0407", .category = .capabilities, .what = "<function> takes a Platform, which only main holds; take the parts it uses instead, such as an Fs or an Out.", .why = "A Platform exists only as fn main's parameter (Q18): main reads its parts and passes each one down, narrowed, so no other function can reach everything the program holds.", .fixes = &.{} },
    .authority_captured = .{ .code = "MO0409", .category = .capabilities, .what = "the anonymous function captures <name>, a <Capability or Handle>; pass <name> as a parameter to a named function instead.", .why = "An anonymous function captures read-only, but a capability or a handle is authority: captured, it lets a call that takes only data, such as map, perform an effect no signature shows (chapter 3, effects). Authority travels only as a parameter, so a named function that takes it says what it touches.", .fixes = &.{} },
    .moved = .{ .code = "MO0410", .category = .capabilities, .what = "<name> went to another process in <Message>, so it is no longer this function's; use it before the send, or not at all.", .why = "A message may carry a capability its message line declares (chapter 3, processes; step 20), and a capability in a message moves rather than being copied: once sent it is the receiving process's, so two processes never act through one connection at once. The checker refuses every use of the name after the send in the function that sent it, and on the next pass of a for; a copy it cannot see, such as a start argument sent in one update and used in the next, still reaches the same connection.", .fixes = &.{} },
    .reply_kept = .{ .code = "MO0411", .category = .capabilities, .what = "<Message>'s arm mentions reply_to but does not hand it to a state field; write state.<field> = ... reply_to ... once, and answer it later with reply.answer(value).", .why = "An arm for a message that carries a reply answers the ask in one of two ways, never both and never neither (chapter 3, processes; step 31): its value is the reply, as it has always been, or it keeps the asker by moving reply_to into a state field and answers it from a later arm with reply.answer(value). reply_to moves as a capability in a message moves (MO0410): the arm names it exactly once, inside an assignment to a place under state, and every later read of it is refused, since the asker is the state's now. A Reply the state drops without answering is no error: the asker times out at its own deadline, as it would if the process never answered.", .fixes = &.{} },
    .no_main = .{ .code = "MO0408", .category = .capabilities, .what = "this module has no fn main(platform: Platform), so mo run has nothing to run; mo test runs its tests", .why = "mo run starts a program at fn main(platform: Platform), the one place it receives its capabilities (Q18). A module without main has nothing to run; mo test runs its tests.", .fixes = &.{} },
});

pub fn check(gpa: std.mem.Allocator, checked: checker.Checked, out: *diag.List) Error!void {
    var c: Caps = .{ .gpa = gpa, .k = &checked, .out = out };
    try c.buildUnits();
    try c.declarations();
    try c.bodies();
    try c.platformUses();
    try c.flowRules();
    try c.captures();
    try c.moves();
    try c.keptReplies();
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
    /// The token of each name a process's update binds to a field of its message (armFields).
    arm_fields: std.AutoHashMapUnmanaged(u32, Field) = .empty,

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

    /// The source of an argument, up to the `,` or `)` that ends it, or the `else` or `end` that
    /// ends a branch of an `if` it sits in (step 25).
    fn argText(c: *Caps, i: Index) []const u8 {
        const toks = c.k.tree.tokens;
        const first = c.firstToken(i);
        var depth: u32 = 0;
        var t = first;
        var last = first;
        while (true) : (t += 1) switch (toks[t].kind) {
            .l_paren, .l_bracket, .l_brace => {
                depth += 1;
                last = t;
            },
            .r_paren, .r_bracket, .r_brace => {
                if (depth == 0) break;
                depth -= 1;
                last = t;
            },
            .comma, .newline, .kw_else, .kw_end => if (depth == 0) break else {
                last = t;
            },
            .eof => break,
            else => last = t,
        };
        return c.k.tree.source[toks[first].start..toks[last].end];
    }

    fn baseTag(c: *Caps, t: Id) types.Type {
        return c.k.pool.get(c.k.pool.base(t));
    }

    /// The first capability or handle inside `t`, looking through lists, options, results, and
    /// tuples. A handle is authority like a capability (step 18): a function that holds one is
    /// effectful, and a value or an anonymous function cannot hold one.
    fn capIn(c: *Caps, t: Id, depth: u8) ?Id {
        return checker.authorityIn(&c.k.pool, t, depth);
    }

    /// capIn, without handles: a function may return the handle it started or was given, and a
    /// recipe's needs line names only capabilities.
    fn capOnlyIn(c: *Caps, t: Id) ?Id {
        const found = c.capIn(t, 0) orelse return null;
        return if (c.k.pool.get(found).tag == .cap) found else null;
    }

    fn paramsHaveCaps(c: *Caps, r: checker.Range) bool {
        for (c.k.params[r.start..r.end]) |p| if (c.capIn(p.type, 0) != null) return true;
        return false;
    }

    /// A process whose message lines declare a capability or a handle receives authority
    /// through its protocol (step 20), so its update is not pure.
    fn messagesHaveCaps(c: *Caps, d: checker.Decl) bool {
        if (d.kind != .process) return false;
        for (c.k.variants[d.variants.start..d.variants.end]) |v| {
            for (c.k.fields[v.fields.start..v.fields.end]) |f| if (c.capIn(f.type, 0) != null) return true;
        }
        return false;
    }

    /// Whether one supervisor names both `a` and `b` as children.
    fn siblings(c: *Caps, a: []const u8, b: []const u8) bool {
        for (c.items()) |it| {
            const n = c.node(it);
            if (n.kind != .supervisor_decl) continue;
            var has_a = false;
            var has_b = false;
            for (c.spanAt(n.rhs)) |ch| {
                const name = c.text(c.node(ch).main_token);
                if (std.mem.eql(u8, name, a)) has_a = true;
                if (std.mem.eql(u8, name, b)) has_b = true;
            }
            if (has_a and has_b) return true;
        }
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
                    for (c.k.tree.span(r.nevers_start, r.nevers_end)) |nv| {
                        try c.addUnit(.{ .kind = .never, .first = p + 1, .last = nv });
                        p = nv;
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
                    const has = if (d) |x| c.paramsHaveCaps(c.k.decls[x].params) or c.messagesHaveCaps(c.k.decls[x]) or c.stateHasHandles(c.k.decls[x]) else false;
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
            switch (d.kind) {
                .struct_ => try c.fieldCaps(d.fields),
                .process => try c.stateCaps(d.fields),
                else => {},
            }
            // A message line may declare a capability or a handle (step 20): the protocol
            // shows the authority the process receives. A struct or an enum may not, and a state
            // only a handle (step 24).
            if (d.kind == .enum_) {
                for (c.k.variants[d.variants.start..d.variants.end]) |v| try c.fieldCaps(v.fields);
            }
        }
        for (c.k.sigs) |s| {
            if (c.capOnlyIn(s.ret)) |cap| try c.report(.outside_params, c.node(s.node).main_token, try c.print("{s} returns a {s}; a capability is passed down as a parameter, never returned.", .{ s.name, try c.tn(cap) }));
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

    /// A process's state field may keep the handles of processes (step 24): a state is owned by
    /// exactly one process, and the runtime counts the handles it holds as it counts those in start
    /// arguments. It keeps one as `Handle(P)`, `Option(Handle(P))`, `List(Handle(P))`, or
    /// `Map(K, Handle(P))`; a capability, or a handle inside anything else, stays refused.
    fn stateCaps(c: *Caps, r: checker.Range) Error!void {
        for (c.k.fields[r.start..r.end]) |f| {
            if (f.node == 0) continue;
            const found = c.capIn(f.type, 0) orelse continue;
            if (c.k.pool.get(found).tag == .reply and c.keptHandle(f.type)) continue;
            if (c.k.pool.get(found).tag == .handle and c.keptHandle(f.type)) continue;
            if (c.k.pool.get(found).tag == .cap) {
                try c.report(.outside_params, c.node(f.node).main_token, try c.print("{s} holds a {s}; a capability travels only as a parameter, never inside a value.", .{ f.name, try c.tn(found) }));
                continue;
            }
            try c.report(.outside_params, c.node(f.node).main_token, try c.print("{s} holds a {s} inside a {s}; a state field keeps a handle only as {s}, Option({s}), List({s}), or Map(K, {s}).", .{ f.name, try c.tn(found), try c.tn(f.type), try c.tn(found), try c.tn(found), try c.tn(found), try c.tn(found) }));
        }
    }

    /// `Handle(P)` or `Reply(T)`, or an Option or a List of one, or a Map whose values are one and
    /// whose keys hold no authority (step 24; step 31 gives a Reply the same four shapes).
    fn keptHandle(c: *Caps, t: Id) bool {
        const b = c.baseTag(t);
        return switch (b.tag) {
            .handle, .reply => true,
            .option, .list => c.kept1(b.a),
            .map => c.capIn(b.a, 0) == null and c.kept1(b.b),
            else => false,
        };
    }

    fn kept1(c: *Caps, t: Id) bool {
        const tag = c.baseTag(t).tag;
        return tag == .handle or tag == .reply;
    }

    // ---- an arm that keeps its asker (step 31)

    /// An arm that mentions `reply_to` keeps the asker instead of answering: it names reply_to
    /// exactly once, on the right of an assignment to a place under `state`, and never again.
    fn keptReplies(c: *Caps) Error!void {
        for (c.k.decls) |d| {
            if (d.kind != .process or d.node == 0) continue;
            const data = c.k.tree.extraData(ast.Process, c.node(d.node).lhs);
            if (data.update == 0 or c.node(data.update).lhs == 0) continue;
            const cn = c.node(c.node(data.update).lhs);
            if (cn.kind != .case_stmt and cn.kind != .case_expr) continue;
            for (c.spanAt(cn.rhs)) |a| try c.keptInArm(a);
        }
    }

    fn keptInArm(c: *Caps, arm: Index) Error!void {
        const an = c.node(arm);
        const d = c.k.tree.extraData(ast.Arm, an.rhs);
        const body = c.k.tree.span(d.body_start, d.body_end);
        if (body.len == 0 or c.k.binding_of.len == 0) return;
        const lo = (if (d.guard != 0) d.guard else an.lhs) + 1;
        const hi = body[body.len - 1];
        var refs: std.ArrayList(Index) = .empty;
        var j = lo;
        while (j <= hi) : (j += 1) {
            const n = c.node(j);
            if (n.kind != .name_ref or c.k.binding_of[j] == 0) continue;
            if (std.mem.eql(u8, c.text(n.main_token), "reply_to")) try refs.append(c.gpa, j);
        }
        if (refs.items.len == 0) return;
        const message = c.text(c.node(an.lhs).main_token);
        if (!c.movedIntoState(lo, hi, refs.items[0])) {
            try c.report(.reply_kept, c.node(refs.items[0]).main_token, try c.print("{s}'s arm mentions reply_to but does not hand it to a state field; write state.<field> = ... reply_to ... once, and answer it later with reply.answer(value).", .{message}));
            return;
        }
        for (refs.items[1..]) |r| try c.report(.reply_kept, c.node(r).main_token, try c.print("reply_to is the state's once {s}'s arm has kept it; read it back from the state field, or answer it with reply.answer(value).", .{message}));
    }

    /// Whether node `at` is on the right of an assignment to a place under `state`, among the
    /// nodes [lo, hi]. A node of the right side lies between the place's root and the value's.
    fn movedIntoState(c: *Caps, lo: Index, hi: Index, at: Index) bool {
        var i = lo;
        while (i <= hi) : (i += 1) {
            const n = c.node(i);
            if (n.kind != .assign or at <= n.lhs or at > n.rhs) continue;
            if (c.placeRootIsState(n.lhs)) return true;
        }
        return false;
    }

    fn placeRootIsState(c: *Caps, place: Index) bool {
        var i = place;
        for (0..64) |_| {
            const n = c.node(i);
            switch (n.kind) {
                .name_ref => return std.mem.eql(u8, c.text(n.main_token), "state"),
                .member, .tuple_index, .member_call => i = n.lhs,
                else => return false,
            }
        }
        return false;
    }

    /// A process whose state keeps a handle holds authority in its box (step 24).
    fn stateHasHandles(c: *Caps, d: checker.Decl) bool {
        if (d.kind != .process) return false;
        for (c.k.fields[d.fields.start..d.fields.end]) |f| if (checker.handleIn(&c.k.pool, f.type, 0)) return true;
        return false;
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
                const cap = c.capOnlyIn(p.type) orelse continue;
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
        const writes = try c.writesThrough();
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
                    .user => |s| {
                        if (c.hasWithin(n)) try c.report(.needless_within, c.firstToken(i), try c.print("{s} does not wait itself, so it takes no within:; the calls inside it carry their own.", .{c.k.sigs[s].name}));
                    },
                    .none => {},
                }
                try c.handedReadOnly(i, writes, read_only.items);
                if ((u.kind == .function or u.kind == .process) and !u.has_caps and !pure_reported and isValue(n.kind)) {
                    const t = c.k.typeOf(i);
                    const b = c.baseTag(t);
                    // A process may start, and send to, the processes its own supervisor names as
                    // children, with no capability (step 20); a function needs one.
                    const sibling = u.kind == .process and b.tag == .handle and c.siblings(u.name, c.k.decls[b.a].name);
                    if ((b.tag == .cap or b.tag == .handle) and !sibling) {
                        try c.report(.outside_params, c.firstToken(i), try c.print("{s} has no capability parameter, so it is pure and cannot use a {s}; take a {s} parameter.", .{ u.name, try c.tn(t), try c.tn(t) }));
                        pure_reported = true;
                    }
                }
            }
        }
    }

    // ---- a read-only Fs handed to a function, a process, or a message that writes through it

    /// What an Fs expression reaches inside the unit it is in: a parameter of the function, the
    /// process, or the supervisor, or a field of the message the process's update took.
    const Root = union(enum) { param: u32, field: Field };
    const Field = struct { variant: u32, field: u32 };
    const Bound = struct { name: []const u8, root: Root };

    /// Where files are written through, settled over the call graph so recursion and calls to
    /// later functions are followed: per signature, per parameter; per process or supervisor, per
    /// start parameter; and per message, per field (step 24), each directly, through a scope, or
    /// by handing either to a function, a start, a child line, or a message that writes.
    const Writes = struct { sigs: [][]bool, decls: [][]bool, variants: [][]bool };

    /// An expression handed on to something that writes through it, and the words that say where.
    const Site = struct { arg: Index, owner: []const u8, label: []const u8 };

    fn falses(c: *Caps, n: usize) Error![]bool {
        const out = try c.gpa.alloc(bool, n);
        @memset(out, false);
        return out;
    }

    fn writesThrough(c: *Caps) Error!Writes {
        const k = c.k;
        const w: Writes = .{
            .sigs = try c.gpa.alloc([]bool, k.sigs.len),
            .decls = try c.gpa.alloc([]bool, k.decls.len),
            .variants = try c.gpa.alloc([]bool, k.variants.len),
        };
        for (k.sigs, w.sigs) |s, *x| x.* = try c.falses(s.params.len());
        for (k.decls, w.decls) |d, *x| x.* = try c.falses(d.params.len());
        for (k.variants, w.variants) |v, *x| x.* = try c.falses(v.fields.len());
        try c.armFields();
        var changed = true;
        while (changed) {
            changed = false;
            for (c.units.items) |u| {
                const owner: []bool, const r: checker.Range = switch (u.kind) {
                    .function => blk: {
                        const si = c.sigIndexOf(u.last) orelse continue;
                        break :blk .{ w.sigs[si], k.sigs[si].params };
                    },
                    .process, .supervisor => blk: {
                        const d = k.findDeclAt(u.last, u.name) orelse continue;
                        break :blk .{ w.decls[d], k.decls[d].params };
                    },
                    else => continue,
                };
                const params = k.params[r.start..r.end];
                var bound: std.ArrayList(Bound) = .empty;
                var i = u.first;
                while (i <= u.last) : (i += 1) {
                    const n = c.node(i);
                    if (n.kind == .binding or n.kind == .var_binding) {
                        if (c.rootOf(n.lhs, params, bound.items)) |p| try bound.append(c.gpa, .{ .name = c.text(n.main_token), .root = p });
                    }
                    if (k.callee[i] == .prelude and writesFiles(prelude.fns[k.callee[i].prelude])) {
                        if (c.rootOf(n.lhs, params, bound.items)) |p| changed = c.mark(w, owner, p) or changed;
                    }
                    for (try c.handed(i, w)) |s| {
                        if (c.rootOf(s.arg, params, bound.items)) |p| changed = c.mark(w, owner, p) or changed;
                    }
                }
            }
        }
        return w;
    }

    /// Marks a root written through; true when it was not yet.
    fn mark(c: *Caps, w: Writes, owner: []bool, root: Root) bool {
        _ = c;
        const slot = switch (root) {
            .param => |p| &owner[p],
            .field => |f| &w.variants[f.variant][f.field],
        };
        if (slot.*) return false;
        slot.* = true;
        return true;
    }

    fn sigIndexOf(c: *Caps, n: Index) ?u32 {
        for (c.k.sigs, 0..) |s, si| if (s.node == n) return @intCast(si);
        return null;
    }

    /// Every name a process's update binds to a field of the message it took, by the name's token:
    /// `Write(files: f)` binds f to Write's field files, and `Take(conn)` to Take's one field.
    fn armFields(c: *Caps) Error!void {
        for (c.units.items) |u| {
            if (u.kind != .process) continue;
            const top = c.unitStatements(u) orelse continue;
            const d = c.k.findDeclAt(u.last, u.name) orelse continue;
            const case = c.node(top.one);
            if (case.kind != .case_stmt and case.kind != .case_expr) continue;
            for (c.spanAt(case.rhs)) |arm| {
                const one = [1]u32{c.node(arm).lhs};
                const p = c.node(arm).lhs;
                const alts: []const u32 = if (c.node(p).kind == .pat_or) c.k.tree.span(c.node(p).lhs, c.node(p).rhs) else &one;
                for (alts) |alt| {
                    const an = c.node(alt);
                    const v = c.variantOf(c.k.decls[d], c.text(an.main_token)) orelse continue;
                    const fields = c.k.fields[c.k.variants[v].fields.start..c.k.variants[v].fields.end];
                    switch (an.kind) {
                        .pat_variant => if (an.lhs != 0 and c.node(an.lhs).kind == .pat_bind and fields.len == 1) {
                            try c.arm_fields.put(c.gpa, c.node(an.lhs).main_token, .{ .variant = v, .field = 0 });
                        },
                        .pat_record => for (c.k.tree.span(an.lhs, an.rhs)) |pf| {
                            const bind = c.node(pf).lhs;
                            if (bind == 0 or c.node(bind).kind != .pat_bind) continue;
                            const name = c.text(c.node(pf).main_token);
                            for (fields, 0..) |f, fi| if (std.mem.eql(u8, f.name, name)) {
                                try c.arm_fields.put(c.gpa, c.node(bind).main_token, .{ .variant = v, .field = @intCast(fi) });
                            };
                        },
                        else => {},
                    }
                }
            }
        }
    }

    fn variantOf(c: *Caps, d: checker.Decl, name: []const u8) ?u32 {
        var v = d.variants.start;
        while (v < d.variants.end) : (v += 1) if (std.mem.eql(u8, c.k.variants[v].name, name)) return v;
        return null;
    }

    /// The Fs an expression reaches: a parameter by name, a local bound to one, a message field
    /// the update's arm bound, or `scoped` on any of those. Not through `read_only`, whose writes
    /// are refused where they are.
    fn rootOf(c: *Caps, i: Index, params: []const checker.Param, bound: []const Bound) ?Root {
        const n = c.node(i);
        switch (n.kind) {
            .name_ref => {
                const name = c.text(n.main_token);
                var k = bound.len;
                while (k > 0) {
                    k -= 1;
                    if (std.mem.eql(u8, bound[k].name, name)) return bound[k].root;
                }
                if (c.k.binding_of.len > i and c.k.binding_of[i] != 0) {
                    if (c.arm_fields.get(c.k.binding_of[i] - 1)) |f| return .{ .field = f };
                }
                for (params, 0..) |p, pk| {
                    if (std.mem.eql(u8, p.name, name) and c.baseTag(p.type).tag == .cap and c.baseTag(p.type).a == @intFromEnum(types.CapKind.fs)) return .{ .param = @intCast(pk) };
                }
                return null;
            },
            .member, .member_call => switch (c.k.callee[i]) {
                .prelude => |r| {
                    const row = prelude.fns[r];
                    if (!std.mem.eql(u8, row.recv, "Fs") or !std.mem.eql(u8, row.name, "scoped")) return null;
                    return c.rootOf(n.lhs, params, bound);
                },
                else => return null,
            },
            else => return null,
        }
    }

    /// The expressions node `i` hands to something `w` says writes through them: an argument to a
    /// function's parameter, a start argument to a process's or a supervisor's (by a start call or
    /// a child line), or a field of a message whose arm writes through it.
    fn handed(c: *Caps, i: Index, w: Writes) Error![]const Site {
        const k = c.k;
        const n = c.node(i);
        var out: std.ArrayList(Site) = .empty;
        switch (k.callee[i]) {
            .user => |s| {
                const params = k.params[k.sigs[s].params.start..k.sigs[s].params.end];
                for (try c.callArgs(i), 0..) |a, j| {
                    if (j >= w.sigs[s].len or !w.sigs[s][j]) continue;
                    try out.append(c.gpa, .{ .arg = a, .owner = k.sigs[s].name, .label = try c.print("its parameter {s}", .{params[j].name}) });
                }
            },
            .prelude => |r| {
                const row = prelude.fns[r];
                const starts = std.mem.eql(u8, row.recv, "Process") or std.mem.eql(u8, row.recv, "Supervisor");
                if (starts and n.kind == .member_call and c.node(n.lhs).kind == .type_name_ref) {
                    const d = k.findDeclAt(i, c.text(c.node(n.lhs).main_token)) orelse return out.items;
                    var j: usize = 0;
                    for (c.spanAt(n.rhs)) |a| {
                        if (c.node(a).kind == .named_arg) continue;
                        defer j += 1;
                        try c.startSite(&out, w, d, j, a);
                    }
                }
            },
            .none => switch (n.kind) {
                .child => {
                    const d = k.findDeclAt(i, c.text(n.main_token)) orelse return out.items;
                    const ch = k.tree.extraData(ast.Child, n.lhs);
                    for (k.tree.span(ch.args_start, ch.args_end), 0..) |a, j| try c.startSite(&out, w, d, j, a);
                },
                .call => {
                    const t = c.baseTag(k.typeOf(i));
                    if (t.tag != .message or c.node(n.lhs).kind != .type_name_ref) return out.items;
                    const d = k.decls[t.a];
                    const vname = c.text(c.node(n.lhs).main_token);
                    const v = c.variantOf(d, vname) orelse return out.items;
                    const fields = k.fields[k.variants[v].fields.start..k.variants[v].fields.end];
                    for (c.spanAt(n.rhs), 0..) |a, j| {
                        const an = c.node(a);
                        const fi = if (an.kind == .named_arg) for (fields, 0..) |f, fk| {
                            if (std.mem.eql(u8, f.name, c.text(an.main_token))) break fk;
                        } else continue else j;
                        if (fi >= w.variants[v].len or !w.variants[v][fi]) continue;
                        const value = if (an.kind == .named_arg) an.lhs else a;
                        try out.append(c.gpa, .{ .arg = value, .owner = d.name, .label = try c.print("{s}'s field {s}", .{ vname, fields[fi].name }) });
                    }
                },
                else => {},
            },
        }
        return out.items;
    }

    fn startSite(c: *Caps, out: *std.ArrayList(Site), w: Writes, d: u32, j: usize, a: Index) Error!void {
        if (j >= w.decls[d].len or !w.decls[d][j]) return;
        const decl = c.k.decls[d];
        const p = c.k.params[decl.params.start + j];
        try out.append(c.gpa, .{ .arg = a, .owner = decl.name, .label = try c.print("its parameter {s}", .{p.name}) });
    }

    /// A user call's arguments by parameter position: the receiver of a dot call first.
    fn callArgs(c: *Caps, i: Index) Error![]const Index {
        const n = c.node(i);
        var out: std.ArrayList(Index) = .empty;
        switch (n.kind) {
            .member => try out.append(c.gpa, n.lhs),
            .member_call => {
                try out.append(c.gpa, n.lhs);
                for (c.spanAt(n.rhs)) |a| if (c.node(a).kind != .named_arg) try out.append(c.gpa, a);
            },
            .call => for (c.spanAt(n.rhs)) |a| if (c.node(a).kind != .named_arg) try out.append(c.gpa, a),
            else => {},
        }
        return out.items;
    }

    /// Node `i` hands an Fs narrowed to read_only to a function's parameter, a process's start
    /// argument, or a message's field that is written through: refused here, at the argument, not
    /// when the write runs. The argument is read-only by what this unit saw bound (a name), or by
    /// its type. An `if` or a `case` handed on is read-only when a branch ends in one, and the
    /// diagnostic names that branch (step 25).
    fn handedReadOnly(c: *Caps, i: Index, writes: Writes, names: []const []const u8) Error!void {
        for (try c.handed(i, writes)) |s| {
            const by_type = c.node(s.arg).kind != .name_ref and c.k.pool.resolve(c.k.typeOf(s.arg)) == types.fs_read_only;
            const a = c.readOnlyBranch(s.arg, names) orelse if (by_type) s.arg else continue;
            const arg = c.argText(a);
            try c.report(.flows_violated, c.firstToken(a), try c.print("{s} writes through {s}, and {s} was narrowed to read_only and only reads; hand it the Fs {s} was narrowed from.", .{ s.owner, s.label, arg, arg }));
        }
    }

    /// The Fs rows that change the file system.
    fn writesFiles(row: prelude.Fn) bool {
        if (!std.mem.eql(u8, row.recv, "Fs")) return false;
        for ([_][]const u8{ "write", "append", "remove", "rename", "mkdir" }) |name| {
            if (std.mem.eql(u8, row.name, name)) return true;
        }
        return false;
    }

    /// Whether an Fs expression is narrowed to read_only where this unit can see it:
    /// `x.read_only`, `scoped` on one, a name bound to one, or an `if` or `case` any of whose
    /// branches ends in one (step 25). An Fs parameter may be either, so it is not; the run
    /// refuses a write through one (stdlib.zig, server.zig).
    fn readOnly(c: *Caps, i: Index, names: []const []const u8) bool {
        return c.readOnlyBranch(i, names) != null;
    }

    /// The expression that makes `i` read-only: `i` itself, or the value a branch of an `if` or a
    /// `case` ends in, or null.
    fn readOnlyBranch(c: *Caps, i: Index, names: []const []const u8) ?Index {
        const n = c.node(i);
        switch (n.kind) {
            .if_expr => {
                const d = c.k.tree.extraData(ast.If, n.rhs);
                return c.blockValueReadOnly(c.k.tree.span(d.then_start, d.then_end), names) orelse
                    c.blockValueReadOnly(c.k.tree.span(d.else_start, d.else_end), names);
            },
            .case_expr => {
                for (c.spanAt(n.rhs)) |a| {
                    const d = c.k.tree.extraData(ast.Arm, c.node(a).rhs);
                    if (c.blockValueReadOnly(c.k.tree.span(d.body_start, d.body_end), names)) |at| return at;
                }
                return null;
            },
            else => return if (c.readOnlyLeaf(i, names)) i else null,
        }
    }

    /// The value a branch's block ends in, when that value is read-only.
    fn blockValueReadOnly(c: *Caps, stmts: []const u32, names: []const []const u8) ?Index {
        if (stmts.len == 0) return null;
        const last = c.node(stmts[stmts.len - 1]);
        return switch (last.kind) {
            .expr_stmt => c.readOnlyBranch(last.lhs, names),
            // A branch that is itself an if or a case, as a one-line if's else: if ...: ... keeps it.
            .if_stmt, .case_stmt => c.readOnlyBranch(stmts[stmts.len - 1], names),
            else => null,
        };
    }

    fn readOnlyLeaf(c: *Caps, i: Index, names: []const []const u8) bool {
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
                    if (v.kind == .call and c.node(v.lhs).kind == .type_name_ref and std.mem.eql(u8, c.text(c.node(v.lhs).main_token), "Handle")) {
                        // into: Handle(P), every send and ask to a P.
                        const args_p = c.spanAt(v.rhs);
                        if (args_p.len != 1 or c.node(args_p[0]).kind != .type_name_ref) continue;
                        const d = c.k.findDeclAt(a, c.text(c.node(args_p[0]).main_token)) orelse continue;
                        if (c.k.decls[d].kind == .process) into = c.k.decls[d].type;
                        continue;
                    }
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
                try c.report(.bad_flows, call.main_token, "flows names a capability or a process's handle after into:, such as into: Events or into: Handle(Store).");
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
                        if (!c.sameAuthority(c.k.typeOf(n.lhs), cap)) continue;
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

    /// Whether a receiver of type `t` is the capability or the process handle a flows rule names.
    fn sameAuthority(c: *Caps, t: Id, cap: Id) bool {
        const r = c.k.pool.base(t);
        if (r == cap) return true;
        const a = c.k.pool.get(r);
        const b = c.k.pool.get(cap);
        return a.tag == .handle and b.tag == .handle and a.a == b.a;
    }

    // ---- a capability in a message moves (step 20)

    /// Every capability a send or an ask puts in a message by its name: each later use of
    /// that name in the unit is refused (MO0410). "Later" follows the blocks: the statements
    /// after the send, the rest of the statement it is in, and in a for body the whole body,
    /// which runs again; not another arm of an if or a case the send is in. A statement's
    /// nodes are the run of indices that ends at it, as an item's are.
    fn moves(c: *Caps) Error!void {
        var after: std.ArrayList(NodeRun) = .empty;
        var reported: std.ArrayList(Index) = .empty;
        for (c.units.items) |u| {
            const top = c.unitStatements(u) orelse continue;
            var i = u.first;
            while (i <= u.last) : (i += 1) {
                const n = c.node(i);
                if (n.kind != .member_call) continue;
                const row = switch (c.k.callee[i]) {
                    .prelude => |p| prelude.fns[p],
                    else => continue,
                };
                if (!std.mem.startsWith(u8, row.recv, "Handle")) continue;
                if (!std.mem.eql(u8, row.name, "send") and !std.mem.eql(u8, row.name, "ask")) continue;
                const message = for (c.spanAt(n.rhs)) |a| {
                    if (c.node(a).kind != .named_arg) break a;
                } else continue;
                const m = c.node(message);
                if (m.kind != .call or c.node(m.lhs).kind != .type_name_ref) continue;
                for (c.spanAt(m.rhs)) |fa| {
                    const v = if (c.node(fa).kind == .named_arg) c.node(fa).lhs else fa;
                    if (c.node(v).kind != .name_ref or c.k.binding_of.len == 0 or c.k.binding_of[v] == 0) continue;
                    if (c.baseTag(c.k.typeOf(v)).tag != .cap) continue;
                    after.clearRetainingCapacity();
                    reported.clearRetainingCapacity();
                    switch (top) {
                        .block => |stmts| try c.runsAfter(stmts, u.first, i, &after),
                        .one => |s| if (i <= s) try c.runsWithin(s, u.first, i, &after),
                    }
                    for (after.items) |r| {
                        var j = r.lo;
                        while (j <= r.hi) : (j += 1) {
                            if (c.node(j).kind != .name_ref or c.k.binding_of[j] != c.k.binding_of[v]) continue;
                            if (std.mem.indexOfScalar(Index, reported.items, j) != null) continue;
                            try reported.append(c.gpa, j);
                            const name = c.text(c.node(j).main_token);
                            try c.report(.moved, c.node(j).main_token, try c.print("{s} went to another process in {s}, so it is no longer this function's; use it before the send, or not at all.", .{ name, c.text(c.node(m.lhs).main_token) }));
                        }
                    }
                }
            }
        }
    }

    /// Inclusive node indices.
    const NodeRun = struct { lo: Index, hi: Index };

    /// The statements a unit runs: a function's body or a test's, or a process's update,
    /// whose case is its one statement.
    const Top = union(enum) { block: []const u32, one: Index };

    fn unitStatements(c: *Caps, u: Unit) ?Top {
        const n = c.node(u.last);
        switch (u.kind) {
            .function => {
                if (n.kind != .fn_decl or n.rhs == 0) return null;
                const body = c.k.tree.extraData(ast.FnBody, n.rhs);
                return .{ .block = c.k.tree.span(body.start, body.end) };
            },
            .test_block => return if (n.kind == .test_decl or n.kind == .test_rejects) .{ .block = c.k.tree.span(n.lhs, n.rhs) } else null,
            .process => {
                if (n.kind != .process_decl) return null;
                const d = c.k.tree.extraData(ast.Process, n.lhs);
                if (d.update == 0 or c.node(d.update).lhs == 0) return null;
                return .{ .one = c.node(d.update).lhs };
            },
            else => return null,
        }
    }

    /// The runs of nodes that execute after node `at` inside the block `stmts`, whose first
    /// statement's nodes start at `lo`.
    fn runsAfter(c: *Caps, stmts: []const u32, lo: Index, at: Index, out: *std.ArrayList(NodeRun)) Error!void {
        const k = for (stmts, 0..) |s, k| {
            if (at <= s) break k;
        } else return;
        if (k + 1 < stmts.len) try out.append(c.gpa, .{ .lo = stmts[k] + 1, .hi = stmts[stmts.len - 1] });
        try c.runsWithin(stmts[k], if (k == 0) lo else stmts[k - 1] + 1, at, out);
    }

    /// The nodes of statement `s` (from `lo`) that execute after node `at` inside it.
    fn runsWithin(c: *Caps, s: Index, lo: Index, at: Index, out: *std.ArrayList(NodeRun)) Error!void {
        const n = c.node(s);
        switch (n.kind) {
            .if_stmt, .if_expr => if (at > n.lhs) {
                const d = c.k.tree.extraData(ast.If, n.rhs);
                const then = c.k.tree.span(d.then_start, d.then_end);
                const other = c.k.tree.span(d.else_start, d.else_end);
                if (then.len > 0 and at <= then[then.len - 1]) return c.runsAfter(then, n.lhs + 1, at, out);
                if (other.len > 0 and at <= other[other.len - 1]) return c.runsAfter(other, if (then.len > 0) then[then.len - 1] + 1 else n.lhs + 1, at, out);
            },
            .case_stmt, .case_expr => if (at > n.lhs) {
                for (c.spanAt(n.rhs)) |a| {
                    if (at > a) continue;
                    const d = c.k.tree.extraData(ast.Arm, c.node(a).rhs);
                    const body = c.k.tree.span(d.body_start, d.body_end);
                    const head = if (d.guard != 0) d.guard else c.node(a).lhs;
                    if (body.len > 0 and at > head and at <= body[body.len - 1]) return c.runsAfter(body, head + 1, at, out);
                    break;
                }
            },
            .for_stmt => {
                const body = c.spanAt(n.rhs);
                if (body.len > 0 and at > n.lhs and at <= body[body.len - 1]) {
                    // The body runs again, so all of it comes after.
                    try out.append(c.gpa, .{ .lo = n.lhs + 1, .hi = body[body.len - 1] });
                    return c.runsAfter(body, n.lhs + 1, at, out);
                }
            },
            .binding, .var_binding, .expr_stmt, .return_stmt => if (n.lhs != 0 and at <= n.lhs) switch (c.node(n.lhs).kind) {
                .if_expr, .case_expr => return c.runsWithin(n.lhs, lo, at, out),
                else => {},
            },
            else => {},
        }
        // Outside any block of the statement: the rest of it.
        if (at < s) try out.append(c.gpa, .{ .lo = at + 1, .hi = s });
    }

    // ---- captures: an anonymous function holds no authority

    fn captures(c: *Caps) Error!void {
        for (c.k.captures) |cap| {
            const held = c.capIn(cap.type, 0) orelse continue;
            try c.report(.authority_captured, cap.token, try c.print("the anonymous function captures {s}, a {s}; pass {s} as a parameter to a named function instead.", .{ cap.name, try c.tn(held), cap.name }));
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
        \\  NotText
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
    // Step 40: replace writes, so a read-only Fs refuses it as it refuses write.
    try expectCodes(
        \\module T.ReadOnlyReplace
        \\fn save(fs: Fs, text: String) : Bool
        \\  replaced = fs.read_only.replace("a.txt", text, within: 1.minute) is Ok(_)
        \\  asked = fs.read_only.kind_of("a.txt", within: 1.minute) is Ok(_)
        \\  replaced and asked
        \\end
    , &.{"MO0404"});
}

test "a read-only Fs handed to a function that writes through it, or through a scope of it further down, is refused at the call" {
    try expectCodes(
        \\module T.Handed
        \\fn copy(logs: Fs) : Bool
        \\  logs.write("x.log", "no", within: 1.minute) is Ok(_)
        \\end
        \\fn deeper(folder: Fs) : Bool
        \\  archive = folder.scoped("archive")
        \\  copy(archive)
        \\end
        \\fn reads(folder: Fs) : Bool
        \\  folder.read("x.log", within: 1.minute) is Ok(_)
        \\end
        \\fn main(platform: Platform)
        \\  data = platform.fs.scoped("data").read_only
        \\  var back = platform.fs.read_only
        \\  back = platform.fs
        \\  if copy(data) and deeper(platform.fs.read_only.scoped("x")) and reads(data) and copy(platform.fs) and copy(back)
        \\    platform.exit(1)
        \\  end
        \\end
    , &.{ "MO0404", "MO0404" });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try capsOf(arena_state.allocator(),
        \\module T.Named
        \\fn copy(logs: Fs) : Bool
        \\  logs.append("x.log", "no", within: 1.minute) is Ok(_)
        \\end
        \\fn main(platform: Platform)
        \\  if copy(platform.fs.scoped("data").read_only)
        \\    platform.exit(1)
        \\  end
        \\end
    );
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings("copy writes through its parameter logs, and platform.fs.scoped(\"data\").read_only was narrowed to read_only and only reads; hand it the Fs platform.fs.scoped(\"data\").read_only was narrowed from.", found[0].what);
}

test "a state keeps a handle alone, in an Option, a List, or a Map's values; a capability, or a handle in anything else, is refused" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try capsOf(arena_state.allocator(),
        \\module T.Kept
        \\process Worker()
        \\  state
        \\    n: UInt64
        \\  end
        \\
        \\  message Tick
        \\
        \\  fn update(state, message)
        \\    case message
        \\      Tick:
        \\        state.n += 1
        \\    end
        \\  end
        \\end
        \\process Holder(first: Handle(Worker))
        \\  state
        \\    one: Handle(Worker) = first
        \\    maybe: Option(Handle(Worker))
        \\    many: List(Handle(Worker))
        \\    named: Map(String, Handle(Worker))
        \\    pairs: List((String, Handle(Worker)))
        \\    keyed: Map(Handle(Worker), String)
        \\    clock: Option(Clock)
        \\  end
        \\
        \\  message Tick
        \\
        \\  fn update(state, message)
        \\    case message
        \\      Tick:
        \\        state.one.send(Tick)
        \\    end
        \\  end
        \\end
        \\supervisor Holders(first: Handle(Worker))
        \\  child Worker, restart: :always
        \\  child Holder(first), restart: :always
        \\end
    );
    try std.testing.expectEqual(@as(usize, 3), found.len);
    try std.testing.expectEqualStrings("pairs holds a Handle(Worker) inside a List((String, Handle(Worker))); a state field keeps a handle only as Handle(Worker), Option(Handle(Worker)), List(Handle(Worker)), or Map(K, Handle(Worker)).", found[0].what);
    try std.testing.expectEqualStrings("keyed holds a Handle(Worker) inside a Map(Handle(Worker), String); a state field keeps a handle only as Handle(Worker), Option(Handle(Worker)), List(Handle(Worker)), or Map(K, Handle(Worker)).", found[1].what);
    try std.testing.expectEqualStrings("clock holds a Clock; a capability travels only as a parameter, never inside a value.", found[2].what);
}

test "a read-only Fs handed to a process that writes through its start argument, by a start or a child line, or in a message whose arm writes through it, is refused" {
    const header =
        \\module T.Started
        \\process Saver(files: Fs)
        \\  state
        \\    saved: Bool
        \\  end
        \\
        \\  message Save : Bool
        \\  message Keep(into: Fs) : Bool
        \\
        \\  fn update(state, message)
        \\    case message
        \\      Save: files.write("a", "b", within: reply_by) is Ok(_)
        \\      Keep(folder): kept(folder.scoped("x"))
        \\    end
        \\  end
        \\end
        \\process Reader(files: Fs)
        \\  state
        \\    read: Bool
        \\  end
        \\
        \\  message Look : Bool
        \\
        \\  fn update(state, message)
        \\    case message
        \\      Look: files.read("a", within: reply_by) is Ok(_)
        \\    end
        \\  end
        \\end
        \\supervisor Savers(files: Fs)
        \\  child Saver(files), restart: :always
        \\end
        \\supervisor Readers(files: Fs)
        \\  child Reader(files), restart: :always
        \\end
        \\fn kept(folder: Fs) : Bool
        \\  folder.append("a", "b", within: 1.minute) is Ok(_)
        \\end
        \\fn keep(saver: Handle(Saver), into: Fs) : Bool
        \\  saver.ask(Keep(into: into), within: 1.minute) is Ok(true)
        \\end
        \\
    ;
    try expectCodes(header ++
        \\fn main(platform: Platform)
        \\  saver = Saver.start(platform.fs.read_only)
        \\  reader = Reader.start(platform.fs.read_only)
        \\  looked = Readers.start(platform.fs.read_only).ask(Look, within: 1.minute) is Ok(true)
        \\  saved = Savers.start(platform.fs.scoped("x").read_only).ask(Save, within: 1.minute) is Ok(true)
        \\  if keep(saver, platform.fs.read_only) and reader.ask(Look, within: 1.minute) is Ok(true) and looked and saved
        \\    platform.exit(1)
        \\  end
        \\end
    , &.{ "MO0404", "MO0404", "MO0404" });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try capsOf(arena_state.allocator(), header ++
        \\fn main(platform: Platform)
        \\  if Saver.start(platform.fs).ask(Keep(into: platform.fs.read_only), within: 1.minute) is Ok(true)
        \\    platform.exit(1)
        \\  end
        \\end
    );
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings("Saver writes through Keep's field into, and platform.fs.read_only was narrowed to read_only and only reads; hand it the Fs platform.fs.read_only was narrowed from.", found[0].what);
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

test "a handle is authority: a pure function cannot start one, no value holds one, no anonymous function captures one" {
    try expectCodes(
        \\module T.Handles
        \\process Tally()
        \\  state
        \\    n: UInt64
        \\  end
        \\  message Read : UInt64
        \\  fn update(state, message)
        \\    case message
        \\      Read: state.n
        \\    end
        \\  end
        \\end
        \\supervisor Tallies
        \\  child Tally, restart: :always
        \\end
        \\struct Held
        \\  tally: Handle(Tally)
        \\end
        \\fn started() : Handle(Tally)
        \\  Tally.start()
        \\end
        \\fn read(tally: Handle(Tally)) : Result(UInt64, AskError)
        \\  tally.ask(Read, within: 1.ms)
        \\end
        \\fn counted(tally: Handle(Tally), ks: List(UInt64)) : List(UInt64)
        \\  ks.filter(fn(k) k > 0 and tally.ask(Read, within: 1.ms) is Ok(_) end)
        \\end
        \\fn stamped(clock: Clock, names: List(String)) : List(String)
        \\  names.map(fn(name) "#{name} at #{clock.now}" end)
        \\end
    , &.{ "MO0403", "MO0403", "MO0409", "MO0409" });
}

test "flows sees a handle: into: Handle(P) is every send and ask to a P" {
    try expectCodes(
        \\module T.FlowHandle
        \\never "a card number reaches the vault"
        \\  flows(Card, into: Handle(Vault))
        \\end
        \\struct Card
        \\  number: String
        \\end
        \\process Vault()
        \\  state
        \\    n: UInt64
        \\  end
        \\  message Keep(note: String)
        \\  fn update(state, message)
        \\    case message
        \\      Keep(note):
        \\        state.n += note.size
        \\    end
        \\  end
        \\end
        \\supervisor Vaults
        \\  child Vault, restart: :always
        \\end
        \\fn kept(vault: Handle(Vault), card: Card, note: String)
        \\  vault.send(Keep(note: note))
        \\  vault.send(Keep(note: "#{card}"))
        \\end
    , &.{"MO0404"});
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

test "a message line may declare a capability or a handle, and a capability sent in one moves" {
    try expectCodes(
        \\module T.Moves
        \\process Back()
        \\  state
        \\    n: UInt64
        \\  end
        \\  message Greet(conn: Conn, front: Handle(Front))
        \\  fn update(state, message)
        \\    case message
        \\      Greet(conn: conn, front: front):
        \\        if conn.write("hi", within: 1.ms) is Ok(_)
        \\          front.send(Thanks)
        \\          state.n += 1
        \\        end
        \\    end
        \\  end
        \\end
        \\process Front(back: Handle(Back), me: Handle(Front))
        \\  state
        \\    n: UInt64
        \\  end
        \\  message Take(conn: Conn)
        \\  message Thanks
        \\  fn update(state, message)
        \\    case message
        \\      Take(conn):
        \\        if state.n > 0
        \\          back.send(Greet(conn: conn, front: me))
        \\          me.send(Thanks)
        \\        else
        \\          conn.close
        \\        end
        \\        state.n += 1
        \\      Thanks:
        \\        state.n += 1
        \\    end
        \\  end
        \\end
        \\supervisor Pair(back: Handle(Back), me: Handle(Front))
        \\  child Back, restart: :always
        \\  child Front(back, me), restart: :always
        \\end
        \\fn handed(back: Handle(Back), front: Handle(Front), conn: Conn)
        \\  back.send(Greet(conn: conn, front: front))
        \\  front.send(Thanks)
        \\  conn.close
        \\end
        \\fn spread(backs: List(Handle(Back)), front: Handle(Front), conn: Conn)
        \\  for back in backs
        \\    back.send(Greet(conn: conn, front: front))
        \\  end
        \\end
        \\struct Held
        \\  conn: Conn
        \\end
    , &.{ "MO0403", "MO0410", "MO0410" });
}

test "a read-only Fs hidden in a branch of an if or a case handed to a process that writes through it is refused" {
    try expectCodes(
        \\module T.Hidden
        \\process Saver(files: Fs)
        \\  state
        \\    saved: Bool
        \\  end
        \\
        \\  message Save : Bool
        \\
        \\  fn update(state, message)
        \\    case message
        \\      Save:
        \\        state.saved = files.write("a.txt", "b", within: reply_by) is Ok(_)
        \\        state.saved
        \\    end
        \\  end
        \\end
        \\supervisor Savers(files: Fs)
        \\  child Saver(files), restart: :always
        \\end
        \\fn lined(fs: Fs, careful: Bool) : Handle(Saver)
        \\  Saver.start(if careful: fs.read_only else: fs)
        \\end
        \\fn blocked(fs: Fs, careful: Bool) : Handle(Saver)
        \\  chosen = if careful
        \\    fs
        \\  else
        \\    fs.scoped("x").read_only
        \\  end
        \\  Saver.start(chosen)
        \\end
        \\fn cased(fs: Fs, how: UInt8) : Handle(Saver)
        \\  Saver.start(case how
        \\    0: fs
        \\    _: if how > 1: fs else: fs.read_only
        \\  end)
        \\end
        \\fn writable(fs: Fs, careful: Bool) : Handle(Saver)
        \\  Saver.start(if careful: fs.scoped("x") else: fs)
        \\end
    , &.{ "MO0404", "MO0404", "MO0404" });
}

test "flows follows a capability a message carries into the process that takes it" {
    try expectCodes(
        \\module T.FlowField
        \\never "a card number is written to a connection"
        \\  flows(Card, into: Conn)
        \\end
        \\struct Card
        \\  number: String
        \\end
        \\process Writer()
        \\  state
        \\    n: UInt64
        \\  end
        \\  message Write(conn: Conn, card: Card)
        \\  fn update(state, message)
        \\    case message
        \\      Write(conn: conn, card: card):
        \\        if conn.write("#{card}", within: 1.ms) is Ok(_)
        \\          state.n += 1
        \\        end
        \\    end
        \\  end
        \\end
        \\supervisor Writers
        \\  child Writer, restart: :always
        \\end
    , &.{"MO0404"});
}

test "a process starts what its own supervisor names as a child with no capability, and a function needs one" {
    try expectCodes(
        \\module T.Siblings
        \\process Job()
        \\  state
        \\    n: UInt64
        \\  end
        \\  message Run
        \\  fn update(state, message)
        \\    case message
        \\      Run:
        \\        state.n += 1
        \\    end
        \\  end
        \\end
        \\process Pool()
        \\  state
        \\    started: UInt64
        \\  end
        \\  message Spawn
        \\  fn update(state, message)
        \\    case message
        \\      Spawn:
        \\        job = Job.start()
        \\        job.send(Run)
        \\        state.started += 1
        \\    end
        \\  end
        \\end
        \\process Stray()
        \\  state
        \\    started: UInt64
        \\  end
        \\  message Spawn
        \\  fn update(state, message)
        \\    case message
        \\      Spawn:
        \\        Job.start().send(Run)
        \\        state.started += 1
        \\    end
        \\  end
        \\end
        \\supervisor Pools
        \\  child Pool, restart: :always
        \\  child Job, restart: :always
        \\end
        \\supervisor Strays
        \\  child Stray, restart: :always
        \\end
        \\fn spawned() : Handle(Job)
        \\  Job.start()
        \\end
    , &.{ "MO0403", "MO0403" });
}

test "an arm that mentions reply_to hands it to a state field once; a Reply lives in a state field as a handle does" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try capsOf(arena_state.allocator(),
        \\module T.Kept
        \\process Keeper()
        \\  state
        \\    one: Option(Reply(UInt64))
        \\    many: List(Reply(UInt64))
        \\    named: Map(String, Reply(UInt64))
        \\    pairs: List((String, Reply(UInt64)))
        \\    n: UInt64
        \\  end
        \\
        \\  message Held : UInt64
        \\  message Loose : UInt64
        \\  message Twice : UInt64
        \\  message Flush
        \\
        \\  fn update(state, message)
        \\    case message
        \\      Held:
        \\        state.many = state.many.push(reply_to)
        \\      Loose:
        \\        reply_to.answer(state.n)
        \\      Twice:
        \\        state.many = state.many.push(reply_to)
        \\        state.one = Some(reply_to)
        \\      Flush:
        \\        for held in state.many
        \\          held.answer(state.n)
        \\        end
        \\        state.many = []
        \\    end
        \\  end
        \\end
        \\supervisor Keepers
        \\  child Keeper, restart: :always
        \\end
    );
    try std.testing.expectEqual(@as(usize, 3), found.len);
    try std.testing.expectEqualStrings("pairs holds a Reply(UInt64) inside a List((String, Reply(UInt64))); a state field keeps a handle only as Reply(UInt64), Option(Reply(UInt64)), List(Reply(UInt64)), or Map(K, Reply(UInt64)).", found[0].what);
    try std.testing.expectEqualStrings("Loose's arm mentions reply_to but does not hand it to a state field; write state.<field> = ... reply_to ... once, and answer it later with reply.answer(value).", found[1].what);
    try std.testing.expectEqualStrings("reply_to is the state's once Twice's arm has kept it; read it back from the state field, or answer it with reply.answer(value).", found[2].what);
}
