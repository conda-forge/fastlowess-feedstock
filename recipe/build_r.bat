@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ===============================================================
:: Setup temp directories (clean /tmp suppression)
:: ===============================================================
if not exist C:\tmp mkdir C:\tmp
set TMP=C:\tmp
set TEMP=C:\tmp
set TMPDIR=C:\tmp

:: Do NOT override HOME (can break R + git + cargo)
if not defined HOME set HOME=%SRC_DIR%

:: ===============================================================
:: Navigate to R bindings
:: ===============================================================
cd bindings\r || exit /b 1

:: ===============================================================
:: Verify required tools
:: ===============================================================
where cmake >nul 2>&1 || (echo ERROR: cmake not found! & exit /b 1)
where curl  >nul 2>&1 || (echo ERROR: curl not found!  & exit /b 1)
where rustc >nul 2>&1 || (echo ERROR: rustc not found! & exit /b 1)
where cargo >nul 2>&1 || (echo ERROR: cargo not found! & exit /b 1)

:: ===============================================================
:: Determine Rust version (correct, stable)
:: ===============================================================
for /f "tokens=2" %%i in ('rustc --version') do set RUST_VERSION=%%i

:: ===============================================================
:: Shared Rust cache (conda-forge friendly)
:: ===============================================================
set RUST_CACHE=%SRC_DIR%\.rust-cache
set CARGO_HOME=%RUST_CACHE%\cargo
set CARGO_TARGET_DIR=%RUST_CACHE%\target

for %%D in ("%RUST_CACHE%" "%CARGO_HOME%" "%CARGO_TARGET_DIR%" "%RUST_CACHE%\rust-std") do (
    if not exist %%~D mkdir %%~D
)

set CARGO_TERM_COLOR=never
set RUST_BACKTRACE=1

:: ===============================================================
:: Rust targets
:: ===============================================================
set TARGETS=x86_64-pc-windows-gnu i686-pc-windows-gnu

echo [%DATE% %TIME%] Preparing Rust std for: %TARGETS%

:: ===============================================================
:: Parallel download + extract
:: ===============================================================
for %%T in (%TARGETS%) do (
    call :DownloadAndExtract %%T
)

:: ===============================================================
:: Wait for completion
:: ===============================================================
:WaitForRustStd
for %%T in (%TARGETS%) do (
    if not exist "%RUST_CACHE%\rust-std\%%T\done.flag" (
        timeout /t 1 >nul
        goto WaitForRustStd
    )
)

echo [%DATE% %TIME%] All Rust std targets ready.

:: ===============================================================
:: Install Rust std into rustc sysroot
:: ===============================================================
for /f "delims=" %%i in ('rustc --print sysroot') do set RUST_SYSROOT=%%i

for %%T in (%TARGETS%) do (
    xcopy /E /Y /Q ^
        "%RUST_CACHE%\rust-std\%%T\rust-std-%%T\lib\rustlib\%%T" ^
        "%RUST_SYSROOT%\lib\rustlib\%%T\" >nul
)

:: ===============================================================
:: Isolate Cargo target directory (avoid MSVC artifacts)
:: ===============================================================
python -c ^
 "from pathlib import Path; p=Path('src/Makevars.win'); \
  p.write_text(p.read_text().replace('TARGET_DIR = ../target','TARGET_DIR = %CARGO_TARGET_DIR%'))"

:: ===============================================================
:: Dummy resource file (winshlib.mk safety)
:: ===============================================================
echo STRINGTABLE { 1 "d" } > src\dummy.rc
echo.>>src\Makevars.win
echo RES = dummy.o >> src\Makevars.win
echo RM = echo >> src\Makevars.win

:: ===============================================================
:: Debug Makevars
:: ===============================================================
echo === Makevars.win Content ===
type src\Makevars.win
echo ============================

:: ===============================================================
:: Vendor extraction
:: ===============================================================
cd src || exit /b 1

if exist vendor.tar.xz (
    echo [%DATE% %TIME%] Extracting vendor.tar.xz...
    cmake -E tar xf vendor.tar.xz || exit /b 1
)

if not exist vendor mkdir vendor
if not exist vendor\lowess     xcopy /E /Y /Q "..\..\..\crates\lowess"     "vendor\lowess\"
if not exist vendor\fastLowess xcopy /E /Y /Q "..\..\..\crates\fastLowess" "vendor\fastLowess\"

cd .. || exit /b 1

:: ===============================================================
:: Patch Cargo manifests
:: ===============================================================
echo [%DATE% %TIME%] Patching Cargo workspace...

python ..\..\dev\prepare_cargo.py clean src\Cargo.toml || exit /b 1
python ..\..\dev\patch_vendor_crates.py ..\..\Cargo.toml src\vendor || exit /b 1

echo {"files":{},"package":null} > src\vendor\lowess\.cargo-checksum.json
echo {"files":{},"package":null} > src\vendor\fastLowess\.cargo-checksum.json

python ..\..\dev\prepare_cargo.py isolate src\Cargo.toml || exit /b 1

:: ===============================================================
:: Build R package
:: ===============================================================
set R_MAKEVARS_USER=src\Makevars.win
"%R%" CMD INSTALL --build . || exit /b 1

echo [%DATE% %TIME%] Build finished successfully.
exit /b 0

:: ===============================================================
:: Function: Download and extract Rust std
:: ===============================================================
:DownloadAndExtract
set TARGET=%1
set BASE=%RUST_CACHE%\rust-std\%TARGET%
set ARCHIVE=%BASE%\rust-std-%RUST_VERSION%-%TARGET%.tar.gz
set URL=https://static.rust-lang.org/dist/rust-std-%RUST_VERSION%-%TARGET%.tar.gz

if not exist "%BASE%" mkdir "%BASE%"

if exist "%BASE%\done.flag" exit /b 0

start /b "" cmd /c ^
 "if not exist \"%ARCHIVE%\" curl -L --retry 5 -o \"%ARCHIVE%\" \"%URL%\" ^&^& ^
  cmake -E tar xf \"%ARCHIVE%\" -C \"%BASE%\" ^&^& ^
  echo done > \"%BASE%\done.flag\""

exit /b
