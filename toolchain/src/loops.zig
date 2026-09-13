//! MO0501, chapter 4's loop rule (toolchain/FORMAT.md, "Loops"): a pure body is
//! written with map, filter, or reduce; `for` is for effects, `try`, `break`, or
//! `return`. `mo check` runs this after the capability pass and `mo fmt --check`
//! runs it too. The finding is reported, never rewritten; rewriting is `mo fix`.
//!
//! A body is pure when it holds no capability call, no `try`, no `break`, no
//! `return`, and no assignment to a name declared outside the loop. A capability
//! call is a call on a capability or a process handle, a call that passes one, or
//! `Process.start`. Reads the types check.zig decided.
const std = @import("std");
const ast = @import("ast.zig");
const checker = @import("check.zig");
const diag = @import("diag.zig");
const prelude = @import("prelude.zig");
const types = @import("types.zig");

const Index = ast.Index;

pub const Error = error{OutOfMemory};

pub const code = "MO0501";
pub const what = "this for has a pure body; write it as map, filter, or reduce";
pub const why = "A pure loop body is written with map, filter, or reduce, so a for always says an effect, a try, a break, or a return is inside (chapter 4, loops). mo fix will rewrite it; until then, write the combinator.";

pub fn check(gpa: std.mem.Allocator, checked: checker.Checked, out: *diag.List) Error!void {
    var l: Loops = .{ .gpa = gpa, .k = &checked, .out = out };
    const root = checked.tree.nodes[0];
    for (checked.tree.span(root.lhs, root.rhs)) |it| try l.item(it);
}

/// A name bound in the unit, and the loops around the place it is bound.
const Binder = struct { text: []const u8, loops: []const Index };

const Loops = struct {
    gpa: std.mem.Allocator,
    k: *const checker.Checked,
    out: *diag.List,
    binders: std.ArrayList(Binder) = .empty,
    fors: std.ArrayList(Index) = .empty,
    stack: std.ArrayList(Index) = .empty,

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
        for (params) |p| try l.binders.append(l.gpa, .{ .text = l.text(l.node(p).main_token), .loops = &.{} });
        for (implicit) |name| try l.binders.append(l.gpa, .{ .text = name, .loops = &.{} });
        for (stmts) |s| try l.collect(s);
        for (l.fors.items) |f| {
            if (l.pure(f)) {
                const kw = l.node(f).main_token - 1;
                try l.out.append(l.gpa, .{ .code = code, .category = .format, .at = l.k.tree.tokens[kw].start, .what = what, .why = why });
            }
        }
    }

    fn bindTok(l: *Loops, tok: u32) Error!void {
        if (l.k.tree.tokens[tok].kind != .ident) return; // `for _ in`
        try l.binders.append(l.gpa, .{ .text = l.text(tok), .loops = try l.gpa.dupe(Index, l.stack.items) });
    }

    fn collect(l: *Loops, i: Index) Error!void {
        const n = l.node(i);
        switch (n.kind) {
            .binding, .var_binding, .pat_bind => try l.bindTok(n.main_token),
            .for_stmt => {
                try l.fors.append(l.gpa, i);
                try l.collect(n.lhs);
                try l.stack.append(l.gpa, i);
                try l.bindTok(n.main_token);
                for (l.spanAt(n.rhs)) |s| try l.collect(s);
                _ = l.stack.pop();
                return;
            },
            .anon_fn => {
                const data = l.k.tree.extraData(ast.AnonFn, n.lhs);
                for (l.k.tree.span(data.params_start, data.params_end)) |tok| try l.bindTok(tok);
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

test "a pure for body is reported at its for" {
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
        \\fn count(xs: List(UInt32)) : UInt32
        \\  var n = 0
        \\  for x in xs
        \\    n += x
        \\  end
        \\  n
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
