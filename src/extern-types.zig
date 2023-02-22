//! structures which can be used in extern structs
//! includes String, ArrayList, ArrayListMut

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const ptrfmt = common.ptrfmt;
const pb = @import("protobuf");
const common = pb.common;

const extern_types = @This();

// comment/uncomment this decl to toggle
// const fmtdebug = true;

/// an extern slice of bytes
pub const String = extern struct {
    len: usize,
    items: [*]const u8,

    var empty_arr = "".*;
    pub const empty: String = String.init(&empty_arr);

    pub fn init(s: []const u8) String {
        return .{ .items = s.ptr, .len = s.len };
    }
    pub fn initEmpty() String {
        return empty;
    }
    pub fn deinit(s: String, allocator: mem.Allocator) void {
        if (s.len != 0 and s.items != empty.items)
            allocator.free(s.items[0..s.len]);
    }
    pub fn slice(s: String) []const u8 {
        return s.items[0..s.len];
    }
    pub const format = if (@hasDecl(extern_types, "fmtdebug"))
        formatDebug
    else
        formatStandard;
    pub fn formatDebug(
        s: String,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{*}/{}-", .{ s.items, s.len });
    }
    pub fn formatStandard(
        s: String,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (s.len > 0) try writer.print("{s}", .{s.slice()});
    }
};

/// helper for repeated message types.
/// checks that T is a pointer to struct and not pointer to String.
/// returns types.ArrayListMut(T)
pub fn ListMut(comptime T: type) type {
    const tinfo = @typeInfo(T);
    assert(tinfo == .Pointer);
    const Child = tinfo.Pointer.child;
    const cinfo = @typeInfo(Child);
    assert(cinfo == .Struct);
    assert(Child != String);
    return ArrayListMut(T);
}

/// helper for repeated scalar types.
/// checks that T is a String non container type.
/// returns ArrayList(T)
pub fn ListMutScalar(comptime T: type) type {
    assert(T == String or !std.meta.trait.isContainer(T));
    return ArrayListMut(T);
}

/// similar to std.ArrayList but can be used in extern structs
pub fn ArrayListMut(comptime T: type) type {
    return extern struct {
        len: usize = 0,
        cap: usize = 0,
        items: [*]T = undefined,

        pub usingnamespace ListMixins(T, @This(), []T);
    };
}

/// similar to std.ArrayList but can be used in extern structs.
/// a const version of ArrayListMut.
pub fn ArrayList(comptime T: type) type {
    return extern struct {
        len: usize = 0,
        cap: usize = 0,
        items: [*]const T = undefined,

        pub usingnamespace ListMixins(T, @This(), []const T);
    };
}

pub fn ListMixins(comptime T: type, comptime Self: type, comptime Slice: type) type {
    return extern struct {
        pub const Child = T;
        pub const Ptr = std.meta.fieldInfo(Self, .items).type;
        pub const alignment = common.ptrAlign(Ptr);

        pub fn init(items: Slice) Self {
            return .{ .items = items.ptr, .len = items.len, .cap = items.len };
        }
        pub fn deinit(l: Self, allocator: mem.Allocator) void {
            allocator.free(l.items[0..l.cap]);
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
            // try writer.print("{}/{}/{}", .{ ptrfmt(l.items), l.len, l.cap });
            _ = try writer.write("{");
            if (l.len != 0) {
                for (l.slice(), 0..) |it, i| {
                    if (i != 0) _ = try writer.write(", ");
                    try writer.print("{}", .{it});
                }
            }
            _ = try writer.write("}");
        }

        pub fn addOne(l: *Self, allocator: mem.Allocator) !*T {
            try l.ensureTotalCapacity(allocator, l.len + 1);
            defer l.len += 1;
            return &l.items[l.len];
        }

        pub fn addOneAssumeCapacity(l: *Self) *T {
            defer l.len += 1;
            return &l.items[l.len];
        }

        pub fn append(l: *Self, allocator: mem.Allocator, item: T) !void {
            const ptr = try l.addOne(allocator);
            ptr.* = item;
        }

        pub fn appendAssumeCapacity(l: *Self, item: T) void {
            const ptr = l.addOneAssumeCapacity();
            ptr.* = item;
        }

        pub fn appendSlice(l: *Self, allocator: mem.Allocator, items: []const T) !void {
            try l.ensureTotalCapacity(allocator, l.len + items.len);
            try l.appendSliceAssumeCapacity(items);
        }

        pub fn appendSliceAssumeCapacity(l: *Self, items: []const T) !void {
            const old_len = l.len;
            const new_len = old_len + items.len;
            assert(new_len <= l.cap);
            l.len = new_len;
            mem.copy(T, l.items[old_len..new_len], items);
        }

        pub fn ensureTotalCapacity(l: *Self, allocator: mem.Allocator, new_cap: usize) !void {
            if (l.cap >= new_cap) return;
            if (l.cap == 0) {
                const items = try allocator.alignedAlloc(T, alignment, new_cap);
                l.items = items.ptr;
                l.cap = new_cap;
            } else {
                const old_memory = l.slice();
                if (allocator.resize(old_memory, new_cap)) {
                    l.cap = new_cap;
                } else {
                    const new_items = try allocator.alignedAlloc(T, alignment, new_cap);
                    std.mem.copy(T, new_items, l.slice());
                    allocator.free(old_memory);
                    l.items = new_items.ptr;
                    l.cap = new_items.len;
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
var tarena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const talloc = tarena.allocator();

test "ArrayListMut" {
    const L = ArrayListMut;
    const count = 5;
    const xs = [1]void{{}} ** count;
    var as = L(L(L(L(u8)))){};
    for (xs) |_| {
        var bs = L(L(L(u8))){};
        for (xs) |_| {
            var cs = L(L(u8)){};
            for (xs) |_| {
                var ds = L(u8){};
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
