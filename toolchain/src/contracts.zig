//! Tier 2 (design-v0/05): `requires`, `ensures`, `invariant`, and `never` evaluated
//! at runtime while the module's tests run. Contract expressions use unbounded
//! integers so the spec cannot overflow. Target: under 100 ms per changed function.
const std = @import("std");

/// Contract expressions evaluate in unbounded integers (chapter 3). i128 stands in for
/// them in this step: every sized operand fits with room to spare, and contract
/// arithmetic that passes i128 crashes with an overflow report instead of wrapping.
/// A bignum replaces it when a contract needs one. bytecode.Num.unbounded marks it.
pub const Unbounded = i128;

/// `any(T)` of a refined type (vm.zig and mo_rt.c, generate) keeps only what the refinement
/// admits: candidates of the base type, and once `refined_base_candidates` of them pass
/// none, candidates between the integer bounds the `where` states (bytecode.Bounds), when it
/// states any. After `refined_candidates` with none passing, the property fails with MO0325.
pub const refined_base_candidates: u32 = 100;
pub const refined_candidates: u32 = 200;

/// MO0325's finding for a refined type none of whose generated candidates pass.
pub fn noneAdmitted(gpa: std.mem.Allocator, type_name: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(gpa, "MO0325 the refinement of {s} admits none of the 200 values any({s}) generated; write its where as a range, such as value >= 1 and value <= 9, or generate the base type and build the value in the property.", .{ type_name, type_name });
}

/// What stopped a run.
pub const Kind = enum {
    requires,
    ensures,
    refinement,
    /// A process's `invariant` block was true after an `update`.
    invariant,
    /// A `never` was true for the values a test or property run held.
    never,
    assert,
    overflow,
    divide_by_zero,
    /// A send found the target's mailbox at its bound; the sender crashes.
    mailbox,
    /// A child crashed more than its `max_restarts` within the window.
    supervisor,
    /// A value no arm matched, or an operation this step does not run.
    other,
};

/// One value a report shows, already rendered as Mo source.
pub const Involved = struct { name: []const u8, value: []const u8 };

/// What a crash inside a process adds to its report (chapter 3, failure).
pub const ProcessCrash = struct {
    process: []const u8,
    seed: u64,
    /// Every message since the process (re)started, rendered, oldest first; the last
    /// one is the message it crashed on.
    log: []const []const u8,
    /// The state before that message, rendered.
    state: []const u8,
};

/// A crash, complete: what tripped, where, and the values involved.
pub const Report = struct {
    kind: Kind,
    /// The violated clause or the trapped operation, quoted from source.
    clause: []const u8,
    /// The function, test, or type the clause belongs to.
    within: []const u8,
    /// Byte offset of the clause in the source.
    at: u32,
    values: []const Involved = &.{},
    /// Set when the crash happened inside a process.
    process: ?ProcessCrash = null,

    /// A `test rejects` passes only on these.
    pub fn tripsRejects(r: Report) bool {
        return r.kind == .requires or r.kind == .refinement or r.kind == .invariant or r.kind == .never;
    }
};
