set -e

zig build &&
~/Downloads/protobuf/conformance_test_runner --output_dir gen/conformance zig-out/bin/conformance &&
echo "done"
