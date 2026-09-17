//! The crypto brick's SHA-256 on 1 MiB called straight, with no `List(UInt8)` around it: the
//! baseline step 35 sets the rows against. Prints the best of five, each `count` hashes, in ms.
//!
//!   zig run -OReleaseFast --dep brick -Mroot=bench/step35/raw.zig -Mbrick=src/bricks/crypto.zig -- [count]
const std = @import("std");
const brick = @import("brick");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const count = if (args.len > 1) try std.fmt.parseInt(usize, args[1], 10) else 200;
    const data = try init.gpa.alloc(u8, 1 << 20);
    defer init.gpa.free(data);
    @memset(data, 'a');
    var best: i96 = std.math.maxInt(i96);
    var digest: [32]u8 = undefined;
    for (0..5) |_| {
        const t0 = std.Io.Clock.Timestamp.now(init.io, .awake);
        for (0..count) |_| brick.mo_crypto_sha256(data.ptr, data.len, &digest);
        const ns = t0.durationTo(std.Io.Clock.Timestamp.now(init.io, .awake)).raw.toNanoseconds();
        best = @min(best, ns);
    }
    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.print("raw sha256 {d} x 1 MiB: {d:.1} ms, {d:.0} MB/s\n", .{ count, @as(f64, @floatFromInt(best)) / 1e6, @as(f64, @floatFromInt(count)) / (@as(f64, @floatFromInt(best)) / 1e9) });
}
