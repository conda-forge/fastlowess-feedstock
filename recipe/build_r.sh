#!/bin/bash
set -ex

# Use python provided by conda build
PYTHON_EXE=$(which python3 || which python)
echo "Using Python: $PYTHON_EXE"

# 1. Extract existing vendor dependencies if present
if [ -f bindings/r/src/vendor.tar.xz ]; then
  echo "Extracting vendor.tar.xz..."
  (cd bindings/r/src && tar -xf vendor.tar.xz)
fi

# 2. Update local crates in vendor directory
mkdir -p bindings/r/src/vendor
cp -rvL crates/fastLowess bindings/r/src/vendor/
cp -rvL crates/lowess bindings/r/src/vendor/
rm -rf bindings/r/src/vendor/*/target bindings/r/src/vendor/*/Cargo.lock

# 3. Patch the vendored crates (remove workspace inheritance)
$PYTHON_EXE dev/prepare_cargo.py clean bindings/r/src/Cargo.toml
$PYTHON_EXE dev/patch_vendor_crates.py Cargo.toml bindings/r/src/vendor/
$PYTHON_EXE dev/prepare_cargo.py isolate bindings/r/src/Cargo.toml

# 4. Final R build
cd bindings/r
# R is provided by conda-build as a variable or on PATH
${R:-R} CMD INSTALL --build .

