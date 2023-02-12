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

const FieldWriteOptions = struct {
    fmt: []const u8 = "{}",
};

fn serializeFieldImpl(
    info: FieldInfo,
    comptime T: type,
    writer: anytype,
    comptime options: FieldWriteOptions,
) !void {
    if (info.is_repeated) {
        const list = ptrAlignCast(*const List(T), info.member);
        for (list.slice()) |int, i| {
            if (i != 0) _ = try writer.writeByte(',');
            try info.options.writeIndent(writer);
            try writer.print(options.fmt, .{int});
        }
        var info_ = info;
        if (info_.options.pretty_print) |*opp| opp.indent_level -= 1;
        try info_.options.writeIndent(writer);
    } else {
        try writer.print(
            options.fmt,
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
) Error!void {
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
        assert(mem.eql(u8, "key", key_field.name.slice()));
        if (key_field.type != .TYPE_STRING)
            _ = try writer.write("\"");
        try serializeField(
            FieldInfo.init(
                key_field,
                buf.ptr + key_field.offset,
                false,
                true,
                child_options,
            ),
            writer,
        );
        if (key_field.type != .TYPE_STRING)
            _ = try writer.write("\":")
        else
            _ = try writer.write(":");
        if (child_options.pretty_print != null) _ = try writer.write(" ");
        const value_field = desc.fields.slice()[1];
        assert(mem.eql(u8, "value", value_field.name.slice()));
        try serializeField(
            FieldInfo.init(
                value_field,
                buf.ptr + value_field.offset,
                false,
                true,
                child_options,
            ),
            writer,
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
        if (child_options.pretty_print != null) _ = try writer.write(" ");
        const is_map = field.descriptor != null and
            (field.type == .TYPE_MESSAGE or field.type == .TYPE_GROUP) and
            flagsContain(
            field.getDescriptor(MessageDescriptor).flags,
            MessageDescriptor.Flag.FLAG_MAP_TYPE,
        );

        try serializeField(
            FieldInfo.init(
                field,
                buf.ptr + field.offset,
                is_repeated,
                is_map,
                child_options,
            ),
            writer,
        );
    }
    if (any_written) try options.writeIndent(writer);
    _ = try writer.writeAll("}");
}

pub const FieldInfo = struct {
    field: FieldDescriptor,
    member: [*]const u8,
    is_repeated: bool,
    is_map: bool,
    options: Options,

    pub fn init(
        field: FieldDescriptor,
        member: [*]const u8,
        is_repeated: bool,
        is_map: bool,
        options: Options,
    ) FieldInfo {
        return .{
            .field = field,
            .member = member,
            .is_repeated = is_repeated,
            .is_map = is_map,
            .options = options,
        };
    }
};

fn serializeField(
    info: FieldInfo,
    writer: anytype,
) !void {
    var child_info = info;
    if (child_info.is_repeated and !child_info.is_map) {
        try writer.writeByte('[');
        if (child_info.options.pretty_print) |*cpp| cpp.indent_level += 1;
    }
    const field = child_info.field;
    const member = child_info.member;

    switch (field.type) {
        .TYPE_INT32,
        .TYPE_SINT32,
        .TYPE_SFIXED32,
        => try serializeFieldImpl(child_info, i32, writer, .{}),
        .TYPE_UINT32,
        .TYPE_FIXED32,
        => try serializeFieldImpl(child_info, u32, writer, .{}),
        .TYPE_BOOL => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(u32), member);
            for (list.slice()) |int, i| {
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
                for (list.slice()) |int, i| {
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
        => try serializeFieldImpl(child_info, i64, writer, .{}),
        .TYPE_UINT64,
        .TYPE_FIXED64,
        => try serializeFieldImpl(child_info, u64, writer, .{}),
        .TYPE_FLOAT => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(f32), member);
            for (list.slice()) |int, i| {
                if (i != 0) _ = try writer.writeByte(',');
                try child_info.options.writeIndent(writer);
                try std.json.stringify(int, .{}, writer);
            }
        } else {
            const v = @bitCast(f32, mem.readIntLittle(u32, member[0..4]));
            try std.json.stringify(v, .{}, writer);
        },
        .TYPE_DOUBLE => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(f64), member);
            for (list.slice()) |int, i| {
                if (i != 0) _ = try writer.writeByte(',');
                try child_info.options.writeIndent(writer);
                try std.json.stringify(int, .{}, writer);
            }
        } else {
            const v = @bitCast(f64, mem.readIntLittle(u64, member[0..8]));
            try std.json.stringify(v, .{}, writer);
        },
        .TYPE_STRING => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(String), member);
            for (list.slice()) |s, i| {
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
            for (list.slice()) |s, i| {
                if (i != 0) _ = try writer.writeByte(',');
                try child_info.options.writeIndent(writer);
                try b64Encode(s, writer);
            }
        } else {
            const s = ptrAlignCast(*const String, member);
            try b64Encode(s.*, writer);
        },
        .TYPE_MESSAGE, .TYPE_GROUP => if (child_info.is_repeated) {
            const list = ptrAlignCast(*const List(*Message), member);
            for (list.slice()) |subm, i| {
                if (i != 0) _ = try writer.writeByte(',');
                try child_info.options.writeIndent(writer);
                try serialize(subm, writer, child_info.options);
            }
        } else {
            const subm = ptrAlignCast(*const *Message, member);
            try serialize(subm.*, writer, child_info.options);
        },
        .TYPE_ERROR => unreachable,
    }

    if (child_info.is_repeated and !child_info.is_map) {
        try info.options.writeIndent(writer);
        try writer.writeByte(']');
    }
}
