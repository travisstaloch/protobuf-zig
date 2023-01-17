:warning: This project is in its early early stages and doesn't do much yet :warning:

# About
A tool for generating zig code capable of de/serializing to the protocol buffer wire format.  Depends on [protoc](https://developers.google.com/protocol-buffers/docs/downloads) to parse .proto files.  


# Usage
Run tests
```console
zig build test
```

Build
```console
zig build
```

:warning: NOT WORKING YET :warning:

```console
PATH=zig-out/bin:$PATH protoc -I=$SRC_DIR --zig_out=$DST_DIR $SRC_DIR/ \
  addressbook.proto
```

This generates the following files in your specified destination directory:
```
addressbook.pb.zig
```


# Resources
### inspired by
* https://github.com/protobuf-c/protobuf-c
