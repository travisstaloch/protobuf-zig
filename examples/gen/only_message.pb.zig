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
const only_enum = @import("only_enum.pb.zig");

// ---
// typedefs
// ---

// ---
// message types
// ---

pub const Person = extern struct {
    base: Message,
    name: String = String.empty,
    id: i32 = 0,
    email: String = String.empty,
    kind: only_enum.SomeKind = undefined,

    pub const field_ids = [_]c_uint{ 1, 2, 3, 4 };
    pub const opt_field_ids = [_]c_uint{ 1, 2, 3, 4 };

    pub usingnamespace MessageMixins(@This());
    pub const field_descriptors = [_]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(Person, "name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "id",
            2,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Person, "id"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "email",
            3,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(Person, "email"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "kind",
            4,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(Person, "kind"),
            &only_enum.SomeKind.descriptor,
            null,
            0,
        ),
    };
};

// ---
// tests
// ---

test { // dummy test for typechecking
    std.testing.log_level = .err; // suppress 'required field' warnings
    _ = Person;
    _ = Person.descriptor;
}
