#!/bin/bash
set -e

# R package is located in bindings/r
cd bindings/r

# R CMD INSTALL --build .
# $R is provided by the conda build environment
$R CMD INSTALL --build .
