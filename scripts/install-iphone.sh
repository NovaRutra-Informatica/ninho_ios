#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_xcode
if [[ -z "${NINHO_DEVICE_ID:-}" ]]; then
  echo 'Defina NINHO_DEVICE_ID, obtido com xcrun devicectl list devices.' >&2
  exit 2
fi
if [[ $# -ne 1 || ! -d "$1" || "$1" != *.app ]]; then
  echo 'Uso: bash scripts/install-iphone.sh /caminho/assinado/Ninho.app' >&2
  exit 2
fi
APP_PATH="$(cd "$1" && pwd)"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_PATH/Info.plist")" != com.aless.ninho.ios ]]; then
  echo 'O pacote informado não é o aplicativo Ninho para iPhone.' >&2
  exit 2
fi
codesign --verify --deep --strict "$APP_PATH"
xcrun devicectl device install app --device "$NINHO_DEVICE_ID" "$APP_PATH"
xcrun devicectl device process launch --device "$NINHO_DEVICE_ID" com.aless.ninho.ios
