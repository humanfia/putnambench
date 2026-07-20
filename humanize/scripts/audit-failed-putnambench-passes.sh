#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/zijian/zhengyang-workspace}"
OUT_ROOT="${OUT_ROOT:-$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs}"
CANONICAL_ROOT="${CANONICAL_ROOT:-$WORKSPACE_ROOT/lean/math-flow-bench}"
STATE_ROOT="${STATE_ROOT:-$OUT_ROOT/pass-audit}"
LEDGER="$STATE_ROOT/verified-passes.tsv"
FAILURES="$STATE_ROOT/audit-failures.tsv"
MIRROR_LEDGER="${MIRROR_LEDGER:-}"
SCAN_SECONDS="${SCAN_SECONDS:-45}"
MAX_NEW="${MAX_NEW:-2}"
DAEMON=0

usage() {
  cat <<'EOF'
Usage: audit-failed-putnambench-passes.sh [options]

Independently audits terminal passed jobs across every original or continuation
run. It verifies the candidate and original hashes against the exact AXLE
artifact, checks the reviewer completion marker, reruns the statement validator
and forbidden-marker scan, and compiles the candidate from the canonical built
MathFlowBench environment. Verified problems are recorded once in a TSV ledger.

Options:
  --daemon            Keep scanning for newly passed jobs.
  --scan-seconds N    Delay between daemon scans. Default: 45.
  --max-new N         Maximum new audits per scan. Default: 2.
  -h, --help          Show this help.
EOF
}

die() {
  printf '[pass-audit] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"
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
    --daemon) DAEMON=1; shift ;;
    --scan-seconds) SCAN_SECONDS="$2"; shift 2 ;;
    --max-new) MAX_NEW="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "$SCAN_SECONDS" =~ ^[1-9][0-9]*$ ]] || die "invalid scan interval"
[[ "$MAX_NEW" =~ ^[1-9][0-9]*$ ]] || die "invalid per-scan audit limit"
[[ -d "$CANONICAL_ROOT/.lake" ]] || die "canonical Lean build is missing"

mkdir -p "$STATE_ROOT/logs"
touch "$LEDGER" "$FAILURES"
lock_dir="$STATE_ROOT/lock"
mkdir "$lock_dir" 2>/dev/null || die "another pass auditor is already running"
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

is_verified() {
  local problem="$1"
  awk -F '\t' -v p="$problem" '$1 == p { found = 1 } END { exit !found }' "$LEDGER"
}

record_failure() {
  local problem="$1" run_id="$2" job="$3" reason="$4"
  printf '%s\t%s\t%s\t%s\t%s\n' "$problem" "$run_id" "$job" "$reason" \
    "$(date -u +%FT%TZ)" >> "$FAILURES"
  log "audit failed for $problem ($reason)"
}

audit_job() {
  local job_dir="$1" run_root run_id job problem module workspace loop
  local review axle candidate original candidate_sha original_sha
  local axle_candidate_sha axle_submitted_sha axle_original_sha request_id
  local last_line compile_log verified_at

  run_root="$(dirname "$(dirname "$job_dir")")"
  run_id="$(basename "$run_root")"
  job="$(basename "$job_dir")"
  problem="${job#*-}"
  [[ "$problem" =~ ^putnam_[0-9]{4}_[ab][1-6]$ ]] || return 0
  is_verified "$problem" && return 0

  module="$(module_name "$problem")"
  workspace="$(cat "$job_dir/workspace.txt")"
  loop="$(find "$workspace/.humanize/rlcr" -mindepth 1 -maxdepth 1 \
    -type d -print -quit)"
  review="$(find "$loop" -maxdepth 1 -type f -name 'round-*-review-result.md' \
    -printf '%f\n' | sort -V | tail -1)"
  [[ -n "$review" ]] || { record_failure "$problem" "$run_id" "$job" no-review; return 1; }
  axle="$loop/$review.axle.json"
  candidate="$workspace/MathFlowBench/$module.lean"
  original="$workspace/source/lean4/src/$problem.lean"
  [[ -f "$candidate" && -f "$original" && -f "$axle" ]] || {
    record_failure "$problem" "$run_id" "$job" missing-artifact
    return 1
  }

  jq -e '.all_okay == true and (.results | length == 1) and
    .results[0].okay == true and .results[0].status == "correct"' \
    "$axle" >/dev/null || {
      record_failure "$problem" "$run_id" "$job" axle-not-okay
      return 1
    }

  candidate_sha="$(sha256sum "$candidate" | awk '{print $1}')"
  original_sha="$(sha256sum "$original" | awk '{print $1}')"
  axle_candidate_sha="$(jq -r '.results[0].candidate_sha256' "$axle")"
  axle_submitted_sha="$(jq -r '.results[0].submitted_content_sha256' "$axle")"
  axle_original_sha="$(jq -r '.results[0].original_sha256' "$axle")"
  request_id="$(jq -r '.results[0].request_id' "$axle")"
  [[ "$candidate_sha" == "$axle_candidate_sha" && \
     "$candidate_sha" == "$axle_submitted_sha" && \
     "$original_sha" == "$axle_original_sha" ]] || {
    record_failure "$problem" "$run_id" "$job" hash-mismatch
    return 1
  }

  last_line="$(awk 'NF { line = $0 } END { print line }' "$loop/$review")"
  [[ "$last_line" == COMPLETE ]] || {
    record_failure "$problem" "$run_id" "$job" review-not-complete
    return 1
  }

  if rg -n '\b(sorry|admit|axiom|native_decide)\b' "$candidate" >/dev/null; then
    record_failure "$problem" "$run_id" "$job" forbidden-marker
    return 1
  fi
  if ! (cd "$workspace" && python3 scripts/validate-putnambench-output.py \
      --problem "$problem" --putnambench-root source --candidate-root .); then
    record_failure "$problem" "$run_id" "$job" statement-validator
    return 1
  fi

  compile_log="$STATE_ROOT/logs/$problem-$candidate_sha.lean.log"
  if ! (cd "$CANONICAL_ROOT" && lake env lean "$candidate") >"$compile_log" 2>&1; then
    record_failure "$problem" "$run_id" "$job" lean-compile
    return 1
  fi

  verified_at="$(date -u +%FT%TZ)"
  {
    flock 8
    if ! awk -F '\t' -v p="$problem" \
        '$1 == p { found = 1 } END { exit !found }' "$LEDGER"; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$problem" "$run_id" "$job" "$candidate_sha" "$original_sha" \
        "$request_id" "$review" "$verified_at" >> "$LEDGER"
    fi
  } 8>"$LEDGER.lock"
  if [[ -n "$MIRROR_LEDGER" ]]; then
    mkdir -p "$(dirname "$MIRROR_LEDGER")"
    touch "$MIRROR_LEDGER"
    {
      flock 9
      if ! awk -F '\t' -v p="$problem" \
          '$1 == p { found = 1 } END { exit !found }' "$MIRROR_LEDGER"; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$problem" "$run_id" "$job" "$candidate_sha" "$original_sha" \
          "$request_id" "$review" "$verified_at" >> "$MIRROR_LEDGER"
      fi
    } 9>"$MIRROR_LEDGER.lock"
  fi
  log "verified $problem ($candidate_sha, AXLE $request_id)"
}

scan_once() {
  local status_file job_dir audited=0
  while IFS= read -r -d '' status_file; do
    [[ "$(head -1 "$status_file" 2>/dev/null || true)" == passed ]] || continue
    job_dir="$(dirname "$status_file")"
    problem="$(basename "$job_dir")"
    problem="${problem#*-}"
    is_verified "$problem" && continue
    audit_job "$job_dir" || true
    audited=$((audited + 1))
    [[ "$audited" -ge "$MAX_NEW" ]] && break
  done < <(find "$OUT_ROOT" -path '*/jobs/*/status.txt' -type f -print0 | sort -z)
  log "scan complete: $(wc -l < "$LEDGER") verified problem(s) in ledger"
}

while :; do
  scan_once
  [[ "$DAEMON" -eq 1 ]] || break
  sleep "$SCAN_SECONDS"
done
