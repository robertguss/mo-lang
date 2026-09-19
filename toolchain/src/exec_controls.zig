//! Step 41's controls: `Exec`, a child process narrowed to fixed commands (design:
//! mo-capabilities-for-the-harness, section 3). Each program runs under `mo run` and as a
//! `mo build` binary against small helper programs the test writes into a temporary folder.
//! The helpers are shell scripts; Mo never runs a shell of its own, it runs a script as it runs
//! any program, by its absolute path. Every child of the test runs under
//! bench/step36/guard.py with a timeout, so a run that never ends fails the test rather than
//! hanging it.
const std = @import("std");
const Io = std.Io;
const corpus = @import("corpus.zig");

const Ran = struct { stdout: []const u8, stderr: []const u8, code: u8 };

const Setup = struct {
    arena: std.mem.Allocator,
    io: Io,
    mo_exe: []const u8,
    guard: []const u8,
    /// The temporary folder, relative to the test's working directory, and absolute.
    cwd: []const u8,
    abs: []const u8,

    /// A shell script run in the temporary folder, which makes the helpers and the tree.
    fn sh(s: Setup, script: []const u8) !void {
        const made = try std.process.run(s.arena, s.io, .{ .argv = &.{ "/bin/sh", "-ec", script }, .cwd = .{ .path = s.cwd } });
        if (!(made.term == .exited and made.term.exited == 0)) std.debug.print("tree: {s}\n", .{made.stderr});
        try std.testing.expect(made.term == .exited and made.term.exited == 0);
    }

    /// `argv` under guard.py, `seconds` at most, in the temporary folder.
    fn guarded(s: Setup, seconds: []const u8, argv: []const []const u8) !Ran {
        var all: std.ArrayList([]const u8) = .empty;
        try all.appendSlice(s.arena, &.{ "python3", s.guard, seconds, "--" });
        try all.appendSlice(s.arena, argv);
        const ran = try std.process.run(s.arena, s.io, .{ .argv = all.items, .cwd = .{ .path = s.cwd }, .stdout_limit = .limited(64 << 20), .stderr_limit = .limited(64 << 20) });
        return .{ .stdout = ran.stdout, .stderr = ran.stderr, .code = if (ran.term == .exited) ran.term.exited else 255 };
    }

    fn built(s: Setup, file: []const u8, name: []const u8, tests: bool) ![]const u8 {
        const b = if (tests)
            try s.guarded("300", &.{ s.mo_exe, "build", "--tests", file, "-o", name })
        else
            try s.guarded("300", &.{ s.mo_exe, "build", file, "-o", name });
        if (b.code != 0) std.debug.print("mo build {s}: exit {d}\n{s}{s}", .{ file, b.code, b.stdout, b.stderr });
        try std.testing.expectEqual(@as(u8, 0), b.code);
        return std.fmt.allocPrint(s.arena, "./zig-out/mo-build/{s}/{s}", .{ name, name });
    }

    fn read(s: Setup, path: []const u8) ![]const u8 {
        const full = try std.fs.path.join(s.arena, &.{ s.cwd, path });
        return Io.Dir.cwd().readFileAlloc(s.io, full, s.arena, .limited(1 << 20));
    }

    fn absent(s: Setup, path: []const u8) bool {
        const full = std.fs.path.join(s.arena, &.{ s.cwd, path }) catch return false;
        _ = Io.Dir.cwd().statFile(s.io, full, .{ .follow_symlinks = false }) catch return true;
        return false;
    }

    /// Whether every process id in the file named is gone (or a zombie no one has reaped yet),
    /// asked of `ps`, within two seconds.
    fn gone(s: Setup, pid_file: []const u8) !bool {
        const pids = std.mem.trim(u8, try s.read(pid_file), " \n");
        try std.testing.expect(pids.len > 0);
        var tries: usize = 0;
        while (tries < 40) : (tries += 1) {
            var all_gone = true;
            var it = std.mem.tokenizeScalar(u8, pids, ' ');
            while (it.next()) |pid| {
                const ps = try std.process.run(s.arena, s.io, .{ .argv = &.{ "/bin/ps", "-o", "stat=", "-p", pid } });
                const stat = std.mem.trim(u8, ps.stdout, " \n");
                if (stat.len > 0 and stat[0] != 'Z') all_gone = false;
            }
            if (all_gone) return true;
            try s.io.sleep(.fromMilliseconds(50), .awake);
        }
        return false;
    }
};

fn setup(arena: std.mem.Allocator, io: Io, tmp: *std.testing.TmpDir) !Setup {
    const gpa = std.testing.allocator;
    const from_environ = std.testing.environ.getAlloc(gpa, "MO_EXE") catch null;
    defer if (from_environ) |e| gpa.free(e);
    const mo_exe = try corpus.moExe(gpa, io, from_environ);
    defer gpa.free(mo_exe);
    const cwd = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    return .{
        .arena = arena,
        .io = io,
        .mo_exe = try arena.dupe(u8, mo_exe),
        .guard = try Io.Dir.cwd().realPathFileAlloc(io, "bench/step36/guard.py", arena),
        .cwd = cwd,
        .abs = try Io.Dir.cwd().realPathFileAlloc(io, cwd, arena),
    };
}

/// The helper programs, and a tree for the working folder: `work`, a link to it the operator
/// names (`linked_work`), and a link inside it (`work/dirlink`).
const helpers =
    \\cat > exit.sh <<'EOF'
    \\#!/bin/sh
    \\exit "$1"
    \\EOF
    \\cat > sig.sh <<'EOF'
    \\#!/bin/sh
    \\kill -9 $$
    \\EOF
    \\cat > stubborn.sh <<'EOF'
    \\#!/bin/sh
    \\trap '' TERM
    \\sleep 30 &
    \\echo "$$ $!" > "$1"
    \\sleep 30
    \\EOF
    \\cat > leaver.sh <<'EOF'
    \\#!/bin/sh
    \\sleep 30 &
    \\echo "$!" > "$1"
    \\exit 0
    \\EOF
    \\cat > big.sh <<'EOF'
    \\#!/bin/sh
    \\if [ "$1" = err ]; then head -c 1048576 /dev/zero >&2; else head -c 1048576 /dev/zero; fi
    \\EOF
    \\cat > args.sh <<'EOF'
    \\#!/bin/sh
    \\printf '%s\n' "$#"
    \\for a in "$@"; do printf '[%s]' "$a"; done
    \\EOF
    \\chmod 755 exit.sh sig.sh stubborn.sh leaver.sh big.sh args.sh
    \\mkdir -p work
    \\ln -s . work/dirlink
    \\ln -s work linked_work
;

/// Shared by the programs: what a run answered, one line each.
const shows =
    \\fn exited(e: Exit) : String
    \\  case e
    \\    Exited(code): "exited #{code}"
    \\    Signalled(signal): "signalled #{signal}"
    \\  end
    \\end
    \\
    \\fn failure(e: ExecError) : String
    \\  case e
    \\    Missing: "missing"
    \\    Refused: "refused"
    \\    Timeout: "timeout"
    \\    Failed(_): "failed"
    \\  end
    \\end
    \\
    \\fn exit_of(r: Result(Done, ExecError)) : String
    \\  case r
    \\    Ok(done): exited(done.exit)
    \\    Error(e): failure(e)
    \\  end
    \\end
    \\
    \\fn text(bytes: List(UInt8)) : String
    \\  String.from_bytes(bytes) or "<not text>"
    \\end
    \\
    \\fn out_of(r: Result(Done, ExecError)) : String
    \\  case r
    \\    Ok(done): text(done.stdout)
    \\    Error(e): failure(e)
    \\  end
    \\end
    \\
    \\fn sizes(r: Result(Done, ExecError)) : String
    \\  case r
    \\    Ok(done): "#{done.stdout.size} #{done.stderr.size} #{done.truncated} #{exited(done.exit)}"
    \\    Error(e): failure(e)
    \\  end
    \\end
    \\
    \\fn yes(b: Bool) : String
    \\  "#{b}"
    \\end
    \\
    \\fn took(r: Result(Done, ExecError)) : String
    \\  case r
    \\    Ok(done): yes(done.took > 0.ms and done.took < 10.seconds)
    \\    Error(e): failure(e)
    \\  end
    \\end
    \\
    \\fn show(out: Out, label: String, what: String)
    \\  out.write_line("#{label}: #{what}")
    \\end
    \\
;

test "corpus: step 41, Exec runs a fixed command: exit codes, a signal, a deadline kept by killing the group, bounded output, holes, the environment, the folder, stdin, and descriptors, under mo run and in a binary" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const s = try setup(arena, io, &tmp);
    try s.sh(helpers);
    try tmp.dir.writeFile(io, .{ .sub_path = "controls.mo", .data = "module Controls\nexpose main\n\n" ++ shows ++
        \\fn main(platform: Platform)
        \\  dir = platform.args.first or "."
        \\  out = platform.stdout
        \\  exec = platform.exec
        \\  code = exec.program("#{dir}/exit.sh").command([Hole])
        \\  show(out, "exit 0", exit_of(code.run(["0"], within: 10.seconds)))
        \\  show(out, "exit 1", exit_of(code.run(["1"], within: 10.seconds)))
        \\  show(out, "exit 255", exit_of(code.run(["255"], within: 10.seconds)))
        \\  show(out, "signal", exit_of(exec.program("#{dir}/sig.sh").command([]).run([], within: 10.seconds)))
        \\  stubborn = exec.program("#{dir}/stubborn.sh").command([Hole])
        \\  show(out, "stubborn", exit_of(stubborn.run(["#{dir}/stubborn.pids"], within: 1.seconds)))
        \\  leaver = exec.program("#{dir}/leaver.sh").command([Hole])
        \\  show(out, "leaver", exit_of(leaver.run(["#{dir}/leaver.pids"], within: 10.seconds)))
        \\  big = exec.program("#{dir}/big.sh").command([Hole])
        \\  show(out, "big stdout, bound 1000", sizes(big.output(1000).run(["out"], within: 10.seconds)))
        \\  show(out, "big stderr, bound 1000", sizes(big.output(1000).run(["err"], within: 10.seconds)))
        \\  show(out, "big stdout, default bound", sizes(big.run(["out"], within: 10.seconds)))
        \\  show(out, "big stdout, bound 2 MiB", sizes(big.output(2_097_152).run(["out"], within: 10.seconds)))
        \\  args = exec.program("#{dir}/args.sh").command([Fixed(text: "-x"), Hole, Fixed(text: "end")])
        \\  odd = "a b  'q' \"d\" $(touch #{dir}/pwned) `touch #{dir}/pwned` ; x\nline two"
        \\  show(out, "odd hole", yes(out_of(args.run([odd], within: 10.seconds)) == "3\n[-x][#{odd}][end]"))
        \\  show(out, "dash hole", out_of(args.run(["--help"], within: 10.seconds)))
        \\  show(out, "empty hole", out_of(args.run([""], within: 10.seconds)))
        \\  show(out, "NUL hole", exit_of(args.run(["a\u{0}b"], within: 10.seconds)))
        \\  show(out, "no value", exit_of(args.run([], within: 10.seconds)))
        \\  show(out, "two values", exit_of(args.run(["a", "b"], within: 10.seconds)))
        \\  show(out, "missing", exit_of(exec.program("#{dir}/nothing").command([]).run([], within: 10.seconds)))
        \\  show(out, "a folder as the program", exit_of(exec.program("#{dir}/work").command([]).run([], within: 10.seconds)))
        \\  env = exec.program("/usr/bin/env").command([])
        \\  show(out, "env by default", "[#{out_of(env.run([], within: 10.seconds))}]")
        \\  show(out, "env given", out_of(env.env(Map.new().set("A", "1").set("B", "two words")).run([], within: 10.seconds)))
        \\  pwd = exec.program("/bin/pwd").command([])
        \\  show(out, "in work", yes(out_of(pwd.in_folder(platform.fs.scoped("work")).run([], within: 10.seconds)) == "#{dir}/work\n"))
        \\  show(out, "in the operator's link", yes(out_of(pwd.in_folder(platform.fs.scoped("linked_work")).run([], within: 10.seconds)) == "#{dir}/work\n"))
        \\  show(out, "in a link inside", out_of(pwd.in_folder(platform.fs.scoped("work").scoped("dirlink")).run([], within: 10.seconds)))
        \\  show(out, "in a folder not there", out_of(pwd.in_folder(platform.fs.scoped("nothing")).run([], within: 10.seconds)))
        \\  show(out, "in a scope that climbed out", out_of(pwd.in_folder(platform.fs.scoped("work").scoped("..")).run([], within: 10.seconds)))
        \\  first = out_of(pwd.run([], within: 10.seconds)).trim
        \\  show(out, "default folder is new", yes(first != dir and first != "#{dir}/work"))
        \\  show(out, "default folder empty", "[#{out_of(exec.program("/bin/ls").command([Fixed(text: "-A")]).run([], within: 10.seconds))}]")
        \\  show(out, "default folder gone after", exit_of(exec.program("/bin/test").command([Fixed(text: "-e"), Hole]).run([first], within: 10.seconds)))
        \\  cat = exec.program("/bin/cat").command([])
        \\  show(out, "stdin", out_of(cat.run([], stdin: "hello\nworld", within: 10.seconds)))
        \\  show(out, "no stdin", "[#{out_of(cat.run([], within: 10.seconds))}]")
        \\  show(out, "1 MiB through cat", sizes(cat.output(2_097_152).run([], stdin: "x".repeat(1_048_576), within: 10.seconds)))
        \\  sh = exec.program("/bin/sh")
        \\  show(out, "descriptors", out_of(sh.command([Fixed(text: "-c"), Fixed(text: "for f in /dev/fd/*; do [ -e \"$f\" ] && printf '%s,' \"${f\#/dev/fd/}\"; done; exit 0")]).run([], within: 10.seconds)))
        \\  show(out, "terminal", out_of(sh.command([Fixed(text: "-c"), Fixed(text: "if (exec 3</dev/tty) 2>/dev/null; then echo tty; else echo none; fi")]).run([], within: 10.seconds)))
        \\  show(out, "group", out_of(sh.command([Fixed(text: "-c"), Fixed(text: "g=$(ps -o pgid= -p $$); [ $g -eq $$ ] && echo leads || echo joined")]).run([], within: 10.seconds)))
        \\  show(out, "took", took(code.run(["0"], within: 10.seconds)))
        \\end
        \\
    });
    const want =
        \\exit 0: exited 0
        \\exit 1: exited 1
        \\exit 255: exited 255
        \\signal: signalled 9
        \\stubborn: timeout
        \\leaver: exited 0
        \\big stdout, bound 1000: 1000 0 true exited 0
        \\big stderr, bound 1000: 0 1000 true exited 0
        \\big stdout, default bound: 65536 0 true exited 0
        \\big stdout, bound 2 MiB: 1048576 0 false exited 0
        \\odd hole: true
        \\dash hole: 3
        \\[-x][--help][end]
        \\empty hole: 3
        \\[-x][][end]
        \\NUL hole: refused
        \\no value: refused
        \\two values: refused
        \\missing: missing
        \\a folder as the program: failed
        \\env by default: []
        \\env given: A=1
        \\B=two words
        \\
        \\in work: true
        \\in the operator's link: true
        \\in a link inside: failed
        \\in a folder not there: failed
        \\in a scope that climbed out: failed
        \\default folder is new: true
        \\default folder empty: []
        \\default folder gone after: exited 1
        \\stdin: hello
        \\world
        \\no stdin: []
        \\1 MiB through cat: 1048576 0 false exited 0
        \\descriptors: 0,1,2,
        \\terminal: none
        \\
        \\group: leads
        \\
        \\took: true
        \\
    ;
    const bin = try s.built("controls.mo", "controls", false);
    const runs = [_]struct { []const u8, []const []const u8 }{
        .{ "mo run", &.{ s.mo_exe, "run", "controls.mo", "--", s.abs } },
        .{ "binary", &.{ bin, s.abs } },
    };
    for (runs) |r| {
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        const ran = try s.guarded("120", r[1]);
        const took_ms = @divFloor(t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds(), std.time.ns_per_ms);
        std.debug.print("---- {s}, exit {d}, {d} ms\n{s}", .{ r[0], ran.code, took_ms, ran.stdout });
        if (ran.stderr.len > 0) std.debug.print("stderr: {s}\n", .{ran.stderr});
        try std.testing.expectEqualStrings(want, ran.stdout);
        try std.testing.expectEqual(@as(u8, 0), ran.code);
        // The stubborn child and its grandchild were killed at the deadline, and the leaver's
        // grandchild when the leaver exited: nothing outlives a run.
        try std.testing.expect(try s.gone("stubborn.pids"));
        try std.testing.expect(try s.gone("leaver.pids"));
        // No hole was read by a shell.
        try std.testing.expect(s.absent("pwned"));
        // The deadline of 1 second was kept by killing, not by waiting out the 30-second sleep.
        try std.testing.expect(took_ms < 20_000);
    }
}

test "corpus: step 41, a relative program path is refused when the Program is made, under mo run and in a binary" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const s = try setup(arena, io, &tmp);
    try tmp.dir.writeFile(io, .{ .sub_path = "relative.mo", .data =
        \\module Relative
        \\expose main
        \\
        \\fn main(platform: Platform)
        \\  platform.stdout.write_line("before")
        \\  platform.stdout.flush
        \\  sh = platform.exec.program("bin/sh")
        \\  platform.stdout.write_line("after")
        \\  case sh.command([]).run([], within: 1.seconds)
        \\    Ok(_): platform.stdout.write_line("ran")
        \\    Error(_): platform.stdout.write_line("did not run")
        \\  end
        \\end
        \\
    });
    const bin = try s.built("relative.mo", "relative", false);
    const runs = [_]struct { []const u8, []const []const u8 }{
        .{ "mo run", &.{ s.mo_exe, "run", "relative.mo" } },
        .{ "binary", &.{bin} },
    };
    for (runs) |r| {
        const ran = try s.guarded("60", r[1]);
        std.debug.print("---- {s}, exit {d}\n{s}stderr: {s}\n", .{ r[0], ran.code, ran.stdout, ran.stderr });
        try std.testing.expectEqualStrings("before\n", ran.stdout);
        try std.testing.expectEqual(@as(u8, 70), ran.code);
        try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "\"bin/sh\" is not an absolute path") != null);
    }
}

/// A module whose functions hold only a `Command`, tested with `Exec.fixture`.
const fixture_module =
    \\module Remover
    \\expose remove, Runner
    \\
    \\fn remove(rm: Command, name: String) : Result(UInt8, ExecError)
    \\  case rm.run([name], within: 10.seconds)
    \\    Ok(done):
    \\      case done.exit
    \\        Exited(code): Ok(code)
    \\        Signalled(signal): Ok(128 + signal)
    \\      end
    \\    Error(e): Error(e)
    \\  end
    \\end
    \\
    \\fn echoed(cmd: Command, stdin: String) : String
    \\  case cmd.run([], stdin: stdin, within: 10.seconds)
    \\    Ok(done): String.from_bytes(done.stdout) or ""
    \\    Error(_): "error"
    \\  end
    \\end
    \\
    \\fn said(argv: List(String), stdin: String) : Done
    \\  Done(exit: Exited(code: argv.size.to_u8), stdout: "#{String.join(argv, " ")}|#{stdin}".bytes, stderr: [], truncated: false, took: 3.ms)
    \\end
    \\
    \\process Runner(rm: Command)
    \\  state
    \\    runs: UInt32
    \\    timeouts: UInt32
    \\    failures: UInt32
    \\  end
    \\  message Run(name: String)
    \\  message Runs : UInt32
    \\  message Timeouts : UInt32
    \\  message Failures : UInt32
    \\  fn update(state, message)
    \\    case message
    \\      Run(name):
    \\        state.runs += 1
    \\        result = rm.run([name], within: 50.ms)
    \\        if result is Error(Timeout)
    \\          state.timeouts += 1
    \\        end
    \\        if result is Error(Failed(_))
    \\          state.failures += 1
    \\        end
    \\      Runs: state.runs
    \\      Timeouts: state.timeouts
    \\      Failures: state.failures
    \\    end
    \\  end
    \\end
    \\
    \\supervisor Runners(rm: Command)
    \\  child Runner(rm), restart: :always
    \\end
    \\
    \\test "a fixture answers every run, with the program's path first and the holes filled"
    \\  rm = Exec.fixture(fn(argv, stdin) said(argv, stdin) end).program("/usr/bin/docker").command([Fixed(text: "rm"), Fixed(text: "-f"), Hole])
    \\  assert remove(rm, "box") == Ok(4)
    \\  case rm.run(["box"], within: 1.minute)
    \\    Ok(done):
    \\      assert String.from_bytes(done.stdout) == Some("/usr/bin/docker rm -f box|")
    \\      assert done.took == 3.ms
    \\      assert !done.truncated
    \\    Error(_):
    \\      assert false
    \\  end
    \\end
    \\
    \\test "a fixture hands the function what stdin was given"
    \\  cat = Exec.fixture(fn(argv, stdin) said(argv, stdin) end).program("/bin/cat").command([])
    \\  assert echoed(cat, "hello") == "/bin/cat|hello"
    \\end
    \\
    \\test "a fixture refuses what the real Exec refuses"
    \\  rm = Exec.fixture(fn(argv, stdin) said(argv, stdin) end).program("/usr/bin/docker").command([Fixed(text: "rm"), Hole])
    \\  assert remove(rm, "a\u{0}b") == Error(Refused)
    \\  assert rm.run([], within: 1.minute) == Error(Refused)
    \\  assert rm.run(["a", "b"], within: 1.minute) == Error(Refused)
    \\end
    \\
    \\test "every run is counted, whatever the child did"
    \\  runner = Runner.start(Exec.fixture(fn(argv, stdin) said(argv, stdin) end).program("/bin/true").command([Hole]))
    \\  runner.send(Run(name: "a"))
    \\  runner.send(Run(name: "b"))
    \\  assert runner.ask(Runs, within: 1.minute) is Ok(2)
    \\end
    \\
    \\test "no run ever times out"
    \\  runner = Runner.start(Exec.fixture(fn(argv, stdin) said(argv, stdin) end).program("/bin/true").command([Hole]))
    \\  runner.send(Run(name: "a"))
    \\  runner.send(Run(name: "b"))
    \\  assert runner.ask(Timeouts, within: 1.minute) is Ok(0)
    \\end
    \\
    \\test "no run ever fails"
    \\  runner = Runner.start(Exec.fixture(fn(argv, stdin) said(argv, stdin) end).program("/bin/true").command([Hole]))
    \\  runner.send(Run(name: "a"))
    \\  runner.send(Run(name: "b"))
    \\  assert runner.ask(Failures, within: 1.minute) is Ok(0)
    \\end
    \\
;

test "corpus: step 41, Exec.fixture answers every run under mo test, in a mo build --tests binary, and under mo test --sim with faults" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const s = try setup(arena, io, &tmp);
    try tmp.dir.writeFile(io, .{ .sub_path = "remover.mo", .data = fixture_module });
    const tested = try s.guarded("120", &.{ s.mo_exe, "test", "remover.mo" });
    std.debug.print("---- mo test, exit {d}\n{s}{s}", .{ tested.code, tested.stdout, tested.stderr });
    try std.testing.expectEqual(@as(u8, 0), tested.code);
    try std.testing.expect(std.mem.indexOf(u8, tested.stdout, "6 passed, 0 failed, 0 skipped") != null);
    const bin = try s.built("remover.mo", "remover-tests", true);
    const native = try s.guarded("120", &.{bin});
    std.debug.print("---- mo build --tests, exit {d}\n{s}{s}", .{ native.code, native.stdout, native.stderr });
    try std.testing.expectEqual(@as(u8, 0), native.code);
    try std.testing.expect(std.mem.indexOf(u8, native.stdout, "6 passed, 0 failed, 0 skipped") != null);
    // Under faults a run is scheduled as any wait is and fails with Timeout or Failed: the
    // counting test holds, and each of the other two passes only without faults.
    const sim = try s.guarded("300", &.{ s.mo_exe, "test", "--sim", "40", "--seed", "1", "--faults", "50", "remover.mo" });
    std.debug.print("---- mo test --sim, exit {d}\n{s}{s}", .{ sim.code, sim.stdout, sim.stderr });
    try std.testing.expectEqual(@as(u8, 0), sim.code);
    try std.testing.expect(std.mem.indexOf(u8, sim.stdout, "6 passed, 0 failed, 0 skipped; 3 tests under 40 seeds with 50% faults: 1 held under faults, 2 passed only without faults") != null);
}

/// With one scheduler (MO_CORES=1), main's code runs on the scheduler's thread, and main's send is
/// delivered before its next statement: the update runs until it ends or waits. A run that held the
/// scheduler would finish before main's next statement; one that waits holding none lets main go on
/// while the child still runs. The child writes a marker when it ends, so main can tell which.
const scheduler_program =
    \\module Sched
    \\expose main
    \\
    \\process Sleeper(nap: Command)
    \\  state
    \\    done: Bool
    \\  end
    \\  message Start
    \\  message Done : Bool
    \\  fn update(state, message)
    \\    case message
    \\      Start:
    \\        state.done = nap.run([], within: 10.seconds) is Ok(_)
    \\      Done: state.done
    \\    end
    \\  end
    \\end
    \\
    \\process Counter()
    \\  state
    \\    n: UInt32
    \\  end
    \\  message Tick : UInt32
    \\  fn update(state, message)
    \\    case message
    \\      Tick:
    \\        state.n += 1
    \\        state.n
    \\    end
    \\  end
    \\end
    \\
    \\supervisor Both(nap: Command)
    \\  child Sleeper(nap), restart: :always
    \\  child Counter(), restart: :always
    \\end
    \\
    \\fn main(platform: Platform)
    \\  out = platform.stdout
    \\  here = platform.fs.scoped(platform.args.first or ".")
    \\  slow = platform.exec.program("/bin/sh").command([Fixed(text: "-c"), Fixed(text: "sleep 1; echo done > marker")])
    \\  sleeper = Sleeper.start(slow.in_folder(here))
    \\  counter = Counter.start()
    \\  sleeper.send(Start)
    \\  out.write_line("main went on while the child ran: #{here.size("marker", within: 1.seconds) is Error(_)}")
    \\  out.write_line("another process answered meanwhile: #{counter.ask(Tick, within: 500.ms) is Ok(1)}")
    \\  out.write_line("the run then answered: #{sleeper.ask(Done, within: 5.seconds) is Ok(true)}")
    \\  out.write_line("and the child had finished: #{here.size("marker", within: 1.seconds) is Ok(_)}")
    \\end
    \\
;

test "corpus: step 41, a run waits holding no scheduler: with one scheduler main goes on while the child runs, under mo run and in a binary" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const s = try setup(arena, io, &tmp);
    try tmp.dir.writeFile(io, .{ .sub_path = "sched.mo", .data = scheduler_program });
    const want =
        \\main went on while the child ran: true
        \\another process answered meanwhile: true
        \\the run then answered: true
        \\and the child had finished: true
        \\
    ;
    const bin = try s.built("sched.mo", "sched", false);
    const runs = [_]struct { []const u8, []const []const u8 }{
        .{ "mo run", &.{ "/usr/bin/env", "MO_CORES=1", s.mo_exe, "run", "sched.mo", "--", s.abs } },
        .{ "binary", &.{ "/usr/bin/env", "MO_CORES=1", bin, s.abs } },
    };
    for (runs) |r| {
        try s.sh("rm -f marker");
        const ran = try s.guarded("60", r[1]);
        std.debug.print("---- {s}, exit {d}\n{s}", .{ r[0], ran.code, ran.stdout });
        if (ran.stderr.len > 0) std.debug.print("stderr: {s}\n", .{ran.stderr});
        try std.testing.expectEqualStrings(want, ran.stdout);
        try std.testing.expectEqual(@as(u8, 0), ran.code);
    }
}
