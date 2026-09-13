//! The stages in order, as one function the CLI, the corpus test, and the benchmark
//! harness all call. `runTo` stops after `stage` so each can be timed on its own. The
//! stages take a program (program.zig): the file given and every module it uses, joined
//! in dependency order.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const caps = @import("caps.zig");
const loops = @import("loops.zig");
const bytecode = @import("bytecode.zig");
const runner = @import("runner.zig");
const diag = @import("diag.zig");
const program = @import("program.zig");

pub const Stage = enum { lex, parse, check, lower, run };

pub const stages = [_]Stage{ .lex, .parse, .check, .lower, .run };

/// The last stage that handles the whole corpus. The corpus test fails if any file
/// gets `NotImplemented` from a stage up to this one.
pub const implemented: Stage = .run;

/// `TestsFailed`: the run stage ran every test and at least one failed.
pub const Error = error{ NotImplemented, OutOfMemory, Crash, Rejected, TestsFailed };

/// Runs the stages up to and including `stage`; `run` means every test of every module.
/// `Rejected` means a diagnostic was produced, by the loader or a stage; the records
/// are in `diags`, at offsets into the program's source. Nothing is freed: pass an
/// arena, and append to `diags` with the same allocator.
pub fn runTo(gpa: std.mem.Allocator, prog: program.Program, stage: Stage, diags: *diag.List) Error!void {
    const checked = try front(gpa, prog, stage, diags) orelse return;
    const lowered = try bytecode.lower(gpa, checked);
    if (stage == .lower) return;
    const r = try runner.run(gpa, &lowered);
    if (r.summary.failures > 0) return error.TestsFailed;
}

/// Checks and lowers a program, then runs the tests of the file it was loaded from, or
/// with `all` the tests of every module it loads, for `mo test` and the corpus test.
pub fn testProgram(gpa: std.mem.Allocator, prog: program.Program, all: bool, diags: *diag.List) Error!runner.Run {
    const checked = (try front(gpa, prog, .run, diags)).?;
    const lowered = try gpa.create(bytecode.Program);
    lowered.* = try bytecode.lower(gpa, checked);
    if (!all) {
        // The given file comes last, so its tests are the ones past its base.
        var mine: std.ArrayList(bytecode.Test) = .empty;
        for (lowered.tests) |t| if (t.at >= prog.main().base) try mine.append(gpa, t);
        lowered.tests = mine.items;
    }
    return runner.run(gpa, lowered);
}

pub const Main = struct { program: *const bytecode.Program, main: u32 };

/// Checks (tier 1) and lowers a program for `mo run`, and finds `main`; no test runs. A
/// program without `fn main(platform: Platform)` is MO0408.
pub fn mainProgram(gpa: std.mem.Allocator, prog: program.Program, diags: *diag.List) Error!Main {
    const checked = (try front(gpa, prog, .run, diags)).?;
    const sig = checked.mainSig() orelse {
        const e = caps.catalog.get(.no_main);
        const given = checked.modules[checked.modules.len - 1];
        const root = checked.tree.nodes[0];
        const module_decl = checked.tree.nodes[checked.tree.span(root.lhs, root.rhs)[given.items.start]];
        try diags.append(gpa, .{ .code = e.code, .category = e.category, .at = checked.tree.tokens[module_decl.main_token].start, .what = "this module has no fn main(platform: Platform), so mo run has nothing to run; mo test runs its tests", .why = e.why });
        return error.Rejected;
    };
    const lowered = try gpa.create(bytecode.Program);
    lowered.* = try bytecode.lower(gpa, checked);
    return .{ .program = lowered, .main = lowered.fn_of_sig[sig] };
}

test "mo run needs fn main: a module without one is MO0408" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    try std.testing.expectError(error.Rejected, mainProgram(arena, try program.single(arena, "m.mo", "# no main here\nmodule M\nfn one() : UInt8\n  1\nend\n"), &diags));
    try std.testing.expectEqualStrings("MO0408", diags.items[0].code);
    try std.testing.expectEqual(@as(u32, 15), diags.items[0].at);
    diags.clearRetainingCapacity();
    const m = try mainProgram(arena, try program.single(arena, "m.mo", "module M\nfn main(platform: Platform)\n  platform.exit(2)\nend\n"), &diags);
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
fn front(gpa: std.mem.Allocator, prog: program.Program, stage: Stage, diags: *diag.List) Error!?check.Checked {
    // What stopped the loader.
    if (diags.items.len > 0) return error.Rejected;
    const tokens = try lexer.lex(gpa, prog.source, diags);
    if (stage == .lex) return null;
    // One file is one module, so a second module line in it does not parse.
    const tree = if (prog.files.len == 1)
        try parser.parse(gpa, prog.source, tokens, diags)
    else
        try parser.parseProgram(gpa, prog.source, tokens, diags);
    if (stage == .parse) return null;
    const checked = try check.checkProgram(gpa, tree, prog.bases, diags);
    try oneMain(gpa, checked, diags);
    try caps.check(gpa, checked, diags);
    try loops.check(gpa, checked, diags);
    if (diags.items.len > 0) return error.Rejected;
    if (stage == .check) return null;
    return checked;
}

/// MO0320: fn main in two modules of one program (two in one module are MO0205).
fn oneMain(gpa: std.mem.Allocator, checked: check.Checked, diags: *diag.List) Error!void {
    const mains = try gpa.alloc(check.ModuleMain, checked.modules.len);
    const at = try gpa.alloc(u32, checked.modules.len);
    for (checked.modules, mains) |m, *mm| mm.* = .{ .path = m.path, .has_main = false };
    for (checked.sigs) |s| if (s.kind == .module and std.mem.eql(u8, s.name, "main")) {
        mains[s.module].has_main = true;
        at[s.module] = checked.tree.tokens[checked.tree.nodes[s.node].main_token].start;
    };
    const two = check.twoMains(mains) orelse return;
    const second = for (mains, 0..) |mm, k| {
        if (mm.has_main and std.mem.eql(u8, mm.path, two[1])) break k;
    } else unreachable;
    const e = check.catalog.get(.two_mains);
    const what = try std.fmt.allocPrint(gpa, "{s} declares fn main, and so does {s}; a program starts in one place.", .{ two[1], two[0] });
    try diags.append(gpa, .{ .code = e.code, .category = e.category, .at = at[second], .what = what, .why = e.why });
}
