#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
application_path="${1:-}"
output_path="${2:-}"
package_version="${3:-}"
installer_identity="${4:-}"
temporary_root=""

fail() {
    echo "windwhisper PKG creation failed: $*" >&2
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
[[ "$package_version" =~ ^[0-9]+(\.[0-9]+)+$ ]] \
    || fail "package version must use numeric dotted notation"

application_path="$(cd "$(dirname "$application_path")" && pwd)/$(basename "$application_path")"
/bin/mkdir -p "$(dirname "$output_path")"
output_path="$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")"

temporary_root="$(mktemp -d /private/tmp/windwhisper-PKG.XXXXXX)"
payload_root="$temporary_root/payload"
install_directory="$payload_root/Library/Input Methods"
/bin/mkdir -p "$install_directory"
/usr/bin/ditto "$application_path" "$install_directory/windwhisper.app"

component_plist="$temporary_root/components.plist"
/usr/bin/pkgbuild --analyze --root "$payload_root" "$component_plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$component_plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsVersionChecked false' "$component_plist"

pkgbuild_arguments=(
    --root "$payload_root"
    --scripts "$project_root/Installer/macOS/Scripts"
    --component-plist "$component_plist"
    --identifier com.shendongchun.inputmethod.windwhisper.pkg
    --version "$package_version"
    --install-location /
    --ownership recommended
)
if [[ -n "$installer_identity" ]]; then
    pkgbuild_arguments+=(--sign "$installer_identity")
fi

/bin/rm -f "$output_path"
/usr/bin/pkgbuild "${pkgbuild_arguments[@]}" "$output_path"
echo "PKG installer: $output_path"
