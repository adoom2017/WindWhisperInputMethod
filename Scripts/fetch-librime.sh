#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
version="1.16.0"
commit="a251145d3aafa33871824a40bbec04c966bd8b56"
archive_name="rime-a251145-macOS-universal.tar.bz2"
archive_sha256="e4c9a8767a456f2550f1242921b7656c6e6be088c89a921274bd5d4404f58b99"
archive_url="https://github.com/rime/librime/releases/download/$version/$archive_name"
temporary_root="$(mktemp -d /private/tmp/RimeInputMethod-librime.XXXXXX)"

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

archive_path="$temporary_root/$archive_name"
distribution_path="$temporary_root/distribution"
mkdir -p "$distribution_path"

curl --fail --location --output "$archive_path" "$archive_url"
actual_archive_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
if [[ "$actual_archive_sha256" != "$archive_sha256" ]]; then
    echo "librime archive checksum mismatch." >&2
    exit 65
fi

tar -xjf "$archive_path" -C "$distribution_path"

vendor_include="$project_root/Vendor/librime/include"
vendor_lib="$project_root/Vendor/librime/lib"
rime_data="$project_root/Resources/Rime"
mkdir -p "$vendor_include" "$vendor_lib" "$rime_data"

install -m 0644 "$distribution_path/dist/include/rime_api.h" "$vendor_include/rime_api.h"
install -m 0644 "$distribution_path/dist/include/rime_api_deprecated.h" "$vendor_include/rime_api_deprecated.h"
install -m 0644 "$distribution_path/dist/include/rime_api_stdbool.h" "$vendor_include/rime_api_stdbool.h"
install -m 0644 "$distribution_path/dist/lib/librime.1.16.0.dylib" "$vendor_lib/librime.1.dylib"

download_data_file() {
    local name="$1"
    local expected_sha256="$2"
    local source_url="https://raw.githubusercontent.com/rime/librime/$version/data/minimal/$name"
    local downloaded_path="$temporary_root/$name"

    curl --fail --location --output "$downloaded_path" "$source_url"
    local actual_sha256
    actual_sha256="$(shasum -a 256 "$downloaded_path" | awk '{print $1}')"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        echo "Rime data checksum mismatch: $name" >&2
        exit 65
    fi
    install -m 0644 "$downloaded_path" "$rime_data/$name"
}

download_data_file "cangjie5.dict.yaml" "2dbc120d838ea1e30286f565060d6f84c11623ff1798fd52c97d50e370b833dd"
download_data_file "cangjie5.schema.yaml" "e112cc9624923befde28be408222d3bc3ca95df7c270c508d735570403e8b272"
download_data_file "default.yaml" "f199599315b4b6502072ac6e2afe8569fec917847b558d5a40a1859a4286eb1c"
download_data_file "essay.txt" "3d11a425aa14a47f536812bc60021138bf6aacbe7da69fc0c4fb04f85811173e"
download_data_file "luna_pinyin.dict.yaml" "971baa1f38a42d3d82f858b5bbdcad6482371f8d93a2f5d5c4ab341046419e3b"
download_data_file "luna_pinyin.schema.yaml" "33ae5531d6e220089edd14a9e8a52e38b6dee13eb51795aa93ba5ff97140ab38"
download_data_file "symbols.yaml" "e4cda5663039e284ce62d7febe207bf6b788df6a9705ca174fabd7f8c140ed30"

echo "Fetched librime $version ($commit) and verified all checksums."
