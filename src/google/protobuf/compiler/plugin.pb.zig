//!
//! this file was originally adapted from https://github.com/protobuf-c/protobuf-c/blob/master/protobuf-c/protobuf-c.h
//! by running `$ zig translate-c` on this file and then doing lots and lots and lots and lots of editing.
//!
//! it is an effort to bootstrap the project and should eventually be generated
//! from https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/descriptor.proto
//! and https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/compiler/plugin.proto
//!

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
// TODO make types.zig into a package
const types = @import("../../../types.zig");
const String = types.String;
const ListMut = types.ListMut;
const ListMutScalar = types.ListMutScalar;
const MessageMixins = types.MessageMixins;
const EnumMixins = types.EnumMixins;
const Message = types.Message;
const FieldDescriptor = types.FieldDescriptor;
const BinaryData = types.BinaryData;

pub const UninterpretedOption = extern struct {
    base: Message,
    name: ListMut(*NamePart) = ListMut(*NamePart).initEmpty(),
    identifier_value: String = String.initEmpty(),
    positive_int_value: u64 = 0,
    negative_int_value: i64 = 0,
    double_value: f64 = 0,
    string_value: BinaryData = .{},
    aggregate_value: String = String.initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const NamePart = extern struct {
        base: Message,
        name_part: String = String.initEmpty(),
        is_extension: bool = false,

        pub usingnamespace MessageMixins(@This());

        pub const field_descriptors = [2]FieldDescriptor{
            FieldDescriptor.init(
                "name_part",
                1,
                .LABEL_REQUIRED,
                .TYPE_STRING,
                @offsetOf(NamePart, "name_part"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "is_extension",
                2,
                .LABEL_REQUIRED,
                .TYPE_BOOL,
                @offsetOf(NamePart, "is_extension"),
                null,
                null,
                0,
            ),
        };
    };

    pub const field_descriptors = [7]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            2,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(UninterpretedOption, "name"),
            &NamePart.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "identifier_value",
            3,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(UninterpretedOption, "identifier_value"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "positive_int_value",
            4,
            .LABEL_OPTIONAL,
            .TYPE_UINT64,
            @offsetOf(UninterpretedOption, "positive_int_value"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "negative_int_value",
            5,
            .LABEL_OPTIONAL,
            .TYPE_INT64,
            @offsetOf(UninterpretedOption, "negative_int_value"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "double_value",
            6,
            .LABEL_OPTIONAL,
            .TYPE_DOUBLE,
            @offsetOf(UninterpretedOption, "double_value"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "string_value",
            7,
            .LABEL_OPTIONAL,
            .TYPE_BYTES,
            @offsetOf(UninterpretedOption, "string_value"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "aggregate_value",
            8,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(UninterpretedOption, "aggregate_value"),
            null,
            null,
            0,
        ),
    };
};

pub const FieldOptions = extern struct {
    base: Message,
    ctype: CType = undefined,
    @"packed": bool = false,
    jstype: JSType = undefined,
    lazy: bool = false,
    unverified_lazy: bool = false,
    deprecated: bool = false,
    weak: bool = false,
    uninterpreted_option: ListMut(*UninterpretedOption) = ListMut(*UninterpretedOption).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const lazy__default_value = @as(c_int, 0);
    pub const unverified_lazy__default_value = @as(c_int, 0);
    pub const deprecated__default_value = @as(c_int, 0);
    pub const weak__default_value = @as(c_int, 0);

    const CType = enum(u8) {
        // Default mode.
        STRING = 0,
        CORD = 1,
        STRING_PIECE = 2,

        pub const default_value: CType = .STRING;
        pub usingnamespace EnumMixins(@This());
    };

    const JSType = enum(u8) {
        // Use the default type.
        JS_NORMAL = 0,

        // Use JavaScript strings.
        JS_STRING = 1,

        // Use JavaScript numbers.
        JS_NUMBER = 2,

        pub const default_value: JSType = .JS_NORMAL;
        pub usingnamespace EnumMixins(@This());
    };

    pub const field_descriptors = [_]FieldDescriptor{
        FieldDescriptor.init(
            "ctype",
            1,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(FieldOptions, "ctype"),
            &CType.descriptor,
            &CType.default_value,
            0,
        ),
        FieldDescriptor.init(
            "packed",
            2,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "packed"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "jstype",
            6,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(FieldOptions, "jstype"),
            &JSType.descriptor,
            &JSType.default_value,
            0,
        ),
        FieldDescriptor.init(
            "lazy",
            5,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "lazy"),
            null,
            &lazy__default_value,
            0,
        ),
        FieldDescriptor.init(
            "unverified_lazy",
            15,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "unverified_lazy"),
            null,
            &unverified_lazy__default_value,
            0,
        ),
        FieldDescriptor.init(
            "deprecated",
            3,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "deprecated"),
            null,
            &deprecated__default_value,
            0,
        ),
        FieldDescriptor.init(
            "weak",
            10,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "weak"),
            null,
            &weak__default_value,
            0,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FieldOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
            0,
        ),
    };
};

pub const FieldDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    number: i32 = 0,
    label: Label = .LABEL_ERROR,
    type: Type = .TYPE_ERROR,
    type_name: String = String.initEmpty(),
    extendee: String = String.initEmpty(),
    default_value: String = String.initEmpty(),
    oneof_index: i32 = 0,
    json_name: String = String.initEmpty(),
    options: FieldOptions = FieldOptions.init(),
    proto3_optional: bool = false,

    pub usingnamespace MessageMixins(@This());

    pub const Type = enum(u8) {
        // 0 is reserved for errors.
        TYPE_ERROR = 0,
        // Order is weird for historical reasons.
        TYPE_DOUBLE = 1,
        TYPE_FLOAT = 2,
        // Not ZigZag encoded.  Negative numbers take 10 bytes.  Use sint64 if
        // negative values are likely.
        TYPE_INT64 = 3,
        TYPE_UINT64 = 4,
        // Not ZigZag encoded.  Negative numbers take 10 bytes.  Use sint32 if
        // negative values are likely.
        TYPE_INT32 = 5,
        TYPE_FIXED64 = 6,
        TYPE_FIXED32 = 7,
        TYPE_BOOL = 8,
        TYPE_STRING = 9,
        // Tag-delimited aggregate.
        // Group type is deprecated and not supported in proto3. However, Proto3
        // implementations should still be able to parse the group wire format and
        // treat group fields as unknown fields.
        TYPE_GROUP = 10,
        TYPE_MESSAGE = 11, // Length-delimited aggregate.

        // New in version 2.
        TYPE_BYTES = 12,
        TYPE_UINT32 = 13,
        TYPE_ENUM = 14,
        TYPE_SFIXED32 = 15,
        TYPE_SFIXED64 = 16,
        TYPE_SINT32 = 17, // Uses ZigZag encoding.
        TYPE_SINT64 = 18, // Uses ZigZag encoding.

        pub usingnamespace EnumMixins(@This());
    };

    pub const Label = enum(u8) {
        LABEL_ERROR = 0,
        LABEL_OPTIONAL = 1,
        LABEL_REQUIRED = 2,
        LABEL_REPEATED = 3,

        pub usingnamespace EnumMixins(@This());
    };

    pub const field_descriptors = [_]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FieldDescriptorProto, "name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "number",
            3,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(FieldDescriptorProto, "number"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "label",
            4,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(FieldDescriptorProto, "label"),
            &Label.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "type",
            5,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(FieldDescriptorProto, "type"),
            &FieldDescriptorProto.Type.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "type_name",
            6,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FieldDescriptorProto, "type_name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "extendee",
            2,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FieldDescriptorProto, "extendee"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "default_value",
            7,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FieldDescriptorProto, "default_value"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "oneof_index",
            9,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(FieldDescriptorProto, "oneof_index"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "json_name",
            10,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FieldDescriptorProto, "json_name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "options",
            8,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(FieldDescriptorProto, "options"),
            &FieldOptions.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "proto3_optional",
            17,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldDescriptorProto, "proto3_optional"),
            null,
            null,
            0,
        ),
    };
};

pub const EnumValueOptions = extern struct {
    base: Message,
    deprecated: bool = false,
    uninterpreted_option: ListMut(*UninterpretedOption) = ListMut(*UninterpretedOption).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const deprecated__default_value = false;
    pub const field_descriptors = [2]FieldDescriptor{
        FieldDescriptor.init(
            "deprecated",
            1,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(EnumValueOptions, "deprecated"),
            null,
            &deprecated__default_value,
            0,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(EnumValueOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
            0,
        ),
    };
};

pub const EnumValueDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    number: i32 = 0,
    options: EnumValueOptions = EnumValueOptions.init(),

    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [3]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(EnumValueDescriptorProto, "name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "number",
            2,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(EnumValueDescriptorProto, "number"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "options",
            3,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(EnumValueDescriptorProto, "options"),
            &EnumValueOptions.descriptor,
            null,
            0,
        ),
    };
};

pub const EnumOptions = extern struct {
    base: Message,
    allow_alias: bool = false,
    deprecated: bool = false,
    uninterpreted_option: ListMut(*UninterpretedOption) = ListMut(*UninterpretedOption).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const deprecated__default_value = false;
    pub const field_descriptors = [3]FieldDescriptor{
        FieldDescriptor.init(
            "allow_alias",
            2,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(EnumOptions, "allow_alias"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "deprecated",
            3,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(EnumOptions, "deprecated"),
            null,
            &deprecated__default_value,
            0,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(EnumOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
            0,
        ),
    };
};

pub const EnumDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    value: ListMut(*EnumValueDescriptorProto) = ListMut(*EnumValueDescriptorProto).initEmpty(),
    options: EnumOptions = EnumOptions.init(),
    reserved_range: ListMut(*EnumReservedRange) = ListMut(*EnumReservedRange).initEmpty(),
    reserved_name: ListMutScalar(String) = ListMutScalar(String).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const EnumReservedRange = extern struct {
        base: Message,
        start: i32 = 0,
        end: i32 = 0,

        pub usingnamespace MessageMixins(@This());

        pub const field_descriptors = [2]FieldDescriptor{
            FieldDescriptor.init(
                "start",
                1,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(EnumReservedRange, "start"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "end",
                2,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(EnumReservedRange, "end"),
                null,
                null,
                0,
            ),
        };
    };

    pub const field_descriptors = [_]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(EnumDescriptorProto, "name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "value",
            2,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(EnumDescriptorProto, "value"),
            &EnumValueDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "options",
            3,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(EnumDescriptorProto, "options"),
            &EnumOptions.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "reserved_range",
            4,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(EnumDescriptorProto, "reserved_range"),
            &EnumReservedRange.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "reserved_name",
            5,
            .LABEL_REPEATED,
            .TYPE_STRING,
            @offsetOf(EnumDescriptorProto, "reserved_name"),
            null,
            null,
            0,
        ),
    };
};

pub const ExtensionRangeOptions = extern struct {
    base: Message,
    uninterpreted_option: ListMut(*UninterpretedOption) = ListMut(*UninterpretedOption).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [1]FieldDescriptor{
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(ExtensionRangeOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
            0,
        ),
    };
};
pub const OneofOptions = extern struct {
    base: Message,
    uninterpreted_option: ListMut(*UninterpretedOption) = ListMut(*UninterpretedOption).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [1]FieldDescriptor{
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(OneofOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
            0,
        ),
    };
};

pub const OneofDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    options: OneofOptions = OneofOptions.init(),

    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [2]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(OneofDescriptorProto, "name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "options",
            2,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(OneofDescriptorProto, "options"),
            &OneofOptions.descriptor,
            null,
            0,
        ),
    };
};

pub const MessageOptions = extern struct {
    base: Message,
    message_set_wire_format: bool = false,
    no_standard_descriptor_accessor: bool = false,
    deprecated: bool = false,
    map_entry: bool = false,
    uninterpreted_option: ListMut(*UninterpretedOption) = ListMut(*UninterpretedOption).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const message_set_wire_format__default_value: c_int = 0;
    pub const no_standard_descriptor_accessor__default_value: c_int = 0;
    pub const deprecated__default_value: c_int = 0;
    pub const field_descriptors = [5]FieldDescriptor{
        FieldDescriptor.init(
            "message_set_wire_format",
            1,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MessageOptions, "message_set_wire_format"),
            null,
            &message_set_wire_format__default_value,
            0,
        ),
        FieldDescriptor.init(
            "no_standard_descriptor_accessor",
            2,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MessageOptions, "no_standard_descriptor_accessor"),
            null,
            &no_standard_descriptor_accessor__default_value,
            0,
        ),
        FieldDescriptor.init(
            "deprecated",
            3,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MessageOptions, "deprecated"),
            null,
            &deprecated__default_value,
            0,
        ),
        FieldDescriptor.init(
            "map_entry",
            7,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MessageOptions, "map_entry"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(MessageOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
            0,
        ),
    };
};

pub const DescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    field: ListMut(*FieldDescriptorProto) = ListMut(*FieldDescriptorProto).initEmpty(),
    extension: ListMut(*FieldDescriptorProto) = ListMut(*FieldDescriptorProto).initEmpty(),
    nested_type: types.ArrayListMut(*DescriptorProto) = .{ .items = types.ArrayListMut(*DescriptorProto).list_sentinel_ptr }, // workaround for 'dependency loop'
    enum_type: ListMut(*EnumDescriptorProto) = ListMut(*EnumDescriptorProto).initEmpty(),
    extension_range: ListMut(*ExtensionRange) = ListMut(*ExtensionRange).initEmpty(),
    oneof_decl: ListMut(*OneofDescriptorProto) = ListMut(*OneofDescriptorProto).initEmpty(),
    options: MessageOptions = MessageOptions.init(),
    reserved_range: ListMut(*ReservedRange) = ListMut(*ReservedRange).initEmpty(),
    reserved_name: ListMutScalar(String) = ListMutScalar(String).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const ExtensionRange = extern struct {
        base: Message,
        start: i32 = 0,
        end: i32 = 0,
        options: ExtensionRangeOptions = ExtensionRangeOptions.init(),

        pub usingnamespace MessageMixins(@This());

        pub const field_descriptors = [3]FieldDescriptor{
            FieldDescriptor.init(
                "start",
                1,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(ExtensionRange, "start"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "end",
                2,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(ExtensionRange, "end"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "options",
                3,
                .LABEL_OPTIONAL,
                .TYPE_MESSAGE,
                @offsetOf(ExtensionRange, "options"),
                &ExtensionRangeOptions.descriptor,
                null,
                0,
            ),
        };
    };

    pub const ReservedRange = extern struct {
        base: Message,
        start: i32 = 0,
        end: i32 = 0,

        pub usingnamespace MessageMixins(@This());

        pub const field_descriptors = [2]FieldDescriptor{
            FieldDescriptor.init(
                "start",
                1,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(ReservedRange, "start"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "end",
                2,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(ReservedRange, "end"),
                null,
                null,
                0,
            ),
        };
    };

    pub const field_descriptors = [_]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(DescriptorProto, "name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "field",
            2,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "field"),
            &FieldDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "extension",
            6,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "extension"),
            &FieldDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "nested_type",
            std.math.maxInt(u32) - 3, // workaround for 'dependency loop'
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "nested_type"),
            null, // workaround for 'dependency loop'
            null,
            0,
        ),
        FieldDescriptor.init(
            "enum_type",
            4,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "enum_type"),
            &EnumDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "extension_range",
            5,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "extension_range"),
            &ExtensionRange.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "oneof_decl",
            8,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "oneof_decl"),
            &OneofDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "options",
            7,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "options"),
            &MessageOptions.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "reserved_range",
            9,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "reserved_range"),
            &ReservedRange.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "reserved_name",
            10,
            .LABEL_REPEATED,
            .TYPE_STRING,
            @offsetOf(DescriptorProto, "reserved_name"),
            null,
            null,
            0,
        ),
    };
};

pub const MethodOptions = extern struct {
    base: Message,
    deprecated: bool = false,
    idempotency_level: IdempotencyLevel = undefined,
    uninterpreted_option: ListMut(*UninterpretedOption) = ListMut(*UninterpretedOption).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const IdempotencyLevel = enum(u8) {
        IDEMPOTENCY_UNKNOWN,
        NO_SIDE_EFFECTS,
        IDEMPOTENT,

        pub usingnamespace EnumMixins(@This());
    };

    pub const deprecated__default_value: c_uint = 0;
    pub const idempotency_level__default_value: IdempotencyLevel = .IDEMPOTENCY_UNKNOWN;
    pub const field_descriptors = [3]FieldDescriptor{
        FieldDescriptor.init(
            "deprecated",
            33,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MethodOptions, "deprecated"),
            null,
            &deprecated__default_value,
            0,
        ),
        FieldDescriptor.init(
            "idempotency_level",
            34,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(MethodOptions, "idempotency_level"),
            &IdempotencyLevel.descriptor,
            &idempotency_level__default_value,
            0,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(MethodOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
            0,
        ),
    };
};

pub const MethodDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    input_type: String = String.initEmpty(),
    output_type: String = String.initEmpty(),
    options: MethodOptions = MethodOptions.init(),
    client_streaming: bool = false,
    server_streaming: bool = false,

    pub usingnamespace MessageMixins(@This());

    pub const client_streaming__default_value: c_int = 0;
    pub const server_streaming__default_value: c_int = 0;
    pub const field_descriptors = [6]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(MethodDescriptorProto, "name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "input_type",
            2,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(MethodDescriptorProto, "input_type"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "output_type",
            3,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(MethodDescriptorProto, "output_type"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "options",
            4,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(MethodDescriptorProto, "options"),
            &MethodOptions.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "client_streaming",
            5,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MethodDescriptorProto, "client_streaming"),
            null,
            &client_streaming__default_value,
            0,
        ),
        FieldDescriptor.init(
            "server_streaming",
            6,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MethodDescriptorProto, "server_streaming"),
            null,
            &server_streaming__default_value,
            0,
        ),
    };
};

pub const ServiceOptions = extern struct {
    base: Message,
    deprecated: bool = false,
    uninterpreted_option: ListMut(*UninterpretedOption) = ListMut(*UninterpretedOption).initEmpty(),

    pub const deprecated__default_value: c_int = 0;
    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [2]FieldDescriptor{
        FieldDescriptor.init(
            "deprecated",
            33,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(ServiceOptions, "deprecated"),
            null,
            &deprecated__default_value,
            0,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(ServiceOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
            0,
        ),
    };
};

pub const ServiceDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    method: ListMut(*MethodDescriptorProto) = ListMut(*MethodDescriptorProto).initEmpty(),
    options: ServiceOptions = ServiceOptions.init(),

    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [3]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(ServiceDescriptorProto, "name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "method",
            2,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(ServiceDescriptorProto, "method"),
            &MethodDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "options",
            3,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(ServiceDescriptorProto, "options"),
            &ServiceOptions.descriptor,
            null,
            0,
        ),
    };
};

pub const FileOptions = extern struct {
    base: Message,
    java_package: String = String.initEmpty(),
    java_outer_classname: String = String.initEmpty(),
    java_multiple_files: bool = false,
    java_generate_equals_and_hash: bool = false,
    java_string_check_utf8: bool = false,
    optimize_for: OptimizeMode = undefined,
    go_package: String = String.initEmpty(),
    cc_generic_services: bool = false,
    java_generic_services: bool = false,
    py_generic_services: bool = false,
    php_generic_services: bool = false,
    deprecated: bool = false,
    cc_enable_arenas: bool = false,
    objc_class_prefix: String = String.initEmpty(),
    csharp_namespace: String = String.initEmpty(),
    swift_prefix: String = String.initEmpty(),
    php_class_prefix: String = String.initEmpty(),
    php_namespace: String = String.initEmpty(),
    php_metadata_namespace: String = String.initEmpty(),
    ruby_package: String = String.initEmpty(),
    uninterpreted_option: ListMut(*UninterpretedOption) = ListMut(*UninterpretedOption).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const OptimizeMode = enum(u8) {
        NONE = 0,
        SPEED = 1,
        CODE_SIZE = 2,
        LITE_RUNTIME = 3,

        pub usingnamespace EnumMixins(@This());
    };
    pub const java_multiple_files__default_value: c_int = 0;
    pub const java_string_check_utf8__default_value: c_int = 0;
    pub const optimize_for__default_value: FileOptions.OptimizeMode = .SPEED;
    pub const cc_generic_services__default_value: c_int = 0;
    pub const java_generic_services__default_value: c_int = 0;
    pub const py_generic_services__default_value: c_int = 0;
    pub const php_generic_services__default_value: c_int = 0;
    pub const deprecated__default_value: c_int = 0;
    pub const cc_enable_arenas__default_value: c_int = 1;
    pub const field_descriptors = [21]FieldDescriptor{
        FieldDescriptor.init(
            "java_package",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "java_package"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "java_outer_classname",
            8,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "java_outer_classname"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "java_multiple_files",
            10,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "java_multiple_files"),
            null,
            &java_multiple_files__default_value,
            0,
        ),
        FieldDescriptor.init(
            "java_generate_equals_and_hash",
            20,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "java_generate_equals_and_hash"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "java_string_check_utf8",
            27,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "java_string_check_utf8"),
            null,
            &java_string_check_utf8__default_value,
            0,
        ),
        FieldDescriptor.init(
            "optimize_for",
            9,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(FileOptions, "optimize_for"),
            &OptimizeMode.descriptor,
            &optimize_for__default_value,
            0,
        ),
        FieldDescriptor.init(
            "go_package",
            11,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "go_package"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "cc_generic_services",
            16,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "cc_generic_services"),
            null,
            &cc_generic_services__default_value,
            0,
        ),
        FieldDescriptor.init(
            "java_generic_services",
            17,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "java_generic_services"),
            null,
            &java_generic_services__default_value,
            0,
        ),
        FieldDescriptor.init(
            "py_generic_services",
            18,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "py_generic_services"),
            null,
            &py_generic_services__default_value,
            0,
        ),
        FieldDescriptor.init(
            "php_generic_services",
            42,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "php_generic_services"),
            null,
            &php_generic_services__default_value,
            0,
        ),
        FieldDescriptor.init(
            "deprecated",
            23,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "deprecated"),
            null,
            &deprecated__default_value,
            0,
        ),
        FieldDescriptor.init(
            "cc_enable_arenas",
            31,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "cc_enable_arenas"),
            null,
            &cc_enable_arenas__default_value,
            0,
        ),
        FieldDescriptor.init(
            "objc_class_prefix",
            36,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "objc_class_prefix"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "csharp_namespace",
            37,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "csharp_namespace"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "swift_prefix",
            39,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "swift_prefix"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "php_class_prefix",
            40,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "php_class_prefix"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "php_namespace",
            41,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "php_namespace"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "php_metadata_namespace",
            44,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "php_metadata_namespace"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "ruby_package",
            45,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "ruby_package"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
            0,
        ),
    };
};

pub const SourceCodeInfo = extern struct {
    base: Message,
    location: ListMut(*Location) = ListMut(*Location).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const Location = extern struct {
        base: Message,
        path: ListMutScalar(i32) = ListMutScalar(i32).initEmpty(),
        span: ListMutScalar(i32) = ListMutScalar(i32).initEmpty(),
        leading_comments: String = String.initEmpty(),
        trailing_comments: String = String.initEmpty(),
        leading_detached_comments: ListMutScalar(String) = ListMutScalar(String).initEmpty(),

        pub usingnamespace MessageMixins(@This());

        pub const field_descriptors = [5]FieldDescriptor{
            FieldDescriptor.init(
                "path",
                1,
                .LABEL_REPEATED,
                .TYPE_INT32,
                @offsetOf(Location, "path"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "span",
                2,
                .LABEL_REPEATED,
                .TYPE_INT32,
                @offsetOf(Location, "span"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "leading_comments",
                3,
                .LABEL_OPTIONAL,
                .TYPE_STRING,
                @offsetOf(Location, "leading_comments"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "trailing_comments",
                4,
                .LABEL_OPTIONAL,
                .TYPE_STRING,
                @offsetOf(Location, "trailing_comments"),
                null,
                null,
                0,
            ),
            FieldDescriptor.init(
                "leading_detached_comments",
                6,
                .LABEL_REPEATED,
                .TYPE_STRING,
                @offsetOf(Location, "leading_detached_comments"),
                null,
                null,
                0,
            ),
        };
    };
    pub const field_descriptors = [1]FieldDescriptor{
        FieldDescriptor.init(
            "location",
            1,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(SourceCodeInfo, "location"),
            &Location.descriptor,
            null,
            0,
        ),
    };
};

pub const FileDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    package: String = String.initEmpty(),
    dependency: ListMutScalar(String) = ListMutScalar(String).initEmpty(),
    public_dependency: ListMutScalar(i32) = ListMutScalar(i32).initEmpty(),
    weak_dependency: ListMutScalar(i32) = ListMutScalar(i32).initEmpty(),
    message_type: ListMut(*DescriptorProto) = ListMut(*DescriptorProto).initEmpty(),
    enum_type: ListMut(*EnumDescriptorProto) = ListMut(*EnumDescriptorProto).initEmpty(),
    service: ListMut(*ServiceDescriptorProto) = ListMut(*ServiceDescriptorProto).initEmpty(),
    extension: ListMut(*FieldDescriptorProto) = ListMut(*FieldDescriptorProto).initEmpty(),
    options: FileOptions = FileOptions.init(),
    source_code_info: SourceCodeInfo = SourceCodeInfo.init(),
    syntax: String = String.initEmpty(),
    edition: String = String.initEmpty(),

    comptime {
        // @compileLog(@sizeOf(FileDescriptorProto));
        assert(@sizeOf(FileDescriptorProto) == 576);
        // @compileLog(@offsetOf(FileDescriptorProto, "enum_type"));
        assert(@offsetOf(FileDescriptorProto, "enum_type") == 0xa8); //  == 168
    }

    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [13]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "name"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "package",
            2,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "package"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "dependency",
            3,
            .LABEL_REPEATED,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "dependency"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "public_dependency",
            10,
            .LABEL_REPEATED,
            .TYPE_INT32,
            @offsetOf(FileDescriptorProto, "public_dependency"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "weak_dependency",
            11,
            .LABEL_REPEATED,
            .TYPE_INT32,
            @offsetOf(FileDescriptorProto, "weak_dependency"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "message_type",
            4,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "message_type"),
            &DescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "enum_type",
            5,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "enum_type"),
            &EnumDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "service",
            6,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "service"),
            &ServiceDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "extension",
            7,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "extension"),
            &FieldDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "options",
            8,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "options"),
            &FileOptions.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "source_code_info",
            9,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "source_code_info"),
            &SourceCodeInfo.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "syntax",
            12,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "syntax"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "edition",
            13,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "edition"),
            null,
            null,
            0,
        ),
    };
};

pub const FileDescriptorSet = extern struct {
    base: Message,
    file: ListMut(*FileDescriptorProto) = ListMut(*FileDescriptorProto).initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [1]FieldDescriptor{
        FieldDescriptor.init(
            "file",
            1,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorSet, "file"),
            &FileDescriptorProto.descriptor,
            null,
            0,
        ),
    };
};
// pub const GeneratedCodeInfo__Annotation = extern struct {
//     base: Message,
//     path: [*c]i32,
//     source_file: String = String.initEmpty(),
//     begin: i32 = 0,
//     end: i32 = 0,
//     semantic: GeneratedCodeInfo__Annotation__Semantic,
// };

// pub const GeneratedCodeInfo = extern struct {
//     base: Message,
//     annotation: [*c][*c]GeneratedCodeInfo__Annotation,
// };

pub const Version = extern struct {
    base: Message,
    major: i32 = 0,
    minor: i32 = 0,
    patch: i32 = 0,
    suffix: String = String.initEmpty(),

    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [4]FieldDescriptor{
        FieldDescriptor.init(
            "major",
            1,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Version, "major"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "minor",
            2,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Version, "minor"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "patch",
            3,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Version, "patch"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "suffix",
            4,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(Version, "suffix"),
            null,
            null,
            0,
        ),
    };
};

pub const CodeGeneratorRequest = extern struct {
    base: Message,
    file_to_generate: ListMutScalar(String) = ListMutScalar(String).initEmpty(),
    parameter: String = String.initEmpty(),
    proto_file: ListMut(*FileDescriptorProto) = ListMut(*FileDescriptorProto).initEmpty(),
    compiler_version: Version = Version.init(),

    comptime {
        // @compileLog(@sizeOf(CodeGeneratorRequest));
        assert(@sizeOf(CodeGeneratorRequest) == 176);
        // @compileLog(@offsetOf(CodeGeneratorRequest, "proto_file"));
        assert(@offsetOf(CodeGeneratorRequest, "proto_file") == 0x50); //  == 80
    }

    pub usingnamespace MessageMixins(@This());

    pub const field_descriptors = [4]FieldDescriptor{
        FieldDescriptor.init(
            "file_to_generate",
            1,
            .LABEL_REPEATED,
            .TYPE_STRING,
            @offsetOf(CodeGeneratorRequest, "file_to_generate"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "parameter",
            2,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(CodeGeneratorRequest, "parameter"),
            null,
            null,
            0,
        ),
        FieldDescriptor.init(
            "proto_file",
            15,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(CodeGeneratorRequest, "proto_file"),
            &FileDescriptorProto.descriptor,
            null,
            0,
        ),
        FieldDescriptor.init(
            "compiler_version",
            3,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(CodeGeneratorRequest, "compiler_version"),
            &Version.descriptor,
            null,
            0,
        ),
    };
};

// pub const CodeGeneratorResponse__File = extern struct {
//     base: Message,
//     name: String = String.initEmpty(),
//     insertion_point: String = String.initEmpty(),
//     content: String = String.initEmpty(),
//     generated_code_info: [*c]GeneratedCodeInfo,
// };

// pub const CodeGeneratorResponse = extern struct {
//     base: Message,
//     @"error": String = String.initEmpty(),
//     supported_features: u64 = 0,
//     file: [*c][*c]Compiler__CodeGeneratorResponse__File,
// };
