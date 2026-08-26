#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
application_path="${1:-$project_root/build/DerivedData/Build/Products/Debug/windwhisper.app}"
executable="$application_path/Contents/MacOS/windwhisper"
library="$application_path/Contents/Frameworks/librime.1.dylib"

if [[ ! -x "$executable" || ! -f "$library" ]]; then
    echo "Missing application executable or embedded librime." >&2
    exit 66
fi

if ! otool -L "$executable" | grep -q '@rpath/librime.1.dylib'; then
    echo "The application does not link the embedded librime install name." >&2
    exit 65
fi

if otool -L "$executable" "$library" | grep -Eq '/opt/homebrew|/usr/local/(Cellar|opt)'; then
    echo "The application contains a development-machine package-manager dependency." >&2
    exit 65
fi

if ! file "$library" | grep -q 'arm64'; then
    echo "The embedded librime is missing arm64." >&2
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
echo "Embedded librime runtime verified."
