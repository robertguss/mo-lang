//! JSON for the stdlib (design-v0/09-stdlib.md). `Json.encode` spells any value as JSON
//! text on one line, `", "` between items and `": "` after a key. The lowering passes the
//! argument's checked type, so a map's keys, an Option, and a `Json` value are spelled by
//! what they are, not by what they look like; where the type says nothing (a type
//! parameter), the value speaks for itself. `Json.decode` reads RFC 8259 text into the
//! prelude's `Json` enum, or names the byte where the text stops being JSON.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const check = @import("check.zig");
const stdlib = @import("stdlib.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;
const Writer = std.Io.Writer;

/// Nesting deeper than this is `Syntax`: the reader recurses once per level.
pub const max_depth = 512;

// ---- encode

/// `Json.encode(v)`; `t` is v's checked type, or bytecode.none.
pub fn encode(vm: *Vm, v: Value, t: u32) Error!Value {
    var aw: Writer.Allocating = .init(vm.heap);
    var e: Encoder = .{ .vm = vm, .k = &vm.program.checked, .w = &aw.writer };
    e.value(v, if (t == bytecode.none) null else t) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        else => |x| return x,
    };
    return .{ .string = try aw.toOwnedSlice() };
}

const Encoder = struct {
    vm: *Vm,
    k: *const check.Checked,
    w: *Writer,

    const Fail = Error || Writer.Error;

    /// The checked type's base, or null when it says nothing the value does not.
    fn known(e: *Encoder, t: ?types.Id) ?types.Type {
        const id = t orelse return null;
        const ty = e.k.pool.get(e.k.pool.base(id));
        return switch (ty.tag) {
            .unknown, .never, .variable, .param, .self_ => null,
            else => ty,
        };
    }

    fn value(e: *Encoder, v: Value, t: ?types.Id) Fail!void {
        const ty = e.known(t);
        switch (v) {
            .none => try e.w.writeAll("null"),
            .bool => |b| try e.w.writeAll(if (b) "true" else "false"),
            .int => |i| try e.w.print("{d}", .{i}),
            .float => |x| try writeFloat(e.w, x),
            .string => |s| try writeString(e.w, s),
            .time => |ms| {
                var buf: [40]u8 = undefined;
                try writeString(e.w, stdlib.iso8601(&buf, ms));
            },
            .duration => |ms| try e.w.print("{d}", .{ms}),
            .list, .set => |xs| {
                const elem: ?types.Id = if (ty) |x| (if (x.tag == .list or x.tag == .set) x.a else null) else null;
                try e.w.writeAll("[");
                for (xs, 0..) |x, i| {
                    if (i > 0) try e.w.writeAll(", ");
                    try e.value(x, elem);
                }
                try e.w.writeAll("]");
            },
            .tuple => |xs| {
                const elems: []const types.Id = if (ty) |x| (if (x.tag == .tuple) e.k.pool.elems(x) else &.{}) else &.{};
                try e.w.writeAll("[");
                for (xs, 0..) |x, i| {
                    if (i > 0) try e.w.writeAll(", ");
                    try e.value(x, if (i < elems.len) elems[i] else null);
                }
                try e.w.writeAll("]");
            },
            .map => |xs| try e.map(xs, ty),
            .record => |r| {
                const d = e.k.decls[r.decl];
                try e.fields(r.fields, e.k.fields[d.fields.start..d.fields.end]);
            },
            .variant => |r| try e.variant(r, ty),
            .func, .cap, .handle => {
                e.vm.report = .{ .kind = .other, .clause = try std.fmt.allocPrint(e.vm.gpa, "{s} has no JSON", .{try e.vm.render(v)}), .within = "encode", .at = 0 };
                return error.Crash;
            },
        }
    }

    /// A map with String keys is an object; any other is an array of [key, value] pairs.
    fn map(e: *Encoder, xs: []const Value, ty: ?types.Type) Fail!void {
        const key_t: ?types.Id = if (ty) |x| (if (x.tag == .map) x.a else null) else null;
        const value_t: ?types.Id = if (ty) |x| (if (x.tag == .map) x.b else null) else null;
        const string_keys = if (e.known(key_t)) |kt| kt.tag == .string else blk: {
            var at: usize = 0;
            while (at < xs.len) : (at += 2) {
                if (xs[at] != .string) break :blk false;
            }
            break :blk true;
        };
        try e.w.writeAll(if (string_keys) "{" else "[");
        var at: usize = 0;
        while (at < xs.len) : (at += 2) {
            if (at > 0) try e.w.writeAll(", ");
            if (string_keys) {
                try writeString(e.w, xs[at].string);
                try e.w.writeAll(": ");
                try e.value(xs[at + 1], value_t);
            } else {
                try e.w.writeAll("[");
                try e.value(xs[at], key_t);
                try e.w.writeAll(", ");
                try e.value(xs[at + 1], value_t);
                try e.w.writeAll("]");
            }
        }
        try e.w.writeAll(if (string_keys) "}" else "]");
    }

    fn fields(e: *Encoder, values: []const Value, defs: []const check.Field) Fail!void {
        try e.w.writeAll("{");
        for (values, 0..) |x, i| {
            if (i > 0) try e.w.writeAll(", ");
            try writeString(e.w, if (i < defs.len) defs[i].name else "");
            try e.w.writeAll(": ");
            try e.value(x, if (i < defs.len) defs[i].type else null);
        }
        try e.w.writeAll("}");
    }

    /// Some(x) is x and None is null; Ok and Error, and a variant with fields, are an
    /// object with one key, the name; a variant with no fields is its name.
    fn variant(e: *Encoder, r: Value.Variant, ty: ?types.Type) Fail!void {
        const k = e.k;
        if (ty) |x| switch (x.tag) {
            .option => {
                if (r.fields.len == 1) return e.value(r.fields[0], x.a);
                return e.w.writeAll("null");
            },
            .result => return e.tagged(r.name, r.fields[0], if (std.mem.eql(u8, r.name, "Ok")) x.a else x.b),
            .decl => if (k.decls[x.a].kind == .prelude_enum and std.mem.eql(u8, k.decls[x.a].name, "Json")) return e.json(r),
            else => {},
        };
        if (ty == null) {
            if (std.mem.eql(u8, r.name, "Some")) return e.value(r.fields[0], null);
            if (std.mem.eql(u8, r.name, "None")) return e.w.writeAll("null");
            if (std.mem.eql(u8, r.name, "Ok") or std.mem.eql(u8, r.name, "Error")) return e.tagged(r.name, r.fields[0], null);
        }
        if (r.fields.len == 0) return writeString(e.w, r.name);
        try e.w.writeAll("{");
        try writeString(e.w, r.name);
        try e.w.writeAll(": ");
        try e.fields(r.fields, e.variantFields(r, ty));
        try e.w.writeAll("}");
    }

    fn tagged(e: *Encoder, name: []const u8, v: Value, t: ?types.Id) Fail!void {
        try e.w.writeAll("{");
        try writeString(e.w, name);
        try e.w.writeAll(": ");
        try e.value(v, t);
        try e.w.writeAll("}");
    }

    /// The variant's field declarations: from its enum when the type names one, else the
    /// first variant of that name and size.
    fn variantFields(e: *Encoder, r: Value.Variant, ty: ?types.Type) []const check.Field {
        const k = e.k;
        const range: ?check.Range = blk: {
            if (ty) |x| if (x.tag == .decl or x.tag == .message) {
                const d = k.decls[x.a];
                for (k.variants[d.variants.start..d.variants.end]) |kv| {
                    if (std.mem.eql(u8, kv.name, r.name)) break :blk kv.fields;
                }
            };
            for (k.variants) |kv| {
                if (std.mem.eql(u8, kv.name, r.name) and kv.fields.len() == r.fields.len) break :blk kv.fields;
            }
            break :blk null;
        };
        const got = range orelse return &.{};
        return k.fields[got.start..got.end];
    }

    /// A `Json` value is the JSON it holds.
    fn json(e: *Encoder, r: Value.Variant) Fail!void {
        if (std.mem.eql(u8, r.name, "Null")) return e.w.writeAll("null");
        const f = r.fields[0];
        if (std.mem.eql(u8, r.name, "Object")) {
            try e.w.writeAll("{");
            var at: usize = 0;
            while (at < f.map.len) : (at += 2) {
                if (at > 0) try e.w.writeAll(", ");
                try writeString(e.w, f.map[at].string);
                try e.w.writeAll(": ");
                try e.json(f.map[at + 1].variant);
            }
            return e.w.writeAll("}");
        }
        if (std.mem.eql(u8, r.name, "Array")) {
            try e.w.writeAll("[");
            for (f.list, 0..) |item, i| {
                if (i > 0) try e.w.writeAll(", ");
                try e.json(item.variant);
            }
            return e.w.writeAll("]");
        }
        if (std.mem.eql(u8, r.name, "String")) return writeString(e.w, f.string);
        if (std.mem.eql(u8, r.name, "Number")) return writeFloat(e.w, f.float);
        return e.w.writeAll(if (f.bool) "true" else "false");
    }
};

/// The shortest decimal spelling that reads back as the same float, with `.0` when it has
/// no fraction; NaN and the infinities have no JSON, so they are null.
fn writeFloat(w: *Writer, x: f64) Writer.Error!void {
    if (std.math.isNan(x) or std.math.isInf(x)) return w.writeAll("null");
    var buf: [400]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{x}) catch unreachable;
    try w.writeAll(text);
    if (std.mem.indexOfScalar(u8, text, '.') == null) try w.writeAll(".0");
}

fn writeString(w: *Writer, s: []const u8) Writer.Error!void {
    try w.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        0x08 => try w.writeAll("\\b"),
        0x0C => try w.writeAll("\\f"),
        0...0x07, 0x0B, 0x0E...0x1F => try w.print("\\u{x:0>4}", .{c}),
        else => try w.writeByte(c),
    };
    try w.writeByte('"');
}

// ---- decode

/// `Json.decode(text)`: `Ok(json)` for text that is exactly one JSON value with optional
/// whitespace around it, or `Error(Syntax(at))`.
pub fn decode(vm: *Vm, text: []const u8) Error!Value {
    var d: Decoder = .{ .vm = vm, .s = text };
    const v = d.value(0) catch |err| switch (err) {
        error.Syntax => return syntax(vm, d.at),
        else => |x| return x,
    };
    d.space();
    if (d.i != text.len) return syntax(vm, d.i);
    return vm.variant("Ok", &.{v});
}

fn syntax(vm: *Vm, at: usize) Error!Value {
    return vm.variant("Error", &.{try vm.variant("Syntax", &.{.{ .int = @intCast(at) }})});
}

const Decoder = struct {
    vm: *Vm,
    s: []const u8,
    i: usize = 0,
    /// Where the text stopped being JSON.
    at: usize = 0,

    const Fail = Error || error{Syntax};

    fn bad(d: *Decoder, at: usize) error{Syntax} {
        d.at = at;
        return error.Syntax;
    }

    fn space(d: *Decoder) void {
        while (d.i < d.s.len and (d.s[d.i] == ' ' or d.s[d.i] == '\t' or d.s[d.i] == '\n' or d.s[d.i] == '\r')) d.i += 1;
    }

    fn value(d: *Decoder, depth: u32) Fail!Value {
        d.space();
        if (d.i >= d.s.len or depth > max_depth) return d.bad(d.i);
        switch (d.s[d.i]) {
            '{' => return d.object(depth),
            '[' => return d.array(depth),
            '"' => return d.vm.variant("String", &.{.{ .string = try d.string() }}),
            't' => return d.word("true", .{ .bool = true }),
            'f' => return d.word("false", .{ .bool = false }),
            'n' => return d.word("null", null),
            '-', '0'...'9' => return d.number(),
            else => return d.bad(d.i),
        }
    }

    fn word(d: *Decoder, text: []const u8, b: ?Value) Fail!Value {
        if (!std.mem.startsWith(u8, d.s[d.i..], text)) return d.bad(d.i);
        d.i += text.len;
        if (b) |v| return d.vm.variant("Bool", &.{v});
        return d.vm.variant("Null", &.{});
    }

    fn object(d: *Decoder, depth: u32) Fail!Value {
        const gpa = d.vm.gpa;
        var entries: std.ArrayList(Value) = .empty;
        defer entries.deinit(gpa);
        d.i += 1;
        d.space();
        if (d.i < d.s.len and d.s[d.i] == '}') {
            d.i += 1;
        } else while (true) {
            d.space();
            if (d.i >= d.s.len or d.s[d.i] != '"') return d.bad(d.i);
            const key: Value = .{ .string = try d.string() };
            d.space();
            if (d.i >= d.s.len or d.s[d.i] != ':') return d.bad(d.i);
            d.i += 1;
            const v = try d.value(depth + 1);
            // A repeated key keeps its first place and its last value.
            if (stdlib.indexOf(entries.items, 2, key)) |k| {
                entries.items[k + 1] = v;
            } else {
                try entries.append(gpa, key);
                try entries.append(gpa, v);
            }
            if (try d.more('}')) continue;
            break;
        }
        return d.vm.variant("Object", &.{.{ .map = try d.vm.heap.dupe(Value, entries.items) }});
    }

    fn array(d: *Decoder, depth: u32) Fail!Value {
        const gpa = d.vm.gpa;
        var items: std.ArrayList(Value) = .empty;
        defer items.deinit(gpa);
        d.i += 1;
        d.space();
        if (d.i < d.s.len and d.s[d.i] == ']') {
            d.i += 1;
        } else while (true) {
            try items.append(gpa, try d.value(depth + 1));
            if (try d.more(']')) continue;
            break;
        }
        return d.vm.variant("Array", &.{.{ .list = try d.vm.heap.dupe(Value, items.items) }});
    }

    /// After an item: true past a `,`, false past `close`.
    fn more(d: *Decoder, close: u8) error{Syntax}!bool {
        d.space();
        if (d.i >= d.s.len) return d.bad(d.i);
        if (d.s[d.i] == ',') {
            d.i += 1;
            return true;
        }
        if (d.s[d.i] != close) return d.bad(d.i);
        d.i += 1;
        return false;
    }

    fn number(d: *Decoder) Fail!Value {
        const start = d.i;
        if (d.s[d.i] == '-') d.i += 1;
        if (d.i < d.s.len and d.s[d.i] == '0') {
            d.i += 1;
        } else if (!d.digits()) return d.bad(d.i);
        if (d.i < d.s.len and d.s[d.i] == '.') {
            d.i += 1;
            if (!d.digits()) return d.bad(d.i);
        }
        if (d.i < d.s.len and (d.s[d.i] == 'e' or d.s[d.i] == 'E')) {
            d.i += 1;
            if (d.i < d.s.len and (d.s[d.i] == '+' or d.s[d.i] == '-')) d.i += 1;
            if (!d.digits()) return d.bad(d.i);
        }
        // A number too large for a Float64 has no Json.
        const x = std.fmt.parseFloat(f64, d.s[start..d.i]) catch return d.bad(start);
        if (std.math.isInf(x)) return d.bad(start);
        return d.vm.variant("Number", &.{.{ .float = x }});
    }

    /// Past one or more digits; false when there are none.
    fn digits(d: *Decoder) bool {
        const start = d.i;
        while (d.i < d.s.len and std.ascii.isDigit(d.s[d.i])) d.i += 1;
        return d.i > start;
    }

    /// A string's text, past its closing quote. Control characters must be escaped, and
    /// bytes above ASCII must be UTF-8.
    fn string(d: *Decoder) Fail![]const u8 {
        const gpa = d.vm.gpa;
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        d.i += 1;
        while (true) {
            if (d.i >= d.s.len) return d.bad(d.i);
            const c = d.s[d.i];
            switch (c) {
                '"' => {
                    d.i += 1;
                    return d.vm.heap.dupe(u8, out.items);
                },
                '\\' => try d.escape(&out),
                0...0x1F => return d.bad(d.i),
                0x20...0x21, 0x23...0x5B, 0x5D...0x7F => {
                    try out.append(gpa, c);
                    d.i += 1;
                },
                else => {
                    const len = std.unicode.utf8ByteSequenceLength(c) catch return d.bad(d.i);
                    if (d.i + len > d.s.len) return d.bad(d.i);
                    _ = std.unicode.utf8Decode(d.s[d.i .. d.i + len]) catch return d.bad(d.i);
                    try out.appendSlice(gpa, d.s[d.i .. d.i + len]);
                    d.i += len;
                },
            }
        }
    }

    fn escape(d: *Decoder, out: *std.ArrayList(u8)) Fail!void {
        const gpa = d.vm.gpa;
        const at = d.i;
        if (d.i + 1 >= d.s.len) return d.bad(at);
        const e = d.s[d.i + 1];
        d.i += 2;
        const byte: u8 = switch (e) {
            '"' => '"',
            '\\' => '\\',
            '/' => '/',
            'b' => 0x08,
            'f' => 0x0C,
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'u' => {
                var cp: u21 = try d.hex4(at);
                if (cp >= 0xD800 and cp <= 0xDBFF) {
                    if (!std.mem.startsWith(u8, d.s[d.i..], "\\u")) return d.bad(at);
                    d.i += 2;
                    const low = try d.hex4(at);
                    if (low < 0xDC00 or low > 0xDFFF) return d.bad(at);
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                } else if (cp >= 0xDC00 and cp <= 0xDFFF) return d.bad(at);
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &buf) catch return d.bad(at);
                try out.appendSlice(gpa, buf[0..n]);
                return;
            },
            else => return d.bad(at),
        };
        try out.append(gpa, byte);
    }

    fn hex4(d: *Decoder, at: usize) error{Syntax}!u21 {
        if (d.i + 4 > d.s.len) return d.bad(at);
        var v: u21 = 0;
        for (d.s[d.i .. d.i + 4]) |h| {
            const digit = std.fmt.charToDigit(h, 16) catch return d.bad(at);
            v = v * 16 + digit;
        }
        d.i += 4;
        return v;
    }
};

test "a string escapes what JSON requires and a float keeps a fraction" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeString(&aw.writer, "a\"b\\c\n\x01é");
    try aw.writer.writeAll(" ");
    try writeFloat(&aw.writer, 3.0);
    try aw.writer.writeAll(" ");
    try writeFloat(&aw.writer, -0.25);
    try aw.writer.writeAll(" ");
    try writeFloat(&aw.writer, std.math.nan(f64));
    try std.testing.expectEqualStrings("\"a\\\"b\\\\c\\n\\u0001é\" 3.0 -0.25 null", aw.written());
}
