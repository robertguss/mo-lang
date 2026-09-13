//! Diagnostics teach (design-v0/05): every finding is a structured record with a
//! stable code, a category, a location, `what`, `why` (written once per code in the
//! error catalog), and zero or more machine-applicable fixes with a confidence.
//! Rendered as prose for humans and JSON for agents. There are no warnings.
const std = @import("std");

/// `format`: the formatter's findings (toolchain/FORMAT.md), MO05xx.
pub const Category = enum { syntax, types, laws, capabilities, contracts, tests, verified, format };

pub const Fix = struct {
    description: []const u8,
    confidence: u8, // 0–100
};

pub const Record = struct {
    code: []const u8, // "MO0412"
    category: Category,
    /// Byte offset into the source; line and column are derived at render time.
    at: u32,
    what: []const u8,
    why: []const u8,
    fixes: []const Fix = &.{},
};

pub const List = std.ArrayList(Record);

/// One file of a program, and where it starts in the program's joined source.
pub const File = struct { path: []const u8, source: []const u8, base: u32 = 0 };

pub const Located = struct { path: []const u8, source: []const u8, at: u32 };

/// The file an offset into a program's joined source falls in, and the offset in it.
pub fn locate(files: []const File, at: u32) Located {
    var f = files[0];
    for (files[1..]) |next| {
        if (next.base > at) break;
        f = next;
    }
    return .{ .path = f.path, .source = f.source, .at = at - f.base };
}

pub const Position = struct { line: usize, column: usize, line_start: usize, line_end: usize };

/// The 1-based line and column of a byte offset, and the bounds of its line.
pub fn position(source: []const u8, offset: u32) Position {
    const at = @min(offset, source.len);
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..at], '\n')) |i| i + 1 else 0;
    const line_end = std.mem.indexOfScalarPos(u8, source, at, '\n') orelse source.len;
    return .{
        .line = 1 + std.mem.count(u8, source[0..line_start], "\n"),
        .column = at - line_start + 1,
        .line_start = line_start,
        .line_end = line_end,
    };
}

/// One record as prose: `path:line:col: code what`, the source line with a caret
/// under the offset, then why.
pub fn renderProse(w: *std.Io.Writer, path: []const u8, source: []const u8, d: Record) std.Io.Writer.Error!void {
    const pos = position(source, d.at);
    const at = @min(d.at, source.len);
    try w.print("{s}:{d}:{d}: {s} {s}\n", .{ path, pos.line, pos.column, d.code, d.what });
    try w.print("  {s}\n  ", .{source[pos.line_start..pos.line_end]});
    for (source[pos.line_start..at]) |c| try w.writeByte(if (c == '\t') '\t' else ' ');
    try w.print("^\n  why: {s}\n", .{d.why});
}

/// One record as one line of JSON, for agents.
pub fn renderJson(w: *std.Io.Writer, path: []const u8, source: []const u8, d: Record) std.Io.Writer.Error!void {
    const pos = position(source, d.at);
    try w.writeAll("{\"code\":");
    try jsonString(w, d.code);
    try w.print(",\"category\":\"{t}\",\"path\":", .{d.category});
    try jsonString(w, path);
    try w.print(",\"line\":{d},\"column\":{d},\"at\":{d},\"what\":", .{ pos.line, pos.column, d.at });
    try jsonString(w, d.what);
    try w.writeAll(",\"why\":");
    try jsonString(w, d.why);
    try w.writeAll(",\"fixes\":[");
    for (d.fixes, 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll("{\"description\":");
        try jsonString(w, f.description);
        try w.print(",\"confidence\":{d}}}", .{f.confidence});
    }
    try w.writeAll("]}\n");
}

fn jsonString(w: *std.Io.Writer, s: []const u8) std.Io.Writer.Error!void {
    try w.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        0...8, 11, 12, 14...0x1f => try w.print("\\u{x:0>4}", .{c}),
        else => try w.writeByte(c),
    };
    try w.writeByte('"');
}

test "prose names the line, the column, and why" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try renderProse(&w, "a.mo", "module M\nfn f(\n", .{ .code = "MO0101", .category = .syntax, .at = 14, .what = "expected a name", .why = "because." });
    try std.testing.expectEqualStrings("a.mo:2:6: MO0101 expected a name\n  fn f(\n       ^\n  why: because.\n", w.buffered());
}

test "json is one line per record, with its text escaped" {
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try renderJson(&w, "a.mo", "module M\nfn f(\n", .{ .code = "MO0101", .category = .syntax, .at = 14, .what = "expected \"x\"", .why = "a\tb", .fixes = &.{.{ .description = "add x", .confidence = 90 }} });
    try std.testing.expectEqualStrings("{\"code\":\"MO0101\",\"category\":\"syntax\",\"path\":\"a.mo\",\"line\":2,\"column\":6,\"at\":14,\"what\":\"expected \\\"x\\\"\",\"why\":\"a\\tb\",\"fixes\":[{\"description\":\"add x\",\"confidence\":90}]}\n", w.buffered());
}
