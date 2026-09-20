//! Http: HTTP/1.1 over Net (design-v0/09, Http), on real sockets for `mo run` and on
//! `Net.fixture()`'s network for `mo test`. An HttpListener is a Listener, its handle the
//! same index; an Exchange's handle is its index in `Net.exchanges` or `Fixture.exchanges`,
//! which keep the connection it answers on and the request's bytes until it is answered.
//!
//! One request per connection, no TLS: `accept` reads one whole request and gives it as an
//! Exchange, `reply` writes the one response and closes the connection, and `send` connects,
//! writes one request, and reads the response to the end. Bodies go by `content-length`; a
//! request or response with a `transfer-encoding` is `Unsupported`, and a request line, the
//! header lines, or a body over 1 MiB is `TooLarge`. Header names are lower-cased on read; a
//! repeated header's values are joined with ", " in the first one's place. Every response and
//! request written carries `content-length` and `connection: close`, whatever the program's
//! headers say about either.
//!
//! A request that is not HTTP gets a response before its connection closes: 400 for
//! `Malformed`, 413 for `TooLarge`, 501 for `Unsupported`; `accept` gives the error.
const std = @import("std");
const Io = std.Io;
const net = @import("net.zig");
const sim_mod = @import("sim.zig");
const stdlib = @import("stdlib.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;

pub const Row = enum { listen, accept, port, request, reply, send, serve };

/// HttpError's variants, by name.
pub const Failure = enum { Timeout, Refused, Closed, Busy, Malformed, TooLarge, Unsupported };

/// The most a request line, the header lines together, or a body may be.
pub const limit = 1 << 20;
/// A connection's buffer at its first read, and at most: a message at every limit, with the
/// line ends past them.
pub const buffer_initial = 16 << 10;
pub const buffer_cap = 3 * limit + 8;

pub const Kind = enum { request, response };

/// A whole message in the bytes of a stream.
pub const Message = struct {
    /// The request line or the status line, without its line end.
    start: []const u8,
    /// The header lines, each with its line end, without the blank line after them.
    headers: []const u8,
    body: []const u8,
    /// The bytes the message takes.
    len: usize,
};

pub const Parsed = union(enum) { more, failed: Failure, whole: Message };

fn withoutCr(line: []const u8) []const u8 {
    return if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
}

/// A token (RFC 9110): a method, or a header name.
fn isToken(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |ch| switch (ch) {
        'a'...'z', 'A'...'Z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => {},
        else => return false,
    };
    return true;
}

/// A header value: no control character but a tab.
fn isValue(s: []const u8) bool {
    for (s) |ch| if ((ch < 0x20 and ch != '\t') or ch == 0x7f) return false;
    return true;
}

/// HTTP/1.0 or HTTP/1.1; another HTTP/d.d is Unsupported, anything else Malformed.
fn version(s: []const u8) ?Failure {
    if (s.len != 8 or !std.mem.startsWith(u8, s, "HTTP/") or !std.ascii.isDigit(s[5]) or s[6] != '.' or !std.ascii.isDigit(s[7])) return .Malformed;
    if (std.mem.eql(u8, s, "HTTP/1.1") or std.mem.eql(u8, s, "HTTP/1.0")) return null;
    return .Unsupported;
}

const RequestLine = struct { method: []const u8, target: []const u8 };

fn requestLine(line: []const u8) union(enum) { ok: RequestLine, failed: Failure } {
    const sp1 = std.mem.indexOfScalar(u8, line, ' ') orelse return .{ .failed = .Malformed };
    const rest = line[sp1 + 1 ..];
    const sp2 = std.mem.indexOfScalar(u8, rest, ' ') orelse return .{ .failed = .Malformed };
    const method = line[0..sp1];
    const target = rest[0..sp2];
    if (!isToken(method) or !isTarget(target)) return .{ .failed = .Malformed };
    if (version(rest[sp2 + 1 ..])) |f| return .{ .failed = f };
    if (std.mem.indexOfScalar(u8, target, '?')) |q| {
        var it = std.mem.splitScalar(u8, target[q + 1 ..], '&');
        while (it.next()) |pair| if (!decodable(pair)) return .{ .failed = .Malformed };
    }
    return .{ .ok = .{ .method = method, .target = target } };
}

/// A target in origin form: a `/`, then no space or control character.
fn isTarget(s: []const u8) bool {
    if (s.len == 0 or s[0] != '/') return false;
    for (s) |ch| if (ch <= 0x20 or ch == 0x7f) return false;
    return true;
}

/// The status of a status line, 100 to 599.
fn statusLine(line: []const u8) union(enum) { ok: u16, failed: Failure } {
    const sp = std.mem.indexOfScalar(u8, line, ' ') orelse return .{ .failed = .Malformed };
    if (version(line[0..sp])) |f| return .{ .failed = f };
    const rest = line[sp + 1 ..];
    if (rest.len < 3 or (rest.len > 3 and rest[3] != ' ')) return .{ .failed = .Malformed };
    for (rest[0..3]) |ch| if (!std.ascii.isDigit(ch)) return .{ .failed = .Malformed };
    const status = std.fmt.parseInt(u16, rest[0..3], 10) catch unreachable;
    if (status < 100 or status > 599) return .{ .failed = .Malformed };
    return .{ .ok = status };
}

const Field = struct { name: []const u8, value: []const u8 };

fn field(line: []const u8) ?Field {
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    const name = line[0..colon];
    const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
    if (!isToken(name) or !isValue(value)) return null;
    return .{ .name = name, .value = value };
}

/// The next header line of `headers`, which ends each with a line end.
fn nextField(headers: []const u8, at: *usize) ?Field {
    if (at.* >= headers.len) return null;
    const k = std.mem.indexOfScalarPos(u8, headers, at.*, '\n').?;
    const line = withoutCr(headers[at.*..k]);
    at.* = k + 1;
    return field(line).?;
}

/// What the bytes of a stream so far hold: a whole request or response, not yet, or why not.
/// `eof`: nothing follows `bytes`. A response with no content-length runs to the end of the
/// stream; a request with none has no body.
pub fn parse(bytes: []const u8, eof: bool, kind: Kind) Parsed {
    const start_end = std.mem.indexOfScalar(u8, bytes, '\n') orelse {
        if (bytes.len > limit + 1) return .{ .failed = .TooLarge };
        return if (eof) .{ .failed = .Closed } else .more;
    };
    const start = withoutCr(bytes[0..start_end]);
    if (start.len > limit) return .{ .failed = .TooLarge };
    switch (kind) {
        .request => switch (requestLine(start)) {
            .ok => {},
            .failed => |f| return .{ .failed = f },
        },
        .response => switch (statusLine(start)) {
            .ok => {},
            .failed => |f| return .{ .failed = f },
        },
    }
    const headers_start = start_end + 1;
    var at = headers_start;
    var content_length: ?u64 = null;
    const headers_end = while (true) {
        const rest = bytes[at..];
        const k = std.mem.indexOfScalar(u8, rest, '\n') orelse {
            if (at - headers_start + rest.len > limit) return .{ .failed = .TooLarge };
            return if (eof) .{ .failed = .Closed } else .more;
        };
        const line = withoutCr(rest[0..k]);
        const line_start = at;
        at += k + 1;
        if (line.len == 0) break line_start;
        if (at - headers_start > limit) return .{ .failed = .TooLarge };
        const f = field(line) orelse return .{ .failed = .Malformed };
        if (std.ascii.eqlIgnoreCase(f.name, "transfer-encoding")) return .{ .failed = .Unsupported };
        if (std.ascii.eqlIgnoreCase(f.name, "content-length")) {
            if (f.value.len == 0 or f.value.len > 19) return .{ .failed = if (f.value.len == 0) .Malformed else .TooLarge };
            for (f.value) |ch| if (!std.ascii.isDigit(ch)) return .{ .failed = .Malformed };
            const n = std.fmt.parseInt(u64, f.value, 10) catch unreachable;
            if (content_length) |prev| if (prev != n) return .{ .failed = .Malformed };
            content_length = n;
        }
    };
    const headers = bytes[headers_start..headers_end];
    if (content_length) |n| {
        if (n > limit) return .{ .failed = .TooLarge };
        if (bytes.len - at < n) return if (eof) .{ .failed = .Closed } else .more;
        return .{ .whole = .{ .start = start, .headers = headers, .body = bytes[at .. at + n], .len = at + n } };
    }
    if (kind == .request) return .{ .whole = .{ .start = start, .headers = headers, .body = "", .len = at } };
    if (bytes.len - at > limit) return .{ .failed = .TooLarge };
    if (!eof) return .more;
    return .{ .whole = .{ .start = start, .headers = headers, .body = bytes[at..], .len = bytes.len } };
}

fn hexDigit(ch: u8) ?u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'a'...'f' => ch - 'a' + 10,
        'A'...'F' => ch - 'A' + 10,
        else => null,
    };
}

/// Whether every `%` in `s` begins two hex digits.
fn decodable(s: []const u8) bool {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] != '%') continue;
        if (i + 2 >= s.len) return false;
        if (hexDigit(s[i + 1]) == null or hexDigit(s[i + 2]) == null) return false;
        i += 2;
    }
    return true;
}

/// A query key or value as it was before it was sent: `+` is a space, `%XX` its byte.
fn decode(a: std.mem.Allocator, s: []const u8) error{OutOfMemory}![]u8 {
    const out = try a.alloc(u8, s.len);
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        out[n] = switch (s[i]) {
            '+' => ' ',
            '%' => blk: {
                i += 2;
                break :blk hexDigit(s[i - 1]).? * 16 + hexDigit(s[i]).?;
            },
            else => s[i],
        };
        n += 1;
    }
    return out[0..n];
}

/// `s` as a query key or value is sent: every byte but a letter, a digit, and `-._~` as %XX.
fn encode(w: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) error{OutOfMemory}!void {
    for (s) |ch| switch (ch) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '.', '_', '~' => try w.append(gpa, ch),
        else => try w.print(gpa, "%{X:0>2}", .{ch}),
    };
}

/// Sets `key` in `entries` (a map's, key then value), or when it is there already joins
/// `value` to its value with ", " (a repeated header) or replaces it (a repeated query key).
fn setEntry(vm: *Vm, entries: *std.ArrayList(Value), key: []const u8, value: []const u8, join: bool) Error!void {
    var i: usize = 0;
    while (i < entries.items.len) : (i += 2) {
        if (!std.mem.eql(u8, entries.items[i].string, key)) continue;
        entries.items[i + 1] = .{ .string = if (join) try std.mem.concat(vm.heap, u8, &.{ entries.items[i + 1].string, ", ", value }) else value };
        return;
    }
    try entries.append(vm.gpa, .{ .string = key });
    try entries.append(vm.gpa, .{ .string = value });
}

fn mapValue(vm: *Vm, entries: []const Value) Error!Value {
    return .{ .map = try stdlib.mapOf(vm.heap, try vm_mod.rawDupe(vm.heap, Value, entries), 2) };
}

/// The header lines as a map, names lower-cased.
fn headersValue(vm: *Vm, headers: []const u8) Error!Value {
    var entries: std.ArrayList(Value) = .empty;
    defer entries.deinit(vm.gpa);
    var at: usize = 0;
    while (nextField(headers, &at)) |f| {
        const name = try std.ascii.allocLowerString(vm.heap, f.name);
        try setEntry(vm, &entries, name, try vm_mod.rawDupe(vm.heap, u8, f.value), true);
    }
    return mapValue(vm, entries.items);
}

/// The `Request` a whole request's bytes spell.
pub fn requestValue(vm: *Vm, bytes: []const u8) Error!Value {
    const m = parse(bytes, true, .request).whole;
    const line = requestLine(m.start).ok;
    const q = std.mem.indexOfScalar(u8, line.target, '?');
    var query: std.ArrayList(Value) = .empty;
    defer query.deinit(vm.gpa);
    if (q) |at| {
        var it = std.mem.splitScalar(u8, line.target[at + 1 ..], '&');
        while (it.next()) |pair| {
            if (pair.len == 0) continue;
            const eq = std.mem.indexOfScalar(u8, pair, '=');
            const key = try decode(vm.heap, pair[0 .. eq orelse pair.len]);
            const value = if (eq) |e| try decode(vm.heap, pair[e + 1 ..]) else "";
            try setEntry(vm, &query, key, value, false);
        }
    }
    const fields = try vm_mod.rawAlloc(vm.heap, Value, 5);
    fields[0] = .{ .string = try vm_mod.rawDupe(vm.heap, u8, line.method) };
    fields[1] = .{ .string = try vm_mod.rawDupe(vm.heap, u8, line.target[0 .. q orelse line.target.len]) };
    fields[2] = try mapValue(vm, query.items);
    fields[3] = try headersValue(vm, m.headers);
    fields[4] = .{ .string = try vm_mod.rawDupe(vm.heap, u8, m.body) };
    return .{ .record = .{ .decl = vm.program.checked.preludeStruct("Request").?, .fields = fields } };
}

/// The `Response` a whole response's bytes spell.
pub fn responseValue(vm: *Vm, bytes: []const u8) Error!Value {
    const m = parse(bytes, true, .response).whole;
    const fields = try vm_mod.rawAlloc(vm.heap, Value, 3);
    fields[0] = .{ .int = statusLine(m.start).ok };
    fields[1] = try headersValue(vm, m.headers);
    fields[2] = .{ .string = try vm_mod.rawDupe(vm.heap, u8, m.body) };
    return .{ .record = .{ .decl = vm.program.checked.preludeStruct("Response").?, .fields = fields } };
}

/// The reason phrase a status line gives a status; empty for one not listed.
pub fn reason(status: i128) []const u8 {
    return switch (status) {
        100 => "Continue",
        101 => "Switching Protocols",
        200 => "OK",
        201 => "Created",
        202 => "Accepted",
        204 => "No Content",
        301 => "Moved Permanently",
        302 => "Found",
        303 => "See Other",
        304 => "Not Modified",
        307 => "Temporary Redirect",
        308 => "Permanent Redirect",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        411 => "Length Required",
        413 => "Content Too Large",
        415 => "Unsupported Media Type",
        422 => "Unprocessable Content",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        else => "",
    };
}

/// The program's headers, each as `name: value`, but content-length and connection, which the
/// runtime writes, and `skip` when it is given; Malformed when a name is not a token or a
/// value holds a control character.
fn writeHeaders(w: *std.ArrayList(u8), gpa: std.mem.Allocator, headers: Value.Map, skip: ?[]const u8) (error{ OutOfMemory, Malformed })!void {
    var i: usize = 0;
    while (i + 1 < headers.entries.len) : (i += 2) {
        const name = headers.entries[i].string;
        const value = headers.entries[i + 1].string;
        if (!isToken(name) or !isValue(value)) return error.Malformed;
        if (std.ascii.eqlIgnoreCase(name, "content-length") or std.ascii.eqlIgnoreCase(name, "connection")) continue;
        if (skip) |s| if (std.ascii.eqlIgnoreCase(name, s)) continue;
        try w.print(gpa, "{s}: {s}\r\n", .{ name, value });
    }
}

fn hasHeader(headers: Value.Map, name: []const u8) bool {
    var i: usize = 0;
    while (i + 1 < headers.entries.len) : (i += 2) if (std.ascii.eqlIgnoreCase(headers.entries[i].string, name)) return true;
    return false;
}

/// A Response as it goes on the wire; Malformed for a status outside 100 to 599 or a header
/// that is not one.
pub fn responseBytes(gpa: std.mem.Allocator, response: Value) (error{ OutOfMemory, Malformed })![]u8 {
    const f = response.record.fields;
    const status = f[0].int;
    if (status < 100 or status > 599) return error.Malformed;
    var w: std.ArrayList(u8) = .empty;
    errdefer w.deinit(gpa);
    try w.print(gpa, "HTTP/1.1 {d} {s}\r\n", .{ status, reason(status) });
    try writeHeaders(&w, gpa, f[1].map, null);
    try w.print(gpa, "content-length: {d}\r\nconnection: close\r\n\r\n", .{f[2].string.len});
    try w.appendSlice(gpa, f[2].string);
    return w.toOwnedSlice(gpa);
}

/// A Request to `host` at `port` as it goes on the wire, with a `host` header unless it has
/// one; Malformed for a method that is not a token, a path that is not `/` and printable
/// bytes, or a header that is not one. The query follows the path, after a `?`, or after an
/// `&` when the path has a `?` already.
pub fn requestBytes(gpa: std.mem.Allocator, request: Value, host: []const u8, port: i128) (error{ OutOfMemory, Malformed })![]u8 {
    const f = request.record.fields;
    const method = f[0].string;
    const path = f[1].string;
    if (!isToken(method) or !isTarget(path)) return error.Malformed;
    var w: std.ArrayList(u8) = .empty;
    errdefer w.deinit(gpa);
    try w.print(gpa, "{s} {s}", .{ method, path });
    const query = f[2].map.entries;
    var i: usize = 0;
    while (i + 1 < query.len) : (i += 2) {
        try w.append(gpa, if (i > 0) '&' else if (std.mem.indexOfScalar(u8, path, '?') != null) '&' else '?');
        try encode(&w, gpa, query[i].string);
        try w.append(gpa, '=');
        try encode(&w, gpa, query[i + 1].string);
    }
    try w.appendSlice(gpa, " HTTP/1.1\r\n");
    if (!hasHeader(f[3].map, "host")) try w.print(gpa, "host: {s}:{d}\r\n", .{ host, port });
    try writeHeaders(&w, gpa, f[3].map, null);
    try w.print(gpa, "content-length: {d}\r\nconnection: close\r\n\r\n", .{f[4].string.len});
    try w.appendSlice(gpa, f[4].string);
    return w.toOwnedSlice(gpa);
}

/// The response a request that is not HTTP gets before its connection closes.
pub fn refusal(f: Failure) ?[]const u8 {
    return switch (f) {
        .Malformed => "HTTP/1.1 400 Bad Request\r\ncontent-length: 0\r\nconnection: close\r\n\r\n",
        .TooLarge => "HTTP/1.1 413 Content Too Large\r\ncontent-length: 0\r\nconnection: close\r\n\r\n",
        .Unsupported => "HTTP/1.1 501 Not Implemented\r\ncontent-length: 0\r\nconnection: close\r\n\r\n",
        else => null,
    };
}

fn fail(vm: *Vm, f: Failure) Error!Value {
    return vm.variant("Error", &.{try vm.variant(@tagName(f), &.{})});
}

fn fromNet(f: net.Failure) Failure {
    return switch (f) {
        .Timeout => .Timeout,
        .Refused => .Refused,
        .Closed, .LineTooLong => .Closed,
        .Busy => .Busy,
    };
}

fn cap(vm: *Vm, kind: @import("types.zig").CapKind, handle: u32) Error!Value {
    return vm.variant("Ok", &.{.{ .cap = .{ .kind = kind, .handle = handle } }});
}

/// A listener's Ok re-kinded as an HttpListener; an error is the same variant in HttpError.
fn asHttpListener(vm: *Vm, listened: Value) Error!Value {
    if (!std.mem.eql(u8, listened.variant.name, "Ok")) return listened;
    return cap(vm, .http_listener, listened.variant.fields[0].cap.handle);
}

fn requestAfterReply(vm: *Vm) Error {
    vm.report = .{ .kind = .other, .clause = "exchange.request after the exchange was answered: read the request before replying", .within = "request", .at = 0 };
    return error.Crash;
}

// ---- real sockets

fn elapsed(io: Io, t0: Io.Clock.Timestamp) i64 {
    return t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toMilliseconds();
}

/// One row on real sockets; `a` is the receiver, then the parameters, then `within`.
pub fn call(n: *net.Net, vm: *Vm, which: Row, a: []const Value) Error!Value {
    return switch (which) {
        .listen => asHttpListener(vm, try n.call(vm, .listen, a)),
        .port => .{ .int = n.listeners.items[a[0].cap.handle].port },
        .accept => accept(n, vm, n.listeners.items[a[0].cap.handle], a[1].duration),
        .request => blk: {
            const e = n.exchanges.items[a[0].cap.handle];
            if (e.answered) return requestAfterReply(vm);
            break :blk requestValue(vm, e.request);
        },
        .reply => reply(n, vm, a[0].cap.handle, a[1], a[2].duration),
        .send => send(n, vm, a[1], a[2].string, a[3].int, a[4].duration),
        // The runtime's loop (sources.zig); vm.zig sends it there.
        .serve => unreachable,
    };
}

const Read = union(enum) { whole: usize, failed: Failure };

/// One whole message from `c`, at most `ms`: the bytes it takes at the front of the buffer.
fn readMessage(n: *net.Net, vm: *Vm, c: *net.Conn, kind: Kind, ms: i64) Error!Read {
    if (c.closed) return .{ .failed = .Closed };
    if (c.reading) return .{ .failed = .Busy };
    const t0 = Io.Clock.Timestamp.now(n.io, .awake);
    while (true) {
        switch (parse(c.buf[c.start..c.end], c.eof, kind)) {
            .whole => |m| return .{ .whole = m.len },
            .failed => |f| return .{ .failed = f },
            .more => {},
        }
        const left = ms - elapsed(n.io, t0);
        if (left <= 0) return .{ .failed = .Timeout };
        switch (try n.fill(vm, c, left, buffer_initial, buffer_cap)) {
            .got, .eof => {},
            .timeout => return .{ .failed = .Timeout },
            .closed => return .{ .failed = .Closed },
            .busy => return .{ .failed = .Busy },
            .full => return .{ .failed = .TooLarge },
        }
    }
}

/// `listener.accept`: the next client's whole request, as an Exchange. A client whose request
/// does not arrive in time, or is not HTTP, is closed, and the listener goes on listening.
fn accept(n: *net.Net, vm: *Vm, l: *net.Listener, ms: i64) Error!Value {
    const t0 = Io.Clock.Timestamp.now(n.io, .awake);
    const h = switch (try n.acceptConn(vm, l, ms)) {
        .ok => |h| h,
        .failed => |f| return fail(vm, fromNet(f)),
    };
    const c = n.conns.items[h];
    switch (try readMessage(n, vm, c, .request, ms - elapsed(n.io, t0))) {
        .whole => |len| {
            const bytes = try n.gpa.dupe(u8, c.buf[c.start .. c.start + len]);
            c.start += len;
            const handle: u32 = @intCast(n.exchanges.items.len);
            try n.exchanges.append(n.gpa, .{ .conn = h, .request = bytes });
            return cap(vm, .exchange, handle);
        },
        .failed => |f| {
            if (refusal(f)) |text| _ = try n.writeAll(vm, c, text, @max(ms - elapsed(n.io, t0), 100));
            n.close(c);
            return fail(vm, f);
        },
    }
}

/// `exchange.reply(response)`: the response, then the connection closes. A second reply is
/// Closed; a Malformed response leaves the exchange unanswered.
fn reply(n: *net.Net, vm: *Vm, handle: u32, response: Value, ms: i64) Error!Value {
    const e = &n.exchanges.items[handle];
    if (e.answered) return fail(vm, .Closed);
    const bytes = responseBytes(n.gpa, response) catch |err| return if (err == error.Malformed) fail(vm, .Malformed) else error.OutOfMemory;
    defer n.gpa.free(bytes);
    const c = n.conns.items[e.conn];
    const failed = try n.writeAll(vm, c, bytes, ms);
    if (failed == .Busy) return fail(vm, .Busy);
    n.exchanges.items[handle].forget(n.gpa);
    n.close(c);
    if (failed) |f| return fail(vm, fromNet(f));
    return vm.variant("Ok", &.{.none});
}

/// `http.send(request, host:, port:)`: connects, writes the request, and reads the whole
/// response; the connection closes either way.
fn send(n: *net.Net, vm: *Vm, request: Value, host: []const u8, port: i128, ms: i64) Error!Value {
    const bytes = requestBytes(n.gpa, request, host, port) catch |err| return if (err == error.Malformed) fail(vm, .Malformed) else error.OutOfMemory;
    defer n.gpa.free(bytes);
    const t0 = Io.Clock.Timestamp.now(n.io, .awake);
    const h = switch (try n.connectConn(vm, host, @intCast(port), ms)) {
        .ok => |h| h,
        .failed => |f| return fail(vm, fromNet(f)),
    };
    const c = n.conns.items[h];
    defer n.close(c);
    const left = ms - elapsed(n.io, t0);
    if (left <= 0) return fail(vm, .Timeout);
    if (try n.writeAll(vm, c, bytes, left)) |f| return fail(vm, fromNet(f));
    return switch (try readMessage(n, vm, c, .response, ms - elapsed(n.io, t0))) {
        .whole => |len| vm.variant("Ok", &.{try responseValue(vm, c.buf[c.start .. c.start + len])}),
        .failed => |f| fail(vm, f),
    };
}

// ---- Http.fixture()

/// One row on `Net.fixture()`'s network (net.zig, Fixture), for a test with no socket. As a
/// Net fixture call, one with nothing to take waits its whole deadline and is Timeout. A
/// `send` waits for a server in the run: while its response is not whole, it delivers the
/// processes' waiting messages a round at a time, as a settle does, and when none is waiting
/// it is Timeout. So a test that sends a server process a message to accept, then sends a
/// request in the same statement, gets the server's response. Under faults, `accept` and
/// `send` can time out by the seed, and `reply` and `send` can find the connection Closed.
pub fn fixtureCall(f: *net.Fixture, vm: *Vm, sim: *sim_mod.Sim, which: Row, a: []const Value) Error!Value {
    const gpa = sim.gpa;
    switch (which) {
        .listen => return asHttpListener(vm, try f.call(vm, sim, .listen, a)),
        .port => return .{ .int = f.listeners.items[a[0].cap.handle].port },
        .accept => {
            const within = a[1].duration;
            if (sim.fault(null, within) != null) return fail(vm, .Timeout);
            const l = &f.listeners.items[a[0].cap.handle];
            if (l.served) return fail(vm, .Busy);
            if (l.head == l.backlog.items.len) {
                sim.wait(within);
                return fail(vm, .Timeout);
            }
            const h = l.backlog.items[l.head];
            l.head += 1;
            const c = &f.conns.items[h];
            const peer_closed = f.peerEnded(h);
            switch (parse(c.inbound.items[c.start..], peer_closed, .request)) {
                .whole => |m| {
                    const bytes = try gpa.dupe(u8, c.inbound.items[c.start .. c.start + m.len]);
                    c.start += m.len;
                    try f.exchanges.append(gpa, .{ .conn = h, .request = bytes });
                    return cap(vm, .exchange, @intCast(f.exchanges.items.len - 1));
                },
                .more => {
                    sim.wait(within);
                    c.closed = true;
                    return fail(vm, .Timeout);
                },
                .failed => |why| {
                    if (refusal(why)) |text| if (!f.conns.items[c.peer].closed) try f.conns.items[c.peer].inbound.appendSlice(gpa, text);
                    f.conns.items[h].closed = true;
                    return fail(vm, why);
                },
            }
        },
        .request => {
            const e = f.exchanges.items[a[0].cap.handle];
            if (e.answered) return requestAfterReply(vm);
            return requestValue(vm, e.request);
        },
        .reply => {
            const handle = a[0].cap.handle;
            if (f.exchanges.items[handle].answered) return fail(vm, .Closed);
            const bytes = responseBytes(gpa, a[1]) catch |err| return if (err == error.Malformed) fail(vm, .Malformed) else error.OutOfMemory;
            const h = f.exchanges.items[handle].conn;
            f.exchanges.items[handle].forget(gpa);
            const peer = f.conns.items[h].peer;
            const was_closed = f.conns.items[h].closed or f.conns.items[peer].closed;
            f.conns.items[h].closed = true;
            if (was_closed) return fail(vm, .Closed);
            if (sim.fault(.closed, a[2].duration)) |fault| return fail(vm, if (fault == .timeout) .Timeout else .Closed);
            try f.conns.items[peer].inbound.appendSlice(gpa, bytes);
            return vm.variant("Ok", &.{.none});
        },
        .send => {
            const within = a[4].duration;
            const bytes = requestBytes(gpa, a[1], a[2].string, a[3].int) catch |err| return if (err == error.Malformed) fail(vm, .Malformed) else error.OutOfMemory;
            if (sim.fault(null, within) != null) return fail(vm, .Timeout);
            const port: u16 = @intCast(a[3].int);
            const li = for (f.listeners.items, 0..) |l, i| {
                if (l.port == port) break i;
            } else return fail(vm, .Refused);
            const client: u32 = @intCast(f.conns.items.len);
            try f.conns.append(gpa, .{ .peer = client + 1 });
            try f.conns.append(gpa, .{ .peer = client, .listener = @intCast(li) });
            try f.listeners.items[li].backlog.append(gpa, client + 1);
            try f.conns.items[client + 1].inbound.appendSlice(gpa, bytes);
            var delivered: u32 = 0;
            const since = sim.deadlineNow();
            while (true) {
                const c = &f.conns.items[client];
                switch (parse(c.inbound.items[c.start..], f.peerEnded(client), .response)) {
                    .whole => |m| {
                        c.closed = true;
                        if (sim.fault(.closed, within)) |fault| return fail(vm, if (fault == .timeout) .Timeout else .Closed);
                        return vm.variant("Ok", &.{try responseValue(vm, c.inbound.items[c.start .. c.start + m.len])});
                    },
                    .failed => |why| {
                        c.closed = true;
                        return fail(vm, why);
                    },
                    .more => if (!try sim.deliverRound(&delivered)) {
                        // Nothing waits: simulated time passes to a delayed send due within the
                        // deadline, and the rounds go on (step 24).
                        if (sim.nextLater()) |at| if (at <= since + within) {
                            sim.wait(@max(at - sim.deadlineNow(), 0));
                            continue;
                        };
                        sim.wait(@max(since + within - sim.deadlineNow(), 0));
                        f.conns.items[client].closed = true;
                        return fail(vm, .Timeout);
                    },
                }
            }
        },
        .serve => unreachable,
    }
}

// ---- tests

test "a request is whole once its body is, and each limit and rule has its error" {
    const whole = parse("GET /hello?name=x HTTP/1.1\r\nHost: a\r\n\r\n", false, .request).whole;
    try std.testing.expectEqualStrings("GET /hello?name=x HTTP/1.1", whole.start);
    try std.testing.expectEqualStrings("Host: a\r\n", whole.headers);
    try std.testing.expect(parse("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhel", false, .request) == .more);
    try std.testing.expectEqualStrings("hello", parse("POST / HTTP/1.1\ncontent-length: 5\n\nhello!", false, .request).whole.body);
    try std.testing.expect(parse("GET / HTTP/1.1\r\n", true, .request).failed == .Closed);
    try std.testing.expect(parse("GET /\r\n\r\n", false, .request).failed == .Malformed);
    try std.testing.expect(parse("GET x HTTP/1.1\r\n\r\n", false, .request).failed == .Malformed);
    try std.testing.expect(parse("GET /?a=%zz HTTP/1.1\r\n\r\n", false, .request).failed == .Malformed);
    try std.testing.expect(parse("GET / HTTP/2.0\r\n\r\n", false, .request).failed == .Unsupported);
    try std.testing.expect(parse("GET / HTTP/1.1\r\nno colon\r\n\r\n", false, .request).failed == .Malformed);
    try std.testing.expect(parse("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n", false, .request).failed == .Unsupported);
    try std.testing.expect(parse("POST / HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n", false, .request).failed == .TooLarge);
    try std.testing.expect(parse("POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n", false, .request).failed == .Malformed);
    const long = try std.testing.allocator.alloc(u8, limit + 2);
    defer std.testing.allocator.free(long);
    @memset(long, 'a');
    try std.testing.expect(parse(long, false, .request).failed == .TooLarge);
    try std.testing.expectEqualStrings("hi", parse("HTTP/1.1 200 OK\r\n\r\nhi", true, .response).whole.body);
    try std.testing.expect(parse("HTTP/1.1 200 OK\r\n\r\nhi", false, .response) == .more);
    try std.testing.expect(parse("HTTP/1.1 99 Low\r\n\r\n", true, .response).failed == .Malformed);
}

test "a query's escapes decode, and a key or value is encoded back" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expect(decodable("a=b%2Fc") and !decodable("a=%2") and !decodable("%"));
    const d = try decode(a, "mo+lang%21");
    try std.testing.expectEqualStrings("mo lang!", d);
    var w: std.ArrayList(u8) = .empty;
    try encode(&w, a, "a b/é");
    try std.testing.expectEqualStrings("a%20b%2F%C3%A9", w.items);
}
