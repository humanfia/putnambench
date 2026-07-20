#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="${1:-$PROJECT_ROOT/comparator.json}"

COMPARATOR_BIN="${COMPARATOR_BIN:-/comparator-tools/comparator}"
LEAN4EXPORT_BIN="${LEAN4EXPORT_BIN:-/comparator-tools/lean4export}"
LANDRUN_BIN="${LANDRUN_BIN:-/comparator-tools/landrun}"

for executable in "$COMPARATOR_BIN" "$LEAN4EXPORT_BIN" "$LANDRUN_BIN"; do
  if [[ ! -x "$executable" ]]; then
    printf 'Comparator self-check tool is missing or not executable: %s\n' \
      "$executable" >&2
    exit 2
  fi
done
[[ -f "$CONFIG_PATH" ]] || {
  printf 'Comparator configuration not found: %s\n' "$CONFIG_PATH" >&2
  exit 2
}

cd "$PROJECT_ROOT"
LEAN_PREFIX="$(lean --print-prefix)"
export PATH="$LEAN_PREFIX/bin:$PATH"
export COMPARATOR_LANDRUN="$LANDRUN_BIN"
export COMPARATOR_LEAN4EXPORT="$LEAN4EXPORT_BIN"

exec lake env "$COMPARATOR_BIN" "$CONFIG_PATH"
