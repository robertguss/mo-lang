//! The `verified:` line (design-v0/05): computed by the toolchain, fixed vocabulary,
//! weakest obligation first, a compile error to edit by hand.
const std = @import("std");
const runner = @import("runner.zig");

pub fn render(w: *std.Io.Writer, s: runner.Summary, sim_runs: u32) std.Io.Writer.Error!void {
    try w.print("verified: types, contracts, tests ({d}), property ({d} seeds), sim ({d} runs)\n", .{ s.tests, s.seeds, sim_runs });
    try w.print("          proven: not run\n", .{});
}

test "the line matches chapter 4" {
    var buf: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try render(&w, .{ .tests = 3, .seeds = 200 }, 1_000);
    try std.testing.expectEqualStrings(
        "verified: types, contracts, tests (3), property (200 seeds), sim (1000 runs)\n          proven: not run\n",
        w.buffered(),
    );
}
