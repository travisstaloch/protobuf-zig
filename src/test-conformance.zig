const std = @import("std");
const pb = @import("protobuf");
const generated = @import("generated");
const test3 = generated.test_messages_proto3;
const testing = std.testing;

const talloc = testing.allocator;
test "conf Required.Proto3.ProtobufInput.PrematureEofInPackedFieldValue.INT64" {
    const input = "82020180";
    try testing.expectError(error.FieldMissing, pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    ));
}

test "conf Required.Proto3.ProtobufInput.IllegalZeroFieldNum_Case_0" {
    const input = "\x01DEADBEEF";
    try testing.expectError(error.FieldMissing, pb.testing.deserializeBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    ));
}

test "conf Required.Proto3.ProtobufInput.ValidDataScalar.BOOL[4].ProtobufOutput" {
    const input = "688080808020";
    const m = try pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
    try testing.expect(m.has(.optional_bool));
    try testing.expect(m.optional_bool);
    var buf = std.ArrayList(u8).init(talloc);
    defer buf.deinit();
    try pb.protobuf.serialize(&m.base, buf.writer());
    const m2 = try pb.testing.deserializeBytesHelper(
        test3.TestAllTypesProto3,
        buf.items,
        talloc,
    );
    defer m2.base.deinit(talloc);
    try testing.expect(m2.has(.optional_bool));
    try testing.expect(m2.optional_bool);
}

test "conf Required.Proto3.ProtobufInput.RepeatedScalarSelectsLast.BOOL.ProtobufOutput" {
    const input = "6800680168ffffffffffffffffff0168cec2f10568808080802068ffffffffffffffff7f6880808080808080808001";
    const m = try pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
    try testing.expect(m.has(.optional_bool));
    try testing.expect(m.optional_bool);
    var buf = std.ArrayList(u8).init(talloc);
    defer buf.deinit();
    try pb.protobuf.serialize(&m.base, buf.writer());
    const m2 = try pb.testing.deserializeBytesHelper(
        test3.TestAllTypesProto3,
        buf.items,
        talloc,
    );
    defer m2.base.deinit(talloc);
    try testing.expect(m2.has(.optional_bool));
    try testing.expect(m2.optional_bool);
}

test "conf Required.Proto3.ProtobufInput.ValidDataRepeated.BOOL.PackedInput.ProtobufOutput" {
    const input = "da02280001ffffffffffffffffff01cec2f1058080808020ffffffffffffffff7f80808080808080808001";
    const m = try pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
    try testing.expect(m.has(.repeated_bool));
    try testing.expectEqual(@as(usize, 7), m.repeated_bool.len);
    try testing.expectEqual(false, m.repeated_bool.items[0]);
    try testing.expectEqual(false, m.repeated_bool.items[1]);
    try testing.expectEqual(false, m.repeated_bool.items[2]);
    try testing.expectEqual(false, m.repeated_bool.items[3]);
    try testing.expectEqual(true, m.repeated_bool.items[4]);
    try testing.expectEqual(false, m.repeated_bool.items[5]);
    try testing.expectEqual(false, m.repeated_bool.items[6]);
}

test "conf Required.Proto3.ProtobufInput.RepeatedScalarSelectsLast.SINT32.ProtobufOutput" {
    const input = "280028f2c00128feffffff0f28ffffffff0f288280808010";
    const m = try pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
    try testing.expect(m.has(.optional_sint32));
    try testing.expectEqual(@as(i32, 1), m.optional_sint32);
}

test "conf Required.Proto3.ProtobufInput.ValidDataRepeated.SINT32.UnpackedInput.ProtobufOutput" {
    const input = "9802009802f2c0019802feffffff0f9802ffffffff0f98028280808010";
    const m = try pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
    try testing.expect(m.has(.repeated_sint32));
    try testing.expectEqual(@as(usize, 5), m.repeated_sint32.len);
    try testing.expectEqual(@as(i32, 0), m.repeated_sint32.items[0]);
    try testing.expectEqual(@as(i32, 12345), m.repeated_sint32.items[1]);
    try testing.expectEqual(@as(i32, 2147483647), m.repeated_sint32.items[2]);
    try testing.expectEqual(@as(i32, -2147483648), m.repeated_sint32.items[3]);
    try testing.expectEqual(@as(i32, 1), m.repeated_sint32.items[4]);
}

test "conf Required.Proto3.ProtobufInput.ValidDataOneof.MESSAGE.Merge.ProtobufOutput" {
    // this is failing because nested messages aren't working yet
    // TODO re-enable after #1 is resolved and recursive messages work
    if (true) return error.SkipZigTest;
    const input = "820709120708011001c8050182070712051001c80501";
    testing.log_level = .debug;
    const m = try pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
    try testing.expect(m.has(.oneof_field__oneof_nested_message));
    // TODO add expectations
    const nested = m.oneof_field.oneof_nested_message;
    _ = nested;
    // try testing.expect(nested.has(.corecursive));
}

test "conf Required.Proto3.ProtobufInput.ValidDataMap.STRING.MESSAGE.MergeValue.ProtobufOutput" {
    // this is failing because nested messages aren't working yet
    // TODO re-enable after #1 is resolved and recursive messages work
    if (true) return error.SkipZigTest;
    const input = "ba040b0a00120712050801f80101ba040b0a00120712051001f80101";
    testing.log_level = .debug;
    const m = try pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
    // TODO add expectations
    const nested = m.oneof_field.oneof_nested_message;
    _ = nested;
    // try testing.expect(nested.has(.corecursive));
}

test "conf Required.Proto3.ProtobufInput.UnknownVarint.ProtobufOutput" {
    const input = "a81f01";
    const m = try pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
    var buf = std.ArrayList(u8).init(talloc);
    defer buf.deinit();
    try pb.protobuf.serialize(&m.base, buf.writer());
    const hex = try std.fmt.allocPrint(
        talloc,
        "{}",
        .{std.fmt.fmtSliceHexLower(buf.items)},
    );
    defer talloc.free(hex);
    try testing.expectEqualSlices(u8, input, hex);
}
