mkdir C:\tmp
set TMP=C:\tmp
set TEMP=C:\tmp

cd bindings/r

:: Fetch and install rust-std-x86_64-pc-windows-gnu to match the installed rustc version
:: This is required because R (MinGW) cannot link against MSVC-compiled Rust code.
for /f "tokens=2" %%i in ('rustc --version') do set RUST_VERSION=%%i
set RUST_STD_URL=https://static.rust-lang.org/dist/rust-std-%RUST_VERSION%-x86_64-pc-windows-gnu.tar.gz
set RUST_STD_ARCHIVE=rust-std.tar.gz

echo Downloading %RUST_STD_URL%...
curl -L -o %RUST_STD_ARCHIVE% %RUST_STD_URL%
if errorlevel 1 exit 1

echo Extracting bundled rust-std...
cmake -E tar xf %RUST_STD_ARCHIVE%

echo Installing rust-std to sysroot...
for /f "delims=" %%i in ('rustc --print sysroot') do set RUST_SYSROOT=%%i
xcopy /E /Y /Q "rust-std-%RUST_VERSION%-x86_64-pc-windows-gnu\rust-std-x86_64-pc-windows-gnu\lib\rustlib\x86_64-pc-windows-gnu" "%RUST_SYSROOT%\lib\rustlib\x86_64-pc-windows-gnu\"
if errorlevel 1 exit 1

:: Isolate R build target to prevent picking up MSVC artifacts from previous build steps
sed -i "s|TARGET_DIR = ../target|TARGET_DIR = ../target_gnu|g" src/Makevars.win

:: Define RES to a dummy non-empty value to prevent 'rm: missing operand' error in R's winshlib.mk
:: R 4.x winshlib.mk may call $(RM) $(RES) without checking if RES is empty.
echo. >> src/Makevars.win
echo RES = dummy_res_file >> src/Makevars.win
echo RM = rm -f >> src/Makevars.win
echo. > src/dummy_res_file

:: Pre-extract vendored dependencies using cmake (more robust on win than msys tar/xz)
cd src
if exist vendor.tar.xz (
    echo "Extracting vendor.tar.xz..."
    cmake -E tar xf vendor.tar.xz
)

echo Copying local crates to vendor...
if not exist vendor mkdir vendor
if not exist vendor\lwoess mkdir vendor\lowess
if not exist vendor\fastLowess mkdir vendor\fastLowess
xcopy /E /Y /Q "..\..\..\crates\lowess" "vendor\lowess\"
xcopy /E /Y /Q "..\..\..\crates\fastLowess" "vendor\fastLowess\"
cd ..

"%R%" CMD INSTALL --build .
if errorlevel 1 exit 1
