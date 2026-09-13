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
pub const bytecode = @import("bytecode.zig");
pub const vm = @import("vm.zig");
pub const stdlib = @import("stdlib.zig");
pub const json = @import("json.zig");
pub const region = @import("region.zig");
pub const memo = @import("memo.zig");
pub const sim = @import("sim.zig");
pub const server = @import("server.zig");
pub const net = @import("net.zig");
pub const contracts = @import("contracts.zig");
pub const runner = @import("runner.zig");
pub const diag = @import("diag.zig");
pub const verified = @import("verified.zig");
pub const ids = @import("ids.zig");
pub const pipeline = @import("pipeline.zig");
pub const program = @import("program.zig");
pub const corpus = @import("corpus.zig");
pub const fmt = @import("fmt.zig");
pub const fix = @import("fix.zig");
pub const diff = @import("diff.zig");
pub const errors = @import("errors.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
