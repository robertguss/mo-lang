//! The stages in order, as one function the CLI, the corpus test, and the benchmark
//! harness all call. `runTo` stops after `stage` so each can be timed on its own.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const caps = @import("caps.zig");
const bytecode = @import("bytecode.zig");
const diag = @import("diag.zig");

pub const Stage = enum { lex, parse, check, lower, run };

pub const stages = [_]Stage{ .lex, .parse, .check, .lower, .run };

/// The last stage that handles the whole corpus. The corpus test fails if any file
/// gets `NotImplemented` from a stage up to this one.
pub const implemented: Stage = .check;

pub const Error = error{ NotImplemented, OutOfMemory, Crash, Rejected };

/// Runs the stages up to and including `stage`. `Rejected` means a diagnostic was
/// produced; the records are in `diags`. Nothing is freed: pass an arena, and append
/// to `diags` with the same allocator.
pub fn runTo(gpa: std.mem.Allocator, source: []const u8, stage: Stage, diags: *diag.List) Error!void {
    const tokens = try lexer.lex(gpa, source, diags);
    if (stage == .lex) return;
    const tree = try parser.parse(gpa, source, tokens, diags);
    if (stage == .parse) return;
    const checked = try check.check(gpa, tree, diags);
    try caps.check(gpa, checked, diags);
    if (diags.items.len > 0) return error.Rejected;
    if (stage == .check) return;
    _ = try bytecode.lower(gpa, checked);
    if (stage == .lower) return;
    return error.NotImplemented;
}
