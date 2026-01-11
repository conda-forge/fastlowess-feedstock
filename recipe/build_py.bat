cd bindings\python
%PYTHON% -m pip install . -vv --no-build-isolation
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
copy THIRDPARTY.yml %RECIPE_DIR%
