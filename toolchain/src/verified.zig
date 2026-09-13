//! The `verified:` line (design-v0/05): computed by the toolchain, fixed vocabulary,
//! weakest obligation first, a compile error to edit by hand. This step prints it;
//! writing it into the file comes with the sidecar.
const std = @import("std");
const runner = @import("runner.zig");

/// The line for a module whose tests ran. A failing test earns nothing past types.
/// Tests run processes on Mo.Sim, but simulation with fault injection and seeds is the
/// next step, so sim is "not run".
pub fn render(w: *std.Io.Writer, s: runner.Summary) std.Io.Writer.Error!void {
    if (s.failures > 0) {
        try w.writeAll("verified: types\n");
    } else {
        try w.print("verified: types, contracts, tests ({d}), property ({d} seeds), sim (not run)\n", .{ s.tests, s.seeds });
    }
    try w.writeAll("          proven: not run\n");
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

test "a failing test earns only types" {
    var buf: [160]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try render(&w, .{ .tests = 2, .failures = 1 });
    try std.testing.expectEqualStrings("verified: types\n          proven: not run\n", w.buffered());
}
