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
//! Contracts run in every build (chapter 3): `requires`, `ensures`, and refinements are compiled
//! in and checked unless the build is `--no-contracts`, a measurement; `MO_CONTRACTS=0` or `1`
//! overrides the build at run time. A `never` is compiled in as the tests that check it: a test
//! binary runs every one. A process `invariant` runs after every update, in a test binary and
//! under main alike.
//!
//! Every program compiles, processes and Net included (mo_rt.c): under main each process runs its
//! updates on a thread of its own, the threads taking turns as under `mo run`, and a test binary
//! runs process tests in the fixed order. The seeded runs of `mo test --sim` are the
//! interpreter's and have no compiled form.
//!
//! The bricks (step 35's `src/bricks/crypto.zig`, step 36's `src/bricks/tls.zig`) are inside `mo`
//! too. A build compiles each for the build's target with `zig build-obj -OReleaseFast` (for this
//! machine's CPU when the build has no `--target`, so AES and SHA use the CPU's instructions)
//! once, into `<cache>/.bricks/<hash>/<brick>.o`, the hash taken over that brick's own
//! source, the target, and the zig that compiles it, so a change to one does not rebuild the
//! other; every build for that target links both objects beside the runtime. A brick needs
//! nothing from libc on Linux (`getrandom` is a system call) and only `arc4random_buf` from
//! libSystem on macOS.
//!
//! The runtime is compiled the same way, once per target and set of flags, into
//! `<cache>/.runtime/<hash>/mo_rt.o`, the hash taken over mo_rt.c, mo_rt.h, the target, the flags,
//! and the zig; every build for that target links the object, so a build compiles only its own
//! program. `mo_rt.c` and `mo_rt.h` are still written beside the program's C, so the folder holds
//! everything the binary was made of. `<cache>` is `$MO_CACHE` when set, else `$HOME/.cache/mo`,
//! else the build's own out_dir: one cache for every folder a user builds from.
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
pub const crypto_brick = @embedFile("bricks/crypto.zig");
pub const tls_brick = @embedFile("bricks/tls.zig");

/// A brick `mo build` compiles for the target and links beside the runtime: its name and its
/// source, embedded in `mo`. Each is cached by its own source hash, so a change to one does not
/// rebuild the other.
const Brick = struct { name: []const u8, source: []const u8 };

const bricks = [_]Brick{
    .{ .name = "crypto", .source = crypto_brick },
    .{ .name = "tls", .source = tls_brick },
};

pub const Options = struct {
    name: []const u8,
    /// False only for `mo build --no-contracts`.
    contracts: bool = true,
    tests: bool = false,
    /// `mo build --surface`: `platform.runtime` is `Some` in the binary, and `MO_SURFACE=PORT` serves it (step 23).
    surface: bool = false,
    target: ?[]const u8 = null,
    /// Wrapping arithmetic with no overflow checks, compiled with -fwrapv: the bench's
    /// comparison build, which measures what the checks cost. Never a flag of `mo build`.
    wrap: bool = false,
    /// A define that makes zig cc miss its cache, so a build is timed as a compile and not as
    /// a cache hit: the bench's, never a flag of `mo build`.
    salt: ?u64 = null,
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
    const c = try emit_c.emit(gpa, checked, prog, .{ .tests = options.tests, .contracts = options.contracts, .surface = options.surface });
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
    const target: ?[]const u8 = options.target orelse if (builtin.os.tag == .linux) try std.fmt.allocPrint(gpa, "{t}-linux-musl", .{builtin.cpu.arch}) else null;
    // A build for this machine gets the bricks for this CPU (AES-NI, SHA-NI, carry-less
    // multiply, which std.crypto picks at compile time); a --target build the triple's baseline.
    const cache_dir = try cacheDir(gpa, environ.get("MO_CACHE"), environ.get("HOME"), options.out_dir);
    var objects: [bricks.len][]const u8 = undefined;
    for (bricks, &objects) |brick, *object| {
        object.* = switch (try brickObject(gpa, io, zig, cache_dir, target, options.target == null, brick)) {
            .built => |path| path,
            .failed => |why| return .{ .failed = why },
        };
    }
    const runtime_object = switch (try runtimeObject(gpa, io, zig, cache_dir, options, target)) {
        .built => |path| path,
        .failed => |why| return .{ .failed = why },
    };
    const binary = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dir, options.name });
    var argv: std.ArrayList([]const u8) = .empty;
    try ccFlags(gpa, &argv, zig, options, target);
    if (target) |t| {
        if (std.mem.indexOf(u8, t, "linux") != null) try argv.append(gpa, "-static");
    }
    try argv.appendSlice(gpa, &.{ "-o", binary, c_path, runtime_object });
    try argv.appendSlice(gpa, &objects);
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

/// Where the runtime's and the bricks' objects are kept across builds: `$MO_CACHE`, else
/// `$HOME/.cache/mo`, else the build's out_dir.
pub fn cacheDir(gpa: std.mem.Allocator, mo_cache: ?[]const u8, home: ?[]const u8, out_dir: []const u8) ![]const u8 {
    if (mo_cache) |dir| if (dir.len > 0) return dir;
    if (home) |dir| if (dir.len > 0) return std.fs.path.join(gpa, &.{ dir, ".cache", "mo" });
    return out_dir;
}

/// `zig cc` and the flags every translation unit of a build is compiled with.
fn ccFlags(gpa: std.mem.Allocator, argv: *std.ArrayList([]const u8), zig: []const u8, options: Options, target: ?[]const u8) !void {
    try argv.appendSlice(gpa, &.{ zig, "cc", "-std=c11", "-Wall", "-Werror", "-O2" });
    if (options.wrap) try argv.appendSlice(gpa, &.{ "-fwrapv", "-DMO_WRAP" });
    if (options.salt) |salt| try argv.append(gpa, try std.fmt.allocPrint(gpa, "-DMO_BUILD_SALT={d}", .{salt}));
    if (target) |t| try argv.appendSlice(gpa, &.{ "-target", t });
}

/// The runtime compiled for `target` with the build's flags, from the cache when it is there.
/// Concurrent builds each compile into a file of their own and rename it into place, as the
/// bricks do.
fn runtimeObject(gpa: std.mem.Allocator, io: Io, zig: []const u8, cache_dir: []const u8, options: Options, target: ?[]const u8) !union(enum) { built: []const u8, failed: []const u8 } {
    var h = std.hash.Wyhash.init(0);
    h.update(runtime_c);
    h.update(runtime_h);
    h.update(target orelse "native");
    h.update(if (options.wrap) "wrap" else "checked");
    if (options.salt) |salt| h.update(std.mem.asBytes(&salt));
    h.update(zig);
    const cache = try std.fmt.allocPrint(gpa, "{s}/.runtime/{x:0>16}", .{ cache_dir, h.final() });
    const object = try std.fmt.allocPrint(gpa, "{s}/mo_rt.o", .{cache});
    const cwd = Io.Dir.cwd();
    if (cwd.access(io, object, .{})) |_| return .{ .built = object } else |_| {}
    try cwd.createDirPath(io, cache);
    var nonce: [8]u8 = undefined;
    io.random(&nonce);
    const tag = std.mem.readInt(u64, &nonce, .little);
    const source_dir = try std.fmt.allocPrint(gpa, "{s}/src-{x}", .{ cache, tag });
    try cwd.createDirPath(io, source_dir);
    defer cwd.deleteTree(io, source_dir) catch {};
    const source = try std.fmt.allocPrint(gpa, "{s}/mo_rt.c", .{source_dir});
    try cwd.writeFile(io, .{ .sub_path = source, .data = runtime_c });
    try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(gpa, "{s}/mo_rt.h", .{source_dir}), .data = runtime_h });
    const partial = try std.fmt.allocPrint(gpa, "{s}/mo_rt-{x}.o", .{ cache, tag });
    var argv: std.ArrayList([]const u8) = .empty;
    try ccFlags(gpa, &argv, zig, options, target);
    try argv.appendSlice(gpa, &.{ "-c", "-o", partial, source });
    const ran = std.process.run(gpa, io, .{ .argv = argv.items }) catch |err| {
        return .{ .failed = try std.fmt.allocPrint(gpa, "{s} cc did not run on the runtime: {t}", .{ zig, err }) };
    };
    if (ran.term != .exited or ran.term.exited != 0) {
        return .{ .failed = try std.fmt.allocPrint(gpa, "zig cc rejected the runtime in {s}:\n{s}", .{ cache, ran.stderr }) };
    }
    cwd.rename(partial, cwd, object, io) catch |err| return .{ .failed = try std.fmt.allocPrint(gpa, "the runtime's object did not move into {s}: {t}", .{ object, err }) };
    return .{ .built = object };
}

/// One brick compiled for `target` (null: the host), from the cache when it is there.
/// Concurrent builds each compile into a file of their own and rename it into place, so none
/// links a half-written object.
fn brickObject(gpa: std.mem.Allocator, io: Io, zig: []const u8, cache_dir: []const u8, target: ?[]const u8, host_cpu: bool, brick: Brick) !union(enum) { built: []const u8, failed: []const u8 } {
    var h = std.hash.Wyhash.init(0);
    h.update(brick.source);
    h.update(target orelse "native");
    h.update(if (host_cpu) "host cpu" else "baseline cpu");
    h.update(zig);
    const cache = try std.fmt.allocPrint(gpa, "{s}/.bricks/{x:0>16}", .{ cache_dir, h.final() });
    const object = try std.fmt.allocPrint(gpa, "{s}/{s}.o", .{ cache, brick.name });
    const cwd = Io.Dir.cwd();
    if (cwd.access(io, object, .{})) |_| return .{ .built = object } else |_| {}
    try cwd.createDirPath(io, cache);
    var nonce: [8]u8 = undefined;
    io.random(&nonce);
    const tag = std.mem.readInt(u64, &nonce, .little);
    const source = try std.fmt.allocPrint(gpa, "{s}/{s}-{x}.zig", .{ cache, brick.name, tag });
    const partial = try std.fmt.allocPrint(gpa, "{s}/{s}-{x}.o", .{ cache, brick.name, tag });
    try cwd.writeFile(io, .{ .sub_path = source, .data = brick.source });
    defer cwd.deleteFile(io, source) catch {};
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(gpa, &.{ zig, "build-obj", "-OReleaseFast", "-fno-compiler-rt", "-fstrip", "--name", brick.name });
    if (target) |t| try argv.appendSlice(gpa, &.{ "-target", t });
    if (host_cpu) try argv.appendSlice(gpa, &.{ "-mcpu", "native" });
    try argv.appendSlice(gpa, &.{ try std.fmt.allocPrint(gpa, "-femit-bin={s}", .{partial}), source });
    const ran = std.process.run(gpa, io, .{ .argv = argv.items }) catch |err| {
        return .{ .failed = try std.fmt.allocPrint(gpa, "{s} build-obj did not run on the {s} brick: {t}", .{ zig, brick.name, err }) };
    };
    if (ran.term != .exited or ran.term.exited != 0) {
        return .{ .failed = try std.fmt.allocPrint(gpa, "zig build-obj rejected the {s} brick in {s}:\n{s}", .{ brick.name, cache, ran.stderr }) };
    }
    cwd.rename(partial, cwd, object, io) catch |err| return .{ .failed = try std.fmt.allocPrint(gpa, "the {s} brick's object did not move into {s}: {t}", .{ brick.name, object, err }) };
    return .{ .built = object };
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
