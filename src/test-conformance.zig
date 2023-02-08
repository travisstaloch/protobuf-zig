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
    const m = try pb.testing.deserializeBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
}

// this test is wierd. this deserialze results in an unknown field for
// field_id == 0 which seems fine. but then errors later. maybe this is correct?
// anyway leaving it here as documentation. maybe come back to it later.
test "conf Required.Proto3.ProtobufInput.IllegalZeroFieldNum_Case_1" {
    const input = "\x02\x01\x01";
    const m = try pb.testing.deserializeBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    );
    defer m.base.deinit(talloc);
    try testing.expectEqual(@as(usize, 1), m.base.unknown_fields.len);
    var buf = std.ArrayList(u8).init(talloc);
    defer buf.deinit();
    try pb.protobuf.serialize(&m.base, buf.writer());
    try testing.expectError(error.NotEnoughBytesRead, pb.testing.deserializeBytesHelper(
        test3.TestAllTypesProto3,
        buf.items,
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
