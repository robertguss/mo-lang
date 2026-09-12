//! Runs `test`, `test rejects`, and `property` blocks of a module on the vm.
//! A `rejects` test passes only when its `requires` trips. Property tests run under
//! N seeds; results feed verified.zig.
pub const Outcome = enum { passed, failed, tripped_as_expected, did_not_trip };

pub const Summary = struct {
    tests: u32 = 0,
    rejects: u32 = 0,
    properties: u32 = 0,
    seeds: u32 = 0,
    failures: u32 = 0,
};
