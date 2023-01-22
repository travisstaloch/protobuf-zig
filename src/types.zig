const std = @import("std");
const extern_types = @import("extern-types.zig");
const plugin = @import("google/protobuf/compiler/plugin.pb.zig");
const pbtypes = @import("protobuf-types.zig");
const assert = std.debug.assert;

pub usingnamespace plugin;
pub usingnamespace pbtypes;
pub usingnamespace extern_types;

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

/// helper for repeated message types.
/// checks that T is a pointer to struct and not pointer to String.
/// returns types.ListTypeMut(T)
pub fn ListMut(comptime T: type) type {
    const tinfo = @typeInfo(T);
    assert(tinfo == .Pointer);
    const Child = tinfo.Pointer.child;
    const cinfo = @typeInfo(Child);
    assert(cinfo == .Struct);
    assert(Child != extern_types.String);
    return extern_types.ArrayListMut(T);
}

/// helper for repeated scalar types.
/// checks that T is a String or other scalar type.
/// returns extern_types.ArrayListMut(T)
pub fn ListMutScalar(comptime T: type) type {
    assert(T == extern_types.String or !std.meta.trait.isContainer(T));
    return extern_types.ArrayListMut(T);
}
