//!
//! this file was originally adapted from https://github.com/protobuf-c/protobuf-c/blob/master/protobuf-c/protobuf-c.h
//! by running `$ zig translate-c` on this file and then doing lots and lots and lots and lots of editing.
//!
//! it is an effort to bootstrap the project and should eventually be generated
//! from https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/descriptor.proto
//! and https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/compiler/plugin.proto
//!

// TODO get rid of __field_ids and __opt_field_ids.
//   these are now redundant and left in only as a sanity check.

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
// TODO move these into single file ie 'protobuf.zig'
const types = @import("../../../types.zig");
const common = @import("../../../common.zig");
const util = @import("../../../protobuf-util.zig");
const String = types.String;
const empty_str = types.empty_str;
const ptrfmt = common.ptrfmt;
const compileErr = common.compileErr;
const ptrAlignCast = common.ptrAlignCast;
const todo = common.todo;

const WireType = types.WireType;
const BinaryType = types.BinaryType;

/// helper for repeated message types.
/// checks that T is a pointer to struct and not pointer to String.
/// returns types.ListTypeMut(T)
fn ListMut(comptime T: type) type {
    const tinfo = @typeInfo(T);
    assert(tinfo == .Pointer);
    const Child = tinfo.Pointer.child;
    const cinfo = @typeInfo(Child);
    assert(cinfo == .Struct);
    assert(Child != String);
    return types.ListTypeMut(T);
}

const List = types.ListType;

/// helper for repeated scalar types.
/// checks that T is a String or other scalar type.
/// returns types.ListTypeMut(T)
fn ListMutScalar(comptime T: type) type {
    assert(T == String or !std.meta.trait.isContainer(T));
    return types.ListTypeMut(T);
}

pub const SERVICE_DESCRIPTOR_MAGIC = 0x14159bc3;
pub const MESSAGE_DESCRIPTOR_MAGIC = 0x28aaeef9;
pub const ENUM_DESCRIPTOR_MAGIC = 0x114315af;
pub const MessageInit = ?*const fn ([*]u8, usize) void;

pub fn InitBytes(comptime T: type) MessageInit {
    return struct {
        pub fn initBytes(bytes: [*]u8, len: usize) void {
            assert(len == @sizeOf(T));
            var ptr = ptrAlignCast(*T, bytes);
            ptr.* = T.init();
        }
    }.initBytes;
}

pub fn Init(comptime T: type) fn () T {
    return struct {
        pub fn init() T {
            assert(mem.endsWith(u8, @typeName(T), T.descriptor.name.slice()));
            return .{
                .base = Message.init(&T.descriptor),
            };
        }
    }.init;
}

pub fn SetPresentField(comptime T: type) fn (*T, comptime std.meta.FieldEnum(T)) void {
    return struct {
        const FieldEnum = std.meta.FieldEnum(T);
        pub fn setPresentField(self: *T, comptime field_enum: std.meta.FieldEnum(T)) void {
            const tagname = @tagName(field_enum);
            const name = T.descriptor.name;
            if (comptime mem.eql(u8, "base", tagname))
                compileErr("{s}.setPresentField() field_enum == .base", .{name});
            const field_idx = std.meta.fieldIndex(T, tagname) orelse
                compileErr("{s}.setPresentField() invalid field name {s}", .{ name, tagname });
            std.log.info("setPresentField() {s}.{s}:{}", .{ name, @tagName(field_enum), field_idx });
            self.base.setPresentFieldIndex(field_idx - 1);
        }
    }.setPresentField;
}

const WriteErr = std.fs.File.WriteError;
pub fn FormatFn(comptime T: type) type {
    return fn (T, comptime []const u8, std.fmt.FormatOptions, anytype) WriteErr!void;
}

fn optionalFieldIds(comptime field_descriptors: []const FieldDescriptor) []const c_uint {
    var result: [field_descriptors.len]c_uint = undefined;
    var count: u32 = 0;
    for (field_descriptors) |fd| {
        if (fd.label == .LABEL_OPTIONAL) {
            result[count] = fd.id;
            count += 1;
        }
    }
    return result[0..count];
}
fn fieldIds(comptime field_descriptors: []const FieldDescriptor) []const c_uint {
    var result: [field_descriptors.len]c_uint = undefined;
    for (field_descriptors) |fd, i| {
        result[i] = fd.id;
    }
    return &result;
}
fn fieldIndicesByName(comptime field_descriptors: []const FieldDescriptor) []const c_uint {
    const Tup = struct { c_uint, []const u8 };
    var tups: [field_descriptors.len]Tup = undefined;
    const lessThan = struct {
        fn lessThan(_: void, a: Tup, b: Tup) bool {
            return std.mem.lessThan(u8, a[1], b[1]);
        }
    }.lessThan;
    for (field_descriptors) |fd, i| tups[i] = .{ @intCast(c_uint, i), fd.name.slice() };
    std.sort.sort(Tup, &tups, {}, lessThan);
    var result: [field_descriptors.len]c_uint = undefined;
    for (tups) |tup, i| result[i] = tup[0];
    return &result;
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
    zig_name: String = String.initEmpty(),
    value: c_int,
    pub fn init(
        name: [:0]const u8,
        zig_name: [:0]const u8,
        value: c_int,
    ) EnumValue {
        return .{
            .name = String.init(name),
            .zig_name = String.init(zig_name),
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

fn enumValuesByNumber(comptime T: type) []const EnumValue {
    const tags = std.meta.tags(T);
    var result: [tags.len]EnumValue = undefined;
    for (tags) |tag, i| {
        result[i] = .{
            .value = @enumToInt(tag),
            .name = String.init(@tagName(tag)),
            .zig_name = String.init(@typeName(T) ++ "." ++ @tagName(tag)),
        };
    }
    return &result;
}

pub const EnumDescriptor = extern struct {
    magic: u32 = 0,
    name: String = String.initEmpty(),
    short_name: String = String.initEmpty(),
    zig_name: String = String.initEmpty(),
    package_name: String = String.initEmpty(),
    values: List(EnumValue),
    reserved1: ?*anyopaque = null,
    reserved2: ?*anyopaque = null,
    reserved3: ?*anyopaque = null,
    reserved4: ?*anyopaque = null,

    pub fn init(comptime T: type) EnumDescriptor {
        const typename = @typeName(T);
        const names = common.splitOn([]const u8, typename, '.');
        const name = names[1];
        const values = T.enum_values_by_number;
        comptime {
            const tfields = std.meta.fields(T);
            for (values) |field, i| {
                const fname = field.name.slice();
                const tfield = tfields[i];
                if (field.value != tfield.value)
                    compileErr("{s} {s} {} != {}", .{ name, fname, field.value, tfield.value });

                if (!mem.eql(u8, fname, tfield.name))
                    compileErr("{s} {s} != {s}", .{ name, fname, tfield.name });
                // TODO values_by_name
            }
        }
        return .{
            .magic = ENUM_DESCRIPTOR_MAGIC,
            .name = String.init(name),
            .package_name = String.init(names[0]),
            .values = List(EnumValue).init(values),
        };
    }
};

pub const FieldDescriptor = extern struct {
    name: String = String.initEmpty(),
    id: c_uint = 0,
    label: FieldDescriptorProto.Label,
    type: FieldDescriptorProto.Type,
    offset: c_uint,
    descriptor: ?*const anyopaque = null,
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
        descriptor: ?*const anyopaque,
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

    pub fn getDescriptor(fd: FieldDescriptor, comptime T: type) *const T {
        assert(fd.descriptor != null);
        return ptrAlignCast(*const T, fd.descriptor);
    }
};

pub const MessageDescriptor = extern struct {
    magic: u32 = 0,
    name: String = String.initEmpty(),
    zig_name: String = String.initEmpty(),
    package_name: String = String.initEmpty(),
    sizeof_message: usize = 0,
    fields: List(FieldDescriptor),
    field_ids: List(c_uint),
    opt_field_ids: List(c_uint),
    message_init: MessageInit = null,
    reserved1: ?*anyopaque = null,
    reserved2: ?*anyopaque = null,
    reserved3: ?*anyopaque = null,

    pub fn init(comptime T: type) MessageDescriptor {
        const typename = @typeName(T);
        const names = common.splitOn([]const u8, typename, '.');
        const name = names[1];
        const result: MessageDescriptor = .{
            .magic = MESSAGE_DESCRIPTOR_MAGIC,
            .name = String.init(name),
            .zig_name = String.init(typename),
            .package_name = String.init(names[0]),
            .sizeof_message = @sizeOf(T),
            .fields = List(FieldDescriptor).init(&T.field_descriptors),
            .field_ids = List(c_uint).init(T.field_ids),
            .opt_field_ids = List(c_uint).init(T.opt_field_ids),
            .message_init = InitBytes(T),
        };
        // TODO - audit and remove unnecessary checks
        comptime {
            const fields = result.fields;
            const field_ids = result.field_ids;
            const opt_field_ids = result.opt_field_ids;
            assert(field_ids.len == fields.len);
            assert(opt_field_ids.len <= 64);

            const sizeof_message = result.sizeof_message;
            assert(sizeof_message == @sizeOf(T));
            const len = @typeInfo(T).Struct.fields.len;
            if (len != fields.len + 1) compileErr(
                "{s} field lengths mismatch. expected '{}' got '{}'",
                .{ name, len, fields.len },
            );
            const tfields = std.meta.fields(T);
            var fields_total_size: usize = @sizeOf(Message);
            var last_field_offset: usize = @sizeOf(Message);
            if (!mem.eql(u8, tfields[0].name, "base"))
                compileErr("{s} missing 'base' field ", .{name});
            if (tfields[0].type != Message)
                compileErr("{s} 'base' field expected 'Message' type. got '{s}'.", .{@typeName(tfields[0].type)});
            for (tfields[1..tfields.len]) |f, i| {
                if (!mem.eql(u8, f.name, fields.items[i].name.slice()))
                    compileErr(
                        "{s} field name mismatch. expected '{s}' got '{s}'",
                        .{ name, f.name, fields.items[i].name },
                    );
                const expected_offset = @offsetOf(T, f.name);
                if (expected_offset != fields.items[i].offset)
                    compileErr(
                        "{s} offset mismatch expected '{}' got '{}'",
                        .{ name, expected_offset, fields.items[i].offset },
                    );
                fields_total_size += expected_offset - last_field_offset;
                last_field_offset = expected_offset;
            }
            fields_total_size += sizeof_message - fields.items[fields.len - 1].offset;
            if (fields_total_size != sizeof_message)
                compileErr(
                    "{s} size mismatch expected {} but fields total calculated size is {}",
                    .{ name, sizeof_message, fields_total_size },
                );
        }

        return result;
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
    key: types.Key,
    data: String = String.initEmpty(),
};

pub const Message = extern struct {
    descriptor: ?*const MessageDescriptor,
    unknown_fields: ListMut(*MessageUnknownField) = ListMut(*MessageUnknownField).initEmpty(),
    optional_fields_present: u64 = 0,

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

    /// returns true when `field_id` is non-optional
    /// otherwise checks `field_id` is in `m.opt_field_ids`
    pub fn isPresent(m: *const Message, field_id: c_uint) bool {
        const desc = m.descriptor orelse unreachable;
        const opt_field_idx = desc.optionalFieldIndex(field_id) orelse
            return true;
        return (m.optional_fields_present >> @intCast(u6, opt_field_idx)) & 1 != 0;
    }

    /// mark `m.optional_fields_present` at the field index corresponding to
    /// if `field_id` is a non optional field
    pub fn setPresent(m: *Message, field_id: c_uint) void {
        const desc = m.descriptor orelse
            @panic("called setPresent() on a message with no descriptor.");
        std.log.info("setPresent({}) - {any}", .{ field_id, desc.opt_field_ids });
        const opt_field_idx = desc.optionalFieldIndex(field_id) orelse return;
        std.log.debug("setPresent 1 m.optional_fields_present {b:0>64}", .{m.optional_fields_present});
        m.optional_fields_present |= @as(u64, 1) << @intCast(u6, opt_field_idx);
        std.log.debug("setPresent 2 m.optional_fields_present {b:0>64}", .{m.optional_fields_present});
    }

    pub fn setPresentFieldIndex(m: *Message, field_index: usize) void {
        const desc = m.descriptor orelse
            @panic("called setPresentFieldIndex() on a message with no descriptor.");
        std.log.info("setPresentFieldIndex() field_index {} opt_field_ids {any}", .{ field_index, desc.opt_field_ids.slice() });
        m.setPresent(desc.field_ids.items[field_index]);
    }

    /// ptr cast to T. verifies that m.descriptor.name ends with @typeName(T)
    pub fn as(m: *Message, comptime T: type) !*T {
        if (!mem.endsWith(u8, @typeName(T), m.descriptor.?.name.slice())) {
            std.log.err("expected '{s}' to contain '{s}'", .{ @typeName(T), m.descriptor.?.name.slice() });
            return error.TypeMismatch;
        }
        return @ptrCast(*T, m);
    }

    pub fn formatMessage(message: *const Message, writer: anytype) WriteErr!void {
        const desc = message.descriptor orelse unreachable;
        try writer.print("{s}{{", .{desc.name.slice()});
        const fields = desc.fields;
        const bytes = @ptrCast([*]const u8, message);
        for (fields.slice()) |f, i| {
            const member = bytes + f.offset;
            const field_id = desc.field_ids.items[i];
            // skip if optional field and not present
            const field_name = f.name.slice();
            if (message.isPresent(field_id)) {
                switch (f.type) {
                    .TYPE_MESSAGE => {
                        if (f.label == .LABEL_REPEATED) {
                            const list = ptrAlignCast(*const ListMut(*Message), member);
                            if (list.len == 0) continue; // prevent extra commas
                            try writer.print(".{s} = &.{{", .{field_name});
                            for (list.slice()) |it, j| {
                                if (j != 0) _ = try writer.write(", ");
                                try Message.formatMessage(it, writer);
                            }
                            _ = try writer.write("}");
                        } else {
                            try writer.print(".{s} = ", .{field_name});
                            try Message.formatMessage(ptrAlignCast(*const Message, member), writer);
                        }
                    },
                    .TYPE_STRING => {
                        if (f.label == .LABEL_REPEATED) {
                            const list = ptrAlignCast(*const ListMutScalar(String), member);
                            if (list.len == 0) continue; // prevent extra commas
                            try writer.print(".{s} = &.{{", .{field_name});
                            for (list.slice()) |it, j| {
                                if (j != 0) _ = try writer.write(", ");
                                try writer.print("{}", .{it});
                            }
                            _ = try writer.write("}");
                        } else try writer.print(".{s} = {}", .{ field_name, ptrAlignCast(*const String, member).* });
                    },
                    .TYPE_BOOL => {
                        if (f.label == .LABEL_REPEATED) todo("format repeated bool", .{});
                        try writer.print(".{s} = {}", .{ field_name, member[0] });
                    },
                    .TYPE_INT32 => {
                        if (f.label == .LABEL_REPEATED) {
                            const list = ptrAlignCast(*const ListMutScalar(i32), member);
                            if (list.len == 0) continue; // prevent extra commas
                            try writer.print(".{s} = &.{{", .{field_name});
                            for (list.slice()) |it, j| {
                                if (j != 0) _ = try writer.write(", ");
                                try writer.print("{}", .{it});
                            }
                            _ = try writer.write("}");
                        } else try writer.print(".{s} = {}", .{ field_name, @bitCast(i32, member[0..4].*) });
                    },
                    else => {
                        todo(".{s} .{s}", .{ @tagName(f.type), @tagName(f.label) });
                    },
                }
                if (i != fields.len - 1) _ = try writer.write(", ");
            }
        }
        _ = try writer.write("}");
    }

    pub fn deinit(m: *Message, allocator: mem.Allocator) void {
        deinitImpl(m, allocator, .all_fields);
    }

    fn isPointerField(f: FieldDescriptor) bool {
        return f.label == .LABEL_REPEATED or f.type == .TYPE_STRING;
    }

    fn deinitImpl(
        m: *Message,
        allocator: mem.Allocator,
        mode: enum { all_fields, only_pointer_fields },
    ) void {
        const bytes = @ptrCast([*]u8, m);
        const desc = m.descriptor orelse
            std.debug.panic("can't deinit a message with no descriptor.", .{});

        std.log.debug("\ndeinit message {s}{}-{} size={}", .{ desc.name.slice(), ptrfmt(m), ptrfmt(bytes + desc.sizeof_message), desc.sizeof_message });

        for (desc.fields.slice()) |field| {
            if (mode == .only_pointer_fields and !isPointerField(field))
                continue;
            if (field.label == .LABEL_REPEATED) {
                if (field.type == .TYPE_STRING) {
                    const L = ListMutScalar(String);
                    var list = ptrAlignCast(*L, bytes + field.offset);
                    if (list.len != 0) {
                        std.log.debug("deinit {s}.{s} repeated string field len {}", .{ desc.name.slice(), field.name.slice(), list.len });
                        for (list.slice()) |s|
                            s.deinit(allocator);
                        list.deinit(allocator);
                    }
                } else if (field.type == .TYPE_MESSAGE) {
                    const L = ListMut(*Message);
                    var list = ptrAlignCast(*L, bytes + field.offset);
                    if (list.len != 0) {
                        std.log.debug(
                            "deinit {s}.{s} repeated message field len/cap {}/{}",
                            .{ desc.name.slice(), field.name.slice(), list.len, list.cap },
                        );
                        for (list.slice()) |subm|
                            deinitImpl(subm, allocator, .all_fields);
                        list.deinit(allocator);
                    }
                } else {
                    const size = common.repeatedEleSize(field.type);
                    const L = ListMutScalar(u8);
                    var list = ptrAlignCast(*L, bytes + field.offset);
                    if (list.len != 0) {
                        std.log.debug(
                            "deinit {s}.{s} repeated field {s} len {} size {} bytelen {}",
                            .{ desc.name.slice(), field.name.slice(), @tagName(field.type), list.len, size, size * list.len },
                        );
                        allocator.free(list.items[0 .. size * list.cap]);
                    }
                }
            } else if (field.type == .TYPE_MESSAGE) {
                if (m.isPresent(field.id)) {
                    std.log.debug("deinit {s}.{s} single message field", .{ desc.name, field.name });
                    var subm = ptrAlignCast(*Message, bytes + field.offset);
                    deinitImpl(subm, allocator, .only_pointer_fields);
                }
            } else if (field.type == .TYPE_STRING) {
                var s = ptrAlignCast(*String, bytes + field.offset);
                if (s.len != 0 and s.items != String.empty.items) {
                    std.log.debug(
                        "deinit {s}.{s} single string field {} offset {}",
                        .{ desc.name.slice(), field.name.slice(), ptrfmt(bytes + field.offset), field.offset },
                    );
                    s.deinit(allocator);
                }
            }
        }

        for (m.unknown_fields.slice()) |ufield| {
            allocator.free(ufield.data.slice());
            allocator.destroy(ufield);
        }
        m.unknown_fields.deinit(allocator);

        if (mode == .all_fields)
            allocator.free(bytes[0..desc.sizeof_message]);
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
//     zig_name: String,
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

pub fn Format(comptime T: type) FormatFn(T) {
    return struct {
        pub fn format(value: T, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) WriteErr!void {
            try value.base.formatMessage(writer);
        }
    }.format;
}

pub fn MessageMixins(comptime Self: type) type {
    return struct {
        pub const init = Init(Self);
        pub const initBytes = InitBytes(Self);
        pub const format = Format(Self);
        pub const setPresentField = SetPresentField(Self);
        pub const field_ids = fieldIds(&Self.field_descriptors);
        pub const opt_field_ids = optionalFieldIds(&Self.field_descriptors);
        pub const descriptor = MessageDescriptor.init(Self);
    };
}

pub fn EnumMixins(comptime Self: type) type {
    return struct {
        pub const enum_values_by_number = enumValuesByNumber(Self);
        pub const descriptor = EnumDescriptor.init(Self);
    };
}

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
};

pub const DescriptorProto = extern struct {
    base: Message,
    name: String = String.initEmpty(),
    field: ListMut(*FieldDescriptorProto) = ListMut(*FieldDescriptorProto).initEmpty(),
    extension: ListMut(*FieldDescriptorProto) = ListMut(*FieldDescriptorProto).initEmpty(),
    nested_type: types.ListTypeMut(*DescriptorProto) = .{ .items = types.ListTypeMut(*DescriptorProto).list_sentinel_ptr }, // workaround for 'dependency loop'
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
