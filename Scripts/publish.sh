#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-1.0.0}"
build_number="${2:-$(date +%Y%m%d%H%M)}"
app_identity="${WINDWHISPER_APP_SIGN_IDENTITY:-${WINDWHISPER_CODE_SIGN_IDENTITY:-Developer ID Application: Dongchun Shen (YH6JCRN97J)}}"
installer_identity="${WINDWHISPER_INSTALLER_SIGN_IDENTITY:-Developer ID Installer: Dongchun Shen (YH6JCRN97J)}"
notary_profile="${WINDWHISPER_NOTARY_PROFILE:-windwhisper-notary}"

WINDWHISPER_APP_SIGN_IDENTITY="$app_identity" \
WINDWHISPER_INSTALLER_SIGN_IDENTITY="$installer_identity" \
WINDWHISPER_NOTARY_PROFILE="$notary_profile" \
WINDWHISPER_DMG_HEADLESS=1 \
    "$project_root/Scripts/package-release.sh" \
        notarized "$version" "$build_number"
