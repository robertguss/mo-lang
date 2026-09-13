//! `mo build` (design-v0/07, build order item 2): a checked program as C (emit_c.zig),
//! compiled with `zig cc` into one binary. Zig is the only dependency: the runtime's source
//! (toolchain/runtime/mo_rt.c and mo_rt.h) is inside `mo`, written beside the program's C for
//! every build, and `zig cc` is the C compiler and the cross-compiler.
//!
//! A build lives in `zig-out/mo-build/<name>/` under the working directory: `<name>.c`,
//! `mo_rt.c`, `mo_rt.h`, and the binary `<name>`. Every file compiles with
//! `-std=c11 -Wall -Werror -O2`. The binary is linked statically wherever the target's libc
//! allows it: a Linux target is built against musl with `-static`; a macOS binary links only
//! libSystem, which Apple does not ship as a static library. `--target` is a zig target triple
//! and nothing else.
//!
//! `zig` is found next to the running `mo`, else on PATH.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const check = @import("check.zig");
const emit_c = @import("emit_c.zig");
const program = @import("program.zig");

pub const runtime_c = @embedFile("mo_rt.c");
pub const runtime_h = @embedFile("mo_rt.h");

pub const Options = struct {
    name: []const u8,
    contracts: bool = false,
    tests: bool = false,
    target: ?[]const u8 = null,
    /// Wrapping arithmetic with no overflow checks, compiled with -fwrapv: the bench's
    /// comparison build, which measures what the checks cost. Never a flag of `mo build`.
    wrap: bool = false,
    /// Where builds go, under the working directory.
    out_dir: []const u8 = "zig-out/mo-build",
};

pub const Built = struct {
    dir: []const u8,
    binary: []const u8,
    /// Emitting the C and writing the files, then `zig cc`.
    emit_ns: i96,
    cc_ns: i96,
};

pub const Outcome = union(enum) {
    built: Built,
    /// What the program uses that does not compile to C yet.
    refused: []const u8,
    /// No zig, or zig cc failed: why, with what it printed.
    failed: []const u8,
};

/// The file's name without `.mo`; for a `main.mo`, its folder's name.
pub fn defaultName(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    const stem = if (std.mem.endsWith(u8, base, ".mo")) base[0 .. base.len - ".mo".len] else base;
    if (!std.mem.eql(u8, stem, "main")) return stem;
    const dir = std.fs.path.dirname(path) orelse return stem;
    const folder = std.fs.path.basename(dir);
    return if (folder.len == 0 or std.mem.eql(u8, folder, ".") or std.mem.eql(u8, folder, "..")) stem else folder;
}

/// Emits, writes, and compiles. Nothing is freed: pass an arena.
pub fn build(gpa: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, prog: program.Program, checked: *const check.Checked, options: Options) !Outcome {
    const t0 = Io.Clock.Timestamp.now(io, .awake);
    const c = switch (try emit_c.emit(gpa, checked, prog, .{ .tests = options.tests, .contracts = options.contracts })) {
        .c => |text| text,
        .refused => |why| return .{ .refused = why },
    };
    const dir = try std.fs.path.join(gpa, &.{ options.out_dir, options.name });
    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, dir);
    const c_path = try std.fmt.allocPrint(gpa, "{s}/{s}.c", .{ dir, options.name });
    const rt_path = try std.fmt.allocPrint(gpa, "{s}/mo_rt.c", .{dir});
    try cwd.writeFile(io, .{ .sub_path = c_path, .data = c });
    try cwd.writeFile(io, .{ .sub_path = rt_path, .data = runtime_c });
    try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(gpa, "{s}/mo_rt.h", .{dir}), .data = runtime_h });
    const t1 = Io.Clock.Timestamp.now(io, .awake);

    const zig = try findZig(gpa, io, environ) orelse return .{ .failed = "there is no zig next to mo or on PATH, and mo build compiles with zig cc" };
    const binary = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir, options.name });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(gpa, &.{ zig, "cc", "-std=c11", "-Wall", "-Werror", "-O2" });
    if (options.wrap) try argv.appendSlice(gpa, &.{ "-fwrapv", "-DMO_WRAP" });
    if (options.target) |t| {
        try argv.appendSlice(gpa, &.{ "-target", t });
        if (std.mem.indexOf(u8, t, "linux") != null) try argv.append(gpa, "-static");
    } else if (builtin.os.tag == .linux) {
        try argv.appendSlice(gpa, &.{ "-target", try std.fmt.allocPrint(gpa, "{t}-linux-musl", .{builtin.cpu.arch}), "-static" });
    }
    try argv.appendSlice(gpa, &.{ "-o", binary, c_path, rt_path });
    const ran = std.process.run(gpa, io, .{ .argv = argv.items }) catch |err| {
        return .{ .failed = try std.fmt.allocPrint(gpa, "{s} cc did not run: {t}", .{ zig, err }) };
    };
    const t2 = Io.Clock.Timestamp.now(io, .awake);
    if (ran.term != .exited or ran.term.exited != 0) {
        return .{ .failed = try std.fmt.allocPrint(gpa, "zig cc rejected the C in {s}:\n{s}", .{ dir, ran.stderr }) };
    }
    return .{ .built = .{
        .dir = dir,
        .binary = binary,
        .emit_ns = t0.durationTo(t1).raw.toNanoseconds(),
        .cc_ns = t1.durationTo(t2).raw.toNanoseconds(),
    } };
}

/// `zig` next to the running `mo`, else the first on PATH.
pub fn findZig(gpa: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map) !?[]const u8 {
    const cwd = Io.Dir.cwd();
    if (std.process.executableDirPathAlloc(io, gpa)) |dir| {
        const beside = try std.fs.path.join(gpa, &.{ dir, "zig" });
        if (cwd.access(io, beside, .{})) |_| return beside else |_| {}
    } else |_| {}
    const path = environ.get("PATH") orelse return null;
    var it = std.mem.tokenizeScalar(u8, path, ':');
    while (it.next()) |entry| {
        const candidate = try std.fs.path.join(gpa, &.{ entry, "zig" });
        if (cwd.access(io, candidate, .{})) |_| return candidate else |_| {}
    }
    return null;
}

test "a build is named by its file, or by its folder for main.mo" {
    try std.testing.expectEqualStrings("hello", defaultName("programs/hello.mo"));
    try std.testing.expectEqualStrings("logstat", defaultName("../examples/programs/logstat/main.mo"));
    try std.testing.expectEqualStrings("main", defaultName("main.mo"));
}
