//! The `.mo.ids` sidecar (design-v0/05, 07): toolchain-owned JSON beside the program
//! root, one record per file under that root. A record names the file's module, gives
//! each top-level declaration a stable id and its content hash, and holds the hash of
//! the `verified:` line `mo test --write` last wrote, with the hash of the declarations
//! it was computed over. Source stays plain text.
//!
//! A declaration is every top-level item but the `verified:` line: the module header's
//! lines, types, functions, processes, and tests. Its hash is SHA-256, cut to 64 bits,
//! over its tokens' text with newlines kept, so a comment or a blank line changes
//! nothing. Its name is its first line up to the first `(`, `{`, `=`, or `:` (`fn split`,
//! `test "a bill splits evenly"`), and its id is kept while its name is: a new name is a
//! new declaration. `MO0317` fires when the file's `verified:` line has no record, when
//! it differs from the record, or when the declarations changed since.
const std = @import("std");
const Io = std.Io;
const token = @import("token.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const check = @import("check.zig");

pub const file_name = ".mo.ids";
pub const version: u32 = 1;

/// A content hash: 16 lowercase hex digits.
pub const Hash = [16]u8;

pub const Declaration = struct { name: []const u8, hash: Hash };

/// What one file holds, as the sidecar sees it.
pub const Stamp = struct {
    module: []const u8,
    declarations: []const Declaration,
    /// The `verified:` line and its `proven:` line, as written, or null.
    verified: ?[]const u8 = null,
    /// Where that line starts in the file; the file's length when it has none.
    verified_at: u32,
};

pub const Record = struct { id: []const u8, name: []const u8, hash: []const u8 };
pub const VerifiedRecord = struct { hash: []const u8, declarations: []const u8 };
pub const FileRecord = struct {
    path: []const u8,
    module: []const u8,
    declarations: []const Record,
    verified: ?VerifiedRecord = null,
};
pub const Sidecar = struct { version: u32 = version, files: []const FileRecord = &.{} };

pub fn hash(bytes: []const u8) Hash {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest[0..8].*, .lower);
}

/// The stamp of a file that parsed.
pub fn stamp(gpa: std.mem.Allocator, tree: ast.Tree) error{OutOfMemory}!Stamp {
    const root = tree.nodes[0];
    const items = tree.span(root.lhs, root.rhs);
    var eof: u32 = 0;
    while (tree.tokens[eof].kind != .eof) eof += 1;
    var s: Stamp = .{ .module = "", .declarations = &.{}, .verified_at = @intCast(tree.source.len) };
    var decls: std.ArrayList(Declaration) = .empty;
    var text: std.ArrayList(u8) = .empty;
    for (items, 0..) |it, k| {
        const n = tree.nodes[it];
        const first = lineStart(tree, n.main_token);
        if (n.kind == .verified) {
            s.verified_at = tree.tokens[first].start;
            const end = std.mem.trimEnd(u8, tree.source[s.verified_at..], " \t\r\n");
            s.verified = try std.fmt.allocPrint(gpa, "{s}\n", .{end});
            continue;
        }
        if (n.kind == .module_decl) {
            const path = tree.nodes[n.lhs];
            s.module = tree.source[tree.tokens[path.main_token].start..tree.tokens[path.lhs].end];
        }
        var end = if (k + 1 < items.len) lineStart(tree, tree.nodes[items[k + 1]].main_token) else eof;
        while (end > first and tree.tokens[end - 1].kind == .newline) end -= 1;
        text.clearRetainingCapacity();
        for (first..end) |t| {
            if (tree.tokens[t].kind == .newline) {
                try text.append(gpa, '\n');
            } else {
                if (text.items.len > 0 and text.items[text.items.len - 1] != '\n') try text.append(gpa, ' ');
                try text.appendSlice(gpa, tree.tokenText(@intCast(t)));
            }
        }
        try decls.append(gpa, .{ .name = try uniqueName(gpa, decls.items, nameOf(tree, first)), .hash = hash(text.items) });
    }
    s.declarations = decls.items;
    return s;
}

/// The first token on the line that holds `tok`.
fn lineStart(tree: ast.Tree, tok: u32) u32 {
    var t = tok;
    while (t > 0 and tree.tokens[t - 1].kind != .newline) t -= 1;
    return t;
}

fn nameOf(tree: ast.Tree, first: u32) []const u8 {
    const kind = tree.tokens[first].kind;
    if (kind == .kw_expose or kind == .kw_intent) return tree.tokenText(first);
    var last = first;
    var t = first + 1;
    while (true) : (t += 1) switch (tree.tokens[t].kind) {
        .l_paren, .l_brace, .eq, .colon, .newline, .eof => break,
        else => last = t,
    };
    return tree.source[tree.tokens[first].start..tree.tokens[last].end];
}

/// A name a file already used gets ` #2`, ` #3`, and so on.
fn uniqueName(gpa: std.mem.Allocator, taken: []const Declaration, name: []const u8) error{OutOfMemory}![]const u8 {
    var candidate = name;
    var n: u32 = 1;
    while (for (taken) |d| {
        if (std.mem.eql(u8, d.name, candidate)) break true;
    } else false) {
        n += 1;
        candidate = try std.fmt.allocPrint(gpa, "{s} #{d}", .{ name, n });
    }
    return candidate;
}

/// The hash every declaration hash of a file folds into, in order.
pub fn declarationsHash(gpa: std.mem.Allocator, decls: []const Declaration) error{OutOfMemory}!Hash {
    var all: std.ArrayList(u8) = .empty;
    defer all.deinit(gpa);
    for (decls) |d| {
        try all.appendSlice(gpa, d.name);
        try all.append(gpa, 0);
        try all.appendSlice(gpa, &d.hash);
        try all.append(gpa, '\n');
    }
    return hash(all.items);
}

pub fn find(sidecar: Sidecar, path: []const u8) ?FileRecord {
    for (sidecar.files) |f| if (std.mem.eql(u8, f.path, path)) return f;
    return null;
}

/// Whether a file's `verified:` line is the one the toolchain recorded for it.
pub fn status(gpa: std.mem.Allocator, sidecar: Sidecar, path: []const u8, s: Stamp) error{OutOfMemory}!check.VerifiedLine {
    const line = s.verified orelse return .recorded;
    const file = find(sidecar, path) orelse return .hand_written;
    const v = file.verified orelse return .hand_written;
    if (!std.mem.eql(u8, v.hash, &hash(line))) return .line_changed;
    if (std.mem.eql(u8, v.declarations, &try declarationsHash(gpa, s.declarations))) return .recorded;
    return .{ .declarations_changed = try changedNames(gpa, file.declarations, s.declarations) };
}

/// `fn a, fn b, and 3 more`: what was added, removed, or changed since the record.
fn changedNames(gpa: std.mem.Allocator, recorded: []const Record, now: []const Declaration) error{OutOfMemory}![]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (now) |d| {
        const same = for (recorded) |r| {
            if (std.mem.eql(u8, r.name, d.name)) break std.mem.eql(u8, r.hash, &d.hash);
        } else false;
        if (!same) try names.append(gpa, d.name);
    }
    for (recorded) |r| {
        const kept = for (now) |d| {
            if (std.mem.eql(u8, r.name, d.name)) break true;
        } else false;
        if (!kept) try names.append(gpa, r.name);
    }
    // Only the order moved.
    if (names.items.len == 0) return "the order of the declarations";
    var out: std.ArrayList(u8) = .empty;
    const shown = @min(names.items.len, 3);
    for (names.items[0..shown], 0..) |name, i| {
        if (i > 0) try out.appendSlice(gpa, if (i + 1 == shown and names.items.len == shown) " and " else ", ");
        try out.appendSlice(gpa, name);
    }
    if (names.items.len > shown) try out.print(gpa, ", and {d} more", .{names.items.len - shown});
    return out.items;
}

/// The sidecar at `root`, or an empty one when there is none or it does not parse: then
/// every `verified:` line under the root is unrecorded, and MO0317 says so.
pub fn read(gpa: std.mem.Allocator, io: Io, root: []const u8) !Sidecar {
    const path = try std.fs.path.join(gpa, &.{ root, file_name });
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 << 20)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => |e| return e,
    };
    return std.json.parseFromSliceLeaky(Sidecar, gpa, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch .{};
}

/// The sidecar with `path`'s record replaced: ids kept by name, new ones derived from
/// the module and the name, and the `verified:` line recorded over these declarations.
pub fn record(gpa: std.mem.Allocator, sidecar: Sidecar, path: []const u8, s: Stamp, line: []const u8) error{OutOfMemory}!Sidecar {
    const old = find(sidecar, path);
    const records = try gpa.alloc(Record, s.declarations.len);
    for (s.declarations, records, 0..) |d, *r, i| {
        const kept: ?[]const u8 = if (old) |o| for (o.declarations) |od| {
            if (std.mem.eql(u8, od.name, d.name)) break od.id;
        } else null else null;
        r.* = .{ .id = kept orelse try newId(gpa, s.module, d.name, records[0..i]), .name = d.name, .hash = try gpa.dupe(u8, &d.hash) };
    }
    const file: FileRecord = .{
        .path = path,
        .module = s.module,
        .declarations = records,
        .verified = .{ .hash = try gpa.dupe(u8, &hash(line)), .declarations = try gpa.dupe(u8, &try declarationsHash(gpa, s.declarations)) },
    };
    var files: std.ArrayList(FileRecord) = .empty;
    var placed = false;
    for (sidecar.files) |f| {
        if (!placed and std.mem.order(u8, path, f.path) != .gt) {
            try files.append(gpa, file);
            placed = true;
        }
        if (!std.mem.eql(u8, f.path, path)) try files.append(gpa, f);
    }
    if (!placed) try files.append(gpa, file);
    return .{ .files = files.items };
}

/// 12 hex digits of the module and name, stable across runs; a clash takes the next.
fn newId(gpa: std.mem.Allocator, module: []const u8, name: []const u8, taken: []const Record) error{OutOfMemory}![]const u8 {
    var salt: u32 = 0;
    while (true) : (salt += 1) {
        const text = try std.fmt.allocPrint(gpa, "{s}\x00{s}\x00{d}", .{ module, name, salt });
        const id = try gpa.dupe(u8, hash(text)[0..12]);
        const clash = for (taken) |r| {
            if (std.mem.eql(u8, r.id, id)) break true;
        } else false;
        if (!clash) return id;
    }
}

/// The sidecar as JSON, two-space indented, one declaration per line, files in path
/// order, so a change to one declaration is a one-line diff.
pub fn render(w: *Io.Writer, sidecar: Sidecar) Io.Writer.Error!void {
    try w.print("{{\n  \"version\": {d},\n  \"files\": [", .{sidecar.version});
    for (sidecar.files, 0..) |f, i| {
        try w.writeAll(if (i == 0) "\n" else ",\n");
        try w.writeAll("    {\n      \"path\": ");
        try string(w, f.path);
        try w.writeAll(",\n      \"module\": ");
        try string(w, f.module);
        try w.writeAll(",\n      \"declarations\": [");
        for (f.declarations, 0..) |d, k| {
            try w.writeAll(if (k == 0) "\n" else ",\n");
            try w.writeAll("        { \"id\": ");
            try string(w, d.id);
            try w.writeAll(", \"name\": ");
            try string(w, d.name);
            try w.writeAll(", \"hash\": ");
            try string(w, d.hash);
            try w.writeAll(" }");
        }
        try w.writeAll(if (f.declarations.len > 0) "\n      ],\n" else "],\n");
        if (f.verified) |v| {
            try w.writeAll("      \"verified\": { \"hash\": ");
            try string(w, v.hash);
            try w.writeAll(", \"declarations\": ");
            try string(w, v.declarations);
            try w.writeAll(" }\n    }");
        } else try w.writeAll("      \"verified\": null\n    }");
    }
    try w.writeAll(if (sidecar.files.len > 0) "\n  ]\n}\n" else "]\n}\n");
}

fn string(w: *Io.Writer, s: []const u8) Io.Writer.Error!void {
    try std.json.Stringify.encodeJsonString(s, .{}, w);
}

/// The file with its `verified:` line replaced by `line`, one blank line above it
/// (FORMAT.md B5).
pub fn withLine(gpa: std.mem.Allocator, source: []const u8, s: Stamp, line: []const u8) error{OutOfMemory}![]const u8 {
    const body = std.mem.trimEnd(u8, source[0..s.verified_at], " \t\r\n");
    return std.fmt.allocPrint(gpa, "{s}\n\n{s}", .{ body, line });
}

/// `mo test --write`: writes `line` into the program's main file and records it in the
/// sidecar at the program root.
pub fn write(gpa: std.mem.Allocator, io: Io, root: []const u8, path: []const u8, key: []const u8, source: []const u8, line: []const u8) !void {
    var scratch: diag.List = .empty;
    const tokens = try lexer.lex(gpa, source, &scratch);
    const tree = try parser.parse(gpa, source, tokens, &scratch);
    const s = try stamp(gpa, tree);
    const updated = try record(gpa, try read(gpa, io, root), key, s, line);
    var json: Io.Writer.Allocating = .init(gpa);
    try render(&json.writer, updated);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(gpa, &.{ root, file_name }), .data = json.written() });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = try withLine(gpa, source, s, line) });
}

fn stampOf(arena: std.mem.Allocator, source: []const u8) !Stamp {
    var scratch: diag.List = .empty;
    const tokens = try lexer.lex(arena, source, &scratch);
    return stamp(arena, try parser.parse(arena, source, tokens, &scratch));
}

const line_a = "verified: types, contracts, tests (1), property (0 seeds), sim (not run)\n          proven: not run\n";

test "a stamp names each declaration and hashes its tokens, not its spacing or comments" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const a = try stampOf(arena, "module T.A\nexpose f\n\nfn f(n: UInt8) : UInt8\n  n\nend\n\ntest \"f\"\n  assert f(1) == 1\nend\n");
    const b = try stampOf(arena, "module T.A\nexpose f\n\n# a comment\nfn f(n: UInt8) : UInt8\n\n  n\nend\n\ntest \"f\"\n  assert f(1) == 1\nend\n\n" ++ line_a);
    try std.testing.expectEqualStrings("T.A", a.module);
    try std.testing.expectEqual(@as(usize, 4), a.declarations.len);
    const names = [_][]const u8{ "module T.A", "expose", "fn f", "test \"f\"" };
    for (names, a.declarations, b.declarations) |name, da, db| {
        try std.testing.expectEqualStrings(name, da.name);
        try std.testing.expectEqualStrings(&da.hash, &db.hash);
    }
    try std.testing.expect(a.verified == null);
    try std.testing.expectEqualStrings(line_a, b.verified.?);
    const c = try stampOf(arena, "module T.A\nexpose f\n\nfn f(n: UInt8) : UInt8\n  n + 0\nend\n\ntest \"f\"\n  assert f(1) == 1\nend\n");
    try std.testing.expect(!std.mem.eql(u8, &a.declarations[2].hash, &c.declarations[2].hash));
}

test "a recorded line holds until the line or a declaration changes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src = "module T.A\n\nfn f(n: UInt8) : UInt8\n  n\nend\n\ntest \"f\"\n  assert f(1) == 1\nend\n";
    const before = try stampOf(arena, src);
    try std.testing.expect(try status(arena, .{}, "a.mo", before) == .recorded);

    const written = try withLine(arena, src, before, line_a);
    try std.testing.expectEqualStrings(src ++ "\n" ++ line_a, written);
    const sidecar = try record(arena, .{}, "a.mo", before, line_a);
    const after = try stampOf(arena, written);
    try std.testing.expect(try status(arena, sidecar, "a.mo", after) == .recorded);
    try std.testing.expect(try status(arena, .{}, "a.mo", after) == .hand_written);
    try std.testing.expect(try status(arena, sidecar, "b.mo", after) == .hand_written);
    // Writing again replaces the line rather than adding one.
    try std.testing.expectEqualStrings(written, try withLine(arena, written, after, line_a));

    const edited_line = try stampOf(arena, try std.mem.replaceOwned(u8, arena, written, "tests (1)", "tests (9)"));
    try std.testing.expect(try status(arena, sidecar, "a.mo", edited_line) == .line_changed);
    const edited_body = try stampOf(arena, try std.mem.replaceOwned(u8, arena, written, "  n\n", "  n + 1\n"));
    const changed = try status(arena, sidecar, "a.mo", edited_body);
    try std.testing.expectEqualStrings("fn f", changed.declarations_changed);

    // The sidecar round-trips through its JSON, and an id survives an edit to its body.
    var json: Io.Writer.Allocating = .init(arena);
    try render(&json.writer, sidecar);
    const parsed = try std.json.parseFromSliceLeaky(Sidecar, arena, json.written(), .{});
    try std.testing.expect(try status(arena, parsed, "a.mo", after) == .recorded);
    const again = try record(arena, parsed, "a.mo", edited_body, line_a);
    try std.testing.expectEqualStrings(parsed.files[0].declarations[1].id, again.files[0].declarations[1].id);
    try std.testing.expect(!std.mem.eql(u8, parsed.files[0].declarations[1].hash, again.files[0].declarations[1].hash));
    try std.testing.expect(try status(arena, again, "a.mo", edited_body) == .recorded);
}
