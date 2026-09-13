//! `mo`: the toolchain CLI. Subcommands land with their stages:
//!   mo check <file.mo>   tier 1 (lex, parse, check)      → exit 0 or diagnostics
//!   mo test  <file.mo>   tier 2 (run the module's tests) → summary + verified: line
//!   mo run   <file.mo>   run the module on the interpreter
//! Diagnostics render as prose by default and as JSON with --json.
const std = @import("std");
const Io = std.Io;
const mo = @import("mo");

const usage =
    \\usage: mo <check|test|run> <file.mo> [--json]
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: Io.File.Writer = .initStreaming(.stderr(), io, &stderr_buffer);
    const err = &stderr_writer.interface;
    defer err.flush() catch {};

    if (args.len < 3) {
        try err.writeAll(usage);
        try err.flush();
        std.process.exit(2);
    }
    const stage: mo.pipeline.Stage = if (std.mem.eql(u8, args[1], "check"))
        .check
    else if (std.mem.eql(u8, args[1], "test") or std.mem.eql(u8, args[1], "run"))
        .run
    else {
        try err.writeAll(usage);
        try err.flush();
        std.process.exit(2);
    };

    const source = try Io.Dir.cwd().readFileAlloc(io, args[2], arena, .limited(1 << 20));
    var diags: mo.diag.List = .empty;
    mo.pipeline.runTo(arena, source, stage, &diags) catch |e| switch (e) {
        error.NotImplemented => {
            try err.print("mo {s}: {s} passes {t}; the stages after it are not implemented yet (see toolchain/README.md for the build order)\n", .{ args[1], args[2], mo.pipeline.implemented });
            try err.flush();
            std.process.exit(3);
        },
        error.Rejected => {
            for (diags.items) |d| try mo.diag.renderProse(err, args[2], source, d);
            try err.flush();
            std.process.exit(1);
        },
        else => return e,
    };
}
