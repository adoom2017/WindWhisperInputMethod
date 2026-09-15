#!/bin/bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$project_root"
test_root="$(mktemp -d /tmp/windwhisper-frequency.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT
sources=(iOS/Keyboard/FengYuSchema.swift Core/SwiftAdapter/InputEnginePlatform.swift
    Core/SwiftAdapter/InputModels.swift Core/SwiftAdapter/InputService.swift
    Scripts/user-frequency-smoke.swift)
case "${1:-macos}" in
    macos)
        xcrun swiftc -O -module-cache-path "$test_root/modules" "${sources[@]}" -o "$test_root/smoke"
        "$test_root/smoke"
        ;;
    ios)
        sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
        xcrun --sdk iphonesimulator swiftc -O -target "$(uname -m)-apple-ios17.0-simulator" \
            -sdk "$sdk" -module-cache-path "$test_root/modules" "${sources[@]}" -o "$test_root/smoke"
        xcrun simctl spawn "${2:-booted}" "$test_root/smoke"
        ;;
    *) echo "Usage: $0 [macos|ios [device]]" >&2; exit 64 ;;
esac
