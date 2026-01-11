#!/bin/bash
set -e

# Build the C++ bindings using CMake
# Source is in bindings/cpp relative to root
# We need to make sure we're at the root of the repo (Conda source root)

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

# Generate license file
cd ..
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
cp THIRDPARTY.yml $RECIPE_DIR/
