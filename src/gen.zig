const std = @import("std");
const mem = std.mem;
const bufPrint = std.fmt.bufPrint;
const types = @import("types.zig");
const common = @import("common.zig");
const todo = common.todo;
const Message = types.Message;
const CodeGeneratorRequest = types.CodeGeneratorRequest;
const DescriptorProto = types.DescriptorProto;
const EnumDescriptorProto = types.EnumDescriptorProto;
const FileDescriptorProto = types.FileDescriptorProto;
const FieldDescriptorProto = types.FieldDescriptorProto;
const OneofDescriptorProto = types.OneofDescriptorProto;
const MessageDescriptor = types.MessageDescriptor;
const EnumDescriptor = types.EnumDescriptor;
const ArrayListMut = types.ArrayListMut;
const String = types.String;
const generator = @This();

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
    buf: [std.fs.MAX_NAME_BYTES]u8 = undefined,
    buf2: [std.fs.MAX_NAME_BYTES]u8 = undefined,
    /// map all req.proto_file from proto_file.name (filename) to proto_file
    depmap: std.StringHashMapUnmanaged(*const FileDescriptorProto) = .{},

    pub fn gen(ctx: *Self, req: *const CodeGeneratorRequest) !void {
        return generator.gen(req, ctx);
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

fn fieldTypeNameHelp(
    source_proto_file: *const FileDescriptorProto,
    found_proto_file: *const FileDescriptorProto,
    ctx: anytype,
    comptime prefix: []const u8,
    comptime suffix: []const u8,
    name: String,
) ![]const u8 {
    // if same proto_file, don't need package
    if (source_proto_file == found_proto_file)
        return bufPrint(
            &ctx.base.buf,
            prefix ++ "{s}" ++ suffix,
            .{name.slice()},
        );
    const package_names =
        try filePackageNames(found_proto_file.name, &ctx.base.buf2);
    // TODO maybe use found_proto_file.package somehow?
    return bufPrint(
        &ctx.base.buf,
        prefix ++ "{s}.{s}" ++ suffix,
        .{ package_names[0], name.slice() },
    );
}

fn fieldTypeName(
    field: *const FieldDescriptorProto,
    source_proto_file: *const FileDescriptorProto,
    ctx: anytype,
    comptime prefix: []const u8,
    comptime suffix: []const u8,
) ![]const u8 {
    // find the namespaced name of this field's type
    for (ctx.base.req.proto_file.slice()) |proto_file| {
        if (field.type == .TYPE_MESSAGE) {
            for (proto_file.message_type.slice()) |it| {
                if (mem.endsWith(u8, field.type_name.slice(), it.name.slice()))
                    return fieldTypeNameHelp(
                        source_proto_file,
                        proto_file,
                        ctx,
                        prefix,
                        suffix,
                        it.name,
                    );
            }
        } else if (field.type == .TYPE_ENUM) {
            for (proto_file.enum_type.slice()) |it| {
                if (mem.endsWith(u8, field.type_name.slice(), it.name.slice()))
                    return fieldTypeNameHelp(
                        source_proto_file,
                        proto_file,
                        ctx,
                        prefix,
                        suffix,
                        it.name,
                    );
            }
        }
    }
    return if (field.type_name.items[0] == '.')
        field.type_name.items[1..field.type_name.len]
    else
        field.type_name.slice();
    // return genErr("internal error missing type name '{s}'", .{field.type_name.slice()}, error.MissingTypeName);
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
        .TYPE_MESSAGE => unreachable,
        .TYPE_ENUM => unreachable,
        .TYPE_ERROR => unreachable,
        .TYPE_GROUP => unreachable,
        .TYPE_BYTES => "pbtypes.BinaryData",
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
        .TYPE_MESSAGE => unreachable,
        .TYPE_ENUM => unreachable,
        .TYPE_ERROR => unreachable,
        .TYPE_GROUP => unreachable,
        .TYPE_BYTES => ".{}",
    };
}

fn writeFieldType(field: *const FieldDescriptorProto, proto_file: *const FileDescriptorProto, ctx: anytype) !void {
    const is_list = field.label == .LABEL_REPEATED;
    if (is_list) _ = try ctx.writer.write("ListMut(");
    _ = try ctx.writer.write(switch (field.type) {
        .TYPE_ENUM,
        .TYPE_MESSAGE,
        => try fieldTypeName(field, proto_file, ctx, "", ""),
        else => scalarFieldZigTypeName(field),
    });

    if (is_list) try ctx.writer.writeByte(')');
}

pub fn genMessage(
    message: *const DescriptorProto,
    proto_file: *const FileDescriptorProto,
    ctx: anytype,
) !void {
    // std.debug.print("message {}\n", .{message});
    try ctx.writer.print(
        \\
        \\pub const {s} = extern struct {{
        \\base: Message,
        \\
    , .{message.name.slice()});
    for (message.field.slice()) |field| {
        if (field.isPresentField(.oneof_index)) continue;
        try ctx.writer.print("{s}: ", .{field.name.slice()});
        try writeFieldType(field, proto_file, ctx);
        _ = try ctx.writer.write(" = ");
        if (field.label == .LABEL_REPEATED) {
            try writeFieldType(field, proto_file, ctx);
            _ = try ctx.writer.write(".initEmpty()");
        } else _ = try ctx.writer.write(switch (field.type) {
            .TYPE_ENUM => "undefined",
            .TYPE_MESSAGE => ".{}",
            else => scalarFieldZigDefault(field),
        });
        _ = try ctx.writer.write(",\n");
    }
    // gen oneof union fields separately
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
            // WARNING - do not change the order of 'type_name' and 'default',
            // otherwise ctx.base.buf will get clobbered
            const type_name_ =
                try fieldTypeName(field, proto_file, ctx, "", "");
            mem.copy(u8, &ctx.base.buf2, type_name_);
            const type_name = ctx.base.buf2[0..type_name_.len];

            const default = switch (field.type) {
                .TYPE_ENUM => //
                try bufPrint(&ctx.base.buf, ".{s}", .{field.default_value.slice()}),
                else => todo("default {s}", .{field.type.tagName()}),
            };
            try ctx.writer.print(
                \\pub const {s}_default: {s} = {s};
                \\
            , .{ field.name.slice(), type_name, default });
        }
    }

    _ = try ctx.writer.write(
        \\
        \\pub usingnamespace MessageMixins(@This());
        \\
        \\pub const field_descriptors = [_]FieldDescriptor{
        \\
    );

    for (message.field.slice()) |field| {
        const descriptor: []const u8 = switch (field.type) {
            .TYPE_MESSAGE,
            .TYPE_ENUM,
            => try fieldTypeName(field, proto_file, ctx, "&", ".descriptor"),
            else => "null",
        };
        const default = if (field.isPresentField(.default_value))
            try bufPrint(&ctx.base.buf2, "&{s}_default", .{field.name.slice()})
        else
            "null";
        const is_oneof = field.isPresentField(.oneof_index);
        const flags = if (is_oneof)
            "@as(u8, 1)<<@enumToInt(FieldFlag.FLAG_ONEOF)"
        else
            "0";
        try ctx.writer.print(
            \\FieldDescriptor.init(
            \\"{s}",
            \\{},
            \\.{s},
            \\.{s},
            \\ @offsetOf({s}, "{s}"),
            \\{s},
            \\{s},
            \\{s},
            \\),
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
            descriptor,
            default,
            flags,
        });
    }

    _ = try ctx.writer.write("};\n");

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
    // FIXME calculate Int size - don't just use u8 here
    try ctx.writer.print("pub const {s} = enum(u8) {{\n", .{enumproto.name.slice()});
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
    try ctx.writer.print(
        \\
        \\test {{ // dummy test just for typechecking
        \\std.testing.log_level = .err; // suppress 'required field' warnings
        \\var ctx = pb.context("", std.testing.allocator);
        \\const mm = ctx.deserialize(&{s}.descriptor) catch null;
        \\if (mm) |m| m.deinit(std.testing.allocator);
        \\}}
        \\
    , .{message.name.slice()});
}

/// given filename = 'foo.x-yz.proto' returns ['foo_xyz', 'foo.xyz']
fn filePackageNames(filename: String, buf: []u8) ![2][]const u8 {
    const prefix = common.splitOn([]const u8, filename.slice(), '.')[0];
    mem.copy(u8, buf, prefix);
    const package_name = buf[0..prefix.len];
    for (package_name) |c, i| {
        if (c == '.' or c == '-' or c == '/') buf[i] = '_';
    }
    return .{ package_name, prefix };
}

pub fn genImport(dep: String, ctx: anytype) !void {
    const names = try filePackageNames(dep, &ctx.base.buf);
    const package_name = names[0];
    try ctx.writer.print("const {s} = @import(\"", .{package_name});
    const filename = try bufPrint(
        &ctx.base.buf,
        "{s}.{s}",
        .{ names[1], pb_zig_ext },
    );
    try ctx.writer.print("{s}\");\n", .{filename});
}

pub fn genPrelude(
    proto_file: *const FileDescriptorProto,
    ctx: anytype,
) !void {
    _ = try ctx.writer.write(
        \\const std = @import("std");
        \\const pbtypes = @import("protobuf-types");
        \\const pb = @import("protobuf");
        \\const String = pbtypes.String;
        \\const ListMut = pbtypes.ListMut;
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
    return bufPrint(buf, "{s}.{s}", .{ split_filename[0], extension });
}

pub fn gen(req: *const CodeGeneratorRequest, ctx: *Context) !void {
    // populate depmap
    for (req.proto_file.slice()) |proto_file|
        try ctx.depmap.putNoClobber(ctx.alloc, proto_file.name.slice(), proto_file);

    // std.debug.print("req {}\n", .{req});
    for (req.proto_file.slice()) |proto_file| {
        const filename =
            try filenameWithExtension(&ctx.buf, proto_file.name, pb_zig_ext);
        const filepath =
            try std.fs.path.join(ctx.alloc, &.{ ctx.gen_path, filename });
        const dirname = std.fs.path.dirname(filepath) orelse unreachable;
        try std.fs.cwd().makePath(dirname);
        const file = std.fs.cwd().createFile(filepath, .{}) catch |e|
            return genErr("error creating file '{s}'", .{filepath}, e);
        defer file.close();
        // std.debug.print("filename {s} proto_file {}\n", .{ filename, proto_file });
        var with_writer = ctx.withWriter(file.writer());
        try genFile(proto_file, &with_writer);
    }
}
