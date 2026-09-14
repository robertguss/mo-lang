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

/// `grammar` rows are named by spec/grammar.md or design-v0; `stdlib` rows by
/// design-v0/09-stdlib.md; `corpus_only` rows exist because a corpus file needs them and
/// are listed in examples/GAPS.md.
pub const Origin = enum { grammar, stdlib, corpus_only };

/// `error_enum` and `enum_` are both enums whose variants are rows below; an error enum
/// is what a capability call fails with.
pub const TypeKind = enum { int, float, bool, string, time, duration, deadline, list, option, result, map, set, handle, capability, error_enum, enum_ };

pub const Type = struct {
    name: []const u8,
    /// Number of type arguments: List(T) has 1, Result(T, E) has 2.
    arity: u8 = 0,
    kind: TypeKind,
    origin: Origin = .grammar,
    /// A module's own type of this name hides the prelude's from the module's code, as its own
    /// `Request` does; the prelude's rows still mean the prelude's (step 23: `Event` is a name
    /// programs already give their own types).
    hideable: bool = false,
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
    .{ .name = "Deadline", .kind = .deadline, .origin = .stdlib },
    .{ .name = "List", .arity = 1, .kind = .list },
    .{ .name = "Option", .arity = 1, .kind = .option },
    .{ .name = "Result", .arity = 2, .kind = .result },
    .{ .name = "Map", .arity = 2, .kind = .map, .origin = .stdlib },
    .{ .name = "Set", .arity = 1, .kind = .set, .origin = .stdlib },
    .{ .name = "Handle", .arity = 1, .kind = .handle },
    .{ .name = "Clock", .kind = .capability },
    .{ .name = "Fs", .kind = .capability },
    .{ .name = "Events", .kind = .capability },
    .{ .name = "Ledger", .kind = .capability },
    .{ .name = "Platform", .kind = .capability },
    .{ .name = "Env", .kind = .capability },
    .{ .name = "Out", .kind = .capability },
    .{ .name = "Net", .kind = .capability, .origin = .stdlib },
    .{ .name = "Listener", .kind = .capability, .origin = .stdlib },
    .{ .name = "Conn", .kind = .capability, .origin = .stdlib },
    .{ .name = "Http", .kind = .capability, .origin = .stdlib },
    .{ .name = "HttpListener", .kind = .capability, .origin = .stdlib },
    .{ .name = "Exchange", .kind = .capability, .origin = .stdlib },
    .{ .name = "FsError", .kind = .error_enum },
    .{ .name = "AskError", .kind = .error_enum },
    .{ .name = "LedgerError", .kind = .error_enum, .origin = .corpus_only },
    .{ .name = "Json", .kind = .enum_, .origin = .stdlib },
    .{ .name = "JsonError", .kind = .error_enum, .origin = .stdlib },
    .{ .name = "NetError", .kind = .error_enum, .origin = .stdlib },
    .{ .name = "HttpError", .kind = .error_enum, .origin = .stdlib },
    // The runtime surface (step 23).
    .{ .name = "Runtime", .kind = .capability, .origin = .stdlib },
    .{ .name = "RuntimeError", .kind = .error_enum, .origin = .stdlib, .hideable = true },
    .{ .name = "Event", .kind = .enum_, .origin = .stdlib, .hideable = true },
    // What `Fs.list_kinds` tells apart (step 28).
    .{ .name = "EntryKind", .kind = .enum_, .origin = .stdlib, .hideable = true },
};

/// Stand-ins for types chapter 4's refund module takes from `Payments.Ledger` and the
/// event log, which are not written yet. Each is corpus-only. A module that declares a
/// name itself (contracts/flows.mo's `CardNumber`) uses its own declaration.
pub const Alias = struct { name: []const u8, base: []const u8, origin: Origin = .corpus_only };

pub const aliases = [_]Alias{
    .{ .name = "ChargeId", .base = "String" },
    .{ .name = "Money", .base = "UInt64" },
    .{ .name = "CardNumber", .base = "String" },
};

/// A struct the prelude declares: a stand-in (corpus-only), or a stdlib struct (`Request`,
/// `Response`). A module's own declaration of a stand-in's name is the one every use of the
/// name means; a module's own `Request` hides the stdlib's from its code, and the stdlib's
/// rows still mean the stdlib's.
pub const Struct = struct { name: []const u8, fields: []const Field, origin: Origin = .corpus_only };

pub const structs = [_]Struct{
    .{ .name = "Charge", .fields = &.{
        .{ .name = "id", .type = "ChargeId" },
        .{ .name = "captured_at", .type = "Time" },
        .{ .name = "captured_amount", .type = "Money" },
        .{ .name = "refunded", .type = "Bool" },
    } },
    .{ .name = "RefundRequest", .fields = &.{ .{ .name = "id", .type = "ChargeId" }, .{ .name = "amount", .type = "Money" } } },
    // The event payloads carry the refund module's own types, so their fields are type
    // variables, bound by the one module that builds them.
    .{ .name = "RefundCompleted", .fields = &.{.{ .name = "refund", .type = "T" }} },
    .{ .name = "RefundFailed", .fields = &.{ .{ .name = "request", .type = "RefundRequest" }, .{ .name = "reason", .type = "E" } } },
    // HTTP (step 16): a field marked optional may be left out when the struct is built, and
    // is then empty.
    .{ .name = "Request", .origin = .stdlib, .fields = &.{
        .{ .name = "method", .type = "String" },
        .{ .name = "path", .type = "String" },
        .{ .name = "query", .type = "Map(String, String)", .optional = true },
        .{ .name = "headers", .type = "Map(String, String)", .optional = true },
        .{ .name = "body", .type = "String", .optional = true },
    } },
    .{ .name = "Response", .origin = .stdlib, .fields = &.{
        .{ .name = "status", .type = "UInt16" },
        .{ .name = "headers", .type = "Map(String, String)", .optional = true },
        .{ .name = "body", .type = "String" },
    } },
    // The runtime surface (step 23): what `Runtime.processes`, `sources`, and `memory` give.
    .{ .name = "ProcessInfo", .origin = .stdlib, .fields = &.{
        .{ .name = "id", .type = "UInt64" },
        .{ .name = "name", .type = "String" },
        .{ .name = "alive", .type = "Bool" },
        .{ .name = "mailbox", .type = "UInt64" },
        .{ .name = "bound", .type = "UInt64" },
        .{ .name = "waiting_in", .type = "Option(String)" },
        .{ .name = "restarts", .type = "UInt64" },
        .{ .name = "region_bytes", .type = "UInt64" },
        .{ .name = "paused", .type = "Bool" },
    } },
    .{ .name = "SourceInfo", .origin = .stdlib, .fields = &.{
        .{ .name = "kind", .type = "String" },
        .{ .name = "target", .type = "UInt64" },
        .{ .name = "name", .type = "String" },
        .{ .name = "in_flight", .type = "UInt64" },
        .{ .name = "paused", .type = "Bool" },
    } },
    // A name `Fs.list_kinds` gives, with whether it is a file or a folder (step 28).
    .{ .name = "Entry", .origin = .stdlib, .fields = &.{
        .{ .name = "name", .type = "String" },
        .{ .name = "kind", .type = "EntryKind" },
    } },
    .{ .name = "MemoryInfo", .origin = .stdlib, .fields = &.{
        .{ .name = "resident_bytes", .type = "UInt64" },
        .{ .name = "region_bytes", .type = "UInt64" },
        .{ .name = "region_resident_bytes", .type = "UInt64" },
        .{ .name = "packed_bytes", .type = "UInt64" },
        .{ .name = "event_bytes", .type = "UInt64" },
        .{ .name = "largest", .type = "List(ProcessInfo)" },
    } },
};

/// Named values: a name that is neither a binding nor a function.
pub const Value = struct { name: []const u8, type: []const u8, only: Only = .anywhere, origin: Origin = .grammar };

pub const values = [_]Value{
    .{ .name = "t0", .type = "Time", .only = .tests, .origin = .corpus_only },
};

pub fn findValue(name: []const u8) ?Value {
    for (values) |v| if (std.mem.eql(u8, v.name, name)) return v;
    return null;
}

/// `optional`: a stdlib struct's field that may be left out when the struct is built.
pub const Field = struct { name: []const u8, type: []const u8, optional: bool = false };

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
    .{ .owner = "FsError", .name = "NotText", .origin = .stdlib },
    .{ .owner = "EntryKind", .name = "File", .origin = .stdlib },
    .{ .owner = "EntryKind", .name = "Folder", .origin = .stdlib },
    .{ .owner = "AskError", .name = "Timeout" },
    .{ .owner = "AskError", .name = "Down" },
    .{ .owner = "LedgerError", .name = "Timeout", .origin = .corpus_only },
    .{ .owner = "Json", .name = "Object", .fields = &.{.{ .name = "fields", .type = "Map(String, Json)" }}, .origin = .stdlib },
    .{ .owner = "Json", .name = "Array", .fields = &.{.{ .name = "items", .type = "List(Json)" }}, .origin = .stdlib },
    .{ .owner = "Json", .name = "String", .fields = &.{.{ .name = "text", .type = "String" }}, .origin = .stdlib },
    .{ .owner = "Json", .name = "Number", .fields = &.{.{ .name = "value", .type = "Float64" }}, .origin = .stdlib },
    .{ .owner = "Json", .name = "Bool", .fields = &.{.{ .name = "value", .type = "Bool" }}, .origin = .stdlib },
    .{ .owner = "Json", .name = "Null", .origin = .stdlib },
    .{ .owner = "JsonError", .name = "Syntax", .fields = &.{.{ .name = "at", .type = "UInt64" }}, .origin = .stdlib },
    .{ .owner = "NetError", .name = "Timeout", .origin = .stdlib },
    .{ .owner = "NetError", .name = "Refused", .origin = .stdlib },
    .{ .owner = "NetError", .name = "Closed", .origin = .stdlib },
    .{ .owner = "NetError", .name = "LineTooLong", .origin = .stdlib },
    .{ .owner = "NetError", .name = "Busy", .origin = .stdlib },
    .{ .owner = "HttpError", .name = "Timeout", .origin = .stdlib },
    .{ .owner = "HttpError", .name = "Refused", .origin = .stdlib },
    .{ .owner = "HttpError", .name = "Closed", .origin = .stdlib },
    .{ .owner = "HttpError", .name = "Busy", .origin = .stdlib },
    .{ .owner = "HttpError", .name = "Malformed", .origin = .stdlib },
    .{ .owner = "HttpError", .name = "TooLarge", .origin = .stdlib },
    .{ .owner = "HttpError", .name = "Unsupported", .origin = .stdlib },
    .{ .owner = "RuntimeError", .name = "NoProcess", .origin = .stdlib },
    .{ .owner = "RuntimeError", .name = "Unparsed", .fields = &.{.{ .name = "why", .type = "String" }}, .origin = .stdlib },
    .{ .owner = "RuntimeError", .name = "ReadOnly", .origin = .stdlib },
    .{ .owner = "RuntimeError", .name = "MailboxFull", .origin = .stdlib },
    .{ .owner = "RuntimeError", .name = "Timeout", .origin = .stdlib },
    .{ .owner = "Event", .name = "Updated", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "pid", .type = "UInt64" }, .{ .name = "name", .type = "String" }, .{ .name = "taking", .type = "String" }, .{ .name = "took_us", .type = "UInt64" }, .{ .name = "waited_us", .type = "UInt64" }, .{ .name = "longest", .type = "String" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "Started", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "pid", .type = "UInt64" }, .{ .name = "name", .type = "String" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "Ended", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "pid", .type = "UInt64" }, .{ .name = "name", .type = "String" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "Restarted", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "pid", .type = "UInt64" }, .{ .name = "name", .type = "String" }, .{ .name = "restarts", .type = "UInt64" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "Crashed", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "pid", .type = "UInt64" }, .{ .name = "name", .type = "String" }, .{ .name = "seed", .type = "UInt64" }, .{ .name = "clause", .type = "String" }, .{ .name = "taking", .type = "String" }, .{ .name = "snapshot", .type = "String" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "Overflowed", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "sender", .type = "Option(UInt64)" }, .{ .name = "sender_name", .type = "String" }, .{ .name = "target", .type = "UInt64" }, .{ .name = "name", .type = "String" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "TimedOut", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "pid", .type = "Option(UInt64)" }, .{ .name = "name", .type = "String" }, .{ .name = "call", .type = "String" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "SourcePaused", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "source", .type = "String" }, .{ .name = "target", .type = "UInt64" }, .{ .name = "name", .type = "String" }, .{ .name = "in_flight", .type = "UInt64" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "SourceResumed", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "source", .type = "String" }, .{ .name = "target", .type = "UInt64" }, .{ .name = "name", .type = "String" }, .{ .name = "in_flight", .type = "UInt64" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "Sent", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "pid", .type = "UInt64" }, .{ .name = "name", .type = "String" }, .{ .name = "taking", .type = "String" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "Paused", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "pid", .type = "UInt64" }, .{ .name = "name", .type = "String" } }, .origin = .stdlib },
    .{ .owner = "Event", .name = "Resumed", .fields = &.{ .{ .name = "at", .type = "Time" }, .{ .name = "pid", .type = "UInt64" }, .{ .name = "name", .type = "String" } }, .origin = .stdlib },
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
    /// The type variable (`T`, `K`) the call orders: it must have the natural order of
    /// design-v0/09 (numbers, strings, times, durations, and tuples of those).
    ordered: []const u8 = "",
    /// The type variable that must be an integer type.
    integer: []const u8 = "",
};

pub const fns = [_]Fn{
    // Lists (grammar: stdlib names the corpus may assume)
    .{ .recv = "List(T)", .name = "size", .ret = "UInt64" },
    .{ .recv = "List(T)", .name = "push", .params = &.{"T"}, .ret = "List(T)" },
    .{ .recv = "List(T)", .name = "map", .params = &.{"fn(T) U"}, .ret = "List(U)" },
    .{ .recv = "Option(T)", .name = "map", .params = &.{"fn(T) U"}, .ret = "Option(U)", .origin = .stdlib },
    .{ .recv = "String", .on_type = true, .name = "grouped", .params = &.{"T"}, .ret = "String", .integer = "T", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "filter", .params = &.{"fn(T) Bool"}, .ret = "List(T)" },
    .{ .recv = "List(T)", .name = "reduce", .params = &.{ "A", "fn(A, T) A" }, .ret = "A" },
    .{ .recv = "List(T)", .name = "contains?", .params = &.{"T"}, .ret = "Bool" },
    .{ .recv = "List(T)", .name = "first", .ret = "Option(T)" },
    .{ .recv = "List(T)", .name = "last", .ret = "Option(T)" },
    .{ .recv = "List(T)", .name = "get", .params = &.{"UInt64"}, .ret = "Option(T)", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "slice", .params = &.{ "UInt64", "UInt64" }, .ret = "List(T)", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "take", .params = &.{"UInt64"}, .ret = "List(T)", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "drop", .params = &.{"UInt64"}, .ret = "List(T)", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "concat", .params = &.{"List(T)"}, .ret = "List(T)", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "reverse", .ret = "List(T)", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "flat_map", .params = &.{"fn(T) List(U)"}, .ret = "List(U)", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "any?", .params = &.{"fn(T) Bool"}, .ret = "Bool", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "all?", .params = &.{"fn(T) Bool"}, .ret = "Bool", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "find", .params = &.{"fn(T) Bool"}, .ret = "Option(T)", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "count", .params = &.{"fn(T) Bool"}, .ret = "UInt64", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "sort", .ret = "List(T)", .ordered = "T", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "sort_by", .params = &.{"fn(T) K"}, .ret = "List(T)", .ordered = "K", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "sort_by_desc", .params = &.{"fn(T) K"}, .ret = "List(T)", .ordered = "K", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "min", .ret = "Option(T)", .ordered = "T", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "max", .ret = "Option(T)", .ordered = "T", .origin = .stdlib },
    // Two values of one ordered type: free functions, called by bare name.
    .{ .recv = "", .name = "min_of", .params = &.{ "T", "T" }, .ret = "T", .ordered = "T", .origin = .stdlib },
    .{ .recv = "", .name = "max_of", .params = &.{ "T", "T" }, .ret = "T", .ordered = "T", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "sum", .ret = "T", .integer = "T", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "zip", .params = &.{"List(U)"}, .ret = "List((T, U))", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "enumerate", .ret = "List((UInt64, T))", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "unique", .ret = "List(T)", .origin = .stdlib },
    .{ .recv = "List(T)", .name = "group_by", .params = &.{"fn(T) K"}, .ret = "Map(K, List(T))", .origin = .stdlib },
    // Maps and sets: values whose keys keep the order they were first added
    .{ .recv = "Map", .on_type = true, .name = "new", .ret = "Map(K, V)", .origin = .stdlib },
    .{ .recv = "Map(K, V)", .name = "size", .ret = "UInt64", .origin = .stdlib },
    .{ .recv = "Map(K, V)", .name = "get", .params = &.{"K"}, .ret = "Option(V)", .origin = .stdlib },
    .{ .recv = "Map(K, V)", .name = "has?", .params = &.{"K"}, .ret = "Bool", .origin = .stdlib },
    .{ .recv = "Map(K, V)", .name = "set", .params = &.{ "K", "V" }, .ret = "Map(K, V)", .origin = .stdlib },
    .{ .recv = "Map(K, V)", .name = "update", .params = &.{ "K", "V", "fn(V) V" }, .ret = "Map(K, V)", .origin = .stdlib },
    .{ .recv = "Map(K, V)", .name = "remove", .params = &.{"K"}, .ret = "Map(K, V)", .origin = .stdlib },
    .{ .recv = "Map(K, V)", .name = "keys", .ret = "List(K)", .origin = .stdlib },
    .{ .recv = "Map(K, V)", .name = "values", .ret = "List(V)", .origin = .stdlib },
    .{ .recv = "Map(K, V)", .name = "entries", .ret = "List((K, V))", .origin = .stdlib },
    .{ .recv = "Set", .on_type = true, .name = "new", .ret = "Set(T)", .origin = .stdlib },
    .{ .recv = "Set(T)", .name = "size", .ret = "UInt64", .origin = .stdlib },
    .{ .recv = "Set(T)", .name = "add", .params = &.{"T"}, .ret = "Set(T)", .origin = .stdlib },
    .{ .recv = "Set(T)", .name = "remove", .params = &.{"T"}, .ret = "Set(T)", .origin = .stdlib },
    .{ .recv = "Set(T)", .name = "has?", .params = &.{"T"}, .ret = "Bool", .origin = .stdlib },
    .{ .recv = "Set(T)", .name = "to_list", .ret = "List(T)", .origin = .stdlib },
    // Strings
    .{ .recv = "String", .name = "size", .ret = "UInt64" },
    .{ .recv = "String", .name = "bytes", .ret = "List(UInt8)" },
    .{ .recv = "String", .name = "byte_size", .ret = "UInt64", .origin = .stdlib },
    .{ .recv = "String", .name = "starts_with?", .params = &.{"String"}, .ret = "Bool" },
    .{ .recv = "String", .on_type = true, .name = "from_bytes", .params = &.{"List(UInt8)"}, .ret = "Option(String)", .origin = .stdlib },
    .{ .recv = "String", .name = "chars", .ret = "List(String)", .origin = .stdlib },
    .{ .recv = "String", .name = "split", .params = &.{"String"}, .ret = "List(String)", .origin = .stdlib },
    .{ .recv = "String", .name = "lines", .ret = "List(String)", .origin = .stdlib },
    .{ .recv = "String", .name = "trim", .ret = "String", .origin = .stdlib },
    .{ .recv = "String", .name = "ends_with?", .params = &.{"String"}, .ret = "Bool", .origin = .stdlib },
    .{ .recv = "String", .name = "contains?", .params = &.{"String"}, .ret = "Bool", .origin = .stdlib },
    .{ .recv = "String", .name = "index_of", .params = &.{"String"}, .ret = "Option(UInt64)", .origin = .stdlib },
    .{ .recv = "String", .name = "slice", .params = &.{ "UInt64", "UInt64" }, .ret = "String", .origin = .stdlib },
    .{ .recv = "String", .name = "replace", .params = &.{ "String", "String" }, .ret = "String", .origin = .stdlib },
    .{ .recv = "String", .name = "to_upper", .ret = "String", .origin = .stdlib },
    .{ .recv = "String", .name = "to_lower", .ret = "String", .origin = .stdlib },
    .{ .recv = "String", .name = "pad_left", .params = &.{ "UInt64", "String" }, .ret = "String", .origin = .stdlib },
    .{ .recv = "String", .name = "pad_right", .params = &.{ "UInt64", "String" }, .ret = "String", .origin = .stdlib },
    .{ .recv = "String", .name = "repeat", .params = &.{"UInt64"}, .ret = "String", .origin = .stdlib },
    .{ .recv = "String", .on_type = true, .name = "join", .params = &.{ "List(String)", "String" }, .ret = "String", .origin = .stdlib },
    .{ .recv = "String", .name = "to_u64", .ret = "Option(UInt64)", .origin = .stdlib },
    .{ .recv = "String", .name = "to_i64", .ret = "Option(Int64)", .origin = .stdlib },
    .{ .recv = "String", .name = "to_f64", .ret = "Option(Float64)", .origin = .stdlib },
    // Integers: named conversions across widths; a value that does not fit is a crash
    .{ .recv = "Int", .name = "to_u8", .ret = "UInt8", .origin = .stdlib },
    .{ .recv = "Int", .name = "to_u16", .ret = "UInt16", .origin = .stdlib },
    .{ .recv = "Int", .name = "to_u32", .ret = "UInt32", .origin = .stdlib },
    .{ .recv = "Int", .name = "to_u64", .ret = "UInt64", .origin = .stdlib },
    .{ .recv = "Int", .name = "to_i64", .ret = "Int64", .origin = .stdlib },
    .{ .recv = "Int", .name = "checked_to_u8", .ret = "Option(UInt8)", .origin = .stdlib },
    .{ .recv = "Int", .name = "checked_to_u16", .ret = "Option(UInt16)", .origin = .stdlib },
    .{ .recv = "Int", .name = "checked_to_u32", .ret = "Option(UInt32)", .origin = .stdlib },
    .{ .recv = "Int", .name = "checked_to_u64", .ret = "Option(UInt64)", .origin = .stdlib },
    .{ .recv = "Int", .name = "checked_to_i64", .ret = "Option(Int64)", .origin = .stdlib },
    .{ .recv = "Int", .name = "to_f64", .ret = "Float64", .origin = .stdlib },
    // Floats
    .{ .recv = "Float64", .name = "round", .params = &.{"UInt64"}, .ret = "Float64", .origin = .stdlib },
    .{ .recv = "Float64", .name = "to_string", .params = &.{"UInt64"}, .ret = "String", .origin = .stdlib },
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
    .{ .recv = "Int", .name = "seconds", .ret = "Duration", .origin = .stdlib },
    .{ .recv = "Int", .name = "minute", .ret = "Duration" },
    .{ .recv = "Int", .name = "days", .ret = "Duration" },
    // Time
    .{ .recv = "Time", .on_type = true, .name = "fixture", .ret = "Time", .only = .tests },
    .{ .recv = "Time", .on_type = true, .name = "parse", .params = &.{"String"}, .ret = "Option(Time)", .origin = .stdlib },
    .{ .recv = "Time", .on_type = true, .name = "from_parts", .params = &.{ "UInt64", "UInt64", "UInt64", "UInt64", "UInt64", "UInt64" }, .ret = "Time", .origin = .stdlib },
    .{ .recv = "Time", .name = "to_iso8601", .ret = "String", .origin = .stdlib },
    .{ .recv = "Time", .name = "since", .params = &.{"Time"}, .ret = "Duration", .origin = .stdlib },
    .{ .recv = "Duration", .name = "ms", .ret = "Int64", .origin = .stdlib },
    .{ .recv = "Duration", .name = "seconds", .ret = "Float64", .origin = .stdlib },
    .{ .recv = "Duration", .name = "minutes", .ret = "Float64", .origin = .stdlib },
    // Capabilities
    .{ .recv = "Clock", .name = "now", .ret = "Time" },
    .{ .recv = "Clock", .on_type = true, .name = "fixture", .ret = "Clock", .only = .tests },
    .{ .recv = "Fs", .name = "read", .params = &.{"String"}, .ret = "Result(String, FsError)", .can_wait = true },
    .{ .recv = "Fs", .name = "read_lines", .params = &.{"String"}, .ret = "Result(List(String), FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "read_bytes", .params = &.{"String"}, .ret = "Result(List(UInt8), FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "fold_lines", .params = &.{ "String", "A", "fn(A, String) A" }, .ret = "Result(A, FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "size", .params = &.{"String"}, .ret = "Result(UInt64, FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "list", .ret = "Result(List(String), FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "list_kinds", .ret = "Result(List(Entry), FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "scoped", .params = &.{"String"}, .ret = "Fs" },
    .{ .recv = "Fs", .name = "read_only", .ret = "Fs" },
    .{ .recv = "Fs", .name = "write", .params = &.{ "String", "String" }, .ret = "Result(none, FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "append", .params = &.{ "String", "String" }, .ret = "Result(none, FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "remove", .params = &.{"String"}, .ret = "Result(none, FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "rename", .params = &.{ "String", "String" }, .ret = "Result(none, FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .name = "mkdir", .params = &.{"String"}, .ret = "Result(none, FsError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Fs", .on_type = true, .name = "fixture", .ret = "Fs", .only = .tests },
    .{ .recv = "Fs", .on_type = true, .name = "fixture", .named = &.{.{ .name = "delay", .type = "Duration" }}, .ret = "Fs", .only = .tests },
    .{ .recv = "Events", .name = "emit", .params = &.{"T"}, .ret = "none" },
    .{ .recv = "Events", .on_type = true, .name = "fixture", .ret = "Events", .only = .tests },
    .{ .recv = "Ledger", .on_type = true, .name = "fixture", .ret = "Ledger", .only = .tests },
    .{ .recv = "Ledger", .name = "find_charge", .params = &.{"ChargeId"}, .ret = "Result(Charge, LedgerError)", .can_wait = true, .origin = .corpus_only },
    .{ .recv = "Ledger", .name = "save_charge", .params = &.{"Charge"}, .ret = "Result(none, LedgerError)", .can_wait = true, .origin = .corpus_only },
    // The platform (Q18): `main`'s one parameter and the capabilities it holds. A part
    // without parentheses reads like a field, as `clock.now` does.
    .{ .recv = "Platform", .name = "args", .ret = "List(String)" },
    .{ .recv = "Platform", .name = "env", .ret = "Env" },
    .{ .recv = "Platform", .name = "stdout", .ret = "Out" },
    .{ .recv = "Platform", .name = "stderr", .ret = "Out" },
    .{ .recv = "Platform", .name = "fs", .ret = "Fs" },
    .{ .recv = "Platform", .name = "clock", .ret = "Clock" },
    .{ .recv = "Platform", .name = "net", .ret = "Net", .origin = .stdlib },
    .{ .recv = "Platform", .name = "http", .ret = "Http", .origin = .stdlib },
    .{ .recv = "Platform", .name = "runtime", .ret = "Option(Runtime)", .origin = .stdlib },
    .{ .recv = "Platform", .name = "exit", .params = &.{"UInt8"}, .ret = "none" },
    .{ .recv = "Env", .name = "get", .params = &.{"String"}, .ret = "Option(String)" },
    .{ .recv = "Out", .name = "write", .params = &.{"String"}, .ret = "none" },
    .{ .recv = "Out", .name = "write_line", .params = &.{"String"}, .ret = "none", .origin = .stdlib },
    .{ .recv = "Out", .name = "flush", .ret = "none", .origin = .stdlib },
    .{ .recv = "Out", .on_type = true, .name = "fixture", .ret = "Out", .only = .tests, .origin = .stdlib },
    .{ .recv = "Out", .name = "written", .ret = "List(String)", .only = .tests, .origin = .stdlib },
    // TCP (step 11): every call that can wait takes within:; a Listener and a Conn are
    // capabilities, passed down like any other.
    .{ .recv = "Net", .name = "listen", .params = &.{"UInt16"}, .ret = "Result(Listener, NetError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Net", .name = "connect", .params = &.{ "String", "UInt16" }, .ret = "Result(Conn, NetError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Listener", .name = "accept", .ret = "Result(Conn, NetError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Listener", .name = "port", .ret = "UInt16", .origin = .stdlib },
    .{ .recv = "Conn", .name = "read_line", .ret = "Result(Option(String), NetError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Conn", .name = "write", .params = &.{"String"}, .ret = "Result(none, NetError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Conn", .name = "close", .ret = "none", .origin = .stdlib },
    // The runtime owns the loop (step 20): from these calls on it accepts on a listener or
    // reads a connection and sends each result to the process `into:` names, as a message
    // that process declares; `idle:` is the wait's deadline. None waits itself.
    .{ .recv = "Listener", .name = "serve", .named = &.{ .{ .name = "into", .type = "Handle(P)" }, .{ .name = "idle", .type = "Duration" } }, .ret = "none", .origin = .stdlib },
    .{ .recv = "Conn", .name = "lines", .named = &.{ .{ .name = "into", .type = "Handle(P)" }, .{ .name = "idle", .type = "Duration" } }, .ret = "none", .origin = .stdlib },
    .{ .recv = "Net", .on_type = true, .name = "fixture", .ret = "Net", .only = .tests, .origin = .stdlib },
    // HTTP/1.1 over TCP (step 16): one request per connection; an HttpListener and an
    // Exchange are capabilities, and an Exchange closes when the process holding it stops.
    .{ .recv = "Http", .name = "listen", .params = &.{"UInt16"}, .ret = "Result(HttpListener, HttpError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "HttpListener", .name = "accept", .ret = "Result(Exchange, HttpError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "HttpListener", .name = "port", .ret = "UInt16", .origin = .stdlib },
    .{ .recv = "HttpListener", .name = "serve", .named = &.{ .{ .name = "into", .type = "Handle(P)" }, .{ .name = "idle", .type = "Duration" } }, .ret = "none", .origin = .stdlib },
    .{ .recv = "Exchange", .name = "request", .ret = "Request", .origin = .stdlib },
    .{ .recv = "Exchange", .name = "reply", .params = &.{"Response"}, .ret = "Result(none, HttpError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Http", .name = "send", .params = &.{"Request"}, .named = &.{ .{ .name = "host", .type = "String" }, .{ .name = "port", .type = "UInt16" } }, .ret = "Result(Response, HttpError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Http", .on_type = true, .name = "fixture", .ret = "Http", .only = .tests, .origin = .stdlib },
    // The runtime surface (step 23): what the processes are doing, read between updates; send,
    // pause, and resume act, and a Runtime narrowed by read_only refuses them. Each read takes
    // within:, since a process in the middle of an update is read once the update ends.
    .{ .recv = "Runtime", .name = "processes", .ret = "List(ProcessInfo)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "state", .params = &.{"UInt64"}, .ret = "Result(String, RuntimeError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "recent", .params = &.{ "UInt64", "UInt64" }, .ret = "List(Event)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "events", .named = &.{ .{ .name = "since", .type = "Time" }, .{ .name = "n", .type = "UInt64" } }, .ret = "List(Event)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "crashes", .params = &.{"UInt64"}, .ret = "List(Event)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "sources", .ret = "List(SourceInfo)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "memory", .ret = "MemoryInfo", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "slowest", .params = &.{"UInt64"}, .ret = "List(Event)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "send", .params = &.{ "UInt64", "String" }, .ret = "Result(none, RuntimeError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "pause", .params = &.{"UInt64"}, .ret = "Result(none, RuntimeError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "resume", .params = &.{"UInt64"}, .ret = "Result(none, RuntimeError)", .can_wait = true, .origin = .stdlib },
    .{ .recv = "Runtime", .name = "read_only", .ret = "Runtime", .origin = .stdlib },
    .{ .recv = "Runtime", .on_type = true, .name = "fixture", .ret = "Runtime", .only = .tests, .origin = .stdlib },
    // JSON
    .{ .recv = "Json", .on_type = true, .name = "encode", .params = &.{"T"}, .ret = "String", .origin = .stdlib },
    .{ .recv = "Json", .on_type = true, .name = "decode", .params = &.{"String"}, .ret = "Result(Json, JsonError)", .origin = .stdlib },
    .{ .recv = "Json", .name = "to_i64", .ret = "Option(Int64)", .origin = .stdlib },
    .{ .recv = "Deadline", .name = "at_most", .params = &.{"Duration"}, .ret = "Deadline", .origin = .stdlib },
    // What remains of the deadline, zero once it has passed (step 24).
    .{ .recv = "Deadline", .name = "remaining", .ret = "Duration", .origin = .stdlib },
    .{ .recv = "Deadline", .on_type = true, .name = "fixture", .params = &.{"Duration"}, .ret = "Deadline", .only = .tests, .origin = .stdlib },
    // The refund module's stand-ins (corpus-only)
    .{ .recv = "Charge", .on_type = true, .name = "fixture", .named = &.{.{ .name = "captured_amount", .type = "Money" }}, .ret = "Charge", .only = .tests, .origin = .corpus_only },
    .{ .recv = "Charge", .on_type = true, .name = "fixture", .named = &.{ .{ .name = "captured_at", .type = "Time" }, .{ .name = "captured_amount", .type = "Money" } }, .ret = "Charge", .only = .tests, .origin = .corpus_only },
    .{ .recv = "Charge", .name = "refunded?", .ret = "Bool", .origin = .corpus_only },
    .{ .recv = "Money", .on_type = true, .name = "cents", .params = &.{"UInt64"}, .ret = "Money", .origin = .corpus_only },
    .{ .recv = "Money", .on_type = true, .name = "zero", .ret = "Money", .origin = .corpus_only },
    // Processes (grammar: Processes)
    .{ .recv = "Process", .on_type = true, .name = "start", .ret = "Handle(P)" },
    // A supervisor starts its children and gives their handles: the one child's Handle,
    // or a tuple of them in child-line order. Nothing names the supervisor itself.
    .{ .recv = "Supervisor", .on_type = true, .name = "start", .ret = "Handle(P)" },
    .{ .recv = "Handle(P)", .name = "send", .params = &.{"Message(P)"}, .ret = "none" },
    // Delivered no earlier than `delay` after the sending update ends (step 24).
    .{ .recv = "Handle(P)", .name = "send", .params = &.{"Message(P)"}, .named = &.{.{ .name = "delay", .type = "Duration" }}, .ret = "none" },
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

/// Whether `name` is a struct the stdlib declares (`Request`, `Response`): a prelude type
/// string that names it means the prelude's, whatever a module declares.
pub fn findStdStruct(name: []const u8) bool {
    for (structs) |s| if (s.origin == .stdlib and std.mem.eql(u8, s.name, name)) return true;
    return false;
}

/// Whether `name` is an alias or struct stand-in.
pub fn findStandIn(name: []const u8) bool {
    for (aliases) |a| if (std.mem.eql(u8, a.name, name)) return true;
    for (structs) |s| if (std.mem.eql(u8, s.name, name)) return true;
    return false;
}

/// Words a type string may use that are not type names.
const type_string_words = [_][]const u8{ "T", "U", "A", "E", "K", "V", "N", "P", "Message", "Reply", "none", "fn", "Capability" };

test "every name in a prelude type string is a prelude type or a type-string word" {
    var strings: std.ArrayList([]const u8) = .empty;
    defer strings.deinit(std.testing.allocator);
    const gpa = std.testing.allocator;
    for (fns) |f| {
        if (f.recv.len > 0 and !std.mem.eql(u8, f.recv, "Int") and !std.mem.eql(u8, f.recv, "Process") and !std.mem.eql(u8, f.recv, "Supervisor") and !std.mem.eql(u8, f.recv, "Type")) try strings.append(gpa, f.recv);
        for (f.params) |p| try strings.append(gpa, p);
        for (f.named) |n| try strings.append(gpa, n.type);
        try strings.append(gpa, f.ret);
    }
    for (variants) |v| for (v.fields) |fld| try strings.append(gpa, fld.type);
    for (structs) |s| for (s.fields) |fld| try strings.append(gpa, fld.type);
    for (aliases) |a| try strings.append(gpa, a.base);
    for (values) |v| try strings.append(gpa, v.type);
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
            const known = findType(word) != null or findStandIn(word) or for (type_string_words) |w| {
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
