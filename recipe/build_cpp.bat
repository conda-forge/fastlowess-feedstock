mkdir build_cpp
cd build_cpp

cmake -G "NMake Makefiles" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DCMAKE_INSTALL_LIBDIR=lib ^
    ../bindings/cpp

cmake --build . --config Release
cmake --install . --config Release

cd ..
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
