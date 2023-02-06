const std = @import("std");
const pb = @import("protobuf");
const pbtypes = pb.types;
const Key = pbtypes.Key;
const protobuf = pb.protobuf;

pub fn encodeVarint(comptime T: type, i: T) []const u8 {
    var buf: [32]u8 = undefined; // handles upto u512
    var fbs = std.io.fixedBufferStream(&buf);
    protobuf.writeVarint128(T, i, fbs.writer(), .int) catch unreachable;
    return fbs.getWritten();
}

pub fn encodeInt(comptime T: type, i: T) []const u8 {
    var buf: [32]u8 = undefined; // handles upto u512
    var fbs = std.io.fixedBufferStream(&buf);
    fbs.writer().writeIntLittle(T, i) catch unreachable;
    return fbs.getWritten();
}

pub fn encodeFloat(comptime T: type, i: T) []const u8 {
    const U = std.meta.Int(.unsigned, @typeInfo(T).Float.bits);
    return encodeInt(U, @bitCast(U, i));
}

pub fn encodeMessage(comptime parts: anytype) []const u8 {
    var result: []const u8 = &.{};
    comptime for (std.meta.fields(@TypeOf(parts))) |f| {
        switch (f.type) {
            Key => result = result ++
                encodeVarint(usize, @field(parts, f.name).encode()),
            comptime_int => result = result ++
                encodeVarint(usize, @field(parts, f.name)),
            bool => result = result ++
                encodeVarint(u8, @boolToInt(@field(parts, f.name))),
            else => if (std.meta.trait.isZigString(f.type)) {
                result = result ++ @field(parts, f.name);
            } else if (std.meta.trait.isIntegral(f.type)) {
                result = result ++
                    encodeVarint(f.type, @field(parts, f.name));
            } else @compileError("unsupported type '" ++ @typeName(f.type) ++ "'"),
        }
    };

    return result;
}

pub fn lengthEncode(comptime parts: anytype) []const u8 {
    const m = encodeMessage(parts);
    return encodeVarint(usize, m.len) ++ m;
}
