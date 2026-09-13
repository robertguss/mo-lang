//! Mutation tests of the contract machinery (step 19). Three corpus files state a `never`, an
//! `ensures`, and an `invariant`; each mutant below changes one of them the way a bug or a
//! careless fix would (a witness omitted, an error returned always, a body inverted) and must be
//! caught: `mo test` of the mutated file fails, as the corpus file itself passes. A mutant that
//! survives is a gap in what the file's tests and contracts can see, and is listed here with
//! `survives = true` and why, so the suite stays green while it records the gap; one that starts
//! being caught fails this test until the line is corrected.
const std = @import("std");
const Io = std.Io;
const diag = @import("diag.zig");
const pipeline = @import("pipeline.zig");
const program = @import("program.zig");
const runner = @import("runner.zig");

const Mutant = struct {
    file: []const u8,
    /// What it does, as the report names it.
    name: []const u8,
    /// The text replaced, which the file holds exactly once, and what replaces it.
    find: []const u8,
    replace: []const u8,
    /// A gap this test records: the mutant passes every test and contract of the file.
    survives: bool = false,
};

pub const mutants = [_]Mutant{
    // contracts/never.mo: never "a seat holds two bookings".
    .{ .file = "contracts/never.mo", .name = "the never's body inverted", .find = "    a.guest != b.guest", .replace = "    a.guest == b.guest" },
    .{ .file = "contracts/never.mo", .name = "the guard that refuses a taken seat omitted", .find = "  return Error(SeatTaken(seat: seat)) if held.map(fn(b) b.seat end).contains?(seat)\n", .replace = "" },
    .{ .file = "contracts/never.mo", .name = "an error returned always", .find = "  Ok(Booking(seat: seat, guest: guest))", .replace = "  Error(SeatTaken(seat: seat))" },
    // contracts/ensures.mo: ensures on add and checkout.
    .{ .file = "contracts/ensures.mo", .name = "add's count of items omitted", .find = "  cart.items += 1\n", .replace = "" },
    .{ .file = "contracts/ensures.mo", .name = "an error returned always", .find = "  Ok(cart.total)", .replace = "  Error(EmptyCart)" },
    .{ .file = "contracts/ensures.mo", .name = "checkout's ensures inverted", .find = "implies paid == cart.total", .replace = "implies paid != cart.total" },
    // processes/invariant.mo: invariant "the odometer never goes backwards".
    .{ .file = "processes/invariant.mo", .name = "the invariant's body inverted", .find = "    state.km >= old(state.km)", .replace = "    state.km < old(state.km)" },
    .{ .file = "processes/invariant.mo", .name = "a drive that goes backwards", .find = "        state.km += distance", .replace = "        state.km -= distance" },
    .{ .file = "processes/invariant.mo", .name = "a drive that sets the reading from the distance", .find = "        state.km += distance", .replace = "        state.km = 42 - distance" },
    .{
        .file = "processes/invariant.mo",
        .name = "the old(state) witness omitted from the invariant",
        .find = "    state.km >= old(state.km)",
        .replace = "    state.km >= state.km",
        // The file's one test drives forward only, so an invariant that compares the state with
        // itself holds everywhere the test goes: nothing in the file drives backwards.
        .survives = true,
    },
};

pub const Outcome = enum { caught, survived, rejected };

/// The mutated file's tests, run as `mo test` runs them; with no mutant, the file's own.
pub fn run(gpa: std.mem.Allocator, io: Io, root: []const u8, file: []const u8, mutant: ?Mutant) !Outcome {
    const path = try std.fs.path.join(gpa, &.{ root, file });
    var diags: diag.List = .empty;
    const original = try program.load(gpa, io, path, &diags);
    if (diags.items.len > 0) return .rejected;
    const source = original.main().source;
    const mutated = if (mutant) |m| blk: {
        const at = std.mem.indexOf(u8, source, m.find) orelse return error.MutantNotFound;
        if (std.mem.indexOfPos(u8, source, at + 1, m.find) != null) return error.MutantAmbiguous;
        break :blk try std.mem.concat(gpa, u8, &.{ source[0..at], m.replace, source[at + m.find.len ..] });
    } else source;
    var prog = try program.withMain(gpa, original, mutated);
    // The verified: line describes the file, not the mutant.
    if (prog.verified_lines.len > 0) prog.verified_lines[prog.verified_lines.len - 1] = .recorded;
    const r = pipeline.testProgram(gpa, prog, false, .{ .sim_runs = 100, .sim_seed = runner.seedOf(mutated) }, &diags) catch |err| switch (err) {
        error.Rejected => return .rejected,
        else => return err,
    };
    return if (r.summary.failures > 0) .caught else .survived;
}

test "mutants of a never, an ensures, and an invariant are caught by the file's tests, but the survivors listed" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const root = "../examples";
    Io.Dir.cwd().access(io, root, .{}) catch return; // no corpus checked out beside the toolchain
    // Each file passes as it is, so what a mutant fails is the mutant's.
    for ([_][]const u8{ "contracts/never.mo", "contracts/ensures.mo", "processes/invariant.mo" }) |file| {
        try std.testing.expectEqual(Outcome.survived, try run(arena, io, root, file, null));
    }
    var wrong: u32 = 0;
    for (mutants) |m| {
        const got = try run(arena, io, root, m.file, m);
        const want: Outcome = if (m.survives) .survived else .caught;
        if (got != want) {
            wrong += 1;
            std.debug.print("mutation: {s}, {s}: {t}, expected {t}\n", .{ m.file, m.name, got, want });
        }
    }
    try std.testing.expectEqual(@as(u32, 0), wrong);
}
