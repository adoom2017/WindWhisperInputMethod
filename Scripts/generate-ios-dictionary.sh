#!/bin/bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(dirname -- "$script_dir")"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/windwhisper-dictionary.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

xcrun swift -module-cache-path "$work_dir/modules" "$script_dir/generate-ios-dictionary.swift" \
    "$project_root/iOS/Resources/allowed_characters.txt" \
    "$project_root/Resources/fy.dict.yaml" \
    "$work_dir/fy.dict.yaml"
mv "$work_dir/fy.dict.yaml" "$project_root/iOS/Resources/fy.dict.yaml"
printf 'Generated %s\n' "$project_root/iOS/Resources/fy.dict.yaml"
