set -ex
zig build  
DEST_DIR=gen
rm $DEST_DIR/*.pb.zig
zig-out/bin/protoc-zig --zig_out=$DEST_DIR $@
zig test gen/only_message2.pb.zig --pkg-begin protobuf-types src/types.zig --pkg-end --pkg-begin protobuf src/protobuf.zig --pkg-end