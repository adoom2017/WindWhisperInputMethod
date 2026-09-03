#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
info_plist="$project_root/Resources/Info.plist"
expected_bundle_id="com.shendongchun.inputmethod.windwhisper"
expected_mode_id="$expected_bundle_id.Hans"
expected_display_name="windwhisper"

plutil -lint "$info_plist"

display_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist")"
bundle_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$info_plist")"
if [[ "$display_name" != "$expected_display_name" || "$bundle_name" != "$expected_display_name" ]]; then
    echo "Product display name must be $expected_display_name." >&2
    exit 65
fi

if /usr/libexec/PlistBuddy -c 'Print :TICapsLockLanguageSwitchCapable' "$info_plist" >/dev/null 2>&1; then
    echo "Caps Lock language switching must not be advertised; the input engine owns modifier behavior." >&2
    exit 65
fi

plist_mode_id="$(/usr/libexec/PlistBuddy -c 'Print :ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0' "$info_plist")"
if [[ "$plist_mode_id" != "$expected_mode_id" ]]; then
    echo "Input mode ID mismatch: $plist_mode_id" >&2
    exit 65
fi

if ! grep -q "PRODUCT_BUNDLE_IDENTIFIER = $expected_bundle_id;" "$project_root/WindWhisperInputMethod.xcodeproj/project.pbxproj"; then
    echo "Project bundle ID does not match Info.plist input mode namespace." >&2
    exit 65
fi

project_file="$project_root/WindWhisperInputMethod.xcodeproj/project.pbxproj"
for required_signing_setting in \
    'CODE_SIGN_IDENTITY = "Apple Development";' \
    'CODE_SIGN_IDENTITY = "Developer ID Application";' \
    'DEVELOPMENT_TEAM = YH6JCRN97J;' \
    'CODE_SIGN_ENTITLEMENTS = Resources/AppStore.entitlements;'; do
    if ! grep -qF "$required_signing_setting" "$project_file"; then
        echo "Required signing setting is missing: $required_signing_setting" >&2
        exit 65
    fi
done

app_store_entitlements="$project_root/Resources/AppStore.entitlements"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$app_store_entitlements")" != true ]]; then
    echo "Mac App Store configuration must enable App Sandbox." >&2
    exit 65
fi

menu_icon="$(/usr/libexec/PlistBuddy -c "Print :ComponentInputModeDict:tsInputModeListKey:$expected_mode_id:tsInputModeMenuIconFileKey" "$info_plist")"
alternate_icon="$(/usr/libexec/PlistBuddy -c "Print :ComponentInputModeDict:tsInputModeListKey:$expected_mode_id:tsInputModeAlternateMenuIconFileKey" "$info_plist")"
palette_icon="$(/usr/libexec/PlistBuddy -c "Print :ComponentInputModeDict:tsInputModeListKey:$expected_mode_id:tsInputModePaletteIconFileKey" "$info_plist")"
stable_input_source_icon="WindWhisperInputIcon-v1.pdf"
if [[ "$menu_icon" != "$stable_input_source_icon" \
    || "$alternate_icon" != "$stable_input_source_icon" \
    || "$palette_icon" != "$stable_input_source_icon" ]]; then
    echo "All input-source icon fields must use one stable windwhisper resource." >&2
    exit 65
fi

for brand_file in \
    "$project_root/Resources/Assets/WindWhisperIconMaster.png" \
	"$project_root/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" \
    "$project_root/Resources/WindWhisperInputIcon-v1.pdf"; do
    if [[ ! -f "$brand_file" ]]; then
        echo "Required windwhisper brand asset is missing: $brand_file" >&2
        exit 66
    fi
done

for localization in zh_CN zh-Hans; do
    localization_file="$project_root/Resources/$localization.lproj/InfoPlist.strings"
    localized_mode_name="$(/usr/libexec/PlistBuddy -c "Print :$expected_mode_id" "$localization_file")"
    if [[ "$localized_mode_name" != "风语" ]]; then
        echo "Input mode name is not localized as 风语 in $localization." >&2
        exit 65
    fi
done

english_localization="$project_root/Resources/en.lproj/InfoPlist.strings"
english_mode_name="$(/usr/libexec/PlistBuddy -c "Print :$expected_mode_id" "$english_localization")"
if [[ "$english_mode_name" != "$expected_display_name" ]]; then
    echo "English input mode name must be $expected_display_name." >&2
    exit 65
fi

for required_file in \
    "$project_root/Resources/fy.dict.yaml" \
    "$project_root/Core/SwiftAdapter/InputService.swift" \
    "$project_root/Platform/macOS/InputMethod/EngineSmokeTest.swift" \
    "$project_root/Installer/macOS/Scripts/preinstall" \
    "$project_root/Installer/macOS/Scripts/postinstall" \
    "$project_root/Scripts/create-pkg.sh" \
    "$project_root/Scripts/verify-pkg.sh"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Required M2 dependency file is missing: $required_file" >&2
        exit 66
    fi
done

for installer_script in \
    "$project_root/Installer/macOS/Scripts/preinstall" \
    "$project_root/Installer/macOS/Scripts/postinstall"; do
    if [[ ! -x "$installer_script" ]]; then
        echo "Installer script must be executable: $installer_script" >&2
        exit 65
    fi
done

verify_sha256() {
    local file="$1"
    local expected="$2"
    if [[ ! -f "$file" ]]; then
        echo "Required locked data file is missing: $file" >&2
        exit 66
    fi
    local actual
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "Locked data checksum mismatch: $file" >&2
        exit 65
    fi
}

verify_sha256 \
    "$project_root/Resources/fy.dict.yaml" \
    "9166aa5dcc76560110485d1cece4fd04692aab37969c78fd7dc9633b5d043c02"

echo "Project metadata verified."
