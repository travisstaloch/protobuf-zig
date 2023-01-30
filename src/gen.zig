const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const pb = @import("protobuf");
const common = pb.common;
const types = pb.types;
const todo = common.todo;
const plugin = pb.plugin;
const CodeGeneratorRequest = plugin.CodeGeneratorRequest;
const DescriptorProto = pb.descr.DescriptorProto;
const EnumDescriptorProto = pb.descr.EnumDescriptorProto;
const FileDescriptorProto = pb.descr.FileDescriptorProto;
const FieldDescriptorProto = pb.descr.FieldDescriptorProto;
const OneofDescriptorProto = plugin.OneofDescriptorProto;
const pbtypes = pb.pbtypes;
const FieldDescriptor = pbtypes.FieldDescriptor;
const EnumDescriptor = pbtypes.EnumDescriptor;
const extern_types = pb.extern_types;
const String = extern_types.String;
const top_level = @This();

pub const GenError = error{
    MissingDependency,
    MissingProtoFile,
    MissingMessageName,
};

const zig_extension = "pb.zig";
const ch_extension = "pb.h";
const cc_extension = "pb.c";
const pbzig_prefix = "PbZig";

fn genErr(comptime fmt: []const u8, args: anytype, err: anyerror) anyerror {
    std.log.err(fmt, args);
    return err;
}

pub fn context(
    gen_path: []const u8,
    alloc: mem.Allocator,
    req: *const CodeGeneratorRequest,
) Context {
    return .{
        .gen_path = gen_path,
        .alloc = alloc,
        .req = req,
        .zig_file = undefined,
        .ch_file = undefined,
        .cc_file = undefined,
    };
}

pub const Node = union(enum) {
    enum_: *const EnumDescriptorProto,
    message: *const DescriptorProto,
    named: String,

    const Tag = std.meta.Tag(Node);

    pub fn name(n: Node) String {
        return switch (n) {
            .enum_ => |enum_| enum_.name,
            .message => |message| message.name,
            .named => |s| s,
        };
    }
};

pub const Context = struct {
    gen_path: []const u8,
    alloc: mem.Allocator,
    req: *const CodeGeneratorRequest,
    buf: [256]u8 = undefined,
    /// map from req.proto_file.(file)name to req.proto_file
    depmap: std.StringHashMapUnmanaged(*const FileDescriptorProto) = .{},
    /// map from child (enum/message pointer) to parent message.
    /// only includes nested types which have a parent - top level are excluded.
    parents: std.AutoHashMapUnmanaged(*const anyopaque, *const DescriptorProto) = .{},
    zig_file: std.fs.File,
    /// c .h file
    ch_file: std.fs.File,
    /// c .c file
    cc_file: std.fs.File,

    pub fn gen(ctx: *Context) !void {
        defer ctx.deinit();
        return top_level.gen(ctx);
    }

    pub fn deinit(ctx: *Context) void {
        ctx.zig_file.close();
        ctx.ch_file.close();
        ctx.cc_file.close();
        ctx.depmap.deinit(ctx.alloc);
        ctx.parents.deinit(ctx.alloc);
    }
};

fn writeFieldZigTypeNameHelp(
    comptime prefix: []const u8,
    file_identifier: []const u8,
    comptime suffix: []const u8,
    type_name: []const u8,
    ctx: *Context,
) !void {
    const zig_writer = ctx.zig_file.writer();
    if (file_identifier.len > 0) try zig_writer.print(
        prefix ++ "{s}.{s}" ++ suffix,
        .{ file_identifier, type_name },
    ) else try zig_writer.print(
        prefix ++ "{s}" ++ suffix,
        .{type_name},
    );
}

fn typenamesMatch(absolute_typename: []const u8, typename: []const u8) bool {
    return absolute_typename[0] == '.' and
        mem.eql(u8, absolute_typename[1..], typename);
}

/// proto_file = null means the package name won't be included
fn writeFieldCTypeName(
    comptime prefix: []const u8,
    field: *const FieldDescriptorProto,
    comptime suffix: []const u8,
    mproto_file: ?*const FileDescriptorProto,
    writer: anytype,
) !void {
    _ = try writer.write(prefix);
    if (!field.isPresentField(.type_name) and field.isPresentField(.type)) {
        _ = try writer.write(scalarFieldCTypeName(field));
    } else {
        const package = if (mproto_file) |pf| pf.package else String.empty;
        try writeCName(writer, package, .{ .named = field.type_name }, null, null);
    }
    _ = try writer.write(suffix);
}

fn writeFieldZigTypeName(
    comptime prefix: []const u8,
    field: *const FieldDescriptorProto,
    comptime suffix: []const u8,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    const field_typename = field.type_name.slice();
    if (!field.isPresentField(.type_name) and field.isPresentField(.type)) {
        const type_name = scalarFieldZigTypeName(field);
        return writeFieldZigTypeNameHelp(prefix, "", suffix, type_name, ctx);
    }

    // search for the typename in deps
    // TODO - should this maybe should be limited to only certain deps?
    const file_identifier = outer: for (ctx.req.proto_file.slice()) |pf| {
        if (pf == proto_file) continue;
        for (pf.message_type.slice()) |it| {
            if (typenamesMatch(field_typename, it.name.slice())) {
                const names = try filePackageNames(pf.name, &ctx.buf);
                break :outer names[0];
            }
        }
        for (pf.enum_type.slice()) |it| {
            if (typenamesMatch(field_typename, it.name.slice())) {
                const names = try filePackageNames(pf.name, &ctx.buf);
                break :outer names[0];
            }
        }
    } else "";

    // if within same package, remove leading '.package.'
    if (proto_file.isPresentField(.package)) {
        const package = proto_file.package.slice();
        if (mem.startsWith(u8, field_typename[1..], package)) {
            const type_name = field_typename[2 + proto_file.package.len ..];
            return writeFieldZigTypeNameHelp(
                prefix,
                file_identifier,
                suffix,
                type_name,
                ctx,
            );
        }
    }

    const type_name = field_typename[1..];
    try writeFieldZigTypeNameHelp(prefix, file_identifier, suffix, type_name, ctx);
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
    assert(field.isPresentField(.default_value));
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
        .TYPE_MESSAGE => try writeFieldZigTypeName("*", field, "", proto_file, ctx),
        .TYPE_ENUM => try writeFieldZigTypeName("", field, "", proto_file, ctx),
        else => _ = try zig_writer.write(scalarFieldZigTypeName(field)),
    }
    if (is_list) _ = try zig_writer.write(")");
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

pub fn genMessageCTypedef(
    message: *const DescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    for (message.enum_type.slice()) |enum_type|
        try genEnumC(enum_type, proto_file, ctx);

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
        try genMessageCTypedef(nested, proto_file, ctx);
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
        try writeSplitDottedIdent(package, writer, toUpper);
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
        try writeParentNames(parent, writer, ctx.?);
    }

    // write name
    try writeTitleCase(writer, node.name());
}

pub fn genMessageC(
    message: *const DescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    for (message.nested_type.slice()) |nested|
        try genMessageC(nested, proto_file, ctx);

    const node: Node = .{ .message = message };
    { // genMessageCHeader
        const ch_writer = ctx.ch_file.writer();

        // gen struct decl
        _ = try ch_writer.write("\nstruct ");
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write(" {\n");

        // gen struct fields
        _ = try ch_writer.write("PbZigMessage base;\n");
        for (message.field.slice()) |field| {
            if (field.isPresentField(.oneof_index)) continue;
            try writeCFieldType(field, null, ch_writer);
            _ = try ch_writer.write(" ");
            const field_name = field.name.slice();
            try ch_writer.print("{s};\n", .{field_name});
        }

        // gen oneof union fields separately because they are grouped by field.oneof_index
        for (message.oneof_decl.slice()) |_, i| {
            _ = try ch_writer.write("union {\n");
            for (message.field.slice()) |field| {
                if (field.isPresentField(.oneof_index) and field.oneof_index == i) {
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
            if (field.isPresentField(.oneof_index)) continue;
            if (nwritten != 0) _ = try ch_writer.write(", \\\n");
            if (field.isPresentField(.default_value)) switch (field.type) {
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

        // gen default value decls
        for (message.field.slice()) |field| {
            if (field.isPresentField(.default_value)) {
                try writeCFieldType(field, null, ch_writer);
                _ = try ch_writer.write(" ");
                try writeCName(ch_writer, proto_file.package, node, ctx, null);
                try ch_writer.print("__{s}__default_value = ", .{
                    field.name,
                });
                if (field.type == .TYPE_ENUM) {
                    const type_name = common.splitOn([]const u8, field.type_name.slice(), '.')[1];
                    try writeTitleCase(ch_writer, String.init(type_name));
                    try ch_writer.print("__{s};\n", .{field.default_value});
                } else if (field.type == .TYPE_BOOL) {
                    try ch_writer.print("{s}{};\n", .{ pbzig_prefix, field.default_value });
                } else try ch_writer.print("{s};\n", .{fieldCDefaultValue(field)});
            }
        }

        // gen descriptor extern
        try ch_writer.print("extern const {s}MessageDescriptor ", .{pbzig_prefix});
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write("__descriptor;\n");
    }

    { // genMessageCImpl
        // gen field descriptors
        const cc_writer = ctx.cc_file.writer();
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
            if (field.isPresentField(.default_value)) {
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
                if (field.isPresentField(.oneof_index))
                    "0 | FIELD_FLAG_ONEOF"
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
        _ = try cc_writer.write(
            \\),
            \\LIST_INIT(
        );
        try writeCName(cc_writer, proto_file.package, node, ctx, null);
        _ = try cc_writer.write(
            \\__field_descriptors),
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

pub fn genMessageZig(
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
            try writeFieldZigTypeName("", field, "", proto_file, ctx);
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

    // gen field descriptors
    _ = try zig_writer.write(
        \\
        \\pub usingnamespace MessageMixins(@This());
        \\
        \\pub const field_descriptors = [_]FieldDescriptor{
        \\
    );

    for (message.field.slice()) |field| {
        const is_oneof = field.isPresentField(.oneof_index);

        _ = try zig_writer.write("FieldDescriptor.init(");
        try zig_writer.print(
            \\"{s}",
            \\{},
            \\.{s},
            \\.{s},
            \\ @offsetOf({s}, "{s}"),
            \\
        , .{
            field.name,
            field.number,
            field.label.tagName(),
            field.type.tagName(),
            message.name,
            if (is_oneof)
                message.oneof_decl.items[@intCast(usize, field.oneof_index)].name
            else
                field.name,
        });

        // descriptor arg
        switch (field.type) {
            .TYPE_MESSAGE,
            .TYPE_ENUM,
            => try writeFieldZigTypeName("&", field, ".descriptor,\n", proto_file, ctx),
            else => _ = try zig_writer.write("null,\n"),
        }

        // default value arg
        if (field.isPresentField(.default_value))
            try zig_writer.print("&{s}_default,\n", .{field.name})
        else
            _ = try zig_writer.write("null,\n");

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
    // --- end gen field descriptors

    for (message.nested_type.slice()) |nested|
        try genMessageZig(nested, proto_file, ctx);

    for (message.enum_type.slice()) |enum_type|
        try genEnumZig(enum_type, proto_file, ctx);

    _ = try zig_writer.write("};\n");
}

pub fn genMessageTest(
    message: *const DescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    // TODO roundtrip ser/de tests
    const zig_writer = ctx.zig_file.writer();
    const names = try filePackageNames(proto_file.name, &ctx.buf);
    try zig_writer.print(
        \\
        \\test {{ // dummy test for typechecking
        \\std.testing.log_level = .err; // suppress 'required field' warnings
        \\_ = {s}.
    , .{names[0]});
    const node: Node = .{ .message = message };
    try writeCName(zig_writer, proto_file.package, node, ctx, null);

    // \\var ctx = pb.protobuf.context("", std.testing.allocator);
    // \\const mm = ctx.deserialize(&{s}.descriptor) catch null;
    // \\if (mm) |m| m.deinit(std.testing.allocator);
    _ = try zig_writer.write(
        \\;
        \\}
        \\
    );
}

/// recursively write parent.name + '__'
fn writeParentNames(
    parent: *const DescriptorProto,
    writer: anytype,
    ctx: *Context,
) !void {
    if (ctx.parents.get(parent)) |pparent|
        try writeParentNames(pparent, writer, ctx);

    _ = try writer.write(parent.name.slice());
    _ = try writer.write("__");
}

/// writes ident replacing '.' with '__'
fn writeSplitDottedIdent(
    ident: String,
    writer: anytype,
    mtransform_char_fn: ?*const fn (u8) u8,
) !void {
    const name = mem.trimLeft(u8, ident.slice(), ".");
    var spliter = mem.split(u8, name, ".");
    var i: u16 = 0;
    while (spliter.next()) |namepart| : (i += 1) {
        if (i != 0) _ = try writer.write("__");
        if (mtransform_char_fn) |txfn| {
            for (namepart) |c| _ = try writer.writeByte(txfn(c));
        } else _ = try writer.write(namepart);
    }
}

/// mtransform_char_fn can be used change bytes - ie to convert case.
fn writeCName(
    writer: anytype,
    package: String,
    node: Node,
    ctx: ?*Context,
    mtransform_char_fn: ?*const fn (u8) u8,
) !void {
    // write package
    if (package.len > 0) {
        try writeSplitDottedIdent(package, writer, mtransform_char_fn);
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
        try writeParentNames(parent, writer, ctx.?);
    }

    // write name
    try writeSplitDottedIdent(node.name(), writer, mtransform_char_fn);
}

const isUpper = std.ascii.isUpper;
const toLower = std.ascii.toLower;
const toUpper = std.ascii.toUpper;

/// convert from camelCase to snake_case
fn writeSnakeCase(writer: anytype, name: String) !void {
    var was_upper = true;
    for (name.slice()) |c| {
        const is_upper = isUpper(c);
        if (is_upper) {
            if (!was_upper)
                _ = try writer.write("_");
            _ = try writer.writeByte(toLower(c));
        } else {
            _ = try writer.writeByte(c);
        }
        was_upper = is_upper;
    }
}

/// convert from camelCase to TITLE_CASE
fn writeTitleCase(writer: anytype, name: String) !void {
    var was_upper = true;
    for (name.slice()) |c| {
        const is_upper = isUpper(c);
        if (is_upper) {
            if (!was_upper)
                _ = try writer.write("_");
            _ = try writer.writeByte(c);
        } else {
            _ = try writer.writeByte(toUpper(c));
        }
        was_upper = is_upper;
    }
}

pub fn genEnumC(
    enumproto: *const EnumDescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    const node: Node = .{ .enum_ = enumproto };
    { // genEnumCHeader
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
        _ = try ch_writer.write(");\n\n");

        // gen descriptor extern
        try ch_writer.print("extern const {s}EnumDescriptor ", .{pbzig_prefix});
        try writeCName(ch_writer, proto_file.package, node, ctx, null);
        _ = try ch_writer.write("__descriptor;\n");
    }
    { // genEnumCImpl
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

pub fn genEnumZig(
    enumproto: *const EnumDescriptorProto,
    ctx: anytype,
) !void {
    const bits = try std.math.ceilPowerOfTwo(usize, @max(8, std.math.log2_int_ceil(
        usize,
        @max(enumproto.value.len, 1),
    )));
    try ctx.writer.print(
        "pub const {s} = enum(u{}) {{\n",
        .{ enumproto.name, bits },
    );
    for (enumproto.value.slice()) |value| {
        try ctx.writer.print("{s} = {},\n", .{ value.name, value.number });
    }

    _ = try ctx.writer.write(
        \\
        \\pub usingnamespace EnumMixins(@This());
        \\
        \\};
    );
}

pub fn genEnumTest(
    enumproto: *const EnumDescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    // TODO roundtrip ser/de tests
    const zig_writer = ctx.zig_file.writer();
    const names = try filePackageNames(proto_file.name, &ctx.buf);
    try zig_writer.print(
        \\test {{ // dummy test for typechecking
        \\_ = {s}.
    , .{names[0]});

    try writeCName(zig_writer, proto_file.package, .{ .enum_ = enumproto }, ctx, null);
    _ = try zig_writer.write(
        \\;
        \\}
        \\
    );
}

fn normalizePackageName(package_name: []u8) void {
    for (package_name) |c, i| {
        if (c == '.' or c == '-' or c == '/')
            package_name[i] = '_';
    }
}

/// given filename = 'foo.x-yz.proto' returns ['foo_xyz', 'foo.xyz']
fn filePackageNames(filename: String, buf: []u8) ![2][]const u8 {
    const prefix = common.splitOn([]const u8, filename.slice(), '.')[0];
    mem.copy(u8, buf, prefix);
    const package_name = buf[0..prefix.len];
    normalizePackageName(package_name);
    return .{ package_name, prefix };
}

pub fn genImport(
    dep: String,
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    const zig_writer = ctx.zig_file.writer();
    // turn /a/b/c.proto info 'const c = @import("/a/b/c.pb.zig");'
    const last_dot_i = mem.lastIndexOfScalar(u8, dep.slice(), '.') orelse
        dep.len;
    // if proto_file.name() is /a/b/c and dep is /a/b/d, remove leading /a/b/
    // from the import path
    const last_slash_i = if (mem.lastIndexOfScalar(u8, dep.slice(), '/')) |i|
        i + 1
    else
        0;
    // discover and remove common path
    var i: usize = 0;
    const max = @min(last_slash_i, proto_file.name.len);
    while (i < max and dep.items[i] == proto_file.name.items[i]) : (i += 1) {}

    const ident = dep.items[last_slash_i..last_dot_i];
    const path = dep.items[i..last_dot_i];

    // if there are '/' in proto_file.name after common prefix, it means that
    // dep is in a folder above proto_file. if so, we must add a '../' for each
    // slash.
    const pfname_rest = proto_file.name.items[i..proto_file.name.len];
    const dotdot_count = mem.count(u8, pfname_rest, "/");
    // if the ident is a zig keyword, add a trailing '_'
    const is_keyword = std.zig.Token.keywords.get(ident) != null;
    const suffix = if (is_keyword) "_" else "";
    try zig_writer.print("const {s}{s} = @import(\"", .{ ident, suffix });
    var j: u8 = 0;
    while (j < dotdot_count) : (j += 1)
        _ = try zig_writer.write("../");
    try zig_writer.print("{s}.{s}\");\n", .{ path, zig_extension });
}

pub fn genPrelude(
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    { // zig imports
        const zig_writer = ctx.zig_file.writer();
        _ = try zig_writer.write(
            \\const std = @import("std");
            \\const pb = @import("protobuf");
            \\
        );
        const names = try filePackageNames(proto_file.name, &ctx.buf);
        try zig_writer.print(
            \\pub const {s} = @cImport({{
            \\    @cInclude("{s}.{s}");
            \\}});
            \\
        ,
            .{ names[0], names[1], ch_extension },
        );

        for (proto_file.dependency.slice()) |dep| {
            _ = ctx.depmap.get(dep.slice()) orelse
                return genErr(
                "missing dependency '{s}'",
                .{dep},
                error.MissingDependency,
            );
            try genImport(dep, proto_file, ctx);
        }
        _ = try zig_writer.write("\n");
    }

    { // c header includes
        const ch_writer = ctx.ch_file.writer();
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

pub fn printToAll(
    ctx: *Context,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    try ctx.zig_file.writer().print(fmt, args);
    try ctx.ch_file.writer().print(fmt, args);
    try ctx.cc_file.writer().print(fmt, args);
}
pub fn genFile(
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    try printToAll(ctx,
        \\// ---
        \\// prelude
        \\// ---
        \\
        \\
    , .{});
    try genPrelude(proto_file, ctx);

    try printToAll(ctx,
        \\
        \\// ---
        \\// typedefs
        \\// ---
        \\
        \\
    , .{});
    for (proto_file.enum_type.slice()) |enum_proto| {
        try genEnumC(enum_proto, proto_file, ctx);
    }

    for (proto_file.message_type.slice()) |desc_proto|
        try genMessageCTypedef(desc_proto, proto_file, ctx);

    try printToAll(ctx,
        \\
        \\// ---
        \\// message types
        \\// ---
        \\
        \\
    , .{});
    for (proto_file.message_type.slice()) |desc_proto| {
        try genMessageC(desc_proto, proto_file, ctx);
    }

    try printToAll(ctx,
        \\
        \\// ---
        \\// tests
        \\// ---
        \\
        \\
    , .{});
    for (proto_file.enum_type.slice()) |enum_proto| {
        try genEnumTest(enum_proto, proto_file, ctx);
    }
    for (proto_file.message_type.slice()) |desc_proto| {
        try genMessageTest(desc_proto, proto_file, ctx);
    }
}

fn filenameWithExtension(buf: []u8, filename: String, extension: []const u8) ![]const u8 {
    const split_filename = common.splitOn([]const u8, filename.slice(), '.');
    return std.fmt.bufPrint(buf, "{s}.{s}", .{ split_filename[0], extension });
}

fn createFile(ctx: *Context, file_to_gen: String, extension: []const u8) !std.fs.File {
    const filename =
        try filenameWithExtension(&ctx.buf, file_to_gen, extension);
    const filepath =
        try std.fs.path.join(ctx.alloc, &.{ ctx.gen_path, filename });
    defer ctx.alloc.free(filepath);
    const dirname = std.fs.path.dirname(filepath) orelse unreachable;
    try std.fs.cwd().makePath(dirname);
    return std.fs.cwd().createFile(filepath, .{}) catch |e|
        return genErr("error creating file '{s}'", .{filepath}, e);
}

fn populateParents(
    ctx: *Context,
    node: Node,
    mparent: ?*const DescriptorProto,
) !void {
    switch (node) {
        .named => unreachable,
        .enum_ => |enum_| try ctx.parents.putNoClobber(ctx.alloc, enum_, mparent.?),
        .message => |message| {
            // don't insert if parent == null (top level)
            if (mparent) |parent|
                try ctx.parents.putNoClobber(ctx.alloc, message, parent);
            for (message.nested_type.slice()) |nested|
                try populateParents(ctx, .{ .message = nested }, message);
            for (message.enum_type.slice()) |enum_|
                try populateParents(ctx, .{ .enum_ = enum_ }, message);
        },
    }
}

pub fn gen(ctx: *Context) !void {
    // populate depmap
    for (ctx.req.proto_file.slice()) |proto_file|
        try ctx.depmap.putNoClobber(ctx.alloc, proto_file.name.slice(), proto_file);

    // populate parents
    for (ctx.req.proto_file.slice()) |proto_file| {
        // skip top level enums - they can't have children
        for (proto_file.message_type.slice()) |message|
            try populateParents(ctx, .{ .message = message }, null);
    }

    var gendir = try std.fs.cwd().openDir("gen", .{});
    defer gendir.close();
    try std.fs.cwd().copyFile("src/protobuf-zig.h", gendir, "protobuf-zig.h", .{});
    for (ctx.req.file_to_generate.slice()) |file_to_gen| {
        // std.debug.print("filename {s} proto_file {}\n", .{ filename, proto_file });
        ctx.zig_file = try createFile(ctx, file_to_gen, zig_extension);
        ctx.ch_file = try createFile(ctx, file_to_gen, ch_extension);
        ctx.cc_file = try createFile(ctx, file_to_gen, cc_extension);

        const proto_file = ctx.depmap.get(file_to_gen.slice()) orelse
            return genErr(
            "file_to_gen '{s}' not found in req.proto_file",
            .{file_to_gen},
            error.MissingDependency,
        );
        try genFile(proto_file, ctx);
    }
}
