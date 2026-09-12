//! Stage 2: tokens → ast.Tree (grammar.md §2–§11). Recursive descent, one function
//! per production, indentation carries no meaning.
const std = @import("std");
const token = @import("token.zig");
const ast = @import("ast.zig");

pub const Error = error{ NotImplemented, OutOfMemory };

pub fn parse(gpa: std.mem.Allocator, source: []const u8, tokens: []const token.Token) Error!ast.Tree {
    _ = gpa;
    _ = source;
    _ = tokens;
    return error.NotImplemented;
}
