#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-Release}"
stress_seconds="${2:-30}"
application_path="$project_root/build/DerivedData/Build/Products/$configuration/windwhisper.app"
test_root="$(mktemp -d /private/tmp/windwhisper-M8-Test.XXXXXX)"

cleanup() {
    rm -rf "$test_root"
}
trap cleanup EXIT

case "$stress_seconds" in
    *[!0-9]*|'')
        echo "Stress duration must be a positive integer number of seconds." >&2
        exit 64
        ;;
esac
if (( stress_seconds < 1 )); then
    echo "Stress duration must be at least one second." >&2
    exit 64
fi

"$project_root/Scripts/build.sh" "$configuration"
"$project_root/Scripts/verify-runtime.sh" "$application_path"
"$application_path/Contents/MacOS/windwhisper" \
    --m8-smoke \
    --user-data-root "$test_root" \
    --stress-seconds "$stress_seconds"
