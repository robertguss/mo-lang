//! The instruction set of the interpreter and the lowering from ast.Tree. Stack
//! machine; contracts are lowered as ordinary code guarded by the tier-2 flag;
//! integer arithmetic traps on overflow in every build (design-v0/02).
const std = @import("std");
const ast = @import("ast.zig");

pub const Op = enum(u8) { nop, todo };

pub const Chunk = struct {
    code: []u8,
    constants: []u64,
};

pub const Error = error{ NotImplemented, OutOfMemory };

pub fn lower(gpa: std.mem.Allocator, tree: ast.Tree) Error!Chunk {
    _ = gpa;
    _ = tree;
    return error.NotImplemented;
}
