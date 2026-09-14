//! `mo fix` (design-v0/07): applies every diagnostic fix that carries confidence 100 and
//! rewrites the file. Three codes carry such fixes. MO0501's is built by the loop rule
//! (loops.zig): the three accumulator loops become map, filter, or reduce. MO0307 deletes
//! an unused binding's line when its value is pure. MO0312 drops a default and passes it
//! at every call in the file that leaves the parameter out. Every other code's catalog row
//! says `fixes: []`; MO0101's fix, which wrote a one-line `if` as its block (step 21), went
//! when the one-line `if` became a value (step 25), so a file that does not parse has
//! nothing to fix.
//!
//! A fix is a list of edits into the program's source. One pass checks the program,
//! takes each fix whose edits lie in the file and overlap no fix taken before it, and
//! formats the result; the next pass checks again, because deleting a binding can leave
//! the binding it read unused. A pass whose result does not format is not taken.
const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const check = @import("check.zig");
const loops = @import("loops.zig");
const program = @import("program.zig");
const pipeline = @import("pipeline.zig");
const fmt = @import("fmt.zig");

const Index = ast.Index;

pub const Error = error{OutOfMemory};

/// A file needs at most this many passes; each one only removes or rewrites code.
pub const max_passes = 16;

// ---- reading tokens

/// Whether token `t` opens a block that `end` closes: `for`, `case`, `fn`, and an `if`
/// that is not trailing a `return` (grammar §5) and is not the one-line value form, or an
/// arm's guard, whose condition ends in `:` (step 25).
pub fn opensBlock(tree: ast.Tree, t: u32) bool {
    const toks = tree.tokens;
    switch (toks[t].kind) {
        .kw_for, .kw_case, .kw_fn => return true,
        .kw_if => {
            var k = t;
            while (k > 0 and toks[k - 1].kind != .newline) {
                k -= 1;
                if (toks[k].kind == .kw_return) return false;
            }
            // The condition runs to a `:` or to the line's end, outside every delimiter; an `if`
            // inside it starts a condition of its own, so this one is a block.
            var depth: u32 = 0;
            k = t + 1;
            while (true) : (k += 1) switch (toks[k].kind) {
                .l_paren, .l_bracket, .l_brace => depth += 1,
                .r_paren, .r_bracket, .r_brace => {
                    if (depth == 0) return true;
                    depth -= 1;
                },
                .colon => if (depth == 0) return false,
                .kw_if => if (depth == 0) return true,
                .newline, .eof => return true,
                else => {},
            };
        },
        else => return false,
    }
}

/// The `end` that closes the block token `open` opens.
pub fn blockEnd(tree: ast.Tree, open: u32) u32 {
    var depth: u32 = 0;
    var t = open;
    while (tree.tokens[t].kind != .eof) : (t += 1) {
        if (opensBlock(tree, t)) {
            depth += 1;
        } else if (tree.tokens[t].kind == .kw_end) {
            depth -|= 1;
            if (depth == 0) return t;
        }
    }
    return t;
}

/// The newline, or eof, that ends the line starting at token `from`, past every block
/// that opens on it.
pub fn lineEnd(tree: ast.Tree, from: u32) u32 {
    var depth: u32 = 0;
    var t = from;
    while (true) : (t += 1) switch (tree.tokens[t].kind) {
        .eof => return t,
        .newline => if (depth == 0) return t,
        .kw_end => depth -|= 1,
        else => if (opensBlock(tree, t)) {
            depth += 1;
        },
    };
}

/// The `(` at token `open`, each comma between the arguments it opens, and its `)`.
pub fn delimiters(gpa: std.mem.Allocator, tree: ast.Tree, open: u32) Error![]const u32 {
    var out: std.ArrayList(u32) = .empty;
    try out.append(gpa, open);
    var parens: u32 = 0;
    var blocks: u32 = 0;
    var t = open;
    while (tree.tokens[t].kind != .eof) : (t += 1) switch (tree.tokens[t].kind) {
        .l_paren, .l_bracket, .l_brace => parens += 1,
        .r_paren, .r_bracket, .r_brace => {
            parens -|= 1;
            if (parens == 0) break;
        },
        .comma => if (parens == 1 and blocks == 0) try out.append(gpa, t),
        .kw_end => blocks -|= 1,
        else => if (opensBlock(tree, t)) {
            blocks += 1;
        },
    };
    try out.append(gpa, t);
    return out.items;
}

/// Where the line holding byte `at` starts.
pub fn lineStartByte(source: []const u8, at: u32) u32 {
    return if (std.mem.lastIndexOfScalar(u8, source[0..at], '\n')) |i| @intCast(i + 1) else 0;
}

/// Whether a comment sits between tokens `from` and `to`, or after `to` on its line.
pub fn hasComment(tree: ast.Tree, from: u32, to: u32) bool {
    const src = tree.source;
    var t = from;
    while (t < to) : (t += 1) {
        if (std.mem.indexOfScalar(u8, src[tree.tokens[t].end..tree.tokens[t + 1].start], '#') != null) return true;
    }
    const rest = src[tree.tokens[to].end..];
    const eol = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    return std.mem.indexOfScalar(u8, rest[0..eol], '#') != null;
}

/// Whether token `t` reads a name: an ident that is not a field after `.` and not a
/// label before `:`.
fn readsName(tree: ast.Tree, t: u32) bool {
    if (tree.tokens[t].kind != .ident) return false;
    if (t > 0 and tree.tokens[t - 1].kind == .dot) return false;
    return tree.tokens[t + 1].kind != .colon;
}

/// Whether a token from `from` up to `to` reads `name`.
pub fn mentions(tree: ast.Tree, from: u32, to: u32, name: []const u8) bool {
    var t = from;
    while (t < to) : (t += 1) {
        if (readsName(tree, t) and std.mem.eql(u8, tree.tokenText(t), name)) return true;
    }
    return false;
}

/// The text of tokens `from` up to `to`, each read of `name` spelled `new`.
pub fn renamed(gpa: std.mem.Allocator, tree: ast.Tree, from: u32, to: u32, name: []const u8, new: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var at = tree.tokens[from].start;
    var t = from;
    while (t < to) : (t += 1) {
        if (!readsName(tree, t) or !std.mem.eql(u8, tree.tokenText(t), name)) continue;
        try out.appendSlice(gpa, tree.source[at..tree.tokens[t].start]);
        try out.appendSlice(gpa, new);
        at = tree.tokens[t].end;
    }
    try out.appendSlice(gpa, tree.source[at..tree.tokens[to - 1].end]);
    return out.items;
}

/// `base`, or `base_2`, `base_3`, …: the first that no token of the file spells and
/// `taken` does not hold.
pub fn freshName(gpa: std.mem.Allocator, tree: ast.Tree, base: []const u8, taken: []const []const u8) Error![]const u8 {
    var n: u32 = 1;
    while (true) : (n += 1) {
        const name = if (n == 1) base else try std.fmt.allocPrint(gpa, "{s}_{d}", .{ base, n });
        const used = for (tree.tokens) |tok| {
            if (tok.kind == .eof) break false;
            if (tok.kind == .ident and std.mem.eql(u8, tree.source[tok.start..tok.end], name)) break true;
        } else false;
        const chosen = for (taken) |t| {
            if (std.mem.eql(u8, t, name)) break true;
        } else false;
        if (!used and !chosen) return name;
    }
}

fn spanAt(tree: ast.Tree, extra_index: u32) []const u32 {
    if (extra_index == 0) return &.{};
    const s = tree.extraData(ast.Span, extra_index);
    return tree.span(s.start, s.end);
}

fn nodeAt(tree: ast.Tree, kinds: []const ast.Node.Kind, at: u32) ?Index {
    for (tree.nodes, 0..) |n, i| {
        if (std.mem.indexOfScalar(ast.Node.Kind, kinds, n.kind) == null) continue;
        if (tree.tokens[n.main_token].start == at) return @intCast(i);
    }
    return null;
}

// ---- MO0307 and MO0312

/// Gives the MO0307 and MO0312 records their fixes. MO0501's come with the record.
pub fn attach(gpa: std.mem.Allocator, checked: check.Checked, records: []diag.Record) Error!void {
    const unused = check.catalog.get(.unused_binding).code;
    const default = check.catalog.get(.default_param).code;
    for (records) |*r| {
        if (r.fixes.len > 0) continue;
        const found = if (std.mem.eql(u8, r.code, unused))
            try unusedBinding(gpa, &checked, r.at)
        else if (std.mem.eql(u8, r.code, default))
            try defaultParam(gpa, &checked, r.at)
        else
            null;
        if (found) |f| r.fixes = try gpa.dupe(diag.Fix, &.{f});
    }
}

/// Deletes the line of `x = e` or `var x = e` when `e` is pure, the statement is alone
/// on its lines, and no comment sits on them.
fn unusedBinding(gpa: std.mem.Allocator, k: *const check.Checked, at: u32) Error!?diag.Fix {
    const tree = k.tree;
    const i = nodeAt(tree, &.{ .binding, .var_binding }, at) orelse return null;
    const n = tree.nodes[i];
    const first = if (n.kind == .var_binding) n.main_token - 1 else n.main_token;
    if (first == 0 or tree.tokens[first - 1].kind != .newline) return null;
    const eol = lineEnd(tree, first);
    if (hasComment(tree, first, eol)) return null;
    if (!loops.pureValue(gpa, k, n.lhs)) return null;
    const from = lineStartByte(tree.source, tree.tokens[first].start);
    const to: u32 = @intCast(@min(tree.tokens[eol].start + 1, tree.source.len));
    return .{
        .description = try std.fmt.allocPrint(gpa, "delete the line that binds {s}", .{tree.tokenText(n.main_token)}),
        .confidence = 100,
        .edits = try gpa.dupe(diag.Edit, &.{.{ .at = from, .len = to - from, .text = "" }}),
    };
}

/// Drops every default of the function the parameter belongs to, and passes each at
/// every call in the same module that gives one argument fewer per default.
fn defaultParam(gpa: std.mem.Allocator, k: *const check.Checked, at: u32) Error!?diag.Fix {
    const tree = k.tree;
    const pi = nodeAt(tree, &.{ .param, .param_inout }, at) orelse return null;
    const si = for (k.sigs, 0..) |s, si| {
        const holds = for (k.params[s.params.start..s.params.end]) |p| {
            if (p.node == pi) break true;
        } else false;
        if (holds) break si;
    } else return null;
    const s = k.sigs[si];
    const ps = k.params[s.params.start..s.params.end];

    var edits: std.ArrayList(diag.Edit) = .empty;
    const values = try gpa.alloc(?[]const u8, ps.len);
    var defaults: usize = 0;
    for (ps, values) |p, *value| {
        value.* = null;
        const pn = tree.nodes[p.node];
        if (pn.rhs == 0) continue;
        const eq = paramEq(tree, pn.main_token) orelse return null;
        const last = valueEnd(tree, eq + 1) - 1;
        value.* = tree.source[tree.tokens[eq + 1].start..tree.tokens[last].end];
        defaults += 1;
        const from = tree.tokens[eq - 1].end;
        try edits.append(gpa, .{ .at = from, .len = tree.tokens[last].end - from, .text = "" });
    }

    const module = k.moduleOf(s.node);
    for (tree.nodes, 0..) |n, i| {
        if (n.kind != .call and n.kind != .member_call) continue;
        switch (k.callee[i]) {
            .user => |c| if (c != si) continue,
            else => continue,
        }
        if (k.moduleOf(@intCast(i)) != module) continue;
        const recv = n.kind == .member_call;
        const args = spanAt(tree, n.rhs);
        const open: u32 = if (recv) n.main_token + 1 else n.main_token;
        const delims = try delimiters(gpa, tree, open);
        var positional: std.ArrayList(u32) = .empty;
        for (args, 0..) |a, j| if (tree.nodes[a].kind != .named_arg) try positional.append(gpa, @intCast(j));
        const given = positional.items.len + @intFromBool(recv);
        if (given == ps.len or given + defaults != ps.len) continue;

        var pending: std.ArrayList(u8) = .empty;
        var g: usize = 0;
        for (values) |value| {
            if (value) |v| {
                if (pending.items.len > 0) try pending.appendSlice(gpa, ", ");
                try pending.appendSlice(gpa, v);
                continue;
            }
            if (pending.items.len > 0) {
                // A dot call's receiver is its first argument; nothing goes before it.
                if (recv and g == 0) return null;
                const j = positional.items[g - @intFromBool(recv)];
                try pending.appendSlice(gpa, ", ");
                try edits.append(gpa, .{ .at = tree.tokens[delims[j] + 1].start, .len = 0, .text = pending.items });
                pending = .empty;
            }
            g += 1;
        }
        if (pending.items.len == 0) continue;
        if (positional.items.len > 0) {
            const j = positional.items[positional.items.len - 1];
            const text = try std.fmt.allocPrint(gpa, ", {s}", .{pending.items});
            try edits.append(gpa, .{ .at = tree.tokens[delims[j + 1] - 1].end, .len = 0, .text = text });
        } else {
            if (args.len > 0) try pending.appendSlice(gpa, ", ");
            try edits.append(gpa, .{ .at = tree.tokens[open].end, .len = 0, .text = pending.items });
        }
    }
    return .{
        .description = try std.fmt.allocPrint(gpa, "drop the default{s} of {s} and pass {s} at each call", .{ if (defaults == 1) "" else "s", s.name, if (defaults == 1) "it" else "them" }),
        .confidence = 100,
        .edits = edits.items,
    };
}

/// The `=` of `name: Type = value`, outside the type's parentheses.
fn paramEq(tree: ast.Tree, name: u32) ?u32 {
    var depth: u32 = 0;
    var t = name;
    while (tree.tokens[t].kind != .eof) : (t += 1) switch (tree.tokens[t].kind) {
        .l_paren, .l_bracket => depth += 1,
        .r_paren, .r_bracket => {
            if (depth == 0) return null;
            depth -= 1;
        },
        .comma => if (depth == 0) return null,
        .eq => if (depth == 0) return t,
        else => {},
    };
    return null;
}

/// The `,` or `)` that ends a parameter's default value starting at token `from`.
fn valueEnd(tree: ast.Tree, from: u32) u32 {
    var depth: u32 = 0;
    var t = from;
    while (tree.tokens[t].kind != .eof) : (t += 1) switch (tree.tokens[t].kind) {
        .l_paren, .l_bracket, .l_brace => depth += 1,
        .r_paren, .r_bracket, .r_brace => {
            if (depth == 0) return t;
            depth -= 1;
        },
        .comma => if (depth == 0) return t,
        else => {},
    };
    return t;
}

// ---- applying

pub const Applied = struct { source: []const u8, fixed: []const diag.Record };

fn overlaps(a: diag.Edit, b: diag.Edit) bool {
    if (a.len == 0 and b.len == 0) return a.at == b.at;
    if (a.len == 0) return b.at <= a.at and a.at <= b.at + b.len;
    if (b.len == 0) return a.at <= b.at and b.at <= a.at + a.len;
    return a.at < b.at + b.len and b.at < a.at + a.len;
}

/// Applies, to `file`, each record's first fix of confidence 100 whose edits all lie in
/// the file and overlap no edit already taken. `fixed` holds each record whose fix was
/// taken, with only that fix.
pub fn apply(gpa: std.mem.Allocator, file: diag.File, records: []const diag.Record) Error!Applied {
    const lo = file.base;
    const hi = file.base + file.source.len;
    var taken: std.ArrayList(diag.Edit) = .empty;
    var fixed: std.ArrayList(diag.Record) = .empty;
    for (records) |r| for (r.fixes) |f| {
        if (f.confidence < 100 or f.edits.len == 0) continue;
        const fits = for (f.edits) |e| {
            if (e.at < lo or e.at + e.len > hi) break false;
            const clash = for (taken.items) |t| {
                if (overlaps(e, t)) break true;
            } else false;
            if (clash) break false;
        } else true;
        if (!fits) continue;
        try taken.appendSlice(gpa, f.edits);
        var one = r;
        one.fixes = try gpa.dupe(diag.Fix, &.{f});
        try fixed.append(gpa, one);
        break;
    };
    std.mem.sort(diag.Edit, taken.items, {}, struct {
        fn lt(_: void, a: diag.Edit, b: diag.Edit) bool {
            return a.at < b.at;
        }
    }.lt);
    var out: std.ArrayList(u8) = .empty;
    var at: u32 = 0;
    for (taken.items) |e| {
        try out.appendSlice(gpa, file.source[at .. e.at - lo]);
        try out.appendSlice(gpa, e.text);
        at = e.at - lo + e.len;
    }
    try out.appendSlice(gpa, file.source[at..]);
    return .{ .source = out.items, .fixed = fixed.items };
}

/// A fix `mo fix` took: its code, the line it was found on in its pass, and what it did.
pub const Taken = struct { code: []const u8, line: usize, description: []const u8 };

pub const Outcome = struct { source: []const u8, taken: []const Taken };

/// Fixes the program's main file until no fix applies, and gives its text. The program
/// on disk is not touched.
pub fn run(gpa: std.mem.Allocator, prog: program.Program) !Outcome {
    var current = prog;
    var taken: std.ArrayList(Taken) = .empty;
    var pass: u32 = 0;
    while (pass < max_passes) : (pass += 1) {
        var diags: diag.List = .empty;
        pipeline.runTo(gpa, current, .check, &diags) catch |err| switch (err) {
            error.Rejected => {},
            else => |e| return e,
        };
        const file = current.main();
        const applied = try apply(gpa, file, diags.items);
        if (applied.fixed.len == 0) break;
        var scratch: diag.List = .empty;
        const formatted = fmt.format(gpa, applied.source, &scratch) catch |err| switch (err) {
            error.Rejected => break,
            else => |e| return e,
        };
        for (applied.fixed) |r| try taken.append(gpa, .{
            .code = r.code,
            .line = diag.position(file.source, r.at - file.base).line,
            .description = r.fixes[0].description,
        });
        current = try program.withMain(gpa, current, formatted);
    }
    return .{ .source = current.main().source, .taken = taken.items };
}

// ---- tests

const runner = @import("runner.zig");

/// The file after `mo fix`, checked clean and its tests passing.
fn expectFixed(arena: std.mem.Allocator, src: []const u8) ![]const u8 {
    const out = try run(arena, try program.single(arena, "t.mo", src));
    var diags: diag.List = .empty;
    const r = pipeline.testProgram(arena, try program.single(arena, "t.mo", out.source), false, .{}, &diags) catch |err| {
        std.debug.print("{s}\n", .{out.source});
        for (diags.items) |d| std.debug.print("  {s} at {d}: {s}\n", .{ d.code, d.at, d.what });
        return err;
    };
    try std.testing.expectEqual(@as(u32, 0), r.summary.failures);
    return out.source;
}

fn contains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("expected to find\n  {s}\nin\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

test "MO0307: an unused binding with a pure value goes, and so does what only it read" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try expectFixed(arena,
        \\module T.Unused
        \\expose total
        \\
        \\fn total(price: UInt32, tax: UInt32) : UInt32
        \\  rate = 10
        \\  discount = price / rate
        \\  sum = price + tax
        \\  sum
        \\end
        \\
        \\test "tax is added"
        \\  assert total(100, 10) == 110
        \\end
        \\
    );
    try std.testing.expect(std.mem.indexOf(u8, out, "discount") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "rate") == null);
    try contains(out, "  sum = price + tax\n");
}

test "MO0307: a binding whose value calls a capability, or carries a comment, is kept" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src =
        \\module T.Kept
        \\
        \\fn stamp(clock: Clock) : UInt8
        \\  now = clock.now
        \\  kept = 1 # a note
        \\  1
        \\end
        \\
    ;
    var diags: diag.List = .empty;
    pipeline.runTo(arena, try program.single(arena, "t.mo", src), .check, &diags) catch {};
    var unused: u32 = 0;
    for (diags.items) |d| if (std.mem.eql(u8, d.code, "MO0307")) {
        unused += 1;
        try std.testing.expectEqual(@as(usize, 0), d.fixes.len);
    };
    try std.testing.expectEqual(@as(u32, 2), unused);
    try std.testing.expectEqualStrings(src, (try run(arena, try program.single(arena, "t.mo", src))).source);
}

test "MO0312: the default is dropped and passed at every call that left it out" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try expectFixed(arena,
        \\module T.Defaults
        \\expose greet
        \\
        \\fn greet(greeting: String, name: String = "friend") : String
        \\  "#{greeting}, #{name}!"
        \\end
        \\
        \\test "greets"
        \\  hey = "Hey"
        \\  assert greet("Hello") == "Hello, friend!"
        \\  assert greet("Hi", "Ada") == "Hi, Ada!"
        \\  assert hey.greet() == "Hey, friend!"
        \\end
        \\
    );
    try contains(out, "fn greet(greeting: String, name: String) : String\n");
    try contains(out, "greet(\"Hello\", \"friend\")");
    try contains(out, "greet(\"Hi\", \"Ada\")");
    try contains(out, "hey.greet(\"friend\")");
}

test "MO0501: the three accumulator loops become map, filter, and reduce" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try expectFixed(arena,
        \\module T.Loops
        \\expose doubled, evens, total, number, left
        \\
        \\fn doubled(xs: List(UInt32)) : List(UInt32)
        \\  var out = xs.take(0)
        \\  for x in xs
        \\    out = out.push(x * 2)
        \\  end
        \\  out
        \\end
        \\
        \\fn evens(xs: List(UInt32)) : List(UInt32)
        \\  var out = xs.take(0)
        \\  for x in xs
        \\    if x % 2 == 0
        \\      out = out.push(x)
        \\    end
        \\  end
        \\  out
        \\end
        \\
        \\fn total(xs: List(UInt32)) : UInt32
        \\  var sum = 0
        \\  for x in xs
        \\    sum += x
        \\  end
        \\  sum
        \\end
        \\
        \\fn number(digits: List(UInt32)) : UInt32
        \\  var n = 0
        \\  for d in digits
        \\    n = n * 10 + d
        \\  end
        \\  n
        \\end
        \\
        \\fn left(budget: UInt32, costs: List(UInt32)) : UInt32
        \\  var rest = budget
        \\  for c in costs
        \\    rest -= c + 1
        \\  end
        \\  rest
        \\end
        \\
        \\test "the loops"
        \\  assert doubled([1, 2]) == [2, 4]
        \\  assert evens([1, 2, 3, 4]) == [2, 4]
        \\  assert total([1, 2, 3]) == 6
        \\  assert number([1, 2, 3]) == 123
        \\  assert left(10, [1, 2]) == 5
        \\end
        \\
    );
    try contains(out, "  out = out.concat(xs.map(fn(x) x * 2 end))\n");
    try contains(out, "  out = out.concat(xs.filter(fn(x) x % 2 == 0 end))\n");
    try contains(out, "  sum = xs.reduce(sum, fn(so_far, x) so_far + x end)\n");
    try contains(out, "  n = digits.reduce(n, fn(so_far, d) so_far * 10 + d end)\n");
    try contains(out, "  rest = costs.reduce(rest, fn(so_far, c) so_far - (c + 1) end)\n");
    try std.testing.expect(std.mem.indexOf(u8, out, "for ") == null);
}

test "MO0501: a loop that reads another var, or holds a comment, is not one of the three" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src =
        \\module T.Honest
        \\expose scaled, counted
        \\
        \\fn scaled(xs: List(UInt32)) : List(UInt32)
        \\  var k = 2
        \\  k += 1
        \\  var out = xs.take(0)
        \\  for x in xs
        \\    out = out.push(x * k)
        \\  end
        \\  out
        \\end
        \\
        \\fn counted(xs: List(UInt32)) : UInt32
        \\  var n = 0
        \\  for x in xs
        \\    # each one counts
        \\    n += x
        \\  end
        \\  n
        \\end
        \\
    ;
    var diags: diag.List = .empty;
    try pipeline.runTo(arena, try program.single(arena, "t.mo", src), .check, &diags);
    try std.testing.expectEqualStrings(src, (try run(arena, try program.single(arena, "t.mo", src))).source);
}

test "edits that overlap are taken one per pass, in record order" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const file: diag.File = .{ .path = "t", .source = "abcdef", .base = 10 };
    // A replaces b; B inserts where A's edit ends, so it waits; C deletes e and f; D is
    // not sure; E points into another file.
    const records = [_]diag.Record{
        .{ .code = "A", .category = .laws, .at = 11, .what = "", .why = "", .fixes = &.{.{ .description = "b→B", .confidence = 100, .edits = &.{.{ .at = 11, .len = 1, .text = "B" }} }} },
        .{ .code = "B", .category = .laws, .at = 11, .what = "", .why = "", .fixes = &.{.{ .description = "insert", .confidence = 100, .edits = &.{.{ .at = 12, .len = 0, .text = "!" }} }} },
        .{ .code = "C", .category = .laws, .at = 14, .what = "", .why = "", .fixes = &.{.{ .description = "e,f→", .confidence = 100, .edits = &.{.{ .at = 14, .len = 2, .text = "" }} }} },
        .{ .code = "D", .category = .laws, .at = 10, .what = "", .why = "", .fixes = &.{.{ .description = "unsure", .confidence = 90, .edits = &.{.{ .at = 10, .len = 1, .text = "" }} }} },
        .{ .code = "E", .category = .laws, .at = 0, .what = "", .why = "", .fixes = &.{.{ .description = "another file", .confidence = 100, .edits = &.{.{ .at = 2, .len = 1, .text = "" }} }} },
    };
    const applied = try apply(arena, file, &records);
    try std.testing.expectEqualStrings("aBcd", applied.source);
    try std.testing.expectEqual(@as(usize, 2), applied.fixed.len);
}

test "mo fix leaves a one-line if value alone, and a dropped one-line if carries no fix" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const value =
        \\module T.Label
        \\expose label
        \\
        \\fn label(n: UInt32) : String
        \\  word = if n == 1: "line" else: "lines"
        \\  "#{n} #{word}"
        \\end
        \\
        \\test "one line"
        \\  assert label(1) == "1 line"
        \\end
        \\
    ;
    try std.testing.expectEqualStrings(value, try expectFixed(arena, value));
    // A body's last line (step 26).
    const tail = "module T.Sign\nexpose sign\n\nfn sign(n: Int32) : String\n  if n < 0: \"negative\" else: \"not negative\"\nend\n\ntest \"negative\"\n  assert sign(-1) == \"negative\"\nend\n";
    try std.testing.expectEqualStrings(tail, try expectFixed(arena, tail));
    const statement = "module T.Sign\nexpose sign\n\nfn sign(n: Int32) : String\n  if n < 0: \"negative\" else: \"not negative\"\n  \"#{n}\"\nend\n";
    var diags: diag.List = .empty;
    try std.testing.expectError(error.Rejected, pipeline.runTo(arena, try program.single(arena, "t.mo", statement), .check, &diags));
    try std.testing.expectEqualStrings("MO0310", diags.items[0].code);
    try std.testing.expectEqual(@as(usize, 0), diags.items[0].fixes.len);
    try std.testing.expectEqualStrings(statement, (try run(arena, try program.single(arena, "t.mo", statement))).source);
}
