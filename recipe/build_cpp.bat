@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ===============================================================
:: CI-friendly temporary directories (avoid /tmp warnings)
:: ===============================================================
if not exist C:\tmp mkdir C:\tmp
set TMP=C:\tmp
set TEMP=C:\tmp
set TMPDIR=C:\tmp

:: ===============================================================
:: Clean, reproducible out-of-source build
:: ===============================================================
if exist build_cpp rmdir /S /Q build_cpp
mkdir build_cpp || exit /b 1

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
echo             f.write('members = [\"crates/lowess\", \"crates/fastLowess\", \"bindings/cpp\"]\n') >> rewrite.py
echo             continue >> rewrite.py
echo         if im: >> rewrite.py
echo             if l.strip().startswith(']'): im = False >> rewrite.py
echo             continue >> rewrite.py
echo         f.write(l) >> rewrite.py
python rewrite.py

cd build_cpp || exit /b 1

:: ===============================================================
:: Toolchain sanity checks
:: ===============================================================
where cmake >nul 2>&1 || (echo ERROR: cmake not found! & exit /b 1)

:: ===============================================================
:: Configure C++ bindings
:: ===============================================================
echo [%DATE% %TIME%] Configuring C++ bindings...

:: Remove -A and -T flags as they are incompatible with the Ninja generator
set "CMAKE_ARGS=%CMAKE_ARGS:-A x64=%"
set "CMAKE_ARGS=%CMAKE_ARGS:-T v142=%"
set "CMAKE_ARGS=%CMAKE_ARGS:-T v141=%"

cmake ^
  %CMAKE_ARGS% ^
  -G "NMake Makefiles" ^
  -DCMAKE_C_COMPILER="%CC%" ^
  -DCMAKE_CXX_COMPILER="%CXX%" ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
  -DCMAKE_INSTALL_LIBDIR=lib ^
  -S "%SRC_DIR%\bindings\cpp" ^
  -B . ^
  || exit /b 1

:: ===============================================================
:: Build C++ bindings (parallel)
:: ===============================================================
echo [%DATE% %TIME%] Building C++ bindings...
cmake --build . --config Release --parallel || exit /b 1

:: ===============================================================
:: Install C++ bindings
:: ===============================================================
echo [%DATE% %TIME%] Installing C++ bindings...
cmake --install . --config Release || exit /b 1

:: ===============================================================
:: Return to source directory
:: ===============================================================
cd "%SRC_DIR%" || exit /b 1

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
    --output "%SRC_DIR%\THIRDPARTY.yml" ^
    || exit /b 1

echo [%DATE% %TIME%] C++ bindings build completed successfully.
exit /b 0
