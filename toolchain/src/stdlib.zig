//! The standard library's rows (design-v0/09-stdlib.md) that vm.zig does not run itself:
//! prelude.zig lists each one, `names` maps it to a `Row`, and `call` runs it on the
//! vm's values. Every row is deterministic: nothing here reads a clock, a random source,
//! or an address. A row whose input comes from outside the program gives an Option or a
//! Result; a row the caller misused crashes with a report, as a tripped contract does.
//!
//! Strings are UTF-8 and counted in graphemes, approximated as a code point with the
//! combining marks after it (`Graphemes`), the same count `size` gives. A result that is
//! part of its receiver is a slice of it: values are immutable, so nothing can tell.
const std = @import("std");
const contracts = @import("contracts.zig");
const prelude = @import("prelude.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;

pub const Row = enum {
    none,
    string_from_bytes,
    string_chars,
    string_split,
    string_lines,
    string_trim,
    string_ends_with,
    string_contains,
    string_index_of,
    string_slice,
    string_replace,
    string_to_upper,
    string_to_lower,
    string_pad_left,
    string_pad_right,
    string_repeat,
    string_join,
    string_to_u64,
    string_to_i64,
    string_to_f64,
    int_to,
    int_checked_to,
    int_to_f64,
    float_round,
    float_to_string,
};

pub const names = std.StaticStringMap(Row).initComptime(.{
    .{ "String.from_bytes", .string_from_bytes }, .{ "String.chars", .string_chars },         .{ "String.split", .string_split },
    .{ "String.lines", .string_lines },           .{ "String.trim", .string_trim },           .{ "String.ends_with?", .string_ends_with },
    .{ "String.contains?", .string_contains },    .{ "String.index_of", .string_index_of },   .{ "String.slice", .string_slice },
    .{ "String.replace", .string_replace },       .{ "String.to_upper", .string_to_upper },   .{ "String.to_lower", .string_to_lower },
    .{ "String.pad_left", .string_pad_left },     .{ "String.pad_right", .string_pad_right }, .{ "String.repeat", .string_repeat },
    .{ "String.join", .string_join },             .{ "String.to_u64", .string_to_u64 },       .{ "String.to_i64", .string_to_i64 },
    .{ "String.to_f64", .string_to_f64 },         .{ "Int.to_u8", .int_to },                  .{ "Int.to_u16", .int_to },
    .{ "Int.to_u32", .int_to },                   .{ "Int.to_u64", .int_to },                 .{ "Int.to_i64", .int_to },
    .{ "Int.checked_to_u8", .int_checked_to },    .{ "Int.checked_to_u16", .int_checked_to }, .{ "Int.checked_to_u32", .int_checked_to },
    .{ "Int.checked_to_u64", .int_checked_to },   .{ "Int.checked_to_i64", .int_checked_to }, .{ "Int.to_f64", .int_to_f64 },
    .{ "Float64.round", .float_round },           .{ "Float64.to_string", .float_to_string },
});

/// The row each prelude function is, or `none` for the rows vm.zig runs.
pub const row_of = blk: {
    @setEvalBranchQuota(20_000);
    var table: [prelude.fns.len]Row = undefined;
    for (prelude.fns, 0..) |f, i| {
        const head = f.recv[0 .. std.mem.indexOfScalar(u8, f.recv, '(') orelse f.recv.len];
        table[i] = names.get(head ++ "." ++ f.name) orelse .none;
    }
    break :blk table;
};

/// Runs `row` on its arguments, the receiver first.
pub fn call(vm: *Vm, row: prelude.Fn, which: Row, a: []const Value) Error!Value {
    return switch (which) {
        .none => unreachable,
        .string_from_bytes => fromBytes(vm, a[0].list),
        .string_chars => .{ .list = try chars(vm, a[0].string) },
        .string_split => split(vm, a[0].string, a[1].string),
        .string_lines => lines(vm, a[0].string),
        .string_trim => .{ .string = trim(a[0].string) },
        .string_ends_with => .{ .bool = std.mem.endsWith(u8, a[0].string, a[1].string) },
        .string_contains => .{ .bool = std.mem.indexOf(u8, a[0].string, a[1].string) != null },
        .string_index_of => if (std.mem.indexOf(u8, a[0].string, a[1].string)) |at|
            vm.variant("Some", &.{.{ .int = count(a[0].string[0..at]) }})
        else
            vm.variant("None", &.{}),
        .string_slice => .{ .string = slice(a[0].string, a[1].int, a[2].int) },
        .string_replace => replace(vm, a[0].string, a[1].string, a[2].string),
        .string_to_upper, .string_to_lower => blk: {
            const out = try vm.heap.alloc(u8, a[0].string.len);
            if (which == .string_to_upper) _ = std.ascii.upperString(out, a[0].string) else _ = std.ascii.lowerString(out, a[0].string);
            break :blk .{ .string = out };
        },
        .string_pad_left, .string_pad_right => pad(vm, row, a[0].string, a[1].int, a[2].string, which == .string_pad_left),
        .string_repeat => repeat(vm, row, a[0].string, a[1].int),
        .string_join => join(vm, row, a[0].list, a[1].string),
        .string_to_u64 => option(vm, parseWhole(a[0].string, false, .u64)),
        .string_to_i64 => option(vm, parseWhole(a[0].string, true, .i64)),
        .string_to_f64 => if (parseFloat(a[0].string)) |x| vm.variant("Some", &.{.{ .float = x }}) else vm.variant("None", &.{}),
        .int_to => blk: {
            const kind = targetKind(row.name);
            if (a[0].int < vm_mod.minOf(kind) or a[0].int > vm_mod.maxOf(kind)) {
                return fail(vm, .overflow, row, "{d}.{s} does not fit {s}", .{ a[0].int, row.name, row.ret });
            }
            break :blk a[0];
        },
        .int_checked_to => blk: {
            const kind = targetKind(row.name);
            const fits = a[0].int >= vm_mod.minOf(kind) and a[0].int <= vm_mod.maxOf(kind);
            break :blk if (fits) vm.variant("Some", &.{a[0]}) else vm.variant("None", &.{});
        },
        .int_to_f64 => .{ .float = @floatFromInt(a[0].int) },
        .float_round, .float_to_string => blk: {
            const x = a[0].float;
            const places = a[1].int;
            if (places > max_places) return fail(vm, .other, row, "{s}({d}) rounds to at most {d} places", .{ row.name, places, max_places });
            if (std.math.isNan(x) or std.math.isInf(x)) {
                if (which == .float_round) break :blk a[0];
                break :blk .{ .string = if (std.math.isNan(x)) "NaN" else if (x > 0) "Infinity" else "-Infinity" };
            }
            var buf: [decimal_buffer]u8 = undefined;
            const text = rounded(&buf, x, @intCast(places));
            if (which == .float_round) break :blk .{ .float = std.fmt.parseFloat(f64, text) catch unreachable };
            break :blk .{ .string = try vm.heap.dupe(u8, text) };
        },
    };
}

fn fail(vm: *Vm, kind: contracts.Kind, row: prelude.Fn, comptime format: []const u8, args: anytype) Error {
    vm.report = .{ .kind = kind, .clause = try std.fmt.allocPrint(vm.gpa, format, args), .within = row.name, .at = 0 };
    return error.Crash;
}

fn option(vm: *Vm, v: ?i128) Error!Value {
    return if (v) |x| vm.variant("Some", &.{.{ .int = x }}) else vm.variant("None", &.{});
}

// ---- graphemes

/// A string's graphemes, in order: each is one code point and the combining marks after
/// it. A byte that does not start valid UTF-8 is a grapheme of its own.
pub const Graphemes = struct {
    s: []const u8,
    i: usize = 0,

    pub fn next(g: *Graphemes) ?[]const u8 {
        if (g.i >= g.s.len) return null;
        const start = g.i;
        g.i += codePoint(g.s, g.i).len;
        while (g.i < g.s.len) {
            const cp = codePoint(g.s, g.i);
            if (!combining(cp.value)) break;
            g.i += cp.len;
        }
        return g.s[start..g.i];
    }
};

const CodePoint = struct { value: u21, len: usize };

/// The code point at byte `i`; an invalid byte reads as U+FFFD, one byte long.
fn codePoint(s: []const u8, i: usize) CodePoint {
    const bad: CodePoint = .{ .value = 0xFFFD, .len = 1 };
    const len = std.unicode.utf8ByteSequenceLength(s[i]) catch return bad;
    if (i + len > s.len) return bad;
    const value = std.unicode.utf8Decode(s[i .. i + len]) catch return bad;
    return .{ .value = value, .len = len };
}

fn combining(cp: u21) bool {
    return (cp >= 0x300 and cp <= 0x36F) or (cp >= 0x1AB0 and cp <= 0x1AFF) or (cp >= 0x1DC0 and cp <= 0x1DFF) or (cp >= 0x20D0 and cp <= 0x20FF) or (cp >= 0xFE20 and cp <= 0xFE2F);
}

/// Graphemes in `s`: what `size` gives.
pub fn count(s: []const u8) i128 {
    var g: Graphemes = .{ .s = s };
    var n: i128 = 0;
    while (g.next() != null) n += 1;
    return n;
}

/// The byte offset where grapheme `index` starts, or `s.len` past the last.
fn byteOffset(s: []const u8, index: i128) usize {
    var g: Graphemes = .{ .s = s };
    var n: i128 = 0;
    while (n < index) : (n += 1) {
        if (g.next() == null) break;
    }
    return g.i;
}

fn whitespace(cp: u21) bool {
    return switch (cp) {
        0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 => true,
        else => false,
    };
}

// ---- strings

fn fromBytes(vm: *Vm, bytes: []const Value) Error!Value {
    const out = try vm.heap.alloc(u8, bytes.len);
    for (bytes, out) |b, *o| o.* = @intCast(b.int);
    if (!std.unicode.utf8ValidateSlice(out)) return vm.variant("None", &.{});
    return vm.variant("Some", &.{.{ .string = out }});
}

fn chars(vm: *Vm, s: []const u8) Error![]const Value {
    const out = try vm.heap.alloc(Value, @intCast(count(s)));
    var g: Graphemes = .{ .s = s };
    for (out) |*o| o.* = .{ .string = g.next().? };
    return out;
}

fn split(vm: *Vm, s: []const u8, sep: []const u8) Error!Value {
    if (sep.len == 0) return .{ .list = try chars(vm, s) };
    const out = try vm.heap.alloc(Value, std.mem.count(u8, s, sep) + 1);
    var it = std.mem.splitSequence(u8, s, sep);
    for (out) |*o| o.* = .{ .string = it.next().? };
    return .{ .list = out };
}

fn lines(vm: *Vm, s: []const u8) Error!Value {
    if (s.len == 0) return .{ .list = &.{} };
    const body = if (s[s.len - 1] == '\n') s[0 .. s.len - 1] else s;
    const out = try vm.heap.alloc(Value, std.mem.count(u8, body, "\n") + 1);
    var it = std.mem.splitScalar(u8, body, '\n');
    for (out) |*o| {
        const line = it.next().?;
        o.* = .{ .string = if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line };
    }
    return .{ .list = out };
}

fn trim(s: []const u8) []const u8 {
    var start: ?usize = null;
    var end: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const cp = codePoint(s, i);
        if (!whitespace(cp.value)) {
            if (start == null) start = i;
            end = i + cp.len;
        }
        i += cp.len;
    }
    return if (start) |from| s[from..end] else s[0..0];
}

fn slice(s: []const u8, from: i128, to: i128) []const u8 {
    const end = byteOffset(s, to);
    const start = byteOffset(s, @min(from, to));
    return s[@min(start, end)..end];
}

fn replace(vm: *Vm, s: []const u8, a: []const u8, b: []const u8) Error!Value {
    if (a.len == 0) return .{ .string = s };
    const n = std.mem.count(u8, s, a);
    if (n == 0) return .{ .string = s };
    const out = try vm.heap.alloc(u8, s.len - n * a.len + n * b.len);
    _ = std.mem.replace(u8, s, a, b, out);
    return .{ .string = out };
}

fn pad(vm: *Vm, row: prelude.Fn, s: []const u8, n: i128, ch: []const u8, left: bool) Error!Value {
    if (count(ch) != 1) return fail(vm, .other, row, "{s} pads with one grapheme, not \"{s}\"", .{ row.name, ch });
    const size = count(s);
    if (size >= n) return .{ .string = s };
    const missing: usize = @intCast(n - size);
    const extra = std.math.mul(usize, missing, ch.len) catch return fail(vm, .overflow, row, "{s}({d}) is too long a string", .{ row.name, n });
    const out = try vm.heap.alloc(u8, s.len + extra);
    const fill = if (left) out[0..extra] else out[s.len..];
    for (0..missing) |k| @memcpy(fill[k * ch.len ..][0..ch.len], ch);
    @memcpy(if (left) out[extra..] else out[0..s.len], s);
    return .{ .string = out };
}

fn repeat(vm: *Vm, row: prelude.Fn, s: []const u8, n: i128) Error!Value {
    const times = std.math.cast(usize, n) orelse return fail(vm, .overflow, row, "repeat({d}) is too long a string", .{n});
    const len = std.math.mul(usize, s.len, times) catch return fail(vm, .overflow, row, "repeat({d}) is too long a string", .{n});
    const out = try vm.heap.alloc(u8, len);
    for (0..times) |k| @memcpy(out[k * s.len ..][0..s.len], s);
    return .{ .string = out };
}

fn join(vm: *Vm, row: prelude.Fn, xs: []const Value, sep: []const u8) Error!Value {
    _ = row;
    if (xs.len == 0) return .{ .string = "" };
    var len: usize = sep.len * (xs.len - 1);
    for (xs) |x| len += x.string.len;
    const out = try vm.heap.alloc(u8, len);
    var at: usize = 0;
    for (xs, 0..) |x, k| {
        if (k > 0) {
            @memcpy(out[at..][0..sep.len], sep);
            at += sep.len;
        }
        @memcpy(out[at..][0..x.string.len], x.string);
        at += x.string.len;
    }
    return .{ .string = out };
}

// ---- numbers

/// `to_u8` and `checked_to_u8` name their target by the name's last part.
fn targetKind(name: []const u8) types.IntKind {
    const suffix = name[std.mem.lastIndexOfScalar(u8, name, '_').? + 1 ..];
    return std.meta.stringToEnum(types.IntKind, suffix).?;
}

/// Whole-number text: ASCII digits, at least one, with one leading `-` when `signed`.
fn parseWhole(s: []const u8, signed: bool, kind: types.IntKind) ?i128 {
    const negative = signed and s.len > 0 and s[0] == '-';
    const digits = s[@intFromBool(negative)..];
    if (digits.len == 0 or digits.len > 40) return null;
    var v: i128 = 0;
    for (digits) |d| {
        if (!std.ascii.isDigit(d)) return null;
        v = v * 10 + (d - '0');
    }
    if (negative) v = -v;
    if (v < vm_mod.minOf(kind) or v > vm_mod.maxOf(kind)) return null;
    return v;
}

/// Float text: `-`?, digits, then `.` and digits, then `e` or `E`, a sign, and digits,
/// the last two parts optional. A value too large for a Float64 is not a number.
fn parseFloat(s: []const u8) ?f64 {
    var i: usize = 0;
    if (i < s.len and s[i] == '-') i += 1;
    i = digitsFrom(s, i) orelse return null;
    if (i < s.len and s[i] == '.') i = digitsFrom(s, i + 1) orelse return null;
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        i += 1;
        if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
        i = digitsFrom(s, i) orelse return null;
    }
    if (i != s.len) return null;
    const x = std.fmt.parseFloat(f64, s) catch return null;
    return if (std.math.isInf(x)) null else x;
}

/// Past one or more digits starting at `i`, or null when there are none.
fn digitsFrom(s: []const u8, i: usize) ?usize {
    var j = i;
    while (j < s.len and std.ascii.isDigit(s[j])) j += 1;
    return if (j == i) null else j;
}

const max_places = 15;
/// A finite f64's shortest decimal spelling has at most 309 whole digits or 324 decimals.
const decimal_buffer = 400;

/// `x` with exactly `places` decimals, rounded half away from zero on its shortest
/// decimal spelling, into `buf`. Zero is never negative.
fn rounded(buf: *[decimal_buffer]u8, x: f64, places: usize) []const u8 {
    var spelled: [decimal_buffer]u8 = undefined;
    const text = std.fmt.bufPrint(&spelled, "{d}", .{@abs(x)}) catch unreachable;
    const dot = std.mem.indexOfScalar(u8, text, '.') orelse text.len;
    const whole = text[0..dot];
    const fraction = if (dot < text.len) text[dot + 1 ..] else "";
    // Digits, whole then `places` of fraction, with room for a carry in front.
    var digits: [decimal_buffer]u8 = undefined;
    digits[0] = '0';
    var n: usize = 1;
    @memcpy(digits[n..][0..whole.len], whole);
    n += whole.len;
    for (0..places) |k| {
        digits[n] = if (k < fraction.len) fraction[k] else '0';
        n += 1;
    }
    if (places < fraction.len and fraction[places] >= '5') {
        var k = n;
        while (k > 0) {
            k -= 1;
            if (digits[k] == '9') {
                digits[k] = '0';
                continue;
            }
            digits[k] += 1;
            break;
        }
    }
    var first: usize = 0;
    while (first + 1 < n - places and digits[first] == '0') first += 1;
    const zero = for (digits[first..n]) |d| {
        if (d != '0') break false;
    } else true;
    var len: usize = 0;
    if (x < 0 and !zero) {
        buf[0] = '-';
        len = 1;
    }
    const whole_len = n - places - first;
    @memcpy(buf[len..][0..whole_len], digits[first .. n - places]);
    len += whole_len;
    if (places > 0) {
        buf[len] = '.';
        len += 1;
        @memcpy(buf[len..][0..places], digits[n - places .. n]);
        len += places;
    }
    return buf[0..len];
}

test "rounding happens on the shortest decimal spelling, half away from zero" {
    var buf: [decimal_buffer]u8 = undefined;
    try std.testing.expectEqualStrings("2.68", rounded(&buf, 2.675, 2));
    try std.testing.expectEqualStrings("-3", rounded(&buf, -2.5, 0));
    try std.testing.expectEqualStrings("10.0", rounded(&buf, 9.96, 1));
    try std.testing.expectEqualStrings("0.00", rounded(&buf, -0.001, 2));
    try std.testing.expectEqualStrings("100.000", rounded(&buf, 99.9995, 3));
    try std.testing.expectEqualStrings("0.0", rounded(&buf, 0.0, 1));
    try std.testing.expectEqualStrings("1000000000000000000000", rounded(&buf, 1e21, 0));
}

test "numbers are read only from text that spells one" {
    try std.testing.expectEqual(@as(?i128, 42), parseWhole("42", false, .u64));
    try std.testing.expectEqual(@as(?i128, null), parseWhole("-42", false, .u64));
    try std.testing.expectEqual(@as(?i128, -42), parseWhole("-42", true, .i64));
    try std.testing.expectEqual(@as(?i128, null), parseWhole("18446744073709551616", false, .u64));
    try std.testing.expectEqual(@as(?i128, null), parseWhole("1_000", false, .u64));
    try std.testing.expectEqual(@as(?f64, 2500), parseFloat("2.5e3"));
    for ([_][]const u8{ ".5", "5.", "+1", "inf", "nan", "0x10", "1e999", "" }) |t| try std.testing.expectEqual(@as(?f64, null), parseFloat(t));
}

test "graphemes carry their combining marks, and trim takes Unicode whitespace" {
    try std.testing.expectEqual(@as(i128, 4), count("cafe\u{301}"));
    try std.testing.expectEqual(@as(i128, 4), count("café"));
    try std.testing.expectEqualStrings("e\u{301}", slice("cafe\u{301}!", 3, 4));
    try std.testing.expectEqualStrings("", slice("abc", 2, 1));
    try std.testing.expectEqualStrings("bc", slice("abc", 1, 99));
    try std.testing.expectEqualStrings("a b", trim("\u{3000} a b\t\n"));
    try std.testing.expectEqualStrings("", trim(" \n"));
}
