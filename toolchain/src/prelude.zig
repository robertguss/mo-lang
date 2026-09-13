//! The prelude: every stdlib type, variant, function, and operator a Mo module may
//! use without declaring it, as data. `toolchain/PRELUDE.md` lists the same rows in
//! tables; nothing outside them exists. The checker instantiates each signature
//! from its type strings at the call.
//!
//! Type strings are a small language of their own:
//!   UInt32, String, List(T), Result(T, E), (A, B)   as in Mo source
//!   fn(A, T) A                                      an anonymous-function argument
//!   T U A E                                         type variables, fresh per call
//!   N                                               the receiver's own integer type
//!   P                                               the process a handle or message belongs to
//!   Message(P)                                      one of P's `message` lines
//!   Reply                                           the reply type of the message passed
//!   none                                            no value (a statement-only call)
const std = @import("std");

/// `grammar` rows are named by spec/grammar.md or design-v0; `corpus_only` rows exist
/// because a corpus file needs them and are listed in examples/GAPS.md.
pub const Origin = enum { grammar, corpus_only };

pub const TypeKind = enum { int, float, bool, string, time, duration, list, option, result, handle, capability, error_enum };

pub const Type = struct {
    name: []const u8,
    /// Number of type arguments: List(T) has 1, Result(T, E) has 2.
    arity: u8 = 0,
    kind: TypeKind,
    origin: Origin = .grammar,
};

pub const types = [_]Type{
    .{ .name = "Int8", .kind = .int },
    .{ .name = "Int16", .kind = .int },
    .{ .name = "Int32", .kind = .int },
    .{ .name = "Int64", .kind = .int },
    .{ .name = "UInt8", .kind = .int },
    .{ .name = "UInt16", .kind = .int },
    .{ .name = "UInt32", .kind = .int },
    .{ .name = "UInt64", .kind = .int },
    .{ .name = "Float32", .kind = .float },
    .{ .name = "Float64", .kind = .float },
    .{ .name = "Bool", .kind = .bool },
    .{ .name = "String", .kind = .string },
    .{ .name = "Time", .kind = .time },
    .{ .name = "Duration", .kind = .duration },
    .{ .name = "List", .arity = 1, .kind = .list },
    .{ .name = "Option", .arity = 1, .kind = .option },
    .{ .name = "Result", .arity = 2, .kind = .result },
    .{ .name = "Handle", .arity = 1, .kind = .handle },
    .{ .name = "Clock", .kind = .capability },
    .{ .name = "Fs", .kind = .capability },
    .{ .name = "Events", .kind = .capability },
    .{ .name = "Ledger", .kind = .capability },
    .{ .name = "FsError", .kind = .error_enum },
    .{ .name = "AskError", .kind = .error_enum },
};

pub const Field = struct { name: []const u8, type: []const u8 };

pub const Variant = struct {
    owner: []const u8,
    name: []const u8,
    /// Some, Ok, and Error take one positional value; its field name is never written.
    fields: []const Field = &.{},
    origin: Origin = .grammar,
};

pub const variants = [_]Variant{
    .{ .owner = "Option", .name = "Some", .fields = &.{.{ .name = "value", .type = "T" }} },
    .{ .owner = "Option", .name = "None" },
    .{ .owner = "Result", .name = "Ok", .fields = &.{.{ .name = "value", .type = "T" }} },
    .{ .owner = "Result", .name = "Error", .fields = &.{.{ .name = "error", .type = "E" }} },
    .{ .owner = "FsError", .name = "Missing", .fields = &.{.{ .name = "path", .type = "String" }}, .origin = .corpus_only },
    .{ .owner = "FsError", .name = "Timeout", .origin = .corpus_only },
    .{ .owner = "AskError", .name = "Timeout" },
    .{ .owner = "AskError", .name = "Down" },
};

/// Where a call is allowed. A capability's `fixture` exists only in tests; `Type.all`
/// and `flows` only inside a `never`.
pub const Only = enum { anywhere, tests, never };

pub const Fn = struct {
    /// The receiver: a type string; `Int` for any integer type; `Process` for a process
    /// name; `Type` for any declared type name; empty for a free function.
    recv: []const u8,
    /// Called on the type itself (`Clock.fixture()`, `Tally.start()`), not on a value.
    on_type: bool = false,
    name: []const u8,
    /// Positional parameters after the receiver.
    params: []const []const u8 = &.{},
    /// Named parameters, all required. `within:` is not listed here; `can_wait` says it.
    named: []const Field = &.{},
    ret: []const u8,
    /// The call can wait, so it takes `within: Duration` (chapter 2, deadlines).
    can_wait: bool = false,
    only: Only = .anywhere,
    origin: Origin = .grammar,
};

pub const fns = [_]Fn{
    // Lists (grammar: stdlib names the corpus may assume)
    .{ .recv = "List(T)", .name = "size", .ret = "UInt64" },
    .{ .recv = "List(T)", .name = "push", .params = &.{"T"}, .ret = "List(T)" },
    .{ .recv = "List(T)", .name = "map", .params = &.{"fn(T) U"}, .ret = "List(U)" },
    .{ .recv = "List(T)", .name = "filter", .params = &.{"fn(T) Bool"}, .ret = "List(T)" },
    .{ .recv = "List(T)", .name = "reduce", .params = &.{ "A", "fn(A, T) A" }, .ret = "A" },
    .{ .recv = "List(T)", .name = "contains?", .params = &.{"T"}, .ret = "Bool" },
    .{ .recv = "List(T)", .name = "first", .ret = "Option(T)" },
    .{ .recv = "List(T)", .name = "last", .ret = "Option(T)" },
    // Strings
    .{ .recv = "String", .name = "size", .ret = "UInt64" },
    .{ .recv = "String", .name = "bytes", .ret = "List(UInt8)" },
    .{ .recv = "String", .name = "starts_with?", .params = &.{"String"}, .ret = "Bool" },
    // Integers: the named edge behaviours
    .{ .recv = "Int", .name = "checked_add", .params = &.{"N"}, .ret = "Option(N)" },
    .{ .recv = "Int", .name = "checked_sub", .params = &.{"N"}, .ret = "Option(N)" },
    .{ .recv = "Int", .name = "checked_mul", .params = &.{"N"}, .ret = "Option(N)" },
    .{ .recv = "Int", .name = "saturating_add", .params = &.{"N"}, .ret = "N" },
    .{ .recv = "Int", .name = "saturating_sub", .params = &.{"N"}, .ret = "N" },
    .{ .recv = "Int", .name = "saturating_mul", .params = &.{"N"}, .ret = "N" },
    .{ .recv = "Int", .name = "wrapping_add", .params = &.{"N"}, .ret = "N" },
    .{ .recv = "Int", .name = "wrapping_sub", .params = &.{"N"}, .ret = "N" },
    .{ .recv = "Int", .name = "wrapping_mul", .params = &.{"N"}, .ret = "N" },
    // Durations from integers (grammar: Time)
    .{ .recv = "Int", .name = "ms", .ret = "Duration" },
    .{ .recv = "Int", .name = "minute", .ret = "Duration" },
    .{ .recv = "Int", .name = "days", .ret = "Duration" },
    // Time
    .{ .recv = "Time", .on_type = true, .name = "fixture", .ret = "Time", .only = .tests },
    // Capabilities
    .{ .recv = "Clock", .name = "now", .ret = "Time" },
    .{ .recv = "Clock", .on_type = true, .name = "fixture", .ret = "Clock", .only = .tests },
    .{ .recv = "Fs", .name = "read", .params = &.{"String"}, .ret = "Result(String, FsError)", .can_wait = true },
    .{ .recv = "Fs", .name = "scoped", .params = &.{"String"}, .ret = "Fs" },
    .{ .recv = "Fs", .name = "read_only", .ret = "Fs" },
    .{ .recv = "Fs", .on_type = true, .name = "fixture", .ret = "Fs", .only = .tests },
    .{ .recv = "Fs", .on_type = true, .name = "fixture", .named = &.{.{ .name = "delay", .type = "Duration" }}, .ret = "Fs", .only = .tests },
    .{ .recv = "Events", .name = "emit", .params = &.{"T"}, .ret = "none" },
    .{ .recv = "Events", .on_type = true, .name = "fixture", .ret = "Events", .only = .tests },
    .{ .recv = "Ledger", .on_type = true, .name = "fixture", .ret = "Ledger", .only = .tests },
    // Processes (grammar: Processes)
    .{ .recv = "Process", .on_type = true, .name = "start", .ret = "Handle(P)" },
    .{ .recv = "Handle(P)", .name = "send", .params = &.{"Message(P)"}, .ret = "none" },
    .{ .recv = "Handle(P)", .name = "ask", .params = &.{"Message(P)"}, .ret = "Result(Reply, AskError)", .can_wait = true },
    // Inside `never` only
    .{ .recv = "Type", .on_type = true, .name = "all", .ret = "List(T)", .only = .never },
    .{ .recv = "", .name = "flows", .params = &.{"T"}, .named = &.{.{ .name = "into", .type = "Capability" }}, .ret = "Bool", .only = .never },
};

pub const Operator = struct { lhs: []const u8, op: []const u8, rhs: []const u8, result: []const u8 };

/// Operators on stdlib types beyond numbers, Bool, and structural `==`.
pub const operators = [_]Operator{
    .{ .lhs = "Time", .op = "-", .rhs = "Time", .result = "Duration" },
    .{ .lhs = "Time", .op = "+", .rhs = "Duration", .result = "Time" },
    .{ .lhs = "Time", .op = "-", .rhs = "Duration", .result = "Time" },
    .{ .lhs = "Duration", .op = "+", .rhs = "Duration", .result = "Duration" },
    .{ .lhs = "Duration", .op = "-", .rhs = "Duration", .result = "Duration" },
};

pub fn findType(name: []const u8) ?Type {
    for (types) |t| if (std.mem.eql(u8, t.name, name)) return t;
    return null;
}

/// Words a type string may use that are not type names.
const type_string_words = [_][]const u8{ "T", "U", "A", "E", "N", "P", "Message", "Reply", "none", "fn", "Capability" };

test "every name in a prelude type string is a prelude type or a type-string word" {
    var strings: std.ArrayList([]const u8) = .empty;
    defer strings.deinit(std.testing.allocator);
    const gpa = std.testing.allocator;
    for (fns) |f| {
        if (f.recv.len > 0 and !std.mem.eql(u8, f.recv, "Int") and !std.mem.eql(u8, f.recv, "Process") and !std.mem.eql(u8, f.recv, "Type")) try strings.append(gpa, f.recv);
        for (f.params) |p| try strings.append(gpa, p);
        for (f.named) |n| try strings.append(gpa, n.type);
        try strings.append(gpa, f.ret);
    }
    for (variants) |v| for (v.fields) |fld| try strings.append(gpa, fld.type);
    for (operators) |o| {
        try strings.append(gpa, o.lhs);
        try strings.append(gpa, o.rhs);
        try strings.append(gpa, o.result);
    }
    for (strings.items) |s| {
        var i: usize = 0;
        while (i < s.len) {
            if (!std.ascii.isAlphabetic(s[i])) {
                i += 1;
                continue;
            }
            const start = i;
            while (i < s.len and (std.ascii.isAlphanumeric(s[i]) or s[i] == '?' or s[i] == '_')) i += 1;
            const word = s[start..i];
            const known = findType(word) != null or for (type_string_words) |w| {
                if (std.mem.eql(u8, w, word)) break true;
            } else false;
            if (!known) std.debug.print("prelude: unknown name {s} in \"{s}\"\n", .{ word, s });
            try std.testing.expect(known);
        }
    }
}

test "every variant belongs to a prelude type" {
    for (variants) |v| try std.testing.expect(findType(v.owner) != null);
}
