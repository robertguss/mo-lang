//! Tier 2 (design-v0/05): `requires`, `ensures`, `invariant`, and `never` evaluated
//! at runtime while the module's tests run. Contract expressions use unbounded
//! integers so the spec cannot overflow. Target: under 100 ms per changed function.
pub const Report = struct {
    /// The violated clause, quoted, plus the contract chain that led to it.
    clause: []const u8,
};
