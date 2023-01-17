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
    FieldNotPresent,
    OptionalFieldNotFound,
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
            reader: Reader,
            alloc: Allocator,
            buf: std.ArrayListUnmanaged(u8) = .{},

            pub const Pb = Self;

            pub fn withReader(self: @This(), reader: Reader) @This() {
                var res = self;
                res.reader = reader;
                return res;
            }

            pub fn deserialize(ctx: *Ctx, mdesc: ?*const MessageDescriptor) Error!*Message {
                return Self.deserialize(mdesc, ctx);
            }

            pub fn deserializeTo(ctx: *Ctx, desc: *const MessageDescriptor, buf: []u8) Error!*Message {
                return Self.deserializeTo(buf, desc, ctx);
            }
        };

        fn structMemberP(message: *Message, offset: usize) [*]u8 {
            const bytes = @ptrCast([*]u8, mem.asBytes(message));
            return bytes + offset;
        }

        fn structMemberPtr(comptime T: type, message: *Message, offset: usize) *align(1) T {
            const bytes = @ptrCast([*]u8, mem.asBytes(message));
            return @ptrCast(*align(1) T, bytes + offset);
        }

        fn structMember(comptime T: type, struct_p: *Message, struct_offset: usize) *align(1) T {
            return @ptrCast(*align(1) T, structMemberP(struct_p, struct_offset));
        }

        fn genericMessageInit(desc: *const MessageDescriptor) Message {
            var message = std.mem.zeroes(Message);
            message.descriptor = desc;

            for (desc.fields.slice()) |field| {
                std.log.debug("genericMessageInit field name {s} default {*} label {s}", .{ field.name.slice(), field.default_value, @tagName(field.label) });
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
                            std.log.debug("genericMessageInit() string/message ptr {*} field.default_value {*}", .{ ptr, field.default_value });
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
        fn intRangeLookup2(ranges: List(IntRange), value: usize) !usize {
            std.log.debug("intRangeLookup({any}, {})", .{ ranges.slice(), value });
            var n: usize = 0;
            var start: usize = 0;

            if (ranges.len == 0)
                return error.NotFound;
            n = ranges.len;
            while (n > 1) {
                var mid = start + n / 2;

                if (value < ranges.items[mid].start_value) {
                    n = mid - start;
                } else if (value >= ranges.items[mid].start_value +
                    @intCast(c_int, (ranges.items[mid + 1].orig_index -%
                    ranges.items[mid].orig_index)))
                {
                    var new_start = mid + 1;
                    n = start + n - new_start;
                    start = new_start;
                } else return (value - @intCast(usize, ranges.items[mid].start_value)) +
                    ranges.items[mid].orig_index;
            }
            if (n > 0) {
                const start_orig_index = ranges.items[start].orig_index;
                const range_size =
                    ranges.items[start + 1].orig_index - start_orig_index;

                if (ranges.items[start].start_value <= value and
                    value < (ranges.items[start].start_value + @intCast(c_int, range_size)))
                {
                    return (value - @intCast(usize, ranges.items[start].start_value)) +
                        start_orig_index;
                }
            }
            return error.NotFound;
        }

        const ScannedMember = struct {
            key: Key,
            field: ?*const FieldDescriptor,
        };

        fn sizeofEltInRepeatedArray(t: types.FieldDescriptorProto.Type) u8 {
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
            return typ != .TYPE_STRING and
                typ != .TYPE_BYTES and
                typ != .TYPE_MESSAGE;
        }

        fn assertIsMessageDescriptor(desc: *const MessageDescriptor) void {
            assert(desc.magic == types.MESSAGE_DESCRIPTOR_MAGIC);
        }

        fn requiredFieldBitmapIsSet(index: usize) bool {
            // (required_fields_bitmap[(index)/8] & (1UL<<((index)%8)))
            // return
            _ = index;
            panicf("TODO requiredFieldBitmapIsSet", .{});
        }

        fn parsePackedRepeatedMember(scanned_member: ScannedMember, member: [*]u8, message: *Message, ctx: *Ctx) !void {
            _ = .{ member, message, ctx };
            const field = scanned_member.field orelse unreachable;
            // size_t *p_n = STRUCT_MEMBER_PTR(size_t, message, field.quantifier_offset);
            // size_t siz = sizeofEltInRepeatedArray(field.type);
            // void *array = *(char **) member + siz * (*p_n);
            // const uint8_t *at = scanned_member.data + scanned_member.length_prefix_len;
            // size_t rem = scanned_member.len - scanned_member.length_prefix_len;
            // size_t count = 0;
            var len = try readVarint128(usize, ctx.reader, .int);

            switch (field.type) {
                .TYPE_ENUM, .TYPE_INT32 => {
                    const list = @ptrCast(*ListMut(i32), @alignCast(8, member));
                    while (len > 0) : (len -= 1) {
                        // if(len == 0) break;
                        const int = try readVarint128(i32, ctx.reader, .int);
                        try list.append(ctx.alloc, int);
                    }
                },
                else => panicf("TODO {s}", .{@tagName(field.type)}),
            }
        }

        fn parseOneofMember(scanned_member: ScannedMember, member: [*]u8, message: *Message, ctx: *Ctx) !void {
            _ = .{ member, message, ctx };
            const field = scanned_member.field orelse unreachable;
            // size_t *p_n = STRUCT_MEMBER_PTR(size_t, message, field.quantifier_offset);
            // size_t siz = sizeofEltInRepeatedArray(field.type);
            // void *array = *(char **) member + siz * (*p_n);
            // const uint8_t *at = scanned_member.data + scanned_member.length_prefix_len;
            // size_t rem = scanned_member.len - scanned_member.length_prefix_len;
            // size_t count = 0;

            switch (field.type) {
                else => panicf("TODO {s}", .{@tagName(field.type)}),
            }
        }

        fn parseOptionalMember(scanned_member: ScannedMember, member: [*]u8, message: *Message, ctx: *Ctx, list_idx: *isize) !void {
            std.log.debug("parseOptionalMember({*})", .{member});

            parseRequiredMember(scanned_member, member, message, ctx, true, list_idx) catch |err| switch (err) {
                error.FieldNotPresent => return,
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
            list_idx: *isize,
        ) !void {
            var field = scanned_member.field orelse unreachable;
            std.log.debug(
                "parseRepeatedMember() field name='{s}' offset=0x{x}/{}",
                .{ field.name.slice(), field.offset, field.offset },
            );
            try parseRequiredMember(scanned_member, member, message, ctx, false, list_idx);
        }

        fn listAppend(alloc: Allocator, member: [*]u8, comptime L: type, item: L.Child) !usize {
            const list = @ptrCast(*L, @alignCast(8, member));
            const len = list.len;
            std.log.info("listAppend() 1 member {*} list {*}/{}/{}", .{ member, @ptrCast([*]u8, list.items), list.len, list.cap });
            try list.append(alloc, item);
            std.log.info("listAppend() 2 member {*} list {*}/{}/{}", .{ member, @ptrCast([*]u8, list.items), list.len, list.cap });
            return len;
        }

        fn parseRequiredMember(
            scanned_member: ScannedMember,
            member: [*]u8,
            message: *Message,
            ctx: *Ctx,
            maybe_clear: bool,
            list_idx: *isize,
        ) !void {
            // TODO when there is a return FALSE make it an error.FieldNotPresent
            _ = .{ member, message, ctx, maybe_clear };

            const wire_type = scanned_member.key.wire_type;
            const field = scanned_member.field orelse unreachable;
            std.log.debug(
                "parseRequiredMember() field={s} .{s} .{s} {*}",
                .{
                    field.name.slice(),
                    @tagName(field.type),
                    @tagName(scanned_member.key.wire_type),
                    member,
                },
            );

            switch (field.type) {
                .TYPE_INT32 => {
                    const int = try readVarint128(u32, ctx.reader, .int);
                    std.log.info("{s}: {}", .{ field.name.slice(), int });
                    if (field.label == .LABEL_REPEATED) {
                        _ = try listAppend(ctx.alloc, member, ListMut(u32), int);
                    } else mem.writeIntLittle(u32, member[0..4], int);
                },
                .TYPE_STRING => {
                    if (wire_type != .length_delimited)
                        return error.FieldNotPresent;

                    const len = try readVarint128(usize, ctx.reader, .int);
                    const bytes = try ctx.alloc.allocSentinel(u8, len, 0);
                    try readString(ctx.reader, bytes, len);
                    if (field.label == .LABEL_REPEATED) {
                        _ = try listAppend(ctx.alloc, member, ListMut(String), String.init(bytes));
                    } else {
                        var fbs = std.io.fixedBufferStream(member[0..@sizeOf(String)]);
                        try fbs.writer().writeStruct(String.init(bytes));
                    }
                    std.log.info("{s}: '{s}' {*}", .{ field.name.slice(), bytes.ptr, bytes.ptr });
                },
                .TYPE_MESSAGE => {
                    if (wire_type != .length_delimited)
                        return error.FieldNotPresent;

                    const len = try readVarint128(usize, ctx.reader, .int);
                    std.log.debug(
                        "parsing message field '{s}' len {} member {*}",
                        .{ field.name, len, member },
                    );
                    if (field.descriptor == null)
                        std.log.err("field.descriptor == null field {}", .{field.*});

                    var limreader = std.io.limitedReader(ctx.reader, len);
                    const vreader = virt_reader.virtualReader(&limreader);
                    var limctx = ctx.withReader(vreader);
                    const field_desc = @ptrCast(
                        *const MessageDescriptor,
                        field.descriptor,
                    );
                    std.log.debug("sizeof_message {}", .{field_desc.sizeof_message});
                    const member_message = @ptrCast(*Message, @alignCast(8, member));
                    const messagep = @ptrCast([*]u8, message);
                    const offset = (@ptrToInt(member) - @ptrToInt(messagep));
                    assert(field.offset == offset);
                    std.log.debug(
                        "member_message is_init={} {*} message {*} offset 0x{x}/{}",
                        .{ member_message.isInit(), @ptrCast([*]u8, member_message), messagep, offset, offset },
                    );

                    if (field.label == .LABEL_REPEATED) {
                        std.log.info(".repeated {s} sizeof={}", .{ field_desc.name.slice(), field_desc.sizeof_message });
                        const submessage = try deserialize(field_desc, &limctx);
                        assert(submessage.isInit());
                        list_idx.* = @bitCast(isize, try listAppend(ctx.alloc, member, ListMut(*Message), submessage));
                        std.log.info("appended message {s} {*} to {*}", .{ field_desc.name.slice(), @ptrCast([*]u8, submessage), member });
                    } else {
                        assert(member_message.isInit());
                        var buf = member[0..field_desc.sizeof_message];
                        std.log.info(".single {s} sizeof={}", .{ field_desc.name.slice(), field_desc.sizeof_message });
                        const submessage = try deserializeTo(buf, field_desc, &limctx);
                        assert(@ptrCast([*]u8, submessage) == buf.ptr);
                    }
                },
                else => panicf("TODO {s} ", .{@tagName(field.type)}),
            }
        }

        fn parseMember(scanned_member: ScannedMember, message: *Message, ctx: *Ctx, list_idx: *isize) !void {
            const field = scanned_member.field orelse
                panicf("TODO unknown field", .{});

            std.log.debug("parseMember() '{s}' .{s} .{s} ", .{ field.name.slice(), @tagName(field.label), @tagName(field.type) });
            var member = @ptrCast([*]u8, message) + field.offset;
            return switch (field.label) {
                .LABEL_REQUIRED => parseRequiredMember(scanned_member, member, message, ctx, true, list_idx),
                .LABEL_OPTIONAL, .LABEL_ERROR => if (flagsContain(field.flags, FieldFlag.FLAG_ONEOF))
                    parseOneofMember(scanned_member, member, message, ctx)
                else
                    return parseOptionalMember(scanned_member, member, message, ctx, list_idx),

                .LABEL_REPEATED => if (scanned_member.key.wire_type == .length_delimited and
                    (flagsContain(field.flags, FieldFlag.FLAG_PACKED) or isPackableType(field.type)))
                    parsePackedRepeatedMember(scanned_member, member, message, ctx)
                else
                    parseRepeatedMember(scanned_member, member, message, ctx, list_idx),
            };
        }

        pub fn deserialize(mdesc: ?*const MessageDescriptor, ctx: *Ctx) Error!*Message {
            const desc = mdesc orelse unreachable;
            var buf = try ctx.alloc.alignedAlloc(u8, 8, desc.sizeof_message);
            const m = @ptrCast(*Message, @alignCast(8, buf.ptr));
            m.descriptor = null; // make sure uninit
            return deserializeTo(buf, desc, ctx);
        }

        fn deserializeTo(buf: []u8, mdesc: ?*const MessageDescriptor, ctx: *Ctx) Error!*Message {
            const desc = mdesc orelse unreachable;
            const debug = false;
            std.log.info("\n--- deserialize {s} {*} ---", .{ desc.name.slice(), buf.ptr });
            var tmpbuf: [mem.page_size]u8 = undefined;

            var last_field: ?*const FieldDescriptor = &desc.fields.items[0];
            // var last_field_index: usize = 0;
            var n_unknown: u32 = 0;
            assertIsMessageDescriptor(desc);
            var message = @ptrCast(*Message, @alignCast(8, buf.ptr));
            std.log.debug("init1: message is_init={}", .{message.isInit()});
            if (!message.isInit()) {
                if (desc.message_init) |initfn| {
                    initfn(buf.ptr, buf.len);
                    std.log.debug("called {s}.initBytes({*}, {})", .{ message.descriptor.?.name.slice(), buf.ptr, buf.len });
                } else {
                    message.* = genericMessageInit(desc);
                    // @memset(bytes[@sizeOf(Message)..].ptr, 0, desc.sizeof_message - @sizeOf(Message));
                }
            }

            const orig_desc = message.descriptor;
            mem.copy(u8, &tmpbuf, buf);
            while (true) {
                std.log.debug(
                    "init2: message is_init={} descriptor={*} message {*}",
                    .{ message.isInit(), @ptrCast([*]const u8, message.descriptor), @ptrCast([*]u8, message) },
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
                var field: [*c]const FieldDescriptor = null;
                if (last_field == null or last_field.?.id != key.field_id) {
                    if (intRangeLookup(desc.field_ids, key.field_id)) |field_index| {
                        std.log.debug("found field_id={} at index={}", .{ key.field_id, field_index });
                        field = desc.fields.items + field_index;
                        last_field = field;
                        // last_field_index = field_index;
                    } else |_| {
                        std.log.debug("field_id {} not found", .{key.field_id});
                        field = null;
                        n_unknown += 1;
                    }
                } else field = last_field;

                if (field != null and field.*.label == .LABEL_REQUIRED)
                    @panic("TODO REQUIRED_FIELD_BITMAP_SET(last_field_index)");

                std.log.debug("field {s}.{s}", .{ desc.name.slice(), field.*.name.slice() });

                var list_idx: isize = -1;
                try parseMember(.{ .key = key, .field = field }, message, ctx, &list_idx);
                if (list_idx >= 0) {
                    assert(field.*.label == .LABEL_REPEATED);
                    const member = @ptrCast([*]u8, message) + field.*.offset;
                    const list = @ptrCast(*ListMut(*u8), @alignCast(8, member));
                    std.log.info("{s}({*}).{s}(0x{x}/{}) list={*}/{}/{} list[{}]={*}", .{
                        desc.name,
                        @ptrCast(*u8, message),
                        field.*.name,
                        field.*.offset,
                        field.*.offset,
                        list.items,
                        list.len,
                        list.cap,
                        list_idx,
                        list.items[@bitCast(usize, list_idx)],
                    });
                }
            }
            if (debug) {
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
                        std.log.info("{s} - difference at 0x{x}/{}\nold {any}\nnew{any}", .{
                            desc.name,
                            start,
                            start,
                            @ptrCast([*]*u8, @alignCast(8, old.ptr))[0 .. old.len / 8],
                            @ptrCast([*]*u8, @alignCast(8, new.ptr))[0 .. new.len / 8],
                        });
                        last_start = start;
                    }
                }
            }

            return message;
        }
    };
}
