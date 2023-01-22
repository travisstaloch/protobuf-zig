const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const types = @import("types.zig");
const common = @import("common.zig");
const plugin = @import("google/protobuf/compiler/plugin.pb.zig");
const ptrfmt = common.ptrfmt;
const compileErr = common.compileErr;
const ptrAlignCast = common.ptrAlignCast;
const todo = common.todo;
const String = types.String;
const List = types.ArrayList;
const ListMut = types.ListMut;
const ListMutScalar = types.ListMutScalar;
const FieldDescriptorProto = plugin.FieldDescriptorProto;

pub const SERVICE_DESCRIPTOR_MAGIC = 0x14159bc3;
pub const MESSAGE_DESCRIPTOR_MAGIC = 0x28aaeef9;
pub const ENUM_DESCRIPTOR_MAGIC = 0x114315af;
pub const MessageInit = ?*const fn ([*]u8, usize) void;

fn InitBytes(comptime T: type) MessageInit {
    return struct {
        pub fn initBytes(bytes: [*]u8, len: usize) void {
            assert(len == @sizeOf(T));
            var ptr = ptrAlignCast(*T, bytes);
            ptr.* = T.init();
        }
    }.initBytes;
}

fn Init(comptime T: type) fn () T {
    return struct {
        pub fn init() T {
            assert(mem.endsWith(u8, @typeName(T), T.descriptor.name.slice()));
            return .{
                .base = Message.init(&T.descriptor),
            };
        }
    }.init;
}

fn SetPresentField(comptime T: type) fn (*T, comptime std.meta.FieldEnum(T)) void {
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

fn Format(comptime T: type) FormatFn(T) {
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

pub const MessageUnknownField = extern struct {
    key: types.Key,
    data: String = String.initEmpty(),
};
