#!/bin/bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$project_root"
device="${1:-booted}"
test_root="$(mktemp -d /tmp/windwhisper-candidates.XXXXXX)"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
sources=(iOS/Keyboard/FengYuSchema.swift Core/SwiftAdapter/InputEnginePlatform.swift
    Core/SwiftAdapter/InputModels.swift Core/SwiftAdapter/InputService.swift)

./Scripts/generate-ios-dictionary.sh
for test in candidates custom-phrases; do
    test_sources=("${sources[@]}")
    if [[ "$test" == custom-phrases ]]; then
        test_sources+=(Platform/macOS/Configuration/CustomWords.swift)
    fi
    xcrun --sdk iphonesimulator swiftc -O -target "$arch-apple-ios17.0-simulator" \
        -sdk "$sdk" -module-cache-path "$test_root/modules" \
        "${test_sources[@]}" "Scripts/ios-$test-smoke.swift" \
        -o "$test_root/$test"
    xcrun simctl spawn "$device" "$test_root/$test" "$project_root/iOS/Resources/fy.dict.yaml"
done

xcodegen generate --spec Scripts/CandidateSmoke/project.yml
xcodebuild -quiet -project Scripts/CandidateSmoke/CandidateSmoke.xcodeproj \
    -scheme CandidateSmoke -configuration Release -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$test_root/build" \
    build CODE_SIGNING_ALLOWED=NO
app="$test_root/build/Build/Products/Release-iphonesimulator/CandidateSmoke.app"
bundle_id=com.shendongchun.windwhisper.candidate-smoke
xcrun simctl install "$device" "$app"
xcrun simctl launch --console "$device" "$bundle_id"
container="$(xcrun simctl get_app_container "$device" "$bundle_id" data)"
grep '^PASS collection:' "$container/tmp/candidate-ui-result.txt"
printf 'Screenshot: %s/tmp/candidate-stress.png\nBuild artifacts: %s\n' "$container" "$test_root"
