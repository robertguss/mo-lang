//! The poller (step 21): under `mo run` with processes, main's thread waits here for every
//! socket a Net call or a runtime loop waits on, with a timeout at the earliest deadline
//! (turns.zig, idle). kqueue on macOS and the BSDs, epoll on Linux. A waiter is armed once and
//! reported once; whoever still waits arms it again.
const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

pub const Filter = enum { read, write };

/// `Waiter.process` when no process waits: main's thread, or a runtime loop.
pub const nobody: u32 = std.math.maxInt(u32);

pub const Waiter = struct {
    fd: posix.fd_t,
    filter: Filter,
    /// Reported ready (or broken) since it was last armed.
    fired: bool = false,
    armed: bool = false,
    /// The process whose update waits on it, or nobody.
    process: u32 = nobody,
    /// The runtime loop (sources.zig) that waits on it, or null.
    source: ?*anyopaque = null,
    /// Linux: a write waiter watches a duplicate of the descriptor, since epoll keys a
    /// registration by descriptor and a read waiter may be watching the original.
    dup: posix.fd_t = -1,
};

const use_kqueue = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .netbsd, .openbsd, .dragonfly => true,
    else => false,
};
const use_epoll = builtin.os.tag == .linux;

/// Events one wait takes from the system at most; the rest wait for the next.
pub const batch = 256;

pub const Poller = struct {
    fd: posix.fd_t,

    pub fn init() error{SystemResources}!Poller {
        if (use_kqueue) {
            const rc = std.c.kqueue();
            if (rc < 0) return error.SystemResources;
            return .{ .fd = rc };
        }
        if (use_epoll) {
            const linux = std.os.linux;
            const rc = linux.epoll_create1(linux.EPOLL.CLOEXEC);
            if (posix.errno(rc) != .SUCCESS) return error.SystemResources;
            return .{ .fd = @intCast(rc) };
        }
        @compileError("mo run's poller needs kqueue or epoll");
    }

    pub fn deinit(p: *Poller) void {
        _ = posix.system.close(p.fd);
    }

    /// Reports `w` once its descriptor is ready. False when the system will not watch it:
    /// the waiter then tries its call again at once and meets whatever is wrong.
    pub fn arm(p: *Poller, w: *Waiter) bool {
        w.fired = false;
        if (w.armed) return true;
        if (use_kqueue) {
            var change = std.mem.zeroes(posix.Kevent);
            change.ident = @intCast(w.fd);
            change.filter = kqueueFilter(w.filter);
            change.flags = std.c.EV.ADD | std.c.EV.ONESHOT;
            change.udata = @intFromPtr(w);
            if (std.c.kevent(p.fd, @ptrCast(&change), 1, @ptrCast(&change), 0, null) < 0) return false;
        } else {
            const linux = std.os.linux;
            var fd = w.fd;
            if (w.filter == .write) {
                const d = linux.dup(w.fd);
                if (posix.errno(d) != .SUCCESS) return false;
                w.dup = @intCast(d);
                fd = w.dup;
            }
            var ev: linux.epoll_event = .{
                .events = @as(u32, if (w.filter == .read) linux.EPOLL.IN | linux.EPOLL.RDHUP else linux.EPOLL.OUT) | linux.EPOLL.ONESHOT,
                .data = .{ .ptr = @intFromPtr(w) },
            };
            if (posix.errno(linux.epoll_ctl(p.fd, linux.EPOLL.CTL_ADD, fd, &ev)) != .SUCCESS) {
                p.dropDup(w);
                return false;
            }
        }
        w.armed = true;
        return true;
    }

    /// Stops watching `w`, reported or not.
    pub fn disarm(p: *Poller, w: *Waiter) void {
        if (!w.armed) return;
        w.armed = false;
        if (use_kqueue) {
            var change = std.mem.zeroes(posix.Kevent);
            change.ident = @intCast(w.fd);
            change.filter = kqueueFilter(w.filter);
            change.flags = std.c.EV.DELETE;
            _ = std.c.kevent(p.fd, @ptrCast(&change), 1, @ptrCast(&change), 0, null);
        } else {
            p.epollDelete(w);
        }
    }

    /// Waits at most `timeout_ms` (null: until something is ready) and gives every waiter
    /// reported, each now `fired` and no longer armed, in `out`.
    pub fn wait(p: *Poller, timeout_ms: ?i64, out: *[batch]*Waiter) usize {
        if (use_kqueue) {
            var events: [batch]posix.Kevent = undefined;
            var ts: posix.timespec = undefined;
            const tsp: ?*const posix.timespec = if (timeout_ms) |ms| blk: {
                const m = @max(ms, 0);
                ts = .{ .sec = @intCast(@divTrunc(m, 1000)), .nsec = @intCast(@rem(m, 1000) * 1_000_000) };
                break :blk &ts;
            } else null;
            const rc = std.c.kevent(p.fd, &events, 0, &events, batch, tsp);
            if (rc <= 0) return 0;
            var k: usize = 0;
            for (events[0..@intCast(rc)]) |e| {
                if (e.udata == 0) continue;
                const w: *Waiter = @ptrFromInt(e.udata);
                w.armed = false;
                w.fired = true;
                out[k] = w;
                k += 1;
            }
            return k;
        }
        const linux = std.os.linux;
        var events: [batch]linux.epoll_event = undefined;
        const t: i32 = if (timeout_ms) |ms| @intCast(@min(@max(ms, 0), std.math.maxInt(i32))) else -1;
        const rc = linux.epoll_wait(p.fd, &events, batch, t);
        if (posix.errno(rc) != .SUCCESS) return 0;
        var k: usize = 0;
        for (events[0..rc]) |e| {
            const w: *Waiter = @ptrFromInt(e.data.ptr);
            // A one-shot registration stays behind, disabled, until it is deleted.
            p.epollDelete(w);
            w.armed = false;
            w.fired = true;
            out[k] = w;
            k += 1;
        }
        return k;
    }

    fn epollDelete(p: *Poller, w: *Waiter) void {
        const linux = std.os.linux;
        const fd = if (w.dup >= 0) w.dup else w.fd;
        _ = linux.epoll_ctl(p.fd, linux.EPOLL.CTL_DEL, fd, null);
        p.dropDup(w);
    }

    fn dropDup(p: *Poller, w: *Waiter) void {
        _ = p;
        if (w.dup < 0) return;
        _ = posix.system.close(w.dup);
        w.dup = -1;
    }
};

fn kqueueFilter(f: Filter) i16 {
    return if (f == .read) std.c.EVFILT.READ else std.c.EVFILT.WRITE;
}

/// Waits on one descriptor at most `ms`, blocking the thread: with no processes there is
/// nothing else to run. True when it is ready, or broke.
pub fn pollOne(fd: posix.fd_t, filter: Filter, ms: i64) bool {
    var fds = [_]posix.pollfd{.{ .fd = fd, .events = if (filter == .read) posix.POLL.IN else posix.POLL.OUT, .revents = 0 }};
    while (true) {
        const rc = posix.system.poll(&fds, 1, @intCast(@min(@max(ms, 0), std.math.maxInt(i32))));
        switch (posix.errno(rc)) {
            .SUCCESS => return rc > 0,
            .INTR => continue,
            else => return true,
        }
    }
}

test "a waiter is reported once when its descriptor is ready, and not before" {
    var p = try Poller.init();
    defer p.deinit();
    var fds: [2]posix.fd_t = undefined;
    if (posix.errno(posix.system.pipe(&fds)) != .SUCCESS) return error.SkipZigTest;
    defer _ = posix.system.close(fds[0]);
    defer _ = posix.system.close(fds[1]);
    var w: Waiter = .{ .fd = fds[0], .filter = .read };
    var out: [batch]*Waiter = undefined;
    try std.testing.expect(p.arm(&w));
    try std.testing.expectEqual(@as(usize, 0), p.wait(0, &out));
    _ = posix.system.write(fds[1], "x", 1);
    try std.testing.expectEqual(@as(usize, 1), p.wait(1000, &out));
    try std.testing.expect(out[0] == &w and w.fired and !w.armed);
    // One-shot: still readable, but not reported again until armed again.
    try std.testing.expectEqual(@as(usize, 0), p.wait(0, &out));
    try std.testing.expect(p.arm(&w));
    try std.testing.expectEqual(@as(usize, 1), p.wait(1000, &out));
    try std.testing.expect(p.arm(&w));
    p.disarm(&w);
    try std.testing.expectEqual(@as(usize, 0), p.wait(0, &out));
}
