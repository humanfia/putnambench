# Humanfia at PutnamBench (99.7%) Acc

Result: **670 of the 672 PutnamBench problems solved** with independently **Lean 4 verified** proofs, ranking #1 on [the offical leaderboard](https://trishullab.github.io/PutnamBench/leaderboard.html).

| Metric | Value |
| --- | --- |
| Benchmark | PutnamBench, all 672 formal statements |
| Verified proofs | **670** |
| Unresolved | 2 |
| Pass rate | **99.7%** |
| Worker / reviewer model | `gpt-5.5`, reasoning effort `xhigh` |
| Lean | `leanprover/lean4:v4.27.0`, Mathlib `a3a10db0` |
| Acceptance | Lean kernel + Comparator + AXLE, all required to agree |

This results has been verified by the putnambench team, and now ranks #1 on [the offical leaderboard](https://trishullab.github.io/PutnamBench/leaderboard.html). A problem counts as solved only when the produced Lean file passes *every* gate
in [Verification Method](#verification-method). Candidates that fail any gate are
retained for inspection but are never counted or labeled as proofs. The unresolved
IDs for a given run are written to `unresolved.txt` in that run's controller
directory.

This repository contains the exact solver, the pinned statements, the pinned
toolchain, and the scripts to re-run the whole benchmark end to end. **To check
the result yourself, start with the AXLE API section directly below — it takes
Python 3 and a network connection, nothing else.**

## Start Here: Verify Our Proofs Through The AXLE API

The verified Lean files are published on [Huggingface](https://huggingface.co/datasets/humanfia-lab/putnambench-solution). Note that upon putnambench authors' request, we do NOT open source all solutions. Instead, we provide a preview of first 12 questions for review and open source the whole solving pipeline. Feel free to eval and run if interested.

The fastest independent check is the AXLE verification API. It needs **only
Python 3 and network access** — no Lean, no Mathlib, no Comparator build, no
model calls, no API key. AXLE receives the proof together with the benchmark
statement, checks it in a clean Lean 4.27.0 environment, and returns Boolean
`okay`.

```bash
# 1. Get the published proofs.
git clone https://huggingface.co/datasets/humanfia-lab/putnambench-solution-preview

# 2. Write the pinned benchmark statements out of the packaged JSONL.
mkdir -p work/originals
python3 - <<'PY'
import json, pathlib
out = pathlib.Path("work/originals")
for line in pathlib.Path("inputs/putnam_bench.jsonl").read_text(encoding="utf-8").splitlines():
    if line.strip():
        record = json.loads(line)
        (out / f"{record['problem_id']}.lean").write_text(
            record["formal_statement"], encoding="utf-8"
        )
PY

# 3. Verify a single proof.
python3 humanize/scripts/verify-putnambench-axle.py \
  --originals-root work/originals \
  --candidate putnam-bench-verified-and-code/Putnam-bench-verified/Putnam1962A2.lean

# 4. Verify every published proof, 50 candidates per invocation.
find putnam-bench-verified-and-code/Putnam-bench-verified -name '*.lean' -print0 \
  | xargs -0 -n 50 sh -c '
      args=""
      for file in "$@"; do args="$args --candidate $file"; done
      python3 humanize/scripts/verify-putnambench-axle.py \
        --originals-root work/originals $args \
        --output "work/axle-$(date -u +%s%N).json"
    ' sh
```

**Reading the result.** The verifier exits `0` only when every candidate came
back `okay: true`, `1` when AXLE rejected a proof, and `2` on input or API
errors. The printed JSON carries `all_okay` and, per candidate, the `problem`,
`status` (`correct` / `incorrect`), the AXLE `request_id`, and SHA-256 hashes of
the candidate, the submitted content, and the original statement — so a third
party can confirm that what AXLE checked was exactly the published file against
the pinned benchmark statement.

Two notes so results are not misread:

- Candidate filenames must be `PutnamYYYYAN.lean` or `putnam_YYYY_aN.lean`. That
  is how each proof is matched to its benchmark statement.
- `formal_statement_solution_patched: true` is expected and sanctioned. It means
  the verifier replaced only the original `<problem>_solution := sorry`
  declaration with the candidate's concrete solution, so AXLE checks against a
  statement with no hole. The theorem itself is never modified.

This API check asks the least of a reader: it trusts nothing in this repository
except the benchmark statements, which are hash-pinned in
`inputs/putnam_bench.jsonl`. For the stronger, fully offline check, continue
below.

## Install Lean 4.27.0

The AXLE check above needs no Lean. Everything below does. This project is
pinned to **Lean 4.27.0** and **Mathlib v4.27.0**.

Lean is installed through Elan, the Lean toolchain manager. On Ubuntu or Debian,
first install the system packages needed by Elan, Lean, and the checker builds:

```bash
sudo apt-get update
sudo apt-get install -y curl git build-essential python3 jq ripgrep golang-go
```

On macOS, install the Xcode command-line tools instead:

```bash
xcode-select --install
```

Then install Elan on either platform:

```bash
curl https://elan.lean-lang.org/elan-init.sh -sSf | sh
source "$HOME/.elan/env"
```

Verify the installation. Entering the pinned project directory makes Elan
download and select Lean 4.27.0 automatically:

```bash
(
  cd inputs/math-flow-bench
  lean --version
  lake --version
)
```

The Lean version should be `4.27.0`. If `elan`, `lean`, or `lake` is not found,
open a new shell or run `source "$HOME/.elan/env"` again. A global
`elan default` is unnecessary because `inputs/math-flow-bench/lean-toolchain`
pins the version for this project. See the [official Lean installation
guide](https://lean-lang.org/install/manual/) for other platforms.

`./reproduce.sh bootstrap` reads your Elan home (`$ELAN_HOME`, else
`$HOME/.elan`), installs the pinned toolchain, fetches the Mathlib cache with
`lake exe cache get` so Mathlib is not compiled from source, and builds
Comparator, Lean4Export, and Landrun under `work/`. Elan must be installed
before that command; it fails with `Elan home not found` otherwise. The
Comparator gate additionally requires x86-64 Linux with Landlock, so gates 1-3
run anywhere Lean runs, while gate 4 is Linux-only.

## Full Local Re-verification

AXLE is one of five gates. To reproduce all of them locally on the published
files, build the pinned environment first:

```bash
./reproduce.sh bootstrap
```

For a proof of problem `putnam_YYYY_aN`, with `<Module>` its `PutnamYYYYAN`
form:

```bash
# Gate 1: no proof escapes.
rg -n '\b(sorry|admit|axiom|native_decide)\b' MathFlowBench/<Module>.lean

# Gate 2: the theorem statement and docstring are unchanged.
python3 inputs/math-flow-bench/scripts/validate-putnambench-output.py \
  --problem putnam_YYYY_aN --putnambench-root source --candidate-root .

# Gate 3: it compiles in the pinned environment.
lake env lean MathFlowBench/<Module>.lean

# Gate 4: Comparator, restricted axioms, Lean kernel replay.
bash humanize/scripts/check-putnambench-comparator.sh comparator.json
```

Gate 1 must print nothing, and gate 4 must end with both `Lean default kernel
accepts the solution` and `Your solution is okay!`. Gates 2-4 expect the
candidate at `MathFlowBench/<Module>.lean` inside a copy of
`inputs/math-flow-bench` whose `.lake/packages` points at the bootstrapped
`work/math-flow-bench/.lake/packages`, with the benchmark statement at
`source/lean4/src/putnam_YYYY_aN.lean` (the same file `work/originals` already
holds) and a matching `comparator.json`. `prepare_workspace` in
`humanize/scripts/run-failed-putnambench.sh` is the exact layout the solver used
and generates that `comparator.json`.

To re-verify proofs that this repository produced itself, run the batch auditor
instead — see [Independently re-verify the proofs](#7-independently-re-verify-the-proofs).

## Verification Method

Verification is deliberately redundant: the model that writes a proof never
decides whether it is accepted. Acceptance requires an independent Lean kernel
replay, an independent statement-equivalence checker, and an independent external
verifier service, all in agreement.

Each candidate must clear all of the following gates:

1. **Exact statement provenance.** The problem's `formal_statement` is extracted
   from the pinned `inputs/putnam_bench.jsonl` by exact `problem_id` match, and
   the workspace source file must match it byte-for-byte.
2. **Statement preservation.** `scripts/validate-putnambench-output.py` confirms
   the theorem statement and docstring in the candidate are unchanged from the
   benchmark statement. Weakened or restated theorems are rejected.
3. **No proof escapes.** The candidate must contain no `sorry`, `admit`, `axiom`,
   or `native_decide`. `native_decide` is rejected because it depends on
   `Lean.ofReduceBool` / `Lean.trustCompiler` rather than the kernel.
4. **Lean compilation.** `lake env lean MathFlowBench/<Module>.lean` succeeds
   against the pinned Lean 4.27.0 / Mathlib environment.
5. **Comparator.** The pinned `leanprover/comparator` build compares the
   candidate against a protected `ComparatorChallenge.lean`, verifies the theorem
   statement and any solution-definition hole, restricts axioms to `propext`,
   `Quot.sound`, and `Classical.choice`, and replays the proof through the Lean
   default kernel. The run must end with both `Lean default kernel accepts the
   solution` and `Your solution is okay!`. Comparator, its config, the Lake files,
   and the wrapper are protected from worker edits; the run executes under real
   Landrun/Landlock sandboxing, not a stub.
6. **AXLE.** A separate reviewer process, which cannot edit the candidate, calls
   `https://axle.axiommath.ai/api/v1/verify_proof` and must receive Boolean
   `okay: true` against the JSONL-sourced statement. The reviewer's only
   permitted network call is this one.
7. **Independent post-hoc audit.** `humanize/scripts/audit-failed-putnambench-passes.sh`
   re-audits every terminal pass after the fact: it re-checks candidate and
   original hashes against the stored AXLE artifact, re-runs the statement
   validator and forbidden-marker scan, and recompiles the candidate from a
   clean canonical MathFlowBench build.

Isolation properties that make the result meaningful:

- The solver runs in a separate sanitized Git workspace per problem, with
  separate worker and reviewer Codex homes.
- Existing PutnamBench solutions are never mounted into either model's namespace.
- Worker tool shells have network syscalls blocked by seccomp — no web search, no
  solution lookup, no prior attempts, no session archives.
- Worker and reviewer are separate processes with separate prompts and separate
  state; the reviewer decides acceptance and cannot modify the proof.

Every run retains the full evidence trail: prompts, event streams, session paths,
reviews, compilation logs, Comparator output, AXLE JSON responses and request IDs,
file hashes, and terminal status files.

## How To Reproduce

### 0. Prerequisites

- x86-64 Linux with unprivileged user, mount, and network namespaces enabled, and
  a kernel able to run Landrun/Landlock.
- Bash, Git, curl, Python 3, jq, ripgrep, a C compiler, Go, the standard GNU
  tools, and Elan/Lake — see [Install Lean 4.27.0](#install-lean-4270).
- Codex CLI authenticated in `${CODEX_HOME:-$HOME/.codex}` with access to
  `gpt-5.5`. Both `auth.json` and `config.toml` must be present; override the
  location with `--base-codex-home PATH`.
- Outbound network access for dependency downloads, Codex calls, and reviewer
  calls to `https://axle.axiommath.ai/api/v1/verify_proof`.
- Enough memory, disk, API quota, and process capacity for the chosen concurrency.

### 1. Check package integrity (no downloads, no model calls)

```bash
./reproduce.sh check
```

This verifies the packaged hashes against `MANIFEST.sha256`, the pinned inputs,
and the source syntax.

### 2. Build the pinned environment

```bash
./reproduce.sh bootstrap
```

This downloads and builds Lean 4.27.0, the pinned Mathlib, Comparator,
Lean4Export, and Landrun under `work/`. Nothing outside `work/`, `runs/`, and
`all-runs/` is modified.

### 3. Confirm the 672-problem selection

```bash
./solve-all-putnambench.sh --list-only
```

The selection is derived directly from `inputs/putnam_bench.jsonl`; the script
fails loudly if the file does not contain exactly 672 unique, well-formed
`problem_id` records with non-empty statements.

### 4. Smoke-test end to end before committing quota

```bash
./solve-all-putnambench.sh --max-problems 2 --jobs 2 --campaigns 1
```

To prepare and audit all 672 sanitized workspaces without making any model call:

```bash
./solve-all-putnambench.sh --prepare-only --jobs 64
```

### 5. Run the full benchmark

One campaign over all 672 problems:

```bash
./solve-all-putnambench.sh --jobs 64 --campaigns 1
```

The published 670/672 figure comes from repeated campaigns, where each later
campaign retries only the problems still unresolved:

```bash
./solve-all-putnambench.sh --jobs 64 --campaigns 3
```

Use `--campaigns 0` to keep launching fresh attempts for unresolved problems
until every selected problem passes:

```bash
./solve-all-putnambench.sh --jobs 64 --campaigns 0
```

Unlimited campaigns can consume unbounded API quota and should be monitored. No
model can guarantee that every theorem will be solved. Exit code `0` means every
selected problem passed all gates; exit code `2` means a bounded campaign limit
was reached with problems still unresolved.

Historical configuration: `gpt-5.5` at `xhigh` reasoning, 50-turn cap per problem
per campaign, four one-turn probe jobs, main concurrency 64, fallback concurrency
16 after rate limits, 7200-second worker and reviewer timeouts. Those are the
defaults; `--jobs`, `--fallback-jobs`, `--max-turns`, and the timeout flags
override them. See `./solve-all-putnambench.sh --help`.

### 6. Read the result

Outputs land under `all-runs/`. The controller directory
`all-runs/<run-id>-controller/` contains:

- `SUMMARY.md` — selected count, **verified passes**, unresolved count, campaigns
  completed, model, and turn cap;
- `attempts.tsv` — one row per attempt: campaign, problem, status, turn,
  candidate SHA-256, candidate path;
- `initial.txt` and `selections/` — the initial selection and each campaign's
  unresolved selection;
- `unresolved.txt` — the problem IDs that never passed.

Each campaign directory keeps its own prompts, event streams, proof candidates,
reviews, AXLE evidence, and Codex session index. Verified proof files are at
`all-runs/<campaign-id>/workspaces/<job>/MathFlowBench/<Module>.lean`.

### 7. Independently re-verify the proofs

```bash
WORKSPACE_ROOT="$PWD/work" \
OUT_ROOT="$PWD/all-runs" \
CANONICAL_ROOT="$PWD/work/math-flow-bench" \
  bash humanize/scripts/audit-failed-putnambench-passes.sh
```

This recompiles each passed candidate from the canonical built environment,
re-runs the statement validator and forbidden-marker scan, and re-checks the
stored AXLE evidence and hashes. Verified problems are recorded once in
`<OUT_ROOT>/pass-audit/verified-passes.tsv`; anything that fails re-verification
is written to `audit-failures.tsv`.

## What Counts As A Reproduction

Model output is nondeterministic and service-side models can change, so proof
text, turn counts, and wall-clock timing will differ between runs. A rerun is
methodologically faithful when it uses:

- the full 672-problem selection derived from the packaged JSONL;
- the byte-identical `formal_statement` values;
- the pinned Lean, Mathlib, Comparator, Lean4Export, and Landrun commits;
- the vendored Humanize orchestration in `humanize/`;
- `gpt-5.5` at `xhigh` reasoning;
- the unmodified acceptance gates above.

The number solved is a property of the model and the campaign budget, not of the
harness. What the harness guarantees is that whatever number it reports is
backed by kernel-checked, statement-preserving, independently audited proofs.

## Pinned Inputs

- Formal statements: `inputs/putnam_bench.jsonl`
  - SHA-256: `2b3a9c40a41b303e9bc7f60f69e3a457c7ee1e45e3e0c240a05a0054970de455`
  - 672 unique `problem_id` records, verified at selection time
- Lean: `leanprover/lean4:v4.27.0`
- Mathlib: tag `v4.27.0`, commit `a3a10db0e9d66acbebf76c5e6a135066525ac900`
- Comparator: `leanprover/comparator@099775bf2e6073fcb22aacd3a2809fdeac3fc84a`
- Lean4Export: `leanprover/lean4export@590dec59d93ab6becdf16fdd8aee5abbb99cb856`
- Landrun: `Zouuup/landrun@5ed4a3db3a4ad930d577215c6b9abaa19df7f99f`
- Humanize upstream: `PolyArch/humanize`; this package vendors the exact
  comparator-enabled source snapshot used by the runner.

`MANIFEST.sha256` covers the immutable packaged source, inputs, and reference
evidence. Generated dependencies and new runs are written only under `work/`,
`runs/`, and `all-runs/`.

## Layout

- `solve-all-putnambench.sh` — the 672-problem entry point: selection, campaigns
  over unresolved problems, aggregate controller state.
- `reproduce.sh` — integrity check, pinned dependency bootstrap, workspace
  preparation.
- `humanize/` — the exact comparator-enabled Humanize source snapshot: worker and
  reviewer orchestration, gates, the AXLE verifier client
  (`scripts/verify-putnambench-axle.py`), and the independent pass auditor
  (`scripts/audit-failed-putnambench-passes.sh`).
- `inputs/` — the pinned JSONL statements, the pinned Lean project template, and
  the earlier problem-subset list.
- `reference/` — retained evidence from an earlier subset run, kept for
  provenance only; it is not the source of the 670/672 figure.
- `provenance/` — source revisions and package notes.
- `work/`, `runs/`, `all-runs/` — generated; created on demand.

No credentials, Codex session database, downloaded dependencies, or generated
workspaces are included in this package.
