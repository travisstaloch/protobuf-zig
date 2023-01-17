# args are optional protopath and protofile
# use system protoc to encode a CodeGeneratorRequest to zig-out/bin/protoc-gen-zig

set -e
PATH=zig-out/bin/:$PATH protoc --zig_out=gen $@