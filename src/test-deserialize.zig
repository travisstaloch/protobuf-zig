const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const pb = @import("protobuf");
const pbtypes = pb.types;
const plugin = pb.plugin;
const descr = pb.descriptor;
const protobuf = pb.protobuf;
const ptrfmt = pb.common.ptrfmt;
const CodeGeneratorRequest = plugin.CodeGeneratorRequest;
const FieldDescriptorProto = descr.FieldDescriptorProto;
const Tag = pbtypes.Tag;
const tcommon = pb.testing;
const lengthEncode = tcommon.lengthEncode;
const encodeMessage = tcommon.encodeMessage;
const encodeVarint = tcommon.encodeVarint;
const deserializeHelper = tcommon.deserializeHelper;
const deserializeBytesHelper = tcommon.deserializeBytesHelper;
const deserializeHexBytesHelper = tcommon.deserializeHexBytesHelper;

const talloc = testing.allocator;
// var tarena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
// const talloc = tarena.allocator();

test "examples/only_enum - system protoc" {
    const req = try deserializeHelper(CodeGeneratorRequest, "examples/only_enum.proto", talloc);
    defer req.base.deinit(talloc);
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
    // `input` was obtained by running $ zig build -Dhex && script/protoc-capture.sh examples/only_enum-1.proto
    const input = "0a1a6578616d706c65732f6f6e6c795f656e756d2d312e70726f746f1a080803100c180422007a8f010a1a6578616d706c65732f6f6e6c795f656e756d2d312e70726f746f2a140a08536f6d654b696e6412080a044e4f4e4510004a530a061204000004010a080a010c12030000120a0a0a0205001204020004010a0a0a03050001120302050d0a0b0a0405000200120303040d0a0c0a05050002000112030304080a0c0a0505000200021203030b0c620670726f746f33";
    const req = try deserializeHexBytesHelper(CodeGeneratorRequest, input, talloc);
    defer req.base.deinit(talloc);
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

    std.log.info("req {}", .{req});
}

test "nested lists" {
    const message = comptime encodeMessage(.{
        Tag.init(.LEN, 15), // CodeGeneratorRequest.proto_file
        lengthEncode(.{
            Tag.init(.LEN, 5), // FileDescriptorProto.enum_type
            lengthEncode(.{
                Tag.init(.LEN, 2), // EnumDescriptorProto.value
                lengthEncode(.{
                    Tag.init(.LEN, 1), // EnumValueDescriptorProto.name
                    lengthEncode(.{"field0"}),
                    Tag.init(.VARINT, 2), // EnumValueDescriptorProto.number
                    1,
                }),
            }),
        }),
    });
    const req = try deserializeBytesHelper(CodeGeneratorRequest, message, talloc);
    defer req.base.deinit(talloc);
    try testing.expectEqual(@as(usize, 1), req.proto_file.len);
    try testing.expectEqual(@as(usize, 1), req.proto_file.items[0].enum_type.len);
    try testing.expectEqual(@as(usize, 1), req.proto_file.items[0].enum_type.items[0].value.len);
    try testing.expectEqualStrings("field0", req.proto_file.items[0].enum_type.items[0].value.items[0].name.slice());
    try testing.expectEqual(@as(i32, 1), req.proto_file.items[0].enum_type.items[0].value.items[0].number);
}

test "examples/only_message - no deps" {
    // testing.log_level = .info;
    // `input` was obtained by running $ zig build -Dhex && script/protoc-capture.sh -I examples/ examples/only_message.proto
    const input = "0a126f6e6c795f6d6573736167652e70726f746f1a080803100c180422007a95020a0f6f6e6c795f656e756d2e70726f746f2a290a08536f6d654b696e6412080a044e4f4e45100012050a0141100112050a0142100212050a014310034ace010a061204000007010a080a010c12030000120a0a0a0205001204020007010a0a0a03050001120302050d0a0b0a0405000200120303040d0a0c0a05050002000112030304080a0c0a0505000200021203030b0c0a0b0a0405000201120304040a0a0c0a05050002010112030404050a0c0a05050002010212030408090a0b0a0405000202120305040a0a0c0a05050002020112030504050a0c0a05050002020212030508090a0b0a0405000203120306040a0a0c0a05050002030112030604050a0c0a0505000203021203060809620670726f746f337ac9030a126f6e6c795f6d6573736167652e70726f746f1a0f6f6e6c795f656e756d2e70726f746f22610a06506572736f6e12120a046e616d6518012001280952046e616d65120e0a0269641802200128055202696412140a05656d61696c1803200128095205656d61696c121d0a046b696e6418042001280e32092e536f6d654b696e6452046b696e644ab6020a06120400000a010a080a010c12030000120a090a02030012030300190a0a0a020400120405000a010a0a0a03040001120305080e0a0b0a040400020012030602120a0c0a05040002000512030602080a0c0a050400020001120306090d0a0c0a05040002000312030610110a300a0404000201120307020f222320556e69717565204944206e756d62657220666f72207468697320706572736f6e2e0a0a0c0a05040002010512030702070a0c0a050400020101120307080a0a0c0a0504000201031203070d0e0a0b0a040400020212030802130a0c0a05040002020512030802080a0c0a050400020201120308090e0a0c0a05040002020312030811120a0b0a040400020312030902140a0c0a050400020306120309020a0a0c0a0504000203011203090b0f0a0c0a0504000203031203091213620670726f746f33";
    const req = try deserializeHexBytesHelper(CodeGeneratorRequest, input, talloc);
    defer req.base.deinit(talloc);
    try testing.expectEqual(@as(usize, 1), req.file_to_generate.len);
    try testing.expectEqualStrings("only_message.proto", req.file_to_generate.items[0].slice());
    const pf = req.proto_file;
    try testing.expectEqual(@as(usize, 2), pf.len);
    try testing.expectEqual(@as(usize, 16), pf.items[0].source_code_info.location.len);
    try testing.expectEqual(@as(usize, 21), pf.items[1].source_code_info.location.len);
    const pf0et = pf.items[0].enum_type;
    try testing.expectEqual(@as(usize, 1), pf0et.len);
    try testing.expectEqualStrings("SomeKind", pf0et.items[0].name.slice());
    try testing.expectEqual(@as(usize, 4), pf0et.items[0].value.len);
    try testing.expectEqualStrings("only_message.proto", pf.items[1].name.slice());
    try testing.expectEqual(@as(usize, 1), pf.items[1].dependency.len);
    try testing.expectEqualStrings("only_enum.proto", pf.items[1].dependency.items[0].slice());

    const pf1mt = pf.items[1].message_type;
    try testing.expectEqual(@as(usize, 1), pf1mt.len);
    const mt0 = pf1mt.items[0];
    try testing.expectEqualStrings("Person", mt0.name.slice());
    try testing.expectEqual(@as(usize, 4), mt0.field.len);

    try testing.expectEqualStrings("name", mt0.field.items[0].name.slice());
    try testing.expectEqualStrings("name", mt0.field.items[0].json_name.slice());
    try testing.expectEqual(@as(i32, 1), mt0.field.items[0].number);
    try testing.expectEqual(FieldDescriptorProto.Label.LABEL_OPTIONAL, mt0.field.items[0].label);
    try testing.expectEqual(FieldDescriptorProto.Type.TYPE_STRING, mt0.field.items[0].type);

    try testing.expectEqualStrings("id", mt0.field.items[1].name.slice());
    try testing.expectEqualStrings("id", mt0.field.items[1].json_name.slice());
    try testing.expectEqual(@as(i32, 2), mt0.field.items[1].number);
    try testing.expectEqual(FieldDescriptorProto.Label.LABEL_OPTIONAL, mt0.field.items[1].label);
    try testing.expectEqual(FieldDescriptorProto.Type.TYPE_INT32, mt0.field.items[1].type);

    try testing.expectEqualStrings("email", mt0.field.items[2].name.slice());
    try testing.expectEqualStrings("email", mt0.field.items[2].json_name.slice());
    try testing.expectEqual(@as(i32, 3), mt0.field.items[2].number);
    try testing.expectEqual(FieldDescriptorProto.Label.LABEL_OPTIONAL, mt0.field.items[2].label);
    try testing.expectEqual(FieldDescriptorProto.Type.TYPE_STRING, mt0.field.items[2].type);

    try testing.expectEqualStrings("kind", mt0.field.items[3].name.slice());
    try testing.expectEqualStrings("kind", mt0.field.items[3].json_name.slice());
    try testing.expectEqual(@as(i32, 4), mt0.field.items[3].number);
    try testing.expectEqual(FieldDescriptorProto.Label.LABEL_OPTIONAL, mt0.field.items[3].label);
    try testing.expectEqual(FieldDescriptorProto.Type.TYPE_ENUM, mt0.field.items[3].type);
}

test "examples/all_types - system protoc" {
    const req = try deserializeHelper(CodeGeneratorRequest, "examples/all_types.proto", talloc);
    defer req.base.deinit(talloc);
    try testing.expectEqual(@as(usize, 1), req.file_to_generate.len);
    try testing.expectEqualStrings("examples/all_types.proto", req.file_to_generate.items[0].slice());
}

test "message deinit" {
    const message = comptime encodeMessage(.{
        Tag.init(.LEN, 15), // CodeGeneratorRequest.proto_file
        lengthEncode(.{
            Tag.init(.LEN, 5), // FileDescriptorProto.enum_type
            lengthEncode(.{
                Tag.init(.LEN, 2), // EnumDescriptorProto.value
                lengthEncode(.{
                    Tag.init(.LEN, 1), // EnumValueDescriptorProto.name
                    lengthEncode(.{"field0"}),
                    Tag.init(.VARINT, 2), // EnumValueDescriptorProto.number
                    1,
                }),
            }),
            Tag.init(.LEN, 12), // FileDescriptorProto.syntax
            lengthEncode(.{"proto3"}),
        }),
    });
    const req = try deserializeBytesHelper(CodeGeneratorRequest, message, testing.allocator);
    defer req.base.deinit(testing.allocator);
}

test "message missing required fields" {
    testing.log_level = .err;
    const req = deserializeBytesHelper(descr.UninterpretedOption.NamePart, "", talloc);
    try testing.expectError(error.RequiredFieldMissing, req);
}

test "message with map fields / nested types" {
    // this test also exercises nested types
    const req = try deserializeHelper(CodeGeneratorRequest, "examples/map.proto", talloc);
    defer req.base.deinit(talloc);
    try testing.expectEqual(@as(usize, 0), req.base.unknown_fields.len);
    try testing.expectEqual(@as(usize, 1), req.proto_file.len);
    try testing.expectEqual(@as(usize, 1), req.proto_file.items[0].message_type.len);
    try testing.expectEqual(@as(usize, 1), req.proto_file.items[0].message_type.items[0].nested_type.len);
}

test "free oneof field when overwritten" {
    const oneof_2 = @import("generated").oneof_2;
    const T = oneof_2.TestAllTypesProto3;

    const message = comptime encodeMessage(.{
        Tag.init(.LEN, 113), // TestAllTypesProto3.oneof_field__oneof_string
        lengthEncode(.{"oneof_field__oneof_string"}),
        Tag.init(.LEN, 114), // TestAllTypesProto3.oneof_field__oneof_bytes
        lengthEncode(.{"oneof_field__oneof_bytes"}),
        Tag.init(.LEN, 112), // TestAllTypesProto3.oneof_field__oneof_nested_message
        lengthEncode(.{
            Tag.init(.VARINT, 1), // TestAllTypesProto3.NestedMessage.a
            42,
        }),
        Tag.init(.VARINT, 111), // TestAllTypesProto3.oneof_field__oneof_uint32
        42,
    });

    var ctx = protobuf.context(message, talloc);
    const m = try ctx.deserialize(&T.descriptor);
    defer m.deinit(talloc);
}

test "deser group" {
    const group = @import("generated").group;
    const T = group.Grouped;

    const message = comptime encodeMessage(.{
        Tag.init(.SGROUP, 201), // Group.Data .SGROUP
        Tag.init(.VARINT, 202), // Group.Data.group_int32
        202,
        Tag.init(.VARINT, 203), // Group.Data.group_uint32
        203,
        Tag.init(.EGROUP, 201), // Group.Data .EGROUP
    });
    var ctx = protobuf.context(message, talloc);
    const m = try ctx.deserialize(&T.descriptor);
    defer m.deinit(talloc);
    const g = try m.as(T);
    try testing.expect(g.has(.data));
    try testing.expect(g.data.has(.group_int32));
    try testing.expectEqual(@as(i32, 202), g.data.group_int32);
    try testing.expect(g.data.has(.group_uint32));
    try testing.expectEqual(@as(u32, 203), g.data.group_uint32);
}
