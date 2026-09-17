//! The interpreter's `Tls` rows (step 36, design-v0/09 `## Tls`): `Tls.server`, which parses a
//! certificate chain and a key through the TLS brick (bricks/tls.zig), and `TlsServer.accept`,
//! which runs the server's half of the handshake on a `Conn` and gives the same `Conn` back with
//! the engine behind it. From there `read_line`, `write`, `close`, and `lines` are the rows they
//! always were (net.zig's `fillTls` and `writeAllTls`), so a program written against a plain
//! socket works behind TLS unchanged.
//!
//! The brick holds the servers and the connections; the run holds only a table of the servers,
//! beside its sockets (net.zig), so a `TlsServer`'s `Value.Cap.handle` is its index there and
//! every process's vm reaches the same ones. The `mo build` binaries call the same exports
//! through `mo_rt.c`.
const std = @import("std");
const brick = @import("bricks/tls.zig");
const net_mod = @import("net.zig");
const prelude = @import("prelude.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;

pub const Row = enum { server, accept };

fn fail(vm: *Vm, which: []const u8) Error!Value {
    return vm.variant("Error", &.{try vm.variant(which, &.{})});
}

fn crash(vm: *Vm, row: prelude.Fn, comptime format: []const u8, args: anytype) Error {
    vm.report = .{ .kind = .other, .clause = try std.fmt.allocPrint(vm.gpa, format, args), .within = row.name, .at = 0 };
    return error.Crash;
}

/// Where a run keeps its TLS servers: beside the sockets, since every process has a vm of its
/// own and they all reach one network (net.zig).
fn servers(vm: *Vm, row: prelude.Fn) Error!*std.ArrayList(*brick.Server) {
    if (vm.server) |s| return &s.sockets.tls_servers;
    if (vm.sim) |s| return &s.fixture.tls_servers;
    return crash(vm, row, "Tls runs only under mo run or in a test", .{});
}

pub fn call(vm: *Vm, row: prelude.Fn, which: Row, a: []const Value) Error!Value {
    switch (which) {
        // `tls.server(cert:, key:)`: the PEM text the program read with an Fs, not a path.
        .server => {
            const cert = a[1].string;
            const key = a[2].string;
            const table = try servers(vm, row);
            const server = brick.mo_tls_server_new(cert.ptr, cert.len, key.ptr, key.len) orelse return fail(vm, "BadPem");
            try table.append(vm.gpa, server);
            return vm.variant("Ok", &.{.{ .cap = .{ .kind = .tls_server, .handle = @intCast(table.items.len - 1) } }});
        },
        // `tls_server.accept(conn, within:)`: the handshake, then the same Conn.
        .accept => {
            const server = (try servers(vm, row)).items[a[0].cap.handle];
            const conn = a[1].cap;
            const ms = a[2].duration;
            if (vm.server) |s| {
                const c = s.sockets.conns.items[conn.handle];
                if (c.used.len > 0) return crash(vm, row, "TlsServer.accept takes a connection nothing has read or written, and {s} was called on this one", .{c.used});
                return switch (try s.sockets.handshake(vm, c, server, ms)) {
                    .done => vm.variant("Ok", &.{.{ .cap = conn }}),
                    inline else => |f| fail(vm, @tagName(f)),
                };
            }
            if (vm.sim) |s| {
                const c = &s.fixture.conns.items[conn.handle];
                if (c.used.len > 0) return crash(vm, row, "TlsServer.accept takes a connection nothing has read or written, and {s} was called on this one", .{c.used});
                return switch (try s.fixture.handshake(s, conn.handle, server, ms)) {
                    .done => vm.variant("Ok", &.{.{ .cap = conn }}),
                    inline else => |f| fail(vm, @tagName(f)),
                };
            }
            return crash(vm, row, "Tls runs only under mo run or in a test", .{});
        },
    }
}

test "the brick's answers reach the rows as TlsError's variants" {
    // The names the rows give back are exactly TlsError's, so a variant renamed in the prelude
    // without a change here does not compile away quietly.
    const want = [_][]const u8{ "BadPem", "Handshake", "Timeout", "Closed" };
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
