# Final Experiment Report

- Run ID: `failed-humanize-jsonl98-20260709T003743Z`
- Result: **96/98 passed**, **2/98 reached the 50-turn cap**
- Model: `gpt-5.5`, reasoning effort `xhigh`
- Concurrency: launched up to `64`; after rate limits, drained and continued at `16`
- Exact statement source: `/home/zijian/zhengyang-workspace/putnam_bench.jsonl`
- Statement source SHA-256: `2b3a9c40a41b303e9bc7f60f69e3a457c7ee1e45e3e0c240a05a0054970de455`
- Source integrity: all 98 workspace source files match their JSONL `formal_statement` byte-for-byte
- Passed-proof audit: all 96 passed candidates independently recompiled, passed the statement validator, and matched their saved AXLE proof/hash evidence
- Generated: `2026-07-09T15:18:59Z`

## Proof Locations

Verified proof files are under:

`/home/zijian/zhengyang-workspace/failed-putnambench-humanize-axle-comparator-runs/failed-humanize-jsonl98-20260709T003743Z/workspaces/<job>/MathFlowBench/<Module>.lean`

The exact per-problem paths, hashes, terminal turns, review files, and AXLE request IDs are indexed in:

- `/home/zijian/zhengyang-workspace/failed-putnambench-humanize-axle-comparator-runs/failed-humanize-jsonl98-20260709T003743Z/FINAL_ARTIFACTS.tsv`
- `/home/zijian/zhengyang-workspace/failed-putnambench-humanize-axle-comparator-runs/failed-humanize-jsonl98-20260709T003743Z/FINAL_ARTIFACTS.json`

## Unresolved

- `putnam_2013_a5`: turn 50, candidate only (not verified as a proof): `/home/zijian/zhengyang-workspace/failed-putnambench-humanize-axle-comparator-runs/failed-humanize-jsonl98-20260709T003743Z/workspaces/j69-putnam_2013_a5/MathFlowBench/Putnam2013A5.lean`
- `putnam_2017_b3`: turn 50, candidate only (not verified as a proof): `/home/zijian/zhengyang-workspace/failed-putnambench-humanize-axle-comparator-runs/failed-humanize-jsonl98-20260709T003743Z/workspaces/j77-putnam_2017_b3/MathFlowBench/Putnam2017B3.lean`

The unresolved candidate files are retained for diagnosis, but they are not counted or labeled as proofs.
