# use system protoc to decode a CodeGeneratorRequest

set -e
INCLUDE_DIR=~/Downloads/protobuf/src
protoc -I $INCLUDE_DIR --decode=google.protobuf.compiler.CodeGeneratorRequest $INCLUDE_DIR/google/protobuf/compiler/plugin.proto
