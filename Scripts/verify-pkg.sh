#!/bin/bash

set -euo pipefail

pkg_path="${1:-}"
mode="${2:-local}"
temporary_root=""

fail() {
    echo "windwhisper PKG verification failed: $*" >&2
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
[[ -f "$pkg_path" ]] || fail "PKG does not exist: $pkg_path"

payload_files="$(/usr/sbin/pkgutil --payload-files "$pkg_path")"
for required_payload in \
    'Library/Input Methods/windwhisper.app/Contents/MacOS/windwhisper' \
    'Library/Input Methods/windwhisper.app/Contents/Resources/Documentation/LICENSES/THIRD_PARTY_NOTICES.md' \
    'Library/Input Methods/windwhisper.app/Contents/Resources/Documentation/INSTALL.md'; do
    if ! /usr/bin/grep -qF "$required_payload" <<< "$payload_files"; then
        fail "required PKG payload is missing: $required_payload"
    fi
done

temporary_root="$(mktemp -d /private/tmp/windwhisper-PKG-Verify.XXXXXX)"
expanded_path="$temporary_root/expanded"
/usr/sbin/pkgutil --expand "$pkg_path" "$expanded_path"
package_info="$expanded_path/PackageInfo"
if ! /usr/bin/grep -q 'identifier="com.shendongchun.inputmethod.windwhisper.pkg"' "$package_info" \
    || ! /usr/bin/grep -q 'install-location="/"' "$package_info" \
    || ! /usr/bin/grep -q 'auth="root"' "$package_info"; then
    fail "PKG metadata does not enforce the system-wide installation contract"
fi
if /usr/bin/grep -q '<relocate>' "$package_info"; then
    fail "PKG payload allows the input method bundle to be relocated"
fi
for installer_script in preinstall postinstall; do
    script_path="$expanded_path/Scripts/$installer_script"
    [[ -x "$script_path" ]] || fail "$installer_script is missing or not executable"
done
if ! /usr/bin/grep -q 'pkill -x windwhisper' "$expanded_path/Scripts/preinstall"; then
    fail "preinstall does not stop the running windwhisper process"
fi
if ! /usr/bin/grep -q 'lsregister.*-f' "$expanded_path/Scripts/postinstall"; then
    fail "postinstall does not register the installed input method"
fi

signature_details=""
signature_valid=false
if signature_details="$(/usr/sbin/pkgutil --check-signature "$pkg_path" 2>&1)"; then
    signature_valid=true
fi
if [[ "$mode" == "local" ]]; then
    [[ "$signature_valid" == false ]] || fail "local PKG must remain unsigned"
else
    [[ "$signature_valid" == true ]] || fail "PKG signature is invalid"
    [[ "$signature_details" == *"Developer ID Installer:"* ]] \
        || fail "PKG is not signed with Developer ID Installer"
fi

if [[ "$mode" == "notarized" ]]; then
    /usr/bin/xcrun stapler validate "$pkg_path"
    /usr/sbin/spctl --assess --type install --verbose=2 "$pkg_path"
fi

echo "installTarget=/Library/Input Methods/windwhisper.app"
echo "upgradeProcessStop=present"
echo "postInstallRegistration=present"
echo "embeddedDocumentation=present"
echo "PKG installer verified."
