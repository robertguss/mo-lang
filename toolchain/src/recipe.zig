//! `mo check --recipe Module.Recipe file.mo` (design-v0/06, recipes; step 19): an implementation
//! against the recipe it implements. Every signature the recipe declares must be a function the
//! file exposes with the same parameters (names, types, and inout), the same result, the same
//! requires, and at least the recipe's ensures. Then the recipe's nevers and tests run against
//! the file, as if written at its end; a test or never the file already has under one of the
//! recipe's names must be the recipe's, line for line, and runs once. Any difference is MO0326.
//! The recipe's module is found by its path under the file's program root, else under the
//! nearest directory above the root that holds it, so a program can implement a shared recipe.
const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");
const check = @import("check.zig");
const diag = @import("diag.zig");
const pipeline = @import("pipeline.zig");
const program = @import("program.zig");
const runner = @import("runner.zig");

pub const Conformance = struct {
    /// The files the records in `diags` point into.
    files: []const diag.File,
    /// The recipe's signatures the file matched.
    signatures: u32 = 0,
    /// The recipe's tests run against the file; null when a record says why they did not run.
    run: ?runner.Run = null,
};

/// A test or never block: its name as the source spells it, and its text.
const Block = struct { name: []const u8, at: u32, text: []const u8 };

pub fn conform(gpa: std.mem.Allocator, io: Io, path: []const u8, name: []const u8, diags: *diag.List) !Conformance {
    const impl = try program.load(gpa, io, path, diags);
    const k = pipeline.buildable(gpa, impl, true, diags) catch |err| switch (err) {
        error.Rejected => return .{ .files = impl.files },
        else => return err,
    };
    const here: u32 = @intCast(k.modules.len - 1);
    const module_at = moduleAt(&k, here);
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse {
        try mismatch(gpa, diags, module_at, try std.fmt.allocPrint(gpa, "{s} names no recipe; --recipe names a module and a recipe in it, such as Recipes.Store.Store.", .{name}));
        return .{ .files = impl.files };
    };
    const recipe_name = name[dot + 1 ..];
    const file = try findModule(gpa, io, impl.root, name[0..dot]) orelse {
        try mismatch(gpa, diags, module_at, try std.fmt.allocPrint(gpa, "no file holds module {s}: {s} is not under the program root or a directory above it.", .{ name[0..dot], try check.moduleFile(gpa, name[0..dot]) }));
        return .{ .files = impl.files };
    };
    const rp = try program.load(gpa, io, file, diags);
    const rk = pipeline.buildable(gpa, rp, true, diags) catch |err| switch (err) {
        error.Rejected => return .{ .files = rp.files },
        else => return err,
    };
    const decl = findRecipe(&rk, recipe_name) orelse {
        try mismatch(gpa, diags, module_at, try std.fmt.allocPrint(gpa, "{s} has no recipe {s}; --recipe names a module and a recipe in it, such as Recipes.Store.Store.", .{ name[0..dot], recipe_name }));
        return .{ .files = impl.files };
    };
    const data = rk.tree.extraData(ast.Recipe, rk.tree.nodes[decl].lhs);

    var out: Conformance = .{ .files = impl.files };
    for (rk.tree.span(data.sigs_start, data.sigs_end)) |s| {
        if (try sameShape(gpa, &k, here, &rk, s, recipe_name, diags)) out.signatures += 1;
    }
    const own = try blocksOf(gpa, &k, here);
    // A module's nevers are in its header and its tests at its end (grammar §2).
    var header: std.ArrayList(u8) = .empty;
    var appended: std.ArrayList(u8) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    for ([_][]const u32{ rk.tree.span(data.nevers_start, data.nevers_end), rk.tree.span(data.tests_start, data.tests_end) }, 0..) |nodes, pass| {
        for (nodes) |n| {
            const b = blockAt(&rk.tree, n);
            if (pass == 1) try names.append(gpa, unquoted(b.name));
            const same = for (own) |o| {
                if (std.mem.eql(u8, o.name, b.name)) break o;
            } else null;
            if (same) |o| {
                if (!try sameLines(gpa, o.text, b.text)) try mismatch(gpa, diags, o.at, try std.fmt.allocPrint(gpa, "{s} {s} here is not recipe {s}'s; delete it, since the recipe's runs against this module.", .{ if (pass == 0) "the never" else "the test", b.name, recipe_name }));
                continue;
            }
            const into = if (pass == 0) &header else &appended;
            try into.appendSlice(gpa, try dedented(gpa, b.text));
            try into.append(gpa, '\n');
        }
    }
    if (diags.items.len > 0) return out;

    // The file with the recipe's blocks at its end, and without its verified: line, which
    // describes the file and not this run.
    const main = impl.main();
    const body = main.source[0..verifiedAt(main.source)];
    const split = headerEnd(&k, here) - main.base;
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(gpa, body[0..split]);
    try source.appendSlice(gpa, header.items);
    try source.appendSlice(gpa, body[split..]);
    if (source.items.len > 0 and source.items[source.items.len - 1] != '\n') try source.append(gpa, '\n');
    if (appended.items.len > 0) try source.append(gpa, '\n');
    try source.appendSlice(gpa, appended.items);
    var synth = try program.withMain(gpa, impl, source.items);
    const files = try gpa.dupe(diag.File, synth.files);
    files[files.len - 1].path = try std.fmt.allocPrint(gpa, "{s} with recipe {s}", .{ main.path, name });
    synth.files = files;
    out.files = files;
    if (synth.verified_lines.len == files.len) synth.verified_lines[files.len - 1] = .recorded;
    const checked = pipeline.buildable(gpa, synth, true, diags) catch |err| switch (err) {
        error.Rejected => return out,
        else => return err,
    };
    const lowered = try gpa.create(bytecode.Program);
    lowered.* = try bytecode.lower(gpa, checked);
    var mine: std.ArrayList(bytecode.Test) = .empty;
    for (lowered.tests) |t| {
        if (t.at < synth.main().base) continue;
        for (names.items) |n| if (std.mem.eql(u8, n, t.name)) {
            try mine.append(gpa, t);
            break;
        };
    }
    lowered.tests = mine.items;
    out.run = try runner.run(gpa, lowered, .{ .sim_seed = runner.seedOf(source.items) });
    return out;
}

fn mismatch(gpa: std.mem.Allocator, diags: *diag.List, at: u32, what: []const u8) !void {
    const e = check.catalog.get(.recipe_mismatch);
    try diags.append(gpa, .{ .code = e.code, .category = e.category, .at = at, .what = what, .why = e.why });
}

/// `module_path`'s file under `root`, else under each directory above it; null when none holds it.
fn findModule(gpa: std.mem.Allocator, io: Io, root: []const u8, module_path: []const u8) !?[]const u8 {
    const rel = try check.moduleFile(gpa, module_path);
    var dir: []const u8 = try Io.Dir.cwd().realPathFileAlloc(io, root, gpa);
    while (true) {
        const candidate = try std.fs.path.join(gpa, &.{ dir, rel });
        if (Io.Dir.cwd().access(io, candidate, .{})) |_| return candidate else |_| {}
        dir = std.fs.path.dirname(dir) orelse return null;
    }
}

fn tokenText(tree: *const ast.Tree, tok: u32) []const u8 {
    return tree.source[tree.tokens[tok].start..tree.tokens[tok].end];
}

fn rootItems(k: *const check.Checked, module: u32) []const u32 {
    const root = k.tree.nodes[0];
    const m = k.modules[module];
    return k.tree.span(root.lhs, root.rhs)[m.items.start..m.items.end];
}

/// Where a finding about the module as a whole points: its module line.
fn moduleAt(k: *const check.Checked, module: u32) u32 {
    return k.tree.tokens[k.tree.nodes[rootItems(k, module)[0]].main_token].start;
}

fn findRecipe(k: *const check.Checked, name: []const u8) ?u32 {
    for (rootItems(k, @intCast(k.modules.len - 1))) |it| {
        const n = k.tree.nodes[it];
        if (n.kind == .recipe_decl and std.mem.eql(u8, tokenText(&k.tree, n.main_token), name)) return it;
    }
    return null;
}

fn exposes(k: *const check.Checked, module: u32, name: []const u8) bool {
    const e = k.modules[module].expose;
    if (e == 0) return false;
    const n = k.tree.nodes[e];
    for (k.tree.span(n.lhs, n.rhs)) |tok| if (std.mem.eql(u8, tokenText(&k.tree, tok), name)) return true;
    return false;
}

fn sigAt(k: *const check.Checked, node: u32) ?check.FnSig {
    for (k.sigs) |s| if (s.node == node) return s;
    return null;
}

/// Each parameter as `name: Type`, `inout` before the name when it is one.
fn paramsText(gpa: std.mem.Allocator, k: *const check.Checked, s: check.FnSig) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (k.params[s.params.start..s.params.end], 0..) |p, i| {
        if (i > 0) try out.appendSlice(gpa, ", ");
        try out.print(gpa, "{s}{s}: {s}", .{ if (p.inout) "inout " else "", p.name, try k.pool.name(gpa, p.type) });
    }
    return out.items;
}

/// The sig's requires or ensures lines, as the source spells them.
fn contracts(gpa: std.mem.Allocator, tree: *const ast.Tree, node: u32, kind: ast.Node.Kind) ![]const []const u8 {
    const sig = tree.extraData(ast.Signature, tree.nodes[node].lhs);
    var out: std.ArrayList([]const u8) = .empty;
    for (tree.span(sig.contracts_start, sig.contracts_end)) |c| {
        if (tree.nodes[c].kind != kind) continue;
        // The line without its keyword.
        const line = lineAt(tree.source, tree.tokens[tree.nodes[c].main_token].start);
        try out.append(gpa, std.mem.trimStart(u8, line[std.mem.indexOfScalar(u8, line, ' ') orelse line.len ..], " "));
    }
    return out.items;
}

fn lineAt(source: []const u8, at: u32) []const u8 {
    const start = if (std.mem.lastIndexOfScalar(u8, source[0..at], '\n')) |i| i + 1 else 0;
    const end = std.mem.indexOfScalarPos(u8, source, at, '\n') orelse source.len;
    return std.mem.trim(u8, source[start..end], " \t\r");
}

fn contains(lines: []const []const u8, line: []const u8) bool {
    for (lines) |l| if (std.mem.eql(u8, l, line)) return true;
    return false;
}

fn joined(gpa: std.mem.Allocator, lines: []const []const u8) ![]const u8 {
    return if (lines.len == 0) "none" else std.mem.join(gpa, "; ", lines);
}

/// Recipe signature `node` against the file's function of its name; true when they match, and
/// a record for each way they do not.
fn sameShape(gpa: std.mem.Allocator, k: *const check.Checked, here: u32, rk: *const check.Checked, node: u32, recipe_name: []const u8, diags: *diag.List) !bool {
    const want = sigAt(rk, node) orelse return false;
    const module = k.modules[here].path;
    const got = for (k.sigs) |s| {
        if (s.kind == .module and s.module == here and std.mem.eql(u8, s.name, want.name)) break s;
    } else null;
    if (got == null or !exposes(k, here, want.name)) {
        try mismatch(gpa, diags, moduleAt(k, here), try std.fmt.allocPrint(gpa, "{s} does not expose {s}, which recipe {s} declares; write it with the recipe's signature and put it on the expose line.", .{ module, want.name, recipe_name }));
        return false;
    }
    const s = got.?;
    const at = k.tree.tokens[k.tree.nodes[s.node].main_token].start;
    const before = diags.items.len;
    const got_params = try paramsText(gpa, k, s);
    const want_params = try paramsText(gpa, rk, want);
    if (!std.mem.eql(u8, got_params, want_params)) try mismatch(gpa, diags, at, try std.fmt.allocPrint(gpa, "{s} takes ({s}) here and ({s}) in recipe {s}; take what the recipe takes.", .{ want.name, got_params, want_params, recipe_name }));
    const got_ret = try k.pool.name(gpa, s.ret);
    const want_ret = try rk.pool.name(gpa, want.ret);
    if (!std.mem.eql(u8, got_ret, want_ret)) try mismatch(gpa, diags, at, try std.fmt.allocPrint(gpa, "{s} gives {s} here and {s} in recipe {s}; give what the recipe gives.", .{ want.name, got_ret, want_ret, recipe_name }));
    const got_requires = try contracts(gpa, &k.tree, s.node, .requires);
    const want_requires = try contracts(gpa, &rk.tree, node, .requires);
    const same_requires = got_requires.len == want_requires.len and for (want_requires) |r| {
        if (!contains(got_requires, r)) break false;
    } else true;
    if (!same_requires) try mismatch(gpa, diags, at, try std.fmt.allocPrint(gpa, "{s} requires {s} here and {s} in recipe {s}; an implementation requires what its recipe requires, no more and no less.", .{ want.name, try joined(gpa, got_requires), try joined(gpa, want_requires), recipe_name }));
    const got_ensures = try contracts(gpa, &k.tree, s.node, .ensures);
    for (try contracts(gpa, &rk.tree, node, .ensures)) |e| {
        if (!contains(got_ensures, e)) try mismatch(gpa, diags, at, try std.fmt.allocPrint(gpa, "{s} does not ensure {s}, which recipe {s} does; add it, since an implementation ensures at least what its recipe ensures.", .{ want.name, e, recipe_name }));
    }
    return diags.items.len == before;
}

/// Where the module's header ends, in the program's source: the start of the line of its first
/// declaration or test, above any comment lines that open it; else where its file ends.
fn headerEnd(k: *const check.Checked, here: u32) u32 {
    const source = k.tree.source;
    for (rootItems(k, here)) |it| switch (k.tree.nodes[it].kind) {
        .fn_decl, .struct_decl, .enum_decl, .type_decl, .trait_decl, .impl_decl, .process_decl, .supervisor_decl, .recipe_decl, .test_decl, .test_rejects, .property, .verified => {
            const at = k.tree.tokens[k.tree.nodes[it].main_token].start;
            var start = if (std.mem.lastIndexOfScalar(u8, source[0..at], '\n')) |i| i + 1 else 0;
            while (start > 0) {
                const above = if (std.mem.lastIndexOfScalar(u8, source[0 .. start - 1], '\n')) |i| i + 1 else 0;
                if (!std.mem.startsWith(u8, source[above..start], "#")) break;
                start = above;
            }
            return @intCast(start);
        },
        else => {},
    };
    return k.modules[here].base + @as(u32, @intCast(if (here + 1 < k.modules.len) k.modules[here + 1].base - k.modules[here].base else source.len - k.modules[here].base));
}

/// The file's own tests and nevers, by name.
fn blocksOf(gpa: std.mem.Allocator, k: *const check.Checked, here: u32) ![]const Block {
    var out: std.ArrayList(Block) = .empty;
    for (rootItems(k, here)) |it| switch (k.tree.nodes[it].kind) {
        .test_decl, .test_rejects, .property, .never => try out.append(gpa, blockAt(&k.tree, it)),
        else => {},
    };
    return out.items;
}

/// A test's or a never's name, and its lines from its first to the `end` that closes it.
fn blockAt(tree: *const ast.Tree, node: u32) Block {
    const n = tree.nodes[node];
    const name_tok = if (n.kind == .never) n.lhs else n.main_token;
    const at = tree.tokens[name_tok].start;
    const source = tree.source;
    const start = if (std.mem.lastIndexOfScalar(u8, source[0..at], '\n')) |i| i + 1 else 0;
    const indent = source[start .. start + (std.mem.indexOfNone(u8, source[start..], " ") orelse 0)];
    var pos = std.mem.indexOfScalarPos(u8, source, start, '\n') orelse source.len;
    while (pos < source.len) {
        const line_start = pos + 1;
        const line_end = std.mem.indexOfScalarPos(u8, source, line_start, '\n') orelse source.len;
        const line = source[line_start..line_end];
        pos = line_end;
        if (std.mem.startsWith(u8, line, indent) and std.mem.eql(u8, line[indent.len..], "end")) break;
    }
    return .{ .name = tokenText(tree, name_tok), .at = at, .text = source[start..@min(pos + 1, source.len)] };
}

fn unquoted(name: []const u8) []const u8 {
    return if (name.len >= 2 and name[0] == '"') name[1 .. name.len - 1] else name;
}

/// The same lines, each without the indentation it has.
fn sameLines(gpa: std.mem.Allocator, a: []const u8, b: []const u8) !bool {
    _ = gpa;
    var x = std.mem.splitScalar(u8, std.mem.trimEnd(u8, a, "\n"), '\n');
    var y = std.mem.splitScalar(u8, std.mem.trimEnd(u8, b, "\n"), '\n');
    while (true) {
        const l = x.next();
        const r = y.next();
        if (l == null or r == null) return l == null and r == null;
        if (!std.mem.eql(u8, std.mem.trim(u8, l.?, " \t\r"), std.mem.trim(u8, r.?, " \t\r"))) return false;
    }
}

/// The block's lines without the indentation of its first.
fn dedented(gpa: std.mem.Allocator, text: []const u8) ![]const u8 {
    const indent = std.mem.indexOfNone(u8, text, " ") orelse 0;
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, text, "\n"), '\n');
    while (lines.next()) |line| {
        const cut = @min(indent, std.mem.indexOfNone(u8, line, " ") orelse line.len);
        try out.appendSlice(gpa, line[cut..]);
        try out.append(gpa, '\n');
    }
    return out.items;
}

/// Where the file's `verified:` line starts, or its end.
fn verifiedAt(source: []const u8) usize {
    if (std.mem.startsWith(u8, source, "verified:")) return 0;
    return if (std.mem.lastIndexOf(u8, source, "\nverified:")) |i| i + 1 else source.len;
}

/// The recipe a file's `# recipe: Module.Recipe` line names among its first comment lines,
/// which the corpus test checks it against.
pub fn named(source: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "#")) return null;
        if (std.mem.startsWith(u8, line, "# recipe: ")) return std.mem.trim(u8, line["# recipe: ".len..], " \r");
    }
    return null;
}

test "a file names its recipe on a first comment line" {
    try std.testing.expectEqualStrings("Recipes.Store.Store", named("# recipe: Recipes.Store.Store\nmodule A\n").?);
    try std.testing.expect(named("module A\n# recipe: X.Y\n") == null);
}

test "an implementation must expose the recipe's signatures with the same shape, and runs the recipe's tests" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "app/recipes");
    try tmp.dir.writeFile(io, .{ .sub_path = "app/mo.root", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "app/recipes/halve.mo", .data =
        \\module Recipes.Halve
        \\expose Halve
        \\recipe Halve
        \\  intent "Halve an even number"
        \\  needs nothing
        \\  fn half(n: UInt32) : UInt32
        \\    requires n % 2 == 0
        \\    ensures result * 2 == n
        \\  end
        \\  never "a half is odd"
        \\    for n in UInt32.all
        \\      n == 7
        \\    end
        \\  end
        \\  test "four halves to two"
        \\    assert half(4) == 2
        \\  end
        \\  test rejects "an odd number"
        \\    half(3)
        \\  end
        \\end
        \\
    });
    try tmp.dir.writeFile(io, .{ .sub_path = "app/good.mo", .data =
        \\module Good
        \\expose half
        \\fn half(n: UInt32) : UInt32
        \\  requires n % 2 == 0
        \\  ensures result * 2 == n
        \\  ensures result <= n
        \\
        \\  n / 2
        \\end
        \\
        \\test rejects "an odd number"
        \\  half(3)
        \\end
        \\
    });
    try tmp.dir.writeFile(io, .{ .sub_path = "app/bad.mo", .data =
        \\module Bad
        \\expose half
        \\fn half(n: UInt64) : UInt64
        \\  ensures result * 2 == n
        \\
        \\  n / 2
        \\end
        \\
        \\test "four halves to two"
        \\  assert half(4) == 2
        \\  assert half(6) == 3
        \\end
        \\
    });
    const base = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/app", .{tmp.sub_path});
    var diags: diag.List = .empty;
    const good = try conform(arena, io, try std.fmt.allocPrint(arena, "{s}/good.mo", .{base}), "Recipes.Halve.Halve", &diags);
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);
    try std.testing.expectEqual(@as(u32, 1), good.signatures);
    try std.testing.expectEqual(@as(usize, 2), good.run.?.results.len);
    try std.testing.expectEqual(@as(u32, 0), good.run.?.summary.failures);

    const bad = try conform(arena, io, try std.fmt.allocPrint(arena, "{s}/bad.mo", .{base}), "Recipes.Halve.Halve", &diags);
    try std.testing.expect(bad.run == null);
    const want = [_][]const u8{
        "half takes (n: UInt64) here and (n: UInt32) in recipe Halve; take what the recipe takes.",
        "half gives UInt64 here and UInt32 in recipe Halve; give what the recipe gives.",
        "half requires none here and n % 2 == 0 in recipe Halve; an implementation requires what its recipe requires, no more and no less.",
        "the test \"four halves to two\" here is not recipe Halve's; delete it, since the recipe's runs against this module.",
    };
    try std.testing.expectEqual(want.len, diags.items.len);
    for (want, diags.items) |w, d| {
        try std.testing.expectEqualStrings("MO0326", d.code);
        try std.testing.expectEqualStrings(w, d.what);
    }
    diags.clearRetainingCapacity();
    _ = try conform(arena, io, try std.fmt.allocPrint(arena, "{s}/good.mo", .{base}), "Recipes.Halve.Double", &diags);
    try std.testing.expectEqualStrings("Recipes.Halve has no recipe Double; --recipe names a module and a recipe in it, such as Recipes.Store.Store.", diags.items[0].what);
}
