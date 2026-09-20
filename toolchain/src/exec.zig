//! `Exec` (step 41; design: mo-capabilities-for-the-harness, section 3): a child process narrowed to
//! fixed commands. `platform.exec` exists only in main; it makes a `Program` (one absolute path),
//! which makes a `Command` (a fixed argument list of `Fixed(text)` and `Hole`); only a `Command`
//! runs or travels. No shell, no PATH, no interpolation: a hole is one whole argument.
//!
//! A value of each is pointer-free, as an Fs is: `Value.Cap.handle` is an index into the run's
//! `Table`, the Server's under `mo run` and the Sim's in a test. An `Exec`'s handle is 0 for the
//! real one and one past its index for an `Exec.fixture(fn)`, whose function answers every run of
//! the commands made from it.
//!
//! A real run (`Job.run`) starts a child (posix_spawn on Darwin, fork elsewhere) in a session of
//! its own, so it leads its own process group and has no terminal; its standard streams are pipes;
//! every other descriptor is closed and every signal is back to its default before `execve`; its working folder is the `Fs` scope's
//! folder (`in_folder`), opened as `Fs.list` opens it, or a new empty private folder removed after
//! the run; its environment is exactly the command's map, empty by default. The parent writes
//! `stdin` and drains stdout and stderr as the child runs, so a child writing more than a pipe holds
//! never blocks; bytes past the bound are dropped and `truncated` set. When the child exits, the
//! rest of its group is killed before it is reaped; at the deadline the whole group is killed, the
//! child reaped, and only then is the answer `Timeout`. The run waits on a thread of its own, so the
//! scheduler is never blocked (blocking.zig, alone). runtime/mo_rt.c's exec rows are the same.
const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const sys = posix.system;
const Io = std.Io;
const prelude = @import("prelude.zig");
const vm_mod = @import("vm.zig");
const blocking = @import("blocking.zig");
const server_mod = @import("server.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;

/// Bytes kept of stdout and of stderr each when a command says nothing (`Command.output`).
pub const default_output: u64 = 65_536;
/// The most `Command.output` may keep of each stream.
pub const max_output: u64 = 16 << 20;

pub const Row = enum { program, command, env, in_folder, output, run, fixture };

pub const Arg = union(enum) { fixed: [:0]const u8, hole };

pub const Program = struct {
    /// The `Exec.fixture` it was made from, by index in `Table.fixtures`; null for the real Exec.
    fixture: ?u32 = null,
    path: [:0]const u8,
};

pub const Command = struct {
    fixture: ?u32 = null,
    path: [:0]const u8,
    args: []const Arg,
    holes: usize,
    /// The child's whole environment, each `NAME=value`; empty by default, never the parent's.
    env: []const [:0]const u8 = &.{},
    /// A name that is empty or holds `=` or a NUL, or a value holding a NUL: every run is `Refused`.
    env_refused: bool = false,
    /// The `Fs` whose folder the child works in, by its handle; null: a new empty folder.
    folder: ?u32 = null,
    output: u64 = default_output,
};

/// Every Program and Command a run has made, and each `Exec.fixture`'s function.
pub const Table = struct {
    programs: std.ArrayList(Program) = .empty,
    commands: std.ArrayList(Command) = .empty,
    fixtures: std.ArrayList(Value.Func) = .empty,
};

const Where = struct { table: *Table, gpa: std.mem.Allocator };

fn tableOf(vm: *Vm) ?Where {
    if (vm.server) |s| return .{ .table = &s.exec, .gpa = s.gpa };
    if (vm.sim) |s| return .{ .table = &s.exec, .gpa = s.gpa };
    return null;
}

/// Runs `which` on its arguments, the receiver first.
pub fn call(vm: *Vm, row: prelude.Fn, which: Row, a: []const Value) Error!Value {
    const w = tableOf(vm) orelse return fail(vm, row, "Exec runs only under mo run or in a test", .{});
    const t = w.table;
    switch (which) {
        .fixture => {
            try t.fixtures.append(w.gpa, a[0].func);
            return .{ .cap = .{ .kind = .exec, .handle = @intCast(t.fixtures.items.len) } };
        },
        .program => {
            const path = a[1].string;
            if (std.mem.indexOfScalar(u8, path, 0) != null) return fail(vm, row, "exec.program: the path holds a NUL, so it names no program", .{});
            if (path.len == 0 or path[0] != '/') return fail(vm, row, "exec.program(\"{s}\"): \"{s}\" is not an absolute path; a program is named by its absolute path, and no PATH is searched", .{ path, path });
            const h = a[0].cap.handle;
            try t.programs.append(w.gpa, .{ .fixture = if (h == 0) null else h - 1, .path = try w.gpa.dupeZ(u8, path) });
            return .{ .cap = .{ .kind = .program, .handle = @intCast(t.programs.items.len - 1) } };
        },
        .command => {
            const p = t.programs.items[a[0].cap.handle];
            const list = a[1].list;
            const args = try w.gpa.alloc(Arg, list.len);
            var holes: usize = 0;
            for (list, args) |v, *arg| {
                if (v.variant.fields.len == 0) {
                    arg.* = .hole;
                    holes += 1;
                    continue;
                }
                const text = v.variant.fields[0].string;
                if (std.mem.indexOfScalar(u8, text, 0) != null) return fail(vm, row, "{s}.command: a Fixed argument holds a NUL, which no argument can carry", .{p.path});
                arg.* = .{ .fixed = try w.gpa.dupeZ(u8, text) };
            }
            return add(w, .{ .fixture = p.fixture, .path = p.path, .args = args, .holes = holes });
        },
        .env => {
            var cmd = t.commands.items[a[0].cap.handle];
            const entries = a[1].map.entries;
            const env = try w.gpa.alloc([:0]const u8, entries.len / 2);
            var refused = false;
            for (env, 0..) |*e, i| {
                const name = entries[2 * i].string;
                const value = entries[2 * i + 1].string;
                if (name.len == 0 or std.mem.indexOfAny(u8, name, "=\x00") != null or std.mem.indexOfScalar(u8, value, 0) != null) refused = true;
                e.* = try std.fmt.allocPrintSentinel(w.gpa, "{s}={s}", .{ name, value }, 0);
            }
            cmd.env = env;
            cmd.env_refused = refused;
            return add(w, cmd);
        },
        .in_folder => {
            var cmd = t.commands.items[a[0].cap.handle];
            cmd.folder = a[1].cap.handle;
            return add(w, cmd);
        },
        .output => {
            var cmd = t.commands.items[a[0].cap.handle];
            const n = a[1].int;
            if (n > max_output) return fail(vm, row, "command.output({d}): a command keeps at most {d} bytes (16 MiB) of each stream", .{ n, max_output });
            cmd.output = @intCast(n);
            return add(w, cmd);
        },
        .run => {
            // Copied out: an append to the table may move it.
            const cmd = t.commands.items[a[0].cap.handle];
            const values = a[1].list;
            const stdin: []const u8 = if (row.named.len == 1) a[2].string else "";
            const within = a[a.len - 1].duration;
            if (values.len != cmd.holes or cmd.env_refused) return err(vm, "Refused", &.{});
            for (values) |v| if (std.mem.indexOfScalar(u8, v.string, 0) != null) return err(vm, "Refused", &.{});
            if (cmd.fixture) |f| return fixtureRun(vm, t.fixtures.items[f], cmd, values, stdin, within);
            const s = vm.server orelse return fail(vm, row, "a Command of the real Exec runs only under mo run", .{});
            return realRun(vm, s, cmd, values, stdin, within);
        },
    }
}

fn add(w: Where, cmd: Command) Error!Value {
    try w.table.commands.append(w.gpa, cmd);
    return .{ .cap = .{ .kind = .command, .handle = @intCast(w.table.commands.items.len - 1) } };
}

/// The argument list a run hands the child, or the fixture: the program's path first, then each
/// argument, each hole filled by the next value.
fn argvValues(vm: *Vm, cmd: Command, values: []const Value) Error!Value {
    const out = try vm_mod.rawAlloc(vm.heap, Value, cmd.args.len + 1);
    out[0] = .{ .string = cmd.path };
    var k: usize = 0;
    for (cmd.args, out[1..]) |arg, *o| o.* = switch (arg) {
        .fixed => |text| .{ .string = text },
        .hole => blk: {
            defer k += 1;
            break :blk values[k];
        },
    };
    return .{ .list = out };
}

/// A fixture's run: in a seeded run with faults it is scheduled as any wait and may fail with
/// `Timeout` or `Failed` (sim.zig, fault); otherwise the fixture's function answers.
fn fixtureRun(vm: *Vm, f: Value.Func, cmd: Command, values: []const Value, stdin: []const u8, within: i64) Error!Value {
    if (vm.sim) |sim| if (sim.fault(.failed, within)) |fault| return switch (fault) {
        .timeout => err(vm, "Timeout", &.{}),
        else => err(vm, "Failed", &.{.{ .string = "a fault the simulator injected" }}),
    };
    const done = try vm.invoke(f, &.{ try argvValues(vm, cmd, values), .{ .string = stdin } });
    return vm.variant("Ok", &.{done});
}

fn realRun(vm: *Vm, s: *server_mod.Server, cmd: Command, values: []const Value, stdin: []const u8, within: i64) Error!Value {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const argv = try arena.allocSentinel(?[*:0]const u8, cmd.args.len + 1, null);
    argv[0] = cmd.path.ptr;
    var k: usize = 0;
    for (cmd.args, argv[1..]) |arg, *o| o.* = switch (arg) {
        .fixed => |text| text.ptr,
        .hole => blk: {
            defer k += 1;
            break :blk (try arena.dupeZ(u8, values[k].string)).ptr;
        },
    };
    const envp = try arena.allocSentinel(?[*:0]const u8, cmd.env.len, null);
    for (cmd.env, envp) |e, *o| o.* = e.ptr;
    var temp: ?[]const u8 = null;
    const dir: posix.fd_t = if (cmd.folder) |h|
        try s.scopeFolder(h) orelse return err(vm, "Failed", &.{.{ .string = "the working folder is not there, or is reached through a link" }})
    else blk: {
        const made = makeTemp(arena, s) orelse return err(vm, "Failed", &.{.{ .string = "no temporary folder could be made" }});
        temp = made.path;
        break :blk made.fd;
    };
    var job: Job = .{ .path = cmd.path.ptr, .argv = argv.ptr, .envp = envp.ptr, .dir = dir, .stdin = stdin, .bound = cmd.output, .within_ms = within, .io = s.io };
    defer job.stdout.deinit(std.heap.smp_allocator);
    defer job.stderr.deinit(std.heap.smp_allocator);
    try blocking.alone(vm, &job, Job.run);
    _ = sys.close(dir);
    if (temp) |path| Io.Dir.cwd().deleteTree(s.io, path) catch {};
    return switch (job.outcome) {
        .timeout => err(vm, "Timeout", &.{}),
        .missing => err(vm, "Missing", &.{}),
        .failed => |why| err(vm, "Failed", &.{.{ .string = try vm_mod.rawDupe(vm.heap, u8, why) }}),
        .exited, .signalled => vm.variant("Ok", &.{try doneOf(vm, job)}),
    };
}

/// A `Done` of a real run.
fn doneOf(vm: *Vm, job: Job) Error!Value {
    const fields = try vm_mod.rawAlloc(vm.heap, Value, 5);
    fields[0] = switch (job.outcome) {
        .exited => |code| try vm.variant("Exited", &.{.{ .int = code }}),
        .signalled => |signal| try vm.variant("Signalled", &.{.{ .int = signal }}),
        else => unreachable,
    };
    fields[1] = try bytesOf(vm, job.stdout.items);
    fields[2] = try bytesOf(vm, job.stderr.items);
    fields[3] = .{ .bool = job.truncated };
    fields[4] = .{ .duration = job.took_ms };
    return .{ .record = .{ .decl = vm.program.prelude_decls.done, .fields = fields } };
}

fn bytesOf(vm: *Vm, bytes: []const u8) Error!Value {
    const out = try vm_mod.rawAlloc(vm.heap, Value, bytes.len);
    for (bytes, out) |b, *o| o.* = .{ .int = b };
    return .{ .list = out };
}

const Temp = struct { path: []const u8, fd: posix.fd_t };

/// A new folder private to the owner (mode 0700) under TMPDIR, or /tmp, named unpredictably.
fn makeTemp(arena: std.mem.Allocator, s: *server_mod.Server) ?Temp {
    const base = s.environ.get("TMPDIR") orelse "/tmp";
    for (0..8) |_| {
        var nonce: [12]u8 = undefined;
        s.io.randomSecure(&nonce) catch s.io.random(&nonce);
        const path = std.fmt.allocPrintSentinel(arena, "{s}/mo-exec-{x}", .{ std.mem.trimEnd(u8, base, "/"), nonce }, 0) catch return null;
        switch (posix.errno(sys.mkdirat(posix.AT.FDCWD, path.ptr, 0o700))) {
            .SUCCESS => {},
            .EXIST, .INTR => continue,
            else => return null,
        }
        const rc = sys.openat(posix.AT.FDCWD, path.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, @as(posix.mode_t, 0));
        if (posix.errno(rc) != .SUCCESS) {
            _ = sys.unlinkat(posix.AT.FDCWD, path.ptr, posix.AT.REMOVEDIR);
            return null;
        }
        return .{ .path = path, .fd = @intCast(rc) };
    }
    return null;
}

fn err(vm: *Vm, name: []const u8, fields: []const Value) Error!Value {
    return vm.variant("Error", &.{try vm.variant(name, fields)});
}

fn fail(vm: *Vm, row: prelude.Fn, comptime fmt: []const u8, args: anytype) Error {
    vm.report = .{ .kind = .other, .clause = try std.fmt.allocPrint(vm.gpa, fmt, args), .within = row.name, .at = 0 };
    return error.Crash;
}

// ---- the child

pub const Outcome = union(enum) { exited: u8, signalled: u8, timeout, missing, failed: []const u8 };

/// One real run: what the child is given, and what came of it. Everything the child needs is made
/// before the fork, so the child calls nothing but the system between `fork` and `execve`.
pub const Job = struct {
    path: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
    dir: posix.fd_t,
    stdin: []const u8,
    bound: u64,
    within_ms: i64,
    io: Io,
    outcome: Outcome = .{ .failed = "the child was not started" },
    stdout: std.ArrayList(u8) = .empty,
    stderr: std.ArrayList(u8) = .empty,
    truncated: bool = false,
    took_ms: i64 = 0,

    /// blocking.alone's work: on a thread of its own, SIGPIPE blocked there.
    pub fn run(ctx: *anyopaque) void {
        const job: *Job = @ptrCast(@alignCast(ctx));
        job.outcome = job.spawnAndWait();
    }

    fn now(job: *const Job) i96 {
        return Io.Clock.Timestamp.now(job.io, .awake).raw.toNanoseconds();
    }

    fn spawnAndWait(job: *Job) Outcome {
        // On the heap: the fallback that runs a job where it was called may be on a fiber's stack.
        const chunk = std.heap.smp_allocator.alloc(u8, 1 << 16) catch return .{ .failed = "the system is out of resources" };
        defer std.heap.smp_allocator.free(chunk);
        const t0 = job.now();
        const deadline = t0 + @as(i96, @max(job.within_ms, 0)) * std.time.ns_per_ms;
        // Each pipe's ends, every one above 2 so the child's dup2 onto 0, 1 and 2 never lands on
        // one it still needs, and close-on-exec, though every child of a run closes all of them.
        var in_p: [2]posix.fd_t = .{ -1, -1 };
        var out_p: [2]posix.fd_t = .{ -1, -1 };
        var err_p: [2]posix.fd_t = .{ -1, -1 };
        defer for ([_]*[2]posix.fd_t{ &in_p, &out_p, &err_p }) |p| closeBoth(p);
        for ([_]*[2]posix.fd_t{ &in_p, &out_p, &err_p }) |p| {
            if (!makePipe(p)) return .{ .failed = "no pipe could be made" };
        }
        const started = start(job, in_p[0], out_p[1], err_p[1]);
        closeOne(&in_p[0]);
        closeOne(&out_p[1]);
        closeOne(&err_p[1]);
        const pid = switch (started) {
            .pid => |pid| pid,
            .failed => |why| return .{ .failed = why },
            .errno => |e| return switch (e) {
                .NOENT, .NOTDIR => .missing,
                else => .{ .failed = whyOf(e) },
            },
        };
        if (job.stdin.len == 0) closeOne(&in_p[1]) else quietWrites(in_p[1]);
        var fds = [3]posix.pollfd{
            .{ .fd = out_p[0], .events = posix.POLL.IN, .revents = 0 },
            .{ .fd = err_p[0], .events = posix.POLL.IN, .revents = 0 },
            .{ .fd = in_p[1], .events = posix.POLL.OUT, .revents = 0 },
        };
        var sent: usize = 0;
        var leader_done = false;
        var timed_out = false;
        var slice_ms: i32 = 1;
        var nap_ns: u64 = 20_000;
        while (true) {
            if (!leader_done and exitedNotReaped(pid)) {
                // Nothing of the group outlives its leader: the rest is killed before the leader is
                // reaped, while its id still names the group.
                leader_done = true;
                _ = sys.kill(-pid, .KILL);
            }
            if (leader_done and fds[0].fd < 0 and fds[1].fd < 0) break;
            const left = deadline - job.now();
            if (left <= 0) {
                // A leader that exited is its answer, whatever still holds its streams (a process
                // that left the group); one still running is killed with its group.
                if (!leader_done) timed_out = true;
                break;
            }
            if (fds[0].fd < 0 and fds[1].fd < 0 and fds[2].fd < 0) {
                // Its streams are closed and it has not exited yet: wait a little, then ask again.
                job.io.sleep(.fromNanoseconds(@intCast(@min(nap_ns, @as(u64, @intCast(left))))), .awake) catch {};
                nap_ns = @min(nap_ns * 2, 10 * std.time.ns_per_ms);
                continue;
            }
            const left_ms: i32 = @intCast(@min(@divFloor(left, std.time.ns_per_ms) + 1, std.math.maxInt(i32)));
            const ready = posix.poll(&fds, @min(slice_ms, left_ms)) catch 0;
            if (ready == 0) {
                slice_ms = @min(slice_ms * 2, 50);
                continue;
            }
            slice_ms = 1;
            for (fds[0..2], [_]*std.ArrayList(u8){ &job.stdout, &job.stderr }) |*p, buf| {
                if (p.fd < 0 or p.revents == 0) continue;
                const n = readSome(p.fd, chunk);
                if (n == 0) {
                    _ = sys.close(p.fd);
                    p.fd = -1;
                    continue;
                }
                const room: usize = @intCast(job.bound -| buf.items.len);
                const keep = @min(n, room);
                if (keep < n) job.truncated = true;
                buf.appendSlice(std.heap.smp_allocator, chunk[0..keep]) catch {
                    job.truncated = true;
                };
            }
            if (fds[2].fd >= 0 and fds[2].revents != 0) {
                switch (writeSome(fds[2].fd, job.stdin[sent..])) {
                    .wrote => |n| sent += n,
                    .again => {},
                    .broke => sent = job.stdin.len,
                }
                if (sent == job.stdin.len) {
                    _ = sys.close(fds[2].fd);
                    fds[2].fd = -1;
                }
            }
        }
        // The descriptors fds holds are the pipes' ends; they are closed once, below.
        in_p[1] = fds[2].fd;
        out_p[0] = fds[0].fd;
        err_p[0] = fds[1].fd;
        if (timed_out) _ = sys.kill(-pid, .KILL);
        const status = reap(pid);
        job.took_ms = @intCast(@divFloor(job.now() - t0, std.time.ns_per_ms));
        if (timed_out) return .timeout;
        const st = status;
        if (posix.W.IFEXITED(st)) return .{ .exited = posix.W.EXITSTATUS(st) };
        if (posix.W.IFSIGNALED(st)) return .{ .signalled = @truncate(@intFromEnum(posix.W.TERMSIG(st))) };
        return .{ .failed = "the child ended neither by exiting nor by a signal" };
    }
};

const Started = union(enum) { pid: posix.pid_t, errno: posix.E, failed: []const u8 };

/// The child started with its pipes on 0, 1 and 2 and nothing else open, in its own session, in the
/// job's folder, every signal at its default and none blocked. On Darwin one posix_spawn does it:
/// CLOEXEC_DEFAULT has the kernel close every descriptor the file actions do not name, however
/// high, where a loop to the descriptor limit (here 1,048,576) cost 90 ms a run. Elsewhere the
/// child is forked, and `close_range` closes what is left (child).
fn start(job: *const Job, in_r: posix.fd_t, out_w: posix.fd_t, err_w: posix.fd_t) Started {
    if (builtin.os.tag.isDarwin()) {
        const c = std.c;
        var actions: c.posix_spawn_file_actions_t = undefined;
        if (c.posix_spawn_file_actions_init(&actions) != 0) return .{ .failed = "the system is out of resources" };
        defer _ = c.posix_spawn_file_actions_destroy(&actions);
        var attr: c.posix_spawnattr_t = undefined;
        if (c.posix_spawnattr_init(&attr) != 0) return .{ .failed = "the system is out of resources" };
        defer _ = c.posix_spawnattr_destroy(&attr);
        var every = posix.sigemptyset();
        var sig: u8 = 1;
        while (sig < 32) : (sig += 1) {
            if (sig != @intFromEnum(posix.SIG.KILL) and sig != @intFromEnum(posix.SIG.STOP)) posix.sigaddset(&every, @enumFromInt(sig));
        }
        const none = posix.sigemptyset();
        const set = [_]c_int{
            c.posix_spawn_file_actions_adddup2(&actions, in_r, 0),
            c.posix_spawn_file_actions_adddup2(&actions, out_w, 1),
            c.posix_spawn_file_actions_adddup2(&actions, err_w, 2),
            c.posix_spawn_file_actions_addfchdir_np(&actions, job.dir),
            spawn.posix_spawnattr_setsigdefault(&attr, &every),
            spawn.posix_spawnattr_setsigmask(&attr, &none),
            c.posix_spawnattr_setflags(&attr, .{ .SETSID = true, .CLOEXEC_DEFAULT = true, .SETSIGDEF = true, .SETSIGMASK = true }),
        };
        for (set) |rc| if (rc != 0) return .{ .failed = "the system is out of resources" };
        var pid: posix.pid_t = 0;
        const rc = c.posix_spawn(&pid, job.path, &actions, &attr, job.argv, job.envp);
        if (rc != 0) return .{ .errno = @enumFromInt(rc) };
        return .{ .pid = pid };
    } else {
        var report: [2]posix.fd_t = .{ -1, -1 };
        defer closeBoth(&report);
        if (!makePipe(&report)) return .{ .failed = "no pipe could be made" };
        const limit = closeLimit();
        const rc = sys.fork();
        if (posix.errno(rc) != .SUCCESS) return .{ .failed = "no process could be made" };
        const pid: posix.pid_t = @intCast(rc);
        if (pid == 0) child(job, in_r, out_w, err_w, report[1], limit);
        closeOne(&report[1]);
        // The child writes its errno here when it could not start the program; the pipe closes
        // without a byte when execve succeeds.
        var why: [4]u8 = undefined;
        if (readAll(report[0], &why) == 4) {
            _ = reap(pid);
            return .{ .errno = @enumFromInt(std.mem.readInt(u32, &why, .little)) };
        }
        return .{ .pid = pid };
    }
}

/// What std does not declare of Darwin's posix_spawn.
const spawn = struct {
    extern "c" fn posix_spawnattr_setsigdefault(attr: *std.c.posix_spawnattr_t, set: *const posix.sigset_t) c_int;
    extern "c" fn posix_spawnattr_setsigmask(attr: *std.c.posix_spawnattr_t, set: *const posix.sigset_t) c_int;
};

/// The child, between fork and execve (all but Darwin): only system calls, each through std's per-target
/// wrapper, and no allocation. It starts a session of its own (so it leads its own process group
/// and has no terminal), takes the pipes as 0, 1 and 2, works in the job's folder, has every signal
/// at its default and none blocked, and closes every other descriptor but the one it reports a
/// failure on, which closes itself when execve succeeds.
fn child(job: *const Job, in_r: posix.fd_t, out_w: posix.fd_t, err_w: posix.fd_t, report_w: posix.fd_t, limit: posix.fd_t) noreturn {
    _ = sys.setsid();
    for ([_][2]posix.fd_t{ .{ in_r, 0 }, .{ out_w, 1 }, .{ err_w, 2 } }) |d| {
        const e = posix.errno(sys.dup2(d[0], d[1]));
        if (e != .SUCCESS) bail(report_w, e);
    }
    const moved = posix.errno(sys.fchdir(job.dir));
    if (moved != .SUCCESS) bail(report_w, moved);
    const dfl: posix.Sigaction = .{ .handler = .{ .handler = posix.SIG.DFL }, .mask = posix.sigemptyset(), .flags = 0 };
    var sig: u8 = 1;
    while (sig < 32) : (sig += 1) {
        if (sig == @intFromEnum(posix.SIG.KILL) or sig == @intFromEnum(posix.SIG.STOP)) continue;
        _ = sys.sigaction(@enumFromInt(sig), &dfl, null);
    }
    const none = posix.sigemptyset();
    _ = sys.sigprocmask(posix.SIG.SETMASK, &none, null);
    closeFrom3(report_w, limit);
    bail(report_w, posix.errno(sys.execve(job.path, job.argv, job.envp)));
}

/// The child could not start the program: the errno of the call that failed goes to the parent, and
/// the child ends.
fn bail(report_w: posix.fd_t, e: posix.E) noreturn {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, @intFromEnum(e), .little);
    _ = sys.write(report_w, &buf, 4);
    exitNow(127);
}

const raw_linux = builtin.os.tag == .linux and !builtin.link_libc;

fn exitNow(code: u8) noreturn {
    if (raw_linux) std.os.linux.exit_group(code) else std.c._exit(code);
}

/// Every descriptor from 3 up closed, but `keep`: Linux's close_range where the kernel has it (5.9),
/// else one at a time up to the limit taken before the fork.
fn closeFrom3(keep: posix.fd_t, limit: posix.fd_t) void {
    if (builtin.os.tag == .linux) {
        const linux = std.os.linux;
        const hi = std.math.maxInt(i32);
        const no_flags: linux.CLOSE_RANGE = .{ .UNSHARE = false, .CLOEXEC = false };
        const below = if (keep > 3) posix.errno(linux.close_range(3, keep - 1, no_flags)) else .SUCCESS;
        const above = posix.errno(linux.close_range(keep + 1, hi, no_flags));
        if (below == .SUCCESS and above == .SUCCESS) return;
    }
    var fd: posix.fd_t = 3;
    while (fd < limit) : (fd += 1) {
        if (fd != keep) _ = sys.close(fd);
    }
}

/// How far closeFrom3 counts: the soft limit on descriptors, at most 2^20.
fn closeLimit() posix.fd_t {
    const r = posix.getrlimit(.NOFILE) catch return 1 << 16;
    return @intCast(@min(r.cur, 1 << 20));
}

fn makePipe(p: *[2]posix.fd_t) bool {
    var fds: [2]posix.fd_t = undefined;
    if (posix.errno(sys.pipe(&fds)) != .SUCCESS) return false;
    for (fds, 0..) |fd, i| {
        p[i] = high(fd) orelse {
            _ = sys.close(fds[0]);
            _ = sys.close(fds[1]);
            if (i == 1) closeOne(&p[0]);
            return false;
        };
    }
    return true;
}

/// `fd` moved to 3 or above if it is below, close-on-exec either way.
fn high(fd: posix.fd_t) ?posix.fd_t {
    if (fd >= 3) {
        _ = sys.fcntl(fd, posix.F.SETFD, @as(usize, posix.FD_CLOEXEC));
        return fd;
    }
    const rc = sys.fcntl(fd, posix.F.DUPFD_CLOEXEC, @as(usize, 3));
    if (posix.errno(rc) != .SUCCESS) return null;
    _ = sys.close(fd);
    return @intCast(rc);
}

fn closeOne(fd: *posix.fd_t) void {
    if (fd.* >= 0) _ = sys.close(fd.*);
    fd.* = -1;
}

fn closeBoth(p: *[2]posix.fd_t) void {
    closeOne(&p[0]);
    closeOne(&p[1]);
}

/// The write end of the child's stdin never blocks and never raises SIGPIPE: on Darwin the pipe
/// says so itself; on Linux blocking.alone's thread has SIGPIPE blocked, and a write to a child
/// that closed its stdin is EPIPE.
fn quietWrites(fd: posix.fd_t) void {
    const flags = sys.fcntl(fd, posix.F.GETFL, @as(usize, 0));
    if (posix.errno(flags) == .SUCCESS) {
        var o: posix.O = @bitCast(@as(u32, @intCast(flags)));
        o.NONBLOCK = true;
        _ = sys.fcntl(fd, posix.F.SETFL, @as(usize, @as(u32, @bitCast(o))));
    }
    if (builtin.os.tag.isDarwin()) _ = sys.fcntl(fd, std.c.F.SETNOSIGPIPE, @as(usize, 1));
}

/// What a read after poll gave: 0 when the pipe closed or failed.
fn readSome(fd: posix.fd_t, buf: []u8) usize {
    while (true) {
        const rc = sys.read(fd, buf.ptr, buf.len);
        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            else => return 0,
        }
    }
}

/// Up to `buf.len` bytes, reading until the pipe closes: 0 when it closed at once.
fn readAll(fd: posix.fd_t, buf: []u8) usize {
    var got: usize = 0;
    while (got < buf.len) {
        const rc = sys.read(fd, buf[got..].ptr, buf.len - got);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) break;
                got += @intCast(rc);
            },
            .INTR => continue,
            else => break,
        }
    }
    return got;
}

const Wrote = union(enum) { wrote: usize, again, broke };

fn writeSome(fd: posix.fd_t, bytes: []const u8) Wrote {
    while (true) {
        const rc = sys.write(fd, bytes.ptr, bytes.len);
        switch (posix.errno(rc)) {
            .SUCCESS => return .{ .wrote = @intCast(rc) },
            .INTR => continue,
            .AGAIN => return .again,
            else => return .broke,
        }
    }
}

/// Whether the child has exited, asked without reaping it (waitid with WNOWAIT), so its id still
/// names its process group.
fn exitedNotReaped(pid: posix.pid_t) bool {
    while (true) {
        // The signal number, the first field of both layouts: SIGCHLD once the child has exited,
        // 0 while it runs (WNOHANG).
        var signo: i32 = 0;
        const e = if (raw_linux) blk: {
            const linux = std.os.linux;
            var info = std.mem.zeroes(linux.siginfo_t);
            const rc = linux.waitid(.PID, pid, &info, linux.W.EXITED | linux.W.NOHANG | linux.W.NOWAIT, null);
            signo = @as(*const i32, @ptrCast(@alignCast(&info))).*;
            break :blk posix.errno(rc);
        } else blk: {
            var info = std.mem.zeroes(std.c.siginfo_t);
            const rc = libc.waitid(libc.P_PID, @intCast(pid), &info, libc.WEXITED | libc.WNOHANG | libc.WNOWAIT);
            signo = @as(*const i32, @ptrCast(@alignCast(&info))).*;
            break :blk posix.errno(rc);
        };
        switch (e) {
            .SUCCESS => return signo != 0,
            .INTR => continue,
            // No such child: it was reaped already, which only this code does. Any other failure
            // leaves the deadline to end the run.
            .CHILD => return true,
            else => return false,
        }
    }
}

/// waitid through libc (Darwin, and Linux when linked with it), which std does not declare.
const libc = struct {
    const P_PID: c_uint = 1;
    const WNOHANG: c_int = 0x01;
    const WEXITED: c_int = 0x04;
    const WNOWAIT: c_int = if (builtin.os.tag == .linux) 0x01000000 else 0x20;
    extern "c" fn waitid(idtype: c_uint, id: c_uint, infop: *std.c.siginfo_t, options: c_int) c_int;
};

/// The child reaped; its wait status.
fn reap(pid: posix.pid_t) u32 {
    while (true) {
        var status: u32 = 0;
        const e = if (raw_linux)
            posix.errno(std.os.linux.wait4(pid, &status, 0, null))
        else
            posix.errno(std.c.waitpid(pid, @ptrCast(&status), 0));
        switch (e) {
            .SUCCESS => return status,
            .INTR => continue,
            else => return 0,
        }
    }
}

/// Why a program could not be started, in a few words.
fn whyOf(e: posix.E) []const u8 {
    return switch (e) {
        .ACCES => "permission denied: not an executable file, or a folder on the way is not searchable",
        .NOEXEC => "not a program this system can run",
        .@"2BIG" => "the arguments and environment are too long",
        .NOMEM, .AGAIN => "the system is out of resources",
        .LOOP => "too many links on the way to the program",
        .NAMETOOLONG => "the path is too long",
        .ISDIR => "a folder, not a program",
        .TXTBSY => "the program is being written",
        else => "the program could not be started",
    };
}
