#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUMANIZE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/zijian/zhengyang-workspace}"
OUT_ROOT="${OUT_ROOT:-$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs}"
BASE_CODEX_HOME="${BASE_CODEX_HOME:-$WORKSPACE_ROOT/.codex}"
RUNNER="$SCRIPT_DIR/run-failed-putnambench.sh"

SOURCE_RUN_ID=""
RUN_ID=""
LAUNCH=0
PROBLEMS=()

usage() {
  cat <<'EOF'
Usage:
  bash scripts/continue-failed-putnambench.sh \
    --source-run-id ID --problem ID [--problem ID ...] [options]

Creates a new isolated 50-turn Humanize run seeded only with each selected
problem's current sanitized candidate and latest independent review from the
source run. Existing solutions and external prior-run files are not exposed to
either model.

Options:
  --source-run-id ID   Required source run under failed-putnambench...-runs.
  --problem ID         Terminal source problem to continue; repeatable.
  --run-id ID          New run ID. Default: continuation timestamp.
  --launch             Launch the prepared continuation in the foreground.
  -h, --help           Show this help.
EOF
}

die() {
  printf '[failed-putnambench-continuation] ERROR: %s\n' "$*" >&2
  exit 1
}

safe_name() {
  printf '%s' "$1" | tr -c '[:alnum:]_.-' '-'
}

module_name() {
  local rest year part
  rest="${1#putnam_}"
  year="${rest%%_*}"
  part="${rest#*_}"
  printf 'Putnam%s%s%s\n' "$year" \
    "$(printf '%s' "${part:0:1}" | tr '[:lower:]' '[:upper:]')" "${part:1}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-run-id) SOURCE_RUN_ID="$2"; shift 2 ;;
    --problem) PROBLEMS+=("$2"); shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --launch) LAUNCH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$SOURCE_RUN_ID" ]] || die "--source-run-id is required"
[[ "${#PROBLEMS[@]}" -gt 0 ]] || die "at least one --problem is required"
RUN_ID="${RUN_ID:-failed-humanize-axle-continuation-$(date -u +%Y%m%dT%H%M%SZ)}"

SOURCE_ROOT="$OUT_ROOT/$SOURCE_RUN_ID"
DEST_ROOT="$OUT_ROOT/$RUN_ID"
[[ -d "$SOURCE_ROOT/jobs" && -d "$SOURCE_ROOT/workspaces" ]] || \
  die "source run does not exist: $SOURCE_ROOT"
[[ ! -e "$DEST_ROOT" ]] || die "destination run already exists: $DEST_ROOT"

prepare_args=(
  --prepare-only
  --run-id "$RUN_ID"
  --base-codex-home "$BASE_CODEX_HOME"
  --max-turns 50
)
for problem in "${PROBLEMS[@]}"; do
  [[ "$problem" =~ ^putnam_[0-9]{4}_[ab][1-6]$ ]] || \
    die "invalid problem id: $problem"
  prepare_args+=(--problem "$problem")
done

CODEX_MODEL=gpt-5.5 MAX_TURNS=50 BASE_CODEX_HOME="$BASE_CODEX_HOME" \
  bash "$RUNNER" "${prepare_args[@]}"

index=0
for problem in "${PROBLEMS[@]}"; do
  safe="$(safe_name "$problem")"
  module="$(module_name "$problem")"
  source_job="$(find "$SOURCE_ROOT/jobs" -mindepth 1 -maxdepth 1 -type d \
    -name "*-$safe" -print -quit)"
  [[ -n "$source_job" ]] || die "source job not found for $problem"
  source_status="$(cat "$source_job/status.txt")"
  [[ "$source_status" != passed ]] || die "$problem already passed in source run"

  source_workspace="$(cat "$source_job/workspace.txt")"
  source_candidate="$source_workspace/MathFlowBench/$module.lean"
  [[ -f "$source_candidate" ]] || die "source candidate missing for $problem"
  source_loop="$(find "$source_workspace/.humanize/rlcr" -mindepth 1 \
    -maxdepth 1 -type d -print -quit)"
  source_review="$(find "$source_loop" -maxdepth 1 -type f \
    -name 'round-*-review-result.md' -printf '%f\n' | sort -V | tail -1)"
  [[ -n "$source_review" ]] || die "source review missing for $problem"

  dest_job="$DEST_ROOT/jobs/j${index}-${safe}"
  dest_workspace="$DEST_ROOT/workspaces/j${index}-${safe}"
  dest_loop="$(find "$dest_workspace/.humanize/rlcr" -mindepth 1 \
    -maxdepth 1 -type d -print -quit)"

  cp "$source_candidate" "$dest_workspace/MathFlowBench/$module.lean"
  cp "$source_loop/$source_review" "$dest_loop/seed-review.md"
  {
    printf 'source_run_id=%s\n' "$SOURCE_RUN_ID"
    printf 'source_job=%s\n' "$(basename "$source_job")"
    printf 'source_status=%s\n' "$source_status"
    printf 'source_candidate_sha256=%s\n' "$(sha256sum "$source_candidate" | awk '{print $1}')"
    printf 'source_review=%s\n' "$source_review"
    printf 'source_review_sha256=%s\n' \
      "$(sha256sum "$source_loop/$source_review" | awk '{print $1}')"
  } > "$dest_job/continuation-source.txt"

  git -C "$dest_workspace" add "MathFlowBench/$module.lean"
  git -C "$dest_workspace" commit -q -m \
    "Seed continuation from sanitized $problem candidate"
  index=$((index + 1))
done

printf '[failed-putnambench-continuation] prepared %s problem(s): %s\n' \
  "${#PROBLEMS[@]}" "$DEST_ROOT"

if [[ "$LAUNCH" -eq 1 ]]; then
  resume_args=(
    --resume-prepared
    --run-id "$RUN_ID"
    --base-codex-home "$BASE_CODEX_HOME"
    --max-turns 50
  )
  for problem in "${PROBLEMS[@]}"; do
    resume_args+=(--problem "$problem")
  done
  CODEX_MODEL=gpt-5.5 MAX_TURNS=50 BASE_CODEX_HOME="$BASE_CODEX_HOME" \
    bash "$RUNNER" "${resume_args[@]}"
fi
