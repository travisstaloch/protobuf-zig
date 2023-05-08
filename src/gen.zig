const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const pb = @import("protobuf");
const common = pb.common;
const types = pb.types;
const todo = common.todo;
const plugin = pb.plugin;
const descr = pb.descriptor;
const CodeGeneratorRequest = plugin.CodeGeneratorRequest;
const CodeGeneratorResponse = plugin.CodeGeneratorResponse;
const DescriptorProto = descr.DescriptorProto;
const EnumDescriptorProto = descr.EnumDescriptorProto;
const FileDescriptorProto = descr.FileDescriptorProto;
const FieldDescriptorProto = descr.FieldDescriptorProto;
const OneofDescriptorProto = plugin.OneofDescriptorProto;
const FieldDescriptor = types.FieldDescriptor;
const EnumDescriptor = types.EnumDescriptor;
const extern_types = pb.extern_types;
const String = extern_types.String;
const top_level = @This();
const genc = @import("gen-c.zig");
const genzig = @import("gen-zig.zig");
const log = common.log;

const output_format = @import("build_options").output_format;

pub const generator = if (output_format == .zig)
    genzig
else
    genc;

pub const GenError = error{
    MissingDependency,
    MissingProtoFile,
    MissingMessageName,
};

pub fn genErr(comptime fmt: []const u8, args: anytype, err: anyerror) anyerror {
    log.err(fmt, args);
    return err;
}

pub fn context(
    alloc: mem.Allocator,
    req: *const CodeGeneratorRequest,
) Context {
    return .{
        .alloc = alloc,
        .req = req,
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
    alloc: mem.Allocator,
    req: *const CodeGeneratorRequest,
    buf: [256]u8 = undefined,
    /// map from req.proto_file.(file)name to req.proto_file
    depmap: std.StringHashMapUnmanaged(*const FileDescriptorProto) = .{},
    /// map from child (enum/message pointer) to parent message.
    /// only includes nested types which have a parent - top level are excluded.
    parents: std.AutoHashMapUnmanaged(*const anyopaque, *const DescriptorProto) = .{},
    output: std.ArrayListUnmanaged(u8) = .{},
    enum_buf: std.ArrayListUnmanaged(i32) = .{},

    pub fn gen(ctx: *Context) !CodeGeneratorResponse {
        defer ctx.deinit();
        return top_level.gen(ctx);
    }

    pub fn deinit(ctx: *Context) void {
        ctx.depmap.deinit(ctx.alloc);
        ctx.parents.deinit(ctx.alloc);
        ctx.enum_buf.deinit(ctx.alloc);
    }
};

pub const isUpper = std.ascii.isUpper;
pub const toLower = std.ascii.toLower;
pub const toUpper = std.ascii.toUpper;

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
pub fn writeTitleCase(writer: anytype, name: String) !void {
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

fn normalizePackageName(package_name: []u8) void {
    for (package_name, 0..) |c, i| {
        if (c == '.' or c == '-' or c == '/')
            package_name[i] = '_';
    }
}

const ImportInfo = struct {
    ident: []const u8,
    path: []const u8,
    is_keyword: bool,
    dotdot_count: usize,
};

pub fn importInfo(
    dep: String,
    proto_file: *const FileDescriptorProto,
) !ImportInfo {
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
    const is_keyword = std.zig.Token.keywords.get(ident) != null or
        types.reserved_words.get(ident) != null;

    return .{ .ident = ident, .path = path, .is_keyword = is_keyword, .dotdot_count = dotdot_count };
}

/// writes ident replacing 'delim' with 'delim_replacement'
pub fn writeSplitIdent(
    ident: String,
    writer: anytype,
    mtransform_char_fn: ?*const fn (u8) u8,
    delim: []const u8,
    delim_replacement: []const u8,
) !void {
    const name = mem.trimLeft(u8, ident.slice(), delim);
    var spliter = mem.split(u8, name, delim);
    var i: u16 = 0;
    while (spliter.next()) |namepart| : (i += 1) {
        if (i != 0) _ = try writer.write(delim_replacement);
        if (mtransform_char_fn) |txfn| {
            for (namepart) |c| _ = try writer.writeByte(txfn(c));
        } else _ = try writer.write(namepart);
    }
}

pub fn writeFileIdent(ctx: *Context, proto_file: *const FileDescriptorProto, writer: anytype) !void {
    try writeSplitIdent(String.init(ctx.gen_path), writer, null, "/", "_");
    _ = try writer.write("_");
    const pname = proto_file.name.slice();
    const last_dot_i = mem.lastIndexOfScalar(u8, pname, '.') orelse pname.len;
    try writeSplitIdent(String.init(pname[0..last_dot_i]), writer, null, "/", "_");
}

/// recursively write parent.name + delimeter
pub fn writeParentNames(
    parent: *const DescriptorProto,
    writer: anytype,
    ctx: *Context,
    delimeter: []const u8,
) !void {
    if (ctx.parents.get(parent)) |pparent|
        try writeParentNames(pparent, writer, ctx, delimeter);

    _ = try writer.write(parent.name.slice());
    _ = try writer.write(delimeter);
}

pub fn printToAll(
    ctx: *Context,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const writer = ctx.output.writer(ctx.alloc);
    _ = try writer.print(fmt, args);
}
pub fn printBanner(
    ctx: *Context,
    comptime fmt: []const u8,
) !void {
    try printToAll(ctx,
        \\
        \\// ---
        \\// 
    ++ fmt ++
        \\
        \\// ---
        \\
        \\
    , .{});
}

pub fn genFile(
    proto_file: *const FileDescriptorProto,
    ctx: *Context,
) !void {
    try printBanner(ctx, "prelude");
    try generator.genPrelude(proto_file, ctx);

    try printBanner(ctx, "typedefs");
    for (proto_file.enum_type.slice()) |enum_proto| {
        try generator.genEnum(enum_proto, proto_file, ctx);
    }

    for (proto_file.message_type.slice()) |desc_proto|
        try generator.genMessageTypedef(desc_proto, proto_file, ctx);

    try printBanner(ctx, "message types");
    for (proto_file.message_type.slice()) |desc_proto| {
        try generator.genMessage(desc_proto, proto_file, ctx);
    }

    try printBanner(ctx, "tests");
    for (proto_file.enum_type.slice()) |enum_proto| {
        try generator.genEnumTest(enum_proto, proto_file, ctx);
    }
    for (proto_file.message_type.slice()) |desc_proto| {
        try generator.genMessageTest(desc_proto, proto_file, ctx);
    }
    try generator.genPostlude(proto_file, ctx);
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

pub fn genPopulateMaps(ctx: *Context) !void {
    // populate depmap
    for (ctx.req.proto_file.slice()) |proto_file|
        try ctx.depmap.putNoClobber(ctx.alloc, proto_file.name.slice(), proto_file);

    // populate parents
    for (ctx.req.proto_file.slice()) |proto_file| {
        // skip top level enums - they can't have children
        for (proto_file.message_type.slice()) |message|
            try populateParents(ctx, .{ .message = message }, null);
    }
}

pub fn gen(ctx: *Context) !CodeGeneratorResponse {
    var res = CodeGeneratorResponse.init();
    try genPopulateMaps(ctx);
    res.set(.supported_features, @intCast(u64, @enumToInt(CodeGeneratorResponse.Feature.FEATURE_PROTO3_OPTIONAL)));

    if (output_format == .c) {
        log.err("TODO support output_format == .c", .{});
        return error.Todo;
    }

    for (ctx.req.file_to_generate.slice()) |file_to_gen| {
        const proto_file = ctx.depmap.get(file_to_gen.slice()) orelse
            return genErr(
            "file_to_gen '{s}' not found in req.proto_file",
            .{file_to_gen},
            error.MissingDependency,
        );
        ctx.output.items.len = 0;
        try genFile(proto_file, ctx);
        var file = try ctx.alloc.create(CodeGeneratorResponse.File);
        file.* = CodeGeneratorResponse.File.init();
        try ctx.output.append(ctx.alloc, 0);
        const tree = try std.zig.Ast.parse(ctx.alloc, ctx.output.items[0 .. ctx.output.items.len - 1 :0], .zig);
        const formatted_source = try tree.render(ctx.alloc);
        file.set(.content, String.init(formatted_source));
        if (!mem.endsWith(u8, file_to_gen.slice(), ".proto")) return error.NonProtoFile;
        const pb_zig_filename = try mem.concat(ctx.alloc, u8, &.{
            file_to_gen.items[0 .. file_to_gen.len - ".proto".len],
            ".pb.zig",
        });
        file.set(.name, String.init(pb_zig_filename));
        try res.file.append(ctx.alloc, file);
    }
    return res;
}
