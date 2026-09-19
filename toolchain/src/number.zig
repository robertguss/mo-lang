//! Numbers from source (step 43): every integer, float, mailbox bound, restart budget, and
//! Duration literal is held to its range by the checker, so neither runtime sees a number the
//! source never wrote.
const std = @import("std");
const Io = std.Io;

// ---- tests

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const diag = @import("diag.zig");

fn checkSource(arena: std.mem.Allocator, src: []const u8) ![]const diag.Record {
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    _ = try check.check(arena, tree, &diags);
    return diags.items;
}

/// The source checks with exactly these codes, in order; with `what`, the first says it.
fn expectCodes(src: []const u8, codes: []const []const u8, what: ?[]const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try checkSource(arena_state.allocator(), src);
    var ok = found.len == codes.len;
    if (ok) for (found, codes) |d, code| {
        if (!std.mem.eql(u8, d.code, code)) ok = false;
    };
    if (ok and what != null) ok = std.mem.eql(u8, found[0].what, what.?);
    if (!ok) {
        std.debug.print("source:\n{s}\nexpected {d} diagnostics:", .{ src, codes.len });
        for (codes) |code| std.debug.print(" {s}", .{code});
        if (what) |w| std.debug.print(" saying \"{s}\"", .{w});
        std.debug.print("\nfound:\n", .{});
        for (found) |d| std.debug.print("  {s} at {d}: {s}\n", .{ d.code, d.at, d.what });
    }
    try std.testing.expect(ok);
}

const refused: []const []const u8 = &.{"MO0217"};
const accepted: []const []const u8 = &.{};

fn returned(arena: std.mem.Allocator, ty: []const u8, literal: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "module T.Lit\nfn f() : {s}\n  {s}\nend\n", .{ ty, literal });
}

fn matched(arena: std.mem.Allocator, ty: []const u8, literal: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "module T.Pat\nfn f(x: {s}) : Bool\n  case x\n    -{s}: true\n    _: false\n  end\nend\n", .{ ty, literal });
}

fn process(arena: std.mem.Allocator, header: []const u8, child: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena,
        \\module T.Box
        \\process Counter(){s}
        \\  state
        \\    count: UInt64
        \\  end
        \\  message Count : UInt64
        \\  fn update(state, message)
        \\    case message
        \\      Count: state.count
        \\    end
        \\  end
        \\end
        \\supervisor Counters
        \\  child Counter, restart: :always{s}
        \\end
        \\
    , .{ header, child });
}

const Edge = struct { ty: []const u8, max: []const u8, past: []const u8, min: ?[]const u8 = null, below: ?[]const u8 = null };

/// Each sized type's largest value and one past it; a signed type's smallest's magnitude and one
/// past that.
const edges = [_]Edge{
    .{ .ty = "Int8", .max = "127", .past = "128", .min = "128", .below = "129" },
    .{ .ty = "Int16", .max = "32767", .past = "32768", .min = "32768", .below = "32769" },
    .{ .ty = "Int32", .max = "2147483647", .past = "2147483648", .min = "2147483648", .below = "2147483649" },
    .{ .ty = "Int64", .max = "9223372036854775807", .past = "9223372036854775808", .min = "9223372036854775808", .below = "9223372036854775809" },
    .{ .ty = "UInt8", .max = "255", .past = "256" },
    .{ .ty = "UInt16", .max = "65535", .past = "65536" },
    .{ .ty = "UInt32", .max = "4294967295", .past = "4294967296" },
    .{ .ty = "UInt64", .max = "18446744073709551615", .past = "18446744073709551616" },
};

const zeros32 = "00000000000000000000000000000000";
const digits54 = "999999999999999999999999999999999999999999999999999999";
const digits26 = "99999999999999999999999999";

test "number: every sized type takes its largest literal and refuses one past it, leading zeros or not" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for (edges) |e| {
        try expectCodes(try returned(arena, e.ty, e.max), accepted, null);
        try expectCodes(try returned(arena, e.ty, e.past), refused, try std.fmt.allocPrint(arena, "{s} does not fit in {s}", .{ e.past, e.ty }));
        try expectCodes(try returned(arena, e.ty, try std.fmt.allocPrint(arena, "{s}{s}", .{ zeros32, e.max })), accepted, null);
        const padded = try std.fmt.allocPrint(arena, "{s}{s}", .{ zeros32, e.past });
        try expectCodes(try returned(arena, e.ty, padded), refused, try std.fmt.allocPrint(arena, "{s} does not fit in {s}", .{ padded, e.ty }));
        try expectCodes(try returned(arena, e.ty, digits54), refused, try std.fmt.allocPrint(arena, "{s} does not fit in {s}", .{ digits54, e.ty }));
    }
}

test "number: the auditor's and the lead's literals are refused, the message printing each as written" {
    try expectCodes("module T.A\nfn f() : UInt64\n  18446744073709551616\nend\n", refused, "18446744073709551616 does not fit in UInt64");
    try expectCodes("module T.A\nfn f() : UInt8\n  " ++ zeros32 ++ "256\nend\n", refused, zeros32 ++ "256 does not fit in UInt8");
    try expectCodes("module T.A\nfn f() : Int8\n  0000000000000000000000000000000000000200\nend\n", refused, "0000000000000000000000000000000000000200 does not fit in Int8");
    try expectCodes("module T.A\nfn f() : UInt64\n  " ++ digits54 ++ "\nend\n", refused, digits54 ++ " does not fit in UInt64");
    // A literal no type constrains is an Int64.
    try expectCodes("module T.A\nfn f() : String\n  a = " ++ digits54 ++ "\n  \"#{a}\"\nend\n", refused, digits54 ++ " does not fit in Int64");
}

test "number: a negative pattern takes each signed type's smallest and refuses one below it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for (edges) |e| {
        const min = e.min orelse {
            try expectCodes(try matched(arena, e.ty, "1"), refused, try std.fmt.allocPrint(arena, "-1 does not fit in {s}", .{e.ty}));
            continue;
        };
        try expectCodes(try matched(arena, e.ty, min), accepted, null);
        try expectCodes(try matched(arena, e.ty, try std.fmt.allocPrint(arena, "{s}{s}", .{ zeros32, min })), accepted, null);
        try expectCodes(try matched(arena, e.ty, e.below.?), refused, try std.fmt.allocPrint(arena, "-{s} does not fit in {s}", .{ e.below.?, e.ty }));
        try expectCodes(try matched(arena, e.ty, digits54), refused, try std.fmt.allocPrint(arena, "-{s} does not fit in {s}", .{ digits54, e.ty }));
    }
}

test "number: underscores anywhere the lexer takes them change nothing about the value" {
    try expectCodes("module T.A\nfn f() : UInt64\n  18_446_744_073_709_551_615\nend\n", accepted, null);
    try expectCodes("module T.A\nfn f() : UInt64\n  18_446_744_073_709_551_616\nend\n", refused, "18_446_744_073_709_551_616 does not fit in UInt64");
    try expectCodes("module T.A\nfn f() : UInt8\n  2__5_5_\nend\n", accepted, null);
    try expectCodes("module T.A\nfn f() : UInt8\n  0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_256\nend\n", refused, "0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0_256 does not fit in UInt8");
    try expectCodes("module T.A\nfn f(x: Int8) : Bool\n  case x\n    -1_2_8: true\n    _: false\n  end\nend\n", accepted, null);
    try expectCodes("module T.A\nfn f(x: Int8) : Bool\n  case x\n    -1_2_9: true\n    _: false\n  end\nend\n", refused, "-1_2_9 does not fit in Int8");
}

test "number: a mailbox bound is 1 to 4,294,967,295" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for ([_][]const u8{ "1", "100", "4294967295", "4_294_967_295", zeros32 ++ "4294967295" }) |ok| {
        try expectCodes(try process(arena, try std.fmt.allocPrint(arena, " mailbox: {s}", .{ok}), ""), accepted, null);
    }
    for ([_][]const u8{ "0", "4294967296", "4_294_967_296", digits26, zeros32 ++ "4294967296" }) |bad| {
        try expectCodes(try process(arena, try std.fmt.allocPrint(arena, " mailbox: {s}", .{bad}), ""), refused, try std.fmt.allocPrint(arena, "mailbox: {s} does not fit in a mailbox bound, 1 to 4,294,967,295", .{bad}));
    }
}

test "number: a restart budget is 0 to 4,294,967,294" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for ([_][]const u8{ "0", "5", "4294967294" }) |ok| {
        try expectCodes(try process(arena, "", try std.fmt.allocPrint(arena, ", max_restarts: {s} per 1.minute", .{ok})), accepted, null);
    }
    // 4,294,967,295 is the lowering's mark for a line with no max_restarts: it read as 3.
    for ([_][]const u8{ "4294967295", "4294967296", digits26 }) |bad| {
        try expectCodes(try process(arena, "", try std.fmt.allocPrint(arena, ", max_restarts: {s} per 1.minute", .{bad})), refused, try std.fmt.allocPrint(arena, "max_restarts: {s} does not fit in a restart budget, 0 to 4,294,967,294", .{bad}));
    }
}

test "number: a Duration written as a literal and a unit fits a Duration's milliseconds" {
    const Unit = struct { name: []const u8, max: []const u8, past: []const u8 };
    const units = [_]Unit{
        .{ .name = "ms", .max = "9223372036854775807", .past = "9223372036854775808" },
        .{ .name = "seconds", .max = "9223372036854775", .past = "9223372036854776" },
        .{ .name = "minute", .max = "153722867280912", .past = "153722867280913" },
        .{ .name = "days", .max = "106751991167", .past = "106751991168" },
    };
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for (units) |u| {
        try expectCodes(try returned(arena, "Duration", try std.fmt.allocPrint(arena, "{s}.{s}", .{ u.max, u.name })), accepted, null);
        const past = try std.fmt.allocPrint(arena, "{s}.{s}", .{ u.past, u.name });
        const what = if (std.mem.eql(u8, u.name, "ms")) try std.fmt.allocPrint(arena, "{s} does not fit in Int64", .{u.past}) else try std.fmt.allocPrint(arena, "{s} does not fit in Duration", .{past});
        try expectCodes(try returned(arena, "Duration", past), refused, what);
    }
    // One diagnostic, the literal's own, when the number alone is already too large.
    try expectCodes(try returned(arena, "Duration", digits54 ++ ".days"), refused, digits54 ++ " does not fit in Int64");
}

test "number: a float literal past Float64's largest is refused, not read as infinity" {
    const big = "9" ** 400 ++ ".5";
    try expectCodes("module T.F\nfn f() : Float64\n  " ++ big ++ "\nend\n", refused, big ++ " does not fit in Float64");
    try expectCodes("module T.F\nfn f(x: Float64) : Bool\n  case x\n    " ++ big ++ ": true\n    _: false\n  end\nend\n", refused, big ++ " does not fit in Float64");
    // Float64's largest finite value, written out, and a tiny one, which rounds as every float does.
    const largest = "179769313486231570" ++ "0" ** 291 ++ ".0";
    try expectCodes("module T.F\nfn f() : Float64\n  " ++ largest ++ "\nend\n", accepted, null);
    try expectCodes("module T.F\nfn f() : Float64\n  0." ++ "0" ** 400 ++ "1\nend\n", accepted, null);
}

test "number: a port and a tuple position from source are held to their range" {
    try expectCodes(
        \\module T.Port
        \\fn f(net: Net) : Bool
        \\  net.listen(65536, within: 1.minute) is Ok(_)
        \\end
    , refused, "65536 does not fit in UInt16");
    try expectCodes(
        \\module T.Port
        \\fn f(http: Http) : Bool
        \\  http.send(Request(method: "GET", path: "/"), host: "localhost", port: 65536, within: 1.minute) is Ok(_)
        \\end
    , refused, "65536 does not fit in UInt16");
    try expectCodes("module T.Tup\nfn f() : Int64\n  t = (1, 2)\n  t." ++ digits26 ++ "\nend\n", &.{"MO0208"}, "(an integer, an integer) has no position " ++ digits26);
}

test "number: Int64's and Duration's smallest are negated only by routes the checker refuses or the runtime traps" {
    // No abs on an integer, no unary minus on a Duration, and no Duration * an integer.
    try expectCodes("module T.N\nfn f(n: Int64) : Int64\n  n.abs\nend\n", &.{"MO0208"}, null);
    try expectCodes("module T.N\nfn f(d: Duration) : Duration\n  -d\nend\n", &.{"MO0206"}, null);
    try expectCodes("module T.N\nfn f(d: Duration) : Duration\n  d * -1\nend\n", &.{"MO0206"}, null);
    // These check; each traps at run time (the end-to-end test below).
    try expectCodes("module T.N\nfn f(n: Int64) : Int64\n  0 - n\nend\n", accepted, null);
    try expectCodes("module T.N\nfn f(n: Int64) : Int64\n  n * -1\nend\n", accepted, null);
    try expectCodes("module T.N\nfn f(n: Int64) : Int64\n  -n\nend\n", accepted, null);
    try expectCodes("module T.N\nfn f(d: Duration) : Duration\n  0.ms - d\nend\n", accepted, null);
}

// ---- end to end: mo check, mo run, and mo build on whole programs

const Refusal = struct { name: []const u8, source: []const u8, code: []const u8, what: []const u8 };

fn program(comptime name: []const u8, comptime ty: []const u8, comptime literal: []const u8) []const u8 {
    return "module P." ++ name ++ "\nfn value() : " ++ ty ++ "\n  " ++ literal ++ "\nend\nfn main(platform: Platform)\n  platform.stdout.write(\"#{value()}\\n\")\nend\n";
}

fn boxed(comptime header: []const u8, comptime child: []const u8) []const u8 {
    return "module P.Box\nprocess Counter()" ++ header ++ "\n  state\n    count: UInt64\n  end\n  message Count : UInt64\n  fn update(state, message)\n    case message\n      Count: state.count\n    end\n  end\nend\nsupervisor Counters\n  child Counter, restart: :always" ++ child ++ "\nend\nfn main(platform: Platform)\n  platform.stdout.write(\"ok\\n\")\nend\n";
}

const refusals = [_]Refusal{
    .{ .name = "oversized", .source = program("Oversized", "UInt64", "18446744073709551616"), .code = "MO0217", .what = "18446744073709551616 does not fit in UInt64" },
    .{ .name = "leading-zero", .source = program("LeadingZero", "UInt8", zeros32 ++ "256"), .code = "MO0217", .what = zeros32 ++ "256 does not fit in UInt8" },
    .{ .name = "lz-int8", .source = program("LzInt8", "Int8", "0000000000000000000000000000000000000200"), .code = "MO0217", .what = "0000000000000000000000000000000000000200 does not fit in Int8" },
    .{ .name = "huge", .source = program("Huge", "UInt64", digits54), .code = "MO0217", .what = digits54 ++ " does not fit in UInt64" },
    .{ .name = "float", .source = program("Float", "Float64", "9" ** 400 ++ ".0"), .code = "MO0217", .what = "9" ** 400 ++ ".0 does not fit in Float64" },
    .{ .name = "days", .source = program("Days", "Duration", "106751991168.days"), .code = "MO0217", .what = "106751991168.days does not fit in Duration" },
    .{ .name = "mailbox-overflow", .source = boxed(" mailbox: 4294967296", ""), .code = "MO0217", .what = "mailbox: 4294967296 does not fit in a mailbox bound, 1 to 4,294,967,295" },
    .{ .name = "mailbox-huge", .source = boxed(" mailbox: " ++ digits26, ""), .code = "MO0217", .what = "mailbox: " ++ digits26 ++ " does not fit in a mailbox bound, 1 to 4,294,967,295" },
    .{ .name = "mailbox-zero", .source = boxed(" mailbox: 0", ""), .code = "MO0217", .what = "mailbox: 0 does not fit in a mailbox bound, 1 to 4,294,967,295" },
    .{ .name = "restarts", .source = boxed("", ", max_restarts: 4294967296 per 1.minute"), .code = "MO0217", .what = "max_restarts: 4294967296 does not fit in a restart budget, 0 to 4,294,967,294" },
};

fn moExe(arena: std.mem.Allocator, io: Io) ![]const u8 {
    const from_environ = std.testing.environ.getAlloc(arena, "MO_EXE") catch null;
    return Io.Dir.cwd().realPathFileAlloc(io, from_environ orelse "zig-out/bin/mo", arena);
}

fn exitCode(term: std.process.Child.Term) ?u8 {
    return switch (term) {
        .exited => |code| code,
        else => null,
    };
}

test "number: mo check, mo run, and mo build refuse each out-of-range number with its diagnostic, not a panic or a value" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const mo_exe = try moExe(arena, io);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const cwd = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    var wrong: u32 = 0;
    for (refusals) |r| {
        const file = try std.fmt.allocPrint(arena, "{s}.mo", .{r.name});
        try tmp.dir.writeFile(io, .{ .sub_path = file, .data = r.source });
        const want = try std.fmt.allocPrint(arena, "{s}:3:", .{file});
        for ([_][]const []const u8{ &.{ mo_exe, "check", file }, &.{ mo_exe, "run", file }, &.{ mo_exe, "build", file, "-o", r.name } }) |argv| {
            const ran = try std.process.run(arena, io, .{ .argv = argv, .cwd = .{ .path = cwd } });
            const line = try std.fmt.allocPrint(arena, " {s} {s}\n", .{ r.code, r.what });
            const said = std.mem.indexOf(u8, ran.stderr, line) != null and std.mem.indexOf(u8, ran.stderr, file) != null;
            if (exitCode(ran.term) != 1 or !said or ran.stdout.len != 0) {
                wrong += 1;
                std.debug.print("{s} {s}: term {any}, want exit 1 and \"{s}{s}\"\nstdout: {s}\nstderr: {s}\n", .{ argv[1], file, ran.term, want, line, ran.stdout, ran.stderr[0..@min(ran.stderr.len, 400)] });
            }
        }
    }
    try std.testing.expectEqual(@as(u32, 0), wrong);
}

test "number: the largest literals and bounds run alike under mo run and as a binary, and negating a smallest traps in both" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const mo_exe = try moExe(arena, io);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const cwd = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    const Case = struct { name: []const u8, source: []const u8, exit: u8, stdout: []const u8, stderr: []const u8 };
    const cases = [_]Case{
        .{ .name = "edges", .exit = 0, .stderr = "", .stdout = "127 -128 18446744073709551615 255 -9223372036854775808 true 106751991167 4294967295\n", .source =
        \\module P.Edges
        \\process Big() mailbox: 4_294_967_295
        \\  state
        \\    count: UInt64
        \\  end
        \\  message Count : UInt64
        \\  fn update(state, message)
        \\    case message
        \\      Count: state.count
        \\    end
        \\  end
        \\end
        \\supervisor Bigs
        \\  child Big, restart: :always, max_restarts: 4294967294 per 1.minute
        \\end
        \\fn small(x: Int8) : Int8
        \\  case x
        \\    -128: x
        \\    _: 127
        \\  end
        \\end
        \\fn least(x: Int64) : Int64
        \\  case x
        \\    -9_223_372_036_854_775_808: x
        \\    _: 0
        \\  end
        \\end
        \\fn top() : Int8
        \\  127
        \\end
        \\fn wide() : UInt64
        \\  0000000000000000000000000000000018446744073709551615
        \\end
        \\fn byte() : UInt8
        \\  2_5_5
        \\end
        \\fn main(platform: Platform)
        \\  low = small(top() - 127 - 127 - 1)
        \\  floor = least(-9_223_372_036_854_775_807 - 1)
        \\  far = 106751991167.days
        \\  platform.stdout.write("#{top()} #{low} #{wide()} #{byte()} #{floor} #{far.ms > 0} #{far.ms / 86_400_000} 4294967295\n")
        \\end
        \\
        },
        .{ .name = "float-underscores", .exit = 0, .stderr = "", .stdout = "1000.5 1.5 10.25 1.5\n", .source = 
        \\module P.FloatUnderscores
        \\fn sign(x: Float64) : Float64
        \\  case x
        \\    -2__5.0: 1.5
        \\    _: -2.5
        \\  end
        \\end
        \\fn main(platform: Platform)
        \\  platform.stdout.write("#{1_000.5} #{1_.5} #{1__0.25} #{sign(0.0 - 25.0)}\n")
        \\end
        \\
        },
        .{ .name = "int-sub", .exit = 70, .stdout = "", .stderr = "main crashed: int-sub.mo:4:7: overflow in 0 - n; left = 0, right = -9223372036854775808\n", .source =
        \\module P.IntSub
        \\fn main(platform: Platform)
        \\  n = -9223372036854775807 - 1
        \\  a = 0 - n
        \\  platform.stdout.write("#{a}\n")
        \\end
        \\
        },
        .{ .name = "int-mul", .exit = 70, .stdout = "", .stderr = "main crashed: int-mul.mo:4:7: overflow in n * -1; left = -9223372036854775808, right = -1\n", .source =
        \\module P.IntMul
        \\fn main(platform: Platform)
        \\  n = -9223372036854775807 - 1
        \\  a = n * -1
        \\  platform.stdout.write("#{a}\n")
        \\end
        \\
        },
        .{ .name = "int-neg", .exit = 70, .stdout = "", .stderr = "", .source =
        \\module P.IntNeg
        \\fn main(platform: Platform)
        \\  n = -9223372036854775807 - 1
        \\  a = -n
        \\  platform.stdout.write("#{a}\n")
        \\end
        \\
        },
        .{ .name = "dur-sub", .exit = 70, .stdout = "", .stderr = "main crashed: dur-sub.mo:5:7: overflow in 0.ms - d; left = 0.ms, right = -9223372036854775808.ms\n", .source =
        \\module P.DurSub
        \\fn main(platform: Platform)
        \\  n = -9223372036854775807 - 1
        \\  d = n.ms
        \\  e = 0.ms - d
        \\  platform.stdout.write("#{e.ms}\n")
        \\end
        \\
        },
    };
    var wrong: u32 = 0;
    for (cases) |c| {
        const file = try std.fmt.allocPrint(arena, "{s}.mo", .{c.name});
        try tmp.dir.writeFile(io, .{ .sub_path = file, .data = c.source });
        const interp = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "run", file }, .cwd = .{ .path = cwd } });
        const made = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "build", file, "-o", c.name }, .cwd = .{ .path = cwd } });
        if (exitCode(made.term) != 0) {
            wrong += 1;
            std.debug.print("build {s}: {any}\n{s}\n", .{ file, made.term, made.stderr });
            continue;
        }
        const binary = try std.fmt.allocPrint(arena, "./zig-out/mo-build/{s}/{s}", .{ c.name, c.name });
        const native = try std.process.run(arena, io, .{ .argv = &.{binary}, .cwd = .{ .path = cwd } });
        for ([_]std.process.RunResult{ interp, native }, [_][]const u8{ "mo run", "binary" }) |ran, how| {
            const stderr_ok = if (c.stderr.len == 0) (c.exit == 0) == (ran.stderr.len == 0) else std.mem.eql(u8, ran.stderr, c.stderr);
            if (exitCode(ran.term) != c.exit or !std.mem.eql(u8, ran.stdout, c.stdout) or !stderr_ok) {
                wrong += 1;
                std.debug.print("{s} {s}: {any}, want exit {d}\nstdout: {s}\nstderr: {s}\n", .{ how, file, ran.term, c.exit, ran.stdout, ran.stderr });
            }
        }
        // The two runtimes say the same thing.
        if (!std.mem.eql(u8, interp.stderr, native.stderr)) {
            wrong += 1;
            std.debug.print("{s}: mo run and the binary differ\n{s}\n{s}\n", .{ file, interp.stderr, native.stderr });
        }
    }
    try std.testing.expectEqual(@as(u32, 0), wrong);
}
