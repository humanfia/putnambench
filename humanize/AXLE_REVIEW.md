# Humanize with Comparator Worker Checks and AXLE Review

This is an isolated copy of Humanize. Existing Humanize files under
`../humanize` and `../humanize-axle-review` are not modified.

Every blind worker receives a protected Comparator harness and must run:

```bash
bash tools/check-with-comparator.sh
```

before handing a candidate to the reviewer. The wrapper uses the untouched
PutnamBench skeleton as the challenge, the worker's module as the solution,
the target Lean version's `lean4export`, current Comparator, and real Landrun.
The runner repeats this check as part of its deterministic local gate. Success
must end with `Lean default kernel accepts the solution` and
`Your solution is okay!`.

The regular and full-alignment Codex review prompts require the reviewer to:

1. identify every PutnamBench candidate covered by the round;
2. compile each candidate locally;
3. call the AXLE proof-verification API with the candidate as `content` and the
   original PutnamBench theorem statement as `formal_statement`;
4. record the API result and request ID; and
5. refuse to output `COMPLETE` unless every result contains `okay: true`.

For PutnamBench files whose theorem type refers to
`putnam_*_solution := sorry`, the verifier may replace only that original
solution declaration in the submitted `formal_statement` with the candidate's
concrete solution declaration. This keeps AXLE's expected theorem type aligned
without changing the benchmark theorem statement or problem.

Use the isolated launcher. It selects this checkout and passes
`--skip-humanize-install`, so it does not replace the currently installed
Humanize skill or hooks:

```bash
bash /home/zijian/zhengyang-workspace/lean/humanize-axle-comparator-review/scripts/run-putnambench.sh \
  --problem putnam_2025_a1
```

The reviewer-facing verifier can also be called directly:

```bash
python3 /home/zijian/zhengyang-workspace/lean/humanize-axle-comparator-review/scripts/verify-putnambench-axle.py \
  --candidate MathFlowBench/Putnam2025A1.lean \
  --output .humanize/axle-review-putnam_2025_a1.json
```

Exit status `0` means every candidate received `okay: true`; `1` means AXLE
rejected at least one proof; and `2` means verification could not be completed.
Both `1` and `2` block review completion, but only `1` is a proof rejection.
The verifier retries transient failures internally. Review prompts retry exit
`2` twice more with backoff and preserve it as `okay: null`; they never convert
an API or network failure into `okay: false`.

Project-local `MathFlowBench.*` imports are recursively inlined before upload so
the submitted proof remains self-contained in AXLE's Mathlib environment. The
report records hashes for the candidate file, submitted content, and original
statement.

## Blind Failed-Problem Batch

`scripts/run-failed-putnambench.sh` parses the problem IDs in
`/home/zijian/zhengyang-workspace/Failed_problems.md`, extracts each exact
`formal_statement` by `problem_id` from
`/home/zijian/zhengyang-workspace/putnam_bench.jsonl`, and runs isolated
Humanize worker/reviewer loops:

```bash
bash /home/zijian/zhengyang-workspace/lean/humanize-axle-comparator-review/scripts/run-failed-putnambench.sh
```

Defaults are `gpt-5.5`, `xhigh`, 50 turns, and a four-job probe followed by 32
parallel problem workers only after a healthy probe without HTTP 429/529. Rate
or transport failures trigger backoff and reduce concurrency to 16. Solver shells
are network-blocked and web tools are disabled. Reviewers see only the
sanitized workspace and may use network access only through the AXLE verifier.

Every Codex home is stored below
`/home/zijian/zhengyang-workspace/.codex/failed-putnambench-humanize-axle/`.
The run directory retains a `codex-sessions.tsv` mapping roles and turns to
thread IDs, JSON event streams, final messages, and rollout session files.
