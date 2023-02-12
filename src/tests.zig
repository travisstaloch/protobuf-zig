test {
    _ = @import("test-deserialize.zig");
    _ = @import("test-serialize.zig");
    _ = @import("test-conformance.zig");
}

// zig test src/tests.zig --pkg-begin protobuf src/lib.zig --pkg-begin protobuf src/lib.zig --pkg-end --pkg-end --main-pkg-path .
test "readme" {
    // Note - the package 'protobuf' below is src/lib.zig.  this package must
    // include itself. i hope to remove this requirement soon.  it can be
    // provided in build.zig or on the command line:
    const std = @import("std");
    const pb = @import("protobuf");
    const Person = @import("generated").person.Person;

    // serialize to a writer
    const alloc = std.testing.allocator; // could be any zig std.mem.Allocator
    var zero = Person.init();
    zero.set(.id, 0);
    zero.set(.name, pb.extern_types.String.init("zero"));
    zero.set(.kind, .NONE);
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    try pb.protobuf.serialize(&zero.base, buf.writer());

    // deserialize from a buffer
    var ctx = pb.protobuf.context(buf.items, alloc);
    const message = try ctx.deserialize(&Person.descriptor);
    defer message.deinit(alloc);
    var zero_copy = try message.as(Person);

    // test that they're equal
    try std.testing.expect(zero_copy.has(.id));
    try std.testing.expectEqual(zero.id, zero_copy.id);
    try std.testing.expect(zero_copy.has(.name));
    try std.testing.expectEqualStrings(zero.name.slice(), zero_copy.name.slice());
    try std.testing.expect(zero_copy.has(.kind));
    try std.testing.expectEqual(zero.kind, zero_copy.kind);

    // serialize to json
    const stderr = std.io.getStdErr().writer();
    try pb.json.serialize(&zero.base, stderr, .{
        .pretty_print = .{ .indent_size = 2 },
    });
    _ = try stderr.write("\n");
    // prints
    //{
    //  "name": "zero",
    //  "id": 0,
    //  "kind": "NONE"
    //}
}
