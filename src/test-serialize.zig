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

test "basic serialization" {
    var data = pb.descr.FieldOptions.init();
    data.set(.ctype, .STRING);
    data.set(.lazy, true);
    data.setPresentField(.uninterpreted_option);
    var ui = pb.descr.UninterpretedOption.init();
    ui.set(.identifier_value, String.init("ident"));
    ui.set(.positive_int_value, 42);
    ui.set(.negative_int_value, -42);
    ui.set(.double_value, 42);
    try data.uninterpreted_option.append(talloc, &ui);
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
