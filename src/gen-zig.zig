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
const top_level = @This();
const gen = @import("gen.zig");
const Context = gen.Context;
const Node = gen.Node;
const genErr = gen.genErr;
const CodeGeneratorRequest = plugin.CodeGeneratorRequest;
const DescriptorProto = pb.descr.DescriptorProto;
const EnumDescriptorProto = pb.descr.EnumDescriptorProto;
const FileDescriptorProto = pb.descr.FileDescriptorProto;
const FieldDescriptorProto = pb.descr.FieldDescriptorProto;
const OneofDescriptorProto = plugin.OneofDescriptorProto;

pub const zig_extension = "pb.zig";

fn typenamesMatch(absolute_typename: []const u8, package: []const u8, typename: []const u8) bool {
    const result = absolute_typename.len >= package.len + typename.len + 1 and
        mem.eql(u8, absolute_typename[1 .. 1 + package.len], package) and
        mem.eql(u8, absolute_typename[1 + package.len + @boolToInt(package.len > 0) ..], typename);
    return result;
}

// search recursively for a message or enum with matching typename
fn searchMessage(message: *const DescriptorProto, package: []const u8, typename: []const u8) bool {
    for (message.enum_type.slice()) |it|
        if (typenamesMatch(typename, package, it.name.slice()))
            return true;
    for (message.nested_type.slice()) |it| {
        if (typenamesMatch(typename, package, it.name.slice()) or
            searchMessage(it, package, typename))
            return true;
    }
    return false;
}

// search recursively for a message or enum with matching typename
fn searchFile(pf: *const FileDescriptorProto, typename: []const u8) bool {
    const package = pf.package.slice();
    for (pf.enum_type.slice()) |it| {
        if (typenamesMatch(typename, package, it.name.slice()))
            return true;
    }
    for (pf.message_type.slice()) |it| {
        if (typenamesMatch(typename, package, it.name.slice()) or
            searchMessage(it, package, typename))
            return true;
    }
    return false;
}

/// if field.type_name is present, asserts its not empty and starts with '.'
fn writeZigFieldTypeName(
    comptime prefix: []const u8,
    field: *const FieldDescriptorProto,
    comptime suffix: []const u8,
    proto_file: *const FileDescriptorProto,
    writer: anytype,
    ctx: *Context,
) !void {
    // scalar fields
    if (!field.isPresentField(.type_name) and field.isPresentField(.type)) {
        const type_name = scalarFieldZigTypeName(field);
        try writer.print(prefix ++ "{s}" ++ suffix, .{type_name});
        return;
    }

    const field_typename = field.type_name.slice();
    // search for the typename in deps because imported types need
    // a leading import symbol later on
    const parent_proto = for (ctx.req.proto_file.slice()) |pf| {
        if (pf == proto_file) continue;
        if (searchFile(pf, field_typename)) break pf;
    } else proto_file;

    const is_imported_typename = parent_proto != proto_file;

    // remove leading shared package names
    assert(field_typename.len > 0 and field_typename[0] == '.');
    var i: usize = 0;
    var spliter = mem.split(u8, parent_proto.package.slice(), ".");
    {
        const field_typename_ = field_typename[1..];
        while (spliter.next()) |part| {
            if (part.len == 0) continue;
            if (!mem.eql(u8, part, field_typename_[i .. i + part.len])) break;
            i += part.len + 1;
        }
    }
    const field_typename_abbrev = field_typename[i..];

    if (is_imported_typename) {
        const import_info = try gen.importInfo(parent_proto.name, proto_file);
        const ident_suffix = if (import_info.is_keyword and is_imported_typename) "_" else "";
        try writer.print(
            prefix ++ "{s}{s}{s}" ++ suffix,
            .{ import_info.ident, ident_suffix, field_typename_abbrev },
        );
    } else try writer.print(
        prefix ++ "{s}" ++ suffix,
        // first char should always be a '.' here
        .{field_typename_abbrev[1..]},
    );
}

fn scalarFieldZigTypeName(field: *const FieldDescriptorProto) []const u8 {
    return switch (field.type) {
        .TYPE_STRING => "String",
        .TYPE_INT32 => "i32",
        .TYPE_DOUBLE => "f64",
        .TYPE_FLOAT => "f32",
        .TYPE_INT64 => "i64",
        .TYPE_UINT64 => "u64",
        .TYPE_FIXED64 => "u64",
        .TYPE_FIXED32 => "u32",
        .TYPE_BOOL => "bool",
        .TYPE_UINT32 => "u32",
        .TYPE_SFIXED32 => "i32",
        .TYPE_SFIXED64 => "i64",
        .TYPE_SINT32 => "i32",
        .TYPE_SINT64 => "i64",
        .TYPE_BYTES => "pbtypes.BinaryData",
        .TYPE_MESSAGE, .TYPE_ENUM, .TYPE_ERROR, .TYPE_GROUP => {
            // std.log.err("field {} {s} {s}", .{ field.name, field.label.tagName(), field.type.tagName() });
            unreachable;
        },
    };
}

fn scalarFieldZigDefault(field: *const FieldDescriptorProto) []const u8 {
    return switch (field.type) {
        .TYPE_STRING => "String.empty",
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
        .TYPE_BOOL => "false",
        .TYPE_BYTES => ".{}",
        .TYPE_MESSAGE, .TYPE_ENUM, .TYPE_ERROR, .TYPE_GROUP => unreachable,
    };
}

fn writeZigFieldType(
    field: *const FieldDescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    const is_list = field.label == .LABEL_REPEATED;
    const zig_writer = ctx.zig_file.writer();
    if (is_list) _ = try zig_writer.write("ArrayListMut(");
    switch (field.type) {
        .TYPE_MESSAGE => try writeZigFieldTypeName("*", field, "", proto_file, zig_writer, ctx),
        .TYPE_ENUM => try writeZigFieldTypeName("", field, "", proto_file, zig_writer, ctx),
        else => _ = try zig_writer.write(scalarFieldZigTypeName(field)),
    }
    if (is_list) _ = try zig_writer.write(")");
}

pub fn genMessageTest(
    message: *const DescriptorProto,
    _: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    // TODO roundtrip ser/de tests
    const zig_writer = ctx.zig_file.writer();

    _ = try zig_writer.write(
        \\
        \\test { // dummy test for typechecking
        \\std.testing.log_level = .err; // suppress 'required field' warnings
        \\_ = 
    );
    try gen.writeParentNames(message, zig_writer, ctx, "");
    _ = try zig_writer.write(
        \\;
        \\_ = 
    );
    try gen.writeParentNames(message, zig_writer, ctx, "");
    _ = try zig_writer.write(
        \\.descriptor;
        \\}
        \\
    );
}

pub fn genMessage(
    message: *const DescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    const zig_writer = ctx.zig_file.writer();
    try zig_writer.print(
        \\
        \\pub const {s} = extern struct {{
        \\base: Message,
        \\
    , .{message.name});

    // gen fields
    for (message.field.slice()) |field| {
        if (field.isPresentField(.oneof_index)) continue;
        const field_name = field.name.slice();
        if (std.zig.Token.keywords.get(field_name) != null)
            try zig_writer.print("@\"{s}\": ", .{field_name})
        else
            try zig_writer.print("{s}: ", .{field_name});
        try writeZigFieldType(field, proto_file, ctx);
        _ = try zig_writer.write(" = ");
        if (field.label == .LABEL_REPEATED) {
            _ = try zig_writer.write(".{}");
        } else switch (field.type) {
            .TYPE_ENUM, .TYPE_MESSAGE => _ = try zig_writer.write("undefined"),
            else => _ = try zig_writer.write(scalarFieldZigDefault(field)),
        }
        _ = try zig_writer.write(",\n");
    }

    // gen oneof union fields separately because they are grouped by field.oneof_index
    for (message.oneof_decl.slice()) |oneof, i| {
        try zig_writer.print("{s}: extern union {{\n", .{oneof.name});
        for (message.field.slice()) |field| {
            if (field.isPresentField(.oneof_index) and field.oneof_index == i) {
                try zig_writer.print("{s}: ", .{field.name});
                try writeZigFieldType(field, proto_file, ctx);
                _ = try zig_writer.write(",\n");
            }
        }
        _ = try zig_writer.write("} = undefined,\n");
    }

    // gen default value decls
    for (message.field.slice()) |field| {
        if (field.isPresentField(.default_value)) {
            try zig_writer.print(
                \\pub const {s}_default: 
            , .{field.name});
            try writeZigFieldTypeName("", field, "", proto_file, zig_writer, ctx);
            switch (field.type) {
                .TYPE_ENUM => //
                try zig_writer.print(" = .{s};\n", .{field.default_value}),
                else => //
                try zig_writer.print(" = {s};\n", .{field.default_value}),
            }
        }
    }

    // gen field_ids and opt_field_ids
    _ = try zig_writer.write(
        \\
        \\pub const field_ids = [_]c_uint{
    );
    for (message.field.slice()) |field, i| {
        if (i != 0) _ = try zig_writer.write(", ");
        try zig_writer.print("{}", .{field.number});
    }
    _ = try zig_writer.write(
        \\};
        \\pub const opt_field_ids = [_]c_uint{
    );
    var nwritten: usize = 0;
    for (message.field.slice()) |field| {
        if (field.label == .LABEL_OPTIONAL) {
            if (nwritten != 0) _ = try zig_writer.write(", ");
            try zig_writer.print("{}", .{field.number});
            nwritten += 1;
        }
    }
    _ = try zig_writer.write("};\n");

    try zig_writer.print(
        \\
        \\pub usingnamespace MessageMixins(@This());
        \\
    , .{});

    try genFieldDescriptors(message, proto_file, ctx);

    for (message.nested_type.slice()) |nested|
        try genMessage(nested, proto_file, ctx);

    for (message.enum_type.slice()) |enum_type|
        try genEnum(enum_type, proto_file, ctx);

    _ = try zig_writer.write("};\n");
}

fn writeTypeName(node: Node, ctx: *Context, writer: anytype) !void {
    const mid: ?*const anyopaque = switch (node) {
        .enum_ => |x| x,
        .message => |x| x,
        .named => null,
    };

    if (mid) |id| if (ctx.parents.get(id)) |parent|
        try gen.writeParentNames(parent, writer, ctx, ".");
    _ = try writer.write(node.name().slice());
}

pub fn genFieldDescriptors(
    message: *const DescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    const zig_writer = ctx.zig_file.writer();

    _ = try zig_writer.write(
        \\pub const field_descriptors = [_]FieldDescriptor{
        \\
    );
    for (message.field.slice()) |field| {
        const is_oneof = field.isPresentField(.oneof_index);

        try zig_writer.print(
            \\FieldDescriptor.init("{s}",
            \\{},
            \\.{s},
            \\.{s},
            \\ @offsetOf(
        , .{
            field.name,
            field.number,
            field.label.tagName(),
            field.type.tagName(),
        });
        try writeTypeName(.{ .message = message }, ctx, zig_writer);
        _ = try zig_writer.print(
            \\, "{s}"),
            \\
        , .{
            if (is_oneof)
                message.oneof_decl.items[@intCast(usize, field.oneof_index)].name
            else
                field.name,
        });

        // descriptor arg
        switch (field.type) {
            .TYPE_MESSAGE,
            .TYPE_ENUM,
            => try writeZigFieldTypeName("&", field, ".descriptor,\n", proto_file, zig_writer, ctx),
            else => _ = try zig_writer.write("null,\n"),
        }

        // default value arg
        if (field.isPresentField(.default_value)) {
            _ = try zig_writer.write("&");
            try writeTypeName(.{ .message = message }, ctx, zig_writer);
            try zig_writer.print(".{s}_default,\n", .{field.name});
        } else _ = try zig_writer.write("null,\n");

        // field flags arg
        try zig_writer.print(
            \\{s},
            \\),
            \\
        , .{
            if (is_oneof)
                "@as(u8, 1)<<@enumToInt(FieldFlag.FLAG_ONEOF)"
            else
                "0",
        });
    }
    _ = try zig_writer.write("};\n");
}

pub fn genMessageTypedef(
    _: *const DescriptorProto,
    _: *const FileDescriptorProto,
    _: *Context,
) !void {}

pub fn genEnum(
    enumproto: *const EnumDescriptorProto,
    _: *const FileDescriptorProto,
    ctx: anytype,
) !void {
    const bits = try std.math.ceilPowerOfTwo(usize, @max(8, std.math.log2_int_ceil(
        usize,
        @max(enumproto.value.len, 1),
    )));
    const writer = ctx.zig_file.writer();
    try writer.print(
        "pub const {s} = enum(u{}) {{\n",
        .{ enumproto.name, bits },
    );
    for (enumproto.value.slice()) |value| {
        try writer.print("{s} = {},\n", .{ value.name, value.number });
    }

    _ = try writer.write(
        \\
        \\pub usingnamespace EnumMixins(@This());
        \\
        \\};
    );
}

pub fn genEnumTest(
    enumproto: *const EnumDescriptorProto,
    _: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    // TODO roundtrip ser/de tests
    const zig_writer = ctx.zig_file.writer();
    _ = try zig_writer.write(
        \\
        \\test { // dummy test for typechecking
        \\std.testing.log_level = .err; // suppress 'required field' warnings
        \\_ = 
    );
    try writeTypeName(.{ .enum_ = enumproto }, ctx, zig_writer);
    _ = try zig_writer.write(
        \\;}
        \\
    );
}

pub fn genPrelude(
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    // zig imports
    const zig_writer = ctx.zig_file.writer();
    _ = try zig_writer.write(
        \\const std = @import("std");
        \\const pb = @import("protobuf");
        \\const pbtypes = pb.pbtypes;
        \\const MessageDescriptor = pbtypes.MessageDescriptor;
        \\const Message = pbtypes.Message;
        \\const FieldDescriptor = pbtypes.FieldDescriptor;
        \\const EnumMixins = pbtypes.EnumMixins;
        \\const MessageMixins = pbtypes.MessageMixins;
        \\const FieldFlag = FieldDescriptor.FieldFlag;
        \\const String = pb.extern_types.String;
        \\const ArrayListMut = pb.extern_types.ArrayListMut;
        \\
    );

    for (proto_file.dependency.slice()) |dep| {
        _ = ctx.depmap.get(dep.slice()) orelse
            return genErr(
            "missing dependency '{s}'",
            .{dep},
            error.MissingDependency,
        );
        const import_info = try gen.importInfo(dep, proto_file);
        const suffix = if (import_info.is_keyword) "_" else "";
        try zig_writer.print("const {s}{s} = @import(\"", .{ import_info.ident, suffix });
        var j: u8 = 0;
        while (j < import_info.dotdot_count) : (j += 1)
            _ = try zig_writer.write("../");
        try zig_writer.print("{s}.{s}\");\n", .{ import_info.path, zig_extension });
    }
    _ = try zig_writer.write("\n");
}

pub fn genPostlude(
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    _ = proto_file;
    _ = ctx;
}
