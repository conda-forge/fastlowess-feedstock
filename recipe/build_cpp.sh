#!/bin/bash
set -e

# Build the C++ bindings using CMake
# Source is in bindings/cpp relative to root
# We need to make sure we're at the root of the repo (Conda source root)

# Temporarily exclude bindings/python from workspace to avoid building it (and thus avoiding linking errors on OSX)
cp Cargo.toml Cargo.toml.bak
# Use a temporary file for sed to be portable across Linux and macOS (bsd sed)
sed '/bindings\/python/d' Cargo.toml > Cargo.toml.tmp && mv Cargo.toml.tmp Cargo.toml

# Create build directory
mkdir -p build_cpp
cd build_cpp

# Configure
cmake ${CMAKE_ARGS} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_INSTALL_LIBDIR=lib \
    ../bindings/cpp

# Build
cmake --build . --config Release

# Install
cmake --install . --config Release

# Manual install of the shared library since cmake install is missing it
# The library name defaults to libfastlowess.so (Linux) or libfastlowess.dylib (macOS)
if [[ "${target_platform}" == osx-* ]]; then
    cp libfastlowess_cpp.dylib $PREFIX/lib/libfastlowess.dylib
else
    cp libfastlowess_cpp.so $PREFIX/lib/libfastlowess.so
fi

# Generate license file
cd ..
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
cp THIRDPARTY.yml $RECIPE_DIR/

# Restore Cargo.toml
mv Cargo.toml.bak Cargo.toml
