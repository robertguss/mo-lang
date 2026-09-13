//! Stage 2: tokens → ast.Tree (grammar.md §2–§11). Recursive descent, one function
//! per production, indentation carries no meaning. The first error stops the file
//! with one MO01xx record; there is no recovery yet.
const std = @import("std");
const token = @import("token.zig");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const diag = @import("diag.zig");

const Kind = token.Kind;
const Node = ast.Node;
const Index = ast.Index;
const Span = ast.Span;

pub const Error = error{ OutOfMemory, Rejected };

const why_token = "spec/grammar.md allows only this at this point in the production.";
const why_expr = "An expression starts with a literal, a name, a type name, (, [, !, -, try, if, case, fn, old, result, or any.";
const why_type = "A type is a type name such as UInt32 or List(T), or a tuple of two or more types such as (UInt32, String).";
const why_pattern = "A pattern is _, a name, a literal, a variant such as Some(x) or Short(by: n), or a tuple of patterns.";
const why_order = "A module is its header (module, expose, use, intent, never), then declarations, then tests, then the verified: line.";
const why_place = "Only a name or a field path such as copy.name can be assigned.";
/// The parser's rows of the error catalog. MO0101 also stands for a malformed
/// `fn main` line, with why_main as its why.
pub const catalog = [_]diag.Entry{
    .{ .code = "MO0101", .category = .syntax, .what = "expected <token>", .why = why_token, .fixes = &.{} },
    .{ .code = "MO0102", .category = .syntax, .what = "expected an expression", .why = why_expr, .fixes = &.{} },
    .{ .code = "MO0103", .category = .syntax, .what = "expected a type", .why = why_type, .fixes = &.{} },
    .{ .code = "MO0104", .category = .syntax, .what = "expected a pattern", .why = why_pattern, .fixes = &.{} },
    .{ .code = "MO0105", .category = .syntax, .what = "expected a declaration, a test, or the end of the file", .why = why_order, .fixes = &.{} },
    .{ .code = "MO0106", .category = .syntax, .what = "this cannot be assigned", .why = why_place, .fixes = &.{} },
};
/// A case arm on one line holds one expression: a statement there is MO0102 at its keyword, or
/// MO0101 at an assignment's `=`.
const arm_assignment = "a case arm holds one expression after its `:`; an assignment is a statement, and a statement goes on its own lines below the arm";

fn armStatement(kind: Kind) ?[]const u8 {
    const rest = "` is a statement, and a statement goes on its own lines below the arm";
    const head = "a case arm holds one expression after its `:`; `";
    return switch (kind) {
        .kw_assert => head ++ "assert" ++ rest,
        .kw_var => head ++ "var" ++ rest,
        .kw_return => head ++ "return" ++ rest,
        .kw_for => head ++ "for" ++ rest,
        .kw_break => head ++ "break" ++ rest,
        else => null,
    };
}

const why_main = "fn main is the program's root (grammar §2, Q18): it takes one parameter, platform: Platform, and has no return type, like update.";
const main_param = "fn main takes one parameter, platform: Platform";

fn describe(comptime kind: Kind) []const u8 {
    return switch (kind) {
        .ident => "a name",
        .type_name => "a type name",
        .int => "an integer",
        .float => "a float",
        .string => "a string",
        .atom => "an atom such as :always",
        .underscore => "`_`",
        .l_paren => "`(`",
        .r_paren => "`)`",
        .l_brace => "`{`",
        .r_brace => "`}`",
        .l_bracket => "`[`",
        .r_bracket => "`]`",
        .comma => "`,`",
        .dot => "`.`",
        .dot_dot => "`..`",
        .colon => "`:`",
        .bang => "`!`",
        .eq => "`=`",
        .eq_eq => "`==`",
        .bang_eq => "`!=`",
        .lt => "`<`",
        .lt_eq => "`<=`",
        .gt => "`>`",
        .gt_eq => "`>=`",
        .plus => "`+`",
        .minus => "`-`",
        .star => "`*`",
        .slash => "`/`",
        .percent => "`%`",
        .plus_eq => "`+=`",
        .minus_eq => "`-=`",
        .newline => "the end of the line",
        .eof => "the end of the file",
        else => "`" ++ @tagName(kind)[3..] ++ "`",
    };
}

const expected_what = blk: {
    var table: [@typeInfo(Kind).@"enum".fields.len][]const u8 = undefined;
    for (&table, 0..) |*slot, i| slot.* = "expected " ++ describe(@enumFromInt(i));
    break :blk table;
};

pub fn parse(gpa: std.mem.Allocator, source: []const u8, tokens: []const token.Token, diags: *diag.List) Error!ast.Tree {
    return parseModules(gpa, source, tokens, diags, false);
}

/// A program's files joined into one source, each a whole module: one root whose items
/// are every module's, in order. Each file parses alone first, so this finds nothing new.
pub fn parseProgram(gpa: std.mem.Allocator, source: []const u8, tokens: []const token.Token, diags: *diag.List) Error!ast.Tree {
    return parseModules(gpa, source, tokens, diags, true);
}

fn parseModules(gpa: std.mem.Allocator, source: []const u8, tokens: []const token.Token, diags: *diag.List, program: bool) Error!ast.Tree {
    var p: Parser = .{ .gpa = gpa, .source = source, .diags = diags, .program = program };
    defer p.scratch.deinit(gpa);
    errdefer {
        p.toks.deinit(gpa);
        p.nodes.deinit(gpa);
        p.extra.deinit(gpa);
    }
    try p.toks.appendSlice(gpa, tokens);
    try p.nodes.append(gpa, .{ .kind = .root, .main_token = 0 });
    try p.extra.append(gpa, 0);
    try p.parseModule();
    return .{
        .source = source,
        .tokens = try p.toks.toOwnedSlice(gpa),
        .nodes = try p.nodes.toOwnedSlice(gpa),
        .extra = try p.extra.toOwnedSlice(gpa),
    };
}

const Parser = struct {
    gpa: std.mem.Allocator,
    source: []const u8,
    diags: *diag.List,
    toks: std.ArrayList(token.Token) = .empty,
    tok: u32 = 0,
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(u32) = .empty,
    /// Children collect here, then move into `extra` as one span.
    scratch: std.ArrayList(u32) = .empty,
    /// More than one module may follow another.
    program: bool = false,

    // ---- cursor

    fn peek(p: *Parser) Kind {
        return p.toks.items[p.tok].kind;
    }

    /// Never looks past an eof, so a hole's tokens stay out of the file's sight.
    fn peekAt(p: *Parser, n: u32) Kind {
        var i = p.tok;
        var k: u32 = 0;
        while (k < n) : (k += 1) {
            if (p.toks.items[i].kind == .eof) return .eof;
            i += 1;
        }
        return p.toks.items[i].kind;
    }

    fn next(p: *Parser) u32 {
        const i = p.tok;
        if (p.toks.items[i].kind != .eof) p.tok += 1;
        return i;
    }

    fn eat(p: *Parser, kind: Kind) ?u32 {
        return if (p.peek() == kind) p.next() else null;
    }

    fn expect(p: *Parser, kind: Kind) Error!u32 {
        return p.eat(kind) orelse p.fail("MO0101", expected_what[@intFromEnum(kind)], why_token);
    }

    fn text(p: *Parser, i: u32) []const u8 {
        const t = p.toks.items[i];
        return p.source[t.start..t.end];
    }

    /// A word the grammar spells out but that is not a keyword: `update`, `restart`.
    fn expectWord(p: *Parser, word: []const u8, what: []const u8) Error!u32 {
        if (p.peek() == .ident and std.mem.eql(u8, p.text(p.tok), word)) return p.next();
        return p.fail("MO0101", what, why_token);
    }

    fn endLine(p: *Parser) Error!void {
        if (p.peek() == .eof) return;
        _ = try p.expect(.newline);
    }

    fn skipNewlines(p: *Parser) void {
        while (p.peek() == .newline) p.tok += 1;
    }

    fn fail(p: *Parser, code: []const u8, what: []const u8, why: []const u8) Error {
        return p.failAt(p.tok, code, what, why);
    }

    fn failAt(p: *Parser, tok: u32, code: []const u8, what: []const u8, why: []const u8) Error {
        try p.diags.append(p.gpa, .{ .code = code, .category = .syntax, .at = p.toks.items[tok].start, .what = what, .why = why });
        return error.Rejected;
    }

    // ---- building

    fn addNode(p: *Parser, node: Node) Error!Index {
        const i: Index = @intCast(p.nodes.items.len);
        try p.nodes.append(p.gpa, node);
        return i;
    }

    fn addExtra(p: *Parser, value: anytype) Error!u32 {
        const start: u32 = @intCast(p.extra.items.len);
        inline for (@typeInfo(@TypeOf(value)).@"struct".fields) |f| try p.extra.append(p.gpa, @field(value, f.name));
        return start;
    }

    fn push(p: *Parser, i: u32) Error!void {
        try p.scratch.append(p.gpa, i);
    }

    fn spanFrom(p: *Parser, top: usize) Error!Span {
        const start: u32 = @intCast(p.extra.items.len);
        try p.extra.appendSlice(p.gpa, p.scratch.items[top..]);
        p.scratch.shrinkRetainingCapacity(top);
        return .{ .start = start, .end = @intCast(p.extra.items.len) };
    }

    fn spanNode(p: *Parser, kind: Node.Kind, main_token: u32, top: usize) Error!Index {
        const s = try p.spanFrom(top);
        return p.addNode(.{ .kind = kind, .main_token = main_token, .lhs = s.start, .rhs = s.end });
    }

    // ---- §2 module

    fn parseModule(p: *Parser) Error!void {
        const top = p.scratch.items.len;
        while (true) {
            p.skipNewlines();
            try p.push(try p.parseModuleDecl());
            if (p.peek() == .kw_expose) try p.push(try p.parseExpose());
            while (p.peek() == .kw_use) try p.push(try p.parseUse());
            if (p.peek() == .kw_intent) try p.push(try p.parseIntent());
            while (p.peek() == .kw_never) try p.push(try p.parseNever());
            while (isDeclStart(p.peek())) try p.push(try p.parseDecl());
            while (p.peek() == .kw_test or p.peek() == .kw_property) try p.push(try p.parseTest());
            if (p.peek() == .kw_verified) try p.push(try p.parseVerified());
            // A program's files, joined in dependency order, are one module after another.
            if (!p.program or p.peek() != .kw_module) break;
        }
        if (p.peek() != .eof) {
            if (isDeclStart(p.peek())) return p.fail("MO0105", "a declaration after the tests", why_order);
            return p.fail("MO0105", "expected a declaration, a test, or the end of the file", why_order);
        }
        const s = try p.spanFrom(top);
        p.nodes.items[0].lhs = s.start;
        p.nodes.items[0].rhs = s.end;
    }

    fn parseModuleDecl(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_module);
        const path = try p.parsePath();
        try p.endLine();
        return p.addNode(.{ .kind = .module_decl, .main_token = kw, .lhs = path });
    }

    fn parsePath(p: *Parser) Error!Index {
        const first = try p.expect(.type_name);
        var last = first;
        while (p.peek() == .dot and p.peekAt(1) == .type_name) {
            _ = p.next();
            last = p.next();
        }
        return p.addNode(.{ .kind = .path, .main_token = first, .lhs = last });
    }

    fn parseExpose(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_expose);
        const top = p.scratch.items.len;
        while (true) {
            switch (p.peek()) {
                .ident, .type_name => try p.push(p.next()),
                else => return p.fail("MO0101", "expected a name to expose", why_token),
            }
            if (p.eat(.comma) == null) break;
        }
        try p.endLine();
        return p.spanNode(.expose, kw, top);
    }

    fn parseUse(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_use);
        const path = try p.parsePath();
        var names: u32 = ast.none;
        if (p.eat(.l_brace)) |_| {
            const top = p.scratch.items.len;
            while (true) {
                switch (p.peek()) {
                    .ident, .type_name => try p.push(p.next()),
                    else => return p.fail("MO0101", "expected a type or function name to use", why_token),
                }
                if (p.eat(.comma) == null) break;
            }
            _ = try p.expect(.r_brace);
            names = try p.addExtra(try p.spanFrom(top));
        }
        try p.endLine();
        return p.addNode(.{ .kind = .use, .main_token = kw, .lhs = path, .rhs = names });
    }

    fn parseIntent(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_intent);
        const str = try p.expect(.string);
        try p.endLine();
        return p.addNode(.{ .kind = .intent, .main_token = kw, .lhs = str });
    }

    fn parseNever(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_never);
        const str = try p.expect(.string);
        try p.endLine();
        const body = if (p.peek() == .kw_for) try p.parseComprehension() else try p.parseExpr();
        try p.endLine();
        p.skipNewlines();
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = .never, .main_token = kw, .lhs = str, .rhs = body });
    }

    fn parseVerified(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_verified);
        _ = try p.expect(.colon);
        while (p.peek() != .newline and p.peek() != .eof) _ = p.next();
        try p.endLine();
        // Chapter 5's second line, `proven: ...`, belongs to the same node.
        const t = p.toks.items[p.tok];
        if (t.kind == .ident and std.mem.eql(u8, p.source[t.start..t.end], "proven")) {
            while (p.peek() != .newline and p.peek() != .eof) _ = p.next();
            try p.endLine();
        }
        return p.addNode(.{ .kind = .verified, .main_token = kw });
    }

    fn isDeclStart(kind: Kind) bool {
        return switch (kind) {
            .kw_fn, .kw_struct, .kw_enum, .kw_type, .kw_trait, .kw_impl, .kw_process, .kw_supervisor, .kw_recipe => true,
            else => false,
        };
    }

    fn parseDecl(p: *Parser) Error!Index {
        return switch (p.peek()) {
            // In a module, the name `main` is the main production, never an ordinary fn.
            .kw_fn => if (p.peekAt(1) == .ident and std.mem.eql(u8, p.text(p.tok + 1), "main")) p.parseMain() else p.parseFn(),
            .kw_struct => p.parseStruct(),
            .kw_enum => p.parseEnum(),
            .kw_type => p.parseTypedef(),
            .kw_trait => p.parseTrait(),
            .kw_impl => p.parseImpl(),
            .kw_process => p.parseProcess(),
            .kw_supervisor => p.parseSupervisor(),
            .kw_recipe => p.parseRecipe(),
            else => unreachable,
        };
    }

    // ---- §3 types

    fn parseType(p: *Parser) Error!Index {
        var t: Index = switch (p.peek()) {
            .type_name => blk: {
                const first = p.tok;
                const path = try p.parsePath();
                var args: u32 = ast.none;
                if (p.eat(.l_paren)) |_| {
                    const top = p.scratch.items.len;
                    while (true) {
                        try p.push(try p.parseType());
                        if (p.eat(.comma) == null) break;
                    }
                    _ = try p.expect(.r_paren);
                    args = try p.addExtra(try p.spanFrom(top));
                }
                break :blk try p.addNode(.{ .kind = .type_ref, .main_token = first, .lhs = path, .rhs = args });
            },
            .l_paren => blk: {
                const open = p.next();
                const top = p.scratch.items.len;
                try p.push(try p.parseType());
                _ = try p.expect(.comma);
                while (true) {
                    try p.push(try p.parseType());
                    if (p.eat(.comma) == null) break;
                }
                _ = try p.expect(.r_paren);
                break :blk try p.spanNode(.type_tuple, open, top);
            },
            else => return p.fail("MO0103", "expected a type", why_type),
        };
        // `where T: Trait` after a return type is a bound, not a refinement.
        while (p.peek() == .kw_where and !(p.peekAt(1) == .type_name and p.peekAt(2) == .colon)) {
            const w = p.next();
            const cond = try p.parseExpr();
            t = try p.addNode(.{ .kind = .type_refined, .main_token = w, .lhs = t, .rhs = cond });
        }
        return t;
    }

    fn parseStruct(p: *Parser) Error!Index {
        _ = try p.expect(.kw_struct);
        const name = try p.expect(.type_name);
        try p.endLine();
        const top = p.scratch.items.len;
        while (true) {
            try p.push(try p.parseField());
            try p.endLine();
            if (p.peek() == .kw_end) break;
        }
        const s = try p.spanFrom(top);
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = .struct_decl, .main_token = name, .lhs = s.start, .rhs = s.end });
    }

    fn parseField(p: *Parser) Error!Index {
        const name = try p.expect(.ident);
        _ = try p.expect(.colon);
        const t = try p.parseType();
        return p.addNode(.{ .kind = .field, .main_token = name, .lhs = t });
    }

    fn parseFieldList(p: *Parser) Error!Span {
        _ = try p.expect(.l_paren);
        const top = p.scratch.items.len;
        while (true) {
            try p.push(try p.parseField());
            if (p.eat(.comma) == null) break;
        }
        _ = try p.expect(.r_paren);
        return p.spanFrom(top);
    }

    fn parseEnum(p: *Parser) Error!Index {
        _ = try p.expect(.kw_enum);
        const name = try p.expect(.type_name);
        try p.endLine();
        const top = p.scratch.items.len;
        while (true) {
            try p.push(try p.parseVariant());
            if (p.peek() == .kw_end) break;
        }
        const s = try p.spanFrom(top);
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = .enum_decl, .main_token = name, .lhs = s.start, .rhs = s.end });
    }

    fn parseVariant(p: *Parser) Error!Index {
        const name = try p.expect(.type_name);
        var s: Span = .{ .start = 0, .end = 0 };
        if (p.peek() == .l_paren) s = try p.parseFieldList();
        try p.endLine();
        return p.addNode(.{ .kind = .variant, .main_token = name, .lhs = s.start, .rhs = s.end });
    }

    fn parseTypedef(p: *Parser) Error!Index {
        _ = try p.expect(.kw_type);
        const name = try p.expect(.type_name);
        _ = try p.expect(.eq);
        const t = try p.parseType();
        try p.endLine();
        return p.addNode(.{ .kind = .type_decl, .main_token = name, .lhs = t });
    }

    fn parseTrait(p: *Parser) Error!Index {
        _ = try p.expect(.kw_trait);
        const name = try p.expect(.type_name);
        try p.endLine();
        const top = p.scratch.items.len;
        while (true) {
            const sig = try p.parseSignature();
            try p.endLine();
            const empty: Span = .{ .start = 0, .end = 0 };
            try p.push(try p.signatureNode(sig, empty));
            if (p.peek() == .kw_end) break;
        }
        const s = try p.spanFrom(top);
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = .trait_decl, .main_token = name, .lhs = s.start, .rhs = s.end });
    }

    fn parseImpl(p: *Parser) Error!Index {
        _ = try p.expect(.kw_impl);
        const name = try p.expect(.type_name);
        _ = try p.expect(.kw_for);
        const t = try p.parseType();
        try p.endLine();
        const top = p.scratch.items.len;
        while (true) {
            try p.push(try p.parseFn());
            if (p.peek() == .kw_end) break;
        }
        const fns = try p.addExtra(try p.spanFrom(top));
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = .impl_decl, .main_token = name, .lhs = t, .rhs = fns });
    }

    // ---- §4 functions and contracts

    const SignatureHead = struct { name: u32, params: Span, ret: Index, bounds: Span };

    fn parseSignature(p: *Parser) Error!SignatureHead {
        _ = try p.expect(.kw_fn);
        const name = try p.expect(.ident);
        const params = try p.parseParams();
        const ret = if (p.eat(.colon)) |_| try p.parseType() else switch (p.peek()) {
            // A function that returns nothing names no type, as main does (grammar §2).
            .newline, .eof, .kw_where => ast.none,
            else => return p.fail("MO0101", "a function that returns a value names its type after `:`; one that returns nothing leaves it off", why_token),
        };
        const bounds = try p.parseBounds();
        return .{ .name = name, .params = params, .ret = ret, .bounds = bounds };
    }

    fn signatureNode(p: *Parser, head: SignatureHead, contracts: Span) Error!Index {
        const sig = try p.addSignature(head, contracts);
        return p.addNode(.{ .kind = .fn_signature, .main_token = head.name, .lhs = sig });
    }

    fn addSignature(p: *Parser, head: SignatureHead, contracts: Span) Error!u32 {
        return p.addExtra(ast.Signature{
            .params_start = head.params.start,
            .params_end = head.params.end,
            .ret = head.ret,
            .bounds_start = head.bounds.start,
            .bounds_end = head.bounds.end,
            .contracts_start = contracts.start,
            .contracts_end = contracts.end,
        });
    }

    fn parseFn(p: *Parser) Error!Index {
        const head = try p.parseSignature();
        const open = p.tok;
        try p.endLine();
        const contracts = try p.parseContracts();
        const body = try p.parseBlock(false);
        const end = try p.expect(.kw_end);
        try p.endLine();
        const sig = try p.addSignature(head, contracts);
        const body_span = try p.addExtra(ast.FnBody{ .start = body.start, .end = body.end, .open_token = open, .end_token = end });
        return p.addNode(.{ .kind = .fn_decl, .main_token = head.name, .lhs = sig, .rhs = body_span });
    }

    /// `fn main(platform: Platform)`: a fn_decl with no return type (ret is none) and no
    /// contracts.
    fn parseMain(p: *Parser) Error!Index {
        _ = try p.expect(.kw_fn);
        const name = p.next();
        _ = try p.expect(.l_paren);
        const at = p.tok;
        if (p.peek() != .ident) return p.failAt(at, "MO0101", main_param, why_main);
        const param = try p.parseParam();
        if (p.peek() != .r_paren or !p.isPlatformParam(param)) return p.failAt(at, "MO0101", main_param, why_main);
        _ = p.next();
        if (p.peek() == .colon) return p.fail("MO0101", "fn main has no return type; end the line after (platform: Platform)", why_main);
        const open = p.tok;
        try p.endLine();
        const top = p.scratch.items.len;
        try p.push(param);
        const params = try p.spanFrom(top);
        const body = try p.parseBlock(false);
        const end = try p.expect(.kw_end);
        try p.endLine();
        const empty: Span = .{ .start = 0, .end = 0 };
        const sig = try p.addSignature(.{ .name = name, .params = params, .ret = ast.none, .bounds = empty }, empty);
        const body_span = try p.addExtra(ast.FnBody{ .start = body.start, .end = body.end, .open_token = open, .end_token = end });
        return p.addNode(.{ .kind = .fn_decl, .main_token = name, .lhs = sig, .rhs = body_span });
    }

    fn isPlatformParam(p: *Parser, param: Index) bool {
        const pn = p.nodes.items[param];
        if (pn.kind != .param or pn.rhs != 0) return false;
        const t = p.nodes.items[pn.lhs];
        if (t.kind != .type_ref or t.rhs != 0) return false;
        const path = p.nodes.items[t.lhs];
        return path.lhs == path.main_token and std.mem.eql(u8, p.text(path.main_token), "Platform");
    }

    fn parseParams(p: *Parser) Error!Span {
        _ = try p.expect(.l_paren);
        const top = p.scratch.items.len;
        if (p.peek() != .r_paren) {
            while (true) {
                try p.push(try p.parseParam());
                if (p.eat(.comma) == null) break;
            }
        }
        _ = try p.expect(.r_paren);
        return p.spanFrom(top);
    }

    fn parseParam(p: *Parser) Error!Index {
        const inout = p.eat(.kw_inout) != null;
        const name = try p.expect(.ident);
        _ = try p.expect(.colon);
        const t = try p.parseType();
        const default: Index = if (p.eat(.eq)) |_| try p.parseExpr() else ast.none;
        return p.addNode(.{ .kind = if (inout) .param_inout else .param, .main_token = name, .lhs = t, .rhs = default });
    }

    fn parseBounds(p: *Parser) Error!Span {
        const top = p.scratch.items.len;
        if (p.eat(.kw_where)) |_| {
            while (true) {
                const name = try p.expect(.type_name);
                _ = try p.expect(.colon);
                const path = try p.parsePath();
                try p.push(try p.addNode(.{ .kind = .bound, .main_token = name, .lhs = path }));
                if (p.eat(.comma) == null) break;
            }
        }
        return p.spanFrom(top);
    }

    fn parseContracts(p: *Parser) Error!Span {
        const top = p.scratch.items.len;
        while (true) {
            p.skipNewlines();
            const kind: Node.Kind = switch (p.peek()) {
                .kw_requires => .requires,
                .kw_ensures => .ensures,
                else => break,
            };
            const kw = p.next();
            const e = try p.parseExpr();
            try p.endLine();
            try p.push(try p.addNode(.{ .kind = kind, .main_token = kw, .lhs = e }));
        }
        return p.spanFrom(top);
    }

    // ---- §5 statements

    /// Statements up to `end`, `else`, or, inside a case arm, the next arm.
    fn parseBlock(p: *Parser, in_arm: bool) Error!Span {
        const top = p.scratch.items.len;
        while (true) {
            p.skipNewlines();
            switch (p.peek()) {
                .kw_end, .kw_else, .eof => break,
                else => {},
            }
            if (in_arm and p.atArmStart()) break;
            try p.push(try p.parseStmt());
        }
        return p.spanFrom(top);
    }

    /// An arm is the only line with a `:` outside every delimiter.
    fn atArmStart(p: *Parser) bool {
        var depth: u32 = 0;
        var i = p.tok;
        while (true) : (i += 1) {
            switch (p.toks.items[i].kind) {
                .l_paren, .l_bracket, .l_brace => depth += 1,
                .r_paren, .r_bracket, .r_brace => depth -|= 1,
                .colon => if (depth == 0) return true,
                .newline => if (depth == 0) return false,
                .eof => return false,
                else => {},
            }
        }
    }

    fn parseStmt(p: *Parser) Error!Index {
        return switch (p.peek()) {
            .kw_var => p.parseVarBinding(),
            .kw_return => p.parseReturn(),
            .kw_for => p.parseFor(),
            .kw_if => p.parseIfStmt(),
            .kw_case => p.parseCaseStmt(),
            .kw_assert => p.parseAssert(),
            .kw_break => p.parseBreak(),
            else => p.parseExprStmt(),
        };
    }

    fn parseVarBinding(p: *Parser) Error!Index {
        _ = try p.expect(.kw_var);
        const name = try p.expect(.ident);
        _ = try p.expect(.eq);
        const e = try p.parseExpr();
        try p.endLine();
        return p.addNode(.{ .kind = .var_binding, .main_token = name, .lhs = e });
    }

    fn parseReturn(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_return);
        switch (p.peek()) {
            .newline, .eof, .kw_if => return p.fail("MO0102", "`return` takes a value; a function that returns nothing ends its body instead", why_expr),
            else => {},
        }
        const e = try p.parseExpr();
        const cond: Index = if (p.eat(.kw_if)) |_| try p.parseExpr() else ast.none;
        try p.endLine();
        return p.addNode(.{ .kind = .return_stmt, .main_token = kw, .lhs = e, .rhs = cond });
    }

    fn parseFor(p: *Parser) Error!Index {
        _ = try p.expect(.kw_for);
        // `for _ in 0..n`: `_` says the index is unused (step 5). The grammar's `for`
        // production takes ident | "_"; the unused-binding law has nothing to bind.
        const name = p.eat(.underscore) orelse try p.expect(.ident);
        _ = try p.expect(.kw_in);
        const iter = try p.parseExpr();
        _ = try p.expect(.newline);
        const body = try p.parseBlock(false);
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = .for_stmt, .main_token = name, .lhs = iter, .rhs = try p.addExtra(body) });
    }

    fn parseIfStmt(p: *Parser) Error!Index {
        const node = try p.parseIf(.if_stmt, false);
        try p.endLine();
        return node;
    }

    /// `if cond NL block (else NL block)? end`, without the line end.
    fn parseIf(p: *Parser, kind: Node.Kind, require_else: bool) Error!Index {
        const kw = try p.expect(.kw_if);
        const cond = try p.parseExpr();
        _ = try p.expect(.newline);
        const then = try p.parseBlock(false);
        var otherwise: Span = .{ .start = 0, .end = 0 };
        if (require_else or p.peek() == .kw_else) {
            _ = try p.expect(.kw_else);
            _ = try p.expect(.newline);
            otherwise = try p.parseBlock(false);
        }
        _ = try p.expect(.kw_end);
        const data = try p.addExtra(ast.If{ .then_start = then.start, .then_end = then.end, .else_start = otherwise.start, .else_end = otherwise.end });
        return p.addNode(.{ .kind = kind, .main_token = kw, .lhs = cond, .rhs = data });
    }

    fn parseCaseStmt(p: *Parser) Error!Index {
        const node = try p.parseCase(.case_stmt);
        try p.endLine();
        return node;
    }

    /// `case subject NL arm+ end`, without the line end.
    fn parseCase(p: *Parser, kind: Node.Kind) Error!Index {
        const kw = try p.expect(.kw_case);
        const subject = try p.parseExpr();
        _ = try p.expect(.newline);
        const top = p.scratch.items.len;
        while (true) {
            try p.push(try p.parseArm());
            p.skipNewlines();
            if (p.peek() == .kw_end) break;
        }
        const arms = try p.addExtra(try p.spanFrom(top));
        _ = try p.expect(.kw_end);
        return p.addNode(.{ .kind = kind, .main_token = kw, .lhs = subject, .rhs = arms });
    }

    fn parseArm(p: *Parser) Error!Index {
        const first = p.tok;
        var pattern = try p.parsePattern();
        if (p.peek() == .pipe) {
            // `A | B | C: body`: each alternative a whole pattern.
            const top = p.scratch.items.len;
            try p.push(pattern);
            while (p.eat(.pipe)) |_| try p.push(try p.parsePattern());
            pattern = try p.spanNode(.pat_or, first, top);
        }
        const guard: Index = if (p.eat(.kw_if)) |_| try p.parseExpr() else ast.none;
        _ = try p.expect(.colon);
        var body: Span = undefined;
        if (p.peek() == .newline) {
            body = try p.parseBlock(true);
        } else {
            const at = p.tok;
            if (armStatement(p.peek())) |what| return p.fail("MO0102", what, why_expr);
            const e = try p.parseExpr();
            switch (p.peek()) {
                .eq, .plus_eq, .minus_eq => return p.fail("MO0101", arm_assignment, why_token),
                else => {},
            }
            try p.endLine();
            const top = p.scratch.items.len;
            try p.push(try p.addNode(.{ .kind = .expr_stmt, .main_token = at, .lhs = e }));
            body = try p.spanFrom(top);
        }
        const data = try p.addExtra(ast.Arm{ .guard = guard, .body_start = body.start, .body_end = body.end });
        return p.addNode(.{ .kind = .arm, .main_token = first, .lhs = pattern, .rhs = data });
    }

    fn parseAssert(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_assert);
        const e = try p.parseExpr();
        try p.endLine();
        return p.addNode(.{ .kind = .assert_stmt, .main_token = kw, .lhs = e });
    }

    fn parseBreak(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_break);
        try p.endLine();
        return p.addNode(.{ .kind = .break_stmt, .main_token = kw });
    }

    /// An expression, a binding (`x = e`), or an assignment to a place.
    fn parseExprStmt(p: *Parser) Error!Index {
        const first = p.tok;
        const target = try p.parseExpr();
        switch (p.peek()) {
            .eq, .plus_eq, .minus_eq => {
                const op = p.next();
                const value = try p.parseExpr();
                try p.endLine();
                const node = p.nodes.items[target];
                if (p.toks.items[op].kind == .eq and node.kind == .name_ref and p.toks.items[node.main_token].kind == .ident) {
                    return p.addNode(.{ .kind = .binding, .main_token = node.main_token, .lhs = value });
                }
                if (!p.isPlace(target)) return p.failAt(first, "MO0106", "this cannot be assigned", why_place);
                return p.addNode(.{ .kind = .assign, .main_token = op, .lhs = target, .rhs = value });
            },
            else => {
                try p.endLine();
                return p.addNode(.{ .kind = .expr_stmt, .main_token = first, .lhs = target });
            },
        }
    }

    fn isPlace(p: *Parser, i: Index) bool {
        const node = p.nodes.items[i];
        return switch (node.kind) {
            .name_ref => true,
            .member => p.isPlace(node.lhs),
            else => false,
        };
    }

    // ---- §6 expressions

    fn parseExpr(p: *Parser) Error!Index {
        const lhs = try p.parseOr();
        if (p.eat(.kw_implies)) |op| {
            const rhs = try p.parseOr();
            return p.addNode(.{ .kind = .implies, .main_token = op, .lhs = lhs, .rhs = rhs });
        }
        return lhs;
    }

    fn parseOr(p: *Parser) Error!Index {
        var lhs = try p.parseAnd();
        while (p.eat(.kw_or)) |op| {
            const rhs = try p.parseAnd();
            lhs = try p.addNode(.{ .kind = .or_expr, .main_token = op, .lhs = lhs, .rhs = rhs });
        }
        return lhs;
    }

    fn parseAnd(p: *Parser) Error!Index {
        var lhs = try p.parseNot();
        while (p.eat(.kw_and)) |op| {
            const rhs = try p.parseNot();
            lhs = try p.addNode(.{ .kind = .and_expr, .main_token = op, .lhs = lhs, .rhs = rhs });
        }
        return lhs;
    }

    fn parseNot(p: *Parser) Error!Index {
        if (p.eat(.bang)) |op| {
            const operand = try p.parseNot();
            return p.addNode(.{ .kind = .not_expr, .main_token = op, .lhs = operand });
        }
        return p.parseCmp();
    }

    fn parseCmp(p: *Parser) Error!Index {
        const lhs = try p.parseRange();
        switch (p.peek()) {
            .eq_eq, .bang_eq, .lt, .lt_eq, .gt, .gt_eq => {
                const op = p.next();
                const rhs = try p.parseRange();
                return p.addNode(.{ .kind = .compare, .main_token = op, .lhs = lhs, .rhs = rhs });
            },
            .kw_is => {
                const op = p.next();
                const pattern = try p.parsePattern();
                return p.addNode(.{ .kind = .is_expr, .main_token = op, .lhs = lhs, .rhs = pattern });
            },
            else => return lhs,
        }
    }

    fn parseRange(p: *Parser) Error!Index {
        const lhs = try p.parseAdd();
        if (p.eat(.dot_dot)) |op| {
            const rhs = try p.parseAdd();
            return p.addNode(.{ .kind = .range, .main_token = op, .lhs = lhs, .rhs = rhs });
        }
        return lhs;
    }

    fn parseAdd(p: *Parser) Error!Index {
        var lhs = try p.parseMul();
        while (p.peek() == .plus or p.peek() == .minus) {
            const op = p.next();
            const rhs = try p.parseMul();
            lhs = try p.addNode(.{ .kind = .add, .main_token = op, .lhs = lhs, .rhs = rhs });
        }
        return lhs;
    }

    fn parseMul(p: *Parser) Error!Index {
        var lhs = try p.parseUnary();
        while (p.peek() == .star or p.peek() == .slash or p.peek() == .percent) {
            const op = p.next();
            const rhs = try p.parseUnary();
            lhs = try p.addNode(.{ .kind = .mul, .main_token = op, .lhs = lhs, .rhs = rhs });
        }
        return lhs;
    }

    fn parseUnary(p: *Parser) Error!Index {
        const kind: Node.Kind = switch (p.peek()) {
            .minus => .negate,
            .kw_try => .try_expr,
            else => return p.parsePostfix(),
        };
        const op = p.next();
        const operand = try p.parseUnary();
        return p.addNode(.{ .kind = kind, .main_token = op, .lhs = operand });
    }

    fn parsePostfix(p: *Parser) Error!Index {
        var e = try p.parsePrimary();
        while (true) {
            switch (p.peek()) {
                .dot => {
                    _ = p.next();
                    switch (p.peek()) {
                        .int => e = try p.addNode(.{ .kind = .tuple_index, .main_token = p.next(), .lhs = e }),
                        .ident, .type_name => {
                            const name = p.next();
                            if (p.peek() == .l_paren) {
                                const args = try p.addExtra(try p.parseCallArgs());
                                e = try p.addNode(.{ .kind = .member_call, .main_token = name, .lhs = e, .rhs = args });
                            } else {
                                e = try p.addNode(.{ .kind = .member, .main_token = name, .lhs = e });
                            }
                        },
                        else => return p.fail("MO0101", "expected a name or a tuple position after `.`", why_token),
                    }
                },
                .l_paren => {
                    const open = p.tok;
                    const args = try p.addExtra(try p.parseCallArgs());
                    e = try p.addNode(.{ .kind = .call, .main_token = open, .lhs = e, .rhs = args });
                },
                else => return e,
            }
        }
    }

    fn parseCallArgs(p: *Parser) Error!Span {
        _ = try p.expect(.l_paren);
        const top = p.scratch.items.len;
        if (p.peek() != .r_paren) {
            while (true) {
                try p.push(try p.parseArg());
                if (p.eat(.comma) == null) break;
            }
        }
        _ = try p.expect(.r_paren);
        return p.spanFrom(top);
    }

    fn parseArg(p: *Parser) Error!Index {
        if (p.peek() == .ident and p.peekAt(1) == .colon) {
            const name = p.next();
            _ = p.next();
            const e = try p.parseExpr();
            return p.addNode(.{ .kind = .named_arg, .main_token = name, .lhs = e });
        }
        return p.parseExpr();
    }

    fn parsePrimary(p: *Parser) Error!Index {
        const leaf: Node.Kind = switch (p.peek()) {
            .int => .int_lit,
            .float => .float_lit,
            .kw_true => .true_lit,
            .kw_false => .false_lit,
            .kw_result => .result_ref,
            .ident, .kw_state, .kw_message => .name_ref,
            .type_name => .type_name_ref,
            .string => return p.parseString(p.next()),
            .l_paren => return p.parseParenExpr(),
            .l_bracket => return p.parseList(),
            .kw_if => return p.parseIf(.if_expr, true),
            .kw_case => return p.parseCase(.case_expr),
            .kw_fn => return p.parseAnonFn(),
            .kw_old => return p.parseOld(),
            .kw_any => return p.parseAny(),
            else => return p.fail("MO0102", "expected an expression", why_expr),
        };
        return p.addNode(.{ .kind = leaf, .main_token = p.next() });
    }

    fn parseParenExpr(p: *Parser) Error!Index {
        const open = try p.expect(.l_paren);
        const first = try p.parseExpr();
        if (p.eat(.r_paren)) |_| return first;
        const top = p.scratch.items.len;
        try p.push(first);
        while (p.eat(.comma)) |_| try p.push(try p.parseExpr());
        _ = try p.expect(.r_paren);
        return p.spanNode(.tuple, open, top);
    }

    fn parseList(p: *Parser) Error!Index {
        const open = try p.expect(.l_bracket);
        const top = p.scratch.items.len;
        if (p.peek() != .r_bracket) {
            while (true) {
                try p.push(try p.parseExpr());
                if (p.eat(.comma) == null) break;
            }
        }
        _ = try p.expect(.r_bracket);
        return p.spanNode(.list, open, top);
    }

    fn parseAnonFn(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_fn);
        _ = try p.expect(.l_paren);
        const top = p.scratch.items.len;
        if (p.peek() != .r_paren) {
            while (true) {
                try p.push(try p.expect(.ident));
                if (p.eat(.comma) == null) break;
            }
        }
        _ = try p.expect(.r_paren);
        const params = try p.spanFrom(top);
        var body: Span = undefined;
        if (p.peek() == .newline) {
            body = try p.parseBlock(false);
        } else {
            const at = p.tok;
            const e = try p.parseExpr();
            const body_top = p.scratch.items.len;
            try p.push(try p.addNode(.{ .kind = .expr_stmt, .main_token = at, .lhs = e }));
            body = try p.spanFrom(body_top);
        }
        _ = try p.expect(.kw_end);
        const data = try p.addExtra(ast.AnonFn{ .params_start = params.start, .params_end = params.end, .body_start = body.start, .body_end = body.end });
        return p.addNode(.{ .kind = .anon_fn, .main_token = kw, .lhs = data });
    }

    fn parseOld(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_old);
        _ = try p.expect(.l_paren);
        const e = try p.parseExpr();
        _ = try p.expect(.r_paren);
        return p.addNode(.{ .kind = .old_expr, .main_token = kw, .lhs = e });
    }

    fn parseAny(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_any);
        _ = try p.expect(.l_paren);
        const t = try p.parseType();
        _ = try p.expect(.r_paren);
        return p.addNode(.{ .kind = .any_expr, .main_token = kw, .lhs = t });
    }

    /// Splits a string token at its `#{...}` holes; each hole is lexed and parsed as
    /// an expression whose tokens are appended after the file's.
    fn parseString(p: *Parser, tok: u32) Error!Index {
        const t = p.toks.items[tok];
        const str = p.source[t.start..t.end];
        if (std.mem.indexOf(u8, str, "#{") == null) return p.addNode(.{ .kind = .string_lit, .main_token = tok });
        const quote: usize = if (std.mem.startsWith(u8, str, "\"\"\"")) 3 else 1;
        const body_end = str.len - quote;
        const top = p.scratch.items.len;
        var i: usize = quote;
        var literal_start: usize = quote;
        while (i < body_end) {
            if (str[i] == '\\') {
                i += 2;
                continue;
            }
            if (str[i] == '#' and i + 1 < body_end and str[i + 1] == '{') {
                if (i > literal_start) try p.push(try p.stringPart(tok, t.start, literal_start, i));
                const close = lexer.holeClose(str, i + 2);
                try p.push(try p.parseHole(t.start + @as(u32, @intCast(i + 2)), t.start + @as(u32, @intCast(close))));
                i = close + 1;
                literal_start = i;
                continue;
            }
            i += 1;
        }
        if (body_end > literal_start) try p.push(try p.stringPart(tok, t.start, literal_start, body_end));
        return p.spanNode(.string_interp, tok, top);
    }

    fn stringPart(p: *Parser, tok: u32, base: u32, from: usize, to: usize) Error!Index {
        return p.addNode(.{ .kind = .string_part, .main_token = tok, .lhs = base + @as(u32, @intCast(from)), .rhs = base + @as(u32, @intCast(to)) });
    }

    fn parseHole(p: *Parser, start: u32, end: u32) Error!Index {
        const hole = lexer.lex(p.gpa, p.source[start..end], p.diags) catch |err| {
            if (err == error.Rejected) p.diags.items[p.diags.items.len - 1].at += start;
            return err;
        };
        defer p.gpa.free(hole);
        const first: u32 = @intCast(p.toks.items.len);
        for (hole) |h| {
            if (h.kind == .newline) continue;
            try p.toks.append(p.gpa, .{ .kind = h.kind, .start = h.start + start, .end = h.end + start });
        }
        const saved = p.tok;
        p.tok = first;
        if (p.peek() == .eof) return p.fail("MO0102", "expected an expression inside #{}", why_expr);
        const e = try p.parseExpr();
        if (p.peek() != .eof) return p.fail("MO0101", "expected `}` to close the interpolation", why_token);
        p.tok = saved;
        return e;
    }

    // ---- §7 patterns

    fn parsePattern(p: *Parser) Error!Index {
        switch (p.peek()) {
            .underscore => return p.addNode(.{ .kind = .pat_wildcard, .main_token = p.next() }),
            .ident => return p.addNode(.{ .kind = .pat_bind, .main_token = p.next() }),
            .int, .float, .string, .kw_true, .kw_false => return p.addNode(.{ .kind = .pat_literal, .main_token = p.next() }),
            // A negative number: the literal's node keeps its `-` token as lhs.
            .minus => {
                const minus = p.next();
                if (p.peek() != .int and p.peek() != .float) return p.fail("MO0104", "expected a number after `-` in a pattern", why_pattern);
                return p.addNode(.{ .kind = .pat_literal, .main_token = p.next(), .lhs = minus });
            },
            .type_name => {
                const name = p.next();
                if (p.peek() != .l_paren) return p.addNode(.{ .kind = .pat_variant, .main_token = name });
                if (p.peekAt(1) == .ident and p.peekAt(2) == .colon) return p.parseRecordPattern(name);
                _ = p.next();
                const inner = try p.parsePattern();
                _ = try p.expect(.r_paren);
                return p.addNode(.{ .kind = .pat_variant, .main_token = name, .lhs = inner });
            },
            .l_paren => {
                const open = p.next();
                const top = p.scratch.items.len;
                try p.push(try p.parsePattern());
                if (p.peek() == .r_paren) {
                    _ = p.next();
                    const inner = p.scratch.items[top];
                    p.scratch.shrinkRetainingCapacity(top);
                    return inner;
                }
                while (p.eat(.comma)) |_| try p.push(try p.parsePattern());
                _ = try p.expect(.r_paren);
                return p.spanNode(.pat_tuple, open, top);
            },
            else => return p.fail("MO0104", "expected a pattern", why_pattern),
        }
    }

    fn parseRecordPattern(p: *Parser, name: u32) Error!Index {
        _ = try p.expect(.l_paren);
        const top = p.scratch.items.len;
        while (true) {
            const field = try p.expect(.ident);
            _ = try p.expect(.colon);
            const inner = try p.parsePattern();
            try p.push(try p.addNode(.{ .kind = .pat_field, .main_token = field, .lhs = inner }));
            if (p.eat(.comma) == null) break;
        }
        _ = try p.expect(.r_paren);
        return p.spanNode(.pat_record, name, top);
    }

    // ---- §8 comprehensions

    fn parseComprehension(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_for);
        const top = p.scratch.items.len;
        while (true) {
            const name = try p.expect(.ident);
            _ = try p.expect(.kw_in);
            const e = try p.parseExpr();
            try p.push(try p.addNode(.{ .kind = .generator, .main_token = name, .lhs = e }));
            if (p.eat(.comma) == null) break;
        }
        const gens = try p.spanFrom(top);
        const guard: Index = if (p.eat(.kw_if)) |_| try p.parseExpr() else ast.none;
        _ = try p.expect(.newline);
        const body = try p.parseBlock(false);
        _ = try p.expect(.kw_end);
        const data = try p.addExtra(ast.Comprehension{ .gens_start = gens.start, .gens_end = gens.end, .guard = guard, .body_start = body.start, .body_end = body.end });
        return p.addNode(.{ .kind = .comprehension, .main_token = kw, .lhs = data });
    }

    // ---- §9 processes and supervisors

    fn parseProcess(p: *Parser) Error!Index {
        _ = try p.expect(.kw_process);
        const name = try p.expect(.type_name);
        const params = try p.parseParams();
        var mailbox: u32 = ast.none;
        if (p.peek() == .ident and std.mem.eql(u8, p.text(p.tok), "mailbox")) {
            _ = p.next();
            _ = try p.expect(.colon);
            mailbox = try p.expect(.int);
        }
        try p.endLine();
        const state = try p.parseStateBlock();

        const inv_top = p.scratch.items.len;
        while (p.peek() == .kw_invariant) try p.push(try p.parseInvariant());
        const invariants = try p.spanFrom(inv_top);

        const msg_top = p.scratch.items.len;
        while (true) {
            try p.push(try p.parseMessage());
            if (p.peek() != .kw_message) break;
        }
        const messages = try p.spanFrom(msg_top);

        const update = try p.parseUpdate();
        _ = try p.expect(.kw_end);
        try p.endLine();
        const data = try p.addExtra(ast.Process{
            .params_start = params.start,
            .params_end = params.end,
            .mailbox = mailbox,
            .state = state,
            .invariants_start = invariants.start,
            .invariants_end = invariants.end,
            .messages_start = messages.start,
            .messages_end = messages.end,
            .update = update,
        });
        return p.addNode(.{ .kind = .process_decl, .main_token = name, .lhs = data });
    }

    fn parseStateBlock(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_state);
        try p.endLine();
        const top = p.scratch.items.len;
        while (true) {
            try p.push(try p.parseStateField());
            if (p.peek() == .kw_end) break;
        }
        const node = try p.spanNode(.state_block, kw, top);
        _ = try p.expect(.kw_end);
        try p.endLine();
        return node;
    }

    fn parseStateField(p: *Parser) Error!Index {
        const name = try p.expect(.ident);
        _ = try p.expect(.colon);
        const t = try p.parseType();
        const init: Index = if (p.eat(.eq)) |_| try p.parseExpr() else ast.none;
        try p.endLine();
        return p.addNode(.{ .kind = .state_field, .main_token = name, .lhs = t, .rhs = init });
    }

    fn parseInvariant(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_invariant);
        const str = try p.expect(.string);
        try p.endLine();
        const e = try p.parseExpr();
        try p.endLine();
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = .invariant, .main_token = kw, .lhs = str, .rhs = e });
    }

    fn parseMessage(p: *Parser) Error!Index {
        _ = try p.expect(.kw_message);
        const name = try p.expect(.type_name);
        var fields: u32 = ast.none;
        if (p.peek() == .l_paren) fields = try p.addExtra(try p.parseFieldList());
        const reply: Index = if (p.eat(.colon)) |_| try p.parseType() else ast.none;
        try p.endLine();
        return p.addNode(.{ .kind = .message_decl, .main_token = name, .lhs = fields, .rhs = reply });
    }

    fn parseUpdate(p: *Parser) Error!Index {
        const kw = p.eat(.kw_fn) orelse return p.fail("MO0101", "expected a message or `fn update(state, message)`", why_token);
        _ = try p.expectWord("update", "expected `update`: a process ends with fn update(state, message)");
        _ = try p.expect(.l_paren);
        _ = try p.expect(.kw_state);
        _ = try p.expect(.comma);
        _ = try p.expect(.kw_message);
        _ = try p.expect(.r_paren);
        try p.endLine();
        const body = try p.parseCaseStmt();
        const end = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = .update_fn, .main_token = kw, .lhs = body, .rhs = end });
    }

    fn parseSupervisor(p: *Parser) Error!Index {
        _ = try p.expect(.kw_supervisor);
        const name = try p.expect(.type_name);
        var params: Span = .{ .start = 0, .end = 0 };
        if (p.peek() == .l_paren) params = try p.parseParams();
        try p.endLine();
        const top = p.scratch.items.len;
        while (true) {
            try p.push(try p.parseChild());
            if (p.peek() == .kw_end) break;
        }
        const children = try p.addExtra(try p.spanFrom(top));
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = .supervisor_decl, .main_token = name, .lhs = try p.addExtra(params), .rhs = children });
    }

    fn parseChild(p: *Parser) Error!Index {
        _ = try p.expect(.kw_child);
        const name = try p.expect(.type_name);
        var args: Span = .{ .start = 0, .end = 0 };
        if (p.peek() == .l_paren) args = try p.parseCallArgs();
        _ = try p.expect(.comma);
        _ = try p.expectWord("restart", "expected `restart:`");
        _ = try p.expect(.colon);
        const restart = try p.expect(.atom);
        var max_restarts: u32 = ast.none;
        var per: Index = ast.none;
        if (p.eat(.comma)) |_| {
            _ = try p.expectWord("max_restarts", "expected `max_restarts:`");
            _ = try p.expect(.colon);
            max_restarts = try p.expect(.int);
            _ = try p.expect(.kw_per);
            per = try p.parseExpr();
        }
        try p.endLine();
        const data = try p.addExtra(ast.Child{ .args_start = args.start, .args_end = args.end, .restart = restart, .max_restarts = max_restarts, .per = per });
        return p.addNode(.{ .kind = .child, .main_token = name, .lhs = data });
    }

    // ---- §10 tests

    fn parseTest(p: *Parser) Error!Index {
        if (p.eat(.kw_property)) |_| {
            const str = try p.expect(.string);
            try p.endLine();
            const body = try p.parseComprehension();
            try p.endLine();
            _ = try p.expect(.kw_end);
            try p.endLine();
            return p.addNode(.{ .kind = .property, .main_token = str, .lhs = body });
        }
        _ = try p.expect(.kw_test);
        const rejects = p.eat(.kw_rejects) != null;
        const str = try p.expect(.string);
        try p.endLine();
        const body = try p.parseBlock(false);
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.addNode(.{ .kind = if (rejects) .test_rejects else .test_decl, .main_token = str, .lhs = body.start, .rhs = body.end });
    }

    // ---- §11 recipes

    fn parseRecipe(p: *Parser) Error!Index {
        _ = try p.expect(.kw_recipe);
        const name = try p.expect(.type_name);
        try p.endLine();
        const intent = try p.parseIntent();
        const needs = try p.parseNeeds();

        const sig_top = p.scratch.items.len;
        while (p.peek() == .kw_fn) try p.push(try p.parseSignatureOnly());
        const sigs = try p.spanFrom(sig_top);

        const test_top = p.scratch.items.len;
        while (p.peek() == .kw_test or p.peek() == .kw_property) try p.push(try p.parseTest());
        const tests = try p.spanFrom(test_top);

        _ = try p.expect(.kw_end);
        try p.endLine();
        const data = try p.addExtra(ast.Recipe{ .intent = intent, .needs = needs, .sigs_start = sigs.start, .sigs_end = sigs.end, .tests_start = tests.start, .tests_end = tests.end });
        return p.addNode(.{ .kind = .recipe_decl, .main_token = name, .lhs = data });
    }

    fn parseNeeds(p: *Parser) Error!Index {
        const kw = try p.expect(.kw_needs);
        const top = p.scratch.items.len;
        if (p.peek() == .ident and std.mem.eql(u8, p.text(p.tok), "nothing")) {
            _ = p.next();
        } else {
            while (true) {
                const t = p.eat(.type_name) orelse return p.fail("MO0101", "expected `nothing` or a capability type", why_token);
                try p.push(t);
                if (p.eat(.comma) == null) break;
            }
        }
        try p.endLine();
        return p.spanNode(.needs, kw, top);
    }

    fn parseSignatureOnly(p: *Parser) Error!Index {
        const head = try p.parseSignature();
        try p.endLine();
        const contracts = try p.parseContracts();
        _ = try p.expect(.kw_end);
        try p.endLine();
        return p.signatureNode(head, contracts);
    }
};

fn parseSource(arena: std.mem.Allocator, source: []const u8, diags: *diag.List) !ast.Tree {
    const tokens = try lexer.lex(arena, source, diags);
    return parse(arena, source, tokens, diags);
}

test "a module parses into flat arrays" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    const src =
        \\module Basics.Tiny
        \\expose add
        \\
        \\intent "Add #{1 + 1} numbers."
        \\
        \\fn add(a: UInt32, b: UInt32) : UInt32
        \\  requires a < 10
        \\
        \\  a + b - 1
        \\end
        \\
        \\test "adds"
        \\  assert add(1, 2) is 2
        \\end
    ;
    const tree = try parseSource(arena, src, &diags);
    const items = tree.span(tree.nodes[0].lhs, tree.nodes[0].rhs);
    try std.testing.expectEqual(@as(usize, 5), items.len);
    try std.testing.expectEqual(Node.Kind.module_decl, tree.nodes[items[0]].kind);
    try std.testing.expectEqual(Node.Kind.fn_decl, tree.nodes[items[3]].kind);
    const body = tree.extraData(Span, tree.nodes[items[3]].rhs);
    const stmt = tree.nodes[tree.extra[body.start]];
    // `a + b - 1` is left-associative: (a + b) - 1.
    const sum = tree.nodes[stmt.lhs];
    try std.testing.expectEqualStrings("-", tree.tokenText(sum.main_token));
    try std.testing.expectEqual(Node.Kind.add, tree.nodes[sum.lhs].kind);
    try std.testing.expectEqual(Node.Kind.test_decl, tree.nodes[items[4]].kind);
}

test "an interpolated string splits into parts and expressions" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    const tree = try parseSource(arena, "module M\nfn f(n: UInt32) : String\n  \"a #{n + 1} b\"\nend\n", &diags);
    var found = false;
    for (tree.nodes) |n| {
        if (n.kind != .string_interp) continue;
        found = true;
        const parts = tree.span(n.lhs, n.rhs);
        try std.testing.expectEqual(@as(usize, 3), parts.len);
        try std.testing.expectEqual(Node.Kind.add, tree.nodes[parts[1]].kind);
    }
    try std.testing.expect(found);
}

test "a parse error is a record with the offset and what was expected" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    try std.testing.expectError(error.Rejected, parseSource(arena, "module M\nfn f() : UInt32\n  1\n", &diags));
    try std.testing.expectEqualStrings("MO0101", diags.items[0].code);
    try std.testing.expectEqualStrings("expected `end`", diags.items[0].what);
    try std.testing.expectEqual(@as(u32, 29), diags.items[0].at);
}

test "a function that returns nothing leaves its return type off; a type without `:`, or a bare return, says so" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    const tree = try parseSource(arena, "module M\nfn close(conn: Conn)\n  conn.close\nend\n", &diags);
    const f = tree.nodes[tree.span(tree.nodes[0].lhs, tree.nodes[0].rhs)[1]];
    try std.testing.expectEqual(ast.none, tree.extraData(ast.Signature, f.lhs).ret);

    const wrong = [_]struct { []const u8, []const u8, []const u8 }{
        .{ "module M\nfn f(n: UInt8) UInt8\n  n\nend\n", "MO0101", "a function that returns a value names its type after `:`; one that returns nothing leaves it off" },
        .{ "module M\nfn f(n: UInt8)\n  return\nend\n", "MO0102", "`return` takes a value; a function that returns nothing ends its body instead" },
        .{ "module M\nfn f(n: UInt8) : UInt8\n  return if n > 1\n  n\nend\n", "MO0102", "`return` takes a value; a function that returns nothing ends its body instead" },
        .{ "module M\ntest \"t\"\n  case 1\n    1: assert true\n    _: assert false\n  end\nend\n", "MO0102", "a case arm holds one expression after its `:`; `assert` is a statement, and a statement goes on its own lines below the arm" },
        .{ "module M\nfn f(o: Bool) : UInt8\n  var n = 0\n  case o\n    true: n = 1\n    false: n += 2\n  end\n  n\nend\n", "MO0101", "a case arm holds one expression after its `:`; an assignment is a statement, and a statement goes on its own lines below the arm" },
    };
    for (wrong) |w| {
        diags.clearRetainingCapacity();
        try std.testing.expectError(error.Rejected, parseSource(arena, w[0], &diags));
        try std.testing.expectEqualStrings(w[1], diags.items[0].code);
        try std.testing.expectEqualStrings(w[2], diags.items[0].what);
    }
}

test "fn main takes one Platform and has no return type" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    const tree = try parseSource(arena, "module M\nfn main(platform: Platform)\n  platform.exit(0)\nend\n", &diags);
    const main = tree.nodes[tree.span(tree.nodes[0].lhs, tree.nodes[0].rhs)[1]];
    try std.testing.expectEqual(Node.Kind.fn_decl, main.kind);
    try std.testing.expectEqual(ast.none, tree.extraData(ast.Signature, main.lhs).ret);

    const wrong = [_]struct { []const u8, []const u8 }{
        .{ "module M\nfn main(platform: Platform) : UInt8\n  0\nend\n", "fn main has no return type; end the line after (platform: Platform)" },
        .{ "module M\nfn main(args: List(String))\nend\n", main_param },
        .{ "module M\nfn main()\nend\n", main_param },
        .{ "module M\nfn main(platform: Platform, n: UInt8)\nend\n", main_param },
    };
    for (wrong) |w| {
        diags.clearRetainingCapacity();
        try std.testing.expectError(error.Rejected, parseSource(arena, w[0], &diags));
        try std.testing.expectEqualStrings("MO0101", diags.items[0].code);
        try std.testing.expectEqualStrings(w[1], diags.items[0].what);
    }
}
