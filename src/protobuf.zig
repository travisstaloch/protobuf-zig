const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const pb = @import("protobuf");
const plugin = pb.plugin;
const types = pb.types;
const WireType = types.WireType;
const Key = types.Key;
const extern_types = pb.extern_types;
const List = extern_types.ArrayList;
const ListMut = extern_types.ArrayListMut;
const String = extern_types.String;
const pbtypes = pb.pbtypes;
const Message = pbtypes.Message;
const MessageDescriptor = pbtypes.MessageDescriptor;
const FieldDescriptor = pbtypes.FieldDescriptor;
const FieldFlag = FieldDescriptor.FieldFlag;
const FieldDescriptorProto = pb.descr.FieldDescriptorProto;
const BinaryData = pbtypes.BinaryData;
const common = pb.common;
const ptrAlignCast = common.ptrAlignCast;
const ptrfmt = common.ptrfmt;
const todo = common.todo;
const afterLastIndexOf = common.afterLastIndexOf;
const flagsContain = common.flagsContain;
const top_level = @This();

pub const LocalError = error{
    InvalidKey,
    NotEnoughBytesRead,
    Overflow,
    FieldMissing,
    RequiredFieldMissing,
    SubMessageMissing,
    DescriptorMissing,
    InvalidType,
    InvalidData,
};

pub const Error = std.mem.Allocator.Error ||
    std.fs.File.WriteFileError ||
    LocalError;

// Reads a varint from the reader and returns the value.
// `mode = .sint` should used for sint32 and sint64 decoding when expecting
// lots of negative numbers as it uses zig zag encoding to reduce the size of
// negative values. negatives encoded otherwise (with `mode = .int`). will
// require extra size (10 bytes each) and are inefficient.
pub fn readVarint128(comptime T: type, reader: anytype, comptime mode: IntMode) !T {
    var shift: u6 = 0;
    var value: u64 = 0;
    while (true) {
        const b = try reader.readByte();
        value |= @as(u64, @truncate(u7, b)) << shift;
        if (b >> 7 == 0) break;
        shift += 7;
    }
    if (mode == .sint) {
        const S = std.meta.Int(.signed, @bitSizeOf(T));
        const svalue = @bitCast(S, value);
        value = @bitCast(T, (svalue >> 1) ^ (-(svalue & 1)));
    }
    return switch (@typeInfo(T).Int.signedness) {
        .signed => @truncate(T, @bitCast(i64, value)),
        .unsigned => @truncate(T, value),
    };
}

pub fn writeVarint128(comptime T: type, _value: T, writer: anytype, comptime mode: IntMode) !void {
    var value = _value;

    if (mode == .sint) {
        value = (value >> (@bitSizeOf(T) - 1)) ^ (value << 1);
    }
    const U = std.meta.Int(.unsigned, @bitSizeOf(T));
    try std.leb.writeULEB128(writer, @bitCast(U, value));
}

pub const IntMode = enum { sint, int };

pub fn context(data: []const u8, alloc: Allocator) Protobuf.Ctx {
    return Protobuf.Ctx.init(data, alloc);
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
        => 4,
        .TYPE_SINT64,
        .TYPE_INT64,
        .TYPE_UINT64,
        .TYPE_SFIXED64,
        .TYPE_FIXED64,
        .TYPE_DOUBLE,
        => 8,
        .TYPE_BOOL => @sizeOf(bool),
        .TYPE_STRING => @sizeOf(pb.extern_types.String),
        .TYPE_MESSAGE => @sizeOf(*Message),
        .TYPE_BYTES => @sizeOf(BinaryData),
        .TYPE_ERROR, .TYPE_GROUP => unreachable,
    };
}

pub const Protobuf = struct {
    const Ctx = struct {
        data: []const u8,
        data_start: []const u8,
        alloc: Allocator,

        pub fn init(data: []const u8, alloc: Allocator) Ctx {
            return .{ .data = data, .alloc = alloc, .data_start = data };
        }

        pub fn withData(ctx: Ctx, data: []const u8) Ctx {
            var res = ctx;
            res.data = data;
            res.data_start = data;
            return res;
        }

        pub fn fbs(ctx: Ctx) std.io.FixedBufferStream([]const u8) {
            return std.io.fixedBufferStream(ctx.data);
        }

        pub fn bytesRead(ctx: Ctx) usize {
            return @ptrToInt(ctx.data.ptr) - @ptrToInt(ctx.data_start.ptr);
        }

        pub fn skip(ctx: *Ctx, len: usize) void {
            ctx.data = ctx.data[len..];
        }

        pub fn deserialize(ctx: *Ctx, mdesc: *const MessageDescriptor) Error!*Message {
            return Protobuf.deserialize(mdesc, ctx);
        }

        // Reads a varint from the reader and returns the value, eos (end of steam) pair.
        // `mode = .sint` should used for sint32 and sint64 decoding when expecting lots of negative numbers as it
        // uses zig zag encoding to reduce the size of negative values. negatives encoded otherwise (with `mode = .int`)
        // will require extra size (10 bytes each) and are inefficient.
        pub fn readVarint128(ctx: *Ctx, comptime T: type, comptime mode: IntMode) !T {
            var ctxfbs = ctx.fbs();
            const reader = ctxfbs.reader();
            const value = try top_level.readVarint128(T, reader, mode);
            ctx.skip(ctxfbs.pos);
            return value;
        }

        pub fn readEnum(ctx: *Ctx, comptime E: type) !E {
            const value = try ctx.readVarint128(i64, .int);
            return @intToEnum(E, if (@hasDecl(E, "is_aliased") and E.is_aliased)
                // TODO this doesn't seem entirely correct as the value can represent multiple tags.
                //      not enirely sure what to do here.
                E.values[@bitCast(u64, value)]
            else
                value);
        }

        pub fn readBool(ctx: *Ctx) !bool {
            const byte = ctx.data[0];
            ctx.skip(1);
            return byte != 0;
        }

        pub fn readKey(ctx: *Ctx) !Key {
            const key = try ctx.readVarint128(usize, .int);
            return Key{
                .wire_type = std.meta.intToEnum(WireType, key & 0b111) catch {
                    std.log.err("readKey() invalid wire_type {}. key {}:0x{x}:0b{b:0>8} field_id {}", .{ @truncate(u3, key), key, key, key, key >> 3 });
                    return error.InvalidKey;
                },
                .field_id = key >> 3,
            };
        }

        pub fn readInt64(ctx: *Ctx, comptime T: type) !T {
            var ctxfbs = ctx.fbs();
            const reader = ctxfbs.reader();
            const result = @bitCast(T, try reader.readIntLittle(u64));
            ctx.skip(ctxfbs.pos);
            return result;
        }

        pub fn readInt32(ctx: *Ctx, comptime T: type) !T {
            var ctxfbs = ctx.fbs();
            const reader = ctxfbs.reader();
            const result = @bitCast(T, try reader.readIntLittle(u32));
            ctx.skip(ctxfbs.pos);
            return result;
        }

        pub fn scanLengthPrefixedData(ctx: *Ctx) ![2]usize {
            const startlen = ctx.data.len;
            const len = try ctx.readVarint128(usize, .int);
            return .{ startlen - ctx.data.len, len };
        }
    };

    fn structMemberP(message: *Message, offset: usize) [*]u8 {
        const bytes = @ptrCast([*]u8, message);
        return bytes + offset;
    }

    fn structMemberPtr(comptime T: type, message: *Message, offset: usize) *T {
        return ptrAlignCast(*T, structMemberP(message, offset));
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
                var field_bytes = structMemberP(&message, field.offset);
                const default = @ptrCast([*]const u8, field.default_value);
                switch (field.type) {
                    .TYPE_INT32,
                    .TYPE_SINT32,
                    .TYPE_SFIXED32,
                    .TYPE_UINT32,
                    .TYPE_FIXED32,
                    .TYPE_FLOAT,
                    .TYPE_ENUM,
                    => @memcpy(field_bytes, default, 4),
                    .TYPE_INT64,
                    .TYPE_SINT64,
                    .TYPE_SFIXED64,
                    .TYPE_UINT64,
                    .TYPE_FIXED64,
                    .TYPE_DOUBLE,
                    => @memcpy(field_bytes, default, 8),
                    .TYPE_BOOL => @memcpy(field_bytes, default, @sizeOf(bool)),
                    .TYPE_BYTES => @memcpy(field_bytes, default, @sizeOf(BinaryData)),
                    .TYPE_STRING,
                    .TYPE_MESSAGE,
                    => { //
                        if (true) @panic("TODO - TYPE_STRING/MESSAGE default_value");
                        mem.writeIntLittle(usize, field_bytes[0..8], @ptrToInt(field.default_value));
                        const ptr = @intToPtr(?*anyopaque, @bitCast(usize, field_bytes[0..8].*));
                        std.log.debug("genericMessageInit() string/message ptr {} field.default_value {}", .{ ptrfmt(ptr), ptrfmt(field.default_value) });
                        assert(ptr == field.default_value);
                    },
                    .TYPE_ERROR, .TYPE_GROUP => unreachable,
                }
            }
        }
        return message;
    }

    fn intRangeLookup(field_ids: List(c_uint), value: usize) !usize {
        for (field_ids.slice()) |num, i|
            if (num == value) return i;
        return error.NotFound;
    }

    // TODO reduce size: make data a [*]const u8, add len: u32, make prefix_len a u32
    const ScannedMember = struct {
        key: Key,
        field: ?*const FieldDescriptor,
        data: []const u8,
        prefix_len: usize = 0,

        pub fn readVarint128(sm: ScannedMember, comptime T: type, comptime mode: IntMode) !T {
            var stream = std.io.fixedBufferStream(sm.data);
            return top_level.readVarint128(T, stream.reader(), mode);
        }

        fn maxB128Numbers(data: []const u8) usize {
            var result: usize = 0;
            for (data) |c| result += @boolToInt(c & 0x80 == 0);
            return result;
        }

        pub fn countPackedElements(sm: ScannedMember, typ: FieldDescriptorProto.Type) !usize {
            switch (typ) {
                .TYPE_SFIXED32,
                .TYPE_FIXED32,
                .TYPE_FLOAT,
                => {
                    if (sm.data.len % 4 != 0) {
                        std.log.err("length must be a multiple of 4 for fixed-length 32-bit types", .{});
                        return error.InvalidType;
                    }
                    return sm.data.len / 4;
                },
                .TYPE_SFIXED64, .TYPE_FIXED64, .TYPE_DOUBLE => {
                    if (sm.data.len % 8 != 0) {
                        std.log.err("length must be a multiple of 8 for fixed-length 64-bit types", .{});
                        return error.InvalidType;
                    }
                    return sm.data.len / 8;
                },
                .TYPE_ENUM,
                .TYPE_INT32,
                .TYPE_SINT32,
                .TYPE_UINT32,
                .TYPE_INT64,
                .TYPE_SINT64,
                .TYPE_UINT64,
                => return maxB128Numbers(sm.data),
                .TYPE_BOOL => return sm.data.len,
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

    fn isPackableType(typ: pb.descr.FieldDescriptorProto.Type) bool {
        return typ != .TYPE_STRING and typ != .TYPE_BYTES and
            typ != .TYPE_MESSAGE;
    }

    fn parsePackedRepeatedMember(
        scanned_member: ScannedMember,
        member: [*]u8,
        _: *Message,
        _: *Ctx,
    ) !void {
        const field = scanned_member.field orelse unreachable;
        var fbs = std.io.fixedBufferStream(scanned_member.data);
        const reader = fbs.reader();
        switch (field.type) {
            .TYPE_ENUM, .TYPE_INT32 => {
                while (true) {
                    const int = readVarint128(i32, reader, .int) catch |e| switch (e) {
                        error.EndOfStream => break,
                        else => return e,
                    };
                    listAppend(member, ListMut(i32), int);
                }
            },
            else => todo("{s}", .{@tagName(field.type)}),
        }
    }

    fn parseOneofMember(
        scanned_member: ScannedMember,
        member: [*]u8,
        message: *Message,
        ctx: *Ctx,
    ) !void {
        _ = member;
        _ = message;
        _ = ctx;
        const field = scanned_member.field orelse unreachable;
        // size_t *p_n = structMemberPtr(size_t, message, field.quantifier_offset);
        // size_t siz = repeatedEleSize(field.type);
        // void *array = *(char **) member + siz * (*p_n);
        // const uint8_t *at = scanned_member.data + scanned_member.prefix_len;
        // size_t rem = scanned_member.len - scanned_member.prefix_len;
        // size_t count = 0;

        switch (field.type) {
            else => todo("{s}", .{@tagName(field.type)}),
        }
    }

    fn parseOptionalMember(
        scanned_member: ScannedMember,
        member: [*]u8,
        message: *Message,
        ctx: *Ctx,
    ) !void {
        std.log.debug("parseOptionalMember({})", .{ptrfmt(member)});

        parseRequiredMember(scanned_member, member, message, ctx, true) catch |err|
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
        try parseRequiredMember(scanned_member, member, message, ctx, false);
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

        const wire_type = scanned_member.key.wire_type;
        const field = scanned_member.field orelse unreachable;
        std.log.debug(
            "parseRequiredMember() field={s} .{s} .{s} {}",
            .{
                field.name,
                @tagName(field.type),
                @tagName(scanned_member.key.wire_type),
                ptrfmt(member),
            },
        );

        switch (field.type) {
            .TYPE_INT32, .TYPE_ENUM => {
                const int = try scanned_member.readVarint128(i32, .int);
                std.log.info("{s}: {}", .{ field.name, int });
                if (field.label == .LABEL_REPEATED) {
                    listAppend(member, ListMut(i32), int);
                } else mem.writeIntLittle(i32, member[0..4], int);
            },
            .TYPE_BOOL => member[0] = scanned_member.data[0],
            .TYPE_STRING => {
                if (wire_type != .LEN) return error.FieldMissing;

                const bytes = try ctx.alloc.dupe(u8, scanned_member.data);
                if (field.label == .LABEL_REPEATED) {
                    listAppend(member, ListMut(String), String.init(bytes));
                } else {
                    var s = ptrAlignCast(*String, member);
                    s.* = String.init(bytes);
                }
                std.log.info("{s}: '{s}'", .{ field.name, bytes });
            },
            .TYPE_MESSAGE => {
                if (wire_type != .LEN) {
                    std.log.err("unexpected wire_type .{s}", .{@tagName(wire_type)});
                    return error.FieldMissing;
                }

                std.log.debug(
                    "parsing message field '{s}' len {} member {}",
                    .{ field.name, scanned_member.data.len, ptrfmt(member) },
                );
                if (field.descriptor == null) {
                    std.log.err("field.descriptor == null field {}", .{field.*});
                    return error.DescriptorMissing;
                }

                var limctx = ctx.withData(scanned_member.data);
                const field_desc = field.getDescriptor(MessageDescriptor);
                std.log.debug(
                    ".{s} {s} sizeof={}",
                    .{ field.label.tagName(), field_desc.name, field_desc.sizeof_message },
                );

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

    fn parseMember(scanned_member: ScannedMember, message: *Message, ctx: *Ctx) !void {
        const field = scanned_member.field orelse {
            var ufield = try ctx.alloc.create(pbtypes.MessageUnknownField);
            ufield.* = .{
                .key = scanned_member.key,
                .data = String.init(try ctx.alloc.dupe(u8, scanned_member.data)),
            };
            message.unknown_fields.appendAssumeCapacity(ufield);
            return;
        };

        std.log.debug(
            "parseMember() '{s}' .{s} .{s} ",
            .{ field.name, @tagName(field.label), @tagName(field.type) },
        );
        var member = structMemberP(message, field.offset);
        return switch (field.label) {
            .LABEL_REQUIRED => parseRequiredMember(scanned_member, member, message, ctx, true),
            .LABEL_OPTIONAL, .LABEL_ERROR => if (flagsContain(field.flags, FieldFlag.FLAG_ONEOF))
                parseOneofMember(scanned_member, member, message, ctx)
            else
                parseOptionalMember(scanned_member, member, message, ctx),

            .LABEL_REPEATED => if (scanned_member.key.wire_type == .LEN and
                (flagsContain(field.flags, FieldFlag.FLAG_PACKED) or isPackableType(field.type)))
                parsePackedRepeatedMember(scanned_member, member, message, ctx)
            else
                parseRepeatedMember(scanned_member, member, message, ctx),
        };
    }

    pub fn deserialize(desc: *const MessageDescriptor, ctx: *Ctx) Error!*Message {
        var buf = try ctx.alloc.alignedAlloc(
            u8,
            common.ptrAlign(*Message),
            desc.sizeof_message,
        );
        var message = ptrAlignCast(*Message, buf.ptr);
        errdefer message.deinit(ctx.alloc);
        message.descriptor = null; // make sure uninit

        const show_summary = false;
        var tmpbuf: if (show_summary) [mem.page_size]u8 else void = undefined;

        var last_field: ?*const FieldDescriptor = desc.fields.items[0];
        var last_field_index: u7 = 0;
        // TODO make this dynamic
        var required_fields_bitmap = std.StaticBitSet(128).initEmpty();
        var n_unknown: u32 = 0;
        assert(desc.magic == pbtypes.MESSAGE_DESCRIPTOR_MAGIC);

        std.log.info("\n+++ deserialize {s} {}-{}/{} isInit={} size=0x{x}/{} data len {} +++", .{
            desc.name,
            ptrfmt(buf.ptr),
            ptrfmt(buf.ptr + buf.len),
            buf.len,
            message.isInit(),
            desc.sizeof_message,
            desc.sizeof_message,
            ctx.data.len,
        });
        if (!message.isInit()) {
            if (desc.message_init) |init| {
                init(buf.ptr, buf.len);
                std.log.debug(
                    "(init) called {s}.initBytes({}, {})",
                    .{ message.descriptor.?.name, ptrfmt(buf.ptr), buf.len },
                );
            } else {
                message.* = genericMessageInit(desc);
            }
        }

        if (show_summary) mem.copy(u8, &tmpbuf, buf);
        var sfa = std.heap.stackFallback(@sizeOf(ScannedMember) * 16, ctx.alloc);
        const sfalloc = sfa.get();
        var scanned_members: std.ArrayListUnmanaged(ScannedMember) = .{};
        defer scanned_members.deinit(sfalloc);
        while (true) {
            const key = ctx.readKey() catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
            };
            std.log.debug("(scan) -- key wire_type=.{s} field_id={} --", .{
                @tagName(key.wire_type),
                key.field_id,
            });
            var mfield: ?*const FieldDescriptor = null;
            if (last_field == null or last_field.?.id != key.field_id) {
                if (intRangeLookup(desc.field_ids, key.field_id)) |field_index| {
                    std.log.debug(
                        "(scan) found field_id={} at index={}",
                        .{ key.field_id, field_index },
                    );
                    mfield = desc.fields.items[field_index];
                    last_field = mfield;
                    last_field_index = @intCast(u7, field_index);
                } else |_| {
                    std.log.debug("(scan) field_id {} not found", .{key.field_id});
                    mfield = null;
                    n_unknown += 1;
                }
            } else mfield = last_field;

            if (mfield) |field| {
                if (field.label == .LABEL_REQUIRED)
                    // TODO make a message.requiredFieldIndex(field_index) method
                    // which ignores optional fields, allowing
                    // required_fields_bitmap to be smaller
                    required_fields_bitmap.set(last_field_index);
            }

            var sm: ScannedMember = .{ .key = key, .field = mfield, .data = ctx.data };

            switch (key.wire_type) {
                .VARINT => {
                    const startlen = ctx.data.len;
                    _ = try ctx.readVarint128(usize, .int);
                    sm.data.len += startlen - ctx.data.len;
                },
                .I64 => {
                    if (ctx.data.len < 8) {
                        std.log.err(
                            "too short after 64 bit wiretype at offset {}",
                            .{ctx.bytesRead()},
                        );
                        return error.InvalidData;
                    }
                    sm.data.len = 8;
                },
                .I32 => {
                    if (ctx.data.len < 4) {
                        std.log.err(
                            "too short after 32 bit wiretype at offset {}",
                            .{ctx.bytesRead()},
                        );
                        return error.InvalidData;
                    }
                    sm.data.len = 4;
                },
                .LEN => {
                    const lens = try ctx.scanLengthPrefixedData();
                    sm.data = sm.data[lens[0]..];
                    sm.data.len = lens[1];
                    sm.prefix_len = lens[0];
                    ctx.skip(sm.data.len);
                },
                else => {
                    std.log.err("unsupported tag .{s} at offset {}", .{
                        @tagName(key.wire_type),
                        ctx.bytesRead(),
                    });
                    return error.InvalidType;
                },
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
                    if (key.wire_type == .LEN and
                        (flagsContain(field.flags, FieldFlag.FLAG_PACKED) or
                        isPackableType(field.type)))
                    {
                        list.len += try sm.countPackedElements(field.type);
                    } else list.len += 1;
                }
            } else std.log.debug("(scan) field {s} unknown", .{desc.name});
            try scanned_members.append(sfalloc, sm);
        }

        var missing_any_required = false;
        for (desc.fields.slice()) |field, i| {
            if (field.label == .LABEL_REPEATED) {
                const size = pb.protobuf.repeatedEleSize(field.type);
                // list ele type doesn't matter, just want to change len
                const list = structMemberPtr(ListMut(u8), message, field.offset);
                if (list.len != 0) {
                    std.log.debug(
                        "(scan) field '{s}' - allocating {}={}*{} list bytes",
                        .{ field.name, size * list.len, size, list.len },
                    );
                    // TODO CLEAR_REMAINING_N_PTRS
                    var bytes = try ctx.alloc.alloc(u8, size * list.len);
                    list.items = bytes.ptr;
                    list.cap = list.len;
                    list.len = 0;
                }
            } else if (field.label == .LABEL_REQUIRED) {
                if (field.default_value == null and
                    !required_fields_bitmap.isSet(i))
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
            try message.unknown_fields.ensureTotalCapacity(ctx.alloc, n_unknown);

        for (scanned_members.items) |sm|
            try parseMember(sm, message, ctx);

        assert(message.unknown_fields.len == message.unknown_fields.cap);

        if (show_summary) {
            std.log.info("\n   --- summary for {s} ---", .{desc.name});
            var i: usize = 0;
            var last_start: usize = 0;
            while (i + 8 < buf.len) : (i += 8) {
                if (!mem.eql(u8, tmpbuf[i..][0..8], buf[i..][0..8])) {
                    const start = i;
                    while (i < buf.len) : (i += 8) {
                        if (mem.eql(u8, tmpbuf[i..][0..8], buf[i..][0..8])) break;
                    }
                    const old = tmpbuf[start..i];
                    const new = buf[start..i];
                    const descfields = desc.fields.slice();
                    const fieldname = for (descfields) |f, j| {
                        if (f.offset > start) break if (j == 0)
                            "base"
                        else
                            descfields[j -| 1].name.slice();
                    } else descfields[descfields.len - 1].name.slice();
                    std.log.info("{s} - difference at {s}:0x{x}/{}\nold {any}\nnew{any}", .{
                        desc.name,
                        fieldname,
                        start,
                        start,
                        ptrAlignCast([*]*u8, old.ptr)[0 .. old.len / 8],
                        ptrAlignCast([*]*u8, new.ptr)[0 .. new.len / 8],
                    });
                    last_start = start;
                }
            }
        }
        std.log.info("\n--- deserialize {s} {}-{} isInit={} size=0x{x}/{} ---", .{
            desc.name,
            ptrfmt(buf.ptr),
            ptrfmt(buf.ptr + buf.len),
            message.isInit(),
            desc.sizeof_message,
            desc.sizeof_message,
        });
        return message;
    }
};

fn debugit(m: *Message, comptime T: type) void {
    const it = @ptrCast(*T, m);
    _ = it;

    @breakpoint();
}
