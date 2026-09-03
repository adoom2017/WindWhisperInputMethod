#!/bin/bash

set -euo pipefail

dmg_path="${1:-}"
mode="${2:-local}"
temporary_root=""
mounted=0

fail() {
    echo "windwhisper DMG verification failed: $*" >&2
    exit 1
}

cleanup() {
    if [[ "$mounted" == "1" ]]; then
        /usr/bin/hdiutil detach "$mount_point" -quiet || true
    fi
    if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
        /bin/rm -rf "$temporary_root"
    fi
}
trap cleanup EXIT

case "$mode" in
    local|signed|notarized) ;;
    *) fail "unknown verification mode: $mode" ;;
esac
[[ -f "$dmg_path" ]] || fail "DMG does not exist: $dmg_path"

temporary_root="$(mktemp -d /private/tmp/windwhisper-DMG-Verify.XXXXXX)"
mount_point="$temporary_root/mount"
/bin/mkdir -p "$mount_point"
/usr/bin/hdiutil attach \
    -readonly -nobrowse -noautoopen -mountpoint "$mount_point" "$dmg_path" -quiet
mounted=1

application_path="$mount_point/windwhisper.app"
installer_link="$mount_point/拖到这里安装"
[[ -d "$application_path" ]] || fail "windwhisper.app is missing"
[[ -L "$installer_link" ]] || fail "installer destination link is missing"
[[ "$(/usr/bin/readlink "$installer_link")" == "/Library/Input Methods" ]] \
    || fail "installer destination link has an unexpected target"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$application_path"

if [[ "$mode" == "signed" ]]; then
    /usr/bin/codesign --verify --verbose=2 "$dmg_path"
fi
if [[ "$mode" == "notarized" ]]; then
    /usr/bin/xcrun stapler validate "$dmg_path"
    /usr/sbin/spctl --assess --type open \
        --context context:primary-signature --verbose=2 "$dmg_path"
fi

echo "application=present"
echo "installTarget=/Library/Input Methods"
echo "layout=drag-to-install"
echo "DMG artifact verified."
