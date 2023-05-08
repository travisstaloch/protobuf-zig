const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const pb = @import("protobuf");
pub const CodeGeneratorRequest = pb.plugin.CodeGeneratorRequest;
pub const gen = @import("gen.zig");

/// A simple protoc plugin implementation.  Similar to
/// https://github.com/protocolbuffers/protobuf-go/blob/master/cmd/protoc-gen-go/main.go.
/// Reads a CodeGeneratorRequest from stdin and writes a CodeGeneratorResponse to stdout.
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const input = try std.io.getStdIn().reader().readAllAlloc(alloc, std.math.maxInt(u32));

    var parse_ctx = pb.protobuf.context(input, alloc);
    const message = try parse_ctx.deserialize(&CodeGeneratorRequest.descriptor);
    const req = try message.as(CodeGeneratorRequest);

    var gen_ctx = gen.context(alloc, req);
    const resp = try gen_ctx.gen();
    const w = std.io.getStdOut().writer();
    try pb.protobuf.serialize(&resp.base, w);
}
