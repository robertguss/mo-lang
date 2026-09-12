//! Diagnostics teach (design-v0/05): every finding is a structured record with a
//! stable code, a category, a location, `what`, `why` (written once per code in the
//! error catalog), and zero or more machine-applicable fixes with a confidence.
//! Rendered as prose for humans and JSON for agents. There are no warnings.
const std = @import("std");

pub const Category = enum { syntax, types, laws, capabilities, contracts, tests, verified };

pub const Fix = struct {
    description: []const u8,
    confidence: u8, // 0–100
};

pub const Record = struct {
    code: []const u8, // "MO0412"
    category: Category,
    /// Byte offset into the source; line and column are derived at render time.
    at: u32,
    what: []const u8,
    why: []const u8,
    fixes: []const Fix = &.{},
};

pub const List = std.ArrayList(Record);
