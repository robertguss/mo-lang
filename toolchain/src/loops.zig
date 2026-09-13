//! MO0501, chapter 4's loop rule (toolchain/FORMAT.md, "Loops"): a pure body is
//! written with map, filter, or reduce; `for` is for effects, `try`, `break`, or
//! `return`. `mo check` runs this after the capability pass and `mo fmt --check`
//! runs it too.
//!
//! A body is pure when it holds no capability call, no `try`, no `break`, no
//! `return`, and no assignment to a name declared outside the loop. A capability
//! call is a call on a capability or a process handle, a call that passes one, or
//! `Process.start`. Reads the types check.zig decided. Such a loop is reported with no
//! fix: what it should become is the author's call.
//!
//! The rule also recognizes three loops over a list whose one statement builds a `var`
//! declared outside the loop, and reports each with the fix `mo fix` applies (fix.zig):
//!
//!   map     `acc = acc.push(e)`                  `acc = acc.concat(xs.map(fn(x) e end))`
//!   filter  `if c` around `acc = acc.push(x)`    `acc = acc.concat(xs.filter(fn(x) c end))`
//!   reduce  `acc = e` where e reads acc,         `acc = xs.reduce(acc, fn(so_far, x) e end)`,
//!           `acc += e`, `acc -= e`               with acc read as so_far, or so_far + e
//!
//! A loop is one of the three only when the rewrite means the same and compiles: the
//! loop names its element and reads it, `e` and `c` are pure and on one line, read no
//! `var` but `acc` (an anonymous function cannot capture one, MO0314), and map and
//! filter do not read `acc`; the `for` is alone on its lines with no comment in it.
const std = @import("std");
const ast = @import("ast.zig");
const checker = @import("check.zig");
const diag = @import("diag.zig");
const fix = @import("fix.zig");
const prelude = @import("prelude.zig");
const types = @import("types.zig");

const Index = ast.Index;

pub const Error = error{OutOfMemory};

pub const code = "MO0501";
pub const what = "this for has a pure body; write it as map, filter, or reduce";
pub const why = "A pure loop body is written with map, filter, or reduce, so a for always says an effect, a try, a break, or a return is inside (chapter 4, loops). mo fix rewrites the three accumulator loops (push into a list, push when a condition holds, fold into a var); any other pure body is rewritten by hand.";

/// The loop rule's row of the error catalog.
pub const entry: diag.Entry = .{ .code = code, .category = .format, .why = why, .fixes = &.{
    "acc = acc.push(e) in a for over xs becomes acc = acc.concat(xs.map(fn(x) e end))",
    "if c around acc = acc.push(x) becomes acc = acc.concat(xs.filter(fn(x) c end))",
    "acc = e reading acc, acc += e, or acc -= e becomes acc = xs.reduce(acc, fn(so_far, x) ... end)",
} };

pub fn check(gpa: std.mem.Allocator, checked: checker.Checked, out: *diag.List) Error!void {
    var l: Loops = .{ .gpa = gpa, .k = &checked, .out = out };
    const root = checked.tree.nodes[0];
    for (checked.tree.span(root.lhs, root.rhs)) |it| try l.item(it);
}

/// Whether an expression holds no capability call, no `try`, and no process start: what
/// deleting it cannot change but for a crash (fix.zig, MO0307).
pub fn pureValue(gpa: std.mem.Allocator, checked: *const checker.Checked, i: Index) bool {
    var none: diag.List = .empty;
    var l: Loops = .{ .gpa = gpa, .k = checked, .out = &none };
    return l.pureNode(i, 0);
}

/// A name bound in the unit, whether it is a `var` (or an `inout` parameter, or
/// `state`), and the loops around the place it is bound.
const Binder = struct { text: []const u8, is_var: bool = false, loops: []const Index };

const Loops = struct {
    gpa: std.mem.Allocator,
    k: *const checker.Checked,
    out: *diag.List,
    binders: std.ArrayList(Binder) = .empty,
    fors: std.ArrayList(Index) = .empty,
    stack: std.ArrayList(Index) = .empty,
    /// The names reduce fixes chose in this unit, so two of its loops never share one.
    fresh: std.ArrayList([]const u8) = .empty,

    fn node(l: *Loops, i: Index) ast.Node {
        return l.k.tree.nodes[i];
    }

    fn text(l: *Loops, tok: u32) []const u8 {
        return l.k.tree.tokenText(tok);
    }

    fn spanAt(l: *Loops, extra_index: u32) []const u32 {
        if (extra_index == 0) return &.{};
        const s = l.k.tree.extraData(ast.Span, extra_index);
        return l.k.tree.span(s.start, s.end);
    }

    fn item(l: *Loops, it: Index) Error!void {
        const n = l.node(it);
        const tree = l.k.tree;
        switch (n.kind) {
            .fn_decl => {
                const sig = tree.extraData(ast.Signature, n.lhs);
                const body = tree.extraData(ast.FnBody, n.rhs);
                try l.unit(tree.span(sig.params_start, sig.params_end), &.{}, tree.span(body.start, body.end));
            },
            .impl_decl => for (l.spanAt(n.rhs)) |f| try l.item(f),
            .process_decl => {
                const data = tree.extraData(ast.Process, n.lhs);
                const update = l.node(data.update);
                try l.unit(tree.span(data.params_start, data.params_end), &.{ "state", "message" }, &.{update.lhs});
            },
            .test_decl, .test_rejects => try l.unit(&.{}, &.{}, tree.span(n.lhs, n.rhs)),
            .recipe_decl => {
                const data = tree.extraData(ast.Recipe, n.lhs);
                for (tree.span(data.tests_start, data.tests_end)) |t| try l.item(t);
            },
            else => {},
        }
    }

    /// One function, update, or test: its binders first, then each of its loops.
    fn unit(l: *Loops, params: []const u32, implicit: []const []const u8, stmts: []const u32) Error!void {
        l.binders.clearRetainingCapacity();
        l.fors.clearRetainingCapacity();
        l.stack.clearRetainingCapacity();
        l.fresh.clearRetainingCapacity();
        for (params) |p| try l.binders.append(l.gpa, .{ .text = l.text(l.node(p).main_token), .is_var = l.node(p).kind == .param_inout, .loops = &.{} });
        for (implicit) |name| try l.binders.append(l.gpa, .{ .text = name, .is_var = std.mem.eql(u8, name, "state"), .loops = &.{} });
        for (stmts) |s| try l.collect(s);
        for (l.fors.items) |f| {
            const at = l.k.tree.tokens[l.node(f).main_token - 1].start;
            if (l.pure(f)) {
                try l.out.append(l.gpa, .{ .code = code, .category = .format, .at = at, .what = what, .why = why });
            } else if (try l.shape(f)) |found| {
                try l.out.append(l.gpa, .{ .code = code, .category = .format, .at = at, .what = what, .why = why, .fixes = try l.gpa.dupe(diag.Fix, &.{found}) });
            }
        }
    }

    fn bindTok(l: *Loops, tok: u32, is_var: bool) Error!void {
        if (l.k.tree.tokens[tok].kind != .ident) return; // `for _ in`
        try l.binders.append(l.gpa, .{ .text = l.text(tok), .is_var = is_var, .loops = try l.gpa.dupe(Index, l.stack.items) });
    }

    fn collect(l: *Loops, i: Index) Error!void {
        const n = l.node(i);
        switch (n.kind) {
            .binding, .pat_bind => try l.bindTok(n.main_token, false),
            .var_binding => try l.bindTok(n.main_token, true),
            .for_stmt => {
                try l.fors.append(l.gpa, i);
                try l.collect(n.lhs);
                try l.stack.append(l.gpa, i);
                try l.bindTok(n.main_token, false);
                for (l.spanAt(n.rhs)) |s| try l.collect(s);
                _ = l.stack.pop();
                return;
            },
            .anon_fn => {
                const data = l.k.tree.extraData(ast.AnonFn, n.lhs);
                for (l.k.tree.span(data.params_start, data.params_end)) |tok| try l.bindTok(tok, false);
            },
            else => {},
        }
        var it = Children.of(l.k.tree, i);
        while (it.next()) |c| try l.collect(c);
    }

    /// Declared outside `loop`: a parameter, or a binder whose loops do not include it.
    fn outside(l: *Loops, name: []const u8, loop: Index) bool {
        for (l.binders.items) |b| {
            if (!std.mem.eql(u8, b.text, name)) continue;
            if (std.mem.indexOfScalar(Index, b.loops, loop) == null) return true;
        }
        return false;
    }

    /// A `var` declared outside `loop`.
    fn outerVar(l: *Loops, name: []const u8, loop: Index) bool {
        for (l.binders.items) |b| {
            if (b.is_var and std.mem.eql(u8, b.text, name) and std.mem.indexOfScalar(Index, b.loops, loop) == null) return true;
        }
        return false;
    }

    /// Whether a token from `from` up to `to` reads a `var` other than `except`.
    fn readsVar(l: *Loops, from: u32, to: u32, except: []const u8) bool {
        const tree = l.k.tree;
        var t = from;
        while (t < to) : (t += 1) {
            const name = tree.tokenText(t);
            if (std.mem.eql(u8, name, except) or !fix.mentions(tree, t, t + 1, name)) continue;
            for (l.binders.items) |b| if (b.is_var and std.mem.eql(u8, b.text, name)) return true;
        }
        return false;
    }

    fn pure(l: *Loops, loop: Index) bool {
        for (l.spanAt(l.node(loop).rhs)) |s| if (!l.pureNode(s, loop)) return false;
        return true;
    }

    fn pureNode(l: *Loops, i: Index, loop: Index) bool {
        const n = l.node(i);
        switch (n.kind) {
            .try_expr, .break_stmt, .return_stmt => return false,
            .binding => if (l.outside(l.text(n.main_token), loop)) return false,
            .assign => {
                var root = n.lhs;
                while (l.node(root).kind == .member) root = l.node(root).lhs;
                if (l.outside(l.text(l.node(root).main_token), loop)) return false;
            },
            .member, .member_call, .call => {
                if (l.effectful(n.lhs)) return false;
                if (n.kind != .member) for (l.spanAt(n.rhs)) |a| {
                    const arg = if (l.node(a).kind == .named_arg) l.node(a).lhs else a;
                    if (l.effectful(arg)) return false;
                };
                switch (l.k.callee[i]) {
                    .prelude => |p| if (std.mem.eql(u8, prelude.fns[p].recv, "Process")) return false,
                    else => {},
                }
            },
            else => {},
        }
        var it = Children.of(l.k.tree, i);
        while (it.next()) |c| if (!l.pureNode(c, loop)) return false;
        return true;
    }

    /// A value of a capability or handle type.
    fn effectful(l: *Loops, i: Index) bool {
        const t = l.k.pool.get(l.k.pool.base(l.k.typeOf(i)));
        return t.tag == .cap or t.tag == .handle;
    }

    // ---- the three loops mo fix rewrites

    /// Tokens `from` up to `to` as one line of text, or null when they are empty or
    /// span lines.
    fn oneLine(l: *Loops, from: u32, to: u32) ?[]const u8 {
        const tree = l.k.tree;
        if (from >= to) return null;
        const s = tree.source[tree.tokens[from].start..tree.tokens[to - 1].end];
        return if (std.mem.indexOfScalar(u8, s, '\n') == null) s else null;
    }

    /// `acc.push(e)` with one positional argument: the tokens of `e`, and its node.
    fn pushOf(l: *Loops, i: Index, acc: []const u8) Error!?struct { from: u32, to: u32, arg: Index } {
        const n = l.node(i);
        if (n.kind != .member_call or !std.mem.eql(u8, l.text(n.main_token), "push")) return null;
        const recv = l.node(n.lhs);
        if (recv.kind != .name_ref or !std.mem.eql(u8, l.text(recv.main_token), acc)) return null;
        const args = l.spanAt(n.rhs);
        if (args.len != 1 or l.node(args[0]).kind == .named_arg) return null;
        const delims = try fix.delimiters(l.gpa, l.k.tree, n.main_token + 1);
        if (delims.len != 2) return null;
        return .{ .from = delims[0] + 1, .to = delims[1], .arg = args[0] };
    }

    /// The fix for a loop that is one of the three, or null.
    fn shape(l: *Loops, f: Index) Error!?diag.Fix {
        const tree = l.k.tree;
        const n = l.node(f);
        const kw = n.main_token - 1;
        const elem = n.main_token;
        if (tree.tokens[elem].kind != .ident) return null;
        // A range counts; it is not a list value to call map on.
        const iterable = l.k.pool.get(l.k.pool.base(l.k.typeOf(n.lhs)));
        if (iterable.tag != .list or l.node(n.lhs).kind == .range) return null;
        const body = l.spanAt(n.rhs);
        if (body.len != 1) return null;
        if (kw == 0 or tree.tokens[kw - 1].kind != .newline) return null;
        const after = fix.blockEnd(tree, kw) + 1;
        if (tree.tokens[after].kind != .newline) return null;
        if (fix.hasComment(tree, kw, after)) return null;
        const x = l.text(elem);
        const listed = l.oneLine(elem + 2, fix.lineEnd(tree, elem + 2)) orelse return null;
        // `(a + b).map(...)`: a call binds tighter than an operator.
        const xs = switch (l.node(n.lhs).kind) {
            .implies, .or_expr, .and_expr, .not_expr, .compare, .is_expr, .add, .mul, .negate, .try_expr => try std.fmt.allocPrint(l.gpa, "({s})", .{listed}),
            else => listed,
        };

        const s = body[0];
        const sn = l.node(s);
        const rewrite: []const u8 = switch (sn.kind) {
            .binding => blk: {
                const acc = l.text(sn.main_token);
                if (!l.outerVar(acc, f)) return null;
                if (try l.pushOf(sn.lhs, acc)) |push| {
                    const e = l.oneLine(push.from, push.to) orelse return null;
                    if (fix.mentions(tree, push.from, push.to, acc) or !fix.mentions(tree, push.from, push.to, x)) return null;
                    if (l.readsVar(push.from, push.to, "") or !l.pureNode(push.arg, f)) return null;
                    break :blk try std.fmt.allocPrint(l.gpa, "{s} = {s}.concat({s}.map(fn({s}) {s} end))", .{ acc, acc, xs, x, e });
                }
                const from = sn.main_token + 2;
                const to = fix.lineEnd(tree, sn.main_token);
                _ = l.oneLine(from, to) orelse return null;
                if (!fix.mentions(tree, from, to, acc) or !fix.mentions(tree, from, to, x)) return null;
                if (l.readsVar(from, to, acc) or !l.pureNode(sn.lhs, f)) return null;
                const p = try l.freshName();
                const e = try fix.renamed(l.gpa, tree, from, to, acc, p);
                break :blk try std.fmt.allocPrint(l.gpa, "{s} = {s}.reduce({s}, fn({s}, {s}) {s} end)", .{ acc, xs, acc, p, x, e });
            },
            .assign => blk: {
                const op = tree.tokens[sn.main_token].kind;
                if (op != .plus_eq and op != .minus_eq) return null;
                const place = l.node(sn.lhs);
                if (place.kind != .name_ref) return null;
                const acc = l.text(place.main_token);
                if (!l.outerVar(acc, f)) return null;
                const from = sn.main_token + 1;
                const to = fix.lineEnd(tree, sn.main_token);
                const e = l.oneLine(from, to) orelse return null;
                if (fix.mentions(tree, from, to, acc) or !fix.mentions(tree, from, to, x)) return null;
                if (l.readsVar(from, to, "") or !l.pureNode(sn.rhs, f)) return null;
                const p = try l.freshName();
                // `so_far - (a + b)`: the fold keeps the grouping `-=` gave it.
                const group = switch (l.node(sn.rhs).kind) {
                    .implies, .or_expr, .and_expr, .compare, .is_expr, .range, .add => true,
                    else => false,
                };
                const sign = if (op == .plus_eq) "+" else "-";
                const lp = if (group) "(" else "";
                const rp = if (group) ")" else "";
                break :blk try std.fmt.allocPrint(l.gpa, "{s} = {s}.reduce({s}, fn({s}, {s}) {s} {s} {s}{s}{s} end)", .{ acc, xs, acc, p, x, p, sign, lp, e, rp });
            },
            .if_stmt => blk: {
                const d = tree.extraData(ast.If, sn.rhs);
                if (d.else_start != d.else_end) return null;
                const then = tree.span(d.then_start, d.then_end);
                if (then.len != 1) return null;
                const tn = l.node(then[0]);
                if (tn.kind != .binding) return null;
                const acc = l.text(tn.main_token);
                if (!l.outerVar(acc, f)) return null;
                const push = try l.pushOf(tn.lhs, acc) orelse return null;
                const pushed = l.node(push.arg);
                if (pushed.kind != .name_ref or !std.mem.eql(u8, l.text(pushed.main_token), x)) return null;
                const from = sn.main_token + 1;
                const to = fix.lineEnd(tree, from);
                const c = l.oneLine(from, to) orelse return null;
                if (fix.mentions(tree, from, to, acc) or !fix.mentions(tree, from, to, x)) return null;
                if (l.readsVar(from, to, "") or !l.pureNode(sn.lhs, f)) return null;
                break :blk try std.fmt.allocPrint(l.gpa, "{s} = {s}.concat({s}.filter(fn({s}) {s} end))", .{ acc, acc, xs, x, c });
            },
            else => return null,
        };
        const line = fix.lineStartByte(tree.source, tree.tokens[kw].start);
        const indent = tree.source[line..tree.tokens[kw].start];
        const to: u32 = @intCast(@min(tree.tokens[after].start + 1, tree.source.len));
        return .{
            .description = try std.fmt.allocPrint(l.gpa, "write it as {s}", .{rewrite}),
            .confidence = 100,
            .edits = try l.gpa.dupe(diag.Edit, &.{.{ .at = line, .len = to - line, .text = try std.fmt.allocPrint(l.gpa, "{s}{s}\n", .{ indent, rewrite }) }}),
        };
    }

    fn freshName(l: *Loops) Error![]const u8 {
        const name = try fix.freshName(l.gpa, l.k.tree, "so_far", l.fresh.items);
        try l.fresh.append(l.gpa, name);
        return name;
    }
};

/// The statement, expression, and pattern children of a node, in source order.
/// Types, declarations, and comprehensions have none here: a loop body never holds
/// them, except `any(T)` whose type is not walked.
const Children = struct {
    tree: ast.Tree,
    buf: [3]Index = undefined,
    len: u32 = 0,
    spans: [2][]const u32 = .{ &.{}, &.{} },
    pos: u32 = 0,
    span_i: u32 = 0,
    span_pos: u32 = 0,

    fn of(tree: ast.Tree, i: Index) Children {
        var c: Children = .{ .tree = tree };
        const n = tree.nodes[i];
        switch (n.kind) {
            .binding, .var_binding, .expr_stmt, .assert_stmt, .requires, .ensures, .not_expr, .negate, .try_expr, .member, .tuple_index, .named_arg, .old_expr, .pat_variant, .pat_field => c.add(n.lhs),
            .assign, .return_stmt, .implies, .or_expr, .and_expr, .compare, .is_expr, .range, .add, .mul => {
                c.add(n.lhs);
                c.add(n.rhs);
            },
            .for_stmt, .case_stmt, .case_expr, .member_call, .call => {
                c.add(n.lhs);
                c.spans[0] = spanAt(tree, n.rhs);
            },
            .if_stmt, .if_expr => {
                c.add(n.lhs);
                const d = tree.extraData(ast.If, n.rhs);
                c.spans = .{ tree.span(d.then_start, d.then_end), tree.span(d.else_start, d.else_end) };
            },
            .arm => {
                c.add(n.lhs);
                const d = tree.extraData(ast.Arm, n.rhs);
                c.add(d.guard);
                c.spans[0] = tree.span(d.body_start, d.body_end);
            },
            .tuple, .list, .string_interp, .pat_record, .pat_tuple => c.spans[0] = tree.span(n.lhs, n.rhs),
            .anon_fn => {
                const d = tree.extraData(ast.AnonFn, n.lhs);
                c.spans[0] = tree.span(d.body_start, d.body_end);
            },
            else => {},
        }
        return c;
    }

    fn spanAt(tree: ast.Tree, extra_index: u32) []const u32 {
        if (extra_index == 0) return &.{};
        const s = tree.extraData(ast.Span, extra_index);
        return tree.span(s.start, s.end);
    }

    fn add(c: *Children, i: Index) void {
        if (i == 0) return;
        c.buf[c.len] = i;
        c.len += 1;
    }

    fn next(c: *Children) ?Index {
        if (c.pos < c.len) {
            c.pos += 1;
            return c.buf[c.pos - 1];
        }
        while (c.span_i < 2) {
            const s = c.spans[c.span_i];
            if (c.span_pos < s.len) {
                c.span_pos += 1;
                return s[c.span_pos - 1];
            }
            c.span_i += 1;
            c.span_pos = 0;
        }
        return null;
    }
};

fn findings(arena: std.mem.Allocator, src: []const u8) ![]const diag.Record {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");
    var scratch: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &scratch);
    const tree = try parser.parse(arena, src, tokens, &scratch);
    const checked = try checker.check(arena, tree, &scratch);
    var out: diag.List = .empty;
    try check(arena, checked, &out);
    return out.items;
}

fn expectLoops(src: []const u8, want: usize) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try findings(arena_state.allocator(), src);
    try std.testing.expectEqual(want, found.len);
    for (found) |d| {
        try std.testing.expectEqualStrings("MO0501", d.code);
        try std.testing.expectEqualStrings(what, d.what);
    }
}

test "a pure for body is reported at its for, with no fix" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const src =
        \\module T.Pure
        \\test "every price is positive"
        \\  for price in [1, 2]
        \\    var bumped = price
        \\    bumped += 1
        \\    assert bumped > 1
        \\  end
        \\end
    ;
    const found = try findings(arena_state.allocator(), src);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqual(@as(u32, 47), found[0].at);
    try std.testing.expectEqual(@as(usize, 0), found[0].fixes.len);
}

test "return, break, try, an outer assignment, and a capability call make a for honest" {
    try expectLoops(
        \\module T.Honest
        \\enum E
        \\  Timeout
        \\end
        \\fn first_over(xs: List(UInt32), limit: UInt32) : Option(UInt32)
        \\  for x in xs
        \\    return Some(x) if x > limit
        \\  end
        \\  None
        \\end
        \\fn count(n: UInt32) : UInt32
        \\  var total = 0
        \\  for x in 0..n
        \\    total += x
        \\  end
        \\  total
        \\end
        \\fn stop(xs: List(UInt32)) : UInt32
        \\  for x in xs
        \\    if x > 1
        \\      break
        \\    end
        \\  end
        \\  0
        \\end
        \\fn log(events: Events, xs: List(String)) : UInt32
        \\  for x in xs
        \\    events.emit(x)
        \\  end
        \\  0
        \\end
    , 0);
}

test "a fold into a var over a list is one of the three, and carries its fix" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try findings(arena_state.allocator(),
        \\module T.Fold
        \\fn count(xs: List(UInt32)) : UInt32
        \\  var n = 0
        \\  for x in xs
        \\    n += x
        \\  end
        \\  n
        \\end
    );
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqual(@as(u8, 100), found[0].fixes[0].confidence);
    try std.testing.expectEqualStrings("  n = xs.reduce(n, fn(so_far, x) so_far + x end)\n", found[0].fixes[0].edits[0].text);
}

test "a pure loop inside an honest one is still reported" {
    try expectLoops(
        \\module T.Nested
        \\fn f(xs: List(UInt32)) : Option(UInt32)
        \\  for x in xs
        \\    for y in xs
        \\      z = x + y
        \\      z
        \\    end
        \\    return Some(x)
        \\  end
        \\  None
        \\end
    , 1);
}
