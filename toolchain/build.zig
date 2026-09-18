const std = @import("std");

// Three executables and three steps.
//   zig build          → zig-out/bin/mo        the toolchain CLI (check, test, run), ReleaseSafe
//   zig build -Ddebug  → zig-out/bin/mo        the same, Debug
//   zig build test     → unit tests of every stage, plus the corpus test, which runs
//                        examples/programs/ through the installed mo (MO_EXE)
//   zig build bench    → zig-out/bin/mo-bench  the benchmark harness, run against ../examples
//   zig build errors   → ../mo-wiki/spec/errors.md, the error catalog, from the diagnostic tables
//   zig build tls-tools → zig-out/bin/mo-tls-peer, mo-tls-fuzz, and mo-tls-limbo, steps 37 and 39's bench tools
// Compile speed is a first-class requirement (design-v0/07), so the harness exists
// before any stage does. bench/rebuild.sh times this build file itself.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // mo is ReleaseSafe: Mo's overflow checks are the vm's own in every mode, and Zig's
    // safety checks stay on. -Ddebug builds it in Debug.
    const debug = b.option(bool, "debug", "Build mo in Debug instead of ReleaseSafe") orelse false;
    const optimize: std.builtin.OptimizeMode = if (debug) .Debug else .ReleaseSafe;

    const mo = b.addModule("mo", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    // mo build writes the C runtime beside every program's C (src/cbuild.zig).
    mo.addAnonymousImport("mo_rt.c", .{ .root_source_file = b.path("runtime/mo_rt.c") });
    mo.addAnonymousImport("mo_rt.h", .{ .root_source_file = b.path("runtime/mo_rt.h") });

    const exe = b.addExecutable(.{
        .name = "mo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "mo", .module = mo }},
        }),
    });
    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
    const mo_path = b.getInstallPath(.bin, "mo");

    const run_step = b.step("run", "Run mo with the args after --");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    // -Dtest-filter=name runs only the tests whose names hold it (the corpus test among them
    // only when it matches).
    const filters = b.option([]const []const u8, "test-filter", "Run only the tests whose names hold this") orelse &.{};
    const mod_tests = b.addTest(.{ .root_module = mo, .filters = filters });
    const test_step = b.step("test", "Run every stage's tests and the corpus test");
    const run_tests = b.addRunArtifact(mod_tests);
    run_tests.setEnvironmentVariable("MO_EXE", mo_path);
    run_tests.step.dependOn(&install_exe.step);
    test_step.dependOn(&run_tests.step);

    // The error catalog page, rendered from the diagnostic tables (src/errors.zig). The
    // corpus test fails when the page on disk is not this.
    const errors_exe = b.addExecutable(.{
        .name = "mo-errors",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/errors_gen.zig"),
            .target = target,
            .imports = &.{.{ .name = "mo", .module = mo }},
        }),
    });
    const errors_step = b.step("errors", "Regenerate ../mo-wiki/spec/errors.md from the diagnostic tables");
    const errors_cmd = b.addRunArtifact(errors_exe);
    errors_cmd.setCwd(b.path("."));
    errors_cmd.addArg("../mo-wiki/spec/errors.md");
    errors_step.dependOn(&errors_cmd.step);

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

    // zig build tls-tools → zig-out/bin/mo-tls-peer and mo-tls-fuzz, step 37's two tools over the
    // TLS brick (bench/step37): the differential run's peer, which drives the brick's exports over
    // a real socket against OpenSSL, and the fuzz driver, a test executable so the brick's test
    // hooks (fixed entropy) exist. Both ReleaseSafe: a fuzzed input that trips a safety check
    // must panic, not run on.
    const brick_mod = b.createModule(.{ .root_source_file = b.path("src/bricks/tls.zig"), .target = target, .optimize = .ReleaseSafe });
    const peer_exe = b.addExecutable(.{
        .name = "mo-tls-peer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/step37/peer.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "tls_brick", .module = brick_mod }},
        }),
    });
    const fuzz_exe = b.addTest(.{
        .name = "mo-tls-fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/step37/fuzz.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "tls_brick", .module = brick_mod }},
        }),
    });
    // And step 39's: the x509-limbo run's checker, the brick's chain check on each case.
    const limbo_exe = b.addExecutable(.{
        .name = "mo-tls-limbo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/step39/limbo.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "tls_brick", .module = brick_mod }},
        }),
    });
    const tools_step = b.step("tls-tools", "Build steps 37 and 39's TLS peer, fuzz driver, and limbo checker into zig-out/bin");
    tools_step.dependOn(&b.addInstallArtifact(peer_exe, .{}).step);
    tools_step.dependOn(&b.addInstallArtifact(fuzz_exe, .{}).step);
    tools_step.dependOn(&b.addInstallArtifact(limbo_exe, .{}).step);
    const bench_step = b.step("bench", "Time every stage over ../examples (args after -- go to mo-bench)");
    const bench_cmd = b.addRunArtifact(bench_exe);
    bench_cmd.step.dependOn(b.getInstallStep());
    bench_cmd.setEnvironmentVariable("MO_EXE", mo_path);
    if (b.args) |args| bench_cmd.addArgs(args);
    bench_step.dependOn(&bench_cmd.step);
}
