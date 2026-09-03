#!/bin/bash

set -euo pipefail

pkg_path="${1:-}"
output_path="${2:-}"
version="${3:-}"
volume_icon="${4:-}"
installer_name="安装风语.pkg"
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

[[ -f "$pkg_path" ]] || fail "PKG installer does not exist: $pkg_path"
[[ -n "$output_path" ]] || fail "output path is required"
[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || fail "version must use numeric dotted notation"

pkg_path="$(cd "$(dirname "$pkg_path")" && pwd)/$(basename "$pkg_path")"
/bin/mkdir -p "$(dirname "$output_path")"
output_path="$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")"

create_dmg="$(command -v create-dmg || true)"
[[ -n "$create_dmg" ]] \
    || fail "create-dmg is required (install it with: brew install create-dmg)"

temporary_root="$(mktemp -d /private/tmp/windwhisper-DMG.XXXXXX)"
dmg_source="$temporary_root/source"
/bin/mkdir -p "$dmg_source"
/bin/cp "$pkg_path" "$dmg_source/$installer_name"

/bin/rm -f "$output_path"

create_dmg_options=(--format UDZO)
if [[ -n "$volume_icon" ]]; then
    [[ -f "$volume_icon" ]] || fail "volume icon does not exist: $volume_icon"
    create_dmg_options+=(--volicon "$volume_icon")
fi
if [[ "${WINDWHISPER_DMG_SANDBOX_SAFE:-0}" == "1" ]]; then
    create_dmg_options+=(--sandbox-safe)
fi
if [[ "${WINDWHISPER_DMG_HEADLESS:-0}" == "1" ]]; then
    create_dmg_options+=(--skip-jenkins)
fi

"$create_dmg" "${create_dmg_options[@]}" \
    --volname "风语输入法 $version" \
    --window-pos 200 120 \
    --window-size 540 360 \
    --text-size 14 \
    --icon-size 128 \
    --icon "$installer_name" 270 175 \
    --hide-extension "$installer_name" \
    --no-internet-enable \
    --overwrite \
    "$output_path" \
    "$dmg_source"

echo "DMG image: $output_path"
