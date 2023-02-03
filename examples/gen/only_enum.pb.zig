// ---
// prelude
// ---

const std = @import("std");
const pb = @import("protobuf");
const pbtypes = pb.pbtypes;
const MessageDescriptor = pbtypes.MessageDescriptor;
const Message = pbtypes.Message;
const FieldDescriptor = pbtypes.FieldDescriptor;
const EnumMixins = pbtypes.EnumMixins;
const MessageMixins = pbtypes.MessageMixins;
const FieldFlag = FieldDescriptor.FieldFlag;
const String = pb.extern_types.String;
const ArrayListMut = pb.extern_types.ArrayListMut;

// ---
// typedefs
// ---

pub const SomeKind = enum(i32) {
    NONE = 0,
    A = 1,
    B = 2,
    C = 3,

    pub usingnamespace EnumMixins(@This());
};
// ---
// message types
// ---

// ---
// tests
// ---

test { // dummy test for typechecking
    std.testing.log_level = .err; // suppress 'required field' warnings
    _ = SomeKind;
}
