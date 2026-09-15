//! Which reads of a local hand its value on instead of sharing it (step 28).
//!
//! A map's or set's entries, or a struct's fields, that one holder holds alone are written in
//! place (vm.zig, owned; runtime/mo_rt.c, owned). Any read that can leave the value held twice
//! gives that claim up (`load_shared`, `disown`), so the next write copies. A read keeps the
//! claim, and hands it to whatever takes the value (a parameter, a binding, a return, a field),
//! when nothing can read the same place after it. Two rules say when, both on the checked tree:
//!
//!   - Liveness. A read of a local, or of a field path under one, is the local's last read: no
//!     read later in the function (in evaluation order) overlaps its path, it is not inside a
//!     loop the local was bound outside of, nor inside an anonymous function (a capture), nor a
//!     case guard (a guard that is false hands the subject to the next arm). Only a function's
//!     parameters and the names its body binds take part: a process's `state`, `message`, and
//!     parameters live past the update, and a function with an `ensures` reads its parameters
//!     after the body.
//!   - Overwrite. The one read of a place on the right of an assignment to that same place
//!     (`m = m.set(k, v)`, `state.board = put(state.board, i)`), when nothing else on the right
//!     reads an overlapping path and nothing on the right can leave early (`try`, `return`,
//!     `break`): the place is overwritten as soon as the right side is done.
//!
//! A read's mark goes on its node: a `name_ref`, or the outermost of a chain of field and tuple
//! projections under one. Both backends (bytecode.zig, emit_c.zig) ask `has`, and a read of a
//! type `ownable` says can hold such a buffer, that is not a move, gives its claim up.
const std = @import("std");
const ast = @import("ast.zig");
const check = @import("check.zig");
const types = @import("types.zig");

const Index = ast.Index;
const Id = types.Id;

pub const Error = error{OutOfMemory};

pub const Moves = struct {
    set: std.AutoHashMapUnmanaged(Index, void) = .empty,
    /// Checker type id → whether a value of it can hold a buffer one holder owns: a map, a set,
    /// a struct, or a tuple, option, result, enum, or message holding one. A list's elements
    /// never do (a row that puts a value into a list gives its claim up).
    ownable: []const bool = &.{},

    pub fn has(m: *const Moves, i: Index) bool {
        return m.set.contains(i);
    }

    pub fn owns(m: *const Moves, k: *const check.Checked, t: Id) bool {
        const r = k.pool.resolve(t);
        return r < m.ownable.len and m.ownable[r];
    }
};

pub fn analyze(gpa: std.mem.Allocator, k: *const check.Checked) Error!Moves {
    var out: Moves = .{ .ownable = try ownableTypes(gpa, k) };
    const tree = k.tree;
    for (tree.nodes, 0..) |n, i| {
        var w: Walker = .{ .gpa = gpa, .k = k, .out = &out };
        switch (n.kind) {
            .fn_decl => {
                const sig = tree.extraData(ast.Signature, n.lhs);
                const contract_nodes = tree.span(sig.contracts_start, sig.contracts_end);
                const ensures = for (contract_nodes) |c| {
                    if (tree.nodes[c].kind == .ensures) break true;
                } else false;
                for (tree.span(sig.params_start, sig.params_end)) |p| try w.declare(tree.nodes[p].main_token, !ensures);
                const body = tree.extraData(ast.FnBody, n.rhs);
                try w.block(tree.span(body.start, body.end));
            },
            .test_decl, .test_rejects => try w.block(tree.span(n.lhs, n.rhs)),
            .process_decl => {
                const data = tree.extraData(ast.Process, n.lhs);
                if (data.update == 0) continue;
                // `state` and `message` live past the update, but an assignment to a place under
                // `state` still takes its one read on the right.
                const update = tree.nodes[data.update];
                for ([_][]const u8{ "state", "message" }) |name| try w.declareName(name, update.main_token, false);
                try w.stmt(update.lhs);
            },
            else => continue,
        }
        try w.finish();
        _ = i;
    }
    return out;
}

/// The fixed point of `Moves.ownable` over every type in the pool.
fn ownableTypes(gpa: std.mem.Allocator, k: *const check.Checked) Error![]bool {
    const pool = &k.pool;
    const n = pool.list.items.len;
    const out = try gpa.alloc(bool, n);
    @memset(out, false);
    var changed = true;
    while (changed) {
        changed = false;
        for (0..n) |id| {
            if (out[id]) continue;
            const t = pool.get(@intCast(id));
            const yes = switch (t.tag) {
                .map, .set, .state => true,
                .variable => blk: {
                    const r = pool.resolve(@intCast(id));
                    break :blk r != id and out[r];
                },
                .alias => out[t.b],
                .option => out[t.a],
                .result => out[t.a] or out[t.b],
                .tuple => for (pool.elems(t)) |e| {
                    if (out[e]) break true;
                } else false,
                .decl, .message => blk: {
                    const d = k.decls[t.a];
                    if (t.tag == .decl and d.kind == .struct_) break :blk true;
                    if (t.tag == .decl and d.kind != .enum_) break :blk false;
                    for (k.variants[d.variants.start..d.variants.end]) |v| {
                        for (k.fields[v.fields.start..v.fields.end]) |f| if (out[f.type]) break :blk true;
                    }
                    break :blk false;
                },
                else => false,
            };
            if (yes) {
                out[id] = true;
                changed = true;
            }
        }
    }
    return out;
}

const Read = struct {
    /// Where a move's mark goes; 0 for a read that is never one (an assignment's target).
    node: Index,
    /// The binding token, plus 1 (check.Checked.binding_of).
    binding: u32,
    path_start: u32,
    path_len: u32,
    /// Evaluation order; reads a constructor's arguments make share one, since the lowering
    /// takes them in the fields' order.
    seq: u32,
    /// Never a move by liveness: inside a loop the binding was declared outside of, an
    /// anonymous function it was declared outside of, or a case guard.
    stays: bool,
    loop_depth: u32,
    fn_depth: u32,
};

const Decl = struct { loop_depth: u32, fn_depth: u32, movable: bool };

const Walker = struct {
    gpa: std.mem.Allocator,
    k: *const check.Checked,
    out: *Moves,
    decls: std.AutoHashMapUnmanaged(u32, Decl) = .empty,
    reads: std.ArrayList(Read) = .empty,
    paths: std.ArrayList([]const u8) = .empty,
    /// Names bound in scope, innermost last, for an assignment written as a binding (`m = e`
    /// on a var), whose name the checker does not resolve.
    scope: std.ArrayList(struct { name: []const u8, token: u32 }) = .empty,
    seq: u32 = 0,
    loop_depth: u32 = 0,
    fn_depth: u32 = 0,
    guard_depth: u32 = 0,
    /// `try`, `return`, and `break` walked in the function at fn_depth.
    exits: u32 = 0,

    fn node(w: *Walker, i: Index) ast.Node {
        return w.k.tree.nodes[i];
    }

    fn text(w: *Walker, tok: u32) []const u8 {
        return w.k.tree.tokenText(tok);
    }

    fn declare(w: *Walker, tok: u32, movable: bool) Error!void {
        try w.declareName(w.text(tok), tok, movable);
    }

    fn declareName(w: *Walker, name: []const u8, tok: u32, movable: bool) Error!void {
        try w.decls.put(w.gpa, tok + 1, .{ .loop_depth = w.loop_depth, .fn_depth = w.fn_depth, .movable = movable });
        try w.scope.append(w.gpa, .{ .name = name, .token = tok });
    }

    fn block(w: *Walker, stmts: []const u32) Error!void {
        const mark = w.scope.items.len;
        for (stmts) |s| try w.stmt(s);
        w.scope.shrinkRetainingCapacity(mark);
    }

    fn stmt(w: *Walker, s: Index) Error!void {
        const n = w.node(s);
        switch (n.kind) {
            .expr_stmt, .assert_stmt => try w.expr(n.lhs),
            .binding => {
                const name = w.text(n.main_token);
                if (w.inScope(name)) |tok| {
                    try w.overwrite(tok + 1, &.{}, n.lhs);
                } else {
                    try w.expr(n.lhs);
                    try w.declare(n.main_token, true);
                }
            },
            .var_binding => {
                try w.expr(n.lhs);
                try w.declare(n.main_token, true);
            },
            .assign => {
                const place = w.placeOf(n.lhs, true);
                if (std.mem.eql(u8, w.text(n.main_token), "=")) {
                    if (place) |p| try w.overwrite(p.binding, p.path, n.rhs) else try w.expr(n.rhs);
                    // The target's struct is rebuilt with the field set: a read of its path.
                    if (place) |p| if (p.path.len > 0) try w.read(0, p.binding, p.path);
                } else {
                    if (place) |p| try w.read(0, p.binding, p.path) else try w.expr(n.lhs);
                    try w.expr(n.rhs);
                }
            },
            .return_stmt => {
                if (n.rhs != 0) try w.expr(n.rhs);
                try w.expr(n.lhs);
                w.exits += 1;
            },
            .break_stmt => w.exits += 1,
            .for_stmt => {
                try w.expr(n.lhs);
                w.loop_depth += 1;
                const mark = w.scope.items.len;
                if (w.k.tree.tokens[n.main_token].kind == .ident) try w.declare(n.main_token, true);
                try w.block(w.spanAt(n.rhs));
                w.scope.shrinkRetainingCapacity(mark);
                w.loop_depth -= 1;
            },
            .if_stmt => try w.ifNode(n),
            .case_stmt => try w.caseNode(n),
            else => try w.expr(s),
        }
    }

    fn spanAt(w: *Walker, extra_index: u32) []const u32 {
        if (extra_index == 0) return &.{};
        const s = w.k.tree.extraData(ast.Span, extra_index);
        return w.k.tree.span(s.start, s.end);
    }

    fn inScope(w: *Walker, name: []const u8) ?u32 {
        var i = w.scope.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, w.scope.items[i].name, name)) return w.scope.items[i].token;
        }
        return null;
    }

    fn ifNode(w: *Walker, n: ast.Node) Error!void {
        const data = w.k.tree.extraData(ast.If, n.rhs);
        try w.expr(n.lhs);
        try w.block(w.k.tree.span(data.then_start, data.then_end));
        try w.block(w.k.tree.span(data.else_start, data.else_end));
    }

    fn caseNode(w: *Walker, n: ast.Node) Error!void {
        try w.expr(n.lhs);
        for (w.spanAt(n.rhs)) |a| {
            const an = w.node(a);
            const data = w.k.tree.extraData(ast.Arm, an.rhs);
            const mark = w.scope.items.len;
            try w.pattern(an.lhs);
            if (data.guard != 0) {
                w.guard_depth += 1;
                try w.expr(data.guard);
                w.guard_depth -= 1;
            }
            try w.block(w.k.tree.span(data.body_start, data.body_end));
            w.scope.shrinkRetainingCapacity(mark);
        }
    }

    fn pattern(w: *Walker, p: Index) Error!void {
        if (p == 0) return;
        const n = w.node(p);
        switch (n.kind) {
            .pat_bind => try w.declare(n.main_token, true),
            .pat_variant, .pat_field => try w.pattern(n.lhs),
            .pat_record, .pat_tuple, .pat_or => for (w.k.tree.span(n.lhs, n.rhs)) |x| try w.pattern(x),
            else => {},
        }
    }

    const Place = struct { binding: u32, path: []const []const u8 };

    /// A name, or a chain of field and tuple projections under one, that reads a local. The
    /// checker resolves no assignment's `target`, so its name is found in scope.
    fn placeOf(w: *Walker, i: Index, target: bool) ?Place {
        var names: [16][]const u8 = undefined;
        var len: usize = 0;
        var at = i;
        while (true) {
            const n = w.node(at);
            switch (n.kind) {
                .member => {
                    if (w.k.callee[at] != .none or len == names.len) return null;
                    names[len] = w.text(n.main_token);
                },
                .tuple_index => {
                    if (len == names.len) return null;
                    names[len] = w.text(n.main_token);
                },
                .name_ref => {
                    const b = if (w.k.binding_of[at] != 0) w.k.binding_of[at] else if (target) (w.inScope(w.text(n.main_token)) orelse return null) + 1 else 0;
                    if (b == 0) return null;
                    const path = w.gpa.alloc([]const u8, len) catch return null;
                    for (path, 0..) |*p, j| p.* = names[len - 1 - j];
                    return .{ .binding = b, .path = path };
                },
                else => return null,
            }
            len += 1;
            at = n.lhs;
        }
    }

    fn read(w: *Walker, at: Index, binding: u32, path: []const []const u8) Error!void {
        const start: u32 = @intCast(w.paths.items.len);
        try w.paths.appendSlice(w.gpa, path);
        const decl = w.decls.get(binding);
        const stays = w.guard_depth > 0 or if (decl) |d| (w.loop_depth > d.loop_depth or w.fn_depth > d.fn_depth) else true;
        w.seq += 1;
        try w.reads.append(w.gpa, .{
            .node = at,
            .binding = binding,
            .path_start = start,
            .path_len = @intCast(path.len),
            .seq = w.seq,
            .stays = stays,
            .loop_depth = w.loop_depth,
            .fn_depth = w.fn_depth,
        });
    }

    /// `place = value`: the one read of the place inside `value` is a move when nothing else
    /// there overlaps it and nothing there leaves early.
    fn overwrite(w: *Walker, binding: u32, path: []const []const u8, value: Index) Error!void {
        const first = w.reads.items.len;
        const exits = w.exits;
        try w.expr(value);
        if (w.exits != exits) return;
        var found: ?usize = null;
        for (w.reads.items[first..], first..) |r, x| {
            if (r.binding != binding) continue;
            const rp = w.pathOf(r);
            if (!overlaps(rp, path)) continue;
            if (found != null or r.node == 0 or !samePath(rp, path) or r.loop_depth != w.loop_depth or r.fn_depth != w.fn_depth) return;
            found = x;
        }
        if (found) |x| try w.out.set.put(w.gpa, w.reads.items[x].node, {});
    }

    fn pathOf(w: *Walker, r: Read) []const []const u8 {
        return w.paths.items[r.path_start..][0..r.path_len];
    }

    fn expr(w: *Walker, i: Index) Error!void {
        if (i == 0) return;
        const n = w.node(i);
        switch (n.kind) {
            .name_ref => if (w.k.binding_of[i] != 0) try w.read(i, w.k.binding_of[i], &.{}),
            .member, .tuple_index => {
                if (w.placeOf(i, false)) |p| return w.read(i, p.binding, p.path);
                try w.expr(n.lhs);
            },
            .string_interp, .tuple, .list => for (w.k.tree.span(n.lhs, n.rhs)) |x| {
                if (w.node(x).kind != .string_part) try w.expr(x);
            },
            .not_expr, .negate, .named_arg, .old_expr => try w.expr(n.lhs),
            .try_expr => {
                try w.expr(n.lhs);
                w.exits += 1;
            },
            .implies, .or_expr, .and_expr, .compare, .range, .add, .mul => {
                try w.expr(n.lhs);
                try w.expr(n.rhs);
            },
            .is_expr => {
                try w.expr(n.lhs);
                try w.pattern(n.rhs);
            },
            .member_call, .call => {
                const args = w.spanAt(n.rhs);
                const constructs = n.kind == .call and w.node(n.lhs).kind == .type_name_ref;
                if (!constructs) try w.expr(n.lhs);
                const reorders = constructs or for (args) |a| {
                    if (w.node(a).kind == .named_arg) break true;
                } else false;
                const first = w.reads.items.len;
                for (args) |a| try w.expr(a);
                // The lowering takes a construction's fields, and a row's named arguments, in
                // their declared order: every read among them is taken as happening at once.
                if (reorders) for (w.reads.items[first..]) |*r| {
                    r.seq = w.seq;
                };
            },
            .if_expr => try w.ifNode(n),
            .case_expr => try w.caseNode(n),
            .anon_fn => {
                const data = w.k.tree.extraData(ast.AnonFn, n.lhs);
                const exits = w.exits;
                w.fn_depth += 1;
                const mark = w.scope.items.len;
                for (w.k.tree.span(data.params_start, data.params_end)) |tok| try w.declare(tok, true);
                try w.block(w.k.tree.span(data.body_start, data.body_end));
                w.scope.shrinkRetainingCapacity(mark);
                w.fn_depth -= 1;
                w.exits = exits;
            },
            .comprehension => {
                const data = w.k.tree.extraData(ast.Comprehension, n.lhs);
                const mark = w.scope.items.len;
                const depth = w.loop_depth;
                for (w.k.tree.span(data.gens_start, data.gens_end)) |g| {
                    try w.expr(w.node(g).lhs);
                    w.loop_depth += 1;
                    try w.declare(w.node(g).main_token, false);
                }
                try w.expr(data.guard);
                try w.block(w.k.tree.span(data.body_start, data.body_end));
                w.loop_depth = depth;
                w.scope.shrinkRetainingCapacity(mark);
            },
            // Statements in expression position (a block's last line).
            .binding, .var_binding, .assign, .return_stmt, .break_stmt, .for_stmt, .if_stmt, .case_stmt, .expr_stmt, .assert_stmt => try w.stmt(i),
            else => {},
        }
    }

    /// Every read that is its local's last, by liveness, gets its mark.
    fn finish(w: *Walker) Error!void {
        const reads = w.reads.items;
        for (reads, 0..) |r, x| {
            if (r.node == 0 or r.stays) continue;
            const d = w.decls.get(r.binding) orelse continue;
            if (!d.movable) continue;
            const rp = w.pathOf(r);
            const later = for (reads, 0..) |o, y| {
                if (y == x or o.binding != r.binding or o.seq < r.seq) continue;
                if (overlaps(w.pathOf(o), rp)) break true;
            } else false;
            if (!later) try w.out.set.put(w.gpa, r.node, {});
        }
    }
};

/// Whether one path is a prefix of the other: a read of either sees the other's buffers.
fn overlaps(a: []const []const u8, b: []const []const u8) bool {
    for (a[0..@min(a.len, b.len)], b[0..@min(a.len, b.len)]) |x, y| {
        if (!std.mem.eql(u8, x, y)) return false;
    }
    return true;
}

fn samePath(a: []const []const u8, b: []const []const u8) bool {
    return a.len == b.len and overlaps(a, b);
}

test "a local's last read moves, a read before another does not, and a loop or a capture keeps a read" {
    const lexer = @import("lexer.zig");
    const parser = @import("parser.zig");
    const diag = @import("diag.zig");
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src =
        \\module T.Moves
        \\struct Box
        \\  data: Map(UInt64, UInt64)
        \\  seen: Set(UInt64)
        \\end
        \\fn put(box: Box, i: UInt64) : Box
        \\  var next = box
        \\  next.data = next.data.set(i, i)
        \\  next
        \\end
        \\fn twice(box: Box) : (Box, Box)
        \\  (box, box)
        \\end
        \\fn halves(pair: (Box, Box)) : (Box, Box)
        \\  (put(pair.0, 1), put(pair.1, 2))
        \\end
        \\fn looped(box: Box) : UInt64
        \\  var total = 0
        \\  for i in 0..3
        \\    total += put(box, i).data.size
        \\  end
        \\  total
        \\end
        \\fn kept(box: Box, xs: List(UInt64)) : UInt64
        \\  xs.map(fn(x) put(box, x).data.size end).size
        \\end
        \\fn rewritten(box: Box, xs: List(UInt64)) : Box
        \\  var b = box
        \\  for x in xs
        \\    b = put(b, x)
        \\  end
        \\  b
        \\end
    ;
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    const checked = try check.check(arena, tree, &diags);
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);
    const moves = try analyze(arena, &checked);
    // Each read of a local, in source order, and whether it moves.
    const want = [_]struct { name: []const u8, moves: bool }{
        .{ .name = "box", .moves = true }, // var next = box
        .{ .name = "next", .moves = true }, // next.data.set: overwritten
        .{ .name = "i", .moves = false },
        .{ .name = "i", .moves = true },
        .{ .name = "next", .moves = true }, // next
        .{ .name = "box", .moves = false }, // (box, box): not the last
        .{ .name = "box", .moves = true },
        .{ .name = "pair", .moves = true }, // pair.0
        .{ .name = "pair", .moves = true }, // pair.1: another path
        .{ .name = "box", .moves = false }, // inside a loop
        .{ .name = "i", .moves = true }, // bound inside it
        .{ .name = "total", .moves = true },
        .{ .name = "xs", .moves = true },
        .{ .name = "box", .moves = false }, // a capture
        .{ .name = "x", .moves = true },
        .{ .name = "box", .moves = true },
        .{ .name = "xs", .moves = true },
        .{ .name = "b", .moves = true }, // put(b, x): overwritten
        .{ .name = "x", .moves = true },
        .{ .name = "b", .moves = true },
    };
    var got: std.ArrayList(struct { at: u32, name: []const u8, moves: bool }) = .empty;
    for (tree.nodes, 0..) |n, i| {
        if (n.kind != .name_ref or checked.binding_of[i] == 0) continue;
        // A projection's mark is on its outermost node.
        var top: Index = @intCast(i);
        for (tree.nodes, 0..) |m, j| {
            if ((m.kind == .member or m.kind == .tuple_index) and m.lhs == top and checked.callee[j] == .none) top = @intCast(j);
        }
        try got.append(arena, .{ .at = tree.tokens[n.main_token].start, .name = tree.tokenText(n.main_token), .moves = moves.has(top) });
    }
    std.mem.sort(@TypeOf(got.items[0]), got.items, {}, struct {
        fn lt(_: void, a: @TypeOf(got.items[0]), b: @TypeOf(got.items[0])) bool {
            return a.at < b.at;
        }
    }.lt);
    // An assignment's target is not a read the checker resolves, so it has no row.
    var at: usize = 0;
    for (want) |x| {
        try std.testing.expect(at < got.items.len);
        try std.testing.expectEqualStrings(x.name, got.items[at].name);
        if (x.moves != got.items[at].moves) {
            std.debug.print("read {d} of {s}: expected moves = {}\n", .{ at, x.name, x.moves });
            return error.TestUnexpectedResult;
        }
        at += 1;
    }
    try std.testing.expectEqual(got.items.len, at);
}
