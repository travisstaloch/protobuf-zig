const std = @import("std");
const mem = std.mem;

pub const log = if (@import("builtin").is_test)
    std.log.scoped(.@"protobuf-zig")
else
    struct {
        pub const debug = dummy_log;
        pub const info = dummy_log;
        pub const warn = dummy_log;
        pub const err = std.log.err;
        fn dummy_log(
            comptime format: []const u8,
            args: anytype,
        ) void {
            _ = args;
            _ = format;
        }
    };

pub const GenFormat = enum { zig, c };
pub const panicf = std.debug.panic;
pub fn ptrAlign(comptime Ptr: type) comptime_int {
    return @typeInfo(Ptr).Pointer.alignment;
}

pub fn ptrAlignCast(comptime Ptr: type, ptr: anytype) Ptr {
    return @ptrCast(Ptr, @alignCast(ptrAlign(Ptr), ptr));
}

pub fn ptrfmt(ptr: anytype) PtrFmt {
    return .{ .ptr = @ptrToInt(ptr) };
}

pub const PtrFmt = struct {
    ptr: usize,

    pub fn format(value: PtrFmt, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("@{x}", .{value.ptr});
    }
};

pub fn firstNBytes(s: []const u8, n: usize) []const u8 {
    return s[0..@min(s.len, n)];
}
pub fn afterLastIndexOf(s: []const u8, delimeter: u8) []const u8 {
    const start = if (mem.lastIndexOfScalar(u8, s, delimeter)) |i| i + 1 else 0;
    return s[start..];
}
/// split on last instance of 'delimeter'
pub fn splitOn(comptime T: type, s: T, delimeter: std.meta.Child(T)) [2]T {
    const start = if (mem.lastIndexOfScalar(std.meta.Child(T), s, delimeter)) |i| i else 0;
    return [2]T{ s[0..start], s[start + 1 ..] };
}
pub fn todo(comptime fmt: []const u8, args: anytype) noreturn {
    panicf("TODO " ++ fmt, args);
}
pub fn compileErr(comptime fmt: []const u8, args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(fmt, args));
}
