const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const pb = @import("protobuf");
pub const CodeGeneratorRequest = pb.plugin.CodeGeneratorRequest;
pub const gen = @import("gen.zig");

pub const std_options = struct {
    pub const log_level = std.meta.stringToEnum(std.log.Level, @tagName(@import("build_options").log_level)).?;
    pub const logFn = log;
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (!std.log.logEnabled(level, scope)) return;

    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(format ++ "\n", args) catch return;
}

fn getArg(args: *[]const []const u8, comptime startswith: []const u8) !?[]const u8 {
    if (std.mem.startsWith(u8, args.*[0], startswith ++ "=")) {
        return args.*[0][startswith.len + 1 ..];
    }
    if (std.mem.startsWith(u8, args.*[0], startswith)) {
        args.* = args.*[1..];
        if (args.len == 0) return error.Args;
        return args.*[0];
    }
    return null;
}

/// A simple protoc plugin implementation.  Similar to
/// https://github.com/protocolbuffers/protobuf-go/blob/master/cmd/protoc-gen-go/main.go.
/// Reads a CodeGeneratorRequest from stdin and writes a CodeGeneratorResponse to stdout.
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const input = try std.io.getStdIn().reader().readAllAlloc(alloc, std.math.maxInt(u32));

    var parse_ctx = pb.protobuf.context(input, alloc);
    const message = try parse_ctx.deserialize(&CodeGeneratorRequest.descriptor);
    const req = try message.as(CodeGeneratorRequest);

    var gen_ctx = gen.context(alloc, req);
    const resp = try gen_ctx.gen();
    const w = std.io.getStdOut().writer();
    try pb.protobuf.serialize(&resp.base, w);
}
