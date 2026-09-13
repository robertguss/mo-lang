const std = @import("std");

// Two executables and two steps.
//   zig build          → zig-out/bin/mo        the toolchain CLI (check, test, run)
//   zig build test     → unit tests of every stage, plus the corpus test
//   zig build bench    → zig-out/bin/mo-bench  the benchmark harness, run against ../examples
// Compile speed is a first-class requirement (design-v0/07), so the harness exists
// before any stage does. bench/rebuild.sh times this build file itself.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mo = b.addModule("mo", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "mo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "mo", .module = mo }},
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run mo with the args after --");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = mo });
    const test_step = b.step("test", "Run every stage's tests and the corpus test");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);

    const bench_exe = b.addExecutable(.{
        .name = "mo-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "mo", .module = mo }},
        }),
    });
    b.installArtifact(bench_exe);
    const bench_step = b.step("bench", "Time every stage over ../examples (args after -- go to mo-bench)");
    const bench_cmd = b.addRunArtifact(bench_exe);
    bench_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| bench_cmd.addArgs(args);
    bench_step.dependOn(&bench_cmd.step);
}
