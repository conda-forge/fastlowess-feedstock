#!/bin/bash
set -ex

# Preparation for R build - mimic Makefile vendoring
# We use the existing vendor.tar.xz to get crates.io deps, then update local crates
cd bindings/r/src
if [ -f vendor.tar.xz ]; then
  echo "Extracting vendor.tar.xz..."
  tar -xf vendor.tar.xz
fi
mkdir -p vendor
echo "Updating local crates in vendor directory..."
cp -rvL ../../../crates/fastLowess vendor/
cp -rvL ../../../crates/lowess vendor/
rm -rf vendor/*/target vendor/*/Cargo.lock

# Back to root to run our custom patching scripts
cd ../../..
${PYTHON} dev/prepare_cargo.py clean bindings/r/src/Cargo.toml
${PYTHON} dev/patch_vendor_crates.py Cargo.toml bindings/r/src/vendor/
${PYTHON} dev/prepare_cargo.py isolate bindings/r/src/Cargo.toml

# Final R build
cd bindings/r
${R:-R} CMD INSTALL --build .

