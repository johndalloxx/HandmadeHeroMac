OSX_LD_FLAGS="-framework AppKit -framework IOKit"

# Check if the build directory exists, create it if it doesn't
if [ ! -d "../../build" ]; then
    mkdir ../../build
fi

pushd ../../build
clang -g $OSX_LD_FLAGS -o handmade ../handmade/code/osx_main.mm
popd
