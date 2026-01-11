@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ===============================================================
:: Modify Cargo.toml to exclude irrelevant bindings (dependency-free Python)
:: ===============================================================
copy Cargo.toml Cargo.toml.bak
echo lines = open('Cargo.toml').readlines() > rewrite.py
echo with open('Cargo.toml', 'w') as f: >> rewrite.py
echo     im = False >> rewrite.py
echo     for l in lines: >> rewrite.py
echo         if l.strip().startswith('members = ['): >> rewrite.py
echo             im = True >> rewrite.py
echo             f.write('members = [\"crates/loess-rs\", \"crates/fastLoess\", \"bindings/python\"]\n') >> rewrite.py
echo             continue >> rewrite.py
echo         if im: >> rewrite.py
echo             if l.strip().startswith(']'): im = False >> rewrite.py
echo             continue >> rewrite.py
echo         f.write(l) >> rewrite.py
python rewrite.py

:: ===============================================================
:: Navigate to Python bindings
:: ===============================================================
cd bindings\python || exit /b 1

:: ===============================================================
:: CI-friendly pip behavior
:: ===============================================================
set PIP_DISABLE_PIP_VERSION_CHECK=1
set PIP_NO_CACHE_DIR=1
set PIP_NO_BUILD_ISOLATION=1

:: ===============================================================
:: Shared Rust / Cargo cache (must match other outputs)
:: ===============================================================
set RUST_CACHE=%SRC_DIR%\.rust-cache
set CARGO_HOME=%RUST_CACHE%\cargo
set CARGO_TARGET_DIR=%RUST_CACHE%\target

for %%D in ("%RUST_CACHE%" "%CARGO_HOME%" "%CARGO_TARGET_DIR%") do (
    if not exist %%~D mkdir %%~D
)

set CARGO_TERM_COLOR=never
set RUST_BACKTRACE=1

:: ===============================================================
:: Verify Python
:: ===============================================================
"%PYTHON%" --version || (
    echo ERROR: Python not found
    exit /b 1
)

:: ===============================================================
:: Build & install Python package
:: - no-build-isolation: reuse Rust artifacts
:: - no-deps: conda handles dependencies
:: ===============================================================
echo [%DATE% %TIME%] Installing Python package...
"%PYTHON%" -m pip install . -vv --no-build-isolation --no-deps || exit /b 1

:: ===============================================================
:: Generate third-party license bundle
:: ===============================================================
where cargo-bundle-licenses >nul 2>&1 || (
    echo ERROR: cargo-bundle-licenses not found
    exit /b 1
)

echo [%DATE% %TIME%] Generating license bundle...
cargo-bundle-licenses ^
    --format yaml ^
    --output THIRDPARTY.yml || exit /b 1

:: ===============================================================
:: Copy license file into recipe directory
:: ===============================================================
if not exist "%RECIPE_DIR%" (
    echo ERROR: RECIPE_DIR does not exist: %RECIPE_DIR%
    exit /b 1
)

copy /Y THIRDPARTY.yml "%RECIPE_DIR%\THIRDPARTY.yml" || exit /b 1

echo [%DATE% %TIME%] Python bindings completed successfully.
exit /b 0
