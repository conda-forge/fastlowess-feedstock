#!/usr/bin/env bash
set -euxo pipefail

# ===============================================================
# CI-friendly Rust/C++ build for fastlowess C++ bindings
# ===============================================================

# Ensure we're at the root of the repo (Conda source root)
cd "${SRC_DIR}"

# ===============================================================
# Shared Rust cache to avoid re-building Rust crates multiple times
# ===============================================================
export CARGO_TERM_COLOR=never
export RUST_BACKTRACE=1

# ===============================================================
# Rewrite Cargo.toml workspace members to include only C++ related crates
# ===============================================================
cp Cargo.toml Cargo.toml.bak
python -c "
lines = open('Cargo.toml').readlines()
with open('Cargo.toml', 'w') as f:
    in_members = False
    for line in lines:
        if line.strip().startswith('members = ['):
            in_members = True
            f.write('members = [\n')
            f.write('    \"crates/lowess\",\n')
            f.write('    \"crates/fastLowess\",\n')
            f.write('    \"bindings/cpp\",\n')
            f.write(']\n')
            continue
        if in_members:
            if line.strip().startswith(']'):
                in_members = False
            continue
        f.write(line)
"

# Remove Cargo.lock to force regeneration to match truncated workspace
rm -f Cargo.lock


# ===============================================================
# Out-of-source build
# ===============================================================
BUILD_DIR=build_cpp
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ===============================================================
# Configure
# ===============================================================
cmake ${CMAKE_ARGS} \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    ../bindings/cpp

# ===============================================================
# Build (parallel)
# ===============================================================
cmake --build . --config Release --parallel

# ===============================================================
# Install
# ===============================================================
cmake --install . --config Release

# ===============================================================
# Ensure the shared library is installed correctly
# ===============================================================
LIB_NAME_CPP=fastlowess_cpp
if [[ "$target_platform" == osx-* ]]; then
    SHARED_LIB="lib${LIB_NAME_CPP}.dylib"
    cp "$SHARED_LIB" "$PREFIX/lib/libfastlowess.dylib"
    # Update the install_name since we renamed the library
    install_name_tool -id "@rpath/libfastlowess.dylib" "$PREFIX/lib/libfastlowess.dylib"
elif [[ "$target_platform" == linux-* ]]; then
    SHARED_LIB="lib${LIB_NAME_CPP}.so"
    cp "$SHARED_LIB" "$PREFIX/lib/libfastlowess.so"
fi

# ===============================================================
# Generate third-party license bundle
# ===============================================================
cd "$SRC_DIR"
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
cp THIRDPARTY.yml "$RECIPE_DIR/"

# ===============================================================
# Restore Cargo.toml
# ===============================================================
mv Cargo.toml.bak Cargo.toml

echo "C++ build completed successfully."
