//! `zig build errors`: writes the error catalog page from the diagnostic tables
//! (errors.zig). The one argument is the page's path.
const std = @import("std");
const Io = std.Io;
const mo = @import("mo");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) {
        std.debug.print("usage: mo-errors <page.md>\n", .{});
        std.process.exit(2);
    }
    var page: Io.Writer.Allocating = .init(arena);
    try mo.errors.render(&page.writer, try mo.errors.rows(arena));
    try Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = page.written() });
}
