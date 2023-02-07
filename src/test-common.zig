const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const pb = @import("protobuf");
const types = pb.types;
const Key = types.Key;
const protobuf = pb.protobuf;
const String = pb.extern_types.String;

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

pub const TestError = error{
    TestExpectedEqual,
    TestExpectedApproxEqAbs,
    TestUnexpectedResult,
};

pub fn expectEqual(comptime T: type, data: T, data2: T) TestError!void {
    @setEvalBranchQuota(4000);
    switch (@typeInfo(T)) {
        .Int, .Bool, .Enum => try std.testing.expectEqual(data, data2),
        .Float => try std.testing.expectApproxEqAbs(
            data,
            data2,
            std.math.epsilon(T),
        ),
        .Struct => if (T == String) {
            try std.testing.expectEqualStrings(data.slice(), data2.slice());
        } else if (comptime mem.indexOf(
            u8,
            @typeName(T),
            "extern-types.ArrayList",
        ) != null) {
            try std.testing.expectEqual(data.len, data2.len);
            for (data.slice()) |it, i|
                try expectEqual(@TypeOf(it), it, data2.items[i]);
        } else {
            const fe = types.FieldEnum(T);
            inline for (comptime std.meta.tags(fe)) |tag| {
                if (comptime mem.eql(u8, @tagName(tag), "base")) continue;
                const F = comptime types.FieldType(T, tag);
                if (!@hasDecl(T, "has")) {
                    const field = @field(data, @tagName(tag));
                    const field2 = @field(data2, @tagName(tag));
                    try expectEqual(F, field, field2);
                } else if (data.has(tag)) {
                    const finfo = @typeInfo(F);
                    const field = types.getFieldHelp(T, data, tag);
                    const field2 = types.getFieldHelp(T, data2, tag);
                    if (finfo == .Union) { // oneof fields
                        const ffe = comptime types.FieldEnum(F);
                        const ftags = comptime std.meta.tags(ffe);
                        inline for (T.oneof_field_ids) |oneof_ids| {
                            inline for (comptime oneof_ids.slice()) |oneof_id, i| {
                                const ftag = ftags[i];
                                try testing.expect(data.base.hasFieldId(oneof_id) ==
                                    data2.base.hasFieldId(oneof_id));
                                if (data.base.hasFieldId(oneof_id)) {
                                    const payload = @field(field, @tagName(ftag));
                                    const payload2 = @field(field2, @tagName(ftag));
                                    const U = types.FieldType(F, ftag);
                                    try expectEqual(U, payload, payload2);
                                }
                            }
                        }
                    } else try expectEqual(F, field, field2);
                }
            }
        },
        .Pointer => |ptr| switch (ptr.size) {
            .One => return expectEqual(ptr.child, data.*, data2.*),
            else => @compileError("unsupported type '" ++ @typeName(T) ++ "'"),
        },
        else => @compileError("unsupported type '" ++ @typeName(T) ++ "'"),
    }
}

/// recursively initializes a protobuf type, setting each field to a
/// representation of its field_id
pub fn testInit(
    comptime T: type,
    comptime field_id: ?c_uint,
    alloc: mem.Allocator,
) mem.Allocator.Error!T {
    @setEvalBranchQuota(10_000);
    switch (@typeInfo(T)) {
        .Int => return @intCast(T, field_id.?),
        .Bool => return true,
        .Enum => return std.meta.tags(T)[0],
        .Float => return @intToFloat(T, field_id.?),
        .Struct => if (T == String) {
            return String.init(try std.fmt.allocPrint(alloc, "{}", .{field_id.?}));
        } else if (comptime mem.indexOf(
            u8,
            @typeName(T),
            "extern-types.ArrayList",
        ) != null) {
            const child = try testInit(T.Child, field_id, alloc);
            const items = try alloc.alloc(T.Child, 1);
            items[0] = child;
            return pb.extern_types.ArrayListMut(T.Child).init(items);
        } else {
            var t = T.init();
            const fields = types.fields(T);
            const fe = types.FieldEnum(T);
            const tags = comptime std.meta.tags(fe);
            comptime var i: usize = 1;
            inline while (i < fields.len) : (i += 1) {
                const field = fields[i];
                const F = field.ty();
                const tag = tags[i];
                if (field == .union_field) {
                    const payload = try testInit(F, T.field_ids[0], alloc);
                    t.set(tag, payload);
                    // skip remaining union fields in this group
                    if (i < T.field_ids.len) {
                        const fid = T.field_ids[i];
                        const oneof_ids = comptime for (T.oneof_field_ids) |oneof_ids| {
                            if (mem.indexOfScalar(c_uint, oneof_ids.slice(), fid) != null)
                                break oneof_ids;
                        } else unreachable;
                        i += oneof_ids.len;
                    }
                } else {
                    t.set(tag, try testInit(F, T.field_ids[i - 1], alloc));
                }
            }
            return t;
        },
        .Pointer => |ptr| switch (ptr.size) {
            .One => {
                const t = try alloc.create(ptr.child);
                t.* = try testInit(ptr.child, field_id, alloc);
                return t;
            },
            else => @compileError("unsupported type '" ++ @typeName(T) ++ "'"),
        },
        .Union => {
            unreachable;
        },
        else => @compileError("unsupported type '" ++ @typeName(T) ++ "'"),
    }
    unreachable;
}
