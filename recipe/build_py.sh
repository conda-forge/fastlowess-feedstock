#!/usr/bin/env bash
set -euxo pipefail

# ===============================================================
# Build Python bindings for fastlowess
# ===============================================================

# Ensure we are in source root
cd "${SRC_DIR}"

# ===============================================================
# Shared Rust cache (reuse artifacts from build_cpp or previous runs)
# ===============================================================
export CARGO_TARGET_DIR="${SRC_DIR}/.rust-cache/target"
export CARGO_HOME="${SRC_DIR}/.rust-cache/cargo"
mkdir -p "$CARGO_TARGET_DIR" "$CARGO_HOME"

export CARGO_TERM_COLOR=never
export RUST_BACKTRACE=1

# ===============================================================
# CI-friendly pip configuration
# ===============================================================
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_CACHE_DIR=1

# ===============================================================
# Rewrite Cargo.toml workspace members to include only Python related crates
# ===============================================================
cp Cargo.toml Cargo.toml.bak
python -c "
lines = open('Cargo.toml').readlines()
with open('Cargo.toml', 'w') as f:
    in_members = False
    for line in lines:
        if line.strip().startswith('members = ['):
            in_members = True
            f.write('members = [\n')
            f.write('    \"crates/lowess\",\n')
            f.write('    \"crates/fastLowess\",\n')
            f.write('    \"bindings/python\",\n')
            f.write(']\n')
            continue
        if in_members:
            if line.strip().startswith(']'):
                in_members = False
            continue
        f.write(line)
"

# Remove Cargo.lock to force regeneration to match truncated workspace
rm -f Cargo.lock

# ===============================================================
# Navigate to Python bindings
# ===============================================================
cd bindings/python

# ===============================================================
# Verify Python and pip
# ===============================================================
"$PYTHON" --version
"$PYTHON" -m pip --version

# ===============================================================
# Install Python package (no-build-isolation, uses prebuilt Rust artifacts)
# ===============================================================
"$PYTHON" -m pip install . -vv --no-build-isolation --no-deps

# ===============================================================
# Generate third-party license file
# ===============================================================
where cargo-bundle-licenses >/dev/null 2>&1 || command -v cargo-bundle-licenses >/dev/null 2>&1 || {
    echo "ERROR: cargo-bundle-licenses not found"
    exit 1
}

cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
cp THIRDPARTY.yml "$RECIPE_DIR/"

echo "Python bindings build completed successfully."
