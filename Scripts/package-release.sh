#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-}"
version="${2:-}"
build_number="${3:-$(date +%Y%m%d%H%M)}"
app_identity="${WINDWHISPER_APP_SIGN_IDENTITY:-${WINDWHISPER_CODE_SIGN_IDENTITY:-}}"
installer_identity="${WINDWHISPER_INSTALLER_SIGN_IDENTITY:-}"
notary_profile="${WINDWHISPER_NOTARY_PROFILE:-}"
notary_keychain="${WINDWHISPER_NOTARY_KEYCHAIN:-}"
dist_directory="$project_root/dist"

usage() {
    cat <<'USAGE'
Usage: Scripts/package-release.sh <local|signed|notarized> <version> [build-number]

  local       Ad-hoc signed local release candidate; not for redistribution.
  signed      Developer ID signed app and PKG installer.
  notarized   Signed, notarized, and stapled PKG and DMG.

Signed modes require WINDWHISPER_APP_SIGN_IDENTITY (or the legacy
WINDWHISPER_CODE_SIGN_IDENTITY) and WINDWHISPER_INSTALLER_SIGN_IDENTITY.
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
if [[ "$mode" != "local" && -z "$app_identity" ]]; then
    fail "WINDWHISPER_APP_SIGN_IDENTITY is required for $mode mode"
fi
if [[ "$mode" != "local" && -z "$installer_identity" ]]; then
    fail "WINDWHISPER_INSTALLER_SIGN_IDENTITY is required for $mode mode"
fi
if [[ "$mode" == "notarized" && -z "$notary_profile" ]]; then
    fail "WINDWHISPER_NOTARY_PROFILE is required for notarized mode"
fi
release_name="windwhisper-$version-$build_number-macos-universal"
staging_root="$dist_directory/$release_name"
pkg_path="$dist_directory/$release_name.pkg"
dmg_path="$dist_directory/$release_name.dmg"

if [[ "$staging_root" != "$dist_directory"/* \
    || "$pkg_path" != "$dist_directory"/* \
    || "$dmg_path" != "$dist_directory"/* ]]; then
    fail "resolved release paths escaped the dist directory"
fi
/bin/mkdir -p "$dist_directory"
/bin/rm -rf "$staging_root"
/bin/rm -f \
    "$pkg_path" "$pkg_path.sha256" \
    "$dmg_path" "$dmg_path.sha256"

if [[ "${WINDWHISPER_SKIP_BUILD:-0}" != "1" ]]; then
    ad_hoc_signing=0
    if [[ "$mode" == "local" ]]; then
        ad_hoc_signing=1
    fi
    WINDWHISPER_VERSION="$version" \
    WINDWHISPER_BUILD_NUMBER="$build_number" \
    WINDWHISPER_AD_HOC_SIGNING="$ad_hoc_signing" \
        "$project_root/Scripts/build.sh" Release
fi

built_app="$project_root/build/DerivedData/Build/Products/Release/windwhisper.app"
release_app="$staging_root/windwhisper.app"
/bin/mkdir -p "$staging_root"
/usr/bin/ditto "$built_app" "$release_app"

embedded_documentation="$release_app/Contents/Resources/Documentation"
/bin/mkdir -p "$embedded_documentation"
/usr/bin/ditto "$project_root/LICENSES" "$embedded_documentation/LICENSES"
/bin/cp "$project_root/docs/RELEASE_INSTALL.md" "$embedded_documentation/INSTALL.md"
/bin/cp "$project_root/docs/RELEASE_NOTES.md" "$embedded_documentation/RELEASE_NOTES.md"
/bin/cp "$project_root/docs/KNOWN_ISSUES.md" "$embedded_documentation/KNOWN_ISSUES.md"

if [[ "$mode" == "local" ]]; then
    /usr/bin/codesign --force --sign - "$release_app"
else
    /usr/bin/codesign \
        --force --options runtime --timestamp --sign "$app_identity" \
        "$release_app/Contents/MacOS/windwhisper"
    /usr/bin/codesign \
        --force --options runtime --timestamp --sign "$app_identity" "$release_app"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$release_app"

/usr/bin/ditto "$project_root/LICENSES" "$staging_root/LICENSES"
/bin/cp "$project_root/docs/RELEASE_INSTALL.md" "$staging_root/INSTALL.md"
/bin/cp "$project_root/docs/RELEASE_NOTES.md" "$staging_root/RELEASE_NOTES.md"
/bin/cp "$project_root/docs/KNOWN_ISSUES.md" "$staging_root/KNOWN_ISSUES.md"

executable_sha="$(/usr/bin/shasum -a 256 "$release_app/Contents/MacOS/windwhisper" | /usr/bin/awk '{print $1}')"
dictionary_sha="$(/usr/bin/shasum -a 256 "$project_root/Resources/fy.dict.yaml" | /usr/bin/awk '{print $1}')"
manifest="$staging_root/VERSION_MANIFEST.json"
/usr/bin/plutil -create xml1 "$manifest"
/usr/bin/plutil -insert product -string windwhisper "$manifest"
/usr/bin/plutil -insert bundleIdentifier -string com.shendongchun.inputmethod.windwhisper "$manifest"
/usr/bin/plutil -insert version -string "$version" "$manifest"
/usr/bin/plutil -insert build -string "$build_number" "$manifest"
/usr/bin/plutil -insert architectures -json '["arm64","x86_64"]' "$manifest"
/usr/bin/plutil -insert signingMode -string "$mode" "$manifest"
/usr/bin/plutil -insert inputEngineVersion -string native-1.0 "$manifest"
/usr/bin/plutil -insert executableSHA256 -string "$executable_sha" "$manifest"
/usr/bin/plutil -insert dictionarySHA256 -string "$dictionary_sha" "$manifest"
/usr/bin/plutil -convert json "$manifest"

"$project_root/Scripts/verify-release.sh" "$staging_root" "$mode"

pkg_installer_identity=""
if [[ "$mode" != "local" ]]; then
    pkg_installer_identity="$installer_identity"
fi
"$project_root/Scripts/create-pkg.sh" \
    "$release_app" "$pkg_path" "$version.$build_number" "$pkg_installer_identity"

if [[ "$mode" == "notarized" ]]; then
    notary_arguments=(--keychain-profile "$notary_profile")
    if [[ -n "$notary_keychain" ]]; then
        notary_arguments+=(--keychain "$notary_keychain")
    fi
    /usr/bin/xcrun notarytool submit "$pkg_path" "${notary_arguments[@]}" --wait
    /usr/bin/xcrun stapler staple "$pkg_path"
fi
"$project_root/Scripts/verify-pkg.sh" "$pkg_path" "$mode"
pkg_sha="$(/usr/bin/shasum -a 256 "$pkg_path" | /usr/bin/awk '{print $1}')"
echo "$pkg_sha  $(basename "$pkg_path")" > "$pkg_path.sha256"

"$project_root/Scripts/create-dmg.sh" \
    "$pkg_path" "$dmg_path" "$version" \
    "$release_app/Contents/Resources/AppIcon.icns"
if [[ "$mode" != "local" ]]; then
    /usr/bin/codesign \
        --force --timestamp --sign "$app_identity" \
        "$dmg_path"
fi
if [[ "$mode" == "notarized" ]]; then
    notary_arguments=(--keychain-profile "$notary_profile")
    if [[ -n "$notary_keychain" ]]; then
        notary_arguments+=(--keychain "$notary_keychain")
    fi
    /usr/bin/xcrun notarytool submit "$dmg_path" "${notary_arguments[@]}" --wait
    /usr/bin/xcrun stapler staple "$dmg_path"
fi
"$project_root/Scripts/verify-dmg.sh" "$dmg_path" "$mode"
dmg_sha="$(/usr/bin/shasum -a 256 "$dmg_path" | /usr/bin/awk '{print $1}')"
echo "$dmg_sha  $(basename "$dmg_path")" > "$dmg_path.sha256"

/bin/rm -rf "$staging_root"
echo "Release PKG: $pkg_path"
echo "SHA-256: $pkg_sha"
echo "Release DMG: $dmg_path"
echo "SHA-256: $dmg_sha"
