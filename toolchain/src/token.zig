//! Token kinds, straight from grammar.md §1. The lexer produces these; nothing
//! else names a keyword by string.
const std = @import("std");

pub const Kind = enum {
    // literals and names
    ident, // snake_case, optional trailing ?
    type_name, // CapCase: types, variants, modules
    int,
    float,
    string, // whole string including interpolation holes; the parser splits #{}
    atom, // :always
    underscore, // _ in patterns
    // punctuation
    l_paren,
    r_paren,
    l_brace,
    r_brace,
    l_bracket,
    r_bracket,
    comma,
    dot,
    dot_dot,
    colon,
    bang,
    eq,
    eq_eq,
    bang_eq,
    lt,
    lt_eq,
    gt,
    gt_eq,
    plus,
    minus,
    star,
    slash,
    percent,
    plus_eq,
    minus_eq,
    newline,
    eof,
    // keywords (grammar.md §1)
    kw_module,
    kw_use,
    kw_intent,
    kw_never,
    kw_expose,
    kw_fn,
    kw_requires,
    kw_ensures,
    kw_var,
    kw_if,
    kw_else,
    kw_end,
    kw_case,
    kw_for,
    kw_in,
    kw_break,
    kw_return,
    kw_try,
    kw_and,
    kw_or,
    kw_implies,
    kw_is,
    kw_old,
    kw_result,
    kw_struct,
    kw_enum,
    kw_type,
    kw_where,
    kw_trait,
    kw_impl,
    kw_process,
    kw_state,
    kw_invariant,
    kw_message,
    kw_supervisor,
    kw_child,
    kw_per,
    kw_recipe,
    kw_needs,
    kw_test,
    kw_rejects,
    kw_property,
    kw_any,
    kw_verified,
    kw_true,
    kw_false,
    kw_inout,
    kw_assert,
};

pub const keywords = std.StaticStringMap(Kind).initComptime(.{
    .{ "module", .kw_module },     .{ "use", .kw_use },           .{ "intent", .kw_intent },
    .{ "never", .kw_never },       .{ "expose", .kw_expose },     .{ "fn", .kw_fn },
    .{ "requires", .kw_requires }, .{ "ensures", .kw_ensures },   .{ "var", .kw_var },
    .{ "if", .kw_if },             .{ "else", .kw_else },         .{ "end", .kw_end },
    .{ "case", .kw_case },         .{ "for", .kw_for },           .{ "in", .kw_in },
    .{ "break", .kw_break },       .{ "return", .kw_return },     .{ "try", .kw_try },
    .{ "and", .kw_and },           .{ "or", .kw_or },             .{ "implies", .kw_implies },
    .{ "is", .kw_is },             .{ "old", .kw_old },           .{ "result", .kw_result },
    .{ "struct", .kw_struct },     .{ "enum", .kw_enum },         .{ "type", .kw_type },
    .{ "where", .kw_where },       .{ "trait", .kw_trait },       .{ "impl", .kw_impl },
    .{ "process", .kw_process },   .{ "state", .kw_state },       .{ "invariant", .kw_invariant },
    .{ "message", .kw_message },   .{ "supervisor", .kw_supervisor }, .{ "child", .kw_child },
    .{ "per", .kw_per },           .{ "recipe", .kw_recipe },     .{ "needs", .kw_needs },
    .{ "test", .kw_test },         .{ "rejects", .kw_rejects },   .{ "property", .kw_property },
    .{ "any", .kw_any },           .{ "verified", .kw_verified }, .{ "true", .kw_true },
    .{ "false", .kw_false },       .{ "inout", .kw_inout },       .{ "assert", .kw_assert },
});

/// A token is an index pair into the source, never a copy (pointer-free, index-based
/// compiler data, design-v0/07). Line and column are recomputed from `start` on demand.
pub const Token = struct {
    kind: Kind,
    start: u32,
    end: u32,
};

test "every grammar keyword is in the table" {
    try std.testing.expectEqual(Kind.kw_module, keywords.get("module").?);
    try std.testing.expectEqual(Kind.kw_verified, keywords.get("verified").?);
    try std.testing.expect(keywords.get("def") == null); // rejected on sight (SCHEMA.md)
}
