# generate a protobuf-c .h/.c files from a .proto file
# args: -I examples/ examples/only_message.proto

protobuf_c_dir=../../c/protobuf-c
$protobuf_c_dir/build/bin/protoc-c --c_out=$protobuf_c_dir/gen $@
echo $protobuf_c_dir/gen/"${@: -1}"
