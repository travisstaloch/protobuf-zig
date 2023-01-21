const std = @import("std");
const util = @import("protobuf-util.zig");
const extern_types = @import("extern-types.zig");
const segmented_list = @import("extern-segmented-list.zig");
const plugin = @import("google/protobuf/compiler/plugin.pb.zig");

pub usingnamespace plugin;
pub usingnamespace extern_types;
pub usingnamespace segmented_list;

pub const ListTypeMut = extern_types.ArrayListMut;
pub const ListType = extern_types.ArrayList;

pub fn IntegerBitset(comptime len: usize) type {
    const n = @max(8, std.math.ceilPowerOfTwo(usize, @max(len, 1)) catch unreachable);
    return std.meta.Int(.unsigned, n);
}

/// https://protobuf.dev/programming-guides/encoding/#structure
pub const WireType = enum(u8) {
    VARINT = 0,
    I64 = 1,
    LEN = 2,
    SGROUP = 3,
    EGROUP = 4,
    I32 = 5,
};

pub const Key = extern struct {
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
