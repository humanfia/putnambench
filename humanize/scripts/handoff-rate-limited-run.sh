#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/zijian/zhengyang-workspace}"
OUT_ROOT="${OUT_ROOT:-$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs}"
BASE_CODEX_HOME="${BASE_CODEX_HOME:-/home/zijian/.codex}"
RUNNER="$SCRIPT_DIR/run-failed-putnambench.sh"
RUN_ID=""
MAIN_PID=""
TARGET=16

usage() {
  cat <<'EOF'
Usage: handoff-rate-limited-run.sh --run-id ID --main-pid PID [--target N]

Waits for a rate-limited runner's active problem count to drain to the target,
pauses its scheduler, fills the remaining prepared jobs at the target
concurrency, then resumes the original scheduler after all active jobs finish.
EOF
}

die() {
  printf '[rate-handoff] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --main-pid) MAIN_PID="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$RUN_ID" ]] || die "--run-id is required"
[[ "$MAIN_PID" =~ ^[1-9][0-9]*$ ]] || die "invalid --main-pid"
[[ "$TARGET" =~ ^[1-9][0-9]*$ ]] || die "invalid --target"
RUN_ROOT="$OUT_ROOT/$RUN_ID"
[[ -d "$RUN_ROOT/jobs" ]] || die "run not found: $RUN_ROOT"
[[ -r "/proc/$MAIN_PID/cmdline" ]] || die "main process is not running: $MAIN_PID"
tr '\0' ' ' < "/proc/$MAIN_PID/cmdline" | grep -Fq -- "--run-id $RUN_ID" || \
  die "PID $MAIN_PID does not own run $RUN_ID"

active_count() {
  find "$RUN_ROOT/jobs" -name status.txt -type f -exec cat {} + 2>/dev/null |
    awk '/^(worker_turn_|review_turn_)/ { n++ } END { print n + 0 }'
}

prepared_count() {
  find "$RUN_ROOT/jobs" -name status.txt -type f -exec cat {} + 2>/dev/null |
    awk '$0 == "prepared" { n++ } END { print n + 0 }'
}

recover_infrastructure_failures() {
  local status_file status problem mode pid
  local -a recovery_pids=()

  while true; do
    recovery_pids=()
    while IFS= read -r status_file; do
      status="$(cat "$status_file")"
      case "$status" in
        worker_rate_limited|worker_timeout|worker_transport_failed)
          mode=--resume-worker-only
          ;;
        reviewer_rate_limited|reviewer_timeout|reviewer_transport_failed|review_infrastructure_failed)
          mode=--resume-review-only
          ;;
        *)
          continue
          ;;
      esac
      problem="$(cat "$(dirname "$status_file")/problem.txt")"
      log "recovering $problem from $status"
      CODEX_MODEL=gpt-5.5 JOBS="$TARGET" FALLBACK_JOBS="$TARGET" MAX_TURNS=50 \
        BASE_CODEX_HOME="$BASE_CODEX_HOME" \
        PUTNAMBENCH_JSONL="$WORKSPACE_ROOT/putnam_bench.jsonl" \
        bash "$RUNNER" "$mode" --run-id "$RUN_ID" --problem "$problem" \
          --jobs "$TARGET" --fallback-jobs "$TARGET" --max-turns 50 &
      recovery_pids+=("$!")
      if [[ "${#recovery_pids[@]}" -ge "$TARGET" ]]; then
        for pid in "${recovery_pids[@]}"; do
          wait "$pid" || true
        done
        recovery_pids=()
      fi
    done < <(find "$RUN_ROOT/jobs" -name status.txt -type f | sort)

    for pid in "${recovery_pids[@]}"; do
      wait "$pid" || true
    done
    recovery_pids=()

    if ! find "$RUN_ROOT/jobs" -name status.txt -type f -exec cat {} + 2>/dev/null |
        grep -Eq '^(worker_rate_limited|worker_timeout|worker_transport_failed|reviewer_rate_limited|reviewer_timeout|reviewer_transport_failed|review_infrastructure_failed)$'; then
      break
    fi
    log "infrastructure failures remain after recovery pass; retrying"
    sleep 60
  done
}

while [[ "$(active_count)" -gt "$TARGET" ]]; do
  [[ -r "/proc/$MAIN_PID/cmdline" ]] || die "main process exited before handoff"
  log "waiting: active=$(active_count), prepared=$(prepared_count), target=$TARGET"
  sleep 30
done

log "pausing scheduler PID $MAIN_PID at active=$(active_count)"
kill -STOP "$MAIN_PID"
trap 'kill -CONT "$MAIN_PID" 2>/dev/null || true' EXIT

CODEX_MODEL=gpt-5.5 JOBS="$TARGET" FALLBACK_JOBS="$TARGET" MAX_TURNS=50 \
  BASE_CODEX_HOME="$BASE_CODEX_HOME" \
  PUTNAMBENCH_JSONL="$WORKSPACE_ROOT/putnam_bench.jsonl" \
  bash "$RUNNER" --resume-prepared --run-id "$RUN_ID" \
    --jobs "$TARGET" --fallback-jobs "$TARGET" --max-turns 50

while [[ "$(active_count)" -gt 0 ]]; do
  log "waiting for handed-off jobs: active=$(active_count)"
  sleep 30
done

recover_infrastructure_failures

log "resuming original scheduler PID $MAIN_PID"
kill -CONT "$MAIN_PID"
trap - EXIT
