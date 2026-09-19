//! Blocking calls off the scheduler (step 30, part B): a file write and its fsync run on a small
//! pool of threads, so a process that writes through the store waits holding no scheduler, and every
//! other process on it goes on. The caller's update waits on a descriptor its scheduler's poller
//! watches, as a Net call waits on a socket (turns.zig, block): a process's fiber parks, and main's
//! code hands out turns. The call answers only once the pool's thread has synced, so `Ok` still means
//! the data is on disk, and a write whose caller crashed while it waited is on disk all the same.
//! runtime/mo_rt.c's blocking_write is the same.
const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

const turns_mod = @import("turns.zig");
const sim_mod = @import("sim.zig");
const vm_mod = @import("vm.zig");

/// The pool's threads.
pub const pool_threads = 4;

/// A write the pool runs: to a file the caller opened (step 40: the scope resolved it, so the pool
/// never looks a path up), or a replace in a folder the caller opened, and how it ended.
const Job = struct {
    op: Op,
    /// The open file a write goes to, or the folder a replace is in.
    fd: posix.fd_t,
    /// The name a replace swaps, in `fd`'s folder, and the Io its temporary name's randomness comes from.
    name: [:0]const u8 = "",
    io: ?std.Io = null,
    text: []const u8,
    ok: bool = false,
    done: std.atomic.Value(bool) = .init(false),
    read_fd: posix.fd_t = -1,
    write_fd: posix.fd_t = -1,
    next: ?*Job = null,

    const Op = enum { write, replace };

    fn now(job: *const Job) bool {
        return switch (job.op) {
            .write => writeNow(job.fd, job.text),
            .replace => replaceNow(job.io.?, job.fd, job.name, job.text),
        };
    }
};

const Pool = struct {
    io: std.Io = undefined,
    mutex: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    head: ?*Job = null,
    tail: ?*Job = null,
    started: bool = false,
};

var pool: Pool = .{};

/// Writes `text` to the open file `fd` and syncs it. Under `mo run` with processes the write runs on
/// the pool and the caller waits holding no scheduler; without, on this thread. True once it is on disk.
pub fn write(vm: *vm_mod.Vm, fd: posix.fd_t, text: []const u8) vm_mod.Error!bool {
    return run(vm, .{ .op = .write, .fd = fd, .text = text });
}

/// `Fs.replace` (step 40): `name` in the open folder `dir` holds exactly `text`, swapped in whole
/// (replaceNow), on the pool as `write` is.
pub fn replace(vm: *vm_mod.Vm, io: std.Io, dir: posix.fd_t, name: [:0]const u8, text: []const u8) vm_mod.Error!bool {
    return run(vm, .{ .op = .replace, .fd = dir, .name = name, .io = io, .text = text });
}

fn run(vm: *vm_mod.Vm, first: Job) vm_mod.Error!bool {
    var job = first;
    const sim = vm.sim orelse return job.now();
    const t = sim.turns orelse return job.now();
    if (!openSignal(&job) or !start(t.io)) return job.now();
    defer closeSignal(&job);
    submit(&job);
    // An hour at a time: the write answers when it is done, and its deadline is checked after it.
    while (!job.done.load(.acquire)) _ = try t.block(sim, job.read_fd, .read, 3_600_000);
    return job.ok;
}

fn submit(job: *Job) void {
    pool.mutex.lockUncancelable(pool.io);
    defer pool.mutex.unlock(pool.io);
    if (pool.tail) |last| last.next = job else pool.head = job;
    pool.tail = job;
    pool.cond.signal(pool.io);
}

fn start(io: std.Io) bool {
    if (!pool.started) pool.io = io;
    pool.mutex.lockUncancelable(pool.io);
    defer pool.mutex.unlock(pool.io);
    if (pool.started) return true;
    for (0..pool_threads) |_| {
        const th = std.Thread.spawn(.{ .stack_size = 256 << 10 }, worker, .{}) catch return false;
        th.detach();
    }
    pool.started = true;
    return true;
}

fn worker() void {
    while (true) {
        pool.mutex.lockUncancelable(pool.io);
        while (pool.head == null) pool.cond.waitUncancelable(pool.io, &pool.mutex);
        const job = pool.head.?;
        pool.head = job.next;
        if (pool.head == null) pool.tail = null;
        pool.mutex.unlock(pool.io);
        job.ok = job.now();
        job.done.store(true, .release);
        const one: u64 = 1;
        _ = posix.system.write(job.write_fd, std.mem.asBytes(&one), if (builtin.os.tag == .linux) 8 else 1);
    }
}

/// The write and its sync, on this thread, to a file already open for writing.
pub fn writeNow(fd: posix.fd_t, text: []const u8) bool {
    return writeAll(fd, text) and syncFd(fd);
}

fn writeAll(fd: posix.fd_t, text: []const u8) bool {
    const sys = posix.system;
    var done: usize = 0;
    while (done < text.len) {
        const w = sys.write(fd, text[done..].ptr, text.len - done);
        switch (posix.errno(w)) {
            .SUCCESS => {
                if (w == 0) return false;
                done += @intCast(w);
            },
            .INTR => continue,
            else => return false,
        }
    }
    return true;
}

/// fsync, as `write` has always synced (step 39 part F owes F_FULLFSYNC on macOS).
fn syncFd(fd: posix.fd_t) bool {
    while (true) switch (posix.errno(posix.system.fsync(fd))) {
        .SUCCESS => return true,
        .INTR => continue,
        else => return false,
    };
}

/// The replace, on this thread (design: mo-capabilities-for-the-harness, section 2): the text is
/// written to a new name in the same folder, unpredictable and created exclusively with mode 0600,
/// synced, renamed over `name`, and the folder synced, so a reader sees the old file or the new
/// one, never a part. Any failure before the rename removes the temporary name and leaves `name` as
/// it was. A folder sync that fails after the rename is false too: the new text is in place, but the
/// swap is not known to be on disk, as a `write` whose sync fails is not.
pub fn replaceNow(io: std.Io, dir: posix.fd_t, name: [:0]const u8, text: []const u8) bool {
    const sys = posix.system;
    // The temporary name is its own fixed length, not built from `name`, so every name a folder
    // can hold can be replaced.
    var buf: [64]u8 = undefined;
    var fd: posix.fd_t = -1;
    var temp: [:0]const u8 = undefined;
    for (0..8) |_| {
        var nonce: [12]u8 = undefined;
        io.randomSecure(&nonce) catch io.random(&nonce);
        temp = std.fmt.bufPrintZ(&buf, ".mo-replace-{x}", .{nonce}) catch return false;
        const flags: posix.O = .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true, .CLOEXEC = true };
        const rc = sys.openat(dir, temp.ptr, flags, @as(posix.mode_t, 0o600));
        switch (posix.errno(rc)) {
            .SUCCESS => {
                fd = @intCast(rc);
                break;
            },
            .EXIST, .INTR => continue,
            else => return false,
        }
    }
    if (fd < 0) return false;
    const written = writeAll(fd, text) and syncFd(fd);
    _ = sys.close(fd);
    if (!written or posix.errno(sys.renameat(dir, temp.ptr, dir, name.ptr)) != .SUCCESS) {
        _ = sys.unlinkat(dir, temp.ptr, 0);
        return false;
    }
    // The rename is on disk once its folder is.
    return syncFd(dir);
}

fn openSignal(job: *Job) bool {
    if (builtin.os.tag == .linux) {
        const linux = std.os.linux;
        const rc = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
        if (posix.errno(rc) != .SUCCESS) return false;
        job.read_fd = @intCast(rc);
        job.write_fd = job.read_fd;
        return true;
    }
    var fds: [2]posix.fd_t = undefined;
    if (posix.errno(posix.system.pipe(&fds)) != .SUCCESS) return false;
    job.read_fd = fds[0];
    job.write_fd = fds[1];
    return true;
}

fn closeSignal(job: *Job) void {
    _ = posix.system.close(job.read_fd);
    if (job.write_fd != job.read_fd) _ = posix.system.close(job.write_fd);
}

test "a write on the pool is on disk when it answers, and a replace leaves no temporary name" {
    var dir_buf: [64]u8 = undefined;
    const sys = posix.system;
    const folder = try std.fmt.bufPrintZ(&dir_buf, "/tmp/mo-blocking-{d}", .{std.os.linux.getpid()});
    const io = std.testing.io;
    std.Io.Dir.cwd().deleteTree(io, folder) catch {};
    try std.Io.Dir.cwd().createDir(io, folder, .default_dir);
    defer std.Io.Dir.cwd().deleteTree(io, folder) catch {};
    const dir_rc = sys.open(folder.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, @as(posix.mode_t, 0));
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(dir_rc));
    const dir: posix.fd_t = @intCast(dir_rc);
    defer _ = sys.close(dir);
    const rc = sys.openat(dir, "a.txt", .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true, .CLOEXEC = true }, @as(posix.mode_t, 0o666));
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(rc));
    const fd: posix.fd_t = @intCast(rc);
    defer _ = sys.close(fd);
    try std.testing.expect(writeNow(fd, "one\n"));
    try std.testing.expect(writeNow(fd, "two\n"));
    var job: Job = .{ .op = .write, .fd = fd, .text = "three\n" };
    try std.testing.expect(openSignal(&job) and start(io));
    defer closeSignal(&job);
    submit(&job);
    try std.testing.expect(@import("poller.zig").pollOne(job.read_fd, .read, 10_000));
    try std.testing.expect(job.done.load(.acquire) and job.ok);
    const a = try std.fmt.allocPrint(std.testing.allocator, "{s}/a.txt", .{folder});
    defer std.testing.allocator.free(a);
    const got = try std.Io.Dir.cwd().readFileAlloc(io, a, std.testing.allocator, .limited(1 << 10));
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("one\ntwo\nthree\n", got);
    try std.testing.expect(replaceNow(io, dir, "a.txt", "whole\n"));
    const swapped = try std.Io.Dir.cwd().readFileAlloc(io, a, std.testing.allocator, .limited(1 << 10));
    defer std.testing.allocator.free(swapped);
    try std.testing.expectEqualStrings("whole\n", swapped);
    // The longest name a folder holds is replaced too: the temporary name is not built from it.
    const long = "x" ** 255;
    try std.testing.expect(replaceNow(io, dir, long, "long\n"));
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(sys.unlinkat(dir, long, 0)));
    // A rename that fails (a folder is at the name): the folder stays and nothing is left behind.
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(sys.mkdirat(dir, "sub", 0o777)));
    try std.testing.expect(!replaceNow(io, dir, "sub", "no"));
    try std.testing.expectEqual(posix.E.SUCCESS, posix.errno(sys.unlinkat(dir, "sub", posix.AT.REMOVEDIR)));
    var opened = try std.Io.Dir.cwd().openDir(io, folder, .{ .iterate = true });
    defer opened.close(io);
    var it = opened.iterate();
    var names: usize = 0;
    while (try it.next(io)) |_| names += 1;
    try std.testing.expectEqual(@as(usize, 1), names);
}
