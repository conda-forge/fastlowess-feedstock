#!/bin/bash
set -e

# R package is located in bindings/r
# Preparation for R build - mimic Makefile vendoring
set -x
python3 dev/prepare_cargo.py clean bindings/r/src/Cargo.toml
mkdir -pv bindings/r/src/vendor
cp -rvL crates/fastLowess bindings/r/src/vendor/
cp -rvL crates/lowess bindings/r/src/vendor/
# Remove target and lock files from vendor to be clean
rm -rf bindings/r/src/vendor/*/target bindings/r/src/vendor/*/Cargo.lock
# Patch the vendored crates to remove workspace inheritance
python3 dev/patch_vendor_crates.py Cargo.toml bindings/r/src/vendor/
# Isolate R package workspace
python3 dev/prepare_cargo.py isolate bindings/r/src/Cargo.toml
# Final location
cd bindings/r

# R CMD INSTALL --build .
# $R is provided by the conda build environment
$R CMD INSTALL --build .
