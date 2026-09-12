//! Stage 1: source bytes → tokens (grammar.md §1). Joins lines that end inside an
//! open paren; `#` to end of line is the only comment; strings always interpolate.
const std = @import("std");
const token = @import("token.zig");

pub const Error = error{ NotImplemented, OutOfMemory };

pub fn lex(gpa: std.mem.Allocator, source: []const u8) Error![]token.Token {
    _ = gpa;
    _ = source;
    return error.NotImplemented;
}
