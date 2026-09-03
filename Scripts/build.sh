#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-Debug}"
derived_data_path="$project_root/build/DerivedData"
build_number="${WINDWHISPER_BUILD_NUMBER:-$(date +%s)}"
marketing_version="${WINDWHISPER_VERSION:-0.1.0}"
build_overrides=(MARKETING_VERSION="$marketing_version")

if [[ "${WINDWHISPER_AD_HOC_SIGNING:-0}" == "1" ]]; then
    build_overrides+=(
        CODE_SIGN_IDENTITY=-
        CODE_SIGN_STYLE=Manual
        DEVELOPMENT_TEAM=
    )
fi

case "$configuration" in
    Debug|Release|AppStore) ;;
    *)
        echo "Usage: $0 [Debug|Release|AppStore]" >&2
        exit 64
        ;;
esac

if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
    echo "WINDWHISPER_BUILD_NUMBER must contain only digits." >&2
    exit 64
fi
if [[ ! "$marketing_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "WINDWHISPER_VERSION must use numeric dotted notation (for example 1.0.0)." >&2
    exit 64
fi

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
        "${build_overrides[@]}" \
        build
else
    xcodebuild \
        -project "$project_root/WindWhisperInputMethod.xcodeproj" \
        -scheme windwhisper \
        -configuration "$configuration" \
        -destination "$destination" \
        -derivedDataPath "$derived_data_path" \
        CURRENT_PROJECT_VERSION="$build_number" \
        "${build_overrides[@]}" \
        build
fi

echo "$derived_data_path/Build/Products/$configuration/windwhisper.app"
