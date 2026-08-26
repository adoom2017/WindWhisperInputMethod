#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-Debug}"
source_app="$project_root/build/DerivedData/Build/Products/$configuration/RimeInputMethod.app"
install_directory="$HOME/Library/Input Methods"
installed_app="$install_directory/RimeInputMethod.app"
installing_app="$install_directory/RimeInputMethod.installing"
previous_app="$install_directory/RimeInputMethod.previous"
failed_migration_app="$install_directory/FengYuInputMethod.app"
system_app="/Library/Input Methods/RimeInputMethod.app"
failed_system_app="/Library/Input Methods/FengYuInputMethod.app"
expected_bundle_id="com.shendongchun.inputmethod.rime.dev"
input_mode_id="com.shendongchun.inputmethod.rime.dev.Hans"
failed_bundle_id="com.shendongchun.inputmethod.fengyu"
failed_input_mode_id="com.shendongchun.inputmethod.fengyu.Hans"
transitional_input_mode_id="com.shendongchun.inputmethod.rime.dev.FengYuHans"
fallback_input_mode_id="com.apple.keylayout.ABC"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fail() {
    echo "RimeInputMethod install failed: $*" >&2
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

if [[ -e "$system_app" || -e "$failed_system_app" ]]; then
    fail "a system-wide FengYu/RimeInputMethod copy exists; keep exactly one development bundle"
fi

if [[ -e "$installing_app" || -e "$previous_app" ]]; then
    fail "an unfinished install is present in $install_directory"
fi

signing_identity="${RIME_CODE_SIGN_IDENTITY:--}"

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

previous_input_source="$($source_app/Contents/MacOS/RimeInputMethod --current-input-source)"
if [[ "$previous_input_source" == "$failed_input_mode_id" \
    || "$previous_input_source" == "$transitional_input_mode_id" ]]; then
    "$source_app/Contents/MacOS/RimeInputMethod" \
        --select-input-source-id "$fallback_input_mode_id"
    previous_input_source="$fallback_input_mode_id"
fi
"$source_app/Contents/MacOS/RimeInputMethod" \
    --disable-input-source-id "$failed_input_mode_id" >/dev/null 2>&1 || true
"$source_app/Contents/MacOS/RimeInputMethod" \
    --disable-input-source-id "$transitional_input_mode_id" >/dev/null 2>&1 || true
"$source_app/Contents/MacOS/RimeInputMethod" \
    --disable-input-source-id "$failed_bundle_id" >/dev/null 2>&1 || true

/bin/mkdir -p "$install_directory"
/usr/bin/pkill -x RimeInputMethod 2>/dev/null || true
"$lsregister" -u "$source_app" 2>/dev/null || true
"$lsregister" -u "$installed_app" 2>/dev/null || true
"$lsregister" -u "$failed_migration_app" 2>/dev/null || true

/bin/mv "$source_app" "$installing_app"
restore_previous_install() {
    trap - ERR
    if [[ -n "${previous_input_source:-}" && -x "${installed_binary:-}" ]]; then
        "$installed_binary" --select-input-source-id "$previous_input_source" >/dev/null 2>&1 || true
    fi
    "$lsregister" -u "$installed_app" 2>/dev/null || true
    /bin/mkdir -p "$(/usr/bin/dirname "$source_app")"
    if [[ -e "$installed_app" ]]; then
        /bin/mv "$installed_app" "$source_app"
    elif [[ -e "$installing_app" ]]; then
        /bin/mv "$installing_app" "$source_app"
    fi
    if [[ -e "$previous_app" ]]; then
        /bin/mv "$previous_app" "$installed_app"
        "$lsregister" -f "$installed_app" 2>/dev/null || true
    fi
    if [[ -e "$failed_migration_app" ]]; then
        "$lsregister" -f "$failed_migration_app" 2>/dev/null || true
    fi
}
trap restore_previous_install ERR

if [[ -e "$installed_app" ]]; then
    /bin/mv "$installed_app" "$previous_app"
fi
/bin/mv "$installing_app" "$installed_app"

installed_binary="$installed_app/Contents/MacOS/RimeInputMethod"
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
    echo "RimeInputMethod install failed: macOS did not expose parent input method $expected_bundle_id" >&2
    false
fi

"$installed_binary" --enable-input-method-parent

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
    echo "RimeInputMethod install failed: macOS did not expose input mode $input_mode_id" >&2
    false
fi

"$installed_binary" --enable-input-source
for _ in {1..60}; do
    input_source_status="$("$installed_binary" --input-source-status)"
    if [[ "$input_source_status" == *"enabled=true"* ]]; then
        break
    fi
    /bin/sleep 0.5
done
if [[ "$input_source_status" != *"enabled=true"* ]]; then
    echo "$input_source_status"
    echo "RimeInputMethod install failed: input mode did not become enabled" >&2
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

if [[ -n "$previous_input_source" \
    && "$previous_input_source" != "$input_mode_id" \
    && "$previous_input_source" != "$failed_input_mode_id" \
    && "$previous_input_source" != "$transitional_input_mode_id" ]]; then
    "$installed_binary" --select-input-source-id "$previous_input_source" >/dev/null || true
fi

if [[ -e "$failed_migration_app" ]]; then
    failed_migration_directory="$project_root/build/FailedMigration"
    failed_migration_backup="$failed_migration_directory/FengYuInputMethod-$build_version.app"
    /bin/mkdir -p "$failed_migration_directory"
    /bin/mv "$failed_migration_app" "$failed_migration_backup"
    echo "Preserved failed migration bundle at: $failed_migration_backup"
fi

if [[ -e "$previous_app" ]]; then
    /bin/rm -rf "$previous_app"
fi
trap - ERR

echo "$input_source_status"
echo "Installed and enabled without logout: $installed_app"
echo "Current input source: $("$installed_binary" --current-input-source)"
