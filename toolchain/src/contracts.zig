//! Tier 2 (design-v0/05): `requires`, `ensures`, `invariant`, and `never` evaluated
//! at runtime while the module's tests run. Contract expressions use unbounded
//! integers so the spec cannot overflow. Target: under 100 ms per changed function.
const std = @import("std");

/// What stopped a run.
pub const Kind = enum {
    requires,
    ensures,
    refinement,
    assert,
    overflow,
    divide_by_zero,
    /// A value no arm matched, or an operation this step does not run.
    other,
};

/// One value a report shows, already rendered as Mo source.
pub const Involved = struct { name: []const u8, value: []const u8 };

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

    /// A `test rejects` passes only on these.
    pub fn tripsRejects(r: Report) bool {
        return r.kind == .requires or r.kind == .refinement;
    }
};
