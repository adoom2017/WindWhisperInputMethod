#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-Debug}"
application_path="$project_root/build/DerivedData/Build/Products/$configuration/RimeInputMethod.app"

"$project_root/Scripts/build.sh" "$configuration"
"$project_root/Scripts/verify-runtime.sh" "$application_path"
"$application_path/Contents/MacOS/RimeInputMethod" --m4-smoke
