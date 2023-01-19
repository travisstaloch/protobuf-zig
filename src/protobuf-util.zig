const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const panicf = std.debug.panic;
const assert = std.debug.assert;
const types = @import("types.zig");
const Message = types.Message;
const MessageDescriptor = types.MessageDescriptor;
const WireType = types.WireType;
const BinaryType = types.BinaryType;
const Label = types.Label;
const FieldFlag = FieldDescriptor.FieldFlag;
const List = types.ListType;
const ListMut = types.ListTypeMut;
const IntRange = types.IntRange;
const FieldDescriptor = types.FieldDescriptor;
const BinaryData = types.BinaryData;
const String = types.String;
const virt_reader = @import("virtual-reader.zig");
const common = @import("common.zig");
const ptrAlignCast = common.ptrAlignCast;
const ptrfmt = common.ptrfmt;

pub fn firstNBytes(s: []const u8, n: usize) []const u8 {
    return s[0..@min(s.len, n)];
}
pub fn todo(comptime fmt: []const u8, args: anytype) noreturn {
    panicf("TODO" ++ fmt, args);
}
pub const LocalError = error{
    InvalidKey,
    NotEnoughBytesRead,
    Overflow,
    FieldMissing,
    OptionalFieldMissing,
    SubMessageMissing,
    DescriptorMissing,
};

pub const Error = std.mem.Allocator.Error ||
    std.fs.File.WriteFileError ||
    LocalError;

pub const Key = struct {
    wire_type: WireType,
    field_id: usize,
    pub inline fn encode(key: Key) usize {
        return (key.field_id << 3) | @enumToInt(key.wire_type);
    }
    pub fn init(wire_type: WireType, field_id: usize) Key {
        return .{
            .wire_type = wire_type,
            .field_id = field_id,
        };
    }
};

pub const IntMode = enum { sint, int };

// Reads a varint from the reader and returns the value, eos (end of steam) pair.
// `mode = .sint` should used for sint32 and sint64 decoding when expecting lots of negative numbers as it
// uses zig zag encoding to reduce the size of negative values. negatives encoded otherwise (with `mode = .int`)
// will require extra size (10 bytes each) and are inefficient.
pub fn readVarint128(comptime T: type, reader: anytype, mode: IntMode) !T {
    const U = std.meta.Int(.unsigned, @bitSizeOf(T));
    var value = @bitCast(T, try std.leb.readULEB128(U, reader));

    if (mode == .sint) {
        const S = std.meta.Int(.signed, @bitSizeOf(T));
        const svalue = @bitCast(S, value);
        value = @bitCast(T, (svalue >> 1) ^ (-(svalue & 1)));
    }
    return value;
}

pub fn readEnum(comptime E: type, reader: anytype) !E {
    const value = try readVarint128(i64, reader, .int);
    return @intToEnum(E, if (@hasDecl(E, "is_aliased") and E.is_aliased)
        // TODO this doesn't seem entirely correct as the value can represent multiple tags.
        //      not enirely sure what to do here.
        E.values[@bitCast(u64, value)]
    else
        value);
}

pub fn readBool(reader: anytype) !bool {
    const byte = try readVarint128(u8, reader, .int);
    return byte != 0;
}

pub fn readKey(reader: anytype) !Key {
    const key = try readVarint128(usize, reader, .int);

    return Key{
        .wire_type = std.meta.intToEnum(WireType, key & 0b111) catch {
            std.log.err("readKey() invalid wire_type {}. key {}:0x{x}:0b{b:0>8} field_id {}", .{ @truncate(u3, key), key, key, key, key >> 3 });
            return error.InvalidKey;
        },
        .field_id = key >> 3,
    };
}

pub fn readString(reader: anytype, str: []u8, len: usize) !void {
    const amt = try reader.read(str[0..len]);
    std.log.debug("readString() '{s}'... len {} amt {}", .{ firstNBytes(str[0..len], 10), len, amt });
    if (amt != len) return error.NotEnoughBytesRead;
}

pub fn readInt64(comptime T: type, reader: anytype) !T {
    return @bitCast(T, try reader.readIntLittle(u64));
}
pub fn readInt32(comptime T: type, reader: anytype) !T {
    return @bitCast(T, try reader.readIntLittle(u32));
}

pub fn context(reader: anytype, alloc: Allocator) Protobuf(virt_reader.VirtualReader(@TypeOf(reader.reader()).Error)).Ctx {
    return .{ .reader = virt_reader.virtualReader(reader), .alloc = alloc };
}

pub fn Protobuf(comptime Reader: type) type {
    return struct {
        const Self = @This();
        const Ctx = struct {
            // reader: Reader,
            data: []const u8,
            data_start: [*]const u8,
            alloc: Allocator,

            pub const Pb = Self;

            // pub fn withReader(self: @This(), reader: Reader) @This() {
            //     var res = self;
            //     res.reader = reader;
            //     return res;
            // }
            pub fn withData(self: @This(), data: []const u8) @This() {
                var res = self;
                res.data = data;
                res.data_start = data.ptr;
                return res;
            }

            pub fn deserialize(ctx: *Ctx, mdesc: *const MessageDescriptor) Error!*Message {
                return Self.deserialize(mdesc, ctx);
            }

            pub fn deserializeTo(ctx: *Ctx, desc: *const MessageDescriptor, buf: []u8) Error!*Message {
                return Self.deserializeTo(buf, desc, ctx);
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
                std.log.debug("genericMessageInit field name {s} default {} label {s}", .{ field.name.slice(), ptrfmt(field.default_value), @tagName(field.label) });
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
                        .TYPE_BYTES => @memcpy(field_bytes, default, @sizeOf(types.BinaryData)),
                        //
                        // The next line essentially implements a cast
                        //from const, which is totally unavoidable.
                        //
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

        const ScannedMember = struct {
            key: Key,
            field: ?*const FieldDescriptor,
        };

        fn repeatedEleSize(t: types.FieldDescriptorProto.Type) u8 {
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
                .TYPE_STRING => @sizeOf(String),
                .TYPE_MESSAGE => @sizeOf(*Message),
                .TYPE_BYTES => @sizeOf(BinaryData),
                .TYPE_ERROR, .TYPE_GROUP => unreachable,
            };
        }

        fn flagsContain(flags: anytype, flag: anytype) bool {
            const Set = std.enums.EnumSet(@TypeOf(flag));
            const I = @TypeOf(@as(Set, undefined).bits.mask);
            const bitset = Set{ .bits = .{ .mask = @truncate(I, flags) } };
            return bitset.contains(flag);
        }

        fn isPackableType(typ: types.FieldDescriptorProto.Type) bool {
            return typ != .TYPE_STRING and typ != .TYPE_BYTES and
                typ != .TYPE_MESSAGE;
        }

        fn assertIsMessageDescriptor(desc: *const MessageDescriptor) void {
            assert(desc.magic == types.MESSAGE_DESCRIPTOR_MAGIC);
        }

        fn requiredFieldBitmapIsSet(index: usize) bool {
            // (required_fields_bitmap[(index)/8] & (1UL<<((index)%8)))
            // return
            _ = index;
            todo("requiredFieldBitmapIsSet", .{});
        }

        fn parsePackedRepeatedMember(scanned_member: ScannedMember, member: [*]u8, _: *Message, ctx: *Ctx) !void {
            const field = scanned_member.field orelse unreachable;
            // size_t *p_n = structMemberPtr(size_t, message, field.quantifier_offset);
            // size_t siz = repeatedEleSize(field.type);
            // void *array = *(char **) member + siz * (*p_n);
            // const uint8_t *at = scanned_member.data + scanned_member.length_prefix_len;
            // size_t rem = scanned_member.len - scanned_member.length_prefix_len;
            // size_t count = 0;
            var len = try readVarint128(usize, ctx.reader, .int);

            switch (field.type) {
                .TYPE_ENUM, .TYPE_INT32 => {
                    const list = ptrAlignCast(*ListMut(i32), member);
                    while (len > 0) : (len -= 1) {
                        // if(len == 0) break;
                        const int = try readVarint128(i32, ctx.reader, .int);
                        try list.append(ctx.alloc, int);
                    }
                },
                else => todo("{s}", .{@tagName(field.type)}),
            }
        }

        fn parseOneofMember(scanned_member: ScannedMember, member: [*]u8, message: *Message, ctx: *Ctx) !void {
            _ = member;
            _ = message;
            _ = ctx;
            const field = scanned_member.field orelse unreachable;
            // size_t *p_n = structMemberPtr(size_t, message, field.quantifier_offset);
            // size_t siz = repeatedEleSize(field.type);
            // void *array = *(char **) member + siz * (*p_n);
            // const uint8_t *at = scanned_member.data + scanned_member.length_prefix_len;
            // size_t rem = scanned_member.len - scanned_member.length_prefix_len;
            // size_t count = 0;

            switch (field.type) {
                else => todo("{s}", .{@tagName(field.type)}),
            }
        }

        fn parseOptionalMember(scanned_member: ScannedMember, member: [*]u8, message: *Message, ctx: *Ctx, subm: ?*Message) !void {
            std.log.debug("parseOptionalMember({})", .{ptrfmt(member)});

            parseRequiredMember(scanned_member, member, message, ctx, true, subm) catch |err| switch (err) {
                error.FieldMissing => return,
                else => return err,
            };
            std.log.debug("parseOptionalMember() setPresent({})", .{scanned_member.field.?.id});
            try message.setPresent(scanned_member.field.?.id);
        }

        fn parseRepeatedMember(
            scanned_member: ScannedMember,
            member: [*]u8,
            message: *Message,
            ctx: *Ctx,
            subm: ?*Message,
        ) !void {
            var field = scanned_member.field orelse unreachable;
            std.log.debug(
                "parseRepeatedMember() field name='{s}' offset=0x{x}/{}",
                .{ field.name.slice(), field.offset, field.offset },
            );
            try parseRequiredMember(scanned_member, member, message, ctx, false, subm);
        }

        fn listAppend(alloc: Allocator, member: [*]u8, comptime L: type, item: L.Child) !void {
            const list = ptrAlignCast(*L, member);
            // const len = list.len;
            // std.log.info("listAppend() 1 member {} list {}/{}/{}", .{ ptrfmt(member), ptrfmt(list.items), list.len, list.cap });
            try list.append(alloc, item);
            // std.log.info("listAppend() 2 member {} list {}/{}/{}", .{ ptrfmt(member), ptrfmt(list.items), list.len, list.cap });

        }

        fn parseRequiredMember(
            scanned_member: ScannedMember,
            member: [*]u8,
            message: *Message,
            ctx: *Ctx,
            maybe_clear: bool,
            msubm: ?*Message,
        ) !void {
            _ = maybe_clear;
            // TODO when there is a return FALSE make it an error.FieldMissing

            const wire_type = scanned_member.key.wire_type;
            const field = scanned_member.field orelse unreachable;
            std.log.debug(
                "parseRequiredMember() field={s} .{s} .{s} {}",
                .{
                    field.name.slice(),
                    @tagName(field.type),
                    @tagName(scanned_member.key.wire_type),
                    ptrfmt(member),
                },
            );

            switch (field.type) {
                .TYPE_INT32, .TYPE_ENUM => {
                    const int = try readVarint128(i32, ctx.reader, .int);
                    std.log.info("{s}: {}", .{ field.name.slice(), int });
                    if (field.label == .LABEL_REPEATED) {
                        try listAppend(ctx.alloc, member, ListMut(i32), int);
                    } else mem.writeIntLittle(i32, member[0..4], int);
                },
                .TYPE_STRING => {
                    if (wire_type != .length_delimited)
                        return error.FieldMissing;

                    const len = try readVarint128(usize, ctx.reader, .int);
                    const bytes = try ctx.alloc.allocSentinel(u8, len, 0);
                    try readString(ctx.reader, bytes, len);
                    if (field.label == .LABEL_REPEATED) {
                        try listAppend(ctx.alloc, member, ListMut(String), String.init(bytes));
                    } else {
                        var fbs = std.io.fixedBufferStream(member[0..@sizeOf(String)]);
                        try fbs.writer().writeStruct(String.init(bytes));
                    }
                    std.log.info("{s}: '{s}'", .{ field.name.slice(), bytes.ptr });
                },
                .TYPE_MESSAGE => {
                    if (wire_type != .length_delimited)
                        return error.FieldMissing;

                    const len = try readVarint128(usize, ctx.reader, .int);
                    std.log.debug(
                        "parsing message field '{s}' len {} member {}",
                        .{ field.name, len, ptrfmt(member) },
                    );
                    if (field.descriptor == null)
                        std.log.err("field.descriptor == null field {}", .{field.*});

                    var limreader = std.io.limitedReader(ctx.reader, len);
                    const vreader = virt_reader.virtualReader(&limreader);
                    var limctx = ctx.withReader(vreader);
                    const field_desc = field.getDescriptor(MessageDescriptor);
                    std.log.debug("sizeof_message {}", .{field_desc.sizeof_message});
                    const member_message = ptrAlignCast(*Message, member);
                    const messagep = @ptrCast([*]u8, message);
                    const offset = (@ptrToInt(member) - @ptrToInt(messagep));
                    assert(field.offset == offset);
                    std.log.debug(
                        "member_message is_init={} {} message {} offset 0x{x}/{}",
                        .{ member_message.isInit(), ptrfmt(member_message), ptrfmt(messagep), offset, offset },
                    );

                    if (field.label == .LABEL_REPEATED) {
                        // const buflen = ctx.buf.items.len;
                        std.log.info(".repeated {s} sizeof={}", .{ field_desc.name.slice(), field_desc.sizeof_message });
                        // try ctx.buf.ensureUnusedCapacity(ctx.alloc, field_desc.sizeof_message);
                        // ctx.buf.items.len += field_desc.sizeof_message;
                        // const tmpmessage = ptrAlignCast(*Message, ctx.buf.items.ptr);
                        // tmpmessage.descriptor = null; // make sure uninit
                        // const list = ptrAlignCast(*ListMut(*Message), member);
                        // const subm = try list.addOne(ctx.alloc);
                        // const subm = list.items[list.len - 1];
                        const subm = msubm orelse return error.SubMessageMissing;
                        // const subdesc = subm.descriptor orelse return error.DescriptorMissing;
                        assert(subm.descriptor == null);
                        const bytes = @ptrCast([*]u8, subm);
                        // assert(subm.descriptor == field_desc);
                        // subm.* = tmpmessage;
                        // _ = try deserializeTo(ctx.buf.items[buflen..][0..field_desc.sizeof_message], field_desc, &limctx);
                        const resm = try deserializeTo(bytes[0..field_desc.sizeof_message], field_desc, &limctx);
                        assert(resm == subm);
                        // const submessage = try deserialize(field_desc, &limctx);
                        // assert(submessage.isInit());
                        // list_idx.* = @bitCast(isize, try listAppend(ctx.alloc, member, ListMut(*Message), submessage));
                        // list_idx.* = @bitCast(isize, list.len);
                        // std.log.info("appended message {s} {} to {}", .{ field_desc.name.slice(), ptrfmt(submessage), ptrfmt(member) });
                    } else {
                        assert(member_message.isInit());
                        var buf = member[0..field_desc.sizeof_message];
                        // var buf = try ctx.alloc.alignedAlloc(u8, 8, field_desc.sizeof_message);
                        // const m = ptrAlignCast(*Message, buf.ptr);
                        // m.descriptor = null;
                        std.log.info(".single {s} sizeof={}", .{ field_desc.name.slice(), field_desc.sizeof_message });
                        _ = try deserializeTo(buf, field_desc, &limctx);
                    }
                },
                else => todo("{s} ", .{@tagName(field.type)}),
            }
        }

        fn parseMember(scanned_member: ScannedMember, message: *Message, ctx: *Ctx, subm: ?*Message) !void {
            const field = scanned_member.field orelse
                todo("unknown field", .{});

            std.log.debug("parseMember() '{s}' .{s} .{s} ", .{ field.name.slice(), @tagName(field.label), @tagName(field.type) });
            var member = structMemberP(message, field.offset);
            return switch (field.label) {
                .LABEL_REQUIRED => parseRequiredMember(scanned_member, member, message, ctx, true, subm),
                .LABEL_OPTIONAL, .LABEL_ERROR => if (flagsContain(field.flags, FieldFlag.FLAG_ONEOF))
                    parseOneofMember(scanned_member, member, message, ctx)
                else
                    return parseOptionalMember(scanned_member, member, message, ctx, subm),

                .LABEL_REPEATED => if (scanned_member.key.wire_type == .length_delimited and
                    (flagsContain(field.flags, FieldFlag.FLAG_PACKED) or isPackableType(field.type)))
                    parsePackedRepeatedMember(scanned_member, member, message, ctx)
                else
                    parseRepeatedMember(scanned_member, member, message, ctx, subm),
            };
        }

        pub fn deserialize(desc: *const MessageDescriptor, ctx: *Ctx) Error!*Message {
            var buf = try ctx.alloc.alignedAlloc(u8, common.ptrAlign(*Message), desc.sizeof_message);
            const m = ptrAlignCast(*Message, buf.ptr);
            m.descriptor = null; // make sure uninit
            return deserializeTo(buf, desc, ctx);
        }

        fn deserializeTo(buf: []u8, desc: *const MessageDescriptor, ctx: *Ctx) Error!*Message {
            // const desc = mdesc orelse unreachable;
            var tmpbuf: [mem.page_size]u8 = undefined;

            var last_field: ?*const FieldDescriptor = &desc.fields.items[0];
            // var last_field_index: usize = 0;
            var n_unknown: u32 = 0;
            assertIsMessageDescriptor(desc);
            var message = ptrAlignCast(*Message, buf.ptr);
            std.log.info("\n+++ deserialize {s} {}-{} isInit={} size=0x{x}/{} +++", .{
                desc.name.slice(),
                ptrfmt(buf.ptr),
                ptrfmt(buf.ptr + buf.len),
                message.isInit(),
                desc.sizeof_message,
                desc.sizeof_message,
            });
            std.log.debug("init1: message is_init={}", .{message.isInit()});
            if (!message.isInit()) {
                if (desc.message_init) |initfn| {
                    initfn(buf.ptr, buf.len);
                    std.log.debug("called {s}.initBytes({}, {})", .{ message.descriptor.?.name.slice(), ptrfmt(buf.ptr), buf.len });
                } else {
                    message.* = genericMessageInit(desc);
                    // @memset(bytes[@sizeOf(Message)..].ptr, 0, desc.sizeof_message - @sizeOf(Message));
                }
            }

            const orig_desc = message.descriptor;
            mem.copy(u8, &tmpbuf, buf);
            // const start_len = ctx.sub_messages.items.len;
            while (true) {
                std.log.debug(
                    "init2: message is_init={} descriptor={} message {}",
                    .{ message.isInit(), ptrfmt(message.descriptor), ptrfmt(message) },
                );
                assert(message.descriptor == orig_desc);
                assert(message.isInit());

                const key = readKey(ctx.reader) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => return e,
                };
                std.log.debug("-- key wire_type=.{s} field_id={} --", .{
                    @tagName(key.wire_type),
                    key.field_id,
                });
                var mfield: ?*const FieldDescriptor = null;
                if (last_field == null or last_field.?.id != key.field_id) {
                    if (intRangeLookup(desc.field_ids, key.field_id)) |field_index| {
                        std.log.debug("found field_id={} at index={}", .{ key.field_id, field_index });
                        mfield = &desc.fields.items[field_index];
                        last_field = mfield;
                        // last_field_index = field_index;
                    } else |_| {
                        std.log.debug("field_id {} not found", .{key.field_id});
                        mfield = null;
                        n_unknown += 1;
                    }
                } else mfield = last_field;
                const field = mfield orelse todo("handle field not found", .{});
                if (field.label == .LABEL_REQUIRED)
                    todo("requiredFieldBitmapSet(last_field_index)", .{});

                std.log.info("field {}.{} (+0x{x}/{}={})", .{ desc.name, field.name, field.offset, field.offset, ptrfmt(buf.ptr + field.offset) });

                const msubm = if (field.label == .LABEL_REPEATED and field.type == .TYPE_MESSAGE) blk: {
                    const field_desc = field.getDescriptor(MessageDescriptor);
                    const bytes = try ctx.alloc.alignedAlloc(u8, common.ptrAlign(*Message), field_desc.sizeof_message);
                    const subm = ptrAlignCast(*Message, bytes.ptr);
                    subm.descriptor = null;

                    // // if (msubm) |subm| {
                    // //     const list = structMemberPtr(ListMut(*Message), message, field.offset);
                    const list = structMemberPtr(ListMut(*Message), message, field.offset);
                    // const len = list.len;
                    try list.append(ctx.alloc, subm);
                    // try listAppend(ctx.alloc, structMemberP(message, field.offset), ListMut(*Message), subm);
                    // }
                    std.log.info(
                        "pre-append {}.{}({}) to list {}/{}/{}",
                        .{ desc.name, field.name, ptrfmt(subm), ptrfmt(list.items), list.len, list.cap },
                    );
                    break :blk subm;
                } else null;
                try parseMember(.{ .key = key, .field = field }, message, ctx, msubm);
                // std.log.info("{}.{} list_idx {}", .{ desc.name, field.name, list_idx });
                // if (list_idx >= 0) {
                //     assert(field.label == .LABEL_REPEATED);
                //     const member = @ptrCast([*]u8, message) + field.offset;
                //     const field_desc = field.getDescriptor(MessageDescriptor);

                //     // const duped = try ctx.alloc.dupe(u8, ctx.buf.items[0..field_desc.sizeof_message]);
                //     const duped = try ctx.alloc.alignedAlloc(u8, @alignOf(*Message), field_desc.sizeof_message);
                //     mem.copy(u8, duped, ctx.buf.items[0..field_desc.sizeof_message]);
                //     ctx.buf.items.len -= field_desc.sizeof_message;
                //     const list = ptrAlignCast(*ListMut(*Message), member);
                //     const subm = ptrAlignCast(*Message, duped.ptr);
                //     // try list.append(ctx.alloc, subm);
                //     try ctx.sub_messages.append(ctx.alloc, .{ list, subm });
                //     // std.log.info("{s}({}).{s}(+0x{x}/{}={}) list={}/{}/{} list[{}]={}", .{
                //     //     desc.name,
                //     //     ptrfmt(message),
                //     //     field.name,
                //     //     field.offset,
                //     //     field.offset,
                //     //     ptrfmt(member),
                //     //     ptrfmt(list.items),
                //     //     list.len,
                //     //     list.cap,
                //     //     list_idx,
                //     //     ptrfmt(list.items[@bitCast(usize, list_idx)]),
                //     // });
                //     const childdesc = subm.descriptor.?;
                //     std.log.info("saved {s}({}) to {s} list={} ctx buf={}/{}, sub_messages={}/{}", .{
                //         childdesc.name,
                //         ptrfmt(subm),
                //         desc.name,
                //         // field.name,
                //         // field.offset,
                //         // field.offset,
                //         // ptrfmt(subm),
                //         ptrfmt(list),
                //         ctx.buf.items.len,
                //         ctx.buf.capacity,
                //         ctx.sub_messages.items.len,
                //         ctx.sub_messages.capacity,
                //     });
                // }
            }
            if (true) {
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
                            if (f.offset > start) break if (j == 0) "base" else descfields[j -| 1].name.slice();
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
            // for (ctx.sub_messages.items[start_len..]) |list_subm, list_idx| {
            //     _ = list_idx;
            //     const list = list_subm[0];
            //     const subm: *Message = list_subm[1];
            //     // std.log.info("list {}/{}/{}", .{ptrfmt(list), list.len, list.cap});
            //     // std.log.info("list {}", .{ptrfmt(list)});
            //     // std.log.info("{s}({}) list={}/{}/{} list[{}]", .{
            //     std.log.info("{s} subm={} ctx buf={}/{}, sub_messages={}/{}", .{
            //         desc.name,
            //         ptrfmt(subm),
            //         ctx.buf.items.len,
            //         ctx.buf.capacity,
            //         ctx.sub_messages.items.len,
            //         ctx.sub_messages.capacity,
            //     });
            //     const childdesc = subm.descriptor.?;
            //     std.log.info("appending {s}({}) list={}", .{
            //         childdesc.name,
            //         ptrfmt(subm),
            //         // field.name,
            //         // field.offset,
            //         // field.offset,
            //         // ptrfmt(subm),
            //         ptrfmt(list),
            //         // ptrfmt(list.items),
            //         // list.len,
            //         // list.cap,
            //         // list_idx,
            //         // ptrfmt(list.items[@bitCast(usize, list_idx)]),
            //     });
            //     // try list.append(ctx.alloc, subm);
            //     list.items[list.len - 1] = subm;
            // }
            // ctx.sub_messages.items.len = start_len;
            std.log.info("\n--- deserialize {s} {}-{} isInit={} size=0x{x}/{} ---", .{
                desc.name.slice(),
                ptrfmt(buf.ptr),
                ptrfmt(buf.ptr + buf.len),
                message.isInit(),
                desc.sizeof_message,
                desc.sizeof_message,
            });
            // if (mem.eql(u8, "FileDescriptorProto", message.descriptor.?.name.slice()))
            //     debugit(message, types.FileDescriptorProto);
            // @breakpoint();
            return message;
        }
        fn deserializeToOld(buf: []u8, desc: *const MessageDescriptor, ctx: *Ctx) Error!*Message {
            // const desc = mdesc orelse unreachable;
            var tmpbuf: [mem.page_size]u8 = undefined;

            var last_field: ?*const FieldDescriptor = &desc.fields.items[0];
            // var last_field_index: usize = 0;
            var n_unknown: u32 = 0;
            assertIsMessageDescriptor(desc);
            var message = ptrAlignCast(*Message, buf.ptr);
            std.log.info("\n+++ deserialize {s} {}-{} isInit={} size=0x{x}/{} +++", .{
                desc.name.slice(),
                ptrfmt(buf.ptr),
                ptrfmt(buf.ptr + buf.len),
                message.isInit(),
                desc.sizeof_message,
                desc.sizeof_message,
            });
            std.log.debug("init1: message is_init={}", .{message.isInit()});
            if (!message.isInit()) {
                if (desc.message_init) |initfn| {
                    initfn(buf.ptr, buf.len);
                    std.log.debug("called {s}.initBytes({}, {})", .{ message.descriptor.?.name.slice(), ptrfmt(buf.ptr), buf.len });
                } else {
                    message.* = genericMessageInit(desc);
                    // @memset(bytes[@sizeOf(Message)..].ptr, 0, desc.sizeof_message - @sizeOf(Message));
                }
            }

            const orig_desc = message.descriptor;
            mem.copy(u8, &tmpbuf, buf);
            // const start_len = ctx.sub_messages.items.len;
            while (true) {
                std.log.debug(
                    "init2: message is_init={} descriptor={} message {}",
                    .{ message.isInit(), ptrfmt(message.descriptor), ptrfmt(message) },
                );
                assert(message.descriptor == orig_desc);
                assert(message.isInit());

                const key = readKey(ctx.reader) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => return e,
                };
                std.log.debug("-- key wire_type=.{s} field_id={} --", .{
                    @tagName(key.wire_type),
                    key.field_id,
                });
                var mfield: ?*const FieldDescriptor = null;
                if (last_field == null or last_field.?.id != key.field_id) {
                    if (intRangeLookup(desc.field_ids, key.field_id)) |field_index| {
                        std.log.debug("found field_id={} at index={}", .{ key.field_id, field_index });
                        mfield = &desc.fields.items[field_index];
                        last_field = mfield;
                        // last_field_index = field_index;
                    } else |_| {
                        std.log.debug("field_id {} not found", .{key.field_id});
                        mfield = null;
                        n_unknown += 1;
                    }
                } else mfield = last_field;
                const field = mfield orelse todo("handle field not found", .{});
                if (field.label == .LABEL_REQUIRED)
                    todo("requiredFieldBitmapSet(last_field_index)", .{});

                std.log.info("field {}.{} (+0x{x}/{}={})", .{ desc.name, field.name, field.offset, field.offset, ptrfmt(buf.ptr + field.offset) });

                const msubm = if (field.label == .LABEL_REPEATED and field.type == .TYPE_MESSAGE) blk: {
                    const field_desc = field.getDescriptor(MessageDescriptor);
                    const bytes = try ctx.alloc.alignedAlloc(u8, common.ptrAlign(*Message), field_desc.sizeof_message);
                    const subm = ptrAlignCast(*Message, bytes.ptr);
                    subm.descriptor = null;

                    // // if (msubm) |subm| {
                    // //     const list = structMemberPtr(ListMut(*Message), message, field.offset);
                    const list = structMemberPtr(ListMut(*Message), message, field.offset);
                    // const len = list.len;
                    try list.append(ctx.alloc, subm);
                    // try listAppend(ctx.alloc, structMemberP(message, field.offset), ListMut(*Message), subm);
                    // }
                    std.log.info(
                        "pre-append {}.{}({}) to list {}/{}/{}",
                        .{ desc.name, field.name, ptrfmt(subm), ptrfmt(list.items), list.len, list.cap },
                    );
                    break :blk subm;
                } else null;
                try parseMember(.{ .key = key, .field = field }, message, ctx, msubm);
                // std.log.info("{}.{} list_idx {}", .{ desc.name, field.name, list_idx });
                // if (list_idx >= 0) {
                //     assert(field.label == .LABEL_REPEATED);
                //     const member = @ptrCast([*]u8, message) + field.offset;
                //     const field_desc = field.getDescriptor(MessageDescriptor);

                //     // const duped = try ctx.alloc.dupe(u8, ctx.buf.items[0..field_desc.sizeof_message]);
                //     const duped = try ctx.alloc.alignedAlloc(u8, @alignOf(*Message), field_desc.sizeof_message);
                //     mem.copy(u8, duped, ctx.buf.items[0..field_desc.sizeof_message]);
                //     ctx.buf.items.len -= field_desc.sizeof_message;
                //     const list = ptrAlignCast(*ListMut(*Message), member);
                //     const subm = ptrAlignCast(*Message, duped.ptr);
                //     // try list.append(ctx.alloc, subm);
                //     try ctx.sub_messages.append(ctx.alloc, .{ list, subm });
                //     // std.log.info("{s}({}).{s}(+0x{x}/{}={}) list={}/{}/{} list[{}]={}", .{
                //     //     desc.name,
                //     //     ptrfmt(message),
                //     //     field.name,
                //     //     field.offset,
                //     //     field.offset,
                //     //     ptrfmt(member),
                //     //     ptrfmt(list.items),
                //     //     list.len,
                //     //     list.cap,
                //     //     list_idx,
                //     //     ptrfmt(list.items[@bitCast(usize, list_idx)]),
                //     // });
                //     const childdesc = subm.descriptor.?;
                //     std.log.info("saved {s}({}) to {s} list={} ctx buf={}/{}, sub_messages={}/{}", .{
                //         childdesc.name,
                //         ptrfmt(subm),
                //         desc.name,
                //         // field.name,
                //         // field.offset,
                //         // field.offset,
                //         // ptrfmt(subm),
                //         ptrfmt(list),
                //         ctx.buf.items.len,
                //         ctx.buf.capacity,
                //         ctx.sub_messages.items.len,
                //         ctx.sub_messages.capacity,
                //     });
                // }
            }
            if (true) {
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
                            if (f.offset > start) break if (j == 0) "base" else descfields[j -| 1].name.slice();
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
            // for (ctx.sub_messages.items[start_len..]) |list_subm, list_idx| {
            //     _ = list_idx;
            //     const list = list_subm[0];
            //     const subm: *Message = list_subm[1];
            //     // std.log.info("list {}/{}/{}", .{ptrfmt(list), list.len, list.cap});
            //     // std.log.info("list {}", .{ptrfmt(list)});
            //     // std.log.info("{s}({}) list={}/{}/{} list[{}]", .{
            //     std.log.info("{s} subm={} ctx buf={}/{}, sub_messages={}/{}", .{
            //         desc.name,
            //         ptrfmt(subm),
            //         ctx.buf.items.len,
            //         ctx.buf.capacity,
            //         ctx.sub_messages.items.len,
            //         ctx.sub_messages.capacity,
            //     });
            //     const childdesc = subm.descriptor.?;
            //     std.log.info("appending {s}({}) list={}", .{
            //         childdesc.name,
            //         ptrfmt(subm),
            //         // field.name,
            //         // field.offset,
            //         // field.offset,
            //         // ptrfmt(subm),
            //         ptrfmt(list),
            //         // ptrfmt(list.items),
            //         // list.len,
            //         // list.cap,
            //         // list_idx,
            //         // ptrfmt(list.items[@bitCast(usize, list_idx)]),
            //     });
            //     // try list.append(ctx.alloc, subm);
            //     list.items[list.len - 1] = subm;
            // }
            // ctx.sub_messages.items.len = start_len;
            std.log.info("\n--- deserialize {s} {}-{} isInit={} size=0x{x}/{} ---", .{
                desc.name.slice(),
                ptrfmt(buf.ptr),
                ptrfmt(buf.ptr + buf.len),
                message.isInit(),
                desc.sizeof_message,
                desc.sizeof_message,
            });
            // if (mem.eql(u8, "FileDescriptorProto", message.descriptor.?.name.slice()))
            //     debugit(message, types.FileDescriptorProto);
            // @breakpoint();
            return message;
        }
    };
}

fn debugit(m: *Message, comptime T: type) void {
    const it = @ptrCast(*T, m);
    _ = it;

    @breakpoint();
}
