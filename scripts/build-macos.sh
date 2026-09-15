#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_xcode
xcodebuild -project "$PROJECT" -scheme Ninho -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$(result_path build)" CODE_SIGNING_ALLOWED=NO build
