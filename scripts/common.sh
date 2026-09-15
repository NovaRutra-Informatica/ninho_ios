#!/bin/bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$IOS_ROOT/Ninho.xcodeproj"
DERIVED_DATA="${NINHO_DERIVED_DATA:-$IOS_ROOT/DerivedData}"
RESULTS="$IOS_ROOT/TestResults"

require_xcode() {
  if [[ "$(uname -s)" != Darwin ]]; then
    echo "Este comando exige macOS com Xcode 26 ou posterior. Nada foi compilado para iOS." >&2
    exit 2
  fi
  command -v python3 >/dev/null
  command -v xcodebuild >/dev/null
  local version
  version="$(xcodebuild -version | awk '/^Xcode / {print $2; exit}')"
  if [[ -z "$version" || "${version%%.*}" -lt 26 ]]; then
    echo "Selecione Xcode 26+ com xcode-select. Versão atual: ${version:-indisponível}." >&2
    exit 2
  fi
  python3 "$IOS_ROOT/scripts/generate_project.py" --check
  plutil -lint "$PROJECT/project.pbxproj"
  mkdir -p "$RESULTS"
}

simulator_id() {
  python3 "$IOS_ROOT/scripts/select_simulator.py"
}

result_path() {
  printf '%s/%s-%s-%s.xcresult' "$RESULTS" "$1" "$(date -u +%Y%m%dT%H%M%SZ)" "$$"
}

signing_arguments() {
  if [[ ! "${NINHO_DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Defina NINHO_DEVELOPMENT_TEAM com o Team ID de 10 caracteres da sua conta Apple." >&2
    exit 2
  fi
  SIGNING_ARGS=("DEVELOPMENT_TEAM=$NINHO_DEVELOPMENT_TEAM" "CODE_SIGN_STYLE=Automatic")
  if [[ "${NINHO_ALLOW_PROVISIONING_UPDATES:-0}" == 1 ]]; then
    SIGNING_ARGS+=(-allowProvisioningUpdates)
  fi
}
