const std = @import("std");

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
