const std = @import("std");

pub usingnamespace @import("protobuf-types.zig");
pub usingnamespace @import("meta.zig");

pub fn IntegerBitset(comptime len: usize) type {
    const l = std.math.ceilPowerOfTwo(usize, @max(len, 1)) catch
        unreachable;
    return std.meta.Int(.unsigned, @max(8, l));
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

pub const Tag = extern struct {
    wire_type: WireType,
    // https://protobuf.dev/programming-guides/proto3/#assigning-field-numbers
    /// The smallest field number you can specify is 1, and the largest is 229
    field_id: u32,
    pub inline fn encode(key: Tag) u32 {
        return (key.field_id << 3) | @enumToInt(key.wire_type);
    }
    pub fn init(wire_type: WireType, field_id: u32) Tag {
        return .{
            .wire_type = wire_type,
            .field_id = field_id,
        };
    }
};
