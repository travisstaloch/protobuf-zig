const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const pb = @import("protobuf");
const plugin = pb.plugin;
const types = pb.types;
const WireType = types.WireType;
const Tag = types.Tag;
const extern_types = pb.extern_types;
const List = extern_types.ArrayList;
const ListMut = extern_types.ArrayListMut;
const String = extern_types.String;
const Message = types.Message;
const MessageDescriptor = types.MessageDescriptor;
const FieldDescriptor = types.FieldDescriptor;
const FieldFlag = FieldDescriptor.FieldFlag;
const descr = pb.descriptor;
const FieldDescriptorProto = descr.FieldDescriptorProto;
const flagsContain = types.flagsContain;
const common = pb.common;
const ptrAlignCast = common.ptrAlignCast;
const ptrfmt = common.ptrfmt;
const todo = common.todo;
const afterLastIndexOf = common.afterLastIndexOf;
const top_level = @This();

pub const LocalError = error{
    InvalidTag,
    NotEnoughBytesRead,
    Overflow,
    FieldMissing,
    RequiredFieldMissing,
    SubMessageMissing,
    DescriptorMissing,
    InvalidType,
    InvalidData,
    InvalidMessageType,
    InternalError,
    UnsupportedListElementSize,
};

pub const Error = std.mem.Allocator.Error ||
    std.fs.File.WriteFileError ||
    LocalError;

/// Reads a varint from the reader and returns the value.  `mode = .sint` should
/// be used when expecting lots of negative numbers as it uses zig zag encoding
/// to reduce the size of negative values. negatives encoded otherwise (with
/// `mode = .int`).  will require extra size (10 bytes each) and are
/// inefficient.
/// adapted from https://github.com/mlugg/zigpb/blob/main/protobuf.zig#decodeVarInt()
/// zigzag notes: https://gist.github.com/mfuerstenau/ba870a29e16536fdbaba
pub fn readVarint128(comptime T: type, reader: anytype, comptime mode: IntMode) !T {
    var shift: u7 = 0;
    var value: u128 = 0;
    while (true) {
        const b = try reader.readByte();
        value |= @as(u128, @truncate(u7, b)) << shift;
        if (b >> 7 == 0) break;
        shift += 7;
    }
    if (mode == .sint) {
        const U = std.meta.Int(.unsigned, @bitSizeOf(T));
        const S = std.meta.Int(.signed, @bitSizeOf(T));
        const v = @truncate(U, value);
        return (v >> 1) ^ @bitCast(U, -@bitCast(S, v & 1));
    }
    return switch (@typeInfo(T).Int.signedness) {
        .signed => @truncate(T, @bitCast(i128, value)),
        .unsigned => @truncate(T, value),
    };
}

/// Writes a varint to the writer.
/// `mode = .sint` should be used when expecting lots of negative values
/// adapted from https://github.com/mlugg/zigpb/blob/main/protobuf.zig#encodeVarInt()
pub fn writeVarint128(comptime T: type, _value: T, writer: anytype, comptime mode: IntMode) !void {
    var value = _value;

    if (mode == .sint) {
        value = (value >> (@bitSizeOf(T) - 1)) ^ (value << 1);
    }
    if (value == 0) {
        try writer.writeByte(0);
        return;
    }
    const U = std.meta.Int(.unsigned, @bitSizeOf(T));
    // try std.leb.writeULEB128(writer, @bitCast(U, value));
    var x = @bitCast(U, value);
    while (x != 0) {
        const lopart: u8 = @truncate(u7, x);
        x >>= 7;
        const hipart = @as(u8, 0b1000_0000) * @boolToInt(x != 0);
        try writer.writeByte(hipart | lopart);
    }
}

pub const IntMode = enum { sint, int };

pub fn context(data: []const u8, allocator: Allocator) Ctx {
    return Ctx.init(data, allocator);
}

pub fn repeatedEleSize(t: FieldDescriptorProto.Type) u8 {
    return switch (t) {
        .TYPE_SINT32,
        .TYPE_INT32,
        .TYPE_UINT32,
        .TYPE_SFIXED32,
        .TYPE_FIXED32,
        .TYPE_FLOAT,
        .TYPE_ENUM,
        .TYPE_BOOL,
        => 4,
        .TYPE_SINT64,
        .TYPE_INT64,
        .TYPE_UINT64,
        .TYPE_SFIXED64,
        .TYPE_FIXED64,
        .TYPE_DOUBLE,
        => 8,
        .TYPE_STRING, .TYPE_BYTES => @sizeOf(pb.extern_types.String),
        .TYPE_MESSAGE, .TYPE_GROUP => @sizeOf(*Message),
        .TYPE_ERROR => unreachable,
    };
}

const Ctx = struct {
    data: []const u8,
    data_start: []const u8,
    allocator: Allocator,
    // TODO add an arena or other allocator for temporary data

    pub fn init(data: []const u8, allocator: Allocator) Ctx {
        return .{
            .data = data,
            .allocator = allocator,
            .data_start = data,
        };
    }

    pub fn withData(ctx: Ctx, data: []const u8) Ctx {
        var res = ctx;
        res.data = data;
        res.data_start = data;
        return res;
    }

    // TODO maybe remove this, store fbs in ctx instead of recreating it?
    pub fn fbs(ctx: Ctx) std.io.FixedBufferStream([]const u8) {
        return std.io.fixedBufferStream(ctx.data);
    }

    pub fn bytesRead(ctx: Ctx) usize {
        return @ptrToInt(ctx.data.ptr) - @ptrToInt(ctx.data_start.ptr);
    }

    pub fn skip(ctx: *Ctx, len: u32) !void {
        if (len > ctx.data.len) return error.NotEnoughBytesRead;
        ctx.data = ctx.data[len..];
    }

    pub fn deserialize(ctx: *Ctx, mdesc: *const MessageDescriptor) Error!*Message {
        return top_level.deserialize(mdesc, ctx);
    }

    /// Read a varint from the ctx.data and returns the value. updates ctx,
    /// skipping the read bytes
    pub fn readVarint128(ctx: *Ctx, comptime T: type, comptime mode: IntMode) !T {
        var ctxfbs = ctx.fbs();
        const reader = ctxfbs.reader();
        const value = try top_level.readVarint128(T, reader, mode);
        try ctx.skip(@intCast(u32, ctxfbs.pos));
        return value;
    }

    pub fn readTag(ctx: *Ctx) !Tag {
        const tag = try ctx.readVarint128(u32, .int);
        return Tag{
            .wire_type = std.meta.intToEnum(WireType, tag & 0b111) catch {
                std.log.err("readTag() invalid wire_type {}. tag {}:0x{x}:0b{b:0>8} field_id {}", .{ @truncate(u3, tag), tag, tag, tag, tag >> 3 });
                return error.InvalidTag;
            },
            .field_id = tag >> 3,
        };
    }

    pub fn scanLengthPrefixedData(ctx: *Ctx) ![2]u32 {
        const startlen = @intCast(u32, ctx.data.len);
        const len = try ctx.readVarint128(u32, .int);
        return .{ startlen - @intCast(u32, ctx.data.len), len };
    }
};

fn structMemberPtr(comptime T: type, message: *Message, offset: usize) *T {
    return ptrAlignCast(*T, @ptrCast([*]u8, message) + offset);
}

fn genericMessageInit(desc: *const MessageDescriptor) Message {
    var message = std.mem.zeroes(Message);
    message.descriptor = desc;
    for (desc.fields.slice()) |field| {
        std.log.debug(
            "genericMessageInit field name {s} default {} label {s}",
            .{ field.name, ptrfmt(field.default_value), @tagName(field.label) },
        );
        if (field.default_value != null and field.label != .LABEL_REPEATED) {
            var field_bytes = @ptrCast([*]u8, &message) + field.offset;
            const default = @ptrCast([*]const u8, field.default_value);
            switch (field.type) {
                .TYPE_INT32,
                .TYPE_SINT32,
                .TYPE_SFIXED32,
                .TYPE_UINT32,
                .TYPE_FIXED32,
                .TYPE_FLOAT,
                .TYPE_ENUM,
                .TYPE_BOOL,
                => @memcpy(field_bytes[0..4], default[0..4]),
                .TYPE_INT64,
                .TYPE_SINT64,
                .TYPE_SFIXED64,
                .TYPE_UINT64,
                .TYPE_FIXED64,
                .TYPE_DOUBLE,
                => @memcpy(field_bytes[0..8], default[0..8]),
                .TYPE_STRING,
                .TYPE_BYTES,
                => @memcpy(field_bytes[0..@sizeOf(String)], default[0..@sizeOf(String)]),
                .TYPE_MESSAGE => { //
                    if (true) @panic("TODO - TYPE_STRING/MESSAGE default_value");
                    mem.writeIntLittle(usize, field_bytes[0..8], @ptrToInt(field.default_value));
                    const ptr = @intToPtr(?*anyopaque, @bitCast(usize, field_bytes[0..8].*));
                    std.log.debug("genericMessageInit() string/message ptr {} field.default_value {}", .{ ptrfmt(ptr), ptrfmt(field.default_value) });
                    assert(ptr == field.default_value);
                },
                else => unreachable,
            }
        }
    }
    return message;
}

fn intRangeLookup(field_ids: List(c_uint), value: usize) !usize {
    for (field_ids.slice(), 0..) |num, i|
        if (num == value) return i;
    return error.NotFound;
}

const ScannedMember = struct {
    tag: Tag,
    field: ?*const FieldDescriptor,
    data: [*]const u8,
    data_len: u32,
    prefix_len: u32 = 0,

    pub fn readVarint128(
        sm: ScannedMember,
        comptime T: type,
        comptime mode: IntMode,
    ) !T {
        var fbs = std.io.fixedBufferStream(sm.dataSlice());
        return top_level.readVarint128(T, fbs.reader(), mode);
    }

    fn maxB128Numbers(data: []const u8) usize {
        var result: usize = 0;
        for (data) |c| result += @boolToInt(c & 0x80 == 0);
        return result;
    }

    pub inline fn dataSlice(sm: ScannedMember) []const u8 {
        return sm.data[0..sm.data_len];
    }

    pub fn countPackedElements(sm: ScannedMember, typ: FieldDescriptorProto.Type) !usize {
        switch (typ) {
            .TYPE_SFIXED32,
            .TYPE_FIXED32,
            .TYPE_FLOAT,
            => {
                if (sm.data_len % 4 != 0) {
                    std.log.err("length must be a multiple of 4 for fixed-length 32-bit types", .{});
                    return error.InvalidType;
                }
                return sm.data_len / 4;
            },
            .TYPE_SFIXED64, .TYPE_FIXED64, .TYPE_DOUBLE => {
                if (sm.data_len % 8 != 0) {
                    std.log.err("length must be a multiple of 8 for fixed-length 64-bit types", .{});
                    return error.InvalidType;
                }
                return sm.data_len / 8;
            },
            .TYPE_ENUM,
            .TYPE_INT32,
            .TYPE_SINT32,
            .TYPE_UINT32,
            .TYPE_INT64,
            .TYPE_SINT64,
            .TYPE_UINT64,
            => return maxB128Numbers(sm.dataSlice()),
            .TYPE_BOOL => return sm.data_len,
            .TYPE_STRING,
            .TYPE_BYTES,
            .TYPE_MESSAGE,
            .TYPE_ERROR,
            .TYPE_GROUP,
            => {
                std.log.err("bad protobuf-c type .{s} for packed-repeated", .{@tagName(typ)});
                return error.InvalidType;
            },
        }
    }
};

fn isPackableType(typ: descr.FieldDescriptorProto.Type) bool {
    return typ != .TYPE_STRING and typ != .TYPE_BYTES and
        typ != .TYPE_MESSAGE;
}

fn packedReadAndListAdd(comptime T: type, reader: anytype, member: [*]u8, comptime mint_mode: ?IntMode) !void {
    const int = if (mint_mode) |int_mode|
        try readVarint128(T, reader, int_mode)
    else
        try reader.readIntLittle(T);

    listAppend(member, ListMut(T), int);
}

fn parsePackedRepeatedMember(
    scanned_member: ScannedMember,
    member: [*]u8,
    _: *Message,
    _: *Ctx,
) !void {
    const field = scanned_member.field orelse unreachable;
    std.log.debug("parsePackedRepeatedMember() '{s}'", .{field.name});
    var fbs = std.io.fixedBufferStream(scanned_member.dataSlice());
    const reader = fbs.reader();
    while (true) {
        const errunion = switch (field.type) {
            .TYPE_ENUM,
            .TYPE_INT32,
            .TYPE_UINT32,
            => packedReadAndListAdd(u32, reader, member, .int),
            .TYPE_SINT32 => packedReadAndListAdd(u32, reader, member, .sint),
            .TYPE_INT64,
            .TYPE_UINT64,
            => packedReadAndListAdd(u64, reader, member, .int),
            .TYPE_SINT64 => packedReadAndListAdd(u64, reader, member, .sint),
            .TYPE_FIXED32,
            .TYPE_SFIXED32,
            .TYPE_FLOAT,
            => packedReadAndListAdd(u32, reader, member, null),
            .TYPE_FIXED64,
            .TYPE_SFIXED64,
            .TYPE_DOUBLE,
            => packedReadAndListAdd(u64, reader, member, null),
            .TYPE_BOOL => if (readVarint128(u64, reader, .int)) |rawint| {
                listAppend(member, ListMut(u32), @boolToInt(rawint != 0));
            } else |e| e,
            .TYPE_STRING,
            .TYPE_MESSAGE,
            .TYPE_BYTES,
            .TYPE_GROUP,
            .TYPE_ERROR,
            => return common.panicf("unreachable {s}", .{@tagName(field.type)}),
        };
        _ = errunion catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
    }
    const list = ptrAlignCast(*const List(u8), member);
    std.log.debug("parsePackedRepeatedMember() count {}", .{list.len});
    if (list.len == 0) return error.FieldMissing;
}

fn parseOneofMember(
    scanned_member: ScannedMember,
    member: [*]u8,
    message: *Message,
    ctx: *Ctx,
) !void {
    const field = scanned_member.field orelse unreachable;
    const descriptor = message.descriptor orelse unreachable;
    // If we have already parsed a member of this oneof, free it.
    // if the message already contains a field_id from the same group,
    // unset all members of the group
    const oneofids_group = for (descriptor.oneof_field_ids.slice()) |oneof_ids| {
        if (mem.indexOfScalar(c_uint, oneof_ids.slice(), field.id) != null) break oneof_ids;
    } else return deserializeErr(
        "internal error. couldn't find oneof group for field {s}.{s} with id {}",
        .{ descriptor.name, field.name, field.id },
        error.InternalError,
    );
    for (oneofids_group.slice()) |oneof_id| {
        if (message.hasFieldId(oneof_id)) {
            const field_idx = intRangeLookup(descriptor.field_ids, oneof_id) catch
                return deserializeErr(
                "oneof_id {} not found in field_ids {}",
                .{ oneof_id, descriptor.field_ids },
                error.FieldMissing,
            );
            std.log.debug("found existing oneof_id {} ", .{oneof_id});
            const old_field = descriptor.fields.items[field_idx];
            const ele_size = repeatedEleSize(old_field.type);
            switch (old_field.type) {
                .TYPE_STRING, .TYPE_BYTES => {
                    const s = ptrAlignCast(*const String, member);
                    s.deinit(ctx.allocator);
                },
                .TYPE_MESSAGE => {
                    const subm = ptrAlignCast(*const *Message, member);
                    subm.*.deinit(ctx.allocator);
                },
                else => {},
            }
            @memset(member[0..ele_size], 0);
            message.setPresentValue(oneof_id, false);
        }
    }

    try parseRequiredMember(scanned_member, member, message, ctx, true);
    message.setPresent(field.id);
}

fn parseOptionalMember(
    scanned_member: ScannedMember,
    member: [*]u8,
    message: *Message,
    ctx: *Ctx,
) !void {
    std.log.debug("parseOptionalMember({})", .{ptrfmt(member)});

    parseRequiredMember(
        scanned_member,
        member,
        message,
        ctx,
        true,
    ) catch |err|
        switch (err) {
        error.FieldMissing => return,
        else => return err,
    };
    const field = scanned_member.field orelse unreachable;
    std.log.debug(
        "parseOptionalMember() setPresent({}) - {s}",
        .{ field.id, field.name },
    );
    message.setPresent(field.id);
}

fn parseRepeatedMember(
    scanned_member: ScannedMember,
    member: [*]u8,
    message: *Message,
    ctx: *Ctx,
) !void {
    var field = scanned_member.field orelse unreachable;
    std.log.debug(
        "parseRepeatedMember() field name='{s}' offset=0x{x}/{}",
        .{ field.name, field.offset, field.offset },
    );
    try parseRequiredMember(
        scanned_member,
        member,
        message,
        ctx,
        false,
    );
}

fn listAppend(
    member: [*]u8,
    comptime L: type,
    item: L.Child,
) void {
    const list = ptrAlignCast(*L, member);
    const short_name = afterLastIndexOf(@typeName(L.Child), '.');
    std.log.debug(
        "listAppend() {s} member {} list {}/{}/{}",
        .{ short_name, ptrfmt(member), ptrfmt(list.items), list.len, list.cap },
    );
    list.appendAssumeCapacity(item);
}

fn parseRequiredMember(
    scanned_member: ScannedMember,
    member: [*]u8,
    _: *Message,
    ctx: *Ctx,
    maybe_clear: bool,
) !void {
    _ = maybe_clear;
    // TODO when there is a return FALSE make it an error.FieldMissing

    const wire_type = scanned_member.tag.wire_type;
    const field = scanned_member.field orelse unreachable;
    std.log.debug(
        "parseRequiredMember() field={s} .{s} .{s} {}",
        .{
            field.name,
            @tagName(field.type),
            @tagName(scanned_member.tag.wire_type),
            ptrfmt(member),
        },
    );

    switch (field.type) {
        .TYPE_INT32, .TYPE_UINT32, .TYPE_ENUM => {
            if (wire_type != .VARINT) return error.FieldMissing;
            const int = try scanned_member.readVarint128(u32, .int);
            std.log.info("{s}: {}", .{ field.name, int });
            if (field.label == .LABEL_REPEATED) {
                listAppend(member, ListMut(u32), int);
            } else mem.writeIntLittle(u32, member[0..4], int);
        },
        .TYPE_SINT32 => {
            if (wire_type != .VARINT) return error.FieldMissing;
            const int = try scanned_member.readVarint128(u32, .sint);
            std.log.info("{s}: {}", .{ field.name, int });
            if (field.label == .LABEL_REPEATED) {
                listAppend(member, ListMut(u32), int);
            } else mem.writeIntLittle(u32, member[0..4], int);
        },
        .TYPE_FIXED32, .TYPE_SFIXED32, .TYPE_FLOAT => {
            if (wire_type != .I32) return error.FieldMissing;
            const int = mem.readIntLittle(u32, scanned_member.data[0..4]);
            std.log.info("{s}: {}", .{ field.name, int });
            if (field.label == .LABEL_REPEATED) {
                listAppend(member, ListMut(u32), int);
            } else mem.writeIntLittle(u32, member[0..4], int);
        },
        .TYPE_FIXED64, .TYPE_SFIXED64, .TYPE_DOUBLE => {
            if (wire_type != .I64) return error.FieldMissing;
            const int = mem.readIntLittle(u64, scanned_member.data[0..8]);
            std.log.info("{s}: {}", .{ field.name, int });
            if (field.label == .LABEL_REPEATED) {
                listAppend(member, ListMut(u64), int);
            } else mem.writeIntLittle(u64, member[0..8], int);
        },
        .TYPE_INT64, .TYPE_UINT64 => {
            if (wire_type != .VARINT) return error.FieldMissing;
            const int = try scanned_member.readVarint128(u64, .int);
            std.log.info("{s}: {}", .{ field.name, int });
            if (field.label == .LABEL_REPEATED) {
                listAppend(member, ListMut(u64), int);
            } else mem.writeIntLittle(u64, member[0..8], int);
        },
        .TYPE_SINT64 => {
            if (wire_type != .VARINT) return error.FieldMissing;
            const int = try scanned_member.readVarint128(u64, .sint);
            std.log.info("{s}: {}", .{ field.name, int });
            if (field.label == .LABEL_REPEATED) {
                listAppend(member, ListMut(u64), int);
            } else mem.writeIntLittle(u64, member[0..8], int);
        },
        .TYPE_BOOL => {
            if (wire_type != .VARINT) return error.FieldMissing;
            const int = @boolToInt(try scanned_member.readVarint128(u64, .int) != 0);
            std.log.info("{s}: {}", .{ field.name, int });
            if (field.label == .LABEL_REPEATED) {
                listAppend(member, ListMut(u32), int);
            } else member[0] = int;
        },
        .TYPE_STRING, .TYPE_BYTES => {
            // TODO free if existing
            if (wire_type != .LEN) return error.FieldMissing;
            const bytes = try ctx.allocator.dupe(u8, scanned_member.dataSlice());
            if (field.label == .LABEL_REPEATED) {
                listAppend(member, ListMut(String), String.init(bytes));
            } else {
                var s = ptrAlignCast(*String, member);
                s.* = String.init(bytes);
            }
            std.log.info("{s}: '{s}'", .{ field.name, bytes });
        },
        .TYPE_MESSAGE => {
            // TODO free if existing
            if (wire_type != .LEN) {
                return deserializeErr(
                    "unexpected wire_type .{s}",
                    .{@tagName(wire_type)},
                    error.FieldMissing,
                );
            }

            std.log.debug(
                "parsing message field '{s}' len {} member {}",
                .{ field.name, scanned_member.data_len, ptrfmt(member) },
            );

            if (field.descriptor == null) {
                return deserializeErr(
                    "field.descriptor == null field {}",
                    .{field.*},
                    error.DescriptorMissing,
                );
            }

            var limctx = ctx.withData(scanned_member.dataSlice());
            const field_desc = field.getDescriptor(MessageDescriptor);

            std.log.info(".{s} {s} sizeof={}", .{
                field.label.tagName(),
                field_desc.name,
                field_desc.sizeof_message,
            });

            if (field.label == .LABEL_REPEATED) {
                const subm = try deserialize(field_desc, &limctx);
                listAppend(member, ListMut(*Message), subm);
            } else {
                const subm = ptrAlignCast(**Message, member);
                subm.* = try deserialize(field_desc, &limctx);
            }
        },
        .TYPE_GROUP => {
            const field_desc = field.getDescriptor(MessageDescriptor);
            var limctx = ctx.withData(scanned_member.dataSlice());
            if (field.label == .LABEL_REPEATED) {
                const subm = try deserialize(field_desc, &limctx);
                listAppend(member, ListMut(*Message), subm);
            } else {
                const subm = ptrAlignCast(**Message, member);
                subm.* = try deserialize(field_desc, &limctx);
            }
        },
        else => todo("{s} ", .{@tagName(field.type)}),
    }
}

fn parseMember(
    scanned_member: ScannedMember,
    message: *Message,
    ctx: *Ctx,
) !void {
    const field = scanned_member.field orelse {
        var ufield = try ctx.allocator.create(types.MessageUnknownField);
        ufield.* = .{
            .tag = scanned_member.tag,
            .data = String.init(try ctx.allocator.dupe(
                u8,
                scanned_member.dataSlice(),
            )),
        };
        std.log.debug("unknown field data {}:'{}' prefix_len {}", .{
            ufield.data.len,
            std.fmt.fmtSliceHexLower(ufield.data.slice()),
            scanned_member.prefix_len,
        });
        message.unknown_fields.appendAssumeCapacity(ufield);
        return;
    };

    std.log.debug(
        "parseMember() '{s}' .{s} .{s} ",
        .{ field.name, @tagName(field.label), @tagName(field.type) },
    );
    var member = @ptrCast([*]u8, message) + field.offset;
    return switch (field.label) {
        .LABEL_REQUIRED => parseRequiredMember(scanned_member, member, message, ctx, true),
        .LABEL_OPTIONAL, .LABEL_NONE => if (flagsContain(field.flags, FieldFlag.FLAG_ONEOF))
            parseOneofMember(scanned_member, member, message, ctx)
        else
            parseOptionalMember(scanned_member, member, message, ctx),

        .LABEL_REPEATED => if (scanned_member.tag.wire_type == .LEN and
            (flagsContain(field.flags, FieldFlag.FLAG_PACKED) or isPackableType(field.type)))
            parsePackedRepeatedMember(scanned_member, member, message, ctx)
        else
            parseRepeatedMember(scanned_member, member, message, ctx),
    };
}

fn messageTypeName(magic: u32) []const u8 {
    return switch (magic) {
        types.MESSAGE_DESCRIPTOR_MAGIC => "message",
        types.ENUM_DESCRIPTOR_MAGIC => "enum",
        types.SERVICE_DESCRIPTOR_MAGIC => "service",
        else => "unknown",
    };
}

pub fn verifyMessageType(magic: u32, expected_magic: u32) Error!void {
    if (magic != expected_magic) {
        std.log.err("deserialize() requires a {s} type but got {s}", .{
            messageTypeName(expected_magic),
            messageTypeName(magic),
        });
        return error.InvalidMessageType;
    }
}

fn deserializeErr(comptime fmt: []const u8, args: anytype, err: Error) Error {
    std.log.err("deserialization error: " ++ fmt, args);
    return err;
}

/// create a new Message and deserialize a protobuf wire format message from
/// ctx.data into its fields. uses ctx.allocator for allocations.
pub fn deserialize(desc: *const MessageDescriptor, ctx: *Ctx) Error!*Message {
    var buf = try ctx.allocator.alignedAlloc(
        u8,
        common.ptrAlign(*Message),
        desc.sizeof_message,
    );
    var message = ptrAlignCast(*Message, buf.ptr);
    errdefer message.deinit(ctx.allocator);

    const desc_fields = desc.fields.slice();
    var last_field: ?*const FieldDescriptor = if (desc_fields.len > 0)
        &desc_fields[0]
    else
        null;

    // use 32 bytes (256 bits) of stack space for req_fields_bitmap, falling
    // back to user allocator
    const req_fields_bitmap_size = @sizeOf(usize) * 4;
    var sfa1 = std.heap.stackFallback(req_fields_bitmap_size, ctx.allocator);
    const sfa1_alloc = sfa1.get();
    var req_fields_bitmap = try std.DynamicBitSetUnmanaged.initEmpty(
        sfa1_alloc,
        req_fields_bitmap_size * @bitSizeOf(usize), // bitsize
    );
    defer req_fields_bitmap.deinit(sfa1_alloc);

    var last_field_index: u32 = 0;
    var n_unknown: u32 = 0;
    try verifyMessageType(desc.magic, types.MESSAGE_DESCRIPTOR_MAGIC);

    std.log.info("\n+++ deserialize {s} {}-{}/{} size=0x{x}/{} data len {} +++", .{
        desc.name,
        ptrfmt(buf.ptr),
        ptrfmt(buf.ptr + buf.len),
        buf.len,
        desc.sizeof_message,
        desc.sizeof_message,
        ctx.data.len,
    });

    if (desc.message_init) |init| {
        init(buf.ptr, buf.len);
        std.log.debug(
            "(init) called {s}.init({}) fields.len {}",
            .{ message.descriptor.?.name, ptrfmt(message), message.descriptor.?.fields.len },
        );
    } else message.* = genericMessageInit(desc);

    // ---
    // pre-scan the wire message saving to scanned_members in order to find out
    // how long repeated fields are before allocating them.
    // ---
    var sfa2 = std.heap.stackFallback(@sizeOf(ScannedMember) * 16, ctx.allocator);
    const sfa2_alloc = sfa2.get();
    var scanned_members: std.ArrayListUnmanaged(ScannedMember) = .{};
    defer scanned_members.deinit(sfa2_alloc);

    while (true) {
        const tag = ctx.readTag() catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        std.log.debug("(scan) -- tag wire_type=.{s} field_id={} --", .{
            @tagName(tag.wire_type),
            tag.field_id,
        });
        // proto2/3 field numbers start at 1
        if (tag.field_id == 0) return error.FieldMissing;

        var mfield: ?*const FieldDescriptor = null;
        if (last_field == null or last_field.?.id != tag.field_id) {
            if (intRangeLookup(desc.field_ids, tag.field_id)) |field_index| {
                std.log.debug(
                    "(scan) found field_id={} at index={}",
                    .{ tag.field_id, field_index },
                );
                mfield = &desc_fields[field_index];
                last_field = mfield;
                last_field_index = @intCast(u32, field_index);
            } else |_| {
                std.log.debug("(scan) field_id {} not found", .{tag.field_id});
                mfield = null;
                n_unknown += 1;
            }
        } else mfield = last_field;

        if (mfield) |field| {
            if (field.label == .LABEL_REQUIRED)
                // TODO make a message.requiredFieldIndex(field_index) method
                // which ignores optional fields, allowing
                // req_fields_bitmap to be smaller
                req_fields_bitmap.set(last_field_index);
        }

        var sm: ScannedMember = .{
            .tag = tag,
            .field = mfield,
            .data = ctx.data.ptr,
            .data_len = @intCast(u32, ctx.data.len),
        };

        switch (tag.wire_type) {
            .VARINT => {
                const startlen = ctx.data.len;
                _ = try ctx.readVarint128(usize, .int);
                sm.data_len = @intCast(u32, startlen - ctx.data.len);
            },
            .I64 => {
                if (ctx.data.len < 8) {
                    return deserializeErr(
                        "too short after 64 bit wiretype at offset {}",
                        .{ctx.bytesRead()},
                        error.InvalidData,
                    );
                }
                sm.data_len = 8;
                ctx.skip(8) catch unreachable;
            },
            .I32 => {
                if (ctx.data.len < 4) {
                    return deserializeErr(
                        "too short after 32 bit wiretype at offset {}",
                        .{ctx.bytesRead()},
                        error.InvalidData,
                    );
                }
                sm.data_len = 4;
                ctx.skip(4) catch unreachable;
            },
            .LEN => {
                const lens = try ctx.scanLengthPrefixedData();
                sm.data = sm.data + lens[0];
                sm.data_len = lens[1];
                sm.prefix_len = lens[0];
                try ctx.skip(sm.data_len);
            },
            .SGROUP => {
                const field = sm.field orelse unreachable;
                const endtag = Tag.init(.EGROUP, sm.tag.field_id);
                var buf1 = [1]u8{0} ** 8;
                var fbs = std.io.fixedBufferStream(&buf1);
                try writeVarint128(usize, endtag.encode(), fbs.writer(), .int);
                const endtag_bytes = buf1[0..fbs.pos];
                // TODO - not 100% sure this is correct. might have to allow
                // for nested groups with the same field number?  if so, need to
                // adapt this search to allow for finding 'starttag's before
                // endtag
                sm.data_len = @intCast(u32, mem.indexOf(u8, ctx.data, endtag_bytes) orelse
                    return deserializeErr(
                    "group missing end tag. field '{s}' {}",
                    .{ field.name, field.id },
                    error.InvalidData,
                ));
                try ctx.skip(sm.data_len + @intCast(u32, fbs.pos));
            },
            .EGROUP => {},
        }

        if (mfield) |field| {
            std.log.debug("(scan) field {s}.{s} (+0x{x}/{}={})", .{
                desc.name,
                field.name,
                field.offset,
                field.offset,
                ptrfmt(buf.ptr + field.offset),
            });
            if (field.label == .LABEL_REPEATED) {
                // list ele type doesn't matter, just want to change len
                const list = structMemberPtr(ListMut(u8), message, field.offset);
                if (tag.wire_type == .LEN and
                    (flagsContain(field.flags, FieldFlag.FLAG_PACKED) or
                    isPackableType(field.type)))
                {
                    list.len += try sm.countPackedElements(field.type);
                } else list.len += 1;
            }
        } else std.log.debug("(scan) field {s} unknown", .{desc.name});
        try scanned_members.append(sfa2_alloc, sm);
    }

    // --
    // post-scan. allocate repeated field lists and unknown fields now that all
    // lengths are known.
    // --
    var missing_any_required = false;
    for (desc_fields, 0..) |field, i| {
        if (field.label == .LABEL_REPEATED) {
            const size = pb.protobuf.repeatedEleSize(field.type);
            // list ele type doesn't matter, just want to change len
            const list = structMemberPtr(ListMut(u8), message, field.offset);
            if (list.len != 0) {
                std.log.debug(
                    "(scan) field '{s}' - allocating {}={}*{} list bytes",
                    .{ field.name, size * list.len, size, list.len },
                );
                // TODO CLEAR_REMAINING_N_PTRS?
                var bytes = switch (field.type) {
                    .TYPE_DOUBLE,
                    .TYPE_INT64,
                    .TYPE_UINT64,
                    .TYPE_FIXED64,
                    .TYPE_SFIXED64,
                    .TYPE_SINT64,
                    .TYPE_BYTES,
                    .TYPE_STRING,
                    .TYPE_MESSAGE,
                    .TYPE_GROUP,
                    => try ctx.allocator.alignedAlloc(u8, 8, size * list.len),
                    .TYPE_FLOAT,
                    .TYPE_INT32,
                    .TYPE_FIXED32,
                    .TYPE_UINT32,
                    .TYPE_ENUM,
                    .TYPE_SFIXED32,
                    .TYPE_SINT32,
                    .TYPE_BOOL,
                    => try ctx.allocator.alignedAlloc(u8, 4, size * list.len),
                    else => {
                        std.log.err("type={s} size={}", .{ @tagName(field.type), size });
                        return error.UnsupportedListElementSize;
                    },
                };
                list.items = bytes.ptr;
                list.cap = list.len;
                list.len = 0;
            }
        } else if (field.label == .LABEL_REQUIRED) {
            if (field.default_value == null and
                !req_fields_bitmap.isSet(i))
            {
                std.log.warn(
                    "message {s}: missing required field {s}",
                    .{ desc.name, field.name },
                );
                missing_any_required = true;
            }
        }
    }

    if (missing_any_required) return error.RequiredFieldMissing;
    assert(ctx.data.len == 0);

    if (n_unknown > 0)
        try message.unknown_fields.ensureTotalCapacity(ctx.allocator, n_unknown);

    for (scanned_members.items) |sm|
        try parseMember(sm, message, ctx);

    assert(message.unknown_fields.len == message.unknown_fields.cap);

    std.log.info("\n--- deserialize {s} {}-{} size=0x{x}/{} ---", .{
        desc.name,
        ptrfmt(buf.ptr),
        ptrfmt(buf.ptr + buf.len),
        desc.sizeof_message,
        desc.sizeof_message,
    });
    return message;
}

fn serializeErr(comptime fmt: []const u8, args: anytype, err: Error) Error {
    std.log.err("serialization error: " ++ fmt, args);
    return err;
}

fn serializeOptionalField(
    message: *const Message,
    field: FieldDescriptor,
    member: [*]const u8,
    writer: anytype,
) Error!void {
    if (!message.hasFieldId(field.id)) return;
    if (field.type == .TYPE_STRING and
        ptrAlignCast(*const String, member).items == field.default_value)
        return
    else if (field.type == .TYPE_MESSAGE and
        ptrAlignCast(*const *Message, member).* == field.default_value)
        return;

    std.log.debug(
        "encodeOptionalField() '{s}' .{s} .{s}",
        .{ field.name, field.type.tagName(), field.label.tagName() },
    );

    return serializeRequiredField(message, field, member, writer);
}

fn serializeRepeatedPacked(
    list: *const List(u8),
    field: FieldDescriptor,
    writer: anytype,
) !void {
    const size = repeatedEleSize(field.type);
    var i: usize = 0;
    while (i < list.len) : (i += 1) {
        switch (field.type) {
            .TYPE_INT32, .TYPE_UINT32, .TYPE_ENUM, .TYPE_BOOL => {
                const int = mem.readIntLittle(u32, (list.items + i * size)[0..4]);
                try writeVarint128(u32, int, writer, .int);
            },
            .TYPE_SINT32 => {
                const int = mem.readIntLittle(u32, (list.items + i * size)[0..4]);
                try writeVarint128(u32, int, writer, .sint);
            },
            .TYPE_SINT64 => {
                const int = mem.readIntLittle(u64, (list.items + i * size)[0..8]);
                try writeVarint128(u64, int, writer, .sint);
            },
            .TYPE_INT64, .TYPE_UINT64 => {
                const int = mem.readIntLittle(u64, (list.items + i * size)[0..8]);
                try writeVarint128(u64, int, writer, .int);
            },
            .TYPE_FIXED32, .TYPE_FLOAT, .TYPE_SFIXED32 => {
                const int = mem.readIntLittle(u32, (list.items + i * size)[0..4]);
                try writer.writeIntLittle(u32, int);
            },
            .TYPE_FIXED64, .TYPE_DOUBLE, .TYPE_SFIXED64 => {
                const int = mem.readIntLittle(u64, (list.items + i * size)[0..8]);
                try writer.writeIntLittle(u64, int);
            },

            .TYPE_STRING,
            .TYPE_MESSAGE,
            .TYPE_BYTES,
            .TYPE_GROUP,
            .TYPE_ERROR,
            => return common.panicf("unreachable {s}", .{@tagName(field.type)}),
        }
    }
}

fn serializeRepeatedField(
    message: *const Message,
    field: FieldDescriptor,
    member: [*]const u8,
    writer: anytype,
) Error!void {
    const list = ptrAlignCast(*const List(u8), member);
    if (list.len == 0) return;
    std.log.debug(
        "encodeRepeatedField() '{s}' .{s} .{s} list.len={}",
        .{ field.name, field.type.tagName(), field.label.tagName(), list.len },
    );
    if (flagsContain(field.flags, FieldFlag.FLAG_PACKED)) {
        var cwriter = std.io.countingWriter(std.io.null_writer);
        try serializeRepeatedPacked(list, field, cwriter.writer());
        const tag = Tag.init(.LEN, field.id);
        try writeVarint128(usize, tag.encode(), writer, .int);
        try writeVarint128(usize, cwriter.bytes_written, writer, .int);
        try serializeRepeatedPacked(list, field, writer);
    } else {
        const size = repeatedEleSize(field.type);
        var i: usize = 0;
        while (i < list.len) : (i += 1) {
            try serializeRequiredField(message, field, list.items + i * size, writer);
        }
    }
}

fn serializeOneofField(
    message: *const Message,
    field: FieldDescriptor,
    member: [*]const u8,
    writer: anytype,
) Error!void {
    if (!message.hasFieldId(field.id)) return;
    std.log.debug(
        "encodeOneofField() .{s} .{s}",
        .{ field.type.tagName(), field.label.tagName() },
    );
    if (field.type == .TYPE_MESSAGE or
        field.type == .TYPE_STRING)
    {
        // const void *ptr = *(const void * const *) member;
        // if (ptr == NULL || ptr == field.default_value)
        //     return 0;
    }
    return serializeRequiredField(message, field, member, writer);
}

fn serializeUnlabeledField(
    message: *const Message,
    field: FieldDescriptor,
    member: [*]const u8,
    writer: anytype,
) Error!void {
    _ = message;
    _ = member;
    _ = writer;
    todo(
        "encodeUnlabeledField() .{s} .{s}",
        .{ field.type.tagName(), field.label.tagName() },
    );
}

fn serializeRequiredField(
    message: *const Message,
    field: FieldDescriptor,
    member: [*]const u8,
    writer: anytype,
) Error!void {
    std.log.debug(
        "serializeRequiredField() '{s}' .{s} .{s}",
        .{ field.name, field.type.tagName(), field.label.tagName() },
    );

    switch (field.type) {
        .TYPE_ENUM, .TYPE_INT32, .TYPE_UINT32 => {
            const tag = Tag.init(.VARINT, field.id);
            try writeVarint128(usize, tag.encode(), writer, .int);
            const value = mem.readIntLittle(u32, member[0..4]);
            try writeVarint128(u32, value, writer, .int);
        },
        .TYPE_SINT32 => {
            const tag = Tag.init(.VARINT, field.id);
            try writeVarint128(usize, tag.encode(), writer, .int);
            const value = mem.readIntLittle(i32, member[0..4]);
            try writeVarint128(i32, value, writer, .sint);
        },
        .TYPE_SINT64 => {
            const tag = Tag.init(.VARINT, field.id);
            try writeVarint128(usize, tag.encode(), writer, .int);
            const value = mem.readIntLittle(i64, member[0..8]);
            try writeVarint128(i64, value, writer, .sint);
        },
        .TYPE_UINT64, .TYPE_INT64 => {
            const tag = Tag.init(.VARINT, field.id);
            try writeVarint128(usize, tag.encode(), writer, .int);
            const value = mem.readIntLittle(u64, member[0..8]);
            try writeVarint128(u64, value, writer, .int);
        },
        .TYPE_BOOL => {
            const tag = Tag.init(.VARINT, field.id);
            try writeVarint128(usize, tag.encode(), writer, .int);
            try writeVarint128(u8, member[0], writer, .int);
        },
        .TYPE_DOUBLE, .TYPE_FIXED64, .TYPE_SFIXED64 => {
            const tag = Tag.init(.I64, field.id);
            try writeVarint128(usize, tag.encode(), writer, .int);
            const value = mem.readIntLittle(u64, member[0..8]);
            try writer.writeIntLittle(u64, value);
        },
        .TYPE_FLOAT, .TYPE_FIXED32, .TYPE_SFIXED32 => {
            const tag = Tag.init(.I32, field.id);
            try writeVarint128(usize, tag.encode(), writer, .int);
            const value = mem.readIntLittle(u32, member[0..4]);
            try writer.writeIntLittle(u32, value);
        },
        .TYPE_MESSAGE => {
            var cwriter = std.io.countingWriter(std.io.null_writer);
            const subm = ptrAlignCast(*const *Message, member);
            try serialize(subm.*, cwriter.writer());
            const tag = Tag.init(.LEN, field.id);
            try writeVarint128(usize, tag.encode(), writer, .int);
            try writeVarint128(usize, cwriter.bytes_written, writer, .int);
            try serialize(subm.*, writer);
        },
        .TYPE_STRING, .TYPE_BYTES => {
            const desc = @ptrCast(*const MessageDescriptor, message.descriptor);
            const ismap = flagsContain(desc.flags, MessageDescriptor.Flag.FLAG_MAP_TYPE);
            std.log.info(".TYPE_STRING/.TYPE_BYTES ismap {}", .{ismap});
            const s = ptrAlignCast(*const String, member);
            if (ismap and s.len == 0) return;
            const tag = Tag.init(.LEN, field.id);
            try writeVarint128(usize, tag.encode(), writer, .int);
            try writeVarint128(usize, s.len, writer, .int);
            std.log.debug("string {*}/{}:{x}", .{ s.items, s.len, s.len });
            _ = try writer.write(s.slice());
        },
        .TYPE_GROUP => {
            const starttag = Tag.init(.SGROUP, field.id);
            try writeVarint128(usize, starttag.encode(), writer, .int);
            const subm = ptrAlignCast(*const *Message, member);
            try serialize(subm.*, writer);
            const endtag = Tag.init(.EGROUP, field.id);
            try writeVarint128(usize, endtag.encode(), writer, .int);
        },
        else => todo("serializeRequiredField() field.type .{s}", .{field.type.tagName()}),
    }
}

fn serializeUnknownField(
    message: *const Message,
    ufield: *const types.MessageUnknownField,
    writer: anytype,
) Error!void {
    _ = message;
    std.log.debug(
        "encodeUnknownField() tag wite_type=.{s} field_id={} data.len={}",
        .{ @tagName(ufield.tag.wire_type), ufield.tag.field_id, ufield.data.len },
    );

    try writeVarint128(usize, ufield.tag.encode(), writer, .int);
    _ = try writer.write(ufield.data.slice());
}

pub fn serialize(message: *const Message, writer: anytype) Error!void {
    const desc = message.descriptor orelse return serializeErr(
        "invalid message. missing descriptor",
        .{},
        error.DescriptorMissing,
    );
    std.log.info("+++ serialize {}", .{desc.name});
    try verifyMessageType(desc.magic, types.MESSAGE_DESCRIPTOR_MAGIC);
    const buf = @ptrCast([*]const u8, message)[0..desc.sizeof_message];
    for (desc.fields.slice()) |field| {
        const member = buf.ptr + field.offset;

        if (field.label == .LABEL_REQUIRED)
            try serializeRequiredField(message, field, member, writer)
        else if ((field.label == .LABEL_OPTIONAL or field.label == .LABEL_NONE) and
            flagsContain(field.flags, FieldFlag.FLAG_ONEOF))
            try serializeOneofField(message, field, member, writer)
        else if (field.label == .LABEL_OPTIONAL)
            try serializeOptionalField(message, field, member, writer)
        else if (field.label == .LABEL_NONE)
            try serializeUnlabeledField(message, field, member, writer)
        else
            try serializeRepeatedField(message, field, member, writer);
    }
    for (message.unknown_fields.slice()) |ufield|
        try serializeUnknownField(message, ufield, writer);
}

fn debugit(m: *Message, comptime T: type) void {
    const it = @ptrCast(*T, m);
    _ = it;
    @breakpoint();
}
