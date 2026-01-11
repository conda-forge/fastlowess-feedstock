#!/bin/bash
set -ex

echo "=== Build Environment ==="
env | sort
pwd
ls -F

# Determine tools
PYTHON_EXE=${PYTHON:-python}
R_EXE=${R:-R}
echo "Using Python: $PYTHON_EXE"
echo "Using R: $R_EXE"
$PYTHON_EXE --version || true
$R_EXE --version || true

# Check for required files in work dir
echo "=== File Check ==="
ls -l Cargo.toml || echo "ERROR: Cargo.toml not found at root"
ls -d dev || echo "ERROR: dev directory not found"
ls -d bindings/r || echo "ERROR: bindings/r not found"
ls -d crates || echo "ERROR: crates directory not found"

# 1. Extract existing vendor dependencies if present
# This contains external crates (extendr-api, etc.)
if [ -f bindings/r/src/vendor.tar.xz ]; then
  echo "Extracting vendor.tar.xz..."
  # Use -v to see what's being extracted
  (cd bindings/r/src && tar -xJf vendor.tar.xz)
  echo "Vendor directory after extraction:"
  ls -F bindings/r/src/vendor/ || echo "Vendor dir empty?"
else
  echo "WARNING: vendor.tar.xz NOT found in bindings/r/src/"
  ls -F bindings/r/src/
fi

# 2. Update local crates in vendor directory
# This ensures we build with the latest local changes
mkdir -p bindings/r/src/vendor
echo "Copying local crates to vendor..."
cp -rvL crates/fastLowess bindings/r/src/vendor/
cp -rvL crates/lowess bindings/r/src/vendor/

# Clean up target/locks from vendored sources
echo "Cleaning up vendored crates..."
rm -rf bindings/r/src/vendor/*/target
rm -f bindings/r/src/vendor/*/Cargo.lock

# 3. Patch and Isolate (remove workspace inheritance)
echo "Running preparation scripts..."
# Verify scripts exist
ls -l dev/prepare_cargo.py
ls -l dev/patch_vendor_crates.py

$PYTHON_EXE dev/prepare_cargo.py clean bindings/r/src/Cargo.toml
$PYTHON_EXE dev/patch_vendor_crates.py Cargo.toml bindings/r/src/vendor/
$PYTHON_EXE dev/prepare_cargo.py isolate bindings/r/src/Cargo.toml

# Remove main lock file to prevent path conflicts with vendored paths
rm -f bindings/r/src/Cargo.lock

# 4. Final R build
echo "Starting R package installation..."
# Move to R package dir
cd bindings/r
# Run configure if it exists (R CMD INSTALL usually does this, but let's be safe)
if [ -f configure ]; then
  chmod +x configure
  ./configure
fi

# We use --no-test to speed up if needed, but here we want a full build
$R_EXE CMD INSTALL --build .

echo "Build complete!"
