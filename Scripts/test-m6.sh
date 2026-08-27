#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-Debug}"
application_path="$project_root/build/DerivedData/Build/Products/$configuration/windwhisper.app"
test_root="$(mktemp -d /private/tmp/windwhisper-M6-Test.XXXXXX)"

cleanup() {
    rm -rf "$test_root"
}
trap cleanup EXIT

"$project_root/Scripts/build.sh" "$configuration"
"$project_root/Scripts/verify-runtime.sh" "$application_path"
/usr/bin/env \
    CLANG_MODULE_CACHE_PATH="$test_root/ModuleCache" \
    SWIFT_MODULECACHE_PATH="$test_root/ModuleCache" \
    "$project_root/Scripts/generate-aux-dictionary.swift" \
    "$project_root/Resources/Rime/luna_pinyin.dict.yaml" \
    "$project_root/Resources/Rime/cangjie5.dict.yaml" \
    "$test_root/fengyu_aux.dict.yaml"
cmp "$test_root/fengyu_aux.dict.yaml" "$project_root/Resources/Rime/fengyu_aux.dict.yaml"
echo "auxiliaryDictionaryReproducible=passed"
echo "flypyRecoveredDictionary=locked"
"$application_path/Contents/MacOS/windwhisper" \
    --m6-smoke \
    --user-data-root "$test_root"
