#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -ne 2 ]]; then
    echo "Usage: Scripts/publish.sh <notary-profile> <version>" >&2
    echo "  e.g. Scripts/publish.sh windwhisper-notary 1.0.47" >&2
    exit 64
fi
notary_profile="$1"
version="$2"
build_number="$(date +%Y%m%d%H%M)"

# The first matching Developer ID identity in the keychain, unless overridden.
find_identity() {
    /usr/bin/security find-identity -v \
        | /usr/bin/sed -nE "s/^.*\"($1: .*)\"$/\1/p" \
        | /usr/bin/head -n 1
}
app_identity="${WINDWHISPER_APP_SIGN_IDENTITY:-${WINDWHISPER_CODE_SIGN_IDENTITY:-$(find_identity "Developer ID Application")}}"
installer_identity="${WINDWHISPER_INSTALLER_SIGN_IDENTITY:-$(find_identity "Developer ID Installer")}"
if [[ -z "$app_identity" || -z "$installer_identity" ]]; then
    echo "publish failed: Developer ID Application/Installer identity not found in keychain" >&2
    exit 1
fi

echo "Version:   $version ($build_number)"
echo "App:       $app_identity"
echo "Installer: $installer_identity"
echo "Notary:    $notary_profile"

WINDWHISPER_APP_SIGN_IDENTITY="$app_identity" \
WINDWHISPER_INSTALLER_SIGN_IDENTITY="$installer_identity" \
WINDWHISPER_NOTARY_PROFILE="$notary_profile" \
WINDWHISPER_DMG_HEADLESS=1 \
    "$project_root/Scripts/package-release.sh" \
        notarized "$version" "$build_number"
