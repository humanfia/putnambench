#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/zijian/zhengyang-workspace}"
OUT_ROOT="${OUT_ROOT:-$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs}"
BASE_CODEX_HOME="${BASE_CODEX_HOME:-$WORKSPACE_ROOT/.codex}"
CONTINUE_SCRIPT="$SCRIPT_DIR/continue-failed-putnambench.sh"
RUNNER="$SCRIPT_DIR/run-failed-putnambench.sh"
STATE_ROOT="${STATE_ROOT:-$OUT_ROOT/continuation-supervisor}"
REGISTRY="$STATE_ROOT/registry.tsv"
SCAN_SECONDS="${SCAN_SECONDS:-30}"
MAX_ACTIVE="${MAX_ACTIVE:-64}"
NO_RECURSE_RUN_ID="${NO_RECURSE_RUN_ID:-}"
DAEMON=0

usage() {
  cat <<'EOF'
Usage: supervise-failed-putnambench-continuations.sh [options]

Finds max-turn jobs in the isolated Humanize runs and launches exactly one
sanitized 50-turn continuation for each terminal source job. Reviewer-only
infrastructure failures are retried against the unchanged candidate. Existing
continuations are discovered from their provenance records before scanning.

Options:
  --daemon            Continue scanning until stopped. The default is one scan.
  --scan-seconds N    Delay between daemon scans. Default: 30.
  --max-active N      Do not launch above this many active problem loops.
                      Default: 64.
  -h, --help          Show this help.

The known false parsed target putnam_2017_b3 is classified as a benchmark
formalization defect and is never relaunched.
EOF
}

die() {
  printf '[continuation-supervisor] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --daemon) DAEMON=1; shift ;;
    --scan-seconds) SCAN_SECONDS="$2"; shift 2 ;;
    --max-active) MAX_ACTIVE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "$SCAN_SECONDS" =~ ^[1-9][0-9]*$ ]] || die "invalid scan interval"
[[ "$MAX_ACTIVE" =~ ^[1-9][0-9]*$ ]] || die "invalid active-job limit"
[[ -x "$CONTINUE_SCRIPT" || -f "$CONTINUE_SCRIPT" ]] || \
  die "continuation script not found: $CONTINUE_SCRIPT"

mkdir -p "$STATE_ROOT"
touch "$REGISTRY"
lock_dir="$STATE_ROOT/lock"
mkdir "$lock_dir" 2>/dev/null || die "another supervisor is already running"
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

registry_has() {
  local source_run="$1" source_job="$2"
  awk -F '\t' -v r="$source_run" -v j="$source_job" \
    '$1 == r && $2 == j { found = 1 } END { exit !found }' "$REGISTRY"
}

register_existing_continuations() {
  local provenance source_run source_job problem dest_run
  while IFS= read -r -d '' provenance; do
    source_run="$(sed -n 's/^source_run_id=//p' "$provenance")"
    source_job="$(sed -n 's/^source_job=//p' "$provenance")"
    problem="${source_job#*-}"
    dest_run="$(basename "$(dirname "$(dirname "$(dirname "$provenance")")")")"
    [[ -n "$source_run" && -n "$source_job" ]] || continue
    if ! registry_has "$source_run" "$source_job"; then
      printf '%s\t%s\t%s\t%s\tdiscovered\t%s\n' \
        "$source_run" "$source_job" "$problem" "$dest_run" \
        "$(date -u +%FT%TZ)" >> "$REGISTRY"
    fi
  done < <(find "$OUT_ROOT" -path '*/jobs/*/continuation-source.txt' \
    -type f -print0 2>/dev/null)
}

active_count() {
  ps -eo args= | awk -v out_root="$OUT_ROOT" '
    /unshare --user --map-root-user/ && /bash -s -- (worker|reviewer)/ && \
      index($0, out_root) { count++ }
    END { print count + 0 }
  '
}

job_runner_active() {
  local source_run="$1" problem="$2"
  ps -eo comm=,args= | awk -v runner="$RUNNER" -v run_id="$source_run" \
      -v problem="$problem" '
    $1 == "bash" && index($0, runner) && index($0, run_id) && \
      index($0, problem) {
      found = 1
    }
    END { exit !found }
  '
}

launch_continuation() {
  local source_run="$1" source_job="$2" problem="$3"
  local stamp key run_id session run_root status i

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  key="$(printf '%s/%s' "$source_run" "$source_job" | sha256sum | cut -c1-8)"
  run_id="failed-humanize-axle-continuation-${problem#putnam_}-${stamp}-${key}"
  session="failed-cont-${problem#putnam_}-${key}"
  run_root="$OUT_ROOT/$run_id"

  log "preparing $problem from $source_run/$source_job"
  if ! BASE_CODEX_HOME="$BASE_CODEX_HOME" bash "$CONTINUE_SCRIPT" \
      --source-run-id "$source_run" --problem "$problem" --run-id "$run_id"; then
    log "preparation failed for $source_run/$source_job; will retry"
    return 1
  fi

  tmux new-session -d -s "$session" \
    "env BASE_CODEX_HOME='$BASE_CODEX_HOME' CODEX_MODEL=gpt-5.5 CODEX_RATE_RETRIES=3 MAX_TURNS=50 bash '$RUNNER' --resume-prepared --run-id '$run_id' --problem '$problem' >> '$run_root/launcher.log' 2>&1"

  status=prepared
  for i in $(seq 1 30); do
    status="$(head -1 "$run_root/jobs/j0-$problem/status.txt" 2>/dev/null || true)"
    [[ "$status" != prepared && -n "$status" ]] && break
    sleep 1
  done
  [[ "$status" != prepared && -n "$status" ]] || \
    die "continuation did not start: $run_id"

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$source_run" "$source_job" "$problem" "$run_id" "$session" \
    "$(date -u +%FT%TZ)" >> "$REGISTRY"
  log "launched $run_id in tmux session $session ($status)"
}

launch_review_recovery() {
  local source_run="$1" source_job="$2" problem="$3" prior_status="$4"
  local stamp key session run_root
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  key="$(printf '%s/%s' "$source_run" "$source_job" | sha256sum | cut -c1-8)"
  session="failed-review-${problem#putnam_}-${key}-${stamp:9:6}"
  run_root="$OUT_ROOT/$source_run"

  log "retrying unchanged $problem review in $source_run/$source_job ($prior_status)"
  tmux new-session -d -s "$session" \
    "env BASE_CODEX_HOME='$BASE_CODEX_HOME' CODEX_MODEL=gpt-5.5 CODEX_RATE_RETRIES=3 REVIEW_INFRA_RETRIES=0 MAX_TURNS=50 bash '$RUNNER' --resume-review-only --run-id '$source_run' --problem '$problem' >> '$run_root/review-recovery.log' 2>&1"
  log "launched review recovery $session for $problem (pre-review gate running)"
}

launch_worker_recovery() {
  local source_run="$1" source_job="$2" problem="$3" prior_status="$4"
  local stamp key session run_root status i
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  key="$(printf '%s/%s' "$source_run" "$source_job" | sha256sum | cut -c1-8)"
  session="failed-worker-${problem#putnam_}-${key}-${stamp:9:6}"
  run_root="$OUT_ROOT/$source_run"

  log "retrying $problem worker in $source_run/$source_job ($prior_status)"
  tmux new-session -d -s "$session" \
    "env BASE_CODEX_HOME='$BASE_CODEX_HOME' CODEX_MODEL=gpt-5.5 CODEX_RATE_RETRIES=3 MAX_TURNS=50 bash '$RUNNER' --resume-worker-only --run-id '$source_run' --problem '$problem' >> '$run_root/worker-recovery.log' 2>&1"

  status="$prior_status"
  for i in $(seq 1 30); do
    status="$(head -1 "$run_root/jobs/$source_job/status.txt" 2>/dev/null || true)"
    [[ "$status" != "$prior_status" && -n "$status" ]] && break
    sleep 1
  done
  if [[ "$status" == "$prior_status" || -z "$status" ]]; then
    log "worker recovery did not start for $source_run/$source_job; will retry"
    return 1
  fi
  log "launched worker recovery $session for $problem ($status)"
}

scan_once() {
  local status_file status job_dir source_root source_run source_job problem active
  register_existing_continuations
  active="$(active_count)"
  log "scan: $active active problem loops (limit $MAX_ACTIVE)"

  while IFS= read -r -d '' status_file; do
    status="$(head -1 "$status_file" 2>/dev/null || true)"
    job_dir="$(dirname "$status_file")"
    source_root="$(dirname "$(dirname "$job_dir")")"
    source_run="$(basename "$source_root")"
    source_job="$(basename "$job_dir")"
    problem="${source_job#*-}"
    [[ "$problem" =~ ^putnam_[0-9]{4}_[ab][1-6]$ ]] || continue

    case "$status" in
      worker_timeout|worker_transport_failed|worker_rate_limited)
        if job_runner_active "$source_run" "$problem"; then
          continue
        fi
        active="$(active_count)"
        if [[ "$active" -ge "$MAX_ACTIVE" ]]; then
          log "active limit reached; deferring worker recovery for $source_run/$source_job"
          break
        fi
        launch_worker_recovery "$source_run" "$source_job" "$problem" "$status" || true
        continue
        ;;
      review_infrastructure_failed|reviewer_timeout|reviewer_transport_failed|reviewer_rate_limited)
        if job_runner_active "$source_run" "$problem"; then
          continue
        fi
        active="$(active_count)"
        if [[ "$active" -ge "$MAX_ACTIVE" ]]; then
          log "active limit reached; deferring review recovery for $source_run/$source_job"
          break
        fi
        launch_review_recovery "$source_run" "$source_job" "$problem" "$status" || true
        continue
        ;;
      max_turns_reached)
        if [[ -n "$NO_RECURSE_RUN_ID" && "$source_run" == "$NO_RECURSE_RUN_ID" ]]; then
          log "leaving $source_run/$source_job terminal at the configured turn limit"
          continue
        fi
        ;;
      *) continue ;;
    esac

    registry_has "$source_run" "$source_job" && continue

    if [[ "$problem" == putnam_2017_b3 ]]; then
      printf '%s\t%s\t%s\tformalization-defect\texcluded\t%s\n' \
        "$source_run" "$source_job" "$problem" "$(date -u +%FT%TZ)" \
        >> "$REGISTRY"
      log "excluded $problem: parsed formal target is kernel-proven false"
      continue
    fi

    active="$(active_count)"
    if [[ "$active" -ge "$MAX_ACTIVE" ]]; then
      log "active limit reached; deferring $source_run/$source_job"
      break
    fi
    launch_continuation "$source_run" "$source_job" "$problem" || true
  done < <(find "$OUT_ROOT" -path '*/jobs/*/status.txt' -type f -print0 | sort -z)
}

while :; do
  scan_once
  [[ "$DAEMON" -eq 1 ]] || break
  sleep "$SCAN_SECONDS"
done
