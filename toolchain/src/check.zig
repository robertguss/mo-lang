//! Stage 3, tier 1 (design-v0/05): names and types. Declarations are registered,
//! then every signature and declared type is resolved, then every body is checked
//! in source order with local inference (literals typed from use, generics fresh per
//! call), and the laws of chapter 2 that need no runtime are checked on the way
//! (MO03xx). Every finding is a diag.Record with a stable code, never a warning.
//! The checked facts (a type per node, the function each call resolved to) go to
//! caps.zig in `Checked`.
const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const prelude = @import("prelude.zig");
const types = @import("types.zig");

const Index = ast.Index;
const Node = ast.Node;
const Id = types.Id;

pub const Error = error{OutOfMemory};

// ---- the error catalog: one `why` per code

pub const Code = enum {
    unknown_name,
    unknown_type,
    expose_undeclared,
    expose_twice,
    declared_twice,
    mismatch,
    arity,
    no_member,
    bad_named_arg,
    bad_try,
    try_variants,
    bad_pattern,
    bound_unmet,
    misplaced,
    not_assignable,
    impl_mismatch,
    unnamed_fields,
    literal_range,
    // the laws, chapter 2
    body_lines,
    file_lines,
    too_many_params,
    nesting,
    state_fields,
    rebinding,
    unused_binding,
    not_exhaustive,
    catch_all,
    unconsumed,
    requires_untested,
    default_param,
    anon_stored,
    var_captured,
    var_to_process,
    unsupervised,
    hand_verified,
    use_cycle,
};

pub const Entry = struct { code: []const u8, category: diag.Category, why: []const u8 };

pub const catalog = std.enums.EnumArray(Code, Entry).init(.{
    .unknown_name = .{ .code = "MO0201", .category = .types, .why = "A name is a binding in scope, a parameter, or a function or variant declared in this module or the prelude (toolchain/PRELUDE.md). Nothing else exists." },
    .unknown_type = .{ .code = "MO0202", .category = .types, .why = "A type is a prelude type, a type declared in this module, a name brought in by use, or a one-letter type parameter in a function signature." },
    .expose_undeclared = .{ .code = "MO0203", .category = .types, .why = "The expose line is the module's table of contents; every name on it must be declared in the module (grammar, semantic rules)." },
    .expose_twice = .{ .code = "MO0204", .category = .types, .why = "The expose line names each public declaration exactly once." },
    .declared_twice = .{ .code = "MO0205", .category = .types, .why = "One name means one declaration in a module, so a reader never has to ask which one a call reaches." },
    .mismatch = .{ .code = "MO0206", .category = .types, .why = "Mo has no implicit conversion: a value is used only where its type is expected. Named conversions cross types." },
    .arity = .{ .code = "MO0207", .category = .types, .why = "Every parameter is passed at every call, and nothing else is: there are no defaults and no optional arguments." },
    .no_member = .{ .code = "MO0208", .category = .types, .why = "x.name reads a field of x's struct, or calls name with x as its first argument; one of the two must exist." },
    .bad_named_arg = .{ .code = "MO0209", .category = .types, .why = "Construction names every field exactly once; functions take their arguments by position, and only the prelude's within:, into:, and delay: are named." },
    .bad_try = .{ .code = "MO0210", .category = .types, .why = "try passes an Error or a None up to the caller, so it applies to a Result or an Option inside a function that returns the same kind." },
    .try_variants = .{ .code = "MO0211", .category = .types, .why = "try re-tags an error, it never converts one: every variant of the error it passes up must exist in the function's error type with the same name and fields." },
    .bad_pattern = .{ .code = "MO0212", .category = .types, .why = "A pattern matches the shape of its subject's type: a one-field variant positionally, a variant with more fields by name, a tuple by position." },
    .bound_unmet = .{ .code = "MO0213", .category = .types, .why = "where T: Trait promises the body that T has the trait's functions, so every type passed as T needs an impl of that trait." },
    .misplaced = .{ .code = "MO0214", .category = .types, .why = "Some forms belong to one place: result and old to contracts, assert to tests, any to properties, T.all and flows to never, break to a for, return to a function body." },
    .not_assignable = .{ .code = "MO0215", .category = .types, .why = "Only var, inout, and state places change; a name bound with = is bound once, and an inout argument must be a var the caller holds." },
    .impl_mismatch = .{ .code = "MO0216", .category = .types, .why = "An impl keeps the trait's promise exactly: every function the trait lists, with Self replaced by the implementing type, and nothing else." },
    .unnamed_fields = .{ .code = "MO0222", .category = .types, .why = "Construction is always by named fields (grammar §6), so a reordered struct never silently swaps two values." },
    .literal_range = .{ .code = "MO0217", .category = .types, .why = "Integers are sized; a literal must fit the type it is given, and overflow is never implicit." },
    .body_lines = .{ .code = "MO0301", .category = .laws, .why = "A function body is at most 70 lines (chapter 2, shape laws), so a whole function is read at once. The fix is named helper functions." },
    .file_lines = .{ .code = "MO0302", .category = .laws, .why = "A file is at most 500 lines (chapter 2, shape laws), so a module is read in one sitting. The fix is a second module." },
    .too_many_params = .{ .code = "MO0303", .category = .laws, .why = "A function takes at most 6 parameters (chapter 2, shape laws); past that, the values belong together in a struct." },
    .nesting = .{ .code = "MO0304", .category = .laws, .why = "Nesting is at most 3 deep (chapter 2, shape laws): each if, case, for, and block anonymous function is a level. The inner block becomes its own function." },
    .state_fields = .{ .code = "MO0305", .category = .laws, .why = "A process state has at most 12 fields (chapter 2, shape laws); a bigger box is a struct field or a second process." },
    .rebinding = .{ .code = "MO0306", .category = .laws, .why = "A name bound with = is bound once (chapter 2, honesty laws), so a reader never has to ask which value it holds. A value that changes is a var." },
    .unused_binding = .{ .code = "MO0307", .category = .laws, .why = "Every binding is read (chapter 2, honesty laws): an unused one is dead code, or a bug where another name was used instead." },
    .not_exhaustive = .{ .code = "MO0308", .category = .laws, .why = "Every case is exhaustive (chapter 2, honesty laws), so a value nobody handles is a compile error, not a crash." },
    .catch_all = .{ .code = "MO0309", .category = .laws, .why = "No catch-all arm on a closed enum (chapter 2, honesty laws): a _ arm would silently take every variant added later." },
    .unconsumed = .{ .code = "MO0310", .category = .laws, .why = "Every Result and Option is consumed (chapter 2, honesty laws): a dropped error is an error nobody handles." },
    .requires_untested = .{ .code = "MO0311", .category = .laws, .why = "Every requires has a test rejects that trips it (chapter 2, contract laws). Tier 1 checks that a test rejects calls the function; tier 2 checks that the call trips." },
    .default_param = .{ .code = "MO0312", .category = .laws, .why = "No default parameters (chapter 2, honesty laws): every call shows every value the function receives." },
    .anon_stored = .{ .code = "MO0313", .category = .laws, .why = "An anonymous function is a call argument only, never stored or returned (chapter 2), so effects never hide in a value." },
    .var_captured = .{ .code = "MO0314", .category = .laws, .why = "A var is never aliased (chapter 3, values): an anonymous function captures read-only, so it cannot hold a var." },
    .var_to_process = .{ .code = "MO0315", .category = .laws, .why = "A var is never aliased (chapter 3, values): a process that received one would see a value its owner still changes." },
    .unsupervised = .{ .code = "MO0316", .category = .laws, .why = "A process not under a supervisor does not compile (chapter 3, processes): every crash has someone to restart it." },
    .hand_verified = .{ .code = "MO0317", .category = .laws, .why = "The verified: line belongs to the toolchain (chapter 5). Until tier 2 computes and writes it, a verified: line in source was written by hand." },
    .use_cycle = .{ .code = "MO0318", .category = .laws, .why = "Modules have no import cycles (chapter 2, shape laws), so each module is understood, checked, and cached after the ones it uses." },
});

// ---- what the checker hands on

pub const DeclKind = enum { struct_, enum_, alias, opaque_, trait, process, supervisor, recipe, prelude_enum };

pub const Range = struct {
    start: u32 = 0,
    end: u32 = 0,
    pub fn len(r: Range) u32 {
        return r.end - r.start;
    }
};

pub const Decl = struct {
    kind: DeclKind,
    name: []const u8,
    node: Index = 0,
    type: Id = types.unknown,
    /// Struct fields, or a process's state fields.
    fields: Range = .{},
    /// Enum variants, or a process's messages.
    variants: Range = .{},
    /// Process and supervisor parameters.
    params: Range = .{},
    /// A trait's signatures.
    sigs: Range = .{},
    resolving: bool = false,
};

pub const Field = struct { name: []const u8, type: Id, node: Index = 0 };

pub const Variant = struct {
    name: []const u8,
    owner: u32,
    fields: Range = .{},
    /// A message's reply type, when it has one.
    reply: ?Id = null,
    node: Index = 0,
};

pub const Param = struct { name: []const u8, type: Id, inout: bool = false, node: Index = 0 };

pub const SigKind = enum { module, recipe, trait, impl };

pub const FnSig = struct {
    name: []const u8,
    node: Index,
    kind: SigKind,
    owner: u32 = 0,
    params: Range = .{},
    ret: Id = types.unknown,
    /// Indices into `generics`.
    generics: Range = .{},
};

pub const Generic = struct { name: []const u8, type: Id };

pub const Bound = struct { generic: u32, trait: u32 };

pub const Impl = struct { trait: u32, for_type: Id, sigs: Range, node: Index };

pub const Callee = union(enum) { none, prelude: u32, user: u32 };

pub const Checked = struct {
    tree: ast.Tree,
    pool: types.Pool,
    node_types: []const Id,
    callee: []const Callee,
    decls: []const Decl,
    fields: []const Field,
    variants: []const Variant,
    params: []const Param,
    sigs: []const FnSig,
    /// `never` bodies that are a flows(...) rule, for caps.zig.
    flows: []const Index,

    pub fn typeOf(c: *const Checked, node: Index) Id {
        return c.pool.resolve(c.node_types[node]);
    }

    pub fn findDecl(c: *const Checked, name: []const u8) ?u32 {
        for (c.decls, 0..) |d, i| if (std.mem.eql(u8, d.name, name) and d.kind != .prelude_enum) return @intCast(i);
        return null;
    }
};

pub fn check(gpa: std.mem.Allocator, tree: ast.Tree, out: *diag.List) Error!Checked {
    var c: Checker = .{ .gpa = gpa, .tree = tree, .out = out, .pool = try types.Pool.init(gpa) };
    c.node_types = try gpa.alloc(Id, tree.nodes.len);
    @memset(c.node_types, types.unknown);
    c.callee = try gpa.alloc(Callee, tree.nodes.len);
    @memset(c.callee, .none);
    try c.line_starts.append(gpa, 0);
    for (tree.source, 0..) |ch, k| if (ch == '\n') try c.line_starts.append(gpa, @intCast(k + 1));
    try c.registerPrelude();
    try c.registerModule();
    try c.resolveModule();
    c.tripped = try gpa.alloc(bool, c.sigs.items.len);
    @memset(c.tripped, false);
    try c.checkModule();
    try c.checkModuleLaws();
    return .{
        .tree = tree,
        .pool = c.pool,
        .node_types = c.node_types,
        .callee = c.callee,
        .decls = c.decls.items,
        .fields = c.fields.items,
        .variants = c.variants.items,
        .params = c.params.items,
        .sigs = c.sigs.items,
        .flows = c.flows.items,
    };
}

// ---- the checker

const BindKind = enum { param, inout, let, var_, pattern, state };

const Binding = struct {
    name: []const u8,
    type: Id,
    kind: BindKind,
    token: u32,
    used: bool = false,
    anon_depth: u32 = 0,
};

const FrameKind = enum { module, function, test_block, never, contract, invariant, update, refinement, supervisor, anon };

const Frame = struct {
    kind: FrameKind = .module,
    name: []const u8 = "",
    ret: Id = types.unknown,
    has_ret: bool = false,
    result: ?Id = null,
    old_ok: bool = false,
    in_test: bool = false,
    in_never: bool = false,
    in_property: bool = false,
    refine_value: ?Id = null,
    scope_base: u32 = 0,
    loop_depth: u32 = 0,
    anon_depth: u32 = 0,
    deferred_start: u32 = 0,
    in_rejects: bool = false,
    nest: u32 = 0,
    nest_reported: bool = false,
};

const Deferred = struct {
    kind: enum { literal, numeric, ordered, bound },
    node: Index,
    type: Id,
    trait: u32 = 0,
};

const Refinement = struct { node: Index, base: Id };

const TypeCtx = struct {
    generics: ?*std.ArrayList(u32) = null,
    self_ok: bool = false,
    recipe: bool = false,
};

const Env = struct {
    letters: [26]Id = [_]Id{types.unknown} ** 26,
    n: Id = types.unknown,
    process: ?u32 = null,
    reply: Id = types.unknown,
};

const Checker = struct {
    gpa: std.mem.Allocator,
    tree: ast.Tree,
    out: *diag.List,
    pool: types.Pool,
    node_types: []Id = &.{},
    callee: []Callee = &.{},

    decls: std.ArrayList(Decl) = .empty,
    fields: std.ArrayList(Field) = .empty,
    variants: std.ArrayList(Variant) = .empty,
    params: std.ArrayList(Param) = .empty,
    sigs: std.ArrayList(FnSig) = .empty,
    generics: std.ArrayList(Generic) = .empty,
    sig_generics: std.ArrayList(u32) = .empty,
    bounds: std.ArrayList(Bound) = .empty,
    impls: std.ArrayList(Impl) = .empty,
    refinements: std.ArrayList(Refinement) = .empty,
    flows: std.ArrayList(Index) = .empty,

    type_names: std.StringHashMapUnmanaged(u32) = .empty,
    fn_names: std.StringHashMapUnmanaged(u32) = .empty,
    sig_of_node: std.AutoHashMapUnmanaged(Index, u32) = .empty,

    bindings: std.ArrayList(Binding) = .empty,
    deferred: std.ArrayList(Deferred) = .empty,
    frame: Frame = .{},
    /// The one node allowed to be an anonymous function right now: the argument
    /// being checked.
    anon_ok: Index = 0,
    /// Signatures a test rejects calls directly.
    tripped: []bool = &.{},
    /// Byte offset where each line starts.
    line_starts: std.ArrayList(u32) = .empty,
    /// Above zero while checking what is sent to a process.
    process_args: u32 = 0,

    // ---- small helpers

    fn text(c: *Checker, tok: u32) []const u8 {
        return c.tree.tokenText(tok);
    }

    fn node(c: *Checker, i: Index) Node {
        return c.tree.nodes[i];
    }

    fn spanAt(c: *Checker, extra_index: u32) []const u32 {
        if (extra_index == 0) return &.{};
        const s = c.tree.extraData(ast.Span, extra_index);
        return c.tree.span(s.start, s.end);
    }

    fn spanOf(c: *Checker, n: Node) []const u32 {
        return c.tree.span(n.lhs, n.rhs);
    }

    fn print(c: *Checker, comptime fmt: []const u8, args: anytype) Error![]const u8 {
        return std.fmt.allocPrint(c.gpa, fmt, args);
    }

    fn tn(c: *Checker, t: Id) Error![]const u8 {
        return c.pool.name(c.gpa, t);
    }

    fn firstToken(c: *Checker, i: Index) u32 {
        var cur = i;
        while (true) {
            const n = c.node(cur);
            switch (n.kind) {
                .implies, .or_expr, .and_expr, .compare, .is_expr, .range, .add, .mul, .member, .member_call, .tuple_index, .call, .assign => cur = n.lhs,
                else => return n.main_token,
            }
        }
    }

    fn report(c: *Checker, code: Code, at: u32, what: []const u8) Error!void {
        const e = catalog.get(code);
        try c.out.append(c.gpa, .{ .code = e.code, .category = e.category, .at = at, .what = what, .why = e.why });
    }

    fn reportTok(c: *Checker, code: Code, tok: u32, what: []const u8) Error!void {
        return c.report(code, c.tree.tokens[tok].start, what);
    }

    fn reportNode(c: *Checker, code: Code, i: Index, what: []const u8) Error!void {
        return c.reportTok(code, c.firstToken(i), what);
    }

    fn mismatch(c: *Checker, at: Index, expected: Id, found: Id) Error!void {
        const what = if (c.pool.resolve(found) == types.none)
            try c.print("this gives no value, but {s} is expected here", .{try c.tn(expected)})
        else
            try c.print("expected {s}, found {s}", .{ try c.tn(expected), try c.tn(found) });
        try c.reportNode(.mismatch, at, what);
    }

    fn expectType(c: *Checker, at: Index, expected: Id, found: Id) Error!Id {
        if (expected != types.unknown and !c.pool.unify(expected, found)) {
            try c.mismatch(at, expected, found);
            return types.unknown;
        }
        return found;
    }

    fn bt(c: *Checker, t: Id) types.Type {
        return c.pool.get(c.pool.base(t));
    }

    // ---- scopes and frames

    fn pushScope(c: *Checker) u32 {
        return @intCast(c.bindings.items.len);
    }

    fn popScope(c: *Checker, mark: u32) Error!void {
        for (c.bindings.items[mark..]) |b| {
            if (b.used or b.kind == .param or b.kind == .inout or b.kind == .state) continue;
            try c.reportTok(.unused_binding, b.token, try c.print("{s} is bound but never used.", .{b.name}));
        }
        c.bindings.shrinkRetainingCapacity(mark);
    }

    fn bind(c: *Checker, name: []const u8, t: Id, kind: BindKind, token: u32) Error!void {
        // One name, one binding, across every scope of the function being checked.
        if (kind == .let or kind == .var_ or kind == .pattern) {
            for (c.bindings.items[c.frame.scope_base..]) |b| if (std.mem.eql(u8, b.name, name)) {
                try c.reportTok(.rebinding, token, try c.print("{s} is bound twice in one scope; make it var {s}, or pick a new name.", .{ name, name }));
                break;
            };
        }
        try c.bindings.append(c.gpa, .{ .name = name, .type = t, .kind = kind, .token = token, .anon_depth = c.frame.anon_depth });
    }

    fn lookup(c: *Checker, name: []const u8) ?u32 {
        var i = c.bindings.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, c.bindings.items[i].name, name)) return @intCast(i);
        }
        return null;
    }

    fn beginFrame(c: *Checker, kind: FrameKind, name: []const u8) Frame {
        const saved = c.frame;
        c.frame = .{ .kind = kind, .name = name, .scope_base = @intCast(c.bindings.items.len), .deferred_start = @intCast(c.deferred.items.len) };
        return saved;
    }

    fn endFrame(c: *Checker, saved: Frame) Error!void {
        try c.finishDeferred(c.frame.deferred_start);
        c.frame = saved;
    }

    fn defer_(c: *Checker, d: Deferred) Error!void {
        try c.deferred.append(c.gpa, d);
    }

    fn finishDeferred(c: *Checker, start: u32) Error!void {
        // Literals no other use constrained become Int64 first, so bounds and operators see them.
        for (c.deferred.items[start..]) |d| {
            if (d.kind == .literal and c.pool.isIntLiteralVar(d.type)) _ = c.pool.unify(d.type, types.int(.i64));
        }
        for (c.deferred.items[start..]) |d| switch (d.kind) {
            .numeric => if (!c.pool.isNumeric(d.type)) {
                try c.reportTok(.mismatch, c.node(d.node).main_token, try c.print("{s} needs numbers, found {s}", .{ c.text(c.node(d.node).main_token), try c.tn(d.type) }));
            },
            .ordered => {
                const t = c.bt(d.type);
                switch (t.tag) {
                    .int, .float, .string, .time, .duration, .unknown, .variable, .never => {},
                    else => try c.reportTok(.mismatch, c.node(d.node).main_token, try c.print("{s} compares numbers, strings, times, and durations; found {s}", .{ c.text(c.node(d.node).main_token), try c.tn(d.type) })),
                }
            },
            .bound => try c.checkBound(d),
            .literal => {},
        };
        for (c.deferred.items[start..]) |d| if (d.kind == .literal) try c.checkLiteral(d);
        c.deferred.shrinkRetainingCapacity(start);
    }

    fn checkLiteral(c: *Checker, d: Deferred) Error!void {
        const t = c.bt(d.type);
        if (t.tag != .int) return;
        const raw = c.text(c.node(d.node).main_token);
        var digits: [32]u8 = undefined;
        var n: usize = 0;
        for (raw) |ch| if (ch != '_' and n < digits.len) {
            digits[n] = ch;
            n += 1;
        };
        const v = std.fmt.parseInt(u64, digits[0..n], 10) catch std.math.maxInt(u64);
        const kind: types.IntKind = @enumFromInt(t.a);
        const max: u64 = switch (kind) {
            .i8 => 127,
            .i16 => 32_767,
            .i32 => 2_147_483_647,
            .i64 => 9_223_372_036_854_775_807,
            .u8 => 255,
            .u16 => 65_535,
            .u32 => 4_294_967_295,
            .u64 => std.math.maxInt(u64),
        };
        if (v > max) try c.reportTok(.literal_range, c.node(d.node).main_token, try c.print("{s} does not fit in {s}", .{ raw, try c.tn(d.type) }));
    }

    fn checkBound(c: *Checker, d: Deferred) Error!void {
        const r = c.pool.resolve(d.type);
        const t = c.pool.get(r);
        const trait = c.decls.items[d.trait];
        switch (t.tag) {
            .variable, .unknown, .never => return,
            .param => {
                for (c.bounds.items) |b| if (b.generic == t.a and b.trait == d.trait) return;
            },
            else => {
                for (c.impls.items) |im| {
                    if (im.trait == d.trait and c.pool.unify(im.for_type, r)) return;
                }
            },
        }
        try c.reportNode(.bound_unmet, d.node, try c.print("{s} has no impl {s}, which this call needs", .{ try c.tn(r), trait.name }));
    }

    // ---- pass 1: register names

    fn addDecl(c: *Checker, d: Decl) Error!u32 {
        const i = try c.pool.addDecl(d.name);
        std.debug.assert(i == c.decls.items.len);
        try c.decls.append(c.gpa, d);
        return i;
    }

    fn registerPrelude(c: *Checker) Error!void {
        for (prelude.types) |pt| {
            if (pt.kind != .error_enum) continue;
            const d = try c.addDecl(.{ .kind = .prelude_enum, .name = pt.name });
            c.decls.items[d].type = try c.pool.add(.{ .tag = .decl, .a = d });
            const vstart: u32 = @intCast(c.variants.items.len);
            for (prelude.variants) |pv| {
                if (!std.mem.eql(u8, pv.owner, pt.name)) continue;
                const fstart: u32 = @intCast(c.fields.items.len);
                for (pv.fields) |f| {
                    var env: Env = .{};
                    try c.fields.append(c.gpa, .{ .name = f.name, .type = try c.parseTs(f.type, &env) });
                }
                try c.variants.append(c.gpa, .{ .name = pv.name, .owner = d, .fields = .{ .start = fstart, .end = @intCast(c.fields.items.len) } });
            }
            c.decls.items[d].variants = .{ .start = vstart, .end = @intCast(c.variants.items.len) };
        }
    }

    fn registerType(c: *Checker, kind: DeclKind, name_tok: u32, n: Index) Error!?u32 {
        const name = c.text(name_tok);
        if (prelude.findType(name) != null) {
            try c.reportTok(.declared_twice, name_tok, try c.print("{s} is already a prelude type", .{name}));
            return null;
        }
        if (c.type_names.get(name) != null) {
            try c.reportTok(.declared_twice, name_tok, try c.print("{s} is declared twice in this module", .{name}));
            return null;
        }
        const d = try c.addDecl(.{ .kind = kind, .name = name, .node = n });
        try c.type_names.put(c.gpa, name, d);
        switch (kind) {
            .struct_, .enum_, .opaque_ => c.decls.items[d].type = try c.pool.add(.{ .tag = .decl, .a = d }),
            .process => c.decls.items[d].type = try c.pool.add(.{ .tag = .handle, .a = d }),
            else => {},
        }
        return d;
    }

    fn registerFn(c: *Checker, name_tok: u32, n: Index, kind: SigKind, owner: u32) Error!u32 {
        const i: u32 = @intCast(c.sigs.items.len);
        try c.sigs.append(c.gpa, .{ .name = c.text(name_tok), .node = n, .kind = kind, .owner = owner });
        try c.sig_of_node.put(c.gpa, n, i);
        if (kind == .module or kind == .recipe) {
            const gop = try c.fn_names.getOrPut(c.gpa, c.text(name_tok));
            if (gop.found_existing) {
                try c.reportTok(.declared_twice, name_tok, try c.print("{s} is declared twice in this module", .{c.text(name_tok)}));
            } else gop.value_ptr.* = i;
        }
        return i;
    }

    fn items(c: *Checker) []const u32 {
        const root = c.node(0);
        return c.tree.span(root.lhs, root.rhs);
    }

    fn registerModule(c: *Checker) Error!void {
        for (c.items()) |it| {
            const n = c.node(it);
            switch (n.kind) {
                .struct_decl => _ = try c.registerType(.struct_, n.main_token, it),
                .enum_decl => _ = try c.registerType(.enum_, n.main_token, it),
                .type_decl => _ = try c.registerType(.alias, n.main_token, it),
                .trait_decl => _ = try c.registerType(.trait, n.main_token, it),
                .process_decl => _ = try c.registerType(.process, n.main_token, it),
                .supervisor_decl => _ = try c.registerType(.supervisor, n.main_token, it),
                .recipe_decl => {
                    _ = try c.registerType(.recipe, n.main_token, it);
                    const r = c.tree.extraData(ast.Recipe, n.lhs);
                    for (c.tree.span(r.sigs_start, r.sigs_end)) |s| _ = try c.registerFn(c.node(s).main_token, s, .recipe, 0);
                },
                .fn_decl => _ = try c.registerFn(n.main_token, it, .module, 0),
                .use => if (n.rhs != 0) {
                    for (c.spanAt(n.rhs)) |tok| {
                        const name = c.text(tok);
                        if (c.type_names.get(name) != null) continue;
                        const d = try c.addDecl(.{ .kind = .opaque_, .name = name, .node = it });
                        c.decls.items[d].type = try c.pool.add(.{ .tag = .decl, .a = d });
                        try c.type_names.put(c.gpa, name, d);
                    }
                },
                else => {},
            }
        }
        try c.checkExpose();
    }

    fn checkExpose(c: *Checker) Error!void {
        for (c.items()) |it| {
            const n = c.node(it);
            if (n.kind != .expose) continue;
            const toks = c.spanOf(n);
            for (toks, 0..) |tok, i| {
                const name = c.text(tok);
                for (toks[0..i]) |prev| if (std.mem.eql(u8, c.text(prev), name)) {
                    try c.reportTok(.expose_twice, tok, try c.print("{s} is on the expose line twice", .{name}));
                    break;
                };
                const declared = if (c.tree.tokens[tok].kind == .type_name)
                    if (c.type_names.get(name)) |d| c.decls.items[d].kind != .opaque_ else false
                else if (c.fn_names.get(name)) |s| c.sigs.items[s].kind == .module else false;
                if (!declared) try c.reportTok(.expose_undeclared, tok, try c.print("{s} is exposed but not declared in this module", .{name}));
            }
        }
    }

    // ---- pass 2: resolve declared types and signatures

    fn resolveModule(c: *Checker) Error!void {
        for (c.items()) |it| {
            const n = c.node(it);
            switch (n.kind) {
                .struct_decl => {
                    const d = c.type_names.get(c.text(n.main_token)) orelse continue;
                    if (c.decls.items[d].node != it) continue;
                    c.decls.items[d].fields = try c.resolveFields(c.spanOf(n));
                },
                .enum_decl => {
                    const d = c.type_names.get(c.text(n.main_token)) orelse continue;
                    if (c.decls.items[d].node != it) continue;
                    const vs = c.spanOf(n);
                    const vstart: u32 = @intCast(c.variants.items.len);
                    try c.variants.appendNTimes(c.gpa, undefined, vs.len);
                    for (vs, 0..) |v, i| {
                        const vn = c.node(v);
                        const fields = try c.resolveFields(c.tree.span(vn.lhs, vn.rhs));
                        c.variants.items[vstart + i] = .{ .name = c.text(vn.main_token), .owner = d, .fields = fields, .node = v };
                    }
                    c.decls.items[d].variants = .{ .start = vstart, .end = @intCast(c.variants.items.len) };
                },
                .type_decl => {
                    const d = c.type_names.get(c.text(n.main_token)) orelse continue;
                    if (c.decls.items[d].node == it) _ = try c.aliasType(d);
                },
                .trait_decl => {
                    const d = c.type_names.get(c.text(n.main_token)) orelse continue;
                    if (c.decls.items[d].node != it) continue;
                    const start: u32 = @intCast(c.sigs.items.len);
                    for (c.spanOf(n)) |s| _ = try c.registerFn(c.node(s).main_token, s, .trait, d);
                    const end: u32 = @intCast(c.sigs.items.len);
                    c.decls.items[d].sigs = .{ .start = start, .end = end };
                    for (start..end) |s| try c.resolveSig(@intCast(s));
                },
                .fn_decl => try c.resolveSig(c.sig_of_node.get(it).?),
                .process_decl => try c.resolveProcess(it),
                .supervisor_decl => {
                    const d = c.type_names.get(c.text(n.main_token)) orelse continue;
                    if (c.decls.items[d].node != it) continue;
                    var ctx: TypeCtx = .{};
                    c.decls.items[d].params = try c.resolveParams(c.spanAt(n.lhs), &ctx);
                    try c.paramLimit(n.main_token, c.decls.items[d].name, c.decls.items[d].params);
                },
                .recipe_decl => {
                    const r = c.tree.extraData(ast.Recipe, n.lhs);
                    for (c.tree.span(r.sigs_start, r.sigs_end)) |s| try c.resolveSig(c.sig_of_node.get(s).?);
                },
                else => {},
            }
        }
        // Impls last, so every trait they name is resolved.
        for (c.items()) |it| if (c.node(it).kind == .impl_decl) try c.resolveImpl(it);
    }

    fn resolveFields(c: *Checker, field_nodes: []const u32) Error!Range {
        const start: u32 = @intCast(c.fields.items.len);
        try c.fields.appendNTimes(c.gpa, undefined, field_nodes.len);
        for (field_nodes, 0..) |f, i| {
            const fnode = c.node(f);
            var ctx: TypeCtx = .{};
            for (field_nodes[0..i]) |prev| if (std.mem.eql(u8, c.text(c.node(prev).main_token), c.text(fnode.main_token))) {
                try c.reportTok(.declared_twice, fnode.main_token, try c.print("the field {s} is declared twice", .{c.text(fnode.main_token)}));
            };
            c.fields.items[start + i] = .{ .name = c.text(fnode.main_token), .type = try c.resolveType(fnode.lhs, &ctx), .node = f };
        }
        return .{ .start = start, .end = @intCast(c.fields.items.len) };
    }

    fn resolveParams(c: *Checker, param_nodes: []const u32, ctx: *TypeCtx) Error!Range {
        const start: u32 = @intCast(c.params.items.len);
        try c.params.appendNTimes(c.gpa, undefined, param_nodes.len);
        for (param_nodes, 0..) |p, i| {
            const pn = c.node(p);
            if (pn.rhs != 0) try c.reportTok(.default_param, pn.main_token, try c.print("{s} has a default value; parameters have no defaults, so pass {s} at the call.", .{ c.text(pn.main_token), c.exprText(pn.rhs) }));
            c.params.items[start + i] = .{ .name = c.text(pn.main_token), .type = try c.resolveType(pn.lhs, ctx), .inout = pn.kind == .param_inout, .node = p };
        }
        return .{ .start = start, .end = @intCast(c.params.items.len) };
    }

    fn resolveProcess(c: *Checker, it: Index) Error!void {
        const n = c.node(it);
        const d = c.type_names.get(c.text(n.main_token)) orelse return;
        if (c.decls.items[d].node != it) return;
        const data = c.tree.extraData(ast.Process, n.lhs);
        var ctx: TypeCtx = .{};
        c.decls.items[d].params = try c.resolveParams(c.tree.span(data.params_start, data.params_end), &ctx);
        try c.paramLimit(n.main_token, c.decls.items[d].name, c.decls.items[d].params);
        c.decls.items[d].fields = try c.resolveFields(c.spanOf(c.node(data.state)));
        const nfields = c.decls.items[d].fields.len();
        if (nfields > 12) try c.reportTok(.state_fields, n.main_token, try c.print("{s} keeps {d} state fields and the limit is 12; move related fields into a struct or a second process.", .{ c.decls.items[d].name, nfields }));
        const ms = c.tree.span(data.messages_start, data.messages_end);
        const vstart: u32 = @intCast(c.variants.items.len);
        try c.variants.appendNTimes(c.gpa, undefined, ms.len);
        for (ms, 0..) |m, i| {
            const mn = c.node(m);
            for (ms[0..i]) |prev| if (std.mem.eql(u8, c.text(c.node(prev).main_token), c.text(mn.main_token))) {
                try c.reportTok(.declared_twice, mn.main_token, try c.print("the message {s} is declared twice", .{c.text(mn.main_token)}));
            };
            const fields = try c.resolveFields(c.spanAt(mn.lhs));
            const reply: ?Id = if (mn.rhs != 0) try c.resolveType(mn.rhs, &ctx) else null;
            c.variants.items[vstart + i] = .{ .name = c.text(mn.main_token), .owner = d, .fields = fields, .reply = reply, .node = m };
        }
        c.decls.items[d].variants = .{ .start = vstart, .end = @intCast(c.variants.items.len) };
    }

    fn resolveSig(c: *Checker, i: u32) Error!void {
        const s = c.sigs.items[i];
        const n = c.node(s.node);
        const sig = c.tree.extraData(ast.Signature, n.lhs);
        var gens: std.ArrayList(u32) = .empty;
        var ctx: TypeCtx = .{ .generics = &gens, .self_ok = s.kind == .trait, .recipe = s.kind == .recipe };
        const params = try c.resolveParams(c.tree.span(sig.params_start, sig.params_end), &ctx);
        try c.paramLimit(n.main_token, s.name, params);
        const ret = try c.resolveType(sig.ret, &ctx);
        for (c.tree.span(sig.bounds_start, sig.bounds_end)) |b| {
            const bn = c.node(b);
            const gname = c.text(bn.main_token);
            const g = for (gens.items) |g| {
                if (std.mem.eql(u8, c.generics.items[g].name, gname)) break g;
            } else {
                try c.reportTok(.unknown_type, bn.main_token, try c.print("{s} is not a type parameter of {s}", .{ gname, s.name }));
                continue;
            };
            const path = c.node(bn.lhs);
            const tname = c.text(path.lhs);
            const trait = c.type_names.get(tname) orelse {
                try c.reportTok(.unknown_type, path.main_token, try c.print("there is no trait named {s}", .{tname}));
                continue;
            };
            if (c.decls.items[trait].kind != .trait) {
                try c.reportTok(.unknown_type, path.main_token, try c.print("{s} is not a trait", .{tname}));
                continue;
            }
            try c.bounds.append(c.gpa, .{ .generic = g, .trait = trait });
        }
        const gstart: u32 = @intCast(c.sig_generics.items.len);
        try c.sig_generics.appendSlice(c.gpa, gens.items);
        c.sigs.items[i].params = params;
        c.sigs.items[i].ret = ret;
        c.sigs.items[i].generics = .{ .start = gstart, .end = @intCast(c.sig_generics.items.len) };
    }

    fn resolveImpl(c: *Checker, it: Index) Error!void {
        const n = c.node(it);
        const tname = c.text(n.main_token);
        var ctx: TypeCtx = .{};
        const for_type = try c.resolveType(n.lhs, &ctx);
        const fns = c.spanAt(n.rhs);
        const trait = c.type_names.get(tname) orelse {
            try c.reportTok(.unknown_type, n.main_token, try c.print("there is no trait named {s}", .{tname}));
            return;
        };
        if (c.decls.items[trait].kind != .trait) {
            try c.reportTok(.unknown_type, n.main_token, try c.print("{s} is not a trait", .{tname}));
            return;
        }
        const start: u32 = @intCast(c.sigs.items.len);
        const index: u32 = @intCast(c.impls.items.len);
        for (fns) |f| _ = try c.registerFn(c.node(f).main_token, f, .impl, index);
        const end: u32 = @intCast(c.sigs.items.len);
        for (start..end) |s| try c.resolveSig(@intCast(s));
        try c.impls.append(c.gpa, .{ .trait = trait, .for_type = for_type, .sigs = .{ .start = start, .end = end }, .node = it });

        const tsigs = c.decls.items[trait].sigs;
        const type_name = try c.tn(for_type);
        for (tsigs.start..tsigs.end) |ts| {
            const want = c.sigs.items[ts];
            const got_i = for (start..end) |s| {
                if (std.mem.eql(u8, c.sigs.items[s].name, want.name)) break s;
            } else {
                try c.reportTok(.impl_mismatch, n.main_token, try c.print("impl {s} for {s} is missing {s}", .{ tname, type_name, want.name }));
                continue;
            };
            const got = c.sigs.items[got_i];
            const want_t = try c.pool.subst(try c.sigType(want), &.{types.self_}, &.{for_type});
            if (!c.pool.unify(want_t, try c.sigType(got))) {
                try c.reportTok(.impl_mismatch, c.node(got.node).main_token, try c.print("{s} does not match trait {s}: expected {s}", .{ got.name, tname, try c.tn(want_t) }));
            }
        }
        for (start..end) |s| {
            const got = c.sigs.items[s];
            const known = for (tsigs.start..tsigs.end) |ts| {
                if (std.mem.eql(u8, c.sigs.items[ts].name, got.name)) break true;
            } else false;
            if (!known) try c.reportTok(.impl_mismatch, c.node(got.node).main_token, try c.print("{s} is not a function of trait {s}", .{ got.name, tname }));
        }
    }

    fn sigType(c: *Checker, s: FnSig) Error!Id {
        var buf: std.ArrayList(Id) = .empty;
        for (c.params.items[s.params.start..s.params.end]) |p| try buf.append(c.gpa, p.type);
        return c.pool.func(buf.items, s.ret);
    }

    fn aliasType(c: *Checker, d: u32) Error!Id {
        if (c.decls.items[d].type != types.unknown) return c.decls.items[d].type;
        const n = c.node(c.decls.items[d].node);
        if (c.decls.items[d].resolving) {
            try c.reportTok(.unknown_type, n.main_token, try c.print("type {s} refers to itself", .{c.decls.items[d].name}));
            return types.unknown;
        }
        c.decls.items[d].resolving = true;
        var ctx: TypeCtx = .{};
        const base = try c.resolveType(n.lhs, &ctx);
        c.decls.items[d].resolving = false;
        c.decls.items[d].type = try c.pool.add(.{ .tag = .alias, .a = d, .b = base });
        return c.decls.items[d].type;
    }

    fn resolveType(c: *Checker, i: Index, ctx: *TypeCtx) Error!Id {
        const n = c.node(i);
        switch (n.kind) {
            .type_tuple => {
                var buf: std.ArrayList(Id) = .empty;
                for (c.spanOf(n)) |e| try buf.append(c.gpa, try c.resolveType(e, ctx));
                return c.pool.tuple(buf.items);
            },
            .type_refined => {
                const base = try c.resolveType(n.lhs, ctx);
                try c.refinements.append(c.gpa, .{ .node = i, .base = base });
                return base;
            },
            .type_ref => {},
            else => unreachable,
        }
        const path = c.node(n.lhs);
        const name = c.text(path.main_token);
        const args = c.spanAt(n.rhs);
        if (path.lhs != path.main_token) {
            const full = c.tree.source[c.tree.tokens[path.main_token].start..c.tree.tokens[path.lhs].end];
            try c.reportTok(.unknown_type, path.main_token, try c.print("there is no type named {s}; a use line brings a type in by its own name", .{full}));
            return types.unknown;
        }
        if (prelude.findType(name)) |pt| {
            if (args.len != pt.arity) {
                try c.reportTok(.unknown_type, path.main_token, try c.print("{s} takes {d} type argument{s}, found {d}", .{ name, pt.arity, if (pt.arity == 1) "" else "s", args.len }));
                return types.unknown;
            }
            return switch (pt.kind) {
                .int, .float, .bool, .string, .time, .duration, .capability => primitive(name).?,
                .list => c.pool.list1(.list, try c.resolveType(args[0], ctx)),
                .option => c.pool.list1(.option, try c.resolveType(args[0], ctx)),
                .result => c.pool.result(try c.resolveType(args[0], ctx), try c.resolveType(args[1], ctx)),
                .error_enum => c.preludeEnum(name),
                .handle => {
                    const an = c.node(args[0]);
                    if (an.kind == .type_ref) {
                        const pname = c.text(c.node(an.lhs).main_token);
                        if (c.type_names.get(pname)) |d| if (c.decls.items[d].kind == .process) return c.pool.add(.{ .tag = .handle, .a = d });
                    }
                    try c.reportNode(.unknown_type, args[0], try c.print("Handle takes the name of a process declared in this module", .{}));
                    return types.unknown;
                },
            };
        }
        if (std.mem.eql(u8, name, "Self")) {
            if (ctx.self_ok) return types.self_;
            try c.reportTok(.unknown_type, path.main_token, "Self names the implementing type, so it appears only in a trait");
            return types.unknown;
        }
        if (c.type_names.get(name)) |d| {
            if (args.len != 0) {
                try c.reportTok(.unknown_type, path.main_token, try c.print("{s} takes no type arguments", .{name}));
                return types.unknown;
            }
            const decl = c.decls.items[d];
            switch (decl.kind) {
                .struct_, .enum_, .opaque_, .prelude_enum => return decl.type,
                .alias => return c.aliasType(d),
                .trait => try c.reportTok(.unknown_type, path.main_token, try c.print("{s} is a trait, not a type; take a type parameter with where T: {s}", .{ name, name })),
                .process => try c.reportTok(.unknown_type, path.main_token, try c.print("{s} is a process; a value that reaches it is a Handle({s})", .{ name, name })),
                .supervisor, .recipe => try c.reportTok(.unknown_type, path.main_token, try c.print("{s} is not a type", .{name})),
            }
            return types.unknown;
        }
        if (name.len == 1) {
            if (ctx.generics) |gens| {
                for (gens.items) |g| if (std.mem.eql(u8, c.generics.items[g].name, name)) return c.generics.items[g].type;
                const g: u32 = @intCast(c.generics.items.len);
                try c.generics.append(c.gpa, .{ .name = name, .type = try c.pool.add(.{ .tag = .param, .a = g }) });
                try gens.append(c.gpa, g);
                return c.generics.items[g].type;
            }
        }
        if (ctx.recipe) {
            // A recipe names types its implementer chooses (examples/GAPS.md): opaque here.
            const d = try c.addDecl(.{ .kind = .opaque_, .name = name, .node = i });
            c.decls.items[d].type = try c.pool.add(.{ .tag = .decl, .a = d });
            try c.type_names.put(c.gpa, name, d);
            return c.decls.items[d].type;
        }
        if (name.len == 1) {
            try c.reportTok(.unknown_type, path.main_token, try c.print("{s} is not declared; a type parameter appears only in a function signature", .{name}));
        } else {
            try c.reportTok(.unknown_type, path.main_token, try c.print("there is no type named {s}", .{name}));
        }
        return types.unknown;
    }

    fn preludeEnum(c: *Checker, name: []const u8) Id {
        for (c.decls.items) |d| if (d.kind == .prelude_enum and std.mem.eql(u8, d.name, name)) return d.type;
        unreachable;
    }

    // ---- prelude type strings

    fn parseTs(c: *Checker, s: []const u8, env: *Env) Error!Id {
        var i: usize = 0;
        return c.tsType(s, &i, env);
    }

    fn tsSkip(s: []const u8, i: *usize) void {
        while (i.* < s.len and s[i.*] == ' ') i.* += 1;
    }

    fn tsList(c: *Checker, s: []const u8, i: *usize, env: *Env, buf: *std.ArrayList(Id)) Error!void {
        i.* += 1; // (
        tsSkip(s, i);
        if (s[i.*] == ')') {
            i.* += 1;
            return;
        }
        while (true) {
            try buf.append(c.gpa, try c.tsType(s, i, env));
            tsSkip(s, i);
            if (s[i.*] == ',') {
                i.* += 1;
                continue;
            }
            i.* += 1; // )
            return;
        }
    }

    fn tsType(c: *Checker, s: []const u8, i: *usize, env: *Env) Error!Id {
        tsSkip(s, i);
        var args: std.ArrayList(Id) = .empty;
        if (s[i.*] == '(') {
            try c.tsList(s, i, env, &args);
            return c.pool.tuple(args.items);
        }
        const start = i.*;
        while (i.* < s.len and (std.ascii.isAlphanumeric(s[i.*]) or s[i.*] == '_')) i.* += 1;
        const word = s[start..i.*];
        if (std.mem.eql(u8, word, "fn")) {
            try c.tsList(s, i, env, &args);
            const ret = try c.tsType(s, i, env);
            return c.pool.func(args.items, ret);
        }
        if (std.mem.eql(u8, word, "Handle") or std.mem.eql(u8, word, "Message")) {
            i.* += 3; // (P)
            const p = env.process orelse return types.unknown;
            return c.pool.add(.{ .tag = if (word[0] == 'H') .handle else .message, .a = p });
        }
        if (i.* < s.len and s[i.*] == '(') try c.tsList(s, i, env, &args);
        if (word.len == 1) {
            if (word[0] == 'N') return env.n;
            const slot = &env.letters[word[0] - 'A'];
            if (slot.* == types.unknown) slot.* = try c.pool.fresh(false);
            return slot.*;
        }
        if (std.mem.eql(u8, word, "none")) return types.none;
        if (std.mem.eql(u8, word, "Reply")) return env.reply;
        if (std.mem.eql(u8, word, "List")) return c.pool.list1(.list, args.items[0]);
        if (std.mem.eql(u8, word, "Option")) return c.pool.list1(.option, args.items[0]);
        if (std.mem.eql(u8, word, "Result")) return c.pool.result(args.items[0], args.items[1]);
        if (std.mem.eql(u8, word, "FsError") or std.mem.eql(u8, word, "AskError")) return c.preludeEnum(word);
        return primitive(word) orelse types.unknown;
    }

    fn recvMatches(c: *Checker, recv: []const u8, t: Id) bool {
        const head = recv[0 .. std.mem.indexOfScalar(u8, recv, '(') orelse recv.len];
        const b = c.bt(t);
        if (std.mem.eql(u8, head, "Int")) return b.tag == .int or c.pool.isIntLiteralVar(t);
        if (std.mem.eql(u8, head, "List")) return b.tag == .list;
        if (std.mem.eql(u8, head, "Handle")) return b.tag == .handle;
        const p = primitive(head) orelse return false;
        return c.pool.base(t) == p;
    }

    // ---- pass 3: bodies

    fn checkModule(c: *Checker) Error!void {
        for (c.refinements.items) |r| try c.checkRefinement(r);
        for (c.items()) |it| {
            const n = c.node(it);
            switch (n.kind) {
                .fn_decl => try c.checkFn(c.sig_of_node.get(it).?),
                .impl_decl => for (c.spanAt(n.rhs)) |f| {
                    if (c.sig_of_node.get(f)) |s| try c.checkFn(s);
                },
                .process_decl => try c.checkProcess(it),
                .supervisor_decl => try c.checkSupervisor(it),
                .recipe_decl => {
                    const r = c.tree.extraData(ast.Recipe, n.lhs);
                    for (c.tree.span(r.sigs_start, r.sigs_end)) |s| try c.checkFn(c.sig_of_node.get(s).?);
                    for (c.tree.span(r.tests_start, r.tests_end)) |t| try c.checkTest(t);
                },
                .never => try c.checkNever(it),
                .test_decl, .test_rejects, .property => try c.checkTest(it),
                else => {},
            }
        }
    }

    fn checkRefinement(c: *Checker, r: Refinement) Error!void {
        const saved = c.beginFrame(.refinement, "");
        c.frame.refine_value = r.base;
        const mark = c.pushScope();
        try c.bind("value", r.base, .param, c.node(r.node).main_token);
        c.bindings.items[mark].used = true;
        _ = try c.expr(c.node(r.node).rhs, types.bool_);
        try c.popScope(mark);
        try c.endFrame(saved);
    }

    fn checkFn(c: *Checker, si: u32) Error!void {
        const s = c.sigs.items[si];
        const n = c.node(s.node);
        const sig = c.tree.extraData(ast.Signature, n.lhs);
        const saved = c.beginFrame(.function, s.name);
        c.frame.ret = s.ret;
        c.frame.has_ret = true;
        const mark = c.pushScope();
        for (c.params.items[s.params.start..s.params.end]) |p| {
            try c.bind(p.name, p.type, if (p.inout) .inout else .param, c.node(p.node).main_token);
            const pn = c.node(p.node);
            if (pn.rhs != 0) _ = try c.expr(pn.rhs, p.type);
        }
        for (c.tree.span(sig.contracts_start, sig.contracts_end)) |k| {
            const kn = c.node(k);
            const inner = c.pushScope();
            c.frame.kind = .contract;
            c.frame.result = if (kn.kind == .ensures) s.ret else null;
            c.frame.old_ok = kn.kind == .ensures;
            _ = try c.expr(kn.lhs, types.bool_);
            c.frame.kind = .function;
            c.frame.result = null;
            c.frame.old_ok = false;
            try c.popScope(inner);
        }
        if (n.kind == .fn_decl) {
            const body = c.tree.extraData(ast.FnBody, n.rhs);
            try c.bodyLimit(n.main_token, s.name, body.open_token, body.end_token);
            _ = try c.blockValue(c.tree.span(body.start, body.end), s.ret);
        }
        try c.popScope(mark);
        try c.endFrame(saved);
    }

    fn processDecl(c: *Checker, it: Index) ?u32 {
        const d = c.type_names.get(c.text(c.node(it).main_token)) orelse return null;
        return if (c.decls.items[d].node == it) d else null;
    }

    fn bindParams(c: *Checker, r: Range) Error!void {
        for (c.params.items[r.start..r.end]) |p| try c.bind(p.name, p.type, if (p.inout) .inout else .param, c.node(p.node).main_token);
    }

    fn checkProcess(c: *Checker, it: Index) Error!void {
        const d = c.processDecl(it) orelse return;
        const n = c.node(it);
        const data = c.tree.extraData(ast.Process, n.lhs);
        const decl = c.decls.items[d];
        const state_t = try c.pool.add(.{ .tag = .state, .a = d });
        const message_t = try c.pool.add(.{ .tag = .message, .a = d });

        var saved = c.beginFrame(.function, decl.name);
        var mark = c.pushScope();
        try c.bindParams(decl.params);
        for (c.fields.items[decl.fields.start..decl.fields.end]) |f| {
            const init = c.node(f.node).rhs;
            if (init != 0) _ = try c.expr(init, f.type);
        }
        try c.popScope(mark);
        try c.endFrame(saved);

        for (c.tree.span(data.invariants_start, data.invariants_end)) |inv| {
            saved = c.beginFrame(.invariant, decl.name);
            c.frame.old_ok = true;
            mark = c.pushScope();
            try c.bindParams(decl.params);
            try c.bind("state", state_t, .state, c.node(inv).main_token);
            _ = try c.expr(c.node(inv).rhs, types.bool_);
            try c.popScope(mark);
            try c.endFrame(saved);
        }

        const update = c.node(data.update);
        try c.bodyLimit(update.main_token, try c.print("update in {s}", .{decl.name}), update.main_token, update.rhs);
        saved = c.beginFrame(.update, decl.name);
        mark = c.pushScope();
        try c.bindParams(decl.params);
        try c.bind("state", state_t, .state, update.main_token);
        try c.bind("message", message_t, .state, update.main_token);
        _ = try c.caseCheck(update.lhs, types.unknown, .update);
        try c.popScope(mark);
        try c.endFrame(saved);
    }

    fn checkSupervisor(c: *Checker, it: Index) Error!void {
        const n = c.node(it);
        const d = c.type_names.get(c.text(n.main_token)) orelse return;
        if (c.decls.items[d].node != it) return;
        const saved = c.beginFrame(.supervisor, c.decls.items[d].name);
        const mark = c.pushScope();
        try c.bindParams(c.decls.items[d].params);
        for (c.spanAt(n.rhs)) |ch| {
            const cn = c.node(ch);
            const data = c.tree.extraData(ast.Child, cn.lhs);
            const pname = c.text(cn.main_token);
            const args = c.tree.span(data.args_start, data.args_end);
            const pd = c.type_names.get(pname);
            if (pd == null or c.decls.items[pd.?].kind != .process) {
                try c.reportTok(.unknown_name, cn.main_token, try c.print("{s} is not a process declared in this module", .{pname}));
                for (args) |a| _ = try c.expr(a, types.unknown);
            } else {
                try c.positionalArgs(ch, pname, null, args, c.decls.items[pd.?].params, &.{}, &.{});
            }
            const atom = c.text(data.restart);
            const ok = for ([_][]const u8{ ":always", ":on_crash", ":never" }) |a| {
                if (std.mem.eql(u8, a, atom)) break true;
            } else false;
            if (!ok) try c.reportTok(.bad_named_arg, data.restart, try c.print("restart: takes :always, :on_crash, or :never, not {s}", .{atom}));
            if (data.per != 0) _ = try c.expr(data.per, types.duration);
        }
        try c.popScope(mark);
        try c.endFrame(saved);
    }

    fn checkTest(c: *Checker, it: Index) Error!void {
        const n = c.node(it);
        const saved = c.beginFrame(.test_block, c.text(n.main_token));
        c.frame.in_test = true;
        c.frame.in_rejects = n.kind == .test_rejects;
        const mark = c.pushScope();
        if (n.kind == .property) {
            c.frame.in_property = true;
            try c.comprehension(n.lhs, false);
        } else {
            try c.blockStmts(c.spanOf(n));
        }
        try c.popScope(mark);
        try c.endFrame(saved);
    }

    fn checkNever(c: *Checker, it: Index) Error!void {
        const n = c.node(it);
        const saved = c.beginFrame(.never, c.text(n.lhs));
        c.frame.in_never = true;
        const body = c.node(n.rhs);
        if (body.kind == .comprehension) {
            try c.comprehension(n.rhs, true);
        } else if (body.kind == .call and c.node(body.lhs).kind == .name_ref and std.mem.eql(u8, c.text(c.node(body.lhs).main_token), "flows")) {
            // The rule's names are checked by caps.zig, which owns flows.
            try c.flows.append(c.gpa, n.rhs);
            c.node_types[n.rhs] = types.bool_;
        } else {
            _ = try c.expr(n.rhs, types.bool_);
        }
        try c.endFrame(saved);
    }

    fn comprehension(c: *Checker, i: Index, is_never: bool) Error!void {
        const data = c.tree.extraData(ast.Comprehension, c.node(i).lhs);
        const mark = c.pushScope();
        for (c.tree.span(data.gens_start, data.gens_end)) |g| {
            const gn = c.node(g);
            const t = try c.expr(gn.lhs, types.unknown);
            try c.bind(c.text(gn.main_token), try c.elementOf(gn.lhs, t), .let, gn.main_token);
        }
        if (data.guard != 0) _ = try c.expr(data.guard, types.bool_);
        const body = c.tree.span(data.body_start, data.body_end);
        if (is_never) _ = try c.blockValue(body, types.bool_) else try c.blockStmts(body);
        try c.popScope(mark);
    }

    /// The element type of something a `for` or a generator iterates.
    fn elementOf(c: *Checker, at: Index, t: Id) Error!Id {
        const b = c.bt(t);
        switch (b.tag) {
            .list => return b.a,
            .unknown, .never => return types.unknown,
            .variable => {
                const elem = try c.pool.fresh(false);
                _ = c.pool.unify(t, try c.pool.list1(.list, elem));
                return elem;
            },
            else => {
                try c.reportNode(.mismatch, at, try c.print("for iterates a List or a range; this is {s}", .{try c.tn(t)}));
                return types.unknown;
            },
        }
    }

    // ---- the laws (chapter 2) that are not checked where they happen

    /// The 1-based line of a byte offset.
    fn lineOf(c: *Checker, offset: u32) u32 {
        const starts = c.line_starts.items;
        var lo: usize = 0;
        var hi: usize = starts.len;
        while (hi - lo > 1) {
            const mid = (lo + hi) / 2;
            if (starts[mid] <= offset) lo = mid else hi = mid;
        }
        return @intCast(lo + 1);
    }

    /// The source of an expression, for a message: from its first token to a `,` or a
    /// closing delimiter it did not open, a comment, or the end of the line.
    fn exprText(c: *Checker, i: Index) []const u8 {
        const src = c.tree.source;
        const start = c.tree.tokens[c.firstToken(i)].start;
        var depth: u32 = 0;
        var in_string = false;
        var k: usize = start;
        while (k < src.len) : (k += 1) {
            const ch = src[k];
            if (in_string) {
                if (ch == '\\') k += 1 else if (ch == '"') in_string = false;
                continue;
            }
            switch (ch) {
                '"' => in_string = true,
                '(', '[', '{' => depth += 1,
                ')', ']', '}' => {
                    if (depth == 0) break;
                    depth -= 1;
                },
                ',' => if (depth == 0) break,
                '\n', '#' => break,
                else => {},
            }
        }
        return std.mem.trimEnd(u8, src[start..k], " \t\r");
    }

    fn pathText(c: *Checker, path: Index) []const u8 {
        const p = c.node(path);
        return c.tree.source[c.tree.tokens[p.main_token].start..c.tree.tokens[p.lhs].end];
    }

    fn paramLimit(c: *Checker, tok: u32, name: []const u8, params: Range) Error!void {
        if (params.len() > 6) try c.reportTok(.too_many_params, tok, try c.print("{s} takes {d} parameters and the limit is 6; group them in a struct.", .{ name, params.len() }));
    }

    fn bodyLimit(c: *Checker, tok: u32, name: []const u8, open: u32, end: u32) Error!void {
        const lines = c.lineOf(c.tree.tokens[end].start) -| c.lineOf(c.tree.tokens[open].start) -| 1;
        if (lines > 70) try c.reportTok(.body_lines, tok, try c.print("{s} has a body of {d} lines and the limit is 70; split it into named functions.", .{ name, lines }));
    }

    fn nestEnter(c: *Checker, tok: u32) Error!void {
        c.frame.nest += 1;
        if (c.frame.nest > 3 and !c.frame.nest_reported) {
            c.frame.nest_reported = true;
            try c.reportTok(.nesting, tok, try c.print("this {s} is nested {d} deep in {s}; the limit is 3, so move the inner block into its own function.", .{ c.text(tok), c.frame.nest, c.frame.name }));
        }
    }

    fn useBinding(c: *Checker, b: u32, tok: u32) Error!void {
        c.bindings.items[b].used = true;
        const binding = c.bindings.items[b];
        if (binding.kind != .var_) return;
        if (binding.anon_depth < c.frame.anon_depth) {
            try c.reportTok(.var_captured, tok, try c.print("{s} is a var and cannot be captured by the anonymous function; bind a plain name first.", .{binding.name}));
        } else if (c.process_args > 0) {
            try c.reportTok(.var_to_process, tok, try c.print("{s} is a var and cannot be sent to a process; bind a plain name first.", .{binding.name}));
        }
    }

    fn checkModuleLaws(c: *Checker) Error!void {
        const src = c.tree.source;
        var lines: u32 = @intCast(c.line_starts.items.len);
        if (src.len > 0 and src[src.len - 1] == '\n') lines -= 1;
        if (lines > 500) try c.report(.file_lines, c.line_starts.items[500], try c.print("this file is {d} lines long and the limit is 500; split it into modules.", .{lines}));

        var module_path: []const u8 = "";
        for (c.items()) |it| {
            const n = c.node(it);
            switch (n.kind) {
                .module_decl => module_path = c.pathText(n.lhs),
                // One file sees one module; a driver that loads imports calls useCycle.
                .use => if (std.mem.eql(u8, c.pathText(n.lhs), module_path)) {
                    try c.reportTok(.use_cycle, n.main_token, try c.print("{s} uses itself; a module never imports its own path.", .{module_path}));
                },
                .verified => try c.reportTok(.hand_verified, n.main_token, "the verified: line was written by hand; delete it and let the toolchain compute it."),
                else => {},
            }
        }

        for (c.sigs.items, 0..) |s, si| {
            if (s.kind == .trait or c.tripped[si]) continue;
            const n = c.node(s.node);
            const sig = c.tree.extraData(ast.Signature, n.lhs);
            for (c.tree.span(sig.contracts_start, sig.contracts_end)) |k| {
                const kn = c.node(k);
                if (kn.kind != .requires) continue;
                try c.reportTok(.requires_untested, n.main_token, try c.print("{s} has requires {s}, but no test rejects trips it.", .{ s.name, c.exprText(kn.lhs) }));
                break;
            }
        }

        for (c.decls.items) |d| {
            if (d.kind != .process) continue;
            var supervised = false;
            for (c.items()) |it| {
                const n = c.node(it);
                if (n.kind != .supervisor_decl) continue;
                for (c.spanAt(n.rhs)) |ch| {
                    if (std.mem.eql(u8, c.text(c.node(ch).main_token), d.name)) supervised = true;
                }
            }
            if (!supervised) try c.reportTok(.unsupervised, c.node(d.node).main_token, try c.print("{s} is not a child of any supervisor; add a supervisor with child {s}.", .{ d.name, d.name }));
        }
    }

    // ---- exhaustiveness: Maranget's usefulness over the arms without guards

    const Ctor = struct {
        name: []const u8,
        kind: enum { variant, some, none, ok, err, tuple, true_, false_ },
        fields: []const Id = &.{},
        field_names: []const []const u8 = &.{},
    };

    fn isWild(c: *Checker, p: Index) bool {
        if (p == 0) return true;
        const k = c.node(p).kind;
        return k == .pat_wildcard or k == .pat_bind;
    }

    /// Every constructor of a closed type, or null for a type with unbounded values.
    fn constructors(c: *Checker, t: Id) Error!?[]const Ctor {
        const b = c.bt(t);
        var out: std.ArrayList(Ctor) = .empty;
        switch (b.tag) {
            .bool => {
                try out.append(c.gpa, .{ .name = "true", .kind = .true_ });
                try out.append(c.gpa, .{ .name = "false", .kind = .false_ });
            },
            .option => {
                try out.append(c.gpa, .{ .name = "Some", .kind = .some, .fields = try c.gpa.dupe(Id, &.{b.a}) });
                try out.append(c.gpa, .{ .name = "None", .kind = .none });
            },
            .result => {
                try out.append(c.gpa, .{ .name = "Ok", .kind = .ok, .fields = try c.gpa.dupe(Id, &.{b.a}) });
                try out.append(c.gpa, .{ .name = "Error", .kind = .err, .fields = try c.gpa.dupe(Id, &.{b.b}) });
            },
            .tuple => try out.append(c.gpa, .{ .name = "", .kind = .tuple, .fields = try c.gpa.dupe(Id, c.pool.elems(b)) }),
            .decl, .message => {
                const d = c.decls.items[b.a];
                const one = [_]Range{d.fields};
                const ranges: []const Range = switch (d.kind) {
                    .enum_, .prelude_enum, .process => &.{},
                    .struct_ => &one,
                    else => return null,
                };
                if (ranges.len == 1) {
                    try out.append(c.gpa, try c.ctorOf(d.name, d.fields));
                } else for (d.variants.start..d.variants.end) |v| {
                    try out.append(c.gpa, try c.ctorOf(c.variants.items[v].name, c.variants.items[v].fields));
                }
            },
            else => return null,
        }
        return out.items;
    }

    fn ctorOf(c: *Checker, name: []const u8, fields: Range) Error!Ctor {
        const defs = c.fields.items[fields.start..fields.end];
        const ts = try c.gpa.alloc(Id, defs.len);
        const names = try c.gpa.alloc([]const u8, defs.len);
        for (defs, 0..) |f, k| {
            ts[k] = f.type;
            names[k] = f.name;
        }
        return .{ .name = name, .kind = .variant, .fields = ts, .field_names = names };
    }

    fn headMatches(c: *Checker, p: Index, k: Ctor) bool {
        if (c.isWild(p)) return false;
        const pn = c.node(p);
        return switch (pn.kind) {
            .pat_variant, .pat_record => std.mem.eql(u8, c.text(pn.main_token), k.name),
            .pat_tuple => k.kind == .tuple,
            .pat_literal => switch (c.tree.tokens[pn.main_token].kind) {
                .kw_true => k.kind == .true_,
                .kw_false => k.kind == .false_,
                else => false,
            },
            else => false,
        };
    }

    /// The patterns under constructor `k` in `p`, one per field; 0 is a wildcard.
    fn subPatterns(c: *Checker, p: Index, k: Ctor) Error![]u32 {
        const out = try c.gpa.alloc(u32, k.fields.len);
        @memset(out, 0);
        if (c.isWild(p)) return out;
        const pn = c.node(p);
        switch (pn.kind) {
            .pat_variant => if (out.len == 1) {
                out[0] = pn.lhs;
            },
            .pat_record => for (c.spanOf(pn)) |pf| {
                const fname = c.text(c.node(pf).main_token);
                for (k.field_names, 0..) |nm, idx| {
                    if (std.mem.eql(u8, nm, fname)) out[idx] = c.node(pf).lhs;
                }
            },
            .pat_tuple => {
                const elems = c.spanOf(pn);
                if (elems.len == out.len) @memcpy(out, elems);
            },
            else => {},
        }
        return out;
    }

    fn defaultRows(c: *Checker, rows: []const []const u32) Error![]const []const u32 {
        var out: std.ArrayList([]const u32) = .empty;
        for (rows) |r| if (c.isWild(r[0])) try out.append(c.gpa, r[1..]);
        return out.items;
    }

    fn prepend(c: *Checker, head: []const u8, rest: []const []const u8) Error![]const []const u8 {
        const out = try c.gpa.alloc([]const u8, rest.len + 1);
        out[0] = head;
        @memcpy(out[1..], rest);
        return out;
    }

    fn renderCtor(c: *Checker, k: Ctor, args: []const []const u8) Error![]const u8 {
        switch (k.kind) {
            .true_, .false_, .none => return k.name,
            .some, .ok, .err => return c.print("{s}({s})", .{ k.name, args[0] }),
            .tuple, .variant => {
                if (k.kind == .variant and args.len == 0) return k.name;
                var aw: std.Io.Writer.Allocating = .init(c.gpa);
                const w = &aw.writer;
                w.writeAll(k.name) catch return error.OutOfMemory;
                w.writeAll("(") catch return error.OutOfMemory;
                for (args, 0..) |a, idx| {
                    if (idx > 0) w.writeAll(", ") catch return error.OutOfMemory;
                    if (k.kind == .variant and args.len > 1) w.print("{s}: ", .{k.field_names[idx]}) catch return error.OutOfMemory;
                    w.writeAll(a) catch return error.OutOfMemory;
                }
                w.writeAll(")") catch return error.OutOfMemory;
                return aw.toOwnedSlice();
            },
        }
    }

    /// A witness no row matches, one pattern per column, or null when the rows cover
    /// every value of `tys`.
    fn uncovered(c: *Checker, rows: []const []const u32, tys: []const Id) Error!?[]const []const u8 {
        if (tys.len == 0) return if (rows.len == 0) &.{} else null;
        const ctors = try c.constructors(tys[0]) orelse {
            const w = try c.uncovered(try c.defaultRows(rows), tys[1..]) orelse return null;
            return try c.prepend("_", w);
        };
        for (ctors) |k| {
            const present = for (rows) |r| {
                if (c.headMatches(r[0], k)) break true;
            } else false;
            if (present) continue;
            const w = try c.uncovered(try c.defaultRows(rows), tys[1..]) orelse return null;
            const blanks = try c.gpa.alloc([]const u8, k.fields.len);
            @memset(blanks, "_");
            return try c.prepend(try c.renderCtor(k, blanks), w);
        }
        for (ctors) |k| {
            var spec: std.ArrayList([]const u32) = .empty;
            for (rows) |r| {
                if (!c.isWild(r[0]) and !c.headMatches(r[0], k)) continue;
                const sub = try c.subPatterns(r[0], k);
                const row = try c.gpa.alloc(u32, sub.len + r.len - 1);
                @memcpy(row[0..sub.len], sub);
                @memcpy(row[sub.len..], r[1..]);
                try spec.append(c.gpa, row);
            }
            const sub_tys = try c.gpa.alloc(Id, k.fields.len + tys.len - 1);
            @memcpy(sub_tys[0..k.fields.len], k.fields);
            @memcpy(sub_tys[k.fields.len..], tys[1..]);
            if (try c.uncovered(spec.items, sub_tys)) |w| {
                return try c.prepend(try c.renderCtor(k, w[0..k.fields.len]), w[k.fields.len..]);
            }
        }
        return null;
    }

    fn joinAnd(c: *Checker, names: []const []const u8) Error![]const u8 {
        return switch (names.len) {
            0 => "",
            1 => names[0],
            2 => c.print("{s} and {s}", .{ names[0], names[1] }),
            else => blk: {
                const head = try std.mem.join(c.gpa, ", ", names[0 .. names.len - 1]);
                break :blk c.print("{s}, and {s}", .{ head, names[names.len - 1] });
            },
        };
    }

    fn caseLaws(c: *Checker, s: Index, subject: Id) Error!void {
        const n = c.node(s);
        const b = c.bt(subject);
        if (b.tag == .unknown or b.tag == .variable) return;
        const arms = c.spanAt(n.rhs);
        const closed = switch (b.tag) {
            .option, .result, .message => true,
            .decl => c.decls.items[b.a].kind == .enum_ or c.decls.items[b.a].kind == .prelude_enum,
            else => false,
        };
        if (closed) {
            const ctors = (try c.constructors(subject)).?;
            for (arms) |a| {
                const pat = c.node(a).lhs;
                if (!c.isWild(pat)) continue;
                var hidden: std.ArrayList([]const u8) = .empty;
                for (ctors) |k| {
                    const named = for (arms) |other| {
                        if (other != a and c.headMatches(c.node(other).lhs, k)) break true;
                    } else false;
                    if (!named) try hidden.append(c.gpa, k.name);
                }
                const arm = c.text(c.node(pat).main_token);
                const what = if (hidden.items.len == 0)
                    try c.print("the {s} arm catches no variant of {s}; remove it.", .{ arm, try c.tn(subject) })
                else
                    try c.print("the {s} arm hides {s}; name each variant of {s}.", .{ arm, try c.joinAnd(hidden.items), try c.tn(subject) });
                try c.reportTok(.catch_all, c.node(pat).main_token, what);
                return;
            }
        }
        var rows: std.ArrayList([]const u32) = .empty;
        for (arms) |a| {
            const an = c.node(a);
            if (c.tree.extraData(ast.Arm, an.rhs).guard != 0) continue;
            try rows.append(c.gpa, try c.gpa.dupe(u32, &.{an.lhs}));
        }
        if (try c.uncovered(rows.items, &.{subject})) |w| {
            try c.reportTok(.not_exhaustive, n.main_token, try c.print("this case does not cover {s}; add an arm for it.", .{w[0]}));
        }
    }

    // ---- statements

    fn blockStmts(c: *Checker, stmts: []const u32) Error!void {
        for (stmts) |s| try c.stmt(s);
    }

    /// The last statement of a body is its value (grammar, Session 5).
    fn blockValue(c: *Checker, stmts: []const u32, expected: Id) Error!Id {
        if (stmts.len == 0) return types.none;
        for (stmts[0 .. stmts.len - 1]) |s| try c.stmt(s);
        return c.stmtValue(stmts[stmts.len - 1], expected);
    }

    fn stmtValue(c: *Checker, s: Index, expected: Id) Error!Id {
        // Where no value is wanted, the last line is one more statement.
        if (expected == types.none) {
            try c.stmt(s);
            return types.none;
        }
        const n = c.node(s);
        switch (n.kind) {
            .expr_stmt => return c.expr(n.lhs, expected),
            .if_stmt => return c.ifCheck(s, expected, true),
            .case_stmt => return c.caseCheck(s, expected, .value),
            .return_stmt => {
                try c.stmt(s);
                return c.expectType(s, expected, if (n.rhs == 0) types.never else types.none);
            },
            .break_stmt => {
                try c.stmt(s);
                return types.never;
            },
            else => {
                try c.stmt(s);
                return c.expectType(s, expected, types.none);
            },
        }
    }

    fn stmt(c: *Checker, s: Index) Error!void {
        const n = c.node(s);
        switch (n.kind) {
            .expr_stmt => {
                const t = try c.expr(n.lhs, types.unknown);
                const b = c.bt(t);
                // A test rejects drops its call's value on purpose: the call is meant to trip.
                if ((b.tag == .result or b.tag == .option) and !c.frame.in_rejects) {
                    try c.reportNode(.unconsumed, n.lhs, try c.print("the {s} from {s} is dropped; match it with case or pass it up with try.", .{ if (b.tag == .result) "Result" else "Option", c.exprText(n.lhs) }));
                }
            },
            .binding => try c.bindingStmt(s),
            .var_binding => {
                const t = try c.boundValue(s);
                try c.bind(c.text(n.main_token), t, .var_, n.main_token);
            },
            .assign => try c.assignStmt(s),
            .return_stmt => {
                if (!c.frame.has_ret) {
                    try c.reportTok(.misplaced, n.main_token, "return leaves a function, so it appears only in a function body");
                    _ = try c.expr(n.lhs, types.unknown);
                } else {
                    _ = try c.expr(n.lhs, c.frame.ret);
                }
                if (n.rhs != 0) _ = try c.expr(n.rhs, types.bool_);
            },
            .for_stmt => try c.forStmt(s),
            .if_stmt => _ = try c.ifCheck(s, types.unknown, false),
            .case_stmt => _ = try c.caseCheck(s, types.unknown, .stmt),
            .assert_stmt => {
                if (!c.frame.in_test) try c.reportTok(.misplaced, n.main_token, "assert belongs in a test, a test rejects, or a property");
                _ = try c.expr(n.lhs, types.bool_);
            },
            .break_stmt => if (c.frame.loop_depth == 0) try c.reportTok(.misplaced, n.main_token, "break leaves a for, so it appears only inside one"),
            else => _ = try c.expr(s, types.unknown),
        }
    }

    fn bindingStmt(c: *Checker, s: Index) Error!void {
        const n = c.node(s);
        const name = c.text(n.main_token);
        if (c.lookup(name)) |b| {
            const kind = c.bindings.items[b].kind;
            if (kind == .var_ or kind == .inout) {
                // `x = e` on a var is an assignment; the two are the same text.
                _ = try c.expr(n.lhs, c.bindings.items[b].type);
                return;
            }
        }
        const t = try c.boundValue(s);
        try c.bind(name, t, .let, n.main_token);
    }

    /// The value of `x = e` or `var x = e`. An anonymous function there is stored.
    fn boundValue(c: *Checker, s: Index) Error!Id {
        const n = c.node(s);
        if (c.node(n.lhs).kind == .anon_fn) {
            const name = c.text(n.main_token);
            try c.reportTok(.anon_stored, c.node(n.lhs).main_token, try c.print("an anonymous function is bound to {s}; pass it straight into {s} instead.", .{ name, c.consumerOf(s, name) }));
            c.anon_ok = n.lhs;
        }
        return c.expr(n.lhs, types.unknown);
    }

    /// The first call after `s` that passes `name` as an argument, to name in a message.
    fn consumerOf(c: *Checker, s: Index, name: []const u8) []const u8 {
        for (c.tree.nodes[s + 1 ..]) |call| {
            if (call.kind != .call and call.kind != .member_call) continue;
            for (c.spanAt(call.rhs)) |a| {
                const an = c.node(a);
                if (an.kind != .name_ref or !std.mem.eql(u8, c.text(an.main_token), name)) continue;
                if (call.kind == .member_call) return c.text(call.main_token);
                const callee = c.node(call.lhs);
                if (callee.kind == .name_ref) return c.text(callee.main_token);
            }
        }
        return "the call that uses it";
    }

    fn assignStmt(c: *Checker, s: Index) Error!void {
        const n = c.node(s);
        const op = c.text(n.main_token);
        const compound = !std.mem.eql(u8, op, "=");
        const place_t = try c.place(n.lhs, compound);
        const t = try c.expr(n.rhs, place_t);
        if (compound) try c.defer_(.{ .kind = .numeric, .node = s, .type = t });
    }

    /// The type of an assignable place; its root must be a var, an inout, or state.
    fn place(c: *Checker, i: Index, reads: bool) Error!Id {
        const n = c.node(i);
        switch (n.kind) {
            .name_ref => {
                const name = c.text(n.main_token);
                const b = c.lookup(name) orelse {
                    try c.reportTok(.unknown_name, n.main_token, try c.print("there is no {s} in scope", .{name}));
                    return types.unknown;
                };
                if (reads) {
                    try c.useBinding(b, n.main_token);
                } else if (c.bindings.items[b].kind == .var_ and c.bindings.items[b].anon_depth < c.frame.anon_depth) {
                    try c.reportTok(.var_captured, n.main_token, try c.print("{s} is a var and cannot be captured by the anonymous function; bind a plain name first.", .{name}));
                }
                const binding = &c.bindings.items[b];
                switch (binding.kind) {
                    .var_, .inout, .state => {},
                    else => try c.reportTok(.not_assignable, n.main_token, try c.print("{s} is not a var, so it cannot be assigned; bind a new name or make it var {s}", .{ name, name })),
                }
                c.node_types[i] = binding.type;
                return binding.type;
            },
            .member => {
                const obj = try c.place(n.lhs, true);
                const t = try c.fieldOf(i, obj, c.text(n.main_token)) orelse {
                    try c.reportTok(.no_member, n.main_token, try c.print("{s} has no field {s}", .{ try c.tn(obj), c.text(n.main_token) }));
                    return types.unknown;
                };
                c.node_types[i] = t;
                return t;
            },
            else => {
                try c.reportNode(.not_assignable, i, "only a name or a field path can be assigned");
                return types.unknown;
            },
        }
    }

    fn fieldOf(c: *Checker, _: Index, obj: Id, name: []const u8) Error!?Id {
        const b = c.bt(obj);
        if (b.tag == .unknown) return types.unknown;
        // An opaque type (a recipe's or a use line's) has fields tier 1 cannot see.
        if (b.tag == .decl and c.decls.items[b.a].kind == .opaque_) return types.unknown;
        const range: Range = switch (b.tag) {
            .decl => if (c.decls.items[b.a].kind == .struct_) c.decls.items[b.a].fields else return null,
            .state => c.decls.items[b.a].fields,
            else => return null,
        };
        for (c.fields.items[range.start..range.end]) |f| if (std.mem.eql(u8, f.name, name)) return f.type;
        return null;
    }

    fn forStmt(c: *Checker, s: Index) Error!void {
        const n = c.node(s);
        const iter = try c.expr(n.lhs, types.unknown);
        const elem = try c.elementOf(n.lhs, iter);
        const mark = c.pushScope();
        c.frame.loop_depth += 1;
        try c.nestEnter(c.firstToken(s));
        try c.bind(c.text(n.main_token), elem, .let, n.main_token);
        try c.blockStmts(c.spanAt(n.rhs));
        c.frame.nest -= 1;
        c.frame.loop_depth -= 1;
        try c.popScope(mark);
    }

    fn ifCheck(c: *Checker, s: Index, expected: Id, value: bool) Error!Id {
        const n = c.node(s);
        const data = c.tree.extraData(ast.If, n.rhs);
        const has_else = n.kind == .if_expr or data.else_end > data.else_start;
        // Names bound by `is` in the condition are in scope for the then-block only.
        const mark = c.pushScope();
        _ = try c.expr(n.lhs, types.bool_);
        try c.nestEnter(n.main_token);
        const then_mark = c.pushScope();
        const then_stmts = c.tree.span(data.then_start, data.then_end);
        var t: Id = types.none;
        if (value and has_else) t = try c.blockValue(then_stmts, expected) else try c.blockStmts(then_stmts);
        try c.popScope(then_mark);
        try c.popScope(mark);
        if (has_else) {
            const else_mark = c.pushScope();
            const else_stmts = c.tree.span(data.else_start, data.else_end);
            if (value) {
                const e = try c.blockValue(else_stmts, if (expected == types.unknown) t else expected);
                if (t == types.never) t = e;
            } else try c.blockStmts(else_stmts);
            try c.popScope(else_mark);
        }
        c.frame.nest -= 1;
        if (value and !has_else) return c.expectType(s, expected, types.none);
        return if (value) t else types.none;
    }

    const CaseMode = enum { stmt, value, update };

    fn caseCheck(c: *Checker, s: Index, expected: Id, mode: CaseMode) Error!Id {
        const n = c.node(s);
        const subject = try c.expr(n.lhs, types.unknown);
        var result = expected;
        const is_update = mode == .update and c.pool.get(c.pool.resolve(subject)).tag == .message;
        try c.nestEnter(n.main_token);
        for (c.spanAt(n.rhs)) |a| {
            const an = c.node(a);
            const data = c.tree.extraData(ast.Arm, an.rhs);
            const mark = c.pushScope();
            try c.pattern(an.lhs, subject);
            if (data.guard != 0) _ = try c.expr(data.guard, types.bool_);
            const body = c.tree.span(data.body_start, data.body_end);
            switch (mode) {
                .stmt => try c.blockStmts(body),
                .value => {
                    const t = try c.blockValue(body, result);
                    if (result == types.unknown or c.pool.resolve(result) == types.never) result = t;
                },
                .update => if (is_update) {
                    _ = try c.blockValue(body, c.replyOfPattern(an.lhs, subject) orelse types.none);
                } else try c.blockStmts(body),
            }
            try c.popScope(mark);
        }
        c.frame.nest -= 1;
        try c.caseLaws(s, subject);
        return if (mode == .value) result else types.none;
    }

    fn replyOfPattern(c: *Checker, pat: Index, subject: Id) ?Id {
        const pn = c.node(pat);
        if (pn.kind != .pat_variant and pn.kind != .pat_record) return null;
        const v = c.findVariant(c.text(pn.main_token), subject) orelse return null;
        return c.variants.items[v].reply;
    }

    // ---- patterns

    fn pattern(c: *Checker, i: Index, subject: Id) Error!void {
        const n = c.node(i);
        c.node_types[i] = subject;
        switch (n.kind) {
            .pat_wildcard => {},
            .pat_bind => try c.bind(c.text(n.main_token), subject, .pattern, n.main_token),
            .pat_literal => {
                const t: Id = switch (c.tree.tokens[n.main_token].kind) {
                    .int => blk: {
                        const v = try c.pool.fresh(true);
                        try c.defer_(.{ .kind = .literal, .node = i, .type = v });
                        break :blk v;
                    },
                    .float => types.float64,
                    .string => types.string,
                    else => types.bool_,
                };
                if (!c.pool.unify(subject, t)) try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} cannot match {s}", .{ c.text(n.main_token), try c.tn(subject) }));
            },
            .pat_variant => try c.variantPattern(i, subject),
            .pat_record => try c.recordPattern(i, subject),
            .pat_tuple => {
                const elems = c.spanOf(n);
                var b = c.bt(subject);
                if (b.tag == .variable) {
                    var buf: std.ArrayList(Id) = .empty;
                    for (elems) |_| try buf.append(c.gpa, try c.pool.fresh(false));
                    _ = c.pool.unify(subject, try c.pool.tuple(buf.items));
                    b = c.bt(subject);
                }
                if (b.tag == .unknown) {
                    for (elems) |e| try c.pattern(e, types.unknown);
                } else if (b.tag != .tuple or b.b != elems.len) {
                    try c.reportTok(.bad_pattern, n.main_token, try c.print("a tuple of {d} cannot match {s}", .{ elems.len, try c.tn(subject) }));
                    for (elems) |e| try c.pattern(e, types.unknown);
                } else {
                    for (elems, 0..) |e, k| try c.pattern(e, c.pool.items.items[b.a + k]);
                }
            },
            else => unreachable,
        }
    }

    fn builtinVariant(name: []const u8) ?enum { some, none, ok, err } {
        if (std.mem.eql(u8, name, "Some")) return .some;
        if (std.mem.eql(u8, name, "None")) return .none;
        if (std.mem.eql(u8, name, "Ok")) return .ok;
        if (std.mem.eql(u8, name, "Error")) return .err;
        return null;
    }

    fn variantPattern(c: *Checker, i: Index, subject: Id) Error!void {
        const n = c.node(i);
        const name = c.text(n.main_token);
        if (builtinVariant(name)) |bv| {
            const want: types.Tag = if (bv == .some or bv == .none) .option else .result;
            var b = c.bt(subject);
            if (b.tag == .variable) {
                const shape = if (want == .option) try c.pool.list1(.option, try c.pool.fresh(false)) else try c.pool.result(try c.pool.fresh(false), try c.pool.fresh(false));
                _ = c.pool.unify(subject, shape);
                b = c.bt(subject);
            }
            if (b.tag == .unknown) {
                if (n.lhs != 0) try c.pattern(n.lhs, types.unknown);
                return;
            }
            if (b.tag != want) {
                try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} matches {s}, but this is {s}", .{ name, if (want == .option) "an Option" else "a Result", try c.tn(subject) }));
                if (n.lhs != 0) try c.pattern(n.lhs, types.unknown);
                return;
            }
            if (bv == .none) {
                if (n.lhs != 0) try c.reportTok(.bad_pattern, n.main_token, "None carries no value");
                return;
            }
            if (n.lhs == 0) return c.reportTok(.bad_pattern, n.main_token, try c.print("{s} carries a value; match it as {s}(_)", .{ name, name }));
            return c.pattern(n.lhs, if (bv == .err) b.b else b.a);
        }
        const v = c.findVariant(name, subject) orelse {
            try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} has no variant named {s}", .{ try c.tn(subject), name }));
            if (n.lhs != 0) try c.pattern(n.lhs, types.unknown);
            return;
        };
        const owner = try c.ownerType(v);
        if (!c.pool.unify(subject, owner)) {
            try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} belongs to {s}, but this is {s}", .{ name, try c.tn(owner), try c.tn(subject) }));
            if (n.lhs != 0) try c.pattern(n.lhs, types.unknown);
            return;
        }
        const fields = c.variants.items[v].fields;
        switch (fields.len()) {
            0 => if (n.lhs != 0) try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} carries no fields", .{name})),
            1 => if (n.lhs == 0) {
                try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} carries {s}; match it as {s}(_)", .{ name, c.fields.items[fields.start].name, name }));
            } else try c.pattern(n.lhs, c.fields.items[fields.start].type),
            else => {
                try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} has {d} fields, so it is matched by name", .{ name, fields.len() }));
                if (n.lhs != 0) try c.pattern(n.lhs, types.unknown);
            },
        }
    }

    fn recordPattern(c: *Checker, i: Index, subject: Id) Error!void {
        const n = c.node(i);
        const name = c.text(n.main_token);
        const pfields = c.spanOf(n);
        var fields: Range = .{};
        if (c.findVariant(name, subject)) |v| {
            const owner = try c.ownerType(v);
            if (!c.pool.unify(subject, owner)) {
                try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} belongs to {s}, but this is {s}", .{ name, try c.tn(owner), try c.tn(subject) }));
                for (pfields) |pf| try c.pattern(c.node(pf).lhs, types.unknown);
                return;
            }
            fields = c.variants.items[v].fields;
            if (fields.len() == 1) try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} has one field, so it is matched by position: {s}(_)", .{ name, name }));
        } else if (c.type_names.get(name)) |d| {
            if (c.decls.items[d].kind != .struct_ or !c.pool.unify(subject, c.decls.items[d].type)) {
                try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} cannot match {s}", .{ name, try c.tn(subject) }));
                for (pfields) |pf| try c.pattern(c.node(pf).lhs, types.unknown);
                return;
            }
            fields = c.decls.items[d].fields;
        } else {
            try c.reportTok(.bad_pattern, n.main_token, try c.print("{s} has no variant named {s}", .{ try c.tn(subject), name }));
            for (pfields) |pf| try c.pattern(c.node(pf).lhs, types.unknown);
            return;
        }
        const defs = c.fields.items[fields.start..fields.end];
        for (pfields) |pf| {
            const pn = c.node(pf);
            const fname = c.text(pn.main_token);
            const f = for (defs) |d| {
                if (std.mem.eql(u8, d.name, fname)) break d;
            } else {
                try c.reportTok(.bad_pattern, pn.main_token, try c.print("{s} has no field {s}", .{ name, fname }));
                try c.pattern(pn.lhs, types.unknown);
                continue;
            };
            try c.pattern(pn.lhs, f.type);
        }
        for (defs) |d| {
            const named = for (pfields) |pf| {
                if (std.mem.eql(u8, c.text(c.node(pf).main_token), d.name)) break true;
            } else false;
            if (!named) {
                try c.reportTok(.bad_pattern, n.main_token, try c.print("this {s} pattern leaves out {s}; name every field, with _ for the ones it ignores", .{ name, d.name }));
                break;
            }
        }
    }

    fn findVariant(c: *Checker, name: []const u8, expected: Id) ?u32 {
        const b = c.bt(expected);
        const scope: ?u32 = switch (b.tag) {
            .decl => if (c.decls.items[b.a].kind == .enum_ or c.decls.items[b.a].kind == .prelude_enum) b.a else null,
            .message => b.a,
            else => null,
        };
        if (scope) |d| {
            const r = c.decls.items[d].variants;
            for (r.start..r.end) |v| if (std.mem.eql(u8, c.variants.items[v].name, name)) return @intCast(v);
            return null;
        }
        // No expectation to go on: this module's enums and messages first, then the prelude's.
        for (c.variants.items, 0..) |v, i| {
            if (c.decls.items[v.owner].kind != .prelude_enum and std.mem.eql(u8, v.name, name)) return @intCast(i);
        }
        for (c.variants.items, 0..) |v, i| {
            if (std.mem.eql(u8, v.name, name)) return @intCast(i);
        }
        return null;
    }

    fn ownerType(c: *Checker, v: u32) Error!Id {
        const d = c.variants.items[v].owner;
        if (c.decls.items[d].kind == .process) return c.pool.add(.{ .tag = .message, .a = d });
        return c.decls.items[d].type;
    }

    // ---- expressions

    fn expr(c: *Checker, i: Index, expected: Id) Error!Id {
        const t = try c.infer(i, expected);
        c.node_types[i] = t;
        if (expected != types.unknown and !c.pool.unify(expected, t)) {
            try c.mismatch(i, expected, t);
            return types.unknown;
        }
        return t;
    }

    fn infer(c: *Checker, i: Index, expected: Id) Error!Id {
        const n = c.node(i);
        switch (n.kind) {
            .int_lit => {
                const v = try c.pool.fresh(true);
                try c.defer_(.{ .kind = .literal, .node = i, .type = v });
                return v;
            },
            .float_lit => return types.float64,
            .true_lit, .false_lit => return types.bool_,
            .string_lit => return types.string,
            .string_interp => {
                for (c.spanOf(n)) |part| {
                    if (c.node(part).kind != .string_part) _ = try c.expr(part, types.unknown);
                }
                return types.string;
            },
            .name_ref => return c.nameRef(i),
            .type_name_ref => return c.variantValue(i, expected),
            .tuple => {
                const elems = c.spanOf(n);
                const b = c.bt(expected);
                var buf: std.ArrayList(Id) = .empty;
                for (elems, 0..) |e, k| {
                    const want = if (b.tag == .tuple and b.b == elems.len) c.pool.items.items[b.a + k] else types.unknown;
                    try buf.append(c.gpa, try c.expr(e, want));
                }
                return c.pool.tuple(buf.items);
            },
            .list => {
                const b = c.bt(expected);
                const elem = if (b.tag == .list) b.a else try c.pool.fresh(false);
                for (c.spanOf(n)) |e| _ = try c.expr(e, elem);
                return c.pool.list1(.list, elem);
            },
            .not_expr => {
                _ = try c.expr(n.lhs, types.bool_);
                return types.bool_;
            },
            .and_expr, .implies => {
                _ = try c.expr(n.lhs, types.bool_);
                _ = try c.expr(n.rhs, types.bool_);
                return types.bool_;
            },
            .or_expr => {
                const lt = try c.expr(n.lhs, types.unknown);
                const b = c.bt(lt);
                if (b.tag == .option) return c.expr(n.rhs, b.a);
                if (b.tag != .variable and b.tag != .unknown and b.tag != .bool) try c.mismatch(n.lhs, types.bool_, lt);
                _ = try c.expr(n.rhs, types.bool_);
                return types.bool_;
            },
            .compare => {
                const lt = try c.expr(n.lhs, types.unknown);
                _ = try c.expr(n.rhs, lt);
                const op = c.text(n.main_token);
                if (!std.mem.eql(u8, op, "==") and !std.mem.eql(u8, op, "!=")) try c.defer_(.{ .kind = .ordered, .node = i, .type = lt });
                return types.bool_;
            },
            .is_expr => {
                const lt = try c.expr(n.lhs, types.unknown);
                try c.pattern(n.rhs, lt);
                return types.bool_;
            },
            .range => {
                const v = try c.pool.fresh(true);
                _ = try c.expr(n.lhs, v);
                _ = try c.expr(n.rhs, v);
                return c.pool.list1(.list, v);
            },
            .add, .mul => return c.arith(i),
            .negate => {
                const t = try c.expr(n.lhs, expected);
                try c.defer_(.{ .kind = .numeric, .node = i, .type = t });
                return t;
            },
            .try_expr => return c.tryExpr(i),
            .member => return c.memberExpr(i),
            .member_call => return c.methodCall(i),
            .tuple_index => {
                const t = try c.expr(n.lhs, types.unknown);
                const b = c.bt(t);
                if (b.tag == .unknown or b.tag == .variable) return types.unknown;
                const k = std.fmt.parseInt(u32, c.text(n.main_token), 10) catch std.math.maxInt(u32);
                if (b.tag != .tuple or k >= b.b) {
                    try c.reportTok(.no_member, n.main_token, try c.print("{s} has no position {s}", .{ try c.tn(t), c.text(n.main_token) }));
                    return types.unknown;
                }
                return c.pool.items.items[b.a + k];
            },
            .call => return c.callExpr(i, expected),
            .named_arg => {
                try c.reportTok(.bad_named_arg, n.main_token, "a named argument appears only inside a call's parentheses");
                return c.expr(n.lhs, types.unknown);
            },
            .if_expr => return c.ifCheck(i, expected, true),
            .case_expr => return c.caseCheck(i, expected, .value),
            .anon_fn => return c.anonFn(i, expected),
            .old_expr => {
                if (!c.frame.old_ok) try c.reportTok(.misplaced, n.main_token, "old(...) is the value on entry, so it appears only in ensures and invariant");
                return c.expr(n.lhs, expected);
            },
            .result_ref => {
                if (c.frame.result) |r| return r;
                try c.reportTok(.misplaced, n.main_token, "result is the value a function returns, so it appears only in ensures");
                return types.unknown;
            },
            .any_expr => {
                if (!c.frame.in_property) try c.reportTok(.misplaced, n.main_token, "any(T) generates values, so it appears only in a property's for");
                var ctx: TypeCtx = .{};
                return c.pool.list1(.list, try c.resolveType(n.lhs, &ctx));
            },
            .comprehension => {
                try c.reportTok(.misplaced, n.main_token, "a comprehension is the body of a never or a property");
                return types.unknown;
            },
            else => return types.unknown,
        }
    }

    fn nameRef(c: *Checker, i: Index) Error!Id {
        const n = c.node(i);
        const name = c.text(n.main_token);
        if (c.lookup(name)) |b| {
            try c.useBinding(b, n.main_token);
            return c.bindings.items[b].type;
        }
        if (c.fn_names.get(name)) |s| return c.instantiateFn(i, s);
        if (c.frame.refine_value) |v| {
            // Inside `where`, a bare name such as `size` is called on the value.
            if (try c.preludeMethod(i, null, v, name, &.{})) |t| return t;
        }
        try c.reportTok(.unknown_name, n.main_token, try c.print("there is no {s} in scope", .{name}));
        return types.unknown;
    }

    fn instantiateFn(c: *Checker, at: Index, si: u32) Error!Id {
        const s = c.sigs.items[si];
        const inst = try c.instantiate(at, s, null);
        return c.pool.subst(try c.sigType(s), inst.from, inst.to);
    }

    const Inst = struct { from: []const Id, to: []const Id };

    fn instantiate(c: *Checker, at: Index, s: FnSig, self_type: ?Id) Error!Inst {
        const gens = c.sig_generics.items[s.generics.start..s.generics.end];
        var from = try c.gpa.alloc(Id, gens.len + 1);
        var to = try c.gpa.alloc(Id, gens.len + 1);
        for (gens, 0..) |g, k| {
            from[k] = c.generics.items[g].type;
            to[k] = try c.pool.fresh(false);
            for (c.bounds.items) |b| if (b.generic == g) try c.defer_(.{ .kind = .bound, .node = at, .type = to[k], .trait = b.trait });
        }
        from[gens.len] = types.self_;
        to[gens.len] = self_type orelse types.self_;
        return .{ .from = from, .to = to };
    }

    fn variantValue(c: *Checker, i: Index, expected: Id) Error!Id {
        const n = c.node(i);
        const name = c.text(n.main_token);
        if (builtinVariant(name)) |bv| {
            if (bv == .none) {
                const b = c.bt(expected);
                return c.pool.list1(.option, if (b.tag == .option) b.a else try c.pool.fresh(false));
            }
            try c.reportTok(.arity, n.main_token, try c.print("{s} takes one value: {s}(x)", .{ name, name }));
            return types.unknown;
        }
        if (c.findVariant(name, expected)) |v| {
            const fields = c.variants.items[v].fields;
            if (fields.len() > 0) {
                try c.reportTok(.unnamed_fields, n.main_token, try c.print("{s} carries {s}; build it as {s}({s}: ...)", .{ name, c.fields.items[fields.start].name, name, c.fields.items[fields.start].name }));
            }
            return c.ownerType(v);
        }
        if (prelude.findType(name) != null or c.type_names.get(name) != null) {
            try c.reportTok(.unknown_name, n.main_token, try c.print("{s} is a type, not a value", .{name}));
        } else {
            try c.reportTok(.unknown_name, n.main_token, try c.print("there is no variant named {s}", .{name}));
        }
        return types.unknown;
    }

    fn arith(c: *Checker, i: Index) Error!Id {
        const n = c.node(i);
        const op = c.text(n.main_token);
        const lt = try c.expr(n.lhs, types.unknown);
        const lb = c.bt(lt);
        if (lb.tag == .time or lb.tag == .duration) {
            const rt = try c.expr(n.rhs, types.unknown);
            const lname = try c.tn(c.pool.base(lt));
            const rname = try c.tn(c.pool.base(rt));
            for (prelude.operators) |o| {
                if (std.mem.eql(u8, o.op, op) and std.mem.eql(u8, o.lhs, lname) and std.mem.eql(u8, o.rhs, rname)) return primitive(o.result).?;
            }
            if (c.bt(rt).tag == .unknown) return types.unknown;
            try c.reportTok(.mismatch, n.main_token, try c.print("{s} {s} {s} is not defined", .{ lname, op, rname }));
            return types.unknown;
        }
        _ = try c.expr(n.rhs, lt);
        try c.defer_(.{ .kind = .numeric, .node = i, .type = lt });
        return lt;
    }

    fn tryExpr(c: *Checker, i: Index) Error!Id {
        const n = c.node(i);
        const t = try c.expr(n.lhs, types.unknown);
        const b = c.bt(t);
        if (b.tag == .unknown or b.tag == .variable) return types.unknown;
        if (b.tag != .result and b.tag != .option) {
            try c.reportTok(.bad_try, n.main_token, try c.print("try applies to a Result or an Option; this is {s}", .{try c.tn(t)}));
            return types.unknown;
        }
        const kind = if (b.tag == .result) "Result" else "Option";
        if (c.frame.kind != .function) {
            try c.reportTok(.bad_try, n.main_token, try c.print("try passes an error up to a caller, so it appears only in a function that returns a {s}", .{kind}));
            return b.a;
        }
        const fret = c.bt(c.frame.ret);
        if (fret.tag != b.tag) {
            try c.reportTok(.bad_try, n.main_token, try c.print("try on a {s} needs {s} to return a {s}; it returns {s}", .{ kind, c.frame.name, kind, try c.tn(c.frame.ret) }));
            return b.a;
        }
        if (b.tag == .result) try c.tryErrors(i, b.b, fret.b);
        return b.a;
    }

    fn tryErrors(c: *Checker, at: Index, from: Id, to: Id) Error!void {
        const rf = c.pool.base(from);
        const rt = c.pool.base(to);
        if (rf == rt) return;
        const tf = c.pool.get(rf);
        const tt = c.pool.get(rt);
        const enum_like = struct {
            fn is(ch: *Checker, t: types.Type) bool {
                return t.tag == .decl and (ch.decls.items[t.a].kind == .enum_ or ch.decls.items[t.a].kind == .prelude_enum);
            }
        }.is;
        if (enum_like(c, tf) and enum_like(c, tt)) {
            if (tf.a == tt.a) return;
            const fd = c.decls.items[tf.a];
            const td = c.decls.items[tt.a];
            for (fd.variants.start..fd.variants.end) |vf| {
                const v = c.variants.items[vf];
                const match = for (td.variants.start..td.variants.end) |vt| {
                    if (std.mem.eql(u8, c.variants.items[vt].name, v.name)) break c.variants.items[vt];
                } else {
                    try c.reportNode(.try_variants, at, try c.print("try passes up {s}.{s}, but {s} has no variant {s}", .{ fd.name, v.name, td.name, v.name }));
                    continue;
                };
                const a = c.fields.items[v.fields.start..v.fields.end];
                const bf = c.fields.items[match.fields.start..match.fields.end];
                const same = a.len == bf.len and for (a, bf) |x, y| {
                    if (!std.mem.eql(u8, x.name, y.name) or !c.pool.unify(x.type, y.type)) break false;
                } else true;
                if (!same) try c.reportNode(.try_variants, at, try c.print("{s}.{s} and {s}.{s} carry different fields", .{ fd.name, v.name, td.name, v.name }));
            }
            return;
        }
        if (!c.pool.unify(from, to)) try c.reportNode(.try_variants, at, try c.print("try passes up {s} errors, but {s} returns {s} errors", .{ try c.tn(from), c.frame.name, try c.tn(to) }));
    }

    fn isTypeName(c: *Checker, name: []const u8) bool {
        if (prelude.findType(name) != null) return true;
        const d = c.type_names.get(name) orelse return false;
        return c.decls.items[d].kind != .recipe;
    }

    fn memberExpr(c: *Checker, i: Index) Error!Id {
        const n = c.node(i);
        const recv = c.node(n.lhs);
        const name = c.text(n.main_token);
        if (recv.kind == .type_name_ref and c.isTypeName(c.text(recv.main_token))) return c.staticCall(i, n.lhs, name, &.{});
        const t = try c.expr(n.lhs, types.unknown);
        if (try c.fieldOf(i, t, name)) |f| return f;
        return c.dotCall(i, n.lhs, t, name, &.{});
    }

    fn methodCall(c: *Checker, i: Index) Error!Id {
        const n = c.node(i);
        const recv = c.node(n.lhs);
        const name = c.text(n.main_token);
        const args = c.spanAt(n.rhs);
        if (recv.kind == .type_name_ref and c.isTypeName(c.text(recv.main_token))) return c.staticCall(i, n.lhs, name, args);
        const t = try c.expr(n.lhs, types.unknown);
        return c.dotCall(i, n.lhs, t, name, args);
    }

    fn dotCall(c: *Checker, i: Index, recv: Index, t: Id, name: []const u8, args: []const u32) Error!Id {
        if (try c.preludeMethod(i, recv, t, name, args)) |r| return r;
        if (c.fn_names.get(name)) |s| return c.userCall(i, s, .{ .node = recv, .type = t }, args, null);
        if (try c.traitCall(i, recv, t, name, args)) |r| return r;
        const b = c.bt(t);
        if (b.tag != .unknown and b.tag != .variable) {
            try c.reportTok(.no_member, c.node(i).main_token, try c.print("{s} has no field or function named {s}", .{ try c.tn(t), name }));
        }
        for (args) |a| _ = try c.argExpr(a, types.unknown);
        return types.unknown;
    }

    fn namedMatches(c: *Checker, row: prelude.Fn, args: []const u32) bool {
        var count: usize = 0;
        for (args) |a| {
            const an = c.node(a);
            if (an.kind != .named_arg) continue;
            const nm = c.text(an.main_token);
            if (std.mem.eql(u8, nm, "within")) continue;
            count += 1;
            const known = for (row.named) |f| {
                if (std.mem.eql(u8, f.name, nm)) break true;
            } else false;
            if (!known) return false;
        }
        return count == row.named.len;
    }

    /// A prelude function called on a value. Null when no row fits the receiver.
    fn preludeMethod(c: *Checker, i: Index, recv: ?Index, t: Id, name: []const u8, args: []const u32) Error!?Id {
        var fallback: ?usize = null;
        for (prelude.fns, 0..) |row, k| {
            if (row.on_type or row.recv.len == 0 or !std.mem.eql(u8, row.name, name)) continue;
            if (!c.recvMatches(row.recv, t)) continue;
            if (c.namedMatches(row, args)) return try c.preludeCall(i, recv, t, k, args);
            fallback = k;
        }
        if (fallback) |k| return try c.preludeCall(i, recv, t, k, args);
        return null;
    }

    fn preludeCall(c: *Checker, i: Index, recv: ?Index, t: Id, k: usize, args: []const u32) Error!Id {
        const row = prelude.fns[k];
        var env: Env = .{ .n = t };
        const b = c.bt(t);
        if (b.tag == .handle) env.process = b.a;
        if (row.recv.len > 0 and std.mem.indexOfScalar(u8, row.recv, '(') != null and b.tag != .handle) {
            _ = c.pool.unify(try c.parseTs(row.recv, &env), t);
        }
        var positional: std.ArrayList(u32) = .empty;
        for (args) |a| {
            const an = c.node(a);
            if (an.kind != .named_arg) {
                try positional.append(c.gpa, a);
                continue;
            }
            const nm = c.text(an.main_token);
            c.node_types[a] = types.none;
            if (std.mem.eql(u8, nm, "within")) {
                _ = try c.expr(an.lhs, types.duration);
                continue;
            }
            const f = for (row.named) |f| {
                if (std.mem.eql(u8, f.name, nm)) break f;
            } else {
                try c.reportTok(.bad_named_arg, an.main_token, try c.print("{s} takes no argument named {s}:", .{ row.name, nm }));
                _ = try c.expr(an.lhs, types.unknown);
                continue;
            };
            _ = try c.expr(an.lhs, try c.parseTs(f.type, &env));
        }
        const label = try c.callLabel(i, recv, row.name);
        const to_process = std.mem.startsWith(u8, row.recv, "Handle");
        if (to_process) c.process_args += 1;
        defer if (to_process) {
            c.process_args -= 1;
        };
        if (positional.items.len != row.params.len) {
            try c.reportTok(.arity, c.node(i).main_token, try c.print("{s} takes {d} argument{s}, found {d}", .{ label, row.params.len, if (row.params.len == 1) "" else "s", positional.items.len }));
            for (positional.items) |a| _ = try c.argExpr(a, types.unknown);
        } else {
            for (positional.items, row.params) |a, p| _ = try c.argExpr(a, try c.parseTs(p, &env));
        }
        if (std.mem.indexOf(u8, row.ret, "Reply") != null) {
            env.reply = if (positional.items.len > 0) try c.replyOfArg(positional.items[0], env.process) else types.unknown;
        }
        c.callee[i] = .{ .prelude = @intCast(k) };
        return c.parseTs(row.ret, &env);
    }

    fn callLabel(c: *Checker, i: Index, recv: ?Index, name: []const u8) Error![]const u8 {
        const r = recv orelse return name;
        const rn = c.node(r);
        if (rn.kind == .name_ref or rn.kind == .type_name_ref) return c.print("{s}.{s}", .{ c.text(rn.main_token), name });
        _ = i;
        return name;
    }

    fn replyOfArg(c: *Checker, arg: Index, process: ?u32) Error!Id {
        const p = process orelse return types.unknown;
        var an = c.node(arg);
        if (an.kind == .call) an = c.node(an.lhs);
        if (an.kind != .type_name_ref) return types.unknown;
        const name = c.text(an.main_token);
        const r = c.decls.items[p].variants;
        for (r.start..r.end) |v| {
            if (!std.mem.eql(u8, c.variants.items[v].name, name)) continue;
            if (c.variants.items[v].reply) |reply| return reply;
            try c.reportTok(.mismatch, an.main_token, try c.print("{s} has no reply type, so it is sent, not asked", .{name}));
            return types.unknown;
        }
        return types.unknown;
    }

    /// Checks one call argument; the argument is the one place an anonymous function may be.
    fn argExpr(c: *Checker, a: Index, expected: Id) Error!Id {
        c.anon_ok = a;
        return c.expr(a, expected);
    }

    fn staticCall(c: *Checker, i: Index, recv: Index, name: []const u8, args: []const u32) Error!Id {
        const tname = c.text(c.node(recv).main_token);
        c.node_types[recv] = types.unknown;
        if (c.type_names.get(tname)) |d| {
            const decl = c.decls.items[d];
            if (decl.kind == .process) {
                if (!std.mem.eql(u8, name, "start")) {
                    try c.reportTok(.no_member, c.node(i).main_token, try c.print("{s} has no function {s}; a process is started with {s}.start(...)", .{ tname, name, tname }));
                    return types.unknown;
                }
                c.process_args += 1;
                try c.positionalArgs(i, try c.print("{s}.start", .{tname}), null, args, decl.params, &.{}, &.{});
                c.process_args -= 1;
                for (prelude.fns, 0..) |row, k| if (std.mem.eql(u8, row.recv, "Process")) {
                    c.callee[i] = .{ .prelude = @intCast(k) };
                };
                return decl.type;
            }
        }
        if (std.mem.eql(u8, name, "all")) {
            if (!c.frame.in_never) try c.reportTok(.misplaced, c.node(i).main_token, try c.print("{s}.all names every {s} the program holds, so it appears only inside a never", .{ tname, tname }));
            for (prelude.fns, 0..) |row, k| if (std.mem.eql(u8, row.recv, "Type")) {
                c.callee[i] = .{ .prelude = @intCast(k) };
            };
            const d = c.type_names.get(tname) orelse return c.pool.list1(.list, primitive(tname) orelse types.unknown);
            const dt = if (c.decls.items[d].kind == .alias) try c.aliasType(d) else c.decls.items[d].type;
            return c.pool.list1(.list, dt);
        }
        var fallback: ?usize = null;
        for (prelude.fns, 0..) |row, k| {
            if (!row.on_type or !std.mem.eql(u8, row.recv, tname) or !std.mem.eql(u8, row.name, name)) continue;
            if (c.namedMatches(row, args)) return c.preludeCall(i, recv, primitive(tname) orelse types.unknown, k, args);
            fallback = k;
        }
        if (fallback) |k| return c.preludeCall(i, recv, primitive(tname) orelse types.unknown, k, args);
        try c.reportTok(.no_member, c.node(i).main_token, try c.print("{s} has no function named {s}", .{ tname, name }));
        for (args) |a| _ = try c.argExpr(a, types.unknown);
        return types.unknown;
    }

    const Recv = struct { node: Index, type: Id };

    fn userCall(c: *Checker, i: Index, si: u32, recv: ?Recv, args: []const u32, self_type: ?Id) Error!Id {
        const s = c.sigs.items[si];
        const inst = try c.instantiate(i, s, self_type);
        try c.positionalArgs(i, s.name, recv, args, s.params, inst.from, inst.to);
        c.callee[i] = .{ .user = si };
        if (c.frame.in_rejects) c.tripped[si] = true;
        return c.pool.subst(s.ret, inst.from, inst.to);
    }

    /// Arguments by position against declared parameters, with `within:` left for caps.zig.
    fn positionalArgs(c: *Checker, i: Index, label: []const u8, recv: ?Recv, args: []const u32, params: Range, from: []const Id, to: []const Id) Error!void {
        var positional: std.ArrayList(u32) = .empty;
        for (args) |a| {
            const an = c.node(a);
            if (an.kind != .named_arg) {
                try positional.append(c.gpa, a);
                continue;
            }
            c.node_types[a] = types.none;
            if (std.mem.eql(u8, c.text(an.main_token), "within")) {
                _ = try c.expr(an.lhs, types.duration);
                continue;
            }
            try c.reportTok(.bad_named_arg, an.main_token, try c.print("{s} takes its arguments by position; {s}: is not one of them", .{ label, c.text(an.main_token) }));
            _ = try c.expr(an.lhs, types.unknown);
        }
        const ps = c.params.items[params.start..params.end];
        const offset: usize = if (recv != null) 1 else 0;
        const given = positional.items.len + offset;
        if (given != ps.len) {
            const at = if (c.node(i).kind == .child) c.node(i).main_token else c.node(i).main_token;
            try c.reportTok(.arity, at, try c.print("{s} takes {d} argument{s}, found {d}", .{ label, ps.len, if (ps.len == 1) "" else "s", given }));
            for (positional.items) |a| _ = try c.argExpr(a, types.unknown);
            return;
        }
        if (recv) |r| {
            const want = try c.pool.subst(ps[0].type, from, to);
            if (!c.pool.unify(want, r.type)) try c.mismatch(r.node, want, r.type);
            if (ps[0].inout) try c.inoutArg(r.node, ps[0].name);
        }
        for (positional.items, ps[offset..]) |a, p| {
            _ = try c.argExpr(a, try c.pool.subst(p.type, from, to));
            if (p.inout) try c.inoutArg(a, p.name);
        }
    }

    fn inoutArg(c: *Checker, a: Index, param: []const u8) Error!void {
        var cur = a;
        while (c.node(cur).kind == .member) cur = c.node(cur).lhs;
        const n = c.node(cur);
        if (n.kind == .name_ref) {
            if (c.lookup(c.text(n.main_token))) |b| switch (c.bindings.items[b].kind) {
                .var_, .inout, .state => return,
                else => {},
            };
        }
        try c.reportNode(.not_assignable, a, try c.print("{s} is inout, so its argument must be a var the caller holds", .{param}));
    }

    fn traitCall(c: *Checker, i: Index, recv: Index, t: Id, name: []const u8, args: []const u32) Error!?Id {
        const r = c.pool.base(t);
        const b = c.pool.get(r);
        switch (b.tag) {
            .param => for (c.bounds.items) |bound| {
                if (bound.generic != b.a) continue;
                const sigs = c.decls.items[bound.trait].sigs;
                for (sigs.start..sigs.end) |s| {
                    if (std.mem.eql(u8, c.sigs.items[s].name, name)) return try c.userCall(i, @intCast(s), .{ .node = recv, .type = t }, args, r);
                }
            },
            .decl => for (c.impls.items) |im| {
                const ib = c.bt(im.for_type);
                if (ib.tag != .decl or ib.a != b.a) continue;
                for (im.sigs.start..im.sigs.end) |s| {
                    if (std.mem.eql(u8, c.sigs.items[s].name, name)) return try c.userCall(i, @intCast(s), .{ .node = recv, .type = t }, args, null);
                }
            },
            else => {},
        }
        return null;
    }

    fn callExpr(c: *Checker, i: Index, expected: Id) Error!Id {
        const n = c.node(i);
        const callee = c.node(n.lhs);
        const args = c.spanAt(n.rhs);
        switch (callee.kind) {
            .type_name_ref => return c.construct(n.lhs, args, expected),
            .name_ref => {
                const name = c.text(callee.main_token);
                if (c.lookup(name) == null) {
                    if (c.fn_names.get(name)) |s| return c.userCall(i, s, null, args, null);
                    if (std.mem.eql(u8, name, "flows")) {
                        try c.reportTok(.misplaced, callee.main_token, "flows(...) is a rule, so it appears only as the body of a never");
                        return types.bool_;
                    }
                }
            },
            else => {},
        }
        const ft = try c.expr(n.lhs, types.unknown);
        const b = c.bt(ft);
        if (b.tag == .func) {
            const ps = c.pool.elems(b);
            if (ps.len != args.len) {
                try c.reportNode(.arity, i, try c.print("this function takes {d} argument{s}, found {d}", .{ ps.len, if (ps.len == 1) "" else "s", args.len }));
                for (args) |a| _ = try c.argExpr(a, types.unknown);
            } else {
                for (args, ps) |a, p| _ = try c.argExpr(a, p);
            }
            return c.pool.funcRet(b);
        }
        if (b.tag != .unknown and b.tag != .variable) try c.reportNode(.mismatch, i, try c.print("only a function can be called; this is {s}", .{try c.tn(ft)}));
        for (args) |a| _ = try c.argExpr(a, types.unknown);
        return types.unknown;
    }

    fn construct(c: *Checker, callee: Index, args: []const u32, expected: Id) Error!Id {
        const tok = c.node(callee).main_token;
        const name = c.text(tok);
        const exp = c.bt(expected);
        if (builtinVariant(name)) |bv| {
            if (bv == .none or args.len != 1 or c.node(args[0]).kind == .named_arg) {
                try c.reportTok(.arity, tok, if (bv == .none) "None takes no value" else try c.print("{s} takes one value: {s}(x)", .{ name, name }));
                for (args) |a| _ = try c.argExpr(a, types.unknown);
                return if (bv == .none) c.pool.list1(.option, try c.pool.fresh(false)) else types.unknown;
            }
            switch (bv) {
                .some => return c.pool.list1(.option, try c.argExpr(args[0], if (exp.tag == .option) exp.a else types.unknown)),
                .ok => {
                    const v = try c.argExpr(args[0], if (exp.tag == .result) exp.a else types.unknown);
                    return c.pool.result(v, if (exp.tag == .result) exp.b else try c.pool.fresh(false));
                },
                .err => {
                    const e = try c.argExpr(args[0], if (exp.tag == .result) exp.b else types.unknown);
                    return c.pool.result(if (exp.tag == .result) exp.a else try c.pool.fresh(false), e);
                },
                .none => unreachable,
            }
        }
        if (c.type_names.get(name)) |d| {
            const decl = c.decls.items[d];
            switch (decl.kind) {
                .struct_ => {
                    try c.namedFields(tok, name, decl.fields, args);
                    return decl.type;
                },
                .process => {
                    try c.reportTok(.unnamed_fields, tok, try c.print("{s} is a process; start it with {s}.start(...)", .{ name, name }));
                    return types.unknown;
                },
                else => {},
            }
        }
        if (c.findVariant(name, expected)) |v| {
            const fields = c.variants.items[v].fields;
            if (fields.len() == 0) {
                try c.reportTok(.arity, tok, try c.print("{s} carries no fields; write {s} without parentheses", .{ name, name }));
                for (args) |a| _ = try c.argExpr(a, types.unknown);
            } else try c.namedFields(tok, name, fields, args);
            return c.ownerType(v);
        }
        try c.reportTok(.unknown_name, tok, try c.print("there is no struct or variant named {s}", .{name}));
        for (args) |a| _ = try c.argExpr(a, types.unknown);
        return types.unknown;
    }

    fn namedFields(c: *Checker, tok: u32, label: []const u8, fields: Range, args: []const u32) Error!void {
        const defs = c.fields.items[fields.start..fields.end];
        var seen = try c.gpa.alloc(bool, defs.len);
        @memset(seen, false);
        for (args) |a| {
            const an = c.node(a);
            if (an.kind != .named_arg) {
                try c.reportNode(.unnamed_fields, a, try c.print("{s} is built by naming its fields: {s}({s}: ...)", .{ label, label, if (defs.len > 0) defs[0].name else "" }));
                _ = try c.expr(a, types.unknown);
                continue;
            }
            c.node_types[a] = types.none;
            const nm = c.text(an.main_token);
            const k = for (defs, 0..) |d, k| {
                if (std.mem.eql(u8, d.name, nm)) break k;
            } else {
                try c.reportTok(.bad_named_arg, an.main_token, try c.print("{s} has no field {s}", .{ label, nm }));
                _ = try c.expr(an.lhs, types.unknown);
                continue;
            };
            if (seen[k]) try c.reportTok(.bad_named_arg, an.main_token, try c.print("{s} is given twice", .{nm}));
            seen[k] = true;
            _ = try c.expr(an.lhs, defs[k].type);
        }
        for (defs, seen) |d, s| if (!s) {
            try c.reportTok(.bad_named_arg, tok, try c.print("{s} needs {s}: every field is given when it is built", .{ label, d.name }));
            break;
        };
    }

    fn anonFn(c: *Checker, i: Index, expected: Id) Error!Id {
        const n = c.node(i);
        const data = c.tree.extraData(ast.AnonFn, n.lhs);
        const names = c.tree.span(data.params_start, data.params_end);
        const exp = c.bt(expected);
        const ptypes = try c.gpa.alloc(Id, names.len);
        var ret: Id = undefined;
        if (exp.tag == .func and exp.b == names.len) {
            @memcpy(ptypes, c.pool.elems(exp));
            ret = c.pool.funcRet(exp);
        } else {
            if (exp.tag == .func) try c.reportTok(.arity, n.main_token, try c.print("this anonymous function takes {d} parameter{s}, but {d} are passed to it", .{ names.len, if (names.len == 1) "" else "s", exp.b }));
            for (ptypes) |*p| p.* = try c.pool.fresh(false);
            ret = try c.pool.fresh(false);
        }
        if (c.anon_ok != i) try c.reportTok(.anon_stored, n.main_token, "an anonymous function is used as a value here; pass it straight into a call instead.");
        const body_stmts = c.tree.span(data.body_start, data.body_end);
        const block_form = body_stmts.len > 0 and c.lineOf(c.tree.tokens[c.firstToken(body_stmts[0])].start) > c.lineOf(c.tree.tokens[n.main_token].start);
        const saved = c.frame;
        c.frame.kind = .anon;
        c.frame.has_ret = false;
        c.frame.loop_depth = 0;
        c.frame.anon_depth += 1;
        c.frame.result = null;
        if (block_form) try c.nestEnter(n.main_token);
        const mark = c.pushScope();
        for (names, ptypes) |tok, p| try c.bind(c.text(tok), p, .let, tok);
        _ = try c.blockValue(c.tree.span(data.body_start, data.body_end), ret);
        try c.popScope(mark);
        const inner_reported = c.frame.nest_reported;
        c.frame = saved;
        c.frame.nest_reported = c.frame.nest_reported or inner_reported;
        // A parameter-count mismatch is already reported; do not report the type again.
        if (exp.tag == .func and exp.b != names.len) return types.unknown;
        return c.pool.func(ptypes, ret);
    }
};

pub fn primitive(name: []const u8) ?Id {
    const table = [_]struct { []const u8, Id }{
        .{ "Int8", types.int(.i8) },         .{ "Int16", types.int(.i16) },   .{ "Int32", types.int(.i32) },
        .{ "Int64", types.int(.i64) },       .{ "UInt8", types.int(.u8) },    .{ "UInt16", types.int(.u16) },
        .{ "UInt32", types.int(.u32) },      .{ "UInt64", types.int(.u64) },  .{ "Float32", types.float32 },
        .{ "Float64", types.float64 },       .{ "Bool", types.bool_ },        .{ "String", types.string },
        .{ "Time", types.time },             .{ "Duration", types.duration }, .{ "Clock", types.cap(.clock) },
        .{ "Fs", types.cap(.fs) },           .{ "Events", types.cap(.events) }, .{ "Ledger", types.cap(.ledger) },
    };
    for (table) |e| if (std.mem.eql(u8, e[0], name)) return e[1];
    return null;
}

pub const ModuleUses = struct { path: []const u8, uses: []const []const u8 };

/// The first `use` cycle among `modules`: the paths around it, the first repeated at
/// the end. `mo check` sees one file, so on its own it finds only a module that uses
/// itself; a driver that loads a module's imports passes every module here.
pub fn useCycle(gpa: std.mem.Allocator, modules: []const ModuleUses) Error!?[]const []const u8 {
    const color = try gpa.alloc(u8, modules.len);
    defer gpa.free(color);
    @memset(color, 0);
    var stack: std.ArrayList(usize) = .empty;
    defer stack.deinit(gpa);
    for (0..modules.len) |root| {
        if (color[root] == 0) if (try visitUses(gpa, modules, color, &stack, root)) |cycle| return cycle;
    }
    return null;
}

fn visitUses(gpa: std.mem.Allocator, modules: []const ModuleUses, color: []u8, stack: *std.ArrayList(usize), i: usize) Error!?[]const []const u8 {
    color[i] = 1;
    try stack.append(gpa, i);
    for (modules[i].uses) |u| {
        const j = for (modules, 0..) |m, k| {
            if (std.mem.eql(u8, m.path, u)) break k;
        } else continue;
        if (color[j] == 1) {
            const pos = std.mem.indexOfScalar(usize, stack.items, j).?;
            const out = try gpa.alloc([]const u8, stack.items.len - pos + 1);
            for (stack.items[pos..], 0..) |k, n| out[n] = modules[k].path;
            out[out.len - 1] = modules[j].path;
            return out;
        }
        if (color[j] == 0) if (try visitUses(gpa, modules, color, stack, j)) |cycle| return cycle;
    }
    _ = stack.pop();
    color[i] = 2;
    return null;
}

// ---- tests

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

fn checkSource(arena: std.mem.Allocator, src: []const u8) ![]const diag.Record {
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    _ = try check(arena, tree, &diags);
    return diags.items;
}

fn expectCodes(src: []const u8, codes: []const []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try checkSource(arena_state.allocator(), src);
    var ok = found.len == codes.len;
    if (ok) for (found, codes) |d, code| {
        if (!std.mem.eql(u8, d.code, code)) ok = false;
    };
    if (!ok) {
        std.debug.print("expected {d} diagnostics:", .{codes.len});
        for (codes) |code| std.debug.print(" {s}", .{code});
        std.debug.print("\nfound:\n", .{});
        for (found) |d| std.debug.print("  {s} at {d}: {s}\n", .{ d.code, d.at, d.what });
    }
    try std.testing.expect(ok);
}

test "a well-typed module has no diagnostics" {
    try expectCodes(
        \\module T.Ok
        \\expose Shape, area
        \\enum Shape
        \\  Square(side: UInt32)
        \\  Rect(w: UInt32, h: UInt32)
        \\end
        \\fn area(s: Shape) : UInt32
        \\  case s
        \\    Square(n): n * n
        \\    Rect(w: a, h: b): a * b
        \\  end
        \\end
        \\test "areas"
        \\  assert Square(side: 3).area == 9
        \\  assert [1, 2].map(fn(x) x + 1 end) == [2, 3]
        \\end
    , &.{});
}

test "a value of the wrong type is MO0206" {
    try expectCodes(
        \\module T.Bad
        \\fn f(n: UInt32) : String
        \\  n
        \\end
    , &.{"MO0206"});
}

test "an unknown name, an unknown type, and an undeclared exposed name" {
    try expectCodes(
        \\module T.Names
        \\expose missing
        \\fn f(n: Nope) : UInt32
        \\  m
        \\end
    , &.{ "MO0203", "MO0202", "MO0201" });
}

test "a literal that does not fit its type is MO0217" {
    try expectCodes(
        \\module T.Lit
        \\fn f() : UInt8
        \\  300
        \\end
    , &.{"MO0217"});
}

test "try needs the error enum's variants in the function's error type" {
    try expectCodes(
        \\module T.Try
        \\enum A
        \\  Gone
        \\  Late
        \\end
        \\enum B
        \\  Gone
        \\end
        \\fn a() : Result(UInt32, A)
        \\  Error(Late)
        \\end
        \\fn b() : Result(UInt32, B)
        \\  n = try a()
        \\  Ok(n)
        \\end
    , &.{"MO0211"});
}

test "construction names every field; a positional argument is MO0222" {
    try expectCodes(
        \\module T.Build
        \\struct P
        \\  x: UInt32
        \\  y: UInt32
        \\end
        \\fn f() : P
        \\  P(x: 1)
        \\end
        \\fn g() : P
        \\  P(1, 2)
        \\end
    , &.{ "MO0209", "MO0222", "MO0222", "MO0209" });
}

test "a bound needs an impl, and an impl must match its trait" {
    try expectCodes(
        \\module T.Traits
        \\trait Sized
        \\  fn weight(item: Self) : UInt32
        \\end
        \\struct Box
        \\  grams: UInt32
        \\end
        \\struct Bag
        \\  grams: UInt32
        \\end
        \\impl Sized for Box
        \\  fn weight(item: Box) : String
        \\    "heavy"
        \\  end
        \\end
        \\fn total(xs: List(T)) : UInt32 where T: Sized
        \\  xs.reduce(0, fn(sum, x) sum + x.weight end)
        \\end
        \\test "bags have no impl"
        \\  assert total([Bag(grams: 1)]) == 1
        \\end
    , &.{ "MO0216", "MO0213" });
}

test "assert outside a test and result outside ensures are misplaced" {
    try expectCodes(
        \\module T.Place
        \\fn f(n: UInt32) : Bool
        \\  assert n > 0
        \\  result
        \\end
    , &.{ "MO0214", "MO0214" });
}

fn expectWhat(src: []const u8, code: []const u8, what: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const found = try checkSource(arena_state.allocator(), src);
    for (found) |d| if (std.mem.eql(u8, d.code, code) and std.mem.eql(u8, d.what, what)) return;
    std.debug.print("expected {s} \"{s}\", found:\n", .{ code, what });
    for (found) |d| std.debug.print("  {s}: {s}\n", .{ d.code, d.what });
    return error.TestExpectedEqual;
}

test "the shape laws: parameters, body lines, nesting, state fields, file lines" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try expectCodes(
        \\module T.Params
        \\fn f(a: UInt8, b: UInt8, c: UInt8, d: UInt8, e: UInt8, g: UInt8, h: UInt8) : UInt8
        \\  a + b + c + d + e + g + h
        \\end
    , &.{"MO0303"});
    try expectCodes("module T.Long\nfn f() : UInt8\n" ++ "\n" ** 70 ++ "  1\nend\n", &.{"MO0301"});
    try expectCodes("module T.Fits\nfn f() : UInt8\n" ++ "\n" ** 69 ++ "  1\nend\n", &.{});
    try expectCodes(
        \\module T.Deep
        \\fn f(a: Bool) : UInt8
        \\  if a
        \\    if a
        \\      if a
        \\        if a
        \\          return 1
        \\        end
        \\      end
        \\    end
        \\  end
        \\  0
        \\end
    , &.{"MO0304"});
    var state: std.ArrayList(u8) = .empty;
    try state.appendSlice(arena, "module T.Big\nprocess Big()\n  state\n");
    for (0..13) |k| try state.print(arena, "    f{d}: UInt8\n", .{k});
    try state.appendSlice(arena, "  end\n  message Go\n  fn update(state, message)\n    case message\n      Go:\n        state.f0 += 1\n    end\n  end\nend\nsupervisor Top\n  child Big, restart: :always\nend\n");
    try expectCodes(state.items, &.{"MO0305"});
    try expectCodes("module T.File\n" ++ "\n" ** 500, &.{"MO0302"});
}

test "bindings: rebinding, unused, a captured var, a var sent to a process" {
    try expectWhat(
        \\module T.Twice
        \\fn f(a: UInt8) : UInt8
        \\  b = a
        \\  b = b + 1
        \\  b
        \\end
    , "MO0306", "b is bound twice in one scope; make it var b, or pick a new name.");
    try expectWhat(
        \\module T.Unused
        \\fn f(a: UInt8) : UInt8
        \\  b = a
        \\  a
        \\end
    , "MO0307", "b is bound but never used.");
    try expectCodes(
        \\module T.Captured
        \\fn f(xs: List(UInt8)) : List(UInt8)
        \\  var n = 1
        \\  n += 1
        \\  xs.map(fn(x) x + n end)
        \\end
    , &.{"MO0314"});
    try expectCodes(
        \\module T.Sent
        \\process P()
        \\  state
        \\    n: UInt8
        \\  end
        \\  message Add(n: UInt8)
        \\  fn update(state, message)
        \\    case message
        \\      Add(k):
        \\        state.n += k
        \\    end
        \\  end
        \\end
        \\supervisor S
        \\  child P, restart: :always
        \\end
        \\test "a var is not sent"
        \\  var k = 1
        \\  k += 1
        \\  p = P.start()
        \\  p.send(Add(n: k))
        \\end
    , &.{"MO0315"});
}

test "case: a missing variant is named; a catch-all arm on an enum names what it hides" {
    try expectWhat(
        \\module T.Missing
        \\enum E
        \\  Gone(path: String)
        \\  Late
        \\end
        \\fn f(r: Result(UInt8, E)) : UInt8
        \\  case r
        \\    Ok(n): n
        \\    Error(Gone(_)): 0
        \\  end
        \\end
    , "MO0308", "this case does not cover Error(Late); add an arm for it.");
    try expectWhat(
        \\module T.CatchAll
        \\enum L
        \\  A
        \\  B
        \\  C
        \\end
        \\fn f(l: L) : Bool
        \\  case l
        \\    A: true
        \\    _: false
        \\  end
        \\end
    , "MO0309", "the _ arm hides B and C; name each variant of L.");
    try expectCodes(
        \\module T.Guards
        \\fn f(n: UInt8, flag: Bool) : UInt8
        \\  case flag
        \\    true if n > 1: 1
        \\    false: 0
        \\  end
        \\end
    , &.{"MO0308"});
}

test "values: a dropped Result, a stored or returned anonymous function, a default parameter" {
    try expectWhat(
        \\module T.Dropped
        \\fn g() : Option(UInt8)
        \\  None
        \\end
        \\fn f() : UInt8
        \\  g()
        \\  1
        \\end
    , "MO0310", "the Option from g() is dropped; match it with case or pass it up with try.");
    try expectWhat(
        \\module T.Stored
        \\fn f(xs: List(UInt8)) : List(UInt8)
        \\  keep = fn(x) x > 1 end
        \\  xs.filter(keep)
        \\end
    , "MO0313", "an anonymous function is bound to keep; pass it straight into filter instead.");
    try expectCodes(
        \\module T.Returned
        \\fn f() : UInt8
        \\  [fn(x) x end]
        \\  1
        \\end
    , &.{"MO0313"});
    try expectWhat(
        \\module T.Default
        \\fn f(n: UInt8 = 3) : UInt8
        \\  n
        \\end
    , "MO0312", "n has a default value; parameters have no defaults, so pass 3 at the call.");
}

test "module laws: requires needs a test rejects, processes need a supervisor, verified: is the toolchain's, no self-use" {
    try expectWhat(
        \\module T.Req
        \\fn f(n: UInt8) : UInt8
        \\  requires n > 0
        \\
        \\  n
        \\end
        \\test "calls it, but not as a rejects"
        \\  assert f(1) == 1
        \\end
    , "MO0311", "f has requires n > 0, but no test rejects trips it.");
    try expectCodes(
        \\module T.Req
        \\fn f(n: UInt8) : UInt8
        \\  requires n > 0
        \\
        \\  n
        \\end
        \\test rejects "zero"
        \\  f(0)
        \\end
    , &.{});
    try expectCodes(
        \\module T.Alone
        \\use T.Alone
        \\process P()
        \\  state
        \\    n: UInt8
        \\  end
        \\  message Go
        \\  fn update(state, message)
        \\    case message
        \\      Go:
        \\        state.n += 1
        \\    end
        \\  end
        \\end
        \\verified: types
    , &.{ "MO0318", "MO0317", "MO0316" });
}

test "a use cycle across modules is found and named" {
    const gpa = std.testing.allocator;
    const modules = [_]ModuleUses{
        .{ .path = "A", .uses = &.{"B"} },
        .{ .path = "B", .uses = &.{"C"} },
        .{ .path = "C", .uses = &.{ "D", "A" } },
        .{ .path = "D", .uses = &.{} },
    };
    const cycle = (try useCycle(gpa, &modules)).?;
    defer gpa.free(cycle);
    try std.testing.expectEqual(@as(usize, 4), cycle.len);
    try std.testing.expectEqualStrings("A", cycle[0]);
    try std.testing.expectEqualStrings("A", cycle[3]);
    try std.testing.expect(try useCycle(gpa, modules[3..]) == null);
}
