#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/zijian/zhengyang-workspace}"
RUN_ID="${RUN_ID:-unresolved-comparator-20260708T020514Z}"
RUN_ROOT="${RUN_ROOT:-$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs/$RUN_ID}"
AUDIT_ROOT="${AUDIT_ROOT:-$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs/pass-audit}"
CLASSIFICATION_LEDGER="${CLASSIFICATION_LEDGER:-$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs/continuation-supervisor/classifications.tsv}"
OUTPUT="${OUTPUT:-$WORKSPACE_ROOT/Unresolved_failed_problems.md}"
SCAN_SECONDS="${SCAN_SECONDS:-30}"
GATE_AUDIT_SINCE="${GATE_AUDIT_SINCE:-2026-07-08 06:06:15Z}"
DAEMON=0

usage() {
  echo "Usage: $0 [--daemon] [--scan-seconds N]" >&2
}

while (($#)); do
  case "$1" in
    --daemon)
      DAEMON=1
      shift
      ;;
    --scan-seconds)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SCAN_SECONDS="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

[[ -d "$RUN_ROOT/jobs" ]] || {
  echo "Run jobs directory does not exist: $RUN_ROOT/jobs" >&2
  exit 1
}

render_status() {
  local tmp now total verified formalization verification active primary_active diagnostic_active workers reviewers
  local sessions runner_roots review_attempts gate_missing max_turn audit_failures

  tmp=$(mktemp "${OUTPUT}.tmp.XXXXXX")
  now=$(date -u +'%Y-%m-%d %H:%M:%SZ')
  total=$(find "$RUN_ROOT/jobs" -mindepth 1 -maxdepth 1 -type d | wc -l)
  verified=$(awk -F '\t' 'NF && $1 !~ /^#/ {seen[$1]=1} END {print length(seen)}' \
    "$AUDIT_ROOT/verified-passes.tsv" 2>/dev/null || echo 0)
  formalization=$(find "$RUN_ROOT/jobs" -mindepth 2 -maxdepth 2 -name status.txt \
    -exec awk '$0 == "formalization_defect" {n++} END {print n+0}' {} +)
  verification=$(awk -F '\t' -v run="$RUN_ID" \
    '$2 == run && $5 == "verification_defect" {seen[$3]=1} END {print length(seen)}' \
    "$CLASSIFICATION_LEDGER" 2>/dev/null || echo 0)
  workers=$(find "$RUN_ROOT/jobs" -mindepth 2 -maxdepth 2 -name status.txt \
    -exec awk '$0 ~ /^worker_turn_/ {n++} END {print n+0}' {} +)
  reviewers=$(find "$RUN_ROOT/jobs" -mindepth 2 -maxdepth 2 -name status.txt \
    -exec awk '$0 ~ /^review_turn_/ {n++} END {print n+0}' {} +)
  active=$((workers + reviewers))
  diagnostic_active=0
  while IFS= read -r job; do
    [[ -n "$job" && -f "$RUN_ROOT/jobs/$job/status.txt" ]] || continue
    case "$(<"$RUN_ROOT/jobs/$job/status.txt")" in
      worker_turn_*|review_turn_*) diagnostic_active=$((diagnostic_active + 1)) ;;
    esac
  done < <(awk -F '\t' -v run="$RUN_ID" \
    '$2 == run && $5 == "verification_defect" && !seen[$3]++ {print $3}' \
    "$CLASSIFICATION_LEDGER" 2>/dev/null)
  primary_active=$((active - diagnostic_active))
  sessions=$(wc -l < "$RUN_ROOT/codex-sessions.tsv")
  runner_roots=$(ps -eo args= | awk -v run="$RUN_ROOT" \
    'index($0, run) && /bash .*run-failed-putnambench\.sh/ {n++} END {print n+0}')
  max_turn=$(find "$RUN_ROOT/jobs" -mindepth 2 -maxdepth 2 -name next-turn.txt \
    -exec cat {} + | awk '$1 > max {max=$1} END {print max+0}')
  audit_failures=$(wc -l < "$AUDIT_ROOT/audit-failures.tsv")

  review_attempts=0
  gate_missing=0
  while IFS= read -r event; do
    local base round log
    review_attempts=$((review_attempts + 1))
    base=$(basename "$event")
    round=${base#round-}
    round=${round%%-reviewer-attempt-*}
    log="$(dirname "$event")/round-$round-local-checks.log"
    if [[ ! -f "$log" ]] ||
      ! grep -q '^Lean default kernel accepts the solution$' "$log" ||
      ! grep -q '^Your solution is okay!$' "$log"; then
      gate_missing=$((gate_missing + 1))
    fi
  done < <(find "$RUN_ROOT/jobs" -type f \
    -name 'round-*-reviewer-attempt-*.events.jsonl' \
    -newermt "$GATE_AUDIT_SINCE" | sort)

  {
    echo '# Unresolved Failed Problems'
    echo
    echo "Generated at: \`$now\`"
    echo
    echo 'This file tracks the original `57` previously failed problems in the active'
    echo 'Comparator-backed humanize continuation:'
    echo
    echo "\`$RUN_ROOT\`"
    echo
    echo 'A problem is counted as solved only after the candidate passes the local Lean'
    echo 'and Comparator gate, the reviewer obtains a fresh same-round AXLE success, and'
    echo 'the independent pass auditor records it in `verified-passes.tsv`.'
    echo
    echo '## Current Summary'
    echo
    echo "- Original problems in this continuation: \`$total\`"
    echo "- Newly AXLE-verified solutions: \`$verified\`"
    echo "- Formalization defects: \`$formalization\`"
    echo "- Verification diagnostic history entries: \`$verification\`"
    echo "- Unclassified active searches: \`$primary_active\`"
    echo "- Verification-defect diagnostic requeues still running: \`$diagnostic_active\`"
    echo "- Total live searches: \`$active\` (\`$workers\` worker stage, \`$reviewers\` review stage)"
    echo "- Highest next turn: \`$max_turn\` of \`50\`"
    echo "- Comparator-backed runner roots: \`$runner_roots\`"
    echo "- Retained Codex session records: \`$sessions\`"
    echo "- Reviewer attempts checked since the hard-gate supervisor restart: \`$review_attempts\`"
    echo "- Reviewer attempts missing Comparator-pass evidence: \`$gate_missing\`"
    echo "- Pass-audit failure rows: \`$audit_failures\`"
    echo
    echo '## Terminal Formalization Defects'
    echo
    echo 'Formalization defects:'
    echo
    echo '```text'
    for d in "$RUN_ROOT"/jobs/*; do
      if [[ $(<"$d/status.txt") == formalization_defect ]]; then
        cat "$d/problem.txt"
      fi
    done | sort
    echo '```'
    echo
    echo '## Verification Diagnostic History'
    echo
    echo 'These entries are retained evidence snapshots, not terminal classifications.'
    if [[ "$diagnostic_active" == 0 ]]; then
      echo 'All currently listed verification-diagnostic requeues have reached terminal status; passed rows are not current failures.'
    else
      echo 'Entries that have not yet passed remain active failed problems and continue to iterate while requeued.'
    fi
    echo
    echo 'Previously flagged verification-defect diagnostic entries:'
    echo
    echo '```text'
    awk -F '\t' -v run="$RUN_ID" \
      '$2 == run && $5 == "verification_defect" && !seen[$3]++ {print $3}' \
      "$CLASSIFICATION_LEDGER" 2>/dev/null \
      | while IFS= read -r job; do
          [[ -f "$RUN_ROOT/jobs/$job/problem.txt" ]] && cat "$RUN_ROOT/jobs/$job/problem.txt"
        done \
      | sort
    echo '```'
    echo
    echo '## Per-Problem Status'
    echo
    echo '| # | Problem | Status | Next turn | Retained sessions |'
    echo '|---:|---|---|---:|---:|'
    find "$RUN_ROOT/jobs" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
      | sort -t- -k1.2n \
      | while IFS= read -r job; do
          local d idx problem status next retained classification
          d="$RUN_ROOT/jobs/$job"
          idx=${job%%-*}
          idx=${idx#j}
          problem=$(<"$d/problem.txt")
          status=$(<"$d/status.txt")
          classification=$(awk -F '\t' -v run="$RUN_ID" -v job="$job" \
            '$2 == run && $3 == job {value=$5} END {print value}' \
            "$CLASSIFICATION_LEDGER" 2>/dev/null || true)
          if [[ -n "$classification" && "$status" != "$classification" ]]; then
            status="$status; $classification diagnostic requeue"
          fi
          next=$(<"$d/next-turn.txt")
          retained=$(wc -l < "$d/sessions.tsv")
          printf '| %d | `%s` | `%s` | %s | %s |\n' "$((idx + 1))" "$problem" "$status" "$next" "$retained"
        done
    echo
    echo '## Evidence'
    echo
    echo "- New verified-pass ledger: \`$AUDIT_ROOT/verified-passes.tsv\`"
    echo "- Pass-audit failures: \`$AUDIT_ROOT/audit-failures.tsv\`"
    echo "- Classifications: \`$CLASSIFICATION_LEDGER\`"
    echo "- Formalization reports: \`$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs/formalization-defects/\`"
    echo "- Verification reports: \`$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs/verification-defects/\`"
    echo "- Retained session ledger: \`$RUN_ROOT/codex-sessions.tsv\`"
  } > "$tmp"

  mv -f "$tmp" "$OUTPUT"
}

if ((DAEMON)); then
  exec 9>"$RUN_ROOT/status-writer.lock"
  flock -n 9 || exit 0
  while :; do
    render_status
    sleep "$SCAN_SECONDS"
  done
else
  render_status
fi
