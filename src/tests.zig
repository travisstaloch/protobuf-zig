test {
    _ = @import("test-deserialize.zig");
    _ = @import("protobuf").gen;
    _ = @import("test-serialize.zig");
}

// zig test src/tests.zig --pkg-begin protobuf src/lib.zig --pkg-begin protobuf src/lib.zig --pkg-end --pkg-end --main-pkg-path .
test "readme" {
    // Note - the package 'protobuf' below is src/lib.zig.  this package must
    // include itself. i hope to remove this requirement soon.  it can be
    // provided in build.zig or on the command line:
    const std = @import("std");
    const pb = @import("protobuf");
    const Person = @import("../examples/gen/only_message.pb.zig").Person;

    // serialize to a writer
    const alloc = std.testing.allocator; // could be any zig std.mem.Allocator
    var person = Person.init();
    person.set(.id, 42);
    person.set(.name, pb.extern_types.String.init("zero"));
    person.set(.kind, .NONE);
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    try pb.protobuf.serialize(&person.base, buf.writer());

    // deserialize from a buffer
    var ctx = pb.protobuf.context(buf.items, alloc);
    const message = try ctx.deserialize(&Person.descriptor);
    defer message.deinit(alloc);
    var person_copy = try message.as(Person);

    // test that they're equal
    try std.testing.expect(person_copy.has(.id));
    try std.testing.expectEqual(person.id, person_copy.id);
    try std.testing.expect(person_copy.has(.name));
    try std.testing.expectEqualStrings(person.name.slice(), person_copy.name.slice());
    try std.testing.expect(person_copy.has(.kind));
    try std.testing.expectEqual(person.kind, person_copy.kind);
}
