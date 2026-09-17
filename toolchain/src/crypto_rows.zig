//! The interpreter's crypto and `Random` rows (step 35, design-v0/09 `## Crypto` and `## Random`):
//! each turns its `List(UInt8)` and `String` arguments into bytes, calls the crypto brick's
//! export (bricks/crypto.zig), the one `mo build`'s binaries link, and turns the bytes back into a
//! value. A key, nonce, seed, salt, or signature of the wrong size is a crash naming the row and the
//! size it got (chapter 9, rule 3); a failed open or verify is a value.
const std = @import("std");
const brick = @import("bricks/crypto.zig");
const prelude = @import("prelude.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;

pub const Row = enum {
    @"Hash.sha256",
    @"Hash.sha512",
    @"Hash.hmac_sha256",
    @"Hash.hkdf_sha256",
    @"Hash.hex",
    @"Hash.from_hex",
    @"Hash.equal?",
    @"AesGcm.seal",
    @"AesGcm.open",
    @"ChaCha.seal",
    @"ChaCha.open",
    @"X25519.public",
    @"X25519.shared",
    @"Ed25519.public",
    @"Ed25519.sign",
    @"Ed25519.verify?",
    @"Password.hash",
    @"Password.verify?",
    @"Random.bytes",
    @"Random.fixture",
};

/// A row's bytes, held for one call in the vm's gpa.
const Bytes = struct {
    items: []u8,

    fn of(vm: *Vm, values: []const Value) Error!Bytes {
        const items = try vm.gpa.alloc(u8, values.len);
        for (values, items) |v, *b| b.* = @intCast(v.int);
        return .{ .items = items };
    }

    fn free(b: Bytes, vm: *Vm) void {
        vm.gpa.free(b.items);
    }
};

fn list(vm: *Vm, bytes: []const u8) Error!Value {
    const out = try vm_mod.rawAlloc(vm.heap, Value, bytes.len);
    for (bytes, out) |b, *o| o.* = .{ .int = b };
    return .{ .list = out };
}

fn crash(vm: *Vm, row: prelude.Fn, comptime format: []const u8, args: anytype) Error {
    vm.report = .{ .kind = .other, .clause = try std.fmt.allocPrint(vm.gpa, format, args), .within = row.name, .at = 0 };
    return error.Crash;
}

/// A crash unless `n` is `want`: `AesGcm.seal takes a key of 32 bytes, not 31`.
fn size(vm: *Vm, row: prelude.Fn, what: []const u8, want: usize, n: usize) Error!void {
    if (n != want) return crash(vm, row, "{s}.{s} takes {s} of {d} bytes, not {d}", .{ row.recv, row.name, what, want, n });
}

/// An export's answer that only a size the row let through could give.
fn unexpected(vm: *Vm, row: prelude.Fn, rc: c_int) Error {
    return switch (rc) {
        brick.no_memory => error.OutOfMemory,
        else => crash(vm, row, "{s}.{s}: the crypto brick answered {d}", .{ row.recv, row.name, rc }),
    };
}

fn some(vm: *Vm, v: Value) Error!Value {
    return vm.variant("Some", &.{v});
}

fn none(vm: *Vm) Error!Value {
    return vm.variant("None", &.{});
}

pub fn call(vm: *Vm, row: prelude.Fn, a: []const Value) Error!Value {
    var label_buf: [64]u8 = undefined;
    const label = std.fmt.bufPrint(&label_buf, "{s}.{s}", .{ row.recv, row.name }) catch unreachable;
    const which = std.meta.stringToEnum(Row, label).?;
    switch (which) {
        .@"Hash.sha256", .@"Hash.sha512" => {
            const in = try Bytes.of(vm, a[0].list);
            defer in.free(vm);
            var d: [64]u8 = undefined;
            if (which == .@"Hash.sha256") {
                brick.mo_crypto_sha256(in.items.ptr, in.items.len, d[0..32]);
                return list(vm, d[0..32]);
            }
            brick.mo_crypto_sha512(in.items.ptr, in.items.len, &d);
            return list(vm, &d);
        },
        .@"Hash.hmac_sha256" => {
            const key = try Bytes.of(vm, a[0].list);
            defer key.free(vm);
            const in = try Bytes.of(vm, a[1].list);
            defer in.free(vm);
            var d: [32]u8 = undefined;
            brick.mo_crypto_hmac_sha256(key.items.ptr, key.items.len, in.items.ptr, in.items.len, &d);
            return list(vm, &d);
        },
        .@"Hash.hkdf_sha256" => {
            if (a[3].int > brick.hkdf_max) return crash(vm, row, "Hash.hkdf_sha256 gives at most {d} bytes, not {d}", .{ brick.hkdf_max, a[3].int });
            const ikm = try Bytes.of(vm, a[0].list);
            defer ikm.free(vm);
            const salt = try Bytes.of(vm, a[1].list);
            defer salt.free(vm);
            const info = try Bytes.of(vm, a[2].list);
            defer info.free(vm);
            var dk: [brick.hkdf_max]u8 = undefined;
            const n: usize = @intCast(a[3].int);
            const rc = brick.mo_crypto_hkdf_sha256(ikm.items.ptr, ikm.items.len, salt.items.ptr, salt.items.len, info.items.ptr, info.items.len, &dk, n);
            if (rc != brick.ok) return unexpected(vm, row, rc);
            return list(vm, dk[0..n]);
        },
        .@"Hash.hex" => {
            const in = try Bytes.of(vm, a[0].list);
            defer in.free(vm);
            const text = try vm_mod.rawAlloc(vm.heap, u8, 2 * in.items.len);
            brick.mo_crypto_hex(in.items.ptr, in.items.len, text.ptr);
            return .{ .string = text };
        },
        .@"Hash.from_hex" => {
            const text = a[0].string;
            const bytes = try vm.gpa.alloc(u8, text.len / 2);
            defer vm.gpa.free(bytes);
            if (brick.mo_crypto_from_hex(text.ptr, text.len, bytes.ptr) != brick.ok) return none(vm);
            return some(vm, try list(vm, bytes));
        },
        .@"Hash.equal?" => {
            const x = try Bytes.of(vm, a[0].list);
            defer x.free(vm);
            const y = try Bytes.of(vm, a[1].list);
            defer y.free(vm);
            return .{ .bool = brick.mo_crypto_equal(x.items.ptr, x.items.len, y.items.ptr, y.items.len) };
        },
        .@"AesGcm.seal", .@"AesGcm.open", .@"ChaCha.seal", .@"ChaCha.open" => {
            try size(vm, row, "a key", brick.key_size, a[0].list.len);
            try size(vm, row, "a nonce", brick.nonce_size, a[1].list.len);
            const key = try Bytes.of(vm, a[0].list);
            defer key.free(vm);
            const nonce = try Bytes.of(vm, a[1].list);
            defer nonce.free(vm);
            const in = try Bytes.of(vm, a[2].list);
            defer in.free(vm);
            const aad = try Bytes.of(vm, a[3].list);
            defer aad.free(vm);
            const sealing = which == .@"AesGcm.seal" or which == .@"ChaCha.seal";
            const n = if (sealing) in.items.len + brick.tag_size else in.items.len -| brick.tag_size;
            const got = try vm.gpa.alloc(u8, n);
            defer vm.gpa.free(got);
            const f = switch (which) {
                .@"AesGcm.seal" => &brick.mo_crypto_aes256gcm_seal,
                .@"AesGcm.open" => &brick.mo_crypto_aes256gcm_open,
                .@"ChaCha.seal" => &brick.mo_crypto_chacha20poly1305_seal,
                else => &brick.mo_crypto_chacha20poly1305_open,
            };
            const rc = f(key.items.ptr, key.items.len, nonce.items.ptr, nonce.items.len, in.items.ptr, in.items.len, aad.items.ptr, aad.items.len, got.ptr);
            if (rc == brick.rejected and !sealing) return none(vm);
            if (rc != brick.ok) return unexpected(vm, row, rc);
            const out = try list(vm, got);
            return if (sealing) out else some(vm, out);
        },
        .@"X25519.public", .@"Ed25519.public" => {
            try size(vm, row, if (which == .@"X25519.public") "a secret" else "a seed", 32, a[0].list.len);
            const secret = try Bytes.of(vm, a[0].list);
            defer secret.free(vm);
            var public: [32]u8 = undefined;
            const rc = if (which == .@"X25519.public")
                brick.mo_crypto_x25519_public(secret.items.ptr, 32, &public)
            else
                brick.mo_crypto_ed25519_public(secret.items.ptr, 32, &public);
            if (rc != brick.ok) return unexpected(vm, row, rc);
            return list(vm, &public);
        },
        .@"X25519.shared" => {
            try size(vm, row, "a secret", 32, a[0].list.len);
            try size(vm, row, "a public key", 32, a[1].list.len);
            const secret = try Bytes.of(vm, a[0].list);
            defer secret.free(vm);
            const public = try Bytes.of(vm, a[1].list);
            defer public.free(vm);
            var shared: [32]u8 = undefined;
            const rc = brick.mo_crypto_x25519_shared(secret.items.ptr, 32, public.items.ptr, 32, &shared);
            if (rc == brick.rejected) return none(vm);
            if (rc != brick.ok) return unexpected(vm, row, rc);
            return some(vm, try list(vm, &shared));
        },
        .@"Ed25519.sign" => {
            try size(vm, row, "a seed", 32, a[0].list.len);
            const seed = try Bytes.of(vm, a[0].list);
            defer seed.free(vm);
            const msg = try Bytes.of(vm, a[1].list);
            defer msg.free(vm);
            var sig: [64]u8 = undefined;
            const rc = brick.mo_crypto_ed25519_sign(seed.items.ptr, 32, msg.items.ptr, msg.items.len, &sig);
            if (rc != brick.ok) return unexpected(vm, row, rc);
            return list(vm, &sig);
        },
        .@"Ed25519.verify?" => {
            try size(vm, row, "a public key", 32, a[0].list.len);
            try size(vm, row, "a signature", brick.signature_size, a[2].list.len);
            const public = try Bytes.of(vm, a[0].list);
            defer public.free(vm);
            const msg = try Bytes.of(vm, a[1].list);
            defer msg.free(vm);
            const sig = try Bytes.of(vm, a[2].list);
            defer sig.free(vm);
            const rc = brick.mo_crypto_ed25519_verify(public.items.ptr, 32, msg.items.ptr, msg.items.len, sig.items.ptr, 64);
            if (rc != brick.ok and rc != brick.rejected) return unexpected(vm, row, rc);
            return .{ .bool = rc == brick.ok };
        },
        .@"Password.hash" => {
            try size(vm, row, "a salt", brick.salt_size, a[1].list.len);
            const salt = try Bytes.of(vm, a[1].list);
            defer salt.free(vm);
            const text = try vm_mod.rawAlloc(vm.heap, u8, brick.phc_size);
            const rc = brick.mo_crypto_argon2id_hash(a[0].string.ptr, a[0].string.len, salt.items.ptr, salt.items.len, text[0..brick.phc_size]);
            if (rc != brick.ok) return unexpected(vm, row, rc);
            return .{ .string = text };
        },
        .@"Password.verify?" => {
            const rc = brick.mo_crypto_argon2id_verify(a[0].string.ptr, a[0].string.len, a[1].string.ptr, a[1].string.len);
            if (rc != brick.ok and rc != brick.rejected) return unexpected(vm, row, rc);
            return .{ .bool = rc == brick.ok };
        },
        .@"Random.bytes" => {
            const n = std.math.cast(usize, a[1].int) orelse return crash(vm, row, "Random.bytes cannot give {d} bytes", .{a[1].int});
            if (n > 1 << 30) return crash(vm, row, "Random.bytes gives at most 1 GiB at once, not {d} bytes", .{n});
            const bytes = try vm.gpa.alloc(u8, n);
            defer vm.gpa.free(bytes);
            const h = a[0].cap.handle;
            if (h == 0) {
                const rc = brick.mo_crypto_random(bytes.ptr, n);
                if (rc != brick.ok) return crash(vm, row, "the OS gave no random bytes", .{});
            } else {
                const sim = vm.sim orelse return crash(vm, row, "Random.fixture() draws only in a test", .{});
                const at = &sim.randoms.items[h - 1];
                brick.mo_crypto_fixture_bytes(sim.seed, at.*, bytes.ptr, n);
                at.* += n;
            }
            return list(vm, bytes);
        },
        .@"Random.fixture" => {
            const sim = vm.sim orelse return crash(vm, row, "Random.fixture() runs only in a test", .{});
            try sim.randoms.append(sim.gpa, 0);
            return .{ .cap = .{ .kind = .random, .handle = @intCast(sim.randoms.items.len) } };
        },
    }
}
