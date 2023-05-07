set -x
zig test "$@" --mod protobuf:protobuf:src/lib.zig  --deps protobuf -freference-trace