# args are optional protopath and protofile
# use system protoc to encode a CodeGeneratorRequest to zig-out/bin/protoc-gen-zig

set -e
zig build
protoc --plugin=./zig-out/bin/protoc-gen-zig --zig_out=gen $@