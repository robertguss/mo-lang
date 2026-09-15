//! Mo.Server: the real platform `mo run` gives `main` (design-v0/03, effects; Q18), over
//! std.Io. `args` and `env` come from the process; `Out.write` goes to the real streams,
//! buffered, and flushed by `Out.flush` and at exit; the `Fs` rows read and write the real
//! file system under the scope `scoped(...)` gave, each write on disk (fsync) before it
//! answers; `clock.now` is the wall clock; `exit(code)` is recorded and applied when `main`
//! returns. No database.
//!
//! main is the root supervisor: a process it starts, directly or through a supervisor,
//! runs on Mo.Sim's scheduler in its fixed order (sim.zig). main's sends are delivered
//! before its next statement runs, an update may use the capabilities its process was
//! started with, and when main returns the run goes on until no message is waiting. A
//! process crash is reported on stderr as it happens and its supervisor restarts it; a
//! supervisor that gives up crashes main. main and every process free what they no longer
//! reach at safe points (vm.zig), and a process keeps nothing of an update past what its
//! new state reaches (sim.zig, settleRegion).
//!
//! An Fs value is pointer-free: `Value.Cap.handle` is its index in `Server.scopes`.
const std = @import("std");
const sources = @import("sources.zig");
const Io = std.Io;
const bytecode = @import("bytecode.zig");
const contracts = @import("contracts.zig");
const diag = @import("diag.zig");
const net = @import("net.zig");
const prelude = @import("prelude.zig");
const runner = @import("runner.zig");
const stdlib = @import("stdlib.zig");
const Sim = @import("sim.zig").Sim;
const turns_mod = @import("turns.zig");
const Turns = turns_mod.Turns;
const surface_mod = @import("surface.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Region = @import("region.zig").Region;

/// The vm's errors, since the rows build values with it; only OutOfMemory comes from here.
pub const Error = vm_mod.Error;

/// The largest file `Fs.read` gives; a larger one is `Missing`, like any file it cannot read.
pub const read_limit = 64 << 20;

/// `Value.Cap.handle` of an Out.
pub const stdout_handle: u32 = 1;
pub const stderr_handle: u32 = 2;

pub const Scope = struct {
    /// Where a relative path starts: the working directory, or the folder scoped to.
    base: []const u8,
    /// Nothing outside this folder is read. "/" for `platform.fs` itself.
    root: []const u8,
    /// A write through it crashes; tier 1 refuses the ones it can see (MO0404).
    read_only: bool = false,
    /// `scoped` was given a path outside the scope it narrowed, so nothing is readable.
    empty: bool = false,
};

pub const Ran = union(enum) { exited: u8, crashed: contracts.Report };

pub const Server = struct {
    gpa: std.mem.Allocator,
    io: Io,
    args: []const []const u8,
    environ: *const std.process.Environ.Map,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    /// Every Fs the run has narrowed to; 0 is `platform.fs`.
    scopes: std.ArrayList(Scope) = .empty,
    /// The last `platform.exit(code)`, or 0.
    exit_code: u8 = 0,
    /// main called exit: once it returns, the runtime's loops stop (sources.zig).
    exited: bool = false,
    /// The program's files, so a process crash reported on stderr names its line.
    files: []const diag.File = &.{},
    /// `platform.net`'s listeners and connections (net.zig).
    sockets: net.Net,
    /// `mo run --clock` (or MO_CLOCK): the time main's clock starts at, in milliseconds since
    /// the epoch, and the wall clock when it was set; the clock then advances with the wall.
    /// Null: the clock is the wall's.
    clock_start: ?i64 = null,
    wall_start: i64 = 0,
    /// After a run, how many process ids it used: a process that finished gives its id to
    /// the next one started (turns.zig, sweep).
    ids_used: usize = 0,
    /// The events the run keeps (events.zig): `mo run --events N`, 4,096 by default (step 23).
    events_cap: u32 = @import("events.zig").default_cap,
    /// `mo run --surface PORT`: the runtime surface is served over HTTP on 127.0.0.1 from before
    /// main runs (step 23); the program must hold its module (program.withSurface).
    surface_port: ?u16 = null,

    /// `cwd` is the absolute working directory a relative path starts from. Nothing is
    /// freed: pass an arena.
    pub fn init(gpa: std.mem.Allocator, io: Io, cwd: []const u8, args: []const []const u8, environ: *const std.process.Environ.Map, stdout: *Io.Writer, stderr: *Io.Writer) Error!Server {
        var s: Server = .{ .gpa = gpa, .io = io, .args = args, .environ = environ, .stdout = stdout, .stderr = stderr, .sockets = .{ .io = io, .gpa = gpa } };
        try s.scopes.append(gpa, .{ .base = cwd, .root = "/" });
        return s;
    }

    /// Calls `main` (functions[main_fn]) with the Platform. The exit code is the last
    /// `platform.exit(code)`, or 0; a crash comes back with its complete report.
    pub fn run(s: *Server, program: *const bytecode.Program, main_fn: u32) Error!Ran {
        // `MO_STATS=1` reads this thread's counts, and each scheduler's (main.zig).
        @import("region.zig").main_stats = &@import("region.zig").stats;
        var machine: Vm = .init(s.gpa, program, 0);
        machine.server = s;
        var scheduler: Sim = .init(&machine, 0, "main");
        scheduler.server = s;
        scheduler.ring = .{ .cap = s.events_cap, .wall_ms = s.now(), .mono_us = s.monoUs() };
        defer s.ids_used = scheduler.procs.items.len;
        machine.sim = &scheduler;
        // Values live in regions freed at safe points (vm.zig): main's here, and each
        // process's in one of its own (turns.zig), each compacting through its scheduler's
        // scratch region, main's and scheduler 0's this one. A value that goes from one vm to
        // another goes packed (Sim.packs), so no compaction needs to see another vm's values.
        // Without the address space for the regions, every value lives until the run ends.
        const processes = program.processes.len > 0;
        var values: ?Region = Region.reserve() catch null;
        defer if (values) |*r| r.release();
        var scratch: ?Region = if (values != null) Region.reserve() catch null else null;
        defer if (scratch) |*r| r.release();
        const regions = values != null and scratch != null;
        if (regions) machine.useRegions(&values.?, &scratch.?);
        if (regions) scheduler.main_region = &values.?;
        defer s.sockets.closeAll();
        // Each process runs its updates on a fiber of its own on its scheduler's thread, a
        // scheduler per core, so one waiting on the network does not hold up the rest (turns.zig).
        var turns: Turns = .{ .io = s.io, .gpa = s.gpa };
        defer if (processes) turns.stop(&scheduler);
        if (processes) {
            scheduler.turns = &turns;
            if (regions) scheduler.packs = true;
            // A scheduler per core (step 30): MO_CORES, else the machine's cores.
            try turns.begin(&scheduler, &machine, turns_mod.coresFrom(s.environ.get("MO_CORES")), if (regions) &scratch.? else null);
        }
        runMain(&machine, &scheduler, main_fn) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            // A recipe signature with no body stops main as surely as a crash does.
            error.Crash, error.Skip => return .{ .crashed = machine.report.? },
            // any(T) belongs to properties, which main is not.
            error.Discard => unreachable,
        };
        return .{ .exited = s.exit_code };
    }

    /// main, then every message still waiting.
    fn runMain(machine: *Vm, scheduler: *Sim, main_fn: u32) Error!void {
        if (machine.server.?.surface_port) |port| try startSurface(machine, scheduler, port);
        _ = try machine.call(main_fn, &.{.{ .cap = .{ .kind = .platform } }});
        // A served listener keeps the program running until it is stopped, unless main
        // called exit: then the program ends at once (step 29): the runtime stops accepting and
        // reading, drops every delayed send with an event, delivers what already waits, and
        // waits for nothing.
        if (machine.server.?.exited) {
            if (scheduler.turns) |t| sources.stopServer(scheduler, t);
            scheduler.exitNow();
        }
        try scheduler.finish();
    }

    /// The runtime surface's module serves the rows over HTTP on 127.0.0.1 at `port` (step 23),
    /// from a process the surface does not show and whose listener does not keep the program
    /// running; a line on stderr says where, or that the port could not be had.
    fn startSurface(machine: *Vm, scheduler: *Sim, port: u16) Error!void {
        const s = machine.server.?;
        const at = surface_mod.entry(machine.program) orelse return;
        scheduler.hidden_process = at.process;
        const got = try machine.call(at.function, &.{ .{ .cap = .{ .kind = .runtime } }, .{ .cap = .{ .kind = .http } }, .{ .int = port } });
        if (got.int == 0) {
            s.stderr.print("runtime surface: 127.0.0.1:{d} could not be had\n", .{port}) catch {};
        } else s.stderr.print("runtime surface: http://127.0.0.1:{d}\n", .{@as(u64, @intCast(got.int))}) catch {};
        s.stderr.flush() catch {};
    }

    /// A process crashed: its complete report goes to stderr as it happens (design-v0/03,
    /// failure), and its supervisor does what the child line says.
    pub fn processCrashed(s: *Server, report: contracts.Report) void {
        var r = report;
        if (s.files.len == 0) r.at = 0;
        s.stderr.writeAll("process crashed: ") catch {};
        runner.writeReport(s.stderr, s.files, r) catch {};
        s.stderr.writeAll("\n") catch {};
    }

    // ---- the rows (vm.zig dispatches here when a run has a server)

    /// `platform.args`, `.env`, `.stdout`, `.stderr`, `.fs`, `.clock`.
    pub fn part(s: *Server, vm: *Vm, name: []const u8) Error!Value {
        if (std.mem.eql(u8, name, "args")) {
            const out = try vm_mod.rawAlloc(vm.heap, Value, s.args.len);
            for (s.args, out) |a, *o| o.* = .{ .string = a };
            return .{ .list = out };
        }
        // Under mo run the runtime surface is on (step 23).
        if (std.mem.eql(u8, name, "runtime")) return vm.variant("Some", &.{.{ .cap = .{ .kind = .runtime } }});
        const cap: Value.Cap = if (std.mem.eql(u8, name, "env"))
            .{ .kind = .env }
        else if (std.mem.eql(u8, name, "stdout"))
            .{ .kind = .out, .handle = stdout_handle }
        else if (std.mem.eql(u8, name, "stderr"))
            .{ .kind = .out, .handle = stderr_handle }
        else if (std.mem.eql(u8, name, "fs"))
            .{ .kind = .fs }
        else if (std.mem.eql(u8, name, "net"))
            .{ .kind = .net }
        else if (std.mem.eql(u8, name, "http"))
            .{ .kind = .http }
        else
            .{ .kind = .clock };
        return .{ .cap = cap };
    }

    pub fn exit(s: *Server, code: i128) void {
        s.exit_code = @intCast(code);
        s.exited = true;
    }

    pub fn envGet(s: *Server, vm: *Vm, name: []const u8) Error!Value {
        const v = s.environ.get(name) orelse return vm.variant("None", &.{});
        return vm.variant("Some", &.{.{ .string = v }});
    }

    /// `Out.write` cannot fail in its signature, so a stream that is gone (a closed pipe)
    /// drops the text.
    pub fn write(s: *Server, out: Value.Cap, text: []const u8) void {
        const w = if (out.handle == stderr_handle) s.stderr else s.stdout;
        w.writeAll(text) catch {};
    }

    /// `out.flush`: what the stream holds goes out now, not when main returns.
    pub fn flush(s: *Server, out: Value.Cap) void {
        const w = if (out.handle == stderr_handle) s.stderr else s.stdout;
        w.flush() catch {};
    }

    /// Milliseconds since the Unix epoch, as `Value.time` counts: the wall clock, or from
    /// `--clock`'s start as far as the wall clock has moved since.
    pub fn now(s: *Server) i64 {
        const wall = Io.Clock.real.now(s.io).toMilliseconds();
        const start = s.clock_start orelse return wall;
        return start + (wall - s.wall_start);
    }

    /// The events' clock (events.zig): the awake clock, in microseconds.
    pub fn monoUs(s: *const Server) i64 {
        return @intCast(@divFloor(Io.Clock.Timestamp.now(s.io, .awake).raw.toNanoseconds(), 1000));
    }

    /// The clock starts at `start` now (`mo run --clock`).
    pub fn startClock(s: *Server, start: i64) void {
        s.wall_start = Io.Clock.real.now(s.io).toMilliseconds();
        s.clock_start = start;
    }

    /// `fs.scoped(path)` and `fs.read_only`: a new scope, never a wider one. A path is
    /// resolved against the scope's folder; one that leaves the scope gives an Fs that
    /// reads nothing.
    pub fn narrow(s: *Server, fs: Value.Cap, name: []const u8, path: []const u8) Error!Value {
        var scope = s.scopes.items[fs.handle];
        if (std.mem.eql(u8, name, "read_only")) {
            scope.read_only = true;
        } else {
            const full = try std.fs.path.resolve(s.gpa, &.{ scope.base, path });
            scope.base = full;
            if (within(scope.root, full)) scope.root = full else scope.empty = true;
        }
        const handle: u32 = @intCast(s.scopes.items.len);
        try s.scopes.append(s.gpa, scope);
        return .{ .cap = .{ .kind = .fs, .handle = handle } };
    }

    /// `fs.read(path, within: d)`: `Ok(text)`; `Missing(path)`, with the path as the
    /// program wrote it, for anything that is not a readable file inside the scope (a
    /// symbolic link that leads out of it included); or `Timeout`.
    ///
    /// The deadline is enforced after the fact in this step: the read runs to its end, is
    /// measured, and one that took longer than `d` is `Timeout`, its text dropped. True
    /// cancellation comes with the async runtime, which suspends the call at its deadline.
    pub fn read(s: *Server, vm: *Vm, fs: Value.Cap, path: []const u8, within_ms: i64) Error!Value {
        return s.readAs(vm, fs, path, within_ms, .text);
    }

    /// `read`, `read_lines`, and `read_bytes`: the file read whole, then given as `as` says;
    /// `NotText` for text or lines that are not UTF-8 (stdlib.readResult).
    pub fn readAs(s: *Server, vm: *Vm, fs: Value.Cap, path: []const u8, within_ms: i64, as: stdlib.ReadAs) Error!Value {
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        const text = try s.readScoped(s.scopes.items[fs.handle], path);
        if (s.late(t0, within_ms)) return vm.variant("Error", &.{try vm.variant("Timeout", &.{})});
        const got = text orelse return missing(vm, path);
        return stdlib.readResult(vm, got, as);
    }

    /// `fs.fold_lines(path, acc, within: d, f)`: each line of a file inside the scope handed to
    /// `f` with the value so far as the file is read (stdlib.LineFeed), so no more of it than its
    /// longest line is held; `read`'s answers for a file it cannot read, and for a line past
    /// `read_limit`. The deadline is checked before each read, and the calls already made stay
    /// made; `Ok` holds the value the last call gave.
    pub fn foldLines(s: *Server, vm: *Vm, fs: Value.Cap, path: []const u8, f: Value.Func, acc: Value, within_ms: i64) Error!Value {
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        const real = try s.realScoped(s.scopes.items[fs.handle], path) orelse
            return if (s.late(t0, within_ms)) timeout(vm) else missing(vm, path);
        const file = Io.Dir.cwd().openFile(s.io, real, .{}) catch
            return if (s.late(t0, within_ms)) timeout(vm) else missing(vm, path);
        defer file.close(s.io);
        var feed: stdlib.LineFeed = .init(vm, f, acc);
        var chunk: [1 << 16]u8 = undefined;
        var buffers = [_][]u8{&chunk};
        while (true) {
            if (s.late(t0, within_ms)) return timeout(vm);
            const n = file.readStreaming(s.io, &buffers) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return missing(vm, path),
            };
            try feed.bytes(chunk[0..n]);
            if (feed.partial.items.len > read_limit) return missing(vm, path);
        }
        try feed.end();
        return vm.variant("Ok", &.{feed.acc});
    }

    /// `fs.size(path, within: d)`: `Ok(bytes)` of a file inside the scope; anything else
    /// is `Missing(path)`, or `Timeout`, as `read` answers.
    pub fn size(s: *Server, vm: *Vm, fs: Value.Cap, path: []const u8, within_ms: i64) Error!Value {
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        const bytes: ?u64 = blk: {
            const real = try s.realScoped(s.scopes.items[fs.handle], path) orelse break :blk null;
            const stat = Io.Dir.cwd().statFile(s.io, real, .{}) catch break :blk null;
            break :blk if (stat.kind == .file) stat.size else null;
        };
        if (s.late(t0, within_ms)) return vm.variant("Error", &.{try vm.variant("Timeout", &.{})});
        const n = bytes orelse return missing(vm, path);
        return vm.variant("Ok", &.{.{ .int = n }});
    }

    /// `fs.list(within: d)`: the names of the files and folders directly inside the
    /// scope's folder, sorted byte by byte; `Missing(".")` when it is not a readable folder.
    /// With `kinds`, `fs.list_kinds`: each name as an `Entry` that says whether it is a folder (step 28).
    pub fn list(s: *Server, vm: *Vm, fs: Value.Cap, within_ms: i64, kinds: bool) Error!Value {
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        const names = try s.listScoped(s.scopes.items[fs.handle]);
        if (s.late(t0, within_ms)) return vm.variant("Error", &.{try vm.variant("Timeout", &.{})});
        const got = names orelse return missing(vm, ".");
        const out = try vm_mod.rawAlloc(vm.heap, Value, got.len);
        for (got, out) |entry, *o| o.* = if (kinds) try stdlib.entryOf(vm, entry.name, entry.folder) else .{ .string = entry.name };
        return vm.variant("Ok", &.{.{ .list = out }});
    }

    /// `fs.write(path, text)` and `fs.append(path, text)`: the file holds the text, or has it
    /// added at its end, created when it is not there, and is on disk (fsync) before `Ok`.
    /// `Missing(path)` for a path that leaves the scope, a folder that is not there, or
    /// anything that is not a file. The deadline is enforced after the fact, as `read`'s is:
    /// a write that took longer is `Timeout`, and is on disk all the same.
    pub fn writeFile(s: *Server, vm: *Vm, row: prelude.Fn, fs: Value.Cap, path: []const u8, text: []const u8, within_ms: i64, append: bool) Error!Value {
        const scope = s.scopes.items[fs.handle];
        if (scope.read_only) return refuse(vm, row, path);
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        // Paths are resolved in an arena of the call's own: a server appends on every change.
        var scratch = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
        defer scratch.deinit();
        const wrote = try s.writeScoped(scratch.allocator(), scope, path, text, append);
        if (s.late(t0, within_ms)) return timeout(vm);
        if (!wrote) return missing(vm, path);
        return vm.variant("Ok", &.{.none});
    }

    fn writeScoped(s: *Server, gpa: std.mem.Allocator, scope: Scope, path: []const u8, text: []const u8, append: bool) Error!bool {
        const target = try s.targetScoped(gpa, scope, path) orelse return false;
        var file = Io.Dir.cwd().createFile(s.io, target, .{ .truncate = !append }) catch return false;
        defer file.close(s.io);
        const at: u64 = if (append) file.length(s.io) catch return false else 0;
        file.writePositionalAll(s.io, text, at) catch return false;
        file.sync(s.io) catch return false;
        return true;
    }

    /// `fs.remove(path)`: the file is gone; `Missing(path)` when no such file is in the scope.
    pub fn remove(s: *Server, vm: *Vm, row: prelude.Fn, fs: Value.Cap, path: []const u8, within_ms: i64) Error!Value {
        const scope = s.scopes.items[fs.handle];
        if (scope.read_only) return refuse(vm, row, path);
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        var scratch = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
        defer scratch.deinit();
        const gone = blk: {
            const real = try s.fileScoped(scratch.allocator(), scope, path) orelse break :blk false;
            Io.Dir.cwd().deleteFile(s.io, real) catch break :blk false;
            break :blk true;
        };
        if (s.late(t0, within_ms)) return timeout(vm);
        if (!gone) return missing(vm, path);
        return vm.variant("Ok", &.{.none});
    }

    /// `fs.mkdir(path)`: a folder at `path`, made when it is not there, in a folder that is.
    /// `Missing(path)` when the path leaves the scope, its folder is not there, or a file is
    /// at it. The folder is not synced: a write into it syncs the file, not the folder.
    pub fn mkdir(s: *Server, vm: *Vm, row: prelude.Fn, fs: Value.Cap, path: []const u8, within_ms: i64) Error!Value {
        const scope = s.scopes.items[fs.handle];
        if (scope.read_only) return refuse(vm, row, path);
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        var scratch = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
        defer scratch.deinit();
        const made = blk: {
            const target = try s.targetScoped(scratch.allocator(), scope, path) orelse break :blk false;
            Io.Dir.cwd().createDir(s.io, target, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    const stat = Io.Dir.cwd().statFile(s.io, target, .{}) catch break :blk false;
                    break :blk stat.kind == .directory;
                },
                else => break :blk false,
            };
            break :blk true;
        };
        if (s.late(t0, within_ms)) return timeout(vm);
        if (!made) return missing(vm, path);
        return vm.variant("Ok", &.{.none});
    }

    /// `fs.rename(from, to)`: the file at `from` is at `to`, replacing a file there.
    /// `Missing(from)` when no such file is in the scope, `Missing(to)` when `to` leaves it
    /// or names a folder that is not there.
    pub fn rename(s: *Server, vm: *Vm, row: prelude.Fn, fs: Value.Cap, from: []const u8, to: []const u8, within_ms: i64) Error!Value {
        const scope = s.scopes.items[fs.handle];
        if (scope.read_only) return refuse(vm, row, from);
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        var scratch = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
        defer scratch.deinit();
        const gpa = scratch.allocator();
        const missed: ?[]const u8 = blk: {
            const real = try s.fileScoped(gpa, scope, from) orelse break :blk from;
            const target = try s.targetScoped(gpa, scope, to) orelse break :blk to;
            Io.Dir.rename(Io.Dir.cwd(), real, Io.Dir.cwd(), target, s.io) catch break :blk to;
            break :blk null;
        };
        if (s.late(t0, within_ms)) return timeout(vm);
        if (missed) |p| return missing(vm, p);
        return vm.variant("Ok", &.{.none});
    }

    /// The real path of a file (not a folder) inside the scope, or null.
    fn fileScoped(s: *Server, gpa: std.mem.Allocator, scope: Scope, path: []const u8) Error!?[]const u8 {
        const real = try s.realScopedIn(gpa, scope, path) orelse return null;
        const stat = Io.Dir.cwd().statFile(s.io, real, .{}) catch return null;
        return if (stat.kind == .file) real else null;
    }

    /// Where a write to `path` lands: its folder's real path and its name, when that folder is
    /// inside the scope, and a name already there, which may be a link, leads inside it too.
    fn targetScoped(s: *Server, gpa: std.mem.Allocator, scope: Scope, path: []const u8) Error!?[]const u8 {
        if (scope.empty) return null;
        const full = try std.fs.path.resolve(gpa, &.{ scope.base, path });
        if (!within(scope.root, full) or std.mem.eql(u8, full, scope.root)) return null;
        const cwd = Io.Dir.cwd();
        const real_root = cwd.realPathFileAlloc(s.io, scope.root, gpa) catch |err| return unreadable(err);
        const folder = std.fs.path.dirname(full) orelse return null;
        const real_folder = cwd.realPathFileAlloc(s.io, folder, gpa) catch |err| return unreadable(err);
        if (!within(real_root, real_folder)) return null;
        const target = try std.fs.path.join(gpa, &.{ real_folder, std.fs.path.basename(full) });
        if (cwd.realPathFileAlloc(s.io, target, gpa)) |real| {
            if (!within(real_root, real)) return null;
        } else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
        return target;
    }

    /// Whether a call that began at `t0` took longer than its deadline. Enforced after the
    /// fact in this step (see `read`).
    fn late(s: *Server, t0: Io.Clock.Timestamp, within_ms: i64) bool {
        const ns = t0.durationTo(Io.Clock.Timestamp.now(s.io, .awake)).raw.toNanoseconds();
        return ns > @as(i96, within_ms) * std.time.ns_per_ms;
    }

    /// The real path of `path` under the scope, or null when it is outside the scope or
    /// is not there. Compared again as real paths, so a symbolic link inside the scope
    /// cannot reach out.
    fn realScoped(s: *Server, scope: Scope, path: []const u8) Error!?[]const u8 {
        return s.realScopedIn(s.gpa, scope, path);
    }

    fn realScopedIn(s: *Server, gpa: std.mem.Allocator, scope: Scope, path: []const u8) Error!?[]const u8 {
        if (scope.empty) return null;
        const full = try std.fs.path.resolve(gpa, &.{ scope.base, path });
        if (!within(scope.root, full)) return null;
        const cwd = Io.Dir.cwd();
        const real_root = cwd.realPathFileAlloc(s.io, scope.root, gpa) catch |err| return unreadable(err);
        const real = cwd.realPathFileAlloc(s.io, full, gpa) catch |err| return unreadable(err);
        if (!within(real_root, real)) return null;
        return real;
    }

    fn readScoped(s: *Server, scope: Scope, path: []const u8) Error!?[]const u8 {
        const real = try s.realScoped(scope, path) orelse return null;
        return Io.Dir.cwd().readFileAlloc(s.io, real, s.gpa, .limited(read_limit)) catch |err| unreadable(err);
    }

    const Listed = struct { name: []const u8, folder: bool };

    fn listScoped(s: *Server, scope: Scope) Error!?[]const Listed {
        const real = try s.realScoped(scope, ".") orelse return null;
        var dir = Io.Dir.cwd().openDir(s.io, real, .{ .iterate = true }) catch return null;
        defer dir.close(s.io);
        var names: std.ArrayList(Listed) = .empty;
        var it = dir.iterate();
        while (it.next(s.io) catch return null) |entry| {
            // A link counts as what it points at.
            const folder = entry.kind == .directory or (entry.kind == .sym_link and if (dir.statFile(s.io, entry.name, .{})) |st| st.kind == .directory else |_| false);
            try names.append(s.gpa, .{ .name = try s.gpa.dupe(u8, entry.name), .folder = folder });
        }
        std.mem.sort(Listed, names.items, {}, struct {
            fn lt(_: void, a: Listed, b: Listed) bool {
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lt);
        return names.items;
    }
};

fn missing(vm: *Vm, path: []const u8) Error!Value {
    return vm.variant("Error", &.{try vm.variant("Missing", &.{.{ .string = path }})});
}

fn timeout(vm: *Vm) Error!Value {
    return vm.variant("Error", &.{try vm.variant("Timeout", &.{})});
}

/// A write through an Fs narrowed to read_only: the caller broke the scope's rule, which
/// tier 1 refuses where it can see the narrowing (caps.zig, MO0404).
fn refuse(vm: *Vm, row: prelude.Fn, path: []const u8) Error!Value {
    vm.report = .{ .kind = .other, .clause = try std.fmt.allocPrint(vm.gpa, "fs.{s}(\"{s}\") writes through an Fs narrowed to read_only, which only reads", .{ row.name, path }), .within = row.name, .at = 0 };
    return error.Crash;
}

fn unreadable(err: anyerror) Error!?[]const u8 {
    return if (err == error.OutOfMemory) error.OutOfMemory else null;
}

/// Whether the resolved absolute `path` is `root` or inside it.
pub fn within(root: []const u8, path: []const u8) bool {
    if (std.mem.eql(u8, root, "/")) return true;
    if (!std.mem.startsWith(u8, path, root)) return false;
    return path.len == root.len or path[root.len] == '/';
}

// ---- tests

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const caps = @import("caps.zig");

fn compile(arena: std.mem.Allocator, src: []const u8) !*bytecode.Program {
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    const checked = try check.check(arena, tree, &diags);
    try caps.check(arena, checked, &diags);
    for (diags.items) |d| std.debug.print("{s} at {d}: {s}\n", .{ d.code, d.at, d.what });
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);
    const program = try arena.create(bytecode.Program);
    program.* = try bytecode.lower(arena, checked);
    return program;
}

test "within: a path is its root or below it, never a sibling that shares the prefix" {
    try std.testing.expect(within("/", "/etc"));
    try std.testing.expect(within("/a/data", "/a/data"));
    try std.testing.expect(within("/a/data", "/a/data/x.txt"));
    try std.testing.expect(!within("/a/data", "/a/database"));
    try std.testing.expect(!within("/a/data", "/a"));
}

test "main on Mo.Server: args, env, both streams, a scoped read that cannot escape, a late read, exit" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "data");
    try tmp.dir.writeFile(io, .{ .sub_path = "secret.txt", .data = "s\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "data/lines.txt", .data = "a\nb\n" });
    try tmp.dir.symLink(io, "../secret.txt", "data/link.txt", .{});
    const cwd = try tmp.dir.realPathFileAlloc(io, ".", arena);

    const program = try compile(arena,
        \\module T.Server
        \\fn describe(r: Result(String, FsError)) : String
        \\  case r
        \\    Ok(text): "ok #{text}"
        \\    Error(Missing(path)): "missing #{path}\n"
        \\    Error(Timeout): "timeout\n"
        \\    Error(NotText): "not text\n"
        \\  end
        \\end
        \\fn main(platform: Platform)
        \\  data = platform.fs.scoped("data").read_only
        \\  out = platform.stdout
        \\  out.write(describe(data.read("lines.txt", within: 1.minute)))
        \\  out.write(describe(data.read("../secret.txt", within: 1.minute)))
        \\  out.write(describe(data.read("link.txt", within: 1.minute)))
        \\  out.write(describe(data.scoped("..").read("secret.txt", within: 1.minute)))
        \\  out.write(describe(platform.fs.read("secret.txt", within: 1.minute)))
        \\  out.write(describe(data.read("lines.txt", within: 0.ms)))
        \\  said = platform.env.get("MO_TEST") or "unset"
        \\  platform.stderr.write("#{platform.args.size} args, #{said}\n")
        \\  platform.exit(3)
        \\end
    );
    var environ: std.process.Environ.Map = .init(arena);
    try environ.put("MO_TEST", "yes");
    var out: Io.Writer.Allocating = .init(arena);
    var err: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, io, cwd, &.{ "x", "y" }, &environ, &out.writer, &err.writer);
    const ran = try server.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(@as(u8, 3), ran.exited);
    try std.testing.expectEqualStrings(
        \\ok a
        \\b
        \\missing ../secret.txt
        \\missing link.txt
        \\missing secret.txt
        \\ok s
        \\timeout
        \\
    , out.written());
    try std.testing.expectEqualStrings("2 args, yes\n", err.written());
    try std.testing.expect(server.now() > vm_mod.fixture_time);
}

test "Fs.list, read_lines, and size stay inside the scope, and write_line ends a line" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "data/sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "secret.txt", .data = "s\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "data/b.txt", .data = "x\r\ny\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "data/a.txt", .data = "" });
    const cwd = try tmp.dir.realPathFileAlloc(io, ".", arena);

    const program = try compile(arena,
        \\module T.Files
        \\fn names(r: Result(List(String), FsError)) : String
        \\  case r
        \\    Ok(xs): String.join(xs, ",")
        \\    Error(Missing(path)): "missing #{path}"
        \\    Error(Timeout): "timeout"
        \\    Error(NotText): "not text"
        \\  end
        \\end
        \\fn bytes(r: Result(UInt64, FsError)) : String
        \\  case r
        \\    Ok(n): "#{n}"
        \\    Error(Missing(path)): "missing #{path}"
        \\    Error(Timeout): "timeout"
        \\    Error(NotText): "not text"
        \\  end
        \\end
        \\fn main(platform: Platform)
        \\  data = platform.fs.scoped("data").read_only
        \\  out = platform.stdout
        \\  out.write_line(names(data.list(within: 1.minute)))
        \\  out.write_line(names(data.read_lines("b.txt", within: 1.minute)))
        \\  out.write_line(names(data.read_lines("../secret.txt", within: 1.minute)))
        \\  out.write_line(bytes(data.size("b.txt", within: 1.minute)))
        \\  out.write_line(bytes(data.size("sub", within: 1.minute)))
        \\  out.write_line(bytes(data.size("../secret.txt", within: 1.minute)))
        \\  out.write_line(names(data.scoped("nowhere").list(within: 1.minute)))
        \\  out.write_line(names(data.scoped("..").list(within: 1.minute)))
        \\  out.write_line(names(data.list(within: 0.ms)))
        \\end
    );
    var environ: std.process.Environ.Map = .init(arena);
    var out: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, io, cwd, &.{}, &environ, &out.writer, &out.writer);
    const ran = try server.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(@as(u8, 0), ran.exited);
    try std.testing.expectEqualStrings(
        \\a.txt,b.txt,sub
        \\x,y
        \\missing ../secret.txt
        \\5
        \\missing sub
        \\missing ../secret.txt
        \\missing .
        \\missing .
        \\timeout
        \\
    , out.written());
}

test "Fs writes on Mo.Server: write, append, rename, and remove inside the scope, Missing outside it, and flush" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "data");
    const cwd = try tmp.dir.realPathFileAlloc(io, ".", arena);

    const program = try compile(arena,
        \\module T.Writes
        \\fn said(r: Result(T, FsError)) : String
        \\  case r
        \\    Ok(_): "ok"
        \\    Error(Missing(path)): "missing #{path}"
        \\    Error(Timeout): "timeout"
        \\    Error(NotText): "not text"
        \\  end
        \\end
        \\fn text(r: Result(String, FsError)) : String
        \\  case r
        \\    Ok(t): t
        \\    Error(_): "unread\n"
        \\  end
        \\end
        \\fn main(platform: Platform)
        \\  data = platform.fs.scoped("data")
        \\  out = platform.stdout
        \\  out.write_line(said(data.write("a.log", "one\n", within: 1.minute)))
        \\  out.write_line(said(data.append("a.log", "two\n", within: 1.minute)))
        \\  out.write_line(said(data.append("b.log", "new\n", within: 1.minute)))
        \\  out.write(text(data.read("a.log", within: 1.minute)))
        \\  out.write_line(said(data.write("../escape.log", "no", within: 1.minute)))
        \\  out.write_line(said(data.write("nofolder/c.log", "no", within: 1.minute)))
        \\  out.write_line(said(data.rename("b.log", "c.log", within: 1.minute)))
        \\  out.write_line(said(data.remove("b.log", within: 1.minute)))
        \\  out.write_line(said(data.remove("a.log", within: 1.minute)))
        \\  out.flush
        \\  out.write(text(data.read("c.log", within: 1.minute)))
        \\end
    );
    var environ: std.process.Environ.Map = .init(arena);
    var out: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, io, cwd, &.{}, &environ, &out.writer, &out.writer);
    const ran = try server.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(@as(u8, 0), ran.exited);
    try std.testing.expectEqualStrings(
        \\ok
        \\ok
        \\ok
        \\one
        \\two
        \\missing ../escape.log
        \\missing nofolder/c.log
        \\ok
        \\missing b.log
        \\ok
        \\new
        \\
    , out.written());
    const kept = try tmp.dir.readFileAlloc(io, "data/c.log", arena, .limited(64));
    try std.testing.expectEqualStrings("new\n", kept);
    try std.testing.expectError(error.FileNotFound, tmp.dir.readFileAlloc(io, "escape.log", arena, .limited(64)));
    try std.testing.expectError(error.FileNotFound, tmp.dir.readFileAlloc(io, "data/x.log", arena, .limited(64)));
}

test "a crash in main comes back with its report" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena,
        \\module T.Crash
        \\fn main(platform: Platform)
        \\  platform.exit(1)
        \\  platform.stdout.write("#{platform.args.size - 1}")
        \\end
    );
    var environ: std.process.Environ.Map = .init(arena);
    var out: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, std.testing.io, "/", &.{}, &environ, &out.writer, &out.writer);
    const ran = try server.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(contracts.Kind.overflow, ran.crashed.kind);
    try std.testing.expectEqualStrings("", out.written());
}

const net_src =
    \\module T.Net
    \\fn describe(r: Result(Option(String), NetError)) : String
    \\  case r
    \\    Ok(Some(line)): "line #{line.size}: #{line.slice(0, 12)}"
    \\    Ok(None): "end"
    \\    Error(e): "error #{e}"
    \\  end
    \\end
    \\fn talk(out: Out, net: Net, listener: Listener) : Result(UInt32, NetError)
    \\  client = try net.connect("localhost", listener.port, within: 5_000.ms)
    \\  try client.write("hello\nwor", within: 5_000.ms)
    \\  conn = try listener.accept(within: 5_000.ms)
    \\  out.write_line(describe(conn.read_line(within: 5_000.ms)))
    \\  out.write_line(describe(conn.read_line(within: 50.ms)))
    \\  long = "x".repeat(70_000)
    \\  try client.write("ld\r\n#{long}\n#{long.slice(0, 65_536)}\nnext\n", within: 5_000.ms)
    \\  out.write_line(describe(conn.read_line(within: 5_000.ms)))
    \\  out.write_line(describe(conn.read_line(within: 5_000.ms)))
    \\  out.write_line(describe(conn.read_line(within: 5_000.ms)))
    \\  out.write_line(describe(conn.read_line(within: 5_000.ms)))
    \\  try conn.write("bye\n", within: 5_000.ms)
    \\  out.write_line(describe(client.read_line(within: 5_000.ms)))
    \\  try client.write("tail", within: 5_000.ms)
    \\  client.close
    \\  out.write_line(describe(client.read_line(within: 5_000.ms)))
    \\  out.write_line(describe(conn.read_line(within: 5_000.ms)))
    \\  out.write_line(describe(conn.read_line(within: 5_000.ms)))
    \\  conn.close
    \\  out.write_line(describe(conn.read_line(within: 5_000.ms)))
    \\  Ok(1)
    \\end
    \\fn main(platform: Platform)
    \\  out = platform.stdout
    \\  net = platform.net
    \\  case net.listen(0, within: 1_000.ms)
    \\    Ok(listener): out.write_line("talked: #{talk(out, net, listener) is Ok(_)}")
    \\    Error(e): out.write_line("listen: #{e}")
    \\  end
    \\  case net.connect("127.0.0.1", 1, within: 1_000.ms)
    \\    Ok(_): out.write_line("port 1 answered")
    \\    Error(e): out.write_line("port 1: #{e}")
    \\  end
    \\end
;

test "Net over a real loopback socket: lines, a deadline, a line too long, the end of the stream, close, and a refusal" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, net_src);
    var environ: std.process.Environ.Map = .init(arena);
    var out: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, std.testing.io, "/", &.{}, &environ, &out.writer, &out.writer);
    const ran = try server.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(@as(u8, 0), ran.exited);
    try std.testing.expectEqualStrings(
        \\line 5: hello
        \\error Timeout
        \\line 5: world
        \\error LineTooLong
        \\line 65536: xxxxxxxxxxxx
        \\line 4: next
        \\line 3: bye
        \\error Closed
        \\line 4: tail
        \\end
        \\error Closed
        \\talked: true
        \\port 1: Refused
        \\
    , out.written());
}

test "a port a listener holds is Busy" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var machine: Vm = .init(arena_state.allocator(), undefined, 0);
    var sockets: net.Net = .{ .io = io, .gpa = arena_state.allocator() };
    defer sockets.closeAll();
    const first = try sockets.call(&machine, .listen, &.{ .none, .{ .int = 0 }, .{ .duration = 1 } });
    const port = sockets.listeners.items[first.variant.fields[0].cap.handle].port;
    const second = try sockets.call(&machine, .listen, &.{ .none, .{ .int = port }, .{ .duration = 1 } });
    try std.testing.expectEqualStrings("Busy", second.variant.fields[0].variant.name);
}

const turns_src =
    \\module T.Turns
    \\process Reader(conn: Conn, out: Out, name: String)
    \\  state
    \\    reads: UInt32
    \\  end
    \\  message Read : UInt32
    \\  fn update(state, message)
    \\    case message
    \\      Read:
    \\        if echo(conn, out, name) is Ok(_)
    \\          state.reads += 1
    \\        end
    \\        state.reads
    \\    end
    \\  end
    \\end
    \\process Harness(net: Net, out: Out)
    \\  state
    \\    runs: UInt32
    \\  end
    \\  message Run
    \\  fn update(state, message)
    \\    case message
    \\      Run:
    \\        state.runs += 1
    \\        if run(net, out) is Error(e)
    \\          out.write_line("harness failed: #{e}")
    \\        end
    \\    end
    \\  end
    \\end
    \\supervisor Top(conn: Conn, net: Net, out: Out)
    \\  child Reader(conn, out, "reader"), restart: :always
    \\  child Harness(net, out), restart: :always
    \\end
    \\fn echo(conn: Conn, out: Out, name: String) : Result(UInt32, NetError)
    \\  line = try conn.read_line(within: 5_000.ms)
    \\  text = line or "nothing"
    \\  out.write_line("#{name} read #{text}")
    \\  try conn.write("#{text} back\n", within: 1_000.ms)
    \\  Ok(1)
    \\end
    \\fn run(net: Net, out: Out) : Result(UInt32, NetError)
    \\  listener = try net.listen(0, within: 1_000.ms)
    \\  client_a = try net.connect("127.0.0.1", listener.port, within: 1_000.ms)
    \\  conn_a = try listener.accept(within: 1_000.ms)
    \\  client_b = try net.connect("127.0.0.1", listener.port, within: 1_000.ms)
    \\  conn_b = try listener.accept(within: 1_000.ms)
    \\  b = Reader.start(conn_b, out, "b")
    \\  a = Reader.start(conn_a, out, "a")
    \\  out.write_line("b: #{b.ask(Read, within: 20.ms)}")
    \\  out.write_line("a: #{a.ask(Read, within: 20.ms)}")
    \\  try client_b.write("ping\n", within: 1_000.ms)
    \\  heard = try client_b.read_line(within: 3_000.ms)
    \\  said = heard or "nothing"
    \\  out.write_line("harness heard #{said}")
    \\  try client_a.write("done\n", within: 1_000.ms)
    \\  Ok(1)
    \\end
    \\fn main(platform: Platform)
    \\  harness = Harness.start(platform.net, platform.stdout)
    \\  harness.send(Run)
    \\end
;

test "a process waiting on the network gives up its turn: the one that waited first finishes last, and nothing waits for a deadline" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, turns_src);
    var environ: std.process.Environ.Map = .init(arena);
    var out: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, std.testing.io, "/", &.{}, &environ, &out.writer, &out.writer);
    const t0 = Io.Clock.Timestamp.now(std.testing.io, .awake);
    const ran = try server.run(program, program.findFunction("main").?);
    const ms = t0.durationTo(Io.Clock.Timestamp.now(std.testing.io, .awake)).raw.toMilliseconds();
    try std.testing.expectEqual(@as(u8, 0), ran.exited);
    // b waits in read_line first, then a; the harness's asks time out while they wait. b
    // hears ping and answers while a still waits, and a hears done only after that.
    try std.testing.expectEqualStrings(
        \\b: Error(Timeout)
        \\a: Error(Timeout)
        \\b read ping
        \\harness heard ping back
        \\a read done
        \\
    , out.written());
    try std.testing.expect(ms < 2_000);
}

const regions_src =
    \\module T.Regions
    \\process Store()
    \\  state
    \\    data: Map(String, String)
    \\    n: UInt8
    \\  end
    \\  message Put(key: String, value: String) : Bool
    \\  message Get(key: String) : String
    \\  message Boom(key: String)
    \\  fn update(state, message)
    \\    case message
    \\      Put(key: key, value: value):
    \\        state.data = state.data.set(key, value)
    \\        true
    \\      Get(key): state.data.get(key) or "none"
    \\      Boom(key):
    \\        state.data = state.data.set(key, "boom")
    \\        state.n -= 1
    \\    end
    \\  end
    \\end
    \\process Tally()
    \\  state
    \\    data: Map(String, String)
    \\  end
    \\  invariant "a value never goes back to empty"
    \\    state.data.get("a") != Some("") or old(state.data.get("a")) != Some("1")
    \\  end
    \\  message Note(key: String, value: String)
    \\  message Read(key: String) : String
    \\  fn update(state, message)
    \\    case message
    \\      Note(key: key, value: value):
    \\        state.data = state.data.set(key, value)
    \\      Read(key): state.data.get(key) or "none"
    \\    end
    \\  end
    \\end
    \\supervisor Stores
    \\  child Store, restart: :always
    \\  child Tally, restart: :always
    \\end
    \\fn shown(r: Result(String, AskError)) : String
    \\  case r
    \\    Ok(text): text.slice(0, 6)
    \\    Error(_): "error"
    \\  end
    \\end
    \\fn main(platform: Platform)
    \\  out = platform.stdout
    \\  store = Store.start()
    \\  pad = "x".repeat(100)
    \\  var failed = 0
    \\  for i in 0..60_000
    \\    if store.ask(Put(key: "k#{i % 500}", value: "v#{i}#{pad}"), within: 1.minute) is Error(_)
    \\      failed += 1
    \\    end
    \\  end
    \\  out.write_line("failed #{failed}")
    \\  out.write_line(shown(store.ask(Get(key: "k7"), within: 1.minute)))
    \\  store.send(Boom(key: "k7"))
    \\  out.write_line(shown(store.ask(Get(key: "k7"), within: 1.minute)))
    \\  tally = Tally.start()
    \\  tally.send(Note(key: "a", value: "1"))
    \\  tally.send(Note(key: "a", value: ""))
    \\  out.write_line("tally #{shown(tally.ask(Read(key: "a"), within: 1.minute))}")
    \\end
    \\test rejects "a value set back to empty"
    \\  tally = Tally.start()
    \\  tally.send(Note(key: "a", value: "1"))
    \\  tally.send(Note(key: "a", value: ""))
    \\end
;

test "processes under mo run free what their state does not reach, write their state in place, and a crash still shows the state before" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, regions_src);
    var environ: std.process.Environ.Map = .init(arena);
    var out: Io.Writer.Allocating = .init(arena);
    var err: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, std.testing.io, "/", &.{}, &environ, &out.writer, &err.writer);
    const ran = try server.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(@as(u8, 0), ran.exited);
    // 60,000 values of 106 bytes went through the store, and the last one per key is what it
    // holds. Boom set k7 in place and crashed: the store restarted empty, and the report shows
    // k7 as it was, not "boom". Tally's invariant saw the old "1" and tripped.
    try std.testing.expectEqualStrings(
        \\failed 0
        \\v59507
        \\none
        \\tally none
        \\
    , out.written());
    const said = err.written();
    try std.testing.expect(std.mem.indexOf(u8, said, "state before the last message: Store(data: Map.new().set(\"k0\", \"v59500x") != null);
    try std.testing.expect(std.mem.indexOf(u8, said, ".set(\"k7\", \"v59507x") != null);
    try std.testing.expect(std.mem.indexOf(u8, said, "\"boom\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, said, "invariant \"a value never goes back to empty\"") != null);
}

const procs_src =
    \\module T.Procs
    \\process Counter(out: Out)
    \\  state
    \\    n: UInt8
    \\  end
    \\  message Add(k: UInt8)
    \\  message Total : UInt8
    \\  fn update(state, message)
    \\    case message
    \\      Add(k):
    \\        state.n += k
    \\        out.write_line("added #{k}")
    \\      Total: state.n
    \\    end
    \\  end
    \\end
    \\process Echo()
    \\  state
    \\    said: UInt32
    \\  end
    \\  message Say : UInt32
    \\  fn update(state, message)
    \\    case message
    \\      Say:
    \\        state.said += 1
    \\        state.said
    \\    end
    \\  end
    \\end
    \\supervisor Pair(out: Out)
    \\  child Counter(out), restart: :always, max_restarts: 1 per 1.minute
    \\  child Echo, restart: :always
    \\end
    \\fn main(platform: Platform)
    \\  pair = Pair.start(platform.stdout)
    \\  counter = pair.0
    \\  counter.send(Add(k: 200))
    \\  counter.send(Add(k: 100))
    \\  counter.send(Add(k: 5))
    \\  said = pair.1.ask(Say, within: 1.minute)
    \\  case counter.ask(Total, within: 1.minute)
    \\    Ok(n): platform.stdout.write_line("total #{n}, said #{said}")
    \\    Error(_): platform.stdout.write_line("no total")
    \\  end
    \\  echo = Echo.start()
    \\  if platform.args.size > 0
    \\    counter.send(Add(k: 251))
    \\    counter.send(Add(k: 1))
    \\  end
    \\  platform.stdout.write_line("echo said #{echo.ask(Say, within: 1.minute)}")
    \\end
;

test "processes under mo run: main starts a supervisor and a process, sends and asks, and a crash is reported, restarted, and once too often crashes main" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, procs_src);
    var environ: std.process.Environ.Map = .init(arena);
    var out: Io.Writer.Allocating = .init(arena);
    var err: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, std.testing.io, "/", &.{}, &environ, &out.writer, &err.writer);
    const ran = try server.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(@as(u8, 0), ran.exited);
    // Add(100) overflowed: the crash is on stderr, and Counter restarted from 0.
    try std.testing.expectEqualStrings(
        \\added 200
        \\added 5
        \\total 5, said Ok(1)
        \\echo said Ok(1)
        \\
    , out.written());
    try std.testing.expect(std.mem.startsWith(u8, err.written(), "process crashed: overflow in state.n += k; left = 200, right = 100\n      in process Counter"));

    // A second crash within the minute is one more than the child line allows: Pair gives up
    // and main crashes with the supervisor's report.
    out.clearRetainingCapacity();
    err.clearRetainingCapacity();
    var again: Server = try .init(arena, std.testing.io, "/", &.{"crash"}, &environ, &out.writer, &err.writer);
    const gave_up = try again.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(contracts.Kind.supervisor, gave_up.crashed.kind);
    try std.testing.expectEqualStrings("Pair gave up: Counter crashed more than 1 times within 60000.ms", gave_up.crashed.clause);
}

const ends_src =
    \\module T.Ends
    \\process Idle()
    \\  state
    \\    pokes: UInt64
    \\  end
    \\  message Poke
    \\  fn update(state, message)
    \\    case message
    \\      Poke:
    \\        state.pokes += 1
    \\    end
    \\  end
    \\end
    \\process Keeper()
    \\  state
    \\    pokes: UInt64
    \\  end
    \\  message Poke
    \\  message Pokes : UInt64
    \\  fn update(state, message)
    \\    case message
    \\      Poke:
    \\        state.pokes += 1
    \\      Pokes: state.pokes
    \\    end
    \\  end
    \\end
    \\process Relay(keeper: Handle(Keeper))
    \\  state
    \\    passed: UInt64
    \\  end
    \\  message Pass
    \\  message Count : UInt64
    \\  fn update(state, message)
    \\    case message
    \\      Pass:
    \\        keeper.send(Poke)
    \\        state.passed += 1
    \\      Count:
    \\        case keeper.ask(Pokes, within: 1.minute)
    \\          Ok(n): n
    \\          Error(_): 0
    \\        end
    \\    end
    \\  end
    \\end
    \\supervisor Ends(keeper: Handle(Keeper))
    \\  child Idle, restart: :always
    \\  child Keeper, restart: :always
    \\  child Relay(keeper), restart: :always
    \\end
    \\fn started(iterations: UInt64, relay: Handle(Relay)) : UInt64
    \\  var count = 0
    \\  for _ in 0..iterations
    \\    idle = Idle.start()
    \\    idle.send(Poke)
    \\    relay.send(Pass)
    \\    count += 1
    \\  end
    \\  count
    \\end
    \\fn main(platform: Platform)
    \\  relay = Relay.start(Keeper.start())
    \\  platform.stdout.write_line("started #{started(5_000, relay)}")
    \\  case relay.ask(Count, within: 1.minute)
    \\    Ok(n): platform.stdout.write_line("kept #{n}")
    \\    Error(_): platform.stdout.write_line("lost")
    \\  end
    \\end
;

test "under mo run a process that finished and that nothing holds a handle to ends and gives its id to the next; one held through a start argument does not" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, ends_src);
    var environ: std.process.Environ.Map = .init(arena);
    var out: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, std.testing.io, "/", &.{}, &environ, &out.writer, &out.writer);
    const ran = try server.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(@as(u8, 0), ran.exited);
    // The keeper is reachable only through the relay's start arguments, and counted every Pass.
    try std.testing.expectEqualStrings("started 5000\nkept 5000\n", out.written());
    // 5,002 processes started; each idle one ended within a sweep or two of its Poke.
    try std.testing.expect(server.ids_used < 300);
}

test "mkdir on Mo.Server makes a folder in a folder that is there, and --clock starts main's clock where it says" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "data");
    const cwd = try tmp.dir.realPathFileAlloc(io, ".", arena);

    const program = try compile(arena,
        \\module T.Folders
        \\fn said(r: Result(T, FsError)) : String
        \\  case r
        \\    Ok(_): "ok"
        \\    Error(Missing(path)): "missing #{path}"
        \\    Error(Timeout): "timeout"
        \\    Error(NotText): "not text"
        \\  end
        \\end
        \\fn main(platform: Platform)
        \\  data = platform.fs.scoped("data")
        \\  out = platform.stdout
        \\  out.write_line(said(data.mkdir("made", within: 1.minute)))
        \\  out.write_line(said(data.mkdir("made", within: 1.minute)))
        \\  out.write_line(said(data.mkdir("nowhere/made", within: 1.minute)))
        \\  out.write_line(said(data.write("made/a.txt", "a", within: 1.minute)))
        \\  out.write_line(said(data.mkdir("made/a.txt", within: 1.minute)))
        \\  out.write_line(said(data.mkdir("../out", within: 1.minute)))
        \\  out.write_line(platform.clock.now.to_iso8601.slice(0, 16))
        \\end
    );
    var environ: std.process.Environ.Map = .init(arena);
    var out: Io.Writer.Allocating = .init(arena);
    var server: Server = try .init(arena, io, cwd, &.{}, &environ, &out.writer, &out.writer);
    server.startClock(stdlib.parseTime("2030-01-01T00:00:00Z").?);
    const ran = try server.run(program, program.findFunction("main").?);
    try std.testing.expectEqual(@as(u8, 0), ran.exited);
    try std.testing.expectEqualStrings(
        \\ok
        \\ok
        \\missing nowhere/made
        \\ok
        \\missing made/a.txt
        \\missing ../out
        \\2030-01-01T00:00
        \\
    , out.written());
    const kept = try tmp.dir.readFileAlloc(io, "data/made/a.txt", arena, .limited(64));
    try std.testing.expectEqualStrings("a", kept);
    try std.testing.expectError(error.FileNotFound, tmp.dir.readFileAlloc(io, "out", arena, .limited(64)));
}
