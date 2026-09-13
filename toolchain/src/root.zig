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
pub const check = @import("check.zig");
pub const caps = @import("caps.zig");
pub const bytecode = @import("bytecode.zig");
pub const vm = @import("vm.zig");
pub const contracts = @import("contracts.zig");
pub const runner = @import("runner.zig");
pub const diag = @import("diag.zig");
pub const verified = @import("verified.zig");
pub const pipeline = @import("pipeline.zig");
pub const corpus = @import("corpus.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
