//! Stage 3, tier 1 (design-v0/05): types, exhaustiveness, the laws of chapter 2
//! (shape numbers, bindings, no rebinding, every Result consumed, requires↔rejects
//! pairing, expose names declared), and the `verified:` line untouched by hand.
//! Target: under 50 ms incremental. Every finding is a diag.Record, never a warning.
const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");

pub const Error = error{ NotImplemented, OutOfMemory };

pub fn check(gpa: std.mem.Allocator, tree: ast.Tree, out: *diag.List) Error!void {
    _ = gpa;
    _ = tree;
    _ = out;
    return error.NotImplemented;
}
