set -x
zig test "$@" --pkg-begin protobuf src/lib.zig --pkg-begin protobuf src/lib.zig --pkg-end -freference-trace