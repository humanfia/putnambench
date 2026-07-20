#!/usr/bin/env python3
"""Validate a solved MathFlowBench file against its PutnamBench skeleton."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def module_name(problem: str) -> str:
    prefix = "putnam_"
    if not problem.startswith(prefix):
        raise ValueError(f"problem must start with {prefix!r}: {problem}")
    rest = problem[len(prefix) :]
    year, part = rest.split("_", 1)
    return f"Putnam{year}{part[:1].upper()}{part[1:]}"


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").replace("\r\n", "\n")
    except FileNotFoundError:
        fail(f"file not found: {path}")


def fail(message: str) -> None:
    print(f"validate-putnambench-output: ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalize_all(text: str) -> str:
    return re.sub(r"\s+", "", text)


def strip_line_comments(text: str) -> str:
    lines: list[str] = []
    for line in text.splitlines():
        if "--" in line:
            line = line.split("--", 1)[0]
        lines.append(line)
    return "\n".join(lines)


def normalize_expr(text: str) -> str:
    return normalize_all(strip_line_comments(text))


def find_theorem_start(source: str, theorem_name: str) -> int:
    match = re.search(rf"(?m)^theorem\s+{re.escape(theorem_name)}\b", source)
    if not match:
        fail(f"theorem {theorem_name} not found")
    return match.start()


def original_decl_guard(source: str, theorem_name: str) -> str:
    theorem_start = find_theorem_start(source, theorem_name)
    block_start = theorem_start

    doc_start = source.rfind("/--", 0, theorem_start)
    if doc_start != -1:
        doc_end = source.find("-/", doc_start, theorem_start)
        if doc_end != -1 and source[doc_end + 2 : theorem_start].strip() == "":
            block_start = doc_start

    proof_match = re.search(r":=\s*(?:by\s+)?sorry\b", source[theorem_start:])
    if not proof_match:
        fail(f"original theorem {theorem_name} is not a PutnamBench sorry skeleton")

    proof_delimiter_end = theorem_start + proof_match.start() + 2
    return source[block_start:proof_delimiter_end]


def extract_solution_body(source: str, solution_name: str) -> str | None:
    match = re.search(
        rf"(?m)^(?:noncomputable\s+)?abbrev\s+{re.escape(solution_name)}\b",
        source,
    )
    if not match:
        return None

    assign = source.find(":=", match.end())
    if assign == -1:
        fail(f"solution abbreviation {solution_name} has no :=")

    end_candidates = []
    for pattern in (
        r"(?m)^/--",
        r"(?m)^theorem\s+",
        r"(?m)^lemma\s+",
        r"(?m)^private\s+",
        r"(?m)^namespace\s+",
        r"(?m)^section\b",
        r"(?m)^end\b",
    ):
        next_match = re.search(pattern, source[assign + 2 :])
        if next_match:
            end_candidates.append(assign + 2 + next_match.start())

    end = min(end_candidates) if end_candidates else len(source)
    return source[assign + 2 : end].strip()


def validate(problem: str, putnambench_root: Path, candidate_root: Path) -> None:
    module = module_name(problem)
    theorem_name = problem
    solution_name = f"{problem}_solution"
    original_file = putnambench_root / "lean4" / "src" / f"{problem}.lean"
    candidate_file = candidate_root / "MathFlowBench" / f"{module}.lean"

    original = read_text(original_file)
    candidate = read_text(candidate_file)

    guard = original_decl_guard(original, theorem_name)
    if normalize_all(guard) not in normalize_all(candidate):
        fail(
            f"benchmark docstring or theorem statement changed for {theorem_name}"
        )

    solution_body = extract_solution_body(candidate, solution_name)
    if solution_body is None:
        return

    body_norm = normalize_expr(solution_body)
    if not body_norm:
        fail(f"solution abbreviation {solution_name} has an empty body")
    if re.search(r"\b(sorry|admit|axiom)\b", solution_body):
        fail(f"solution abbreviation {solution_name} still contains a placeholder")

    candidate_norm = normalize_expr(candidate)
    solution_norm = normalize_expr(solution_name)
    if f"{body_norm}={solution_norm}" in candidate_norm:
        fail(
            f"tautological solution body detected for {solution_name}: "
            "the solution is syntactically the theorem left-hand side"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--problem", required=True)
    parser.add_argument("--putnambench-root", required=True, type=Path)
    parser.add_argument("--candidate-root", required=True, type=Path)
    args = parser.parse_args()

    validate(args.problem, args.putnambench_root, args.candidate_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
