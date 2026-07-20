# FULL GOAL ALIGNMENT CHECK - Round {{CURRENT_ROUND}}

This is a **mandatory checkpoint** (at configurable intervals). You must conduct a comprehensive goal alignment audit.

## Original Implementation Plan

**IMPORTANT**: The original plan that Claude is implementing is located at:
@{{PLAN_FILE}}

You MUST read this plan file first to understand the full scope of work before conducting your review.

---
## Claude's Work Summary
<!-- CLAUDE's WORK SUMMARY START -->
{{SUMMARY_CONTENT}}
<!-- CLAUDE's WORK SUMMARY  END  -->
---

{{COMMIT_HISTORY_SECTION}}

## Part 1: Goal Tracker Audit (MANDATORY)

Read @{{GOAL_TRACKER_FILE}} and verify:

### 1.1 Acceptance Criteria Status
For EACH Acceptance Criterion in the IMMUTABLE SECTION:
| AC | Status | Evidence (if MET) | Blocker (if NOT MET) | Justification (if DEFERRED) |
|----|--------|-------------------|---------------------|----------------------------|
| AC-1 | MET / PARTIAL / NOT MET / DEFERRED | ... | ... | ... |
| ... | ... | ... | ... | ... |

### 1.2 Forgotten Items Detection
Compare the original plan (@{{PLAN_FILE}}) with the current goal-tracker:
- Are there tasks that are neither in "Active", "Completed", nor "Deferred"?
- Are there tasks marked "complete" in summaries but not verified?
- List any forgotten items found.

### 1.3 Deferred Items Audit
For each item in "Explicitly Deferred":
- Is the deferral justification still valid?
- Should it be un-deferred based on current progress?
- Does it contradict the Ultimate Goal?

### 1.4 Goal Completion Summary
```
Acceptance Criteria: X/Y met (Z deferred)
Active Tasks: N remaining
Estimated remaining rounds: ?
Critical blockers: [list if any]
```

## Part 2: Mainline Drift Audit (MANDATORY)

Determine whether the recent rounds are still serving the original plan:
- Is the current round's mainline objective clear and singular?
- Has Claude been advancing mainline ACs, or mostly clearing side issues?
- Which findings are true **blocking side issues** versus merely **queued side issues**?

Include a short drift summary:
```
Mainline Progress Verdict: ADVANCED / STALLED / REGRESSED
Blocking Side Issues: N
Queued Side Issues: N
```

The `Mainline Progress Verdict` line is mandatory. If you omit it, the Humanize stop hook will block the round and require the review to be rerun.

## Part 3: Implementation Review

- Conduct a deep critical review of the implementation
- Verify Claude's claims match reality
- Identify any gaps, bugs, or incomplete work
- Reference @{{DOCS_PATH}} for design documents

## Part 4: PutnamBench Proof Verification via AXLE (MANDATORY)

For every PutnamBench Lean candidate covered by the plan, independently run its
local Lean compilation and verify it against the original PutnamBench theorem
statement. Do not trust summaries or reuse results from earlier rounds.

Call the isolated verifier with one `--candidate` argument per target:

```bash
axle_status=2
for axle_delay in 0 30 120; do
  if [ "$axle_delay" -gt 0 ]; then sleep "$axle_delay"; fi
  if python3 "{{AXLE_VERIFIER}}" \
      --candidate <candidate-file> \
      --retries 4 \
      --output "{{REVIEW_RESULT_FILE}}.axle.json"; then
    axle_status=0
  else
    axle_status=$?
  fi
  # Exit 0 is verified; exit 1 is a real AXLE rejection. Retry only exit 2.
  if [ "$axle_status" -ne 2 ]; then break; fi
done
test "$axle_status" -eq 0
```

Before making that call, inspect the output path. If it already contains a
completed AXLE result from an interrupted reviewer attempt in this same round,
reuse it only when every recorded candidate SHA-256 matches the current file,
every original SHA-256 matches the current original, and every result contains
a Boolean `okay`. Do not resubmit an identical same-hash proof merely because
the Codex response stream failed after AXLE answered. An `api_error`, `okay:
null`, missing hash, stale hash, or malformed artifact is unavailable evidence
and requires the normal retry command.

The verifier submits candidate code as `content` and the matching original
skeleton as `formal_statement`. Completion requires local compilation success,
process exit `0`, and a Boolean `okay: true` for every candidate.
For PutnamBench answers encoded as `putnam_*_solution := sorry`, the verifier
may replace only that solution declaration in the submitted `formal_statement`
with the candidate's concrete solution declaration. This sanctioned
normalization keeps AXLE's expected theorem type aligned with the candidate and
does not change the theorem statement, docstring, problem source, or required
result. Treat `formal_statement_solution_patched: true` as valid verifier
evidence when the AXLE result is otherwise `okay: true`.

- Treat exit `1`, which represents an explicit `okay: false`, as a Mainline Gap.
- Retry exit `2` using the full command above. Timeouts, network errors, malformed
  responses, and absent Boolean `okay` remain `okay: null`; never convert them
  into `okay: false`.
- If all exit-`2` retries fail, report review infrastructure as unavailable and
  request another review attempt. Do not request proof changes on that evidence.
- Treat a missing input or compilation failure as a Blocking Side Issue, not as
  an AXLE rejection.
- Never output `COMPLETE` when the API check was skipped, unavailable, stale, or
  incomplete.
- Do not edit proof files during review; report exact fixes for the worker.

Interpret AXLE diagnostics precisely:
- If AXLE reports that a theorem does not match the expected signature while
  the displayed `expected type` and `got` type look identical, first confirm
  that the theorem block still matches the original and that the local
  statement validator passes. In that situation, the usual cause is that a
  reducible `*_solution` abbreviation is not definitionally equal to the
  hidden expected answer. Ask the worker to rederive and correct the solution
  value, including canonical operand/order choices when relevant.
- Before proposing another `*_solution` value, inspect the prior review results
  and git history in this sanitized workspace. List the distinct rejected
  right-hand sides relevant to the next recommendation. Do not recommend a
  value already rejected in an earlier round.
- Do not spend a round on a spelling that is definitionally equal to a rejected
  value. Use a temporary local Lean check such as an `example : old = new :=
  rfl` (outside the candidate proof file) when equivalence is uncertain. Changes
  limited to constructor notation, explicit numeral coercions, pair notation,
  or other reducible wrappers need this check before being recommended.
- After two consecutive signature-mismatch rejections, independently rederive
  the mathematical answer from the original problem and test the proposed term
  against every binder, order convention, sign, endpoint, and uniqueness issue.
  Give the worker one mathematically justified, definitionally distinct next
  value rather than an arbitrary permutation of the current expression.
- Unrelated helper declarations and their position before or after the theorem
  cannot change the theorem type. Do not prescribe moving or inlining helpers,
  changing declaration order, or other layout-only refactors as a remedy for a
  signature mismatch.
- If AXLE names disallowed axioms such as `Lean.ofReduceBool` or
  `Lean.trustCompiler`, identify the producing tactic (commonly
  `native_decide`) and require a kernel-checked replacement.
- Never recommend weakening the theorem, editing the original statement, or
  changing the acceptance criteria. If the candidate contains a locally
  compiling, kernel-checked counterexample or proof that the exact parsed
  benchmark statement is false, classify it as a benchmark formalization
  defect, cite the precise declarations and checks, and keep the proof result
  incomplete. A false target is not converted into a pass.

Write an `AXLE Verification` section to `{{REVIEW_RESULT_FILE}}` with candidate
and original paths, compilation results, API status, `okay`, request IDs, and
both SHA-256 values.
In the Goal Alignment Summary, count acceptance criteria as satisfied only when
their required outcome actually passed. An attempted check, an AXLE call, or
Boolean `okay: false` is addressed work but is not a satisfied criterion.

## Part 5: {{GOAL_TRACKER_UPDATE_SECTION}}

## Part 6: Progress Stagnation Check (MANDATORY for Full Alignment Rounds)

To implement the original plan at @{{PLAN_FILE}}, we have completed **{{COMPLETED_ITERATIONS}} iterations** (Round 0 to Round {{CURRENT_ROUND}}).

The project's `.humanize/rlcr/{{LOOP_TIMESTAMP}}/` directory contains the history of each round's iteration:
- Round input prompts: `round-N-prompt.md`
- Round output summaries: `round-N-summary.md`
- Round review prompts: `round-N-review-prompt.md`
- Round review results: `round-N-review-result.md`

**How to Access Historical Files**: Read the historical review results and summaries using file paths like:
- `@.humanize/rlcr/{{LOOP_TIMESTAMP}}/round-{{PREV_ROUND}}-review-result.md` (previous round)
- `@.humanize/rlcr/{{LOOP_TIMESTAMP}}/round-{{PREV_PREV_ROUND}}-review-result.md` (2 rounds ago)
- `@.humanize/rlcr/{{LOOP_TIMESTAMP}}/round-{{PREV_ROUND}}-summary.md` (previous summary)

**Your Task**: Review the historical review results, especially the **recent rounds** of development progress and review outcomes, to determine if the development has stalled.

**Signs of Stagnation** (circuit breaker triggers):
- Same issues appearing repeatedly across multiple rounds
- No meaningful progress on Acceptance Criteria over several rounds
- Claude making the same mistakes repeatedly
- Circular discussions without resolution
- No new code changes despite continued iterations
- Codex giving similar feedback repeatedly without Claude addressing it

**If development is stagnating**, write **STOP** (as a single word on its own line) as the last line of your review output @{{REVIEW_RESULT_FILE}} instead of COMPLETE.

## Part 7: Output Requirements

- If issues found OR any AC is NOT MET (including deferred ACs), write your findings to @{{REVIEW_RESULT_FILE}}
- Include specific action items for Claude to address, classified into:
  - Mainline Gaps
  - Blocking Side Issues
  - Queued Side Issues
- **If development is stagnating** (see Part 4), write "STOP" as the last line
- **CRITICAL**: Only write "COMPLETE" as the last line if ALL ACs from the original plan are FULLY MET with no deferrals
  - Local Lean compilation and a fresh AXLE `okay: true` result are mandatory
  - Exhausted API retries mean verification is unavailable, not that the proof is false
  - DEFERRED items are considered INCOMPLETE - do NOT output COMPLETE if any AC is deferred
  - The ONLY condition for COMPLETE is: all original plan tasks are done, all ACs are met, no deferrals allowed
- When complete, the file at @{{REVIEW_RESULT_FILE}} itself MUST end with a
  separate final line containing exactly `COMPLETE`. Putting `COMPLETE` only in
  your chat/final response does not complete the review.
