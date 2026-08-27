#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
info_plist="$project_root/Resources/Info.plist"
expected_bundle_id="com.shendongchun.inputmethod.windwhisper.local"
expected_mode_id="$expected_bundle_id.Hans"
legacy_mode_id="com.shendongchun.inputmethod.rime.dev.Hans"
older_mode_id="com.shendongchun.inputmethod.fengyu.Hans"
transitional_mode_id="com.shendongchun.inputmethod.rime.dev.FengYuHans"
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

if grep -Eq "$legacy_mode_id|$older_mode_id|$transitional_mode_id" "$info_plist"; then
    echo "Legacy input mode IDs must not remain in Info.plist." >&2
    exit 65
fi

if ! grep -q "PRODUCT_BUNDLE_IDENTIFIER = $expected_bundle_id;" "$project_root/WindWhisperInputMethod.xcodeproj/project.pbxproj"; then
    echo "Project bundle ID does not match Info.plist input mode namespace." >&2
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

if grep -Eq 'Rime\.icns|Resources/InputModeIcon\.pdf' \
    "$info_plist" "$project_root/WindWhisperInputMethod.xcodeproj/project.pbxproj"; then
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
    "$project_root/Sources/RimeBridge/M8SmokeTest.swift" \
    "$project_root/Scripts/test-m8.sh" \
    "$project_root/Scripts/test-m9.sh" \
    "$project_root/Scripts/package-release.sh" \
    "$project_root/Scripts/verify-release.sh" \
    "$project_root/Scripts/lib/install-transaction.sh" \
    "$project_root/docs/M8_VALIDATION.md" \
    "$project_root/docs/M9_VALIDATION.md" \
    "$project_root/docs/RELEASE_INSTALL.md" \
    "$project_root/docs/RELEASE_NOTES.md" \
    "$project_root/docs/KNOWN_ISSUES.md" \
    "$project_root/LICENSES/librime-BSD-3-Clause.txt" \
    "$project_root/LICENSES/rime-data-LGPL-3.0.txt"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Required M2 dependency file is missing: $required_file" >&2
        exit 66
    fi
done

if ! grep -q 'M8SmokeTest.swift in Sources' \
    "$project_root/WindWhisperInputMethod.xcodeproj/project.pbxproj"; then
    echo "M8 smoke test is not included in the application target." >&2
    exit 65
fi

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
verify_sha256 \
    "$project_root/Resources/Rime/flypy.dict.yaml" \
    "ea284029473466e10ee752748626f19c579da3d3a868250d61f3b457bacfa5d6"
verify_sha256 \
    "$project_root/Resources/Rime/flypy.schema.yaml" \
    "6f5d341405cf46df29feb7ce287231185abe5f7e76de61dc97172e6ecc2050aa"

for removed_prebuilt in \
    "$project_root/Resources/Rime/build/flypy.table.bin" \
    "$project_root/Resources/Rime/build/flypy.prism.bin" \
    "$project_root/Resources/Rime/build/flypy.reverse.bin"; do
    if [[ -e "$removed_prebuilt" ]]; then
        echo "Flypy prebuilt data must be generated at deployment time: $removed_prebuilt" >&2
        exit 65
    fi
done

echo "Project metadata verified."
