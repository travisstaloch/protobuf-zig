//!
//! This program converts annoying octal conformance error payloads into
//! hex.  Example of this conversion the command line:
//! $ zig run src/conformance-helper.zig
//! \222\001\013\022\010\341!\030\341!\370\001\341!
//! =>
//! 92010b1208e12118e121f801e121
//!
const std = @import("std");
const assert = std.debug.assert;

// supports escape sequences \n, \r, \\, \t, \NNN (octal)
pub fn parseEscapeSequence(slice: []const u8, offsetp: *usize) !u8 {
    const offset = offsetp.*;
    assert(slice.len > offset);
    assert(slice[offset] == '\\');

    if (slice.len == offset + 1) return error.InvalidEscape;

    var skiplen: u8 = 2;
    defer offsetp.* += skiplen;
    return switch (slice[offset + 1]) {
        'n' => '\n',
        'r' => '\r',
        '\\' => '\\',
        't' => '\t',
        '0'...'7' => blk: {
            const octstr = slice[offset + 1 .. offset + 4];
            assert(octstr.len == 3);
            const oct = try std.fmt.parseUnsigned(u8, octstr, 8);
            skiplen += 2;
            break :blk oct;
        },
        else => blk: {
            std.log.err("invalid escape '{c}'", .{slice[offset + 1]});
            break :blk error.InvalidEscape;
        },
    };
}

/// converts escape sequences in-place
pub fn parseEscapes(content_: []u8) ![]u8 {
    var content = content_;
    var fbs = std.io.fixedBufferStream(content);
    const writer = fbs.writer();

    var index: usize = 0;
    while (true) {
        if (index >= content.len)
            return content[0..fbs.pos];

        const b = content[index];

        switch (b) {
            '\\' => try writer.writeByte(try parseEscapeSequence(content, &index)),
            else => {
                try writer.writeByte(b);
                index += 1;
            },
        }
    }
}
const Format = enum { hex, binary };
pub fn main() !void {
    // var input = "\\202\\002\\001\\200".*;
    const stdin = std.io.getStdIn().reader();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    var args = try std.process.argsWithAllocator(alloc);
    _ = args.next();

    // parse args: format
    var format = Format.hex;
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--format")) {
            const s = args.next() orelse {
                std.log.err("missing --format arg. accepted values {s}", .{std.meta.fieldNames(Format)});
                return error.Arg;
            };
            format = std.meta.stringToEnum(Format, s) orelse {
                std.log.err("invalid --format arg '{s}'. accepted values {s}", .{ s, std.meta.fieldNames(Format) });
                return error.Arg;
            };
        } else if (std.mem.eql(u8, arg, "-b")) {
            format = .binary;
        } else {
            unreachable;
        }
    }
    var input = try stdin.readAllAlloc(alloc, std.math.maxInt(u32));

    // trim newlines. maybe should only trim one?
    while (input.len > 0) : (input.len -= 1) {
        if (input[input.len - 1] != '\n') break;
    }
    const escaped = try parseEscapes(input);
    const stdout = std.io.getStdOut().writer();
    if (format == .hex)
        try stdout.print("\n{}\n", .{std.fmt.fmtSliceHexLower(escaped)})
    else
        try stdout.print("{s}", .{escaped});
}
