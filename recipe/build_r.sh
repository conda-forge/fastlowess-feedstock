#!/bin/bash
set -ex

echo "=== System Info ==="
uname -a
python3 --version || python --version || true

# Determine R executable
R_EXE=${R:-R}
$R_EXE --version

# Use python provided by conda build
PYTHON_EXE=$(which python3 || which python || echo "python")
echo "Using Python: $PYTHON_EXE"

# 1. Extract existing vendor dependencies if present
# This contains external crates (extendr-api, etc.)
if [ -f bindings/r/src/vendor.tar.xz ]; then
  echo "Extracting vendor.tar.xz..."
  (cd bindings/r/src && tar -xf vendor.tar.xz)
fi

# 2. Update local crates in vendor directory
# This ensures we build with the latest local changes
mkdir -p bindings/r/src/vendor
cp -rvL crates/fastLowess bindings/r/src/vendor/
cp -rvL crates/lowess bindings/r/src/vendor/

# Clean up target/locks from vendored sources
rm -rf bindings/r/src/vendor/*/target
rm -f bindings/r/src/vendor/*/Cargo.lock

# 3. Patch and Isolate (remove workspace inheritance)
echo "Running preparation scripts..."
$PYTHON_EXE dev/prepare_cargo.py clean bindings/r/src/Cargo.toml
$PYTHON_EXE dev/patch_vendor_crates.py Cargo.toml bindings/r/src/vendor/
$PYTHON_EXE dev/prepare_cargo.py isolate bindings/r/src/Cargo.toml

# Remove main lock file to prevent path conflicts
rm -f bindings/r/src/Cargo.lock

# 4. Final R build
echo "Starting R package installation..."
cd bindings/r
$R_EXE CMD INSTALL --build .

