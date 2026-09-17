//! The crypto brick (step 35; mo-wiki/deep-dives/bricks-and-the-cost-of-zero-dependencies.md):
//! the one implementation of `Hash`, `AesGcm`, `ChaCha`, `X25519`, `Ed25519`, `Password`, and
//! `Random` (design-v0/09, `## Crypto`, `## Random`), as C-ABI exports over Zig's `std.crypto`.
//! Nothing here is hand-rolled but the hex text and the fixture stream's framing. Both runtimes call
//! these same exports: the interpreter imports this file (stdlib.zig), and `mo build` compiles it
//! for the target with `zig build-obj -OReleaseFast` and links the object beside `mo_rt.c`
//! (cbuild.zig), whose rows declare the exports in `mo_rt.h` and implement none of them. So the
//! brick is audited once.
//!
//! Every export takes pointers and lengths and writes into a buffer its caller sized. It checks
//! the sizes it needs and answers `bad_size` when one is wrong: the rows check first and crash
//! with a message naming the row and the size (chapter 9, rule 3), so `bad_size` is never
//! reached from Mo. A failed `open` or `verify`, or a low-order X25519 point, is `rejected`:
//! a value the row gives back (`None`, `false`).
//!
//! Entropy comes from the OS on every call and never from process memory: `getrandom(2)` on
//! Linux (a system call, no libc, kernel 3.17 or later), `arc4random_buf(3)` from libSystem on
//! macOS. No other target builds.
const std = @import("std");
const builtin = @import("builtin");
const crypto = std.crypto;

const Sha256 = crypto.hash.sha2.Sha256;
const Sha512 = crypto.hash.sha2.Sha512;
const HmacSha256 = crypto.auth.hmac.sha2.HmacSha256;
const HkdfSha256 = crypto.kdf.hkdf.HkdfSha256;
const Aes256Gcm = crypto.aead.aes_gcm.Aes256Gcm;
const ChaChaPoly = crypto.aead.chacha_poly.ChaCha20Poly1305;
const X25519 = crypto.dh.X25519;
const Ed25519 = crypto.sign.Ed25519;
const argon2 = crypto.pwhash.argon2;
const phc = @import("std").crypto.pwhash.phc_format;

/// What an export answers: done, a value the row gives back as None or false, or a size the
/// row should have refused.
pub const ok: c_int = 0;
pub const rejected: c_int = 1;
pub const bad_size: c_int = -1;
pub const no_memory: c_int = -2;
pub const no_entropy: c_int = -3;

pub const key_size = 32;
pub const nonce_size = 12;
pub const tag_size = 16;
pub const signature_size = 64;
/// HKDF-SHA256 gives at most 255 blocks.
pub const hkdf_max = 255 * 32;
pub const salt_size = 16;
/// `Password.hash`'s parameters (RFC 9106's second recommended option's memory, three passes, one
/// lane), and the only ones `Password.verify?` accepts: a PHC string naming others is false, so a
/// string from outside cannot make a verify take a gibibyte or an hour.
pub const argon_m: u32 = 65536;
pub const argon_t: u32 = 3;
pub const argon_p: u24 = 1;
/// `$argon2id$v=19$m=65536,t=3,p=1$` and a 16-byte salt and a 32-byte hash, unpadded base64.
pub const phc_size = 97;
/// Argon2 version 1.3, which `std.crypto.pwhash.argon2` implements and keeps private.
const argon_version: u32 = 0x13;

fn slice(p: ?[*]const u8, n: usize) []const u8 {
    return if (n == 0) &.{} else p.?[0..n];
}

fn out(p: ?[*]u8, n: usize) []u8 {
    return if (n == 0) &.{} else p.?[0..n];
}

// ---- hashes

pub export fn mo_crypto_sha256(in: ?[*]const u8, n: usize, digest: *[32]u8) void {
    Sha256.hash(slice(in, n), digest, .{});
}

pub export fn mo_crypto_sha512(in: ?[*]const u8, n: usize, digest: *[64]u8) void {
    Sha512.hash(slice(in, n), digest, .{});
}

pub export fn mo_crypto_hmac_sha256(key: ?[*]const u8, key_n: usize, in: ?[*]const u8, n: usize, mac: *[32]u8) void {
    HmacSha256.create(mac, slice(in, n), slice(key, key_n));
}

/// RFC 5869: extract with `salt`, then expand `ikm`'s key with `info` to `size` bytes.
pub export fn mo_crypto_hkdf_sha256(ikm: ?[*]const u8, ikm_n: usize, salt: ?[*]const u8, salt_n: usize, info: ?[*]const u8, info_n: usize, dk: ?[*]u8, size: usize) c_int {
    if (size > hkdf_max) return bad_size;
    const prk = HkdfSha256.extract(slice(salt, salt_n), slice(ikm, ikm_n));
    HkdfSha256.expand(out(dk, size), slice(info, info_n), prk);
    return ok;
}

/// Constant time over the bytes when the lengths are equal; the lengths are not secret.
pub export fn mo_crypto_equal(a: ?[*]const u8, a_n: usize, b: ?[*]const u8, b_n: usize) bool {
    if (a_n != b_n) return false;
    return crypto.timing_safe.compare(u8, slice(a, a_n), slice(b, b_n), .big) == .eq;
}

/// Lowercase hex: `2 * n` bytes into `text`.
pub export fn mo_crypto_hex(in: ?[*]const u8, n: usize, text: ?[*]u8) void {
    const digits = "0123456789abcdef";
    const t = out(text, 2 * n);
    for (slice(in, n), 0..) |b, i| {
        t[2 * i] = digits[b >> 4];
        t[2 * i + 1] = digits[b & 15];
    }
}

/// Hex text, either case, into `n / 2` bytes; `rejected` for an odd length or a byte that is
/// not a hex digit.
pub export fn mo_crypto_from_hex(text: ?[*]const u8, n: usize, bytes: ?[*]u8) c_int {
    if (n % 2 != 0) return rejected;
    const t = slice(text, n);
    const b = out(bytes, n / 2);
    for (b, 0..) |*o, i| {
        const hi = std.fmt.charToDigit(t[2 * i], 16) catch return rejected;
        const lo = std.fmt.charToDigit(t[2 * i + 1], 16) catch return rejected;
        o.* = hi << 4 | lo;
    }
    return ok;
}

// ---- AEADs: `sealed` is the ciphertext and then the 16-byte tag

fn Aead(comptime A: type) type {
    return struct {
        fn seal(key: ?[*]const u8, key_n: usize, nonce: ?[*]const u8, nonce_n: usize, plain: ?[*]const u8, n: usize, aad: ?[*]const u8, aad_n: usize, sealed: ?[*]u8) c_int {
            if (key_n != A.key_length or nonce_n != A.nonce_length) return bad_size;
            const s = out(sealed, n + A.tag_length);
            A.encrypt(s[0..n], s[n..][0..A.tag_length], slice(plain, n), slice(aad, aad_n), nonce.?[0..A.nonce_length].*, key.?[0..A.key_length].*);
            return ok;
        }

        /// `plain` holds `n - 16` bytes; a sealed text shorter than a tag, or one whose tag
        /// does not match, is `rejected` and leaves `plain` zeroed.
        fn open(key: ?[*]const u8, key_n: usize, nonce: ?[*]const u8, nonce_n: usize, sealed: ?[*]const u8, n: usize, aad: ?[*]const u8, aad_n: usize, plain: ?[*]u8) c_int {
            if (key_n != A.key_length or nonce_n != A.nonce_length) return bad_size;
            if (n < A.tag_length) return rejected;
            const s = slice(sealed, n);
            const m = n - A.tag_length;
            A.decrypt(out(plain, m), s[0..m], s[m..][0..A.tag_length].*, slice(aad, aad_n), nonce.?[0..A.nonce_length].*, key.?[0..A.key_length].*) catch return rejected;
            return ok;
        }
    };
}

pub export fn mo_crypto_aes256gcm_seal(key: ?[*]const u8, key_n: usize, nonce: ?[*]const u8, nonce_n: usize, plain: ?[*]const u8, n: usize, aad: ?[*]const u8, aad_n: usize, sealed: ?[*]u8) c_int {
    return Aead(Aes256Gcm).seal(key, key_n, nonce, nonce_n, plain, n, aad, aad_n, sealed);
}

pub export fn mo_crypto_aes256gcm_open(key: ?[*]const u8, key_n: usize, nonce: ?[*]const u8, nonce_n: usize, sealed: ?[*]const u8, n: usize, aad: ?[*]const u8, aad_n: usize, plain: ?[*]u8) c_int {
    return Aead(Aes256Gcm).open(key, key_n, nonce, nonce_n, sealed, n, aad, aad_n, plain);
}

pub export fn mo_crypto_chacha20poly1305_seal(key: ?[*]const u8, key_n: usize, nonce: ?[*]const u8, nonce_n: usize, plain: ?[*]const u8, n: usize, aad: ?[*]const u8, aad_n: usize, sealed: ?[*]u8) c_int {
    return Aead(ChaChaPoly).seal(key, key_n, nonce, nonce_n, plain, n, aad, aad_n, sealed);
}

pub export fn mo_crypto_chacha20poly1305_open(key: ?[*]const u8, key_n: usize, nonce: ?[*]const u8, nonce_n: usize, sealed: ?[*]const u8, n: usize, aad: ?[*]const u8, aad_n: usize, plain: ?[*]u8) c_int {
    return Aead(ChaChaPoly).open(key, key_n, nonce, nonce_n, sealed, n, aad, aad_n, plain);
}

// ---- X25519 (RFC 7748)

pub export fn mo_crypto_x25519_public(secret: ?[*]const u8, secret_n: usize, public: *[32]u8) c_int {
    if (secret_n != X25519.secret_length) return bad_size;
    public.* = X25519.recoverPublicKey(secret.?[0..32].*) catch return rejected;
    return ok;
}

/// `rejected` when `public` is a low-order point, whose shared secret is all zeros.
pub export fn mo_crypto_x25519_shared(secret: ?[*]const u8, secret_n: usize, public: ?[*]const u8, public_n: usize, shared: *[32]u8) c_int {
    if (secret_n != X25519.secret_length or public_n != X25519.public_length) return bad_size;
    shared.* = X25519.scalarmult(secret.?[0..32].*, public.?[0..32].*) catch return rejected;
    return ok;
}

// ---- Ed25519 (RFC 8032): a key pair from a 32-byte seed, deterministic signatures

fn keyPair(seed: ?[*]const u8, seed_n: usize) ?Ed25519.KeyPair {
    if (seed_n != Ed25519.KeyPair.seed_length) return null;
    return Ed25519.KeyPair.generateDeterministic(seed.?[0..32].*) catch null;
}

pub export fn mo_crypto_ed25519_public(seed: ?[*]const u8, seed_n: usize, public: *[32]u8) c_int {
    const pair = keyPair(seed, seed_n) orelse return bad_size;
    public.* = pair.public_key.toBytes();
    return ok;
}

pub export fn mo_crypto_ed25519_sign(seed: ?[*]const u8, seed_n: usize, msg: ?[*]const u8, n: usize, signature: *[64]u8) c_int {
    const pair = keyPair(seed, seed_n) orelse return bad_size;
    const sig = pair.sign(slice(msg, n), null) catch return bad_size;
    signature.* = sig.toBytes();
    return ok;
}

/// `ok` when the signature is valid for the message under the key; `rejected` for any other
/// 32-byte key and 64-byte signature, a key that is not a point included.
pub export fn mo_crypto_ed25519_verify(public: ?[*]const u8, public_n: usize, msg: ?[*]const u8, n: usize, signature: ?[*]const u8, signature_n: usize) c_int {
    if (public_n != Ed25519.PublicKey.encoded_length or signature_n != Ed25519.Signature.encoded_length) return bad_size;
    const key = Ed25519.PublicKey.fromBytes(public.?[0..32].*) catch return rejected;
    const sig = Ed25519.Signature.fromBytes(signature.?[0..64].*);
    sig.verify(slice(msg, n), key) catch return rejected;
    return ok;
}

// ---- Argon2id in a PHC string

const PhcHash = struct {
    alg_id: []const u8,
    alg_version: ?u32,
    m: u32,
    t: u32,
    p: u24,
    salt: phc.BinValue(64),
    hash: phc.BinValue(64),
};

fn argonKdf(dk: []u8, password: []const u8, salt: []const u8) c_int {
    // One lane runs on the calling thread, so the kdf never reaches its Io.
    argon2.kdf(std.heap.page_allocator, dk, password, salt, .{ .t = argon_t, .m = argon_m, .p = argon_p }, .argon2id, std.Io.failing) catch |err| return switch (err) {
        error.OutOfMemory => no_memory,
        else => bad_size,
    };
    return ok;
}

/// Writes the PHC string, `phc_size` bytes, into `text`. The salt is 16 bytes.
pub export fn mo_crypto_argon2id_hash(password: ?[*]const u8, n: usize, salt: ?[*]const u8, salt_n: usize, text: *[phc_size]u8) c_int {
    if (salt_n != salt_size) return bad_size;
    var dk: [32]u8 = undefined;
    const got = argonKdf(&dk, slice(password, n), slice(salt, salt_n));
    if (got != ok) return got;
    const written = phc.serialize(PhcHash{
        .alg_id = "argon2id",
        .alg_version = argon_version,
        .m = argon_m,
        .t = argon_t,
        .p = argon_p,
        .salt = phc.BinValue(64).fromSlice(slice(salt, salt_n)) catch unreachable,
        .hash = phc.BinValue(64).fromSlice(&dk) catch unreachable,
    }, text) catch return bad_size;
    std.debug.assert(written.len == phc_size);
    return ok;
}

/// `ok` when the string is one `mo_crypto_argon2id_hash` writes (argon2id, version 19, its
/// parameters, a 16-byte salt, a 32-byte hash) and the password hashes to it; `rejected` for
/// anything else, a malformed string included; `no_memory` when the 64 MiB were not there.
pub export fn mo_crypto_argon2id_verify(password: ?[*]const u8, n: usize, text: ?[*]const u8, text_n: usize) c_int {
    if (text_n != phc_size) return rejected;
    const got = phc.deserialize(PhcHash, slice(text, text_n)) catch return rejected;
    if (!std.mem.eql(u8, got.alg_id, "argon2id") or got.alg_version != argon_version) return rejected;
    if (got.m != argon_m or got.t != argon_t or got.p != argon_p) return rejected;
    if (got.salt.len != salt_size or got.hash.len != 32) return rejected;
    // The parser lets some strings through that the hash never writes (a trailing `$`, base64
    // with stray bits): only the one spelling of these values verifies.
    var again: [phc_size]u8 = undefined;
    const spelled = phc.serialize(got, &again) catch return rejected;
    if (!std.mem.eql(u8, spelled, slice(text, text_n))) return rejected;
    var dk: [32]u8 = undefined;
    const kdf = argonKdf(&dk, slice(password, n), got.salt.constSlice());
    if (kdf != ok) return kdf;
    return if (crypto.timing_safe.eql([32]u8, dk, got.hash.constSlice()[0..32].*)) ok else rejected;
}

// ---- randomness

extern "c" fn arc4random_buf(buf: [*]u8, n: usize) void;

/// `n` bytes from the OS CSPRNG.
pub export fn mo_crypto_random(bytes: ?[*]u8, n: usize) c_int {
    const b = out(bytes, n);
    switch (builtin.os.tag) {
        .linux => {
            const linux = std.os.linux;
            var i: usize = 0;
            while (i < b.len) {
                const rc = linux.getrandom(b[i..].ptr, b.len - i, 0);
                switch (linux.errno(rc)) {
                    .SUCCESS => i += rc,
                    .INTR => {},
                    else => return no_entropy,
                }
            }
        },
        .macos, .ios, .tvos, .watchos, .visionos => if (b.len > 0) arc4random_buf(b.ptr, b.len),
        else => @compileError("the crypto brick has no entropy source for this target"),
    }
    return ok;
}

/// `Random.fixture()`'s stream (tests only): the bytes at `offset` of a ChaCha20 keystream whose
/// key is SHA-256 of the run's seed, so a test that draws a key replays under its seed.
pub export fn mo_crypto_fixture_bytes(seed: u64, offset: u64, bytes: ?[*]u8, n: usize) void {
    const Stream = crypto.stream.chacha.ChaCha20With64BitNonce;
    var key: [32]u8 = undefined;
    var seed_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &seed_bytes, seed, .little);
    Sha256.hash(&seed_bytes, &key, .{});
    const b = out(bytes, n);
    var block: [64]u8 = undefined;
    var at = offset;
    var i: usize = 0;
    while (i < b.len) {
        Stream.stream(&block, at / 64, key, @splat(0));
        const skip: usize = @intCast(at % 64);
        const take = @min(64 - skip, b.len - i);
        @memcpy(b[i..][0..take], block[skip..][0..take]);
        i += take;
        at += take;
    }
}

// ---- the standards' vectors

const testing = std.testing;

fn hex(comptime text: []const u8) [text.len / 2]u8 {
    var b: [text.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&b, text) catch unreachable;
    return b;
}

test "FIPS 180-4: SHA-256 and SHA-512" {
    var d: [32]u8 = undefined;
    mo_crypto_sha256(null, 0, &d);
    try testing.expectEqual(hex("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), d);
    mo_crypto_sha256("abc", 3, &d);
    try testing.expectEqual(hex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"), d);
    const two = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    mo_crypto_sha256(two, two.len, &d);
    try testing.expectEqual(hex("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"), d);
    var e: [64]u8 = undefined;
    mo_crypto_sha512("abc", 3, &e);
    try testing.expectEqual(hex("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"), e);
    const two512 = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu";
    mo_crypto_sha512(two512, two512.len, &e);
    try testing.expectEqual(hex("8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909"), e);
}

test "RFC 4231: HMAC-SHA256, cases 1, 2, and 6" {
    var m: [32]u8 = undefined;
    const k1: [20]u8 = @splat(0x0b);
    mo_crypto_hmac_sha256(&k1, 20, "Hi There", 8, &m);
    try testing.expectEqual(hex("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"), m);
    const d2 = "what do ya want for nothing?";
    mo_crypto_hmac_sha256("Jefe", 4, d2, d2.len, &m);
    try testing.expectEqual(hex("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"), m);
    const k6: [131]u8 = @splat(0xaa);
    const d6 = "Test Using Larger Than Block-Size Key - Hash Key First";
    mo_crypto_hmac_sha256(&k6, 131, d6, d6.len, &m);
    try testing.expectEqual(hex("60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"), m);
}

test "RFC 5869: HKDF-SHA256, cases 1 and 3" {
    const ikm: [22]u8 = @splat(0x0b);
    const salt = hex("000102030405060708090a0b0c");
    const info = hex("f0f1f2f3f4f5f6f7f8f9");
    var dk: [42]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_hkdf_sha256(&ikm, 22, &salt, salt.len, &info, info.len, &dk, 42));
    try testing.expectEqual(hex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"), dk);
    try testing.expectEqual(ok, mo_crypto_hkdf_sha256(&ikm, 22, null, 0, null, 0, &dk, 42));
    try testing.expectEqual(hex("8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"), dk);
    try testing.expectEqual(bad_size, mo_crypto_hkdf_sha256(&ikm, 22, null, 0, null, 0, &dk, hkdf_max + 1));
}

test "NIST GCM: AES-256, test cases 13, 14, and 16" {
    const zero_key: [32]u8 = @splat(0);
    const zero_iv: [12]u8 = @splat(0);
    var tag_only: [16]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_aes256gcm_seal(&zero_key, 32, &zero_iv, 12, null, 0, null, 0, &tag_only));
    try testing.expectEqual(hex("530f8afbc74536b9a963b4f1c4cb738b"), tag_only);
    const zeros: [16]u8 = @splat(0);
    var s14: [32]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_aes256gcm_seal(&zero_key, 32, &zero_iv, 12, &zeros, 16, null, 0, &s14));
    try testing.expectEqual(hex("cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919"), s14);
    const key = hex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308");
    const iv = hex("cafebabefacedbaddecaf888");
    const p = hex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39");
    const a = hex("feedfacedeadbeeffeedfacedeadbeefabaddad2");
    const want = hex("522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662" ++ "76fc6ece0f4e1768cddf8853bb2d551b");
    var s16: [want.len]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_aes256gcm_seal(&key, 32, &iv, 12, &p, p.len, &a, a.len, &s16));
    try testing.expectEqual(want, s16);
    var back: [p.len]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_aes256gcm_open(&key, 32, &iv, 12, &s16, s16.len, &a, a.len, &back));
    try testing.expectEqual(p, back);
    s16[3] ^= 1;
    try testing.expectEqual(rejected, mo_crypto_aes256gcm_open(&key, 32, &iv, 12, &s16, s16.len, &a, a.len, &back));
    try testing.expectEqual(rejected, mo_crypto_aes256gcm_open(&key, 32, &iv, 12, &s16, 15, &a, a.len, &back));
    try testing.expectEqual(bad_size, mo_crypto_aes256gcm_seal(&key, 31, &iv, 12, &p, p.len, &a, a.len, &s16));
    try testing.expectEqual(bad_size, mo_crypto_aes256gcm_open(&key, 32, &iv, 11, &s16, s16.len, &a, a.len, &back));
}

test "RFC 8439 2.8.2: ChaCha20-Poly1305" {
    const key = hex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f");
    const nonce = hex("070000004041424344454647");
    const aad = hex("50515253c0c1c2c3c4c5c6c7");
    const plain = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
    const want = hex("d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116" ++ "1ae10b594f09e26a7e902ecbd0600691");
    var sealed: [want.len]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_chacha20poly1305_seal(&key, 32, &nonce, 12, plain, plain.len, &aad, aad.len, &sealed));
    try testing.expectEqual(want, sealed);
    var back: [plain.len]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_chacha20poly1305_open(&key, 32, &nonce, 12, &sealed, sealed.len, &aad, aad.len, &back));
    try testing.expectEqualStrings(plain, &back);
    try testing.expectEqual(rejected, mo_crypto_chacha20poly1305_open(&key, 32, &nonce, 12, &sealed, sealed.len, &aad, aad.len - 1, &back));
}

test "RFC 7748 6.1: X25519" {
    const alice = hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
    const bob = hex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
    var alice_pub: [32]u8 = undefined;
    var bob_pub: [32]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_x25519_public(&alice, 32, &alice_pub));
    try testing.expectEqual(ok, mo_crypto_x25519_public(&bob, 32, &bob_pub));
    try testing.expectEqual(hex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"), alice_pub);
    try testing.expectEqual(hex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"), bob_pub);
    var k1: [32]u8 = undefined;
    var k2: [32]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_x25519_shared(&alice, 32, &bob_pub, 32, &k1));
    try testing.expectEqual(ok, mo_crypto_x25519_shared(&bob, 32, &alice_pub, 32, &k2));
    try testing.expectEqual(hex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"), k1);
    try testing.expectEqual(k1, k2);
    const low_order: [32]u8 = @splat(0);
    try testing.expectEqual(rejected, mo_crypto_x25519_shared(&alice, 32, &low_order, 32, &k1));
    try testing.expectEqual(bad_size, mo_crypto_x25519_shared(&alice, 31, &bob_pub, 32, &k1));
}

test "RFC 8032 7.1: Ed25519, tests 1 and 2" {
    const cases = [_]struct { seed: [32]u8, public: [32]u8, msg: []const u8, sig: [64]u8 }{
        .{
            .seed = hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"),
            .public = hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"),
            .msg = "",
            .sig = hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
        },
        .{
            .seed = hex("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"),
            .public = hex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"),
            .msg = "\x72",
            .sig = hex("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
        },
    };
    for (cases) |c| {
        var public: [32]u8 = undefined;
        var sig: [64]u8 = undefined;
        try testing.expectEqual(ok, mo_crypto_ed25519_public(&c.seed, 32, &public));
        try testing.expectEqual(c.public, public);
        try testing.expectEqual(ok, mo_crypto_ed25519_sign(&c.seed, 32, c.msg.ptr, c.msg.len, &sig));
        try testing.expectEqual(c.sig, sig);
        try testing.expectEqual(ok, mo_crypto_ed25519_verify(&public, 32, c.msg.ptr, c.msg.len, &sig, 64));
        sig[0] ^= 1;
        try testing.expectEqual(rejected, mo_crypto_ed25519_verify(&public, 32, c.msg.ptr, c.msg.len, &sig, 64));
        try testing.expectEqual(bad_size, mo_crypto_ed25519_verify(&public, 32, c.msg.ptr, c.msg.len, &sig, 63));
    }
    try testing.expectEqual(bad_size, mo_crypto_ed25519_public(&cases[0].seed, 31, undefined));
}

test "RFC 9106 5.3: Argon2id, and the brick's parameters against OpenSSL" {
    // The RFC's vector has four lanes, a secret, and associated data, which the rows do not
    // take: it checks the std implementation the brick calls.
    const password: [32]u8 = @splat(0x01);
    const salt: [16]u8 = @splat(0x02);
    const secret: [8]u8 = @splat(0x03);
    const ad: [12]u8 = @splat(0x04);
    var dk: [32]u8 = undefined;
    try argon2.kdf(testing.allocator, &dk, &password, &salt, .{ .t = 3, .m = 32, .p = 4, .secret = &secret, .ad = &ad }, .argon2id, testing.io);
    try testing.expectEqual(hex("0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"), dk);
    // m=65536, t=3, p=1 on "password" with sixteen 0x02 bytes: OpenSSL 3's Argon2id through
    // Python's cryptography 50 gives this tag (toolchain/bench/step35).
    var text: [phc_size]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_argon2id_hash("password", 8, &salt, 16, &text));
    const tag = hex("fe525ab59ed3b936920e320c0c812a4721c7e8213b4bd4b960c9f15b409c9540");
    var b64: [43]u8 = undefined;
    _ = std.base64.standard_no_pad.Encoder.encode(&b64, &tag);
    try testing.expectEqualStrings("$argon2id$v=19$m=65536,t=3,p=1$AgICAgICAgICAgICAgICAg$" ++ b64, &text);
    try testing.expectEqual(ok, mo_crypto_argon2id_verify("password", 8, &text, text.len));
    try testing.expectEqual(rejected, mo_crypto_argon2id_verify("passwore", 8, &text, text.len));
    try testing.expectEqual(rejected, mo_crypto_argon2id_verify("password", 8, "$argon2id$v=19$m=65536", 22));
    try testing.expectEqual(rejected, mo_crypto_argon2id_verify("password", 8, null, 0));
    var trailing: [phc_size + 1]u8 = undefined;
    @memcpy(trailing[0..phc_size], &text);
    trailing[phc_size] = '$';
    try testing.expectEqual(rejected, mo_crypto_argon2id_verify("password", 8, &trailing, trailing.len));
    const heavy = "$argon2id$v=19$m=1048576,t=3,p=1$AgICAgICAgICAgICAgICAg$" ++ b64;
    try testing.expectEqual(rejected, mo_crypto_argon2id_verify("password", 8, heavy, heavy.len));
    try testing.expectEqual(bad_size, mo_crypto_argon2id_hash("password", 8, &salt, 15, &text));
}

test "constant-time equality, hex, and the two random sources" {
    try testing.expect(mo_crypto_equal("abc", 3, "abc", 3));
    try testing.expect(!mo_crypto_equal("abc", 3, "abd", 3));
    try testing.expect(!mo_crypto_equal("abc", 3, "ab", 2));
    try testing.expect(mo_crypto_equal(null, 0, null, 0));
    var t: [6]u8 = undefined;
    mo_crypto_hex("\x00\xab\xff", 3, &t);
    try testing.expectEqualStrings("00abff", &t);
    var b: [3]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_from_hex("00ABff", 6, &b));
    try testing.expectEqualStrings("\x00\xab\xff", &b);
    try testing.expectEqual(rejected, mo_crypto_from_hex("00abf", 5, &b));
    try testing.expectEqual(rejected, mo_crypto_from_hex("00abfg", 6, &b));

    var r1: [64]u8 = undefined;
    var r2: [64]u8 = undefined;
    try testing.expectEqual(ok, mo_crypto_random(&r1, 64));
    try testing.expectEqual(ok, mo_crypto_random(&r2, 64));
    try testing.expect(!std.mem.eql(u8, &r1, &r2));

    // The fixture stream is one keystream: drawn in pieces or at once, the same bytes.
    var whole: [200]u8 = undefined;
    mo_crypto_fixture_bytes(7, 0, &whole, 200);
    var pieces: [200]u8 = undefined;
    mo_crypto_fixture_bytes(7, 0, &pieces, 5);
    mo_crypto_fixture_bytes(7, 5, pieces[5..].ptr, 70);
    mo_crypto_fixture_bytes(7, 75, pieces[75..].ptr, 125);
    try testing.expectEqualSlices(u8, &whole, &pieces);
    mo_crypto_fixture_bytes(8, 0, &pieces, 200);
    try testing.expect(!std.mem.eql(u8, &whole, &pieces));
}
