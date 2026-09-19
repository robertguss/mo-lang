//! The Mo toolchain, stage by stage. Build order follows design-v0/07-toolchain.md:
//! an interpreter first, which is also the reference semantics. The milestone
//! (design-v0/08-milestone.md) is: lex, parse, typecheck, and run the refund
//! module with its tests, contracts at tier 2, `rejects` tests tripping their
//! `requires`, the `verified:` line computed.
//!
//! Every stage is a stub until it is built. A stub returns `error.NotImplemented`
//! so the benchmark harness and the corpus test light up stage by stage.
pub const token = @import("token.zig");
pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const prelude = @import("prelude.zig");
pub const types = @import("types.zig");
pub const check = @import("check.zig");
pub const caps = @import("caps.zig");
pub const loops = @import("loops.zig");
pub const moves = @import("moves.zig");
pub const bytecode = @import("bytecode.zig");
pub const emit_c = @import("emit_c.zig");
pub const cbuild = @import("cbuild.zig");
pub const vm = @import("vm.zig");
pub const stdlib = @import("stdlib.zig");
pub const json = @import("json.zig");
pub const region = @import("region.zig");
pub const sim = @import("sim.zig");
pub const server = @import("server.zig");
pub const net = @import("net.zig");
pub const http = @import("http.zig");
pub const turns = @import("turns.zig");
pub const blocking = @import("blocking.zig");
pub const events = @import("events.zig");
pub const surface = @import("surface.zig");
pub const fiber = @import("fiber.zig");
pub const poller = @import("poller.zig");
pub const contracts = @import("contracts.zig");
pub const runner = @import("runner.zig");
pub const diag = @import("diag.zig");
pub const verified = @import("verified.zig");
pub const ids = @import("ids.zig");
pub const pipeline = @import("pipeline.zig");
pub const recipe = @import("recipe.zig");
pub const mutation = @import("mutation.zig");
pub const program = @import("program.zig");
pub const corpus = @import("corpus.zig");
pub const fmt = @import("fmt.zig");
pub const fix = @import("fix.zig");
pub const diff = @import("diff.zig");
pub const errors = @import("errors.zig");
/// Step 40's controls: a scope that holds against links, `Fs.kind_of`, and `Fs.replace`.
pub const fs_scope = @import("fs_scope.zig");
/// The crypto brick (step 35): both runtimes call its exports.
pub const crypto_brick = @import("bricks/crypto.zig");
/// The TLS brick (step 36): a TLS 1.3 server as an engine over bytes, driven by both runtimes.
pub const tls_brick = @import("bricks/tls.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
