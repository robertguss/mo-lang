//! Mo.Server: the real platform `mo run` gives `main` (design-v0/03, effects; Q18), over
//! std.Io. `args` and `env` come from the process; `Out.write` goes to the real streams,
//! buffered, and the caller flushes them at exit; `Fs.read` reads the real file system
//! under the scope `scoped(...)` gave; `clock.now` is the wall clock; `exit(code)` is
//! recorded and applied when `main` returns. No database and no writes to the file system.
//!
//! main is the root supervisor: a process it starts, directly or through a supervisor,
//! runs on Mo.Sim's scheduler in its fixed order (sim.zig). main's sends are delivered
//! before its next statement runs, an update may use the capabilities its process was
//! started with, and when main returns the run goes on until no message is waiting. A
//! process crash is reported on stderr as it happens and its supervisor restarts it; a
//! supervisor that gives up crashes main.
//!
//! An Fs value is pointer-free: `Value.Cap.handle` is its index in `Server.scopes`.
const std = @import("std");
const Io = std.Io;
const bytecode = @import("bytecode.zig");
const contracts = @import("contracts.zig");
const diag = @import("diag.zig");
const runner = @import("runner.zig");
const Sim = @import("sim.zig").Sim;
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Region = @import("region.zig").Region;
const Memo = @import("memo.zig").Memo;

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
    /// Nothing writes yet, so this refuses nothing at run time; the checker would.
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
    /// The program's files, so a process crash reported on stderr names its line.
    files: []const diag.File = &.{},

    /// `cwd` is the absolute working directory a relative path starts from. Nothing is
    /// freed: pass an arena.
    pub fn init(gpa: std.mem.Allocator, io: Io, cwd: []const u8, args: []const []const u8, environ: *const std.process.Environ.Map, stdout: *Io.Writer, stderr: *Io.Writer) Error!Server {
        var s: Server = .{ .gpa = gpa, .io = io, .args = args, .environ = environ, .stdout = stdout, .stderr = stderr };
        try s.scopes.append(gpa, .{ .base = cwd, .root = "/" });
        return s;
    }

    /// Calls `main` (functions[main_fn]) with the Platform. The exit code is the last
    /// `platform.exit(code)`, or 0; a crash comes back with its complete report.
    pub fn run(s: *Server, program: *const bytecode.Program, main_fn: u32) Error!Ran {
        var machine: Vm = .init(s.gpa, program, 0);
        machine.server = s;
        var scheduler: Sim = .init(&machine, 0, "main");
        scheduler.server = s;
        machine.sim = &scheduler;
        // Values live in a region freed at safe points (vm.zig); without the address space
        // for one, every value lives until the run ends. A program with processes keeps
        // every value: a message main sends, or a process's state, is reached from a
        // mailbox the region's compaction does not see.
        const processes = program.processes.len > 0;
        var values: ?Region = if (processes) null else Region.reserve() catch null;
        defer if (values) |*r| r.release();
        var scratch: ?Region = if (processes) null else Region.reserve() catch null;
        defer if (scratch) |*r| r.release();
        if (values != null and scratch != null) machine.useRegions(&values.?, &scratch.?);
        // A call reaches the world only through a capability, so a pure call seen before can
        // be answered from memory (memo.zig). Starting a process or sending to one needs no
        // capability, so a program with processes remembers nothing.
        var memo: ?Memo = if (processes) null else try .init(s.gpa, program.functions.len);
        defer if (memo) |*m| m.deinit();
        if (memo) |*m| machine.memo = m;
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
        _ = try machine.call(main_fn, &.{.{ .cap = .{ .kind = .platform } }});
        try scheduler.finish();
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
            const out = try vm.heap.alloc(Value, s.args.len);
            for (s.args, out) |a, *o| o.* = .{ .string = a };
            return .{ .list = out };
        }
        const cap: Value.Cap = if (std.mem.eql(u8, name, "env"))
            .{ .kind = .env }
        else if (std.mem.eql(u8, name, "stdout"))
            .{ .kind = .out, .handle = stdout_handle }
        else if (std.mem.eql(u8, name, "stderr"))
            .{ .kind = .out, .handle = stderr_handle }
        else if (std.mem.eql(u8, name, "fs"))
            .{ .kind = .fs }
        else
            .{ .kind = .clock };
        return .{ .cap = cap };
    }

    pub fn exit(s: *Server, code: i128) void {
        s.exit_code = @intCast(code);
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

    /// Milliseconds since the Unix epoch, as `Value.time` counts.
    pub fn now(s: *Server) i64 {
        return Io.Clock.real.now(s.io).toMilliseconds();
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
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        const text = try s.readScoped(s.scopes.items[fs.handle], path);
        if (s.late(t0, within_ms)) return vm.variant("Error", &.{try vm.variant("Timeout", &.{})});
        const got = text orelse return missing(vm, path);
        return vm.variant("Ok", &.{.{ .string = got }});
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
    pub fn list(s: *Server, vm: *Vm, fs: Value.Cap, within_ms: i64) Error!Value {
        const t0 = Io.Clock.Timestamp.now(s.io, .awake);
        const names = try s.listScoped(s.scopes.items[fs.handle]);
        if (s.late(t0, within_ms)) return vm.variant("Error", &.{try vm.variant("Timeout", &.{})});
        const got = names orelse return missing(vm, ".");
        const out = try vm.heap.alloc(Value, got.len);
        for (got, out) |name, *o| o.* = .{ .string = name };
        return vm.variant("Ok", &.{.{ .list = out }});
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
        if (scope.empty) return null;
        const full = try std.fs.path.resolve(s.gpa, &.{ scope.base, path });
        if (!within(scope.root, full)) return null;
        const cwd = Io.Dir.cwd();
        const real_root = cwd.realPathFileAlloc(s.io, scope.root, s.gpa) catch |err| return unreadable(err);
        const real = cwd.realPathFileAlloc(s.io, full, s.gpa) catch |err| return unreadable(err);
        if (!within(real_root, real)) return null;
        return real;
    }

    fn readScoped(s: *Server, scope: Scope, path: []const u8) Error!?[]const u8 {
        const real = try s.realScoped(scope, path) orelse return null;
        return Io.Dir.cwd().readFileAlloc(s.io, real, s.gpa, .limited(read_limit)) catch |err| unreadable(err);
    }

    fn listScoped(s: *Server, scope: Scope) Error!?[]const []const u8 {
        const real = try s.realScoped(scope, ".") orelse return null;
        var dir = Io.Dir.cwd().openDir(s.io, real, .{ .iterate = true }) catch return null;
        defer dir.close(s.io);
        var names: std.ArrayList([]const u8) = .empty;
        var it = dir.iterate();
        while (it.next(s.io) catch return null) |entry| try names.append(s.gpa, try s.gpa.dupe(u8, entry.name));
        std.mem.sort([]const u8, names.items, {}, struct {
            fn lt(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lt);
        return names.items;
    }
};

fn missing(vm: *Vm, path: []const u8) Error!Value {
    return vm.variant("Error", &.{try vm.variant("Missing", &.{.{ .string = path }})});
}

fn unreadable(err: anyerror) Error!?[]const u8 {
    return if (err == error.OutOfMemory) error.OutOfMemory else null;
}

/// Whether the resolved absolute `path` is `root` or inside it.
fn within(root: []const u8, path: []const u8) bool {
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
        \\  end
        \\end
        \\fn bytes(r: Result(UInt64, FsError)) : String
        \\  case r
        \\    Ok(n): "#{n}"
        \\    Error(Missing(path)): "missing #{path}"
        \\    Error(Timeout): "timeout"
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
