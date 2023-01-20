const std = @import("std");
const testing = std.testing;

const pb = @import("protobuf-util.zig");
const types = @import("types.zig");
const common = @import("common.zig");
const util = @import("protobuf-util.zig");
const ptrfmt = common.ptrfmt;
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

inline fn deserializeHelper(comptime T: type, protofile: []const u8) !*T {
    const bytes = try parseWithSystemProtoc(protofile);
    return deserializeBytesHelper(T, bytes);
}
inline fn deserializeBytesHelper(comptime T: type, bytes: []const u8) !*T {
    var ctx = pb.context(bytes, talloc);
    const message = try ctx.deserialize(&T.descriptor);
    return try message.as(T);
}
inline fn deserializeHexBytesHelper(comptime T: type, hexbytes: []const u8) !*T {
    var out = try talloc.alloc(u8, hexbytes.len / 2);
    const bytes = try std.fmt.hexToBytes(out, hexbytes);
    return deserializeBytesHelper(T, bytes);
}

test "examples/only_enum - system protoc" {
    // testing.log_level = .info;
    const req = try deserializeHelper(CodeGeneratorRequest, "examples/only_enum.proto");
    try testing.expectEqual(@as(usize, 1), req.file_to_generate.len);
    try testing.expectEqual(@as(usize, 1), req.file_to_generate.cap);
    try testing.expectEqualStrings("examples/only_enum.proto", req.file_to_generate.items[0].slice());
    try testing.expectEqual(@as(usize, 1), req.proto_file.len);
    const pf = req.proto_file;
    try testing.expectEqual(@as(usize, 1), pf.len);
    const pf0et = pf.items[0].enum_type;
    try testing.expectEqual(@as(usize, 1), pf0et.len);
    const pf0et0val = pf0et.items[0].value;
    try testing.expectEqual(@as(usize, 4), pf0et0val.len);
    try testing.expectEqualStrings("NONE", pf0et0val.items[0].name.slice());
    try testing.expectEqual(@as(i32, 0), pf0et0val.items[0].number);
    try testing.expectEqualStrings("A", pf0et0val.items[1].name.slice());
    try testing.expectEqual(@as(i32, 1), pf0et0val.items[1].number);
    try testing.expectEqualStrings("B", pf0et0val.items[2].name.slice());
    try testing.expectEqual(@as(i32, 2), pf0et0val.items[2].number);
    try testing.expectEqualStrings("C", pf0et0val.items[3].name.slice());
    try testing.expectEqual(@as(i32, 3), pf0et0val.items[3].number);
    const pfscloc = pf.items[0].source_code_info.location;
    try testing.expectEqual(@as(usize, 16), pfscloc.len);
}

test "examples/only_enum-1 - no deps" {
    // testing.log_level = .info;
    // `input` was obtained by running $ zig build -Dhex && script/protoc-capture.sh examples/only_enum-1.proto
    const input = "0a1a6578616d706c65732f6f6e6c795f656e756d2d312e70726f746f1a080803100c180422007a8f010a1a6578616d706c65732f6f6e6c795f656e756d2d312e70726f746f2a140a08536f6d654b696e6412080a044e4f4e4510004a530a061204000004010a080a010c12030000120a0a0a0205001204020004010a0a0a03050001120302050d0a0b0a0405000200120303040d0a0c0a05050002000112030304080a0c0a0505000200021203030b0c620670726f746f33";
    const req = try deserializeHexBytesHelper(CodeGeneratorRequest, input);
    try testing.expectEqual(@as(usize, 1), req.file_to_generate.len);
    try testing.expectEqual(@as(usize, 1), req.file_to_generate.cap);
    try testing.expectEqualStrings("examples/only_enum-1.proto", req.file_to_generate.items[0].slice());
    try testing.expectEqual(@as(usize, 1), req.proto_file.len);
    const pf = req.proto_file;
    try testing.expectEqual(@as(usize, 1), pf.len);
    const pf0et = pf.items[0].enum_type;
    try testing.expectEqual(@as(usize, 1), pf0et.len);
    const pf0et0val = pf0et.items[0].value;
    try testing.expectEqual(@as(usize, 1), pf0et0val.len);
    try testing.expectEqualStrings("NONE", pf0et0val.items[0].name.slice());
    try testing.expectEqual(@as(i32, 0), pf0et0val.items[0].number);
    const pfscloc = pf.items[0].source_code_info.location;
    try testing.expectEqual(@as(usize, 7), pfscloc.len);
    try testing.expectEqual(@as(usize, 0), pfscloc.items[0].path.len);
    try testing.expectEqual(@as(usize, 4), pfscloc.items[0].span.len);
    try testing.expectEqual(@as(usize, 1), pfscloc.items[1].path.len);
    try testing.expectEqual(@as(usize, 3), pfscloc.items[1].span.len);
    try testing.expectEqual(@as(usize, 2), pfscloc.items[2].path.len);
    try testing.expectEqual(@as(usize, 4), pfscloc.items[2].span.len);
    try testing.expectEqual(@as(usize, 3), pfscloc.items[3].path.len);
    try testing.expectEqual(@as(usize, 3), pfscloc.items[3].span.len);
    try testing.expectEqual(@as(usize, 4), pfscloc.items[4].path.len);
    try testing.expectEqual(@as(usize, 3), pfscloc.items[4].span.len);
    try testing.expectEqual(@as(usize, 5), pfscloc.items[5].path.len);
    try testing.expectEqual(@as(usize, 3), pfscloc.items[5].span.len);
    try testing.expectEqual(@as(usize, 5), pfscloc.items[6].path.len);
    try testing.expectEqual(@as(usize, 3), pfscloc.items[6].span.len);
}

fn encodeMessage(comptime parts: anytype) []const u8 {
    var result: []const u8 = &.{};
    const Parts = @TypeOf(parts);
    comptime {
        for (std.meta.fields(Parts)) |f| {
            switch (f.type) {
                util.Key => result = result ++ [1]u8{@field(parts, f.name).encode()},
                comptime_int => result = result ++ [1]u8{@field(parts, f.name)},
                else => if (std.meta.trait.isZigString(f.type)) {
                    result = result ++ @field(parts, f.name);
                } else @compileLog(f.type),
            }
        }
    }
    return result;
}

fn lengthEncode(comptime parts: anytype) []const u8 {
    const m = encodeMessage(parts);
    var buf: [10]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try util.writeVarint128(usize, m.len, fbs.writer(), .int);
    return buf[0..fbs.pos] ++ m;
}

test "nested lists" {
    const message = comptime encodeMessage(.{
        util.Key.init(.LEN, 15), // CodeGeneratorRequest.proto_file
        lengthEncode(.{
            util.Key.init(.LEN, 5), // FileDescriptorProto.enum_type
            lengthEncode(.{
                util.Key.init(.LEN, 2), // EnumDescriptorProto.value
                lengthEncode(.{
                    util.Key.init(.LEN, 1), // EnumValueDescriptorProto.name
                    lengthEncode(.{"field0"}),
                    util.Key.init(.VARINT, 2), // EnumValueDescriptorProto.number
                    1,
                }),
            }),
        }),
    });
    const req = try deserializeBytesHelper(CodeGeneratorRequest, message);
    try testing.expectEqual(@as(usize, 1), req.proto_file.len);
    try testing.expectEqual(@as(usize, 1), req.proto_file.items[0].enum_type.len);
    try testing.expectEqual(@as(usize, 1), req.proto_file.items[0].enum_type.items[0].value.len);
    try testing.expectEqualStrings("field0", req.proto_file.items[0].enum_type.items[0].value.items[0].name.slice());
    try testing.expectEqual(@as(i32, 1), req.proto_file.items[0].enum_type.items[0].value.items[0].number);
}
