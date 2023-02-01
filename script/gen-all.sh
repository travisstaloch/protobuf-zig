# args should be folders to be generated. usually examples/
# usage example: $ script/gen-all.sh -I examples examples/

set -e
ZIG_FLAGS= #-Dlog-level=info
zig build $ZIG_FLAGS -freference-trace
DEST_DIR=gen

# recursively remove all *.pb.zig files from $DEST_DIR
#find $DEST_DIR -name "*.pb.zig" -exec rm {} \;

# iterate args, skipping '-I examples'
state="start"
inc=""
for arg in $@; do
  if [[ $arg == "-I" ]]; then
    state="-I"
  elif [[ $state == "-I" ]]; then
    state=""
    inc=$arg
  else
    PROTOFILES=$(find $arg -name "*.proto")

    for file in $PROTOFILES; do
      script/gen.sh -I $inc $file      
    done

    for file in $PROTOFILES; do
      script/gen-test.sh -I $inc $file
    done
  fi
done
