const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const pb = @import("protobuf");
const common = pb.common;
const types = pb.types;
const todo = common.todo;
const plugin = pb.plugin;
const pbtypes = pb.pbtypes;
const extern_types = pb.extern_types;
const String = extern_types.String;
const gen = @import("gen.zig");
const Context = gen.Context;
const Node = gen.Node;
const writeSplitIdent = gen.writeSplitIdent;
const writeTitleCase = gen.writeTitleCase;
const writeFileIdent = gen.writeFileIdent;
const CodeGeneratorRequest = plugin.CodeGeneratorRequest;
const DescriptorProto = pb.descr.DescriptorProto;
const EnumDescriptorProto = pb.descr.EnumDescriptorProto;
const FileDescriptorProto = pb.descr.FileDescriptorProto;
const FieldDescriptorProto = pb.descr.FieldDescriptorProto;
const OneofDescriptorProto = plugin.OneofDescriptorProto;
const top_level = @This();

pub const pbzig_prefix = "PbZig";
pub const ch_extension = "pb.h";
pub const cc_extension = "pb.c";

/// proto_file = null means the package name won't be included
fn writeFieldCTypeName(
    comptime prefix: []const u8,
    field: *const FieldDescriptorProto,
    comptime suffix: []const u8,
    mproto_file: ?*const FileDescriptorProto,
    writer: anytype,
) !void {
    _ = try writer.write(prefix);
    if (!field.has(.type_name) and field.has(.type)) {
        _ = try writer.write(scalarFieldCTypeName(field));
    } else {
        const package = if (mproto_file) |pf| pf.package else String.empty;
        try writeCName(writer, package, .{ .named = field.type_name }, null, null);
    }
    _ = try writer.write(suffix);
}

fn scalarFieldCTypeName(field: *const FieldDescriptorProto) []const u8 {
    return switch (field.type) {
        .TYPE_BYTES, .TYPE_STRING => "PbZigString",
        .TYPE_INT32 => "int32_t",
        .TYPE_DOUBLE => "double",
        .TYPE_FLOAT => "float",
        .TYPE_INT64 => "int64_t",
        .TYPE_UINT64 => "uint64_t",
        .TYPE_FIXED64 => "uint64_t",
        .TYPE_FIXED32 => "uint32_t",
        .TYPE_BOOL => "uint8_t",
        .TYPE_UINT32 => "uint32_t",
        .TYPE_SFIXED32 => "int32_t",
        .TYPE_SFIXED64 => "int64_t",
        .TYPE_SINT32 => "int32_t",
        .TYPE_SINT64 => "int64_t",
        .TYPE_MESSAGE, .TYPE_ENUM, .TYPE_ERROR, .TYPE_GROUP => {
            // std.log.err("field {} {s} {s}", .{ field.name, field.label.tagName(), field.type.tagName() });
            unreachable;
        },
    };
}

fn scalarFieldCDefault(field: *const FieldDescriptorProto) []const u8 {
    return switch (field.type) {
        .TYPE_BYTES, .TYPE_STRING => "PbZigString_empty",
        .TYPE_INT32,
        .TYPE_DOUBLE,
        .TYPE_FLOAT,
        .TYPE_INT64,
        .TYPE_UINT64,
        .TYPE_FIXED64,
        .TYPE_FIXED32,
        .TYPE_UINT32,
        .TYPE_SFIXED32,
        .TYPE_SFIXED64,
        .TYPE_SINT32,
        .TYPE_SINT64,
        => "0",
        .TYPE_BOOL => "PbZigfalse",
        .TYPE_MESSAGE, .TYPE_ENUM, .TYPE_ERROR, .TYPE_GROUP => unreachable,
    };
}

/// doesn't handle TYPE_{ENUM,BOOL,MESSAGE,ERROR,GROUP}
fn fieldCDefaultValue(field: *const FieldDescriptorProto) []const u8 {
    assert(field.has(.default_value));
    return switch (field.type) {
        .TYPE_BYTES,
        .TYPE_STRING,
        .TYPE_INT32,
        .TYPE_DOUBLE,
        .TYPE_FLOAT,
        .TYPE_INT64,
        .TYPE_UINT64,
        .TYPE_FIXED64,
        .TYPE_FIXED32,
        .TYPE_UINT32,
        .TYPE_SFIXED32,
        .TYPE_SFIXED64,
        .TYPE_SINT32,
        .TYPE_SINT64,
        => field.default_value.slice(),
        .TYPE_BOOL, .TYPE_ENUM, .TYPE_MESSAGE, .TYPE_ERROR, .TYPE_GROUP => std.debug.panic(
            "fieldCDefault() invalid type .{s} value '{s}'",
            .{ field.type.tagName(), field.default_value },
        ),
    };
}

/// appends 'List' suffix for list types, '*' for single message types
fn writeCFieldType(
    field: *const FieldDescriptorProto,
    proto_file: ?*const FileDescriptorProto,
    writer: anytype,
) !void {
    const is_list = field.label == .LABEL_REPEATED;
    if (is_list) {
        try writeFieldCTypeName("", field, "", proto_file, writer);
        _ = try writer.write("List ");
    } else switch (field.type) {
        .TYPE_MESSAGE => try writeFieldCTypeName("", field, "*", proto_file, writer),
        .TYPE_ENUM => try writeFieldCTypeName("", field, "", proto_file, writer),
        else => _ = try writer.write(scalarFieldCTypeName(field)),
    }
}

pub fn genMessageTypedef(
    message: *const DescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    for (message.enum_type.slice()) |enum_type|
        try genEnum(enum_type, proto_file, ctx);

    // gen 'typdef name name;'
    const ch_writer = ctx.ch_file.writer();
    _ = try ch_writer.write("typedef struct ");
    const node: Node = .{ .message = message };
    try writeCName(ch_writer, proto_file.package, node, ctx, null);

    _ = try ch_writer.write(" ");
    try writeCName(ch_writer, proto_file.package, node, ctx, null);
    _ = try ch_writer.write(";\n");

    // gen 'LIST_DEF(nameList, name *);'
    _ = try ch_writer.write("LIST_DEF(");
    try writeCName(ch_writer, proto_file.package, node, ctx, null);
    _ = try ch_writer.write("List, ");
    try writeCName(ch_writer, proto_file.package, node, ctx, null);
    _ = try ch_writer.write(" *);\n");

    for (message.nested_type.slice()) |nested|
        try genMessageTypedef(nested, proto_file, ctx);
}

/// writes a name like this: GOOGLE__PROTOBUF__FILE_DESCRIPTOR_SET
fn writeCMacroName(
    writer: anytype,
    package: String,
    node: Node,
    ctx: ?*Context,
) !void {
    // write package
    if (package.len > 0) {
        try writeSplitIdent(package, writer, gen.toUpper, ".", "__");
        _ = try writer.write("__");
    }

    // write 'parent names'.
    // nested messages and enums have 'parent names' which need to be included.
    // field names (.named) are absolute and don't need parent names included.
    if (switch (node) {
        .enum_ => |ptr| @ptrCast(?*const anyopaque, ptr),
        .message => |ptr| @ptrCast(?*const anyopaque, ptr),
        .named => null,
    }) |id| blk: {
        const parent = ctx.?.parents.get(id) orelse break :blk;
        try gen.writeParentNames(parent, writer, ctx.?, "__");
    }

    // write name
    try writeTitleCase(writer, node.name());
}

pub fn genMessage(
    message: *const DescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    for (message.nested_type.slice()) |nested|
        try genMessage(nested, proto_file, ctx);

    const node: Node = .{ .message = message };
    { // genMessageHeader
        const ch_writer = ctx.ch_file.writer();

        // gen struct decl
        _ = try ch_writer.write("\nstruct ");
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write(" {\n");

        // gen struct fields
        _ = try ch_writer.write("PbZigMessage base;\n");
        for (message.field.slice()) |field| {
            if (field.has(.oneof_index)) continue;
            try writeCFieldType(field, null, ch_writer);
            _ = try ch_writer.write(" ");
            const field_name = field.name.slice();
            try ch_writer.print("{s};\n", .{field_name});
        }

        // gen oneof union fields separately because they are grouped by field.oneof_index
        for (message.oneof_decl.slice()) |_, i| {
            _ = try ch_writer.write("union {\n");
            for (message.field.slice()) |field| {
                if (field.has(.oneof_index) and field.oneof_index == i) {
                    try writeCFieldType(field, null, ch_writer);
                    try ch_writer.print(" {s};\n", .{field.name});
                }
            }
            _ = try ch_writer.write("};\n");
        }

        _ = try ch_writer.write("};\n\n");

        // -- gen message init
        _ = try ch_writer.write("#define ");
        try writeCMacroName(ch_writer, proto_file.package, node, ctx);
        _ = try ch_writer.write(
            \\__INIT { \
            \\PBZIG_MESSAGE_INIT(&
        );

        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write(
            \\__descriptor), \
            \\
        );

        var nwritten: usize = 0;
        for (message.field.slice()) |field| {
            if (field.has(.oneof_index)) continue;
            if (nwritten != 0) _ = try ch_writer.write(", \\\n");
            if (field.has(.default_value)) switch (field.type) {
                .TYPE_ENUM => _ = {
                    const type_name = common.splitOn([]const u8, field.type_name.slice(), '.')[1];
                    try writeTitleCase(ch_writer, String.init(type_name));
                    try ch_writer.print("__{s}", .{field.default_value});
                },
                .TYPE_BOOL => _ = try ch_writer.print(
                    "{s}{s}",
                    .{ pbzig_prefix, field.default_value },
                ),
                else => _ = try ch_writer.write(field.default_value.slice()),
            } else if (field.label == .LABEL_REPEATED)
                _ = try ch_writer.write("List_empty")
            else switch (field.type) {
                // TODO find and use first enum field
                .TYPE_ENUM => _ = try ch_writer.write("0"), // FIXME wrong
                .TYPE_MESSAGE => _ = try ch_writer.write("NULL"),
                else => _ = try ch_writer.write(scalarFieldCDefault(field)),
            }
            nwritten += 1;
        }
        _ = try ch_writer.write(
            \\}
            \\
            \\
        );
        // -- end gen message init

        // gen descriptor extern
        try ch_writer.print("extern const {s}MessageDescriptor ", .{pbzig_prefix});
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write("__descriptor;\n");
    }

    { // genMessageImpl

        const cc_writer = ctx.cc_file.writer();
        // gen default value decls
        for (message.field.slice()) |field| {
            if (field.has(.default_value)) {
                try writeCFieldType(field, null, cc_writer);
                _ = try cc_writer.write(" ");
                try writeCName(cc_writer, proto_file.package, node, ctx, null);
                try cc_writer.print("__{s}__default_value = ", .{
                    field.name,
                });
                if (field.type == .TYPE_ENUM) {
                    const type_name = common.splitOn([]const u8, field.type_name.slice(), '.')[1];
                    try writeTitleCase(cc_writer, String.init(type_name));
                    try cc_writer.print("__{s};\n", .{field.default_value});
                } else if (field.type == .TYPE_BOOL) {
                    try cc_writer.print("{s}{};\n", .{ pbzig_prefix, field.default_value });
                } else try cc_writer.print("{s};\n", .{fieldCDefaultValue(field)});
            }
        }

        // gen field descriptors
        try cc_writer.print(
            \\
            \\
            \\static const {s}FieldDescriptor 
        , .{pbzig_prefix});
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        try cc_writer.print(
            \\__field_descriptors[{}] = {{
            \\
        , .{message.field.len});
        for (message.field.slice()) |field| {
            try cc_writer.print(
                \\{{
                \\STRING_INIT("{s}"),
                \\{},
                \\{s},
                \\{s},
                \\offsetof(
            , .{
                field.name,
                field.number,
                field.label.tagName(),
                field.type.tagName(),
            });
            try writeCName(cc_writer, proto_file.package, node, ctx, null);
            try cc_writer.print(
                \\, {s}),
                \\
            , .{field.name});

            // descriptor arg
            switch (field.type) {
                .TYPE_MESSAGE,
                .TYPE_ENUM,
                => try writeFieldCTypeName("&", field, "__descriptor,\n", null, cc_writer),
                else => _ = try cc_writer.write("NULL,\n"),
            }

            // default value arg
            if (field.has(.default_value)) {
                _ = try cc_writer.write("&");
                try writeCName(cc_writer, proto_file.package, node, ctx, null);
                try cc_writer.print("__{s}__default_value,\n", .{field.name});
            } else _ = try cc_writer.write("NULL,\n");

            // field flags arg
            try cc_writer.print(
                \\{s},
                \\}},
                \\
            , .{
                if (field.has(.oneof_index))
                    "0 | FIELD_FLAG_ONEOF"
                else if (field.has(.options) and field.options.@"packed")
                    "0 | FIELD_FLAG_PACKED"
                else
                    "0",
            });
        }

        // gen init()
        _ = try cc_writer.write(
            \\};
            \\
            \\
            \\void 
        );
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write("__init(");
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write(
            \\ *message) {
            \\static const 
        );
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write(" init_value = ");
        try writeCMacroName(cc_writer, proto_file.package, node, ctx);
        _ = try cc_writer.write(
            \\__INIT;
            \\*message = init_value;
            \\}
            \\
            \\
        );

        // gen field_ids and opt_field_ids
        _ = try cc_writer.write("\nstatic const uint32_t ");
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        try cc_writer.print("__field_ids[{}] = {{ ", .{message.field.len});
        for (message.field.slice()) |field, i| {
            if (i != 0) _ = try cc_writer.write(", ");
            try cc_writer.print("{}", .{field.number});
        }
        _ = try cc_writer.write(" };\nstatic const uint32_t ");
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        var opt_fields_len: u32 = 0;
        for (message.field.slice()) |field| opt_fields_len += @boolToInt(field.label == .LABEL_OPTIONAL);
        try cc_writer.print("__opt_field_ids[{}] = {{ ", .{opt_fields_len});
        var nwritten: usize = 0;
        for (message.field.slice()) |field| {
            if (field.label == .LABEL_OPTIONAL) {
                if (nwritten != 0) _ = try cc_writer.write(", ");
                try cc_writer.print("{}", .{field.number});
                nwritten += 1;
            }
        }
        _ = try cc_writer.write(" };\n");

        // gen descriptor
        _ = try cc_writer.write("const PbZigMessageDescriptor ");
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        try cc_writer.print(
            \\__descriptor = {{
            \\MESSAGE_DESCRIPTOR_MAGIC,
            \\STRING_INIT("{s}.{s}"),
            \\STRING_INIT("{s}"),
            \\STRING_INIT("
        , .{
            proto_file.package,
            message.name,
            message.name,
        });
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        try cc_writer.print(
            \\"),
            \\STRING_INIT("{s}"),
            \\sizeof(
        , .{
            proto_file.package,
        });

        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write("),\nLIST_INIT(");
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write("__field_descriptors),\nLIST_INIT(");
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write("__field_ids),\nLIST_INIT(");
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write(
            \\__opt_field_ids),
            \\(PbZigMessageInit) 
        );
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write(
            \\__init,
            \\NULL,
            \\NULL,
            \\NULL,
            \\};
            \\
            \\
        );
    }
}

/// mtransform_char_fn can be used change bytes - ie to convert case.
pub fn writeCName(
    writer: anytype,
    package: String,
    node: Node,
    ctx: ?*Context,
    mtransform_char_fn: ?*const fn (u8) u8,
) !void {
    // write package
    if (package.len > 0) {
        try writeSplitIdent(package, writer, mtransform_char_fn, ".", "__");
        _ = try writer.write("__");
    }

    // write 'parent names'.
    // nested messages and enums have 'parent names' which need to be included.
    // field names (.named) are absolute and don't need parent names included.
    if (switch (node) {
        .enum_ => |ptr| @ptrCast(?*const anyopaque, ptr),
        .message => |ptr| @ptrCast(?*const anyopaque, ptr),
        .named => null,
    }) |id| blk: {
        const parent = ctx.?.parents.get(id) orelse break :blk;
        try gen.writeParentNames(parent, writer, ctx.?, "__");
    }

    // write name
    try writeSplitIdent(node.name(), writer, mtransform_char_fn, ".", "__");
}

pub fn genEnum(
    enumproto: *const EnumDescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    const node: Node = .{ .enum_ = enumproto };
    { // genEnumHeader
        const ch_writer = ctx.ch_file.writer();
        _ = try ch_writer.write("typedef enum _");
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write(" {\n");
        for (enumproto.value.slice()) |value| {
            try writeTitleCase(ch_writer, enumproto.name);
            try ch_writer.print("__{s} = {},\n", .{ value.name, value.number });
        }

        _ = try ch_writer.write("} ");
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write(";\n");

        // gen 'LIST_DEF(nameList, name);'
        _ = try ch_writer.write("LIST_DEF(");
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write("List, ");
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write(" );\n\n");

        // gen descriptor extern
        try ch_writer.print("extern const {s}EnumDescriptor ", .{pbzig_prefix});
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write("__descriptor;\n");
    }
    { // genEnumImpl
        const cc_writer = ctx.cc_file.writer();
        // gen enum_values_by_number
        _ = try cc_writer.write("static const PbZigEnumValue ");
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.print("__enum_values_by_number[{}] = {{\n", .{enumproto.value.len});

        for (enumproto.value.slice()) |value| {
            try cc_writer.print(
                \\{{ STRING_INIT("{s}"), STRING_INIT("
            , .{
                value.name,
            });
            try writeTitleCase(cc_writer, enumproto.name);
            try cc_writer.print(
                \\__{s}"), {} }},
                \\
            , .{
                value.name,
                value.number,
            });
        }
        _ = try cc_writer.write("};\n\n");

        // gen descriptor
        _ = try cc_writer.write("const PbZigEnumDescriptor ");
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        try cc_writer.print(
            \\__descriptor = {{
            \\ENUM_DESCRIPTOR_MAGIC,
            \\STRING_INIT("{s}.{s}"),
            \\STRING_INIT("{s}"),
            \\STRING_INIT("
        , .{
            proto_file.package,
            enumproto.name,
            enumproto.name,
        });
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        try cc_writer.print(
            \\"),
            \\STRING_INIT("{s}"),
            \\LIST_INIT(
        , .{
            proto_file.package,
        });
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write(
            \\__enum_values_by_number),
            \\NULL,
            \\NULL,
            \\NULL,
            \\NULL,
            \\};
            \\
            \\
        );
    }
}

pub fn genEnumTest(
    _: *const EnumDescriptorProto,
    _: *const FileDescriptorProto,
    _: *Context,
) !void {}
pub fn genMessageTest(
    _: *const DescriptorProto,
    _: *const FileDescriptorProto,
    _: *Context,
) !void {}

pub fn genPrelude(
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    { // c header includes
        const ch_writer = ctx.ch_file.writer();
        _ = try ch_writer.write("#ifndef PROTOBUF_ZIG_");
        try writeFileIdent(ctx, proto_file, ch_writer);
        _ = try ch_writer.write("__INCLUDED\n");
        _ = try ch_writer.write("#define PROTOBUF_ZIG_");
        try writeFileIdent(ctx, proto_file, ch_writer);
        _ = try ch_writer.write("__INCLUDED\n");

        _ = try ch_writer.write("#include <protobuf-zig.h>\n");
        for (proto_file.dependency.slice()) |dep| {
            const parts = common.splitOn([]const u8, dep.slice(), '.');
            try ch_writer.print(
                \\#include "{s}.{s}"
                \\
            , .{ parts[0], ch_extension });
        }
    }

    { // c impl includes
        const wholename = proto_file.name.slice();
        const last_dot_i = mem.lastIndexOfScalar(u8, wholename, '.') orelse wholename.len;
        const last_dot_i2 = mem.lastIndexOfScalar(u8, wholename[0..last_dot_i], '.') orelse 0;
        const name = wholename[last_dot_i2..last_dot_i];
        const cc_writer = ctx.cc_file.writer();
        _ = try cc_writer.print(
            \\#include "{s}.{s}"
            \\
        , .{ name, ch_extension });
    }
}

pub fn genPostlude(
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    const ch_writer = ctx.ch_file.writer();
    _ = try ch_writer.write("#endif // PROTOBUF_ZIG_");
    try writeFileIdent(ctx, proto_file, ch_writer);
}
