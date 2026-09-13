//! The stages in order, as one function the CLI, the corpus test, and the benchmark
//! harness all call. `runTo` stops after `stage` so each can be timed on its own.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const caps = @import("caps.zig");
const bytecode = @import("bytecode.zig");
const runner = @import("runner.zig");
const diag = @import("diag.zig");

pub const Stage = enum { lex, parse, check, lower, run };

pub const stages = [_]Stage{ .lex, .parse, .check, .lower, .run };

/// The last stage that handles the whole corpus. The corpus test fails if any file
/// gets `NotImplemented` from a stage up to this one.
pub const implemented: Stage = .check;

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

/// The stages through check; null when `stage` stops before lowering.
fn front(gpa: std.mem.Allocator, source: []const u8, stage: Stage, diags: *diag.List) Error!?check.Checked {
    const tokens = try lexer.lex(gpa, source, diags);
    if (stage == .lex) return null;
    const tree = try parser.parse(gpa, source, tokens, diags);
    if (stage == .parse) return null;
    const checked = try check.check(gpa, tree, diags);
    try caps.check(gpa, checked, diags);
    if (diags.items.len > 0) return error.Rejected;
    if (stage == .check) return null;
    return checked;
}
