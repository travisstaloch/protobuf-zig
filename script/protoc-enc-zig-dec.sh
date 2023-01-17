# use system protoc to parse a proto and then decode it to text format

set -ex
script/protoc-capture.sh $@ |& script/zig-decode-text.sh