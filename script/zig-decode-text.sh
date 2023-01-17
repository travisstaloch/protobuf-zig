# build and run src/main.zig which is a driver for message deserialization
# it expects to read a protobuf message from stdin

set -e
INCLUDE_DIR=~/Downloads/protobuf/src
zig build run -freference-trace=10 -Dlog-level=info -- -I $INCLUDE_DIR --decode=google.protobuf.compiler.CodeGeneratorRequest $INCLUDE_DIR/google/protobuf/compiler/plugin.proto
