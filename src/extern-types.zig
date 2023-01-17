//! structures which can be used in extern structs
//! includes String, ArrayList, ArrayListMut

const std = @import("std");
const types = @import("types.zig");

// a zero terminated slice of bytes
pub const String = extern struct {
    len: usize,
    items: [*:0]const u8,

    pub fn init(s: [:0]const u8) String {
        return .{ .items = s.ptr, .len = s.len };
    }
    pub fn initEmpty() String {
        return empty_str;
    }
    pub fn slice(s: String) [:0]const u8 {
        return s.items[0..s.len :0];
    }
    pub fn format(s: String, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        // try writer.print("{*}/{}-", .{ s.items, s.len });
        if (s.len > 0) _ = try writer.write(s.slice());
    }
};

pub var empty_str_arr = "".*;
pub const empty_str: String = String.init(&empty_str_arr); // .{ .items = &empty_str_arr, .len = 0 };

/// a version of std.ArrayList that can be used in extern structs
pub fn ArrayListMut(comptime T: type) type {
    return extern struct {
        len: usize = 0,
        cap: usize = 0,
        items: [*]T,

        pub usingnamespace ListMixins(T, @This(), []T);
    };
}

pub fn ArrayList(comptime T: type) type {
    return extern struct {
        len: usize = 0,
        cap: usize = 0,
        items: [*]const T,

        pub usingnamespace ListMixins(T, @This(), []const T);
    };
}

// pub fn ArrayListMutStable(comptime T: type) type {
//     return extern struct {
//         len: usize = 0,
//         cap: usize = 0,
//         items: *[*]T,

//         pub usingnamespace ListMixins(T, @This(), []T);
//     };
// }

pub const sentinel_pointer = 0xdead_0000_0000_0000;

pub fn ListMixins(comptime T: type, comptime Self: type, comptime Slice: type) type {
    return struct {
        pub const Child = T;
        pub const alignment = @alignOf(T);
        pub const Ptr = @TypeOf(@as(Self, undefined).items);
        pub const list_sentinel_ptr = @intToPtr(Ptr, sentinel_pointer);
        pub const is_stable = @typeInfo(Ptr).Pointer.size == .One;

        pub fn init(items: Slice) Self {
            return .{ .items = items.ptr, .len = items.len, .cap = items.len };
        }
        pub fn initEmpty() Self {
            return .{ .items = list_sentinel_ptr, .len = 0, .cap = 0 };
        }

        pub fn slice(self: Self) Slice {
            const items = blk: {
                if (is_stable) {
                    if (self.items == Self.list_sentinel_ptr) {
                        return &.{};
                    } else break :blk self.items.*;
                } else break :blk self.items;
            };
            return if (self.len > 0) items[0..self.len] else &.{};
        }

        pub fn format(l: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            // try writer.print("{*}/{}/{}", .{ l.items, l.len, l.cap });
            _ = try writer.write("{");
            if (l.len != 0) {
                for (l.slice()) |it, i| {
                    if (i != 0) _ = try writer.write(", ");
                    if (T == String) {
                        try writer.print("{s}", .{it.slice()});
                    } else try writer.print("{}", .{it});
                }
            }
            _ = try writer.write("}");
        }

        pub fn addOne(l: *Self, allocator: std.mem.Allocator) !*T {
            const len = l.len;
            try l.ensureTotalCapacity(allocator, len + 1);
            l.len += 1;
            return if (is_stable) &l.items.*[len] else &l.items[len];
        }

        pub fn append(l: *Self, allocator: std.mem.Allocator, item: T) !void {
            const ptr = try l.addOne(allocator);
            ptr.* = item;
        }

        pub fn ensureTotalCapacity(l: *Self, allocator: std.mem.Allocator, new_cap: usize) !void {
            if (l.cap >= new_cap) return;
            // std.log.debug("ensureTotalCapacity l.items {*} is_sentinel {}", .{ l.items, l.items == Self.list_sentinel_ptr });
            if (l.items == Self.list_sentinel_ptr) {
                const mem = try allocator.alignedAlloc(T, alignment, new_cap);
                if (is_stable) {
                    const child = @typeInfo(Ptr).Pointer.child;
                    l.items = try allocator.create(child);
                    l.items.* = mem.ptr;
                } else l.items = mem.ptr;
                l.cap = new_cap;
            } else {
                const old_memory = l.slice();
                if (allocator.resize(old_memory, new_cap)) {
                    l.cap = new_cap;
                } else {
                    const new_memory = try allocator.alignedAlloc(T, alignment, new_cap);
                    std.mem.copy(T, new_memory, l.slice());
                    allocator.free(old_memory);
                    if (is_stable)
                        l.items.* = new_memory.ptr
                    else
                        l.items = new_memory.ptr;
                    l.cap = new_memory.len;
                }
            }
            // if (is_stable)
            //     std.log.debug("ensureTotalCapacity l.items {*} l.items.* {*}", .{ l.items, l.items.* });
        }
    };
}

const testing = std.testing;
// const talloc = testing.allocator;
var tarena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const talloc = tarena.allocator();

test "ArrayListMut" {
    const L = ArrayListMut;
    const count = 5;
    const xs = [1]void{{}} ** count;
    var as = L(L(L(L(u8)))).initEmpty();
    for (xs) |_| {
        var bs = L(L(L(u8))).initEmpty();
        for (xs) |_| {
            var cs = L(L(u8)).initEmpty();
            for (xs) |_| {
                var ds = L(u8).initEmpty();
                for (xs) |_| try ds.append(talloc, 0);
                try cs.append(talloc, ds);
            }
            try bs.append(talloc, cs);
        }
        try as.append(talloc, bs);
    }
    try testing.expectEqual(xs.len, as.len);
    for (as.slice()) |a| {
        try testing.expectEqual(xs.len, a.len);
        for (a.slice()) |b| {
            try testing.expectEqual(xs.len, b.len);
            for (b.slice()) |c|
                try testing.expectEqual(xs.len, c.len);
        }
    }
}
