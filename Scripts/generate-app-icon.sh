#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_image="${1:-$project_root/Resources/Assets/FengYuIconMaster.png}"
output_iconset="${2:-$project_root/Resources/Assets.xcassets/AppIcon.appiconset}"

if [[ ! -f "$source_image" ]]; then
    echo "FengYu icon master is missing: $source_image" >&2
    exit 66
fi

mkdir -p "$output_iconset"
for size in 16 32 128 256 512; do
    double_size=$((size * 2))
    /usr/bin/sips -z "$size" "$size" "$source_image" \
        --out "$output_iconset/icon_${size}x${size}.png" >/dev/null
    /usr/bin/sips -z "$double_size" "$double_size" "$source_image" \
        --out "$output_iconset/icon_${size}x${size}@2x.png" >/dev/null
done

echo "$output_iconset"
