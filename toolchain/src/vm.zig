//! The bytecode interpreter: the edit-loop runtime and the executable reference
//! semantics (design-v0/07). Hosts contracts, the test runner, and later the
//! simulator, replay, and fault injection. A tripped contract or an overflow is
//! a crash with a complete report, never a value.
const std = @import("std");
const bytecode = @import("bytecode.zig");

pub const Error = error{ NotImplemented, OutOfMemory, Crash };

pub fn run(gpa: std.mem.Allocator, chunk: bytecode.Chunk) Error!void {
    _ = gpa;
    _ = chunk;
    return error.NotImplemented;
}
