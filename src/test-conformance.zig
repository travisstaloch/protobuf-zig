const std = @import("std");
const pb = @import("protobuf");
const generated = @import("generated");
const test3 = generated.test_messages_proto3;
const testing = std.testing;

const talloc = testing.allocator;
test "conf Required.Proto3.ProtobufInput.PrematureEofInPackedFieldValue.INT64" {
    const input = "82020180";
    testing.log_level = .debug;
    try testing.expectError(error.FieldMissing, pb.testing.deserializeHexBytesHelper(
        test3.TestAllTypesProto3,
        input,
        talloc,
    ));
}
