:warning: This project is in its early early stages. expect bugs and missing features. :warning:

# About
A tool for generating zig code capable of de/serializing to the protocol buffer wire format.  Depends on [protoc](https://developers.google.com/protocol-buffers/docs/downloads) to parse .proto files.  

# Status
- [x] initial code generation
- [x] initial deserialization from wire format
- [ ] serialization to wire format

# Todo
- [ ] parse text format - this could make for nice readable tests cases
- [ ] output text format
- [ ] maybe parse json?
- [ ] output json
- [ ] conformance testing?
- [ ] support more protoc args?
  - [ ] --encode=MESSAGE_TYPE
  - [ ] --decode=MESSAGE_TYPE
  - [ ] --decode_raw
  - [ ] --descriptor_set_in=FILES
  - [ ] -oFILE / --descriptor_set_out=FILE

# Usage
Run tests
```console
zig build test
```

Build
```console
zig build
```

```console
zig build
zig-out/bin/protoc-zig --zig_out=gen/ -I examples/ examples/only_message.proto
```

This generates the following files in gen/:
```
only_message.pb.zig
only_enum.pb.zig
```

In your zig application:
```zig
// test.protobuf.zig
test {
    // Note - this file depends on packages 'protobuf' and 'protobuf-types'
    // these can be provided in build.zig or on the command line line this:
    // $ zig test test.protobuf.zig --pkg-begin protobuf-types src/types.zig --pkg-end --pkg-begin protobuf src/protobuf.zig --pkg-end
    const protobuf = @import("protobuf"); // src/protobuf.zig
    const Person = @import("../gen/only_message.pb.zig").Person;

    const bytes = ""; // should be protobuf wire format bytes
    const alloc = std.heap.page_allocator; // any zig std.mem.Allocator
    var ctx = protobuf.context(bytes, alloc);
    const person_message = try ctx.deserialize(&Person.descriptor);
    var person = try person_message.as(Person);
    person.id = 42;
}

```

# Resources
### inspired by
* https://github.com/protobuf-c/protobuf-c
