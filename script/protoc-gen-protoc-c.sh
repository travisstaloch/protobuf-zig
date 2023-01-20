set -x
pushd ../../c/protobuf-c/
GENDIR=gen2
PATH=build/bin:$PATH protoc --c_out=$GENDIR -I ~/Downloads/protobuf/src/google/ ~/Downloads/protobuf/src/google/protobuf/descriptor.proto
pwd
ls $GENDIR
popd