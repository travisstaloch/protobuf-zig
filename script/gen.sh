set -ex
ZIG_FLAGS= #-Dlog-level=debug
zig build $ZIG_FLAGS -freference-trace=20
DEST_DIR=gen
find $DEST_DIR -name "*.pb.zig" -exec rm {} \;
zig-out/bin/protoc-zig --zig_out=$DEST_DIR -I examples/ examples/$1.proto
zig test gen/$1.pb.zig --pkg-begin protobuf-types src/types.zig --pkg-end --pkg-begin protobuf src/protobuf.zig --pkg-end