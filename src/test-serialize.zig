const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const pb = @import("protobuf");
const types = pb.types;
const plugin = pb.plugin;
const protobuf = pb.protobuf;
const CodeGeneratorRequest = plugin.CodeGeneratorRequest;
const FieldDescriptorProto = pb.descr.FieldDescriptorProto;
const Key = types.Key;
const tcommon = @import("test-common.zig");
const encodeMessage = tcommon.encodeMessage;
const lengthEncode = tcommon.lengthEncode;
const encodeInt = tcommon.encodeInt;
const encodeFloat = tcommon.encodeFloat;
const String = pb.extern_types.String;

const talloc = testing.allocator;

test "basic ser" {
    var data = pb.descr.FieldOptions.init();
    data.set(.ctype, .STRING);
    data.set(.lazy, true);
    var ui = pb.descr.UninterpretedOption.init();
    ui.set(.identifier_value, String.init("ident"));
    ui.set(.positive_int_value, 42);
    ui.set(.negative_int_value, -42);
    ui.set(.double_value, 42);
    try data.uninterpreted_option.append(talloc, &ui);
    data.setPresent(.uninterpreted_option);
    defer data.uninterpreted_option.deinit(talloc);
    var buf = std.ArrayList(u8).init(talloc);
    defer buf.deinit();
    try protobuf.serialize(&data.base, buf.writer());

    const message = comptime encodeMessage(.{
        Key.init(.VARINT, 1), // FieldOptions.ctype
        @enumToInt(pb.descr.FieldOptions.CType.STRING),
        Key.init(.VARINT, 5), // FieldOptions.lazy
        true,
        Key.init(.LEN, 999), // FieldOptions.uninterpreted_option
        lengthEncode(.{
            Key.init(.LEN, 3), // UninterpretedOption.identifier_value
            lengthEncode(.{"ident"}),
            Key.init(.VARINT, 4), // UninterpretedOption.positive_int_value
            encodeInt(u8, 42),
            Key.init(.VARINT, 5), // UninterpretedOption.negative_int_value
            encodeInt(i64, -42),
            Key.init(.I64, 6), // UninterpretedOption.double_value
            encodeFloat(f64, 42.0),
        }),
    });

    try testing.expectEqualSlices(u8, message, buf.items);
}

test "packed repeated ser 1" {
    // from https://developers.google.com/protocol-buffers/docs/encoding#packed
    const Test5 = extern struct {
        base: pb.pbtypes.Message,
        // repeated int32 f = 6 [packed=true];
        f: pb.extern_types.ArrayListMut(i32) = .{},

        pub const field_ids = [_]c_uint{6};
        pub const opt_field_ids = [_]c_uint{};
        pub usingnamespace pb.pbtypes.MessageMixins(@This());

        pub const field_descriptors = [_]pb.pbtypes.FieldDescriptor{
            pb.pbtypes.FieldDescriptor.init(
                "f",
                6,
                .LABEL_REPEATED,
                .TYPE_INT32,
                @offsetOf(@This(), "f"),
                null,
                null,
                @enumToInt(pb.pbtypes.FieldDescriptor.FieldFlag.FLAG_PACKED),
            ),
        };
    };

    var data = Test5.init();
    defer data.f.deinit(talloc);
    try data.f.appendSlice(talloc, &.{ 3, 270, 86942 });
    data.setPresent(.f);

    var buf = std.ArrayList(u8).init(talloc);
    defer buf.deinit();
    try protobuf.serialize(&data.base, buf.writer());

    var buf2: [64]u8 = undefined;
    const actual = try std.fmt.bufPrint(&buf2, "{}", .{std.fmt.fmtSliceHexLower(buf.items)});
    try testing.expectEqualStrings("3206038e029ea705", actual);
}

test "packed repeated ser 2" {
    var data = pb.descr.FileDescriptorProto.init();
    // defer data.base.deinit(talloc);
    // ^ don't do this as it tries to free list strings and the bytes of data
    var deps: pb.extern_types.ArrayListMut(String) = .{};
    try deps.append(talloc, String.init("dep1"));
    defer deps.deinit(talloc);
    data.set(.dependency, deps);
    var pubdeps: pb.extern_types.ArrayListMut(i32) = .{};
    defer pubdeps.deinit(talloc);
    try pubdeps.appendSlice(talloc, &.{ 0, 1, 2 });
    data.set(.public_dependency, pubdeps);

    var buf = std.ArrayList(u8).init(talloc);
    defer buf.deinit();
    try protobuf.serialize(&data.base, buf.writer());

    var ctx = protobuf.context(buf.items, talloc);
    const m = try ctx.deserialize(&pb.descr.FileDescriptorProto.descriptor);
    defer m.deinit(talloc);
    const T = pb.descr.FileDescriptorProto;
    const data2 = try m.as(T);
    try expectEqual(T, data, data2.*);
}

const TestError = error{ TestExpectedEqual, TestExpectedApproxEqAbs };
fn expectEqual(comptime T: type, data: T, data2: T) TestError!void {
    @setEvalBranchQuota(4000);
    const tinfo = @typeInfo(T);
    switch (tinfo) {
        .Int, .Bool, .Enum => try std.testing.expectEqual(data, data2),
        .Float => try std.testing.expectApproxEqAbs(data, data2, std.math.epsilon(T)),
        .Struct => if (T == String) {
            try std.testing.expectEqualStrings(data.slice(), data2.slice());
        } else if (comptime mem.indexOf(u8, @typeName(T), "extern-types.ArrayList") != null) {
            try std.testing.expectEqual(data.len, data2.len);
            for (data.slice()) |it, i|
                try expectEqual(@TypeOf(it), it, data2.items[i]);
        } else {
            const fe = std.meta.FieldEnum(T);
            inline for (comptime std.meta.tags(fe)) |tag| {
                if (comptime mem.eql(u8, @tagName(tag), "base")) continue;
                const F = std.meta.FieldType(T, tag);
                if (!@hasDecl(T, "has")) {
                    const field = @field(data, @tagName(tag));
                    const field2 = @field(data2, @tagName(tag));
                    try expectEqual(F, field, field2);
                } else if (data.has(tag)) {
                    const field = @field(data, @tagName(tag));
                    const field2 = @field(data2, @tagName(tag));
                    try expectEqual(F, field, field2);
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
