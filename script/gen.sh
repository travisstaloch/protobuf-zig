# args: -I examples examples/file.proto
# set -ex
DEST_DIR=gen

dir=${dir%/*}
CMD="protoc --plugin=zig-out/bin/protoc-gen-zig --zig_out=$DEST_DIR $@"
echo $CMD
$($CMD)
