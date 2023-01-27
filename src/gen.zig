const std = @import("std");
const mem = std.mem;
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
    };
}

pub const Context = struct {
    const Self = @This();

    gen_path: []const u8,
    alloc: mem.Allocator,
    req: *const CodeGeneratorRequest,
    buf: [256]u8 = undefined,
    /// map from req.proto_file.(file)name to req.proto_file
    depmap: std.StringHashMapUnmanaged(*const FileDescriptorProto) = .{},

    pub fn gen(ctx: *Self, req: *const CodeGeneratorRequest) !void {
        return top_level.gen(req, ctx);
    }

    pub fn withWriter(ctx: Self, writer: anytype) WithWriter(@TypeOf(writer)) {
        return WithWriter(@TypeOf(writer)){
            .writer = writer,
            .base = ctx,
        };
    }
    pub fn WithWriter(comptime Writer: type) type {
        return struct {
            writer: Writer,
            base: Context,
        };
    }
};

fn writeFieldTypeNameHelp(
    comptime prefix: []const u8,
    file_identifier: []const u8,
    comptime suffix: []const u8,
    type_name: []const u8,
    ctx: anytype,
) !void {
    if (file_identifier.len > 0) try ctx.writer.print(
        prefix ++ "{s}.{s}" ++ suffix,
        .{ file_identifier, type_name },
    ) else try ctx.writer.print(
        prefix ++ "{s}" ++ suffix,
        .{type_name},
    );
}

fn typenamesMatch(absolute_typename: []const u8, typename: []const u8) bool {
    return absolute_typename[0] == '.' and
        mem.eql(u8, absolute_typename[1..], typename);
}

fn writeFieldTypeName(
    comptime prefix: []const u8,
    field: *const FieldDescriptorProto,
    comptime suffix: []const u8,
    proto_file: *const FileDescriptorProto,
    ctx: anytype,
) !void {
    const field_typename = field.type_name.slice();
    if (!field.isPresentField(.type_name) and field.isPresentField(.type)) {
        const type_name = scalarFieldZigTypeName(field);
        return writeFieldTypeNameHelp(prefix, "", suffix, type_name, ctx);
    }

    // search for the typename in deps
    // TODO - should this maybe should be limited to only certain deps?
    const file_identifier = outer: for (ctx.base.req.proto_file.slice()) |pf| {
        if (pf == proto_file) continue;
        for (pf.message_type.slice()) |it| {
            if (typenamesMatch(field_typename, it.name.slice())) {
                const names = try filePackageNames(pf.name, &ctx.base.buf);
                break :outer names[0];
            }
        }
        for (pf.enum_type.slice()) |it| {
            if (typenamesMatch(field_typename, it.name.slice())) {
                const names = try filePackageNames(pf.name, &ctx.base.buf);
                break :outer names[0];
            }
        }
    } else "";

    // if within same package, remove leading '.package.'
    if (proto_file.isPresentField(.package)) {
        const package = proto_file.package.slice();
        if (mem.startsWith(u8, field_typename[1..], package)) {
            const type_name = field_typename[2 + proto_file.package.len ..];
            return writeFieldTypeNameHelp(
                prefix,
                file_identifier,
                suffix,
                type_name,
                ctx,
            );
        }
    }

    const type_name = field_typename[1..];
    try writeFieldTypeNameHelp(prefix, file_identifier, suffix, type_name, ctx);
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

fn writeFieldType(
    field: *const FieldDescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: anytype,
) !void {
    const is_list = field.label == .LABEL_REPEATED;
    if (is_list) _ = try ctx.writer.write("ArrayListMut(");
    switch (field.type) {
        .TYPE_MESSAGE => try writeFieldTypeName("*", field, "", proto_file, ctx),
        .TYPE_ENUM => try writeFieldTypeName("", field, "", proto_file, ctx),
        else => _ = try ctx.writer.write(scalarFieldZigTypeName(field)),
    }
    if (is_list) _ = try ctx.writer.write(")");
}

pub fn genMessage(
    message: *const DescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: anytype,
) !void {
    try ctx.writer.print(
        \\
        \\pub const {s} = extern struct {{
        \\base: Message,
        \\
    , .{message.name.slice()});

    // gen fields
    for (message.field.slice()) |field| {
        if (field.isPresentField(.oneof_index)) continue;
        const field_name = field.name.slice();
        if (std.zig.Token.keywords.get(field_name) != null)
            try ctx.writer.print("@\"{s}\": ", .{field_name})
        else
            try ctx.writer.print("{s}: ", .{field_name});
        try writeFieldType(field, proto_file, ctx);
        _ = try ctx.writer.write(" = ");
        if (field.label == .LABEL_REPEATED) {
            _ = try ctx.writer.write(".{}");
        } else switch (field.type) {
            .TYPE_ENUM, .TYPE_MESSAGE => _ = try ctx.writer.write("undefined"),
            else => _ = try ctx.writer.write(scalarFieldZigDefault(field)),
        }
        _ = try ctx.writer.write(",\n");
    }

    // gen oneof union fields separately because they are grouped by field.oneof_index
    for (message.oneof_decl.slice()) |oneof, i| {
        try ctx.writer.print("{s}: extern union {{\n", .{oneof.name.slice()});
        for (message.field.slice()) |field| {
            if (field.isPresentField(.oneof_index) and field.oneof_index == i) {
                try ctx.writer.print("{s}: ", .{field.name.slice()});
                try writeFieldType(field, proto_file, ctx);
                _ = try ctx.writer.write(",\n");
            }
        }
        _ = try ctx.writer.write("} = undefined,\n");
    }

    // gen default value decls
    for (message.field.slice()) |field| {
        if (field.isPresentField(.default_value)) {
            try ctx.writer.print(
                \\pub const {s}_default: 
            , .{field.name.slice()});
            try writeFieldTypeName("", field, "", proto_file, ctx);
            switch (field.type) {
                .TYPE_ENUM => //
                try ctx.writer.print(" = .{s};\n", .{field.default_value.slice()}),
                else => //
                try ctx.writer.print(" = {s};\n", .{field.default_value.slice()}),
            }
        }
    }

    // gen field_ids and opt_field_ids
    _ = try ctx.writer.write(
        \\
        \\pub const field_ids = [_]c_uint{
    );
    for (message.field.slice()) |field, i| {
        if (i != 0) _ = try ctx.writer.write(", ");
        try ctx.writer.print("{}", .{field.number});
    }
    _ = try ctx.writer.write(
        \\};
        \\pub const opt_field_ids = [_]c_uint{
    );
    var nwritten: usize = 0;
    for (message.field.slice()) |field| {
        if (field.label == .LABEL_OPTIONAL) {
            if (nwritten != 0) _ = try ctx.writer.write(", ");
            try ctx.writer.print("{}", .{field.number});
            nwritten += 1;
        }
    }
    _ = try ctx.writer.write("};\n");

    // gen field descriptors
    _ = try ctx.writer.write(
        \\
        \\pub usingnamespace MessageMixins(@This());
        \\
        \\pub const field_descriptors = [_]FieldDescriptor{
        \\
    );

    for (message.field.slice()) |field| {
        const is_oneof = field.isPresentField(.oneof_index);
        const is_recursive_type = false;
        // try pbtypes.isRecursiveType(field.type_name.slice(), message, ctx);
        if (is_recursive_type)
            _ = try ctx.writer.write("FieldDescriptor.initRecursive(")
        else
            _ = try ctx.writer.write("FieldDescriptor.init(");
        try ctx.writer.print(
            \\"{s}",
            \\{},
            \\.{s},
            \\.{s},
            \\ @offsetOf({s}, "{s}"),
            \\
        , .{
            field.name.slice(),
            field.number,
            field.label.tagName(),
            field.type.tagName(),
            message.name.slice(),
            if (is_oneof)
                message.oneof_decl.items[@intCast(usize, field.oneof_index)].name.slice()
            else
                field.name.slice(),
        });

        // descriptor arg
        if (is_recursive_type)
            _ = try ctx.writer.write("null,\n")
        else switch (field.type) {
            .TYPE_MESSAGE,
            .TYPE_ENUM,
            => try writeFieldTypeName("&", field, ".descriptor,\n", proto_file, ctx),
            else => _ = try ctx.writer.write("null,\n"),
        }

        // default value arg
        if (field.isPresentField(.default_value))
            try ctx.writer.print("&{s}_default,\n", .{field.name.slice()})
        else
            _ = try ctx.writer.write("null,\n");

        // field flags arg
        try ctx.writer.print(
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
    _ = try ctx.writer.write("};\n");
    // --- end gen field descriptors

    for (message.nested_type.slice()) |nested|
        try genMessage(nested, proto_file, ctx);

    for (message.enum_type.slice()) |enum_type|
        try genEnum(enum_type, ctx);

    _ = try ctx.writer.write("};\n");
}

pub fn genEnum(
    enumproto: *const EnumDescriptorProto,
    ctx: anytype,
) !void {
    const bits = try std.math.ceilPowerOfTwo(usize, @max(8, std.math.log2_int_ceil(
        usize,
        @max(enumproto.value.len, 1),
    )));
    try ctx.writer.print(
        "pub const {s} = enum(u{}) {{\n",
        .{ enumproto.name.slice(), bits },
    );
    for (enumproto.value.slice()) |value| {
        try ctx.writer.print("{s} = {},\n", .{ value.name.slice(), value.number });
    }

    _ = try ctx.writer.write(
        \\
        \\pub usingnamespace EnumMixins(@This());
        \\
        \\};
    );
}

pub fn genMessageTest(
    message: *const DescriptorProto,
    ctx: anytype,
) !void {
    // TODO roundtrip ser/de tests
    try ctx.writer.print(
        \\
        \\test {{ // dummy test for typechecking
        \\std.testing.log_level = .err; // suppress 'required field' warnings
        \\var ctx = pb.protobuf.context("", std.testing.allocator);
        \\const mm = ctx.deserialize(&{s}.descriptor) catch null;
        \\if (mm) |m| m.deinit(std.testing.allocator);
        \\}}
        \\
    , .{message.name.slice()});
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

pub fn genImport(dep: String, ctx: anytype) !void {
    const names = try filePackageNames(dep, &ctx.base.buf);
    try ctx.writer.print(
        "const {s} = @import(\"{s}.{s}\");\n",
        .{ names[0], names[1], pb_zig_ext },
    );
}

pub fn genPrelude(
    proto_file: *const FileDescriptorProto,
    ctx: anytype,
) !void {
    _ = try ctx.writer.write(
        \\const std = @import("std");
        \\const pb = @import("protobuf");
        \\const extern_types = pb.extern_types;
        \\const String = extern_types.String;
        \\const ArrayListMut = extern_types.ArrayListMut;
        \\const ArrayList = extern_types.ArrayList;
        \\const pbtypes = pb.pbtypes;
        \\const EnumMixins = pbtypes.EnumMixins;
        \\const MessageMixins = pbtypes.MessageMixins;
        \\const FieldDescriptor = pbtypes.FieldDescriptor;
        \\const Message = pbtypes.Message;
        \\const FieldFlag = FieldDescriptor.FieldFlag;
        \\
    );
    for (proto_file.dependency.slice()) |dep| {
        _ = ctx.base.depmap.get(dep.slice()) orelse
            return genErr(
            "missing dependency '{s}'",
            .{dep.slice()},
            error.MissingDependency,
        );
        try genImport(dep, ctx);
    }
    _ = try ctx.writer.write("\n");
}
pub fn genFile(
    proto_file: *const FileDescriptorProto,
    ctx: anytype,
) !void {
    try genPrelude(proto_file, ctx);
    for (proto_file.enum_type.slice()) |enum_proto| {
        try genEnum(enum_proto, ctx);
    }
    for (proto_file.message_type.slice()) |desc_proto| {
        try genMessage(desc_proto, proto_file, ctx);
    }
    for (proto_file.message_type.slice()) |desc_proto| {
        try genMessageTest(desc_proto, ctx);
    }
}

const pb_zig_ext = "pb.zig";
fn filenameWithExtension(buf: []u8, filename: String, extension: []const u8) ![]const u8 {
    const split_filename = common.splitOn([]const u8, filename.slice(), '.');
    return std.fmt.bufPrint(buf, "{s}.{s}", .{ split_filename[0], extension });
}

pub fn gen(req: *const CodeGeneratorRequest, ctx: *Context) !void {
    // populate depmap
    for (req.proto_file.slice()) |proto_file|
        try ctx.depmap.putNoClobber(ctx.alloc, proto_file.name.slice(), proto_file);

    for (req.file_to_generate.slice()) |file_to_gen| {
        const filename =
            try filenameWithExtension(&ctx.buf, file_to_gen, pb_zig_ext);
        const filepath =
            try std.fs.path.join(ctx.alloc, &.{ ctx.gen_path, filename });
        const dirname = std.fs.path.dirname(filepath) orelse unreachable;
        try std.fs.cwd().makePath(dirname);
        const file = std.fs.cwd().createFile(filepath, .{}) catch |e|
            return genErr("error creating file '{s}'", .{filepath}, e);
        defer file.close();
        // std.debug.print("filename {s} proto_file {}\n", .{ filename, proto_file });
        var with_writer = ctx.withWriter(file.writer());
        const proto_file = ctx.depmap.get(file_to_gen.slice()) orelse
            return genErr(
            "file_to_gen '{s}' not found in req.proto_file",
            .{file_to_gen.slice()},
            error.MissingDependency,
        );
        try genFile(proto_file, &with_writer);
    }
}
