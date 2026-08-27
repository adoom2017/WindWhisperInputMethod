#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_root/Scripts/lib/install-transaction.sh"
test_root="$(mktemp -d /private/tmp/windwhisper-M9-Test.XXXXXX)"

cleanup() {
    /bin/rm -rf "$test_root"
}
trap cleanup EXIT

source_app="$test_root/build/windwhisper.app"
installed_app="$test_root/Input Methods/windwhisper.app"
installing_app="$test_root/Input Methods/windwhisper.installing"
previous_app="$test_root/Input Methods/windwhisper.previous"
/bin/mkdir -p "$source_app" "$installed_app"
echo new > "$source_app/version"
echo old > "$installed_app/version"

windwhisper_begin_install_transaction \
    "$source_app" "$installed_app" "$installing_app" "$previous_app"
[[ "$(<"$installed_app/version")" == new && "$(<"$previous_app/version")" == old ]]
windwhisper_rollback_install_transaction \
    "$source_app" "$installed_app" "$installing_app" "$previous_app"
[[ "$(<"$source_app/version")" == new && "$(<"$installed_app/version")" == old ]]
echo "upgradeRollback=passed"

/bin/rm -rf "$installed_app"
windwhisper_begin_install_transaction \
    "$source_app" "$installed_app" "$installing_app" "$previous_app"
[[ "$(<"$installed_app/version")" == new && ! -e "$previous_app" ]]
windwhisper_rollback_install_transaction \
    "$source_app" "$installed_app" "$installing_app" "$previous_app"
[[ "$(<"$source_app/version")" == new && ! -e "$installed_app" ]]
echo "freshInstallRollback=passed"

/bin/mkdir -p "$installed_app"
echo old > "$installed_app/version"

/bin/mv "$source_app" "$installing_app"
WINDWHISPER_INSTALL_TRANSACTION_STATE="staged"
windwhisper_rollback_install_transaction \
    "$source_app" "$installed_app" "$installing_app" "$previous_app"
[[ "$(<"$source_app/version")" == new && "$(<"$installed_app/version")" == old ]]
echo "partialStagingRollback=passed"

/bin/mv "$source_app" "$installing_app"
/bin/mv "$installed_app" "$previous_app"
WINDWHISPER_INSTALL_TRANSACTION_STATE="previous"
windwhisper_rollback_install_transaction \
    "$source_app" "$installed_app" "$installing_app" "$previous_app"
[[ "$(<"$source_app/version")" == new && "$(<"$installed_app/version")" == old ]]
echo "partialSwapRollback=passed"

if windwhisper_begin_install_transaction \
    "$source_app" "$installed_app" "$installed_app" "$previous_app"; then
    echo "Path collision was unexpectedly accepted." >&2
    exit 1
fi
[[ "$(<"$source_app/version")" == new && "$(<"$installed_app/version")" == old ]]
echo "pathValidation=passed"

windwhisper_begin_install_transaction \
    "$source_app" "$installed_app" "$installing_app" "$previous_app"
windwhisper_commit_install_transaction "$previous_app"
[[ "$(<"$installed_app/version")" == new && ! -e "$previous_app" ]]
echo "upgradeCommit=passed"

if [[ "${WINDWHISPER_SKIP_PACKAGE:-0}" != "1" ]]; then
    "$project_root/Scripts/package-release.sh" local 0.1.0 9000001
    "$project_root/Scripts/verify-release.sh" \
        "$project_root/dist/windwhisper-0.1.0-9000001-macos-universal.zip" local
    echo "localReleaseCandidate=passed"
fi
