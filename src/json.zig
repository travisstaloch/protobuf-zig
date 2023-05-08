const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const pb = @import("protobuf");
const types = pb.types;
const Message = types.Message;
const MessageDescriptor = types.MessageDescriptor;
const FieldDescriptor = types.FieldDescriptor;
const extern_types = pb.extern_types;
const String = extern_types.String;
const List = extern_types.ArrayList;
const common = pb.common;
const ptrAlignCast = common.ptrAlignCast;
const flagsContain = types.flagsContain;
const Error = pb.protobuf.Error;

fn b64Encode(s: String, writer: anytype) !void {
    var encbuf: [0x100]u8 = undefined;
    var source = s.slice();
    _ = try writer.writeByte('"');
    while (source.len > 0) {
        const encoded = std.base64.standard.Encoder.encode(&encbuf, source);
        _ = try writer.write(encoded);
        source = source[@min(source.len, encoded.len)..];
    }
    _ = try writer.writeByte('"');
}

fn serializeErr(comptime fmt: []const u8, args: anytype, err: Error) Error {
    std.log.err("json serialization error: " ++ fmt, args);
    return err;
}

fn enumTagname(enumdesc: *const types.EnumDescriptor, int: i32) ![]const u8 {
    return for (enumdesc.values.slice()) |enum_value| {
        if (enum_value.value == int)
            break enum_value.name.slice();
    } else return serializeErr(
        "missing enum tag for value '{}'",
        .{int},
        error.FieldMissing,
    );
}

fn serializeFieldImpl(
    info: FieldInfo,
    comptime T: type,
    writer: anytype,
) !void {
    if (info.is_repeated) {
        const list = ptrAlignCast(*const List(T), info.member);
        for (list.slice(), 0..) |int, i| {
            if (i != 0) _ = try writer.writeByte(',');
            try info.options.writeIndent(writer);
            try writer.print("{}", .{int});
        }
    } else {
        try writer.print(
            "{}",
            .{mem.readIntLittle(T, info.member[0..@sizeOf(T)])},
        );
    }
}

pub const Options = struct {
    /// Whether to always print enums as ints. By default they are rendered as
    /// strings.
    /// TODO
    always_print_enums_as_ints: bool = false,
    /// Whether to preserve proto field names
    /// TODO
    preserve_proto_field_names: bool = false,
    /// Controls how to add spaces, line breaks and indentation to make the JSON output
    /// easy to read.
    pretty_print: ?struct {
        /// The number of space chars to print per indent level.
        indent_size: u4 = 4,
        /// The char to use for whitespace
        space_char: enum { space, tab } = .space,
        /// The current indent level
        indent_level: u8 = 0,
        /// After a colon, should whitespace be inserted?
        separator: bool = true,
    } = null,

    /// Whether to always print primitive fields. By default proto3 primitive
    /// fields with default values will be omitted in JSON output. For example, an
    /// int32 field set to 0 will be omitted. Set this flag to true will override
    /// the default behavior and print primitive fields regardless of their values.
    /// TODO
    always_print_primitive_fields: bool = false,

    pub fn writeIndent(
        options: Options,
        writer: anytype,
    ) !void {
        if (options.pretty_print) |opp| {
            try writer.writeByte('\n');
            const space_char: u8 = switch (opp.space_char) {
                .space => ' ',
                .tab => '\t',
            };
            try writer.writeByteNTimes(
                space_char,
                opp.indent_size * opp.indent_level,
            );
        }
    }
};

/// https://protobuf.dev/programming-guides/proto3/#json
pub fn serialize(
    message: *const Message,
    writer: anytype,
    options: Options,
) (@TypeOf(writer).Error || Error)!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    return serializeImpl(message, writer, options, &arena);
}
pub fn serializeImpl(
    message: *const Message,
    writer: anytype,
    options: Options,
    arena: *std.heap.ArenaAllocator,
) (@TypeOf(writer).Error || Error)!void {
    const desc = message.descriptor orelse return serializeErr(
        "invalid message. missing descriptor",
        .{},
        error.DescriptorMissing,
    );
    // std.debug.print("+++ serialize {}", .{desc.name});
    try pb.protobuf.verifyMessageType(desc.magic, types.MESSAGE_DESCRIPTOR_MAGIC);
    const buf = @ptrCast([*]const u8, message)[0..desc.sizeof_message];

    try writer.writeByte('{');
    var child_options = options;
    if (child_options.pretty_print) |*cpp| cpp.indent_level += 1;

    var any_written: bool = false;
    if (flagsContain(desc.flags, MessageDescriptor.Flag.FLAG_MAP_TYPE)) {
        const key_field = desc.fields.slice()[0];
        assert(key_field.id == 1);
        if (key_field.type != .TYPE_STRING)
            _ = try writer.write("\"");
        try serializeField(
            FieldInfo.init(
                key_field,
                buf.ptr + key_field.offset,
                false,
                child_options,
            ),
            writer,
            arena,
        );
        if (key_field.type != .TYPE_STRING)
            _ = try writer.write("\":")
        else
            _ = try writer.write(":");
        if (child_options.pretty_print) |cpp|
            _ = try writer.write(" "[0..@boolToInt(cpp.separator)]);
        const value_field = desc.fields.slice()[1];
        assert(value_field.id == 2);
        try serializeField(
            FieldInfo.init(
                value_field,
                buf.ptr + value_field.offset,
                value_field.label == .LABEL_REPEATED,
                child_options,
            ),
            writer,
            arena,
        );
    } else for (desc.fields.slice()) |field| {
        if (!message.hasFieldId(field.id)) continue;
        const member = buf.ptr + field.offset;
        const is_repeated = field.label == .LABEL_REPEATED;
        if (is_repeated) {
            const list = ptrAlignCast(*const List(u32), member);
            if (list.len == 0) continue;
        }
        if (any_written)
            _ = try writer.writeByte(',')
        else
            any_written = true;
        try child_options.writeIndent(writer);

        _ = try writer.print(
            \\"{}":
        , .{field.name});
        if (child_options.pretty_print) |cpp|
            _ = try writer.write(" "[0..@boolToInt(cpp.separator)]);

        try serializeField(
            FieldInfo.init(
                field,
                buf.ptr + field.offset,
                is_repeated,
                child_options,
            ),
            writer,
            arena,
        );
    }
    if (any_written) try options.writeIndent(writer);
    _ = try writer.writeAll("}");
}

pub const FieldInfo = struct {
    field: FieldDescriptor,
    member: [*]const u8,
    is_repeated: bool,
    options: Options,

    pub fn init(
        field: FieldDescriptor,
        member: [*]const u8,
        is_repeated: bool,
        options: Options,
    ) FieldInfo {
        return .{
            .field = field,
            .member = member,
            .is_repeated = is_repeated,
            .options = options,
        };
    }
};

/// either writes "NaN" or calls json.stringify(float)
fn serializeFloat(float: anytype, writer: anytype) !void {
    if (std.math.isNan(float) or std.math.isSignalNan(float))
        _ = try writer.write("\"NaN\"")
    else
        try std.json.stringify(float, .{}, writer);
}

fn serializeField(
    info: FieldInfo,
    writer: anytype,
    arena: *std.heap.ArenaAllocator,
) !void {
    var child_info = info;
    const field = child_info.field;
    const member = child_info.member;
    const is_map = field.descriptor != null and
        (field.type == .TYPE_MESSAGE or field.type == .TYPE_GROUP) and
        flagsContain(
        field.getDescriptor(MessageDescriptor).flags,
        MessageDescriptor.Flag.FLAG_MAP_TYPE,
    );

    if (child_info.is_repeated and !is_map) {
        try writer.writeByte('[');
        if (child_info.options.pretty_print) |*cpp| cpp.indent_level += 1;
    }

    switch (field.type) {
        .TYPE_INT32,
        .TYPE_SINT32,
        .TYPE_SFIXED32,
        => try serializeFieldImpl(child_info, i32, writer),
        .TYPE_UINT32,
        .TYPE_FIXED32,
        => try serializeFieldImpl(child_info, u32, writer),
        .TYPE_BOOL => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(u32), member);
            for (list.slice(), 0..) |int, i| {
                if (i != 0) _ = try writer.writeByte(',');
                try child_info.options.writeIndent(writer);
                try writer.print("{}", .{int != 0});
            }
        } else {
            try writer.print("{}", .{member[0] != 0});
        },
        .TYPE_ENUM => {
            const enumdesc = field.getDescriptor(types.EnumDescriptor);
            if (child_info.is_repeated) {
                const list = ptrAlignCast(*const List(i32), member);
                for (list.slice(), 0..) |int, i| {
                    if (i != 0) _ = try writer.writeByte(',');
                    const tagname = try enumTagname(enumdesc, int);
                    try child_info.options.writeIndent(writer);
                    try writer.print("\"{s}\"", .{tagname});
                }
            } else {
                const int = mem.readIntLittle(i32, member[0..4]);
                const tagname = try enumTagname(enumdesc, int);
                try writer.print("\"{s}\"", .{tagname});
            }
        },
        .TYPE_INT64,
        .TYPE_SINT64,
        .TYPE_SFIXED64,
        => try serializeFieldImpl(child_info, i64, writer),
        .TYPE_UINT64,
        .TYPE_FIXED64,
        => try serializeFieldImpl(child_info, u64, writer),
        .TYPE_FLOAT => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(f32), member);
            for (list.slice(), 0..) |float, i| {
                if (i != 0) _ = try writer.writeByte(',');
                try child_info.options.writeIndent(writer);
                try serializeFloat(float, writer);
            }
        } else try serializeFloat(
            @bitCast(f32, mem.readIntLittle(u32, member[0..4])),
            writer,
        ),
        .TYPE_DOUBLE => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(f64), member);
            for (list.slice(), 0..) |d, i| {
                if (i != 0) _ = try writer.writeByte(',');
                try child_info.options.writeIndent(writer);
                try serializeFloat(d, writer);
            }
        } else try serializeFloat(
            @bitCast(f64, mem.readIntLittle(u64, member[0..8])),
            writer,
        ),
        .TYPE_STRING => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(String), member);
            for (list.slice(), 0..) |s, i| {
                if (i != 0) _ = try writer.writeByte(',');
                try child_info.options.writeIndent(writer);
                try std.json.stringify(s.slice(), .{}, writer);
            }
        } else {
            const s = ptrAlignCast(*const String, member);
            try std.json.stringify(s.slice(), .{}, writer);
        },
        .TYPE_BYTES => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(String), member);
            for (list.slice(), 0..) |s, i| {
                if (i != 0) _ = try writer.writeByte(',');
                try child_info.options.writeIndent(writer);
                try b64Encode(s, writer);
            }
        } else {
            const s = ptrAlignCast(*const String, member);
            try b64Encode(s.*, writer);
        },
        .TYPE_MESSAGE, .TYPE_GROUP => if (child_info.is_repeated) {
            if (!is_map) {
                const list = ptrAlignCast(*const List(*Message), member);
                for (list.slice(), 0..) |subm, i| {
                    if (i != 0) _ = try writer.writeByte(',');
                    try child_info.options.writeIndent(writer);
                    try serializeImpl(subm, writer, child_info.options, arena);
                }
            } else { // is_map
                // don't write duplicate key entries. each list element
                // is a map entry type. strategy to avoid duplicates: store a
                // set of all previously written keys and iterate the list
                // backwards, skipping if key is found.
                const list = ptrAlignCast(*const List(*Message), member);
                var i = list.len - 1; // already know that len != 0
                var any_written = false;

                _ = arena.reset(.retain_capacity);
                const aalloc = arena.allocator();
                var namebuf =
                    try std.ArrayListUnmanaged(u8).initCapacity(aalloc, 256);
                var keys_written = std.StringHashMapUnmanaged(void){};
                while (true) : (i -= 1) {
                    const subm = list.items[i];
                    const desc = field.getDescriptor(MessageDescriptor);
                    const key_field = desc.fields.slice()[0];
                    assert(key_field.id == 1);
                    namebuf.items.len = 0;
                    try serializeField(
                        FieldInfo.init(
                            key_field,
                            @ptrCast([*]const u8, subm) + key_field.offset,
                            false,
                            child_info.options,
                        ),
                        namebuf.writer(aalloc),
                        arena,
                    );
                    const gop =
                        try keys_written.getOrPut(aalloc, namebuf.items);
                    if (!gop.found_existing) {
                        if (any_written)
                            _ = try writer.writeByte(',')
                        else
                            any_written = true;
                        try child_info.options.writeIndent(writer);
                        try serializeImpl(
                            subm,
                            writer,
                            child_info.options,
                            arena,
                        );
                    }
                    if (i == 0) break;
                }
            }
        } else { // .TYPE_MESSAGE or .TYPE_GROUP non-repeated
            const subm = ptrAlignCast(*const *Message, member);
            try serializeImpl(subm.*, writer, child_info.options, arena);
        },
        .TYPE_ERROR => unreachable,
    }

    if (child_info.is_repeated and !is_map) {
        try info.options.writeIndent(writer);
        try writer.writeByte(']');
    }
}
