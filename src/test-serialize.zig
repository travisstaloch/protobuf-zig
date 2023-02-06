const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

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
const encodeVarint = tcommon.encodeVarint;
const encodeFloat = tcommon.encodeFloat;
const String = pb.extern_types.String;

const talloc = testing.allocator;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const tarena = arena.allocator();

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
            encodeVarint(u8, 42),
            Key.init(.VARINT, 5), // UninterpretedOption.negative_int_value
            encodeVarint(i64, -42),
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

    var ctx = pb.protobuf.context(buf.items, talloc);
    const m = try ctx.deserialize(&pb.descr.FileDescriptorProto.descriptor);
    defer m.deinit(talloc);
    const T = pb.descr.FileDescriptorProto;
    const data2 = try m.as(T);
    try expectEqual(T, data, data2.*);
}

const TestError = error{
    TestExpectedEqual,
    TestExpectedApproxEqAbs,
    TestUnexpectedResult,
};

fn expectEqual(comptime T: type, data: T, data2: T) TestError!void {
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
                    const finfo = @typeInfo(F);
                    if (finfo == .Union) { // oneof fields
                        const ffe = std.meta.FieldEnum(F);
                        const ftags = comptime std.meta.tags(ffe);
                        inline for (T.oneof_field_ids) |oneof_ids| {
                            inline for (comptime oneof_ids.slice()) |oneof_id, i| {
                                const ftag = ftags[i];
                                try testing.expect(data.base.hasFieldId(oneof_id) ==
                                    data2.base.hasFieldId(oneof_id));
                                if (data.base.hasFieldId(oneof_id)) {
                                    const payload = @field(field, @tagName(ftag));
                                    const payload2 = @field(field2, @tagName(ftag));
                                    const U = std.meta.FieldType(F, ftag);
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
fn testInit(
    comptime T: type,
    comptime field_id: ?c_uint,
    alloc: mem.Allocator,
) mem.Allocator.Error!T {
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
            const fe = std.meta.FieldEnum(T);
            const tags = comptime std.meta.tags(fe);
            comptime var i: usize = 0;
            inline while (i + 1 < tags.len) : (i += 1) {
                const tag = tags[i + 1];
                const F = std.meta.FieldType(T, tag);
                const finfo = @typeInfo(F);
                if (finfo == .Union) {
                    const tagname = @tagName(tag);
                    const fepl = std.meta.FieldEnum(F);
                    const tagspl = (comptime std.meta.tags(fepl));
                    const tagpl = tagspl[0];
                    const C = std.meta.FieldType(F, tagpl);
                    const plchild = try testInit(C, T.field_ids[0], alloc);
                    const u = @unionInit(F, @tagName(tagpl), plchild);
                    @field(t, tagname) = u;
                    t.base.setPresent(T.field_ids[0]);

                    // std.debug.print("\n\n\nplchild {}\n", .{plchild});
                } else t.set(tag, try testInit(F, T.field_ids[i], alloc));
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

test "ser all" {
    const all_types = @import("generated").all_types;
    const T = all_types.All;

    // init the all_types object
    var data = try testInit(T, null, tarena);
    try testing.expectEqual(@as(usize, 1), data.oneof_fields.len);
    try testing.expect(data.oneof_fields.items[0].base.hasFieldId(111));

    // serialize the object to buf
    var buf = std.ArrayList(u8).init(talloc);
    defer buf.deinit();
    try protobuf.serialize(&data.base, buf.writer());

    // deserialize from buf and check equality
    var ctx = protobuf.context(buf.items, talloc);
    const m = try ctx.deserialize(&T.descriptor);
    defer m.deinit(talloc);
    const data2 = try m.as(T);
    try expectEqual(T, data, data2.*);

    // serialize m to buf2 and verify buf and buf2 are equal
    var buf2 = std.ArrayList(u8).init(talloc);
    defer buf2.deinit();
    try protobuf.serialize(m, buf2.writer());
    try testing.expectEqualStrings(buf.items, buf2.items);
}
