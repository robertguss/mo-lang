//! The TLS brick (steps 36 and 37; mo-wiki/deep-dives/bricks-and-the-cost-of-zero-dependencies.md):
//! TLS 1.3 for both ends of a connection, written once and used by both runtimes, as C-ABI
//! exports over `std.crypto`. Zig 0.16 ships a TLS 1.3 client (`std/crypto/tls/Client.zig`) that
//! owns its own reader and writer, and the record layer's types and key schedule
//! (`std/crypto/tls.zig`); it ships no server, and its client is not an engine a runtime's
//! scheduler can drive. So both halves of RFC 8446 are here, over one record layer. Every AEAD,
//! hash, HKDF, X25519, and signature comes from `std.crypto`: nothing cryptographic here is
//! hand-rolled, only the wire format around it.
//!
//! It is an engine over bytes and holds no socket, no allocator of the runtime's, no clock, and
//! no scheduler: ciphertext goes in with `mo_tls_feed`, plaintext comes out with `mo_tls_read`,
//! plaintext goes in with `mo_tls_write`, and ciphertext comes out with `mo_tls_flush`. So each
//! runtime drives it from its own sockets and its own poller (net.zig, mo_rt.c) and the handshake
//! is written once. A connection has a role: `mo_tls_conn_new` makes a server's, and
//! `mo_tls_connect` a client's; every export after that is the same for both.
//!
//! What it speaks (the bricks page's cut): TLS 1.3 alone, the two suites
//! `TLS_AES_128_GCM_SHA256` and `TLS_CHACHA20_POLY1305_SHA256` (both over SHA-256, so the
//! transcript hash and the key schedule have one shape), X25519 alone for the key exchange with
//! one HelloRetryRequest either way, Ed25519 and ECDSA P-256 certificates, ALPN (RFC 7301) on both
//! sides, post-handshake `KeyUpdate` started by either side, and `close_notify` both ways. The
//! client checks the server's chain up to a root it trusts, with the host name and the dates.
//! Not here, in either direction: TLS 1.2, session tickets (a client reads a server's and drops
//! it), resumption, PSK, 0-RTT, client certificates, renegotiation, OCSP, and RSA anywhere in a
//! chain. The server reads SNI and ignores it.
const std = @import("std");
const builtin = @import("builtin");
const crypto = std.crypto;
const tls = crypto.tls;
const mem = std.mem;

const Sha256 = crypto.hash.sha2.Sha256;
const HmacSha256 = crypto.auth.hmac.sha2.HmacSha256;
const HkdfSha256 = crypto.kdf.hkdf.HkdfSha256;
const Aes128Gcm = crypto.aead.aes_gcm.Aes128Gcm;
const ChaChaPoly = crypto.aead.chacha_poly.ChaCha20Poly1305;
const X25519 = crypto.dh.X25519;
const Ed25519 = crypto.sign.Ed25519;
const EcdsaP256 = crypto.sign.ecdsa.EcdsaP256Sha256;
const Certificate = crypto.Certificate;

/// What an export answers.
pub const ok: c_int = 0;
/// `mo_tls_read`: the records so far held no more plaintext; feed it more ciphertext.
pub const want_more: c_int = 1;
/// `mo_tls_read`: the peer sent `close_notify`, or the connection is finished.
pub const closed: c_int = 2;
/// The handshake or a record was wrong, or the peer sent a fatal alert: the connection is over,
/// `mo_tls_alert` says with which description, and `mo_tls_flush` has the alert to write.
pub const failed: c_int = -1;
/// `mo_tls_server_new`: the certificate or the key does not parse, or they do not match;
/// `mo_tls_client_new`: no root certificate parses.
pub const bad_pem: c_int = -2;
pub const no_memory: c_int = -3;

/// The longest plaintext one record carries (RFC 8446 5.1), and the longest ciphertext record
/// body a peer may send (the plaintext, its content type, and the tag, plus 256 of slack).
pub const max_plaintext = tls.max_ciphertext_inner_record_len;
pub const max_ciphertext = tls.max_ciphertext_len;
const record_header_len = tls.record_header_len;
const tag_len = 16;
const nonce_len = 12;

/// Everything the brick allocates: never the runtime's allocator, since the brick holds a
/// connection's buffers across calls and both runtimes free by calling `mo_tls_conn_free`.
const gpa = std.heap.smp_allocator;

/// Entropy for the handshake's key share and the ServerHello random, from the operating system
/// on every call: `getrandom(2)` on Linux (a system call, no libc), `arc4random_buf(3)` from
/// libSystem on macOS. The crypto brick asks the same way; the two bricks are linked as separate
/// objects, so neither may call the other's exports and each carries these ten lines.
extern "c" fn arc4random_buf(buf: [*]u8, n: usize) void;

fn entropy(bytes: []u8) void {
    switch (builtin.os.tag) {
        .linux => {
            const linux = std.os.linux;
            var i: usize = 0;
            while (i < bytes.len) {
                const rc = linux.getrandom(bytes[i..].ptr, bytes.len - i, 0);
                switch (linux.errno(rc)) {
                    .SUCCESS => i += rc,
                    .INTR => {},
                    // The kernel's pool is always ready after boot; nothing else can fail here.
                    else => @panic("the TLS brick got no entropy from getrandom(2)"),
                }
            }
        },
        .macos, .ios, .tvos, .watchos, .visionos => if (bytes.len > 0) arc4random_buf(bytes.ptr, bytes.len),
        else => @compileError("the TLS brick has no entropy source for this target"),
    }
}

// ---- a growable byte buffer with a consumed head

const Buf = struct {
    data: []u8 = &.{},
    off: usize = 0,
    len: usize = 0,

    fn deinit(b: *Buf) void {
        if (b.data.len > 0) gpa.free(b.data);
        b.* = .{};
    }

    fn slice(b: *const Buf) []u8 {
        return b.data[b.off..b.len];
    }

    fn room(b: *Buf, extra: usize) error{OutOfMemory}![]u8 {
        if (b.off > 0 and b.off == b.len) {
            b.off = 0;
            b.len = 0;
        }
        if (b.data.len - b.len < extra) {
            if (b.off > 0) {
                mem.copyForwards(u8, b.data, b.data[b.off..b.len]);
                b.len -= b.off;
                b.off = 0;
            }
            if (b.data.len - b.len < extra) {
                var size = if (b.data.len == 0) @max(extra, 512) else b.data.len;
                while (size - b.len < extra) size *= 2;
                const grown = try gpa.alloc(u8, size);
                @memcpy(grown[0..b.len], b.data[0..b.len]);
                if (b.data.len > 0) gpa.free(b.data);
                b.data = grown;
            }
        }
        return b.data[b.len..];
    }

    fn append(b: *Buf, bytes: []const u8) error{OutOfMemory}!void {
        const dest = try b.room(bytes.len);
        @memcpy(dest[0..bytes.len], bytes);
        b.len += bytes.len;
    }

    fn consume(b: *Buf, n: usize) void {
        b.off += n;
        if (b.off == b.len) {
            b.off = 0;
            b.len = 0;
            // A buffer at rest holds nothing: an idle connection's cost is its struct.
            if (b.data.len > 4096) {
                gpa.free(b.data);
                b.data = &.{};
            }
        }
    }
};

// ---- reading the wire without running off the end

const Cursor = struct {
    b: []const u8,
    i: usize = 0,

    const Short = error{Short};

    fn take(c: *Cursor, n: usize) Short![]const u8 {
        if (c.b.len - c.i < n) return error.Short;
        defer c.i += n;
        return c.b[c.i..][0..n];
    }

    fn u8_(c: *Cursor) Short!u8 {
        return (try c.take(1))[0];
    }

    fn u16_(c: *Cursor) Short!u16 {
        return mem.readInt(u16, (try c.take(2))[0..2], .big);
    }

    fn u24_(c: *Cursor) Short!u24 {
        return mem.readInt(u24, (try c.take(3))[0..3], .big);
    }

    /// The bytes an 8-, 16-, or 24-bit length prefixes.
    fn vec(c: *Cursor, comptime Len: type) Short![]const u8 {
        const n: usize = switch (Len) {
            u8 => try c.u8_(),
            u16 => try c.u16_(),
            u24 => try c.u24_(),
            else => unreachable,
        };
        return c.take(n);
    }

    fn rest(c: *const Cursor) []const u8 {
        return c.b[c.i..];
    }

    fn done(c: *const Cursor) bool {
        return c.i == c.b.len;
    }
};

fn put16(out: []u8, v: u16) void {
    mem.writeInt(u16, out[0..2], v, .big);
}

// ---- PEM and the keys it holds

/// The base64 bodies of every `-----BEGIN <label>-----` block in `text`, decoded and appended.
fn pemBlocks(text: []const u8, label: []const u8, into: *std.ArrayList([]u8)) !void {
    var head: []const u8 = text;
    var open_buf: [64]u8 = undefined;
    var close_buf: [64]u8 = undefined;
    const open = try std.fmt.bufPrint(&open_buf, "-----BEGIN {s}-----", .{label});
    const close = try std.fmt.bufPrint(&close_buf, "-----END {s}-----", .{label});
    while (mem.indexOf(u8, head, open)) |at| {
        const body_start = at + open.len;
        const end = mem.indexOfPos(u8, head, body_start, close) orelse return error.BadPem;
        const body = head[body_start..end];
        var b64: std.ArrayList(u8) = .empty;
        defer b64.deinit(gpa);
        for (body) |ch| switch (ch) {
            ' ', '\t', '\r', '\n' => {},
            else => try b64.append(gpa, ch),
        };
        const decoder = std.base64.standard.Decoder;
        const size = decoder.calcSizeForSlice(b64.items) catch return error.BadPem;
        const der = try gpa.alloc(u8, size);
        errdefer gpa.free(der);
        decoder.decode(der, b64.items) catch return error.BadPem;
        try into.append(gpa, der);
        head = head[end + close.len ..];
    }
}

/// One DER element: its tag, and its contents.
const Der = struct {
    b: []const u8,
    i: usize = 0,

    const Bad = error{BadDer};

    fn next(d: *Der, want: u8) Bad![]const u8 {
        if (d.i >= d.b.len) return error.BadDer;
        const tag = d.b[d.i];
        if (tag != want) return error.BadDer;
        d.i += 1;
        if (d.i >= d.b.len) return error.BadDer;
        var n: usize = d.b[d.i];
        d.i += 1;
        if (n & 0x80 != 0) {
            const count = n & 0x7f;
            if (count == 0 or count > 4 or d.b.len - d.i < count) return error.BadDer;
            n = 0;
            for (d.b[d.i..][0..count]) |byte| n = n << 8 | byte;
            d.i += count;
        }
        if (d.b.len - d.i < n) return error.BadDer;
        defer d.i += n;
        return d.b[d.i..][0..n];
    }

    fn of(bytes: []const u8) Der {
        return .{ .b = bytes };
    }
};

const seq = 0x30;
const integer = 0x02;
const octet_string = 0x04;
const bit_string = 0x03;
const object_id = 0x06;
const context_1 = 0xa1;

const oid_ed25519 = [_]u8{ 0x2b, 0x65, 0x70 };
const oid_ec_public_key = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01 };
const oid_prime256v1 = [_]u8{ 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07 };

/// The server's signing key: what `openssl req -newkey ed25519` and `-newkey ec` write as
/// PKCS#8 (`BEGIN PRIVATE KEY`), and nothing else.
pub const Key = union(enum) {
    ed25519: Ed25519.KeyPair,
    p256: EcdsaP256.KeyPair,

    fn scheme(k: Key) tls.SignatureScheme {
        return switch (k) {
            .ed25519 => .ed25519,
            .p256 => .ecdsa_secp256r1_sha256,
        };
    }
};

/// A PKCS#8 `PrivateKeyInfo`, Ed25519 or EC P-256.
fn parsePkcs8(der: []const u8) !Key {
    var outer = Der.of(der);
    var info = Der.of(try outer.next(seq));
    _ = try info.next(integer);
    var algo = Der.of(try info.next(seq));
    const oid = try algo.next(object_id);
    const private = try info.next(octet_string);
    if (mem.eql(u8, oid, &oid_ed25519)) {
        var inner = Der.of(private);
        const seed = try inner.next(octet_string);
        if (seed.len != 32) return error.BadDer;
        return .{ .ed25519 = Ed25519.KeyPair.generateDeterministic(seed[0..32].*) catch return error.BadDer };
    }
    if (!mem.eql(u8, oid, &oid_ec_public_key)) return error.BadDer;
    const curve = try algo.next(object_id);
    if (!mem.eql(u8, curve, &oid_prime256v1)) return error.BadDer;
    var ec = Der.of(private);
    var key_seq = Der.of(try ec.next(seq));
    _ = try key_seq.next(integer);
    const scalar = try key_seq.next(octet_string);
    if (scalar.len != 32) return error.BadDer;
    const secret = EcdsaP256.SecretKey.fromBytes(scalar[0..32].*) catch return error.BadDer;
    return .{ .p256 = EcdsaP256.KeyPair.fromSecretKey(secret) catch return error.BadDer };
}

/// A listener's certificate chain and key: no authority beyond its own key, so a program may
/// store one and hand it to every worker.
pub const Server = struct {
    /// The chain as the PEM gave it, leaf first, DER.
    chain: [][]u8,
    key: Key,
    /// ALPN: the protocols this server accepts, in its order of preference; none, and a
    /// client's list goes unanswered.
    protocols: [][]u8 = &.{},
    /// The suite it takes when a client offers both: AES-128-GCM, which has an instruction on
    /// every CPU the runtimes run on. Only a test sets the other, so Zig's own client, which
    /// offers both, can be held to each.
    prefer: Suite = .aes_128_gcm,

    fn deinit(s: *Server) void {
        for (s.chain) |der| gpa.free(der);
        gpa.free(s.chain);
        freeNames(s.protocols);
        gpa.destroy(s);
    }
};

/// A client's trust: the root certificates a server's chain must lead to, parsed from PEM text
/// the program read, and held in memory (the brick reads no files). No authority beyond that.
pub const Client = struct {
    /// Every root the PEM held that parses, DER.
    trust: [][]u8,
    /// ALPN: the protocols this client offers, in order; none, and it offers nothing.
    protocols: [][]u8 = &.{},

    fn deinit(cl: *Client) void {
        for (cl.trust) |der| gpa.free(der);
        gpa.free(cl.trust);
        freeNames(cl.protocols);
        gpa.destroy(cl);
    }
};

// ---- ALPN's names (RFC 7301): what the runtimes pass as NUL-separated text

/// The names in `text`, each ended by a NUL or by the text's end; empty names are skipped. A name
/// is 1 to 255 bytes, and the whole list must fit one extension.
fn parseNames(text: []const u8) error{ OutOfMemory, BadName }![][]u8 {
    var list: std.ArrayList([]u8) = .empty;
    errdefer {
        for (list.items) |n| gpa.free(n);
        list.deinit(gpa);
    }
    var total: usize = 0;
    var it = mem.splitScalar(u8, text, 0);
    while (it.next()) |name| {
        if (name.len == 0) continue;
        if (name.len > 255) return error.BadName;
        total += 1 + name.len;
        if (total > 0xff00) return error.BadName;
        try list.append(gpa, try gpa.dupe(u8, name));
    }
    return list.toOwnedSlice(gpa);
}

fn freeNames(names: [][]u8) void {
    for (names) |n| gpa.free(n);
    if (names.len > 0) gpa.free(names);
}

fn dupeList(list: []const []u8) error{OutOfMemory}![][]u8 {
    const out = try gpa.alloc([]u8, list.len);
    var done: usize = 0;
    errdefer {
        for (out[0..done]) |d| gpa.free(d);
        gpa.free(out);
    }
    for (list, 0..) |item, i| {
        out[i] = try gpa.dupe(u8, item);
        done += 1;
    }
    return out;
}

/// An ALPN extension's body: the list of names, each 8-bit-length prefixed, 16-bit-length
/// prefixed. `null` when it does not parse or holds an empty name.
fn alpnNames(body: []const u8, into: *[64][]const u8) ?[]const []const u8 {
    var cur: Cursor = .{ .b = body };
    var list: Cursor = .{ .b = cur.vec(u16) catch return null };
    if (!cur.done() or list.done()) return null;
    var n: usize = 0;
    while (!list.done()) {
        const name = list.vec(u8) catch return null;
        if (name.len == 0) return null;
        // Past sixty-four names the rest are not read: no server's list is that long.
        if (n < into.len) {
            into[n] = name;
            n += 1;
        }
    }
    return into[0..n];
}

// ---- a certificate's shape, checked before std.crypto.Certificate reads it
//
// `Certificate.parse` and `der.Element.parse` index the bytes without a bound (they were written
// for the operating system's own trust store), so a server that sends a malformed certificate
// could panic them. Every certificate the brick hands them, off the wire or out of a trust PEM,
// is first walked here: every element inside its parent, and the exact shape `parse` walks,
// so that each element it reads exists.

const Tlv = struct { tag: u8, start: usize, end: usize };

fn tlvAt(b: []const u8, at: usize, limit: usize) ?Tlv {
    if (at >= limit or limit - at < 2) return null;
    const tag = b[at];
    // High tag numbers never appear in a certificate this brick takes.
    if (tag & 0x1f == 0x1f) return null;
    var i = at + 1;
    var n: usize = b[i];
    i += 1;
    if (n & 0x80 != 0) {
        const k = n & 0x7f;
        if (k == 0 or k > 3 or limit - i < k) return null;
        n = 0;
        for (b[i..][0..k]) |x| n = n << 8 | x;
        i += k;
    }
    if (n > limit - i) return null;
    return .{ .tag = tag, .start = i, .end = i + n };
}

/// Every element in `start..end`, and inside every constructed one, fits where it is.
fn derTree(b: []const u8, start: usize, end: usize, depth: u8) bool {
    if (depth > 12) return false;
    var i = start;
    while (i < end) {
        const e = tlvAt(b, i, end) orelse return false;
        if (e.tag & 0x20 != 0 and !derTree(b, e.start, e.end, depth + 1)) return false;
        i = e.end;
    }
    return true;
}

/// The children of `parent`, at most `out.len` of them; `null` when there are more.
fn kids(b: []const u8, parent: Tlv, out: []Tlv) ?[]Tlv {
    var n: usize = 0;
    var i = parent.start;
    while (i < parent.end) {
        if (n == out.len) return null;
        out[n] = tlvAt(b, i, parent.end) orelse return null;
        i = out[n].end;
        n += 1;
    }
    return out[0..n];
}

fn certShape(b: []const u8) bool {
    if (b.len > 0xffff_ff or !derTree(b, 0, b.len, 0)) return false;
    const cert = tlvAt(b, 0, b.len) orelse return false;
    if (cert.tag != 0x30 or cert.end != b.len) return false;
    var top_buf: [3]Tlv = undefined;
    const top = kids(b, cert, &top_buf) orelse return false;
    if (top.len != 3 or top[0].tag != 0x30 or top[1].tag != 0x30 or top[2].tag != 0x03) return false;
    if (top[2].end == top[2].start) return false;
    var alg_buf: [2]Tlv = undefined;
    const alg = kids(b, top[1], &alg_buf) orelse return false;
    if (alg.len == 0 or alg[0].tag != 0x06) return false;

    var tbs_buf: [12]Tlv = undefined;
    const tbs = kids(b, top[0], &tbs_buf) orelse return false;
    const v: usize = if (tbs.len > 0 and tbs[0].tag == 0xa0) 1 else 0;
    if (tbs.len < v + 6) return false;
    const validity = tbs[v + 3];
    const subject = tbs[v + 4];
    const spki = tbs[v + 5];
    if (tbs[v].tag != 0x02 or tbs[v + 2].tag != 0x30 or validity.tag != 0x30 or subject.tag != 0x30 or spki.tag != 0x30) return false;
    var when_buf: [2]Tlv = undefined;
    const when = kids(b, validity, &when_buf) orelse return false;
    if (when.len != 2) return false;
    // The subject: RDN sets of attribute pairs, read two elements at a time.
    var rdn_buf: [32]Tlv = undefined;
    for (kids(b, subject, &rdn_buf) orelse return false) |rdn| {
        if (rdn.tag != 0x31) return false;
        var atav_buf: [8]Tlv = undefined;
        for (kids(b, rdn, &atav_buf) orelse return false) |atav| {
            if (atav.tag != 0x30) return false;
            var pair_buf: [2]Tlv = undefined;
            const pair = kids(b, atav, &pair_buf) orelse return false;
            if (pair.len != 2) return false;
        }
    }
    var key_buf: [2]Tlv = undefined;
    const key = kids(b, spki, &key_buf) orelse return false;
    if (key.len != 2 or key[0].tag != 0x30 or key[1].tag != 0x03 or key[1].end == key[1].start) return false;
    var key_alg_buf: [2]Tlv = undefined;
    const key_alg = kids(b, key[0], &key_alg_buf) orelse return false;
    if (key_alg.len == 0 or key_alg[0].tag != 0x06) return false;
    // `parse` reads a curve after an EC key's algorithm.
    if (mem.eql(u8, b[key_alg[0].start..key_alg[0].end], &oid_ec_public_key) and key_alg.len != 2) return false;

    // After the key: the extensions, and nothing else (`parse` reads only the element there).
    const rest = tbs[v + 6 ..];
    if (rest.len > 1) return false;
    if (rest.len == 1) {
        if (rest[0].tag != 0xa3) return false;
        var outer_buf: [1]Tlv = undefined;
        const outer = kids(b, rest[0], &outer_buf) orelse return false;
        if (outer.len != 1 or outer[0].tag != 0x30) return false;
        var ext_buf: [32]Tlv = undefined;
        for (kids(b, outer[0], &ext_buf) orelse return false) |ext| {
            if (ext.tag != 0x30) return false;
            var part_buf: [3]Tlv = undefined;
            const part = kids(b, ext, &part_buf) orelse return false;
            if (part.len < 2 or part[0].tag != 0x06) return false;
            if (part[1].tag == 0x01 and part.len != 3) return false;
        }
    }
    return true;
}

// ---- the chain a client checks

const oid_basic_constraints = [_]u8{ 0x55, 0x1d, 0x13 };
/// The most certificates a server's chain may hold, the leaf among them.
pub const max_chain = 5;

/// The extension with `oid` in a certificate `certShape` has passed: its value's bytes.
fn extensionValue(b: []const u8, oid: []const u8) ?[]const u8 {
    const cert = tlvAt(b, 0, b.len).?;
    var top_buf: [3]Tlv = undefined;
    const top = kids(b, cert, &top_buf).?;
    var tbs_buf: [12]Tlv = undefined;
    const tbs = kids(b, top[0], &tbs_buf).?;
    const last = tbs[tbs.len - 1];
    if (last.tag != 0xa3) return null;
    var outer_buf: [1]Tlv = undefined;
    const outer = kids(b, last, &outer_buf).?;
    var ext_buf: [32]Tlv = undefined;
    for (kids(b, outer[0], &ext_buf).?) |ext| {
        var part_buf: [3]Tlv = undefined;
        const part = kids(b, ext, &part_buf).?;
        if (!mem.eql(u8, b[part[0].start..part[0].end], oid)) continue;
        const value = part[part.len - 1];
        if (value.tag != 0x04) return null;
        return b[value.start..value.end];
    }
    return null;
}

/// Whether a certificate may sign others: basicConstraints with cA true (RFC 5280 4.2.1.9).
/// A certificate without the extension is not a CA.
fn isCa(der_bytes: []const u8) bool {
    const value = extensionValue(der_bytes, &oid_basic_constraints) orelse return false;
    const bc = tlvAt(value, 0, value.len) orelse return false;
    if (bc.tag != 0x30 or bc.end != value.len or bc.start == bc.end) return false;
    const first = tlvAt(value, bc.start, bc.end) orelse return false;
    return first.tag == 0x01 and first.end - first.start == 1 and value[first.start] != 0;
}

fn isRsa(p: Certificate.Parsed) bool {
    return switch (p.signature_algorithm) {
        .sha1WithRSAEncryption, .sha224WithRSAEncryption, .sha256WithRSAEncryption, .sha384WithRSAEncryption, .sha512WithRSAEncryption, .md2WithRSAEncryption, .md5WithRSAEncryption => true,
        else => p.pub_key_algo == .rsaEncryption or p.pub_key_algo == .rsassa_pss,
    };
}

/// A certificate `certShape` has passed, parsed; an algorithm `parse` does not know is
/// `unsupported_certificate`, anything else wrong `bad_certificate`.
fn parseCert(der_bytes: []const u8) error{ Unsupported, Bad }!Certificate.Parsed {
    if (!certShape(der_bytes)) return error.Bad;
    const cert: Certificate = .{ .buffer = der_bytes, .index = 0 };
    return cert.parse() catch |err| switch (err) {
        error.CertificateHasUnrecognizedObjectId => error.Unsupported,
        else => error.Bad,
    };
}

/// RFC 6125's rule as Zig's `verifyHostName` writes it: the name exactly, ignoring case, or one
/// leftmost wildcard label.
fn hostMatches(host: []const u8, name: []const u8) bool {
    if (host.len == 0 or name.len == 0) return false;
    if (std.ascii.eqlIgnoreCase(name, host)) return true;
    if (name.len >= 3 and mem.startsWith(u8, name, "*.")) {
        const suffix = name[2..];
        if (mem.indexOfScalar(u8, suffix, '*') != null) return false;
        const dot = mem.indexOfScalar(u8, host, '.') orelse return false;
        return std.ascii.eqlIgnoreCase(suffix, host[dot + 1 ..]);
    }
    return false;
}

/// The address `host` spells, four bytes or sixteen, or none when it is a name.
fn hostAddress(host: []const u8, out: *[16]u8) ?[]const u8 {
    if (std.Io.net.Ip4Address.parse(host, 0)) |a| {
        out[0..4].* = a.bytes;
        return out[0..4];
    } else |_| {}
    if (std.Io.net.Ip6Address.parse(host, 0)) |a| {
        out.* = a.bytes;
        return out[0..16];
    } else |_| {}
    return null;
}

/// The leaf is for `host`: a DNS name or an IP address in its subject alternative names, or,
/// when it has none, its common name (Zig's `verifyHostName`, which reads DNS names alone, plus
/// the addresses RFC 6125 6.2.1 checks when the host is an IP literal).
fn leafIsFor(leaf: Certificate.Parsed, host: []const u8) bool {
    var addr_buf: [16]u8 = undefined;
    const addr = hostAddress(host, &addr_buf);
    const san = leaf.subjectAltName();
    if (san.len == 0) return hostMatches(host, leaf.commonName());
    const names = tlvAt(san, 0, san.len) orelse return false;
    if (names.tag != 0x30 or names.end != san.len) return false;
    var i = names.start;
    while (i < names.end) {
        const name = tlvAt(san, i, names.end) orelse return false;
        i = name.end;
        const value = san[name.start..name.end];
        switch (name.tag) {
            // dNSName, [2] IA5String: never matched by an address.
            0x82 => if (addr == null and hostMatches(host, value)) return true,
            // iPAddress, [7] OCTET STRING: four bytes or sixteen.
            0x87 => if (addr) |a| {
                if (mem.eql(u8, a, value)) return true;
            },
            else => {},
        }
    }
    return false;
}

/// The whole check a client makes of the chain a server sent, leaf first, before it reads the
/// CertificateVerify: at most `max_chain` certificates (a longer chain is `unknown_ca`); no RSA anywhere (the cut); each one's
/// issuer the next one sent, until one's issuer is a root in `trust`; every issuer in the chain
/// a CA; the leaf for `host`; every signature good; and every certificate's dates, the root's
/// too, around `now`. The answer is the alert RFC 8446 6.2 names, or null for a good chain.
fn checkChain(chain: []const []const u8, trust: []const []u8, host: []const u8, now: i64) ?tls.Alert.Description {
    if (chain.len == 0) return .decode_error;
    // A chain past the depth is `unknown_ca`, as OpenSSL answers one (its
    // X509_V_ERR_CERT_CHAIN_TOO_LONG): no root was reached within the depth.
    if (chain.len > max_chain) return .unknown_ca;
    var parsed: [max_chain]Certificate.Parsed = undefined;
    for (chain, 0..) |der_bytes, i| {
        parsed[i] = parseCert(der_bytes) catch |err| return switch (err) {
            error.Unsupported => .unsupported_certificate,
            error.Bad => .bad_certificate,
        };
        if (isRsa(parsed[i])) return .unsupported_certificate;
    }

    // The path as sent: each certificate's issuer the next, up to the first a root signed.
    var last: usize = 0;
    var root: ?Certificate.Parsed = null;
    while (true) : (last += 1) {
        for (trust) |r| {
            const p = parseCert(r) catch continue;
            if (!mem.eql(u8, p.subject(), parsed[last].issuer())) continue;
            if (isRsa(p)) return .unsupported_certificate;
            // A root with the right name and the wrong key is not this chain's.
            signedBy(parsed[last], p) catch continue;
            root = p;
            break;
        }
        if (root != null) break;
        if (last + 1 >= chain.len) return .unknown_ca;
        if (!mem.eql(u8, parsed[last].issuer(), parsed[last + 1].subject())) return .unknown_ca;
    }
    for (chain[1 .. last + 1]) |issuer| if (!isCa(issuer)) return .unknown_ca;
    if (!leafIsFor(parsed[0], host)) return .bad_certificate;

    // From the top down, as OpenSSL's `internal_verify` goes: each certificate's signature, then
    // its dates; the root's dates first.
    const r = root.?;
    if (datesOf(r, now)) |desc| return desc;
    var j: usize = last + 1;
    while (j > 0) {
        j -= 1;
        signedBy(parsed[j], if (j == last) r else parsed[j + 1]) catch |err| return switch (err) {
            error.Unsupported => .unsupported_certificate,
            error.Bad => .bad_certificate,
        };
        if (datesOf(parsed[j], now)) |desc| return desc;
    }
    return null;
}

fn datesOf(p: Certificate.Parsed, now: i64) ?tls.Alert.Description {
    if (now < 0 or @as(u64, @intCast(now)) < p.validity.not_before) return .bad_certificate;
    if (@as(u64, @intCast(now)) > p.validity.not_after) return .certificate_expired;
    return null;
}

/// `subject` was signed by `issuer`'s key, with an algorithm the cut covers: Ed25519, or ECDSA
/// P-256 with SHA-256; anything else is `unsupported_certificate`. Zig's `Parsed.verify` is not
/// called: it holds RSA's verification for every modulus size and hash, which the cut refuses,
/// and with P-384 beside P-256 the brick took 14.4 s to compile against 8.6 s for step 36's (this
/// function, P-256 alone: 10.2 s). Every `mo build` with a cold cache compiles the brick.
fn signedBy(subject: Certificate.Parsed, issuer: Certificate.Parsed) error{ Unsupported, Bad }!void {
    if (!mem.eql(u8, subject.issuer(), issuer.subject())) return error.Bad;
    const message = subject.message();
    const sig = subject.signature();
    const key = issuer.pubKey();
    switch (subject.signature_algorithm) {
        .curveEd25519 => {
            if (issuer.pub_key_algo != .curveEd25519 or sig.len != 64 or key.len != 32) return error.Bad;
            const pk = Ed25519.PublicKey.fromBytes(key[0..32].*) catch return error.Bad;
            Ed25519.Signature.fromBytes(sig[0..64].*).verify(message, pk) catch return error.Bad;
        },
        .ecdsa_with_SHA256 => {
            const curve = switch (issuer.pub_key_algo) {
                .X9_62_id_ecPublicKey => |cv| cv,
                else => return error.Bad,
            };
            if (curve != .X9_62_prime256v1) return error.Unsupported;
            const s = EcdsaP256.Signature.fromDer(sig) catch return error.Bad;
            const pk = EcdsaP256.PublicKey.fromSec1(key) catch return error.Bad;
            s.verify(message, pk) catch return error.Bad;
        },
        else => return error.Unsupported,
    }
}

/// The leaf certificate's public key must be the private key's: a chain and a key from two
/// different pairs is `BadPem`, not a handshake every client rejects.
fn keyMatchesLeaf(leaf: []const u8, key: Key) bool {
    if (!certShape(leaf)) return false;
    const cert: Certificate = .{ .buffer = leaf, .index = 0 };
    const parsed = cert.parse() catch return false;
    const pub_key = parsed.pubKey();
    return switch (key) {
        .ed25519 => |kp| parsed.pub_key_algo == .curveEd25519 and
            mem.eql(u8, pub_key, &kp.public_key.toBytes()),
        .p256 => |kp| parsed.pub_key_algo == .X9_62_id_ecPublicKey and
            parsed.pub_key_algo.X9_62_id_ecPublicKey == .X9_62_prime256v1 and
            mem.eql(u8, pub_key, &kp.public_key.toUncompressedSec1()),
    };
}

// ---- the suites: both over SHA-256, so only the AEAD differs

pub const Suite = enum {
    aes_128_gcm,
    chacha20_poly1305,

    fn tag(s: Suite) tls.CipherSuite {
        return switch (s) {
            .aes_128_gcm => .AES_128_GCM_SHA256,
            .chacha20_poly1305 => .CHACHA20_POLY1305_SHA256,
        };
    }

    fn keyLen(s: Suite) usize {
        return switch (s) {
            .aes_128_gcm => Aes128Gcm.key_length,
            .chacha20_poly1305 => ChaChaPoly.key_length,
        };
    }
};

/// One direction's record protection: the key, the IV, and the records already sent or read.
const Cipher = struct {
    secret: [32]u8 = @splat(0),
    key: [32]u8 = @splat(0),
    iv: [nonce_len]u8 = @splat(0),
    seq: u64 = 0,

    /// The key's length is part of the label HKDF expands, so each suite asks for its own.
    fn derive(c: *Cipher, suite: Suite, secret: [32]u8) void {
        c.secret = secret;
        c.key = @splat(0);
        switch (suite) {
            .aes_128_gcm => c.key[0..Aes128Gcm.key_length].* = tls.hkdfExpandLabel(HkdfSha256, secret, "key", "", Aes128Gcm.key_length),
            .chacha20_poly1305 => c.key[0..ChaChaPoly.key_length].* = tls.hkdfExpandLabel(HkdfSha256, secret, "key", "", ChaChaPoly.key_length),
        }
        c.iv = tls.hkdfExpandLabel(HkdfSha256, secret, "iv", "", nonce_len);
        c.seq = 0;
    }

    /// RFC 8446 7.2: the next secret is the old one expanded with "traffic upd".
    fn update(c: *Cipher, suite: Suite) void {
        c.derive(suite, tls.hkdfExpandLabel(HkdfSha256, c.secret, "traffic upd", "", 32));
    }

    fn nonce(c: *const Cipher) [nonce_len]u8 {
        var n = c.iv;
        var counter: [8]u8 = undefined;
        mem.writeInt(u64, &counter, c.seq, .big);
        for (n[nonce_len - 8 ..], counter) |*b, x| b.* ^= x;
        return n;
    }

    fn seal(c: *Cipher, suite: Suite, out: []u8, tag: *[tag_len]u8, plain: []const u8, ad: []const u8) void {
        const n = c.nonce();
        switch (suite) {
            .aes_128_gcm => Aes128Gcm.encrypt(out, tag, plain, ad, n, c.key[0..Aes128Gcm.key_length].*),
            .chacha20_poly1305 => ChaChaPoly.encrypt(out, tag, plain, ad, n, c.key[0..ChaChaPoly.key_length].*),
        }
        c.seq += 1;
    }

    fn open(c: *Cipher, suite: Suite, out: []u8, ciphertext: []const u8, tag: [tag_len]u8, ad: []const u8) bool {
        const n = c.nonce();
        switch (suite) {
            .aes_128_gcm => Aes128Gcm.decrypt(out, ciphertext, tag, ad, n, c.key[0..Aes128Gcm.key_length].*) catch return false,
            .chacha20_poly1305 => ChaChaPoly.decrypt(out, ciphertext, tag, ad, n, c.key[0..ChaChaPoly.key_length].*) catch return false,
        }
        c.seq += 1;
        return true;
    }
};

// ---- the connection: a state machine over bytes

pub const Role = enum { server, client };

const Phase = enum {
    // The server's handshake.
    /// Nothing read yet: the next handshake message must be a ClientHello.
    hello,
    /// A HelloRetryRequest went out: the next must be the second ClientHello, and no third.
    retried,
    /// Our Finished went out: the client's Finished is what is left.
    wait_finished,

    // The client's handshake.
    /// The ClientHello went out: a ServerHello or one HelloRetryRequest is next.
    wait_server_hello,
    /// The handshake keys are up: EncryptedExtensions, Certificate, CertificateVerify,
    /// Finished, in that order.
    wait_encrypted_extensions,
    wait_certificate,
    wait_certificate_verify,
    wait_server_finished,

    /// The handshake is done; records carry the program's bytes.
    running,
    /// `close_notify` came, or the stream ended.
    over,
    /// An alert went out (or came in fatal): nothing more is read or written.
    broken,
};

/// What only a test may set: the client's entropy (the RFC 8448 replay injects the trace's), a
/// ClientHello laid out as the trace's, a client that sends no key share (so a brick server
/// answers a HelloRetryRequest), and a client that takes a server's certificate unchecked (the
/// trace's is RSA, outside the cut). In any other build it is empty and every use of it is
/// compiled away.
pub const TestHooks = if (builtin.is_test) struct {
    random: ?[32]u8 = null,
    x25519_secret: ?[32]u8 = null,
    session_id: ?[]const u8 = null,
    no_share: bool = false,
    skip_auth: bool = false,
    hello: ?HelloLayout = null,
    /// Every handshake message this side sends, as it goes out: how the fuzz driver
    /// (bench/step37/fuzz.zig) records the plaintext its corpus mutates.
    sent: ?*const fn (ctx: *anyopaque, message: []const u8) void = null,
    ctx: ?*anyopaque = null,
} else struct {};

/// A ClientHello's suites and extensions as given, with the client's own key share written
/// between `before_share` and `after_share`: how the RFC 8448 trace lays its hello out.
pub const HelloLayout = struct {
    suites: []const u8,
    before_share: []const u8,
    after_share: []const u8,
};

/// A handshake message or record being written, its lengths filled in when it is closed.
const Msg = struct {
    b: std.ArrayList(u8) = .empty,

    fn deinit(m: *Msg) void {
        m.b.deinit(gpa);
    }

    fn bytes(m: *Msg, x: []const u8) error{OutOfMemory}!void {
        try m.b.appendSlice(gpa, x);
    }

    fn int(m: *Msg, comptime T: type, v: T) error{OutOfMemory}!void {
        var buf: [@divExact(@typeInfo(T).int.bits, 8)]u8 = undefined;
        mem.writeInt(T, &buf, v, .big);
        try m.bytes(&buf);
    }

    /// A length of type `T` to be filled in by `close`.
    fn open(m: *Msg, comptime T: type) error{OutOfMemory}!usize {
        const at = m.b.items.len;
        try m.int(T, 0);
        return at;
    }

    fn close(m: *Msg, comptime T: type, at: usize) void {
        const size = @divExact(@typeInfo(T).int.bits, 8);
        mem.writeInt(T, m.b.items[at..][0..size], @intCast(m.b.items.len - at - size), .big);
    }
};

pub const Conn = struct {
    role: Role = .server,
    /// The server's chain and key, for a server's connection.
    server: ?*Server = null,
    /// The client's trust and ALPN list, for a client's connection.
    client: ?*Client = null,
    phase: Phase = .hello,
    suite: Suite = .aes_128_gcm,
    /// Ciphertext fed in and not yet a whole record.
    in: Buf = .{},
    /// Plaintext the records held, waiting for `mo_tls_read`.
    plain: Buf = .{},
    /// Ciphertext waiting for `mo_tls_flush`.
    out: Buf = .{},
    /// A handshake message read across records, or being read now.
    hs: Buf = .{},
    transcript: Sha256 = Sha256.init(.{}),
    /// The X25519 key pair of this handshake, until the shared secret is taken.
    secret_key: [32]u8 = @splat(0),
    public_key: [32]u8 = @splat(0),
    handshake_secret: [32]u8 = @splat(0),
    master_secret: [32]u8 = @splat(0),
    client_finished_key: [32]u8 = @splat(0),
    server_finished_key: [32]u8 = @splat(0),
    read_cipher: Cipher = .{},
    write_cipher: Cipher = .{},
    /// Before the first ServerHello no record is protected.
    encrypting: bool = false,
    decrypting: bool = false,
    /// The legacy session id: the client's, echoed back by the server (middlebox compatibility).
    session_id: [32]u8 = @splat(0),
    session_id_len: u8 = 0,
    /// The client's random, and whether it has had its one HelloRetryRequest.
    client_random: [32]u8 = @splat(0),
    retried: bool = false,
    /// Whether this side's one middlebox-compatibility change_cipher_spec has gone out.
    sent_ccs: bool = false,
    /// A client's: the name it checks the leaf against (and sends as SNI when it is not an
    /// address), and the moment the chain's dates are checked at.
    host: []u8 = &.{},
    now: i64 = 0,
    /// The server's leaf key, read from its Certificate for the CertificateVerify.
    peer_key: [65]u8 = @splat(0),
    peer_key_len: u8 = 0,
    peer_key_ed25519: bool = false,
    /// The ALPN protocol agreed, empty for none.
    protocol: [255]u8 = @splat(0),
    protocol_len: u8 = 0,
    /// The alert this connection ended on, or 255 for none; `alert_from_peer` says whether the
    /// peer sent it or this side did.
    alert: u8 = 255,
    alert_from_peer: bool = false,
    sent_close_notify: bool = false,
    /// KeyUpdates this side sent and read, for the differential run's log.
    key_updates_sent: u32 = 0,
    key_updates_read: u32 = 0,
    /// Set by a message after which the peer's next record must start under new keys.
    keys_changed: bool = false,
    /// A client's handshake ended on the server's chain: its root, a name, a date, the depth,
    /// or an algorithm outside the cut (`Untrusted` in the rows).
    untrusted: bool = false,
    hooks: TestHooks = .{},

    fn deinit(c: *Conn) void {
        c.in.deinit();
        c.plain.deinit();
        c.out.deinit();
        c.hs.deinit();
        if (c.host.len > 0) gpa.free(c.host);
        crypto.secureZero(u8, &c.secret_key);
        crypto.secureZero(u8, &c.handshake_secret);
        crypto.secureZero(u8, &c.master_secret);
        crypto.secureZero(u8, &c.read_cipher.key);
        crypto.secureZero(u8, &c.write_cipher.key);
        crypto.secureZero(u8, &c.read_cipher.secret);
        crypto.secureZero(u8, &c.write_cipher.secret);
        gpa.destroy(c);
    }

    const Fail = error{ Alert, OutOfMemory };

    /// Ends the connection with `desc`: the alert goes out as the last record, and every later
    /// call is `failed`.
    fn fatal(c: *Conn, desc: tls.Alert.Description) Fail {
        if (c.phase != .broken) {
            c.alert = @intFromEnum(desc);
            c.alert_from_peer = false;
            const body = [2]u8{ @intFromEnum(tls.Alert.Level.fatal), @intFromEnum(desc) };
            c.compatCcs() catch {};
            c.sendRecord(.alert, &body) catch {};
            c.phase = .broken;
        }
        return error.Alert;
    }

    fn handshaking(c: *const Conn) bool {
        return switch (c.phase) {
            .running, .over, .broken => false,
            else => true,
        };
    }

    // ---- writing records

    /// One record: protected when the keys are up, plain before that. A change_cipher_spec is
    /// never protected.
    fn sendRecord(c: *Conn, inner: tls.ContentType, payload: []const u8) Fail!void {
        std.debug.assert(payload.len <= max_plaintext);
        if (!c.encrypting or inner == .change_cipher_spec) {
            const dest = try c.out.room(record_header_len + payload.len);
            dest[0] = @intFromEnum(inner);
            dest[1] = 0x03;
            // A client's plain records carry the version of its first hello, as RFC 8446 5.1
            // allows and every client does; a server's say TLS 1.2.
            dest[2] = if (c.role == .client and inner != .change_cipher_spec) 0x01 else 0x03;
            put16(dest[3..5], @intCast(payload.len));
            @memcpy(dest[record_header_len..][0..payload.len], payload);
            c.out.len += record_header_len + payload.len;
            return;
        }
        // TLSInnerPlaintext: the payload, its real content type, no padding.
        const body_len = payload.len + 1 + tag_len;
        const dest = try c.out.room(record_header_len + body_len);
        dest[0] = @intFromEnum(tls.ContentType.application_data);
        dest[1] = 0x03;
        dest[2] = 0x03;
        put16(dest[3..5], @intCast(body_len));
        const header = dest[0..record_header_len];
        var inner_buf = dest[record_header_len..][0 .. payload.len + 1];
        @memcpy(inner_buf[0..payload.len], payload);
        inner_buf[payload.len] = @intFromEnum(inner);
        const tag = dest[record_header_len + payload.len + 1 ..][0..tag_len];
        c.write_cipher.seal(c.suite, inner_buf, tag, inner_buf, header);
        c.out.len += record_header_len + body_len;
    }

    /// A handshake message, fragmented across records at the record limit.
    fn sendHandshake(c: *Conn, bytes: []const u8) Fail!void {
        c.transcript.update(bytes);
        try c.sendUntracked(bytes);
    }

    /// A handshake message that is not part of the transcript (a KeyUpdate).
    fn sendUntracked(c: *Conn, bytes: []const u8) Fail!void {
        if (builtin.is_test) if (c.hooks.sent) |f| f(c.hooks.ctx.?, bytes);
        var at: usize = 0;
        while (at < bytes.len) {
            const n = @min(max_plaintext, bytes.len - at);
            try c.sendRecord(.handshake, bytes[at..][0..n]);
            at += n;
        }
    }

    /// A client that sent a legacy session id sends one change_cipher_spec before its first
    /// protected record or its second hello (RFC 8446 D.4); the server sends its own after its
    /// first hello.
    fn compatCcs(c: *Conn) Fail!void {
        if (c.role != .client or c.sent_ccs or c.session_id_len == 0) return;
        if (!c.encrypting and !c.retried) return;
        c.sent_ccs = true;
        try c.sendRecord(.change_cipher_spec, &.{1});
    }

    // ---- reading records

    /// Every whole record `in` holds. `Short` is not an error: it means feed more.
    fn pump(c: *Conn) Fail!void {
        while (c.phase != .broken and c.phase != .over) {
            const avail = c.in.slice();
            if (avail.len < record_header_len) return;
            const ct: tls.ContentType = @enumFromInt(avail[0]);
            const len = mem.readInt(u16, avail[3..5], .big);
            switch (ct) {
                .handshake, .alert, .application_data, .change_cipher_spec => {},
                // A peer that is not speaking TLS at all: a plain HTTP request starts 'G', a
                // plain HTTP response 'H'.
                else => return c.fatal(.unexpected_message),
            }
            if (len > max_ciphertext) return c.fatal(.record_overflow);
            if (avail.len < record_header_len + len) return;
            const header = avail[0..record_header_len];
            const body = avail[record_header_len..][0..len];
            try c.record(ct, header, body);
            c.in.consume(record_header_len + len);
        }
    }

    fn record(c: *Conn, ct: tls.ContentType, header: []const u8, body: []const u8) Fail!void {
        // A change_cipher_spec is the middlebox-compatibility no-op and is never protected; it
        // has no place once the handshake is done.
        if (ct == .change_cipher_spec) {
            if (body.len != 1 or body[0] != 1 or !c.handshaking()) return c.fatal(.unexpected_message);
            return;
        }
        // An alert in the clear during the handshake: a peer that gave up before it had keys,
        // or before it installed them (OpenSSL's client refuses a chain that way).
        if (ct == .alert and c.handshaking()) return c.peerAlert(body);
        if (!c.decrypting) {
            if (ct != .handshake) return c.fatal(.unexpected_message);
            return c.handshakeBytes(body);
        }
        if (ct != .application_data) return c.fatal(.unexpected_message);
        if (body.len < tag_len + 1) return c.fatal(.bad_record_mac);
        const ciphertext_len = body.len - tag_len;
        if (ciphertext_len > max_plaintext + 1) return c.fatal(.record_overflow);
        // Every record is decrypted onto the tail of `plain`; a handshake or alert record is
        // taken off it again, so only the program's bytes stay.
        const dest = try c.plain.room(ciphertext_len);
        const tag: [tag_len]u8 = body[ciphertext_len..][0..tag_len].*;
        if (!c.read_cipher.open(c.suite, dest[0..ciphertext_len], body[0..ciphertext_len], tag, header))
            return c.fatal(.bad_record_mac);
        // TLSInnerPlaintext: the content, its type, then zero padding.
        const cleartext = mem.trimEnd(u8, dest[0..ciphertext_len], "\x00");
        if (cleartext.len == 0) return c.fatal(.unexpected_message);
        const inner: tls.ContentType = @enumFromInt(cleartext[cleartext.len - 1]);
        const content = cleartext[0 .. cleartext.len - 1];
        switch (inner) {
            .application_data => {
                if (c.phase != .running) return c.fatal(.unexpected_message);
                c.plain.len += content.len;
            },
            .handshake => {
                if (content.len == 0) return c.fatal(.unexpected_message);
                try c.handshakeBytes(content);
            },
            .alert => try c.peerAlert(content),
            else => return c.fatal(.unexpected_message),
        }
    }

    /// An alert from the peer: `close_notify` (or `user_canceled`) ends the stream, anything else
    /// ends the connection and nothing goes back.
    fn peerAlert(c: *Conn, content: []const u8) Fail!void {
        if (content.len != 2) return c.fatal(.decode_error);
        const desc: tls.Alert.Description = @enumFromInt(content[1]);
        c.alert = content[1];
        c.alert_from_peer = true;
        if (desc == .close_notify or desc == .user_canceled) {
            c.phase = .over;
            return;
        }
        c.phase = .broken;
    }

    /// Handshake bytes, which may be part of a message or several: whole ones are dispatched.
    /// Public for the fuzz driver, which feeds it plaintext behind the record layer's AEAD.
    pub fn handshakeBytes(c: *Conn, bytes: []const u8) Fail!void {
        try c.hs.append(bytes);
        while (c.phase != .broken) {
            const held = c.hs.slice();
            if (held.len < 4) break;
            const len = mem.readInt(u24, held[1..4], .big);
            if (len > max_plaintext) return c.fatal(.record_overflow);
            if (held.len < 4 + len) break;
            const kind: tls.HandshakeType = @enumFromInt(held[0]);
            const whole = held[0 .. 4 + len];
            c.keys_changed = false;
            try c.message(kind, whole);
            c.hs.consume(4 + len);
            // RFC 8446 5.1: a message after which the keys change ends its record.
            if (c.keys_changed and c.hs.slice().len > 0) return c.fatal(.unexpected_message);
        }
        // Nor may a key change fall inside a message that is only partly here.
        if (c.keys_changed and c.hs.slice().len > 0) return c.fatal(.unexpected_message);
    }

    fn message(c: *Conn, kind: tls.HandshakeType, whole: []const u8) Fail!void {
        const server = c.role == .server;
        switch (kind) {
            .client_hello => {
                if (!server or (c.phase != .hello and c.phase != .retried)) return c.fatal(.unexpected_message);
                try c.clientHello(whole);
            },
            .server_hello => {
                if (server or c.phase != .wait_server_hello) return c.fatal(.unexpected_message);
                try c.serverHello(whole);
            },
            .encrypted_extensions => {
                if (server or c.phase != .wait_encrypted_extensions) return c.fatal(.unexpected_message);
                try c.encryptedExtensions(whole);
            },
            .certificate => {
                if (server or c.phase != .wait_certificate) return c.fatal(.unexpected_message);
                try c.certificate(whole);
            },
            .certificate_verify => {
                if (server or c.phase != .wait_certificate_verify) return c.fatal(.unexpected_message);
                try c.certificateVerify(whole);
            },
            .finished => {
                if (server and c.phase == .wait_finished) return c.clientFinished(whole);
                if (!server and c.phase == .wait_server_finished) return c.serverFinished(whole);
                return c.fatal(.unexpected_message);
            },
            .key_update => {
                if (c.phase != .running) return c.fatal(.unexpected_message);
                try c.keyUpdate(whole);
            },
            // A server may hand a client tickets at any time after the handshake; with no
            // resumption in the cut, the client checks the shape and drops them.
            .new_session_ticket => {
                if (server or c.phase != .running) return c.fatal(.unexpected_message);
                var cur: Cursor = .{ .b = whole[4..] };
                _ = cur.take(8) catch return c.fatal(.decode_error);
                _ = cur.vec(u8) catch return c.fatal(.decode_error);
                const ticket = cur.vec(u16) catch return c.fatal(.decode_error);
                _ = cur.vec(u16) catch return c.fatal(.decode_error);
                if (ticket.len == 0 or !cur.done()) return c.fatal(.decode_error);
            },
            else => return c.fatal(.unexpected_message),
        }
    }

    // ---- the key schedule, both roles (RFC 8446 7.1)

    /// The handshake secrets from the shared secret and the transcript through the ServerHello;
    /// each side reads under the other's key and writes under its own.
    fn handshakeKeys(c: *Conn, shared: [32]u8) void {
        const hello_hash = c.transcript.peek();
        const zeroes: [32]u8 = @splat(0);
        const early = HkdfSha256.extract(&[1]u8{0}, &zeroes);
        const empty = tls.emptyHash(Sha256);
        const hs_derived = tls.hkdfExpandLabel(HkdfSha256, early, "derived", &empty, 32);
        c.handshake_secret = HkdfSha256.extract(&hs_derived, &shared);
        const ap_derived = tls.hkdfExpandLabel(HkdfSha256, c.handshake_secret, "derived", &empty, 32);
        c.master_secret = HkdfSha256.extract(&ap_derived, &zeroes);
        const client_secret = tls.hkdfExpandLabel(HkdfSha256, c.handshake_secret, "c hs traffic", &hello_hash, 32);
        const server_secret = tls.hkdfExpandLabel(HkdfSha256, c.handshake_secret, "s hs traffic", &hello_hash, 32);
        c.client_finished_key = tls.hkdfExpandLabel(HkdfSha256, client_secret, "finished", "", 32);
        c.server_finished_key = tls.hkdfExpandLabel(HkdfSha256, server_secret, "finished", "", 32);
        switch (c.role) {
            .server => {
                c.read_cipher.derive(c.suite, client_secret);
                c.write_cipher.derive(c.suite, server_secret);
            },
            .client => {
                c.read_cipher.derive(c.suite, server_secret);
                c.write_cipher.derive(c.suite, client_secret);
            },
        }
        c.encrypting = true;
        c.decrypting = true;
    }

    /// The application secrets, from the transcript through the server's Finished.
    fn applicationSecrets(c: *Conn) struct { client: [32]u8, server: [32]u8 } {
        const handshake_hash = c.transcript.peek();
        return .{
            .client = tls.hkdfExpandLabel(HkdfSha256, c.master_secret, "c ap traffic", &handshake_hash, 32),
            .server = tls.hkdfExpandLabel(HkdfSha256, c.master_secret, "s ap traffic", &handshake_hash, 32),
        };
    }

    /// RFC 8446 4.4.1: after a HelloRetryRequest the transcript starts with a synthetic
    /// `message_hash` message holding the hash of the first ClientHello.
    fn restartTranscript(c: *Conn, hello1_hash: [32]u8) void {
        c.transcript = Sha256.init(.{});
        c.transcript.update(&[_]u8{ @intFromEnum(tls.HandshakeType.message_hash), 0, 0, 32 });
        c.transcript.update(&hello1_hash);
    }

    fn secretFor(c: *Conn, dest: []u8, comptime which: enum { random, x25519 }) void {
        if (builtin.is_test) {
            const hooked = switch (which) {
                .random => c.hooks.random,
                .x25519 => c.hooks.x25519_secret,
            };
            if (hooked) |h| {
                @memcpy(dest, &h);
                return;
            }
        }
        entropy(dest);
    }

    // ---- the server's handshake

    fn clientHello(c: *Conn, whole: []const u8) Fail!void {
        var cur: Cursor = .{ .b = whole[4..] };
        const hello = c.readHello(&cur) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Alert => return error.Alert,
            error.Short => return c.fatal(.decode_error),
        };
        if (hello.retry) {
            // One HelloRetryRequest and no more: a client that asks twice is giving up on us.
            if (c.phase == .retried) return c.fatal(.illegal_parameter);
            try c.sendRetry(whole);
            c.phase = .retried;
            return;
        }
        c.transcript.update(whole);
        try c.sendServerHello(hello.share);
        try c.sendFlight();
        c.keys_changed = true;
    }

    const Hello = struct {
        /// The client's X25519 share, or none and `retry` set.
        share: [32]u8 = @splat(0),
        retry: bool = false,
    };

    fn readHello(c: *Conn, cur: *Cursor) (Fail || Cursor.Short)!Hello {
        const server = c.server.?;
        _ = try cur.u16_(); // legacy_version
        _ = try cur.take(32); // random
        const session_id = try cur.vec(u8);
        if (session_id.len > 32) return c.fatal(.illegal_parameter);
        c.session_id_len = @intCast(session_id.len);
        @memcpy(c.session_id[0..session_id.len], session_id);
        const suites = try cur.vec(u16);
        if (suites.len % 2 != 0) return c.fatal(.decode_error);
        const compression = try cur.vec(u8);
        if (mem.indexOfScalar(u8, compression, 0) == null) return c.fatal(.illegal_parameter);

        var tls13 = false;
        var share: ?[32]u8 = null;
        var supports_x25519 = false;
        var signatures: []const u8 = &.{};
        var alpn: ?[]const []const u8 = null;
        var alpn_buf: [64][]const u8 = undefined;
        if (!cur.done()) {
            var exts: Cursor = .{ .b = try cur.vec(u16) };
            if (!cur.done()) return c.fatal(.decode_error);
            while (!exts.done()) {
                const et: tls.ExtensionType = @enumFromInt(try exts.u16_());
                const body = try exts.vec(u16);
                var ext: Cursor = .{ .b = body };
                switch (et) {
                    .supported_versions => {
                        const versions = try ext.vec(u8);
                        var k: usize = 0;
                        while (k + 1 < versions.len) : (k += 2) {
                            if (mem.readInt(u16, versions[k..][0..2], .big) == @intFromEnum(tls.ProtocolVersion.tls_1_3)) tls13 = true;
                        }
                    },
                    .supported_groups => {
                        const groups = try ext.vec(u16);
                        var k: usize = 0;
                        while (k + 1 < groups.len) : (k += 2) {
                            if (mem.readInt(u16, groups[k..][0..2], .big) == @intFromEnum(tls.NamedGroup.x25519)) supports_x25519 = true;
                        }
                    },
                    .key_share => {
                        var shares: Cursor = .{ .b = try ext.vec(u16) };
                        while (!shares.done()) {
                            const group = try shares.u16_();
                            const key = try shares.vec(u16);
                            if (group == @intFromEnum(tls.NamedGroup.x25519) and share == null) {
                                if (key.len != 32) return c.fatal(.illegal_parameter);
                                share = key[0..32].*;
                            }
                        }
                    },
                    .signature_algorithms => signatures = try ext.vec(u16),
                    .application_layer_protocol_negotiation => alpn = alpnNames(body, &alpn_buf) orelse return c.fatal(.decode_error),
                    // SNI is read and ignored: a server here has one chain.
                    else => {},
                }
            }
        }
        if (!tls13) return c.fatal(.protocol_version);

        c.suite = pick: {
            var aes = false;
            var chacha = false;
            var k: usize = 0;
            while (k + 1 < suites.len) : (k += 2) {
                switch (@as(tls.CipherSuite, @enumFromInt(mem.readInt(u16, suites[k..][0..2], .big)))) {
                    .AES_128_GCM_SHA256 => aes = true,
                    .CHACHA20_POLY1305_SHA256 => chacha = true,
                    else => {},
                }
            }
            if (aes and chacha) break :pick server.prefer;
            if (aes) break :pick .aes_128_gcm;
            if (chacha) break :pick .chacha20_poly1305;
            return c.fatal(.handshake_failure);
        };

        // The client must accept the signature the key can make; with no extension it asks for
        // nothing TLS 1.3 allows.
        const want = @intFromEnum(server.key.scheme());
        var signable = false;
        var k: usize = 0;
        while (k + 1 < signatures.len) : (k += 2) {
            if (mem.readInt(u16, signatures[k..][0..2], .big) == want) signable = true;
        }
        if (!signable) return c.fatal(.handshake_failure);

        // ALPN (RFC 7301 3.2): the first of the server's own, in its order, that the client
        // offered; both lists and nothing shared is `no_application_protocol`; either list
        // missing is no ALPN at all.
        c.protocol_len = 0;
        if (alpn) |offered| if (server.protocols.len > 0) {
            const chosen = choose: for (server.protocols) |mine| {
                for (offered) |theirs| if (mem.eql(u8, mine, theirs)) break :choose mine;
            } else return c.fatal(.no_application_protocol);
            @memcpy(c.protocol[0..chosen.len], chosen);
            c.protocol_len = @intCast(chosen.len);
        };

        if (share) |s| return .{ .share = s };
        if (supports_x25519) return .{ .retry = true };
        return c.fatal(.handshake_failure);
    }

    fn sendRetry(c: *Conn, hello1: []const u8) Fail!void {
        var digest: [32]u8 = undefined;
        Sha256.hash(hello1, &digest, .{});
        c.restartTranscript(digest);

        var body: [128]u8 = undefined;
        const n = c.writeHelloBody(&body, &tls.hello_retry_request_sequence, null);
        var msg: [132]u8 = undefined;
        msg[0] = @intFromEnum(tls.HandshakeType.server_hello);
        mem.writeInt(u24, msg[1..4], @intCast(n), .big);
        @memcpy(msg[4..][0..n], body[0..n]);
        try c.sendHandshake(msg[0 .. 4 + n]);
        try c.sendRecord(.change_cipher_spec, &.{1});
    }

    /// A ServerHello or a HelloRetryRequest: the same message, differing in `random` and in
    /// whether the key_share extension carries a key or only the group.
    fn writeHelloBody(c: *Conn, body: []u8, random: *const [32]u8, share: ?*const [32]u8) usize {
        var n: usize = 0;
        put16(body[n..], @intFromEnum(tls.ProtocolVersion.tls_1_2));
        n += 2;
        @memcpy(body[n..][0..32], random);
        n += 32;
        body[n] = c.session_id_len;
        n += 1;
        @memcpy(body[n..][0..c.session_id_len], c.session_id[0..c.session_id_len]);
        n += c.session_id_len;
        put16(body[n..], @intFromEnum(c.suite.tag()));
        n += 2;
        body[n] = 0; // legacy_compression_method
        n += 1;
        const exts_at = n;
        n += 2;
        put16(body[n..], @intFromEnum(tls.ExtensionType.supported_versions));
        n += 2;
        put16(body[n..], 2);
        n += 2;
        put16(body[n..], @intFromEnum(tls.ProtocolVersion.tls_1_3));
        n += 2;
        put16(body[n..], @intFromEnum(tls.ExtensionType.key_share));
        n += 2;
        if (share) |key| {
            put16(body[n..], 2 + 2 + 32);
            n += 2;
            put16(body[n..], @intFromEnum(tls.NamedGroup.x25519));
            n += 2;
            put16(body[n..], 32);
            n += 2;
            @memcpy(body[n..][0..32], key);
            n += 32;
        } else {
            put16(body[n..], 2);
            n += 2;
            put16(body[n..], @intFromEnum(tls.NamedGroup.x25519));
            n += 2;
        }
        put16(body[exts_at..], @intCast(n - exts_at - 2));
        return n;
    }

    fn sendServerHello(c: *Conn, client_share: [32]u8) Fail!void {
        c.secretFor(&c.secret_key, .x25519);
        const kp = X25519.KeyPair.generateDeterministic(c.secret_key) catch return c.fatal(.internal_error);
        c.public_key = kp.public_key;
        const shared = X25519.scalarmult(kp.secret_key, client_share) catch return c.fatal(.illegal_parameter);

        var random: [32]u8 = undefined;
        c.secretFor(&random, .random);
        var body: [128]u8 = undefined;
        const n = c.writeHelloBody(&body, &random, &c.public_key);
        var msg: [132]u8 = undefined;
        msg[0] = @intFromEnum(tls.HandshakeType.server_hello);
        mem.writeInt(u24, msg[1..4], @intCast(n), .big);
        @memcpy(msg[4..][0..n], body[0..n]);
        try c.sendHandshake(msg[0 .. 4 + n]);
        // After a HelloRetryRequest the compatibility CCS has already gone out.
        if (c.phase != .retried) try c.sendRecord(.change_cipher_spec, &.{1});
        c.handshakeKeys(shared);
    }

    /// EncryptedExtensions, Certificate, CertificateVerify, Finished, all under the handshake key.
    fn sendFlight(c: *Conn) Fail!void {
        const server = c.server.?;
        // EncryptedExtensions: ALPN's answer when there is one, and nothing else.
        var ee: Msg = .{};
        defer ee.deinit();
        try ee.int(u8, @intFromEnum(tls.HandshakeType.encrypted_extensions));
        const ee_len = try ee.open(u24);
        const exts = try ee.open(u16);
        if (c.protocol_len > 0) {
            try ee.int(u16, @intFromEnum(tls.ExtensionType.application_layer_protocol_negotiation));
            const body = try ee.open(u16);
            const list = try ee.open(u16);
            try ee.int(u8, c.protocol_len);
            try ee.bytes(c.protocol[0..c.protocol_len]);
            ee.close(u16, list);
            ee.close(u16, body);
        }
        ee.close(u16, exts);
        ee.close(u24, ee_len);
        try c.sendHandshake(ee.b.items);

        var certs_len: usize = 0;
        for (server.chain) |der| certs_len += 3 + der.len + 2;
        const body_len = 1 + 3 + certs_len;
        const cert_msg = try gpa.alloc(u8, 4 + body_len);
        defer gpa.free(cert_msg);
        cert_msg[0] = @intFromEnum(tls.HandshakeType.certificate);
        mem.writeInt(u24, cert_msg[1..4], @intCast(body_len), .big);
        cert_msg[4] = 0; // certificate_request_context
        mem.writeInt(u24, cert_msg[5..8], @intCast(certs_len), .big);
        var at: usize = 8;
        for (server.chain) |der| {
            mem.writeInt(u24, cert_msg[at..][0..3], @intCast(der.len), .big);
            at += 3;
            @memcpy(cert_msg[at..][0..der.len], der);
            at += der.len;
            put16(cert_msg[at..], 0); // no certificate extensions
            at += 2;
        }
        try c.sendHandshake(cert_msg);

        const signed = verifyContent(c.transcript.peek());
        var sig_buf: [EcdsaP256.Signature.der_encoded_length_max]u8 = undefined;
        const signature: []const u8 = switch (server.key) {
            .ed25519 => |kp| blk: {
                const s = kp.sign(&signed, null) catch return c.fatal(.internal_error);
                sig_buf[0..64].* = s.toBytes();
                break :blk sig_buf[0..64];
            },
            .p256 => |kp| blk: {
                const s = kp.sign(&signed, null) catch return c.fatal(.internal_error);
                break :blk s.toDer(&sig_buf);
            },
        };
        var verify: [4 + 2 + 2 + EcdsaP256.Signature.der_encoded_length_max]u8 = undefined;
        verify[0] = @intFromEnum(tls.HandshakeType.certificate_verify);
        mem.writeInt(u24, verify[1..4], @intCast(4 + signature.len), .big);
        put16(verify[4..], @intFromEnum(server.key.scheme()));
        put16(verify[6..], @intCast(signature.len));
        @memcpy(verify[8..][0..signature.len], signature);
        try c.sendHandshake(verify[0 .. 8 + signature.len]);

        var finished: [4 + 32]u8 = undefined;
        finished[0] = @intFromEnum(tls.HandshakeType.finished);
        mem.writeInt(u24, finished[1..4], 32, .big);
        HmacSha256.create(finished[4..36], &c.transcript.peek(), &c.server_finished_key);
        try c.sendHandshake(&finished);

        // The application keys are taken from the transcript through the server's Finished; the
        // client still writes under the handshake key until its own Finished.
        const secrets = c.applicationSecrets();
        c.write_cipher.derive(c.suite, secrets.server);
        // Kept until the client's Finished is checked, then installed.
        c.handshake_secret = secrets.client;
        c.phase = .wait_finished;
    }

    fn clientFinished(c: *Conn, whole: []const u8) Fail!void {
        if (whole.len != 4 + 32) return c.fatal(.decode_error);
        var want: [32]u8 = undefined;
        HmacSha256.create(&want, &c.transcript.peek(), &c.client_finished_key);
        if (!crypto.timing_safe.eql([32]u8, want, whole[4..36].*)) return c.fatal(.decrypt_error);
        c.transcript.update(whole);
        c.read_cipher.derive(c.suite, c.handshake_secret);
        crypto.secureZero(u8, &c.handshake_secret);
        c.phase = .running;
        c.keys_changed = true;
    }

    // ---- the client's handshake

    /// The first ClientHello, or the second after a HelloRetryRequest with its cookie.
    fn sendClientHello(c: *Conn, cookie: []const u8, with_share: bool) Fail!void {
        const client = c.client.?;
        var m: Msg = .{};
        defer m.deinit();
        try m.int(u8, @intFromEnum(tls.HandshakeType.client_hello));
        const len = try m.open(u24);
        try m.int(u16, @intFromEnum(tls.ProtocolVersion.tls_1_2));
        try m.bytes(&c.client_random);
        try m.int(u8, c.session_id_len);
        try m.bytes(c.session_id[0..c.session_id_len]);
        var layout: ?HelloLayout = null;
        if (builtin.is_test) layout = c.hooks.hello;
        if (layout) |l| {
            try m.bytes(l.suites);
        } else {
            // AES-128-GCM first, as the server here prefers it.
            try m.bytes(&.{ 0, 4, 0x13, 0x01, 0x13, 0x03 });
        }
        try m.bytes(&.{ 1, 0 }); // legacy_compression_methods: null
        const exts = try m.open(u16);
        if (layout) |l| {
            try m.bytes(l.before_share);
            try c.writeKeyShare(&m, with_share);
            try m.bytes(l.after_share);
        } else {
            // SNI (RFC 6066 3) for a name, never for an address.
            var addr_buf: [16]u8 = undefined;
            if (c.host.len > 0 and hostAddress(c.host, &addr_buf) == null) {
                try m.int(u16, @intFromEnum(tls.ExtensionType.server_name));
                const body = try m.open(u16);
                const list = try m.open(u16);
                try m.int(u8, 0); // host_name
                try m.int(u16, @intCast(c.host.len));
                try m.bytes(c.host);
                m.close(u16, list);
                m.close(u16, body);
            }
            try m.bytes(&.{ 0x00, 0x2b, 0x00, 0x03, 0x02, 0x03, 0x04 }); // supported_versions: TLS 1.3
            try m.bytes(&.{ 0x00, 0x0a, 0x00, 0x04, 0x00, 0x02, 0x00, 0x1d }); // supported_groups: x25519
            // signature_algorithms: the two the cut checks, Ed25519 and ECDSA P-256 SHA-256.
            try m.bytes(&.{ 0x00, 0x0d, 0x00, 0x06, 0x00, 0x04, 0x08, 0x07, 0x04, 0x03 });
            try c.writeKeyShare(&m, with_share);
            if (client.protocols.len > 0) {
                try m.int(u16, @intFromEnum(tls.ExtensionType.application_layer_protocol_negotiation));
                const body = try m.open(u16);
                const list = try m.open(u16);
                for (client.protocols) |name| {
                    try m.int(u8, @intCast(name.len));
                    try m.bytes(name);
                }
                m.close(u16, list);
                m.close(u16, body);
            }
            if (cookie.len > 0) {
                try m.int(u16, @intFromEnum(tls.ExtensionType.cookie));
                const body = try m.open(u16);
                try m.int(u16, @intCast(cookie.len));
                try m.bytes(cookie);
                m.close(u16, body);
            }
        }
        m.close(u16, exts);
        m.close(u24, len);
        try c.sendHandshake(m.b.items);
    }

    fn writeKeyShare(c: *Conn, m: *Msg, with_share: bool) Fail!void {
        try m.int(u16, @intFromEnum(tls.ExtensionType.key_share));
        const body = try m.open(u16);
        const list = try m.open(u16);
        if (with_share) {
            try m.int(u16, @intFromEnum(tls.NamedGroup.x25519));
            try m.int(u16, 32);
            try m.bytes(&c.public_key);
        }
        m.close(u16, list);
        m.close(u16, body);
    }

    fn connect(c: *Conn) Fail!void {
        c.secretFor(&c.client_random, .random);
        c.secretFor(&c.secret_key, .x25519);
        c.public_key = (X25519.KeyPair.generateDeterministic(c.secret_key) catch return c.fatal(.internal_error)).public_key;
        // A legacy session id of 32 random bytes: middlebox compatibility mode (RFC 8446 D.4).
        c.session_id_len = 32;
        entropy(&c.session_id);
        var share = true;
        if (builtin.is_test) {
            if (c.hooks.session_id) |sid| {
                c.session_id_len = @intCast(sid.len);
                @memcpy(c.session_id[0..sid.len], sid);
            }
            share = !c.hooks.no_share;
        }
        c.phase = .wait_server_hello;
        try c.sendClientHello("", share);
    }

    const ServerHello = struct {
        retry: bool,
        suite: Suite,
        /// The server's share, or for a HelloRetryRequest the group it asks for.
        share: ?[32]u8 = null,
        group: ?u16 = null,
        cookie: []const u8 = &.{},
    };

    fn readServerHello(c: *Conn, cur: *Cursor) (Fail || Cursor.Short)!ServerHello {
        const version = try cur.u16_();
        const random = try cur.take(32);
        const retry = mem.eql(u8, random, &tls.hello_retry_request_sequence);
        const session_id = try cur.vec(u8);
        const suite_tag: tls.CipherSuite = @enumFromInt(try cur.u16_());
        const compression = try cur.u8_();
        // A server with no extensions at all speaks TLS 1.2 or older.
        if (cur.done()) return c.fatal(.protocol_version);
        var exts: Cursor = .{ .b = try cur.vec(u16) };
        if (!cur.done()) return c.fatal(.decode_error);
        var hello: ServerHello = .{ .retry = retry, .suite = .aes_128_gcm };
        var tls13 = false;
        var seen: u8 = 0;
        while (!exts.done()) {
            const et: tls.ExtensionType = @enumFromInt(try exts.u16_());
            var ext: Cursor = .{ .b = try exts.vec(u16) };
            const bit: u8 = switch (et) {
                .supported_versions => 1,
                .key_share => 2,
                .cookie => 4,
                // RFC 8446 4.1.3: nothing the client did not ask for.
                else => return c.fatal(.unsupported_extension),
            };
            if (seen & bit != 0) return c.fatal(.illegal_parameter);
            seen |= bit;
            switch (et) {
                .supported_versions => {
                    if (try ext.u16_() != @intFromEnum(tls.ProtocolVersion.tls_1_3)) return c.fatal(.illegal_parameter);
                    tls13 = true;
                },
                .key_share => {
                    const group = try ext.u16_();
                    if (retry) {
                        hello.group = group;
                    } else {
                        if (group != @intFromEnum(tls.NamedGroup.x25519)) return c.fatal(.illegal_parameter);
                        const key = try ext.vec(u16);
                        if (key.len != 32) return c.fatal(.illegal_parameter);
                        hello.share = key[0..32].*;
                    }
                },
                .cookie => {
                    if (!retry) return c.fatal(.unsupported_extension);
                    hello.cookie = try ext.vec(u16);
                    if (hello.cookie.len == 0) return c.fatal(.decode_error);
                },
                else => unreachable,
            }
            if (!ext.done()) return c.fatal(.decode_error);
        }
        if (!tls13) return c.fatal(.protocol_version);
        if (version != @intFromEnum(tls.ProtocolVersion.tls_1_2)) return c.fatal(.illegal_parameter);
        if (!mem.eql(u8, session_id, c.session_id[0..c.session_id_len])) return c.fatal(.illegal_parameter);
        if (compression != 0) return c.fatal(.illegal_parameter);
        hello.suite = switch (suite_tag) {
            .AES_128_GCM_SHA256 => .aes_128_gcm,
            .CHACHA20_POLY1305_SHA256 => .chacha20_poly1305,
            else => return c.fatal(.illegal_parameter),
        };
        // After a HelloRetryRequest the ServerHello keeps the suite it named.
        if (c.retried and hello.suite != c.suite) return c.fatal(.illegal_parameter);
        return hello;
    }

    fn serverHello(c: *Conn, whole: []const u8) Fail!void {
        var cur: Cursor = .{ .b = whole[4..] };
        const hello = c.readServerHello(&cur) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Alert => return error.Alert,
            error.Short => return c.fatal(.decode_error),
        };
        if (hello.retry) {
            if (c.retried) return c.fatal(.unexpected_message);
            // RFC 8446 4.1.4: it must change something, and a group asked for must be one we
            // offered and did not already share.
            if (hello.group == null and hello.cookie.len == 0) return c.fatal(.illegal_parameter);
            var shared_before = true;
            if (builtin.is_test) shared_before = !c.hooks.no_share;
            if (hello.group) |g| if (g != @intFromEnum(tls.NamedGroup.x25519) or shared_before) return c.fatal(.illegal_parameter);
            c.retried = true;
            c.suite = hello.suite;
            c.restartTranscript(c.transcript.peek());
            c.transcript.update(whole);
            try c.compatCcs();
            try c.sendClientHello(hello.cookie, true);
            return;
        }
        const share = hello.share orelse return c.fatal(.missing_extension);
        c.suite = hello.suite;
        c.transcript.update(whole);
        const shared = X25519.scalarmult(c.secret_key, share) catch return c.fatal(.illegal_parameter);
        crypto.secureZero(u8, &c.secret_key);
        c.handshakeKeys(shared);
        c.phase = .wait_encrypted_extensions;
        c.keys_changed = true;
    }

    fn encryptedExtensions(c: *Conn, whole: []const u8) Fail!void {
        const client = c.client.?;
        var cur: Cursor = .{ .b = whole[4..] };
        var exts: Cursor = .{ .b = cur.vec(u16) catch return c.fatal(.decode_error) };
        if (!cur.done()) return c.fatal(.decode_error);
        while (!exts.done()) {
            const et: tls.ExtensionType = @enumFromInt(exts.u16_() catch return c.fatal(.decode_error));
            const body = exts.vec(u16) catch return c.fatal(.decode_error);
            switch (et) {
                .application_layer_protocol_negotiation => {
                    // RFC 7301 3.1: exactly one name, and one this client offered.
                    if (client.protocols.len == 0) return c.fatal(.unsupported_extension);
                    var names_buf: [64][]const u8 = undefined;
                    const names = alpnNames(body, &names_buf) orelse return c.fatal(.decode_error);
                    if (names.len != 1) return c.fatal(.illegal_parameter);
                    for (client.protocols) |mine| {
                        if (mem.eql(u8, mine, names[0])) break;
                    } else return c.fatal(.illegal_parameter);
                    @memcpy(c.protocol[0..names[0].len], names[0]);
                    c.protocol_len = @intCast(names[0].len);
                },
                // Answers a ServerHello may not carry (RFC 8446 4.2's table).
                .supported_versions, .key_share, .cookie, .pre_shared_key, .signature_algorithms => return c.fatal(.illegal_parameter),
                else => {},
            }
        }
        c.transcript.update(whole);
        c.phase = .wait_certificate;
    }

    /// The server's chain, checked whole before its CertificateVerify is read.
    fn certificate(c: *Conn, whole: []const u8) Fail!void {
        var cur: Cursor = .{ .b = whole[4..] };
        const context = cur.vec(u8) catch return c.fatal(.decode_error);
        var list: Cursor = .{ .b = cur.vec(u24) catch return c.fatal(.decode_error) };
        if (!cur.done()) return c.fatal(.decode_error);
        // A client that asked for no certificate context gets none back.
        if (context.len != 0) return c.fatal(.illegal_parameter);
        var chain: [max_chain + 1][]const u8 = undefined;
        var n: usize = 0;
        while (!list.done()) {
            const der = list.vec(u24) catch return c.fatal(.decode_error);
            _ = list.vec(u16) catch return c.fatal(.decode_error);
            if (der.len == 0) return c.fatal(.decode_error);
            if (n == chain.len) return c.fatal(.unknown_ca);
            chain[n] = der;
            n += 1;
        }
        if (n == 0) return c.fatal(.decode_error);
        var skip = false;
        if (builtin.is_test) skip = c.hooks.skip_auth;
        if (!skip) {
            if (checkChain(chain[0..n], c.client.?.trust, c.host, c.now)) |desc| {
                c.untrusted = true;
                return c.fatal(desc);
            }
            // The leaf's key, for the CertificateVerify: checkChain has parsed it already.
            const leaf = parseCert(chain[0]) catch unreachable;
            const key = leaf.pubKey();
            switch (leaf.pub_key_algo) {
                .curveEd25519 => {
                    if (key.len != 32) {
                        c.untrusted = true;
                        return c.fatal(.bad_certificate);
                    }
                    c.peer_key_ed25519 = true;
                },
                .X9_62_id_ecPublicKey => |curve| {
                    if (curve != .X9_62_prime256v1 or key.len != 65) {
                        c.untrusted = true;
                        return c.fatal(.unsupported_certificate);
                    }
                },
                else => {
                    c.untrusted = true;
                    return c.fatal(.unsupported_certificate);
                },
            }
            @memcpy(c.peer_key[0..key.len], key);
            c.peer_key_len = @intCast(key.len);
        }
        c.transcript.update(whole);
        c.phase = .wait_certificate_verify;
    }

    fn certificateVerify(c: *Conn, whole: []const u8) Fail!void {
        var cur: Cursor = .{ .b = whole[4..] };
        const scheme: tls.SignatureScheme = @enumFromInt(cur.u16_() catch return c.fatal(.decode_error));
        const signature = cur.vec(u16) catch return c.fatal(.decode_error);
        if (!cur.done()) return c.fatal(.decode_error);
        const signed = verifyContent(c.transcript.peek());
        var skip = false;
        if (builtin.is_test) skip = c.hooks.skip_auth;
        if (!skip) {
            const key = c.peer_key[0..c.peer_key_len];
            switch (scheme) {
                .ed25519 => {
                    if (!c.peer_key_ed25519) return c.fatal(.illegal_parameter);
                    if (signature.len != 64) return c.fatal(.decrypt_error);
                    const pk = Ed25519.PublicKey.fromBytes(key[0..32].*) catch return c.fatal(.decrypt_error);
                    Ed25519.Signature.fromBytes(signature[0..64].*).verify(&signed, pk) catch return c.fatal(.decrypt_error);
                },
                .ecdsa_secp256r1_sha256 => {
                    if (c.peer_key_ed25519) return c.fatal(.illegal_parameter);
                    const pk = EcdsaP256.PublicKey.fromSec1(key) catch return c.fatal(.decrypt_error);
                    const sig = EcdsaP256.Signature.fromDer(signature) catch return c.fatal(.decrypt_error);
                    sig.verify(&signed, pk) catch return c.fatal(.decrypt_error);
                },
                // A scheme this client did not offer.
                else => return c.fatal(.illegal_parameter),
            }
        }
        c.transcript.update(whole);
        c.phase = .wait_server_finished;
    }

    fn serverFinished(c: *Conn, whole: []const u8) Fail!void {
        if (whole.len != 4 + 32) return c.fatal(.decode_error);
        var want: [32]u8 = undefined;
        HmacSha256.create(&want, &c.transcript.peek(), &c.server_finished_key);
        if (!crypto.timing_safe.eql([32]u8, want, whole[4..36].*)) return c.fatal(.decrypt_error);
        c.transcript.update(whole);
        const secrets = c.applicationSecrets();
        c.read_cipher.derive(c.suite, secrets.server);

        var finished: [4 + 32]u8 = undefined;
        finished[0] = @intFromEnum(tls.HandshakeType.finished);
        mem.writeInt(u24, finished[1..4], 32, .big);
        HmacSha256.create(finished[4..36], &c.transcript.peek(), &c.client_finished_key);
        try c.compatCcs();
        try c.sendHandshake(&finished);
        c.write_cipher.derive(c.suite, secrets.client);
        crypto.secureZero(u8, &c.handshake_secret);
        c.phase = .running;
        c.keys_changed = true;
    }

    // ---- after the handshake, both roles

    /// RFC 8446 4.6.3: the peer's keys move on, and when it asks, ours do too and it hears so.
    fn keyUpdate(c: *Conn, whole: []const u8) Fail!void {
        if (whole.len != 5) return c.fatal(.decode_error);
        const request: tls.KeyUpdateRequest = @enumFromInt(whole[4]);
        switch (request) {
            .update_requested, .update_not_requested => {},
            _ => return c.fatal(.illegal_parameter),
        }
        c.read_cipher.update(c.suite);
        c.key_updates_read += 1;
        c.keys_changed = true;
        if (request == .update_requested) try c.startKeyUpdate(false);
    }

    /// A KeyUpdate from this side: the message goes out under the current write keys, then they
    /// move on. With `request_peer` the peer must answer with its own.
    fn startKeyUpdate(c: *Conn, request_peer: bool) Fail!void {
        const request: tls.KeyUpdateRequest = if (request_peer) .update_requested else .update_not_requested;
        try c.sendUntracked(&[_]u8{ @intFromEnum(tls.HandshakeType.key_update), 0, 0, 1, @intFromEnum(request) });
        c.write_cipher.update(c.suite);
        c.key_updates_sent += 1;
    }

    // ---- what the runtime calls

    fn feed(c: *Conn, bytes: []const u8) c_int {
        if (c.phase == .broken) return failed;
        c.in.append(bytes) catch return no_memory;
        c.pump() catch |err| return switch (err) {
            error.OutOfMemory => no_memory,
            error.Alert => failed,
        };
        return ok;
    }

    fn write(c: *Conn, bytes: []const u8) c_int {
        if (c.phase != .running) return failed;
        var at: usize = 0;
        while (at < bytes.len) {
            const n = @min(max_plaintext, bytes.len - at);
            c.sendRecord(.application_data, bytes[at..][0..n]) catch |err| return switch (err) {
                error.OutOfMemory => no_memory,
                error.Alert => failed,
            };
            at += n;
        }
        return ok;
    }
};

/// RFC 8446 4.4.3: what a server's CertificateVerify signs: 64 spaces, the context string, a
/// zero byte, and the transcript hash.
fn verifyContent(transcript_hash: [32]u8) [64 + 33 + 1 + 32]u8 {
    var signed: [64 + 33 + 1 + 32]u8 = undefined;
    @memset(signed[0..64], 0x20);
    @memcpy(signed[64..][0..33], "TLS 1.3, server CertificateVerify");
    signed[97] = 0;
    @memcpy(signed[98..][0..32], &transcript_hash);
    return signed;
}

// ---- the exports both runtimes call

/// A server from PEM text: the chain leaf first, and a PKCS#8 key that is the leaf's.
pub export fn mo_tls_server_new(cert_pem: ?[*]const u8, cert_n: usize, key_pem: ?[*]const u8, key_n: usize) ?*Server {
    const cert_text = if (cert_n == 0) "" else cert_pem.?[0..cert_n];
    const key_text = if (key_n == 0) "" else key_pem.?[0..key_n];
    return newServer(cert_text, key_text) catch null;
}

fn newServer(cert_text: []const u8, key_text: []const u8) !*Server {
    var chain: std.ArrayList([]u8) = .empty;
    defer chain.deinit(gpa);
    errdefer for (chain.items) |der| gpa.free(der);
    try pemBlocks(cert_text, "CERTIFICATE", &chain);
    if (chain.items.len == 0) return error.BadPem;

    var keys: std.ArrayList([]u8) = .empty;
    defer {
        for (keys.items) |der| gpa.free(der);
        keys.deinit(gpa);
    }
    try pemBlocks(key_text, "PRIVATE KEY", &keys);
    if (keys.items.len != 1) return error.BadPem;
    const key = try parsePkcs8(keys.items[0]);
    if (!keyMatchesLeaf(chain.items[0], key)) return error.BadPem;

    const s = try gpa.create(Server);
    errdefer gpa.destroy(s);
    s.* = .{ .chain = try chain.toOwnedSlice(gpa), .key = key };
    return s;
}

pub export fn mo_tls_server_free(s: ?*Server) void {
    if (s) |server| server.deinit();
}

pub export fn mo_tls_conn_new(s: ?*Server) ?*Conn {
    const server = s orelse return null;
    const c = gpa.create(Conn) catch return null;
    c.* = .{ .server = server };
    return c;
}

pub export fn mo_tls_conn_free(c: ?*Conn) void {
    if (c) |conn| conn.deinit();
}

/// A client from PEM text holding one or more root certificates: the trust a server's chain must
/// lead to. Null when no certificate in the text parses (`BadPem` in the rows).
pub export fn mo_tls_client_new(trust_pem: ?[*]const u8, n: usize) ?*Client {
    return newClient(if (n == 0) "" else trust_pem.?[0..n]) catch null;
}

fn newClient(text: []const u8) !*Client {
    var blocks: std.ArrayList([]u8) = .empty;
    defer blocks.deinit(gpa);
    errdefer for (blocks.items) |der| gpa.free(der);
    try pemBlocks(text, "CERTIFICATE", &blocks);
    // A block that is not a certificate this brick can read is left out; none left is BadPem.
    var kept: usize = 0;
    for (blocks.items) |der| {
        if (parseCert(der)) |_| {
            blocks.items[kept] = der;
            kept += 1;
        } else |_| gpa.free(der);
    }
    blocks.items.len = kept;
    if (kept == 0) return error.BadPem;
    const cl = try gpa.create(Client);
    errdefer gpa.destroy(cl);
    cl.* = .{ .trust = try blocks.toOwnedSlice(gpa) };
    return cl;
}

pub export fn mo_tls_client_free(cl: ?*Client) void {
    if (cl) |client| client.deinit();
}

/// ALPN: a new client offering `protocols` (NUL-separated names, in order), the given one
/// unchanged, so a program's `TlsClient` is a value. Null when a name is longer than 255 bytes.
pub export fn mo_tls_client_offer(cl: ?*Client, protocols: ?[*]const u8, n: usize) ?*Client {
    const client = cl orelse return null;
    const names = parseNames(if (n == 0) "" else protocols.?[0..n]) catch return null;
    const trust = dupeList(client.trust) catch {
        freeNames(names);
        return null;
    };
    const copy = gpa.create(Client) catch {
        for (trust) |der| gpa.free(der);
        gpa.free(trust);
        freeNames(names);
        return null;
    };
    copy.* = .{ .trust = trust, .protocols = names };
    return copy;
}

/// ALPN: a new server accepting `protocols` (NUL-separated names, its order of preference), the
/// given one unchanged. Null when a name is longer than 255 bytes.
pub export fn mo_tls_server_offer(s: ?*Server, protocols: ?[*]const u8, n: usize) ?*Server {
    const server = s orelse return null;
    const names = parseNames(if (n == 0) "" else protocols.?[0..n]) catch return null;
    const chain = dupeList(server.chain) catch {
        freeNames(names);
        return null;
    };
    const copy = gpa.create(Server) catch {
        for (chain) |der| gpa.free(der);
        gpa.free(chain);
        freeNames(names);
        return null;
    };
    copy.* = .{ .chain = chain, .key = server.key, .protocols = names, .prefer = server.prefer };
    return copy;
}

/// A client's connection: the ClientHello is queued for `mo_tls_flush`. `host` is sent as SNI
/// (when it is a name, not an address) and is what the leaf certificate must be for; `now_sec`
/// is the moment, in seconds since 1970, the chain's dates are checked at. The client must
/// outlive the connection's handshake.
pub export fn mo_tls_connect(cl: ?*Client, host: ?[*]const u8, n: usize, now_sec: i64) ?*Conn {
    const client = cl orelse return null;
    return connectWith(client, if (n == 0) "" else host.?[0..n], now_sec, .{}) catch null;
}

/// `mo_tls_connect` with a test's hooks (only a test build has any).
pub fn connectWith(client: *Client, host: []const u8, now_sec: i64, hooks: TestHooks) !*Conn {
    const c = try gpa.create(Conn);
    c.* = .{ .role = .client, .client = client, .now = now_sec, .hooks = hooks, .phase = .wait_server_hello };
    errdefer c.deinit();
    c.host = try gpa.dupe(u8, host);
    c.connect() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        // Nothing in a first hello can fail but memory; a failure is left for the runtime to see.
        error.Alert => {},
    };
    return c;
}

/// The ALPN protocol agreed, copied into `out`; its length, 0 when none was.
pub export fn mo_tls_protocol(c: ?*Conn, out: ?[*]u8, cap: usize) usize {
    const conn = c orelse return 0;
    if (conn.phase != .running and conn.phase != .over) return 0;
    const n = @min(cap, conn.protocol_len);
    if (n > 0) @memcpy(out.?[0..n], conn.protocol[0..n]);
    return n;
}

/// Queues a KeyUpdate from this side, either role: the message goes out under the current write
/// keys, which then move on; with `request_peer` the peer must answer with its own. `failed`
/// before the handshake is done or after the connection is.
pub export fn mo_tls_key_update(c: ?*Conn, request_peer: bool) c_int {
    const conn = c orelse return failed;
    if (conn.phase != .running) return failed;
    conn.startKeyUpdate(request_peer) catch |err| return switch (err) {
        error.OutOfMemory => no_memory,
        error.Alert => failed,
    };
    return ok;
}

/// Ciphertext from the socket. `failed` once the connection is over.
pub export fn mo_tls_feed(c: ?*Conn, bytes: ?[*]const u8, n: usize) c_int {
    const conn = c orelse return failed;
    return conn.feed(if (n == 0) "" else bytes.?[0..n]);
}

/// The plaintext the records held, at most `cap` bytes: `ok` with `got` set, `want_more`,
/// `closed`, or `failed`.
pub export fn mo_tls_read(c: ?*Conn, out: ?[*]u8, cap: usize, got: *usize) c_int {
    got.* = 0;
    const conn = c orelse return failed;
    const held = conn.plain.slice();
    if (held.len > 0) {
        const n = @min(cap, held.len);
        if (n > 0) @memcpy(out.?[0..n], held[0..n]);
        conn.plain.consume(n);
        got.* = n;
        return ok;
    }
    return switch (conn.phase) {
        .broken => failed,
        .over => closed,
        else => want_more,
    };
}

/// Plaintext the program wrote, as records. `failed` before the handshake is done.
pub export fn mo_tls_write(c: ?*Conn, plain: ?[*]const u8, n: usize) c_int {
    const conn = c orelse return failed;
    return conn.write(if (n == 0) "" else plain.?[0..n]);
}

/// Ciphertext for the socket, at most `cap` bytes; `got` is 0 when there is nothing to write.
/// The bytes stay in the engine until `mo_tls_sent` says how many reached the socket, so a
/// runtime that may write only part of them (a nonblocking socket with a full buffer) loses
/// none. Always `ok`: a connection that failed still has its alert to put on the wire.
pub export fn mo_tls_flush(c: ?*Conn, out: ?[*]u8, cap: usize, got: *usize) c_int {
    got.* = 0;
    const conn = c orelse return failed;
    const held = conn.out.slice();
    const n = @min(cap, held.len);
    if (n > 0) @memcpy(out.?[0..n], held[0..n]);
    got.* = n;
    return ok;
}

/// `n` of the bytes `mo_tls_flush` gave reached the socket: the engine forgets them.
pub export fn mo_tls_sent(c: ?*Conn, n: usize) void {
    const conn = c orelse return;
    conn.out.consume(@min(n, conn.out.slice().len));
}

/// Queues `close_notify`; the runtime flushes it before it shuts the socket.
pub export fn mo_tls_close(c: ?*Conn) void {
    const conn = c orelse return;
    if (conn.sent_close_notify or conn.phase == .broken) return;
    conn.sent_close_notify = true;
    const body = [2]u8{ @intFromEnum(tls.Alert.Level.warning), @intFromEnum(tls.Alert.Description.close_notify) };
    conn.sendRecord(.alert, &body) catch {};
}

/// Whether the handshake is done and the connection carries the program's bytes.
pub export fn mo_tls_ready(c: ?*Conn) bool {
    const conn = c orelse return false;
    return conn.phase == .running;
}

/// Whether a client's handshake ended because it refused the server's chain (its root, the
/// host name, a date, the depth, or RSA): the alert it sent is `mo_tls_alert`.
pub export fn mo_tls_untrusted(c: ?*Conn) bool {
    const conn = c orelse return false;
    return conn.untrusted;
}

/// The alert description this connection ended on, or -1 while it is alive.
pub export fn mo_tls_alert(c: ?*Conn) c_int {
    const conn = c orelse return -1;
    return if (conn.alert == 255) -1 else conn.alert;
}

/// Bytes waiting for `mo_tls_flush`.
pub export fn mo_tls_pending(c: ?*Conn) usize {
    const conn = c orelse return 0;
    return conn.out.slice().len;
}

// ---- tests: the handshake against Zig's own client, RFC 8448's schedule, and the rejections

const testing = std.testing;

/// Two self-signed pairs, the ones step 36 checked in (`openssl req -x509 -newkey ed25519 -days
/// 3650 -subj /CN=localhost`, and `-newkey ec` on P-256), kept for Zig's own client, whose
/// `.self_signed` mode wants a leaf that signed itself. The chains of step 37 follow the tests
/// against Zig's client. All are written here and not read from a file so the brick stays one
/// file: `mo build` writes this source alone into its cache and compiles it there.
const ed25519_cert =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBUzCCAQWgAwIBAgIUezLLClFE6Kk5mrl54JhJWvbLXPMwBQYDK2VwMBQxEjAQ
    \\BgNVBAMMCWxvY2FsaG9zdDAeFw0yNjA5MTcxOTI0MDRaFw0zNjA5MTQxOTI0MDRa
    \\MBQxEjAQBgNVBAMMCWxvY2FsaG9zdDAqMAUGAytlcAMhAARTp3qAE8E1cQRtDwpT
    \\aRWPIPG6tgcJslpuYqhi1ebxo2kwZzAdBgNVHQ4EFgQULj/kPJm0T6AHNDbPj2Iv
    \\LbF9MhcwHwYDVR0jBBgwFoAULj/kPJm0T6AHNDbPj2IvLbF9MhcwDwYDVR0TAQH/
    \\BAUwAwEB/zAUBgNVHREEDTALgglsb2NhbGhvc3QwBQYDK2VwA0EAnMn3HbpwwPj5
    \\fB43amhTujMvM5GDAjAuwkDujf4d27Nuq4cr/oi0q95n1r4k7KnLyoClrodc3EkY
    \\Xh6NHG0hDA==
    \\-----END CERTIFICATE-----
;
const ed25519_key =
    \\-----BEGIN PRIVATE KEY-----
    \\MC4CAQAwBQYDK2VwBCIEILztkUJ1ZEn2x5XmjH02yEJpFIdN5ujlkWGyjjJIQYFn
    \\-----END PRIVATE KEY-----
;
const p256_cert =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBkzCCATmgAwIBAgIUPCWLAsB7GcZcvQ3JqcirE0GJc80wCgYIKoZIzj0EAwIw
    \\FDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MDkxNzE5MjQwNFoXDTM2MDkxNDE5
    \\MjQwNFowFDESMBAGA1UEAwwJbG9jYWxob3N0MFkwEwYHKoZIzj0CAQYIKoZIzj0D
    \\AQcDQgAEP9ucSLjvAqikj6cJbHUZSX7Jd+paTMQo6Sx7Tj1JBCSaPAeJorY1uohH
    \\3EvRzIVvCZiyrSymw5dlO8XE0MwRrqNpMGcwHQYDVR0OBBYEFLjBpl1c1rBeJDtB
    \\FR+Jp7Iwp9s2MB8GA1UdIwQYMBaAFLjBpl1c1rBeJDtBFR+Jp7Iwp9s2MA8GA1Ud
    \\EwEB/wQFMAMBAf8wFAYDVR0RBA0wC4IJbG9jYWxob3N0MAoGCCqGSM49BAMCA0gA
    \\MEUCIF+L1J0A1jEgRGMpLc1noqtxpSToFpzK2TDZ1+lYOZeZAiEAsfVkyDP7QW2T
    \\CyzWDpHpefKfCpbqBXjj50Y/sc+LgdA=
    \\-----END CERTIFICATE-----
;
const p256_key =
    \\-----BEGIN PRIVATE KEY-----
    \\MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg3W0DXO8nFwCwcVQ9
    \\sn0332wYzHzNPbLh8U4EBzBhniWhRANCAAQ/25xIuO8CqKSPpwlsdRlJfsl36lpM
    \\xCjpLHtOPUkEJJo8B4mitjW6iEfcS9HMhW8JmLKtLKbDl2U7xcTQzBGu
    \\-----END PRIVATE KEY-----
;

/// A pair of pipes: one end the brick reads and writes, the other Zig's `tls.Client` does, so a
/// test drives a real handshake with no socket of the operating system's under it.
const Pair = struct {
    to_server: [2]std.posix.fd_t,
    to_client: [2]std.posix.fd_t,

    fn open() !Pair {
        var a: [2]std.posix.fd_t = undefined;
        var b: [2]std.posix.fd_t = undefined;
        try socketPair(&a);
        errdefer {
            _ = std.posix.system.close(a[0]);
            _ = std.posix.system.close(a[1]);
        }
        try socketPair(&b);
        return .{ .to_server = a, .to_client = b };
    }

    fn close(p: *Pair) void {
        for ([_]std.posix.fd_t{ p.to_server[0], p.to_server[1], p.to_client[0], p.to_client[1] }) |fd| {
            _ = std.posix.system.close(fd);
        }
    }
};

fn socketPair(out: *[2]std.posix.fd_t) !void {
    var fds: [2]i32 = undefined;
    const rc = std.posix.system.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds);
    if (std.posix.errno(rc) != .SUCCESS) return error.SocketPairFailed;
    out[0] = fds[0];
    out[1] = fds[1];
}

/// A write that gives up rather than hanging a test, as `readSomeFd` does: a peer that stops
/// reading for thirty seconds fills the socket's buffer, and that is a hang, not slowness.
fn writeAllFd(fd: std.posix.fd_t, bytes: []const u8) !void {
    var at: usize = 0;
    while (at < bytes.len) {
        var p = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.OUT, .revents = 0 }};
        if (try std.posix.poll(&p, 30_000) == 0) return error.TestTimedOut;
        const rc = std.posix.system.write(fd, bytes[at..].ptr, bytes.len - at);
        if (std.posix.errno(rc) != .SUCCESS) return error.WriteFailed;
        if (rc == 0) return error.WriteFailed;
        at += @intCast(rc);
    }
}

/// A read that gives up rather than hanging a test: thirty seconds is far past any of these.
fn readSomeFd(fd: std.posix.fd_t, dest: []u8) !usize {
    var p = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.IN, .revents = 0 }};
    if (try std.posix.poll(&p, 30_000) == 0) return error.TestTimedOut;
    const rc = std.posix.system.read(fd, dest.ptr, dest.len);
    if (std.posix.errno(rc) != .SUCCESS) return error.ReadFailed;
    return @intCast(rc);
}

/// What the client thread does: a whole TLS session against the brick, then its result.
const ClientRun = struct {
    /// Bytes the client writes to the server after the handshake, and reads back.
    echo_size: usize,
    /// It asks for a key update halfway when this is set.
    key_update: bool = false,
    in_fd: std.posix.fd_t,
    out_fd: std.posix.fd_t,
    failed: ?anyerror = null,
    round_tripped: bool = false,

    fn run(r: *ClientRun) void {
        r.session() catch |err| {
            r.failed = err;
            // The server's loop reads until the stream ends: a client that gave up hangs up.
            _ = std.posix.system.shutdown(r.out_fd, std.posix.SHUT.WR);
        };
    }

    fn session(r: *ClientRun) !void {
        var in_buf: [tls.max_ciphertext_record_len]u8 = undefined;
        var out_buf: [tls.max_ciphertext_record_len]u8 = undefined;
        const in_file: std.Io.File = .{ .handle = r.in_fd, .flags = .{ .nonblocking = false } };
        const out_file: std.Io.File = .{ .handle = r.out_fd, .flags = .{ .nonblocking = false } };
        var reader = in_file.readerStreaming(testing.io, &in_buf);
        var writer = out_file.writerStreaming(testing.io, &out_buf);
        var client_entropy: [tls.Client.Options.entropy_len]u8 = undefined;
        entropy(&client_entropy);
        const write_buffer = try testing.allocator.alloc(u8, tls.max_ciphertext_record_len);
        defer testing.allocator.free(write_buffer);
        const read_buffer = try testing.allocator.alloc(u8, tls.max_ciphertext_record_len);
        defer testing.allocator.free(read_buffer);
        var client = try tls.Client.init(&reader.interface, &writer.interface, .{
            .host = .{ .explicit = "localhost" },
            .ca = .self_signed,
            .write_buffer = write_buffer,
            .read_buffer = read_buffer,
            .entropy = &client_entropy,
            .realtime_now = std.Io.Timestamp.now(testing.io, .real),
        });

        const sent = try testing.allocator.alloc(u8, r.echo_size);
        defer testing.allocator.free(sent);
        for (sent, 0..) |*b, i| b.* = @truncate(i *% 31 +% 7);
        try client.writer.writeAll(sent);
        // Client.flush only turns the plaintext into records; the socket's writer needs its own.
        try client.writer.flush();
        try writer.interface.flush();

        const back = try testing.allocator.alloc(u8, r.echo_size);
        defer testing.allocator.free(back);
        try client.reader.readSliceAll(back);
        r.round_tripped = mem.eql(u8, sent, back);
        try client.end();
        try writer.interface.flush();
    }
};

/// Zig's client on its own thread over a fresh pair. `stop` shuts every end both ways, which
/// ends any read or write the client is blocked in, and joins; the tests defer it, so a test that
/// fails early still leaves no thread behind, and a client stuck on a quiet pipe cannot outlive
/// the main thread's own thirty-second bounds.
const ClientThread = struct {
    pair: Pair,
    run: ClientRun,
    thread: ?std.Thread = null,

    fn start(c: *ClientThread, echo_size: usize) !void {
        c.pair = try Pair.open();
        errdefer c.pair.close();
        c.run = .{ .echo_size = echo_size, .in_fd = c.pair.to_client[0], .out_fd = c.pair.to_server[1] };
        c.thread = try std.Thread.spawn(.{}, ClientRun.run, .{&c.run});
    }

    fn join(c: *ClientThread) void {
        if (c.thread) |t| t.join();
        c.thread = null;
    }

    fn stop(c: *ClientThread) void {
        for ([_]std.posix.fd_t{ c.pair.to_server[0], c.pair.to_server[1], c.pair.to_client[0], c.pair.to_client[1] }) |fd| {
            _ = std.posix.system.shutdown(fd, std.posix.SHUT.RDWR);
        }
        c.join();
    }

    fn deinit(c: *ClientThread) void {
        c.stop();
        c.pair.close();
    }
};

fn nonblock(fd: std.posix.fd_t) void {
    const linux = std.os.linux;
    const flags = linux.fcntl(fd, linux.F.GETFL, 0);
    _ = linux.fcntl(fd, linux.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
}

/// Pumps the brick as a runtime would: ciphertext off `in_fd`, ciphertext onto `out_fd`, and
/// every plaintext byte written straight back (an echo). Both ends are nonblocking and polled,
/// as the runtime's sockets are, so a megabyte in one direction never deadlocks against the
/// client's own writes.
fn serveEcho(conn: *Conn, in_fd: std.posix.fd_t, out_fd: std.posix.fd_t) !void {
    nonblock(in_fd);
    nonblock(out_fd);
    var wire: [16384]u8 = undefined;
    var plain: [16384]u8 = undefined;
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(testing.allocator);
    var n: usize = 0;
    while (true) {
        // Everything the engine has to say goes on the queue for the socket.
        while (true) {
            try testing.expectEqual(ok, mo_tls_flush(conn, &wire, wire.len, &n));
            if (n == 0) break;
            mo_tls_sent(conn, n);
            try pending.appendSlice(testing.allocator, wire[0..n]);
        }
        // Every plaintext byte goes straight back through the engine.
        var echoed = false;
        while (true) {
            const rc = mo_tls_read(conn, &plain, plain.len, &n);
            if (rc != ok or n == 0) break;
            try testing.expectEqual(ok, mo_tls_write(conn, &plain, n));
            echoed = true;
        }
        if (echoed) continue;
        if (conn.phase == .over or conn.phase == .broken) {
            // The close_notify or the alert still has to reach the client.
            var at: usize = 0;
            while (at < pending.items.len) {
                var p = [_]std.posix.pollfd{.{ .fd = out_fd, .events = std.posix.POLL.OUT, .revents = 0 }};
                if (try std.posix.poll(&p, 30_000) == 0) return error.TestTimedOut;
                const rc = std.posix.system.write(out_fd, pending.items[at..].ptr, pending.items.len - at);
                if (std.posix.errno(rc) != .SUCCESS) break;
                at += @intCast(rc);
            }
            return;
        }
        var fds: [2]std.posix.pollfd = .{
            .{ .fd = in_fd, .events = std.posix.POLL.IN, .revents = 0 },
            .{ .fd = out_fd, .events = std.posix.POLL.OUT, .revents = 0 },
        };
        const watched = fds[0..if (pending.items.len > 0) @as(usize, 2) else 1];
        // Thirty seconds is far past any of these tests; reaching it is a hang, not slowness.
        if (try std.posix.poll(watched, 30_000) == 0) return error.TestTimedOut;
        if (pending.items.len > 0 and watched.len == 2 and watched[1].revents & std.posix.POLL.OUT != 0) {
            const rc = std.posix.system.write(out_fd, pending.items.ptr, pending.items.len);
            if (std.posix.errno(rc) == .SUCCESS) {
                const wrote: usize = @intCast(rc);
                std.mem.copyForwards(u8, pending.items, pending.items[wrote..]);
                pending.items.len -= wrote;
            } else if (std.posix.errno(rc) != .AGAIN) return;
        }
        if (watched[0].revents & (std.posix.POLL.IN | std.posix.POLL.HUP) == 0) continue;
        const rc = std.posix.system.read(in_fd, &wire, wire.len);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {},
            .AGAIN => continue,
            else => return,
        }
        const got: usize = @intCast(rc);
        if (got == 0) return;
        if (mo_tls_feed(conn, &wire, got) == failed) {
            try testing.expectEqual(ok, mo_tls_flush(conn, &wire, wire.len, &n));
            if (n > 0) {
                mo_tls_sent(conn, n);
                // A client that already hung up leaves nobody to hear the alert; a client that
                // stopped reading for thirty seconds is a hang, and says so.
                writeAllFd(out_fd, wire[0..n]) catch |err| if (err == error.TestTimedOut) return err;
            }
            return;
        }
    }
}

/// One session of Zig's own `tls.Client` against the brick's server, the suite the server's
/// preference forces (Zig's client offers both): `size` bytes to the server and back, then the
/// client's close_notify. Zig's answer when it gave up, or null for a whole session.
fn sessionWithZigClient(cert: []const u8, key: []const u8, suite: Suite, size: usize) !?anyerror {
    const server = mo_tls_server_new(cert.ptr, cert.len, key.ptr, key.len) orelse return error.BadPem;
    defer mo_tls_server_free(server);
    server.prefer = suite;
    const conn = mo_tls_conn_new(server) orelse return error.OutOfMemory;
    defer mo_tls_conn_free(conn);

    var client: ClientThread = undefined;
    try client.start(size);
    defer client.deinit();
    const served = serveEcho(conn, client.pair.to_server[0], client.pair.to_client[1]);
    // The client's read ends when the server's end of the pipe closes.
    _ = std.posix.system.shutdown(client.pair.to_client[1], std.posix.SHUT.WR);
    client.join();
    try served;
    try testing.expectEqual(suite, conn.suite);
    if (client.run.failed) |err| {
        // Zig's client gave up without an alert: the brick is left waiting for its Finished.
        try testing.expectEqual(Phase.wait_finished, conn.phase);
        return @as(?anyerror, err);
    }
    try testing.expect(client.run.round_tripped);
    // The client's `end` sends close_notify, so a whole session leaves the connection over.
    try testing.expectEqual(Phase.over, conn.phase);
    return null;
}

/// Both suites and both key types against Zig's client, an implementation that shares none of
/// the brick's record layer or key schedule. Zig 0.16's client cannot check an Ed25519
/// CertificateVerify: `Client.zig`'s `verifySignature` maps only the ECDSA and RSA schemes to a
/// key algorithm and answers `TlsBadSignatureScheme` for `.ed25519` (line 1549), although its
/// ClientHello offers the scheme. So the two Ed25519 sessions run to exactly that answer: Zig has
/// read the brick's ServerHello, its EncryptedExtensions, and its certificate (checked as
/// self-signed with Zig's own `Certificate.verify`) under the brick's handshake keys, and stops at
/// the one message it has no code for. The whole Ed25519 session is held against OpenSSL in
/// `bench/step37/diff.py` and against the brick's own client below.
fn zigClientMatrix(size: usize) !void {
    for ([_]Suite{ .aes_128_gcm, .chacha20_poly1305 }) |suite| {
        try testing.expectEqual(@as(?anyerror, null), try sessionWithZigClient(p256_cert, p256_key, suite, size));
        try testing.expectEqual(@as(?anyerror, error.TlsBadSignatureScheme), try sessionWithZigClient(ed25519_cert, ed25519_key, suite, size));
    }
}

test "a handshake and a megabyte both ways against Zig's own client, each suite and each key type" {
    try zigClientMatrix(1 << 20);
}

test "a small handshake against Zig's own client, each suite and each key type" {
    try zigClientMatrix(5);
}

/// A ClientHello the tests build by hand, offering one suite and one X25519 share.
fn helloBytes(out: []u8, suite: Suite, groups: []const tls.NamedGroup, share: ?[32]u8, version: u16) usize {
    var n: usize = 0;
    const body_at = n + 4;
    out[0] = @intFromEnum(tls.HandshakeType.client_hello);
    n = body_at;
    put16(out[n..], @intFromEnum(tls.ProtocolVersion.tls_1_2));
    n += 2;
    @memset(out[n..][0..32], 0xab);
    n += 32;
    out[n] = 32;
    n += 1;
    @memset(out[n..][0..32], 0xcd);
    n += 32;
    put16(out[n..], 2);
    n += 2;
    put16(out[n..], @intFromEnum(suite.tag()));
    n += 2;
    out[n] = 1;
    n += 1;
    out[n] = 0;
    n += 1;
    const exts_at = n;
    n += 2;
    // supported_versions
    put16(out[n..], @intFromEnum(tls.ExtensionType.supported_versions));
    n += 2;
    put16(out[n..], 3);
    n += 2;
    out[n] = 2;
    n += 1;
    put16(out[n..], version);
    n += 2;
    // signature_algorithms: both the brick can make
    put16(out[n..], @intFromEnum(tls.ExtensionType.signature_algorithms));
    n += 2;
    put16(out[n..], 6);
    n += 2;
    put16(out[n..], 4);
    n += 2;
    put16(out[n..], @intFromEnum(tls.SignatureScheme.ed25519));
    n += 2;
    put16(out[n..], @intFromEnum(tls.SignatureScheme.ecdsa_secp256r1_sha256));
    n += 2;
    // supported_groups
    put16(out[n..], @intFromEnum(tls.ExtensionType.supported_groups));
    n += 2;
    put16(out[n..], @intCast(2 + 2 * groups.len));
    n += 2;
    put16(out[n..], @intCast(2 * groups.len));
    n += 2;
    for (groups) |g| {
        put16(out[n..], @intFromEnum(g));
        n += 2;
    }
    // key_share
    put16(out[n..], @intFromEnum(tls.ExtensionType.key_share));
    n += 2;
    const share_len: usize = if (share == null) 0 else 2 + 2 + 32;
    put16(out[n..], @intCast(2 + share_len));
    n += 2;
    put16(out[n..], @intCast(share_len));
    n += 2;
    if (share) |key| {
        put16(out[n..], @intFromEnum(tls.NamedGroup.x25519));
        n += 2;
        put16(out[n..], 32);
        n += 2;
        @memcpy(out[n..][0..32], &key);
        n += 32;
    }
    put16(out[exts_at..], @intCast(n - exts_at - 2));
    mem.writeInt(u24, out[1..4], @intCast(n - body_at), .big);
    return n;
}

fn recordBytes(out: []u8, ct: tls.ContentType, payload: []const u8) usize {
    out[0] = @intFromEnum(ct);
    out[1] = 0x03;
    out[2] = 0x01;
    put16(out[3..5], @intCast(payload.len));
    @memcpy(out[5..][0..payload.len], payload);
    return 5 + payload.len;
}

fn testServer() *Server {
    return mo_tls_server_new(ed25519_cert.ptr, ed25519_cert.len, ed25519_key.ptr, ed25519_key.len).?;
}

/// The pair Zig's own client can check: its `verifySignature` has no Ed25519 arm.
fn testServerP256() *Server {
    return mo_tls_server_new(p256_cert.ptr, p256_cert.len, p256_key.ptr, p256_key.len).?;
}

test "a truncated record waits, and never answers on its own" {
    const server = testServer();
    defer mo_tls_server_free(server);
    const conn = mo_tls_conn_new(server).?;
    defer mo_tls_conn_free(conn);
    var hello: [512]u8 = undefined;
    const hello_n = helloBytes(&hello, .aes_128_gcm, &.{.x25519}, @as([32]u8, @splat(9)), @intFromEnum(tls.ProtocolVersion.tls_1_3));
    var rec: [600]u8 = undefined;
    const rec_n = recordBytes(&rec, .handshake, hello[0..hello_n]);
    // Everything but the last byte: the brick answers nothing and waits.
    try testing.expectEqual(ok, mo_tls_feed(conn, &rec, rec_n - 1));
    try testing.expectEqual(@as(usize, 0), mo_tls_pending(conn));
    try testing.expect(!mo_tls_ready(conn));
    var got: usize = 0;
    var out: [64]u8 = undefined;
    try testing.expectEqual(want_more, mo_tls_read(conn, &out, out.len, &got));
    // The last byte completes it and the flight goes out.
    try testing.expectEqual(ok, mo_tls_feed(conn, rec[rec_n - 1 ..].ptr, 1));
    try testing.expect(mo_tls_pending(conn) > 0);
}

test "a record past 16 KiB plus 256 is record_overflow" {
    const server = testServer();
    defer mo_tls_server_free(server);
    const conn = mo_tls_conn_new(server).?;
    defer mo_tls_conn_free(conn);
    var header: [5]u8 = .{ @intFromEnum(tls.ContentType.handshake), 0x03, 0x03, 0, 0 };
    put16(header[3..5], max_ciphertext + 1);
    try testing.expectEqual(failed, mo_tls_feed(conn, &header, header.len));
    try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.record_overflow)), mo_tls_alert(conn));
    try testing.expect(mo_tls_pending(conn) > 0);
}

test "a plain HTTP request is unexpected_message" {
    const server = testServer();
    defer mo_tls_server_free(server);
    const conn = mo_tls_conn_new(server).?;
    defer mo_tls_conn_free(conn);
    const request = "GET / HTTP/1.1\r\nhost: localhost\r\n\r\n";
    try testing.expectEqual(failed, mo_tls_feed(conn, request.ptr, request.len));
    try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.unexpected_message)), mo_tls_alert(conn));
}

test "a client with no TLS 1.3 is protocol_version" {
    const server = testServer();
    defer mo_tls_server_free(server);
    const conn = mo_tls_conn_new(server).?;
    defer mo_tls_conn_free(conn);
    var hello: [512]u8 = undefined;
    const hello_n = helloBytes(&hello, .aes_128_gcm, &.{.x25519}, @as([32]u8, @splat(9)), @intFromEnum(tls.ProtocolVersion.tls_1_2));
    var rec: [600]u8 = undefined;
    const rec_n = recordBytes(&rec, .handshake, hello[0..hello_n]);
    try testing.expectEqual(failed, mo_tls_feed(conn, &rec, rec_n));
    try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.protocol_version)), mo_tls_alert(conn));
}

test "a client with no X25519 at all is handshake_failure" {
    const server = testServer();
    defer mo_tls_server_free(server);
    const conn = mo_tls_conn_new(server).?;
    defer mo_tls_conn_free(conn);
    var hello: [512]u8 = undefined;
    const hello_n = helloBytes(&hello, .aes_128_gcm, &.{.secp256r1}, null, @intFromEnum(tls.ProtocolVersion.tls_1_3));
    var rec: [600]u8 = undefined;
    const rec_n = recordBytes(&rec, .handshake, hello[0..hello_n]);
    try testing.expectEqual(failed, mo_tls_feed(conn, &rec, rec_n));
    try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.handshake_failure)), mo_tls_alert(conn));
}

test "a client that supports X25519 but shares none gets one HelloRetryRequest" {
    const server = testServer();
    defer mo_tls_server_free(server);
    const conn = mo_tls_conn_new(server).?;
    defer mo_tls_conn_free(conn);
    var hello: [512]u8 = undefined;
    const hello_n = helloBytes(&hello, .aes_128_gcm, &.{ .secp256r1, .x25519 }, null, @intFromEnum(tls.ProtocolVersion.tls_1_3));
    var rec: [600]u8 = undefined;
    const rec_n = recordBytes(&rec, .handshake, hello[0..hello_n]);
    try testing.expectEqual(ok, mo_tls_feed(conn, &rec, rec_n));
    var out: [1024]u8 = undefined;
    var got: usize = 0;
    try testing.expectEqual(ok, mo_tls_flush(conn, &out, out.len, &got));
    // A ServerHello whose random is the HelloRetryRequest sequence, then the compatibility CCS.
    try testing.expect(got > 5 + 4 + 2 + 32);
    try testing.expectEqual(@intFromEnum(tls.ContentType.handshake), out[0]);
    try testing.expectEqual(@intFromEnum(tls.HandshakeType.server_hello), out[5]);
    try testing.expectEqualSlices(u8, &tls.hello_retry_request_sequence, out[11..43]);
    // A second hello with no share again: one retry and no more.
    try testing.expectEqual(failed, mo_tls_feed(conn, &rec, rec_n));
    try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.illegal_parameter)), mo_tls_alert(conn));
}

test "a wrong Finished is decrypt_error, and a bad tag is bad_record_mac" {
    // Both are driven through Zig's client, whose flight is right up to the byte we spoil.
    for ([_]enum { finished, tag }{ .finished, .tag }) |spoil| {
        const server = testServerP256();
        defer mo_tls_server_free(server);
        const conn = mo_tls_conn_new(server).?;
        defer mo_tls_conn_free(conn);

        var client: ClientThread = undefined;
        try client.start(1);
        defer client.deinit();
        const pair = &client.pair;

        var wire: [8192]u8 = undefined;
        var n: usize = 0;
        // The server's flight, then the client's answer, whose last record we spoil.
        while (!mo_tls_ready(conn) and conn.phase != .broken) {
            while (true) {
                try testing.expectEqual(ok, mo_tls_flush(conn, &wire, wire.len, &n));
                if (n == 0) break;
                mo_tls_sent(conn, n);
                try writeAllFd(pair.to_client[1], wire[0..n]);
            }
            const got = readSomeFd(pair.to_server[0], &wire) catch |err| switch (err) {
                error.TestTimedOut => return err,
                else => break,
            };
            if (got == 0) break;
            // Spoiling the client's Finished record: its last byte is the tag's, and a byte in
            // the middle of the ciphertext is the verify data's once the tag is recomputed --
            // which we cannot do, so `finished` spoils a byte the client's own MAC covers and
            // `tag` the tag. The brick must answer bad_record_mac for both; the decrypt_error
            // case is driven by hand below.
            var bytes = wire[0..got];
            if (conn.phase == .wait_finished and got > 6) {
                switch (spoil) {
                    .finished => bytes[got - 3] ^= 0x01,
                    .tag => bytes[got - 1] ^= 0x01,
                }
            }
            if (mo_tls_feed(conn, bytes.ptr, got) == failed) break;
        }
        client.stop();
        try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.bad_record_mac)), mo_tls_alert(conn));
        try testing.expect(!mo_tls_ready(conn));
    }
}

test "a Finished whose verify data is wrong is decrypt_error" {
    // Driven by hand: the brick's own record layer seals a Finished with the right key and the
    // wrong data, so the tag is right and only the HMAC is wrong.
    const server = testServerP256();
    defer mo_tls_server_free(server);
    const conn = mo_tls_conn_new(server).?;
    defer mo_tls_conn_free(conn);

    var client: ClientThread = undefined;
    try client.start(1);
    defer client.deinit();
    const pair = &client.pair;
    var wire: [8192]u8 = undefined;
    var n: usize = 0;
    // The hello alone, so the client's keys are up and its Finished has not come yet.
    const hello_n = try readSomeFd(pair.to_server[0], &wire);
    _ = mo_tls_feed(conn, &wire, hello_n);
    while (true) {
        try testing.expectEqual(ok, mo_tls_flush(conn, &wire, wire.len, &n));
        if (n == 0) break;
        mo_tls_sent(conn, n);
        try writeAllFd(pair.to_client[1], wire[0..n]);
    }
    // A Finished of 32 zero bytes, sealed under the client's own handshake key.
    var forged: Cipher = conn.read_cipher;
    var body: [4 + 32 + 1]u8 = @splat(0);
    body[0] = @intFromEnum(tls.HandshakeType.finished);
    mem.writeInt(u24, body[1..4], 32, .big);
    body[36] = @intFromEnum(tls.ContentType.handshake);
    var rec: [5 + 37 + tag_len]u8 = undefined;
    rec[0] = @intFromEnum(tls.ContentType.application_data);
    rec[1] = 0x03;
    rec[2] = 0x03;
    put16(rec[3..5], 37 + tag_len);
    forged.seal(conn.suite, rec[5..42], rec[42..58], &body, rec[0..5]);
    try testing.expectEqual(failed, mo_tls_feed(conn, &rec, rec.len));
    try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.decrypt_error)), mo_tls_alert(conn));
    client.stop();
}

test "a KeyUpdate round trip" {
    const server = testServerP256();
    defer mo_tls_server_free(server);
    const conn = mo_tls_conn_new(server).?;
    defer mo_tls_conn_free(conn);

    var client: ClientThread = undefined;
    try client.start(16);
    defer client.deinit();
    const pair = &client.pair;
    var wire: [8192]u8 = undefined;
    var n: usize = 0;
    while (!mo_tls_ready(conn) and conn.phase != .broken) {
        while (true) {
            try testing.expectEqual(ok, mo_tls_flush(conn, &wire, wire.len, &n));
            if (n == 0) break;
            // Without this the engine hands back the same flight forever: the client rejects
            // the second copy, stops reading, and the pipe fills under this loop.
            mo_tls_sent(conn, n);
            try writeAllFd(pair.to_client[1], wire[0..n]);
        }
        if (mo_tls_ready(conn)) break;
        const got = readSomeFd(pair.to_server[0], &wire) catch |err| switch (err) {
            error.TestTimedOut => return err,
            else => break,
        };
        if (got == 0) break;
        _ = mo_tls_feed(conn, &wire, got);
    }
    try testing.expect(mo_tls_ready(conn));

    // The client asks us to update: our read keys move, and a KeyUpdate goes back with ours.
    const before_read = conn.read_cipher.key;
    const before_write = conn.write_cipher.key;
    var forged: Cipher = conn.read_cipher;
    var body: [5 + 1]u8 = undefined;
    body[0] = @intFromEnum(tls.HandshakeType.key_update);
    mem.writeInt(u24, body[1..4], 1, .big);
    body[4] = @intFromEnum(tls.KeyUpdateRequest.update_requested);
    body[5] = @intFromEnum(tls.ContentType.handshake);
    var rec: [5 + 6 + tag_len]u8 = undefined;
    rec[0] = @intFromEnum(tls.ContentType.application_data);
    rec[1] = 0x03;
    rec[2] = 0x03;
    put16(rec[3..5], 6 + tag_len);
    forged.seal(conn.suite, rec[5..11], rec[11..27], &body, rec[0..5]);
    try testing.expectEqual(ok, mo_tls_feed(conn, &rec, rec.len));
    try testing.expect(!mem.eql(u8, &before_read, &conn.read_cipher.key));
    try testing.expect(!mem.eql(u8, &before_write, &conn.write_cipher.key));
    try testing.expectEqual(@as(u64, 0), conn.read_cipher.seq);
    try testing.expect(mo_tls_pending(conn) > 0);

    client.stop();
}

test "PEM: a chain, a key, and the pair that does not match" {
    const good = mo_tls_server_new(ed25519_cert.ptr, ed25519_cert.len, ed25519_key.ptr, ed25519_key.len);
    try testing.expect(good != null);
    mo_tls_server_free(good);

    const p256 = mo_tls_server_new(p256_cert.ptr, p256_cert.len, p256_key.ptr, p256_key.len);
    try testing.expect(p256 != null);
    mo_tls_server_free(p256);

    // The other pair's key.
    try testing.expect(mo_tls_server_new(ed25519_cert.ptr, ed25519_cert.len, p256_key.ptr, p256_key.len) == null);
    try testing.expect(mo_tls_server_new(p256_cert.ptr, p256_cert.len, ed25519_key.ptr, ed25519_key.len) == null);
    // Text that is not PEM, PEM with no block, and a block whose base64 is spoiled.
    try testing.expect(mo_tls_server_new("hello", 5, ed25519_key.ptr, ed25519_key.len) == null);
    try testing.expect(mo_tls_server_new(ed25519_cert.ptr, ed25519_cert.len, "hello", 5) == null);
    const spoiled = "-----BEGIN CERTIFICATE-----\n!!!!\n-----END CERTIFICATE-----\n";
    try testing.expect(mo_tls_server_new(spoiled.ptr, spoiled.len, ed25519_key.ptr, ed25519_key.len) == null);
}

// RFC 8448 section 3's derived secrets. The trace is a client's; the key schedule is the one
// both ends run, so the brick's own steps must reach the same bytes from the same inputs.
test "RFC 8448 section 3: the key schedule's derived secrets" {
    const zeroes: [32]u8 = @splat(0);
    const early = HkdfSha256.extract(&[1]u8{0}, &zeroes);
    try testing.expectEqualSlices(u8, &hex("33ad0a1c607ec03b09e6cd9893680ce210adf300aa1f2660e1b22e10f170f92a"), &early);

    const empty = tls.emptyHash(Sha256);
    try testing.expectEqualSlices(u8, &hex("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), &empty);

    const hs_derived = tls.hkdfExpandLabel(HkdfSha256, early, "derived", &empty, 32);
    try testing.expectEqualSlices(u8, &hex("6f2615a108c702c5678f54fc9dbab69716c076189c48250cebeac3576c3611ba"), &hs_derived);

    const shared = hex("8bd4054fb55b9d63fdfbacf9f04b9f0d35e6d63f537563efd46272900f89492d");
    const handshake_secret = HkdfSha256.extract(&hs_derived, &shared);
    try testing.expectEqualSlices(u8, &hex("1dc826e93606aa6fdc0aadc12f741b01046aa6b99f691ed221a9f0ca043fbeac"), &handshake_secret);

    const hello_hash = hex("860c06edc07858ee8e78f0e7428c58edd6b43f2ca3e6e95f02ed063cf0e1cad8");
    const c_hs = tls.hkdfExpandLabel(HkdfSha256, handshake_secret, "c hs traffic", &hello_hash, 32);
    try testing.expectEqualSlices(u8, &hex("b3eddb126e067f35a780b3abf45e2d8f3b1a950738f52e9600746a0e27a55a21"), &c_hs);
    const s_hs = tls.hkdfExpandLabel(HkdfSha256, handshake_secret, "s hs traffic", &hello_hash, 32);
    try testing.expectEqualSlices(u8, &hex("b67b7d690cc16c4e75e54213cb2d37b4e9c912bcded9105d42befd59d391ad38"), &s_hs);

    // The server's handshake write keys, as `Cipher.derive` takes them.
    var write: Cipher = .{};
    write.derive(.aes_128_gcm, s_hs);
    try testing.expectEqualSlices(u8, &hex("3fce516009c21727d0f2e4e86ee403bc"), write.key[0..16]);
    try testing.expectEqualSlices(u8, &hex("5d313eb2671276ee13000b30"), &write.iv);

    const ap_derived = tls.hkdfExpandLabel(HkdfSha256, handshake_secret, "derived", &empty, 32);
    try testing.expectEqualSlices(u8, &hex("43de77e0c77713859a944db9db2590b53190a65b3ee2e4f12dd7a0bb7ce254b4"), &ap_derived);
    const master_secret = HkdfSha256.extract(&ap_derived, &zeroes);
    try testing.expectEqualSlices(u8, &hex("18df06843d13a08bf2a449844c5f8a478001bc4d4c627984d5a41da8d0402919"), &master_secret);

    const handshake_hash = hex("9608102a0f1ccc6db6250b7b7e417b1a000eaada3daae4777a7686c9ff83df13");
    const c_ap = tls.hkdfExpandLabel(HkdfSha256, master_secret, "c ap traffic", &handshake_hash, 32);
    try testing.expectEqualSlices(u8, &hex("9e40646ce79a7f9dc05af8889bce6552875afa0b06df0087f792ebb7c17504a5"), &c_ap);
    const s_ap = tls.hkdfExpandLabel(HkdfSha256, master_secret, "s ap traffic", &handshake_hash, 32);
    try testing.expectEqualSlices(u8, &hex("a11af9f05531f856ad47116b45a950328204b4f44bfb6b3a4b4f1f3fcb631643"), &s_ap);
}

test "a record's nonce is the IV xor the sequence number" {
    var c: Cipher = .{};
    c.iv = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
    try testing.expectEqualSlices(u8, &c.iv, &c.nonce());
    c.seq = 1;
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13 }, &c.nonce());
    c.seq = 256;
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12 }, &c.nonce());
}

// ---- a client of the tests' own, so every suite and every key type meets a whole session

/// A TLS 1.3 client just complete enough to hold up the server's half: it builds a ClientHello,
/// checks the server's flight the way a client must (the certificate's signature over the
/// transcript, the server's Finished), sends its own Finished, and then carries records both
/// ways. It shares the brick's record layer and key schedule, so it is not an independent
/// implementation: Zig's client above and OpenSSL in `bench/step36` are. What it adds is the
/// matrix -- both suites and both key types through a whole session, with no socket -- and an
/// independent statement of the client's checks.
const TestClient = struct {
    suite: Suite,
    x_secret: [32]u8,
    x_public: [32]u8,
    transcript: Sha256 = Sha256.init(.{}),
    read: Cipher = .{},
    write: Cipher = .{},
    master_secret: [32]u8 = @splat(0),
    client_hs_secret: [32]u8 = @splat(0),
    server_finished_key: [32]u8 = @splat(0),
    client_finished_key: [32]u8 = @splat(0),
    hello: [512]u8 = undefined,
    hello_len: usize = 0,
    /// Ciphertext from the server that is not yet a whole record.
    in: std.ArrayList(u8) = .empty,
    /// Plaintext the server sent.
    plain: std.ArrayList(u8) = .empty,
    /// Ciphertext for the server.
    out: std.ArrayList(u8) = .empty,
    state: enum { hello, flight, running } = .hello,
    /// The certificate the server presented, leaf first.
    leaf: []u8 = &.{},

    fn init(suite: Suite, seed: [32]u8) TestClient {
        const kp = X25519.KeyPair.generateDeterministic(seed) catch unreachable;
        var c: TestClient = .{ .suite = suite, .x_secret = seed, .x_public = kp.public_key };
        c.hello_len = helloBytes(&c.hello, suite, &.{.x25519}, kp.public_key, @intFromEnum(tls.ProtocolVersion.tls_1_3));
        c.transcript.update(c.hello[0..c.hello_len]);
        return c;
    }

    fn deinit(c: *TestClient) void {
        c.in.deinit(testing.allocator);
        c.plain.deinit(testing.allocator);
        c.out.deinit(testing.allocator);
        if (c.leaf.len > 0) testing.allocator.free(c.leaf);
    }

    /// The ClientHello as one record, the first thing the server is fed.
    fn firstRecord(c: *TestClient, buf: []u8) []u8 {
        return buf[0..recordBytes(buf, .handshake, c.hello[0..c.hello_len])];
    }

    fn sealRecord(c: *TestClient, inner: tls.ContentType, payload: []const u8) !void {
        const body_len = payload.len + 1 + tag_len;
        const at = c.out.items.len;
        try c.out.resize(testing.allocator, at + record_header_len + body_len);
        const dest = c.out.items[at..];
        dest[0] = @intFromEnum(tls.ContentType.application_data);
        dest[1] = 0x03;
        dest[2] = 0x03;
        put16(dest[3..5], @intCast(body_len));
        const inner_buf = dest[record_header_len..][0 .. payload.len + 1];
        @memcpy(inner_buf[0..payload.len], payload);
        inner_buf[payload.len] = @intFromEnum(inner);
        c.write.seal(c.suite, inner_buf, dest[record_header_len + payload.len + 1 ..][0..tag_len], inner_buf, dest[0..record_header_len]);
    }

    fn write_(c: *TestClient, bytes: []const u8) !void {
        var at: usize = 0;
        while (at < bytes.len) {
            const n = @min(max_plaintext, bytes.len - at);
            try c.sealRecord(.application_data, bytes[at..][0..n]);
            at += n;
        }
    }

    /// Ciphertext from the server: every whole record it holds is read.
    fn feed(c: *TestClient, bytes: []const u8) !void {
        try c.in.appendSlice(testing.allocator, bytes);
        var at: usize = 0;
        while (c.in.items.len - at >= record_header_len) {
            const header = c.in.items[at..][0..record_header_len];
            const len = mem.readInt(u16, header[3..5], .big);
            if (c.in.items.len - at - record_header_len < len) break;
            const body = c.in.items[at + record_header_len ..][0..len];
            try c.record(@enumFromInt(header[0]), header, body);
            at += record_header_len + len;
        }
        if (at > 0) {
            mem.copyForwards(u8, c.in.items, c.in.items[at..]);
            c.in.items.len -= at;
        }
    }

    fn record(c: *TestClient, ct: tls.ContentType, header: []const u8, body: []u8) !void {
        if (ct == .change_cipher_spec) return;
        if (c.state == .hello) {
            try testing.expectEqual(tls.ContentType.handshake, ct);
            return c.serverHello(body);
        }
        try testing.expectEqual(tls.ContentType.application_data, ct);
        const cipher_len = body.len - tag_len;
        const cleartext = try testing.allocator.alloc(u8, cipher_len);
        defer testing.allocator.free(cleartext);
        try testing.expect(c.read.open(c.suite, cleartext, body[0..cipher_len], body[cipher_len..][0..tag_len].*, header));
        const trimmed = mem.trimEnd(u8, cleartext, "\x00");
        const inner: tls.ContentType = @enumFromInt(trimmed[trimmed.len - 1]);
        const content = trimmed[0 .. trimmed.len - 1];
        switch (inner) {
            .application_data => try c.plain.appendSlice(testing.allocator, content),
            .handshake => try c.handshake(content),
            .alert => {
                try testing.expectEqual(@as(usize, 2), content.len);
                try testing.expectEqual(@intFromEnum(tls.Alert.Description.close_notify), content[1]);
            },
            else => return error.UnexpectedRecord,
        }
    }

    fn serverHello(c: *TestClient, body: []const u8) !void {
        var cur: Cursor = .{ .b = body };
        try testing.expectEqual(@intFromEnum(tls.HandshakeType.server_hello), try cur.u8_());
        _ = try cur.u24_();
        _ = try cur.u16_(); // legacy_version
        _ = try cur.take(32); // random
        _ = try cur.vec(u8); // legacy_session_id_echo
        try testing.expectEqual(@intFromEnum(c.suite.tag()), try cur.u16_());
        _ = try cur.u8_(); // legacy_compression_method
        var exts: Cursor = .{ .b = try cur.vec(u16) };
        var server_share: ?[32]u8 = null;
        while (!exts.done()) {
            const et: tls.ExtensionType = @enumFromInt(try exts.u16_());
            var ext: Cursor = .{ .b = try exts.vec(u16) };
            if (et == .key_share) {
                try testing.expectEqual(@intFromEnum(tls.NamedGroup.x25519), try ext.u16_());
                server_share = (try ext.vec(u16))[0..32].*;
            }
        }
        c.transcript.update(body);

        const shared = try X25519.scalarmult(c.x_secret, server_share.?);
        const zeroes: [32]u8 = @splat(0);
        const empty = tls.emptyHash(Sha256);
        const early = HkdfSha256.extract(&[1]u8{0}, &zeroes);
        const handshake_secret = HkdfSha256.extract(&tls.hkdfExpandLabel(HkdfSha256, early, "derived", &empty, 32), &shared);
        c.master_secret = HkdfSha256.extract(&tls.hkdfExpandLabel(HkdfSha256, handshake_secret, "derived", &empty, 32), &zeroes);
        const hello_hash = c.transcript.peek();
        const client_secret = tls.hkdfExpandLabel(HkdfSha256, handshake_secret, "c hs traffic", &hello_hash, 32);
        const server_secret = tls.hkdfExpandLabel(HkdfSha256, handshake_secret, "s hs traffic", &hello_hash, 32);
        c.client_finished_key = tls.hkdfExpandLabel(HkdfSha256, client_secret, "finished", "", 32);
        c.server_finished_key = tls.hkdfExpandLabel(HkdfSha256, server_secret, "finished", "", 32);
        c.client_hs_secret = client_secret;
        c.read.derive(c.suite, server_secret);
        c.write.derive(c.suite, client_secret);
        c.state = .flight;
    }

    fn handshake(c: *TestClient, bytes: []const u8) !void {
        var cur: Cursor = .{ .b = bytes };
        while (!cur.done()) {
            const kind: tls.HandshakeType = @enumFromInt(try cur.u8_());
            const at = cur.i - 1;
            const len = try cur.u24_();
            _ = try cur.take(len);
            const whole = bytes[at..cur.i];
            switch (kind) {
                .encrypted_extensions => c.transcript.update(whole),
                .certificate => {
                    var certs: Cursor = .{ .b = whole[4..] };
                    _ = try certs.vec(u8); // certificate_request_context
                    var list: Cursor = .{ .b = try certs.vec(u24) };
                    const first = try list.vec(u24);
                    if (c.leaf.len == 0) c.leaf = try testing.allocator.dupe(u8, first);
                    c.transcript.update(whole);
                },
                .certificate_verify => try c.certificateVerify(whole),
                .finished => try c.serverFinished(whole),
                else => return error.UnexpectedHandshake,
            }
        }
    }

    /// The client's check of RFC 8446 4.4.3, written here and not taken from the brick.
    fn certificateVerify(c: *TestClient, whole: []const u8) !void {
        var signed: [64 + 33 + 1 + 32]u8 = undefined;
        @memset(signed[0..64], 0x20);
        @memcpy(signed[64..][0..33], "TLS 1.3, server CertificateVerify");
        signed[97] = 0;
        @memcpy(signed[98..][0..32], &c.transcript.peek());

        var cur: Cursor = .{ .b = whole[4..] };
        const scheme: tls.SignatureScheme = @enumFromInt(try cur.u16_());
        const signature = try cur.vec(u16);
        const cert: Certificate = .{ .buffer = c.leaf, .index = 0 };
        const parsed = try cert.parse();
        switch (scheme) {
            .ed25519 => {
                try testing.expectEqual(Certificate.AlgorithmCategory.curveEd25519, @as(Certificate.AlgorithmCategory, parsed.pub_key_algo));
                const key = try Ed25519.PublicKey.fromBytes(parsed.pubKey()[0..32].*);
                const sig: Ed25519.Signature = .fromBytes(signature[0..64].*);
                try sig.verify(&signed, key);
            },
            .ecdsa_secp256r1_sha256 => {
                try testing.expectEqual(Certificate.AlgorithmCategory.X9_62_id_ecPublicKey, @as(Certificate.AlgorithmCategory, parsed.pub_key_algo));
                const key = try EcdsaP256.PublicKey.fromSec1(parsed.pubKey());
                const sig = try EcdsaP256.Signature.fromDer(signature);
                try sig.verify(&signed, key);
            },
            else => return error.UnexpectedScheme,
        }
        c.transcript.update(whole);
    }

    fn serverFinished(c: *TestClient, whole: []const u8) !void {
        var want: [32]u8 = undefined;
        HmacSha256.create(&want, &c.transcript.peek(), &c.server_finished_key);
        try testing.expectEqualSlices(u8, &want, whole[4..36]);
        c.transcript.update(whole);

        // The server's records from here on are under the application key; ours stay under the
        // handshake key until our Finished has gone out.
        const handshake_hash = c.transcript.peek();
        c.read.derive(c.suite, tls.hkdfExpandLabel(HkdfSha256, c.master_secret, "s ap traffic", &handshake_hash, 32));

        var finished: [4 + 32]u8 = undefined;
        finished[0] = @intFromEnum(tls.HandshakeType.finished);
        mem.writeInt(u24, finished[1..4], 32, .big);
        HmacSha256.create(finished[4..36], &handshake_hash, &c.client_finished_key);
        try c.sealRecord(.handshake, &finished);
        c.write.derive(c.suite, tls.hkdfExpandLabel(HkdfSha256, c.master_secret, "c ap traffic", &handshake_hash, 32));
        c.state = .running;
    }
};

/// A whole session with no socket at all: the test client's bytes go straight into the brick and
/// the brick's straight back, and every plaintext byte the brick reads it writes again.
fn sessionWithTestClient(cert: []const u8, key: []const u8, suite: Suite, size: usize) !void {
    const server = mo_tls_server_new(cert.ptr, cert.len, key.ptr, key.len) orelse return error.BadPem;
    defer mo_tls_server_free(server);
    const conn = mo_tls_conn_new(server) orelse return error.OutOfMemory;
    defer mo_tls_conn_free(conn);

    var client: TestClient = .init(suite, @splat(0x5a));
    defer client.deinit();

    var wire: [16384]u8 = undefined;
    var plain: [16384]u8 = undefined;
    var n: usize = 0;
    var hello_buf: [600]u8 = undefined;
    const first = client.firstRecord(&hello_buf);
    try testing.expectEqual(ok, mo_tls_feed(conn, first.ptr, first.len));

    const sent = try testing.allocator.alloc(u8, size);
    defer testing.allocator.free(sent);
    for (sent, 0..) |*b, i| b.* = @truncate(i *% 31 +% 7);
    var written = false;

    // Each round: the server's ciphertext to the client, the client's back, and every plaintext
    // byte the server read written out again.
    var rounds: usize = 0;
    while (client.plain.items.len < size) : (rounds += 1) {
        if (rounds > 4 * (size / max_plaintext + 8)) return error.NoProgress;
        while (true) {
            try testing.expectEqual(ok, mo_tls_flush(conn, &wire, wire.len, &n));
            if (n == 0) break;
            mo_tls_sent(conn, n);
            try client.feed(wire[0..n]);
        }
        if (client.state == .running and !written) {
            try client.write_(sent);
            written = true;
        }
        if (client.out.items.len > 0) {
            try testing.expectEqual(ok, mo_tls_feed(conn, client.out.items.ptr, client.out.items.len));
            client.out.clearRetainingCapacity();
        }
        while (true) {
            const rc = mo_tls_read(conn, &plain, plain.len, &n);
            if (rc != ok or n == 0) break;
            try testing.expectEqual(ok, mo_tls_write(conn, &plain, n));
        }
        if (mo_tls_pending(conn) == 0 and client.out.items.len == 0 and client.plain.items.len < size and written) return error.Stalled;
    }
    try testing.expect(mo_tls_ready(conn));
    try testing.expectEqualSlices(u8, sent, client.plain.items[0..size]);

    // close_notify both ways: the server's goes out, the client's comes back.
    mo_tls_close(conn);
    try testing.expect(mo_tls_pending(conn) > 0);
    try testing.expectEqual(ok, mo_tls_flush(conn, &wire, wire.len, &n));
    mo_tls_sent(conn, n);
    try client.feed(wire[0..n]);
    const bye = [2]u8{ @intFromEnum(tls.Alert.Level.warning), @intFromEnum(tls.Alert.Description.close_notify) };
    try client.sealRecord(.alert, &bye);
    try testing.expectEqual(ok, mo_tls_feed(conn, client.out.items.ptr, client.out.items.len));
    try testing.expectEqual(closed, mo_tls_read(conn, &plain, plain.len, &n));
}

test "a megabyte both ways, each suite and each key type" {
    for ([_]Suite{ .aes_128_gcm, .chacha20_poly1305 }) |suite| {
        try sessionWithTestClient(ed25519_cert, ed25519_key, suite, 1 << 20);
        try sessionWithTestClient(p256_cert, p256_key, suite, 1 << 20);
    }
}

test "a small session, each suite and each key type" {
    for ([_]Suite{ .aes_128_gcm, .chacha20_poly1305 }) |suite| {
        try sessionWithTestClient(ed25519_cert, ed25519_key, suite, 5);
        try sessionWithTestClient(p256_cert, p256_key, suite, 5);
    }
}

// ---- the brick's own client (step 37): against the brick's server, the chain, ALPN, KeyUpdate,
// the rejections, and RFC 8448's trace

// The chain fixtures, as examples/effects/tls/gen.sh wrote them (OpenSSL 3.0, `openssl ca`,
// every certificate valid 2025-01-01 to 2035-01-01 but the expired leaf's 2020 to 2021).
pub const fx_root =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBMzCB5qADAgECAgIQADAFBgMrZXAwITEfMB0GA1UEAwwWTW8gVGVzdCBSb290
    \\IChFZDI1NTE5KTAeFw0yNTAxMDEwMDAwMDBaFw0zNTAxMDEwMDAwMDBaMCExHzAd
    \\BgNVBAMMFk1vIFRlc3QgUm9vdCAoRWQyNTUxOSkwKjAFBgMrZXADIQDeIWJUEE8q
    \\hsQpjoMpSprF0ahdxYLZBLkz9HBybAiSiqNCMEAwDwYDVR0TAQH/BAUwAwEB/zAO
    \\BgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFGPVUJFKjO60TFE656zLmRHv2BnEMAUG
    \\AytlcANBAJWFiUgoeLAzaJgUUOuh3DKaEOPGjAbuUN96MOU6X9K6oUADR9UVPkBd
    \\hYQFwRexU17XhtvxIZAD59ceKq62xAE=
    \\-----END CERTIFICATE-----
;
pub const fx_chain =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBgDCCATKgAwIBAgICEAIwBQYDK2VwMCkxJzAlBgNVBAMMHk1vIFRlc3QgSW50
    \\ZXJtZWRpYXRlIChFZDI1NTE5KTAeFw0yNTAxMDEwMDAwMDBaFw0zNTAxMDEwMDAw
    \\MDBaMBQxEjAQBgNVBAMMCWxvY2FsaG9zdDAqMAUGAytlcAMhAPWlBXHb/Reusmcl
    \\cbW42ZWrKs/YKsSnQ5ntlVvWjQu8o4GSMIGPMAwGA1UdEwEB/wQCMAAwDgYDVR0P
    \\AQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMBMBoGA1UdEQQTMBGCCWxvY2Fs
    \\aG9zdIcEfwAAATAdBgNVHQ4EFgQUG1YyQbz9PmEkcSeMeRtk1eyC5WAwHwYDVR0j
    \\BBgwFoAUs8Wqz4ozRi2d7GjNPmghqQilLDwwBQYDK2VwA0EAK+PG4xU+bYA6WiiA
    \\krI4jiJRpXHj7QkfA6P02aOcI9KMm1LdZf/yhP6XytiLPMQBKw0r2HnjXudDIeP8
    \\Vx6LAg==
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBXTCCAQ+gAwIBAgICEAEwBQYDK2VwMCExHzAdBgNVBAMMFk1vIFRlc3QgUm9v
    \\dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjApMScw
    \\JQYDVQQDDB5NbyBUZXN0IEludGVybWVkaWF0ZSAoRWQyNTUxOSkwKjAFBgMrZXAD
    \\IQCA33biT7qABH3WMNRD6wDTOw0AL+lnfcwhM8GeVp17mqNjMGEwDwYDVR0TAQH/
    \\BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFLPFqs+KM0YtnexozT5o
    \\IakIpSw8MB8GA1UdIwQYMBaAFGPVUJFKjO60TFE656zLmRHv2BnEMAUGAytlcANB
    \\ANGlNXiuwuCAxd5JzgQn4uOEXkiBGNRsiL+JqcY1h37ICxouv9AEAh/RU2N/fE0M
    \\swc6mTQOkJVG9wOjFsYbnQs=
    \\-----END CERTIFICATE-----
;
pub const fx_key =
    \\-----BEGIN PRIVATE KEY-----
    \\MC4CAQAwBQYDK2VwBCIEIJRPytK0+NsKYitWFX7mQgdwAI6ZovJtK98lEdxY7lWl
    \\-----END PRIVATE KEY-----
;
pub const fx_root_p256 =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBcDCCARagAwIBAgICEA8wCgYIKoZIzj0EAwIwHzEdMBsGA1UEAwwUTW8gVGVz
    \\dCBSb290IChQLTI1NikwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAf
    \\MR0wGwYDVQQDDBRNbyBUZXN0IFJvb3QgKFAtMjU2KTBZMBMGByqGSM49AgEGCCqG
    \\SM49AwEHA0IABEDpBFaHldA9nkzGVgceKK4ADYgAmYG/5UWqJhAM/+8OMmM5yaku
    \\YLt8Mdwp7SlDUyTU/BYa8UL+7EwFk8yNrZmjQjBAMA8GA1UdEwEB/wQFMAMBAf8w
    \\DgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBQvROdw5bE9uxUhutRk49TfUByeHDAK
    \\BggqhkjOPQQDAgNIADBFAiBbe7OUpF3pj/KIOrEKNXc57DkJ8o+AKFLLagXMooQ2
    \\5wIhANC4nWy6BJ9H5LFJrPTGe1fQ0M/ETz5U58mSCID9LpBX
    \\-----END CERTIFICATE-----
;
pub const fx_chain_p256 =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBvTCCAWSgAwIBAgICEBEwCgYIKoZIzj0EAwIwJzElMCMGA1UEAwwcTW8gVGVz
    \\dCBJbnRlcm1lZGlhdGUgKFAtMjU2KTAeFw0yNTAxMDEwMDAwMDBaFw0zNTAxMDEw
    \\MDAwMDBaMBQxEjAQBgNVBAMMCWxvY2FsaG9zdDBZMBMGByqGSM49AgEGCCqGSM49
    \\AwEHA0IABP0WnJmri3KzxFezakMc3mXC1o5riCFJKxQG3CBOE9wfAAMIXnKzASH/
    \\uqs706Y+lcsnuSYySx73r3M6x+BqKzejgZIwgY8wDAYDVR0TAQH/BAIwADAOBgNV
    \\HQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwEwGgYDVR0RBBMwEYIJbG9j
    \\YWxob3N0hwR/AAABMB0GA1UdDgQWBBSTKfmA1wNPU1I/cOxSOxkOavMEFjAfBgNV
    \\HSMEGDAWgBTITaPWuUNkHuIYQ1FW0AY8oC0O+TAKBggqhkjOPQQDAgNHADBEAiAk
    \\mCWUhi65jUTfZnzfj72RNPZeJy8mBZaTbo8YEtEYXQIgTcQUELvlW7e2mJPyjOmC
    \\h/oT9ruospzp77neX24yogk=
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBmTCCAT+gAwIBAgICEBAwCgYIKoZIzj0EAwIwHzEdMBsGA1UEAwwUTW8gVGVz
    \\dCBSb290IChQLTI1NikwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAn
    \\MSUwIwYDVQQDDBxNbyBUZXN0IEludGVybWVkaWF0ZSAoUC0yNTYpMFkwEwYHKoZI
    \\zj0CAQYIKoZIzj0DAQcDQgAEQ6eCcNUik7yPNQobraOdPjNca/ZGJL1fnk9ybJRi
    \\Aj+bYWs01mzC+rGrHElDbazdeX8HbI6IYUgvyiVKWrZwU6NjMGEwDwYDVR0TAQH/
    \\BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFMhNo9a5Q2Qe4hhDUVbQ
    \\BjygLQ75MB8GA1UdIwQYMBaAFC9E53DlsT27FSG61GTj1N9QHJ4cMAoGCCqGSM49
    \\BAMCA0gAMEUCIHwXTCt2CO71aoGJ62ZpO0i5eA3rtHtbbJ1zs2CtPQfOAiEA7try
    \\H8KWnl7/pwutGO5/adGV3oMC8SUYbsNjdJRdRZQ=
    \\-----END CERTIFICATE-----
;
pub const fx_key_p256 =
    \\-----BEGIN PRIVATE KEY-----
    \\MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgYnkbU3QrLcA6+13H
    \\ZBhL4H1INO7H5uZTfyv2KhLose2hRANCAAT9FpyZq4tys8RXs2pDHN5lwtaOa4gh
    \\SSsUBtwgThPcHwADCF5yswEh/7qrO9OmPpXLJ7kmMkse969zOsfgais3
    \\-----END PRIVATE KEY-----
;
pub const fx_root_other =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBNTCB6KADAgECAgIQDjAFBgMrZXAwIjEgMB4GA1UEAwwXTW8gT3RoZXIgUm9v
    \\dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAiMSAw
    \\HgYDVQQDDBdNbyBPdGhlciBSb290IChFZDI1NTE5KTAqMAUGAytlcAMhAHQZcxGd
    \\6KGDS/ZcRZNodH99WMGi8STv7jXWQMqNFVJuo0IwQDAPBgNVHRMBAf8EBTADAQH/
    \\MA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUB6OsojSRohcN5MTBjfeP9X0Jp4Yw
    \\BQYDK2VwA0EAblxbn4cmS9fVnCXNvjXUu0PGT3PCvBQVt7GD0JJ9GjcL68Pr/AEP
    \\PCg1Ur6mGiLv/ndwWY74QTKUCEbxmoYqBg==
    \\-----END CERTIFICATE-----
;
pub const fx_host =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBfjCCATCgAwIBAgICEAMwBQYDK2VwMCkxJzAlBgNVBAMMHk1vIFRlc3QgSW50
    \\ZXJtZWRpYXRlIChFZDI1NTE5KTAeFw0yNTAxMDEwMDAwMDBaFw0zNTAxMDEwMDAw
    \\MDBaMBYxFDASBgNVBAMMC2V4YW1wbGUub3JnMCowBQYDK2VwAyEA8e89KoqoDFmr
    \\1sejeu4OEBYcBplsRXLubaRQ2FGhGGmjgY4wgYswDAYDVR0TAQH/BAIwADAOBgNV
    \\HQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwEwFgYDVR0RBA8wDYILZXhh
    \\bXBsZS5vcmcwHQYDVR0OBBYEFJIImJ1jHNHr3EHlErnKXmxNlcAKMB8GA1UdIwQY
    \\MBaAFLPFqs+KM0YtnexozT5oIakIpSw8MAUGAytlcANBAIgtRSJCFZDm8jA/sqKA
    \\Ecdbp5FYRL6ELOZJN07h5vSeZ9TQyxQ8aRLm1zCovMdc49cIyyyRYxhj31FkiqBh
    \\RwY=
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBXTCCAQ+gAwIBAgICEAEwBQYDK2VwMCExHzAdBgNVBAMMFk1vIFRlc3QgUm9v
    \\dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjApMScw
    \\JQYDVQQDDB5NbyBUZXN0IEludGVybWVkaWF0ZSAoRWQyNTUxOSkwKjAFBgMrZXAD
    \\IQCA33biT7qABH3WMNRD6wDTOw0AL+lnfcwhM8GeVp17mqNjMGEwDwYDVR0TAQH/
    \\BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFLPFqs+KM0YtnexozT5o
    \\IakIpSw8MB8GA1UdIwQYMBaAFGPVUJFKjO60TFE656zLmRHv2BnEMAUGAytlcANB
    \\ANGlNXiuwuCAxd5JzgQn4uOEXkiBGNRsiL+JqcY1h37ICxouv9AEAh/RU2N/fE0M
    \\swc6mTQOkJVG9wOjFsYbnQs=
    \\-----END CERTIFICATE-----
;
pub const fx_host_key =
    \\-----BEGIN PRIVATE KEY-----
    \\MC4CAQAwBQYDK2VwBCIEIJ5cRlG2FVcKL27aJf5PVjJW1LQJDHT6I0e2c95n6lqh
    \\-----END PRIVATE KEY-----
;
pub const fx_expired =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBgDCCATKgAwIBAgICEAQwBQYDK2VwMCkxJzAlBgNVBAMMHk1vIFRlc3QgSW50
    \\ZXJtZWRpYXRlIChFZDI1NTE5KTAeFw0yMDAxMDEwMDAwMDBaFw0yMTAxMDEwMDAw
    \\MDBaMBQxEjAQBgNVBAMMCWxvY2FsaG9zdDAqMAUGAytlcAMhAJCZ2D0mASrimFbA
    \\nbrMfja65BWsOaA1ZtTm5KOiVzYWo4GSMIGPMAwGA1UdEwEB/wQCMAAwDgYDVR0P
    \\AQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMBMBoGA1UdEQQTMBGCCWxvY2Fs
    \\aG9zdIcEfwAAATAdBgNVHQ4EFgQU593MSQVr1OuTGCQ/g/1Nway0rpMwHwYDVR0j
    \\BBgwFoAUs8Wqz4ozRi2d7GjNPmghqQilLDwwBQYDK2VwA0EAnuDc+37qFFPWdYuf
    \\SRiaTWUPAUaseBgCce3IQP93FxrvymPkls8Tc0TnKkt4bvWVvY2/txlw6kJaAI6G
    \\1VP+Aw==
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBXTCCAQ+gAwIBAgICEAEwBQYDK2VwMCExHzAdBgNVBAMMFk1vIFRlc3QgUm9v
    \\dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjApMScw
    \\JQYDVQQDDB5NbyBUZXN0IEludGVybWVkaWF0ZSAoRWQyNTUxOSkwKjAFBgMrZXAD
    \\IQCA33biT7qABH3WMNRD6wDTOw0AL+lnfcwhM8GeVp17mqNjMGEwDwYDVR0TAQH/
    \\BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFLPFqs+KM0YtnexozT5o
    \\IakIpSw8MB8GA1UdIwQYMBaAFGPVUJFKjO60TFE656zLmRHv2BnEMAUGAytlcANB
    \\ANGlNXiuwuCAxd5JzgQn4uOEXkiBGNRsiL+JqcY1h37ICxouv9AEAh/RU2N/fE0M
    \\swc6mTQOkJVG9wOjFsYbnQs=
    \\-----END CERTIFICATE-----
;
pub const fx_expired_key =
    \\-----BEGIN PRIVATE KEY-----
    \\MC4CAQAwBQYDK2VwBCIEINXnWuyctmMYDmCVa1Zj+oPFitEPQWN5eT0HiFKgPbwD
    \\-----END PRIVATE KEY-----
;
pub const fx_depth6 =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBezCCAS2gAwIBAgICEAowBQYDK2VwMCQxIjAgBgNVBAMMGU1vIFRlc3QgRGVw
    \\dGggNSAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAU
    \\MRIwEAYDVQQDDAlsb2NhbGhvc3QwKjAFBgMrZXADIQAEUNxt99HCzoeFj07I5Lb6
    \\Nt3brJDCSnXN49adFdhKLqOBkjCBjzAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQE
    \\AwIHgDATBgNVHSUEDDAKBggrBgEFBQcDATAaBgNVHREEEzARgglsb2NhbGhvc3SH
    \\BH8AAAEwHQYDVR0OBBYEFI9WXy9vB6Ta9BaCiG1d2ZM7CUOqMB8GA1UdIwQYMBaA
    \\FKiR1h+MBaamzQphNLf5kv1GftTpMAUGAytlcANBAOcu5VAp2Ik+fEf+vw6WWDG2
    \\VGVS52GB67Rj6kOUi9uW6RcIqidF9NjntaxOhVapf+wQL4XVf1A3PWtJfYpxZAc=
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBWzCCAQ2gAwIBAgICEAkwBQYDK2VwMCQxIjAgBgNVBAMMGU1vIFRlc3QgRGVw
    \\dGggNCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAk
    \\MSIwIAYDVQQDDBlNbyBUZXN0IERlcHRoIDUgKEVkMjU1MTkpMCowBQYDK2VwAyEA
    \\DnnTZQi02wc3Z+MI+/3DTPEn7G/SPVqsiftz1eQ1Rk2jYzBhMA8GA1UdEwEB/wQF
    \\MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBSokdYfjAWmps0KYTS3+ZL9
    \\Rn7U6TAfBgNVHSMEGDAWgBQVlhEcXW54Nbhq3d3Ok6ncSALwlDAFBgMrZXADQQCv
    \\gLOFa24lfo/uXwkf8zUniKLVSzqkPKByJbPOT1GIm+HGivHzGjpzmPSbobOnytnO
    \\H9dVwPI2LaVp0qL9JyMI
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBWzCCAQ2gAwIBAgICEAgwBQYDK2VwMCQxIjAgBgNVBAMMGU1vIFRlc3QgRGVw
    \\dGggMyAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAk
    \\MSIwIAYDVQQDDBlNbyBUZXN0IERlcHRoIDQgKEVkMjU1MTkpMCowBQYDK2VwAyEA
    \\LBnvAVOW+oCM8SUhHqY4E5+oByHuq36uxtX7JA8zBnmjYzBhMA8GA1UdEwEB/wQF
    \\MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBQVlhEcXW54Nbhq3d3Ok6nc
    \\SALwlDAfBgNVHSMEGDAWgBSw3OcwKlPBq2tXY68ZHT0ZAXrFvzAFBgMrZXADQQCA
    \\zfSfyssh8wSzh63GQzFfUMfjEA1oTqmdlLhtiPElWJuu8+cYxE4SsB/xzpu8NRo/
    \\mbTOCd+SK5xHHUT1/gsJ
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBWzCCAQ2gAwIBAgICEAcwBQYDK2VwMCQxIjAgBgNVBAMMGU1vIFRlc3QgRGVw
    \\dGggMiAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAk
    \\MSIwIAYDVQQDDBlNbyBUZXN0IERlcHRoIDMgKEVkMjU1MTkpMCowBQYDK2VwAyEA
    \\H+JvPHRNSYSaVfD7joxVEjYT+Q9MksqA3Wffq2AH2bWjYzBhMA8GA1UdEwEB/wQF
    \\MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBSw3OcwKlPBq2tXY68ZHT0Z
    \\AXrFvzAfBgNVHSMEGDAWgBTQi4QEtWsJlS0N9eIk317pzvGStTAFBgMrZXADQQDv
    \\pybeP0nK0H/JsNgVlyGu2tgIZGf7yHEWCbSZxdK6RECvWfUyj+KXShtCHgfn5xDa
    \\C1bGKsOlQoDiP85JtMkI
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBWzCCAQ2gAwIBAgICEAYwBQYDK2VwMCQxIjAgBgNVBAMMGU1vIFRlc3QgRGVw
    \\dGggMSAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAk
    \\MSIwIAYDVQQDDBlNbyBUZXN0IERlcHRoIDIgKEVkMjU1MTkpMCowBQYDK2VwAyEA
    \\5gRxFaESkxG6s9g7jfe6CoG3D4l9qulBRYOLZH9B0hyjYzBhMA8GA1UdEwEB/wQF
    \\MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBTQi4QEtWsJlS0N9eIk317p
    \\zvGStTAfBgNVHSMEGDAWgBTNeaOlpddLiTH5R9T6jQPLePbC8DAFBgMrZXADQQD8
    \\OsQ0CMfYv6cW1vHXcl9+xOH8Q6tEqDw4Uj4sbaIbGx6AG4VAOAUMmCLjfKO5tBOg
    \\tnFuGHQSlCxP/+1PDGkP
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBWDCCAQqgAwIBAgICEAUwBQYDK2VwMCExHzAdBgNVBAMMFk1vIFRlc3QgUm9v
    \\dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAkMSIw
    \\IAYDVQQDDBlNbyBUZXN0IERlcHRoIDEgKEVkMjU1MTkpMCowBQYDK2VwAyEAp4+7
    \\7w5Ythg3zIpYevuUEvTSBFWS0+KOSgyHGenn5/ajYzBhMA8GA1UdEwEB/wQFMAMB
    \\Af8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBTNeaOlpddLiTH5R9T6jQPLePbC
    \\8DAfBgNVHSMEGDAWgBRj1VCRSozutExROuesy5kR79gZxDAFBgMrZXADQQANB5Uc
    \\drsC7f8gIxCPrmNhT7oNZJllU1u5qT0dqhDV7hUpbpLYTGhdGmy3sdppAU2XXwI8
    \\n4L76UrNIsYtm5EN
    \\-----END CERTIFICATE-----
;
pub const fx_depth6_key =
    \\-----BEGIN PRIVATE KEY-----
    \\MC4CAQAwBQYDK2VwBCIEIOQ2f+SYrldkntiNfx1RbK/QqQ9YHDi1iC6tH+pBbTf2
    \\-----END PRIVATE KEY-----
;
pub const fx_depth5 =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBezCCAS2gAwIBAgICEAswBQYDK2VwMCQxIjAgBgNVBAMMGU1vIFRlc3QgRGVw
    \\dGggNCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAU
    \\MRIwEAYDVQQDDAlsb2NhbGhvc3QwKjAFBgMrZXADIQBY28BPnp7ZKxcwdngHOtgb
    \\KKbWaWOgubBRP2c+1HLBF6OBkjCBjzAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQE
    \\AwIHgDATBgNVHSUEDDAKBggrBgEFBQcDATAaBgNVHREEEzARgglsb2NhbGhvc3SH
    \\BH8AAAEwHQYDVR0OBBYEFMqwipEWdJvi86egD3osJ6IyG02rMB8GA1UdIwQYMBaA
    \\FBWWERxdbng1uGrd3c6TqdxIAvCUMAUGAytlcANBANAyVKa6ay7qWYZwk28/QNFG
    \\aHXnDe2ioarHIfCjzlBvSF5VwobwLWizAG/ya0Zx4mVzn/TBK998BUte/rqdggc=
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBWzCCAQ2gAwIBAgICEAgwBQYDK2VwMCQxIjAgBgNVBAMMGU1vIFRlc3QgRGVw
    \\dGggMyAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAk
    \\MSIwIAYDVQQDDBlNbyBUZXN0IERlcHRoIDQgKEVkMjU1MTkpMCowBQYDK2VwAyEA
    \\LBnvAVOW+oCM8SUhHqY4E5+oByHuq36uxtX7JA8zBnmjYzBhMA8GA1UdEwEB/wQF
    \\MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBQVlhEcXW54Nbhq3d3Ok6nc
    \\SALwlDAfBgNVHSMEGDAWgBSw3OcwKlPBq2tXY68ZHT0ZAXrFvzAFBgMrZXADQQCA
    \\zfSfyssh8wSzh63GQzFfUMfjEA1oTqmdlLhtiPElWJuu8+cYxE4SsB/xzpu8NRo/
    \\mbTOCd+SK5xHHUT1/gsJ
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBWzCCAQ2gAwIBAgICEAcwBQYDK2VwMCQxIjAgBgNVBAMMGU1vIFRlc3QgRGVw
    \\dGggMiAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAk
    \\MSIwIAYDVQQDDBlNbyBUZXN0IERlcHRoIDMgKEVkMjU1MTkpMCowBQYDK2VwAyEA
    \\H+JvPHRNSYSaVfD7joxVEjYT+Q9MksqA3Wffq2AH2bWjYzBhMA8GA1UdEwEB/wQF
    \\MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBSw3OcwKlPBq2tXY68ZHT0Z
    \\AXrFvzAfBgNVHSMEGDAWgBTQi4QEtWsJlS0N9eIk317pzvGStTAFBgMrZXADQQDv
    \\pybeP0nK0H/JsNgVlyGu2tgIZGf7yHEWCbSZxdK6RECvWfUyj+KXShtCHgfn5xDa
    \\C1bGKsOlQoDiP85JtMkI
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBWzCCAQ2gAwIBAgICEAYwBQYDK2VwMCQxIjAgBgNVBAMMGU1vIFRlc3QgRGVw
    \\dGggMSAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAk
    \\MSIwIAYDVQQDDBlNbyBUZXN0IERlcHRoIDIgKEVkMjU1MTkpMCowBQYDK2VwAyEA
    \\5gRxFaESkxG6s9g7jfe6CoG3D4l9qulBRYOLZH9B0hyjYzBhMA8GA1UdEwEB/wQF
    \\MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBTQi4QEtWsJlS0N9eIk317p
    \\zvGStTAfBgNVHSMEGDAWgBTNeaOlpddLiTH5R9T6jQPLePbC8DAFBgMrZXADQQD8
    \\OsQ0CMfYv6cW1vHXcl9+xOH8Q6tEqDw4Uj4sbaIbGx6AG4VAOAUMmCLjfKO5tBOg
    \\tnFuGHQSlCxP/+1PDGkP
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBWDCCAQqgAwIBAgICEAUwBQYDK2VwMCExHzAdBgNVBAMMFk1vIFRlc3QgUm9v
    \\dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjAkMSIw
    \\IAYDVQQDDBlNbyBUZXN0IERlcHRoIDEgKEVkMjU1MTkpMCowBQYDK2VwAyEAp4+7
    \\7w5Ythg3zIpYevuUEvTSBFWS0+KOSgyHGenn5/ajYzBhMA8GA1UdEwEB/wQFMAMB
    \\Af8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBTNeaOlpddLiTH5R9T6jQPLePbC
    \\8DAfBgNVHSMEGDAWgBRj1VCRSozutExROuesy5kR79gZxDAFBgMrZXADQQANB5Uc
    \\drsC7f8gIxCPrmNhT7oNZJllU1u5qT0dqhDV7hUpbpLYTGhdGmy3sdppAU2XXwI8
    \\n4L76UrNIsYtm5EN
    \\-----END CERTIFICATE-----
;
pub const fx_depth5_key =
    \\-----BEGIN PRIVATE KEY-----
    \\MC4CAQAwBQYDK2VwBCIEID8RziCz4lH6rtqswoYyY3zQ75XtDj6+l0tgTem7Zx5e
    \\-----END PRIVATE KEY-----
;
pub const fx_notca =
    \\-----BEGIN CERTIFICATE-----
    \\MIIBbTCCAR+gAwIBAgICEA0wBQYDK2VwMBYxFDASBgNVBAMMC2V4YW1wbGUub3Jn
    \\MB4XDTI1MDEwMTAwMDAwMFoXDTM1MDEwMTAwMDAwMFowFDESMBAGA1UEAwwJbG9j
    \\YWxob3N0MCowBQYDK2VwAyEAsGFbnpgo2tXgZHVD+/ziqqwmkJuI7YzAfnp2fdw+
    \\Q6SjgZIwgY8wDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAww
    \\CgYIKwYBBQUHAwEwGgYDVR0RBBMwEYIJbG9jYWxob3N0hwR/AAABMB0GA1UdDgQW
    \\BBTZNloWxnySgJuQqBGLx7W9OIV99TAfBgNVHSMEGDAWgBSSCJidYxzR69xB5RK5
    \\yl5sTZXACjAFBgMrZXADQQB+g+/EQdjmX8Ci94YmssFzpIgERrCD6Ic0pdF1zooe
    \\8qcDrXROdohehplSrkJAtVWnlBnJ4YahtkaPJsIyRbsI
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBfjCCATCgAwIBAgICEAMwBQYDK2VwMCkxJzAlBgNVBAMMHk1vIFRlc3QgSW50
    \\ZXJtZWRpYXRlIChFZDI1NTE5KTAeFw0yNTAxMDEwMDAwMDBaFw0zNTAxMDEwMDAw
    \\MDBaMBYxFDASBgNVBAMMC2V4YW1wbGUub3JnMCowBQYDK2VwAyEA8e89KoqoDFmr
    \\1sejeu4OEBYcBplsRXLubaRQ2FGhGGmjgY4wgYswDAYDVR0TAQH/BAIwADAOBgNV
    \\HQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwEwFgYDVR0RBA8wDYILZXhh
    \\bXBsZS5vcmcwHQYDVR0OBBYEFJIImJ1jHNHr3EHlErnKXmxNlcAKMB8GA1UdIwQY
    \\MBaAFLPFqs+KM0YtnexozT5oIakIpSw8MAUGAytlcANBAIgtRSJCFZDm8jA/sqKA
    \\Ecdbp5FYRL6ELOZJN07h5vSeZ9TQyxQ8aRLm1zCovMdc49cIyyyRYxhj31FkiqBh
    \\RwY=
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBXTCCAQ+gAwIBAgICEAEwBQYDK2VwMCExHzAdBgNVBAMMFk1vIFRlc3QgUm9v
    \\dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjApMScw
    \\JQYDVQQDDB5NbyBUZXN0IEludGVybWVkaWF0ZSAoRWQyNTUxOSkwKjAFBgMrZXAD
    \\IQCA33biT7qABH3WMNRD6wDTOw0AL+lnfcwhM8GeVp17mqNjMGEwDwYDVR0TAQH/
    \\BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFLPFqs+KM0YtnexozT5o
    \\IakIpSw8MB8GA1UdIwQYMBaAFGPVUJFKjO60TFE656zLmRHv2BnEMAUGAytlcANB
    \\ANGlNXiuwuCAxd5JzgQn4uOEXkiBGNRsiL+JqcY1h37ICxouv9AEAh/RU2N/fE0M
    \\swc6mTQOkJVG9wOjFsYbnQs=
    \\-----END CERTIFICATE-----
;
pub const fx_notca_key =
    \\-----BEGIN PRIVATE KEY-----
    \\MC4CAQAwBQYDK2VwBCIEIH7e9XGWCu3oYygWFhd76uBr5NwVZbclvf4EvSRC6IjE
    \\-----END PRIVATE KEY-----
;
pub const fx_rsa =
    \\-----BEGIN CERTIFICATE-----
    \\MIICejCCAiygAwIBAgICEAwwBQYDK2VwMCkxJzAlBgNVBAMMHk1vIFRlc3QgSW50
    \\ZXJtZWRpYXRlIChFZDI1NTE5KTAeFw0yNTAxMDEwMDAwMDBaFw0zNTAxMDEwMDAw
    \\MDBaMBQxEjAQBgNVBAMMCWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEP
    \\ADCCAQoCggEBALN61cHV6v0Z4lnvPmCkLG1HBzOSYXVSXURgz98iCLaAjRxE9ga9
    \\/mcvzcIYAjWnwy1/7hi4TpHsl+pO3HmTwA00pQPhWpMI8T/G1qMcKwr5b2o/7KLL
    \\cuTaX9cZ87HsbA349psiNnplJWvtWGyDx4TPif7yC3lBfkIwoZ/7hu+UzxK/uK2y
    \\In9WWnfQk5LET64/AAOkHFSO5sJDniHuv/x7BARDXx70mmkK1RyERMlh830B1P+c
    \\i0YoKXhfvXNKmU474BbzRxjP5GGUZ3yCip/TJGhwMx1FgnUDz35WtbP6juoefoPs
    \\2H7JPjQEoF8iftGLoJDtk3KcOKvWMonm6yECAwEAAaOBkjCBjzAMBgNVHRMBAf8E
    \\AjAAMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDATAaBgNVHREE
    \\EzARgglsb2NhbGhvc3SHBH8AAAEwHQYDVR0OBBYEFIYTCmaDFxIzxCW6bw4fxb+N
    \\cdJyMB8GA1UdIwQYMBaAFLPFqs+KM0YtnexozT5oIakIpSw8MAUGAytlcANBAKQP
    \\8WcD8P1DLx1JkK1JVpBuaX96NVIDOzrqTdJq1xQT/tbR+fmPBDeKDRhF45oCFmVG
    \\03/PeuOaZYw2bu7r4gQ=
    \\-----END CERTIFICATE-----
    \\-----BEGIN CERTIFICATE-----
    \\MIIBXTCCAQ+gAwIBAgICEAEwBQYDK2VwMCExHzAdBgNVBAMMFk1vIFRlc3QgUm9v
    \\dCAoRWQyNTUxOSkwHhcNMjUwMTAxMDAwMDAwWhcNMzUwMTAxMDAwMDAwWjApMScw
    \\JQYDVQQDDB5NbyBUZXN0IEludGVybWVkaWF0ZSAoRWQyNTUxOSkwKjAFBgMrZXAD
    \\IQCA33biT7qABH3WMNRD6wDTOw0AL+lnfcwhM8GeVp17mqNjMGEwDwYDVR0TAQH/
    \\BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFLPFqs+KM0YtnexozT5o
    \\IakIpSw8MB8GA1UdIwQYMBaAFGPVUJFKjO60TFE656zLmRHv2BnEMAUGAytlcANB
    \\ANGlNXiuwuCAxd5JzgQn4uOEXkiBGNRsiL+JqcY1h37ICxouv9AEAh/RU2N/fE0M
    \\swc6mTQOkJVG9wOjFsYbnQs=
    \\-----END CERTIFICATE-----
;

/// 2026-01-01T00:00:00Z: inside every fixture's dates but the expired leaf's.
pub const test_now: i64 = 1767225600;

fn hex(comptime text: []const u8) [text.len / 2]u8 {
    @setEvalBranchQuota(100_000);
    var out: [text.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, text) catch unreachable;
    return out;
}

/// The first certificate of a PEM chain, as PEM: a leaf sent without the intermediate that
/// signed it.
fn firstBlock(pem: []const u8) []const u8 {
    const end = "-----END CERTIFICATE-----";
    return pem[0 .. mem.indexOf(u8, pem, end).? + end.len];
}

fn testClient(trust: []const u8, protocols: []const u8) !*Client {
    const plain = mo_tls_client_new(trust.ptr, trust.len) orelse return error.BadPem;
    if (protocols.len == 0) return plain;
    defer mo_tls_client_free(plain);
    return mo_tls_client_offer(plain, protocols.ptr, protocols.len) orelse error.OutOfMemory;
}

fn testServerOf(chain: []const u8, key: []const u8, protocols: []const u8) !*Server {
    const plain = mo_tls_server_new(chain.ptr, chain.len, key.ptr, key.len) orelse return error.BadPem;
    if (protocols.len == 0) return plain;
    defer mo_tls_server_free(plain);
    return mo_tls_server_offer(plain, protocols.ptr, protocols.len) orelse error.OutOfMemory;
}

/// Hands each side's ciphertext to the other until neither has anything to say: the network
/// between a brick client and a brick server, in memory, with nothing that can block.
fn shuttle(a: *Conn, b: *Conn) !void {
    var wire: [32768]u8 = undefined;
    var rounds: usize = 0;
    while (rounds < 100_000) : (rounds += 1) {
        var moved = false;
        for ([_][2]*Conn{ .{ a, b }, .{ b, a } }) |dir| {
            var n: usize = 0;
            _ = mo_tls_flush(dir[0], &wire, wire.len, &n);
            if (n == 0) continue;
            mo_tls_sent(dir[0], n);
            _ = mo_tls_feed(dir[1], &wire, n);
            moved = true;
        }
        if (!moved) return;
    }
    return error.NoProgress;
}

/// A brick server and a brick client, the client's hello answered as far as it goes.
const Session = struct {
    server: *Server,
    client: *Client,
    s: *Conn,
    c: *Conn,

    fn start(server: *Server, client: *Client, host: []const u8, now: i64, hooks: TestHooks) !Session {
        const s = mo_tls_conn_new(server) orelse return error.OutOfMemory;
        errdefer mo_tls_conn_free(s);
        const c = try connectWith(client, host, now, hooks);
        const session: Session = .{ .server = server, .client = client, .s = s, .c = c };
        try shuttle(s, c);
        return session;
    }

    fn deinit(se: *Session) void {
        mo_tls_conn_free(se.s);
        mo_tls_conn_free(se.c);
        mo_tls_server_free(se.server);
        mo_tls_client_free(se.client);
    }
};

/// Every plaintext byte `conn` holds, up to `size`.
fn readAll(conn: *Conn, size: usize) ![]u8 {
    const got = try testing.allocator.alloc(u8, size);
    errdefer testing.allocator.free(got);
    var at: usize = 0;
    while (at < size) {
        var n: usize = 0;
        const rc = mo_tls_read(conn, got[at..].ptr, size - at, &n);
        if (rc != ok) return error.ShortRead;
        at += n;
    }
    return got;
}

/// `size` bytes from `from` to `to`, checked on arrival.
fn flow(from: *Conn, to: *Conn, size: usize, seed: u8) !void {
    const sent = try testing.allocator.alloc(u8, size);
    defer testing.allocator.free(sent);
    for (sent, 0..) |*b, i| b.* = @truncate(i *% 31 +% seed);
    try testing.expectEqual(ok, mo_tls_write(from, sent.ptr, sent.len));
    try shuttle(from, to);
    const back = try readAll(to, size);
    defer testing.allocator.free(back);
    try testing.expectEqualSlices(u8, sent, back);
}

/// close_notify from `first`, then from the other: each reads `closed`.
fn closeBoth(first: *Conn, second: *Conn) !void {
    var n: usize = 0;
    var buf: [16]u8 = undefined;
    mo_tls_close(first);
    try shuttle(first, second);
    try testing.expectEqual(closed, mo_tls_read(second, &buf, buf.len, &n));
    mo_tls_close(second);
    try shuttle(first, second);
    try testing.expectEqual(closed, mo_tls_read(first, &buf, buf.len, &n));
}

test "the brick's client and server: a handshake and a megabyte both ways, each suite, each key type, with and without ALPN" {
    const pairs = [_][3][]const u8{ .{ fx_chain, fx_key, fx_root }, .{ fx_chain_p256, fx_key_p256, fx_root_p256 } };
    for (pairs) |p| for ([_]Suite{ .aes_128_gcm, .chacha20_poly1305 }) |suite| for ([_]bool{ false, true }) |alpn| {
        for ([_]usize{ 5, 1 << 20 }) |size| {
            const server = try testServerOf(p[0], p[1], if (alpn) "echo/1" else "");
            server.prefer = suite;
            var se = try Session.start(server, try testClient(p[2], if (alpn) "mo/1\x00echo/1" else ""), "localhost", test_now, .{});
            defer se.deinit();
            try testing.expect(mo_tls_ready(se.c));
            try testing.expect(mo_tls_ready(se.s));
            try testing.expectEqual(suite, se.c.suite);
            var name: [255]u8 = undefined;
            const n = mo_tls_protocol(se.c, &name, name.len);
            try testing.expectEqualStrings(if (alpn) "echo/1" else "", name[0..n]);
            try testing.expectEqual(n, mo_tls_protocol(se.s, &name, name.len));
            try flow(se.c, se.s, size, 7);
            try flow(se.s, se.c, size, 11);
            try closeBoth(se.c, se.s);
        }
    };
}

test "the chain: three certificates, five, an address, and the name in any case, all accepted" {
    const cases = [_]struct { chain: []const u8, key: []const u8, root: []const u8, host: []const u8 }{
        .{ .chain = fx_chain, .key = fx_key, .root = fx_root, .host = "localhost" },
        .{ .chain = fx_chain_p256, .key = fx_key_p256, .root = fx_root_p256, .host = "localhost" },
        .{ .chain = fx_depth5, .key = fx_depth5_key, .root = fx_root, .host = "localhost" },
        .{ .chain = fx_chain, .key = fx_key, .root = fx_root, .host = "127.0.0.1" },
        .{ .chain = fx_chain, .key = fx_key, .root = fx_root, .host = "LocalHost" },
        // Both roots in one trust file: the chain finds its own.
        .{ .chain = fx_chain_p256, .key = fx_key_p256, .root = fx_root ++ "\n" ++ fx_root_p256, .host = "localhost" },
    };
    for (cases) |k| {
        var se = try Session.start(try testServerOf(k.chain, k.key, ""), try testClient(k.root, ""), k.host, test_now, .{});
        defer se.deinit();
        try testing.expect(mo_tls_ready(se.c));
        try flow(se.c, se.s, 100, 3);
    }
}

/// A handshake the client must refuse with `want`: the client sends the alert and is over, and
/// the server reads it as the client's.
fn expectRefused(server: *Server, trust: []const u8, host: []const u8, now: i64, want: tls.Alert.Description) !void {
    var se = try Session.start(server, try testClient(trust, ""), host, now, .{});
    defer se.deinit();
    try testing.expect(!mo_tls_ready(se.c));
    try testing.expectEqual(@as(c_int, @intFromEnum(want)), mo_tls_alert(se.c));
    try testing.expect(!se.c.alert_from_peer);
    try testing.expectEqual(Phase.broken, se.c.phase);
    try testing.expect(mo_tls_untrusted(se.c));
    try testing.expect(!mo_tls_ready(se.s));
    try testing.expectEqual(@as(c_int, @intFromEnum(want)), mo_tls_alert(se.s));
    try testing.expect(se.s.alert_from_peer);
    var n: usize = 0;
    var buf: [8]u8 = undefined;
    try testing.expectEqual(failed, mo_tls_read(se.c, &buf, buf.len, &n));
    try testing.expectEqual(failed, mo_tls_write(se.c, "x", 1));
}

test "the chain: each refusal is the alert RFC 8446 names" {
    // A leaf for another name, and this leaf for a name or an address it does not hold.
    try expectRefused(try testServerOf(fx_host, fx_host_key, ""), fx_root, "localhost", test_now, .bad_certificate);
    try expectRefused(try testServerOf(fx_chain, fx_key, ""), fx_root, "example.org", test_now, .bad_certificate);
    try expectRefused(try testServerOf(fx_chain, fx_key, ""), fx_root, "127.0.0.2", test_now, .bad_certificate);
    try expectRefused(try testServerOf(fx_chain, fx_key, ""), fx_root, "a.localhost", test_now, .bad_certificate);
    // Dates: the leaf's past, the root's not yet begun, and the root's past.
    try expectRefused(try testServerOf(fx_expired, fx_expired_key, ""), fx_root, "localhost", test_now, .certificate_expired);
    try expectRefused(try testServerOf(fx_chain, fx_key, ""), fx_root, "localhost", 1704067200, .bad_certificate);
    try expectRefused(try testServerOf(fx_chain, fx_key, ""), fx_root, "localhost", 2082758400, .certificate_expired);
    // A root nobody trusts, the other key type's root, and a chain with its intermediate left out.
    try expectRefused(try testServerOf(fx_chain, fx_key, ""), fx_root_other, "localhost", test_now, .unknown_ca);
    try expectRefused(try testServerOf(fx_chain_p256, fx_key_p256, ""), fx_root, "localhost", test_now, .unknown_ca);
    try expectRefused(try testServerOf(firstBlock(fx_chain), fx_key, ""), fx_root, "localhost", test_now, .unknown_ca);
    // A leaf that signed another as if it were a CA.
    try expectRefused(try testServerOf(fx_notca, fx_notca_key, ""), fx_root, "localhost", test_now, .unknown_ca);
    // Six certificates, one past the depth of five: no root within the depth, as OpenSSL says it.
    try expectRefused(try testServerOf(fx_depth6, fx_depth6_key, ""), fx_root, "localhost", test_now, .unknown_ca);
    // A leaf with an RSA key, outside the cut. No brick server signs with RSA, so this one is put
    // together by hand: the RSA chain presented, the Ed25519 leaf's key signing (the client never
    // reaches the signature).
    {
        var chain: std.ArrayList([]u8) = .empty;
        try pemBlocks(fx_rsa, "CERTIFICATE", &chain);
        var keys: std.ArrayList([]u8) = .empty;
        defer {
            for (keys.items) |d| gpa.free(d);
            keys.deinit(gpa);
        }
        try pemBlocks(fx_key, "PRIVATE KEY", &keys);
        const server = try gpa.create(Server);
        server.* = .{ .chain = try chain.toOwnedSlice(gpa), .key = try parsePkcs8(keys.items[0]) };
        try expectRefused(server, fx_root, "localhost", test_now, .unsupported_certificate);
    }
}

test "a trust PEM with no certificate in it is BadPem, and a bad block among good ones is left out" {
    try testing.expect(mo_tls_client_new("hello", 5) == null);
    try testing.expect(mo_tls_client_new(fx_key.ptr, fx_key.len) == null);
    const junk = "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n";
    try testing.expect(mo_tls_client_new(junk.ptr, junk.len) == null);
    const mixed = junk ++ fx_root;
    const client = mo_tls_client_new(mixed.ptr, mixed.len).?;
    defer mo_tls_client_free(client);
    try testing.expectEqual(@as(usize, 1), client.trust.len);
    // A name longer than 255 bytes cannot be offered.
    const long: [256]u8 = @splat('a');
    try testing.expect(mo_tls_client_offer(client, &long, long.len) == null);
    const server = testServer();
    defer mo_tls_server_free(server);
    try testing.expect(mo_tls_server_offer(server, &long, long.len) == null);
}

test "ALPN: the server's first that the client offered, nothing shared, and either side alone" {
    const Case = struct { server: []const u8, client: []const u8, agreed: ?[]const u8 };
    const cases = [_]Case{
        .{ .server = "echo/1", .client = "mo/1\x00echo/1", .agreed = "echo/1" },
        .{ .server = "echo/1\x00mo/1", .client = "mo/1\x00echo/1", .agreed = "echo/1" },
        .{ .server = "", .client = "mo/1\x00echo/1", .agreed = "" },
        .{ .server = "echo/1", .client = "", .agreed = "" },
        .{ .server = "echo/1", .client = "mo/1", .agreed = null },
    };
    for (cases) |k| {
        var se = try Session.start(try testServerOf(fx_chain, fx_key, k.server), try testClient(fx_root, k.client), "localhost", test_now, .{});
        defer se.deinit();
        var name: [255]u8 = undefined;
        if (k.agreed) |want| {
            try testing.expect(mo_tls_ready(se.c));
            try testing.expectEqualStrings(want, name[0..mo_tls_protocol(se.c, &name, name.len)]);
            try testing.expectEqualStrings(want, name[0..mo_tls_protocol(se.s, &name, name.len)]);
            try flow(se.c, se.s, 10, 1);
        } else {
            // RFC 7301 3.2: the server's no_application_protocol, and the client reads it.
            try testing.expect(!mo_tls_ready(se.c));
            try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.no_application_protocol)), mo_tls_alert(se.s));
            try testing.expect(!se.s.alert_from_peer);
            try testing.expectEqual(@as(c_int, 120), mo_tls_alert(se.c));
            try testing.expect(se.c.alert_from_peer);
            try testing.expectEqual(@as(usize, 0), mo_tls_protocol(se.c, &name, name.len));
        }
    }
}

test "a KeyUpdate started by the client and one started by the server, records flowing after each" {
    var se = try Session.start(try testServerOf(fx_chain_p256, fx_key_p256, ""), try testClient(fx_root_p256, ""), "localhost", test_now, .{});
    defer se.deinit();
    try testing.expect(mo_tls_ready(se.c));
    try testing.expectEqual(failed, mo_tls_key_update(null, true));

    // The client asks for the server's to move too.
    const c_write = se.c.write_cipher.key;
    try testing.expectEqual(ok, mo_tls_key_update(se.c, true));
    try testing.expect(!mem.eql(u8, &c_write, &se.c.write_cipher.key));
    try shuttle(se.c, se.s);
    try testing.expectEqual(@as(u32, 1), se.s.key_updates_read);
    try testing.expectEqual(@as(u32, 1), se.s.key_updates_sent);
    try testing.expectEqual(@as(u32, 1), se.c.key_updates_read);
    try flow(se.c, se.s, 40_000, 5);
    try flow(se.s, se.c, 40_000, 9);

    // The server moves its own and asks nothing.
    try testing.expectEqual(ok, mo_tls_key_update(se.s, false));
    try shuttle(se.c, se.s);
    try testing.expectEqual(@as(u32, 2), se.c.key_updates_read);
    try testing.expectEqual(@as(u32, 1), se.c.key_updates_sent);
    try flow(se.s, se.c, 1000, 13);
    try flow(se.c, se.s, 1000, 17);

    // The server asks, and the client answers.
    try testing.expectEqual(ok, mo_tls_key_update(se.s, true));
    try shuttle(se.c, se.s);
    try testing.expectEqual(@as(u32, 2), se.c.key_updates_sent);
    try testing.expectEqual(@as(u32, 2), se.s.key_updates_read);
    try flow(se.c, se.s, 1000, 19);
    try flow(se.s, se.c, 1000, 23);
    try closeBoth(se.s, se.c);
    // Neither side updates a connection that is over.
    try testing.expectEqual(failed, mo_tls_key_update(se.c, false));
}

test "a client that shares no key gets one HelloRetryRequest and answers it" {
    var se = try Session.start(try testServerOf(fx_chain, fx_key, ""), try testClient(fx_root, ""), "localhost", test_now, .{ .no_share = true });
    defer se.deinit();
    try testing.expect(se.c.retried);
    try testing.expect(mo_tls_ready(se.c));
    try testing.expect(mo_tls_ready(se.s));
    try flow(se.c, se.s, 1000, 29);
    try flow(se.s, se.c, 1000, 31);
}

/// The records in `bytes`, whole, in order.
fn splitRecords(bytes: []const u8, out: [][]const u8) [][]const u8 {
    var n: usize = 0;
    var at: usize = 0;
    while (at + record_header_len <= bytes.len and n < out.len) {
        const len = mem.readInt(u16, bytes[at + 3 ..][0..2], .big);
        out[n] = bytes[at..][0 .. record_header_len + len];
        at += record_header_len + len;
        n += 1;
    }
    return out[0..n];
}

/// A client whose hello a brick server has answered: the server's first flight, record by record
/// (ServerHello, change_cipher_spec, EncryptedExtensions, Certificate, CertificateVerify,
/// Finished), not yet fed to the client.
const Flight = struct {
    se: Session,
    bytes: [8192]u8 = undefined,
    records: [8][]const u8 = undefined,
    count: usize = 0,

    fn start(f: *Flight) !void {
        f.se.server = try testServerOf(fx_chain, fx_key, "");
        f.se.client = try testClient(fx_root, "");
        f.se.s = mo_tls_conn_new(f.se.server).?;
        f.se.c = try connectWith(f.se.client, "localhost", test_now, .{});
        var wire: [2048]u8 = undefined;
        var n: usize = 0;
        _ = mo_tls_flush(f.se.c, &wire, wire.len, &n);
        mo_tls_sent(f.se.c, n);
        try testing.expectEqual(ok, mo_tls_feed(f.se.s, &wire, n));
        _ = mo_tls_flush(f.se.s, &f.bytes, f.bytes.len, &n);
        mo_tls_sent(f.se.s, n);
        f.count = splitRecords(f.bytes[0..n], &f.records).len;
        try testing.expectEqual(@as(usize, 6), f.count);
    }

    fn feed(f: *Flight, i: usize) c_int {
        return mo_tls_feed(f.se.c, f.records[i].ptr, f.records[i].len);
    }
};

test "the five rejections, fed to the client" {
    // 1. A truncated record waits and answers nothing; its last byte completes it.
    {
        var f: Flight = .{ .se = undefined };
        try f.start();
        defer f.se.deinit();
        const hello = f.records[0];
        try testing.expectEqual(ok, mo_tls_feed(f.se.c, hello.ptr, hello.len - 1));
        try testing.expectEqual(@as(usize, 0), mo_tls_pending(f.se.c));
        var got: usize = 0;
        var out: [64]u8 = undefined;
        try testing.expectEqual(want_more, mo_tls_read(f.se.c, &out, out.len, &got));
        try testing.expectEqual(Phase.wait_server_hello, f.se.c.phase);
        try testing.expectEqual(ok, mo_tls_feed(f.se.c, hello[hello.len - 1 ..].ptr, 1));
        try testing.expectEqual(Phase.wait_encrypted_extensions, f.se.c.phase);
        for (1..f.count) |i| try testing.expectEqual(ok, f.feed(i));
        try testing.expect(mo_tls_ready(f.se.c));
    }
    // 2. A wrong Finished: the server's Finished checked against a key one bit off, which is the
    // client's view of a Finished that is wrong (the record's tag is right, only the HMAC is not).
    {
        var f: Flight = .{ .se = undefined };
        try f.start();
        defer f.se.deinit();
        for (0..f.count - 1) |i| try testing.expectEqual(ok, f.feed(i));
        try testing.expectEqual(Phase.wait_server_finished, f.se.c.phase);
        f.se.c.server_finished_key[0] ^= 1;
        try testing.expectEqual(failed, f.feed(f.count - 1));
        try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.decrypt_error)), mo_tls_alert(f.se.c));
        try testing.expect(mo_tls_pending(f.se.c) > 0);
    }
    // 3. A record past 16 KiB plus 256.
    {
        var f: Flight = .{ .se = undefined };
        try f.start();
        defer f.se.deinit();
        var header: [5]u8 = .{ @intFromEnum(tls.ContentType.handshake), 0x03, 0x03, 0, 0 };
        put16(header[3..5], max_ciphertext + 1);
        try testing.expectEqual(failed, mo_tls_feed(f.se.c, &header, header.len));
        try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.record_overflow)), mo_tls_alert(f.se.c));
    }
    // 4. A bad tag on the first protected record.
    {
        var f: Flight = .{ .se = undefined };
        try f.start();
        defer f.se.deinit();
        try testing.expectEqual(ok, f.feed(0));
        try testing.expectEqual(ok, f.feed(1));
        const ee = f.records[2];
        f.bytes[@intFromPtr(ee.ptr) - @intFromPtr(&f.bytes) + ee.len - 1] ^= 0x01;
        try testing.expectEqual(failed, f.feed(2));
        try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.bad_record_mac)), mo_tls_alert(f.se.c));
    }
    // 5. A plain HTTP response where a ServerHello belongs.
    {
        var f: Flight = .{ .se = undefined };
        try f.start();
        defer f.se.deinit();
        const response = "HTTP/1.1 400 Bad Request\r\ncontent-length: 0\r\n\r\n";
        try testing.expectEqual(failed, mo_tls_feed(f.se.c, response.ptr, response.len));
        try testing.expectEqual(@as(c_int, @intFromEnum(tls.Alert.Description.unexpected_message)), mo_tls_alert(f.se.c));
        try testing.expect(!f.se.c.alert_from_peer);
    }
}

// RFC 8448 section 3, the simple 1-RTT handshake, as the trace prints it: the client's ephemeral
// X25519 key and random, its hello's layout, and every record either side sent.
const rfc_client_random = hex("cb34ecb1e78163ba1c38c6dacb196a6dffa21a8d9912ec18a2ef6283024dece7");
const rfc_client_secret = hex("49af42ba7f7994852d713ef2784bcbcaa7911de26adc5642cb634540e7ea5005");
const rfc_suites = hex("0006130113031302");
const rfc_before_share = hex("0000000b0009000006736572766572ff01000100000a00140012001d0017001800190100010101020103010400230000");
const rfc_after_share = hex("002b0003020304000d0020001e040305030603020308040805080604010501060102010402050206020202002d000201" ++
    "01001c00024001");
const rfc_client_hello = hex("16030100c4010000c00303cb34ecb1e78163ba1c38c6dacb196a6dffa21a8d9912ec18a2ef6283024dece70000061301" ++
    "13031302010000910000000b0009000006736572766572ff01000100000a00140012001d001700180019010001010102" ++
    "0103010400230000003300260024001d002099381de560e4bd43d23d8e435a7dbafeb3c06e51c13cae4d5413691e529a" ++
    "af2c002b0003020304000d0020001e040305030603020308040805080604010501060102010402050206020202002d00" ++
    "020101001c00024001");
const rfc_server_hello = hex("160303005a020000560303a6af06a4121860dc5e6e60249cd34c95930c8ac5cb1434dac155772ed3e269280013010000" ++
    "2e00330024001d0020c9828876112095fe66762bdbf7c672e156d6cc253b833df1dd69b1b04e751f0f002b00020304");
const rfc_server_flight = hex("17030302a2d1ff334a56f5bff6594a07cc87b580233f500f45e489e7f33af35edf7869fcf40aa40aa2b8ea73f848a7ca" ++
    "07612ef9f945cb960b4068905123ea78b111b429ba9191cd05d2a389280f526134aadc7fc78c4b729df828b5ecf7b13b" ++
    "d9aefb0e57f271585b8ea9bb355c7c79020716cfb9b1183ef3ab20e37d57a6b9d7477609aee6e122a4cf51427325250c" ++
    "7d0e509289444c9b3a648f1d71035d2ed65b0e3cdd0cbae8bf2d0b227812cbb360987255cc744110c453baa4fcd61092" ++
    "8d809810e4b7ed1a8fd991f06aa6248204797e36a6a73b70a2559c09ead686945ba246ab66e5edd8044b4c6de3fcf2a8" ++
    "9441ac66272fd8fb330ef8190579b3684596c960bd596eea520a56a8d650f563aad27409960dca63d3e688611ea5e22f" ++
    "4415cf9538d51a200c27034272968a264ed6540c84838d89f72c24461aad6d26f59ecaba9acbbb317b66d902f4f292a3" ++
    "6ac1b639c637ce343117b659622245317b49eeda0c6258f100d7d961ffb138647e92ea330faeea6dfa31c7a84dc3bd7e" ++
    "1b7a6c7178af36879018e3f252107f243d243dc7339d5684c8b0378bf30244da8c87c843f5e56eb4c5e8280a2b48052c" ++
    "f93b16499a66db7cca71e4599426f7d461e66f99882bd89fc50800becca62d6c74116dbd2972fda1fa80f85df881edbe" ++
    "5a37668936b335583b599186dc5c6918a396fa48a181d6b6fa4f9d62d513afbb992f2b992f67f8afe67f76913fa388cb" ++
    "5630c8ca01e0c65d11c66a1e2ac4c85977b7c7a6999bbf10dc35ae69f5515614636c0b9b68c19ed2e31c0b3b66763038" ++
    "ebba42f3b38edc0399f3a9f23faa63978c317fc9fa66a73f60f0504de93b5b845e275592c12335ee340bbc4fddd50278" ++
    "4016e4b3be7ef04dda49f4b440a30cb5d2af939828fd4ae3794e44f94df5a631ede42c1719bfdabf0253fe5175be898e" ++
    "750edc53370d2b");
const rfc_client_finished = hex("170303003575ec4dc238cce60b298044a71e219c56cc77b0517fe9b93c7a4bfc44d87f38f80338ac98fc46deb384bd1c" ++
    "aeacab6867d726c40546");
const rfc_ticket = hex("17030300de3a6b8f90414a97d6959c3487680de5134a2b240e6cffac116e95d41d6af8f6b580dcf3d11d63c758db289a" ++
    "015940252f55713e061dc13e078891a38efbcf5753ad8ef170ad3c7353d16d9da773b9ca7f2b9fa1b6c0d4a3d03f75e0" ++
    "9c30ba1e62972ac46f75f7b981be63439b2999ce13064615139891d5e4c5b406f16e3fc181a77ca475840025db2f0a77" ++
    "f81b5ab05b94c01346755f69232c86519d86cbeeac87aac347d143f9605d64f650db4d023e70e952ca49fe5137121c74" ++
    "bc2697687e248746d6df353005f3bce18696129c8153556b3b6c6779b37bf15985684f");
const rfc_client_app = hex("1703030043a23f7054b62c94d0affafe8228ba55cbefacea42f914aa66bcab3f2b9819a8a5b46b395bd54a9a20441e2b" ++
    "62974e1f5a6292a2977014bd1e3deae63aeebb21694915e4");
const rfc_server_app = hex("17030300432e937e11ef4ac740e538ad36005fc4a46932fc3225d05f82aa1b36e30efaf97d90e6dffc602dcb501a59a8" ++
    "fcc49c4bf2e5f0a21c0047c2abf332540dd032e167c2955d");
const rfc_client_alert = hex("1703030013c9872760655666b74d7ff1153efd6db6d0b0e3");
const rfc_server_alert = hex("1703030013b58fd67166ebf599d24720cfbe7efa7a8864a9");
const rfc_app_payload = hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f" ++
    "3031");

test "RFC 8448 section 3 replayed through the client: its hello, its Finished, and the records after, byte for byte" {
    const client = try testClient(fx_root, "");
    defer mo_tls_client_free(client);
    // The trace's certificate is RSA, outside the cut, so this client takes it unchecked: what
    // is held to the trace is the hello, the key schedule, the transcript, and the records.
    const c = try connectWith(client, "server", 0, .{
        .random = rfc_client_random,
        .x25519_secret = rfc_client_secret,
        .session_id = "",
        .skip_auth = true,
        .hello = .{ .suites = &rfc_suites, .before_share = &rfc_before_share, .after_share = &rfc_after_share },
    });
    defer mo_tls_conn_free(c);
    try testing.expectEqualSlices(u8, &hex("99381de560e4bd43d23d8e435a7dbafeb3c06e51c13cae4d5413691e529aaf2c"), &c.public_key);

    var wire: [1024]u8 = undefined;
    var n: usize = 0;
    _ = mo_tls_flush(c, &wire, wire.len, &n);
    mo_tls_sent(c, n);
    try testing.expectEqualSlices(u8, &rfc_client_hello, wire[0..n]);

    try testing.expectEqual(ok, mo_tls_feed(c, &rfc_server_hello, rfc_server_hello.len));
    try testing.expectEqual(ok, mo_tls_feed(c, &rfc_server_flight, rfc_server_flight.len));
    try testing.expect(mo_tls_ready(c));
    _ = mo_tls_flush(c, &wire, wire.len, &n);
    mo_tls_sent(c, n);
    try testing.expectEqualSlices(u8, &rfc_client_finished, wire[0..n]);

    // The server's ticket is read and dropped; its 50 bytes come through.
    try testing.expectEqual(ok, mo_tls_feed(c, &rfc_ticket, rfc_ticket.len));
    try testing.expectEqual(ok, mo_tls_feed(c, &rfc_server_app, rfc_server_app.len));
    var plain: [64]u8 = undefined;
    try testing.expectEqual(ok, mo_tls_read(c, &plain, plain.len, &n));
    try testing.expectEqualSlices(u8, &rfc_app_payload, plain[0..n]);

    // The client's own 50 bytes, and its close_notify, are the trace's records.
    try testing.expectEqual(ok, mo_tls_write(c, &rfc_app_payload, rfc_app_payload.len));
    _ = mo_tls_flush(c, &wire, wire.len, &n);
    mo_tls_sent(c, n);
    try testing.expectEqualSlices(u8, &rfc_client_app, wire[0..n]);
    mo_tls_close(c);
    _ = mo_tls_flush(c, &wire, wire.len, &n);
    mo_tls_sent(c, n);
    try testing.expectEqualSlices(u8, &rfc_client_alert, wire[0..n]);
    try testing.expectEqual(ok, mo_tls_feed(c, &rfc_server_alert, rfc_server_alert.len));
    try testing.expectEqual(closed, mo_tls_read(c, &plain, plain.len, &n));
}
