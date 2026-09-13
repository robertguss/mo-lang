//! The `verified:` line (design-v0/05): computed by the toolchain, fixed vocabulary,
//! weakest obligation first, a compile error to edit by hand. This step prints it;
//! writing it into the file comes with the sidecar.
const std = @import("std");
const runner = @import("runner.zig");

/// The line for a module whose tests ran. A failing test earns nothing past types.
/// `contracts` means every contract the tests reached held, and every never was checked
/// at the end of every test, test rejects, and property run (runner.zig).
/// `sim (N runs)` when `mo test --sim N` ran at least one test under seeds with no
/// failure; `sim (not run)` without --sim, or when no test starts a process. A test that
/// passes only without faults is a pass, so it does not hold the line back.
pub fn render(w: *std.Io.Writer, s: runner.Summary) std.Io.Writer.Error!void {
    if (s.failures > 0) {
        try w.writeAll("verified: types\n");
    } else {
        try w.writeAll("verified: types, contracts, tests (");
        try grouped(w, s.tests);
        try w.writeAll("), property (");
        try grouped(w, s.seeds);
        if (s.sim_runs > 0 and s.simulated > 0) {
            try w.writeAll(" seeds), sim (");
            try grouped(w, s.sim_runs);
            try w.writeAll(" runs)\n");
        } else try w.writeAll(" seeds), sim (not run)\n");
    }
    try w.writeAll("          proven: not run\n");
}

/// A count as chapter 5 spells it: 1_000.
fn grouped(w: *std.Io.Writer, n: u32) std.Io.Writer.Error!void {
    if (n < 1000) return w.print("{d}", .{n});
    try grouped(w, n / 1000);
    try w.print("_{d:0>3}", .{n % 1000});
}

test "the line matches chapter 4, with the simulator not yet run" {
    var buf: [160]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try render(&w, .{ .tests = 3, .rejects = 1, .properties = 1, .seeds = 200 });
    try std.testing.expectEqualStrings(
        "verified: types, contracts, tests (3), property (200 seeds), sim (not run)\n          proven: not run\n",
        w.buffered(),
    );
}

test "--sim N with no failure earns sim (N runs), spelled as chapter 5 spells it" {
    var buf: [160]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try render(&w, .{ .tests = 5, .seeds = 200, .sim_runs = 1_000, .simulated = 2, .fault_free_only = 1 });
    try std.testing.expectEqualStrings(
        "verified: types, contracts, tests (5), property (200 seeds), sim (1_000 runs)\n          proven: not run\n",
        w.buffered(),
    );
    // --sim over a module whose tests start no process simulated nothing.
    w = .fixed(&buf);
    try render(&w, .{ .tests = 2, .sim_runs = 100 });
    try std.testing.expectEqualStrings(
        "verified: types, contracts, tests (2), property (0 seeds), sim (not run)\n          proven: not run\n",
        w.buffered(),
    );
}

test "a failing test earns only types" {
    var buf: [160]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try render(&w, .{ .tests = 2, .failures = 1 });
    try std.testing.expectEqualStrings("verified: types\n          proven: not run\n", w.buffered());
}
