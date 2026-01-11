#!/bin/bash
set -ex

# Preparation for R build - mimic Makefile vendoring
# We use ${PYTHON} provided by conda-build
${PYTHON} dev/prepare_cargo.py clean bindings/r/src/Cargo.toml
mkdir -pv bindings/r/src/vendor
cp -rvL crates/fastLowess bindings/r/src/vendor/
cp -rvL crates/lowess bindings/r/src/vendor/

# Remove target and lock files from vendor to be clean
rm -rf bindings/r/src/vendor/*/target bindings/r/src/vendor/*/Cargo.lock

# Patch the vendored crates to remove workspace inheritance/GPU deps
${PYTHON} dev/patch_vendor_crates.py Cargo.toml bindings/r/src/vendor/

# Isolate R package workspace
${PYTHON} dev/prepare_cargo.py isolate bindings/r/src/Cargo.toml

# Build the R package
cd bindings/r
${R:-R} CMD INSTALL --build .
