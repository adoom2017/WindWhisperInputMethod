#!/bin/bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(dirname -- "$script_dir")"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/windwhisper-predictions.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

source_url="https://github.com/rime/librime-predict/releases/download/data-1.0/predict.txt"
source_sha256="df0f7a9ef96569da402d9ea2376aefad4d15382ebcccb05ec84a0acbc00c7f83"
curl -fsSL --retry 3 -o "$work_dir/predict.txt" "$source_url"
echo "$source_sha256  $work_dir/predict.txt" | shasum -a 256 -c --quiet

xcrun swift -module-cache-path "$work_dir/modules" "$script_dir/generate-ios-predictions.swift" \
    "$project_root/iOS/Resources/fy.dict.yaml" \
    "$work_dir/predict.txt" \
    "$work_dir/predict.txt.out"
mv "$work_dir/predict.txt.out" "$project_root/iOS/Resources/predict.txt"
printf 'Generated %s\n' "$project_root/iOS/Resources/predict.txt"
