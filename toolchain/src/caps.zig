//! Capability checking (design-v0/03 effects) and `flows(T, into: Cap)`: a function
//! with no capability parameter is pure; effectful calls carry `within:`; capabilities
//! are obtained only at the root and narrowed on the way down. Runs in tier 1.
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
