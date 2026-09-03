#!/bin/bash

set -euo pipefail

application_path="${1:-}"
output_path="${2:-}"
version="${3:-}"
installer_link_name="拖到这里安装"
temporary_root=""

fail() {
    echo "windwhisper DMG creation failed: $*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
        /bin/rm -rf "$temporary_root"
    fi
}
trap cleanup EXIT

[[ -d "$application_path" ]] || fail "application does not exist: $application_path"
[[ -n "$output_path" ]] || fail "output path is required"
[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || fail "version must use numeric dotted notation"

application_path="$(cd "$(dirname "$application_path")" && pwd)/$(basename "$application_path")"
/bin/mkdir -p "$(dirname "$output_path")"
output_path="$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")"

create_dmg="$(command -v create-dmg || true)"
[[ -n "$create_dmg" ]] \
    || fail "create-dmg is required (install it with: brew install create-dmg)"

temporary_root="$(mktemp -d /private/tmp/windwhisper-DMG.XXXXXX)"
dmg_source="$temporary_root/source"
/bin/mkdir -p "$dmg_source"
/usr/bin/ditto "$application_path" "$dmg_source/windwhisper.app"
/bin/ln -s "/Library/Input Methods" "$dmg_source/$installer_link_name"

/bin/rm -f "$output_path"

create_dmg_options=(--format UDZO)
if [[ "${WINDWHISPER_DMG_SANDBOX_SAFE:-0}" == "1" ]]; then
    create_dmg_options+=(--sandbox-safe)
fi
if [[ "${WINDWHISPER_DMG_HEADLESS:-0}" == "1" ]]; then
    create_dmg_options+=(--skip-jenkins)
fi

"$create_dmg" "${create_dmg_options[@]}" \
    --volname "风语输入法 $version" \
    --volicon "$application_path/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 660 380 \
    --text-size 14 \
    --icon-size 128 \
    --icon "windwhisper.app" 170 185 \
    --icon "$installer_link_name" 490 185 \
    --hide-extension "windwhisper.app" \
    --no-internet-enable \
    --overwrite \
    "$output_path" \
    "$dmg_source"

echo "DMG image: $output_path"
