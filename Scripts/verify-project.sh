#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
info_plist="$project_root/Resources/Info.plist"
expected_bundle_id="com.shendongchun.inputmethod.rime.dev"
expected_mode_id="$expected_bundle_id.Hans"
expected_display_name="风语"

plutil -lint "$info_plist"

display_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist")"
bundle_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$info_plist")"
if [[ "$display_name" != "$expected_display_name" || "$bundle_name" != "$expected_display_name" ]]; then
    echo "Product display name must be $expected_display_name." >&2
    exit 65
fi

plist_mode_id="$(/usr/libexec/PlistBuddy -c 'Print :ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0' "$info_plist")"
if [[ "$plist_mode_id" != "$expected_mode_id" ]]; then
    echo "Input mode ID mismatch: $plist_mode_id" >&2
    exit 65
fi

if ! grep -q "PRODUCT_BUNDLE_IDENTIFIER = $expected_bundle_id;" "$project_root/RimeInputMethod.xcodeproj/project.pbxproj"; then
    echo "Project bundle ID does not match Info.plist input mode namespace." >&2
    exit 65
fi

menu_icon="$(/usr/libexec/PlistBuddy -c "Print :ComponentInputModeDict:tsInputModeListKey:$expected_mode_id:tsInputModeMenuIconFileKey" "$info_plist")"
if [[ "$menu_icon" != "FengYuInputModeIcon.pdf" ]]; then
    echo "Input mode menu icon must use the FengYu original artwork." >&2
    exit 65
fi

alternate_icon="$(/usr/libexec/PlistBuddy -c "Print :ComponentInputModeDict:tsInputModeListKey:$expected_mode_id:tsInputModeAlternateMenuIconFileKey" "$info_plist")"
palette_icon="$(/usr/libexec/PlistBuddy -c "Print :ComponentInputModeDict:tsInputModeListKey:$expected_mode_id:tsInputModePaletteIconFileKey" "$info_plist")"
if [[ "$alternate_icon" != "FengYuInputSwitcherIcon-v1.pdf" || "$palette_icon" != "FengYuInputSwitcherIcon-v1.pdf" ]]; then
    echo "Input switcher must use its versioned FengYu icon resource." >&2
    exit 65
fi

for brand_file in \
    "$project_root/Resources/Assets/FengYuIconMaster.png" \
	"$project_root/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" \
	"$project_root/Resources/FengYuInputModeIcon.pdf" \
	"$project_root/Resources/FengYuInputSwitcherIcon-v1.pdf"; do
    if [[ ! -f "$brand_file" ]]; then
        echo "Required FengYu brand asset is missing: $brand_file" >&2
        exit 66
    fi
done

for localization in zh_CN zh-Hans en; do
    localization_file="$project_root/Resources/$localization.lproj/InfoPlist.strings"
    localized_mode_name="$(/usr/libexec/PlistBuddy -c "Print :$expected_mode_id" "$localization_file")"
    if [[ "$localized_mode_name" != "$expected_display_name" ]]; then
        echo "Input mode name is not localized as $expected_display_name in $localization." >&2
        exit 65
    fi
done

if grep -Eq 'Rime\.icns|Resources/InputModeIcon\.pdf' \
    "$info_plist" "$project_root/RimeInputMethod.xcodeproj/project.pbxproj"; then
    echo "Legacy Rime icon reference is still present." >&2
    exit 65
fi

library="$project_root/Vendor/librime/lib/librime.1.dylib"
expected_library_sha256="922aad7de56473dd13e25836b0eecfa3698e07506154f418cf27e1f5e268e8b3"
if [[ ! -f "$library" ]]; then
    echo "Pinned librime runtime is missing; run Scripts/fetch-librime.sh." >&2
    exit 66
fi

actual_library_sha256="$(shasum -a 256 "$library" | awk '{print $1}')"
if [[ "$actual_library_sha256" != "$expected_library_sha256" ]]; then
    echo "Pinned librime runtime checksum mismatch." >&2
    exit 65
fi

architectures="$(lipo -archs "$library")"
if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
    echo "Pinned librime runtime must contain arm64 and x86_64." >&2
    exit 65
fi

if otool -L "$library" | grep -Eq '/opt/homebrew|/usr/local/(Cellar|opt)'; then
    echo "Pinned librime runtime contains a package-manager dependency." >&2
    exit 65
fi

for required_file in \
    "$project_root/Vendor/librime/LOCK.json" \
    "$project_root/Vendor/librime/include/rime_api.h" \
    "$project_root/Resources/Rime/default.yaml" \
    "$project_root/Resources/Rime/luna_pinyin.schema.yaml" \
    "$project_root/Resources/Rime/luna_pinyin.dict.yaml" \
    "$project_root/Resources/Rime/flypy.schema.yaml" \
    "$project_root/Resources/Rime/flypy.dict.yaml" \
    "$project_root/Resources/Rime/flypydz.dict.yaml" \
    "$project_root/Scripts/generate-flypy-dictionary.swift" \
    "$project_root/LICENSES/librime-BSD-3-Clause.txt"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Required M2 dependency file is missing: $required_file" >&2
        exit 66
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
    "$project_root/Resources/Rime/opencc/t2s.json" \
    "b818534194f27c2d95f01001edb0a5ec49b9050119892cb30a0504bb202cc07c"
verify_sha256 \
    "$project_root/Resources/Rime/opencc/TSCharacters.ocd2" \
    "85291e0173e972bbca58c848fb90b3bb41c79674cb61a75645e01bd884ad5927"
verify_sha256 \
    "$project_root/Resources/Rime/opencc/TSPhrases.ocd2" \
    "edafc46f5c3eca61a754c78e47117e7c73995cacd6c99aadcb8a219d7ae3e53d"
verify_sha256 \
    "$project_root/LICENSES/OpenCC-Apache-2.0.txt" \
    "b534e465949558eec2597b04f5092b5e161236a68dfbfd04d547592ac3964308"

echo "Project metadata verified."
