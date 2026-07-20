#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUMANIZE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/home/zijian/zhengyang-workspace}"
MATH_FLOW_BENCH_ROOT="${MATH_FLOW_BENCH_ROOT:-$WORKSPACE_ROOT/lean/math-flow-bench}"
PUTNAMBENCH_JSONL="${PUTNAMBENCH_JSONL:-$WORKSPACE_ROOT/putnam_bench.jsonl}"
FAILURE_FILE="${FAILURE_FILE:-$WORKSPACE_ROOT/Failed_problems.md}"
BASE_CODEX_HOME="${BASE_CODEX_HOME:-$WORKSPACE_ROOT/.codex}"
OUT_ROOT="${OUT_ROOT:-$WORKSPACE_ROOT/failed-putnambench-humanize-axle-comparator-runs}"
COMPARATOR_TOOLS_ROOT="${COMPARATOR_TOOLS_ROOT:-$WORKSPACE_ROOT/.work/comparator-tools}"
COMPARATOR_BIN="${COMPARATOR_BIN:-$COMPARATOR_TOOLS_ROOT/comparator-current/.lake/build/bin/comparator}"
LEAN4EXPORT_BIN="${LEAN4EXPORT_BIN:-$COMPARATOR_TOOLS_ROOT/lean4export/.lake/build/bin/lean4export}"
LANDRUN_BIN="${LANDRUN_BIN:-$COMPARATOR_TOOLS_ROOT/landrun}"

CODEX_MODEL="${CODEX_MODEL:-gpt-5.5}"
MAX_TURNS="${MAX_TURNS:-50}"
JOBS="${JOBS:-32}"
FALLBACK_JOBS="${FALLBACK_JOBS:-16}"
PROBE_COUNT="${PROBE_COUNT:-4}"
WORKER_TIMEOUT_SECONDS="${WORKER_TIMEOUT_SECONDS:-7200}"
REVIEW_TIMEOUT_SECONDS="${REVIEW_TIMEOUT_SECONDS:-7200}"
CODEX_RATE_RETRIES="${CODEX_RATE_RETRIES:-6}"
REVIEW_INFRA_RETRIES="${REVIEW_INFRA_RETRIES:-0}"
RUN_ID="${RUN_ID:-failed-humanize-axle-comparator-$(date -u +%Y%m%dT%H%M%SZ)}"

DRY_RUN=0
PREPARE_ONLY=0
RESUME_PREPARED=0
RESUME_REVIEW_ONLY=0
RESUME_WORKER_ONLY=0
MAX_PROBLEMS=0
PROBLEMS=()

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run-failed-putnambench.sh [options]

Runs blind PutnamBench proof workers and isolated AXLE-backed reviewers for the
problem IDs listed in Failed_problems.md. Each problem gets at most 50
worker/reviewer turns by default. Solver shell commands are network-blocked.
Workers must self-check with Comparator before review. Reviewers may use the
network only for the required AXLE verification call.

Options:
  --problem ID                 Run only this problem; repeatable.
  --max-problems N             Limit parsed problems. Default: all.
  --jobs N                     Main concurrency after a clean probe. Default: 32.
  --fallback-jobs N            Concurrency after 429/529. Default: 16.
  --probe-count N              One-turn jobs before ramp-up. Default: 4.
  --max-turns N                Worker/reviewer turns per problem. Default: 50.
  --worker-timeout-seconds N   Timeout per worker Codex call. Default: 7200.
  --review-timeout-seconds N   Timeout per reviewer Codex call. Default: 7200.
  --run-id ID                  Override timestamped run ID.
  --failure-file PATH          Markdown problem list.
  --putnambench-jsonl PATH     JSONL containing problem_id and formal_statement.
                              Default: workspace putnam_bench.jsonl.
  --base-codex-home PATH       Codex auth/config source. Default: workspace .codex.
  --out-root PATH              Output parent directory.
  --prepare-only               Build and audit sanitized workspaces; run no models.
  --resume-prepared            Reuse an existing run and launch only jobs whose
                               status is still `prepared`; never rewrite workspaces.
  --resume-review-only         Resume a terminal reviewer failure against the
                               unchanged candidate; never rerun the worker first.
  --resume-worker-only         Resume a terminal worker failure from its current
                               turn without rewriting the prepared workspace.
  --dry-run                    Print selected IDs and checks; write nothing.
  -h, --help                   Show this help.

Environment defaults:
  CODEX_MODEL=gpt-5.5
  MAX_TURNS=50
  JOBS=32
  BASE_CODEX_HOME=/home/zijian/zhengyang-workspace/.codex
  COMPARATOR_TOOLS_ROOT=/home/zijian/zhengyang-workspace/.work/comparator-tools
EOF
}

log() {
  printf '[failed-putnambench-humanize] %s\n' "$*"
}

die() {
  printf '[failed-putnambench-humanize] ERROR: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --problem) PROBLEMS+=("$2"); shift 2 ;;
    --max-problems) MAX_PROBLEMS="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --fallback-jobs) FALLBACK_JOBS="$2"; shift 2 ;;
    --probe-count) PROBE_COUNT="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --worker-timeout-seconds) WORKER_TIMEOUT_SECONDS="$2"; shift 2 ;;
    --review-timeout-seconds) REVIEW_TIMEOUT_SECONDS="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --failure-file) FAILURE_FILE="$2"; shift 2 ;;
    --putnambench-jsonl) PUTNAMBENCH_JSONL="$2"; shift 2 ;;
    --base-codex-home) BASE_CODEX_HOME="$2"; shift 2 ;;
    --out-root) OUT_ROOT="$2"; shift 2 ;;
    --prepare-only) PREPARE_ONLY=1; shift ;;
    --resume-prepared) RESUME_PREPARED=1; shift ;;
    --resume-review-only) RESUME_REVIEW_ONLY=1; shift ;;
    --resume-worker-only) RESUME_WORKER_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

for name in MAX_PROBLEMS JOBS FALLBACK_JOBS PROBE_COUNT MAX_TURNS \
  WORKER_TIMEOUT_SECONDS REVIEW_TIMEOUT_SECONDS CODEX_RATE_RETRIES REVIEW_INFRA_RETRIES; do
  value="${!name}"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be a non-negative integer"
done
[[ "$JOBS" -ge 1 ]] || die "JOBS must be at least 1"
[[ "$FALLBACK_JOBS" -ge 1 ]] || die "FALLBACK_JOBS must be at least 1"
[[ "$MAX_TURNS" -ge 1 ]] || die "MAX_TURNS must be at least 1"
[[ "$WORKER_TIMEOUT_SECONDS" -ge 60 ]] || die "worker timeout must be at least 60"
[[ "$REVIEW_TIMEOUT_SECONDS" -ge 60 ]] || die "review timeout must be at least 60"
[[ "$REVIEW_INFRA_RETRIES" -eq 0 || "$REVIEW_INFRA_RETRIES" -ge 1 ]] || \
  die "REVIEW_INFRA_RETRIES must be 0 (unlimited) or at least 1"
[[ $((PREPARE_ONLY + RESUME_PREPARED + RESUME_REVIEW_ONLY + RESUME_WORKER_ONLY)) -le 1 ]] || \
  die "prepare/resume modes are mutually exclusive"

RUN_ROOT="$OUT_ROOT/$RUN_ID"
CODEX_RUN_HOME="$BASE_CODEX_HOME/failed-putnambench-humanize-axle-comparator/$RUN_ID"
RATE_FLAG="$RUN_ROOT/rate-limit.detected"
RATE_LOG="$RUN_ROOT/rate-limit-events.tsv"
INFRA_FLAG="$RUN_ROOT/transport-failure.detected"
INFRA_LOG="$RUN_ROOT/transport-failures.tsv"
METRICS="$RUN_ROOT/metrics.tsv"
SESSIONS="$RUN_ROOT/codex-sessions.tsv"
LOOP_STAMP="$(date -u +%Y-%m-%d_%H-%M-%S)"
NO_NET_BASH="$RUN_ROOT/no-net-bash"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

module_name() {
  local rest year part
  rest="${1#putnam_}"
  year="${rest%%_*}"
  part="${rest#*_}"
  printf 'Putnam%s%s%s\n' "$year" "$(printf '%s' "${part:0:1}" | tr '[:lower:]' '[:upper:]')" "${part:1}"
}

safe_name() {
  printf '%s' "$1" | tr -c '[:alnum:]_.-' '-'
}

parse_failed_problems() {
  if [[ "${#PROBLEMS[@]}" -gt 0 ]]; then
    printf '%s\n' "${PROBLEMS[@]}"
  else
    rg -o 'putnam_[0-9]{4}_[ab][1-6]' "$FAILURE_FILE" | sort -u
  fi | awk -v max="$MAX_PROBLEMS" 'NF && !seen[$0]++ { print; n++; if (max > 0 && n >= max) exit }'
}

codex_binary() {
  readlink -f "$(command -v codex)"
}

codex_runtime() {
  local binary
  binary="$(codex_binary)"
  (cd "$(dirname "$binary")/.." && pwd)
}

base_url() {
  awk -F= '/^[[:space:]]*base_url[[:space:]]*=/{gsub(/[ "\r]/, "", $2); print $2; exit}' \
    "$BASE_CODEX_HOME/config.toml"
}

write_codex_config() {
  local output="$1"
  local role="$2"
  local network="disabled"
  local provider_url
  [[ "$role" == reviewer ]] && network="enabled"
  provider_url="$(base_url)"
  cat > "$output" <<EOF
model = "$CODEX_MODEL"
review_model = "$CODEX_MODEL"
model_reasoning_effort = "xhigh"
disable_response_storage = true
network_access = "$network"
windows_wsl_setup_acknowledged = true
approvals_reviewer = "user"
service_tier = "default"
EOF

  if [[ -n "$provider_url" ]]; then
    cat >> "$output" <<EOF
model_provider = "OpenAI"

[model_providers.OpenAI]
name = "OpenAI"
base_url = "$provider_url"
wire_api = "responses"
requires_openai_auth = true
EOF
  fi
}

compile_no_net_bash() {
  local source="${NO_NET_BASH}.c"
  cat > "$source" <<'EOF'
#define _GNU_SOURCE
#include <errno.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#define DENY_SYSCALL(nr) \
  BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (nr), 0, 1), \
  BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EACCES)

static void install_no_network_filter(void) {
  struct sock_filter filter[] = {
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
#ifdef __NR_socket
    DENY_SYSCALL(__NR_socket),
#endif
#ifdef __NR_connect
    DENY_SYSCALL(__NR_connect),
#endif
#ifdef __NR_accept
    DENY_SYSCALL(__NR_accept),
#endif
#ifdef __NR_accept4
    DENY_SYSCALL(__NR_accept4),
#endif
#ifdef __NR_bind
    DENY_SYSCALL(__NR_bind),
#endif
#ifdef __NR_listen
    DENY_SYSCALL(__NR_listen),
#endif
#ifdef __NR_socketpair
    DENY_SYSCALL(__NR_socketpair),
#endif
#ifdef __NR_sendto
    DENY_SYSCALL(__NR_sendto),
#endif
#ifdef __NR_recvfrom
    DENY_SYSCALL(__NR_recvfrom),
#endif
#ifdef __NR_sendmsg
    DENY_SYSCALL(__NR_sendmsg),
#endif
#ifdef __NR_recvmsg
    DENY_SYSCALL(__NR_recvmsg),
#endif
#ifdef __NR_getsockname
    DENY_SYSCALL(__NR_getsockname),
#endif
#ifdef __NR_getpeername
    DENY_SYSCALL(__NR_getpeername),
#endif
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
  };
  struct sock_fprog prog = {
    .len = (unsigned short)(sizeof(filter) / sizeof(filter[0])),
    .filter = filter,
  };
  if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) exit(126);
  if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog) != 0) exit(126);
}

int main(int argc, char **argv) {
  (void)argc;
  install_no_network_filter();
  execv("/usr/bin/bash", argv);
  perror("execv(/usr/bin/bash)");
  return 127;
}
EOF
  cc -O2 -Wall -Wextra -o "$NO_NET_BASH" "$source"
}

extract_problem_statement() {
  local problem="$1"
  local output="$2"
  jq -e -j --arg problem "$problem" '
    select(.problem_id == $problem)
    | .formal_statement
    | select(type == "string" and length > 0)
  ' "$PUTNAMBENCH_JSONL" > "$output"
}

write_plan_files() {
  local workspace="$1"
  local problem="$2"
  local module="$3"
  local loop_dir="$workspace/.humanize/rlcr/$LOOP_STAMP"
  mkdir -p "$workspace/docs/humanize" "$loop_dir"
  cat > "$workspace/docs/humanize/active-failed-putnambench-plan.md" <<EOF
# Blind Humanize PutnamBench Repair: $problem

## Goal

Solve the PutnamBench `formal_statement` snapshot in
\`MathFlowBench/$module.lean\` without consulting prior solutions.

## Acceptance Criteria

- AC-1: The theorem statement and docstring match \`source/lean4/src/$problem.lean\`.
- AC-2: The candidate contains no \`sorry\`, \`admit\`, \`axiom\`, or \`native_decide\`.
- AC-3: \`lake env lean MathFlowBench/$module.lean\` succeeds.
- AC-4: \`bash tools/check-with-comparator.sh\` ends with \`Your solution is okay!\`.
- AC-5: The isolated AXLE reviewer returns Boolean \`okay: true\` against the
  JSONL-sourced theorem statement.
  The AXLE verifier may replace only the original \`${problem}_solution := sorry\`
  declaration in the submitted \`formal_statement\` with the candidate's concrete
  solution declaration; this is sanctioned verifier normalization, not a change
  to the theorem statement or the benchmark problem.

## Constraints

- The worker may read only this sanitized workspace and the mounted Mathlib tree.
- The worker must not use the Internet, prior attempts, session archives, or existing solutions.
- The reviewer must not edit the candidate. Its only permitted external network call is AXLE verification.
- Both worker and reviewer use \`$CODEX_MODEL\` with \`xhigh\` reasoning effort.
- Stop after at most $MAX_TURNS worker/reviewer turns.
EOF
  cat > "$loop_dir/goal-tracker.md" <<EOF
# Goal Tracker

## IMMUTABLE SECTION

Ultimate Goal: Produce a complete Lean proof of $problem from the JSONL formal statement.

Acceptance Criteria: AC-1 through AC-5 in the active plan.

## MUTABLE SECTION

Active task: solve and independently verify \`MathFlowBench/$module.lean\`.
Completed: none.
Blocking side issues: none.
Queued side issues: none.
EOF
}

prepare_workspace() {
  local index="$1"
  local problem="$2"
  local module="$3"
  local safe workspace job_dir worker_home reviewer_home
  safe="$(safe_name "$problem")"
  workspace="$RUN_ROOT/workspaces/j${index}-${safe}"
  job_dir="$RUN_ROOT/jobs/j${index}-${safe}"
  worker_home="$CODEX_RUN_HOME/j${index}-${safe}/worker"
  reviewer_home="$CODEX_RUN_HOME/j${index}-${safe}/reviewer"

  mkdir -p "$workspace/MathFlowBench" "$workspace/source/lean4/src" \
    "$workspace/scripts" "$workspace/tools" "$workspace/.lake/build" \
    "$workspace/.lake/packages" "$workspace/home" "$job_dir" \
    "$worker_home" "$reviewer_home"

  cp "$MATH_FLOW_BENCH_ROOT/lakefile.lean" "$workspace/lakefile.lean"
  cp "$MATH_FLOW_BENCH_ROOT/lake-manifest.json" "$workspace/lake-manifest.json"
  cp "$MATH_FLOW_BENCH_ROOT/lean-toolchain" "$workspace/lean-toolchain"
  cp "$MATH_FLOW_BENCH_ROOT/scripts/validate-putnambench-output.py" \
    "$workspace/scripts/validate-putnambench-output.py"
  cp "$HUMANIZE_ROOT/scripts/verify-putnambench-axle.py" \
    "$workspace/tools/verify-putnambench-axle.py"
  cp "$HUMANIZE_ROOT/scripts/check-putnambench-comparator.sh" \
    "$workspace/tools/check-with-comparator.sh"
  chmod +x "$workspace/tools/check-with-comparator.sh"

  extract_problem_statement "$problem" "$workspace/source/lean4/src/$problem.lean"
  cp "$workspace/source/lean4/src/$problem.lean" "$workspace/MathFlowBench/$module.lean"
  cp "$workspace/source/lean4/src/$problem.lean" "$workspace/ComparatorChallenge.lean"
  cat >> "$workspace/lakefile.lean" <<'EOF'

lean_lib ComparatorChallenge
EOF
  python3 - "$workspace/ComparatorChallenge.lean" "$workspace/comparator.json" \
    "$problem" "$module" <<'PY'
import json
from pathlib import Path
import re
import sys

challenge = Path(sys.argv[1]).read_text()
output = Path(sys.argv[2])
problem = sys.argv[3]
module = sys.argv[4]
solution_name = f"{problem}_solution"
has_solution_hole = re.search(
    rf"(?m)^\s*(?:noncomputable\s+)?(?:abbrev|def)\s+{re.escape(solution_name)}\b",
    challenge,
) is not None
config = {
    "challenge_module": "ComparatorChallenge",
    "solution_module": f"MathFlowBench.{module}",
    "theorem_names": [problem],
    "definition_names": [solution_name] if has_solution_hole else [],
    "permitted_axioms": ["propext", "Quot.sound", "Classical.choice"],
    "enable_nanoda": False,
}
output.write_text(json.dumps(config, indent=2) + "\n")
PY
  printf 'import MathFlowBench.%s\n' "$module" > "$workspace/MathFlowBench.lean"
  write_plan_files "$workspace" "$problem" "$module"

  cp "$BASE_CODEX_HOME/auth.json" "$worker_home/auth.json"
  cp "$BASE_CODEX_HOME/auth.json" "$reviewer_home/auth.json"
  write_codex_config "$worker_home/config.toml" worker
  write_codex_config "$reviewer_home/config.toml" reviewer
  mkdir -p "$worker_home/sessions" "$worker_home/shell_snapshots" "$worker_home/tmp"
  mkdir -p "$reviewer_home/sessions" "$reviewer_home/shell_snapshots" "$reviewer_home/tmp"

  git -C "$workspace" init -q
  git -C "$workspace" config user.name "Blind PutnamBench Runner"
  git -C "$workspace" config user.email "runner@localhost"
  git -C "$workspace" add MathFlowBench MathFlowBench.lean ComparatorChallenge.lean \
    comparator.json source scripts tools docs lakefile.lean lake-manifest.json lean-toolchain
  git -C "$workspace" commit -q -m "Initialize sanitized $problem skeleton"

  sha256sum "$workspace/source/lean4/src/$problem.lean" > "$job_dir/original.sha256"
  printf '%s\n' "$problem" > "$job_dir/problem.txt"
  printf '%s\n' "$module" > "$job_dir/module.txt"
  printf '%s\n' "$workspace" > "$job_dir/workspace.txt"
  printf '%s\n' "$worker_home" > "$job_dir/worker-codex-home.txt"
  printf '%s\n' "$reviewer_home" > "$job_dir/reviewer-codex-home.txt"
  printf '1\n' > "$job_dir/next-turn.txt"
  printf 'prepared\n' > "$job_dir/status.txt"
}

write_worker_prompt() {
  local workspace="$1"
  local problem="$2"
  local module="$3"
  local turn="$4"
  local feedback="$5"
  local loop_dir="$workspace/.humanize/rlcr/$LOOP_STAMP"
  local prompt="$loop_dir/round-${turn}-prompt.md"
  if [[ -z "$feedback" && "$turn" -eq 1 && -s "$loop_dir/seed-review.md" ]]; then
    feedback="$loop_dir/seed-review.md"
  fi
  cat > "$prompt" <<EOF
You are the blind Lean proof worker in Humanize round $turn of at most $MAX_TURNS.

Problem: $problem
Only editable proof file: \`MathFlowBench/$module.lean\`
JSONL formal-statement snapshot: \`source/lean4/src/$problem.lean\`

Hard isolation and blindness rules:
- Work only inside this sanitized workspace and mounted Mathlib.
- Never inspect existing solutions, other worktrees, prior experiment outputs,
  Codex session archives, or paths outside this workspace.
- Do not use the Internet, web search, curl, wget, sockets, or network resources.
- Do not launch nested model workers.
- Treat the snapshot as authoritative and preserve it exactly apart from filling proof holes.

Proof rules:
- Preserve the theorem statement, binders, hypotheses, theorem name, and docstring exactly.
- Replace every placeholder, including any \`${problem}_solution\` abbreviation.
- Preserve the original solution declaration kind, type annotation, and location.
  Fill only its right-hand side unless Lean proof support genuinely requires
  additional declarations elsewhere.
- The reducible solution value participates in PutnamBench's expected theorem
  type. Use the simplest canonical form of the derived answer; avoid wrappers,
  helper indirection, or algebraically equivalent operand reorderings when a
  direct expression is available.
- Never use \`sorry\`, \`admit\`, \`axiom\`, \`native_decide\`, unsound declarations, or theorem weakening.
- AXLE rejects \`native_decide\` because it depends on \`Lean.ofReduceBool\` and
  \`Lean.trustCompiler\`. Use kernel-checked alternatives such as \`decide\`,
  \`norm_num\`, \`omega\`, or an explicit proof.
- Never define a solution abbreviation as the theorem's left-hand side or another tautological restatement.
- Edit only \`MathFlowBench/$module.lean\`.

Required local checks:
- \`rg -n '\\b(sorry|admit|axiom|native_decide)\\b' MathFlowBench/$module.lean\`
- \`python3 scripts/validate-putnambench-output.py --problem $problem --putnambench-root source --candidate-root .\`
- \`lake env lean MathFlowBench/$module.lean\`
- \`bash tools/check-with-comparator.sh\`

Comparator self-check (mandatory before handing the proof to the reviewer):
- The wrapper compares the protected \`ComparatorChallenge.lean\` against
  \`MathFlowBench/$module.lean\` using \`comparator.json\`.
- It verifies the exact theorem statement and any solution-definition hole,
  rejects unpermitted axioms, and replays the proof through the Lean kernel.
- Do not edit \`ComparatorChallenge.lean\`, \`comparator.json\`, the Lake files,
  or \`tools/check-with-comparator.sh\`. Fix only the candidate proof.
- A pass must end with both \`Lean default kernel accepts the solution\` and
  \`Your solution is okay!\`. An attempted run or ordinary Lean compilation is
  not a substitute. If it fails, read the diagnostic, repair the candidate,
  and rerun the wrapper until it passes.
- Use the supplied real Landrun-backed wrapper. Do not use fake Landrun or
  bypass Comparator.

Do not run a full \`lake build\`; compile only the target file. Leave the best
useful candidate in place even if this round is incomplete.
EOF
  if [[ -n "$feedback" && -s "$feedback" ]]; then
    cat >> "$prompt" <<EOF

## Previous Independent Review

Read and address this review. The reviewer cannot edit the proof:

EOF
    cat "$feedback" >> "$prompt"
  fi
}

run_comparator_local_check() {
  local workspace="$1"
  unshare --user --map-root-user --mount --net --fork bash -s -- \
    "$workspace" "$MATH_FLOW_BENCH_ROOT/.lake/packages" \
    "$MATH_FLOW_BENCH_ROOT/.venv/elan" "$COMPARATOR_BIN" \
    "$LEAN4EXPORT_BIN" "$LANDRUN_BIN" <<'NSH'
set -Eeuo pipefail
workspace="$1"
packages="$2"
elan_root="$3"
comparator_bin="$4"
lean4export_bin="$5"
landrun_bin="$6"

mount --make-rprivate /
mount --rbind "$packages" "$workspace/.lake/packages"
mount -o remount,ro,bind "$workspace/.lake/packages" 2>/dev/null || true

export ELAN_HOME="$elan_root"
export PATH="$elan_root/bin:$PATH"
COMPARATOR_BIN="$comparator_bin" LEAN4EXPORT_BIN="$lean4export_bin" \
  LANDRUN_BIN="$landrun_bin" bash "$workspace/tools/check-with-comparator.sh"
NSH
}

local_checks() {
  local workspace="$1"
  local problem="$2"
  local module="$3"
  local log_file="$4"
  local code=0
  {
    printf '## forbidden markers\n'
    if rg -n '\b(sorry|admit|axiom|native_decide)\b' "$workspace/MathFlowBench/$module.lean"; then
      printf 'FAIL: forbidden marker found\n'
      code=20
    else
      printf 'PASS\n'
    fi
    printf '\n## statement validator\n'
    if python3 "$workspace/scripts/validate-putnambench-output.py" \
      --problem "$problem" --putnambench-root "$workspace/source" --candidate-root "$workspace"; then
      printf 'PASS\n'
    else
      printf 'FAIL\n'
      [[ "$code" -eq 0 ]] && code=21
    fi
    printf '\n## Lean target compilation\n'
    if (cd "$MATH_FLOW_BENCH_ROOT" && \
      ELAN_HOME="$MATH_FLOW_BENCH_ROOT/.venv/elan" \
      lake env lean "$workspace/MathFlowBench/$module.lean"); then
      printf 'PASS\n'
    else
      printf 'FAIL\n'
      [[ "$code" -eq 0 ]] && code=22
    fi
    printf '\n## Comparator self-check\n'
    if run_comparator_local_check "$workspace"; then
      printf 'PASS\n'
    else
      printf 'FAIL\n'
      [[ "$code" -eq 0 ]] && code=23
    fi
  } > "$log_file" 2>&1
  return "$code"
}

write_summary() {
  local workspace="$1"
  local problem="$2"
  local module="$3"
  local turn="$4"
  local check_code="$5"
  local check_log="$6"
  local worker_final="$7"
  local summary="$workspace/.humanize/rlcr/$LOOP_STAMP/round-${turn}-summary.md"
  cat > "$summary" <<EOF
# Round $turn Worker Summary

Problem: \`$problem\`
Candidate: \`MathFlowBench/$module.lean\`
Local check exit: \`$check_code\`

## Worker Final Message

$(sed -n '1,240p' "$worker_final" 2>/dev/null || true)

## Deterministic Local Checks

\`\`\`
$(sed -n '1,320p' "$check_log" 2>/dev/null || true)
\`\`\`

The runner, not the worker, generated this summary from isolated artifacts.
EOF
}

render_review_prompt() {
  local workspace="$1"
  local problem="$2"
  local module="$3"
  local turn="$4"
  local template="$HUMANIZE_ROOT/prompt-template/codex/regular-review.md"
  local loop_dir="$workspace/.humanize/rlcr/$LOOP_STAMP"
  local output="$loop_dir/round-${turn}-review-prompt.md"
  TEMPLATE="$template" WORKSPACE="$workspace" PROBLEM="$problem" MODULE="$module" \
    TURN="$turn" LOOP_STAMP="$LOOP_STAMP" OUTPUT="$output" python3 - <<'PY'
from pathlib import Path
import os
import subprocess

workspace = Path(os.environ["WORKSPACE"])
problem = os.environ["PROBLEM"]
module = os.environ["MODULE"]
turn = int(os.environ["TURN"])
stamp = os.environ["LOOP_STAMP"]
loop_host = workspace / ".humanize" / "rlcr" / stamp
loop_chroot = Path("/work/.humanize/rlcr") / stamp
summary = (loop_host / f"round-{turn}-summary.md").read_text()
try:
    history = subprocess.run(
        ["git", "-C", str(workspace), "log", "--oneline", "--reverse"],
        check=True, text=True, stdout=subprocess.PIPE,
    ).stdout.strip()
except Exception:
    history = "(git history unavailable)"

values = {
    "CURRENT_ROUND": str(turn),
    "PLAN_FILE": "/work/docs/humanize/active-failed-putnambench-plan.md",
    "PROMPT_FILE": str(loop_chroot / f"round-{turn}-prompt.md"),
    "SUMMARY_CONTENT": summary,
    "GOAL_TRACKER_FILE": str(loop_chroot / "goal-tracker.md"),
    "DOCS_PATH": "/work/docs",
    "GOAL_TRACKER_UPDATE_SECTION": (
        "The goal tracker is runner-managed. You may update its mutable section, "
        "but you must not edit the candidate proof or immutable acceptance criteria."
    ),
    "COMMIT_HISTORY_SECTION": "## Development History\n\n```\n" + history + "\n```",
    "COMPLETED_ITERATIONS": str(turn),
    "LOOP_TIMESTAMP": stamp,
    "PREV_ROUND": str(max(0, turn - 1)),
    "PREV_PREV_ROUND": str(max(0, turn - 2)),
    "AXLE_VERIFIER": "/work/tools/verify-putnambench-axle.py",
    "REVIEW_RESULT_FILE": str(loop_chroot / f"round-{turn}-review-result.md"),
}

text = Path(os.environ["TEMPLATE"]).read_text()
for key, value in values.items():
    text = text.replace("{{" + key + "}}", value)
text = text.replace("<candidate-file>", f"MathFlowBench/{module}.lean")
prefix = f"""# Isolated Blind PutnamBench Reviewer\n\n
You are reviewing `{problem}` in a sanitized filesystem. References to Claude
in the inherited Humanize template mean the blind Codex proof worker.

- Use model gpt-5.5 with xhigh reasoning effort.
- Do not inspect Codex sessions, prior experiments, other worktrees, or existing solutions.
- Do not use web search or any external network resource except the AXLE call
  made by `/work/tools/verify-putnambench-axle.py`.
- The proof file is mounted read-only. Never modify it.
- Compile with `cd /work && lake env lean MathFlowBench/{module}.lean`.
- The original is `/work/source/lean4/src/{problem}.lean` and the verifier is
  configured to use `/work/source/lean4/src` as its originals root.
- AXLE evidence is valid when `/work/tools/verify-putnambench-axle.py` reports
  `okay: true`, even if `formal_statement_solution_patched: true`. That flag
  means the verifier normalized only the original `{problem}_solution := sorry`
  declaration to the candidate's concrete solution declaration so AXLE checks
  the same theorem type. It does not mean the worker changed the benchmark
  theorem statement or formalized a different problem.

"""
Path(os.environ["OUTPUT"]).write_text(prefix + text)
PY
}

codex_error_text() {
  local file="$1"
  if [[ "$file" == *.jsonl ]]; then
    jq -r '
      select(.type == "error" or .type == "turn.failed") |
      .message // .error.message // .item.message // empty
    ' "$file" 2>/dev/null
  else
    cat "$file"
  fi
}

rate_error_in() {
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    if codex_error_text "$file" | rg -qi "(HTTP([[:space:]_-]+status)?[^0-9]{0,20}(429|529)|status(_code)?[\\\"':= ]+(429|529)|too many requests|rate[ _-]*limit|request rate limit|upstream.*overload|overloaded.*(429|529))"; then
      return 0
    fi
  done
  return 1
}

transient_error_in() {
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    if codex_error_text "$file" | rg -qi "(stream disconnected|error sending request|connection (reset|closed|refused)|temporar(il)?y unavailable|timed? out|selected model is at capacity|model[^.\n]{0,40}at capacity|HTTP[^0-9]{0,20}(408|500|502|503|504)|status(_code)?[\\\"':= ]+(408|500|502|503|504))"; then
      return 0
    fi
  done
  return 1
}

record_rate_error() {
  local problem="$1" role="$2" turn="$3" attempt="$4"
  touch "$RATE_FLAG"
  {
    flock 9
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$problem" "$role" "$turn" "$attempt" >> "$RATE_LOG"
  } 9>"$RUN_ROOT/rate.lock"
}

record_transport_failure() {
  local problem="$1" role="$2" turn="$3" attempt="$4" code="$5"
  touch "$INFRA_FLAG"
  {
    flock 9
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$problem" "$role" "$turn" "$attempt" "$code" >> "$INFRA_LOG"
  } 9>"$RUN_ROOT/infra.lock"
}

record_sessions() {
  local job_dir="$1" problem="$2" role="$3" turn="$4" attempt="$5"
  local codex_home="$6" marker="$7" events="$8" final="$9"
  local thread_id session_file
  thread_id="$(jq -r 'select(.type == "thread.started") | .thread_id // empty' "$events" 2>/dev/null | head -n 1)"
  [[ -n "$thread_id" ]] || thread_id="$(rg -o 'session id: [0-9a-f-]+' "$events" 2>/dev/null | head -n1 | awk '{print $3}')"
  [[ -n "$thread_id" ]] || thread_id="unknown"

  mapfile -t new_sessions < <(find "$codex_home/sessions" -type f -name '*.jsonl' -newer "$marker" -print 2>/dev/null | sort)
  if [[ "${#new_sessions[@]}" -eq 0 ]]; then
    new_sessions=("")
  fi
  for session_file in "${new_sessions[@]}"; do
    {
      flock 9
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$problem" "$role" "$turn" "$attempt" \
        "$thread_id" "$events" "$final" "$session_file" >> "$SESSIONS"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$role" "$turn" "$attempt" \
        "$thread_id" "$events" "$session_file" >> "$job_dir/sessions.tsv"
    } 9>"$RUN_ROOT/sessions.lock"
  done
}

run_codex_namespace_once() {
  local role="$1" workspace="$2" codex_home="$3" prompt_rel="$4"
  local events="$5" stderr_log="$6" final_rel="$7" nsroot="$8"
  local module="$9" timeout_seconds="${10}"
  local runtime network_mode
  runtime="$(codex_runtime)"
  network_mode="disabled"
  [[ "$role" == reviewer ]] && network_mode="enabled"

  unshare --user --map-root-user --mount --fork --pid --mount-proc bash -s -- \
    "$role" "$workspace" "$codex_home" "$prompt_rel" "$final_rel" "$nsroot" \
    "$NO_NET_BASH" "$MATH_FLOW_BENCH_ROOT/.lake/packages" \
    "$MATH_FLOW_BENCH_ROOT/.venv/elan" "$runtime" "$module" \
    "$timeout_seconds" "$CODEX_MODEL" "$network_mode" \
    "$COMPARATOR_BIN" "$LEAN4EXPORT_BIN" "$LANDRUN_BIN" \
    > "$events" 2> "$stderr_log" <<'NSH'
set -Eeuo pipefail
role="$1"
workspace="$2"
codex_home="$3"
prompt_rel="$4"
final_rel="$5"
nsroot="$6"
no_net_bash="$7"
packages="$8"
elan_root="$9"
runtime="${10}"
module="${11}"
timeout_seconds="${12}"
model="${13}"
network_mode="${14}"
comparator_bin="${15}"
lean4export_bin="${16}"
landrun_bin="${17}"

mkdir -p "$nsroot"/{bin,usr,lib,lib64,etc,dev,proc,run,tmp,work,home/codex,codex-home,codex-runtime,elan,comparator-tools}
mount --make-rprivate /
for directory in usr lib lib64 etc dev; do
  if [[ -e "/$directory" ]]; then
    mount --rbind "/$directory" "$nsroot/$directory"
    mount -o remount,ro,bind "$nsroot/$directory" 2>/dev/null || true
  fi
done
# /etc/resolv.conf is a symlink into this runtime directory on systemd hosts.
# Keep the resolver configuration visible without exposing the rest of /run.
if [[ -d /run/systemd/resolve ]]; then
  mkdir -p "$nsroot/run/systemd/resolve"
  mount --rbind /run/systemd/resolve "$nsroot/run/systemd/resolve"
  mount -o remount,ro,bind "$nsroot/run/systemd/resolve" 2>/dev/null || true
fi
if [[ "$role" == worker ]]; then
  install -m 0755 "$no_net_bash" "$nsroot/bin/bash"
else
  ln -sfn /usr/bin/bash "$nsroot/bin/bash"
fi
ln -sfn bash "$nsroot/bin/sh"
mount -t proc proc "$nsroot/proc"
mount --rbind "$workspace" "$nsroot/work"
mount --rbind "$packages" "$nsroot/work/.lake/packages"
mount -o remount,ro,bind "$nsroot/work/.lake/packages" 2>/dev/null || true
mount --rbind "$elan_root" "$nsroot/elan"
mount -o remount,ro,bind "$nsroot/elan" 2>/dev/null || true
mount --rbind "$runtime" "$nsroot/codex-runtime"
mount -o remount,ro,bind "$nsroot/codex-runtime" 2>/dev/null || true
mount --rbind "$codex_home" "$nsroot/codex-home"

for tool_spec in \
  "$comparator_bin:comparator" \
  "$lean4export_bin:lean4export" \
  "$landrun_bin:landrun"; do
  source_path="${tool_spec%%:*}"
  target_name="${tool_spec#*:}"
  touch "$nsroot/comparator-tools/$target_name"
  mount --bind "$source_path" "$nsroot/comparator-tools/$target_name"
  mount -o remount,ro,bind "$nsroot/comparator-tools/$target_name"
done

for protected_file in \
  ComparatorChallenge.lean comparator.json lakefile.lean lake-manifest.json \
  lean-toolchain tools/check-with-comparator.sh; do
  mount --bind "$workspace/$protected_file" "$nsroot/work/$protected_file"
  mount -o remount,ro,bind "$nsroot/work/$protected_file"
done
mount --bind "$workspace/source" "$nsroot/work/source"
mount -o remount,ro,bind "$nsroot/work/source"

if [[ "$role" == reviewer ]]; then
  candidate="$nsroot/work/MathFlowBench/$module.lean"
  mount --bind "$workspace/MathFlowBench/$module.lean" "$candidate"
  mount -o remount,ro,bind "$candidate"
fi

env_args=(
  HOME=/home/codex
  USER=codex
  CODEX_HOME=/codex-home
  ELAN_HOME=/elan
  PATH=/elan/bin:/codex-runtime/codex-path:/usr/bin:/bin
  TERM=dumb
  PUTNAMBENCH_ORIGINALS_ROOT=/work/source/lean4/src
  PYTHONDONTWRITEBYTECODE=1
)

chroot "$nsroot" /usr/bin/env -i "${env_args[@]}" \
  timeout --foreground "$timeout_seconds" \
    /codex-runtime/bin/codex --ask-for-approval never exec \
      --cd /work --skip-git-repo-check --model "$model" \
      --sandbox danger-full-access --json \
      --disable browser_use \
      --disable browser_use_external \
      --disable browser_use_full_cdp_access \
      --disable in_app_browser \
      --disable search_tool \
      --disable standalone_web_search \
      --disable hooks \
      -c model_reasoning_effort='"xhigh"' \
      -c network_access="\"$network_mode\"" \
      -c disable_response_storage=true \
      -c shell_environment_policy.inherit='"all"' \
      -o "/work/$final_rel" \
      - < "$workspace/$prompt_rel"
NSH
}

run_codex_with_retries() {
  local role="$1" workspace="$2" codex_home="$3" prompt_rel="$4"
  local final_rel="$5" job_dir="$6" problem="$7" module="$8" turn="$9"
  local timeout_seconds="${10}"
  local attempt events stderr_log marker code delay nsroot
  for ((attempt = 1; attempt <= CODEX_RATE_RETRIES + 1; attempt++)); do
    events="$job_dir/round-${turn}-${role}-attempt-${attempt}.events.jsonl"
    stderr_log="$job_dir/round-${turn}-${role}-attempt-${attempt}.stderr.log"
    marker="$job_dir/round-${turn}-${role}-attempt-${attempt}.session-marker"
    nsroot="$RUN_ROOT/nsroot/$(basename "$job_dir")-$role"
    touch "$marker"
    code=0
    run_codex_namespace_once "$role" "$workspace" "$codex_home" "$prompt_rel" \
      "$events" "$stderr_log" "$final_rel" "$nsroot" "$module" "$timeout_seconds" || code="$?"
    record_sessions "$job_dir" "$problem" "$role" "$turn" "$attempt" \
      "$codex_home" "$marker" "$events" "$workspace/$final_rel"
    if rate_error_in "$events" "$stderr_log"; then
      record_rate_error "$problem" "$role" "$turn" "$attempt"
      if [[ "$attempt" -le "$CODEX_RATE_RETRIES" ]]; then
        delay=$((30 * (2 ** (attempt - 1))))
        [[ "$delay" -gt 600 ]] && delay=600
        log "$problem $role turn $turn hit 429/529; retrying in ${delay}s"
        sleep "$delay"
        continue
      fi
      return 75
    fi
    if [[ "$code" -ne 0 ]] && transient_error_in "$events" "$stderr_log"; then
      if [[ "$attempt" -le "$CODEX_RATE_RETRIES" ]]; then
        delay=$((30 * (2 ** (attempt - 1))))
        [[ "$delay" -gt 600 ]] && delay=600
        log "$problem $role turn $turn hit a transient transport failure; retrying in ${delay}s"
        sleep "$delay"
        continue
      fi
      record_transport_failure "$problem" "$role" "$turn" "$attempt" "$code"
      return "$code"
    fi
    if [[ "$code" -ne 0 ]]; then
      record_transport_failure "$problem" "$role" "$turn" "$attempt" "$code"
    fi
    return "$code"
  done
  return 75
}

commit_candidate_round() {
  local workspace="$1" problem="$2" turn="$3"
  if [[ -n "$(git -C "$workspace" status --porcelain -- MathFlowBench)" ]]; then
    git -C "$workspace" add MathFlowBench
    git -C "$workspace" commit -q -m "Round $turn candidate for $problem"
  fi
}

review_is_complete() {
  local workspace="$1" turn="$2"
  local loop_dir="$workspace/.humanize/rlcr/$LOOP_STAMP"
  local result="$loop_dir/round-${turn}-review-result.md"
  local axle="$result.axle.json"
  [[ -s "$result" ]] || return 1
  [[ "$(awk 'NF{line=$0} END{print line}' "$result")" == "COMPLETE" ]] || return 1
  jq -e '.all_okay == true and (.results | length > 0) and all(.results[]; .okay == true)' \
    "$axle" >/dev/null 2>&1
}

axle_infrastructure_failed() {
  local workspace="$1" turn="$2"
  local result="$workspace/.humanize/rlcr/$LOOP_STAMP/round-${turn}-review-result.md"
  local axle="$result.axle.json"
  [[ -f "$axle" ]] || return 0
  jq -e 'any(.results[]?; .status == "api_error")' "$axle" >/dev/null 2>&1
}

run_job() {
  local index="$1" problem="$2" end_turn="$3"
  local module safe workspace job_dir worker_home reviewer_home loop_dir
  local turn feedback worker_prompt_rel worker_final_rel check_log check_code
  local review_prompt_rel review_final_rel review_result review_try code status start end
  module="$(module_name "$problem")"
  safe="$(safe_name "$problem")"
  workspace="$RUN_ROOT/workspaces/j${index}-${safe}"
  job_dir="$RUN_ROOT/jobs/j${index}-${safe}"
  worker_home="$CODEX_RUN_HOME/j${index}-${safe}/worker"
  reviewer_home="$CODEX_RUN_HOME/j${index}-${safe}/reviewer"
  loop_dir="$workspace/.humanize/rlcr/$LOOP_STAMP"

  if [[ "$(cat "$job_dir/status.txt" 2>/dev/null || true)" == passed ]]; then
    return 0
  fi
  turn="$(cat "$job_dir/next-turn.txt")"
  feedback=""
  if [[ "$turn" -gt 1 ]]; then
    feedback="$loop_dir/round-$((turn - 1))-review-result.md"
  fi
  start="$(date +%s)"
  status="pending"

  while [[ "$turn" -le "$end_turn" && "$turn" -le "$MAX_TURNS" ]]; do
    printf 'worker_turn_%s\n' "$turn" > "$job_dir/status.txt"
    write_worker_prompt "$workspace" "$problem" "$module" "$turn" "$feedback"
    worker_prompt_rel=".humanize/rlcr/$LOOP_STAMP/round-${turn}-prompt.md"
    worker_final_rel=".humanize/rlcr/$LOOP_STAMP/round-${turn}-worker-final.md"
    code=0
    run_codex_with_retries worker "$workspace" "$worker_home" "$worker_prompt_rel" \
      "$worker_final_rel" "$job_dir" "$problem" "$module" "$turn" \
      "$WORKER_TIMEOUT_SECONDS" || code="$?"
    if [[ "$code" -eq 75 ]]; then
      status="worker_rate_limited"
      break
    fi
    if [[ "$code" -eq 124 ]]; then
      status="worker_timeout"
      break
    elif [[ "$code" -ne 0 ]]; then
      status="worker_transport_failed"
      break
    fi

    commit_candidate_round "$workspace" "$problem" "$turn"
    check_log="$job_dir/round-${turn}-local-checks.log"
    check_code=0
    local_checks "$workspace" "$problem" "$module" "$check_log" || check_code="$?"
    write_summary "$workspace" "$problem" "$module" "$turn" "$check_code" \
      "$check_log" "$workspace/$worker_final_rel"

    # The reviewer only evaluates candidates that have passed every deterministic
    # local gate, including the real Landrun-backed Comparator replay.
    if [[ "$check_code" -ne 0 ]]; then
      feedback="$loop_dir/round-${turn}-summary.md"
      turn=$((turn + 1))
      printf '%s\n' "$turn" > "$job_dir/next-turn.txt"
      status="pending"
      continue
    fi

    printf 'review_turn_%s\n' "$turn" > "$job_dir/status.txt"
    render_review_prompt "$workspace" "$problem" "$module" "$turn"
    review_prompt_rel=".humanize/rlcr/$LOOP_STAMP/round-${turn}-review-prompt.md"
    review_final_rel=".humanize/rlcr/$LOOP_STAMP/round-${turn}-reviewer-final.md"
    review_result="$loop_dir/round-${turn}-review-result.md"
    review_try=1
    while [[ "$REVIEW_INFRA_RETRIES" -eq 0 || "$review_try" -le "$REVIEW_INFRA_RETRIES" ]]; do
      code=0
      run_codex_with_retries reviewer "$workspace" "$reviewer_home" "$review_prompt_rel" \
        "$review_final_rel" "$job_dir" "$problem" "$module" "$turn" \
        "$REVIEW_TIMEOUT_SECONDS" || code="$?"
      if [[ ! -s "$review_result" && -s "$workspace/$review_final_rel" ]]; then
        cp "$workspace/$review_final_rel" "$review_result"
      fi
      if [[ "$code" -eq 75 ]]; then
        status="reviewer_rate_limited"
        break 2
      fi
      if [[ "$code" -eq 124 ]]; then
        status="reviewer_timeout"
        break 2
      elif [[ "$code" -ne 0 ]]; then
        status="reviewer_transport_failed"
        break 2
      fi
      if axle_infrastructure_failed "$workspace" "$turn"; then
        if [[ "$REVIEW_INFRA_RETRIES" -eq 0 || "$review_try" -lt "$REVIEW_INFRA_RETRIES" ]]; then
          local review_delay=$((60 * review_try))
          [[ "$review_delay" -gt 600 ]] && review_delay=600
          log "$problem reviewer turn $turn has unavailable AXLE result; retrying review"
          sleep "$review_delay"
          review_try=$((review_try + 1))
          continue
        fi
        status="review_infrastructure_failed"
        break 2
      fi
      break
    done

    if [[ "$check_code" -eq 0 ]] && review_is_complete "$workspace" "$turn"; then
      status="passed"
      printf 'passed\n' > "$job_dir/status.txt"
      printf '%s\n' "$turn" > "$job_dir/completed-turn.txt"
      sha256sum "$workspace/MathFlowBench/$module.lean" > "$job_dir/candidate.sha256"
      break
    fi

    feedback="$review_result"
    turn=$((turn + 1))
    printf '%s\n' "$turn" > "$job_dir/next-turn.txt"
    status="pending"
  done

  if [[ "$status" == pending && "$turn" -gt "$MAX_TURNS" ]]; then
    status="max_turns_reached"
  fi
  printf '%s\n' "$status" > "$job_dir/status.txt"
  end="$(date +%s)"
  {
    flock 9
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RUN_ID" "j${index}-${safe}" \
      "$problem" "$module" "$status" "$turn" "$((end - start))" >> "$METRICS"
  } 9>"$RUN_ROOT/metrics.lock"
  [[ "$status" == passed || "$status" == pending ]]
}

resume_worker_job() {
  local problem="$1"
  local safe job_dir job_name index current_status
  safe="$(safe_name "$problem")"
  job_dir="$(find "$RUN_ROOT/jobs" -mindepth 1 -maxdepth 1 -type d \
    -name "*-$safe" -print -quit)"
  [[ -n "$job_dir" ]] || die "worker recovery job not found for $problem"
  job_name="$(basename "$job_dir")"
  index="${job_name%%-*}"
  index="${index#j}"
  current_status="$(head -1 "$job_dir/status.txt" 2>/dev/null || true)"
  case "$current_status" in
    worker_rate_limited|worker_timeout|worker_transport_failed)
      ;;
    *) die "$problem is not in a recoverable worker state: $current_status" ;;
  esac

  log "worker-only recovery for $problem from turn $(cat "$job_dir/next-turn.txt")"
  run_job "$index" "$problem" "$MAX_TURNS"
}

resume_review_job() {
  local problem="$1"
  local safe module job_dir job_name index workspace reviewer_home loop_dir turn
  local current_status review_prompt_rel review_final_rel review_result review_try
  local review_delay code status check_log check_code start end
  safe="$(safe_name "$problem")"
  module="$(module_name "$problem")"
  job_dir="$(find "$RUN_ROOT/jobs" -mindepth 1 -maxdepth 1 -type d \
    -name "*-$safe" -print -quit)"
  [[ -n "$job_dir" ]] || die "review recovery job not found for $problem"
  job_name="$(basename "$job_dir")"
  index="${job_name%%-*}"
  index="${index#j}"
  workspace="$RUN_ROOT/workspaces/$job_name"
  reviewer_home="$CODEX_RUN_HOME/$job_name/reviewer"
  loop_dir="$workspace/.humanize/rlcr/$LOOP_STAMP"
  current_status="$(head -1 "$job_dir/status.txt" 2>/dev/null || true)"
  case "$current_status" in
    review_infrastructure_failed|reviewer_timeout|reviewer_transport_failed|reviewer_rate_limited)
      ;;
    *) die "$problem is not in a recoverable reviewer state: $current_status" ;;
  esac

  turn="$(cat "$job_dir/next-turn.txt")"
  review_prompt_rel=".humanize/rlcr/$LOOP_STAMP/round-${turn}-review-prompt.md"
  review_final_rel=".humanize/rlcr/$LOOP_STAMP/round-${turn}-reviewer-final.md"
  review_result="$loop_dir/round-${turn}-review-result.md"
  [[ -s "$workspace/$review_prompt_rel" ]] || \
    die "review recovery prompt missing for $problem turn $turn"
  [[ -s "$loop_dir/round-${turn}-summary.md" ]] || \
    die "review recovery summary missing for $problem turn $turn"

  # Revalidate before a recovered reviewer is launched. Older runner versions
  # could enter review recovery even when the local Comparator gate had failed.
  check_log="$job_dir/round-${turn}-local-checks.log"
  check_code=0
  local_checks "$workspace" "$problem" "$module" "$check_log" || check_code="$?"
  write_summary "$workspace" "$problem" "$module" "$turn" "$check_code" \
    "$check_log" "$loop_dir/round-${turn}-worker-final.md"
  if [[ "$check_code" -ne 0 ]]; then
    turn=$((turn + 1))
    printf '%s\n' "$turn" > "$job_dir/next-turn.txt"
    log "$problem failed the local gate during review recovery; resuming worker turn $turn"
    run_job "$index" "$problem" "$MAX_TURNS"
    return $?
  fi

  start="$(date +%s)"
  status="pending"
  review_try=1
  printf 'review_turn_%s\n' "$turn" > "$job_dir/status.txt"
  while [[ "$REVIEW_INFRA_RETRIES" -eq 0 || "$review_try" -le "$REVIEW_INFRA_RETRIES" ]]; do
    code=0
    run_codex_with_retries reviewer "$workspace" "$reviewer_home" "$review_prompt_rel" \
      "$review_final_rel" "$job_dir" "$problem" "$module" "$turn" \
      "$REVIEW_TIMEOUT_SECONDS" || code="$?"
    if [[ ! -s "$review_result" && -s "$workspace/$review_final_rel" ]]; then
      cp "$workspace/$review_final_rel" "$review_result"
    fi
    if [[ "$code" -eq 75 ]]; then
      status="reviewer_rate_limited"
      break
    elif [[ "$code" -eq 124 ]]; then
      status="reviewer_timeout"
      break
    elif [[ "$code" -ne 0 ]]; then
      status="reviewer_transport_failed"
      break
    fi
    if axle_infrastructure_failed "$workspace" "$turn"; then
      if [[ "$REVIEW_INFRA_RETRIES" -eq 0 || "$review_try" -lt "$REVIEW_INFRA_RETRIES" ]]; then
        review_delay=$((60 * review_try))
        [[ "$review_delay" -gt 600 ]] && review_delay=600
        log "$problem reviewer turn $turn remains unavailable; retrying unchanged candidate"
        sleep "$review_delay"
        review_try=$((review_try + 1))
        continue
      fi
      status="review_infrastructure_failed"
    fi
    break
  done

  if [[ "$status" != pending ]]; then
    printf '%s\n' "$status" > "$job_dir/status.txt"
    return 1
  fi

  check_log="$job_dir/round-${turn}-local-checks.log"
  check_code=0
  local_checks "$workspace" "$problem" "$module" "$check_log" || check_code="$?"
  if [[ "$check_code" -eq 0 ]] && review_is_complete "$workspace" "$turn"; then
    status="passed"
    printf 'passed\n' > "$job_dir/status.txt"
    printf '%s\n' "$turn" > "$job_dir/completed-turn.txt"
    sha256sum "$workspace/MathFlowBench/$module.lean" > "$job_dir/candidate.sha256"
    end="$(date +%s)"
    {
      flock 9
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RUN_ID" "$job_name" \
        "$problem" "$module" "$status" "$turn" "$((end - start))" >> "$METRICS"
    } 9>"$RUN_ROOT/metrics.lock"
    return 0
  fi

  turn=$((turn + 1))
  printf '%s\n' "$turn" > "$job_dir/next-turn.txt"
  log "$problem review recovery returned a Boolean rejection; resuming worker turn $turn"
  run_job "$index" "$problem" "$MAX_TURNS"
}

write_run_manifest() {
  local count="$1"
  cat > "$RUN_ROOT/RUN.md" <<EOF
# Failed PutnamBench Humanize + Comparator + AXLE Run

- Run ID: \`$RUN_ID\`
- Failure source: \`$FAILURE_FILE\`
- Problems: $count
- Problem source: \`$PUTNAMBENCH_JSONL\`
- Problem source SHA-256: \`$(sha256sum "$PUTNAMBENCH_JSONL" | awk '{print $1}')\`
- Statement field: \`formal_statement\` selected by exact \`problem_id\`
- Worker/reviewer model: \`$CODEX_MODEL\`
- Reasoning effort: \`xhigh\`
- Maximum turns: $MAX_TURNS
- Requested main concurrency: $JOBS
- Rate-limited fallback concurrency: $FALLBACK_JOBS
- Base Codex home: \`$BASE_CODEX_HOME\`
- Per-job Codex homes: \`$CODEX_RUN_HOME\`
- Solver network: blocked by seccomp for every tool shell
- Worker self-check: current Comparator, target-version lean4export, and real Landrun
- Reviewer network: permitted only for the prompted AXLE verifier call
- Existing solutions: not mounted into either model namespace

All prompts, event streams, final messages, session paths, reviews, compilation
logs, Comparator output, AXLE JSON, hashes, and status files are retained under this run directory.
EOF
}

main() {
  local command selected problem index missing active limit total probe_n
  for command in awk bash cc chroot codex date find flock git jq lake mount python3 rg sha256sum timeout unshare; do
    need_cmd "$command"
  done
  [[ -f "$FAILURE_FILE" ]] || die "failure file not found: $FAILURE_FILE"
  [[ -f "$PUTNAMBENCH_JSONL" ]] || die "PutnamBench JSONL not found: $PUTNAMBENCH_JSONL"
  [[ -f "$BASE_CODEX_HOME/auth.json" ]] || die "Codex auth missing: $BASE_CODEX_HOME/auth.json"
  [[ -f "$BASE_CODEX_HOME/config.toml" ]] || die "Codex config missing: $BASE_CODEX_HOME/config.toml"
  [[ -d "$MATH_FLOW_BENCH_ROOT/.lake/packages" ]] || die "Mathlib packages missing"
  [[ -f "$HUMANIZE_ROOT/prompt-template/codex/regular-review.md" ]] || die "new review template missing"
  [[ -x "$COMPARATOR_BIN" ]] || die "Comparator binary missing or not executable: $COMPARATOR_BIN"
  [[ -x "$LEAN4EXPORT_BIN" ]] || die "lean4export binary missing or not executable: $LEAN4EXPORT_BIN"
  [[ -x "$LANDRUN_BIN" ]] || die "Landrun binary missing or not executable: $LANDRUN_BIN"
  [[ -x "$HUMANIZE_ROOT/scripts/check-putnambench-comparator.sh" ]] || \
    die "Comparator wrapper missing or not executable"
  [[ "$CODEX_MODEL" == "gpt-5.5" ]] || die "this run requires CODEX_MODEL=gpt-5.5"
  mapfile -t selected < <(parse_failed_problems)
  [[ "${#selected[@]}" -gt 0 ]] || die "no failed problems parsed"
  missing=0
  for problem in "${selected[@]}"; do
    if ! [[ "$problem" =~ ^putnam_[0-9]{4}_[ab][1-6]$ ]]; then
      printf 'invalid problem id: %s\n' "$problem" >&2
      missing=$((missing + 1))
    elif [[ "$(jq -r --arg problem "$problem" '
        select(.problem_id == $problem and (.formal_statement | type) == "string" and
          (.formal_statement | length) > 0) | .problem_id
      ' "$PUTNAMBENCH_JSONL" | wc -l)" -ne 1 ]]; then
      printf 'expected exactly one nonempty JSONL formal_statement: %s\n' "$problem" >&2
      missing=$((missing + 1))
    fi
  done
  [[ "$missing" -eq 0 ]] || die "$missing selected JSONL problems are unavailable or duplicated"

  log "run id: $RUN_ID"
  log "selected problems: ${#selected[@]}"
  log "model: $CODEX_MODEL; effort: xhigh; max turns: $MAX_TURNS"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%s\n' "${selected[@]}"
    return 0
  fi

  if [[ "$RESUME_WORKER_ONLY" -eq 1 ]]; then
    local existing_stamp
    [[ "${#selected[@]}" -eq 1 ]] || die "worker-only recovery requires exactly one problem"
    [[ -d "$RUN_ROOT/jobs" && -d "$RUN_ROOT/workspaces" ]] || \
      die "cannot recover worker in missing run: $RUN_ROOT"
    existing_stamp="$(find "$RUN_ROOT/workspaces" -mindepth 4 -maxdepth 4 \
      -type d -path '*/.humanize/rlcr/*' -printf '%f\n' | sort -u | head -n 1)"
    [[ -n "$existing_stamp" ]] || die "cannot locate existing Humanize loop stamp"
    LOOP_STAMP="$existing_stamp"
    log "worker-only recovery for $RUN_ID using loop $LOOP_STAMP"
    resume_worker_job "${selected[0]}"
    return 0
  fi

  if [[ "$RESUME_REVIEW_ONLY" -eq 1 ]]; then
    local existing_stamp
    [[ "${#selected[@]}" -eq 1 ]] || die "review-only recovery requires exactly one problem"
    [[ -d "$RUN_ROOT/jobs" && -d "$RUN_ROOT/workspaces" ]] || \
      die "cannot recover review in missing run: $RUN_ROOT"
    existing_stamp="$(find "$RUN_ROOT/workspaces" -mindepth 4 -maxdepth 4 \
      -type d -path '*/.humanize/rlcr/*' -printf '%f\n' | sort -u | head -n 1)"
    [[ -n "$existing_stamp" ]] || die "cannot locate existing Humanize loop stamp"
    LOOP_STAMP="$existing_stamp"
    log "review-only recovery for $RUN_ID using loop $LOOP_STAMP"
    resume_review_job "${selected[0]}"
    return 0
  fi

  if [[ "$RESUME_PREPARED" -eq 1 ]]; then
    local existing_stamp status_file job_dir job_name pid
    local -a resume_pids=()
    [[ -d "$RUN_ROOT/jobs" && -d "$RUN_ROOT/workspaces" ]] || \
      die "cannot resume missing run: $RUN_ROOT"
    existing_stamp="$(find "$RUN_ROOT/workspaces" -mindepth 4 -maxdepth 4 \
      -type d -path '*/.humanize/rlcr/*' -printf '%f\n' | sort -u | head -n 1)"
    [[ -n "$existing_stamp" ]] || die "cannot locate existing Humanize loop stamp"
    LOOP_STAMP="$existing_stamp"
    log "resume-prepared for run $RUN_ID using loop $LOOP_STAMP"
    active=0
    for problem in "${selected[@]}"; do
      job_dir="$(find "$RUN_ROOT/jobs" -mindepth 1 -maxdepth 1 -type d \
        -name "*-$(safe_name "$problem")" -print -quit)"
      [[ -n "$job_dir" ]] || die "prepared job not found for $problem"
      job_name="$(basename "$job_dir")"
      index="${job_name%%-*}"
      index="${index#j}"
      status_file="$job_dir/status.txt"
      if [[ "$(cat "$status_file" 2>/dev/null || true)" == prepared ]]; then
        while [[ "$(find "$RUN_ROOT/jobs" -name status.txt -type f -exec cat {} + 2>/dev/null | \
            awk '/^(worker_turn_|review_turn_)/ { n++ } END { print n + 0 }')" -ge "$JOBS" ]]; do
          sleep 5
        done
        run_job "$index" "$problem" "$MAX_TURNS" &
        resume_pids+=("$!")
        active=$((active + 1))
        sleep 0.2
      fi
    done
    log "resume-prepared launched $active jobs"
    for pid in "${resume_pids[@]}"; do
      wait "$pid" || true
    done
    log "resume-prepared jobs finished: $RUN_ROOT"
    return 0
  fi

  mkdir -p "$RUN_ROOT"/{jobs,workspaces,nsroot} "$CODEX_RUN_HOME"
  printf 'timestamp\tproblem\trole\tturn\tattempt\n' > "$RATE_LOG"
  printf 'timestamp\tproblem\trole\tturn\tattempt\texit_code\n' > "$INFRA_LOG"
  printf 'timestamp\tproblem\trole\tturn\tattempt\tthread_id\tevents\tfinal\tsession_file\n' > "$SESSIONS"
  printf 'timestamp\trun_id\tjob\tproblem\tmodule\tstatus\tturn\telapsed_seconds\n' > "$METRICS"
  write_run_manifest "${#selected[@]}"
  compile_no_net_bash

  index=0
  for problem in "${selected[@]}"; do
    prepare_workspace "$index" "$problem" "$(module_name "$problem")"
    index=$((index + 1))
  done
  log "prepared and provenance-audited ${#selected[@]} sanitized workspaces"
  if [[ "$PREPARE_ONLY" -eq 1 ]]; then
    log "prepare-only complete: $RUN_ROOT"
    return 0
  fi

  probe_n="$PROBE_COUNT"
  [[ "$probe_n" -gt "${#selected[@]}" ]] && probe_n="${#selected[@]}"
  log "starting $probe_n one-turn probe jobs"
  active=0
  for ((index = 0; index < probe_n; index++)); do
    run_job "$index" "${selected[$index]}" 1 &
    active=$((active + 1))
  done
  while [[ "$active" -gt 0 ]]; do
    wait -n || true
    active=$((active - 1))
  done

  if [[ -f "$RATE_FLAG" ]]; then
    limit="$FALLBACK_JOBS"
    log "probe detected HTTP 429/529; using fallback concurrency $limit"
  elif [[ -f "$INFRA_FLAG" ]]; then
    limit="$FALLBACK_JOBS"
    log "probe had transport failures; withholding 64-worker ramp and using $limit"
  else
    limit="$JOBS"
    log "probe clean: launching up to $limit parallel problem workers"
  fi
  printf '%s\n' "$limit" > "$RUN_ROOT/selected-concurrency.txt"

  total="${#selected[@]}"
  active=0
  index=0
  while [[ "$index" -lt "$total" || "$active" -gt 0 ]]; do
    if [[ -f "$RATE_FLAG" ]]; then
      limit="$FALLBACK_JOBS"
    fi
    while [[ "$index" -lt "$total" && "$active" -lt "$limit" ]]; do
      run_job "$index" "${selected[$index]}" "$MAX_TURNS" &
      index=$((index + 1))
      active=$((active + 1))
      sleep 0.2
    done
    if [[ "$active" -gt 0 ]]; then
      wait -n || true
      active=$((active - 1))
    fi
  done
  log "all jobs finished: $RUN_ROOT"
}

main "$@"
