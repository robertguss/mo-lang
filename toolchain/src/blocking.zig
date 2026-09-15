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

/// A write the pool runs: `path` NUL-terminated, the text, and how it ended.
const Job = struct {
    path: [*:0]const u8,
    text: []const u8,
    append: bool,
    ok: bool = false,
    done: std.atomic.Value(bool) = .init(false),
    read_fd: posix.fd_t = -1,
    write_fd: posix.fd_t = -1,
    next: ?*Job = null,
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

/// Writes `text` to `path` (the file created when it is not there, else truncated, or added to at its
/// end when `append`) and syncs it. Under `mo run` with processes the write runs on the pool and the
/// caller waits holding no scheduler; without, on this thread. True once it is on disk.
pub fn write(vm: *vm_mod.Vm, path: [:0]const u8, text: []const u8, append: bool) vm_mod.Error!bool {
    const sim = vm.sim orelse return writeNow(path, text, append);
    const t = sim.turns orelse return writeNow(path, text, append);
    var job: Job = .{ .path = path.ptr, .text = text, .append = append };
    if (!openSignal(&job) or !start(t.io)) return writeNow(path, text, append);
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
        job.ok = writeNow(std.mem.span(job.path), job.text, job.append);
        job.done.store(true, .release);
        const one: u64 = 1;
        _ = posix.system.write(job.write_fd, std.mem.asBytes(&one), if (builtin.os.tag == .linux) 8 else 1);
    }
}

/// The write and its sync, on this thread.
pub fn writeNow(path: [:0]const u8, text: []const u8, append: bool) bool {
    const sys = posix.system;
    var flags: posix.O = .{ .ACCMODE = .WRONLY, .CREAT = true, .CLOEXEC = true };
    if (append) flags.APPEND = true else flags.TRUNC = true;
    const rc = sys.open(path.ptr, flags, @as(posix.mode_t, 0o666));
    if (posix.errno(rc) != .SUCCESS) return false;
    const fd: posix.fd_t = @intCast(rc);
    defer _ = sys.close(fd);
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
    while (true) switch (posix.errno(sys.fsync(fd))) {
        .SUCCESS => return true,
        .INTR => continue,
        else => return false,
    };
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

test "a write on the pool is on disk when it answers" {
    var dir_buf: [64]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&dir_buf, "/tmp/mo-blocking-{d}.txt", .{std.os.linux.getpid()});
    defer _ = posix.system.unlink(path.ptr);
    try std.testing.expect(writeNow(path, "one\n", false));
    try std.testing.expect(writeNow(path, "two\n", true));
    var job: Job = .{ .path = path.ptr, .text = "three\n", .append = true };
    try std.testing.expect(openSignal(&job) and start(std.testing.io));
    defer closeSignal(&job);
    submit(&job);
    try std.testing.expect(@import("poller.zig").pollOne(job.read_fd, .read, 10_000));
    try std.testing.expect(job.done.load(.acquire) and job.ok);
    const got = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(1 << 10));
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("one\ntwo\nthree\n", got);
}
