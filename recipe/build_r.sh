#!/usr/bin/env bash
set -euxo pipefail

# ===============================================================
# build_r.sh - Build R bindings for fastlowess
# Optimized for Conda-forge CI and caching
# ===============================================================

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

# ---------------------------------------------------------------
# 0. Setup Environment
# ---------------------------------------------------------------
export PYTHON_EXE="${BUILD_PREFIX}/bin/python"
export R_EXE="${PREFIX}/bin/R"

# Shared Rust cache to speed up repeated builds across outputs
export CARGO_HOME="${SRC_DIR}/.rust-cache/cargo"
export CARGO_TARGET_DIR="${SRC_DIR}/.rust-cache/target"
mkdir -p "$CARGO_HOME" "$CARGO_TARGET_DIR"

# CI-friendly Cargo options
export CARGO_TERM_COLOR=never
export RUST_BACKTRACE=1
export CARGO_NET_OFFLINE=true

# Ensure /tmp exists (for MSYS/Git Bash)
mkdir -p /tmp
export TMP=/tmp
export TEMP=/tmp
export TMPDIR=/tmp
export HOME=/tmp

# ---------------------------------------------------------------
# 1. Prepare vendor crates and patch Cargo manifests
# ---------------------------------------------------------------
echo "=== Step 1: Cleaning and Preparing Vendor ==="
rm -rf bindings/r/src/vendor
if [ -f bindings/r/src/vendor.tar.xz ]; then
    echo "Extracting vendor.tar.xz..."
    (cd bindings/r/src && tar -xJf vendor.tar.xz)
fi
mkdir -p bindings/r/src/vendor
cp -rvL crates/lowess bindings/r/src/vendor/
cp -rvL crates/fastLowess bindings/r/src/vendor/
rm -rf bindings/r/src/vendor/*/target

echo "=== Step 2: Patching vendor crates and workspace ==="
$PYTHON_EXE dev/prepare_cargo.py clean bindings/r/src/Cargo.toml -q
$PYTHON_EXE dev/patch_vendor_crates.py Cargo.toml bindings/r/src/vendor -q

echo "=== Step 3: Creating Checksums ==="
echo '{"files":{},"package":null}' > bindings/r/src/vendor/lowess/.cargo-checksum.json
echo '{"files":{},"package":null}' > bindings/r/src/vendor/fastLowess/.cargo-checksum.json

echo "=== Step 4: Workspace Isolation ==="
$PYTHON_EXE dev/prepare_cargo.py isolate bindings/r/src/Cargo.toml -q
if [ -f dev/clean_checksums.py ]; then
    $PYTHON_EXE dev/clean_checksums.py -q bindings/r/src/vendor
fi

# ---------------------------------------------------------------
# 2. Build Rust library
# ---------------------------------------------------------------
echo "=== Step 5: Building Rust library ==="
(
    cd bindings/r/src
    mkdir -p .cargo
    cp -v cargo-config.toml .cargo/config.toml
    mkdir -p ../target
    cargo build --release --manifest-path=Cargo.toml --target-dir ../target
)

# ---------------------------------------------------------------
# 3. Move static lib to src/ for R CMD INSTALL
# ---------------------------------------------------------------
# Look for the release artifact specifically
STATIC_LIB=$(find bindings/r/target -path "*/release/librfastlowess.a" | head -n 1)

if [ -n "$STATIC_LIB" ]; then
    echo "Moving static lib to src/ from $STATIC_LIB"
    cp -v "$STATIC_LIB" bindings/r/src/librfastlowess.a
else
    echo "ERROR: librfastlowess.a not found"
    find bindings/r/target -name "*.a"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Patch configure and Makevars
# ---------------------------------------------------------------
echo "=== Step 6: Patching configure and Makevars ==="
sed 's|${TARGET_DIR}/release/librfastlowess.a|librfastlowess.a|g' bindings/r/configure > bindings/r/configure.tmp
mv bindings/r/configure.tmp bindings/r/configure
chmod +x bindings/r/configure

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

# Create dummy.c to avoid missing operand issues
echo "int dummy() { return 0; }" > bindings/r/src/dummy.c

# ---------------------------------------------------------------
# 5. Build and install R package
# ---------------------------------------------------------------
echo "=== Step 7: R CMD INSTALL ==="
cd bindings/r
./configure
$R_EXE CMD INSTALL --build .

echo "=== R Build Success: $(date) ==="
trap - EXIT
exit 0
