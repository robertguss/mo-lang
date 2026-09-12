//! The syntax tree as flat arrays. Nodes refer to each other by index, never by
//! pointer, so the tree can be memcpy'd to and from the disk cache (design-v0/07).
//! One node kind per grammar production; the first ones to land are the ones the
//! refund module needs (module, expose, use, intent, never, struct, enum, fn,
//! contracts, statements, expressions, process, supervisor, test, property).
pub const Node = struct {
    kind: Kind,
    main_token: u32,
    /// Meaning depends on `kind`: child index, extra-array range start, or literal index.
    lhs: u32 = 0,
    rhs: u32 = 0,

    pub const Kind = enum { root, module, expose, use, intent, never, todo };
};

pub const Tree = struct {
    nodes: []Node,
    /// Overflow storage for nodes with more than two children.
    extra: []u32,
};
