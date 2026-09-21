//! Step 40's controls: a scope that holds against links, FIFOs and devices, `Fs.kind_of`, and
//! `Fs.replace`, each run under `mo run` and as a `mo build` binary on a hostile tree the test
//! makes in a temporary folder (Mo cannot make a link). The cases are
//! harness/executor/test_workspace.py's hostile entries (a file link, a folder link as a middle
//! component, a hard link, a FIFO, a setuid file), so the two stay comparable. Every child runs
//! under bench/step36/guard.py with a timeout, so a read that blocks on a FIFO fails the test
//! rather than hanging it.
const std = @import("std");
const Io = std.Io;
const corpus = @import("corpus.zig");

const Ran = struct { stdout: []const u8, code: u8 };

const Setup = struct {
    arena: std.mem.Allocator,
    io: Io,
    mo_exe: []const u8,
    guard: []const u8,
    /// The temporary folder, relative to the test's working directory.
    cwd: []const u8,

    /// A shell script run in the temporary folder, which builds the tree.
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
        const ran = try std.process.run(s.arena, s.io, .{ .argv = all.items, .cwd = .{ .path = s.cwd } });
        if (ran.stderr.len > 0) std.debug.print("{s}: {s}\n", .{ argv[argv.len - 1], ran.stderr });
        return .{ .stdout = ran.stdout, .code = if (ran.term == .exited) ran.term.exited else 255 };
    }

    /// `mo run file`, then `mo build file -o name` and the binary: both outputs.
    fn both(s: Setup, file: []const u8, name: []const u8) ![2]Ran {
        const interp = try s.guarded("60", &.{ s.mo_exe, "run", file });
        const built = try s.guarded("300", &.{ s.mo_exe, "build", file, "-o", name });
        try std.testing.expectEqual(@as(u8, 0), built.code);
        const binary = try std.fmt.allocPrint(s.arena, "./zig-out/mo-build/{s}/{s}", .{ name, name });
        return .{ interp, try s.guarded("60", &.{binary}) };
    }

    /// A file's tests built by `mo build --tests` and run as a binary.
    fn nativeTests(s: Setup, file: []const u8, name: []const u8) !Ran {
        const built = try s.guarded("300", &.{ s.mo_exe, "build", "--tests", file, "-o", name });
        try std.testing.expectEqual(@as(u8, 0), built.code);
        return s.guarded("120", &.{try std.fmt.allocPrint(s.arena, "./zig-out/mo-build/{s}/{s}", .{ name, name })});
    }

    fn read(s: Setup, path: []const u8) ![]const u8 {
        const full = try std.fs.path.join(s.arena, &.{ s.cwd, path });
        return Io.Dir.cwd().readFileAlloc(s.io, full, s.arena, .limited(64 << 20));
    }

    fn mode(s: Setup, path: []const u8) !u32 {
        const full = try std.fs.path.join(s.arena, &.{ s.cwd, path });
        const st = try Io.Dir.cwd().statFile(s.io, full, .{ .follow_symlinks = false });
        return @intCast(@intFromEnum(st.permissions) & 0o7777);
    }

    fn linkThere(s: Setup, path: []const u8) !bool {
        const full = try std.fs.path.join(s.arena, &.{ s.cwd, path });
        const st = Io.Dir.cwd().statFile(s.io, full, .{ .follow_symlinks = false }) catch return false;
        return st.kind == .sym_link;
    }

    fn absent(s: Setup, path: []const u8) !bool {
        const full = try std.fs.path.join(s.arena, &.{ s.cwd, path });
        _ = Io.Dir.cwd().statFile(s.io, full, .{ .follow_symlinks = false }) catch return true;
        return false;
    }
};

fn setup(arena: std.mem.Allocator, io: Io, tmp: *std.testing.TmpDir) !Setup {
    const gpa = std.testing.allocator;
    const mo_exe = try corpus.integrationMo(gpa, io);
    defer gpa.free(mo_exe);
    return .{
        .arena = arena,
        .io = io,
        .mo_exe = try arena.dupe(u8, mo_exe),
        .guard = try Io.Dir.cwd().realPathFileAlloc(io, "bench/step36/guard.py", arena),
        .cwd = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}", .{tmp.sub_path}),
    };
}

/// Shared by the programs below: what a call answered, one line each.
const shows =
    \\fn said(r: Result(T, FsError)) : String
    \\  case r
    \\    Ok(_): "ok"
    \\    Error(Missing(path)): "missing #{path}"
    \\    Error(Timeout): "timeout"
    \\    Error(NotText): "not text"
    \\  end
    \\end
    \\
    \\fn text(r: Result(String, FsError)) : String
    \\  case r
    \\    Ok(t): "ok #{t}"
    \\    Error(Missing(path)): "missing #{path}"
    \\    Error(Timeout): "timeout"
    \\    Error(NotText): "not text"
    \\  end
    \\end
    \\
    \\fn names(r: Result(List(String), FsError)) : String
    \\  case r
    \\    Ok(all): String.join(all, ", ")
    \\    Error(_): "unlisted"
    \\  end
    \\end
    \\
    \\fn kind(e: Entry) : String
    \\  if e.kind == File
    \\    "#{e.name} file"
    \\  else
    \\    if e.kind == Folder
    \\      "#{e.name} folder"
    \\    else
    \\      "#{e.name} link"
    \\    end
    \\  end
    \\end
    \\
    \\fn show(out: Out, label: String, what: String)
    \\  out.write_line("#{label}: #{what}")
    \\end
    \\
;

const hostile_tree =
    \\mkdir -p work/sub dirout
    \\printf secret > outside.txt
    \\printf outer > dirout/x.txt
    \\printf safe > work/a.txt
    \\printf deep > work/sub/b.txt
    \\ln -s ../outside.txt work/out_link
    \\ln -s a.txt work/in_link
    \\ln -s . work/dirlink
    \\ln -s ../dirout work/dirout_link
    \\ln work/a.txt work/hard
    \\mkfifo work/fifo
    \\ln -s work linked_work
;

test "corpus: step 40, a scope holds against links, a FIFO and a device, under mo run and in a binary" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const s = try setup(arena, io, &tmp);
    try s.sh(hostile_tree);
    try tmp.dir.writeFile(io, .{ .sub_path = "hostile.mo", .data = "module Hostile\nexpose main\n\n" ++ shows ++
        \\fn kinds(r: Result(List(Entry), FsError)) : String
        \\  case r
        \\    Ok(entries): String.join(entries.map(fn(e) kind(e) end), ", ")
        \\    Error(_): "unlisted"
        \\  end
        \\end
        \\
        \\fn main(platform: Platform)
        \\  work = platform.fs.scoped("work")
        \\  out = platform.stdout
        \\  show(out, "read a.txt", text(work.read("a.txt", within: 1.minute)))
        \\  show(out, "read hard", text(work.read("hard", within: 1.minute)))
        \\  show(out, "read out_link", text(work.read("out_link", within: 1.minute)))
        \\  show(out, "read in_link", text(work.read("in_link", within: 1.minute)))
        \\  show(out, "read dirlink/a.txt", text(work.read("dirlink/a.txt", within: 1.minute)))
        \\  show(out, "read dirout_link/x.txt", text(work.read("dirout_link/x.txt", within: 1.minute)))
        \\  show(out, "read_lines in_link", said(work.read_lines("in_link", within: 1.minute)))
        \\  show(out, "read_bytes in_link", said(work.read_bytes("in_link", within: 1.minute)))
        \\  show(out, "size in_link", said(work.size("in_link", within: 1.minute)))
        \\  show(out, "fold_lines in_link", said(work.fold_lines("in_link", 0, within: 1.minute, fn(n, line) n + line.byte_size end)))
        \\  show(out, "scoped dirout_link", text(work.scoped("dirout_link").read("x.txt", within: 1.minute)))
        \\  show(out, "scoped dirlink", text(work.scoped("dirlink").read("a.txt", within: 1.minute)))
        \\  show(out, "scoped dirlink, listed", names(work.scoped("dirlink").list(within: 1.minute)))
        \\  show(out, "operator's link", text(platform.fs.scoped("linked_work").read("a.txt", within: 1.minute)))
        \\  show(out, "operator's link, then in_link", text(platform.fs.scoped("linked_work").read("in_link", within: 1.minute)))
        \\  show(out, "device", text(platform.fs.scoped("/dev").read("null", within: 1.minute)))
        \\  show(out, "list", names(work.list(within: 1.minute)))
        \\  show(out, "list_kinds", kinds(work.list_kinds(within: 1.minute)))
        \\  show(out, "write out_link", said(work.write("out_link", "x", within: 1.minute)))
        \\  show(out, "write in_link", said(work.write("in_link", "x", within: 1.minute)))
        \\  show(out, "append in_link", said(work.append("in_link", "x", within: 1.minute)))
        \\  show(out, "write dirlink/new.txt", said(work.write("dirlink/new.txt", "x", within: 1.minute)))
        \\  show(out, "mkdir dirlink", said(work.mkdir("dirlink", within: 1.minute)))
        \\  show(out, "mkdir dirlink/made", said(work.mkdir("dirlink/made", within: 1.minute)))
        \\  show(out, "remove in_link", said(work.remove("in_link", within: 1.minute)))
        \\  show(out, "rename in_link to moved", said(work.rename("in_link", "moved", within: 1.minute)))
        \\  show(out, "rename sub/b.txt to in_link", said(work.rename("sub/b.txt", "in_link", within: 1.minute)))
        \\  show(out, "rename sub/b.txt to dirlink/b.txt", said(work.rename("sub/b.txt", "dirlink/b.txt", within: 1.minute)))
        \\  show(out, "read a.txt after", text(work.read("a.txt", within: 1.minute)))
        \\  out.flush
        \\  show(out, "write fifo", said(work.write("fifo", "x", within: 1.minute)))
        \\  out.flush
        \\  show(out, "read fifo", text(work.read("fifo", within: 1.minute)))
        \\  show(out, "size fifo", said(work.size("fifo", within: 1.minute)))
        \\end
        \\
    });
    const want =
        \\read a.txt: ok safe
        \\read hard: ok safe
        \\read out_link: missing out_link
        \\read in_link: missing in_link
        \\read dirlink/a.txt: missing dirlink/a.txt
        \\read dirout_link/x.txt: missing dirout_link/x.txt
        \\read_lines in_link: missing in_link
        \\read_bytes in_link: missing in_link
        \\size in_link: missing in_link
        \\fold_lines in_link: missing in_link
        \\scoped dirout_link: missing x.txt
        \\scoped dirlink: missing a.txt
        \\scoped dirlink, listed: unlisted
        \\operator's link: ok safe
        \\operator's link, then in_link: missing in_link
        \\device: missing null
        \\list: a.txt, dirlink, dirout_link, fifo, hard, in_link, out_link, sub
        \\list_kinds: a.txt file, dirlink link, dirout_link link, fifo file, hard file, in_link link, out_link link, sub folder
        \\write out_link: missing out_link
        \\write in_link: missing in_link
        \\append in_link: missing in_link
        \\write dirlink/new.txt: missing dirlink/new.txt
        \\mkdir dirlink: missing dirlink
        \\mkdir dirlink/made: missing dirlink/made
        \\remove in_link: missing in_link
        \\rename in_link to moved: missing in_link
        \\rename sub/b.txt to in_link: missing in_link
        \\rename sub/b.txt to dirlink/b.txt: missing dirlink/b.txt
        \\read a.txt after: ok safe
        \\write fifo: missing fifo
        \\read fifo: missing fifo
        \\size fifo: missing fifo
        \\
    ;
    const ran = try s.both("hostile.mo", "hostile");
    for (ran, [_][]const u8{ "mo run", "binary" }) |r, which| {
        std.debug.print("---- {s}, exit {d}\n{s}", .{ which, r.code, r.stdout });
    }
    for (ran) |r| {
        try std.testing.expectEqualStrings(want, r.stdout);
        try std.testing.expectEqual(@as(u8, 0), r.code);
    }
    // Nothing outside the scope changed, and every link is where it was.
    try std.testing.expectEqualStrings("secret", try s.read("outside.txt"));
    try std.testing.expectEqualStrings("outer", try s.read("dirout/x.txt"));
    try std.testing.expectEqualStrings("safe", try s.read("work/a.txt"));
    try std.testing.expectEqualStrings("deep", try s.read("work/sub/b.txt"));
    for ([_][]const u8{ "work/in_link", "work/out_link", "work/dirlink", "work/dirout_link" }) |p| try std.testing.expect(try s.linkThere(p));
    for ([_][]const u8{ "work/new.txt", "work/made", "work/moved", "work/b.txt" }) |p| try std.testing.expect(try s.absent(p));
}

test "corpus: step 40, Fs.kind_of names a link, counts hard links, and sees setuid, under mo run and in a binary" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const s = try setup(arena, io, &tmp);
    try s.sh(hostile_tree ++ "\nprintf run > work/suid\nchmod 4755 work/suid\n");
    try tmp.dir.writeFile(io, .{ .sub_path = "kinds.mo", .data = "module Kinds\nexpose main\n\n" ++ shows ++
        \\fn entry(r: Result(Entry, FsError)) : String
        \\  case r
        \\    Ok(e): "#{kind(e)}, setuid #{e.setuid}"
        \\    Error(Missing(path)): "missing #{path}"
        \\    Error(_): "other"
        \\  end
        \\end
        \\
        \\fn links(r: Result(Entry, FsError)) : String
        \\  case r
        \\    Ok(e): "#{e.links}"
        \\    Error(_): "none"
        \\  end
        \\end
        \\
        \\fn main(platform: Platform)
        \\  work = platform.fs.scoped("work")
        \\  out = platform.stdout
        \\  show(out, "a.txt", entry(work.kind_of("a.txt", within: 1.minute)))
        \\  show(out, "a.txt links", links(work.kind_of("a.txt", within: 1.minute)))
        \\  show(out, "suid", entry(work.kind_of("suid", within: 1.minute)))
        \\  show(out, "suid links", links(work.kind_of("suid", within: 1.minute)))
        \\  show(out, "in_link", entry(work.kind_of("in_link", within: 1.minute)))
        \\  show(out, "out_link", entry(work.kind_of("out_link", within: 1.minute)))
        \\  show(out, "sub", entry(work.kind_of("sub", within: 1.minute)))
        \\  show(out, "sub/b.txt", entry(work.kind_of("sub/b.txt", within: 1.minute)))
        \\  show(out, "dirlink/a.txt", entry(work.kind_of("dirlink/a.txt", within: 1.minute)))
        \\  show(out, "../outside.txt", entry(work.kind_of("../outside.txt", within: 1.minute)))
        \\  show(out, "nothing", entry(work.kind_of("nothing", within: 1.minute)))
        \\  show(out, "fifo", entry(work.kind_of("fifo", within: 1.minute)))
        \\end
        \\
        \\test "a fixture's file and folder are what kind_of says, one link each and never setuid"
        \\  fs = Fs.fixture()
        \\  assert fs.write("logs/a.log", "one", within: 1.minute) is Ok(_)
        \\  assert fs.kind_of("logs/a.log", within: 1.minute) == Ok(Entry(name: "logs/a.log", kind: File, links: 1, setuid: false))
        \\  assert fs.kind_of("logs", within: 1.minute) == Ok(Entry(name: "logs", kind: Folder, links: 1, setuid: false))
        \\  assert fs.kind_of("b.log", within: 1.minute) == Error(Missing(path: "b.log"))
        \\  assert Fs.fixture(delay: 2.minute).kind_of("a", within: 1.minute) == Error(Timeout)
        \\end
        \\
    });
    const want =
        \\a.txt: a.txt file, setuid false
        \\a.txt links: 2
        \\suid: suid file, setuid true
        \\suid links: 1
        \\in_link: in_link link, setuid false
        \\out_link: out_link link, setuid false
        \\sub: sub folder, setuid false
        \\sub/b.txt: sub/b.txt file, setuid false
        \\dirlink/a.txt: missing dirlink/a.txt
        \\../outside.txt: missing ../outside.txt
        \\nothing: missing nothing
        \\fifo: fifo file, setuid false
        \\
    ;
    const ran = try s.both("kinds.mo", "kinds");
    for (ran, [_][]const u8{ "mo run", "binary" }) |r, which| {
        std.debug.print("---- {s}, exit {d}\n{s}", .{ which, r.code, r.stdout });
    }
    for (ran) |r| {
        try std.testing.expectEqualStrings(want, r.stdout);
        try std.testing.expectEqual(@as(u8, 0), r.code);
    }
    // The fixture's test, under mo test and in a built test binary.
    const tested = try s.guarded("120", &.{ s.mo_exe, "test", "kinds.mo" });
    std.debug.print("---- mo test, exit {d}\n{s}", .{ tested.code, tested.stdout });
    try std.testing.expectEqual(@as(u8, 0), tested.code);
    const native = try s.nativeTests("kinds.mo", "kinds-tests");
    std.debug.print("---- mo build --tests, exit {d}\n{s}", .{ native.code, native.stdout });
    try std.testing.expectEqual(@as(u8, 0), native.code);
}

test "corpus: step 40, Fs.replace swaps a file whole, private to its owner, and refuses a link, under mo run and in a binary" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const s = try setup(arena, io, &tmp);
    const tree = hostile_tree ++ "\nprintf old > work/t.txt\nchmod 644 work/t.txt\n";
    try s.sh(tree);
    try tmp.dir.writeFile(io, .{ .sub_path = "swap.mo", .data = "module Swap\nexpose main\n\n" ++ shows ++
        \\fn main(platform: Platform)
        \\  work = platform.fs.scoped("work")
        \\  out = platform.stdout
        \\  show(out, "replace t.txt", said(work.replace("t.txt", "new", within: 1.minute)))
        \\  show(out, "read t.txt", text(work.read("t.txt", within: 1.minute)))
        \\  show(out, "replace fresh.txt", said(work.replace("fresh.txt", "made", within: 1.minute)))
        \\  show(out, "replace sub/b.txt", said(work.replace("sub/b.txt", "deeper", within: 1.minute)))
        \\  show(out, "replace in_link", said(work.replace("in_link", "x", within: 1.minute)))
        \\  show(out, "replace out_link", said(work.replace("out_link", "x", within: 1.minute)))
        \\  show(out, "replace dirlink/t.txt", said(work.replace("dirlink/t.txt", "x", within: 1.minute)))
        \\  show(out, "replace nofolder/t.txt", said(work.replace("nofolder/t.txt", "x", within: 1.minute)))
        \\  show(out, "replace sub", said(work.replace("sub", "x", within: 1.minute)))
        \\  show(out, "replace fifo", said(work.replace("fifo", "x", within: 1.minute)))
        \\  show(out, "replace ../outside.txt", said(work.replace("../outside.txt", "x", within: 1.minute)))
        \\  long = "l".repeat(255)
        \\  show(out, "replace a 255-byte name", said(work.replace(long, "long", within: 1.minute)))
        \\  show(out, "read it", text(work.read(long, within: 1.minute)))
        \\  show(out, "remove it", said(work.remove(long, within: 1.minute)))
        \\  show(out, "list", names(work.list(within: 1.minute)))
        \\  show(out, "list sub", names(work.scoped("sub").list(within: 1.minute)))
        \\end
        \\
        \\test "on a fixture, replace is write"
        \\  fs = Fs.fixture()
        \\  assert fs.replace("a.log", "one", within: 1.minute) is Ok(_)
        \\  assert fs.replace("a.log", "two", within: 1.minute) is Ok(_)
        \\  assert fs.read("a.log", within: 1.minute) == Ok("two")
        \\  assert fs.list(within: 1.minute) == Ok(["a.log"])
        \\  assert Fs.fixture(delay: 2.minute).replace("a.log", "x", within: 1.minute) == Error(Timeout)
        \\end
        \\
    });
    const want =
        \\replace t.txt: ok
        \\read t.txt: ok new
        \\replace fresh.txt: ok
        \\replace sub/b.txt: ok
        \\replace in_link: missing in_link
        \\replace out_link: missing out_link
        \\replace dirlink/t.txt: missing dirlink/t.txt
        \\replace nofolder/t.txt: missing nofolder/t.txt
        \\replace sub: missing sub
        \\replace fifo: missing fifo
        \\replace ../outside.txt: missing ../outside.txt
        \\replace a 255-byte name: ok
        \\read it: ok long
        \\remove it: ok
        \\list: a.txt, dirlink, dirout_link, fifo, fresh.txt, hard, in_link, out_link, sub, t.txt
        \\list sub: b.txt
        \\
    ;
    const interp = try s.guarded("60", &.{ s.mo_exe, "run", "swap.mo" });
    std.debug.print("---- mo run, exit {d}\n{s}", .{ interp.code, interp.stdout });
    try std.testing.expectEqualStrings(want, interp.stdout);
    try std.testing.expectEqual(@as(u8, 0), interp.code);
    try checkSwapped(s);
    // The tree again, fresh, for the binary.
    try s.sh("rm -rf work dirout outside.txt linked_work\n" ++ tree);
    const built = try s.guarded("300", &.{ s.mo_exe, "build", "swap.mo", "-o", "swap" });
    try std.testing.expectEqual(@as(u8, 0), built.code);
    const binary = try s.guarded("60", &.{"./zig-out/mo-build/swap/swap"});
    std.debug.print("---- binary, exit {d}\n{s}", .{ binary.code, binary.stdout });
    try std.testing.expectEqualStrings(want, binary.stdout);
    try std.testing.expectEqual(@as(u8, 0), binary.code);
    try checkSwapped(s);
    const tested = try s.guarded("120", &.{ s.mo_exe, "test", "swap.mo" });
    std.debug.print("---- mo test, exit {d}\n{s}", .{ tested.code, tested.stdout });
    try std.testing.expectEqual(@as(u8, 0), tested.code);
    const native = try s.nativeTests("swap.mo", "swap-tests");
    std.debug.print("---- mo build --tests, exit {d}\n{s}", .{ native.code, native.stdout });
    try std.testing.expectEqual(@as(u8, 0), native.code);
}

fn checkSwapped(s: Setup) !void {
    try std.testing.expectEqualStrings("new", try s.read("work/t.txt"));
    try std.testing.expectEqualStrings("made", try s.read("work/fresh.txt"));
    try std.testing.expectEqualStrings("deeper", try s.read("work/sub/b.txt"));
    try std.testing.expectEqual(@as(u32, 0o600), try s.mode("work/t.txt"));
    try std.testing.expectEqual(@as(u32, 0o600), try s.mode("work/fresh.txt"));
    try std.testing.expectEqualStrings("safe", try s.read("work/a.txt"));
    try std.testing.expectEqualStrings("secret", try s.read("outside.txt"));
    try std.testing.expect(try s.linkThere("work/in_link"));
    try std.testing.expect(try s.linkThere("work/out_link"));
}

/// The program both replace controls run: `rounds` replaces of work/target, alternating two
/// texts of different lengths, each a single repeated byte, so any mix of them shows.
const flipper =
    \\module Flip
    \\expose main
    \\
    \\intent "Replaces one file again and again with one of two texts, so a reader or a kill can catch it between them."
    \\
    \\fn main(platform: Platform)
    \\  work = platform.fs.scoped("work")
    \\  rounds = (platform.args.get(0) or "0").to_u64 or 0
    \\  size = (platform.args.get(1) or "0").to_u64 or 0
    \\  one = "a".repeat(size)
    \\  two = "b".repeat(size / 2)
    \\  var done = 0
    \\  for i in 0..rounds
    \\    text = if i % 2 == 0
    \\      two
    \\    else
    \\      one
    \\    end
    \\    if work.replace("target", text, within: 1.minute) is Ok(_)
    \\      done += 1
    \\    end
    \\  end
    \\  platform.stdout.write_line("#{done} replaced")
    \\end
    \\
;

/// Whether `got` is `n` a's or `n / 2` b's: one of the two texts whole.
fn whole(got: []const u8, n: usize) bool {
    if (got.len == n) return std.mem.allEqual(u8, got, 'a');
    if (got.len == n / 2) return std.mem.allEqual(u8, got, 'b');
    return false;
}

test "corpus: step 40, a reader looping through 1,000 replaces never sees a part of a file, under mo run and in a binary" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const s = try setup(arena, io, &tmp);
    const n = 200_000;
    try s.sh("mkdir work\npython3 -c 'import sys; sys.stdout.write(\"a\" * 200000)' > work/target\n");
    try tmp.dir.writeFile(io, .{ .sub_path = "flip.mo", .data = flipper });
    const built = try s.guarded("300", &.{ s.mo_exe, "build", "flip.mo", "-o", "flip" });
    try std.testing.expectEqual(@as(u8, 0), built.code);
    const target = try std.fs.path.join(arena, &.{ s.cwd, "work/target" });
    for ([_][]const []const u8{ &.{ s.mo_exe, "run", "flip.mo", "--", "1000", "200000" }, &.{ "./zig-out/mo-build/flip/flip", "1000", "200000" } }) |argv| {
        var all: std.ArrayList([]const u8) = .empty;
        try all.appendSlice(arena, &.{ "python3", s.guard, "120", "--" });
        try all.appendSlice(arena, argv);
        var child = try std.process.spawn(io, .{ .argv = all.items, .cwd = .{ .path = s.cwd }, .stdin = .ignore, .stdout = .pipe, .stderr = .inherit });
        var reads: usize = 0;
        var parts: usize = 0;
        var gone: usize = 0;
        // Read until the child's stdout closes, which it does when it exits.
        var done = false;
        var said: std.ArrayList(u8) = .empty;
        const out = child.stdout.?;
        // Between reads of the target, a poll that does not wait says whether the pipe has
        // something (or has closed); only then does the read run, so it never blocks. Through the
        // std.posix wrappers, which read the error the same way on every platform: the raw Linux
        // system call returns it negated in the result, where libc returns -1 and sets errno.
        while (!done) {
            if (Io.Dir.cwd().readFileAlloc(io, target, arena, .limited(1 << 20))) |got| {
                reads += 1;
                if (!whole(got, n)) parts += 1;
                arena.free(got);
            } else |_| gone += 1;
            var fds = [_]std.posix.pollfd{.{ .fd = out.handle, .events = std.posix.POLL.IN, .revents = 0 }};
            if (try std.posix.poll(&fds, 0) == 0) {
                io.sleep(.fromMicroseconds(50), .awake) catch {};
                continue;
            }
            var chunk: [256]u8 = undefined;
            const r = try std.posix.read(out.handle, &chunk);
            if (r == 0) done = true else try said.appendSlice(arena, chunk[0..r]);
        }
        const term = try child.wait(io);
        std.debug.print("---- {s}: {s}{d} reads, {d} partial, {d} not there, exit {any}\n", .{ argv[0], said.items, reads, parts, gone, term });
        try std.testing.expect(term == .exited and term.exited == 0);
        try std.testing.expectEqualStrings("1000 replaced\n", said.items);
        try std.testing.expectEqual(@as(usize, 0), parts);
        try std.testing.expectEqual(@as(usize, 0), gone);
        try std.testing.expect(reads > 0);
    }
}

test "corpus: step 40, a replace killed at any moment leaves one whole file, under mo run and in a binary" {
    // guard.py kills its child with SIGKILL past its limit, and checks every half second, so each
    // round's kill lands at an arbitrary point of the replace loop. A temporary file the kill left
    // whole (a full text's length) shows the kill landed between the write and the rename.
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const s = try setup(arena, io, &tmp);
    const n = 8_000_000;
    try s.sh("mkdir work\npython3 -c 'import sys; sys.stdout.write(\"a\" * 8000000)' > work/target\n");
    try tmp.dir.writeFile(io, .{ .sub_path = "flip.mo", .data = flipper });
    const built = try s.guarded("300", &.{ s.mo_exe, "build", "flip.mo", "-o", "flip" });
    try std.testing.expectEqual(@as(u8, 0), built.code);
    for ([_][]const []const u8{ &.{ s.mo_exe, "run", "flip.mo", "--", "1000000", "8000000" }, &.{ "./zig-out/mo-build/flip/flip", "1000000", "8000000" } }) |argv| {
        var kills: usize = 0;
        var between: usize = 0;
        var left: usize = 0;
        for (0..8) |round| {
            const limit = try std.fmt.allocPrint(arena, "{d}.{d}", .{ 1 + round / 4, (round * 3) % 10 });
            const ran = try s.guarded(limit, argv);
            if (ran.code == 137) kills += 1;
            try std.testing.expect(whole(try s.read("work/target"), n));
            // What the kill left: temporary names beside the target.
            var dir = try Io.Dir.cwd().openDir(io, try std.fs.path.join(arena, &.{ s.cwd, "work" }), .{ .iterate = true });
            defer dir.close(io);
            var it = dir.iterate();
            while (try it.next(io)) |entry| {
                if (std.mem.eql(u8, entry.name, "target")) continue;
                left += 1;
                const st = try dir.statFile(io, entry.name, .{});
                if (st.size == n or st.size == n / 2) between += 1;
                try dir.deleteFile(io, entry.name);
            }
        }
        std.debug.print("---- {s}: {d} of 8 rounds killed, {d} temporary files left, {d} of them whole (killed between write and rename); the target whole every time\n", .{ argv[0], kills, left, between });
        try std.testing.expect(kills > 0);
    }
}
