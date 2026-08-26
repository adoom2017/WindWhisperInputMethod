#!/bin/bash

set -euo pipefail

installed_app="$HOME/Library/Input Methods/windwhisper.app"
expected_bundle_id="com.shendongchun.inputmethod.windwhisper.local"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$installed_app" ]]; then
    echo "windwhisper is not installed for the current user."
    exit 0
fi

actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist")"
if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
    echo "Refusing to move unexpected bundle: $actual_bundle_id" >&2
    exit 65
fi

trash_directory="$HOME/.Trash"
trash_app="$trash_directory/windwhisper.$(date +%Y%m%d-%H%M%S).removed"
mkdir -p "$trash_directory"
"$installed_app/Contents/MacOS/windwhisper" --disable-input-source 2>/dev/null || true
"$installed_app/Contents/MacOS/windwhisper" --disable-input-method-parent 2>/dev/null || true
pkill -x windwhisper 2>/dev/null || true
"$lsregister" -u "$installed_app" 2>/dev/null || true
mv "$installed_app" "$trash_app"
/usr/bin/killall imklaunchagent 2>/dev/null || true
/usr/bin/killall TextInputMenuAgent 2>/dev/null || true
/bin/launchctl kickstart -k "gui/$(id -u)/com.apple.imklaunchagent" 2>/dev/null || true

echo "Moved to Trash: $trash_app"
echo "Input-method services refreshed; logout is not required."
