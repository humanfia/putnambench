#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUMANIZE_ROOT="$ROOT/humanize"
INPUT_ROOT="$ROOT/inputs"
MATH_TEMPLATE="$INPUT_ROOT/math-flow-bench"
WORK_ROOT="$ROOT/work"
MATH_ROOT="$WORK_ROOT/math-flow-bench"
TOOLS_ROOT="$WORK_ROOT/comparator-tools"

COMPARATOR_REPO="https://github.com/leanprover/comparator.git"
COMPARATOR_COMMIT="099775bf2e6073fcb22aacd3a2809fdeac3fc84a"
LEAN4EXPORT_REPO="https://github.com/leanprover/lean4export.git"
LEAN4EXPORT_COMMIT="590dec59d93ab6becdf16fdd8aee5abbb99cb856"
LANDRUN_REPO="https://github.com/Zouuup/landrun.git"
LANDRUN_COMMIT="5ed4a3db3a4ad930d577215c6b9abaa19df7f99f"

EXPECTED_FAILURE_SHA="67a97f0927b5ce8331077c53b68a9d71f388aaf4b176c568f40be2a5c11d47a7"
EXPECTED_JSONL_SHA="2b3a9c40a41b303e9bc7f60f69e3a457c7ee1e45e3e0c240a05a0054970de455"
EXPECTED_MANIFEST_SHA="42127580b8f3b85ec90f285ce137e6c715031f58d1d9f83412985af7857faf81"

MODE="${1:-check}"
if [[ $# -gt 0 ]]; then
  shift
fi

JOBS="${REPRO_JOBS:-64}"
FALLBACK_JOBS="${REPRO_FALLBACK_JOBS:-16}"
PROBE_COUNT="${REPRO_PROBE_COUNT:-4}"
MAX_TURNS="${REPRO_MAX_TURNS:-50}"
WORKER_TIMEOUT="${REPRO_WORKER_TIMEOUT:-7200}"
REVIEW_TIMEOUT="${REPRO_REVIEW_TIMEOUT:-7200}"
RUN_ID="${REPRO_RUN_ID:-humanize-98-$(date -u +%Y%m%dT%H%M%SZ)}"
BASE_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
OUT_ROOT="$ROOT/runs"
SKIP_BOOTSTRAP=0
RUNNER_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  ./reproduce.sh check
  ./reproduce.sh bootstrap
  ./reproduce.sh prepare [options]
  ./reproduce.sh run [options]

Modes:
  check       Verify package hashes, the 98-problem selection, and source syntax.
              This is the default and performs no network or model calls.
  bootstrap   Build the pinned Lean and Comparator environment under work/.
  prepare     Bootstrap, then create and audit all sanitized workspaces without
              making model calls.
  run         Bootstrap and launch the complete Humanize worker/reviewer run.

Options for prepare/run:
  --jobs N                    Main concurrency. Historical value: 64.
  --fallback-jobs N           Concurrency after rate limits. Historical value: 16.
  --probe-count N             One-turn probe jobs. Historical value: 4.
  --max-turns N               Turns per problem. Historical value: 50.
  --worker-timeout N          Seconds per worker call. Historical value: 7200.
  --review-timeout N          Seconds per reviewer call. Historical value: 7200.
  --run-id ID                 Output run identifier.
  --base-codex-home PATH      Directory containing auth.json and config.toml.
  --out-root PATH             Output parent. Default: ./runs.
  --skip-bootstrap            Use an already prepared work/ directory.
  --problem ID                Restrict the runner; repeatable for smoke tests.
  --max-problems N            Restrict the number of selected problems.
  -h, --help                  Show this help.

The full run makes paid model calls and may run for many hours. Exact proof text
is nondeterministic; see README.md for the reproduction criteria.
EOF
}

log() {
  printf '[putnambench-reproduction] %s\n' "$*"
}

die() {
  printf '[putnambench-reproduction] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

file_sha() {
  sha256sum "$1" | awk '{print $1}'
}

check_package() {
  local actual
  for command_name in bash python3 sha256sum; do
    need_cmd "$command_name"
  done

  [[ -f "$ROOT/MANIFEST.sha256" ]] || die "missing MANIFEST.sha256"
  (
    cd "$ROOT"
    sha256sum --check --quiet MANIFEST.sha256
  ) || die "package checksum verification failed"

  actual="$(file_sha "$INPUT_ROOT/Failed_problems.md")"
  [[ "$actual" == "$EXPECTED_FAILURE_SHA" ]] || die "Failed_problems.md hash mismatch"
  actual="$(file_sha "$INPUT_ROOT/putnam_bench.jsonl")"
  [[ "$actual" == "$EXPECTED_JSONL_SHA" ]] || die "putnam_bench.jsonl hash mismatch"
  actual="$(file_sha "$MATH_TEMPLATE/lake-manifest.json")"
  [[ "$actual" == "$EXPECTED_MANIFEST_SHA" ]] || die "Lake manifest hash mismatch"

  python3 - "$INPUT_ROOT/Failed_problems.md" "$INPUT_ROOT/putnam_bench.jsonl" <<'PY'
import json
import re
import sys
from pathlib import Path

failure_file = Path(sys.argv[1])
jsonl_file = Path(sys.argv[2])
selected = sorted(set(re.findall(r"putnam_[0-9]{4}_[ab][1-6]", failure_file.read_text())))
if len(selected) != 98:
    raise SystemExit(f"expected 98 selected problems, found {len(selected)}")

records = {}
for line_number, line in enumerate(jsonl_file.read_text().splitlines(), 1):
    record = json.loads(line)
    problem = record.get("problem_id")
    statement = record.get("formal_statement")
    if problem in records:
        raise SystemExit(f"duplicate problem_id at line {line_number}: {problem}")
    records[problem] = statement

missing = [problem for problem in selected if not isinstance(records.get(problem), str) or not records[problem]]
if missing:
    raise SystemExit("missing nonempty formal statements: " + ", ".join(missing))
print(f"validated {len(selected)} unique problems against {len(records)} JSONL records")
PY

  bash -n "$HUMANIZE_ROOT/scripts/run-failed-putnambench.sh"
  python3 - "$HUMANIZE_ROOT/scripts/verify-putnambench-axle.py" \
    "$MATH_TEMPLATE/scripts/validate-putnambench-output.py" <<'PY'
import ast
import sys
from pathlib import Path

for name in sys.argv[1:]:
    ast.parse(Path(name).read_text(), filename=name)
print("validated shell and Python source syntax")
PY

  log "package integrity check passed"
}

clone_at() {
  local repository="$1"
  local commit="$2"
  local destination="$3"

  if [[ ! -d "$destination/.git" ]]; then
    rm -rf "$destination"
    git clone --quiet "$repository" "$destination"
  fi

  if ! git -C "$destination" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$destination" fetch --quiet origin "$commit"
  fi
  git -C "$destination" checkout --quiet --detach "$commit"
  [[ "$(git -C "$destination" rev-parse HEAD)" == "$commit" ]] || \
    die "failed to pin $destination to $commit"
}

prepare_mathlib() {
  local host_elan_home local_elan_home toolchain
  host_elan_home="${HOST_ELAN_HOME:-${ELAN_HOME:-$HOME/.elan}}"
  local_elan_home="$MATH_ROOT/.venv/elan"
  toolchain="$(tr -d '[:space:]' < "$MATH_TEMPLATE/lean-toolchain")"

  [[ -d "$host_elan_home" ]] || die "Elan home not found: $host_elan_home"
  mkdir -p "$WORK_ROOT"
  if [[ ! -d "$MATH_ROOT" ]]; then
    cp -a "$MATH_TEMPLATE" "$MATH_ROOT"
  fi
  mkdir -p "$MATH_ROOT/.venv"
  rm -rf "$local_elan_home"
  ln -s "$host_elan_home" "$local_elan_home"

  ELAN_HOME="$local_elan_home" elan toolchain install "$toolchain"
  (
    cd "$MATH_ROOT"
    ELAN_HOME="$local_elan_home" lake exe cache get
  )

  [[ -d "$MATH_ROOT/.lake/packages/mathlib" ]] || die "Mathlib package setup failed"
  [[ "$(file_sha "$MATH_ROOT/lake-manifest.json")" == "$EXPECTED_MANIFEST_SHA" ]] || \
    die "bootstrap changed the pinned Lake manifest"
}

prepare_comparator_tools() {
  local local_elan_home="$MATH_ROOT/.venv/elan"
  mkdir -p "$TOOLS_ROOT"

  clone_at "$COMPARATOR_REPO" "$COMPARATOR_COMMIT" "$TOOLS_ROOT/comparator-current"
  clone_at "$LEAN4EXPORT_REPO" "$LEAN4EXPORT_COMMIT" "$TOOLS_ROOT/lean4export"
  clone_at "$LANDRUN_REPO" "$LANDRUN_COMMIT" "$TOOLS_ROOT/landrun-main"

  (
    cd "$TOOLS_ROOT/comparator-current"
    ELAN_HOME="$local_elan_home" lake build comparator
  )
  (
    cd "$TOOLS_ROOT/lean4export"
    ELAN_HOME="$local_elan_home" lake build lean4export
  )
  (
    cd "$TOOLS_ROOT/landrun-main"
    go build -trimpath -o "$TOOLS_ROOT/landrun" ./cmd/landrun
  )

  [[ -x "$TOOLS_ROOT/comparator-current/.lake/build/bin/comparator" ]] || \
    die "Comparator build did not produce a binary"
  [[ -x "$TOOLS_ROOT/lean4export/.lake/build/bin/lean4export" ]] || \
    die "lean4export build did not produce a binary"
  [[ -x "$TOOLS_ROOT/landrun" ]] || die "Landrun build did not produce a binary"
}

bootstrap() {
  local command_name
  for command_name in cc curl elan git go lake unshare; do
    need_cmd "$command_name"
  done
  unshare --user --map-root-user --mount --net --fork true 2>/dev/null || \
    die "unprivileged user/mount/network namespaces are unavailable"
  prepare_mathlib
  prepare_comparator_tools
  log "pinned Lean and Comparator environment is ready under $WORK_ROOT"
}

run_experiment() {
  local prepare_flag=()
  local command_name

  for command_name in awk bash cc chroot codex date find flock git jq lake mount \
    python3 rg sha256sum timeout unshare; do
    need_cmd "$command_name"
  done
  [[ -f "$BASE_CODEX_HOME/auth.json" ]] || die "missing $BASE_CODEX_HOME/auth.json"
  [[ -f "$BASE_CODEX_HOME/config.toml" ]] || die "missing $BASE_CODEX_HOME/config.toml"
  [[ -d "$MATH_ROOT/.lake/packages" ]] || die "run bootstrap first"
  [[ -x "$TOOLS_ROOT/landrun" ]] || die "run bootstrap first"
  mkdir -p "$OUT_ROOT"

  if [[ "$MODE" == "prepare" ]]; then
    prepare_flag=(--prepare-only)
  fi

  log "run id: $RUN_ID"
  log "mode: $MODE; jobs: $JOBS; fallback jobs: $FALLBACK_JOBS; max turns: $MAX_TURNS"
  if [[ "$MODE" == "run" ]]; then
    log "this mode makes paid Codex calls and contacts the AXLE verification API"
  fi

  WORKSPACE_ROOT="$WORK_ROOT" \
  MATH_FLOW_BENCH_ROOT="$MATH_ROOT" \
  PUTNAMBENCH_JSONL="$INPUT_ROOT/putnam_bench.jsonl" \
  FAILURE_FILE="$INPUT_ROOT/Failed_problems.md" \
  BASE_CODEX_HOME="$BASE_CODEX_HOME" \
  OUT_ROOT="$OUT_ROOT" \
  COMPARATOR_TOOLS_ROOT="$TOOLS_ROOT" \
  CODEX_MODEL="gpt-5.5" \
  MAX_TURNS="$MAX_TURNS" \
  JOBS="$JOBS" \
  FALLBACK_JOBS="$FALLBACK_JOBS" \
  PROBE_COUNT="$PROBE_COUNT" \
  WORKER_TIMEOUT_SECONDS="$WORKER_TIMEOUT" \
  REVIEW_TIMEOUT_SECONDS="$REVIEW_TIMEOUT" \
    bash "$HUMANIZE_ROOT/scripts/run-failed-putnambench.sh" \
      --run-id "$RUN_ID" \
      --failure-file "$INPUT_ROOT/Failed_problems.md" \
      --putnambench-jsonl "$INPUT_ROOT/putnam_bench.jsonl" \
      --base-codex-home "$BASE_CODEX_HOME" \
      --out-root "$OUT_ROOT" \
      --jobs "$JOBS" \
      --fallback-jobs "$FALLBACK_JOBS" \
      --probe-count "$PROBE_COUNT" \
      --max-turns "$MAX_TURNS" \
      --worker-timeout-seconds "$WORKER_TIMEOUT" \
      --review-timeout-seconds "$REVIEW_TIMEOUT" \
      "${prepare_flag[@]}" \
      "${RUNNER_ARGS[@]}"
}

case "$MODE" in
  check|bootstrap|prepare|run) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "unknown mode: $MODE"
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) JOBS="$2"; shift 2 ;;
    --fallback-jobs) FALLBACK_JOBS="$2"; shift 2 ;;
    --probe-count) PROBE_COUNT="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --worker-timeout) WORKER_TIMEOUT="$2"; shift 2 ;;
    --review-timeout) REVIEW_TIMEOUT="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --base-codex-home) BASE_CODEX_HOME="$2"; shift 2 ;;
    --out-root) OUT_ROOT="$2"; shift 2 ;;
    --skip-bootstrap) SKIP_BOOTSTRAP=1; shift ;;
    --problem|--max-problems)
      RUNNER_ARGS+=("$1" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

check_package
case "$MODE" in
  check) ;;
  bootstrap) bootstrap ;;
  prepare|run)
    if [[ "$SKIP_BOOTSTRAP" -eq 0 ]]; then
      bootstrap
    fi
    run_experiment
    ;;
esac
