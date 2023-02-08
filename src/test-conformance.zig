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
