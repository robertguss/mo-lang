//! The interpreter's `Tls` rows (steps 36 and 37, design-v0/09 `## Tls`): `Tls.server`, which
//! parses a certificate chain and a key through the TLS brick (bricks/tls.zig), and
//! `TlsServer.accept`, which runs the server's half of the handshake on a `Conn` and gives the
//! same `Conn` back with the engine behind it; `Tls.client`, which parses the roots a client
//! trusts, and `TlsClient.connect`, the client's half on a `Conn` from `Net.connect`; each side's
//! ALPN list (`offer`, a new value each time); and `Conn.protocol`, what the two agreed. From the
//! handshake on, `read_line`, `write`, `close`, and `lines` are the rows they always were
//! (net.zig's `fillTls` and `writeAllTls`), so a program written against a plain socket works
//! behind TLS unchanged, on either end.
//!
//! The brick holds the servers, the clients, and the connections; the run holds only a table of
//! each, beside its sockets (net.zig), so a `TlsServer`'s or a `TlsClient`'s `Value.Cap.handle`
//! is its index there and every process's vm reaches the same ones. The `mo build` binaries call
//! the same exports through `mo_rt.c`.
const std = @import("std");
const brick = @import("bricks/tls.zig");
const net_mod = @import("net.zig");
const prelude = @import("prelude.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;

pub const Row = enum { server, accept, client, connect, offer, protocol };

fn fail(vm: *Vm, which: []const u8) Error!Value {
    return vm.variant("Error", &.{try vm.variant(which, &.{})});
}

fn crash(vm: *Vm, row: prelude.Fn, comptime format: []const u8, args: anytype) Error {
    vm.report = .{ .kind = .other, .clause = try std.fmt.allocPrint(vm.gpa, format, args), .within = row.name, .at = 0 };
    return error.Crash;
}

/// Where a run keeps its TLS servers and clients: beside the sockets, since every process has a
/// vm of its own and they all reach one network (net.zig).
const Tables = struct {
    servers: *std.ArrayList(*brick.Server),
    clients: *std.ArrayList(*brick.Client),
};

fn tables(vm: *Vm, row: prelude.Fn) Error!Tables {
    if (vm.server) |s| return .{ .servers = &s.sockets.tls_servers, .clients = &s.sockets.tls_clients };
    if (vm.sim) |s| return .{ .servers = &s.fixture.tls_servers, .clients = &s.fixture.tls_clients };
    return crash(vm, row, "Tls runs only under mo run or in a test", .{});
}

/// The runtime's clock in seconds, which a client checks a chain's dates against: the wall clock
/// under `mo run`, and in a test the simulator's (`Time.fixture()`, 2026-01-01, moved by
/// fixture waits).
fn nowSec(vm: *Vm) i64 {
    const ms = if (vm.sim) |s| s.clockNow() else if (vm.server) |s| s.now() else vm_mod.fixture_time;
    return @divFloor(ms, 1000);
}

/// ALPN's names as the brick takes them, NUL-separated. A name that is empty, longer than 255
/// bytes, or holds a NUL is the caller's broken rule (RFC 7301 3.1), and a crash.
fn names(vm: *Vm, row: prelude.Fn, list: []const Value) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(vm.gpa);
    for (list) |v| {
        const name = v.string;
        if (name.len == 0 or name.len > 255 or std.mem.indexOfScalar(u8, name, 0) != null)
            return crash(vm, row, "an ALPN protocol name is 1 to 255 bytes with no NUL, and \"{s}\" is not", .{name});
        try out.appendSlice(vm.gpa, name);
        try out.append(vm.gpa, 0);
    }
    // The list's size on the wire is its NUL-separated size: each name's length and one.
    if (out.items.len > brick.max_alpn_bytes)
        return crash(vm, row, "an ALPN list is at most {d} bytes on the wire, each name's length and one, and this one is {d}", .{ brick.max_alpn_bytes, out.items.len });
    return out.toOwnedSlice(vm.gpa);
}

pub fn call(vm: *Vm, row: prelude.Fn, which: Row, a: []const Value) Error!Value {
    switch (which) {
        // `tls.server(cert:, key:)`: the PEM text the program read with an Fs, not a path.
        .server => {
            const cert = a[1].string;
            const key = a[2].string;
            const t = try tables(vm, row);
            const server = brick.mo_tls_server_new(cert.ptr, cert.len, key.ptr, key.len) orelse return fail(vm, "BadPem");
            try t.servers.append(vm.gpa, server);
            return vm.variant("Ok", &.{.{ .cap = .{ .kind = .tls_server, .handle = @intCast(t.servers.items.len - 1) } }});
        },
        // `tls.client(trust:)`: PEM text holding one or more root certificates.
        .client => {
            const trust = a[1].string;
            const t = try tables(vm, row);
            const client = brick.mo_tls_client_new(trust.ptr, trust.len) orelse return fail(vm, "BadPem");
            try t.clients.append(vm.gpa, client);
            return vm.variant("Ok", &.{.{ .cap = .{ .kind = .tls_client, .handle = @intCast(t.clients.items.len - 1) } }});
        },
        // `server.offer(protocols)` and `client.offer(protocols)`: a new one with the list, the
        // old one as it was.
        .offer => {
            const t = try tables(vm, row);
            const list = try names(vm, row, a[1].list);
            defer vm.gpa.free(list);
            const h = a[0].cap.handle;
            if (a[0].cap.kind == .tls_server) {
                const server = brick.mo_tls_server_offer(t.servers.items[h], list.ptr, list.len) orelse return error.OutOfMemory;
                try t.servers.append(vm.gpa, server);
                return .{ .cap = .{ .kind = .tls_server, .handle = @intCast(t.servers.items.len - 1) } };
            }
            const client = brick.mo_tls_client_offer(t.clients.items[h], list.ptr, list.len) orelse return error.OutOfMemory;
            try t.clients.append(vm.gpa, client);
            return .{ .cap = .{ .kind = .tls_client, .handle = @intCast(t.clients.items.len - 1) } };
        },
        // `tls_server.accept(conn, within:)`: the handshake, then the same Conn.
        .accept => {
            const server = (try tables(vm, row)).servers.items[a[0].cap.handle];
            return handshake(vm, row, a[1].cap, .{ .server = server }, a[2].duration);
        },
        // `tls_client.connect(conn, host:, within:)`: the client's half, then the same Conn.
        .connect => {
            const client = (try tables(vm, row)).clients.items[a[0].cap.handle];
            return handshake(vm, row, a[1].cap, .{ .client = .{ .client = client, .host = a[2].string, .now = nowSec(vm) } }, a[3].duration);
        },
        // `conn.protocol`: the ALPN protocol the handshake agreed, None on a plain Conn.
        .protocol => {
            const h = a[0].cap.handle;
            const t: ?*brick.Conn = if (vm.server) |s| s.sockets.conns.items[h].tls else if (vm.sim) |s| s.fixture.conns.items[h].tls else null;
            var buf: [255]u8 = undefined;
            const n = if (t) |engine| brick.mo_tls_protocol(engine, &buf, buf.len) else 0;
            if (n == 0) return vm.variant("None", &.{});
            return vm.variant("Some", &.{.{ .string = try vm_mod.rawDupe(vm.heap, u8, buf[0..n]) }});
        },
    }
}

fn handshake(vm: *Vm, row: prelude.Fn, conn: Value.Cap, side: net_mod.Side, ms: i64) Error!Value {
    if (vm.server) |s| {
        const c = s.sockets.conns.items[conn.handle];
        if (c.used.len > 0) return crash(vm, row, "{s} takes a connection nothing has read or written, and {s} was called on this one", .{ side.row(), c.used });
        return switch (try s.sockets.handshake(vm, c, side, ms)) {
            .done => vm.variant("Ok", &.{.{ .cap = conn }}),
            inline else => |f| fail(vm, @tagName(f)),
        };
    }
    if (vm.sim) |s| {
        const c = &s.fixture.conns.items[conn.handle];
        if (c.used.len > 0) return crash(vm, row, "{s} takes a connection nothing has read or written, and {s} was called on this one", .{ side.row(), c.used });
        return switch (try s.fixture.handshake(s, conn.handle, side, ms)) {
            .done => vm.variant("Ok", &.{.{ .cap = conn }}),
            inline else => |f| fail(vm, @tagName(f)),
        };
    }
    return crash(vm, row, "Tls runs only under mo run or in a test", .{});
}

test "the brick's answers reach the rows as TlsError's variants" {
    // The names the rows give back are exactly TlsError's, so a variant renamed in the prelude
    // without a change here does not compile away quietly.
    const want = [_][]const u8{ "BadPem", "Handshake", "Timeout", "Closed", "Untrusted" };
    var found: usize = 0;
    for (prelude.variants) |v| {
        if (!std.mem.eql(u8, v.owner, "TlsError")) continue;
        found += 1;
        for (want) |w| {
            if (std.mem.eql(u8, w, v.name)) break;
        } else return error.UnknownVariant;
    }
    try std.testing.expectEqual(want.len, found);
    inline for (@typeInfo(net_mod.Handshook).@"enum".fields) |f| {
        if (!comptime std.mem.eql(u8, f.name, "done")) {
            for (want) |w| {
                if (std.mem.eql(u8, w, f.name)) break;
            } else return error.UnknownOutcome;
        }
    }
}
