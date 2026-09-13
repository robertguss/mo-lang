//! The stages in order, as one function the CLI, the corpus test, and the benchmark
//! harness all call. `runTo` stops after `stage` so each can be timed on its own.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const caps = @import("caps.zig");
const loops = @import("loops.zig");
const bytecode = @import("bytecode.zig");
const runner = @import("runner.zig");
const diag = @import("diag.zig");

pub const Stage = enum { lex, parse, check, lower, run };

pub const stages = [_]Stage{ .lex, .parse, .check, .lower, .run };

/// The last stage that handles the whole corpus. The corpus test fails if any file
/// gets `NotImplemented` from a stage up to this one.
pub const implemented: Stage = .run;

/// `TestsFailed`: the run stage ran every test and at least one failed.
pub const Error = error{ NotImplemented, OutOfMemory, Crash, Rejected, TestsFailed };

/// Runs the stages up to and including `stage`; `run` means every test in the module.
/// `Rejected` means a diagnostic was produced; the records are in `diags`. Nothing is
/// freed: pass an arena, and append to `diags` with the same allocator.
pub fn runTo(gpa: std.mem.Allocator, source: []const u8, stage: Stage, diags: *diag.List) Error!void {
    const checked = try front(gpa, source, stage, diags) orelse return;
    const program = try bytecode.lower(gpa, checked);
    if (stage == .lower) return;
    const r = try runner.run(gpa, &program);
    if (r.summary.failures > 0) return error.TestsFailed;
}

/// Checks, lowers, and runs every test of `source`, for `mo test` and the corpus test.
pub fn testSource(gpa: std.mem.Allocator, source: []const u8, diags: *diag.List) Error!runner.Run {
    const checked = (try front(gpa, source, .run, diags)).?;
    const program = try gpa.create(bytecode.Program);
    program.* = try bytecode.lower(gpa, checked);
    return runner.run(gpa, program);
}

pub const Main = struct { program: *const bytecode.Program, main: u32 };

/// Checks (tier 1) and lowers `source` for `mo run`, and finds `main`; no test runs. A
/// module without `fn main(platform: Platform)` is MO0408.
pub fn mainProgram(gpa: std.mem.Allocator, source: []const u8, diags: *diag.List) Error!Main {
    const checked = (try front(gpa, source, .run, diags)).?;
    const sig = checked.mainSig() orelse {
        const e = caps.catalog.get(.no_main);
        const module_decl = checked.tree.nodes[checked.tree.span(checked.tree.nodes[0].lhs, checked.tree.nodes[0].rhs)[0]];
        try diags.append(gpa, .{ .code = e.code, .category = e.category, .at = checked.tree.tokens[module_decl.main_token].start, .what = "this module has no fn main(platform: Platform), so mo run has nothing to run; mo test runs its tests", .why = e.why });
        return error.Rejected;
    };
    const program = try gpa.create(bytecode.Program);
    program.* = try bytecode.lower(gpa, checked);
    return .{ .program = program, .main = program.fn_of_sig[sig] };
}

test "mo run needs fn main: a module without one is MO0408" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    try std.testing.expectError(error.Rejected, mainProgram(arena, "# no main here\nmodule M\nfn one() : UInt8\n  1\nend\n", &diags));
    try std.testing.expectEqualStrings("MO0408", diags.items[0].code);
    try std.testing.expectEqual(@as(u32, 15), diags.items[0].at);
    diags.clearRetainingCapacity();
    const m = try mainProgram(arena, "module M\nfn main(platform: Platform)\n  platform.exit(2)\nend\n", &diags);
    try std.testing.expectEqualStrings("main", m.program.functions[m.main].name);
}

/// MO0501 alone, for `mo fmt --check`: the loop rule over a file that parses, whatever
/// else the checker finds in it.
pub fn loopFindings(gpa: std.mem.Allocator, source: []const u8, out: *diag.List) Error!void {
    var scratch: diag.List = .empty;
    const tokens = try lexer.lex(gpa, source, &scratch);
    const tree = try parser.parse(gpa, source, tokens, &scratch);
    const checked = try check.check(gpa, tree, &scratch);
    try loops.check(gpa, checked, out);
}

/// The stages through check; null when `stage` stops before lowering.
fn front(gpa: std.mem.Allocator, source: []const u8, stage: Stage, diags: *diag.List) Error!?check.Checked {
    const tokens = try lexer.lex(gpa, source, diags);
    if (stage == .lex) return null;
    const tree = try parser.parse(gpa, source, tokens, diags);
    if (stage == .parse) return null;
    const checked = try check.check(gpa, tree, diags);
    try caps.check(gpa, checked, diags);
    try loops.check(gpa, checked, diags);
    if (diags.items.len > 0) return error.Rejected;
    if (stage == .check) return null;
    return checked;
}
