//! The TLS brick (step 36; mo-wiki/deep-dives/bricks-and-the-cost-of-zero-dependencies.md):
//! a TLS 1.3 server, written once and used by both runtimes, as C-ABI exports over `std.crypto`.
//! Zig 0.16 ships a TLS 1.3 *client* (`std/crypto/tls/Client.zig`) and the record layer's types
//! and key schedule (`std/crypto/tls.zig`); it ships no server, so the server's half of RFC 8446
//! is what this file is. Every AEAD, hash, HKDF, X25519, and signature comes from `std.crypto`:
//! nothing cryptographic here is hand-rolled, only the wire format around it.
//!
//! It is an engine over bytes and holds no socket, no allocator of the runtime's, and no
//! scheduler: ciphertext goes in with `mo_tls_feed`, plaintext comes out with `mo_tls_read`,
//! plaintext goes in with `mo_tls_write`, and ciphertext comes out with `mo_tls_flush`. So each
//! runtime drives it from its own sockets and its own poller (net.zig, mo_rt.c) and the handshake
//! is written once.
//!
//! What it speaks (the bricks page's cut, narrowed to this step): TLS 1.3 alone, the two suites
//! `TLS_AES_128_GCM_SHA256` and `TLS_CHACHA20_POLY1305_SHA256` (both over SHA-256, so the
//! transcript hash and the key schedule have one shape), X25519 alone for the key exchange with
//! one HelloRetryRequest when the client supports it but sent no share, Ed25519 and ECDSA P-256
//! server certificates, and post-handshake `KeyUpdate`. Not here, in either direction: TLS 1.2,
//! session tickets, PSK, 0-RTT, client certificates, renegotiation. ALPN is read and left
//! unanswered until step 37, and SNI is read and ignored.
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
/// `mo_tls_server_new`: the certificate or the key does not parse, or they do not match.
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

    fn deinit(s: *Server) void {
        for (s.chain) |der| gpa.free(der);
        gpa.free(s.chain);
        gpa.destroy(s);
    }
};

/// The leaf certificate's public key must be the private key's: a chain and a key from two
/// different pairs is `BadPem`, not a handshake every client rejects.
fn keyMatchesLeaf(leaf: []const u8, key: Key) bool {
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

const Phase = enum {
    /// Nothing read yet: the next handshake message must be a ClientHello.
    hello,
    /// A HelloRetryRequest went out: the next must be the second ClientHello, and no third.
    retried,
    /// Our Finished went out: the client's Finished is what is left.
    wait_finished,
    /// The handshake is done; records carry the program's bytes.
    running,
    /// `close_notify` came, or the stream ended.
    over,
    /// An alert went out (or came in fatal): nothing more is read or written.
    broken,
};

pub const Conn = struct {
    server: *Server,
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
    /// The session id the client sent, echoed back (middlebox compatibility).
    session_id: [32]u8 = @splat(0),
    session_id_len: u8 = 0,
    /// The alert this connection ended on, or 255 for none.
    alert: u8 = 255,
    sent_close_notify: bool = false,

    fn deinit(c: *Conn) void {
        c.in.deinit();
        c.plain.deinit();
        c.out.deinit();
        c.hs.deinit();
        crypto.secureZero(u8, &c.secret_key);
        crypto.secureZero(u8, &c.handshake_secret);
        crypto.secureZero(u8, &c.master_secret);
        crypto.secureZero(u8, &c.read_cipher.key);
        crypto.secureZero(u8, &c.write_cipher.key);
        gpa.destroy(c);
    }

    const Fail = error{ Alert, OutOfMemory };

    /// Ends the connection with `desc`: the alert goes out as the last record, and every later
    /// call is `failed`.
    fn fatal(c: *Conn, desc: tls.Alert.Description) Fail {
        if (c.phase != .broken) {
            c.alert = @intFromEnum(desc);
            const body = [2]u8{ @intFromEnum(tls.Alert.Level.fatal), @intFromEnum(desc) };
            c.sendRecord(.alert, &body) catch {};
            c.phase = .broken;
        }
        return error.Alert;
    }

    // ---- writing records

    /// One record: protected when the keys are up, plain before that.
    fn sendRecord(c: *Conn, inner: tls.ContentType, payload: []const u8) Fail!void {
        std.debug.assert(payload.len <= max_plaintext);
        if (!c.encrypting) {
            const dest = try c.out.room(record_header_len + payload.len);
            dest[0] = @intFromEnum(inner);
            dest[1] = 0x03;
            dest[2] = 0x03;
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
        var at: usize = 0;
        while (at < bytes.len) {
            const n = @min(max_plaintext, bytes.len - at);
            try c.sendRecord(.handshake, bytes[at..][0..n]);
            at += n;
        }
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
                // A client that is not speaking TLS at all: a plain HTTP request starts 'G'.
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
        // A change_cipher_spec is the middlebox-compatibility no-op and is never protected.
        if (ct == .change_cipher_spec) {
            if (body.len != 1 or body[0] != 1) return c.fatal(.unexpected_message);
            return;
        }
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
            .handshake => try c.handshakeBytes(content),
            .alert => {
                if (content.len != 2) return c.fatal(.decode_error);
                const desc: tls.Alert.Description = @enumFromInt(content[1]);
                c.alert = content[1];
                if (desc == .close_notify or desc == .user_canceled) {
                    c.phase = .over;
                    return;
                }
                // A fatal alert from the client: nothing goes back, the connection is over.
                c.phase = .broken;
            },
            else => return c.fatal(.unexpected_message),
        }
    }

    /// Handshake bytes, which may be part of a message or several: whole ones are dispatched.
    fn handshakeBytes(c: *Conn, bytes: []const u8) Fail!void {
        try c.hs.append(bytes);
        while (true) {
            const held = c.hs.slice();
            if (held.len < 4) return;
            const len = mem.readInt(u24, held[1..4], .big);
            if (len > max_plaintext) return c.fatal(.record_overflow);
            if (held.len < 4 + len) return;
            const kind: tls.HandshakeType = @enumFromInt(held[0]);
            const whole = held[0 .. 4 + len];
            try c.message(kind, whole);
            c.hs.consume(4 + len);
        }
    }

    fn message(c: *Conn, kind: tls.HandshakeType, whole: []const u8) Fail!void {
        switch (kind) {
            .client_hello => {
                if (c.phase != .hello and c.phase != .retried) return c.fatal(.unexpected_message);
                try c.clientHello(whole);
            },
            .finished => {
                if (c.phase != .wait_finished) return c.fatal(.unexpected_message);
                try c.clientFinished(whole);
            },
            .key_update => {
                if (c.phase != .running) return c.fatal(.unexpected_message);
                try c.keyUpdate(whole);
            },
            else => return c.fatal(.unexpected_message),
        }
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
    }

    const Hello = struct {
        /// The client's X25519 share, or none and `retry` set.
        share: [32]u8 = @splat(0),
        retry: bool = false,
    };

    fn readHello(c: *Conn, cur: *Cursor) (Fail || Cursor.Short)!Hello {
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
        if (!cur.done()) {
            var exts: Cursor = .{ .b = try cur.vec(u16) };
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
                    // Read and ignored this step: SNI, and ALPN, which step 37 answers.
                    .server_name, .application_layer_protocol_negotiation => {},
                    else => {},
                }
            }
        }
        if (!tls13) return c.fatal(.protocol_version);

        c.suite = pick: {
            var chacha = false;
            var k: usize = 0;
            while (k + 1 < suites.len) : (k += 2) {
                switch (@as(tls.CipherSuite, @enumFromInt(mem.readInt(u16, suites[k..][0..2], .big)))) {
                    .AES_128_GCM_SHA256 => break :pick .aes_128_gcm,
                    .CHACHA20_POLY1305_SHA256 => chacha = true,
                    else => {},
                }
            }
            if (chacha) break :pick .chacha20_poly1305;
            return c.fatal(.handshake_failure);
        };

        // The client must accept the signature the key can make; with no extension it asks for
        // nothing TLS 1.3 allows.
        const want = @intFromEnum(c.server.key.scheme());
        var signable = false;
        var k: usize = 0;
        while (k + 1 < signatures.len) : (k += 2) {
            if (mem.readInt(u16, signatures[k..][0..2], .big) == want) signable = true;
        }
        if (!signable) return c.fatal(.handshake_failure);

        if (share) |s| return .{ .share = s };
        if (supports_x25519) return .{ .retry = true };
        return c.fatal(.handshake_failure);
    }

    /// RFC 8446 4.4.1: after a HelloRetryRequest the transcript starts with a synthetic
    /// `message_hash` message holding the hash of the first ClientHello.
    fn sendRetry(c: *Conn, hello1: []const u8) Fail!void {
        var digest: [32]u8 = undefined;
        var h = Sha256.init(.{});
        h.update(hello1);
        h.final(&digest);
        c.transcript = Sha256.init(.{});
        c.transcript.update(&[_]u8{ @intFromEnum(tls.HandshakeType.message_hash), 0, 0, 32 });
        c.transcript.update(&digest);

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
        entropy(&c.secret_key);
        const kp = X25519.KeyPair.generateDeterministic(c.secret_key) catch return c.fatal(.internal_error);
        c.public_key = kp.public_key;
        const shared = X25519.scalarmult(kp.secret_key, client_share) catch return c.fatal(.illegal_parameter);

        var random: [32]u8 = undefined;
        entropy(&random);
        var body: [128]u8 = undefined;
        const n = c.writeHelloBody(&body, &random, &c.public_key);
        var msg: [132]u8 = undefined;
        msg[0] = @intFromEnum(tls.HandshakeType.server_hello);
        mem.writeInt(u24, msg[1..4], @intCast(n), .big);
        @memcpy(msg[4..][0..n], body[0..n]);
        try c.sendHandshake(msg[0 .. 4 + n]);
        try c.sendRecord(.change_cipher_spec, &.{1});

        // RFC 8446 7.1, with the transcript through the ServerHello.
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
        c.read_cipher.derive(c.suite, client_secret);
        c.write_cipher.derive(c.suite, server_secret);
        c.encrypting = true;
        c.decrypting = true;
    }

    /// EncryptedExtensions, Certificate, CertificateVerify, Finished, all under the handshake key.
    fn sendFlight(c: *Conn) Fail!void {
        // EncryptedExtensions: none of them this step (ALPN is step 37's).
        try c.sendHandshake(&[_]u8{ @intFromEnum(tls.HandshakeType.encrypted_extensions), 0, 0, 2, 0, 0 });

        var certs_len: usize = 0;
        for (c.server.chain) |der| certs_len += 3 + der.len + 2;
        const body_len = 1 + 3 + certs_len;
        const cert_msg = try gpa.alloc(u8, 4 + body_len);
        defer gpa.free(cert_msg);
        cert_msg[0] = @intFromEnum(tls.HandshakeType.certificate);
        mem.writeInt(u24, cert_msg[1..4], @intCast(body_len), .big);
        cert_msg[4] = 0; // certificate_request_context
        mem.writeInt(u24, cert_msg[5..8], @intCast(certs_len), .big);
        var at: usize = 8;
        for (c.server.chain) |der| {
            mem.writeInt(u24, cert_msg[at..][0..3], @intCast(der.len), .big);
            at += 3;
            @memcpy(cert_msg[at..][0..der.len], der);
            at += der.len;
            put16(cert_msg[at..], 0); // no certificate extensions
            at += 2;
        }
        try c.sendHandshake(cert_msg);

        // RFC 8446 4.4.3: 64 spaces, the context string, a zero byte, the transcript hash.
        var signed: [64 + 33 + 1 + 32]u8 = undefined;
        @memset(signed[0..64], 0x20);
        @memcpy(signed[64..][0..33], "TLS 1.3, server CertificateVerify");
        signed[97] = 0;
        @memcpy(signed[98..][0..32], &c.transcript.peek());
        var sig_buf: [EcdsaP256.Signature.der_encoded_length_max]u8 = undefined;
        const signature: []const u8 = switch (c.server.key) {
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
        put16(verify[4..], @intFromEnum(c.server.key.scheme()));
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
        const handshake_hash = c.transcript.peek();
        const client_secret = tls.hkdfExpandLabel(HkdfSha256, c.master_secret, "c ap traffic", &handshake_hash, 32);
        const server_secret = tls.hkdfExpandLabel(HkdfSha256, c.master_secret, "s ap traffic", &handshake_hash, 32);
        c.write_cipher.derive(c.suite, server_secret);
        // Kept until the client's Finished is checked, then installed.
        c.handshake_secret = client_secret;
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
    }

    /// RFC 8446 4.6.3: the client's keys move on, and when it asks, ours do too and it hears so.
    fn keyUpdate(c: *Conn, whole: []const u8) Fail!void {
        if (whole.len != 5) return c.fatal(.decode_error);
        const request: tls.KeyUpdateRequest = @enumFromInt(whole[4]);
        c.read_cipher.update(c.suite);
        if (request == .update_requested) {
            try c.sendHandshake(&[_]u8{ @intFromEnum(tls.HandshakeType.key_update), 0, 0, 1, @intFromEnum(tls.KeyUpdateRequest.update_not_requested) });
            c.write_cipher.update(c.suite);
        }
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
        if (c.phase == .broken) return failed;
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

/// The certificate and key pairs the brick's own tests hand it, the same two `examples/effects/tls`
/// checks in (`openssl req -x509 -newkey ed25519 -days 3650 -subj /CN=localhost`, and `-newkey ec`
/// on P-256). They are written here and not read from a file so the brick stays one file: `mo build`
/// writes this source alone into its cache and compiles it there.
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
                if (std.posix.poll(&p, 1000) catch 0 == 0) break;
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
        const watched = fds[0 .. if (pending.items.len > 0) @as(usize, 2) else 1];
        // Thirty seconds is far past any of these tests; reaching it is a hang, not slowness.
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
                writeAllFd(out_fd, wire[0..n]) catch {};
            }
            return;
        }
    }
}

fn handshakeAndEcho(cert: []const u8, key: []const u8, size: usize) !void {
    const server = mo_tls_server_new(cert.ptr, cert.len, key.ptr, key.len) orelse return error.BadPem;
    defer mo_tls_server_free(server);
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
    if (client.run.failed) |err| return err;
    try testing.expect(client.run.round_tripped);
    // The client's `end` sends close_notify, so a whole session leaves the connection over.
    try testing.expectEqual(Phase.over, conn.phase);
}

// Zig 0.16's own client cannot check an Ed25519 CertificateVerify: `Client.zig`'s
// `verifySignature` maps only the ECDSA and RSA schemes to a key algorithm and answers
// `TlsBadSignatureScheme` for `.ed25519` (line 1549), although its ClientHello offers the
// scheme. So the run against Zig's client is the P-256 pair; the Ed25519 pair's flight is
// checked against the test client below, whose signature check is written here, and against
// OpenSSL in `bench/step36`.
test "a handshake and a megabyte both ways against Zig's own client" {
    try handshakeAndEcho(p256_cert, p256_key, 1 << 20);
}

test "a small handshake against Zig's own client" {
    try handshakeAndEcho(p256_cert, p256_key, 5);
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
            const got = readSomeFd(pair.to_server[0], &wire) catch break;
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
    const hello_n = readSomeFd(pair.to_server[0], &wire) catch 0;
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
        const got = readSomeFd(pair.to_server[0], &wire) catch break;
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
    const hex = struct {
        fn to(comptime text: []const u8) [text.len / 2]u8 {
            var out: [text.len / 2]u8 = undefined;
            _ = std.fmt.hexToBytes(&out, text) catch unreachable;
            return out;
        }
    }.to;

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
