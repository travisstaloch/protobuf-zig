//! for capturing output of system installed protoc.
//! used by script/protoc-capture.sh. look here for a usage example.
//! just echoes out whatever protoc sends from stdin to stderr
//! outputs hex representation when $ zig build -Dhex

const std = @import("std");
const build_options = @import("build_options");
const io = std.io;

pub fn main() !void {
    const stdin = io.getStdIn().reader();
    const stderr = io.getStdErr().writer();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const input = try stdin.readAllAlloc(alloc, std.math.maxInt(u32));

    // std.debug.print("stdin {}\n", .{input});

    if (build_options.echo_hex)
        try stderr.print("{}", .{std.fmt.fmtSliceHexLower(input)})
    else
        _ = try stderr.writeAll(input);
}
