//! structures which can be used in extern structs
//! includes String, ArrayList, ArrayListMut

const std = @import("std");
const types = @import("types.zig");
const common = @import("common.zig");

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
        items: *[*]T,

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

pub const sentinel_pointer = 0xdead_0000_0000;

pub fn ListMixins(comptime T: type, comptime Self: type, comptime Slice: type) type {
    return extern struct {
        pub const Child = T;
        // pub const alignment = @alignOf(T);
        pub const Ptr = std.meta.fieldInfo(Self, .items).type;
        pub const alignment = common.ptrAlign(Ptr);
        pub const list_sentinel_ptr = @intToPtr(Ptr, sentinel_pointer);
        pub const is_stable = @typeInfo(Ptr).Pointer.size == .One;

        pub fn init(items: Slice) Self {
            return .{ .items = items.ptr, .len = items.len, .cap = items.len };
        }
        pub fn initEmpty() Self {
            return .{ .items = list_sentinel_ptr };
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
            // return &l.items[len];
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
                // l.items = mem.ptr;
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
                    // l.items = new_memory.ptr;
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

// pub fn LinkedList(comptime T: type) type {
//     return extern struct {
//         pub const Self = @This();
//         first: ?*Node = null,
//         last: ?*Node = null,

//         len: usize = 0,

//         pub const Node = extern struct {
//             next: ?*Node = null,
//             prev: ?*Node = null,
//             data: T,
//         };

//         pub fn initEmpty() Self {
//             return .{};
//         }
//         pub fn append(self: *Self, alloc: Allocator, item: T) !void {
//             const new = try allocator.create(Node);
//             new.data = t;

//         }
//         pub fn format(s: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
//             // try writer.print("{*}/{}-", .{ s.items, s.len });
//             var cur = self.first;
//             var i: usize = 0;
//             while (cur) : ({
//                 cur = cur.next;
//                 i += 1;
//             }) {
//                 if (i != 0) _ = try writer.write(", ");
//                 try writer.print("{}", .{cur.data});
//             }
//         }
//     };
// }

/// A tail queue is headed by a pair of pointers, one to the head of the
/// list and the other to the tail of the list. The elements are doubly
/// linked so that an arbitrary element can be removed without a need to
/// traverse the list. New elements can be added to the list before or
/// after an existing element, at the head of the list, or at the end of
/// the list. A tail queue may be traversed in either direction.
pub fn TailQueue(comptime T: type) type {
    return extern struct {
        const Self = @This();
        pub const Child = T;

        /// Node inside the linked list wrapping the actual data.
        pub const Node = struct {
            prev: ?*Node = null,
            next: ?*Node = null,
            data: T,
        };

        first: ?*Node = null,
        last: ?*Node = null,
        len: usize = 0,

        pub fn initEmpty() Self {
            return .{};
        }

        /// Insert a new node after an existing one.
        ///
        /// Arguments:
        ///     node: Pointer to a node in the list.
        ///     new_node: Pointer to the new node to insert.
        pub fn insertAfter(list: *Self, node: *Node, new_node: *Node) void {
            new_node.prev = node;
            if (node.next) |next_node| {
                // Intermediate node.
                new_node.next = next_node;
                next_node.prev = new_node;
            } else {
                // Last element of the list.
                new_node.next = null;
                list.last = new_node;
            }
            node.next = new_node;

            list.len += 1;
        }

        /// Insert a new node before an existing one.
        ///
        /// Arguments:
        ///     node: Pointer to a node in the list.
        ///     new_node: Pointer to the new node to insert.
        pub fn insertBefore(list: *Self, node: *Node, new_node: *Node) void {
            new_node.next = node;
            if (node.prev) |prev_node| {
                // Intermediate node.
                new_node.prev = prev_node;
                prev_node.next = new_node;
            } else {
                // First element of the list.
                new_node.prev = null;
                list.first = new_node;
            }
            node.prev = new_node;

            list.len += 1;
        }

        /// Concatenate list2 onto the end of list1, removing all entries from the former.
        ///
        /// Arguments:
        ///     list1: the list to concatenate onto
        ///     list2: the list to be concatenated
        pub fn concatByMoving(list1: *Self, list2: *Self) void {
            const l2_first = list2.first orelse return;
            if (list1.last) |l1_last| {
                l1_last.next = list2.first;
                l2_first.prev = list1.last;
                list1.len += list2.len;
            } else {
                // list1 was empty
                list1.first = list2.first;
                list1.len = list2.len;
            }
            list1.last = list2.last;
            list2.first = null;
            list2.last = null;
            list2.len = 0;
        }

        /// Insert a new node at the end of the list.
        ///
        /// Arguments:
        ///     new_node: Pointer to the new node to insert.
        pub fn append(list: *Self, alloc: std.mem.Allocator, item: T) !void {
            const new_node = try alloc.create(Node);
            new_node.data = item;
            if (list.last) |last| {
                // Insert after last.
                list.insertAfter(last, new_node);
            } else {
                // Empty list.
                list.prepend(new_node);
            }
        }

        /// Insert a new node at the beginning of the list.
        ///
        /// Arguments:
        ///     new_node: Pointer to the new node to insert.
        pub fn prepend(list: *Self, new_node: *Node) void {
            if (list.first) |first| {
                // Insert before first.
                list.insertBefore(first, new_node);
            } else {
                // Empty list.
                list.first = new_node;
                list.last = new_node;
                new_node.prev = null;
                new_node.next = null;

                list.len = 1;
            }
        }

        /// Remove a node from the list.
        ///
        /// Arguments:
        ///     node: Pointer to the node to be removed.
        pub fn remove(list: *Self, node: *Node) void {
            if (node.prev) |prev_node| {
                // Intermediate node.
                prev_node.next = node.next;
            } else {
                // First element of the list.
                list.first = node.next;
            }

            if (node.next) |next_node| {
                // Intermediate node.
                next_node.prev = node.prev;
            } else {
                // Last element of the list.
                list.last = node.prev;
            }

            list.len -= 1;
            std.debug.assert(list.len == 0 or (list.first != null and list.last != null));
        }

        /// Remove and return the last node in the list.
        ///
        /// Returns:
        ///     A pointer to the last node in the list.
        pub fn pop(list: *Self) ?*Node {
            const last = list.last orelse return null;
            list.remove(last);
            return last;
        }

        /// Remove and return the first node in the list.
        ///
        /// Returns:
        ///     A pointer to the first node in the list.
        pub fn popFirst(list: *Self) ?*Node {
            const first = list.first orelse return null;
            list.remove(first);
            return first;
        }

        pub fn at(list: *Self, index: usize) ?T {
            var iter = iterator(list.first);
            var i = index;
            while (true) {
                if (i == 0) return if (iter.next()) |n| n.data else null;
                i -= 1;
                _ = iter.next();
            }
        }

        pub fn iterator(node: ?*Node) Iterator {
            return .{ .node = node };
        }

        pub const Iterator = struct {
            node: ?*Node,

            pub fn next(self: *Iterator) ?*Node {
                defer {
                    if (self.node) |nd| {
                        if (nd.next) |n| self.node = n;
                    }
                }
                return self.node;
            }
        };
    };
}
