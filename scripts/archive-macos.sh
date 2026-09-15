#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_xcode
signing_arguments
ARCHIVE="${NINHO_ARCHIVE_PATH:-$IOS_ROOT/build/Ninho-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcarchive}"
if [[ -e "$ARCHIVE" ]]; then
  echo "O arquivo de destino já existe; escolha outro NINHO_ARCHIVE_PATH." >&2
  exit 2
fi
mkdir -p "$(dirname "$ARCHIVE")"
xcodebuild -project "$PROJECT" -scheme Ninho -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE" -resultBundlePath "$(result_path archive)" \
  "${SIGNING_ARGS[@]}" archive
printf 'Arquivo assinado: %s\n' "$ARCHIVE"
