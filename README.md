:warning: This project is in its early early stages. expect bugs and missing features. :warning:

# About
A tool for generating zig code capable of de/serializing to the protocol buffer wire format.  Depends on [protoc](https://developers.google.com/protocol-buffers/docs/downloads) to parse .proto files.  

# Status
- [x] zig code generation
  - [ ] recursive message types don't work yet [#1](../../issues/1). see [examples/recursive.proto](examples/recursive.proto)
- [x] deserialization from wire format
  - [ ] merging messages not yet implemented - 6 conformance failures
- [x] serialization to wire format
- [x] initial serialization to json format - 13 conformance failures
- [w] conformance testing results: 1485/408/19 success/skip/fail.  the 408 skipped are in these categories:
  - [ ] json input
  - [ ] text format output
  - [ ] jspb format output

# Usage

First, install the `protoc` compiler on your system.  

* on linux systems with apt:
```console
sudo apt install protobuf-compiler
```
* otherwise: [protoc](https://developers.google.com/protocol-buffers/docs/downloads)

Once you have `protoc` in your PATH

### Build
```console
zig build
```

### Run tests. 
note: some of these depend on `protoc` being available.
```console
zig build test
```

### Generate .zig files from .proto files
```console
zig build
zig-out/bin/protoc-zig --zig_out=gen/ -I examples/ examples/only_message.proto examples/only_enum.proto
```

This generates the following files in gen/:
```
only_message.pb.zig
only_enum.pb.zig
```

### Use the generated code
  * see below for an example `zig test` command
  * see [build.zig](build.zig) for a packaging example
```zig
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
```

```console
$ zig test src/tests.zig --pkg-begin protobuf src/lib.zig --pkg-begin protobuf src/lib.zig --pkg-end --pkg-end --main-pkg-path .
```

# Resources
### inspired by
* https://github.com/protobuf-c/protobuf-c
* https://github.com/mlugg/zigpb