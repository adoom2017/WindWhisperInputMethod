#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-Debug}"
derived_data_path="$project_root/build/DerivedData"
build_number="${WINDWHISPER_BUILD_NUMBER:-$(date +%s)}"

case "$configuration" in
    Debug|Release) ;;
    *)
        echo "Usage: $0 [Debug|Release]" >&2
        exit 64
        ;;
esac

destination="generic/platform=macOS"
if [[ "$configuration" == "Debug" ]]; then
    destination="platform=macOS,arch=arm64"
    xcodebuild \
        -project "$project_root/WindWhisperInputMethod.xcodeproj" \
        -scheme windwhisper \
        -configuration "$configuration" \
        -destination "$destination" \
        -derivedDataPath "$derived_data_path" \
        CURRENT_PROJECT_VERSION="$build_number" \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=YES \
        build
else
    xcodebuild \
        -project "$project_root/WindWhisperInputMethod.xcodeproj" \
        -scheme windwhisper \
        -configuration "$configuration" \
        -destination "$destination" \
        -derivedDataPath "$derived_data_path" \
        CURRENT_PROJECT_VERSION="$build_number" \
        build
fi

echo "$derived_data_path/Build/Products/$configuration/windwhisper.app"
