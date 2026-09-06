#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(dirname -- "$SCRIPT_DIR")
SOURCE_DICTIONARY="$PROJECT_ROOT/Resources/fy.dict.yaml"
OUTPUT_DIRECTORY="$PROJECT_ROOT/iOS/Resources"
OUTPUT_DICTIONARY="$OUTPUT_DIRECTORY/fy.dict.yaml"
TEMP_DICTIONARY="$OUTPUT_DICTIONARY.tmp"

mkdir -p "$OUTPUT_DIRECTORY"

LC_ALL=C awk -F '\t' '
    NF < 5 { print; next }
    $4 == "pinyin" { print; next }
    $4 == "flypy" && length($2) <= 4 { print; next }
    $4 == "essay" && ($3 + 0) >= 500 { print; next }
' "$SOURCE_DICTIONARY" > "$TEMP_DICTIONARY"

mv "$TEMP_DICTIONARY" "$OUTPUT_DICTIONARY"

source_lines=$(wc -l < "$SOURCE_DICTIONARY" | tr -d ' ')
output_lines=$(wc -l < "$OUTPUT_DICTIONARY" | tr -d ' ')
source_bytes=$(wc -c < "$SOURCE_DICTIONARY" | tr -d ' ')
output_bytes=$(wc -c < "$OUTPUT_DICTIONARY" | tr -d ' ')

printf 'Generated %s\n' "$OUTPUT_DICTIONARY"
printf 'Lines: %s -> %s; bytes: %s -> %s\n' \
    "$source_lines" "$output_lines" "$source_bytes" "$output_bytes"
