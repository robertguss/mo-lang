//! Line diffs for `mo fmt --check`: the unified format, three lines of context. A
//! line keeps its newline, so a file that lacks the final one shows as changed.
const std = @import("std");

const context = 3;

const Op = enum { same, del, ins };

const Edit = struct { op: Op, a: u32, b: u32 };

fn lines(gpa: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    for (text, 0..) |c, i| if (c == '\n') {
        try out.append(gpa, text[start .. i + 1]);
        start = i + 1;
    };
    if (start < text.len) try out.append(gpa, text[start..]);
    return out.toOwnedSlice(gpa);
}

/// The edit script from `a` to `b`: the longest common subsequence of lines, after
/// the common prefix and suffix are set aside. Nothing is freed: pass an arena.
fn script(gpa: std.mem.Allocator, a: []const []const u8, b: []const []const u8) ![]Edit {
    var out: std.ArrayList(Edit) = .empty;
    var pre: usize = 0;
    while (pre < a.len and pre < b.len and std.mem.eql(u8, a[pre], b[pre])) pre += 1;
    var suf: usize = 0;
    while (suf < a.len - pre and suf < b.len - pre and std.mem.eql(u8, a[a.len - 1 - suf], b[b.len - 1 - suf])) suf += 1;
    for (0..pre) |i| try out.append(gpa, .{ .op = .same, .a = @intCast(i), .b = @intCast(i) });
    const n = a.len - pre - suf;
    const m = b.len - pre - suf;
    // lcs[i][j]: the common subsequence length of a[pre+i..] and b[pre+j..].
    const w = m + 1;
    const lcs = try gpa.alloc(u32, (n + 1) * w);
    @memset(lcs, 0);
    var i = n;
    while (i > 0) {
        i -= 1;
        var j = m;
        while (j > 0) {
            j -= 1;
            lcs[i * w + j] = if (std.mem.eql(u8, a[pre + i], b[pre + j]))
                lcs[(i + 1) * w + j + 1] + 1
            else
                @max(lcs[(i + 1) * w + j], lcs[i * w + j + 1]);
        }
    }
    i = 0;
    var j: usize = 0;
    while (i < n or j < m) {
        if (i < n and j < m and std.mem.eql(u8, a[pre + i], b[pre + j])) {
            try out.append(gpa, .{ .op = .same, .a = @intCast(pre + i), .b = @intCast(pre + j) });
            i += 1;
            j += 1;
        } else if (i < n and (j == m or lcs[(i + 1) * w + j] >= lcs[i * w + j + 1])) {
            // Deletions first, so a changed line reads - then +.
            try out.append(gpa, .{ .op = .del, .a = @intCast(pre + i), .b = @intCast(pre + j) });
            i += 1;
        } else {
            try out.append(gpa, .{ .op = .ins, .a = @intCast(pre + i), .b = @intCast(pre + j) });
            j += 1;
        }
    }
    for (0..suf) |k| try out.append(gpa, .{ .op = .same, .a = @intCast(a.len - suf + k), .b = @intCast(b.len - suf + k) });
    return out.toOwnedSlice(gpa);
}

/// Writes nothing when `a` and `b` are equal. Nothing is freed: pass an arena.
pub fn unified(gpa: std.mem.Allocator, w: *std.Io.Writer, path: []const u8, a_text: []const u8, b_text: []const u8) !void {
    if (std.mem.eql(u8, a_text, b_text)) return;
    const a = try lines(gpa, a_text);
    const b = try lines(gpa, b_text);
    const edits = try script(gpa, a, b);
    try w.print("--- {s}\n+++ {s} (formatted)\n", .{ path, path });
    var k: usize = 0;
    while (k < edits.len) {
        while (k < edits.len and edits[k].op == .same) k += 1;
        if (k == edits.len) break;
        // A hunk runs from `context` lines before the first change to `context`
        // lines after the last change that is no more than 2 * context away.
        const first = k -| context;
        var last = k;
        var run: usize = 0;
        var e = k;
        while (e < edits.len) : (e += 1) {
            if (edits[e].op == .same) {
                run += 1;
                if (run > 2 * context) break;
            } else {
                run = 0;
                last = e;
            }
        }
        const end = @min(edits.len, last + 1 + context);
        var a_len: usize = 0;
        var b_len: usize = 0;
        for (edits[first..end]) |ed| {
            if (ed.op != .ins) a_len += 1;
            if (ed.op != .del) b_len += 1;
        }
        const a_start = if (a_len == 0) edits[first].a else edits[first].a + 1;
        const b_start = if (b_len == 0) edits[first].b else edits[first].b + 1;
        try w.print("@@ -{d},{d} +{d},{d} @@\n", .{ a_start, a_len, b_start, b_len });
        for (edits[first..end]) |ed| {
            const text = if (ed.op == .ins) b[ed.b] else a[ed.a];
            try w.writeByte(switch (ed.op) {
                .same => ' ',
                .del => '-',
                .ins => '+',
            });
            if (std.mem.endsWith(u8, text, "\n")) {
                try w.writeAll(text);
            } else {
                try w.print("{s}\n\\ No newline at end of file\n", .{text});
            }
        }
        k = end;
    }
}

fn expectDiff(a: []const u8, b: []const u8, want: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var aw: std.Io.Writer.Allocating = .init(arena_state.allocator());
    try unified(arena_state.allocator(), &aw.writer, "a.mo", a, b);
    try std.testing.expectEqualStrings(want, aw.written());
}

test "equal texts give no diff" {
    try expectDiff("x\n", "x\n", "");
}

test "a change in the middle keeps three lines of context" {
    try expectDiff("1\n2\n3\n4\nx = 1\n6\n7\n8\n9\n", "1\n2\n3\n4\nx=1\n6\n7\n8\n9\n",
        \\--- a.mo
        \\+++ a.mo (formatted)
        \\@@ -2,7 +2,7 @@
        \\ 2
        \\ 3
        \\ 4
        \\-x = 1
        \\+x=1
        \\ 6
        \\ 7
        \\ 8
        \\
    );
}

test "two distant changes are two hunks; an added line and a missing newline" {
    try expectDiff("a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nend", "a\n\nb\nc\nd\ne\nf\ng\nh\ni\nj\nend\n",
        \\--- a.mo
        \\+++ a.mo (formatted)
        \\@@ -1,4 +1,5 @@
        \\ a
        \\+
        \\ b
        \\ c
        \\ d
        \\@@ -8,4 +9,4 @@
        \\ h
        \\ i
        \\ j
        \\-end
        \\\ No newline at end of file
        \\+end
        \\
    );
}
