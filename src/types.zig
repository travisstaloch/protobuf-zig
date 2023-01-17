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

// https://developers.google.com/protocol-buffers/docs/encoding#structure
pub const WireType = enum(u8) {
    varint = 0,
    fixed64 = 1,
    length_delimited = 2,
    start_group = 3,
    end_group = 4,
    fixed32 = 5,
};
