//! Stage 1: source bytes → tokens (grammar.md §1). `#` to end of line is the only
//! comment; strings always interpolate, and a `#{...}` hole stays inside the string
//! token for the parser to split.
//!
//! Newlines are tokens, collapsed so that blank lines and comment lines yield one.
//! Inside an open paren, bracket, or brace the lexer joins lines, except inside a
//! block that sits in one: the block form of an anonymous function (`fn(x)` then a
//! newline) and an `if`, `case`, or `for` opened there keep their newlines until
//! their `end`, because the grammar needs them to separate statements.
const std = @import("std");
const token = @import("token.zig");
const diag = @import("diag.zig");

const Kind = token.Kind;
const Token = token.Token;

pub const Error = error{ OutOfMemory, Rejected };

pub const why_unexpected = "Mo source outside strings and comments is names, numbers, and the operators of grammar §1; this character is none of those.";
pub const why_unterminated = "A string opened with \" closes on the same line; text that spans lines goes in a \"\"\" block.";

/// Tokens end with `.eof`. The first lexical error stops the file with one record.
pub fn lex(gpa: std.mem.Allocator, source: []const u8, diags: *diag.List) Error![]Token {
    std.debug.assert(source.len < std.math.maxInt(u32));
    var l: Lexer = .{ .gpa = gpa, .src = source, .diags = diags };
    defer l.nest.deinit(gpa);
    errdefer l.tokens.deinit(gpa);
    try l.run();
    return l.tokens.toOwnedSlice(gpa);
}

const Nest = enum {
    /// `(`, `[`, `{`: newlines are joined.
    open,
    /// `fn` inside an open delimiter, before its parameters close.
    fn_head,
    /// A block inside an open delimiter: newlines count until `end`.
    block,
    /// The one-line form `fn(x) expr end`: newlines joined, closed by `end`.
    line_block,
};

const Lexer = struct {
    gpa: std.mem.Allocator,
    src: []const u8,
    diags: *diag.List,
    i: u32 = 0,
    tokens: std.ArrayList(Token) = .empty,
    nest: std.ArrayList(Nest) = .empty,

    fn run(l: *Lexer) Error!void {
        while (l.i < l.src.len) {
            const c = l.src[l.i];
            switch (c) {
                ' ', '\t', '\r' => l.i += 1,
                '#' => l.skipComment(),
                '\n' => {
                    l.i += 1;
                    if (l.newlineCounts()) try l.emitNewline(l.i - 1);
                },
                '"' => try l.string(),
                'a'...'z' => try l.word(),
                'A'...'Z' => try l.typeName(),
                '0'...'9' => try l.number(),
                else => try l.punct(),
            }
        }
        try l.emitNewline(l.i);
        try l.tokens.append(l.gpa, .{ .kind = .eof, .start = l.i, .end = l.i });
    }

    fn newlineCounts(l: *Lexer) bool {
        const top = l.nest.getLastOrNull() orelse return true;
        return top == .block;
    }

    fn emitNewline(l: *Lexer, at: u32) Error!void {
        const last = l.tokens.getLastOrNull() orelse return;
        if (last.kind == .newline) return;
        try l.tokens.append(l.gpa, .{ .kind = .newline, .start = at, .end = at });
    }

    fn add(l: *Lexer, kind: Kind, start: u32) Error!void {
        try l.tokens.append(l.gpa, .{ .kind = kind, .start = start, .end = l.i });
    }

    fn fail(l: *Lexer, code: []const u8, at: u32, what: []const u8, why: []const u8) Error {
        try l.diags.append(l.gpa, .{ .code = code, .category = .syntax, .at = at, .what = what, .why = why });
        return error.Rejected;
    }

    fn skipComment(l: *Lexer) void {
        while (l.i < l.src.len and l.src[l.i] != '\n') l.i += 1;
    }

    fn peekByte(l: *Lexer, ahead: u32) u8 {
        const at = l.i + ahead;
        return if (at < l.src.len) l.src[at] else 0;
    }

    fn prevKind(l: *Lexer) ?Kind {
        const last = l.tokens.getLastOrNull() orelse return null;
        return last.kind;
    }

    fn isAlnum(c: u8) bool {
        return std.ascii.isAlphanumeric(c);
    }

    fn word(l: *Lexer) Error!void {
        const start = l.i;
        while (l.i < l.src.len and (isAlnum(l.src[l.i]) or l.src[l.i] == '_')) l.i += 1;
        if (l.i < l.src.len and l.src[l.i] == '?') l.i += 1;
        const text = l.src[start..l.i];
        // After a dot a keyword is a field or function name: `state.km`, `x.type`.
        const after_dot = l.prevKind() == .dot;
        const kind: Kind = if (after_dot) .ident else token.keywords.get(text) orelse .ident;
        const prev = l.prevKind();
        try l.add(kind, start);
        if (l.nest.items.len == 0) return;
        switch (kind) {
            .kw_fn => try l.nest.append(l.gpa, .fn_head),
            .kw_case, .kw_for => try l.nest.append(l.gpa, .block),
            // A trailing `if` (on `return`, an arm guard, a comprehension guard) follows
            // an operand and opens nothing; any other `if` opens a block.
            .kw_if => if (prev == null or !endsOperand(prev.?)) try l.nest.append(l.gpa, .block),
            .kw_end => switch (l.nest.getLast()) {
                .block, .line_block, .fn_head => _ = l.nest.pop(),
                .open => {},
            },
            else => {},
        }
    }

    fn endsOperand(kind: Kind) bool {
        return switch (kind) {
            .ident, .type_name, .int, .float, .string, .atom, .underscore => true,
            .r_paren, .r_bracket, .r_brace, .kw_true, .kw_false, .kw_result => true,
            else => false,
        };
    }

    fn typeName(l: *Lexer) Error!void {
        const start = l.i;
        while (l.i < l.src.len and isAlnum(l.src[l.i])) l.i += 1;
        try l.add(.type_name, start);
    }

    fn number(l: *Lexer) Error!void {
        const start = l.i;
        while (l.i < l.src.len and (std.ascii.isDigit(l.src[l.i]) or l.src[l.i] == '_')) l.i += 1;
        // `result.0.1` reads as two tuple fields, never as the float `0.1`.
        const after_dot = l.prevKind() == .dot;
        if (!after_dot and l.peekByte(0) == '.' and std.ascii.isDigit(l.peekByte(1))) {
            l.i += 1;
            while (l.i < l.src.len and std.ascii.isDigit(l.src[l.i])) l.i += 1;
            return l.add(.float, start);
        }
        try l.add(.int, start);
    }

    fn string(l: *Lexer) Error!void {
        const start = l.i;
        if (std.mem.startsWith(u8, l.src[l.i..], "\"\"\"")) {
            const rest = l.src[l.i + 3 ..];
            const close = std.mem.indexOf(u8, rest, "\"\"\"") orelse
                return l.fail("MO0002", start, "unterminated \"\"\" string", why_unterminated);
            l.i += @intCast(3 + close + 3);
            return l.add(.string, start);
        }
        l.i = try l.scanLine(start);
        try l.add(.string, start);
    }

    /// Scans a one-line string starting at the quote at `start`; returns the index
    /// after the closing quote. Holes may hold braces and strings of their own.
    fn scanLine(l: *Lexer, start: u32) Error!u32 {
        var i = start + 1;
        while (i < l.src.len) {
            switch (l.src[i]) {
                '"' => return i + 1,
                '\n' => break,
                '\\' => i += 2,
                '#' => if (i + 1 < l.src.len and l.src[i + 1] == '{') {
                    i = try l.scanHole(start, i + 2);
                } else {
                    i += 1;
                },
                else => i += 1,
            }
        }
        return l.fail("MO0002", start, "unterminated string", why_unterminated);
    }

    fn scanHole(l: *Lexer, string_start: u32, from: u32) Error!u32 {
        var depth: u32 = 1;
        var i = from;
        while (i < l.src.len) {
            switch (l.src[i]) {
                '{' => {
                    depth += 1;
                    i += 1;
                },
                '}' => {
                    depth -= 1;
                    i += 1;
                    if (depth == 0) return i;
                },
                '"' => i = try l.scanLine(i),
                '\n' => break,
                else => i += 1,
            }
        }
        return l.fail("MO0002", string_start, "unterminated string", why_unterminated);
    }

    fn punct(l: *Lexer) Error!void {
        const start = l.i;
        const c = l.src[l.i];
        const next = l.peekByte(1);
        l.i += 1;
        switch (c) {
            '(', '[', '{' => {
                try l.add(switch (c) {
                    '(' => .l_paren,
                    '[' => .l_bracket,
                    else => .l_brace,
                }, start);
                try l.nest.append(l.gpa, .open);
            },
            ')', ']', '}' => {
                try l.add(switch (c) {
                    ')' => .r_paren,
                    ']' => .r_bracket,
                    else => .r_brace,
                }, start);
                l.closeOpen();
            },
            ',' => try l.add(.comma, start),
            '.' => if (next == '.') {
                l.i += 1;
                try l.add(.dot_dot, start);
            } else try l.add(.dot, start),
            ':' => if (std.ascii.isLower(next) and start > 0 and std.ascii.isWhitespace(l.src[start - 1])) {
                // `restart: :always`; a colon glued to the name before it is never an atom.
                while (l.i < l.src.len and (isAlnum(l.src[l.i]) or l.src[l.i] == '_')) l.i += 1;
                try l.add(.atom, start);
            } else try l.add(.colon, start),
            '!' => try l.pair(next, '=', .bang_eq, .bang, start),
            '=' => try l.pair(next, '=', .eq_eq, .eq, start),
            '<' => try l.pair(next, '=', .lt_eq, .lt, start),
            '>' => try l.pair(next, '=', .gt_eq, .gt, start),
            '+' => try l.pair(next, '=', .plus_eq, .plus, start),
            '-' => try l.pair(next, '=', .minus_eq, .minus, start),
            '*' => try l.add(.star, start),
            '/' => try l.add(.slash, start),
            '%' => try l.add(.percent, start),
            '_' => if (isAlnum(next) or next == '_') {
                return l.fail("MO0001", start, "unexpected character: a name starts with a lowercase letter", why_unexpected);
            } else try l.add(.underscore, start),
            else => return l.fail("MO0001", start, "unexpected character", why_unexpected),
        }
    }

    fn pair(l: *Lexer, next: u8, want: u8, two: Kind, one: Kind, start: u32) Error!void {
        if (next == want) {
            l.i += 1;
            return l.add(two, start);
        }
        try l.add(one, start);
    }

    /// Pops through to the matching open delimiter. When that closes an anonymous
    /// function's parameters, the rest of the line says which form it has.
    fn closeOpen(l: *Lexer) void {
        while (l.nest.pop()) |n| if (n == .open) break;
        const top = l.nest.getLastOrNull() orelse return;
        if (top != .fn_head) return;
        var j = l.i;
        while (j < l.src.len and (l.src[j] == ' ' or l.src[j] == '\t' or l.src[j] == '\r')) j += 1;
        const block = j >= l.src.len or l.src[j] == '\n' or l.src[j] == '#';
        l.nest.items[l.nest.items.len - 1] = if (block) .block else .line_block;
    }
};

/// For the parser, which splits strings: `text[from]` is just after a `#{` in a
/// string the lexer accepted; returns the index of the `}` that closes the hole.
pub fn holeClose(text: []const u8, from: usize) usize {
    var depth: usize = 1;
    var i = from;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            '"' => i = stringClose(text, i),
            else => {},
        }
    }
    return text.len;
}

fn stringClose(text: []const u8, open: usize) usize {
    var i = open + 1;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '"' => return i,
            '\\' => i += 1,
            '#' => if (i + 1 < text.len and text[i + 1] == '{') {
                i = holeClose(text, i + 2);
            },
            else => {},
        }
    }
    return text.len;
}

fn kindsOf(source: []const u8) ![]Kind {
    const gpa = std.testing.allocator;
    var diags: diag.List = .empty;
    defer diags.deinit(gpa);
    const toks = try lex(gpa, source, &diags);
    defer gpa.free(toks);
    const kinds = try gpa.alloc(Kind, toks.len);
    for (toks, kinds) |t, *k| k.* = t.kind;
    return kinds;
}

fn expectKinds(source: []const u8, want: []const Kind) !void {
    const got = try kindsOf(source);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualSlices(Kind, want, got);
}

test "every keyword" {
    for (token.keywords.keys()) |text| {
        const want = token.keywords.get(text).?;
        try expectKinds(text, &.{ want, .newline, .eof });
    }
}

test "every operator" {
    try expectKinds("( ) [ ] { } , . .. : ! != = == < <= > >= + += - -= * / % _ x :always", &.{
        .l_paren,  .r_paren, .l_bracket, .r_bracket, .l_brace, .r_brace, .comma, .dot,   .dot_dot,
        .colon,    .bang,    .bang_eq,   .eq,        .eq_eq,   .lt,      .lt_eq, .gt,    .gt_eq,
        .plus,     .plus_eq, .minus,     .minus_eq,  .star,    .slash,   .percent, .underscore, .ident,
        .atom,     .newline, .eof,
    });
}

test "names, numbers, and comments" {
    try expectKinds("empty? Int64 10_000 2.5 result.0.1 200.ms # a comment\n\n\nx", &.{
        .ident, .type_name, .int,  .float, .kw_result, .dot, .int, .dot, .int,
        .int,   .dot,       .ident, .newline, .ident, .newline, .eof,
    });
    try expectKinds("state.state", &.{ .kw_state, .dot, .ident, .newline, .eof });
}

test "a string with a hole" {
    const gpa = std.testing.allocator;
    var diags: diag.List = .empty;
    defer diags.deinit(gpa);
    const src = "\"a #{f(\"}\")} b\" x";
    const toks = try lex(gpa, src, &diags);
    defer gpa.free(toks);
    try std.testing.expectEqual(Kind.string, toks[0].kind);
    try std.testing.expectEqualStrings("\"a #{f(\"}\")} b\"", src[toks[0].start..toks[0].end]);
    try std.testing.expectEqual(Kind.ident, toks[1].kind);
}

test "a triple-quoted block" {
    try expectKinds("x = \"\"\"\n  one\n  two\n  \"\"\"\n", &.{ .ident, .eq, .string, .newline, .eof });
}

test "a joined line" {
    try expectKinds("f(a,\n  b)\ng", &.{ .ident, .l_paren, .ident, .comma, .ident, .r_paren, .newline, .ident, .newline, .eof });
}

test "a block inside parens keeps its newlines; a one-line fn does not" {
    try expectKinds("m(fn(x)\n  y = x\n  y\nend)\n", &.{
        .ident, .l_paren, .kw_fn, .l_paren, .ident, .r_paren, .newline, .ident, .eq, .ident, .newline,
        .ident, .newline, .kw_end, .r_paren, .newline, .eof,
    });
    try expectKinds("m(fn(x) x if\n y end)", &.{
        .ident, .l_paren, .kw_fn, .l_paren, .ident, .r_paren, .ident, .kw_if, .ident, .kw_end, .r_paren, .newline, .eof,
    });
}

test "errors are records with stable codes" {
    const gpa = std.testing.allocator;
    var diags: diag.List = .empty;
    defer diags.deinit(gpa);
    try std.testing.expectError(error.Rejected, lex(gpa, "x = $", &diags));
    try std.testing.expectEqualStrings("MO0001", diags.items[0].code);
    try std.testing.expectEqual(@as(u32, 4), diags.items[0].at);
    try std.testing.expectError(error.Rejected, lex(gpa, "x = \"open\ny", &diags));
    try std.testing.expectEqualStrings("MO0002", diags.items[1].code);
}
