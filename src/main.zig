const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const pb = @import("protobuf.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const gen = @import("gen.zig");
pub const CodeGeneratorRequest = types.CodeGeneratorRequest;

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

/// a simple driver for testing message deserialization
///
/// supports protoc args '-I inc-dir' and '--decode typename'.
/// example usage in script/zig-decode-text.sh
/// $ script/protoc-enc-zig-dec.sh examples/only_enum.proto
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var args = try std.process.argsAlloc(alloc);
    const exepath = args[0];
    _ = exepath;
    args = args[1..];
    var includes = std.ArrayList([]const u8).init(alloc);
    var decode: []const u8 = "";
    var zig_out: []const u8 = "";
    var files = std.ArrayList([]const u8).init(alloc);
    while (args.len > 0) : (args = args[1..]) {
        if (try getArg(&args, "-I")) |inc|
            try includes.append(inc)
        else if (try getArg(&args, "--decode")) |s|
            decode = s
        else if (try getArg(&args, "--zig_out")) |s|
            zig_out = s
        else
            try files.append(args[0]);
    }
    std.log.debug("decode    '{s}'", .{decode});
    std.log.debug("zig_out   '{s}'", .{zig_out});
    std.log.debug("includes  '{s}'", .{includes.items});
    std.log.debug("files     '{s}'", .{files.items});

    var argv = std.ArrayList([]const u8).init(alloc);
    try argv.appendSlice(&.{
        "protoc",
        "--plugin=zig-out/bin/protoc-gen-zig",
        "--zig_out",
        zig_out,
    });
    for (includes.items) |inc|
        try argv.appendSlice(&.{ "-I", inc });
    for (files.items) |file|
        try argv.append(file);

    std.debug.print("argv {s}\n", .{argv.items});

    const res = try std.ChildProcess.exec(.{
        .allocator = alloc,
        .argv = argv.items,
    });

    // std.debug.print("res stdout {s}\n", .{res.stdout});
    // std.debug.print("res stderr {s}\n", .{res.stderr});

    var parse_ctx = pb.context(res.stderr, alloc);
    if (decode.len == 0) {
        const message = try parse_ctx.deserialize(&CodeGeneratorRequest.descriptor);
        const req = try message.as(CodeGeneratorRequest);
        var gen_ctx = gen.context(zig_out, alloc, req);
        try gen_ctx.gen(req);
    } else {
        std.log.err("TODO support decode='{s}'", .{decode});
    }
}
