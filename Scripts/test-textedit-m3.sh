#!/bin/bash

set -euo pipefail

installed_binary="$HOME/Library/Input Methods/RimeInputMethod.app/Contents/MacOS/RimeInputMethod"
expected_text="你好"
previous_input_source=""

restore_input_source() {
    local exit_code=$?
    trap - EXIT
    if [[ -n "$previous_input_source" && -x "$installed_binary" ]]; then
        "$installed_binary" --select-input-source-id "$previous_input_source" >/dev/null 2>&1 || true
    fi
    exit "$exit_code"
}
trap restore_input_source EXIT

if [[ ! -x "$installed_binary" ]]; then
    echo "Installed RimeInputMethod binary is missing." >&2
    exit 1
fi

previous_input_source="$("$installed_binary" --current-input-source)"
"$installed_binary" --select-input-source >/dev/null

actual_text="$(/usr/bin/osascript <<'APPLESCRIPT'
tell application "TextEdit"
    activate
    set testDocument to make new document
end tell

try
    delay 0.8
    tell application "System Events"
        tell process "TextEdit"
            keystroke "n"
            keystroke "i"
            key code 51
            key code 53
            keystroke "nihao"
            key code 49
        end tell
    end tell
    delay 0.8
    tell application "TextEdit"
        set resultText to text of testDocument
        close testDocument saving no
    end tell
    return resultText
on error errorMessage number errorNumber
    tell application "TextEdit"
        try
            close testDocument saving no
        end try
    end tell
    error errorMessage number errorNumber
end try
APPLESCRIPT
)"

if [[ "$actual_text" != "$expected_text" ]]; then
    echo "textEditCommitMatched=false" >&2
    echo "textEditUTF8Length=$(/usr/bin/printf '%s' "$actual_text" | /usr/bin/wc -c | /usr/bin/tr -d ' ')" >&2
    exit 1
fi

echo "textEditCommitMatched=true"
