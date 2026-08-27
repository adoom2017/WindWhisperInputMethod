#!/bin/bash

set -euo pipefail

artifact="${1:-}"
mode="${2:-local}"
temporary_root=""

fail() {
    echo "windwhisper release verification failed: $*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
        /bin/rm -rf "$temporary_root"
    fi
}
trap cleanup EXIT

case "$mode" in
    local|signed|notarized) ;;
    *) fail "unknown verification mode: $mode" ;;
esac
if [[ -z "$artifact" || ! -e "$artifact" ]]; then
    fail "release artifact does not exist: $artifact"
fi

if [[ -d "$artifact" ]]; then
    release_root="$artifact"
else
    temporary_root="$(mktemp -d /private/tmp/windwhisper-Release-Verify.XXXXXX)"
    /usr/bin/ditto -x -k "$artifact" "$temporary_root"
    release_roots=("$temporary_root"/*)
    if [[ "${#release_roots[@]}" -ne 1 || ! -d "${release_roots[0]}" ]]; then
        fail "archive must contain exactly one release directory"
    fi
    release_root="${release_roots[0]}"
fi

application_path="$release_root/windwhisper.app"
executable="$application_path/Contents/MacOS/windwhisper"
manifest="$release_root/VERSION_MANIFEST.json"

for required in \
    "$application_path" "$executable" "$manifest" \
    "$release_root/LICENSES/THIRD_PARTY_NOTICES.md" \
    "$release_root/INSTALL.md" "$release_root/RELEASE_NOTES.md" \
    "$release_root/KNOWN_ISSUES.md"; do
    [[ -e "$required" ]] || fail "required release content is missing: $required"
done

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$application_path/Contents/Info.plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$application_path/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$application_path/Contents/Info.plist")"
[[ "$bundle_id" == "com.shendongchun.inputmethod.windwhisper.local" ]] \
    || fail "unexpected bundle identifier: $bundle_id"
[[ "$(/usr/bin/plutil -extract version raw "$manifest")" == "$version" ]] \
    || fail "manifest version does not match Info.plist"
[[ "$(/usr/bin/plutil -extract build raw "$manifest")" == "$build" ]] \
    || fail "manifest build does not match Info.plist"
[[ "$(/usr/bin/plutil -extract signingMode raw "$manifest")" == "$mode" ]] \
    || fail "manifest signing mode does not match verification mode"
executable_sha="$(/usr/bin/shasum -a 256 "$executable" | /usr/bin/awk '{print $1}')"
[[ "$(/usr/bin/plutil -extract executableSHA256 raw "$manifest")" == "$executable_sha" ]] \
    || fail "manifest executable checksum does not match"
[[ "$(/usr/bin/plutil -extract inputEngineVersion raw "$manifest")" == "native-1.0" ]] \
    || fail "manifest native input-engine version does not match"

for binary in "$executable"; do
    architectures="$(/usr/bin/lipo -archs "$binary")"
    [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] \
        || fail "universal architectures are missing from $binary"
done
if [[ -e "$application_path/Contents/Frameworks/librime.1.dylib" ]] \
    || /usr/bin/otool -L "$executable" \
    | /usr/bin/grep -Eq 'librime|/opt/homebrew|/usr/local/(Cellar|opt)'; then
    fail "release contains librime or a package-manager runtime dependency"
fi
if /usr/bin/find "$application_path" -type f \( -name '*.swift' -o -name '*.c' -o -name '*.h' \) \
    | /usr/bin/grep -q .; then
    fail "release bundle contains project source files"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$application_path"
signature_details="$(/usr/bin/codesign -dvv "$application_path" 2>&1)"
if [[ "$mode" == "local" ]]; then
    [[ "$signature_details" == *"Signature=adhoc"* ]] \
        || fail "local candidate is not ad-hoc signed"
else
    [[ "$signature_details" == *"Authority=Developer ID Application:"* ]] \
        || fail "release is not signed with Developer ID Application"
    [[ "$signature_details" == *"flags=0x10000(runtime)"* ]] \
        || fail "Hardened Runtime is not enabled"
fi
if [[ "$mode" == "notarized" ]]; then
    /usr/bin/xcrun stapler validate "$application_path"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$application_path"
fi

echo "bundleIdentifier=$bundle_id"
echo "version=$version"
echo "build=$build"
echo "architectures=arm64,x86_64"
echo "signingMode=$mode"
echo "runtimeDependencies=portable"
echo "licenses=present"
echo "Release artifact verified."
