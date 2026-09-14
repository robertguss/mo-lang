//! A program is a tree of files (grammar, Session 5). `mo check`, `mo test`, and
//! `mo run` take one file and load every module it uses by path: `A.B` is `a/b.mo`
//! under the program root, the nearest ancestor directory of the given file that holds
//! a `mo.root` file, else the file's own directory. Each module loads once, after the
//! modules it uses, and the given file last; a cycle is MO0318. The stages see the
//! files joined into one source, and diag.locate maps an offset in it back to its file.
const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const diag = @import("diag.zig");
const ids = @import("ids.zig");

/// The empty file that makes its directory a program root.
pub const root_marker = "mo.root";

pub const Program = struct {
    /// Every module after the modules it uses; the given file is last.
    files: []const diag.File,
    /// The files one after another, each ending in a newline before the next begins.
    source: []const u8,
    /// Where each file starts in `source`.
    bases: []const u32,
    /// The program root, spelled from the working directory; the sidecar lives there.
    root: []const u8 = ".",
    /// Per file: its path under the root, the sidecar's key for it.
    keys: []const []const u8 = &.{},
    /// Per file: what the sidecar says of its `verified:` line. Empty for a program
    /// that was not loaded from disk, so every line in it is hand-written.
    verified_lines: []check.VerifiedLine = &.{},
    /// Per file that loaded: the modules it uses, directly or through another, with the hash
    /// of each one's declarations but its tests, for the sidecar (ids.zig).
    uses: []const []const ids.Use = &.{},
    /// The main file's lines as it is on disk, when its source here holds more than the file:
    /// `mo check --recipe` appends the recipe's tests and nevers, which are not the file, so
    /// the 500-line law (MO0302) counts these (step 22).
    own_lines: ?u32 = null,

    /// The file the program was loaded from.
    pub fn main(p: Program) diag.File {
        return p.files[p.files.len - 1];
    }
};

/// The runtime surface's module (step 23), which `mo run --surface` and `mo build --surface` put
/// before a program's first module and start before main (surface.zig).
pub const surface_source = @embedFile("surface.mo");
pub const surface_path = "(the runtime surface) surface.mo";

/// The program with the runtime surface's module first; the given file stays last.
pub fn withSurface(gpa: std.mem.Allocator, p: Program) error{OutOfMemory}!Program {
    const files = try gpa.alloc(diag.File, p.files.len + 1);
    files[0] = .{ .path = surface_path, .source = surface_source };
    @memcpy(files[1..], p.files);
    var q = try join(gpa, files);
    q.root = p.root;
    q.own_lines = p.own_lines;
    if (p.keys.len > 0) {
        const keys = try gpa.alloc([]const u8, p.keys.len + 1);
        keys[0] = "";
        @memcpy(keys[1..], p.keys);
        q.keys = keys;
    }
    if (p.verified_lines.len > 0) {
        const lines = try gpa.alloc(check.VerifiedLine, p.verified_lines.len + 1);
        lines[0] = .recorded;
        @memcpy(lines[1..], p.verified_lines);
        q.verified_lines = lines;
    }
    if (p.uses.len > 0) {
        const uses = try gpa.alloc([]const ids.Use, p.uses.len + 1);
        uses[0] = &.{};
        @memcpy(uses[1..], p.uses);
        q.uses = uses;
    }
    return q;
}

/// One source on its own, as a program of one module, for a caller with no files.
pub fn single(gpa: std.mem.Allocator, path: []const u8, source: []const u8) error{OutOfMemory}!Program {
    const files = try gpa.alloc(diag.File, 1);
    files[0] = .{ .path = path, .source = source };
    return join(gpa, files);
}

/// The program with its main file's text replaced, for `mo fix` between passes.
pub fn withMain(gpa: std.mem.Allocator, p: Program, source: []const u8) error{OutOfMemory}!Program {
    const files = try gpa.dupe(diag.File, p.files);
    files[files.len - 1].source = source;
    var q = try join(gpa, files);
    q.root = p.root;
    q.keys = p.keys;
    q.verified_lines = p.verified_lines;
    q.uses = p.uses;
    q.own_lines = p.own_lines;
    return q;
}

/// Reads `path` and every module it uses. What stops loading (a file that does not lex
/// or parse, a use cycle, a used file that declares another module) goes to `diags` at
/// its offset in the program's source, and the program holds the files read so far. A
/// used module with no file is the checker's to report (MO0323). Nothing is freed: pass
/// an arena.
pub fn load(gpa: std.mem.Allocator, io: Io, path: []const u8, diags: *diag.List) !Program {
    const source = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 20));
    const root = try findRoot(gpa, io, std.fs.path.dirname(path) orelse ".");
    var l: Loader = .{ .gpa = gpa, .io = io, .root = root.rel, .abs_root = root.abs };
    _ = try l.visit(path, source);
    var program = try join(gpa, l.files.items);
    for (l.found.items) |f| {
        var d = f.record;
        d.at += program.bases[f.file];
        try diags.append(gpa, d);
    }
    program.root = root.rel;
    program.keys = l.keys.items;
    const uses = try gpa.alloc([]const ids.Use, l.stamps.items.len);
    for (l.stamps.items, uses) |s, *u| u.* = s.uses;
    program.uses = uses;
    // A file that stopped the loading has no stamp, and nothing past it is checked.
    const sidecar = try ids.read(gpa, io, root.rel);
    program.verified_lines = try gpa.alloc(check.VerifiedLine, program.files.len);
    for (program.verified_lines, 0..) |*v, i| {
        v.* = if (i < l.stamps.items.len) try ids.status(gpa, sidecar, l.keys.items[i], l.stamps.items[i]) else .recorded;
    }
    return program;
}

fn join(gpa: std.mem.Allocator, files: []diag.File) error{OutOfMemory}!Program {
    var source: std.ArrayList(u8) = .empty;
    const bases = try gpa.alloc(u32, files.len);
    for (files, bases, 0..) |*f, *base, i| {
        base.* = @intCast(source.items.len);
        f.base = base.*;
        try source.appendSlice(gpa, f.source);
        const ends_line = f.source.len > 0 and f.source[f.source.len - 1] == '\n';
        if (i + 1 < files.len and !ends_line) try source.append(gpa, '\n');
    }
    return .{ .files = files, .source = try source.toOwnedSlice(gpa), .bases = bases };
}

const Root = struct { rel: []const u8, abs: []const u8 };

/// The nearest directory from `dir` upward that holds a mo.root file, spelled from
/// `dir` (`dir/..`), else `dir` itself; and the same directory as an absolute path.
fn findRoot(gpa: std.mem.Allocator, io: Io, dir: []const u8) !Root {
    const start: []const u8 = try Io.Dir.cwd().realPathFileAlloc(io, dir, gpa);
    var abs = start;
    var rel: []const u8 = dir;
    while (true) {
        const marker = try std.fs.path.join(gpa, &.{ abs, root_marker });
        if (Io.Dir.cwd().access(io, marker, .{})) |_| return .{ .rel = rel, .abs = abs } else |_| {}
        abs = std.fs.path.dirname(abs) orelse return .{ .rel = dir, .abs = start };
        rel = if (std.mem.eql(u8, rel, ".")) ".." else try std.fs.path.join(gpa, &.{ rel, ".." });
    }
}

fn pathText(tree: ast.Tree, path_node: ast.Index) []const u8 {
    const n = tree.nodes[path_node];
    return tree.source[tree.tokens[n.main_token].start..tree.tokens[n.lhs].end];
}

const Found = struct { file: usize, record: diag.Record };

const Loader = struct {
    gpa: std.mem.Allocator,
    io: Io,
    root: []const u8,
    abs_root: []const u8,
    files: std.ArrayList(diag.File) = .empty,
    /// Per file, the sidecar's key; per file that parsed, its stamp.
    keys: std.ArrayList([]const u8) = .empty,
    stamps: std.ArrayList(ids.Stamp) = .empty,
    /// Per file that loaded, the module it declares.
    modules: std.ArrayList([]const u8) = .empty,
    /// Module path → loaded (true), or still loading the modules it uses (false).
    state: std.StringHashMapUnmanaged(bool) = .empty,
    /// The modules still loading, outermost first, to name a cycle.
    stack: std.ArrayList([]const u8) = .empty,
    /// Records at offsets into their own file, until the files are joined.
    found: std.ArrayList(Found) = .empty,

    /// Loads the modules a file uses, then the file. The module path it declares, or
    /// null when loading stopped.
    fn visit(l: *Loader, path: []const u8, source: []const u8) !?[]const u8 {
        var local: diag.List = .empty;
        const tokens = lexer.lex(l.gpa, source, &local) catch |err| return l.stop(err, path, source, local.items);
        const tree = parser.parse(l.gpa, source, tokens, &local) catch |err| return l.stop(err, path, source, local.items);
        const root = tree.nodes[0];
        const items = tree.span(root.lhs, root.rhs);
        const module_path = pathText(tree, tree.nodes[items[0]].lhs);
        try l.state.put(l.gpa, module_path, false);
        try l.stack.append(l.gpa, module_path);
        var here: std.ArrayList(diag.Record) = .empty;
        // The modules this file's tests can reach: those it uses, and theirs.
        var reach: std.ArrayList([]const u8) = .empty;
        for (items) |it| {
            const n = tree.nodes[it];
            if (n.kind != .use) continue;
            const used = pathText(tree, n.lhs);
            const at = tree.tokens[n.main_token].start;
            // A module that uses itself is the checker's MO0318.
            if (std.mem.eql(u8, used, module_path)) continue;
            if (l.state.get(used)) |loaded| {
                if (!loaded) try here.append(l.gpa, try l.cycle(used, at));
                if (loaded) try l.reaches(&reach, used);
                continue;
            }
            const file = try l.fileOf(used);
            const dep = Io.Dir.cwd().readFileAlloc(l.io, file, l.gpa, .limited(1 << 20)) catch |err| switch (err) {
                // MO0323 is the checker's, which knows the refund module's stand-ins.
                error.FileNotFound => continue,
                else => |e| return e,
            };
            const declared = try l.visit(file, dep) orelse return null;
            if (!std.mem.eql(u8, declared, used)) {
                try l.state.put(l.gpa, used, true);
                const e = check.catalog.get(.no_module);
                const what = try std.fmt.allocPrint(l.gpa, "{s} holds module {s}, not {s}; a module's file is its path under the program root.", .{ file, declared, used });
                try here.append(l.gpa, .{ .code = e.code, .category = e.category, .at = at, .what = what, .why = e.why });
            } else try l.reaches(&reach, used);
        }
        _ = l.stack.pop();
        var s = try ids.stamp(l.gpa, tree);
        std.mem.sort([]const u8, reach.items, {}, struct {
            fn lt(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lt);
        const uses = try l.gpa.alloc(ids.Use, reach.items.len);
        for (reach.items, uses) |m, *u| {
            const k = for (l.modules.items, 0..) |loaded, i| {
                if (std.mem.eql(u8, loaded, m)) break i;
            } else unreachable;
            u.* = .{ .module = m, .hash = try ids.bodiesHash(l.gpa, l.stamps.items[k].declarations) };
        }
        s.uses = uses;
        try l.stamps.append(l.gpa, s);
        try l.modules.append(l.gpa, module_path);
        try l.add(path, source, here.items);
        try l.state.put(l.gpa, module_path, true);
        return module_path;
    }

    /// Adds `used` and every module it reaches to `reach`, once each.
    fn reaches(l: *Loader, reach: *std.ArrayList([]const u8), used: []const u8) !void {
        const k = for (l.modules.items, 0..) |m, i| {
            if (std.mem.eql(u8, m, used)) break i;
        } else return;
        try addOnce(l.gpa, reach, used);
        for (l.stamps.items[k].uses) |u| try addOnce(l.gpa, reach, u.module);
    }

    fn addOnce(gpa: std.mem.Allocator, list: *std.ArrayList([]const u8), name: []const u8) !void {
        for (list.items) |n| if (std.mem.eql(u8, n, name)) return;
        try list.append(gpa, name);
    }

    /// A file that does not lex or parse ends the loading with its records.
    fn stop(l: *Loader, err: anyerror, path: []const u8, source: []const u8, records: []const diag.Record) !?[]const u8 {
        if (err != error.Rejected) return err;
        try l.add(path, source, records);
        return null;
    }

    fn add(l: *Loader, path: []const u8, source: []const u8, records: []const diag.Record) !void {
        for (records) |r| try l.found.append(l.gpa, .{ .file = l.files.items.len, .record = r });
        try l.files.append(l.gpa, .{ .path = path, .source = source });
        // The sidecar's key: the file's path under the root, with / between segments.
        const abs = try Io.Dir.cwd().realPathFileAlloc(l.io, path, l.gpa);
        const under = std.mem.startsWith(u8, abs, l.abs_root) and abs.len > l.abs_root.len and abs[l.abs_root.len] == std.fs.path.sep;
        const key = if (under) try l.gpa.dupe(u8, abs[l.abs_root.len + 1 ..]) else std.fs.path.basename(abs);
        if (std.fs.path.sep != '/') std.mem.replaceScalar(u8, @constCast(key), std.fs.path.sep, '/');
        try l.keys.append(l.gpa, key);
    }

    /// A use of a module still loading: the modules from it to this one form a cycle.
    fn cycle(l: *Loader, used: []const u8, at: u32) !diag.Record {
        var from: usize = 0;
        for (l.stack.items, 0..) |m, i| {
            if (std.mem.eql(u8, m, used)) from = i;
        }
        var text: std.ArrayList(u8) = .empty;
        for (l.stack.items[from..]) |m| {
            try text.appendSlice(l.gpa, m);
            try text.appendSlice(l.gpa, " uses ");
        }
        try text.appendSlice(l.gpa, used);
        const e = check.catalog.get(.use_cycle);
        const what = try std.fmt.allocPrint(l.gpa, "{s}; modules have no import cycles.", .{text.items});
        return .{ .code = e.code, .category = e.category, .at = at, .what = what, .why = e.why };
    }

    fn fileOf(l: *Loader, module_path: []const u8) ![]const u8 {
        const rel = try check.moduleFile(l.gpa, module_path);
        if (std.mem.eql(u8, l.root, ".")) return rel;
        return std.fs.path.join(l.gpa, &.{ l.root, rel });
    }
};

test "a program loads each module once, after the modules it uses; a cycle is MO0318" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "app/a");
    try tmp.dir.writeFile(io, .{ .sub_path = "app/mo.root", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "app/a/lib.mo", .data = "module A.Lib\nexpose one\nfn one() : UInt8\n  1\nend\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "app/a/mid.mo", .data = "module A.Mid\nexpose two\nuse A.Lib{one}\nfn two() : UInt8\n  one() + 1\nend\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "app/a/main.mo", .data = "module A.Main\nuse A.Lib{one}\nuse A.Mid{two}\nfn three() : UInt8\n  one() + two()\nend\n" });
    const main_path = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/app/a/main.mo", .{tmp.sub_path});

    var diags: diag.List = .empty;
    const p = try load(arena, io, main_path, &diags);
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);
    try std.testing.expectEqual(@as(usize, 3), p.files.len);
    try std.testing.expect(std.mem.endsWith(u8, p.files[0].path, "a/lib.mo"));
    try std.testing.expect(std.mem.endsWith(u8, p.files[1].path, "a/mid.mo"));
    try std.testing.expectEqualStrings(main_path, p.main().path);

    try tmp.dir.writeFile(io, .{ .sub_path = "app/a/lib.mo", .data = "module A.Lib\nexpose one\nuse A.Mid{two}\nfn one() : UInt8\n  two()\nend\n" });
    const cyclic = try load(arena, io, main_path, &diags);
    try std.testing.expectEqualStrings("MO0318", diags.items[0].code);
    try std.testing.expectEqualStrings("A.Lib uses A.Mid uses A.Lib; modules have no import cycles.", diags.items[0].what);
    try std.testing.expect(std.mem.endsWith(u8, diag.locate(cyclic.files, diags.items[0].at).path, "a/mid.mo"));
}
