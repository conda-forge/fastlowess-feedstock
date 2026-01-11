#!/bin/bash
set -e

# R package is located in bindings/r
cd bindings/r
mkdir -pv src/vendor && cp -rv ../../crates/fastLowess src/vendor/ && cp -rv ../../crates/lowess src/vendor/

# R CMD INSTALL --build .
# $R is provided by the conda build environment
$R CMD INSTALL --build .
