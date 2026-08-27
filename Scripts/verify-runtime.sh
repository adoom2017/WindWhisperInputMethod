#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
application_path="${1:-$project_root/build/DerivedData/Build/Products/Debug/windwhisper.app}"
executable="$application_path/Contents/MacOS/windwhisper"

if [[ ! -x "$executable" ]]; then
    echo "Missing application executable." >&2
    exit 66
fi

if [[ -e "$application_path/Contents/Frameworks/librime.1.dylib" ]] || otool -L "$executable" | grep -q 'librime'; then
    echo "The application must not link or embed librime." >&2
    exit 65
fi

executable_architectures="$(lipo -archs "$executable")"
if [[ "$executable_architectures" != *arm64* ]]; then
    echo "The application executable is missing arm64." >&2
    exit 65
fi
if [[ "$application_path" == */Release/* && "$executable_architectures" != *x86_64* ]]; then
    echo "The Release application executable is missing x86_64." >&2
    exit 65
fi

codesign --verify --deep --strict "$application_path"
echo "Native input engine runtime verified."
