#!/bin/bash
set -e

# Build the Python bindings
# Standard maturin build
cd bindings/python
$PYTHON -m pip install . -vv --no-build-isolation

# Generate license file and copy to recipe dir for conda to find it
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
cp THIRDPARTY.yml $RECIPE_DIR/
