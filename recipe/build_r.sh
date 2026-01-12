#!/bin/bash
# High-visibility build script for Conda R package (Azure Pipelines optimized)
set -ex

# 0. Setup trap for failure diagnostic
cleanup() {
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!!! R Build Failed with exit code $EXIT_CODE"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "=== Current Directory Recursion (depth 3) ==="
        find . -maxdepth 3 -not -path '*/.*'
        echo "=== End of Diagnostic Output ==="
    fi
}
trap cleanup EXIT

echo "=== R Build Start: $(date) ==="

# 1. Setup Environment
# Use Python from build environment for patching scripts
export PYTHON_EXE="${BUILD_PREFIX}/bin/python"
# Use R from host environment
export R_EXE="${PREFIX}/bin/R"
export LIBRSYS_R_VERSION=4.2.0
export CARGO_NET_OFFLINE=true
mkdir -p .cargo_home
export CARGO_HOME=$(pwd)/.cargo_home

# 2. Preparation (Synced with Makefile)
echo "=== Step 1: Cleaning R Cargo.toml ==="
$PYTHON_EXE dev/prepare_cargo.py clean bindings/r/src/Cargo.toml -q

echo "=== Step 2: Extracting/Preparing Vendor ==="
# Remove existing vendor to ensure clean slate
rm -rf bindings/r/src/vendor
if [ -f bindings/r/src/vendor.tar.xz ]; then
  echo "Found vendor.tar.xz, extracting..."
  (cd bindings/r/src && tar -xJf vendor.tar.xz)
fi
mkdir -p bindings/r/src/vendor
# Update with fresh local source
cp -rvL crates/lowess-rs bindings/r/src/vendor/
cp -rvL crates/fastLowess bindings/r/src/vendor/
rm -rf bindings/r/src/vendor/*/target

echo "=== Step 3: Patching ==="
# Use the root Cargo.toml for workspace definitions, but patch the R manifest and its vendor
$PYTHON_EXE dev/patch_vendor_crates.py Cargo.toml bindings/r/src/vendor -q

echo "=== Step 4: Checksums ==="
echo '{"files":{},"package":null}' > bindings/r/src/vendor/lowess-rs/.cargo-checksum.json
echo '{"files":{},"package":null}' > bindings/r/src/vendor/fastLowess/.cargo-checksum.json

echo "=== Step 5: Isolation ==="
$PYTHON_EXE dev/prepare_cargo.py isolate bindings/r/src/Cargo.toml -q

if [ -f dev/clean_checksums.py ]; then
    $PYTHON_EXE dev/clean_checksums.py -q bindings/r/src/vendor
fi

# 3. VERBOSE CARGO BUILD
echo "=== Step 6: Manual Verbose Cargo Build ==="
(
    cd bindings/r/src
    mkdir -p .cargo
    cp -v cargo-config.toml .cargo/config.toml
    # Add workspace if missing (mimic Makevars)
    if ! grep -q "^\[workspace\]" Cargo.toml; then
        echo "" >> Cargo.toml
        echo "[workspace]" >> Cargo.toml
    fi
    # Use explicit target dir relative to R package root
    mkdir -p ../target
    echo "Running verbose cargo build..."
    if ! cargo build --verbose --release --manifest-path=Cargo.toml --target-dir ../target; then
        echo "ERROR: Cargo build failed. Dumping patched manifests for debugging:"
        cat Cargo.toml
        cat vendor/fastLowess/Cargo.toml
        cat vendor/lowess-rs/Cargo.toml
        exit 1
    fi
)

# 4. PRE-INSTALL PATCHING (Crucial for Conda)
echo "=== Step 7: Patching R for Pre-built Library ==="
# Move the static library to src/ so it survives R's temp-copy and skip target-dir issues
STATIC_LIB=$(find bindings/r/target -name librfastlowess.a | head -n 1)
if [ -n "$STATIC_LIB" ]; then
    echo "Found static lib at $STATIC_LIB, moving to bindings/r/src/librfastlowess.a"
    cp -v "$STATIC_LIB" bindings/r/src/librfastlowess.a
else
    echo "ERROR: librfastlowess.a not found even after build!"
    find bindings/r/target -name "*.a" || echo "No .a files found at all"
    exit 1
fi

# Patch configure to point to the library in src/
# Patch configure to point to the library in src/
# Use tmp file to avoid sed -i incompatibility on macOS (BSD sed vs GNU sed)
sed 's|${TARGET_DIR}/release/librfastlowess.a|librfastlowess.a|g' bindings/r/configure > bindings/r/configure.tmp
mv bindings/r/configure.tmp bindings/r/configure
chmod +x bindings/r/configure

# Patch Makevars.in to avoid 'all: clean' and internal cargo build
cat <<'EOF' > bindings/r/src/Makevars.in
TARGET_DIR = .
STATLIB = librfastlowess.a
PKG_LIBS = @UNDEFINED_FLAGS@ @GC_SECTIONS@

all: $(SHLIB)

$(SHLIB): $(STATLIB) dummy.o

$(STATLIB):
	@echo "Using pre-built static library: $(STATLIB)"
	@ls -l $(STATLIB)

dummy.o: dummy.c
	@$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS) -c dummy.c -o dummy.o

clean:
	@rm -f $(SHLIB) $(OBJECTS)
EOF

# 5. Final R build and Install
echo "=== Step 8: R CMD INSTALL ==="
cd bindings/r
# Run configure to generate Makevars from our patched template
./configure
# Now install
$R_EXE CMD INSTALL --build .

echo "=== R Build Success: $(date) ==="
trap - EXIT
exit 0
