//! `mo fmt`: the one shape of a Mo file (toolchain/FORMAT.md, one rule per row).
//! The file is lexed and parsed, then printed again from the tree. The tree has no
//! comments, blank lines, or grouping parentheses, so a trivia scan keeps those from
//! the source by token: the comments on their own lines above a token, the comment
//! after it on its line, whether a blank line comes before it, and whether a `(` only
//! groups. The printer walks the tree and consumes the file's tokens in order through
//! a cursor, so every token it prints is the source's own and a comment is printed
//! exactly where its token lands. A comment that cannot be placed rejects the file
//! (MO0502); the formatter never moves or drops one.
//!
//! Three forms depend on width: a one-line anonymous function (S8), a one-line case
//! arm (C1), and a one-line `if` value (I1). Each is tried first; when its line ends past
//! the limit, the line is printed again from its start with that form in block shape.
const std = @import("std");
const token = @import("token.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const diag = @import("diag.zig");

const Kind = token.Kind;
const Node = ast.Node;
const Index = ast.Index;

/// FORMAT.md L4.
pub const limit = 100;

pub const Error = error{ OutOfMemory, Rejected };

pub const why_comment = "The formatter never moves or drops a comment (toolchain/FORMAT.md, K5), and this one sits inside a line the formatter joins, such as parentheses that span lines. Put it on its own line above the statement.";

/// The formatter's row of the error catalog; the loop rule's is loops.entry.
pub const catalog = [_]diag.Entry{
    .{ .code = "MO0502", .category = .format, .what = "this comment sits inside a line the formatter joins; move it above the line", .why = why_comment, .fixes = &.{} },
};

/// Formats `source`, or rejects it with the lexer's, the parser's, or MO0502's record.
/// Nothing is freed: pass an arena.
pub fn format(gpa: std.mem.Allocator, source: []const u8, diags: *diag.List) Error![]u8 {
    const tokens = try lexer.lex(gpa, source, diags);
    const tree = try parser.parse(gpa, source, tokens, diags);
    return formatTree(gpa, tree, diags);
}

pub fn formatTree(gpa: std.mem.Allocator, tree: ast.Tree, diags: *diag.List) Error![]u8 {
    var p = try Printer.init(gpa, tree);
    p.module() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CommentInside => return reject(gpa, diags, p.tv.comments[p.bad_comment].start),
        error.Refit, error.NotFlat => unreachable, // every line is printed inside a frame that catches these
    };
    for (p.emitted, 0..) |done, k| if (!done) return reject(gpa, diags, p.tv.comments[k].start);
    return p.out.toOwnedSlice(gpa);
}

fn reject(gpa: std.mem.Allocator, diags: *diag.List, at: u32) Error {
    try diags.append(gpa, .{ .code = "MO0502", .category = .format, .at = at, .what = "this comment sits inside a line the formatter joins; move it above the line", .why = why_comment });
    return error.Rejected;
}

// ---- trivia

const Comment = struct {
    start: u32,
    end: u32,
    /// A blank line separates this comment from the comment above it.
    blank_before: bool,
};

const Trivia = struct {
    comments: []Comment,
    /// Per file token: the comments on their own lines directly above it.
    lead: []ast.Span,
    /// Per file token: 1 + the comment after it on its line, or 0.
    trail: []u32,
    /// Per file token: the author left a blank line above it (above its comments).
    blank: []bool,
    /// Per file token: a `(` that only groups, and the `)` that closes one.
    group_open: []bool,
    group_close: []bool,
    /// The eof token; the tokens after it belong to interpolation holes.
    eof: u32,
};

fn scan(gpa: std.mem.Allocator, tree: ast.Tree) error{OutOfMemory}!Trivia {
    const src = tree.source;
    const toks = tree.tokens;
    var eof: u32 = 0;
    while (toks[eof].kind != .eof) eof += 1;
    const n = eof + 1;
    const tv: Trivia = .{
        .comments = undefined,
        .lead = try gpa.alloc(ast.Span, n),
        .trail = try gpa.alloc(u32, n),
        .blank = try gpa.alloc(bool, n),
        .group_open = try gpa.alloc(bool, n),
        .group_close = try gpa.alloc(bool, n),
        .eof = eof,
    };
    @memset(tv.trail, 0);
    @memset(tv.blank, false);
    @memset(tv.group_open, false);
    @memset(tv.group_close, false);

    var comments: std.ArrayList(Comment) = .empty;
    var prev: ?u32 = null;
    var ti: u32 = 0;
    while (ti < n) : (ti += 1) {
        const t = toks[ti];
        tv.lead[ti] = .{ .start = 0, .end = 0 };
        if (t.kind == .newline) continue;
        var i: u32 = if (prev) |pi| toks[pi].end else 0;
        var on_prev_line = prev != null;
        var line_empty = true;
        var seen_blank = false;
        var lead_start: u32 = @intCast(comments.items.len);
        var first_lead = true;
        while (i < t.start) {
            switch (src[i]) {
                '\n' => {
                    if (line_empty and !on_prev_line) seen_blank = true;
                    on_prev_line = false;
                    line_empty = true;
                    i += 1;
                },
                '#' => {
                    var e = i;
                    while (e < src.len and src[e] != '\n') e += 1;
                    var te = e;
                    while (te > i and (src[te - 1] == ' ' or src[te - 1] == '\t' or src[te - 1] == '\r')) te -= 1;
                    if (on_prev_line) {
                        tv.trail[prev.?] = @intCast(comments.items.len + 1);
                        try comments.append(gpa, .{ .start = i, .end = te, .blank_before = false });
                        lead_start += 1;
                    } else {
                        if (first_lead) tv.blank[ti] = seen_blank;
                        first_lead = false;
                        try comments.append(gpa, .{ .start = i, .end = te, .blank_before = seen_blank });
                        seen_blank = false;
                    }
                    line_empty = false;
                    i = e;
                },
                else => i += 1,
            }
        }
        if (first_lead) tv.blank[ti] = seen_blank;
        tv.lead[ti] = .{ .start = lead_start, .end = @intCast(comments.items.len) };
        prev = ti;
    }

    // A `(` is structural when it follows something a call can follow, or opens a
    // tuple; every other `(` groups (the parser drops those from the tree).
    const tuple_open = try gpa.alloc(bool, n);
    @memset(tuple_open, false);
    for (tree.nodes) |node| switch (node.kind) {
        .tuple, .pat_tuple, .type_tuple => if (node.main_token < n) {
            tuple_open[node.main_token] = true;
        },
        else => {},
    };
    // `fn(acc, x) (acc + x) % 7 end`: the `(` right after an anonymous function's
    // parameters opens its body, so it groups though it follows a `)`.
    const body_open = try gpa.alloc(bool, n);
    @memset(body_open, false);
    for (tree.nodes) |node| if (node.kind == .anon_fn and node.main_token + 1 < n) {
        var depth: u32 = 0;
        var k = node.main_token + 1;
        while (k < n) : (k += 1) switch (toks[k].kind) {
            .l_paren => depth += 1,
            .r_paren => {
                depth -= 1;
                if (depth == 0) break;
            },
            else => {},
        };
        if (k + 1 < n and toks[k + 1].kind == .l_paren) body_open[k + 1] = true;
    };
    var stack: std.ArrayList(bool) = .empty;
    ti = 0;
    while (ti < n) : (ti += 1) switch (toks[ti].kind) {
        .l_paren => {
            const structural = tuple_open[ti] or (!body_open[ti] and ti > 0 and followsOperand(toks[ti - 1].kind));
            tv.group_open[ti] = !structural;
            try stack.append(gpa, !structural);
        },
        .r_paren => if (stack.pop()) |group| {
            tv.group_close[ti] = group;
        },
        else => {},
    };
    var result = tv;
    result.comments = try comments.toOwnedSlice(gpa);
    return result;
}

fn followsOperand(kind: Kind) bool {
    return switch (kind) {
        .ident, .type_name, .int, .float, .string, .r_paren, .r_bracket => true,
        .kw_end, .kw_true, .kw_false, .kw_result, .kw_state, .kw_message, .kw_fn, .kw_old, .kw_any => true,
        else => false,
    };
}

// ---- the printer

const E = error{
    OutOfMemory,
    /// A comment would land inside a line; `bad_comment` names it.
    CommentInside,
    /// The line starting at `refit_at` is too long and holds a one-line form; the
    /// first one is now forced to block shape.
    Refit,
    /// A line ended inside an attempt at a one-line form.
    NotFlat,
};

const Snap = struct {
    out: usize,
    cur: u32,
    indent: u32,
    bol: bool,
    want_blank: bool,
    line_start: usize,
    code_start: usize,
    line_brackets: u32,
    pending: u32,
    breaks: usize,
    marks: usize,
    flats: usize,
    flat_depth: u32,
    log: usize,
};

/// A bracket written on the current line, at its offset in the output.
const Mark = struct { at: usize, open: bool, list: bool };

/// A comma a line may break after (L5): the offset of the space after it in the line's code,
/// how many brackets are open around it, and the innermost one's offset and kind.
const Cut = struct { at: usize, depth: u32, group: usize, list: bool };

const Plan = struct { at: []const usize, fits: bool };

const Printer = struct {
    gpa: std.mem.Allocator,
    tree: ast.Tree,
    tv: Trivia,
    emitted: []bool,
    /// Comments emitted, in order, so a retry can take them back.
    log: std.ArrayList(u32) = .empty,
    out: std.ArrayList(u8) = .empty,
    /// The next source token to print.
    cur: u32 = 0,
    indent: u32 = 0,
    /// Nothing is written on the current line yet, not even its indent.
    bol: bool = true,
    want_blank: bool = false,
    line_start: usize = 0,
    code_start: usize = 0,
    /// `(` and `[` opened on this line and not yet closed.
    line_brackets: u32 = 0,
    /// 1 + a comment to print at the end of this line, or 0.
    pending: u32 = 0,
    /// Offsets of the space after each comma this line may break at (L5).
    breaks: std.ArrayList(usize) = .empty,
    /// Every bracket written on this line, in order, so a break knows how deep it sits.
    marks: std.ArrayList(Mark) = .empty,
    /// One-line forms on this line, outermost first.
    flats: std.ArrayList(Index) = .empty,
    flat_depth: u32 = 0,
    forced: []bool,
    refit_at: usize = 0,
    bad_comment: u32 = 0,

    fn init(gpa: std.mem.Allocator, tree: ast.Tree) error{OutOfMemory}!Printer {
        const tv = try scan(gpa, tree);
        const emitted = try gpa.alloc(bool, tv.comments.len);
        @memset(emitted, false);
        const forced = try gpa.alloc(bool, tree.nodes.len);
        @memset(forced, false);
        return .{ .gpa = gpa, .tree = tree, .tv = tv, .emitted = emitted, .forced = forced };
    }

    fn node(p: *Printer, i: Index) Node {
        return p.tree.nodes[i];
    }

    fn spanAt(p: *Printer, extra_index: u32) []const u32 {
        if (extra_index == 0) return &.{};
        const s = p.tree.extraData(ast.Span, extra_index);
        return p.tree.span(s.start, s.end);
    }

    // ---- output

    fn snap(p: *Printer) Snap {
        return .{
            .out = p.out.items.len,
            .cur = p.cur,
            .indent = p.indent,
            .bol = p.bol,
            .want_blank = p.want_blank,
            .line_start = p.line_start,
            .code_start = p.code_start,
            .line_brackets = p.line_brackets,
            .pending = p.pending,
            .breaks = p.breaks.items.len,
            .marks = p.marks.items.len,
            .flats = p.flats.items.len,
            .flat_depth = p.flat_depth,
            .log = p.log.items.len,
        };
    }

    fn restore(p: *Printer, s: Snap) void {
        p.out.shrinkRetainingCapacity(s.out);
        p.cur = s.cur;
        p.indent = s.indent;
        p.bol = s.bol;
        p.want_blank = s.want_blank;
        p.line_start = s.line_start;
        p.code_start = s.code_start;
        p.line_brackets = s.line_brackets;
        p.pending = s.pending;
        // A snapshot taken mid-line saw these lists grow only; one taken at the start
        // of a line sees them cleared before they are read again.
        p.breaks.shrinkRetainingCapacity(@min(s.breaks, p.breaks.items.len));
        p.marks.shrinkRetainingCapacity(@min(s.marks, p.marks.items.len));
        p.flats.shrinkRetainingCapacity(@min(s.flats, p.flats.items.len));
        p.flat_depth = s.flat_depth;
        for (p.log.items[s.log..]) |k| p.emitted[k] = false;
        p.log.shrinkRetainingCapacity(s.log);
    }

    /// Prints one line-starting construct, again from its start when a line in it
    /// needs a one-line form turned into a block.
    fn line(p: *Printer, comptime f: fn (*Printer, Index) E!void, i: Index) E!void {
        const s = p.snap();
        while (true) {
            if (f(p, i)) |_| return else |err| {
                if (err == error.Refit and p.refit_at >= s.out) {
                    p.restore(s);
                    continue;
                }
                return err;
            }
        }
    }

    fn startLine(p: *Printer) E!void {
        if (!p.bol) return;
        if (p.want_blank and p.out.items.len > 0) try p.out.append(p.gpa, '\n');
        p.want_blank = false;
        p.line_start = p.out.items.len;
        try p.out.appendNTimes(p.gpa, ' ', p.indent * 2);
        p.code_start = p.out.items.len;
        p.bol = false;
        p.line_brackets = 0;
        p.breaks.clearRetainingCapacity();
        p.marks.clearRetainingCapacity();
        p.flats.clearRetainingCapacity();
    }

    fn text(p: *Printer, s: []const u8) E!void {
        try p.startLine();
        try p.out.appendSlice(p.gpa, s);
    }

    fn sp(p: *Printer) E!void {
        try p.text(" ");
    }

    fn emitComment(p: *Printer, k: u32) E!void {
        const c = p.tv.comments[k];
        try p.out.appendSlice(p.gpa, p.tree.source[c.start..c.end]);
        p.emitted[k] = true;
        try p.log.append(p.gpa, k);
    }

    fn nl(p: *Printer) E!void {
        if (p.flat_depth > 0) return error.NotFlat;
        try p.startLine();
        const code = p.out.items[p.code_start..];
        if (p.indent * 2 + cols(code) > limit) {
            const plan = try p.planBreaks();
            // A one-line arm (C1) moves its body below before its line breaks. A one-line
            // anonymous function (S8) or `if` value (I2) stays one line when breaking around
            // it makes every piece fit, and takes its block form when that is not enough.
            var keep = plan.fits;
            for (p.flats.items) |f| switch (p.node(f).kind) {
                .anon_fn, .if_expr, .if_stmt => {},
                else => keep = false,
            };
            if (p.flats.items.len > 0 and !keep) {
                p.forced[p.flats.items[0]] = true;
                p.refit_at = p.line_start;
                return error.Refit;
            }
            if (plan.at.len > 0) try p.applyBreaks(plan.at);
        }
        if (p.pending != 0) {
            try p.out.appendSlice(p.gpa, "  ");
            try p.emitComment(p.pending - 1);
            p.pending = 0;
        }
        try p.out.append(p.gpa, '\n');
        p.bol = true;
    }

    /// L5: the commas a line over the limit breaks after, and whether every piece then fits.
    fn planBreaks(p: *Printer) E!Plan {
        const base = p.code_start;
        const code = p.out.items[base..];
        // Each comma's depth and innermost bracket, from the brackets written before it; a
        // bracket that closes one opened on a line above closes nothing here.
        var cuts: std.ArrayList(Cut) = .empty;
        var open: std.ArrayList(Mark) = .empty;
        var m: usize = 0;
        for (p.breaks.items) |abs| {
            while (m < p.marks.items.len and p.marks.items[m].at < abs) : (m += 1) {
                const mark = p.marks.items[m];
                if (mark.open) try open.append(p.gpa, mark) else _ = open.pop();
            }
            const inner = open.getLastOrNull() orelse continue;
            try cuts.append(p.gpa, .{ .at = abs - base, .depth = @intCast(open.items.len), .group = inner.at, .list = inner.list });
        }
        var at: std.ArrayList(usize) = .empty;
        const fits = try p.cutPiece(code, cuts.items, 0, code.len, p.indent * 2, &at);
        std.mem.sort(usize, at.items, {}, std.sort.asc(usize));
        return .{ .at = at.items, .fits = fits };
    }

    /// Breaks `code[from..to]`, which starts `width` columns in, after its outermost commas,
    /// each piece as late as still fits, so a nested call is split only when breaking outside
    /// it is not enough. A list broken after any comma is broken after all of them, one
    /// element per line. A piece that still does not fit breaks one level in. True when every
    /// piece fits.
    fn cutPiece(p: *Printer, code: []const u8, cuts: []const Cut, from: usize, to: usize, width: usize, at: *std.ArrayList(usize)) E!bool {
        if (width + cols(code[from..to]) <= limit) return true;
        var depth: u32 = std.math.maxInt(u32);
        for (cuts) |c| {
            if (c.at > from and c.at < to) depth = @min(depth, c.depth);
        }
        if (depth == std.math.maxInt(u32)) return false;
        const cont = (p.indent + 1) * 2;
        // The lists broken one element per line, by their `[`.
        var lists: std.ArrayList(usize) = .empty;
        var picks: std.ArrayList(usize) = .empty;
        while (true) {
            picks.clearRetainingCapacity();
            var seg = from;
            var w = width;
            while (true) {
                const rest_fits = w + cols(code[seg..to]) <= limit;
                var pick: ?usize = null;
                for (cuts, 0..) |c, k| {
                    if (c.depth != depth or c.at <= seg or c.at >= to) continue;
                    const every = c.list and std.mem.indexOfScalar(usize, lists.items, c.group) != null;
                    if (rest_fits and !every) continue;
                    const fits = w + cols(code[seg..c.at]) <= limit;
                    if (fits or pick == null) pick = k;
                    if (!fits or every) break;
                }
                const k = pick orelse break;
                try picks.append(p.gpa, k);
                seg = cuts[k].at + 1;
                w = cont;
            }
            var grew = false;
            for (picks.items) |k| {
                if (cuts[k].list and std.mem.indexOfScalar(usize, lists.items, cuts[k].group) == null) {
                    try lists.append(p.gpa, cuts[k].group);
                    grew = true;
                }
            }
            if (!grew) break;
        }
        var fits = true;
        var seg = from;
        var w = width;
        for (picks.items) |k| {
            try at.append(p.gpa, cuts[k].at);
            if (!try p.cutPiece(code, cuts, seg, cuts[k].at, w, at)) fits = false;
            seg = cuts[k].at + 1;
            w = cont;
        }
        if (!try p.cutPiece(code, cuts, seg, to, w, at)) fits = false;
        return fits;
    }

    /// The line again, broken after each comma in `at`, each continuation one level deeper.
    fn applyBreaks(p: *Printer, at: []const usize) E!void {
        const base = p.code_start;
        const code = try p.gpa.dupe(u8, p.out.items[base..]);
        p.out.shrinkRetainingCapacity(base);
        var seg: usize = 0;
        for (at) |b| {
            try p.out.appendSlice(p.gpa, code[seg..b]);
            try p.out.append(p.gpa, '\n');
            try p.out.appendNTimes(p.gpa, ' ', (p.indent + 1) * 2);
            seg = b + 1;
        }
        try p.out.appendSlice(p.gpa, code[seg..]);
    }

    fn leading(p: *Printer, t: u32) E!void {
        const lead = p.tv.lead[t];
        var k = lead.start;
        while (k < lead.end) : (k += 1) {
            if (p.emitted[k]) continue;
            if (!p.bol or p.flat_depth > 0) {
                p.bad_comment = k;
                return error.CommentInside;
            }
            if (k > lead.start and p.tv.comments[k].blank_before) p.want_blank = true;
            try p.startLine();
            try p.emitComment(k);
            try p.out.append(p.gpa, '\n');
            p.bol = true;
        }
    }

    // ---- tokens

    fn skipNewlines(p: *Printer, from: u32) u32 {
        var i = from;
        while (p.tree.tokens[i].kind == .newline) i += 1;
        return i;
    }

    fn peek(p: *Printer) u32 {
        return p.skipNewlines(p.cur);
    }

    fn writeTok(p: *Printer, i: u32) E!void {
        if (p.pending != 0) {
            p.bad_comment = p.pending - 1;
            return error.CommentInside;
        }
        try p.leading(i);
        try p.text(p.tree.tokenText(i));
        switch (p.tree.tokens[i].kind) {
            .l_paren, .l_bracket => |kind| {
                try p.marks.append(p.gpa, .{ .at = p.out.items.len - 1, .open = true, .list = kind == .l_bracket });
                p.line_brackets += 1;
            },
            .r_paren, .r_bracket => {
                try p.marks.append(p.gpa, .{ .at = p.out.items.len - 1, .open = false, .list = false });
                p.line_brackets -|= 1;
            },
            else => {},
        }
        p.cur = i + 1;
        p.pending = p.tv.trail[i];
    }

    /// Prints the token at the cursor, with the grouping parens around it. `kind` is
    /// what the tree says comes next; null accepts any token.
    fn tk(p: *Printer, kind: ?Kind) E!u32 {
        var i = p.peek();
        while (p.tv.group_open[i]) {
            try p.writeTok(i);
            i = p.peek();
        }
        if (kind) |k| if (p.tree.tokens[i].kind != k) {
            std.debug.panic("fmt: expected {t} at byte {d}, found {t}", .{ k, p.tree.tokens[i].start, p.tree.tokens[i].kind });
        };
        try p.writeTok(i);
        var j = p.peek();
        while (p.tv.group_close[j]) {
            try p.writeTok(j);
            j = p.peek();
        }
        return i;
    }

    /// Steps over tokens the shape leaves out (S10), which must carry no comment.
    fn skip(p: *Printer, kind: Kind) E!void {
        const i = p.peek();
        std.debug.assert(p.tree.tokens[i].kind == kind);
        const lead = p.tv.lead[i];
        if (lead.end > lead.start) {
            p.bad_comment = lead.start;
            return error.CommentInside;
        }
        if (p.tv.trail[i] != 0) {
            p.bad_comment = p.tv.trail[i] - 1;
            return error.CommentInside;
        }
        p.cur = i + 1;
    }

    fn op(p: *Printer, kind: ?Kind) E!void {
        try p.sp();
        _ = try p.tk(kind);
        try p.sp();
    }

    fn comma(p: *Printer) E!void {
        _ = try p.tk(.comma);
        // A one-line anonymous function is never broken inside (S8).
        if (p.line_brackets > 0 and p.flat_depth == 0) try p.breaks.append(p.gpa, p.out.items.len);
        try p.sp();
    }

    /// K2: the comments above an `end` or `else` sit at the block's own indent.
    fn closeBlock(p: *Printer, kind: Kind) E!void {
        try p.leading(p.peek());
        p.indent -= 1;
        _ = try p.tk(kind);
    }

    // ---- §2 module

    fn module(p: *Printer) E!void {
        const root = p.node(0);
        const items = p.tree.span(root.lhs, root.rhs);
        var i: usize = 0;
        var prev: ?Node.Kind = null;
        while (i < items.len) {
            const kind = p.node(items[i]).kind;
            if (prev) |pk| {
                if (!(pk == .module_decl and kind == .expose)) p.want_blank = true;
            }
            prev = kind;
            if (kind == .use) {
                var j = i;
                while (j < items.len and p.node(items[j]).kind == .use) j += 1;
                try p.uses(items[i..j]);
                i = j;
                continue;
            }
            try p.line(item, items[i]);
            i += 1;
        }
        const eof = p.tv.eof;
        if (p.tv.lead[eof].end > p.tv.lead[eof].start) {
            p.want_blank = p.tv.blank[eof];
            p.indent = 0;
            try p.leading(eof);
        }
    }

    /// O2 and K6: sorted by path, each line with its comments.
    fn uses(p: *Printer, group: []const u32) E!void {
        const sorted = try p.gpa.dupe(u32, group);
        std.mem.sort(u32, sorted, p, struct {
            fn lt(pr: *Printer, a: u32, b: u32) bool {
                return std.mem.lessThan(u8, pr.pathText(pr.node(a).lhs), pr.pathText(pr.node(b).lhs));
            }
        }.lt);
        var end: u32 = p.cur;
        for (sorted) |u| {
            p.cur = p.node(u).main_token;
            try p.line(item, u);
            end = @max(end, p.cur);
        }
        p.cur = end;
    }

    fn pathText(p: *Printer, path_node: Index) []const u8 {
        const n = p.node(path_node);
        return p.tree.source[p.tree.tokens[n.main_token].start..p.tree.tokens[n.lhs].end];
    }

    fn path(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        // `none` in a signature is a lowercase name standing alone (step 24).
        if (p.tree.tokens[n.main_token].kind == .ident) {
            _ = try p.tk(.ident);
            return;
        }
        var last = try p.tk(.type_name);
        while (last != n.lhs) {
            _ = try p.tk(.dot);
            last = try p.tk(.type_name);
        }
    }

    fn item(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        switch (n.kind) {
            .module_decl => {
                _ = try p.tk(.kw_module);
                try p.sp();
                try p.path(n.lhs);
            },
            .expose => {
                _ = try p.tk(.kw_expose);
                try p.sp();
                for (p.tree.span(n.lhs, n.rhs), 0..) |_, k| {
                    if (k > 0) try p.comma();
                    _ = try p.tk(null);
                }
            },
            .use => {
                _ = try p.tk(.kw_use);
                try p.sp();
                try p.path(n.lhs);
                if (n.rhs != 0) {
                    _ = try p.tk(.l_brace);
                    for (p.spanAt(n.rhs), 0..) |_, k| {
                        if (k > 0) try p.comma();
                        _ = try p.tk(null);
                    }
                    _ = try p.tk(.r_brace);
                }
            },
            .intent => {
                _ = try p.tk(.kw_intent);
                try p.sp();
                _ = try p.tk(.string);
            },
            .never => {
                _ = try p.tk(.kw_never);
                try p.sp();
                _ = try p.tk(.string);
                try p.nl();
                p.indent += 1;
                try p.line(exprLine, n.rhs);
                try p.closeBlock(.kw_end);
            },
            .verified => try p.verified(),
            .struct_decl, .enum_decl => {
                _ = try p.tk(if (n.kind == .struct_decl) .kw_struct else .kw_enum);
                try p.sp();
                _ = try p.tk(.type_name);
                try p.nl();
                p.indent += 1;
                for (p.tree.span(n.lhs, n.rhs)) |f| {
                    if (n.kind == .struct_decl) try p.line(fieldLine, f) else try p.line(variantLine, f);
                }
                try p.closeBlock(.kw_end);
            },
            .type_decl => {
                _ = try p.tk(.kw_type);
                try p.sp();
                _ = try p.tk(.type_name);
                try p.op(.eq);
                try p.typ(n.lhs);
            },
            .trait_decl => {
                _ = try p.tk(.kw_trait);
                try p.sp();
                _ = try p.tk(.type_name);
                try p.nl();
                p.indent += 1;
                for (p.tree.span(n.lhs, n.rhs)) |s| try p.line(signatureLine, s);
                try p.closeBlock(.kw_end);
            },
            .impl_decl => {
                _ = try p.tk(.kw_impl);
                try p.sp();
                _ = try p.tk(.type_name);
                try p.op(.kw_for);
                try p.typ(n.lhs);
                try p.nl();
                p.indent += 1;
                for (p.spanAt(n.rhs), 0..) |f, k| {
                    if (k > 0) p.want_blank = true; // B10
                    try p.line(fnDecl, f);
                }
                try p.closeBlock(.kw_end);
            },
            .fn_decl => return p.fnDecl(i),
            .fn_signature => {
                // A recipe's body-less signature: its contracts, then `end`.
                try p.signature(i);
                try p.nl();
                p.indent += 1;
                const sig = p.tree.extraData(ast.Signature, n.lhs);
                for (p.tree.span(sig.contracts_start, sig.contracts_end)) |c| try p.line(stmtLine, c);
                try p.closeBlock(.kw_end);
            },
            .process_decl => try p.process(i),
            .supervisor_decl => {
                _ = try p.tk(.kw_supervisor);
                try p.sp();
                _ = try p.tk(.type_name);
                try p.paramsOrNothing(p.spanAt(n.lhs));
                try p.nl();
                p.indent += 1;
                for (p.spanAt(n.rhs)) |c| try p.line(childLine, c);
                try p.closeBlock(.kw_end);
            },
            .recipe_decl => {
                const data = p.tree.extraData(ast.Recipe, n.lhs);
                _ = try p.tk(.kw_recipe);
                try p.sp();
                _ = try p.tk(.type_name);
                try p.nl();
                p.indent += 1;
                try p.line(item, data.intent);
                try p.line(item, data.needs);
                for (p.tree.span(data.sigs_start, data.sigs_end)) |s| try p.line(item, s);
                for (p.tree.span(data.nevers_start, data.nevers_end)) |nv| try p.line(item, nv);
                for (p.tree.span(data.tests_start, data.tests_end)) |t| try p.line(item, t);
                try p.closeBlock(.kw_end);
            },
            .needs => {
                _ = try p.tk(.kw_needs);
                try p.sp();
                const names = p.tree.span(n.lhs, n.rhs);
                if (names.len == 0) _ = try p.tk(.ident);
                for (names, 0..) |_, k| {
                    if (k > 0) try p.comma();
                    _ = try p.tk(.type_name);
                }
            },
            .test_decl, .test_rejects => {
                _ = try p.tk(.kw_test);
                try p.sp();
                if (n.kind == .test_rejects) {
                    _ = try p.tk(.kw_rejects);
                    try p.sp();
                }
                _ = try p.tk(.string);
                try p.nl();
                p.indent += 1;
                try p.block(p.tree.span(n.lhs, n.rhs));
                try p.closeBlock(.kw_end);
            },
            .property => {
                _ = try p.tk(.kw_property);
                try p.sp();
                _ = try p.tk(.string);
                try p.nl();
                p.indent += 1;
                try p.line(exprLine, n.lhs);
                try p.closeBlock(.kw_end);
            },
            else => unreachable,
        }
        try p.nl();
    }

    /// The `verified:` line's text, and its `proven:` line, are the toolchain's, printed
    /// as written (N2).
    fn verified(p: *Printer) E!void {
        const kw = try p.tk(.kw_verified);
        const toks = p.tree.tokens;
        var last = kw;
        var i = kw + 1;
        while (toks[i].kind != .newline and toks[i].kind != .eof) : (i += 1) last = i;
        if (toks[i].kind == .newline and toks[i + 1].kind == .ident and std.mem.eql(u8, p.tree.tokenText(i + 1), "proven")) {
            i += 1;
            while (toks[i].kind != .newline and toks[i].kind != .eof) : (i += 1) last = i;
        }
        try p.text(p.tree.source[toks[kw].end..toks[last].end]);
        p.cur = last + 1;
        p.pending = p.tv.trail[last];
    }

    fn fieldLine(p: *Printer, i: Index) E!void {
        try p.field(i);
        try p.nl();
    }

    fn field(p: *Printer, i: Index) E!void {
        _ = try p.tk(null); // a name, or `state` or `old` in a struct (step 25)
        _ = try p.tk(.colon);
        try p.sp();
        try p.typ(p.node(i).lhs);
    }

    fn fieldList(p: *Printer, fields: []const u32) E!void {
        _ = try p.tk(.l_paren);
        for (fields, 0..) |f, k| {
            if (k > 0) try p.comma();
            try p.field(f);
        }
        _ = try p.tk(.r_paren);
    }

    fn variantLine(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        _ = try p.tk(.type_name);
        if (n.rhs > n.lhs) try p.fieldList(p.tree.span(n.lhs, n.rhs));
        try p.nl();
    }

    // ---- §3 types

    fn typ(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        switch (n.kind) {
            .type_ref => {
                try p.path(n.lhs);
                if (n.rhs != 0) {
                    _ = try p.tk(.l_paren);
                    for (p.spanAt(n.rhs), 0..) |a, k| {
                        if (k > 0) try p.comma();
                        try p.typ(a);
                    }
                    _ = try p.tk(.r_paren);
                }
            },
            .type_tuple => {
                _ = try p.tk(.l_paren);
                for (p.tree.span(n.lhs, n.rhs), 0..) |e, k| {
                    if (k > 0) try p.comma();
                    try p.typ(e);
                }
                _ = try p.tk(.r_paren);
            },
            .type_refined => {
                try p.typ(n.lhs);
                try p.op(.kw_where);
                try p.expr(n.rhs);
            },
            else => unreachable,
        }
    }

    // ---- §4 functions and contracts

    fn signatureLine(p: *Printer, i: Index) E!void {
        try p.signature(i);
        try p.nl();
    }

    fn signature(p: *Printer, i: Index) E!void {
        const sig = p.tree.extraData(ast.Signature, p.node(i).lhs);
        _ = try p.tk(.kw_fn);
        try p.sp();
        _ = try p.tk(.ident);
        _ = try p.tk(.l_paren);
        for (p.tree.span(sig.params_start, sig.params_end), 0..) |a, k| {
            if (k > 0) try p.comma();
            try p.param(a);
        }
        _ = try p.tk(.r_paren);
        // `fn main(platform: Platform)` has no return type (grammar §2).
        if (sig.ret != ast.none) {
            try p.op(.colon);
            try p.typ(sig.ret);
        }
        for (p.tree.span(sig.bounds_start, sig.bounds_end), 0..) |b, k| {
            if (k == 0) try p.op(.kw_where) else try p.comma();
            _ = try p.tk(.type_name);
            _ = try p.tk(.colon);
            try p.sp();
            try p.path(p.node(b).lhs);
        }
    }

    fn param(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        if (n.kind == .param_inout) {
            _ = try p.tk(.kw_inout);
            try p.sp();
        }
        _ = try p.tk(.ident);
        _ = try p.tk(.colon);
        try p.sp();
        try p.typ(n.lhs);
        if (n.rhs != 0) {
            try p.op(.eq);
            try p.expr(n.rhs);
        }
    }

    /// S10: a supervisor or child with nothing to pass writes no parentheses.
    fn paramsOrNothing(p: *Printer, params: []const u32) E!void {
        if (params.len == 0) {
            if (p.tree.tokens[p.peek()].kind == .l_paren) {
                try p.skip(.l_paren);
                try p.skip(.r_paren);
            }
            return;
        }
        _ = try p.tk(.l_paren);
        for (params, 0..) |a, k| {
            if (k > 0) try p.comma();
            try p.param(a);
        }
        _ = try p.tk(.r_paren);
    }

    fn fnDecl(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        const sig = p.tree.extraData(ast.Signature, n.lhs);
        const body = p.tree.extraData(ast.FnBody, n.rhs);
        try p.signature(i);
        try p.nl();
        p.indent += 1;
        const contracts = p.tree.span(sig.contracts_start, sig.contracts_end);
        for (contracts) |c| try p.line(stmtLine, c);
        const stmts = p.tree.span(body.start, body.end);
        if (contracts.len > 0 and stmts.len > 0) p.want_blank = true; // B6
        try p.block(stmts);
        try p.closeBlock(.kw_end);
        try p.nl();
    }

    // ---- §5 statements

    /// B7: statements keep one blank line where the author left any.
    fn block(p: *Printer, stmts: []const u32) E!void {
        for (stmts, 0..) |s, k| {
            if (k > 0 and p.tv.blank[p.peek()]) p.want_blank = true;
            try p.line(stmtLine, s);
        }
    }

    fn stmtLine(p: *Printer, i: Index) E!void {
        try p.stmt(i);
        try p.nl();
    }

    fn exprLine(p: *Printer, i: Index) E!void {
        try p.expr(i);
        try p.nl();
    }

    fn stmt(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        switch (n.kind) {
            .binding => {
                _ = try p.tk(.ident);
                try p.op(.eq);
                try p.expr(n.lhs);
            },
            .var_binding => {
                _ = try p.tk(.kw_var);
                try p.sp();
                _ = try p.tk(.ident);
                try p.op(.eq);
                try p.expr(n.lhs);
            },
            .assign => {
                try p.expr(n.lhs);
                try p.op(null);
                try p.expr(n.rhs);
            },
            .return_stmt => {
                _ = try p.tk(.kw_return);
                try p.sp();
                try p.expr(n.lhs);
                if (n.rhs != 0) {
                    try p.op(.kw_if);
                    try p.expr(n.rhs);
                }
            },
            .for_stmt => {
                _ = try p.tk(.kw_for);
                try p.sp();
                _ = try p.tk(null); // a name, or `_`
                try p.op(.kw_in);
                try p.expr(n.lhs);
                try p.nl();
                p.indent += 1;
                try p.block(p.spanAt(n.rhs));
                try p.closeBlock(.kw_end);
            },
            .requires, .ensures => {
                _ = try p.tk(null);
                try p.sp();
                try p.expr(n.lhs);
            },
            .assert_stmt => {
                _ = try p.tk(.kw_assert);
                try p.sp();
                try p.expr(n.lhs);
            },
            .break_stmt => _ = try p.tk(.kw_break),
            .expr_stmt => try p.expr(n.lhs),
            .if_stmt => try p.ifNode(i),
            .case_stmt => try p.caseNode(i),
            else => unreachable,
        }
    }

    /// An `if` as a block, or an `if` value on one line when it may be (I1–I3). The block
    /// form printed from a one-line source steps over its colons and writes its `end`.
    fn ifNode(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        // A one-line `if` that starts a line is a value there too (step 26) and keeps its line as
        // any `if` value does (I1–I3); a block `if` there stays a block (I4).
        const line_start = n.kind == .if_stmt and p.tree.tokens[n.main_token - 1].kind == .newline and p.tree.lineIfColon(n.main_token) != null;
        if ((n.kind == .if_expr or line_start) and !p.forced[i] and p.lineShaped(i)) {
            if (try p.attemptIf(i)) return;
        }
        const data = p.tree.extraData(ast.If, n.rhs);
        _ = try p.tk(.kw_if);
        try p.sp();
        try p.expr(n.lhs);
        const one_line = p.tree.tokens[p.peek()].kind == .colon;
        if (one_line) try p.skip(.colon);
        try p.nl();
        p.indent += 1;
        try p.block(p.tree.span(data.then_start, data.then_end));
        if (p.tree.tokens[p.peek()].kind == .kw_else) {
            try p.closeBlock(.kw_else);
            if (one_line) try p.skip(.colon);
            try p.nl();
            p.indent += 1;
            try p.block(p.tree.span(data.else_start, data.else_end));
        }
        if (one_line) {
            p.indent -= 1;
            try p.text("end");
        } else try p.closeBlock(.kw_end);
    }

    /// I1: an `if` value whose branches are one expression each, the else branch possibly an
    /// `if` of the same shape (an else-if chain), in either form in the source: the two forms
    /// are one tree, so the formatter picks the shape.
    fn lineShaped(p: *Printer, i: Index) bool {
        const data = p.tree.extraData(ast.If, p.node(i).rhs);
        const then = p.tree.span(data.then_start, data.then_end);
        const otherwise = p.tree.span(data.else_start, data.else_end);
        if (then.len != 1 or otherwise.len != 1) return false;
        if (p.node(then[0]).kind != .expr_stmt) return false;
        return switch (p.node(otherwise[0]).kind) {
            .expr_stmt => true,
            .if_stmt => p.lineShaped(otherwise[0]),
            else => false,
        };
    }

    /// Tries the `if` value at `i` on the current line, as `attempt` does for an arm.
    fn attemptIf(p: *Printer, i: Index) E!bool {
        const s = p.snap();
        p.flat_depth += 1;
        p.flatIf(i) catch |err| switch (err) {
            error.NotFlat, error.CommentInside => {
                p.restore(s);
                return false;
            },
            else => return err,
        };
        p.flat_depth -= 1;
        try p.flats.append(p.gpa, i);
        return true;
    }

    /// `if cond: a else: b`, from either form of the source. From the block form, the `end`
    /// must close the expression: a one-line `if` takes everything after `else:` into its else
    /// branch, so `end.size` or `end + 1` would read differently on one line (I4). One comment
    /// after the else branch or after `end` ends the one line, as it ends a one-line source; any
    /// other comment inside keeps the block (I2).
    fn flatIf(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        const data = p.tree.extraData(ast.If, n.rhs);
        _ = try p.tk(.kw_if);
        try p.sp();
        try p.expr(n.lhs);
        const one_line = p.tree.tokens[p.peek()].kind == .colon;
        try p.lineColon();
        try p.sp();
        try p.expr(p.node(p.tree.span(data.then_start, data.then_end)[0]).lhs);
        try p.sp();
        _ = try p.tk(.kw_else);
        try p.lineColon();
        try p.sp();
        const otherwise = p.tree.span(data.else_start, data.else_end)[0];
        if (p.node(otherwise).kind == .if_stmt) try p.flatIf(otherwise) else try p.expr(p.node(otherwise).lhs);
        if (!one_line) try p.skipEnd();
    }

    /// Steps over a block `if`'s `end` that the one-line form leaves out.
    fn skipEnd(p: *Printer) E!void {
        const i = p.peek();
        std.debug.assert(p.tree.tokens[i].kind == .kw_end);
        switch (p.tree.tokens[i + 1].kind) {
            .newline, .eof, .comma, .r_paren, .r_bracket, .r_brace, .kw_end => {},
            else => return error.NotFlat,
        }
        const lead = p.tv.lead[i];
        if (lead.end > lead.start) {
            p.bad_comment = lead.start;
            return error.CommentInside;
        }
        if (p.tv.trail[i] != 0) {
            if (p.pending != 0) {
                p.bad_comment = p.pending - 1;
                return error.CommentInside;
            }
            p.pending = p.tv.trail[i];
        }
        p.cur = i + 1;
    }

    /// A one-line `if`'s `:`, the source's own when it has one.
    fn lineColon(p: *Printer) E!void {
        if (p.tree.tokens[p.peek()].kind == .colon) {
            _ = try p.tk(.colon);
        } else try p.text(":");
    }

    fn caseNode(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        _ = try p.tk(.kw_case);
        try p.sp();
        try p.expr(n.lhs);
        try p.nl();
        p.indent += 1;
        for (p.spanAt(n.rhs)) |a| try p.line(arm, a);
        try p.closeBlock(.kw_end);
    }

    /// C1–C3.
    fn arm(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        const data = p.tree.extraData(ast.Arm, n.rhs);
        try p.pattern(n.lhs);
        if (data.guard != 0) {
            try p.op(.kw_if);
            try p.expr(data.guard);
        }
        _ = try p.tk(.colon);
        const body = p.tree.span(data.body_start, data.body_end);
        if (body.len == 1 and p.node(body[0]).kind == .expr_stmt) {
            const e = p.node(body[0]).lhs;
            if (!p.forced[i]) {
                if (try p.attempt(i, e, false)) return p.nl();
            }
            switch (p.node(e).kind) {
                .case_expr, .if_expr => {
                    try p.sp();
                    try p.expr(e);
                    return p.nl();
                },
                else => {},
            }
        }
        try p.nl();
        p.indent += 1;
        try p.block(body);
        p.indent -= 1;
    }

    /// Tries ` expr` (and ` end` for an anonymous function) on the current line.
    /// On success the form is remembered for the line's width check.
    fn attempt(p: *Printer, owner: Index, e: Index, with_end: bool) E!bool {
        const s = p.snap();
        p.flat_depth += 1;
        const ok = flat: {
            p.flatBody(e, with_end) catch |err| switch (err) {
                error.NotFlat, error.CommentInside => break :flat false,
                else => return err,
            };
            break :flat true;
        };
        if (!ok) {
            p.restore(s);
            return false;
        }
        p.flat_depth -= 1;
        try p.flats.append(p.gpa, owner);
        return true;
    }

    fn flatBody(p: *Printer, e: Index, with_end: bool) E!void {
        try p.sp();
        try p.expr(e);
        if (with_end) {
            try p.sp();
            _ = try p.tk(.kw_end);
        }
    }

    // ---- §6 expressions

    fn expr(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        switch (n.kind) {
            .implies, .or_expr, .and_expr, .compare, .add, .mul => {
                try p.expr(n.lhs);
                try p.op(null);
                try p.expr(n.rhs);
            },
            .is_expr => {
                try p.expr(n.lhs);
                try p.op(.kw_is);
                try p.pattern(n.rhs);
            },
            .range => {
                try p.expr(n.lhs);
                _ = try p.tk(.dot_dot);
                try p.expr(n.rhs);
            },
            .not_expr, .negate => {
                _ = try p.tk(null);
                try p.expr(n.lhs);
            },
            .try_expr => {
                _ = try p.tk(.kw_try);
                try p.sp();
                try p.expr(n.lhs);
            },
            .member, .tuple_index => {
                try p.expr(n.lhs);
                _ = try p.tk(.dot);
                _ = try p.tk(null);
            },
            .member_call => {
                try p.expr(n.lhs);
                _ = try p.tk(.dot);
                _ = try p.tk(null);
                try p.args(n.rhs);
            },
            .call => {
                try p.expr(n.lhs);
                try p.args(n.rhs);
            },
            .named_arg => {
                _ = try p.tk(null); // a name, or `state` or `old` for a struct's field (step 25)
                _ = try p.tk(.colon);
                try p.sp();
                try p.expr(n.lhs);
            },
            .name_ref, .type_name_ref, .int_lit, .float_lit, .string_lit, .string_interp, .true_lit, .false_lit, .result_ref => _ = try p.tk(null),
            .tuple, .list => {
                _ = try p.tk(if (n.kind == .tuple) .l_paren else .l_bracket);
                for (p.tree.span(n.lhs, n.rhs), 0..) |e, k| {
                    if (k > 0) try p.comma();
                    try p.expr(e);
                }
                _ = try p.tk(if (n.kind == .tuple) .r_paren else .r_bracket);
            },
            .if_expr => try p.ifNode(i),
            .case_expr => try p.caseNode(i),
            .anon_fn => try p.anonFn(i),
            .old_expr => {
                _ = try p.tk(.kw_old);
                _ = try p.tk(.l_paren);
                try p.expr(n.lhs);
                _ = try p.tk(.r_paren);
            },
            .any_expr => {
                _ = try p.tk(.kw_any);
                _ = try p.tk(.l_paren);
                try p.typ(n.lhs);
                _ = try p.tk(.r_paren);
            },
            .comprehension => try p.comprehension(i),
            else => unreachable,
        }
    }

    fn args(p: *Printer, extra_index: u32) E!void {
        _ = try p.tk(.l_paren);
        for (p.spanAt(extra_index), 0..) |a, k| {
            if (k > 0) try p.comma();
            try p.expr(a);
        }
        _ = try p.tk(.r_paren);
    }

    /// S8.
    fn anonFn(p: *Printer, i: Index) E!void {
        const data = p.tree.extraData(ast.AnonFn, p.node(i).lhs);
        _ = try p.tk(.kw_fn);
        _ = try p.tk(.l_paren);
        for (p.tree.span(data.params_start, data.params_end), 0..) |tok, k| {
            if (k > 0) try p.comma();
            // `_` leaves a parameter unread (step 28).
            _ = try p.tk(if (p.tree.tokens[tok].kind == .underscore) .underscore else .ident);
        }
        _ = try p.tk(.r_paren);
        const body = p.tree.span(data.body_start, data.body_end);
        if (body.len == 1 and p.node(body[0]).kind == .expr_stmt) {
            const e = p.node(body[0]).lhs;
            if (!p.forced[i]) {
                if (try p.attempt(i, e, true)) return;
            }
            switch (p.node(e).kind) {
                // Moving these below `fn(x)` would parse as statements (C3's reason).
                .case_expr, .if_expr => return p.flatBody(e, true),
                else => {},
            }
        }
        try p.nl();
        p.indent += 1;
        try p.block(body);
        try p.closeBlock(.kw_end);
    }

    // ---- §7 patterns

    fn pattern(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        switch (n.kind) {
            .pat_wildcard, .pat_bind => _ = try p.tk(null),
            .pat_literal => {
                if (n.lhs != 0) _ = try p.tk(.minus);
                _ = try p.tk(null);
            },
            .pat_variant => {
                _ = try p.tk(.type_name);
                if (n.lhs != 0) {
                    _ = try p.tk(.l_paren);
                    try p.pattern(n.lhs);
                    _ = try p.tk(.r_paren);
                }
            },
            .pat_record => {
                _ = try p.tk(.type_name);
                _ = try p.tk(.l_paren);
                for (p.tree.span(n.lhs, n.rhs), 0..) |f, k| {
                    if (k > 0) try p.comma();
                    _ = try p.tk(.ident);
                    _ = try p.tk(.colon);
                    try p.sp();
                    try p.pattern(p.node(f).lhs);
                }
                _ = try p.tk(.r_paren);
            },
            .pat_tuple => {
                _ = try p.tk(.l_paren);
                for (p.tree.span(n.lhs, n.rhs), 0..) |e, k| {
                    if (k > 0) try p.comma();
                    try p.pattern(e);
                }
                _ = try p.tk(.r_paren);
            },
            // C5.
            .pat_or => for (p.tree.span(n.lhs, n.rhs), 0..) |alt, k| {
                if (k > 0) try p.op(.pipe);
                try p.pattern(alt);
            },
            else => unreachable,
        }
    }

    // ---- §8 comprehensions

    fn comprehension(p: *Printer, i: Index) E!void {
        const data = p.tree.extraData(ast.Comprehension, p.node(i).lhs);
        _ = try p.tk(.kw_for);
        try p.sp();
        for (p.tree.span(data.gens_start, data.gens_end), 0..) |g, k| {
            if (k > 0) try p.comma();
            _ = try p.tk(.ident);
            try p.op(.kw_in);
            try p.expr(p.node(g).lhs);
        }
        if (data.guard != 0) {
            try p.op(.kw_if);
            try p.expr(data.guard);
        }
        try p.nl();
        p.indent += 1;
        try p.block(p.tree.span(data.body_start, data.body_end));
        try p.closeBlock(.kw_end);
    }

    // ---- §9 processes and supervisors

    /// B8.
    fn process(p: *Printer, i: Index) E!void {
        const data = p.tree.extraData(ast.Process, p.node(i).lhs);
        _ = try p.tk(.kw_process);
        try p.sp();
        _ = try p.tk(.type_name);
        _ = try p.tk(.l_paren);
        for (p.tree.span(data.params_start, data.params_end), 0..) |a, k| {
            if (k > 0) try p.comma();
            try p.param(a);
        }
        _ = try p.tk(.r_paren);
        if (data.mailbox != 0) {
            try p.sp();
            _ = try p.tk(.ident);
            _ = try p.tk(.colon);
            try p.sp();
            _ = try p.tk(.int);
        }
        try p.nl();
        p.indent += 1;
        try p.line(stateBlock, data.state);
        p.want_blank = true;
        for (p.tree.span(data.invariants_start, data.invariants_end)) |inv| {
            try p.line(invariant, inv);
            p.want_blank = true;
        }
        for (p.tree.span(data.messages_start, data.messages_end)) |m| try p.line(message, m);
        p.want_blank = true;
        try p.line(update, data.update);
        try p.closeBlock(.kw_end);
    }

    fn stateBlock(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        _ = try p.tk(.kw_state);
        try p.nl();
        p.indent += 1;
        for (p.tree.span(n.lhs, n.rhs)) |f| try p.line(stateField, f);
        try p.closeBlock(.kw_end);
        try p.nl();
    }

    fn stateField(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        try p.field(i);
        if (n.rhs != 0) {
            try p.op(.eq);
            try p.expr(n.rhs);
        }
        try p.nl();
    }

    fn invariant(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        _ = try p.tk(.kw_invariant);
        try p.sp();
        _ = try p.tk(.string);
        try p.nl();
        p.indent += 1;
        try p.line(exprLine, n.rhs);
        try p.closeBlock(.kw_end);
        try p.nl();
    }

    fn message(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        _ = try p.tk(.kw_message);
        try p.sp();
        _ = try p.tk(.type_name);
        if (n.lhs != 0) try p.fieldList(p.spanAt(n.lhs));
        if (n.rhs != 0) {
            try p.op(.colon);
            try p.typ(n.rhs);
        }
        try p.nl();
    }

    fn update(p: *Printer, i: Index) E!void {
        const n = p.node(i);
        _ = try p.tk(.kw_fn);
        try p.sp();
        _ = try p.tk(.ident);
        _ = try p.tk(.l_paren);
        _ = try p.tk(.kw_state);
        try p.comma();
        _ = try p.tk(.kw_message);
        _ = try p.tk(.r_paren);
        try p.nl();
        p.indent += 1;
        try p.line(stmtLine, n.lhs);
        try p.closeBlock(.kw_end);
        try p.nl();
    }

    fn childLine(p: *Printer, i: Index) E!void {
        const data = p.tree.extraData(ast.Child, p.node(i).lhs);
        _ = try p.tk(.kw_child);
        try p.sp();
        _ = try p.tk(.type_name);
        const child_args = p.tree.span(data.args_start, data.args_end);
        if (child_args.len == 0) {
            if (p.tree.tokens[p.peek()].kind == .l_paren) {
                try p.skip(.l_paren);
                try p.skip(.r_paren);
            }
        } else {
            _ = try p.tk(.l_paren);
            for (child_args, 0..) |a, k| {
                if (k > 0) try p.comma();
                try p.expr(a);
            }
            _ = try p.tk(.r_paren);
        }
        try p.comma();
        _ = try p.tk(.ident);
        _ = try p.tk(.colon);
        try p.sp();
        _ = try p.tk(.atom);
        if (data.max_restarts != 0) {
            try p.comma();
            _ = try p.tk(.ident);
            _ = try p.tk(.colon);
            try p.sp();
            _ = try p.tk(.int);
            try p.op(.kw_per);
            try p.expr(data.per);
        }
        try p.nl();
    }
};

/// Characters, for the column limit.
fn cols(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

// ---- the tree as text, for the faithfulness property

/// The tree under `i` as an S-expression of node kinds and token texts, with no
/// positions, so two parses of differently spaced text compare equal exactly when
/// their trees are the same.
pub fn dump(w: *std.Io.Writer, tree: ast.Tree, i: Index) std.Io.Writer.Error!void {
    const n = tree.nodes[i];
    try w.print("({t}", .{n.kind});
    if (n.kind == .string_part) {
        try w.print(" \"{s}\")", .{tree.source[n.lhs..n.rhs]});
        return;
    }
    if (n.kind != .root) try w.print(" {s}", .{tree.tokenText(n.main_token)});
    const D = struct {
        fn nodes(wr: *std.Io.Writer, t: ast.Tree, s: u32, e: u32) std.Io.Writer.Error!void {
            try wr.writeAll(" [");
            for (t.span(s, e)) |c| try dump(wr, t, c);
            try wr.writeAll("]");
        }
        fn nodesAt(wr: *std.Io.Writer, t: ast.Tree, extra_index: u32) std.Io.Writer.Error!void {
            if (extra_index == 0) return wr.writeAll(" -");
            const sp = t.extraData(ast.Span, extra_index);
            try nodes(wr, t, sp.start, sp.end);
        }
        fn toks(wr: *std.Io.Writer, t: ast.Tree, s: u32, e: u32) std.Io.Writer.Error!void {
            try wr.writeAll(" [");
            for (t.span(s, e)) |c| try wr.print(" {s}", .{t.tokenText(c)});
            try wr.writeAll("]");
        }
        fn one(wr: *std.Io.Writer, t: ast.Tree, c: u32) std.Io.Writer.Error!void {
            if (c == 0) return wr.writeAll(" -");
            try dump(wr, t, c);
        }
        fn tok(wr: *std.Io.Writer, t: ast.Tree, c: u32) std.Io.Writer.Error!void {
            if (c == 0) return wr.writeAll(" -");
            try wr.print(" {s}", .{t.tokenText(c)});
        }
        fn sig(wr: *std.Io.Writer, t: ast.Tree, extra_index: u32) std.Io.Writer.Error!void {
            const s = t.extraData(ast.Signature, extra_index);
            try nodes(wr, t, s.params_start, s.params_end);
            try one(wr, t, s.ret);
            try nodes(wr, t, s.bounds_start, s.bounds_end);
            try nodes(wr, t, s.contracts_start, s.contracts_end);
        }
    };
    switch (n.kind) {
        .root => {
            // O2 reorders the use lines, and nothing else: compare them as a set.
            var items: std.ArrayList([]const u8) = .empty;
            var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
            defer aw.deinit();
            defer {
                for (items.items) |u| std.heap.page_allocator.free(u);
                items.deinit(std.heap.page_allocator);
            }
            try w.writeAll(" [");
            for (tree.span(n.lhs, n.rhs)) |c| {
                if (tree.nodes[c].kind != .use) {
                    try dump(w, tree, c);
                    continue;
                }
                aw.clearRetainingCapacity();
                try dump(&aw.writer, tree, c);
                items.append(std.heap.page_allocator, std.heap.page_allocator.dupe(u8, aw.written()) catch return error.WriteFailed) catch return error.WriteFailed;
            }
            std.mem.sort([]const u8, items.items, {}, struct {
                fn lt(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.lessThan(u8, a, b);
                }
            }.lt);
            for (items.items) |u| try w.print("(uses {s})", .{u});
            try w.writeAll("]");
        },
        .struct_decl, .enum_decl, .trait_decl, .variant, .type_tuple, .string_interp, .tuple, .list, .pat_record, .pat_tuple, .pat_or, .state_block, .test_decl, .test_rejects => try D.nodes(w, tree, n.lhs, n.rhs),
        .expose, .needs => try D.toks(w, tree, n.lhs, n.rhs),
        .path => try D.tok(w, tree, n.lhs),
        .use => {
            try D.one(w, tree, n.lhs);
            if (n.rhs == 0) try w.writeAll(" -") else {
                const s = tree.extraData(ast.Span, n.rhs);
                try D.toks(w, tree, s.start, s.end);
            }
        },
        .intent => try D.tok(w, tree, n.lhs),
        .never, .invariant => {
            try D.tok(w, tree, n.lhs);
            try D.one(w, tree, n.rhs);
        },
        .module_decl, .field, .type_decl, .bound, .requires, .ensures, .binding, .var_binding, .assert_stmt, .expr_stmt => try D.one(w, tree, n.lhs),
        .not_expr, .negate, .try_expr, .member, .tuple_index, .named_arg, .old_expr, .any_expr, .pat_variant, .pat_field, .generator, .property, .update_fn => try D.one(w, tree, n.lhs),
        .impl_decl => {
            try D.one(w, tree, n.lhs);
            try D.nodesAt(w, tree, n.rhs);
        },
        .type_ref, .member_call, .call, .case_stmt, .case_expr, .for_stmt => {
            try D.one(w, tree, n.lhs);
            try D.nodesAt(w, tree, n.rhs);
        },
        .type_refined, .param, .param_inout, .assign, .return_stmt, .implies, .or_expr, .and_expr, .compare, .is_expr, .range, .add, .mul, .state_field, .message_decl => {
            if (n.kind == .message_decl) try D.nodesAt(w, tree, n.lhs) else try D.one(w, tree, n.lhs);
            try D.one(w, tree, n.rhs);
        },
        .fn_decl => {
            try D.sig(w, tree, n.lhs);
            const b = tree.extraData(ast.FnBody, n.rhs);
            try D.nodes(w, tree, b.start, b.end);
        },
        .fn_signature => try D.sig(w, tree, n.lhs),
        .if_stmt, .if_expr => {
            try D.one(w, tree, n.lhs);
            const d = tree.extraData(ast.If, n.rhs);
            try D.nodes(w, tree, d.then_start, d.then_end);
            try D.nodes(w, tree, d.else_start, d.else_end);
        },
        .arm => {
            try D.one(w, tree, n.lhs);
            const d = tree.extraData(ast.Arm, n.rhs);
            try D.one(w, tree, d.guard);
            try D.nodes(w, tree, d.body_start, d.body_end);
        },
        .anon_fn => {
            const d = tree.extraData(ast.AnonFn, n.lhs);
            try D.toks(w, tree, d.params_start, d.params_end);
            try D.nodes(w, tree, d.body_start, d.body_end);
        },
        .comprehension => {
            const d = tree.extraData(ast.Comprehension, n.lhs);
            try D.nodes(w, tree, d.gens_start, d.gens_end);
            try D.one(w, tree, d.guard);
            try D.nodes(w, tree, d.body_start, d.body_end);
        },
        .process_decl => {
            const d = tree.extraData(ast.Process, n.lhs);
            try D.nodes(w, tree, d.params_start, d.params_end);
            try D.tok(w, tree, d.mailbox);
            try D.one(w, tree, d.state);
            try D.nodes(w, tree, d.invariants_start, d.invariants_end);
            try D.nodes(w, tree, d.messages_start, d.messages_end);
            try D.one(w, tree, d.update);
        },
        .supervisor_decl => {
            try D.nodesAt(w, tree, n.lhs);
            try D.nodesAt(w, tree, n.rhs);
        },
        .child => {
            const d = tree.extraData(ast.Child, n.lhs);
            try D.nodes(w, tree, d.args_start, d.args_end);
            try D.tok(w, tree, d.restart);
            try D.tok(w, tree, d.max_restarts);
            try D.one(w, tree, d.per);
        },
        .recipe_decl => {
            const d = tree.extraData(ast.Recipe, n.lhs);
            try D.one(w, tree, d.intent);
            try D.one(w, tree, d.needs);
            try D.nodes(w, tree, d.sigs_start, d.sigs_end);
            try D.nodes(w, tree, d.nevers_start, d.nevers_end);
            try D.nodes(w, tree, d.tests_start, d.tests_end);
        },
        .verified, .break_stmt, .name_ref, .type_name_ref, .int_lit, .float_lit, .string_lit, .true_lit, .false_lit, .result_ref, .pat_wildcard, .pat_bind, .pat_literal, .string_part => {},
    }
    try w.writeAll(")");
}

/// The dump of a whole source, or null when it does not parse.
pub fn dumpSource(arena: std.mem.Allocator, source: []const u8) !?[]const u8 {
    var diags: diag.List = .empty;
    const tokens = lexer.lex(arena, source, &diags) catch |err| switch (err) {
        error.Rejected => return null,
        else => return err,
    };
    const tree = parser.parse(arena, source, tokens, &diags) catch |err| switch (err) {
        error.Rejected => return null,
        else => return err,
    };
    var aw: std.Io.Writer.Allocating = .init(arena);
    try dump(&aw.writer, tree, 0);
    return try aw.toOwnedSlice();
}

// ---- tests

fn expectFormat(input: []const u8, want: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    const got = format(arena, input, &diags) catch |err| {
        for (diags.items) |d| std.debug.print("{s} at {d}: {s}\n", .{ d.code, d.at, d.what });
        return err;
    };
    try std.testing.expectEqualStrings(want, got);
    // Both properties hold for every case here too.
    const again = try format(arena, got, &diags);
    try std.testing.expectEqualStrings(got, again);
    try std.testing.expectEqualStrings((try dumpSource(arena, input)).?, (try dumpSource(arena, got)).?);
}

test "spacing, blank lines at the top level, and use lines sorted" {
    try expectFormat(
        \\module   Shop.Cart
        \\
        \\expose total,Item
        \\use Shop.Tax{Rate}
        \\use Shop.Money{ Cents,Euro }
        \\intent "Sum a cart."
        \\struct Item
        \\
        \\  price : UInt32
        \\end
        \\
        \\
        \\fn total(items: List(Item),rate:Rate):UInt32
        \\  requires items.size<=100
        \\  ensures  result>=0
        \\  sum=items.reduce(0,fn(acc,x) acc+x.price end)
        \\
        \\
        \\  sum*(rate+1)
        \\end
        \\test "an empty cart"
        \\  assert total([],1)==0
        \\end
        \\
    ,
        \\module Shop.Cart
        \\expose total, Item
        \\
        \\use Shop.Money{Cents, Euro}
        \\use Shop.Tax{Rate}
        \\
        \\intent "Sum a cart."
        \\
        \\struct Item
        \\  price: UInt32
        \\end
        \\
        \\fn total(items: List(Item), rate: Rate) : UInt32
        \\  requires items.size <= 100
        \\  ensures result >= 0
        \\
        \\  sum = items.reduce(0, fn(acc, x) acc + x.price end)
        \\
        \\  sum * (rate + 1)
        \\end
        \\
        \\test "an empty cart"
        \\  assert total([], 1) == 0
        \\end
        \\
    );
}

test "comments stay attached, trailing comments stay on their line" {
    try expectFormat(
        \\# the header
        \\module M
        \\expose f
        \\intent "x"
        \\# about f
        \\
        \\# more about f
        \\fn f(n: UInt32) : UInt32   # trailing
        \\
        \\  # first
        \\  x = n    # two
        \\  if x > 1
        \\    x
        \\    # before else
        \\  else
        \\    0
        \\  # before end
        \\  end
        \\end
        \\# the last word
    ,
        \\# the header
        \\module M
        \\expose f
        \\
        \\intent "x"
        \\
        \\# about f
        \\
        \\# more about f
        \\fn f(n: UInt32) : UInt32  # trailing
        \\  # first
        \\  x = n  # two
        \\  if x > 1
        \\    x
        \\    # before else
        \\  else
        \\    0
        \\    # before end
        \\  end
        \\end
        \\# the last word
        \\
    );
}

test "arms on one line when they fit, blocks when they do not" {
    try expectFormat(
        \\module M
        \\fn f(n: Option(UInt32)) : UInt32
        \\  case n
        \\    Some(x):
        \\      x
        \\    None: 0
        \\  end
        \\end
        \\fn g(n: Option(UInt32)) : UInt32
        \\  case n
        \\    Some(x): aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa + x
        \\    None:
        \\      y = 1
        \\      y
        \\  end
        \\end
    ,
        \\module M
        \\
        \\fn f(n: Option(UInt32)) : UInt32
        \\  case n
        \\    Some(x): x
        \\    None: 0
        \\  end
        \\end
        \\
        \\fn g(n: Option(UInt32)) : UInt32
        \\  case n
        \\    Some(x):
        \\      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa + x
        \\    None:
        \\      y = 1
        \\      y
        \\  end
        \\end
        \\
    );
}

test "anonymous functions: one line when it fits, the block form otherwise" {
    try expectFormat(
        \\module M
        \\fn f(xs: List(UInt32)) : List(UInt32)
        \\  xs.filter(fn(x)
        \\    x > 0
        \\  end)
        \\end
        \\fn g(xs: List(UInt32)) : List(UInt32)
        \\  xs.map(fn(x) x + aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa end)
        \\end
    ,
        \\module M
        \\
        \\fn f(xs: List(UInt32)) : List(UInt32)
        \\  xs.filter(fn(x) x > 0 end)
        \\end
        \\
        \\fn g(xs: List(UInt32)) : List(UInt32)
        \\  xs.map(fn(x)
        \\    x + aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        \\  end)
        \\end
        \\
    );
}

test "a long line breaks after the latest comma that fits" {
    try expectFormat(
        \\module M
        \\fn f(aaaaaaaaaaaaaaaaaaaa: UInt32, bbbbbbbbbbbbbbbbbbbbbbbb: UInt32, cccccccccccccccccccccccc: UInt32, dddd: UInt32) : UInt32
        \\  aaaaaaaaaaaaaaaaaaaa
        \\end
    ,
        \\module M
        \\
        \\fn f(aaaaaaaaaaaaaaaaaaaa: UInt32, bbbbbbbbbbbbbbbbbbbbbbbb: UInt32,
        \\  cccccccccccccccccccccccc: UInt32, dddd: UInt32) : UInt32
        \\  aaaaaaaaaaaaaaaaaaaa
        \\end
        \\
    );
}

test "round 2: a long list breaks after its commas, one element per line when it does not fit" {
    try expectFormat(
        \\module M
        \\fn f(once: Tally, since: Option(Time)) : Tally
        \\  twice = add_lines(once, ["2026-09-12T10:00:02Z GET /a 200 3", "2026-09-12T10:00:09Z GET /a 503 2"], since)
        \\  lines = ["2026-09-12T10:00:01Z GET /a 500 1", "2026-09-12T10:00:02Z GET /a 200 3", "2026-09-12T10:00:09Z GET /a 503 2"]
        \\  add_lines(twice, lines, since)
        \\end
    ,
        \\module M
        \\
        \\fn f(once: Tally, since: Option(Time)) : Tally
        \\  twice = add_lines(once,
        \\    ["2026-09-12T10:00:02Z GET /a 200 3", "2026-09-12T10:00:09Z GET /a 503 2"], since)
        \\  lines = ["2026-09-12T10:00:01Z GET /a 500 1",
        \\    "2026-09-12T10:00:02Z GET /a 200 3",
        \\    "2026-09-12T10:00:09Z GET /a 503 2"]
        \\  add_lines(twice, lines, since)
        \\end
        \\
    );
}

test "round 2: a one-line anonymous function inside a long call stays one line, and the call breaks around it" {
    try expectFormat(
        \\module M
        \\fn f(records: List(Record), since: Option(Time), top_limit_value: UInt64) : Tally
        \\  records.reduce(empty_tally(), fn(tally, record) add_record(tally, record, since, top_limit_value) end)
        \\end
    ,
        \\module M
        \\
        \\fn f(records: List(Record), since: Option(Time), top_limit_value: UInt64) : Tally
        \\  records.reduce(empty_tally(),
        \\    fn(tally, record) add_record(tally, record, since, top_limit_value) end)
        \\end
        \\
    );
}

test "round 2: a nested call is never split across lines by itself" {
    try expectFormat(
        \\module M
        \\fn f(tally: Tally, share: Float64, top: UInt64) : Summary
        \\  Summary(requests: tally.requests, errors: tally.errors, rate: share, busiest: busiest(tally.hits, top))
        \\end
    ,
        \\module M
        \\
        \\fn f(tally: Tally, share: Float64, top: UInt64) : Summary
        \\  Summary(requests: tally.requests, errors: tally.errors, rate: share,
        \\    busiest: busiest(tally.hits, top))
        \\end
        \\
    );
}

test "grouping parentheses stay as written; strings and numbers are untouched" {
    try expectFormat(
        \\module M
        \\fn f(a: UInt32) : String
        \\  b = ((a))+( 1_000 )
        \\  "#{b  +1}  x"
        \\end
    ,
        \\module M
        \\
        \\fn f(a: UInt32) : String
        \\  b = ((a)) + (1_000)
        \\  "#{b  +1}  x"
        \\end
        \\
    );
}

test "a process, a supervisor, and a recipe" {
    try expectFormat(
        \\module M
        \\expose C, S
        \\process C() mailbox:10
        \\  state
        \\    n: UInt32
        \\
        \\    m: UInt32 = 1
        \\  end
        \\  invariant "n never drops"
        \\    state.n >= old(state.n)
        \\  end
        \\
        \\  message Up
        \\
        \\  message Get :UInt32
        \\  fn update(state,message)
        \\    case message
        \\      Up:
        \\        state.n += 1
        \\      Get: state.n
        \\    end
        \\  end
        \\end
        \\supervisor S()
        \\  child C(), restart: :always,max_restarts: 5 per 1.minute
        \\end
        \\recipe R
        \\  intent "r"
        \\  needs nothing
        \\
        \\  fn r(n: UInt32) : UInt32
        \\    requires n > 0
        \\  end
        \\end
    ,
        \\module M
        \\expose C, S
        \\
        \\process C() mailbox: 10
        \\  state
        \\    n: UInt32
        \\    m: UInt32 = 1
        \\  end
        \\
        \\  invariant "n never drops"
        \\    state.n >= old(state.n)
        \\  end
        \\
        \\  message Up
        \\  message Get : UInt32
        \\
        \\  fn update(state, message)
        \\    case message
        \\      Up:
        \\        state.n += 1
        \\      Get: state.n
        \\    end
        \\  end
        \\end
        \\
        \\supervisor S
        \\  child C, restart: :always, max_restarts: 5 per 1.minute
        \\end
        \\
        \\recipe R
        \\  intent "r"
        \\  needs nothing
        \\  fn r(n: UInt32) : UInt32
        \\    requires n > 0
        \\  end
        \\end
        \\
    );
}

test "if values: one line when they fit and no comment sits inside, the block form otherwise" {
    try expectFormat(
        \\module M
        \\fn f(n: UInt32, o: Option(UInt32)) : String
        \\  word = if n == 1
        \\    "line"
        \\  else
        \\    "lines"
        \\  end
        \\  long = if n > 1: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" else: "the other branch, which does not fit on the line"
        \\  kept = if n > 1
        \\    # many
        \\    "lines"
        \\  else
        \\    "line"
        \\  end
        \\  after = if n > 1
        \\    "lines"  # many
        \\  else
        \\    "line"
        \\  end
        \\  last = if n > 1
        \\    "lines"
        \\  else
        \\    "line"  # one
        \\  end
        \\  sized = if n > 1
        \\    "lines"
        \\  else
        \\    "line"
        \\  end.size
        \\  noted = if n > 1
        \\    "lines"
        \\  else
        \\    "line"
        \\  end  # why
        \\  chain = if n > 99
        \\    "long"
        \\  else
        \\    if n > 9
        \\      "medium"
        \\    else
        \\      "short"
        \\    end
        \\  end
        \\  arm = case o
        \\    Some(x): if x > 1
        \\      "big"
        \\    else
        \\      "small"
        \\    end
        \\    None: "none"
        \\  end
        \\  g(word, long, kept, after, last, sized, noted, chain, arm, bbbbbbbbbbbb, if n > 0: "positive" else: "zero")
        \\end
    ,
        \\module M
        \\
        \\fn f(n: UInt32, o: Option(UInt32)) : String
        \\  word = if n == 1: "line" else: "lines"
        \\  long = if n > 1
        \\    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        \\  else
        \\    "the other branch, which does not fit on the line"
        \\  end
        \\  kept = if n > 1
        \\    # many
        \\    "lines"
        \\  else
        \\    "line"
        \\  end
        \\  after = if n > 1
        \\    "lines"  # many
        \\  else
        \\    "line"
        \\  end
        \\  last = if n > 1: "lines" else: "line"  # one
        \\  sized = if n > 1
        \\    "lines"
        \\  else
        \\    "line"
        \\  end.size
        \\  noted = if n > 1: "lines" else: "line"  # why
        \\  chain = if n > 99: "long" else: if n > 9: "medium" else: "short"
        \\  arm = case o
        \\    Some(x): if x > 1: "big" else: "small"
        \\    None: "none"
        \\  end
        \\  g(word, long, kept, after, last, sized, noted, chain, arm, bbbbbbbbbbbb,
        \\    if n > 0: "positive" else: "zero")
        \\end
        \\
    );
}

test "a comment the formatter would have to move rejects the file" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    const src = "module M\nfn f(a: UInt32,  # the first\n  b: UInt32) : UInt32\n  a\nend\n";
    try std.testing.expectError(error.Rejected, format(arena, src, &diags));
    try std.testing.expectEqualStrings("MO0502", diags.items[0].code);
    try std.testing.expectEqual(@as(u32, 26), diags.items[0].at);
}

test "an anonymous function whose one-line body starts with a parenthesis formats, and keeps its tree" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const source =
        \\module P.Fmt
        \\
        \\intent "probe"
        \\
        \\fn hashed(n: UInt64) : UInt64
        \\  [n].reduce(0, fn(acc, x) (acc + x) % 7 end)
        \\end
        \\
        \\fn bucket(key: String) : UInt64
        \\  key.bytes.reduce(0, fn(hash, b)   (hash * 31 + b.to_u64) % 256 end)
        \\end
        \\
    ;
    var diags: diag.List = .empty;
    const once = try format(arena, source, &diags);
    try std.testing.expectEqualStrings(once, try format(arena, once, &diags));
    try std.testing.expectEqualStrings((try dumpSource(arena, source)).?, (try dumpSource(arena, once)).?);
    try std.testing.expect(std.mem.indexOf(u8, once, "fn(acc, x) (acc + x) % 7 end") != null);
}

/// One whitespace change at a random place: a space doubled or dropped, a space put before
/// a bracket, a comma, a dot, or a colon, or a line end doubled or given a space before it.
fn mutateWhitespace(gpa: std.mem.Allocator, text: *std.ArrayList(u8), random: std.Random) error{OutOfMemory}!void {
    if (text.items.len == 0) return;
    for (0..256) |_| {
        const at = random.uintLessThan(usize, text.items.len);
        switch (text.items[at]) {
            ' ' => if (random.boolean()) {
                _ = text.orderedRemove(at);
            } else try text.insert(gpa, at, ' '),
            '(', ')', '[', ']', ',', '.', ':' => try text.insert(gpa, at, ' '),
            '\n' => try text.insert(gpa, at, if (random.boolean()) '\n' else ' '),
            else => continue,
        }
        return;
    }
}

test "mo fmt never crashes: every corpus file formats after each of ten random whitespace mutations" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const corpus = @import("corpus.zig");
    const root = "../examples";
    const paths = corpus.collect(gpa, io, root) catch |err| switch (err) {
        error.FileNotFound => return, // no corpus checked out beside the toolchain
        else => return err,
    };
    defer {
        for (paths) |p| gpa.free(p);
        gpa.free(paths);
    }
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    var rng: std.Random.DefaultPrng = .init(0x6d6f_2066_6d74);
    const random = rng.random();
    var formatted: u32 = 0;
    for (paths) |rel| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(arena, try dir.readFileAlloc(io, rel, arena, .limited(1 << 20)));
        for (0..10) |_| {
            try mutateWhitespace(arena, &text, random);
            // A change that leaves the file unparsable is a diagnostic; a crash ends the run.
            var diags: diag.List = .empty;
            _ = format(arena, text.items, &diags) catch |err| switch (err) {
                error.Rejected => continue,
                else => return err,
            };
            formatted += 1;
        }
    }
    try std.testing.expect(formatted > 0);
}

test "every corpus file: formatting is idempotent and keeps the tree" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const corpus = @import("corpus.zig");
    const root = "../examples";
    const paths = corpus.collect(gpa, io, root) catch |err| switch (err) {
        error.FileNotFound => return, // no corpus checked out beside the toolchain
        else => return err,
    };
    defer {
        for (paths) |p| gpa.free(p);
        gpa.free(paths);
    }
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    for (paths) |rel| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const source = try dir.readFileAlloc(io, rel, arena, .limited(1 << 20));
        // A rejects file that expects a syntax code does not parse, by design (step 21).
        if (corpus.isRejectsPath(rel)) if (corpus.expectedCode(source)) |code| if (std.mem.startsWith(u8, code, "MO01")) continue;
        var diags: diag.List = .empty;
        const once = format(arena, source, &diags) catch |err| {
            for (diags.items) |d| std.debug.print("fmt: {s} at byte {d}: {s} {s}\n", .{ rel, d.at, d.code, d.what });
            return err;
        };
        const twice = try format(arena, once, &diags);
        std.testing.expectEqualStrings(once, twice) catch |err| {
            std.debug.print("fmt: {s} is not idempotent\n", .{rel});
            return err;
        };
        std.testing.expectEqualStrings((try dumpSource(arena, source)).?, (try dumpSource(arena, once)).?) catch |err| {
            std.debug.print("fmt: {s} formats to a different tree\n", .{rel});
            return err;
        };
    }
}
