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
const types = @import("../../../types.zig");
const String = types.String;
const empty_str = types.empty_str;

const WireType = types.WireType;
const BinaryType = types.BinaryType;

// fn ListMut(comptime T: type) type {
//     assert(@typeInfo(T) == .Struct);
//     return types.SegmentedList0(T);
// }
const List = types.ListType;
const ListMut = types.ListTypeMut;
const ListMut1 = types.ListTypeMut;
// fn ListMut1(comptime T: type) type {
//     assert(T == String or @typeInfo(T) != .Struct);
//     return types.ArrayListMut(T);
// }

pub const SERVICE_DESCRIPTOR_MAGIC = 0x14159bc3;
pub const MESSAGE_DESCRIPTOR_MAGIC = 0x28aaeef9;
pub const ENUM_DESCRIPTOR_MAGIC = 0x114315af;
pub const MessageInit = ?*const fn ([*]u8, usize) void;

pub fn InitBytes(comptime T: type) MessageInit {
    return struct {
        pub fn initBytes(bytes: [*]u8, len: usize) void {
            assert(len == @sizeOf(T));
            // var ptr = @ptrCast(*T, @alignCast(@alignOf(T), bytes));
            var ptr = @ptrCast(*T, @alignCast(@typeInfo(*T).Pointer.alignment, bytes));
            if (@ptrToInt(ptr) == types.sentinel_pointer) @panic("invalid pointer");
            // std.log.debug("initBytes bytes={*} ptr.base.descriptor={*}", .{ bytes, ptr.base.descriptor });
            ptr.* = T.init();
        }
    }.initBytes;
}

pub fn Init(comptime T: type) fn () T {
    return struct {
        pub fn init() T {
            return .{
                .base = Message.init(&T.descriptor),
            };
        }
    }.init;
}

const WriteErr = std.fs.File.WriteError;
pub fn FormatFn(comptime T: type) type {
    return fn (T, comptime []const u8, std.fmt.FormatOptions, anytype) WriteErr!void;
}
pub fn Format(comptime T: type) FormatFn(T) {
    return struct {
        pub fn format(value: T, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) WriteErr!void {
            // try writer.print("{s}.{s} :: ", .{ T.descriptor.package_name, T.descriptor.name });
            try writer.print("{s} :: ", .{T.descriptor.name.slice()});
            inline for (std.meta.fields(T)[1..]) |f, i| { // skip base: Message

                // skip if optional field and not present
                const field_id = T.__field_ids[i];

                const is_required_or_present_opt =
                    value.base.isPresent(field_id) orelse true;

                if (is_required_or_present_opt) {
                    if (i != 1) _ = try writer.write(", ");

                    const info = @typeInfo(f.type);
                    switch (info) {
                        .Struct => {
                            // try writer.print("{s} has Child {}\n", .{ @typeName(f.type), @hasDecl(f.type, "Child") });
                            if (T == String) {
                                if (@field(value, f.name).len > 0) {
                                    _ = try writer.write(f.name);
                                    _ = try writer.write(": ");
                                    try writer.print("{}", .{@field(value, f.name)});
                                }
                            } else if (@hasDecl(f.type, "Child")) {
                                const val = @field(value, f.name);
                                // try writer.print("{*}/{}", .{ val.items, val.len });
                                if (val.len > 0) {
                                    _ = try writer.write(f.name);
                                    _ = try writer.write(": ");
                                    try writer.print("{}", .{val});
                                }
                            } else {
                                _ = try writer.write(f.name);
                                _ = try writer.write(": ");
                                try writer.print("{}", .{@field(value, f.name)});
                            }
                        },
                        .Pointer => |ptr| switch (ptr.size) {
                            .One => try writer.print("{}", .{@field(value, f.name).*}),
                            else => |size| if (std.meta.trait.isZigString(f.type))
                                try writer.print("\"{s}\"", .{@field(value, f.name)})
                            else if (size == .Many and
                                info.Pointer.sentinel != null and
                                info.Pointer.child == u8)
                            {
                                const p = @field(value, f.name);
                                if (@ptrToInt(p) != 0 and p != types.empty_str) {
                                    _ = try writer.write(f.name);
                                    _ = try writer.write(": ");
                                    // try writer.print("{*}-\"{s}\"", .{ p, p });
                                }
                                // else
                                //     _ = try writer.write("null");
                            } else {
                                @compileError(std.fmt.comptimePrint(
                                    "{} {s}",
                                    .{ size, @typeName(f.type) },
                                ));
                            },
                        },
                        .Enum => {
                            _ = try writer.write(f.name);
                            _ = try writer.write(": ");
                            try writer.print(".{s}", .{@tagName(@field(value, f.name))});
                        },
                        else => {
                            // if (true) @compileError(@typeName(f.type));
                            _ = try writer.write(f.name);
                            _ = try writer.write(": ");
                            try writer.print("{}", .{@field(value, f.name)});
                        },
                    }
                }
            }
        }
    }.format;
}

fn optionalFieldIds(comptime field_descriptors: []const FieldDescriptor) []const c_uint {
    // var result: []const c_uint = &.{};
    var result: [field_descriptors.len]c_uint = undefined;
    var count: u32 = 0;
    for (field_descriptors) |fd| {
        // if (fd.label == .LABEL_OPTIONAL) result = result ++ [1]c_uint{fd.id};
        if (fd.label == .LABEL_OPTIONAL) {
            result[count] = fd.id;
            count += 1;
        }
    }
    return result[0..count];
}

pub const BinaryData = extern struct {
    len: usize = 0,
    data: String = String.initEmpty(),
};

// pub const Buffer = extern struct {
//     append: ?*const fn ([*c]Buffer, usize, [*c]const u8) callconv(.C) void,
// };

// pub const BufferSimple = extern struct {
//     base: Buffer,
//     alloced: usize = 0,
//     len: usize = 0,
//     data: String = String.initEmpty(),
//     must_free_data: bool = false,
//     allocator: [*c]Allocator,
// };
pub const EnumValue = extern struct {
    name: String = String.initEmpty(),
    c_name: String = String.initEmpty(),
    value: c_int,
    pub fn init(
        name: [:0]const u8,
        c_name: [:0]const u8,
        value: c_int,
    ) EnumValue {
        return .{
            .name = String.init(name),
            .c_name = String.init(c_name),
            .value = value,
        };
    }
};

pub const EnumValueIndex = extern struct {
    name: String = String.initEmpty(),
    index: c_uint,
    pub fn init(
        name: [:0]const u8,
        index: c_uint,
    ) EnumValueIndex {
        return .{
            .name = String.init(name),
            .index = index,
        };
    }
};

pub const IntRange = extern struct {
    start_value: u32 = 0,
    orig_index: u32 = 0,

    //
    // NOTE: the number of values in the range can be inferred by looking
    // at the next element's orig_index. A dummy element is added to make
    // this simple.
    //

    pub fn init(
        start_value: u32,
        orig_index: u32,
    ) IntRange {
        return .{
            .start_value = start_value,
            .orig_index = orig_index,
        };
    }

    pub fn format(r: IntRange, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("start {} oidx {}", .{ r.start_value, r.orig_index });
    }
};

pub const EnumDescriptor = extern struct {
    magic: u32 = 0,
    name: String = String.initEmpty(),
    short_name: String = String.initEmpty(),
    c_name: String = String.initEmpty(),
    package_name: String = String.initEmpty(),
    values: List(EnumValue),
    values_by_name: List(EnumValueIndex),
    // value_ranges: List(IntRange),
    reserved1: ?*anyopaque = null,
    reserved2: ?*anyopaque = null,
    reserved3: ?*anyopaque = null,
    reserved4: ?*anyopaque = null,

    pub fn init(
        magic: u32,
        comptime name: [:0]const u8,
        package_name: [:0]const u8,
        values: List(EnumValue),
        values_by_name: List(EnumValueIndex),
    ) EnumDescriptor {
        comptime {
            if (findDecl(name, TopLevel)) |T| {
                const tfields = std.meta.fields(T);
                for (values.slice()) |field, i| {
                    const fname = field.name.slice();
                    const tfield = tfields[i];
                    if (field.value != tfield.value)
                        @compileError(std.fmt.comptimePrint("{s} {s} {} != {}", .{ name, fname, field.value, tfield.value }));

                    if (!mem.eql(u8, fname, tfield.name))
                        @compileError(std.fmt.comptimePrint("{s} {s} != {s}", .{ name, fname, tfield.name }));
                    // TODO sort fields and check against values_by_name
                }
            } else @compileError(std.fmt.comptimePrint("not found {s}", .{name}));
        }
        return .{
            .magic = magic,
            .name = String.init(name),
            .package_name = String.init(package_name),
            .values = values,
            .values_by_name = values_by_name,
        };
    }
};

pub const FieldDescriptor = extern struct {
    name: String = String.initEmpty(),
    id: c_uint = 0,
    label: FieldDescriptorProto.Label,
    type: FieldDescriptorProto.Type,
    offset: c_uint,
    descriptor: ?*align(8) const anyopaque = null,
    default_value: ?*const anyopaque = null,
    flags: FieldFlags = 0,
    reserved_flags: c_uint = 0,
    reserved2: ?*anyopaque = null,
    reserved3: ?*anyopaque = null,

    const FieldFlags = types.IntegerBitset(std.meta.tags(FieldFlag).len);
    pub const FieldFlag = enum(u8) {
        FLAG_PACKED,
        FLAG_DEPRECATED,
        FLAG_ONEOF,
    };

    pub fn init(
        name: [:0]const u8,
        id: u32,
        label: FieldDescriptorProto.Label,
        typ: FieldDescriptorProto.Type,
        offset: c_uint,
        descriptor: ?*align(8) const anyopaque,
        default_value: ?*const anyopaque,
    ) FieldDescriptor {
        return .{
            .name = String.init(name),
            .id = id,
            .label = label,
            .type = typ,
            .offset = offset,
            .descriptor = descriptor,
            .default_value = default_value,
        };
    }
};

const TopLevel = @This();
pub fn findDecl(comptime type_name: []const u8, comptime T: type) ?type {
    comptime {
        for (std.meta.declarations(T)) |d| {
            if (mem.eql(u8, type_name, d.name)) {
                const U = @field(T, d.name);
                if (@TypeOf(U) == type)
                    return U;
            }
            if (!d.is_pub) continue;
            const U = @field(T, d.name);
            if (@TypeOf(U) != type) continue;
            const uinfo = @typeInfo(U);
            if (uinfo != .Struct) continue;
            if (findDecl(type_name, U)) |n| {
                return n;
            }
        }
        return null;
    }
}

pub const MessageDescriptor = extern struct {
    magic: u32 = 0,
    name: String = String.initEmpty(),
    package_name: String = String.initEmpty(),
    sizeof_message: usize = 0,
    fields: List(FieldDescriptor),
    fields_sorted_by_name: List(c_uint),
    field_ids: List(c_uint),
    opt_field_ids: List(c_uint),
    message_init: MessageInit = null,
    reserved1: ?*anyopaque = null,
    reserved2: ?*anyopaque = null,
    reserved3: ?*anyopaque = null,

    pub fn init(
        magic: u32,
        comptime name: [:0]const u8,
        package_name: [:0]const u8,
        sizeof_message: usize,
        comptime fields: List(FieldDescriptor),
        fields_sorted_by_name: List(c_uint),
        field_ids: List(c_uint),
        message_init: MessageInit,
        opt_field_ids: []const c_uint,
    ) MessageDescriptor {
        assert(field_ids.len == fields.len);
        assert(opt_field_ids.len <= 64);
        comptime {
            const expected_opt_fields = optionalFieldIds(fields.slice());
            if (!(expected_opt_fields.len == opt_field_ids.len and mem.eql(u32, opt_field_ids, expected_opt_fields)))
                @compileError(std.fmt.comptimePrint(
                    "expected len {} got {} {any}",
                    .{ expected_opt_fields.len, opt_field_ids.len, expected_opt_fields },
                ));

            for (field_ids.slice()) |field_num, i| {
                const field = fields.items[i];
                // if (field.id != field_num and field.id != std.math.maxInt(u32) - field_num) @compileLog(field.id, field_num);
                assert(field.id == field_num or field.id == std.math.maxInt(u32) - field_num);
            }
        }
        comptime {
            @setEvalBranchQuota(4000);
            if (findDecl(name, TopLevel)) |T| {
                assert(sizeof_message == @sizeOf(T));
                const len = @typeInfo(T).Struct.fields.len;
                const ok = len == fields.len + 1;
                if (!ok) @compileLog(name, fields.len, len);
                assert(ok);
                const tfields = std.meta.fields(T);
                for (tfields[1..tfields.len]) |f, i| {
                    if (!mem.eql(u8, f.name, fields.items[i].name.slice()))
                        @compileError(std.fmt.comptimePrint("{s} {s} != {s}", .{ name, f.name, fields.items[i].name }));
                    const expected_offset = @offsetOf(T, f.name);
                    if (expected_offset != fields.items[i].offset)
                        @compileError(std.fmt.comptimePrint("{s} offset {} != {}", .{ name, expected_offset, fields.items[i].offset }));
                    const expected_size = @sizeOf(T);
                    if (expected_size != sizeof_message)
                        @compileError(std.fmt.comptimePrint("{s} size {} != {}", .{ name, expected_size, sizeof_message }));
                }
            } else @compileError("couldn't find " ++ name);
        }

        return .{
            .magic = magic,
            .name = String.init(name),
            .package_name = String.init(package_name),
            .sizeof_message = sizeof_message,
            .fields = fields,
            .fields_sorted_by_name = fields_sorted_by_name,
            .field_ids = field_ids,
            .opt_field_ids = List(c_uint).init(opt_field_ids),
            .message_init = message_init,
        };
    }

    /// returns the index of `field_id` within `desc.opt_field_ids`
    pub fn optionalFieldIndex(desc: *const MessageDescriptor, field_id: c_uint) ?usize {
        return if (mem.indexOfScalar(c_uint, desc.opt_field_ids.slice(), field_id)) |idx|
            idx
        else
            null;
    }
    /// returns the index of `field_id` within `desc.field_ids`
    pub fn fieldIndex(desc: *const MessageDescriptor, field_id: c_uint) ?usize {
        return if (mem.indexOfScalar(c_uint, desc.field_ids.slice(), field_id)) |idx|
            idx
        else
            null;
    }
};

pub const MessageUnknownField = extern struct {
    tag: u32 = 0,
    wire_type: WireType = undefined,
    len: usize = 0,
    data: String = String.initEmpty(),
};

pub const Message = extern struct {
    descriptor: ?*const MessageDescriptor,
    unknown_fields: ListMut(MessageUnknownField) = ListMut(MessageUnknownField).initEmpty(),
    fields_present: u64 = 0,

    comptime {
        assert(@sizeOf(Message) == 40);
    }
    pub fn isInit(m: Message) bool {
        return m.descriptor != null;
    }
    pub fn init(descriptor: *const MessageDescriptor) Message {
        return .{
            .descriptor = descriptor,
        };
    }
    /// returns null when field_id is not an optional field
    /// returns true/false when field_id is an optional field
    pub fn isPresent(m: *const Message, field_id: c_uint) ?bool {
        const desc = m.descriptor orelse unreachable;
        const opt_field_idx = desc.optionalFieldIndex(field_id) orelse
            return null;
        return (m.fields_present >> @intCast(u6, opt_field_idx)) & 1 != 0;
    }
    /// returns error.OptionalFieldNotFound if field_id is a non optional field
    pub fn setPresent(m: *Message, field_id: c_uint) !void {
        const desc = m.descriptor orelse unreachable;
        const opt_field_idx = desc.optionalFieldIndex(field_id) orelse
            return error.OptionalFieldNotFound;
        std.log.debug("setPresent 1 m.fields_present {b:0>64}", .{m.fields_present});
        m.fields_present |= @as(u64, 1) << @intCast(u6, opt_field_idx);
        std.log.debug("setPresent 2 m.fields_present {b:0>64}", .{m.fields_present});
    }

    /// ptr cast to T. verifies that m.descriptor.name ends with @typeName(T)
    pub fn as(m: *Message, comptime T: type) !*T {
        if (!mem.endsWith(u8, @typeName(T), m.descriptor.?.name.slice())) {
            std.log.err("expected '{s}' to contain '{s}'", .{ @typeName(T), m.descriptor.?.name.slice() });
            return error.TypeMismatch;
        }
        return @ptrCast(*T, m);
    }
};

// pub const MethodDescriptor = extern struct {
//     name: String,
//     input: [*c]const MessageDescriptor,
//     output: [*c]const MessageDescriptor,
// };
// pub const MethodDescriptor = MethodDescriptor;
// pub const ServiceDescriptor = extern struct {
//     magic: u32 = 0,
//     name: String,
//     short_name: String,
//     c_name: String,
//     package: String,
//     methods: [*c]const MethodDescriptor,
//     method_indices_by_name: [*c]const c_uint,
// };
// pub const ServiceDescriptor = ServiceDescriptor;
// pub const Service = Service;
// pub const Closure = ?*const fn ([*c]const Message, ?*anyopaque) callconv(.C) void;
// pub const Service = extern struct {
//     descriptor: [*c]const ServiceDescriptor,
//     invoke: ?*const fn ([*c]Service, c_uint, [*c]const Message, Closure, ?*anyopaque) callconv(.C) void,
//     destroy: ?*const fn ([*c]Service) callconv(.C) void,
// };

pub const UninterpretedOption = extern struct {
    base: Message,
    name: ListMut(NamePart) = ListMut(NamePart).initEmpty(),
    identifier_value: String = String.initEmpty(),
    positive_int_value: u64 = 0,
    negative_int_value: i64 = 0,
    double_value: f64 = 0,
    string_value: BinaryData = .{},
    aggregate_value: String = String.initEmpty(),

    pub const init = Init(UninterpretedOption);
    pub const format = Format(UninterpretedOption);

    pub const NamePart = extern struct {
        base: Message,
        name_part: String = String.initEmpty(),
        is_extension: bool = false,

        pub const init = Init(NamePart);
        pub const format = Format(NamePart);

        pub const field_descriptors = [2]FieldDescriptor{
            FieldDescriptor.init(
                "name_part",
                1,
                .LABEL_REQUIRED,
                .TYPE_STRING,
                @offsetOf(NamePart, "name_part"),
                null,
                null,
            ),
            FieldDescriptor.init(
                "is_extension",
                2,
                .LABEL_REQUIRED,
                .TYPE_BOOL,
                @offsetOf(NamePart, "is_extension"),
                null,
                null,
            ),
        };
        pub const field_indices_by_name = [_:0]c_uint{
            1, // field[1] = is_extension
            0, // field[0] = name_part
        };
        // pub const IntRange number_ranges[1 + 1] =
        // {
        //   { 1, 0 },
        //   { 0, 2 }
        // };
        pub const __field_ids = [_]c_uint{ 1, 2 };
        pub const __opt_field_ids = [_]c_uint{};
        pub const descriptor = MessageDescriptor.init(
            MESSAGE_DESCRIPTOR_MAGIC,
            "NamePart",
            "google.protobuf",
            @sizeOf(NamePart),
            List(FieldDescriptor).init(&NamePart.field_descriptors),
            List(c_uint).init(&NamePart.field_indices_by_name),
            List(c_uint).init(&NamePart.__field_ids),
            InitBytes(NamePart),
            &NamePart.__opt_field_ids,
        );
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
        ),
        FieldDescriptor.init(
            "identifier_value",
            3,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(UninterpretedOption, "identifier_value"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "positive_int_value",
            4,
            .LABEL_OPTIONAL,
            .TYPE_UINT64,
            @offsetOf(UninterpretedOption, "positive_int_value"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "negative_int_value",
            5,
            .LABEL_OPTIONAL,
            .TYPE_INT64,
            @offsetOf(UninterpretedOption, "negative_int_value"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "double_value",
            6,
            .LABEL_OPTIONAL,
            .TYPE_DOUBLE,
            @offsetOf(UninterpretedOption, "double_value"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "string_value",
            7,
            .LABEL_OPTIONAL,
            .TYPE_BYTES,
            @offsetOf(UninterpretedOption, "string_value"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "aggregate_value",
            8,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(UninterpretedOption, "aggregate_value"),
            null,
            null,
        ),
    };
    pub const field_indices_by_name = [_:0]c_uint{
        6, // field[6] = aggregate_value
        4, // field[4] = double_value
        1, // field[1] = identifier_value
        0, // field[0] = name
        3, // field[3] = negative_int_value
        2, // field[2] = positive_int_value
        5, // field[5] = string_value
    };
    // pub const IntRange number_ranges[1 + 1] =
    // {
    // FieldDescriptor.init( 2, 0 },
    //   { 0, 7 }
    // };
    pub const __field_ids = [_]c_uint{ 2, 3, 4, 5, 6, 7, 8 };
    pub const __opt_field_ids = [_]c_uint{ 3, 4, 5, 6, 7, 8 };
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "UninterpretedOption",
        "google.protobuf",
        @sizeOf(UninterpretedOption),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(UninterpretedOption),
        &__opt_field_ids,
    );
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
    uninterpreted_option: ListMut(UninterpretedOption) = ListMut(UninterpretedOption).initEmpty(),

    pub const init = Init(FieldOptions);
    pub const format = Format(FieldOptions);

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
        pub const enum_values_by_number = [_]EnumValue{
            EnumValue.init("STRING", "FieldOptions.CType.STRING", 0),
            EnumValue.init("CORD", "FieldOptions.CType.CORD", 1),
            EnumValue.init("STRING_PIECE", "FieldOptions.CType.STRING_PIECE", 2),
        };
        // pub const google__protobuf__field_options__ctype__value_ranges = [_]IntRange{
        // {0, 0},{0, 3}
        // };
        pub const enum_values_by_name = [_]EnumValueIndex{
            EnumValueIndex.init("CORD", 1),
            EnumValueIndex.init("STRING", 0),
            EnumValueIndex.init("STRING_PIECE", 2),
        };

        pub const descriptor = EnumDescriptor.init(
            ENUM_DESCRIPTOR_MAGIC,
            "CType",
            "google.protobuf.FieldOptions",
            List(EnumValue).init(&enum_values_by_number),
            List(EnumValueIndex).init(&enum_values_by_name),
            // value_ranges,
        );
    };

    const JSType = enum(u8) {
        // Use the default type.
        JS_NORMAL = 0,

        // Use JavaScript strings.
        JS_STRING = 1,

        // Use JavaScript numbers.
        JS_NUMBER = 2,

        pub const default_value: JSType = .JS_NORMAL;
        pub const enum_values_by_number = [_]EnumValue{
            EnumValue.init("JS_NORMAL", "FieldOptions.JSType.JS_NORMAL", 0),
            EnumValue.init("JS_STRING", "FieldOptions.JSType.JS_STRING", 1),
            EnumValue.init("JS_NUMBER", "FieldOptions.JSType.JS_NUMBER", 2),
        };
        // pub const IntRange value_ranges[] = {
        // {0, 0},{0, 3}
        // };
        pub const enum_values_by_name = [_]EnumValueIndex{
            EnumValueIndex.init("JS_NORMAL", 0),
            EnumValueIndex.init("JS_NUMBER", 2),
            EnumValueIndex.init("JS_STRING", 1),
        };
        const descriptor = EnumDescriptor.init(
            ENUM_DESCRIPTOR_MAGIC,
            "JSType",
            "google.protobuf.FieldOptions",
            List(EnumValue).init(&enum_values_by_number),
            List(EnumValueIndex).init(&enum_values_by_name),
            // value_ranges,

        );
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
        ),
        FieldDescriptor.init(
            "packed",
            2,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "packed"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "jstype",
            6,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(FieldOptions, "jstype"),
            &JSType.descriptor,
            &JSType.default_value,
        ),
        FieldDescriptor.init(
            "lazy",
            5,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "lazy"),
            null,
            &lazy__default_value,
        ),
        FieldDescriptor.init(
            "unverified_lazy",
            15,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "unverified_lazy"),
            null,
            &unverified_lazy__default_value,
        ),
        FieldDescriptor.init(
            "deprecated",
            3,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "deprecated"),
            null,
            &deprecated__default_value,
        ),
        FieldDescriptor.init(
            "weak",
            10,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldOptions, "weak"),
            null,
            &weak__default_value,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FieldOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_:0]c_uint{
        0, // field[0] = ctype
        2, // field[2] = deprecated
        4, // field[4] = jstype
        3, // field[3] = lazy
        1, // field[1] = packed
        7, // field[7] = uninterpreted_option
        6, // field[6] = unverified_lazy
        5, // field[5] = weak
    };
    pub const number_ranges = [5 + 1]IntRange{
        IntRange.init(1, 0),
        IntRange.init(5, 3),
        IntRange.init(10, 5),
        IntRange.init(15, 6),
        IntRange.init(999, 7),
        IntRange.init(0, 8),
    };
    pub const __field_ids = [_]c_uint{ 1, 2, 6, 5, 15, 3, 10, 999 };
    pub const __opt_field_ids = [_]c_uint{ 1, 2, 6, 5, 15, 3, 10 };
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "FieldOptions",
        "google.protobuf",
        @sizeOf(FieldOptions),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(FieldOptions),
        &__opt_field_ids,
    );
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

        pub const enum_values_by_number = [_]EnumValue{
            EnumValue.init("TYPE_ERROR", "FieldDescriptorProto.Type.TYPE_ERROR", 0),
            EnumValue.init("TYPE_DOUBLE", "FieldDescriptorProto.Type.TYPE_DOUBLE", 1),
            EnumValue.init("TYPE_FLOAT", "FieldDescriptorProto.Type.TYPE_FLOAT", 2),
            EnumValue.init("TYPE_INT64", "FieldDescriptorProto.Type.TYPE_INT64", 3),
            EnumValue.init("TYPE_UINT64", "FieldDescriptorProto.Type.TYPE_UINT64", 4),
            EnumValue.init("TYPE_INT32", "FieldDescriptorProto.Type.TYPE_INT32", 5),
            EnumValue.init("TYPE_FIXED64", "FieldDescriptorProto.Type.TYPE_FIXED64", 6),
            EnumValue.init("TYPE_FIXED32", "FieldDescriptorProto.Type.TYPE_FIXED32", 7),
            EnumValue.init("TYPE_BOOL", "FieldDescriptorProto.Type.TYPE_BOOL", 8),
            EnumValue.init("TYPE_STRING", "FieldDescriptorProto.Type.TYPE_STRING", 9),
            EnumValue.init("TYPE_GROUP", "FieldDescriptorProto.Type.TYPE_GROUP", 10),
            EnumValue.init("TYPE_MESSAGE", "FieldDescriptorProto.Type.TYPE_MESSAGE", 11),
            EnumValue.init("TYPE_BYTES", "FieldDescriptorProto.Type.TYPE_BYTES", 12),
            EnumValue.init("TYPE_UINT32", "FieldDescriptorProto.Type.TYPE_UINT32", 13),
            EnumValue.init("TYPE_ENUM", "FieldDescriptorProto.Type.TYPE_ENUM", 14),
            EnumValue.init("TYPE_SFIXED32", "FieldDescriptorProto.Type.TYPE_SFIXED32", 15),
            EnumValue.init("TYPE_SFIXED64", "FieldDescriptorProto.Type.TYPE_SFIXED64", 16),
            EnumValue.init("TYPE_SINT32", "FieldDescriptorProto.Type.TYPE_SINT32", 17),
            EnumValue.init("TYPE_SINT64", "FieldDescriptorProto.Type.TYPE_SINT64", 18),
        };
        // pub const value_ranges = [_]IntRange {
        // {1, 0},{0, 18}
        // };
        pub const enum_values_by_name = [_]EnumValueIndex{
            EnumValueIndex.init("TYPE_BOOL", 7),
            EnumValueIndex.init("TYPE_BYTES", 11),
            EnumValueIndex.init("TYPE_DOUBLE", 0),
            EnumValueIndex.init("TYPE_ENUM", 13),
            EnumValueIndex.init("TYPE_FIXED32", 6),
            EnumValueIndex.init("TYPE_FIXED64", 5),
            EnumValueIndex.init("TYPE_FLOAT", 1),
            EnumValueIndex.init("TYPE_GROUP", 9),
            EnumValueIndex.init("TYPE_INT32", 4),
            EnumValueIndex.init("TYPE_INT64", 2),
            EnumValueIndex.init("TYPE_MESSAGE", 10),
            EnumValueIndex.init("TYPE_SFIXED32", 14),
            EnumValueIndex.init("TYPE_SFIXED64", 15),
            EnumValueIndex.init("TYPE_SINT32", 16),
            EnumValueIndex.init("TYPE_SINT64", 17),
            EnumValueIndex.init("TYPE_STRING", 8),
            EnumValueIndex.init("TYPE_UINT32", 12),
            EnumValueIndex.init("TYPE_UINT64", 3),
        };
        pub const descriptor = EnumDescriptor.init(
            ENUM_DESCRIPTOR_MAGIC,
            "Type",
            "google.protobuf.FieldDescriptorProto",
            List(EnumValue).init(&enum_values_by_number),
            List(EnumValueIndex).init(&enum_values_by_name),
            // value_ranges,
        );
    };

    pub const Label = enum(u8) {
        LABEL_ERROR = 0,
        LABEL_OPTIONAL = 1,
        LABEL_REQUIRED = 2,
        LABEL_REPEATED = 3,

        pub const enum_values_by_number = [_]EnumValue{
            EnumValue.init("LABEL_ERROR", "FieldDescriptorProto.Label.LABEL_ERROR", 0),
            EnumValue.init("LABEL_OPTIONAL", "FieldDescriptorProto.Label.LABEL_OPTIONAL", 1),
            EnumValue.init("LABEL_REQUIRED", "FieldDescriptorProto.Label.LABEL_REQUIRED", 2),
            EnumValue.init("LABEL_REPEATED", "FieldDescriptorProto.Label.LABEL_REPEATED", 3),
        };
        // pub const value_ranges[] = {
        // {1, 0},{0, 3}
        // };
        pub const enum_values_by_name = .{
            EnumValueIndex.init("LABEL_OPTIONAL", 0),
            EnumValueIndex.init("LABEL_REPEATED", 2),
            EnumValueIndex.init("LABEL_REQUIRED", 1),
        };
        pub const descriptor = EnumDescriptor.init(
            ENUM_DESCRIPTOR_MAGIC,
            "Label",
            "google.protobufFieldDescriptorProto",
            List(EnumValue).init(&enum_values_by_number),
            List(EnumValueIndex).init(&enum_values_by_name),
            // value_ranges,
        );
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
        ),
        FieldDescriptor.init(
            "number",
            3,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(FieldDescriptorProto, "number"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "label",
            4,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(FieldDescriptorProto, "label"),
            &Label.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "type",
            5,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(FieldDescriptorProto, "type"),
            &FieldDescriptorProto.Type.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "type_name",
            6,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FieldDescriptorProto, "type_name"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "extendee",
            2,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FieldDescriptorProto, "extendee"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "default_value",
            7,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FieldDescriptorProto, "default_value"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "oneof_index",
            9,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(FieldDescriptorProto, "oneof_index"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "json_name",
            10,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FieldDescriptorProto, "json_name"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "options",
            8,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(FieldDescriptorProto, "options"),
            &FieldOptions.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "proto3_optional",
            17,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FieldDescriptorProto, "proto3_optional"),
            null,
            null,
        ),
    };
    pub const field_indices_by_name = [_:0]c_uint{
        6, // field[6] = default_value
        1, // field[1] = extendee
        9, // field[9] = json_name
        3, // field[3] = label
        0, // field[0] = name
        2, // field[2] = number
        8, // field[8] = oneof_index
        7, // field[7] = options
        10, //* field[10] = proto3_optional
        4, // field[4] = type
        5, // field[5] = type_name
    };
    // pub const  number_ranges[2 + 1] =
    // {
    //   { 1, 0 },
    //   { 17, 10 },
    //   { 0, 11 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 3, 4, 5, 6, 2, 7, 9, 10, 8, 17 };
    pub const __opt_field_ids = [_]c_uint{ 1, 3, 4, 5, 6, 2, 7, 9, 10, 8, 17 };
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "FieldDescriptorProto",
        "google.protobuf",
        @sizeOf(FieldDescriptorProto),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(FileDescriptorProto),
        &__opt_field_ids,
    );
};

pub const EnumValueOptions = extern struct {
    base: Message,
    deprecated: bool = false,
    uninterpreted_option: ListMut(UninterpretedOption) = ListMut(UninterpretedOption).initEmpty(),

    pub const init = Init(EnumValueOptions);
    pub const format = Format(EnumValueOptions);
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
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(EnumValueOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_:0]c_uint{
        0, // field[0] = deprecated
        1, // field[1] = uninterpreted_option
    };
    // pub const IntRange number_ranges[2 + 1] =
    // {
    //   { 1, 0 },
    //   { 999, 1 },
    //   { 0, 2 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 999 };
    pub const __opt_field_ids = [_]c_uint{1};
    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "EnumValueOptions",
        "google.protobuf",
        @sizeOf(EnumValueOptions),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(EnumValueOptions),
        &__opt_field_ids,
    );
};

pub const EnumValueDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    number: i32 = 0,
    options: EnumValueOptions = EnumValueOptions.init(),

    pub const init = Init(EnumValueDescriptorProto);
    pub const format = Format(EnumValueDescriptorProto);

    pub const field_descriptors = [3]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(EnumValueDescriptorProto, "name"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "number",
            2,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(EnumValueDescriptorProto, "number"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "options",
            3,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(EnumValueDescriptorProto, "options"),
            &EnumValueOptions.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_:0]c_uint{
        0, // field[0] = name
        1, // field[1] = number
        2, // field[2] = options
    };
    // pub const IntRange number_ranges[1 + 1] =
    // {
    //   { 1, 0 },
    //   { 0, 3 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 2, 3 };
    pub const __opt_field_ids = [_]c_uint{ 1, 2, 3 };
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "EnumValueDescriptorProto",
        "google.protobuf",
        @sizeOf(EnumValueDescriptorProto),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(EnumValueDescriptorProto),
        &__opt_field_ids,
    );
};

pub const EnumOptions = extern struct {
    base: Message,
    allow_alias: bool = false,
    deprecated: bool = false,
    uninterpreted_option: ListMut(UninterpretedOption) = ListMut(UninterpretedOption).initEmpty(),

    pub const init = Init(EnumOptions);
    pub const format = Format(EnumOptions);
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
        ),
        FieldDescriptor.init(
            "deprecated",
            3,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(EnumOptions, "deprecated"),
            null,
            &deprecated__default_value,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(EnumOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_:0]c_uint{
        0, // field[0] = allow_alias
        1, // field[1] = deprecated
        2, // field[2] = uninterpreted_option
    };
    // pub const IntRange number_ranges[2 + 1] =
    // {
    //   { 2, 0 },
    //   { 999, 2 },
    //   { 0, 3 }
    // };
    pub const __field_ids = [_]c_uint{ 2, 3, 999 };
    pub const __opt_field_ids = [_]c_uint{ 2, 3 };
    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "EnumOptions",
        "google.protobuf",
        @sizeOf(EnumOptions),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(EnumOptions),
        &__opt_field_ids,
    );
};

pub const EnumDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    value: ListMut(EnumValueDescriptorProto) = ListMut(EnumValueDescriptorProto).initEmpty(),
    options: EnumOptions = EnumOptions.init(),
    reserved_range: ListMut(EnumReservedRange) = ListMut(EnumReservedRange).initEmpty(),
    reserved_name: ListMut1(String) = ListMut1(String).initEmpty(),

    pub const init = Init(EnumDescriptorProto);
    pub const format = Format(EnumDescriptorProto);

    pub const EnumReservedRange = extern struct {
        base: Message,
        start: i32 = 0,
        end: i32 = 0,

        pub const init = Init(EnumReservedRange);
        pub const format = Format(EnumReservedRange);
        pub const field_descriptors = [2]FieldDescriptor{
            FieldDescriptor.init(
                "start",
                1,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(EnumReservedRange, "start"),
                null,
                null,
            ),
            FieldDescriptor.init(
                "end",
                2,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(EnumReservedRange, "end"),
                null,
                null,
            ),
        };
        pub const field_indices_by_name = [_:0]c_uint{
            1, // field[1] = end
            0, // field[0] = start
        };
        // pub const IntRange number_ranges[1 + 1] =
        // {
        //   { 1, 0 },
        //   { 0, 2 }
        // };
        pub const __field_ids = [_]c_uint{ 1, 2 };
        pub const __opt_field_ids = [_]c_uint{ 1, 2 };
        const descriptor = MessageDescriptor.init(
            MESSAGE_DESCRIPTOR_MAGIC,
            "EnumReservedRange",
            "google.protobuf.EnumDescriptorProto",
            @sizeOf(EnumReservedRange),
            List(FieldDescriptor).init(&EnumReservedRange.field_descriptors),
            List(c_uint).init(&EnumReservedRange.field_indices_by_name),
            List(c_uint).init(&EnumReservedRange.__field_ids),
            InitBytes(EnumReservedRange),
            &EnumReservedRange.__opt_field_ids,
        );
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
        ),
        FieldDescriptor.init(
            "value",
            2,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(EnumDescriptorProto, "value"),
            &EnumValueDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "options",
            3,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(EnumDescriptorProto, "options"),
            &EnumOptions.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "reserved_range",
            4,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(EnumDescriptorProto, "reserved_range"),
            &EnumReservedRange.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "reserved_name",
            5,
            .LABEL_REPEATED,
            .TYPE_STRING,
            @offsetOf(EnumDescriptorProto, "reserved_name"),
            null,
            null,
        ),
    };
    pub const field_indices_by_name = [_:0]c_uint{
        0, // field[0] = name
        2, // field[2] = options
        4, // field[4] = reserved_name
        3, // field[3] = reserved_range
        1, // field[1] = value
    };
    // pub  const  number_ranges = [1 + 1]IntRange
    // {
    //   IntRange.init{ 1, 0 },
    //   IntRange.init{ 0, 5 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 2, 3, 4, 5 };
    pub const __opt_field_ids = [_]c_uint{ 1, 3 };
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "EnumDescriptorProto",
        "google.protobuf",
        @sizeOf(EnumDescriptorProto),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(EnumDescriptorProto),
        &__opt_field_ids,
    );
};
pub const ExtensionRangeOptions = extern struct {
    base: Message,
    uninterpreted_option: ListMut(UninterpretedOption) = ListMut(UninterpretedOption).initEmpty(),

    pub const init = Init(ExtensionRangeOptions);
    pub const format = Format(ExtensionRangeOptions);
    pub const field_descriptors = [1]FieldDescriptor{
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(ExtensionRangeOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = .{
        0, // field[0] = uninterpreted_option
    };
    // pub const IntRange number_ranges[1 + 1] =
    // {
    //   { 999, 0 },
    //   { 0, 1 }
    // };
    pub const __field_ids = [_]c_uint{999};
    pub const __opt_field_ids = [_]c_uint{};
    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "ExtensionRangeOptions",
        "google.protobuf",
        @sizeOf(ExtensionRangeOptions),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(ExtensionRangeOptions),
        &__opt_field_ids,
    );
};
pub const OneofOptions = extern struct {
    base: Message,
    uninterpreted_option: ListMut(UninterpretedOption) = ListMut(UninterpretedOption).initEmpty(),

    pub const init = Init(OneofOptions);
    pub const format = Format(OneofOptions);

    pub const field_descriptors = [1]FieldDescriptor{
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(OneofOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        0, // field[0] = uninterpreted_option
    };
    // pub const IntRange number_ranges[1 + 1] =
    // {
    //   { 999, 0 },
    //   { 0, 1 }
    // };
    pub const __field_ids = [_]c_uint{999};
    pub const __opt_field_ids = [_]c_uint{};
    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "OneofOptions",
        "google.protobuf",
        @sizeOf(OneofOptions),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(OneofOptions),
        &__opt_field_ids,
    );
};
pub const OneofDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    options: OneofOptions = OneofOptions.init(),

    pub const init = Init(OneofDescriptorProto);
    pub const format = Format(OneofDescriptorProto);
    pub const field_descriptors = [2]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(OneofDescriptorProto, "name"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "options",
            2,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(OneofDescriptorProto, "options"),
            &OneofOptions.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        0, // field[0] = name
        1, // field[1] = options
    };
    // pub const IntRange number_ranges[1 + 1] =
    // {
    //   { 1, 0 },
    //   { 0, 2 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 2 };
    pub const __opt_field_ids = [_]c_uint{ 1, 2 };
    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "OneofDescriptorProto",
        "google.protobuf",
        @sizeOf(OneofDescriptorProto),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(OneofDescriptorProto),
        &__opt_field_ids,
    );
};
pub const MessageOptions = extern struct {
    base: Message,
    message_set_wire_format: bool = false,
    no_standard_descriptor_accessor: bool = false,
    deprecated: bool = false,
    map_entry: bool = false,
    uninterpreted_option: ListMut(UninterpretedOption) = ListMut(UninterpretedOption).initEmpty(),

    pub const init = Init(MessageOptions);
    pub const format = Format(MessageOptions);
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
        ),
        FieldDescriptor.init(
            "no_standard_descriptor_accessor",
            2,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MessageOptions, "no_standard_descriptor_accessor"),
            null,
            &no_standard_descriptor_accessor__default_value,
        ),
        FieldDescriptor.init(
            "deprecated",
            3,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MessageOptions, "deprecated"),
            null,
            &deprecated__default_value,
        ),
        FieldDescriptor.init(
            "map_entry",
            7,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MessageOptions, "map_entry"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(MessageOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        2, // field[2] = deprecated
        3, // field[3] = map_entry
        0, // field[0] = message_set_wire_format
        1, // field[1] = no_standard_descriptor_accessor
        4, // field[4] = uninterpreted_option
    };
    // pub const IntRange number_ranges[3 + 1] =
    // {
    //   { 1, 0 },
    //   { 7, 3 },
    //   { 999, 4 },
    //   { 0, 5 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 2, 3, 7, 999 };
    pub const __opt_field_ids = [_]c_uint{ 1, 2, 3, 7 };
    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "MessageOptions",
        "google.protobuf",
        @sizeOf(MessageOptions),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(MessageOptions),
        &__opt_field_ids,
    );
};

pub const DescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    field: ListMut(FieldDescriptorProto) = ListMut(FieldDescriptorProto).initEmpty(),
    extension: ListMut(FieldDescriptorProto) = ListMut(FieldDescriptorProto).initEmpty(),
    // nested_type: ListMut(DescriptorProto) = .{ .dynamic_segments = undefined }, // workaround for 'dependency loop'
    nested_type: ListMut(DescriptorProto) = .{ .items = undefined }, // workaround for 'dependency loop'
    enum_type: ListMut(EnumDescriptorProto) = ListMut(EnumDescriptorProto).initEmpty(),
    extension_range: ListMut(ExtensionRange) = ListMut(ExtensionRange).initEmpty(),
    oneof_decl: ListMut(OneofDescriptorProto) = ListMut(OneofDescriptorProto).initEmpty(),
    options: MessageOptions = MessageOptions.init(),
    reserved_range: ListMut(ReservedRange) = ListMut(ReservedRange).initEmpty(),
    reserved_name: ListMut1(String) = ListMut1(String).initEmpty(),

    pub const init = Init(DescriptorProto);
    pub const format = Format(DescriptorProto);
    pub const ExtensionRange = extern struct {
        base: Message,
        start: i32 = 0,
        end: i32 = 0,
        options: ExtensionRangeOptions = ExtensionRangeOptions.init(),

        pub const init = Init(ExtensionRange);
        pub const format = Format(ExtensionRange);
        pub const field_descriptors = [3]FieldDescriptor{
            FieldDescriptor.init(
                "start",
                1,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(ExtensionRange, "start"),
                null,
                null,
            ),
            FieldDescriptor.init(
                "end",
                2,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(ExtensionRange, "end"),
                null,
                null,
            ),
            FieldDescriptor.init(
                "options",
                3,
                .LABEL_OPTIONAL,
                .TYPE_MESSAGE,
                @offsetOf(ExtensionRange, "options"),
                &ExtensionRangeOptions.descriptor,
                null,
            ),
        };
        pub const field_indices_by_name = [_]c_uint{
            1, // field[1] = end
            2, // field[2] = options
            0, // field[0] = start
        };
        // pub const IntRange number_ranges[1 + 1] =
        // {
        //   { 1, 0 },
        //   { 0, 3 }
        // };
        pub const __field_ids = [_]c_uint{ 1, 2, 3 };
        pub const __opt_field_ids = [_]c_uint{ 1, 2, 3 };
        const descriptor = MessageDescriptor.init(
            MESSAGE_DESCRIPTOR_MAGIC,
            "ExtensionRange",
            "google.protobuf",
            @sizeOf(ExtensionRange),
            List(FieldDescriptor).init(&ExtensionRange.field_descriptors),
            List(c_uint).init(&ExtensionRange.field_indices_by_name),
            List(c_uint).init(&ExtensionRange.__field_ids),
            InitBytes(ExtensionRange),
            &ExtensionRange.__opt_field_ids,
        );
    };

    pub const ReservedRange = extern struct {
        base: Message,
        start: i32 = 0,
        end: i32 = 0,

        pub const init = Init(ReservedRange);
        pub const format = Format(ReservedRange);
        pub const field_descriptors = [2]FieldDescriptor{
            FieldDescriptor.init(
                "start",
                1,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(ReservedRange, "start"),
                null,
                null,
            ),
            FieldDescriptor.init(
                "end",
                2,
                .LABEL_OPTIONAL,
                .TYPE_INT32,
                @offsetOf(ReservedRange, "end"),
                null,
                null,
            ),
        };
        pub const field_indices_by_name = [_]c_uint{
            1, // field[1] = end
            0, // field[0] = start
        };
        // pub const IntRange number_ranges[1 + 1] =
        // {
        //   { 1, 0 },
        //   { 0, 2 }
        // };
        pub const __field_ids = [_]c_uint{ 1, 2 };
        pub const __opt_field_ids = [_]c_uint{ 1, 2 };
        const descriptor = MessageDescriptor.init(
            MESSAGE_DESCRIPTOR_MAGIC,
            "ReservedRange",
            "google.protobuf",
            @sizeOf(ReservedRange),
            List(FieldDescriptor).init(&ReservedRange.field_descriptors),
            List(c_uint).init(&ReservedRange.field_indices_by_name),
            List(c_uint).init(&ReservedRange.__field_ids),
            InitBytes(ReservedRange),
            &ReservedRange.__opt_field_ids,
        );
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
        ),
        FieldDescriptor.init(
            "field",
            2,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "field"),
            &FieldDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "extension",
            6,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "extension"),
            &FieldDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "nested_type",
            std.math.maxInt(u32) - 3, // workaround for 'dependency loop'
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "nested_type"),
            null, // workaround for 'dependency loop'
            null,
        ),
        FieldDescriptor.init(
            "enum_type",
            4,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "enum_type"),
            &EnumDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "extension_range",
            5,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "extension_range"),
            &ExtensionRange.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "oneof_decl",
            8,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "oneof_decl"),
            &OneofDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "options",
            7,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "options"),
            &MessageOptions.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "reserved_range",
            9,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(DescriptorProto, "reserved_range"),
            &ReservedRange.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "reserved_name",
            10,
            .LABEL_REPEATED,
            .TYPE_STRING,
            @offsetOf(DescriptorProto, "reserved_name"),
            null,
            null,
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        3, // field[3] = enum_type
        5, // field[5] = extension
        4, // field[4] = extension_range
        1, // field[1] = field
        0, // field[0] = name
        2, // field[2] = nested_type
        7, // field[7] = oneof_decl
        6, // field[6] = options
        9, // field[9] = reserved_name
        8, // field[8] = reserved_range
    };
    // pub const IntRange number_ranges[1 + 1] =
    // {
    //   { 1, 0 },
    //   { 0, 10 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 2, 6, 3, 4, 5, 8, 7, 9, 10 };
    pub const __opt_field_ids = [_]c_uint{ 1, 7 };
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "DescriptorProto",
        "google.protobuf",
        @sizeOf(DescriptorProto),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&DescriptorProto.field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(DescriptorProto),
        &__opt_field_ids,
    );
};

pub const MethodOptions = extern struct {
    base: Message,
    deprecated: bool = false,
    idempotency_level: IdempotencyLevel = undefined,
    uninterpreted_option: ListMut(UninterpretedOption) = ListMut(UninterpretedOption).initEmpty(),

    pub const init = Init(MethodOptions);
    pub const format = Format(MethodOptions);
    pub const IdempotencyLevel = enum(u8) {
        IDEMPOTENCY_UNKNOWN,
        NO_SIDE_EFFECTS,
        IDEMPOTENT,
        pub const enum_values_by_number = [_]EnumValue{
            EnumValue.init("IDEMPOTENCY_UNKNOWN", "MethodOptions.Idempotency.unknown", 0),
            EnumValue.init("NO_SIDE_EFFECTS", "MethodOptions.Idempotency.no_side_effects", 1),
            EnumValue.init("IDEMPOTENT", "MethodOptions.Idempotency.IDEMPOTENT", 2),
        };
        // pub const IntRange value_ranges[] = {
        // {0, 0},{0, 3}
        // };
        pub const enum_values_by_name = [_]EnumValueIndex{
            EnumValueIndex.init("IDEMPOTENCY_UNKNOWN", 0),
            EnumValueIndex.init("IDEMPOTENT", 2),
            EnumValueIndex.init("NO_SIDE_EFFECTS", 1),
        };
        const descriptor = EnumDescriptor.init(
            ENUM_DESCRIPTOR_MAGIC,
            "IdempotencyLevel",
            "google.protobuf.MethodOptions",
            List(EnumValue).init(&enum_values_by_number),
            List(EnumValueIndex).init(&enum_values_by_name),
        );
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
        ),
        FieldDescriptor.init(
            "idempotency_level",
            34,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(MethodOptions, "idempotency_level"),
            &IdempotencyLevel.descriptor,
            &idempotency_level__default_value,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(MethodOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        0, // field[0] = deprecated
        1, // field[1] = idempotency_level
        2, // field[2] = uninterpreted_option
    };
    // pub const IntRange number_ranges[2 + 1] =
    // {
    //   { 33, 0 },
    //   { 999, 2 },
    //   { 0, 3 }
    // };
    pub const __field_ids = [_]c_uint{ 33, 34, 999 };
    pub const __opt_field_ids = [_]c_uint{ 33, 34 };
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "MethodOptions",
        "google.protobuf",
        @sizeOf(MethodOptions),

        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(MethodOptions),
        &__opt_field_ids,
    );
};

pub const MethodDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    input_type: String = String.initEmpty(),
    output_type: String = String.initEmpty(),
    options: MethodOptions = MethodOptions.init(),
    client_streaming: bool = false,
    server_streaming: bool = false,

    pub const init = Init(MethodDescriptorProto);
    pub const format = Format(MethodDescriptorProto);
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
        ),
        FieldDescriptor.init(
            "input_type",
            2,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(MethodDescriptorProto, "input_type"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "output_type",
            3,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(MethodDescriptorProto, "output_type"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "options",
            4,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(MethodDescriptorProto, "options"),
            &MethodOptions.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "client_streaming",
            5,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MethodDescriptorProto, "client_streaming"),
            null,
            &client_streaming__default_value,
        ),
        FieldDescriptor.init(
            "server_streaming",
            6,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(MethodDescriptorProto, "server_streaming"),
            null,
            &server_streaming__default_value,
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        4, // field[4] = client_streaming
        1, // field[1] = input_type
        0, // field[0] = name
        3, // field[3] = options
        2, // field[2] = output_type
        5, // field[5] = server_streaming
    };
    // pub const IntRange number_ranges[1 + 1] =
    // {
    //   { 1, 0 },
    //   { 0, 6 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 2, 3, 4, 5, 6 };
    pub const __opt_field_ids = [_]c_uint{ 1, 2, 3, 4, 5, 6 };
    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "MethodDescriptorProto",
        "google.protobuf",
        @sizeOf(MethodDescriptorProto),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(MethodDescriptorProto),
        &__opt_field_ids,
    );
};

pub const ServiceOptions = extern struct {
    base: Message,
    deprecated: bool = false,
    uninterpreted_option: ListMut(UninterpretedOption) = ListMut(UninterpretedOption).initEmpty(),

    pub const deprecated__default_value: c_int = 0;
    pub const init = Init(ServiceOptions);
    pub const format = Format(ServiceOptions);
    pub const field_descriptors = [2]FieldDescriptor{
        FieldDescriptor.init(
            "deprecated",
            33,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(ServiceOptions, "deprecated"),
            null,
            &deprecated__default_value,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(ServiceOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        0, // field[0] = deprecated
        1, // field[1] = uninterpreted_option
    };
    // pub const IntRange number_ranges[2 + 1] =
    // {
    //   { 33, 0 },
    //   { 999, 1 },
    //   { 0, 2 }
    // };
    pub const __field_ids = [_]c_uint{ 33, 999 };
    pub const __opt_field_ids = [_]c_uint{33};
    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "ServiceOptions",
        "google.protobuf",
        @sizeOf(ServiceOptions),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(ServiceOptions),
        &__opt_field_ids,
    );
};

pub const ServiceDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    method: ListMut(MethodDescriptorProto) = ListMut(MethodDescriptorProto).initEmpty(),
    options: ServiceOptions = ServiceOptions.init(),

    pub const init = Init(ServiceDescriptorProto);
    pub const format = Format(ServiceDescriptorProto);
    pub const field_descriptors = [3]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(ServiceDescriptorProto, "name"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "method",
            2,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(ServiceDescriptorProto, "method"),
            &MethodDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "options",
            3,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(ServiceDescriptorProto, "options"),
            &ServiceOptions.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        1, // field[1] = method
        0, // field[0] = name
        2, // field[2] = options
    };
    // pub const IntRange number_ranges[1 + 1] =
    // {
    //   { 1, 0 },
    //   { 0, 3 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 2, 3 };
    pub const __opt_field_ids = [_]c_uint{ 1, 3 };
    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "ServiceDescriptorProto",
        "google.protobuf",
        @sizeOf(ServiceDescriptorProto),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(ServiceDescriptorProto),
        &__opt_field_ids,
    );
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
    uninterpreted_option: ListMut(UninterpretedOption) = ListMut(UninterpretedOption).initEmpty(),

    pub const init = Init(FileOptions);
    pub const format = Format(FileOptions);

    pub const OptimizeMode = enum(u8) {
        NONE = 0,
        SPEED = 1,
        CODE_SIZE = 2,
        LITE_RUNTIME = 3,
        pub const enum_values_by_number = [_]EnumValue{
            EnumValue.init("NONE", "FileOptions.OptimizeMode.NONE", 0),
            EnumValue.init("SPEED", "FileOptions.OptimizeMode.SPEED", 1),
            EnumValue.init("CODE_SIZE", "FileOptions.OptimizeMode.CODE_SIZE", 2),
            EnumValue.init("LITE_RUNTIME", "FileOptions.OptimizeMode.LITE_RUNTIME", 3),
        };
        // pub const  value_ranges = [] IntRange{
        // {1, 0},{0, 3}
        // };
        pub const enum_values_by_name = [_]EnumValueIndex{
            EnumValueIndex.init("CODE_SIZE", 2),
            EnumValueIndex.init("LITE_RUNTIME", 3),
            EnumValueIndex.init("NONE", 0),
            EnumValueIndex.init("SPEED", 1),
        };
        pub const descriptor = EnumDescriptor.init(
            ENUM_DESCRIPTOR_MAGIC,
            "OptimizeMode",
            "google.protobuf.FileOptions",
            List(EnumValue).init(&enum_values_by_number),
            List(EnumValueIndex).init(&enum_values_by_name),
        );
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
        ),
        FieldDescriptor.init(
            "java_outer_classname",
            8,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "java_outer_classname"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "java_multiple_files",
            10,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "java_multiple_files"),
            null,
            &java_multiple_files__default_value,
        ),
        FieldDescriptor.init(
            "java_generate_equals_and_hash",
            20,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "java_generate_equals_and_hash"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "java_string_check_utf8",
            27,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "java_string_check_utf8"),
            null,
            &java_string_check_utf8__default_value,
        ),
        FieldDescriptor.init(
            "optimize_for",
            9,
            .LABEL_OPTIONAL,
            .TYPE_ENUM,
            @offsetOf(FileOptions, "optimize_for"),
            &OptimizeMode.descriptor,
            &optimize_for__default_value,
        ),
        FieldDescriptor.init(
            "go_package",
            11,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "go_package"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "cc_generic_services",
            16,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "cc_generic_services"),
            null,
            &cc_generic_services__default_value,
        ),
        FieldDescriptor.init(
            "java_generic_services",
            17,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "java_generic_services"),
            null,
            &java_generic_services__default_value,
        ),
        FieldDescriptor.init(
            "py_generic_services",
            18,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "py_generic_services"),
            null,
            &py_generic_services__default_value,
        ),
        FieldDescriptor.init(
            "php_generic_services",
            42,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "php_generic_services"),
            null,
            &php_generic_services__default_value,
        ),
        FieldDescriptor.init(
            "deprecated",
            23,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "deprecated"),
            null,
            &deprecated__default_value,
        ),
        FieldDescriptor.init(
            "cc_enable_arenas",
            31,
            .LABEL_OPTIONAL,
            .TYPE_BOOL,
            @offsetOf(FileOptions, "cc_enable_arenas"),
            null,
            &cc_enable_arenas__default_value,
        ),
        FieldDescriptor.init(
            "objc_class_prefix",
            36,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "objc_class_prefix"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "csharp_namespace",
            37,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "csharp_namespace"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "swift_prefix",
            39,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "swift_prefix"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "php_class_prefix",
            40,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "php_class_prefix"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "php_namespace",
            41,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "php_namespace"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "php_metadata_namespace",
            44,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "php_metadata_namespace"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "ruby_package",
            45,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileOptions, "ruby_package"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "uninterpreted_option",
            999,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileOptions, "uninterpreted_option"),
            &UninterpretedOption.descriptor,
            null,
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        11, // field[11] = cc_enable_arenas
        5, // field[5] = cc_generic_services
        13, // field[13] = csharp_namespace
        9, // field[9] = deprecated
        4, // field[4] = go_package
        8, // field[8] = java_generate_equals_and_hash
        6, // field[6] = java_generic_services
        3, // field[3] = java_multiple_files
        1, // field[1] = java_outer_classname
        0, // field[0] = java_package
        10, // field[10] = java_string_check_utf8
        12, // field[12] = objc_class_prefix
        2, // field[2] = optimize_for
        15, // field[15] = php_class_prefix
        17, // field[17] = php_generic_services
        18, // field[18] = php_metadata_namespace
        16, // field[16] = php_namespace
        7, // field[7] = py_generic_services
        19, // field[19] = ruby_package
        14, // field[14] = swift_prefix
        20, // field[20] = uninterpreted_option
    };
    // pub const IntRange number_ranges[11 + 1] =
    // {
    //   { 1, 0 },
    //   { 8, 1 },
    //   { 16, 5 },
    //   { 20, 8 },
    //   { 23, 9 },
    //   { 27, 10 },
    //   { 31, 11 },
    //   { 36, 12 },
    //   { 39, 14 },
    //   { 44, 18 },
    //   { 999, 20 },
    //   { 0, 21 }
    // };
    pub const __field_ids = [_]c_uint{ 1, 8, 10, 20, 27, 9, 11, 16, 17, 18, 42, 23, 31, 36, 37, 39, 40, 41, 44, 45, 999 };
    pub const __opt_field_ids = [_]c_uint{ 1, 8, 10, 20, 27, 9, 11, 16, 17, 18, 42, 23, 31, 36, 37, 39, 40, 41, 44, 45 };

    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "FileOptions",
        "google.protobuf",
        @sizeOf(FileOptions),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(FileOptions),
        &__opt_field_ids,
    );
};

pub const SourceCodeInfo = extern struct {
    base: Message,
    location: ListMut(Location) = ListMut(Location).initEmpty(),

    pub const init = Init(SourceCodeInfo);
    pub const format = Format(SourceCodeInfo);

    pub const Location = extern struct {
        base: Message,
        path: ListMut1(i32) = ListMut1(i32).initEmpty(),
        span: ListMut1(i32) = ListMut1(i32).initEmpty(),
        leading_comments: String = String.initEmpty(),
        trailing_comments: String = String.initEmpty(),
        leading_detached_comments: ListMut1(String) = ListMut1(String).initEmpty(),

        pub const init = Init(Location);
        pub const format = Format(Location);

        pub const field_descriptors = [5]FieldDescriptor{
            FieldDescriptor.init(
                "path",
                1,
                .LABEL_REPEATED,
                .TYPE_INT32,
                @offsetOf(Location, "path"),
                null,
                null,
            ),
            FieldDescriptor.init(
                "span",
                2,
                .LABEL_REPEATED,
                .TYPE_INT32,
                @offsetOf(Location, "span"),
                null,
                null,
            ),
            FieldDescriptor.init(
                "leading_comments",
                3,
                .LABEL_OPTIONAL,
                .TYPE_STRING,
                @offsetOf(Location, "leading_comments"),
                null,
                null,
            ),
            FieldDescriptor.init(
                "trailing_comments",
                4,
                .LABEL_OPTIONAL,
                .TYPE_STRING,
                @offsetOf(Location, "trailing_comments"),
                null,
                null,
            ),
            FieldDescriptor.init(
                "leading_detached_comments",
                6,
                .LABEL_REPEATED,
                .TYPE_STRING,
                @offsetOf(Location, "leading_detached_comments"),
                null,
                null,
            ),
        };
        pub const field_indices_by_name = [_]c_uint{
            2, // field[2] = leading_comments
            4, // field[4] = leading_detached_comments
            0, // field[0] = path
            1, // field[1] = span
            3, // field[3] = trailing_comments
        };
        // pub const IntRange number_ranges[2 + 1] =
        // {
        //   { 1, 0 },
        //   { 6, 4 },
        //   { 0, 5 }
        // };
        pub const __field_ids = [_]c_uint{ 1, 2, 3, 4, 6 };
        pub const __opt_field_ids = [_]c_uint{ 3, 4 };

        const descriptor = MessageDescriptor.init(
            MESSAGE_DESCRIPTOR_MAGIC,
            "Location",
            "google.protobuf",
            @sizeOf(Location),
            List(FieldDescriptor).init(&Location.field_descriptors),
            List(c_uint).init(&Location.field_indices_by_name),
            List(c_uint).init(&Location.__field_ids),
            InitBytes(Location),
            &Location.__opt_field_ids,
        );
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
        ),
    };
    pub const field_indices_by_name = [_]c_uint{
        0, //field[0] = location
    };
    // pub const IntRange number_ranges[1 + 1] =
    // {
    //   { 1, 0 },
    //   { 0, 1 }
    // };
    pub const __field_ids = [_]c_uint{1};
    pub const __opt_field_ids = [_]c_uint{};

    const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "SourceCodeInfo",
        "google.protobuf",
        @sizeOf(SourceCodeInfo),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(SourceCodeInfo),
        &__opt_field_ids,
    );
};

pub const FileDescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    package: String = String.initEmpty(),
    dependency: ListMut1(String) = ListMut1(String).initEmpty(),
    public_dependency: ListMut1(i32) = ListMut1(i32).initEmpty(),
    weak_dependency: ListMut1(i32) = ListMut1(i32).initEmpty(),
    message_type: ListMut(DescriptorProto) = ListMut(DescriptorProto).initEmpty(),
    enum_type: ListMut(EnumDescriptorProto) = ListMut(EnumDescriptorProto).initEmpty(),
    service: ListMut(ServiceDescriptorProto) = ListMut(ServiceDescriptorProto).initEmpty(),
    extension: ListMut(FieldDescriptorProto) = ListMut(FieldDescriptorProto).initEmpty(),
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

    pub const init = Init(FileDescriptorProto);
    pub const format = Format(FileDescriptorProto);

    pub const field_descriptors = [13]FieldDescriptor{
        FieldDescriptor.init(
            "name",
            1,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "name"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "package",
            2,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "package"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "dependency",
            3,
            .LABEL_REPEATED,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "dependency"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "public_dependency",
            10,
            .LABEL_REPEATED,
            .TYPE_INT32,
            @offsetOf(FileDescriptorProto, "public_dependency"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "weak_dependency",
            11,
            .LABEL_REPEATED,
            .TYPE_INT32,
            @offsetOf(FileDescriptorProto, "weak_dependency"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "message_type",
            4,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "message_type"),
            &DescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "enum_type",
            5,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "enum_type"),
            &EnumDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "service",
            6,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "service"),
            &ServiceDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "extension",
            7,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "extension"),
            &FieldDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "options",
            8,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "options"),
            &FileOptions.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "source_code_info",
            9,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorProto, "source_code_info"),
            &SourceCodeInfo.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "syntax",
            12,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "syntax"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "edition",
            13,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(FileDescriptorProto, "edition"),
            null,
            null,
        ),
    };

    pub const field_indices_by_name = [_:0]c_uint{
        2, //  field[2] = dependency
        12, //  field[12] = edition
        4, //  field[4] = enum_type
        6, //  field[6] = extension
        3, //  field[3] = message_type
        0, //  field[0] = name
        7, //  field[7] = options
        1, //  field[1] = package
        9, //  field[9] = public_dependency
        5, //  field[5] = service
        8, //  field[8] = source_code_info
        11, //  field[11] = syntax
        10, //  field[10] = weak_dependency
    };

    pub const __field_ids = [_]c_uint{ 1, 2, 3, 10, 11, 4, 5, 6, 7, 8, 9, 12, 13 };
    pub const __opt_field_ids = [_]c_uint{ 1, 2, 8, 9, 12, 13 };
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "FileDescriptorProto",
        "google.protobuf",
        @sizeOf(FileDescriptorProto),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(FileDescriptorProto),
        &__opt_field_ids,
    );
    // pub const number_ranges = [1 + 1]IntRange{
    //     IntRange.init(1, 0),
    //     IntRange.init(0, 13),
    // };
};

pub const FileDescriptorSet = extern struct {
    base: Message,
    file: ListMut(FileDescriptorProto) = ListMut(FileDescriptorProto).initEmpty(),

    pub const init = Init(FileDescriptorSet);
    pub const format = Format(FileDescriptorSet);

    pub const field_indices_by_name = [_:0]c_uint{
        0, // field[0] = file
    };
    // pub const number_ranges = [1 + 1]IntRange{
    //     IntRange.init(1, 0),
    //     IntRange.init(0, 1),
    // };

    pub const field_descriptors = [1]FieldDescriptor{
        FieldDescriptor.init(
            "file",
            1,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(FileDescriptorSet, "file"),
            &FileDescriptorProto.descriptor,
            null,
        ),
    };
    pub const __field_ids = [_]c_uint{1};
    pub const __opt_field_ids = [_]c_uint{};
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "FileDescriptorSet",
        "google.protobuf",
        @sizeOf(FileDescriptorSet),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(FileDescriptorSet),
        &__opt_field_ids,
    );
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

    pub const init = Init(Version);
    pub const format = Format(Version);

    pub const field_descriptors = [4]FieldDescriptor{
        FieldDescriptor.init(
            "major",
            1,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Version, "major"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "minor",
            2,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Version, "minor"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "patch",
            3,
            .LABEL_OPTIONAL,
            .TYPE_INT32,
            @offsetOf(Version, "patch"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "suffix",
            4,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(Version, "suffix"),
            null,
            null,
        ),
    };
    pub const field_indices_by_name = [_:0]c_uint{
        0, // field[0] = major
        1, // field[1] = minor
        2, // field[2] = patch
        3, // field[3] = suffix
    };
    // pub const number_ranges = [1 + 1]IntRange{
    //     IntRange.init(1, 0),
    //     IntRange.init(0, 4),
    // };
    pub const __field_ids = [_]c_uint{ 1, 2, 3, 4 };
    pub const __opt_field_ids = [_]c_uint{ 1, 2, 3, 4 };
    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "Version",
        "google.protobuf.compiler",
        @sizeOf(Version),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(Version),
        &__opt_field_ids,
    );
};

pub const CodeGeneratorRequest = extern struct {
    base: Message,
    file_to_generate: ListMut1(String) = ListMut1(String).initEmpty(),
    parameter: String = String.initEmpty(),
    proto_file: ListMut(FileDescriptorProto) = ListMut(FileDescriptorProto).initEmpty(),
    compiler_version: Version = Version.init(),

    comptime {
        // @compileLog(@sizeOf(CodeGeneratorRequest));
        assert(@sizeOf(CodeGeneratorRequest) == 176);
        // @compileLog(@offsetOf(CodeGeneratorRequest, "proto_file"));
        assert(@offsetOf(CodeGeneratorRequest, "proto_file") == 0x50); //  == 80
    }

    pub const init = Init(CodeGeneratorRequest);
    pub const initBytes = InitBytes(CodeGeneratorRequest);
    pub const format = Format(CodeGeneratorRequest);

    pub const field_descriptors = [4]FieldDescriptor{
        FieldDescriptor.init(
            "file_to_generate",
            1,
            .LABEL_REPEATED,
            .TYPE_STRING,
            @offsetOf(CodeGeneratorRequest, "file_to_generate"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "parameter",
            2,
            .LABEL_OPTIONAL,
            .TYPE_STRING,
            @offsetOf(CodeGeneratorRequest, "parameter"),
            null,
            null,
        ),
        FieldDescriptor.init(
            "proto_file",
            15,
            .LABEL_REPEATED,
            .TYPE_MESSAGE,
            @offsetOf(CodeGeneratorRequest, "proto_file"),
            &FileDescriptorProto.descriptor,
            null,
        ),
        FieldDescriptor.init(
            "compiler_version",
            3,
            .LABEL_OPTIONAL,
            .TYPE_MESSAGE,
            @offsetOf(CodeGeneratorRequest, "compiler_version"),
            &Version.descriptor,
            null,
        ),
    };

    pub const field_indices_by_name = [_:0]c_uint{
        2, //  field[2] = compiler_version
        0, //  field[0] = file_to_generate
        1, //  field[1] = parameter
        3, //  field[3] = proto_file
    };

    pub const __field_ids = [_]c_uint{ 1, 2, 15, 3 };
    pub const __opt_field_ids = [_]c_uint{ 2, 3 };
    // [2 + 1]IntRange{
    //     IntRange.init(1, 0),
    //     IntRange.init(15, 3),
    //     IntRange.init(0, 4),
    // };

    pub const descriptor = MessageDescriptor.init(
        MESSAGE_DESCRIPTOR_MAGIC,
        "CodeGeneratorRequest",
        "google.protobuf.compiler",
        @sizeOf(CodeGeneratorRequest),
        List(FieldDescriptor).init(&field_descriptors),
        List(c_uint).init(&field_indices_by_name),
        List(c_uint).init(&__field_ids),
        InitBytes(CodeGeneratorRequest),
        &__opt_field_ids,
    );
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
