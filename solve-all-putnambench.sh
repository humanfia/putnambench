#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUMANIZE_ROOT="$ROOT/humanize"
JSONL="$ROOT/inputs/putnam_bench.jsonl"
WORK_ROOT="$ROOT/work"
MATH_ROOT="$WORK_ROOT/math-flow-bench"
TOOLS_ROOT="$WORK_ROOT/comparator-tools"

JOBS="${PUTNAM_ALL_JOBS:-64}"
FALLBACK_JOBS="${PUTNAM_ALL_FALLBACK_JOBS:-16}"
PROBE_COUNT="${PUTNAM_ALL_PROBE_COUNT:-4}"
MAX_TURNS="${PUTNAM_ALL_MAX_TURNS:-50}"
MAX_CAMPAIGNS="${PUTNAM_ALL_CAMPAIGNS:-1}"
WORKER_TIMEOUT="${PUTNAM_ALL_WORKER_TIMEOUT:-7200}"
REVIEW_TIMEOUT="${PUTNAM_ALL_REVIEW_TIMEOUT:-7200}"
RUN_ID="${PUTNAM_ALL_RUN_ID:-putnambench-all-$(date -u +%Y%m%dT%H%M%SZ)}"
BASE_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
OUT_ROOT="$ROOT/all-runs"
MAX_PROBLEMS=0
PREPARE_ONLY=0
SKIP_BOOTSTRAP=0
LIST_ONLY=0
PROBLEMS=()

usage() {
  cat <<'EOF'
Usage:
  ./solve-all-putnambench.sh [options]

Selects all 672 problems from the packaged PutnamBench JSONL and runs the
Comparator-and-AXLE-gated Humanize solver. Later campaigns contain only
problems that did not pass an earlier campaign.

Options:
  --jobs N                    Main concurrency. Default: 64.
  --fallback-jobs N           Concurrency after rate limits. Default: 16.
  --probe-count N             One-turn probe jobs. Default: 4.
  --max-turns N               Turns per problem per campaign. Default: 50.
  --campaigns N               Maximum campaigns. Default: 1; 0 means continue
                              until every selected problem passes.
  --worker-timeout N          Seconds per worker call. Default: 7200.
  --review-timeout N          Seconds per reviewer call. Default: 7200.
  --run-id ID                 Controller and campaign run prefix.
  --base-codex-home PATH      Directory containing auth.json and config.toml.
  --out-root PATH             Output parent. Default: ./all-runs.
  --prepare-only              Prepare and audit workspaces; make no model calls.
  --skip-bootstrap            Reuse the existing pinned work/ environment.
  --problem ID                Restrict to a problem; repeatable for smoke tests.
  --max-problems N            Restrict the sorted selection for smoke tests.
  --list-only                 Print the selected IDs without downloads or calls.
  -h, --help                  Show this help.

The full 672-problem run makes paid model calls and can consume substantial
time, quota, memory, disk, and process capacity.
EOF
}

log() {
  printf '[solve-all-putnambench] %s\n' "$*"
}

die() {
  printf '[solve-all-putnambench] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_uint() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be a non-negative integer"
}

select_problems() {
  local output="$1"
  shift
  python3 - "$JSONL" "$MAX_PROBLEMS" "$@" > "$output" <<'PY'
import json
import re
import sys
from pathlib import Path

jsonl_path = Path(sys.argv[1])
maximum = int(sys.argv[2])
requested = sys.argv[3:]
pattern = re.compile(r"putnam_[0-9]{4}_[ab][1-6]")

records = {}
for line_number, line in enumerate(jsonl_path.read_text().splitlines(), 1):
    record = json.loads(line)
    problem = record.get("problem_id")
    statement = record.get("formal_statement")
    if not isinstance(problem, str) or pattern.fullmatch(problem) is None:
        raise SystemExit(f"invalid problem_id at JSONL line {line_number}: {problem!r}")
    if problem in records:
        raise SystemExit(f"duplicate problem_id at JSONL line {line_number}: {problem}")
    if not isinstance(statement, str) or not statement:
        raise SystemExit(f"empty formal_statement at JSONL line {line_number}: {problem}")
    records[problem] = statement

if len(records) != 672:
    raise SystemExit(f"expected 672 PutnamBench records, found {len(records)}")

if requested:
    unknown = sorted(set(requested) - records.keys())
    if unknown:
        raise SystemExit("unknown requested problems: " + ", ".join(unknown))
    selected = sorted(set(requested))
else:
    selected = sorted(records)

if maximum:
    selected = selected[:maximum]
for problem in selected:
    print(problem)
PY
}

write_selection_markdown() {
  local ids_file="$1" output="$2" title="$3"
  {
    printf '# %s\n\n' "$title"
    while IFS= read -r problem; do
      [[ -n "$problem" ]] && printf -- '- `%s`\n' "$problem"
    done < "$ids_file"
  } > "$output"
}

run_campaign() {
  local campaign="$1" selection="$2" campaign_id="$3"
  local prepare_args=()
  [[ "$PREPARE_ONLY" -eq 1 ]] && prepare_args=(--prepare-only)

  log "campaign $campaign: $campaign_id"
  WORKSPACE_ROOT="$WORK_ROOT" \
  MATH_FLOW_BENCH_ROOT="$MATH_ROOT" \
  PUTNAMBENCH_JSONL="$JSONL" \
  FAILURE_FILE="$selection" \
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
      --run-id "$campaign_id" \
      --failure-file "$selection" \
      --putnambench-jsonl "$JSONL" \
      --base-codex-home "$BASE_CODEX_HOME" \
      --out-root "$OUT_ROOT" \
      --jobs "$JOBS" \
      --fallback-jobs "$FALLBACK_JOBS" \
      --probe-count "$PROBE_COUNT" \
      --max-turns "$MAX_TURNS" \
      --worker-timeout-seconds "$WORKER_TIMEOUT" \
      --review-timeout-seconds "$REVIEW_TIMEOUT" \
      "${prepare_args[@]}"
}

collect_campaign() {
  local campaign="$1" campaign_id="$2" next_ids="$3" ledger="$4"
  local campaign_root="$OUT_ROOT/$campaign_id"
  local job problem status turn workspace candidate hash

  : > "$next_ids"
  for job in "$campaign_root"/jobs/j*-putnam_*; do
    [[ -d "$job" ]] || continue
    problem="$(cat "$job/problem.txt")"
    status="$(cat "$job/status.txt" 2>/dev/null || printf 'missing_status')"
    turn="$(cat "$job/completed-turn.txt" 2>/dev/null || cat "$job/next-turn.txt" 2>/dev/null || printf 'unknown')"
    workspace="$(cat "$job/workspace.txt")"
    candidate="$workspace/MathFlowBench/$(cat "$job/module.txt").lean"
    hash=""
    if [[ -f "$candidate" ]]; then
      hash="$(sha256sum "$candidate" | awk '{print $1}')"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$campaign" "$problem" "$status" "$turn" "$hash" "$candidate" >> "$ledger"
    if [[ "$status" != passed ]]; then
      printf '%s\n' "$problem" >> "$next_ids"
    fi
  done
  sort -u -o "$next_ids" "$next_ids"
}

write_summary() {
  local control_root="$1" selected_count="$2" unresolved_count="$3" campaigns_run="$4"
  local passed_count=$((selected_count - unresolved_count))
  {
    printf '# PutnamBench All-Problems Controller Summary\n\n'
    printf -- '- Run prefix: `%s`\n' "$RUN_ID"
    printf -- '- Selected problems: %s\n' "$selected_count"
    printf -- '- Verified passes: %s\n' "$passed_count"
    printf -- '- Unresolved: %s\n' "$unresolved_count"
    printf -- '- Campaigns completed: %s\n' "$campaigns_run"
    printf -- '- Model: `gpt-5.5`\n'
    printf -- '- Reasoning effort: `xhigh`\n'
    printf -- '- Per-campaign turn cap: %s\n' "$MAX_TURNS"
    printf '\nThe aggregate attempt ledger is `attempts.tsv`.\n'
    if [[ "$unresolved_count" -gt 0 ]]; then
      printf '\nUnresolved problem IDs are in `unresolved.txt`.\n'
    fi
  } > "$control_root/SUMMARY.md"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) JOBS="$2"; shift 2 ;;
    --fallback-jobs) FALLBACK_JOBS="$2"; shift 2 ;;
    --probe-count) PROBE_COUNT="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --campaigns) MAX_CAMPAIGNS="$2"; shift 2 ;;
    --worker-timeout) WORKER_TIMEOUT="$2"; shift 2 ;;
    --review-timeout) REVIEW_TIMEOUT="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --base-codex-home) BASE_CODEX_HOME="$2"; shift 2 ;;
    --out-root) OUT_ROOT="$2"; shift 2 ;;
    --prepare-only) PREPARE_ONLY=1; shift ;;
    --skip-bootstrap) SKIP_BOOTSTRAP=1; shift ;;
    --problem) PROBLEMS+=("$2"); shift 2 ;;
    --max-problems) MAX_PROBLEMS="$2"; shift 2 ;;
    --list-only) LIST_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

for pair in \
  "JOBS:$JOBS" \
  "FALLBACK_JOBS:$FALLBACK_JOBS" \
  "PROBE_COUNT:$PROBE_COUNT" \
  "MAX_TURNS:$MAX_TURNS" \
  "MAX_CAMPAIGNS:$MAX_CAMPAIGNS" \
  "WORKER_TIMEOUT:$WORKER_TIMEOUT" \
  "REVIEW_TIMEOUT:$REVIEW_TIMEOUT" \
  "MAX_PROBLEMS:$MAX_PROBLEMS"; do
  require_uint "${pair%%:*}" "${pair#*:}"
done
[[ "$JOBS" -ge 1 ]] || die "JOBS must be at least 1"
[[ "$FALLBACK_JOBS" -ge 1 ]] || die "FALLBACK_JOBS must be at least 1"
[[ "$MAX_TURNS" -ge 1 ]] || die "MAX_TURNS must be at least 1"

need_cmd python3
tmp_ids="$(mktemp)"
trap 'rm -f "$tmp_ids"' EXIT
select_problems "$tmp_ids" "${PROBLEMS[@]}"
selected_count="$(wc -l < "$tmp_ids")"
[[ "$selected_count" -gt 0 ]] || die "no problems selected"

if [[ "$LIST_ONLY" -eq 1 ]]; then
  "$ROOT/reproduce.sh" check >&2
  cat "$tmp_ids"
  printf '[solve-all-putnambench] selected %s problems\n' "$selected_count" >&2
  exit 0
fi

if [[ "$SKIP_BOOTSTRAP" -eq 0 ]]; then
  "$ROOT/reproduce.sh" bootstrap
else
  "$ROOT/reproduce.sh" check
fi

for command_name in awk bash codex jq sha256sum sort wc; do
  need_cmd "$command_name"
done
[[ -f "$BASE_CODEX_HOME/auth.json" ]] || die "missing $BASE_CODEX_HOME/auth.json"
[[ -f "$BASE_CODEX_HOME/config.toml" ]] || die "missing $BASE_CODEX_HOME/config.toml"
[[ -d "$MATH_ROOT/.lake/packages" ]] || die "pinned Mathlib environment is missing"
[[ -x "$TOOLS_ROOT/comparator-current/.lake/build/bin/comparator" ]] || die "Comparator is missing"
[[ -x "$TOOLS_ROOT/lean4export/.lake/build/bin/lean4export" ]] || die "Lean4Export is missing"
[[ -x "$TOOLS_ROOT/landrun" ]] || die "Landrun is missing"

mkdir -p "$OUT_ROOT"
control_root="$OUT_ROOT/${RUN_ID}-controller"
[[ ! -e "$control_root" ]] || die "controller output already exists: $control_root"
mkdir -p "$control_root/selections"
cp "$tmp_ids" "$control_root/initial.txt"
printf 'campaign\tproblem\tstatus\tturn\tcandidate_sha256\tcandidate_path\n' > "$control_root/attempts.tsv"

current_ids="$control_root/initial.txt"
campaign=1
campaigns_run=0
unresolved_count="$selected_count"

while [[ "$unresolved_count" -gt 0 ]]; do
  campaign_id="${RUN_ID}-c${campaign}"
  selection="$control_root/selections/campaign-${campaign}.md"
  next_ids="$control_root/selections/campaign-$((campaign + 1)).txt"
  write_selection_markdown "$current_ids" "$selection" \
    "PutnamBench campaign $campaign unresolved problems"
  log "campaign $campaign selected $unresolved_count problems"
  run_campaign "$campaign" "$selection" "$campaign_id"
  campaigns_run="$campaign"

  if [[ "$PREPARE_ONLY" -eq 1 ]]; then
    cp "$current_ids" "$control_root/unresolved.txt"
    write_summary "$control_root" "$selected_count" "$selected_count" "$campaigns_run"
    log "prepare-only complete: $OUT_ROOT/$campaign_id"
    exit 0
  fi

  collect_campaign "$campaign" "$campaign_id" "$next_ids" "$control_root/attempts.tsv"
  unresolved_count="$(wc -l < "$next_ids")"
  cp "$next_ids" "$control_root/unresolved.txt"
  log "campaign $campaign complete: $((selected_count - unresolved_count))/$selected_count passed overall"

  if [[ "$unresolved_count" -eq 0 ]]; then
    break
  fi
  if [[ "$MAX_CAMPAIGNS" -gt 0 && "$campaign" -ge "$MAX_CAMPAIGNS" ]]; then
    break
  fi
  current_ids="$next_ids"
  campaign=$((campaign + 1))
done

write_summary "$control_root" "$selected_count" "$unresolved_count" "$campaigns_run"
if [[ "$unresolved_count" -eq 0 ]]; then
  log "all $selected_count selected PutnamBench problems passed"
  exit 0
fi

log "$unresolved_count of $selected_count problems remain unresolved; see $control_root/unresolved.txt"
exit 2
