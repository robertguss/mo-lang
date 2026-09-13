//! The syntax tree as flat arrays. Nodes refer to each other by index, never by
//! pointer, so the tree can be memcpy'd to and from the disk cache (design-v0/07).
//! One node kind per grammar production. A node has a main token and two u32 slots;
//! a node with more children keeps them in `extra`, either as a span (`start..end`,
//! a run of node or token indices) or as one of the structs below.
//!
//! Node 0 is the root and nothing points at it, and extra[0] is reserved, so 0 in a
//! child slot or an extra-index slot means "absent".
const std = @import("std");
const token = @import("token.zig");

pub const Index = u32;
pub const none: Index = 0;

pub const Node = struct {
    kind: Kind,
    main_token: u32,
    lhs: u32 = 0,
    rhs: u32 = 0,

    /// "span" below means lhs..rhs is a run of extra; "extra X" means lhs indexes
    /// struct X in extra; "token span" is a run of token indices.
    pub const Kind = enum {
        // §2 module
        /// span of the module's items in source order.
        root,
        /// `module` path: lhs path.
        module_decl,
        /// first TypeName; lhs is the last TypeName token.
        path,
        /// token span of exposed names.
        expose,
        /// lhs path; rhs extra Span of imported TypeName tokens, or none.
        use,
        /// lhs string token.
        intent,
        /// lhs string token; rhs comprehension or expression.
        never,
        /// `verified:` and the rest of its line.
        verified,

        // §3 types
        /// name token; span of field.
        struct_decl,
        /// name token; lhs type.
        field,
        /// name token; span of variant.
        enum_decl,
        /// name token; span of field.
        variant,
        /// `type Name = T`: name token; lhs type.
        type_decl,
        /// name token; span of fn_signature.
        trait_decl,
        /// trait name token; lhs type; rhs extra Span of fn_decl.
        impl_decl,
        /// first token; lhs path; rhs extra Span of argument types, or none.
        type_ref,
        /// span of element types.
        type_tuple,
        /// `where`: lhs type; rhs expression.
        type_refined,

        // §4 functions and contracts
        /// name token; lhs extra Signature; rhs extra FnBody.
        fn_decl,
        /// A body-less signature (trait, recipe): name token; lhs extra Signature.
        fn_signature,
        /// name token; lhs type; rhs default value, or none. The grammar has no
        /// defaults; the parser keeps one so the checker can reject it by name.
        param,
        /// `inout` param, same slots.
        param_inout,
        /// `where T: Trait`: TypeName token; lhs path.
        bound,
        /// lhs expression.
        requires,
        /// lhs expression.
        ensures,

        // §5 statements
        /// `x = e`: name token; lhs expression. When x is already a var, the checker
        /// reads this as an assignment; the two are the same text.
        binding,
        /// `var x = e`: name token; lhs expression.
        var_binding,
        /// op token (`=`, `+=`, `-=`); lhs place; rhs expression.
        assign,
        /// lhs expression; rhs trailing condition, or none.
        return_stmt,
        /// loop name token; lhs iterable; rhs extra Span of body.
        for_stmt,
        /// lhs condition; rhs extra If.
        if_stmt,
        /// lhs subject; rhs extra Span of arm.
        case_stmt,
        /// lhs pattern; rhs extra Arm.
        arm,
        /// lhs expression.
        assert_stmt,
        break_stmt,
        /// first token; lhs expression.
        expr_stmt,

        // §6 expressions
        /// op token; lhs, rhs.
        implies,
        or_expr,
        and_expr,
        /// `!`: lhs.
        not_expr,
        /// op token (== != < <= > >=); lhs, rhs.
        compare,
        /// `is`: lhs expression; rhs pattern.
        is_expr,
        /// `..`: lhs, rhs.
        range,
        /// op token (+ -); lhs, rhs.
        add,
        /// op token (* / %); lhs, rhs.
        mul,
        /// unary `-`: lhs.
        negate,
        /// `try`: lhs.
        try_expr,
        /// `x.name`: name token; lhs object.
        member,
        /// `x.name(args)`: name token; lhs receiver; rhs extra Span of args.
        member_call,
        /// `x.0`: int token; lhs object.
        tuple_index,
        /// `f(args)`: `(` token; lhs callee; rhs extra Span of args.
        call,
        /// `name: e`: name token; lhs expression.
        named_arg,
        /// a lowercase name (also `state` and `message` inside update).
        name_ref,
        /// a CapCase name: a type, a variant, a module.
        type_name_ref,
        int_lit,
        float_lit,
        /// a string with no holes.
        string_lit,
        /// string token; span of string_part and expression nodes, in order.
        string_interp,
        /// literal text of an interpolated string: lhs..rhs byte offsets into source.
        string_part,
        true_lit,
        false_lit,
        /// span of elements.
        tuple,
        /// span of elements.
        list,
        /// lhs condition; rhs extra If.
        if_expr,
        /// lhs subject; rhs extra Span of arm.
        case_expr,
        /// `fn`: lhs extra AnonFn.
        anon_fn,
        /// lhs expression.
        old_expr,
        result_ref,
        /// `any(T)`: lhs type.
        any_expr,

        // §7 patterns
        pat_wildcard,
        pat_bind,
        /// literal token.
        pat_literal,
        /// TypeName token; lhs the one positional pattern, or none.
        pat_variant,
        /// TypeName token; span of pat_field.
        pat_record,
        /// name token; lhs pattern.
        pat_field,
        /// span of patterns.
        pat_tuple,
        /// `A | B | C`, a whole arm's pattern: span of the alternatives (step 18).
        pat_or,

        // §8 comprehensions
        /// `for`: lhs extra Comprehension.
        comprehension,
        /// name token; lhs expression.
        generator,

        // §9 processes and supervisors
        /// name token; lhs extra Process.
        process_decl,
        /// span of state_field.
        state_block,
        /// name token; lhs type; rhs initial value, or none.
        state_field,
        /// lhs string token; rhs expression.
        invariant,
        /// name token; lhs extra Span of field, or none; rhs reply type, or none.
        message_decl,
        /// `fn update(state, message)`: lhs case_stmt; rhs its `end` token.
        update_fn,
        /// name token; lhs extra Span of param; rhs extra Span of child.
        supervisor_decl,
        /// TypeName token; lhs extra Child.
        child,

        // §10 tests
        /// string token; span of statements.
        test_decl,
        /// string token; span of statements.
        test_rejects,
        /// string token; lhs comprehension.
        property,

        // §11 recipes
        /// name token; lhs extra Recipe.
        recipe_decl,
        /// token span of TypeNames; empty for `needs nothing`.
        needs,
    };
};

pub const Span = struct { start: u32, end: u32 };

/// A function body: its statements (first, so extraData(Span) reads them too), the
/// newline that ends the signature, and the `end` token. The shape laws count the
/// lines between those two.
pub const FnBody = struct { start: u32, end: u32, open_token: u32, end_token: u32 };

pub const Signature = struct {
    params_start: u32,
    params_end: u32,
    ret: Index,
    bounds_start: u32,
    bounds_end: u32,
    contracts_start: u32,
    contracts_end: u32,
};

pub const If = struct { then_start: u32, then_end: u32, else_start: u32, else_end: u32 };

pub const Arm = struct { guard: Index, body_start: u32, body_end: u32 };

pub const AnonFn = struct { params_start: u32, params_end: u32, body_start: u32, body_end: u32 };

pub const Comprehension = struct { gens_start: u32, gens_end: u32, guard: Index, body_start: u32, body_end: u32 };

pub const Process = struct {
    params_start: u32,
    params_end: u32,
    /// int token, or none
    mailbox: u32,
    state: Index,
    invariants_start: u32,
    invariants_end: u32,
    messages_start: u32,
    messages_end: u32,
    update: Index,
};

pub const Child = struct {
    args_start: u32,
    args_end: u32,
    /// atom token
    restart: u32,
    /// int token, or none
    max_restarts: u32,
    per: Index,
};

pub const Recipe = struct { intent: Index, needs: Index, sigs_start: u32, sigs_end: u32, tests_start: u32, tests_end: u32 };

pub const Tree = struct {
    source: []const u8,
    /// The lexer's tokens, then the tokens of every interpolation hole.
    tokens: []const token.Token,
    nodes: []const Node,
    extra: []const u32,

    pub fn span(t: Tree, start: u32, end: u32) []const u32 {
        return t.extra[start..end];
    }

    pub fn extraData(t: Tree, comptime T: type, index: u32) T {
        var result: T = undefined;
        inline for (@typeInfo(T).@"struct".fields, 0..) |f, i| @field(result, f.name) = t.extra[index + i];
        return result;
    }

    pub fn tokenText(t: Tree, i: u32) []const u8 {
        return t.source[t.tokens[i].start..t.tokens[i].end];
    }
};
