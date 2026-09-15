#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_xcode
# Separate macOS and Linux build caches.
swift test --package-path "$IOS_ROOT" --scratch-path "$IOS_ROOT/.build/macos"
SIMULATOR_ID="$(simulator_id)"
if ! xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null; then
  # bootstatus below verifies that boot succeeded.
  true
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild -project "$PROJECT" -scheme Ninho -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 \
  -derivedDataPath "$DERIVED_DATA" -resultBundlePath "$(result_path tests)" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
