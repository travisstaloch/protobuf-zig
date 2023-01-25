# args should be folders to be generated. usually examples/
# set -ex
ZIG_FLAGS= #-Dlog-level=info
zig build $ZIG_FLAGS -freference-trace=20
DEST_DIR=gen
# find $DEST_DIR -name "*.pb.zig" -exec rm {} \;

for dir in $@; do
  PROTOFILES=$(find $dir -name "*.proto")
  for file in $PROTOFILES; do
    CMD="zig-out/bin/protoc-zig --zig_out=$DEST_DIR -I $dir $file"
    echo $CMD
    $($CMD)
  done
done

for dir in $@; do
  PROTOFILES=$(find $dir -name "*.proto")
  for file in $PROTOFILES; do
    BASE=$(basename $file) # get rid of the directory
    FILE="$DEST_DIR/${BASE%.*}.pb.zig" # replace the extension
    CMD="zig test $FILE --pkg-begin protobuf src/lib.zig --pkg-begin protobuf src/lib.zig --pkg-end"
    echo $CMD
    $($CMD)
  done
done
