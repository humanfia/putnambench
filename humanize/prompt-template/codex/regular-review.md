# Code Review - Round {{CURRENT_ROUND}}

## Original Implementation Plan

**IMPORTANT**: The original plan that Claude is implementing is located at:
@{{PLAN_FILE}}

You MUST read this plan file first to understand the full scope of work before conducting your review.
This plan contains the complete requirements and implementation details that Claude should be following.

Based on the original plan and @{{PROMPT_FILE}}, Claude claims to have completed the work. Please conduct a thorough critical review to verify this.

---
Below is Claude's summary of the work completed:
<!-- CLAUDE's WORK SUMMARY START -->
{{SUMMARY_CONTENT}}
<!-- CLAUDE's WORK SUMMARY  END  -->
---

## Deterministic Runner Gate

The runner generated the embedded summary after independently running the
forbidden-marker scan, statement validator, target Lean compilation, and the
real Landrun-backed Comparator replay against this exact candidate. It launches
the reviewer only when all four checks pass. The candidate is mounted read-only
during review.

Treat the recorded Comparator `PASS`, including `Lean default kernel accepts
the solution` and `Your solution is okay!`, as authoritative runner evidence.
Do not rerun `tools/check-with-comparator.sh`; that duplicates the already
completed kernel replay and delays the fresh AXLE decision. You must still run
the local Lean compilation required below and make or validate the same-round
AXLE call.

---

{{COMMIT_HISTORY_SECTION}}

## Part 1: Implementation Review

- Your task is to conduct a deep critical review, focusing on finding implementation issues and identifying gaps between "plan-design" and actual implementation.
- Relevant top-level guidance documents, phased implementation plans, and other important documentation and implementation references are located under @{{DOCS_PATH}}.
- If Claude planned to defer any tasks to future phases in its summary, DO NOT follow its lead. Instead, you should force Claude to complete ALL tasks as planned.
  - Such deferred tasks are considered incomplete work and should be flagged in your review comments, requiring Claude to address them.
  - If Claude planned to defer any tasks, please explore the codebase in-depth and draft a detailed implementation plan. This plan should be included in your review comments for Claude to follow.
  - Your review should be meticulous and skeptical. Look for any discrepancies, missing features, incomplete implementations.
- If Claude does not plan to defer any tasks, but honestly admits that some tasks are still pending (not yet completed), you should also include those pending tasks in your review.
  - Your review should elaborate on those unfinished tasks, explore the codebase, and draft an implementation plan.
  - A good engineering implementation plan should be **singular, directive, and definitive**, rather than discussing multiple possible implementation options.
  - The implementation plan should be **unambiguous**, internally consistent, and coherent from beginning to end, so that **Claude can execute the work accurately and without error**.

## Part 2: PutnamBench Proof Verification via AXLE (MANDATORY)

For every PutnamBench Lean candidate covered by this round, you MUST independently
verify the proof against the original PutnamBench theorem statement. Do not rely
on Claude's summary or an API result from an earlier round.

1. Identify the candidate file from the plan and round prompt. Candidate names
   may be `MathFlowBench/PutnamYYYYAN.lean` or `putnam_YYYY_aN.lean`.
2. Confirm the corresponding original exists under the PutnamBench
   `lean4/src` directory.
3. Run the appropriate local Lean compilation command for the candidate.
4. Call AXLE using the isolated verifier, repeating `--candidate` for every
   candidate in scope:

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

The verifier sends the candidate file as `content` and the original benchmark
skeleton as `formal_statement` to the AXLE `/api/v1/verify_proof` endpoint.
For PutnamBench answers encoded as `putnam_*_solution := sorry`, the verifier
may replace only that solution declaration in the submitted `formal_statement`
with the candidate's concrete solution declaration. This sanctioned
normalization keeps AXLE's expected theorem type aligned with the candidate and
does not change the theorem statement, docstring, problem source, or required
result. Treat `formal_statement_solution_patched: true` as valid verifier
evidence when the AXLE result is otherwise `okay: true`.

Fail closed:
- Exit `0` and `okay: true` for every candidate are required for completion.
- Exit `1` means AXLE explicitly returned `okay: false`. This is a Mainline Gap
  and must be returned to the worker; do not retry it as an infrastructure error.
- Exit `2` means verification was unavailable. Retry the complete API command as
  shown above. API errors, timeouts, and missing or malformed responses remain
  `okay: null`; never record or describe them as `okay: false`.
- If all retry attempts end with exit `2`, classify the result as a review
  infrastructure failure and request another review attempt. Do not ask the
  worker to change the proof based only on an unavailable API.
- A missing candidate/original or nonzero local compilation remains a Blocking
  Side Issue and is not converted into an AXLE rejection.
- Do not output `COMPLETE` when verification is rejected, unavailable, skipped,
  stale, or incomplete.
- Do not edit candidate proof files. Diagnose and report; the worker must fix them.

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

Include an `AXLE Verification` section in `{{REVIEW_RESULT_FILE}}` containing,
for every candidate: candidate path, original path, local compilation result,
AXLE status, Boolean `okay`, request ID, and candidate/original SHA-256 values.
In the Goal Alignment Summary, count acceptance criteria as satisfied only when
their required outcome actually passed. An attempted check, an AXLE call, or
Boolean `okay: false` is addressed work but is not a satisfied criterion.

## Part 3: Goal Alignment Check (MANDATORY)

Read @{{GOAL_TRACKER_FILE}} and verify:

1. **Acceptance Criteria Progress**: For each AC, is progress being made? Are any ACs being ignored?
2. **Forgotten Items**: Are there tasks from the original plan that are not tracked in Active/Completed/Deferred?
3. **Deferred Items**: Are deferrals justified? Do they block any ACs?
4. **Plan Evolution**: If Claude modified the plan, is the justification valid?

Include a brief Goal Alignment Summary in your review:
```
ACs: X/Y addressed | Forgotten items: N | Unjustified deferrals: N
```

## Part 4: Required Finding Classification

You MUST classify your findings into these lanes:
- **Mainline Gaps**: plan-derived work or AC progress that is missing, incomplete, or regressing
- **Blocking Side Issues**: bugs or implementation issues that block the current mainline objective from succeeding safely
- **Queued Side Issues**: valid non-blocking follow-up issues that should be documented but must NOT take over the next round

Also include a one-line verdict:
```
Mainline Progress Verdict: ADVANCED / STALLED / REGRESSED
```

This verdict line is mandatory. If you omit it, the Humanize stop hook will block the round and require the review to be rerun.

If Claude mostly worked on queued side issues and failed to advance the mainline, say so explicitly.

## Part 5: {{GOAL_TRACKER_UPDATE_SECTION}}

## Part 6: Output Requirements

- In short, your review comments can include: problems/findings/blockers; claims that don't match reality; implementation plans for deferred work (to be implemented now); implementation plans for unfinished work; goal alignment issues.
- Your output should be structured so Claude can tell which items are mainline gaps, blocking side issues, and queued side issues.
- If after your investigation the actual situation does not match what Claude claims to have completed, or there is pending work to be done, output your review comments to @{{REVIEW_RESULT_FILE}}.
- **CRITICAL**: Only output "COMPLETE" if ALL tasks from the original plan are FULLY completed with no deferrals
  - Local Lean compilation and a fresh AXLE `okay: true` result are mandatory tasks
  - Exhausted API retries mean verification is unavailable, not that the proof is false
  - DEFERRED items are considered INCOMPLETE - do NOT output COMPLETE if any task is deferred
  - UNFINISHED items are considered INCOMPLETE - do NOT output COMPLETE if any task is pending
  - The ONLY condition for COMPLETE is: all original plan tasks are done, all ACs are met, no deferrals or pending work allowed
- When complete, the file at @{{REVIEW_RESULT_FILE}} itself MUST end with a
  separate final line containing exactly `COMPLETE`. Putting `COMPLETE` only in
  your chat/final response does not complete the review.
- The word COMPLETE on the final nonblank line of that file will stop Claude.
