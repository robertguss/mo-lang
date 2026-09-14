//! Fibers (step 21): a stack and a saved stack pointer, switched to and from on one thread.
//! Under `mo run` a process's update runs on one (turns.zig), so an update that waits in `ask`,
//! `accept`, `read_line`, or `write` keeps its place without holding a thread. A fiber is
//! borrowed for one delivery and given back when the update ends; only an update that is waiting
//! keeps one, so a process at rest holds no stack at all.
//!
//! The switch is a few lines of assembly: it pushes the registers a call must preserve onto the
//! stack it leaves, saves that stack pointer, loads the other, and pops them back, so it depends
//! on nothing the compiler knows (std.Io.fiber.contextSwitch saves only sp, fp, and pc and relies
//! on the compiler to spill the rest, which it did not do for us). runtime/mo_rt.c switches with
//! the same assembly.
//!
//! A stack is address space reserved whole and committed as it is touched, with unmapped guard
//! pages below it, so running off its end faults and never writes over something else. The call
//! depth limit (contracts.depth_limit) keeps Mo code well inside it.
const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

/// A context not running: its stack pointer, below the registers its switch pushed.
pub const Context = struct { sp: usize = 0 };

/// Never mapped readable, below every stack: larger than any frame the vm makes, so no frame
/// steps over it.
const guard_bytes: usize = 1 << 20;

pub const Fiber = struct {
    context: Context,
    /// The whole mapping: the guard, then the stack.
    memory: []align(std.heap.page_size_min) u8,
    /// What it runs each time it is switched to after its last job ended, and with what.
    run: *const fn (*Fiber) void = undefined,
    owner: *anyopaque = undefined,
    arg: u32 = 0,
    /// Set by `run` before it returns: where the fiber switches when the job has ended.
    back: *Context = undefined,

    /// A fiber whose first switch runs `run`, on a stack of `stack_bytes`.
    pub fn create(stack_bytes: usize) error{OutOfMemory}!*Fiber {
        const len = std.mem.alignForward(usize, stack_bytes + guard_bytes, std.heap.pageSize());
        const memory = posix.mmap(null, len, .{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0) catch return error.OutOfMemory;
        if (builtin.os.tag == .linux) {
            _ = std.os.linux.mprotect(memory.ptr, guard_bytes, .{});
        } else {
            _ = std.c.mprotect(@ptrCast(memory.ptr), guard_bytes, .{});
        }
        const f = std.heap.smp_allocator.create(Fiber) catch {
            posix.munmap(memory);
            return error.OutOfMemory;
        };
        const top = std.mem.alignBackward(usize, @intFromPtr(memory.ptr) + memory.len, 16);
        // The frame a switch into it pops: zeroed registers, the fiber where `entry` looks for
        // it, and `entry` where the switch returns to.
        const frame = frameOf(top);
        @memset(frame.slots, 0);
        frame.slots[frame.fiber_slot] = @intFromPtr(f);
        frame.slots[frame.return_slot] = @intFromPtr(&entry);
        f.* = .{ .memory = memory, .context = .{ .sp = frame.sp } };
        return f;
    }

    pub fn destroy(f: *Fiber) void {
        posix.munmap(f.memory);
        std.heap.smp_allocator.destroy(f);
    }

    /// Gives back the stack's pages more than `keep` bytes below its top: they are mapped over
    /// with fresh ones, as Region.decommit does. Called on the fiber itself near its top, or on
    /// one not running.
    pub fn decommit(f: *Fiber, keep: usize) void {
        const lo = @intFromPtr(f.memory.ptr) + guard_bytes;
        const hi = std.mem.alignBackward(usize, @intFromPtr(f.memory.ptr) + f.memory.len - keep, std.heap.pageSize());
        if (hi <= lo) return;
        const at: [*]align(std.heap.page_size_min) u8 = @ptrFromInt(lo);
        _ = posix.mmap(at, hi - lo, .{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .FIXED = true }, -1, 0) catch {};
    }
};

/// Where a fresh stack's first frame goes, and which of its slots `entry` and the switch read.
fn frameOf(top: usize) struct { sp: usize, slots: []usize, fiber_slot: usize, return_slot: usize } {
    switch (builtin.cpu.arch) {
        // x19..x28, x29, x30, d8..d15: 20 slots; x19 holds the fiber, x30 the return.
        .aarch64 => {
            const sp = top - 160;
            return .{ .sp = sp, .slots = @as([*]usize, @ptrFromInt(sp))[0..20], .fiber_slot = 0, .return_slot = 11 };
        },
        // r15, r14, r13, r12, rbx, rbp, then the return address, and 8 bytes of padding so
        // `entry` starts with the stack as a call leaves it.
        .x86_64 => {
            const sp = top - 64;
            return .{ .sp = sp, .slots = @as([*]usize, @ptrFromInt(sp))[0..8], .fiber_slot = 4, .return_slot = 6 };
        },
        else => |arch| @compileError("fibers are not implemented for " ++ @tagName(arch)),
    }
}

/// Saves the running context in `from` and resumes `to`; returns when something switches back
/// to `from`.
pub fn switchTo(from: *Context, to: *Context) void {
    const f: *const fn (*Context, *Context) callconv(.c) void = @ptrCast(&swap);
    f(from, to);
}

fn swap() callconv(.naked) void {
    switch (builtin.cpu.arch) {
        .aarch64 => asm volatile (
            \\ sub sp, sp, #160
            \\ stp x19, x20, [sp, #0]
            \\ stp x21, x22, [sp, #16]
            \\ stp x23, x24, [sp, #32]
            \\ stp x25, x26, [sp, #48]
            \\ stp x27, x28, [sp, #64]
            \\ stp x29, x30, [sp, #80]
            \\ stp d8, d9, [sp, #96]
            \\ stp d10, d11, [sp, #112]
            \\ stp d12, d13, [sp, #128]
            \\ stp d14, d15, [sp, #144]
            \\ mov x2, sp
            \\ str x2, [x0]
            \\ ldr x2, [x1]
            \\ mov sp, x2
            \\ ldp x19, x20, [sp, #0]
            \\ ldp x21, x22, [sp, #16]
            \\ ldp x23, x24, [sp, #32]
            \\ ldp x25, x26, [sp, #48]
            \\ ldp x27, x28, [sp, #64]
            \\ ldp x29, x30, [sp, #80]
            \\ ldp d8, d9, [sp, #96]
            \\ ldp d10, d11, [sp, #112]
            \\ ldp d12, d13, [sp, #128]
            \\ ldp d14, d15, [sp, #144]
            \\ add sp, sp, #160
            \\ ret
        ),
        .x86_64 => asm volatile (
            \\ pushq %%rbp
            \\ pushq %%rbx
            \\ pushq %%r12
            \\ pushq %%r13
            \\ pushq %%r14
            \\ pushq %%r15
            \\ movq %%rsp, (%%rdi)
            \\ movq (%%rsi), %%rsp
            \\ popq %%r15
            \\ popq %%r14
            \\ popq %%r13
            \\ popq %%r12
            \\ popq %%rbx
            \\ popq %%rbp
            \\ retq
        ),
        else => |arch| @compileError("fibers are not implemented for " ++ @tagName(arch)),
    }
}

/// A fresh fiber's first instruction, where its first switch returns: the fiber is in the
/// register the switch popped it into, and becomes the first argument.
fn entry() callconv(.naked) void {
    switch (builtin.cpu.arch) {
        .aarch64 => asm volatile (
            \\ mov x0, x19
            \\ mov x29, #0
            \\ b %[start]
            :
            : [start] "X" (&start),
        ),
        .x86_64 => asm volatile (
            \\ movq %%rbx, %%rdi
            \\ xorl %%ebp, %%ebp
            \\ jmp %[start:P]
            :
            : [start] "X" (&start),
        ),
        else => |arch| @compileError("fibers are not implemented for " ++ @tagName(arch)),
    }
}

fn start(f: *Fiber) callconv(.c) noreturn {
    while (true) {
        f.run(f);
        switchTo(&f.context, f.back);
    }
}

const TestJob = struct {
    main: Context = .{},
    trace: std.ArrayList(u8) = .empty,

    fn run(f: *Fiber) void {
        const j: *TestJob = @ptrCast(@alignCast(f.owner));
        j.trace.appendAssumeCapacity('a' + @as(u8, @intCast(f.arg)));
        // Wait: back to main, keeping this stack and this frame's locals.
        var kept: [4]u64 = .{ f.arg, f.arg * 3, f.arg * 5, f.arg * 7 };
        std.mem.doNotOptimizeAway(&kept);
        switchTo(&f.context, &j.main);
        j.trace.appendAssumeCapacity('0' + @as(u8, @intCast(kept[0] + kept[1] + kept[2] + kept[3] - 15 * f.arg)));
        f.back = &j.main;
    }
};

/// Holds values in registers a call must preserve across switches, then checks them.
noinline fn churn(f: *Fiber, j: *TestJob, seed: u64) !void {
    var a = seed *% 0x9e37_79b9;
    var b = a ^ 0x5555;
    var c = b +% 17;
    const d: f64 = @floatFromInt(seed);
    switchTo(&j.main, &f.context);
    a +%= 1;
    b +%= 1;
    c +%= 1;
    try std.testing.expectEqual(seed *% 0x9e37_79b9 +% 1, a);
    try std.testing.expectEqual((seed *% 0x9e37_79b9 ^ 0x5555) +% 1, b);
    try std.testing.expectEqual((seed *% 0x9e37_79b9 ^ 0x5555) +% 18, c);
    try std.testing.expectEqual(@as(f64, @floatFromInt(seed)), d);
}

test "a fiber runs a job, waits in it keeping its locals and its caller's registers, goes on, and runs the next job" {
    var job: TestJob = .{};
    try job.trace.ensureTotalCapacity(std.testing.allocator, 16);
    defer job.trace.deinit(std.testing.allocator);
    const f = try Fiber.create(1 << 20);
    defer f.destroy();
    f.run = TestJob.run;
    f.owner = &job;
    f.arg = 1;
    try churn(f, &job, 11); // runs to the wait
    try churn(f, &job, 12); // goes on, and the job ends
    f.arg = 2;
    try churn(f, &job, 13);
    try churn(f, &job, 14);
    try std.testing.expectEqualStrings("b1c2", job.trace.items);
    f.decommit(64 << 10);
}
