#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-}"
version="${2:-}"
build_number="${3:-$(date +%Y%m%d%H%M)}"
identity="${WINDWHISPER_CODE_SIGN_IDENTITY:-}"
notary_profile="${WINDWHISPER_NOTARY_PROFILE:-}"
dist_directory="$project_root/dist"

usage() {
    cat <<'USAGE'
Usage: Scripts/package-release.sh <local|signed|notarized> <version> [build-number]

  local       Ad-hoc signed local release candidate; not for redistribution.
  signed      Developer ID signed package; requires WINDWHISPER_CODE_SIGN_IDENTITY.
  notarized   Signed, notarized, and stapled package; also requires WINDWHISPER_NOTARY_PROFILE.
USAGE
}

fail() {
    echo "windwhisper release packaging failed: $*" >&2
    exit 1
}

case "$mode" in
    local|signed|notarized) ;;
    *) usage >&2; exit 64 ;;
esac
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    fail "version must use numeric dotted notation (for example 1.0.0)"
fi
if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
    fail "build number must contain only digits"
fi
if [[ "$mode" != "local" && -z "$identity" ]]; then
    fail "WINDWHISPER_CODE_SIGN_IDENTITY is required for $mode mode"
fi
if [[ "$mode" == "notarized" && -z "$notary_profile" ]]; then
    fail "WINDWHISPER_NOTARY_PROFILE is required for notarized mode"
fi

release_name="windwhisper-$version-$build_number-macos-universal"
staging_root="$dist_directory/$release_name"
archive_path="$dist_directory/$release_name.zip"
submission_archive="$dist_directory/$release_name.notary.zip"

if [[ "$staging_root" != "$dist_directory"/* \
    || "$archive_path" != "$dist_directory"/* \
    || "$submission_archive" != "$dist_directory"/* ]]; then
    fail "resolved release paths escaped the dist directory"
fi
/bin/mkdir -p "$dist_directory"
/bin/rm -rf "$staging_root"
/bin/rm -f "$archive_path" "$submission_archive" "$archive_path.sha256"

if [[ "${WINDWHISPER_SKIP_BUILD:-0}" != "1" ]]; then
    WINDWHISPER_VERSION="$version" \
    WINDWHISPER_BUILD_NUMBER="$build_number" \
        "$project_root/Scripts/build.sh" Release
fi

built_app="$project_root/build/DerivedData/Build/Products/Release/windwhisper.app"
release_app="$staging_root/windwhisper.app"
/bin/mkdir -p "$staging_root"
/usr/bin/ditto "$built_app" "$release_app"

if [[ "$mode" != "local" ]]; then
    while IFS= read -r -d '' code_file; do
        /usr/bin/codesign \
            --force --options runtime --timestamp --sign "$identity" "$code_file"
    done < <(/usr/bin/find "$release_app/Contents/Frameworks" -type f -print0)
    /usr/bin/codesign \
        --force --options runtime --timestamp --sign "$identity" \
        "$release_app/Contents/MacOS/windwhisper"
    /usr/bin/codesign \
        --force --options runtime --timestamp --sign "$identity" "$release_app"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$release_app"

if [[ "$mode" == "notarized" ]]; then
    /usr/bin/ditto -c -k --keepParent "$release_app" "$submission_archive"
    /usr/bin/xcrun notarytool submit "$submission_archive" \
        --keychain-profile "$notary_profile" --wait
    /usr/bin/xcrun stapler staple "$release_app"
    /usr/bin/xcrun stapler validate "$release_app"
    /bin/rm -f "$submission_archive"
fi

/usr/bin/ditto "$project_root/LICENSES" "$staging_root/LICENSES"
/bin/cp "$project_root/docs/RELEASE_INSTALL.md" "$staging_root/INSTALL.md"
/bin/cp "$project_root/docs/RELEASE_NOTES.md" "$staging_root/RELEASE_NOTES.md"
/bin/cp "$project_root/docs/KNOWN_ISSUES.md" "$staging_root/KNOWN_ISSUES.md"

executable_sha="$(/usr/bin/shasum -a 256 "$release_app/Contents/MacOS/windwhisper" | /usr/bin/awk '{print $1}')"
librime_sha="$(/usr/bin/shasum -a 256 "$release_app/Contents/Frameworks/librime.1.dylib" | /usr/bin/awk '{print $1}')"
data_lock_sha="$(/usr/bin/shasum -a 256 "$project_root/Resources/Rime/DATA_LOCK.json" | /usr/bin/awk '{print $1}')"
manifest="$staging_root/VERSION_MANIFEST.json"
/usr/bin/plutil -create xml1 "$manifest"
/usr/bin/plutil -insert product -string windwhisper "$manifest"
/usr/bin/plutil -insert bundleIdentifier -string com.shendongchun.inputmethod.windwhisper.local "$manifest"
/usr/bin/plutil -insert version -string "$version" "$manifest"
/usr/bin/plutil -insert build -string "$build_number" "$manifest"
/usr/bin/plutil -insert architectures -json '["arm64","x86_64"]' "$manifest"
/usr/bin/plutil -insert signingMode -string "$mode" "$manifest"
/usr/bin/plutil -insert librimeVersion -string 1.16.0 "$manifest"
/usr/bin/plutil -insert executableSHA256 -string "$executable_sha" "$manifest"
/usr/bin/plutil -insert librimeSHA256 -string "$librime_sha" "$manifest"
/usr/bin/plutil -insert dataLockSHA256 -string "$data_lock_sha" "$manifest"
/usr/bin/plutil -convert json "$manifest"

/usr/bin/ditto -c -k --keepParent "$staging_root" "$archive_path"
archive_sha="$(/usr/bin/shasum -a 256 "$archive_path" | /usr/bin/awk '{print $1}')"
echo "$archive_sha  $(basename "$archive_path")" > "$archive_path.sha256"

"$project_root/Scripts/verify-release.sh" "$archive_path" "$mode"
echo "Release archive: $archive_path"
echo "SHA-256: $archive_sha"
