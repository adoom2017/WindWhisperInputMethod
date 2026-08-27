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
"$application_path/Contents/MacOS/windwhisper" \
    --engine-smoke \
    --user-data-root "$test_root"
