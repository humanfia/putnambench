#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUMANIZE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MATH_FLOW_BENCH_ROOT="${MATH_FLOW_BENCH_ROOT:-$HUMANIZE_ROOT/../math-flow-bench}"
RUNNER="$MATH_FLOW_BENCH_ROOT/scripts/run-humanize-putnambench.sh"

if [[ ! -f "$RUNNER" ]]; then
  printf 'humanize-axle-comparator-review: runner not found: %s\n' "$RUNNER" >&2
  exit 2
fi

exec bash "$RUNNER" \
  --humanize-root "$HUMANIZE_ROOT" \
  --skip-humanize-install \
  "$@"
