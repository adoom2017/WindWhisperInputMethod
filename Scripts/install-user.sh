#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_root/Scripts/lib/install-transaction.sh"
configuration="${1:-Debug}"
source_app="$project_root/build/DerivedData/Build/Products/$configuration/windwhisper.app"
install_directory="$HOME/Library/Input Methods"
installed_app="$install_directory/windwhisper.app"
installing_app="$install_directory/windwhisper.installing"
previous_app="$install_directory/windwhisper.previous"
system_app="/Library/Input Methods/windwhisper.app"
expected_bundle_id="com.shendongchun.inputmethod.windwhisper"
input_mode_id="com.shendongchun.inputmethod.windwhisper.Hans"
fallback_input_mode_id="com.apple.keylayout.ABC"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fail() {
    echo "windwhisper install failed: $*" >&2
    exit 1
}

bundle_id_at() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

if [[ ! -d "$source_app" ]]; then
    fail "build not found at $source_app; run Scripts/build.sh $configuration first"
fi

actual_bundle_id="$(bundle_id_at "$source_app")"
if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
    fail "refusing unexpected bundle: $actual_bundle_id"
fi

if [[ -e "$system_app" ]]; then
    fail "a system-wide windwhisper copy exists; keep exactly one development bundle"
fi

if [[ -e "$installing_app" || -e "$previous_app" ]]; then
    fail "an unfinished install is present in $install_directory"
fi

signing_identity="${WINDWHISPER_CODE_SIGN_IDENTITY:--}"

build_version="$(date +%s)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_version" "$source_app/Contents/Info.plist"
if [[ ! -f "$source_app/Contents/PkgInfo" ]]; then
    printf 'APPL????' > "$source_app/Contents/PkgInfo"
fi

echo "Signing for local development..."
while IFS= read -r -d '' code_file; do
    /usr/bin/codesign --force --sign "$signing_identity" "$code_file"
done < <(
    /usr/bin/find \
        "$source_app/Contents/Frameworks" \
        "$source_app/Contents/MacOS" \
        -type f -print0
)
/usr/bin/codesign --force --sign "$signing_identity" "$source_app"
/usr/bin/codesign --verify --deep --strict "$source_app"

source_binary="$source_app/Contents/MacOS/windwhisper"
original_input_source="$($source_binary --current-input-source)"
if [[ "$original_input_source" == "" ]]; then
    "$source_binary" --select-input-source-id "$fallback_input_mode_id"
fi

/bin/mkdir -p "$install_directory"
/usr/bin/pkill -x windwhisper 2>/dev/null || true
"$lsregister" -u "$source_app" 2>/dev/null || true
"$lsregister" -u "$installed_app" 2>/dev/null || true

restore_previous_install() {
    trap - ERR
    if [[ -n "${original_input_source:-}" && -x "${installed_binary:-}" ]]; then
        "$installed_binary" --select-input-source-id "$original_input_source" >/dev/null 2>&1 || true
    fi
    "$lsregister" -u "$installed_app" 2>/dev/null || true
    if ! windwhisper_rollback_install_transaction \
        "$source_app" "$installed_app" "$installing_app" "$previous_app"; then
        echo "windwhisper: automatic install rollback failed" >&2
    fi
    if [[ -e "$installed_app" ]]; then
        "$lsregister" -f "$installed_app" 2>/dev/null || true
    fi
}
trap restore_previous_install ERR

windwhisper_begin_install_transaction \
    "$source_app" "$installed_app" "$installing_app" "$previous_app"

installed_binary="$installed_app/Contents/MacOS/windwhisper"
"$lsregister" -f "$installed_app"
"$installed_binary" --register-input-source

echo "Refreshing the current login session's input-method services..."
/usr/bin/killall imklaunchagent 2>/dev/null || true
/usr/bin/killall TextInputMenuAgent 2>/dev/null || true
/usr/bin/killall -9 TextInputSwitcher 2>/dev/null || true
/usr/bin/killall -9 CursorUIViewService 2>/dev/null || true
/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/com.apple.imklaunchagent" 2>/dev/null || true

parent_status="found=false"
for _ in {1..60}; do
    parent_status="$("$installed_binary" --input-method-parent-status)"
    if [[ "$parent_status" == *"found=true"* ]]; then
        break
    fi
    /bin/sleep 0.5
done
if [[ "$parent_status" != *"found=true"* ]]; then
    echo "$parent_status"
    echo "windwhisper install failed: macOS did not expose parent input method $expected_bundle_id" >&2
    false
fi

input_source_status="found=false"
for _ in {1..60}; do
    input_source_status="$("$installed_binary" --input-source-status)"
    if [[ "$input_source_status" == *"found=true"* ]]; then
        break
    fi
    /bin/sleep 0.5
done
if [[ "$input_source_status" != *"found=true"* ]]; then
    echo "$input_source_status"
    echo "windwhisper install failed: macOS did not expose input mode $input_mode_id" >&2
    false
fi

enabled_third_party_sources="$(
    /usr/bin/defaults read \
        com.apple.inputsources AppleEnabledThirdPartyInputSources 2>/dev/null || true
)"
authorization_required=false
if [[ "$enabled_third_party_sources" != *"$input_mode_id"* ]]; then
    authorization_required=true
    echo "macOS authorization is required for the new windwhisper input-source identity."
fi

if [[ "$authorization_required" == false ]]; then
    "$installed_binary" --enable-input-method-parent >/dev/null 2>&1 || true
    "$installed_binary" --enable-input-source >/dev/null 2>&1 || true
    for _ in {1..60}; do
        input_source_status="$("$installed_binary" --input-source-status)"
        if [[ "$input_source_status" == *"enabled=true"* ]]; then
            break
        fi
        /bin/sleep 0.5
    done
    if [[ "$input_source_status" != *"enabled=true"* ]]; then
        echo "windwhisper install failed: authorized input mode did not become enabled" >&2
        false
    fi

    /usr/bin/open -gj "$installed_app" 2>/dev/null || true
    /bin/sleep 1

    select_succeeded=false
    for _ in {1..60}; do
        if "$installed_binary" --select-input-source >/dev/null 2>&1; then
            select_succeeded=true
        fi
        input_source_status="$("$installed_binary" --input-source-status)"
        if [[ "$select_succeeded" == true && "$input_source_status" == *"selected=true"* ]]; then
            break
        fi
        /bin/sleep 0.5
    done
    if [[ "$input_source_status" != *"selected=true"* ]]; then
        echo "Input mode is enabled; initial selection is deferred until macOS finishes refreshing it."
    fi
fi

if [[ "$authorization_required" == false ]]; then
    if [[ -n "$original_input_source" \
        && "$original_input_source" != "$input_mode_id" \
        && "$original_input_source" != "$input_mode_id" ]]; then
        "$installed_binary" --select-input-source-id "$original_input_source" >/dev/null || true
    fi

else
    if [[ -n "$original_input_source" ]]; then
        "$installed_binary" --select-input-source-id "$original_input_source" >/dev/null 2>&1 || true
    fi
    echo "The installed legacy input method was kept active until windwhisper is authorized."
fi

windwhisper_commit_install_transaction "$previous_app"
trap - ERR

echo "$input_source_status"
if [[ "$authorization_required" == true ]]; then
    echo "Installed with a fresh identity: $installed_app"
    echo "Add windwhisper in System Settings > Keyboard > Text Input > Edit before selecting it."
else
    echo "Installed and enabled without logout: $installed_app"
fi
echo "Current input source: $("$installed_binary" --current-input-source)"
