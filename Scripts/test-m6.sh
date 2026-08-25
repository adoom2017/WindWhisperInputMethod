#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-Debug}"
application_path="$project_root/build/DerivedData/Build/Products/$configuration/RimeInputMethod.app"
test_root="$(mktemp -d /private/tmp/RimeInputMethod-M6-Test.XXXXXX)"

cleanup() {
    rm -rf "$test_root"
}
trap cleanup EXIT

"$project_root/Scripts/build.sh" "$configuration"
"$project_root/Scripts/verify-runtime.sh" "$application_path"
"$project_root/Scripts/generate-aux-dictionary.swift" \
    "$project_root/Resources/Rime/luna_pinyin.dict.yaml" \
    "$project_root/Resources/Rime/cangjie5.dict.yaml" \
    "$test_root/fengyu_aux.dict.yaml"
cmp "$test_root/fengyu_aux.dict.yaml" "$project_root/Resources/Rime/fengyu_aux.dict.yaml"
echo "auxiliaryDictionaryReproducible=passed"
"$project_root/Scripts/generate-flypy-dictionary.swift" \
    "$project_root/Resources/Rime/flypydz.dict.yaml" \
    "$test_root/flypy.dict.yaml" \
    "$project_root/Resources/Rime/flypy_top.txt" \
    "$project_root/Resources/Rime/flypy_sys.txt" \
    "$project_root/Resources/Rime/flypy_user.txt" \
    "$project_root/Resources/Rime/flypy_full.txt"
cmp "$test_root/flypy.dict.yaml" "$project_root/Resources/Rime/flypy.dict.yaml"
echo "flypyDictionaryReproducible=passed"
"$application_path/Contents/MacOS/RimeInputMethod" \
    --m6-smoke \
    --user-data-root "$test_root"
