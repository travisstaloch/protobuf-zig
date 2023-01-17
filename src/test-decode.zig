const std = @import("std");
const testing = std.testing;

const pb = @import("protobuf-util.zig");
const types = @import("types.zig");
pub const CodeGeneratorRequest = types.CodeGeneratorRequest;

// const talloc = testing.allocator;
var tarena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const talloc = tarena.allocator();

/// 1. genrate zig-out/bin/protoc-gen-zig by running $ zig build
/// 2. run the following with a modified $PATH that includes zig-out/bin/
///    $ protoc --zig_out=gen `protofile`
fn parseWithSystemProtoc(protofile: []const u8) ![]const u8 {
    { // make sure the exe is built
        _ = try std.ChildProcess.exec(.{ .allocator = talloc, .argv = &.{ "zig", "build" } });
    }
    var envmap = try std.process.getEnvMap(talloc);
    const path = envmap.get("PATH") orelse unreachable;
    const newpath = try std.mem.concat(talloc, u8, &.{ path, ":zig-out/bin/" });
    try envmap.put("PATH", newpath);
    const r = try std.ChildProcess.exec(.{
        .allocator = talloc,
        .argv = &.{ "protoc", "--zig_out=gen", protofile },
        .env_map = &envmap,
    });
    return r.stderr;
}

fn deserializeHelper(comptime T: type, protofile: []const u8) !*T {
    const bytes = try parseWithSystemProtoc(protofile);
    return deserializeBytesHelper(T, bytes);
}
fn deserializeBytesHelper(comptime T: type, bytes: []const u8) !*T {
    var fbs = std.io.fixedBufferStream(bytes);
    var ctx = pb.context(&fbs, talloc);
    const message = try ctx.deserialize(&T.descriptor);
    return try message.as(T);
}
fn deserializeHexBytesHelper(comptime T: type, hexbytes: []const u8) !*T {
    var out = try talloc.alloc(u8, hexbytes.len / 2);
    const bytes = try std.fmt.hexToBytes(out, hexbytes);
    return deserializeBytesHelper(T, bytes);
}

test "only_enum - system protoc" {
    // testing.log_level = .info;
    const req = try deserializeHelper(CodeGeneratorRequest, "examples/only_enum.proto");
    try testing.expectEqual(@as(usize, 1), req.file_to_generate.len);
    try testing.expectEqual(@as(usize, 1), req.proto_file.len);
    const pf = req.proto_file.slice()[0];
    std.log.info("pf.enum_type {*}/{}", .{ @ptrCast([*]u8, pf.enum_type.items), pf.enum_type.len });
    try testing.expectEqual(@as(usize, 1), pf.enum_type.len);
    try testing.expect(@ptrToInt(pf.enum_type.items) != 0);
}

test "only_enum - no deps" {
    // testing.log_level = .info;
    // `input` was obtained by running $ zig build -Dhex && script/protoc-capture.sh examples/only_enum.proto
    const input = "0a186578616d706c65732f6f6e6c795f656e756d2e70726f746f1a080803100c180422007a9e020a186578616d706c65732f6f6e6c795f656e756d2e70726f746f2a290a08536f6d654b696e6412080a044e4f4e45100012050a0141100112050a0142100212050a014310034ace010a061204000007010a080a010c12030000120a0a0a0205001204020007010a0a0a03050001120302050d0a0b0a0405000200120303040d0a0c0a05050002000112030304080a0c0a0505000200021203030b0c0a0b0a0405000201120304040a0a0c0a05050002010112030404050a0c0a05050002010212030408090a0b0a0405000202120305040a0a0c0a05050002020112030504050a0c0a05050002020212030508090a0b0a0405000203120306040a0a0c0a05050002030112030604050a0c0a0505000203021203060809620670726f746f33";
    const req = try deserializeHexBytesHelper(CodeGeneratorRequest, input);
    try testing.expectEqual(@as(usize, 1), req.file_to_generate.len);
    try testing.expectEqual(@as(usize, 1), req.proto_file.len);
    const pf = req.proto_file.slice()[0];
    std.log.info("pf.enum_type {*}/{}", .{ @ptrCast([*]u8, pf.enum_type.items), pf.enum_type.len });
    try testing.expectEqual(@as(usize, 1), pf.enum_type.len);
    try testing.expect(@ptrToInt(pf.enum_type.items) != 0);
}
