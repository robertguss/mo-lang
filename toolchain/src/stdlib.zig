//! The standard library's rows (design-v0/09-stdlib.md) that vm.zig does not run itself:
//! prelude.zig lists each one, `names` maps it to a `Row`, and `call` runs it on the
//! vm's values. Every row is deterministic: nothing here reads a clock, a random source,
//! or an address. A row whose input comes from outside the program gives an Option or a
//! Result; a row the caller misused crashes with a report, as a tripped contract does.
//!
//! Strings are UTF-8 and counted in graphemes, approximated as a code point with the
//! combining marks after it (`Graphemes`), the same count `size` gives. A result that is
//! part of its receiver is a slice of it: values are immutable, so nothing can tell.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const contracts = @import("contracts.zig");
const crypto_rows = @import("crypto_rows.zig");
const json = @import("json.zig");
const prelude = @import("prelude.zig");
const server_mod = @import("server.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;

pub const Row = enum {
    none,
    string_from_bytes,
    string_byte_size,
    string_chars,
    string_split,
    string_lines,
    string_trim,
    string_ends_with,
    string_contains,
    string_index_of,
    string_slice,
    string_replace,
    string_to_upper,
    string_to_lower,
    string_pad_left,
    string_pad_right,
    string_repeat,
    string_join,
    string_to_u64,
    string_to_i64,
    string_to_f64,
    int_to,
    int_checked_to,
    int_to_f64,
    float_round,
    float_to_string,
    list_get,
    list_slice,
    list_take,
    list_drop,
    list_concat,
    list_reverse,
    list_flat_map,
    list_any,
    list_all,
    list_find,
    list_count,
    list_sort,
    list_sort_by,
    list_sort_by_desc,
    list_min,
    list_max,
    min_of,
    max_of,
    list_sum,
    list_zip,
    list_enumerate,
    list_unique,
    list_group_by,
    map_new,
    map_size,
    map_get,
    map_has,
    map_set,
    map_update,
    map_remove,
    map_keys,
    map_values,
    map_entries,
    set_new,
    set_size,
    set_add,
    set_remove,
    set_has,
    set_to_list,
    time_parse,
    time_from_parts,
    time_to_iso8601,
    time_since,
    duration_ms,
    duration_seconds,
    duration_minutes,
    fs_read_lines,
    fs_read_bytes,
    fs_fold_lines,
    fs_size,
    fs_list,
    fs_list_kinds,
    fs_write,
    fs_append,
    fs_remove,
    fs_rename,
    fs_mkdir,
    fs_replace,
    fs_kind_of,
    /// `Fs.read`, which vm.zig runs; here only for a fixture's files.
    fs_read,
    out_write_line,
    out_flush,
    out_fixture,
    out_written,
    json_encode,
    json_decode,
    json_to_i64,
    deadline_at_most,
    deadline_remaining,
    deadline_fixture,
    option_map,
    string_grouped,
    /// A crypto or Random row (crypto_rows.zig, step 35).
    crypto,
};

pub const names = std.StaticStringMap(Row).initComptime(.{
    .{ "String.from_bytes", .string_from_bytes }, .{ "String.chars", .string_chars },         .{ "String.split", .string_split },
    .{ "String.byte_size", .string_byte_size },
    .{ "String.lines", .string_lines },           .{ "String.trim", .string_trim },           .{ "String.ends_with?", .string_ends_with },
    .{ "String.contains?", .string_contains },    .{ "String.index_of", .string_index_of },   .{ "String.slice", .string_slice },
    .{ "String.replace", .string_replace },       .{ "String.to_upper", .string_to_upper },   .{ "String.to_lower", .string_to_lower },
    .{ "String.pad_left", .string_pad_left },     .{ "String.pad_right", .string_pad_right }, .{ "String.repeat", .string_repeat },
    .{ "String.join", .string_join },             .{ "String.to_u64", .string_to_u64 },       .{ "String.to_i64", .string_to_i64 },
    .{ "String.to_f64", .string_to_f64 },         .{ "Int.to_u8", .int_to },                  .{ "Int.to_u16", .int_to },
    .{ "Int.to_u32", .int_to },                   .{ "Int.to_u64", .int_to },                 .{ "Int.to_i64", .int_to },
    .{ "Int.checked_to_u8", .int_checked_to },    .{ "Int.checked_to_u16", .int_checked_to }, .{ "Int.checked_to_u32", .int_checked_to },
    .{ "Int.checked_to_u64", .int_checked_to },   .{ "Int.checked_to_i64", .int_checked_to }, .{ "Int.to_f64", .int_to_f64 },
    .{ "Float64.round", .float_round },           .{ "Float64.to_string", .float_to_string }, .{ "List.get", .list_get },
    .{ "List.slice", .list_slice },               .{ "List.take", .list_take },               .{ "List.drop", .list_drop },
    .{ "List.concat", .list_concat },             .{ "List.reverse", .list_reverse },         .{ "List.flat_map", .list_flat_map },
    .{ "List.any?", .list_any },                  .{ "List.all?", .list_all },                .{ "List.find", .list_find },
    .{ "List.count", .list_count },               .{ "List.sort", .list_sort },               .{ "List.sort_by", .list_sort_by },
    .{ "List.sort_by_desc", .list_sort_by_desc }, .{ ".min_of", .min_of },                 .{ ".max_of", .max_of },
   
    .{ "List.min", .list_min },                   .{ "List.max", .list_max },                 .{ "List.sum", .list_sum },
    .{ "List.zip", .list_zip },                   .{ "List.enumerate", .list_enumerate },     .{ "List.unique", .list_unique },
    .{ "List.group_by", .list_group_by },         .{ "Map.new", .map_new },                   .{ "Map.size", .map_size },
    .{ "Map.get", .map_get },                     .{ "Map.has?", .map_has },                  .{ "Map.set", .map_set },
    .{ "Map.update", .map_update },               .{ "Map.remove", .map_remove },             .{ "Map.keys", .map_keys },
    .{ "Map.values", .map_values },               .{ "Map.entries", .map_entries },           .{ "Set.new", .set_new },
    .{ "Set.size", .set_size },                   .{ "Set.add", .set_add },                   .{ "Set.remove", .set_remove },
    .{ "Set.has?", .set_has },                    .{ "Set.to_list", .set_to_list },           .{ "Time.parse", .time_parse },
    .{ "Time.from_parts", .time_from_parts },     .{ "Time.to_iso8601", .time_to_iso8601 },   .{ "Time.since", .time_since },
    .{ "Duration.ms", .duration_ms },             .{ "Duration.seconds", .duration_seconds }, .{ "Duration.minutes", .duration_minutes },
    .{ "Fs.read_lines", .fs_read_lines },         .{ "Fs.read_bytes", .fs_read_bytes },
    .{ "Fs.fold_lines", .fs_fold_lines },
            .{ "Fs.size", .fs_size },                   .{ "Fs.list", .fs_list },                   .{ "Fs.list_kinds", .fs_list_kinds },
    .{ "Fs.write", .fs_write },                   .{ "Fs.append", .fs_append },               .{ "Fs.remove", .fs_remove },
    .{ "Fs.rename", .fs_rename },                 .{ "Fs.mkdir", .fs_mkdir },                 .{ "Fs.replace", .fs_replace },             .{ "Fs.kind_of", .fs_kind_of },                 .{ "Out.write_line", .out_write_line },     .{ "Out.flush", .out_flush },
    .{ "Out.fixture", .out_fixture },             .{ "Out.written", .out_written },           .{ "Json.encode", .json_encode },
    .{ "Json.decode", .json_decode },           .{ "Json.to_i64", .json_to_i64 },         .{ "Deadline.at_most", .deadline_at_most }, .{ "Deadline.remaining", .deadline_remaining },
    .{ "Hash.sha256", .crypto },
    .{ "Hash.sha512", .crypto },
    .{ "Hash.hmac_sha256", .crypto },
    .{ "Hash.hkdf_sha256", .crypto },
    .{ "Hash.hex", .crypto },
    .{ "Hash.from_hex", .crypto },
    .{ "Hash.equal?", .crypto },
    .{ "AesGcm.seal", .crypto },
    .{ "AesGcm.open", .crypto },
    .{ "ChaCha.seal", .crypto },
    .{ "ChaCha.open", .crypto },
    .{ "X25519.public", .crypto },
    .{ "X25519.shared", .crypto },
    .{ "Ed25519.public", .crypto },
    .{ "Ed25519.sign", .crypto },
    .{ "Ed25519.verify?", .crypto },
    .{ "Password.hash", .crypto },
    .{ "Password.verify?", .crypto },
    .{ "Random.bytes", .crypto },
    .{ "Random.fixture", .crypto },
    .{ "Deadline.fixture", .deadline_fixture },   .{ "Option.map", .option_map },             .{ "String.grouped", .string_grouped },
});

/// The row each prelude function is, or `none` for the rows vm.zig runs.
pub const row_of = blk: {
    @setEvalBranchQuota(20_000);
    var table: [prelude.fns.len]Row = undefined;
    for (prelude.fns, 0..) |f, i| {
        const head = f.recv[0 .. std.mem.indexOfScalar(u8, f.recv, '(') orelse f.recv.len];
        table[i] = names.get(head ++ "." ++ f.name) orelse .none;
    }
    break :blk table;
};

/// Runs `row` on its arguments, the receiver first. `int_kind` is the receiver's integer
/// kind (a list's element's), or bytecode.none.
pub fn call(vm: *Vm, row: prelude.Fn, which: Row, a: []const Value, int_kind: u32) Error!Value {
    return switch (which) {
        .none => unreachable,
        .json_encode => json.encode(vm, a[0], int_kind),
        .crypto => crypto_rows.call(vm, row, a),
        .json_decode => json.decode(vm, a[0].string),
        .json_to_i64 => option(vm, json.whole(a[0])),
        // The earlier of the deadline and now plus d: a nested deadline tightens, never extends.
        .deadline_at_most => .{ .time = if (vm.sim) |s| @min(a[0].time, s.deadlineNow() +| a[1].duration) else a[0].time },
        // What remains of the deadline on the runtime's clock, zero once it has passed (step 24).
        .deadline_remaining => .{ .duration = @max(a[0].time - (if (vm.sim) |s| s.deadlineNow() else 0), 0) },
        // A test has no asker: a deadline d from now on the run's clock, for a function that takes one.
        .deadline_fixture => .{ .time = (if (vm.sim) |s| s.deadlineNow() else 0) +| a[0].duration },
        .time_parse => if (parseTime(a[0].string)) |t| vm.variant("Some", &.{.{ .time = t }}) else vm.variant("None", &.{}),
        .time_from_parts => blk: {
            var parts: [6]i64 = undefined;
            for (&parts, a[0..6]) |*p, v| p.* = std.math.cast(i64, v.int) orelse std.math.maxInt(i64);
            const t = instant(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]) orelse
                return fail(vm, .other, row, "{d}-{d}-{d} {d}:{d}:{d} is not a date and time in the years 0 to 9999", .{ a[0].int, a[1].int, a[2].int, a[3].int, a[4].int, a[5].int });
            break :blk .{ .time = t };
        },
        .time_to_iso8601 => blk: {
            var buf: [40]u8 = undefined;
            break :blk .{ .string = try vm_mod.rawDupe(vm.heap, u8, iso8601(&buf, a[0].time)) };
        },
        .time_since => .{ .duration = std.math.sub(i64, a[0].time, a[1].time) catch return fail(vm, .overflow, row, "the span does not fit a Duration", .{}) },
        .duration_ms => .{ .int = a[0].duration },
        .duration_seconds => .{ .float = @as(f64, @floatFromInt(a[0].duration)) / 1000.0 },
        .duration_minutes => .{ .float = @as(f64, @floatFromInt(a[0].duration)) / 60_000.0 },
        // Some(x) is Some of the function's value, None stays None (step 28).
        .option_map => if (a[0].variant.fields.len == 1) vm.variant("Some", &.{try vm.invoke(a[1].func, &.{a[0].variant.fields[0]})}) else a[0],
        .string_grouped => .{ .string = try groupedText(vm, a[0].int) },
        .fs_read_lines, .fs_read_bytes, .fs_fold_lines, .fs_size, .fs_list, .fs_list_kinds, .fs_write, .fs_append, .fs_remove, .fs_rename, .fs_mkdir, .fs_replace, .fs_kind_of, .fs_read => files(vm, row, which, a),
        .out_write_line => blk: {
            try writeOut(vm, row, a[0].cap, a[1].string, true);
            break :blk .none;
        },
        .out_flush => blk: {
            if (vm.server) |s| s.flush(a[0].cap);
            break :blk .none;
        },
        .out_fixture => blk: {
            const sim = vm.sim orelse return fail(vm, .other, row, "Out.fixture() runs only in a test", .{});
            try sim.outs.append(sim.gpa, .empty);
            break :blk .{ .cap = .{ .kind = .out, .handle = @intCast(sim.outs.items.len) } };
        },
        .out_written => blk: {
            const sim = vm.sim orelse break :blk .{ .list = &.{} };
            const h = a[0].cap.handle;
            if (vm.server != null or h == 0 or h > sim.outs.items.len) break :blk .{ .list = &.{} };
            const kept = sim.outs.items[h - 1].items;
            const out = try vm_mod.rawAlloc(vm.heap, Value, kept.len);
            for (kept, out) |text, *o| o.* = .{ .string = text };
            break :blk .{ .list = out };
        },
        .list_group_by => groupBy(vm, a[0].list, a[1].func),
        .map_new => .{ .map = .{ .entries = &.{} } },
        .set_new => .{ .set = .{ .entries = &.{} } },
        .map_size => .{ .int = @intCast(a[0].map.entries.len / 2) },
        .set_size => .{ .int = @intCast(a[0].set.entries.len) },
        .map_get => if (find(a[0].map, 2, a[1])) |k| vm.variant("Some", &.{a[0].map.entries[k + 1]}) else vm.variant("None", &.{}),
        .map_has => .{ .bool = find(a[0].map, 2, a[1]) != null },
        .set_has => .{ .bool = find(a[0].set, 1, a[1]) != null },
        .map_set => .{ .map = try put(vm, a[0].map, 2, a[1], a[2], int_kind) },
        .map_update => blk: {
            const current = if (find(a[0].map, 2, a[1])) |k| a[0].map.entries[k + 1] else a[2];
            const next = try vm.invoke(a[3].func, &.{current});
            // In a map, a value never holds a buffer alone (vm.disownIn).
            vm.disownIn(next);
            break :blk .{ .map = try put(vm, a[0].map, 2, a[1], next, int_kind) };
        },
        .set_add => .{ .set = try put(vm, a[0].set, 1, a[1], .none, int_kind) },
        .map_remove => .{ .map = try without(vm, a[0].map, 2, a[1], int_kind) },
        .set_remove => .{ .set = try without(vm, a[0].set, 1, a[1], int_kind) },
        .map_keys, .map_values => blk: {
            const xs = a[0].map.entries;
            const out = try vm_mod.rawAlloc(vm.heap, Value, xs.len / 2);
            const offset: usize = if (which == .map_keys) 0 else 1;
            for (out, 0..) |*o, k| o.* = xs[2 * k + offset];
            break :blk .{ .list = out };
        },
        .map_entries => blk: {
            const xs = a[0].map.entries;
            const pairs = try vm_mod.rawDupe(vm.heap, Value, xs);
            const out = try vm_mod.rawAlloc(vm.heap, Value, xs.len / 2);
            for (out, 0..) |*o, k| o.* = .{ .tuple = pairs[2 * k .. 2 * k + 2] };
            break :blk .{ .list = out };
        },
        .set_to_list => .{ .list = try vm_mod.rawDupe(vm.heap, Value, a[0].set.entries) },
        .list_get => if (a[1].int < a[0].list.len) vm.variant("Some", &.{a[0].list[@intCast(a[1].int)]}) else vm.variant("None", &.{}),
        .list_slice => .{ .list = cut(a[0].list, a[1].int, a[2].int) },
        .list_take => .{ .list = cut(a[0].list, 0, a[1].int) },
        .list_drop => .{ .list = cut(a[0].list, a[1].int, a[0].list.len) },
        .list_concat => .{ .list = try concat(vm, a[0].list, a[1].list) },
        .list_reverse => blk: {
            const xs = a[0].list;
            const out = try vm_mod.rawAlloc(vm.heap, Value, xs.len);
            for (xs, 0..) |x, k| out[xs.len - 1 - k] = x;
            break :blk .{ .list = out };
        },
        .list_flat_map => flatMap(vm, a[0].list, a[1].func),
        .list_any, .list_all, .list_find, .list_count => scan(vm, which, a[0].list, a[1].func),
        .list_sort => blk: {
            const out = try vm_mod.rawAlloc(vm.heap, Value, a[0].list.len);
            @memcpy(out, a[0].list);
            std.sort.block(Value, out, {}, before);
            break :blk .{ .list = out };
        },
        .list_sort_by, .list_sort_by_desc => sortBy(vm, a[0].list, a[1].func, which == .list_sort_by_desc),
        // The first of two that order level, as min and max give the first of a list's.
        .min_of => if (vm_mod.order(a[1], a[0]) == .lt) a[1] else a[0],
        .max_of => if (vm_mod.order(a[1], a[0]) == .gt) a[1] else a[0],
        .list_min, .list_max => blk: {
            const xs = a[0].list;
            if (xs.len == 0) break :blk vm.variant("None", &.{});
            const want: std.math.Order = if (which == .list_min) .lt else .gt;
            var best = xs[0];
            for (xs[1..]) |x| if (vm_mod.order(x, best) == want) {
                best = x;
            };
            break :blk vm.variant("Some", &.{best});
        },
        .list_sum => blk: {
            var total: i128 = 0;
            for (a[0].list) |x| {
                total = std.math.add(i128, total, x.int) catch return fail(vm, .overflow, row, "the sum passes every integer", .{});
                if (int_kind == bytecode.none) continue;
                const k: types.IntKind = @enumFromInt(int_kind);
                if (total < vm_mod.minOf(k) or total > vm_mod.maxOf(k)) return fail(vm, .overflow, row, "the sum reaches {d}, past its {t} elements", .{ total, k });
            }
            break :blk .{ .int = total };
        },
        .list_zip, .list_enumerate => blk: {
            const xs = a[0].list;
            const n = if (which == .list_zip) @min(xs.len, a[1].list.len) else xs.len;
            const pairs = try vm_mod.rawAlloc(vm.heap, Value, 2 * n);
            const out = try vm_mod.rawAlloc(vm.heap, Value, n);
            for (out, 0..) |*o, k| {
                pairs[2 * k] = if (which == .list_zip) xs[k] else .{ .int = @intCast(k) };
                pairs[2 * k + 1] = if (which == .list_zip) a[1].list[k] else xs[k];
                o.* = .{ .tuple = pairs[2 * k .. 2 * k + 2] };
            }
            break :blk .{ .list = out };
        },
        .list_unique => blk: {
            var seen: std.HashMapUnmanaged(Value, void, ValueContext, 80) = .empty;
            defer seen.deinit(vm.gpa);
            const out = try vm_mod.rawAlloc(vm.heap, Value, a[0].list.len);
            var n: usize = 0;
            for (a[0].list) |x| {
                if ((try seen.getOrPut(vm.gpa, x)).found_existing) continue;
                out[n] = x;
                n += 1;
            }
            break :blk .{ .list = out[0..n] };
        },
        .string_from_bytes => fromBytes(vm, a[0].list),
        .string_byte_size => .{ .int = @intCast(a[0].string.len) },
        .string_chars => .{ .list = try chars(vm, a[0].string) },
        .string_split => split(vm, a[0].string, a[1].string),
        .string_lines => lines(vm, a[0].string),
        .string_trim => .{ .string = trim(a[0].string) },
        .string_ends_with => .{ .bool = std.mem.endsWith(u8, a[0].string, a[1].string) },
        .string_contains => .{ .bool = std.mem.indexOf(u8, a[0].string, a[1].string) != null },
        .string_index_of => if (std.mem.indexOf(u8, a[0].string, a[1].string)) |at|
            vm.variant("Some", &.{.{ .int = count(a[0].string[0..at]) }})
        else
            vm.variant("None", &.{}),
        .string_slice => .{ .string = slice(a[0].string, a[1].int, a[2].int) },
        .string_replace => replace(vm, a[0].string, a[1].string, a[2].string),
        .string_to_upper, .string_to_lower => blk: {
            const out = try vm_mod.rawAlloc(vm.heap, u8, a[0].string.len);
            if (which == .string_to_upper) _ = std.ascii.upperString(out, a[0].string) else _ = std.ascii.lowerString(out, a[0].string);
            break :blk .{ .string = out };
        },
        .string_pad_left, .string_pad_right => pad(vm, row, a[0].string, a[1].int, a[2].string, which == .string_pad_left),
        .string_repeat => repeat(vm, row, a[0].string, a[1].int),
        .string_join => join(vm, row, a[0].list, a[1].string),
        .string_to_u64 => option(vm, parseWhole(a[0].string, false, .u64)),
        .string_to_i64 => option(vm, parseWhole(a[0].string, true, .i64)),
        .string_to_f64 => if (parseFloat(a[0].string)) |x| vm.variant("Some", &.{.{ .float = x }}) else vm.variant("None", &.{}),
        .int_to => blk: {
            const kind = targetKind(row.name);
            if (a[0].int < vm_mod.minOf(kind) or a[0].int > vm_mod.maxOf(kind)) {
                return fail(vm, .overflow, row, "{d}.{s} does not fit {s}", .{ a[0].int, row.name, row.ret });
            }
            break :blk a[0];
        },
        .int_checked_to => blk: {
            const kind = targetKind(row.name);
            const fits = a[0].int >= vm_mod.minOf(kind) and a[0].int <= vm_mod.maxOf(kind);
            break :blk if (fits) vm.variant("Some", &.{a[0]}) else vm.variant("None", &.{});
        },
        .int_to_f64 => .{ .float = @floatFromInt(a[0].int) },
        .float_round, .float_to_string => blk: {
            const x = a[0].float;
            const places = a[1].int;
            if (places > max_places) return fail(vm, .other, row, "{s}({d}) rounds to at most {d} places", .{ row.name, places, max_places });
            if (std.math.isNan(x) or std.math.isInf(x)) {
                if (which == .float_round) break :blk a[0];
                break :blk .{ .string = if (std.math.isNan(x)) "NaN" else if (x > 0) "Infinity" else "-Infinity" };
            }
            var buf: [decimal_buffer]u8 = undefined;
            const text = rounded(&buf, x, @intCast(places));
            if (which == .float_round) break :blk .{ .float = std.fmt.parseFloat(f64, text) catch unreachable };
            break :blk .{ .string = try vm_mod.rawDupe(vm.heap, u8, text) };
        },
    };
}

fn fail(vm: *Vm, kind: contracts.Kind, row: prelude.Fn, comptime format: []const u8, args: anytype) Error {
    vm.report = .{ .kind = kind, .clause = try std.fmt.allocPrint(vm.gpa, format, args), .within = row.name, .at = 0 };
    return error.Crash;
}

fn option(vm: *Vm, v: ?i128) Error!Value {
    return if (v) |x| vm.variant("Some", &.{.{ .int = x }}) else vm.variant("None", &.{});
}

// ---- graphemes

/// A string's graphemes, in order: each is one code point and the combining marks after
/// it. A byte that does not start valid UTF-8 is a grapheme of its own.
pub const Graphemes = struct {
    s: []const u8,
    i: usize = 0,

    pub fn next(g: *Graphemes) ?[]const u8 {
        if (g.i >= g.s.len) return null;
        const start = g.i;
        g.i += codePoint(g.s, g.i).len;
        while (g.i < g.s.len) {
            const cp = codePoint(g.s, g.i);
            if (!combining(cp.value)) break;
            g.i += cp.len;
        }
        return g.s[start..g.i];
    }
};

const CodePoint = struct { value: u21, len: usize };

/// The code point at byte `i`; an invalid byte reads as U+FFFD, one byte long.
fn codePoint(s: []const u8, i: usize) CodePoint {
    const bad: CodePoint = .{ .value = 0xFFFD, .len = 1 };
    const len = std.unicode.utf8ByteSequenceLength(s[i]) catch return bad;
    if (i + len > s.len) return bad;
    const value = std.unicode.utf8Decode(s[i .. i + len]) catch return bad;
    return .{ .value = value, .len = len };
}

fn combining(cp: u21) bool {
    return (cp >= 0x300 and cp <= 0x36F) or (cp >= 0x1AB0 and cp <= 0x1AFF) or (cp >= 0x1DC0 and cp <= 0x1DFF) or (cp >= 0x20D0 and cp <= 0x20FF) or (cp >= 0xFE20 and cp <= 0xFE2F);
}

/// Graphemes in `s`: what `size` gives.
pub fn count(s: []const u8) i128 {
    var g: Graphemes = .{ .s = s };
    var n: i128 = 0;
    while (g.next() != null) n += 1;
    return n;
}

/// The byte offset where grapheme `index` starts, or `s.len` past the last.
fn byteOffset(s: []const u8, index: i128) usize {
    var g: Graphemes = .{ .s = s };
    var n: i128 = 0;
    while (n < index) : (n += 1) {
        if (g.next() == null) break;
    }
    return g.i;
}

fn whitespace(cp: u21) bool {
    return switch (cp) {
        0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 => true,
        else => false,
    };
}

// ---- strings

fn fromBytes(vm: *Vm, bytes: []const Value) Error!Value {
    const out = try vm_mod.rawAlloc(vm.heap, u8, bytes.len);
    for (bytes, out) |b, *o| o.* = @intCast(b.int);
    if (!std.unicode.utf8ValidateSlice(out)) return vm.variant("None", &.{});
    return vm.variant("Some", &.{.{ .string = out }});
}

fn chars(vm: *Vm, s: []const u8) Error![]const Value {
    const out = try vm_mod.rawAlloc(vm.heap, Value, @intCast(count(s)));
    var g: Graphemes = .{ .s = s };
    for (out) |*o| o.* = .{ .string = g.next().? };
    return out;
}

fn split(vm: *Vm, s: []const u8, sep: []const u8) Error!Value {
    if (sep.len == 0) return .{ .list = try chars(vm, s) };
    const out = try vm_mod.rawAlloc(vm.heap, Value, std.mem.count(u8, s, sep) + 1);
    var it = std.mem.splitSequence(u8, s, sep);
    for (out) |*o| o.* = .{ .string = it.next().? };
    return .{ .list = out };
}

fn lines(vm: *Vm, s: []const u8) Error!Value {
    if (s.len == 0) return .{ .list = &.{} };
    const body = if (s[s.len - 1] == '\n') s[0 .. s.len - 1] else s;
    const out = try vm_mod.rawAlloc(vm.heap, Value, std.mem.count(u8, body, "\n") + 1);
    var it = std.mem.splitScalar(u8, body, '\n');
    for (out) |*o| {
        const line = it.next().?;
        o.* = .{ .string = if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line };
    }
    return .{ .list = out };
}

/// `Fs.fold_lines`: bytes as they are read, split as `lines` splits a whole text (at each
/// "\n", without it and one "\r" before it, then what follows the last "\n" when it is not
/// empty), each line handed to the function in turn with the value so far; what the call gives
/// is the safe point's one root and the value handed with the next line, so a file of any size
/// is read in the memory of its longest line and the value.
pub const LineFeed = struct {
    vm: *Vm,
    f: Value.Func,
    /// Its safe points compact in generations (Vm.foldStep, step 29).
    fold: Vm.Fold,
    /// A line begun in bytes read so far, waiting for its "\n".
    partial: std.ArrayList(u8) = .empty,
    /// The value so far, from `init`.
    acc: Value,

    pub fn init(vm: *Vm, f: Value.Func, acc: Value) LineFeed {
        return .{ .vm = vm, .f = f, .fold = vm.foldMark(), .acc = acc };
    }

    pub fn bytes(l: *LineFeed, chunk: []const u8) Error!void {
        var rest = chunk;
        while (std.mem.indexOfScalar(u8, rest, '\n')) |at| {
            if (l.partial.items.len > 0) {
                try l.partial.appendSlice(l.vm.gpa, rest[0..at]);
                try l.line(l.partial.items);
                l.partial.clearRetainingCapacity();
            } else try l.line(rest[0..at]);
            rest = rest[at + 1 ..];
        }
        try l.partial.appendSlice(l.vm.gpa, rest);
    }

    pub fn end(l: *LineFeed) Error!void {
        if (l.partial.items.len > 0) try l.line(l.partial.items);
        l.partial.deinit(l.vm.gpa);
    }

    fn line(l: *LineFeed, raw: []const u8) Error!void {
        const text = if (raw.len > 0 and raw[raw.len - 1] == '\r') raw[0 .. raw.len - 1] else raw;
        const handed: Value = .{ .string = try replaced(l.vm, text) };
        var roots = [1]Value{try l.vm.invoke(l.f, &.{ l.acc, handed })};
        try l.vm.foldStep(&l.fold, &roots);
        l.acc = roots[0];
    }
};

/// A line as `fold_lines` hands it on (step 27): its bytes when they are UTF-8, and otherwise each
/// byte that begins no UTF-8 character replaced by U+FFFD, so the caller counts the line and
/// folds on. runtime/mo_rt.c's replaced_line is the same.
fn replaced(vm: *Vm, text: []const u8) Error![]const u8 {
    if (std.unicode.utf8ValidateSlice(text)) return vm_mod.rawDupe(vm.heap, u8, text);
    const mark = "\u{FFFD}";
    var size: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const cp = codePoint(text, i);
        size += if (cp.len == 1 and cp.value == 0xFFFD) mark.len else cp.len;
        i += cp.len;
    }
    const out = try vm_mod.rawAlloc(vm.heap, u8, size);
    var o: usize = 0;
    i = 0;
    while (i < text.len) {
        const cp = codePoint(text, i);
        const piece: []const u8 = if (cp.len == 1 and cp.value == 0xFFFD) mark else text[i .. i + cp.len];
        @memcpy(out[o .. o + piece.len], piece);
        o += piece.len;
        i += cp.len;
    }
    return out;
}

fn trim(s: []const u8) []const u8 {
    var start: ?usize = null;
    var end: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const cp = codePoint(s, i);
        if (!whitespace(cp.value)) {
            if (start == null) start = i;
            end = i + cp.len;
        }
        i += cp.len;
    }
    return if (start) |from| s[from..end] else s[0..0];
}

fn slice(s: []const u8, from: i128, to: i128) []const u8 {
    const end = byteOffset(s, to);
    const start = byteOffset(s, @min(from, to));
    return s[@min(start, end)..end];
}

fn replace(vm: *Vm, s: []const u8, a: []const u8, b: []const u8) Error!Value {
    if (a.len == 0) return .{ .string = s };
    const n = std.mem.count(u8, s, a);
    if (n == 0) return .{ .string = s };
    const out = try vm_mod.rawAlloc(vm.heap, u8, s.len - n * a.len + n * b.len);
    _ = std.mem.replace(u8, s, a, b, out);
    return .{ .string = out };
}

fn pad(vm: *Vm, row: prelude.Fn, s: []const u8, n: i128, ch: []const u8, left: bool) Error!Value {
    if (count(ch) != 1) return fail(vm, .other, row, "{s} pads with one grapheme, not \"{s}\"", .{ row.name, ch });
    const size = count(s);
    if (size >= n) return .{ .string = s };
    const missing: usize = @intCast(n - size);
    const extra = std.math.mul(usize, missing, ch.len) catch return fail(vm, .overflow, row, "{s}({d}) is too long a string", .{ row.name, n });
    const out = try vm_mod.rawAlloc(vm.heap, u8, s.len + extra);
    const fill = if (left) out[0..extra] else out[s.len..];
    for (0..missing) |k| @memcpy(fill[k * ch.len ..][0..ch.len], ch);
    @memcpy(if (left) out[extra..] else out[0..s.len], s);
    return .{ .string = out };
}

fn repeat(vm: *Vm, row: prelude.Fn, s: []const u8, n: i128) Error!Value {
    const times = std.math.cast(usize, n) orelse return fail(vm, .overflow, row, "repeat({d}) is too long a string", .{n});
    const len = std.math.mul(usize, s.len, times) catch return fail(vm, .overflow, row, "repeat({d}) is too long a string", .{n});
    const out = try vm_mod.rawAlloc(vm.heap, u8, len);
    for (0..times) |k| @memcpy(out[k * s.len ..][0..s.len], s);
    return .{ .string = out };
}

fn join(vm: *Vm, row: prelude.Fn, xs: []const Value, sep: []const u8) Error!Value {
    _ = row;
    if (xs.len == 0) return .{ .string = "" };
    var len: usize = sep.len * (xs.len - 1);
    for (xs) |x| len += x.string.len;
    const out = try vm_mod.rawAlloc(vm.heap, u8, len);
    var at: usize = 0;
    for (xs, 0..) |x, k| {
        if (k > 0) {
            @memcpy(out[at..][0..sep.len], sep);
            at += sep.len;
        }
        @memcpy(out[at..][0..x.string.len], x.string);
        at += x.string.len;
    }
    return .{ .string = out };
}

// ---- lists

/// `xs[from..to]` with both bounds clamped to the list.
fn cut(xs: []const Value, from: i128, to: i128) []const Value {
    const hi: usize = @intCast(@min(to, @as(i128, @intCast(xs.len))));
    const lo: usize = @intCast(@min(from, @as(i128, @intCast(hi))));
    return xs[lo..hi];
}

fn concat(vm: *Vm, xs: []const Value, ys: []const Value) Error![]const Value {
    if (ys.len == 0) return xs;
    if (xs.len == 0) return ys;
    const out = try vm_mod.rawAlloc(vm.heap, Value, xs.len + ys.len);
    @memcpy(out[0..xs.len], xs);
    @memcpy(out[xs.len..], ys);
    return out;
}

fn before(_: void, a: Value, b: Value) bool {
    return vm_mod.order(a, b) == .lt;
}

/// Nothing survives a step of `scan`: its only state is a count.
var no_roots: [0]Value = .{};

/// `any?`, `all?`, `find`, and `count`: each step is a safe point, and the first three stop
/// at the element that settles them.
fn scan(vm: *Vm, which: Row, xs: []const Value, f: Value.Func) Error!Value {
    const from = vm.mark();
    var kept: usize = 0;
    var n: i128 = 0;
    for (xs) |x| {
        const hit = (try vm.invoke(f, &.{x})).bool;
        switch (which) {
            .list_any => if (hit) return .{ .bool = true },
            .list_all => if (!hit) return .{ .bool = false },
            .list_find => if (hit) return vm.variant("Some", &.{x}),
            else => n += @intFromBool(hit),
        }
        kept = try vm.iterate(from, &no_roots, kept);
    }
    return switch (which) {
        .list_any => .{ .bool = false },
        .list_all => .{ .bool = true },
        .list_find => vm.variant("None", &.{}),
        else => .{ .int = n },
    };
}

fn flatMap(vm: *Vm, xs: []const Value, f: Value.Func) Error!Value {
    const parts = try vm_mod.rawAlloc(vm.heap, Value, xs.len);
    const from = vm.mark();
    var kept: usize = 0;
    var len: usize = 0;
    for (xs, 0..) |x, i| {
        parts[i] = try vm.invoke(f, &.{x});
        len += parts[i].list.len;
        kept = try vm.iterate(from, parts[0 .. i + 1], kept);
    }
    const out = try vm_mod.rawAlloc(vm.heap, Value, len);
    var at: usize = 0;
    for (parts) |p| {
        @memcpy(out[at..][0..p.list.len], p.list);
        at += p.list.len;
    }
    return .{ .list = out };
}

/// Each key is computed once; the positions are sorted by key, stably.
fn sortBy(vm: *Vm, xs: []const Value, f: Value.Func, descending: bool) Error!Value {
    const keys = try vm_mod.rawAlloc(vm.heap, Value, xs.len);
    const from = vm.mark();
    var kept: usize = 0;
    for (xs, 0..) |x, i| {
        keys[i] = try vm.invoke(f, &.{x});
        kept = try vm.iterate(from, keys[0 .. i + 1], kept);
    }
    const positions = try vm.gpa.alloc(u32, xs.len);
    defer vm.gpa.free(positions);
    for (positions, 0..) |*p, i| p.* = @intCast(i);
    // Stable either way: keys that order level keep the list's order.
    const By = struct { keys: []const Value, descending: bool };
    std.sort.block(u32, positions, By{ .keys = keys, .descending = descending }, struct {
        fn lt(by: By, a: u32, b: u32) bool {
            return vm_mod.order(by.keys[a], by.keys[b]) == @as(std.math.Order, if (by.descending) .gt else .lt);
        }
    }.lt);
    const out = try vm_mod.rawAlloc(vm.heap, Value, xs.len);
    for (positions, out) |p, *o| o.* = xs[p];
    return .{ .list = out };
}

fn groupBy(vm: *Vm, xs: []const Value, f: Value.Func) Error!Value {
    const keys = try vm_mod.rawAlloc(vm.heap, Value, xs.len);
    const from = vm.mark();
    var kept: usize = 0;
    for (xs, 0..) |x, i| {
        keys[i] = try vm.invoke(f, &.{x});
        vm.disownIn(keys[i]);
        kept = try vm.iterate(from, keys[0 .. i + 1], kept);
    }
    const gpa = vm.gpa;
    var index: std.HashMapUnmanaged(Value, u32, ValueContext, 80) = .empty;
    defer index.deinit(gpa);
    // Per group: its first element's position and its size; per element: its group.
    var firsts: std.ArrayList(u32) = .empty;
    defer firsts.deinit(gpa);
    var sizes: std.ArrayList(u32) = .empty;
    defer sizes.deinit(gpa);
    const group_of = try gpa.alloc(u32, xs.len);
    defer gpa.free(group_of);
    for (keys, 0..) |key, i| {
        const found = try index.getOrPut(gpa, key);
        if (!found.found_existing) {
            found.value_ptr.* = @intCast(firsts.items.len);
            try firsts.append(gpa, @intCast(i));
            try sizes.append(gpa, 0);
        }
        group_of[i] = found.value_ptr.*;
        sizes.items[found.value_ptr.*] += 1;
    }
    // Every group's list is a run of one block, in element order.
    const block = try vm_mod.rawAlloc(vm.heap, Value, xs.len);
    const entries = try vm_mod.rawAlloc(vm.heap, Value, 2 * firsts.items.len);
    const filled = try gpa.alloc(u32, firsts.items.len);
    defer gpa.free(filled);
    var start: usize = 0;
    for (firsts.items, sizes.items, filled, 0..) |first, size, *fill, g| {
        fill.* = @intCast(start);
        entries[2 * g] = keys[first];
        entries[2 * g + 1] = .{ .list = block[start .. start + size] };
        start += size;
    }
    for (xs, group_of) |x, g| {
        block[filled[g]] = x;
        filled[g] += 1;
    }
    return .{ .map = try mapOf(vm.heap, entries, 2) };
}

// ---- time

const ms_per_day: i64 = 86_400_000;

/// Days from 1970-01-01 to a date of the proleptic Gregorian calendar (Hinnant's
/// days_from_civil).
fn daysFromCivil(year: i64, month: i64, day: i64) i64 {
    const y = if (month <= 2) year - 1 else year;
    const era = @divFloor(y, 400);
    const of_era = y - era * 400;
    const of_year = @divFloor(153 * @mod(month + 9, 12) + 2, 5) + day - 1;
    const days = of_era * 365 + @divFloor(of_era, 4) - @divFloor(of_era, 100) + of_year;
    return era * 146_097 + days - 719_468;
}

const Civil = struct { year: i64, month: i64, day: i64 };

/// The date `days` after 1970-01-01 (Hinnant's civil_from_days).
fn civilFromDays(days: i64) Civil {
    const z = days + 719_468;
    const era = @divFloor(z, 146_097);
    const of_era = z - era * 146_097;
    const year_of_era = @divFloor(of_era - @divFloor(of_era, 1460) + @divFloor(of_era, 36_524) - @divFloor(of_era, 146_096), 365);
    const of_year = of_era - (365 * year_of_era + @divFloor(year_of_era, 4) - @divFloor(year_of_era, 100));
    const mp = @divFloor(5 * of_year + 2, 153);
    const month = if (mp < 10) mp + 3 else mp - 9;
    return .{ .year = year_of_era + era * 400 + @intFromBool(month <= 2), .month = month, .day = of_year - @divFloor(153 * mp + 2, 5) + 1 };
}

fn daysIn(year: i64, month: i64) i64 {
    return switch (month) {
        2 => if (@mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0)) 29 else 28,
        4, 6, 9, 11 => 30,
        else => 31,
    };
}

/// Milliseconds since the epoch of a UTC date and time that exist in the years 0 to 9999;
/// null for any other.
fn instant(year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64) ?i64 {
    if (year < 0 or year > 9999 or month < 1 or month > 12 or day < 1 or day > daysIn(year, month)) return null;
    if (hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0 or second > 59) return null;
    return ((daysFromCivil(year, month, day) * 24 + hour) * 60 + minute) * 60_000 + second * 1000;
}

/// Digits only, as a number; null when any byte is not a digit.
fn fixedDigits(digits: []const u8) ?i64 {
    var v: i64 = 0;
    for (digits) |d| {
        if (!std.ascii.isDigit(d)) return null;
        v = v * 10 + (d - '0');
    }
    return v;
}

/// RFC 3339: `2026-09-12T10:00:02Z`, optional fractional seconds kept to the millisecond,
/// and `Z` or an offset `+02:00`.
pub fn parseTime(s: []const u8) ?i64 {
    if (s.len < 20) return null;
    if (s[4] != '-' or s[7] != '-' or (s[10] != 'T' and s[10] != 't') or s[13] != ':' or s[16] != ':') return null;
    const year = fixedDigits(s[0..4]) orelse return null;
    const month = fixedDigits(s[5..7]) orelse return null;
    const day = fixedDigits(s[8..10]) orelse return null;
    const hour = fixedDigits(s[11..13]) orelse return null;
    const minute = fixedDigits(s[14..16]) orelse return null;
    const second = fixedDigits(s[17..19]) orelse return null;
    var i: usize = 19;
    var ms: i64 = 0;
    if (s[i] == '.') {
        i += 1;
        const start = i;
        while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
        if (i == start or i - start > 9) return null;
        for (0..3) |k| ms = ms * 10 + (if (start + k < i) @as(i64, s[start + k] - '0') else 0);
    }
    if (i >= s.len) return null;
    var offset: i64 = 0;
    if (s[i] == 'Z' or s[i] == 'z') {
        i += 1;
    } else if (s[i] == '+' or s[i] == '-') {
        if (s.len - i != 6 or s[i + 3] != ':') return null;
        const hours = fixedDigits(s[i + 1 .. i + 3]) orelse return null;
        const minutes = fixedDigits(s[i + 4 .. i + 6]) orelse return null;
        if (hours > 23 or minutes > 59) return null;
        offset = (hours * 60 + minutes) * 60_000;
        if (s[i] == '-') offset = -offset;
        i += 6;
    } else return null;
    if (i != s.len) return null;
    return (instant(year, month, day, hour, minute, second) orelse return null) + ms - offset;
}

/// `2026-09-12T10:00:02Z`, with `.mmm` when the milliseconds are not zero.
pub fn iso8601(buf: *[40]u8, t: i64) []const u8 {
    const c = civilFromDays(@divFloor(t, ms_per_day));
    const in_day: u64 = @intCast(@mod(t, ms_per_day));
    var w: std.Io.Writer = .fixed(buf);
    if (c.year >= 0 and c.year <= 9999) {
        w.print("{d:0>4}", .{@as(u64, @intCast(c.year))}) catch unreachable;
    } else {
        w.print("{d}", .{c.year}) catch unreachable;
    }
    w.print("-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{ @as(u64, @intCast(c.month)), @as(u64, @intCast(c.day)), in_day / 3_600_000, in_day / 60_000 % 60, in_day / 1000 % 60 }) catch unreachable;
    if (in_day % 1000 != 0) w.print(".{d:0>3}", .{in_day % 1000}) catch unreachable;
    w.writeAll("Z") catch unreachable;
    return w.buffered();
}

test "the calendar round-trips, leap days and the years before 1970 included" {
    var buf: [40]u8 = undefined;
    try std.testing.expectEqual(@as(?i64, 0), parseTime("1970-01-01T00:00:00Z"));
    try std.testing.expectEqualStrings("1969-12-31T23:59:59.999Z", iso8601(&buf, -1));
    try std.testing.expectEqualStrings("2026-01-01T00:00:00Z", iso8601(&buf, vm_mod.fixture_time));
    try std.testing.expectEqual(parseTime("2026-09-12T10:00:02Z"), parseTime("2026-09-12T12:00:02+02:00"));
    try std.testing.expectEqual(@as(?i64, null), parseTime("2023-02-29T00:00:00Z"));
    try std.testing.expectEqual(@as(?i64, null), parseTime("2026-09-12T10:00:60Z"));
    try std.testing.expectEqual(@as(?i64, null), parseTime("2026-09-12T10:00:02.Z"));
    var day: i64 = -800_000;
    while (day < 800_000) : (day += 997) {
        const c = civilFromDays(day);
        try std.testing.expectEqual(day, daysFromCivil(c.year, c.month, c.day));
    }
    const back = parseTime(iso8601(&buf, 1_789_200_123_456)).?;
    try std.testing.expectEqual(@as(i64, 1_789_200_123_456), back);
}

// ---- files

/// An `EntryKind`: a link is its own kind, never what it points at (step 40).
pub const EntryKind = enum { file, folder, link };

/// An `Entry` of `Fs.list_kinds` (step 28) and `Fs.kind_of` (step 40): the name, whether it is a
/// file, a folder, or a link, its hard link count, and its setuid bit.
pub fn entryOf(vm: *Vm, name: []const u8, kind: EntryKind, links: u64, setuid: bool) Error!Value {
    const fields = try vm_mod.rawAlloc(vm.heap, Value, 4);
    fields[0] = .{ .string = name };
    fields[1] = try vm.variant(switch (kind) {
        .file => "File",
        .folder => "Folder",
        .link => "Link",
    }, &.{});
    fields[2] = .{ .int = links };
    fields[3] = .{ .bool = setuid };
    return .{ .record = .{ .decl = vm.program.checked.preludeStruct("Entry").?, .fields = fields } };
}

/// `String.grouped(n)` (step 28): the integer in Mo's own spelling, `_` between each three digits
/// counted from the right, `-1_204_000`. runtime/mo_rt.c's grouped_text is the same.
fn groupedText(vm: *Vm, n: i128) Error![]const u8 {
    var digits: [48]u8 = undefined;
    const plain = std.fmt.bufPrint(&digits, "{d}", .{if (n < 0) -n else n}) catch unreachable;
    var out: std.ArrayList(u8) = .empty;
    if (n < 0) try out.append(vm.gpa, '-');
    for (plain, 0..) |d, k| {
        if (k > 0 and (plain.len - k) % 3 == 0) try out.append(vm.gpa, '_');
        try out.append(vm.gpa, d);
    }
    return vm_mod.rawDupe(vm.heap, u8, out.items);
}

/// The `Fs` rows but `read`, `scoped`, and `read_only`, and `read` too for a fixture. Under
/// mo run the file system is real (server.zig); in a test it is a fixture's, in memory.
fn files(vm: *Vm, row: prelude.Fn, which: Row, a: []const Value) Error!Value {
    const fs = a[0].cap;
    const within = a[a.len - 1].duration;
    const path: []const u8 = if (which == .fs_list or which == .fs_list_kinds) "." else a[1].string;
    const s = vm.server orelse return fixtureFiles(vm, row, which, a);
    return switch (which) {
        .fs_read_lines => s.readAs(vm, fs, path, within, .lines),
        .fs_read_bytes => s.readAs(vm, fs, path, within, .bytes),
        .fs_fold_lines => s.foldLines(vm, fs, path, a[3].func, a[2], within),
        .fs_size => s.size(vm, fs, path, within),
        .fs_list => s.list(vm, fs, within, false),
        .fs_list_kinds => s.list(vm, fs, within, true),
        .fs_write, .fs_append => s.writeFile(vm, row, fs, path, a[2].string, within, which == .fs_append),
        .fs_remove => s.remove(vm, row, fs, path, within),
        .fs_rename => s.rename(vm, row, fs, path, a[2].string, within),
        .fs_mkdir => s.mkdir(vm, row, fs, path, within),
        .fs_replace => s.replace(vm, row, fs, path, a[2].string, within),
        .fs_kind_of => s.kindOf(vm, fs, path, within),
        else => unreachable,
    };
}

/// The file system every `Fs.fixture()` of a test gives (design-v0/09, Files): files in
/// memory, by their path from the fixture's root, which keep what the test writes and which
/// every Fs narrowed from the fixture shares. A folder is any path a file is under, so it is
/// there once a file is, or one `mkdir` made, kept as a mark: its path and a slash. A call that a seeded run's fault fails changes nothing.
pub const FixtureFs = struct {
    /// Each fixture's files: one set per `Fs.fixture()` call.
    systems: std.ArrayList(std.StringArrayHashMapUnmanaged([]const u8)) = .empty,
    /// Each fixture Fs value, by `Value.Cap.handle - 1`. Handle 0, a capability made by hand,
    /// is an empty file system that keeps nothing.
    scopes: std.ArrayList(Scope) = .empty,

    pub const Scope = struct {
        /// Index in `systems`, or null for handle 0.
        system: ?u32 = null,
        /// The folder the Fs was scoped to, an absolute path from the fixture's root.
        folder: []const u8 = "/",
        read_only: bool = false,
        /// `scoped` was given a path outside the scope it narrowed: nothing is there.
        empty: bool = false,
        delay: i64 = 0,
    };

    fn scopeOf(f: *const FixtureFs, cap: Value.Cap) Scope {
        if (cap.handle == 0 or cap.handle > f.scopes.items.len) return .{ .delay = cap.delay };
        return f.scopes.items[cap.handle - 1];
    }

    fn add(f: *FixtureFs, gpa: std.mem.Allocator, scope: Scope) Error!Value {
        try f.scopes.append(gpa, scope);
        return .{ .cap = .{ .kind = .fs, .delay = scope.delay, .handle = @intCast(f.scopes.items.len) } };
    }

    /// The path a name in the scope is at, or null when it leaves the scope. A name whose `..`
    /// climbs above the scope's folder leaves it, even above the fixture's root, which is its
    /// whole world: the real Fs refuses such a name, and so does the fixture (step 21; before,
    /// a climb above the root stopped there and was taken).
    fn pathIn(gpa: std.mem.Allocator, scope: Scope, name: []const u8) Error!?[]const u8 {
        if (scope.system == null or scope.empty) return null;
        if (climbsOut(scope.folder, name)) return null;
        const full = try std.fs.path.resolvePosix(gpa, &.{ scope.folder, name });
        return if (server_mod.within(scope.folder, full)) full else null;
    }

    /// Whether `name`, taken from `folder` (or from the root when it is absolute), climbs above
    /// `folder` at any `..`.
    fn climbsOut(folder: []const u8, name: []const u8) bool {
        const base = depthOf(folder);
        var depth: usize = if (std.mem.startsWith(u8, name, "/")) 0 else base;
        var parts = std.mem.tokenizeScalar(u8, name, '/');
        while (parts.next()) |part| {
            if (std.mem.eql(u8, part, ".")) continue;
            if (std.mem.eql(u8, part, "..")) {
                if (depth <= base) return true;
                depth -= 1;
            } else depth += 1;
        }
        return false;
    }

    fn depthOf(folder: []const u8) usize {
        var n: usize = 0;
        var parts = std.mem.tokenizeScalar(u8, folder, '/');
        while (parts.next()) |_| n += 1;
        return n;
    }
};

/// `Fs.fixture()` and `Fs.fixture(delay: d)`: a new file system in memory, empty.
pub fn fixtureFs(vm: *Vm, delay: i64) Error!Value {
    const sim = vm.sim orelse return .{ .cap = .{ .kind = .fs, .delay = delay } };
    try sim.files.systems.append(sim.gpa, .empty);
    return sim.files.add(sim.gpa, .{ .system = @intCast(sim.files.systems.items.len - 1), .delay = delay });
}

/// `scoped(path)` and `read_only` on a fixture Fs: a new scope on the same files.
pub fn fixtureNarrow(vm: *Vm, cap: Value.Cap, name: []const u8, path: []const u8) Error!Value {
    const sim = vm.sim orelse return .{ .cap = cap };
    var scope = sim.files.scopeOf(cap);
    if (std.mem.eql(u8, name, "read_only")) {
        scope.read_only = true;
    } else if (try FixtureFs.pathIn(sim.gpa, scope, path)) |folder| {
        scope.folder = folder;
    } else scope.empty = true;
    return sim.files.add(sim.gpa, scope);
}

fn fixtureFiles(vm: *Vm, row: prelude.Fn, which: Row, a: []const Value) Error!Value {
    const sim = vm.sim orelse return fail(vm, .other, row, "an Fs.fixture() works only in a test", .{});
    const gpa = sim.gpa;
    const scope = sim.files.scopeOf(a[0].cap);
    const within = a[a.len - 1].duration;
    const path: []const u8 = if (which == .fs_list or which == .fs_list_kinds) "." else a[1].string;
    const writes = switch (which) {
        .fs_write, .fs_append, .fs_remove, .fs_rename, .fs_mkdir, .fs_replace => true,
        else => false,
    };
    if (writes and scope.read_only) return fail(vm, .other, row, "fs.{s}(\"{s}\") writes through an Fs narrowed to read_only, which only reads", .{ row.name, path });
    if (scope.delay > within) {
        // Past its deadline the call waited the whole of it, as a fault's timeout does (step 22).
        sim.wait(@max(within, 0));
        return timedOut(vm);
    }
    const waited_before = sim.waited;
    const lists = which == .fs_list or which == .fs_list_kinds;
    if (try vm.fixtureFault(!lists, path, within)) |failed| return failed;
    // A call that answers after the fixture's delay waited it, on top of any slowness a fault
    // gave it: the clock moves, and past the deadline the call is Timeout there (step 22).
    if (scope.delay > 0) {
        const slow = sim.waited - waited_before;
        if (slow + scope.delay > within) {
            sim.wait(within - slow);
            return timedOut(vm);
        }
        sim.wait(scope.delay);
    }
    const system: ?*std.StringArrayHashMapUnmanaged([]const u8) = if (scope.system) |i| &sim.files.systems.items[i] else null;
    if (lists) {
        const all = system orelse return vm.variant("Ok", &.{.{ .list = &.{} }});
        // A scope that climbed out of the one it narrowed holds nothing, as the real Fs's.
        if (scope.empty) return missed(vm, ".");
        const prefix = if (std.mem.eql(u8, scope.folder, "/")) "/" else try std.fmt.allocPrint(gpa, "{s}/", .{scope.folder});
        var listed: std.ArrayList([]const u8) = .empty;
        var folders: std.StringHashMapUnmanaged(void) = .empty;
        // A folder is there when a file is under it or mkdir made it; the root always is.
        var there = std.mem.eql(u8, scope.folder, "/");
        for (all.keys()) |key| {
            if (!std.mem.startsWith(u8, key, prefix)) continue;
            there = true;
            const rest = key[prefix.len..];
            const name = rest[0 .. std.mem.indexOfScalar(u8, rest, '/') orelse rest.len];
            // A folder's own mark (mkdir) under the listed folder names nothing.
            if (name.len == 0) continue;
            if (name.len < rest.len) try folders.put(gpa, name, {});
            const seen = for (listed.items) |n| {
                if (std.mem.eql(u8, n, name)) break true;
            } else false;
            if (!seen) try listed.append(gpa, name);
        }
        // As the real Fs answers a scope that is not a readable folder (step 22).
        if (!there) return missed(vm, ".");
        std.mem.sort([]const u8, listed.items, {}, struct {
            fn lt(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.lessThan(u8, x, y);
            }
        }.lt);
        const out = try vm_mod.rawAlloc(vm.heap, Value, listed.items.len);
        for (listed.items, out) |n, *o| o.* = if (which == .fs_list_kinds) try entryOf(vm, n, if (folders.contains(n)) .folder else .file, 1, false) else .{ .string = n };
        return vm.variant("Ok", &.{.{ .list = out }});
    }
    const all = system orelse return missed(vm, path);
    const full = try FixtureFs.pathIn(gpa, scope, path) orelse return missed(vm, path);
    switch (which) {
        .fs_fold_lines => {
            const text = all.get(full) orelse return missed(vm, path);
            var feed: LineFeed = .init(vm, a[3].func, a[2]);
            try feed.bytes(text);
            try feed.end();
            return vm.variant("Ok", &.{feed.acc});
        },
        .fs_read, .fs_read_lines, .fs_read_bytes, .fs_size => {
            const text = all.get(full) orelse return missed(vm, path);
            return switch (which) {
                .fs_read => readResult(vm, text, .text),
                .fs_read_lines => readResult(vm, text, .lines),
                .fs_read_bytes => readResult(vm, text, .bytes),
                else => vm.variant("Ok", &.{.{ .int = text.len }}),
            };
        },
        // A fixture has no partial files, so a replace is a write (design: section 2).
        .fs_write, .fs_replace => try all.put(gpa, full, try gpa.dupe(u8, a[2].string)),
        // A fixture has no links: a file or a folder, one link each, never setuid (step 40).
        .fs_kind_of => {
            if (all.contains(full)) return vm.variant("Ok", &.{try entryOf(vm, path, .file, 1, false)});
            const under = if (std.mem.eql(u8, full, "/")) "/" else try std.fmt.allocPrint(gpa, "{s}/", .{full});
            defer if (!std.mem.eql(u8, full, "/")) gpa.free(under);
            const folder = std.mem.eql(u8, full, "/") or for (all.keys()) |key| {
                if (std.mem.startsWith(u8, key, under)) break true;
            } else false;
            if (!folder) return missed(vm, path);
            return vm.variant("Ok", &.{try entryOf(vm, path, .folder, 1, false)});
        },
        .fs_append => {
            const held = all.get(full) orelse "";
            try all.put(gpa, full, try std.mem.concat(gpa, u8, &.{ held, a[2].string }));
        },
        .fs_remove => if (!all.orderedRemove(full)) return missed(vm, path),
        .fs_mkdir => {
            // A folder is a mark, its path and a slash, so list shows it before a file is in it.
            if (all.contains(full)) return missed(vm, path);
            const mark = try std.fmt.allocPrint(gpa, "{s}/", .{full});
            if (!all.contains(mark)) try all.put(gpa, mark, "");
        },
        .fs_rename => {
            const text = all.get(full) orelse return missed(vm, path);
            const to = try FixtureFs.pathIn(gpa, scope, a[2].string) orelse return missed(vm, a[2].string);
            _ = all.orderedRemove(full);
            try all.put(gpa, to, text);
        },
        else => unreachable,
    }
    return vm.variant("Ok", &.{.none});
}

pub const ReadAs = enum { text, lines, bytes };

/// What `read`, `read_lines`, and `read_bytes` give for a file's bytes: its text, its lines,
/// or its bytes as a `List(UInt8)`; `NotText` for text or lines that are not UTF-8, since a
/// `String` is.
pub fn readResult(vm: *Vm, file: []const u8, as: ReadAs) Error!Value {
    if (as == .bytes) {
        const out = try vm_mod.rawAlloc(vm.heap, Value, file.len);
        for (file, out) |byte, *o| o.* = .{ .int = byte };
        return vm.variant("Ok", &.{.{ .list = out }});
    }
    if (!std.unicode.utf8ValidateSlice(file)) return notText(vm);
    return vm.variant("Ok", &.{if (as == .text) .{ .string = file } else try lines(vm, file)});
}

pub fn notText(vm: *Vm) Error!Value {
    return vm.variant("Error", &.{try vm.variant("NotText", &.{})});
}

fn missed(vm: *Vm, path: []const u8) Error!Value {
    return vm.variant("Error", &.{try vm.variant("Missing", &.{.{ .string = path }})});
}

fn timedOut(vm: *Vm) Error!Value {
    return vm.variant("Error", &.{try vm.variant("Timeout", &.{})});
}

// ---- output

/// `out.write(text)` and `out.write_line(text)`: to the real stream under mo run; in a test,
/// to an `Out.fixture()`, whose `written` keeps each call's text, a line with its "\n".
pub fn writeOut(vm: *Vm, row: prelude.Fn, out: Value.Cap, text: []const u8, line: bool) Error!void {
    if (vm.server) |s| {
        s.write(out, text);
        if (line) s.write(out, "\n");
        return;
    }
    const sim = vm.sim orelse return fail(vm, .other, row, "Out.{s} runs only under mo run, or on an Out.fixture() in a test", .{row.name});
    if (out.handle == 0 or out.handle > sim.outs.items.len) return;
    const kept = if (line) try std.fmt.allocPrint(sim.gpa, "{s}\n", .{text}) else try sim.gpa.dupe(u8, text);
    try sim.outs.items[out.handle - 1].append(sim.gpa, kept);
}

// ---- maps and sets

/// Where `key` is in `xs`, whose entries are `stride` values wide (a map's are 2), by
/// looking at each.
pub fn indexOf(xs: []const Value, stride: usize, key: Value) ?usize {
    var k: usize = 0;
    while (k < xs.len) : (k += stride) {
        if (vm_mod.equal(xs[k], key)) return k;
    }
    return null;
}

/// A map or set of fewer keys than this is searched from the front; one this big has an
/// index: `index[0]` counts the slots in use, and `index[1..]` is the table, a power of two
/// long.
pub const index_from = 8;

/// Where `key` is in a map or set: through its index, or from the front when it has none.
/// A table has at most half its slots in use, so a probe always reaches an empty one.
pub fn find(m: Value.Map, stride: usize, key: Value) ?usize {
    if (m.index.len == 0) return indexOf(m.entries, stride, key);
    const table = m.index[1..];
    const mask = table.len - 1;
    var i: usize = @intCast(ValueContext.hash(.{}, key) & mask);
    while (true) : (i = (i + 1) & mask) {
        const slot = table[i];
        if (slot == 0) return null;
        const at = (slot - 1) * stride;
        if (at < m.entries.len and vm_mod.equal(m.entries[at], key)) return at;
    }
}

/// Whether a table has room for one more slot in use.
fn roomForOne(index: []const u32) bool {
    return index.len > 0 and index.len - 1 >= 2 * (index[0] + 1);
}

/// A table slot whose entry a remove took out in place (step 28): a probe goes on past it, as
/// past any ordinal beyond the entries, and it stays counted in use until the table is built
/// again.
pub const removed_slot: u32 = std.math.maxInt(u32);

/// `index` built again in place over `entries`, which it has room for: a crashed update's
/// remove taken back (vm.rollBack).
pub fn rebuildIndex(index: []u32, entries: []const Value, stride: usize) void {
    @memset(index, 0);
    for (0..entries.len / stride) |ordinal| insertOrdinal(index, entries, stride, ordinal);
}

/// The entry `key`, at ordinal `gone`, was taken out and the ones after it moved down one: its
/// slot, found as a lookup finds it, is marked removed, and every later ordinal counts one less,
/// in one pass without a branch.
fn dropOrdinal(index: []u32, key: Value, gone: usize) void {
    const table = index[1..];
    const mask = table.len - 1;
    const past: u32 = @intCast(gone + 1);
    var i: usize = @intCast(ValueContext.hash(.{}, key) & mask);
    while (table[i] != past) i = (i + 1) & mask;
    table[i] = removed_slot;
    for (table) |*slot| slot.* -= @intFromBool(slot.* > past) & @intFromBool(slot.* != removed_slot);
}

fn insertOrdinal(index: []u32, entries: []const Value, stride: usize, ordinal: usize) void {
    const table = index[1..];
    const mask = table.len - 1;
    var i: usize = @intCast(ValueContext.hash(.{}, entries[ordinal * stride]) & mask);
    while (table[i] != 0) i = (i + 1) & mask;
    table[i] = @intCast(ordinal + 1);
    index[0] += 1;
}

/// The slots in a map's table, for an index built again at least as large.
pub fn tableSlots(index: []const u32) usize {
    return if (index.len == 0) 0 else index.len - 1;
}

/// An index over `entries` of at least `min_slots` slots and twice the keys, or none for a
/// map too small to need one.
pub fn buildIndex(a: std.mem.Allocator, entries: []const Value, stride: usize, min_slots: usize) error{OutOfMemory}![]const u32 {
    const keys = entries.len / stride;
    if (keys < index_from) return &.{};
    var slots: usize = @max(16, min_slots);
    while (slots < 2 * keys) slots *= 2;
    const index = try a.alloc(u32, slots + 1);
    @memset(index, 0);
    for (0..keys) |ordinal| insertOrdinal(index, entries, stride, ordinal);
    return index;
}

/// A map or set of these entries, with the index it needs.
pub fn mapOf(a: std.mem.Allocator, entries: []const Value, stride: usize) error{OutOfMemory}!Value.Map {
    return .{ .entries = entries, .index = try buildIndex(a, entries, stride, 0) };
}

/// `m` with `key` set to `value` (a set passes stride 1, and no value): an existing key
/// keeps its place, a new one goes last. When the lowering marked the call `unique` (its
/// receiver's read moves it, moves.zig) and one holder holds the buffer alone, the row
/// writes in place. An owned buffer's table is its own: a remove changes it in place.
fn put(vm: *Vm, m: Value.Map, stride: usize, key: Value, value: Value, int_kind: u32) Error!Value.Map {
    const xs = m.entries;
    const on_var = int_kind == bytecode.unique;
    const mine = on_var and vm.isOwned(xs);
    if (find(m, stride, key)) |k| {
        if (stride == 1) return m;
        if (mine and vm.overwritable(@intFromPtr(xs.ptr))) {
            try vm.overwrite(@constCast(&xs[k + 1]), value);
            return m;
        }
        // The keys and their places are the same, so a copy nobody owns shares the index: its
        // entries never grow in place, so nothing inserts into the table for them. One that is
        // owned may be removed from in place, which changes its table, so it takes a copy.
        const out = try vm_mod.rawDupe(vm.heap, Value, xs);
        out[k + 1] = value;
        if (!on_var) return .{ .entries = out, .index = m.index };
        try vm.own(out);
        return .{ .entries = out, .index = if (m.index.len > 0) try vm_mod.rawDupe(vm.heap, u32, m.index) else m.index };
    }
    var out = try vm.pushList(xs, key);
    if (stride == 2) out = try vm.pushList(out, value);
    const keys = out.len / stride;
    const index: []const u32 = blk: {
        if (roomForOne(m.index)) {
            // Grown in place, the entries keep their table: every value that shares the
            // buffer is a prefix of it, and skips the ordinals past its own.
            if (out.ptr == xs.ptr) {
                insertOrdinal(@constCast(m.index), out, stride, keys - 1);
                break :blk m.index;
            }
            // A copy keeps every ordinal, so a table holding exactly the old keys is
            // copied rather than built again.
            if (m.index[0] == keys - 1) {
                const copy = try vm_mod.rawDupe(vm.heap, u32, m.index);
                insertOrdinal(copy, out, stride, keys - 1);
                break :blk copy;
            }
        }
        break :blk try buildIndex(vm.heap, out, stride, 0);
    };
    // Grown in place from a buffer others may share a prefix of, a result is not owned.
    if (on_var and (mine or out.ptr != xs.ptr)) {
        vm.disown(xs);
        try vm.own(out);
    }
    return .{ .entries = out, .index = index };
}

/// `m` without `key`; unchanged when it is absent.
fn without(vm: *Vm, m: Value.Map, stride: usize, key: Value, int_kind: u32) Error!Value.Map {
    const xs = m.entries;
    const k = find(m, stride, key) orelse return m;
    const on_var = int_kind == bytecode.unique;
    const rest = xs.len - stride;
    // The last key comes off as a shorter view: the table's ordinal past it is skipped.
    if (k == rest) {
        if (on_var and vm.isOwned(xs)) {
            vm.disown(xs);
            try vm.own(xs[0..rest]);
        }
        return .{ .entries = xs[0..rest], .index = m.index };
    }
    // Held alone, the entries after the key move down in place and the table, the buffer's own,
    // drops the key's slot (step 28); under an update a buffer older than it keeps what a crash
    // puts back.
    if (on_var and vm.isOwned(xs) and vm.overwritable(@intFromPtr(xs.ptr))) {
        const buf = @constCast(xs);
        try vm.keepRemove(xs, k, stride, m.index);
        if (m.index.len > 0) dropOrdinal(@constCast(m.index), key, k / stride);
        std.mem.copyForwards(Value, buf[k..rest], buf[k + stride ..]);
        try vm.rememberShift(xs, k, stride);
        vm.disown(xs);
        try vm.own(xs[0..rest]);
        return .{ .entries = xs[0..rest], .index = m.index };
    }
    const out = try vm_mod.rawAlloc(vm.heap, Value, rest);
    @memcpy(out[0..k], xs[0..k]);
    @memcpy(out[k..], xs[k + stride ..]);
    if (on_var) try vm.own(out);
    return .{ .entries = out, .index = try buildIndex(vm.heap, out, stride, tableSlots(m.index)) };
}

/// Hashes a value so that equal values (vm.equal) hash alike.
pub const ValueContext = struct {
    pub fn hash(_: ValueContext, v: Value) u64 {
        var h: std.hash.Wyhash = .init(0);
        hashInto(&h, v);
        return h.final();
    }

    pub fn eql(_: ValueContext, a: Value, b: Value) bool {
        return vm_mod.equal(a, b);
    }
};

/// Equal maps and sets can hold their entries in different orders (vm.equal), so each entry
/// hashes on its own and the hashes add up.
fn hashUnordered(h: *std.hash.Wyhash, entries: []const Value, stride: usize) void {
    var sum: u64 = 0;
    var k: usize = 0;
    while (k < entries.len) : (k += stride) {
        var one: std.hash.Wyhash = .init(0);
        for (entries[k .. k + stride]) |v| hashInto(&one, v);
        sum +%= one.final();
    }
    h.update(std.mem.asBytes(&entries.len));
    h.update(std.mem.asBytes(&sum));
}

fn hashInto(h: *std.hash.Wyhash, v: Value) void {
    h.update(&.{@intFromEnum(std.meta.activeTag(v))});
    switch (v) {
        .none => {},
        .bool => |b| h.update(&.{@intFromBool(b)}),
        .int => |i| h.update(std.mem.asBytes(&i)),
        // 0.0 and -0.0 are equal, so they hash alike.
        .float => |x| h.update(std.mem.asBytes(&(if (x == 0) @as(f64, 0) else x))),
        .string => |s| {
            h.update(std.mem.asBytes(&s.len));
            h.update(s);
        },
        .time, .duration => |t| h.update(std.mem.asBytes(&t)),
        .list, .tuple => |xs| hashAll(h, xs),
        .map => |m| hashUnordered(h, m.entries, 2),
        .set => |m| hashUnordered(h, m.entries, 1),
        .record => |r| {
            h.update(std.mem.asBytes(&r.decl));
            hashAll(h, r.fields);
        },
        .variant => |r| {
            h.update(std.mem.asBytes(&r.name.len));
            h.update(r.name);
            hashAll(h, r.fields);
        },
        .func => |f| {
            h.update(std.mem.asBytes(&f.function));
            hashAll(h, f.captures);
        },
        .cap => |c| {
            h.update(&.{@intFromEnum(c.kind)});
            h.update(std.mem.asBytes(&c.delay));
            h.update(std.mem.asBytes(&c.handle));
        },
        .handle => |x| h.update(std.mem.asBytes(&x)),
        .reply => |seq| h.update(std.mem.asBytes(&seq)),
    }
}

fn hashAll(h: *std.hash.Wyhash, xs: []const Value) void {
    h.update(std.mem.asBytes(&xs.len));
    for (xs) |x| hashInto(h, x);
}

// ---- numbers

/// `to_u8` and `checked_to_u8` name their target by the name's last part.
fn targetKind(name: []const u8) types.IntKind {
    const suffix = name[std.mem.lastIndexOfScalar(u8, name, '_').? + 1 ..];
    return std.meta.stringToEnum(types.IntKind, suffix).?;
}

/// Whole-number text: ASCII digits, at least one, with one leading `-` when `signed`.
fn parseWhole(s: []const u8, signed: bool, kind: types.IntKind) ?i128 {
    const negative = signed and s.len > 0 and s[0] == '-';
    const digits = s[@intFromBool(negative)..];
    if (digits.len == 0 or digits.len > 40) return null;
    var v: i128 = 0;
    for (digits) |d| {
        if (!std.ascii.isDigit(d)) return null;
        // Past every width it stays past them all, so 40 digits cannot overflow the i128.
        v = if (v > 1 << 120) 1 << 121 else v * 10 + (d - '0');
    }
    if (negative) v = -v;
    if (v < vm_mod.minOf(kind) or v > vm_mod.maxOf(kind)) return null;
    return v;
}

/// Float text: `-`?, digits, then `.` and digits, then `e` or `E`, a sign, and digits,
/// the last two parts optional. A value too large for a Float64 is not a number.
fn parseFloat(s: []const u8) ?f64 {
    var i: usize = 0;
    if (i < s.len and s[i] == '-') i += 1;
    i = digitsFrom(s, i) orelse return null;
    if (i < s.len and s[i] == '.') i = digitsFrom(s, i + 1) orelse return null;
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        i += 1;
        if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
        i = digitsFrom(s, i) orelse return null;
    }
    if (i != s.len) return null;
    const x = std.fmt.parseFloat(f64, s) catch return null;
    return if (std.math.isInf(x)) null else x;
}

/// Past one or more digits starting at `i`, or null when there are none.
fn digitsFrom(s: []const u8, i: usize) ?usize {
    var j = i;
    while (j < s.len and std.ascii.isDigit(s[j])) j += 1;
    return if (j == i) null else j;
}

const max_places = 15;
/// A finite f64's shortest decimal spelling has at most 309 whole digits or 324 decimals.
const decimal_buffer = 400;

/// `x` with exactly `places` decimals, rounded half away from zero on its shortest
/// decimal spelling, into `buf`. Zero is never negative.
fn rounded(buf: *[decimal_buffer]u8, x: f64, places: usize) []const u8 {
    var spelled: [decimal_buffer]u8 = undefined;
    const text = std.fmt.bufPrint(&spelled, "{d}", .{@abs(x)}) catch unreachable;
    const dot = std.mem.indexOfScalar(u8, text, '.') orelse text.len;
    const whole = text[0..dot];
    const fraction = if (dot < text.len) text[dot + 1 ..] else "";
    // Digits, whole then `places` of fraction, with room for a carry in front.
    var digits: [decimal_buffer]u8 = undefined;
    digits[0] = '0';
    var n: usize = 1;
    @memcpy(digits[n..][0..whole.len], whole);
    n += whole.len;
    for (0..places) |k| {
        digits[n] = if (k < fraction.len) fraction[k] else '0';
        n += 1;
    }
    if (places < fraction.len and fraction[places] >= '5') {
        var k = n;
        while (k > 0) {
            k -= 1;
            if (digits[k] == '9') {
                digits[k] = '0';
                continue;
            }
            digits[k] += 1;
            break;
        }
    }
    var first: usize = 0;
    while (first + 1 < n - places and digits[first] == '0') first += 1;
    const zero = for (digits[first..n]) |d| {
        if (d != '0') break false;
    } else true;
    var len: usize = 0;
    if (x < 0 and !zero) {
        buf[0] = '-';
        len = 1;
    }
    const whole_len = n - places - first;
    @memcpy(buf[len..][0..whole_len], digits[first .. n - places]);
    len += whole_len;
    if (places > 0) {
        buf[len] = '.';
        len += 1;
        @memcpy(buf[len..][0..places], digits[n - places .. n]);
        len += places;
    }
    return buf[0..len];
}

test "rounding happens on the shortest decimal spelling, half away from zero" {
    var buf: [decimal_buffer]u8 = undefined;
    try std.testing.expectEqualStrings("2.68", rounded(&buf, 2.675, 2));
    try std.testing.expectEqualStrings("-3", rounded(&buf, -2.5, 0));
    try std.testing.expectEqualStrings("10.0", rounded(&buf, 9.96, 1));
    try std.testing.expectEqualStrings("0.00", rounded(&buf, -0.001, 2));
    try std.testing.expectEqualStrings("100.000", rounded(&buf, 99.9995, 3));
    try std.testing.expectEqualStrings("0.0", rounded(&buf, 0.0, 1));
    try std.testing.expectEqualStrings("1000000000000000000000", rounded(&buf, 1e21, 0));
}

test "numbers are read only from text that spells one" {
    try std.testing.expectEqual(@as(?i128, 42), parseWhole("42", false, .u64));
    try std.testing.expectEqual(@as(?i128, null), parseWhole("-42", false, .u64));
    try std.testing.expectEqual(@as(?i128, -42), parseWhole("-42", true, .i64));
    try std.testing.expectEqual(@as(?i128, null), parseWhole("18446744073709551616", false, .u64));
    try std.testing.expectEqual(@as(?i128, null), parseWhole("1_000", false, .u64));
    try std.testing.expectEqual(@as(?f64, 2500), parseFloat("2.5e3"));
    for ([_][]const u8{ ".5", "5.", "+1", "inf", "nan", "0x10", "1e999", "" }) |t| try std.testing.expectEqual(@as(?f64, null), parseFloat(t));
}

test "graphemes carry their combining marks, and trim takes Unicode whitespace" {
    try std.testing.expectEqual(@as(i128, 4), count("cafe\u{301}"));
    try std.testing.expectEqual(@as(i128, 4), count("café"));
    try std.testing.expectEqualStrings("e\u{301}", slice("cafe\u{301}!", 3, 4));
    try std.testing.expectEqualStrings("", slice("abc", 2, 1));
    try std.testing.expectEqualStrings("bc", slice("abc", 1, 99));
    try std.testing.expectEqualStrings("a b", trim("\u{3000} a b\t\n"));
    try std.testing.expectEqualStrings("", trim(" \n"));
}
