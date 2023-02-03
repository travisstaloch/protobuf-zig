const std = @import("std");
const pb = @import("protobuf");
const pbtypes = pb.types;
const Key = pbtypes.Key;
const protobuf = pb.protobuf;

pub fn encodeInt(comptime T: type, i: T) []const u8 {
    var buf: [32]u8 = undefined; // handles upto u512
    var fbs = std.io.fixedBufferStream(&buf);
    protobuf.writeVarint128(T, i, fbs.writer(), .int) catch unreachable;
    return fbs.getWritten();
}

pub fn encodeFloat(comptime T: type, i: T) []const u8 {
    const U = std.meta.Int(.unsigned, @typeInfo(T).Float.bits);
    return encodeInt(U, @bitCast(U, i));
}

pub fn encodeMessage(comptime parts: anytype) []const u8 {
    var result: []const u8 = &.{};
    const Parts = @TypeOf(parts);
    comptime {
        for (std.meta.fields(Parts)) |f| {
            switch (f.type) {
                Key => result = result ++ encodeInt(usize, @field(parts, f.name).encode()),
                comptime_int => {
                    const i = @field(parts, f.name);
                    if (i < 256)
                        result = result ++ [1]u8{i}
                    else
                        @panic("TODO handle comptime_int >= 256");
                },
                bool => result = result ++ [1]u8{@boolToInt(@field(parts, f.name))},
                else => if (std.meta.trait.isZigString(f.type)) {
                    result = result ++ @field(parts, f.name);
                } else if (std.meta.trait.isIntegral(f.type)) {
                    result = result ++ encodeInt(f.type, @field(parts, f.name));
                } else @compileLog(f.type),
            }
        }
    }
    return result;
}

pub fn lengthEncode(comptime parts: anytype) []const u8 {
    const m = encodeMessage(parts);
    return encodeInt(usize, m.len) ++ m;
}
