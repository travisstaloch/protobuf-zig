//! structures which can be used in extern structs
//! includes String, ArrayList, ArrayListMut

const std = @import("std");
const types = @import("types.zig");
const common = @import("common.zig");
const ptrfmt = common.ptrfmt;

const extern_types = @This();

// comment/uncomment this decl to toggle
// const fmtdebug = true;

// a zero terminated slice of bytes
pub const String = extern struct {
    len: usize,
    items: [*]const u8,

    pub fn init(s: []const u8) String {
        return .{ .items = s.ptr, .len = s.len };
    }
    pub fn initEmpty() String {
        return empty_str;
    }
    pub fn slice(s: String) []const u8 {
        return s.items[0..s.len];
    }
    pub const format = if (@hasDecl(extern_types, "fmtdebug")) formatDebug else formatStandard;
    pub fn formatDebug(s: String, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{*}/{}-", .{ s.items, s.len });
    }
    pub fn formatStandard(s: String, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
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

pub const sentinel_pointer = 0xdead_0000_0000;

pub fn ListMixins(comptime T: type, comptime Self: type, comptime Slice: type) type {
    return extern struct {
        pub const Child = T;
        pub const Ptr = std.meta.fieldInfo(Self, .items).type;
        pub const alignment = common.ptrAlign(Ptr);
        pub const list_sentinel_ptr = @intToPtr(Ptr, sentinel_pointer);

        pub fn init(items: Slice) Self {
            return .{ .items = items.ptr, .len = items.len, .cap = items.len };
        }
        pub fn initEmpty() Self {
            return .{ .items = list_sentinel_ptr };
        }

        pub fn slice(self: Self) Slice {
            return if (self.len > 0) self.items[0..self.len] else &.{};
        }

        pub const format = if (@hasDecl(extern_types, "fmtdebug")) formatDebug else formatStandard;

        pub fn formatDebug(l: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("{}/0x{x}/0x{}", .{ ptrfmt(l.items), l.len, l.cap });
            _ = try writer.write("...}");
        }
        pub fn formatStandard(l: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("{}/{}/{}", .{ ptrfmt(l.items), l.len, l.cap });
            _ = try writer.write("{");
            if (l.len != 0) {
                for (l.slice()) |it, i| {
                    if (i != 0) _ = try writer.write(", ");

                    try writer.print("{}", .{it});
                }
            }
            _ = try writer.write("}");
        }

        pub fn addOne(l: *Self, allocator: std.mem.Allocator) !*T {
            try l.ensureTotalCapacity(allocator, l.len + 1);
            defer l.len += 1;
            return &l.items[l.len];
        }

        pub fn addOneAssumeCapacity(l: *Self) *T {
            defer l.len += 1;
            return &l.items[l.len];
        }

        pub fn append(l: *Self, allocator: std.mem.Allocator, item: T) !void {
            const ptr = try l.addOne(allocator);
            ptr.* = item;
        }

        pub fn appendAssumeCapacity(l: *Self, item: T) void {
            const ptr = l.addOneAssumeCapacity();
            ptr.* = item;
        }

        pub fn ensureTotalCapacity(l: *Self, allocator: std.mem.Allocator, new_cap: usize) !void {
            if (l.cap >= new_cap) return;
            if (l.items == Self.list_sentinel_ptr) {
                const mem = try allocator.alignedAlloc(T, alignment, new_cap);
                l.items = mem.ptr;
                l.cap = new_cap;
            } else {
                const old_memory = l.slice();
                if (allocator.resize(old_memory, new_cap)) {
                    l.cap = new_cap;
                } else {
                    const new_memory = try allocator.alignedAlloc(T, alignment, new_cap);
                    std.mem.copy(T, new_memory, l.slice());
                    allocator.free(old_memory);
                    l.items = new_memory.ptr;
                    l.cap = new_memory.len;
                }
            }
        }
        const Fmt = struct {
            fmt: common.PtrFmt,
            len: usize,
            cap: usize,
            pub fn format(f: Fmt, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                try writer.print("{}/{}/{}", .{ f.fmt, f.len, f.cap });
            }
        };
        pub fn inspect(l: Self) Fmt {
            return .{ .fmt = ptrfmt(l.items), .len = l.len, .cap = l.cap };
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
