const std = @import("std");
const common = @import("common.zig");

pub fn VirtualReader(comptime ErrSet: type) type {
    const VirtualReaderImpl = struct {
        internal_ctx: *anyopaque,
        readFn: *const fn (context: *anyopaque, buffer: []u8) ErrSet!usize,
        pub fn read(context: @This(), buffer: []u8) ErrSet!usize {
            return context.readFn(context.internal_ctx, buffer);
        }
    };
    return std.io.Reader(VirtualReaderImpl, ErrSet, VirtualReaderImpl.read);
}

pub fn virtualReader(reader_impl_ptr: anytype) VirtualReader(@TypeOf(reader_impl_ptr.reader()).Error) {
    const ErrSet = @TypeOf(reader_impl_ptr.reader()).Error;
    const ReaderImplPtr = @TypeOf(reader_impl_ptr);
    const gen = struct {
        pub fn read(context: *anyopaque, buffer: []u8) !usize {
            return common.ptrAlignCast(ReaderImplPtr, context).reader().read(buffer);
        }
    };
    return VirtualReader(ErrSet){
        .context = .{
            .internal_ctx = reader_impl_ptr,
            .readFn = gen.read,
        },
    };
}
