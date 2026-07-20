# PutnamBench Humanize 98-Problem Reproduction

This directory reproduces the Humanize + Comparator + AXLE experiment started
on 2026-07-09 for the 98 problem IDs in `inputs/Failed_problems.md`.

The recorded run used `gpt-5.5` with `xhigh` reasoning, a 50-turn cap, a
four-job probe, up to 64 concurrent workers, and a fallback concurrency of 16.
It produced 96 independently verified proofs. `putnam_2013_a5` and
`putnam_2017_b3` reached the turn cap and were not counted as proofs. The exact
historical report is in `reference/FINAL_REPORT.md`.

## Quick Start

Verify the package locally without downloads or model calls:

```bash
./reproduce.sh check
```

Download and build the pinned Lean and Comparator dependencies:

```bash
./reproduce.sh bootstrap
```

Prepare and audit the 98 isolated workspaces without making model calls:

```bash
./reproduce.sh prepare
```

Run the full experiment with the historical concurrency:

```bash
./reproduce.sh run --jobs 64 --fallback-jobs 16 --max-turns 50
```

For a cheaper smoke test, restrict the run to one problem:

```bash
./reproduce.sh run --problem putnam_1962_a2 --jobs 1
```

The full run makes paid model calls, may consume substantial quota, and can run
for many hours. Use `./reproduce.sh --help` for all options.

## Solve All 672 PutnamBench Problems

`solve-all-putnambench.sh` derives the complete 672-problem selection directly
from the pinned JSONL rather than from the historical 98-problem failure list.
It uses the same isolated Humanize worker/reviewer loop and the same Lean,
Comparator, Lean4Export, Landrun, and AXLE acceptance gates.

Inspect the complete selection without downloads or model calls:

```bash
./solve-all-putnambench.sh --list-only
```

Prepare all 672 sanitized workspaces without model calls:

```bash
./solve-all-putnambench.sh --prepare-only --jobs 64
```

Run one complete campaign:

```bash
./solve-all-putnambench.sh --jobs 64 --campaigns 1
```

Run up to three campaigns, retrying only unresolved problems:

```bash
./solve-all-putnambench.sh --jobs 64 --campaigns 3
```

Use `--campaigns 0` to continue launching fresh attempts for unresolved
problems until every selected problem passes:

```bash
./solve-all-putnambench.sh --jobs 64 --campaigns 0
```

Unlimited campaigns can consume unbounded API quota and should be monitored.
No model can guarantee that every theorem will be solved. The launcher exits
successfully only when every selected problem has passed Lean compilation,
statement preservation, Comparator, and AXLE verification. It exits with code
`2` when a bounded campaign limit is reached with unresolved problems.

For a two-problem end-to-end smoke test:

```bash
./solve-all-putnambench.sh --max-problems 2 --jobs 2 --campaigns 1
```

All-problem campaign outputs are written under `all-runs/`. The controller
directory `<run-id>-controller/` contains the initial selection, per-campaign
unresolved selections, `attempts.tsv`, `unresolved.txt`, and `SUMMARY.md`.
Every campaign retains its own prompts, event streams, proof candidates,
reviews, AXLE evidence, and Codex session index.

## Requirements

- x86-64 Linux with unprivileged user, mount, and network namespaces enabled;
- a kernel and configuration capable of running Landrun/Landlock;
- Bash, Git, curl, Python 3, jq, ripgrep, a C compiler, Go, Elan/Lake, and the
  standard GNU command-line tools used by the runner;
- Codex CLI authenticated in `${CODEX_HOME:-$HOME/.codex}` with access to
  `gpt-5.5`;
- outbound network access for dependency downloads, Codex calls, and reviewer
  calls to `https://axle.axiommath.ai/api/v1/verify_proof`;
- enough memory, disk, API quota, and process capacity for the chosen
  concurrency.

The runner requires both `auth.json` and `config.toml` in the selected Codex
home. Override it with `--base-codex-home PATH`.

## Pinned Inputs

- Problem selection: `inputs/Failed_problems.md`
  - SHA-256: `67a97f0927b5ce8331077c53b68a9d71f388aaf4b176c568f40be2a5c11d47a7`
- Formal statements: `inputs/putnam_bench.jsonl`
  - SHA-256: `2b3a9c40a41b303e9bc7f60f69e3a457c7ee1e45e3e0c240a05a0054970de455`
- Lean: `leanprover/lean4:v4.27.0`
- Mathlib: tag `v4.27.0`, commit `a3a10db0e9d66acbebf76c5e6a135066525ac900`
- Comparator: `leanprover/comparator@099775bf2e6073fcb22aacd3a2809fdeac3fc84a`
- Lean4Export: `leanprover/lean4export@590dec59d93ab6becdf16fdd8aee5abbb99cb856`
- Landrun: `Zouuup/landrun@5ed4a3db3a4ad930d577215c6b9abaa19df7f99f`
- Humanize upstream: `PolyArch/humanize`; this package includes the exact local
  comparator-enabled source snapshot used by the historical runner.

`MANIFEST.sha256` covers the immutable packaged source, inputs, and reference
evidence. Generated dependencies and new runs are written only under `work/`
and `runs/`.

## What The Runner Does

For each selected problem, the vendored Humanize runner:

1. extracts the exact `formal_statement` by `problem_id` from the JSONL input;
2. creates a separate sanitized Git workspace and separate worker/reviewer
   Codex homes;
3. blocks network syscalls from worker shell commands;
4. asks the worker to produce a Lean proof without mounting existing solutions;
5. checks statement preservation, forbidden markers, Lean compilation, current
   Comparator, target-version Lean4Export, and real Landrun;
6. gives the reviewer network access only for the AXLE proof-verification call;
7. accepts a candidate only when the deterministic local gates pass and AXLE
   returns Boolean `okay: true`;
8. retains prompts, event streams, session paths, reviews, compilation logs,
   Comparator output, AXLE JSON, hashes, and terminal status files.

Outputs are placed in `runs/<run-id>/`. Per-job Codex homes are placed beneath
`${CODEX_HOME:-$HOME/.codex}/failed-putnambench-humanize-axle-comparator/`.

## Reproduction Criterion

Model output is nondeterministic, and service-side models can change. A rerun
is methodologically reproduced when it uses the packaged 98-problem selection,
the byte-identical JSONL statements, the pinned toolchain and checker commits,
the vendored Humanize orchestration, `gpt-5.5`/`xhigh`, and the same acceptance
gates. Exact proof text, turn counts, timing, and the final number solved are not
expected to be byte-for-byte identical.

Compare a new run with:

- `reference/RUN.md` for the historical configuration;
- `reference/FINAL_REPORT.md` for the 96/98 outcome;
- `reference/FINAL_ARTIFACTS.tsv` and `.json` for proof paths, hashes, turns,
  reviews, and AXLE request IDs;
- `reference/pass-audit/verified-passes.tsv` for the independently audited pass
  ledger.

## Layout

- `reproduce.sh`: integrity checking, dependency bootstrap, workspace
  preparation, and full-run entry point.
- `solve-all-putnambench.sh`: selects all 672 benchmark records and optionally
  runs repeated campaigns over only the unresolved problems.
- `humanize/`: exact comparator-enabled Humanize source snapshot used by the
  experiment.
- `inputs/`: the exact 98-problem list, JSONL statements, and pinned Lean project
  files required by the runner.
- `reference/`: retained configuration and final evidence from the historical
  run.
- `provenance/`: source revisions and package notes.
- `work/`: generated dependency checkouts and Mathlib cache; created on demand.
- `runs/`: generated reproduction attempts; created on demand.
- `all-runs/`: generated 672-problem campaigns and aggregate controller state;
  created on demand.

No credentials, Codex session database, downloaded dependencies, or generated
workspaces are included in the package.
