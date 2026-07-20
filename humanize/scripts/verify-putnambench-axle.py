#!/usr/bin/env python3
"""Verify PutnamBench Lean candidates against their original statements via AXLE."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_API_URL = "https://axle.axiommath.ai/api/v1/verify_proof"
DEFAULT_ENVIRONMENT = "lean-4.27.0"
DEFAULT_ORIGINALS_ROOT = Path(
    "/home/zijian/zhengyang-workspace/lean/PutnamBench/lean4/src"
)
MODULE_RE = re.compile(r"Putnam(\d{4})([AB])(\d)\.lean$")
SOURCE_RE = re.compile(r"putnam_(\d{4})_([ab])(\d)\.lean$")
IMPORT_RE = re.compile(r"^import\s+(\S+)\s*$")
TOP_LEVEL_RE = re.compile(
    r"^(?:/--|theorem\s+|lemma\s+|private\s+(?:lemma|def|abbrev)\s+|"
    r"(?:noncomputable\s+)?(?:def|abbrev)\s+|open\s+|namespace\s+|"
    r"section\s+|variable\s+|instance\s+)"
)


def problem_id(candidate: Path) -> str:
    module_match = MODULE_RE.fullmatch(candidate.name)
    if module_match:
        year, section, number = module_match.groups()
        return f"putnam_{year}_{section.lower()}{number}"

    source_match = SOURCE_RE.fullmatch(candidate.name)
    if source_match:
        return candidate.stem

    raise ValueError(
        f"Cannot derive a PutnamBench problem id from candidate name: {candidate.name}"
    )


def resolve_originals_root(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit.resolve()

    configured = os.environ.get("PUTNAMBENCH_ORIGINALS_ROOT")
    if configured:
        return Path(configured).resolve()

    if DEFAULT_ORIGINALS_ROOT.is_dir():
        return DEFAULT_ORIGINALS_ROOT

    for parent in (Path.cwd(), *Path.cwd().parents):
        candidate = parent / "PutnamBench" / "lean4" / "src"
        if candidate.is_dir():
            return candidate.resolve()

    raise FileNotFoundError(
        "PutnamBench originals were not found. Pass --originals-root or set "
        "PUTNAMBENCH_ORIGINALS_ROOT."
    )


def post_json(
    url: str,
    payload: dict[str, str],
    *,
    timeout: int,
    retries: int,
) -> tuple[dict[str, Any], int]:
    encoded = json.dumps(payload).encode()
    last_error: Exception | None = None

    for attempt in range(retries + 1):
        request = urllib.request.Request(
            url,
            data=encoded,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as reply:
                status = reply.status
                response = json.loads(reply.read())
            if not isinstance(response, dict):
                raise ValueError("AXLE returned a non-object JSON response")
            if not isinstance(response.get("okay"), bool):
                last_error = ValueError(
                    "AXLE response did not contain a Boolean 'okay' field: "
                    + json.dumps(response, ensure_ascii=False)[:2000]
                )
                if attempt == retries:
                    break
                time.sleep(min(30, 2**attempt))
                continue
            return response, status
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")
            retryable = exc.code == 429 or exc.code >= 500
            last_error = RuntimeError(f"HTTP {exc.code}: {body[:2000]}")
            if not retryable or attempt == retries:
                break
        except (
            TimeoutError,
            urllib.error.URLError,
            json.JSONDecodeError,
            ValueError,
        ) as exc:
            last_error = exc
            if attempt == retries:
                break

        time.sleep(min(30, 2**attempt))

    assert last_error is not None
    raise last_error


def compact_api_response(response: dict[str, Any]) -> dict[str, Any]:
    """Keep verification evidence without duplicating AXLE's echoed proof content."""
    return {
        key: response[key]
        for key in (
            "failed_declarations",
            "lean_messages",
            "tool_messages",
            "timings",
            "info",
        )
        if key in response
    }


def project_root_for(candidate: Path) -> Path | None:
    for parent in candidate.parents:
        module_root = parent / "MathFlowBench"
        if module_root.is_dir() and candidate.is_relative_to(module_root):
            return parent
    return None


def standalone_candidate(candidate: Path) -> str:
    """Inline project-local MathFlowBench imports for AXLE's Mathlib-only image."""
    project_root = project_root_for(candidate)
    visited: set[Path] = set()
    external_imports: list[str] = []
    bodies: list[str] = []

    def visit(source: Path) -> None:
        source = source.resolve()
        if source in visited:
            return
        visited.add(source)

        body: list[str] = []
        for line in source.read_text().splitlines():
            match = IMPORT_RE.fullmatch(line)
            if not match:
                body.append(line)
                continue

            module = match.group(1)
            if module == "MathFlowBench" or module.startswith("MathFlowBench."):
                if project_root is None:
                    raise FileNotFoundError(
                        f"Cannot resolve local import {module} for {candidate}"
                    )
                dependency = project_root / Path(*module.split("."))
                dependency = dependency.with_suffix(".lean")
                if not dependency.is_file():
                    raise FileNotFoundError(
                        f"Local import {module} resolves to missing file {dependency}"
                    )
                visit(dependency)
            elif line not in external_imports:
                external_imports.append(line)

        rendered_body = "\n".join(body).strip()
        if rendered_body:
            bodies.append(rendered_body)

    visit(candidate)
    sections = [*external_imports, *bodies]
    return "\n\n".join(sections) + "\n"


def declaration_span(source: str, declaration_name: str) -> tuple[int, int] | None:
    lines = source.splitlines()
    start_re = re.compile(
        rf"^(?:noncomputable\s+)?(?:abbrev|def)\s+"
        rf"{re.escape(declaration_name)}\b"
    )
    start = None
    for index, line in enumerate(lines):
        if start_re.match(line):
            start = index
            break
    if start is None:
        return None

    end = start + 1
    while end < len(lines):
        line = lines[end]
        if line and not line[0].isspace() and TOP_LEVEL_RE.match(line):
            break
        end += 1
    return start, end


def in_noncomputable_section(lines: list[str], index: int) -> bool:
    last_noncomputable_section = -1
    last_end = -1
    for line_index, line in enumerate(lines[:index]):
        stripped = line.strip()
        if stripped == "noncomputable section":
            last_noncomputable_section = line_index
        elif stripped == "end" or stripped.startswith("end "):
            last_end = line_index
    return last_noncomputable_section > last_end


def solution_declaration(source: str, problem: str) -> str | None:
    span = declaration_span(source, f"{problem}_solution")
    if span is None:
        return None
    lines = source.splitlines()
    start, end = span
    declaration = "\n".join(lines[start:end]).rstrip()
    if declaration.startswith(("abbrev ", "def ")) and in_noncomputable_section(
        lines, start
    ):
        declaration = "noncomputable " + declaration
    return declaration


def source_prefix_through_declaration(source: str, declaration_name: str) -> str | None:
    span = declaration_span(source, declaration_name)
    if span is None:
        return None
    lines = source.splitlines()
    return "\n".join(lines[: span[1]]).rstrip()


def formal_statement_with_candidate_solution(
    original_source: str,
    candidate_context_source: str,
    problem: str,
) -> tuple[str, bool]:
    """Use the candidate's concrete solution value in AXLE's expected theorem.

    PutnamBench originals encode the answer as `putnam_*_solution := sorry` and
    the theorem type refers to that abbreviation. If AXLE compares the theorem
    against that literal `sorry`-backed abbreviation, correct candidates can be
    rejected with an identical-looking signature mismatch. Keep the original
    theorem text intact, but elaborate the expected solution declaration in the
    same standalone prefix that the candidate uses. This matters for reducible
    answer declarations whose printed values are identical but whose elaborated
    environments differ.
    """
    declaration_name = f"{problem}_solution"
    original_span = declaration_span(original_source, declaration_name)
    if original_span is None:
        return original_source, False

    candidate_prefix = source_prefix_through_declaration(
        candidate_context_source, declaration_name
    )
    if candidate_prefix is not None:
        original_lines = original_source.splitlines()
        _start, end = original_span
        original_tail = "\n".join(original_lines[end:]).lstrip("\n")
        patched = candidate_prefix
        if original_tail:
            patched += "\n\n" + original_tail
        if original_source.endswith("\n"):
            patched += "\n"
        return patched, patched != original_source

    replacement = solution_declaration(candidate_context_source, problem)
    if replacement is None:
        return original_source, False

    lines = original_source.splitlines()
    start, end = original_span
    patched = "\n".join([*lines[:start], *replacement.splitlines(), *lines[end:]])
    if original_source.endswith("\n"):
        patched += "\n"
    return patched, patched != original_source


def verify_candidate(
    candidate: Path,
    originals_root: Path,
    *,
    api_url: str,
    environment: str,
    timeout: int,
    retries: int,
) -> dict[str, Any]:
    candidate = candidate.resolve()
    problem = problem_id(candidate)
    original = (originals_root / f"{problem}.lean").resolve()

    base = {
        "problem": problem,
        "candidate_path": str(candidate),
        "original_path": str(original),
        "api_url": api_url,
        "environment": environment,
    }

    if not candidate.is_file():
        return {**base, "status": "input_error", "okay": None,
                "error": "Candidate file does not exist"}
    if not original.is_file():
        return {**base, "status": "input_error", "okay": None,
                "error": "Original PutnamBench statement does not exist"}

    try:
        candidate_source = candidate.read_text()
        content = standalone_candidate(candidate)
        original_source = original.read_text()
        formal_statement, solution_patched = formal_statement_with_candidate_solution(
            original_source,
            content,
            problem,
        )
    except (OSError, UnicodeError) as exc:
        return {
            **base,
            "status": "input_error",
            "okay": None,
            "error": f"{type(exc).__name__}: {exc}",
        }
    payload = {
        "content": content,
        "formal_statement": formal_statement,
        "environment": environment,
    }
    hashes = {
        "candidate_sha256": hashlib.sha256(candidate_source.encode()).hexdigest(),
        "submitted_content_sha256": hashlib.sha256(content.encode()).hexdigest(),
        "original_sha256": hashlib.sha256(original_source.encode()).hexdigest(),
        "submitted_formal_statement_sha256": hashlib.sha256(
            formal_statement.encode()
        ).hexdigest(),
        "formal_statement_solution_patched": solution_patched,
    }

    try:
        response, http_status = post_json(
            api_url, payload, timeout=timeout, retries=retries
        )
    except Exception as exc:
        return {
            **base,
            **hashes,
            "status": "api_error",
            "okay": None,
            "error": f"{type(exc).__name__}: {exc}",
        }

    # post_json enforces this contract; keep the guard for defensive callers.
    okay = response.get("okay")
    if not isinstance(okay, bool):
        return {
            **base,
            **hashes,
            "status": "api_error",
            "okay": None,
            "http_status": http_status,
            "error": "AXLE response did not contain a Boolean 'okay' field",
            "response": compact_api_response(response),
        }

    return {
        **base,
        **hashes,
        "status": "correct" if okay else "incorrect",
        "okay": okay,
        "http_status": http_status,
        "request_id": (response.get("info") or {}).get("request_id"),
        "response": compact_api_response(response),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Call AXLE for one or more PutnamBench Lean candidates and compare "
            "each candidate with its original benchmark statement."
        )
    )
    parser.add_argument(
        "--candidate",
        action="append",
        required=True,
        type=Path,
        help="Candidate PutnamYYYYAN.lean or putnam_YYYY_aN.lean file; repeatable.",
    )
    parser.add_argument("--originals-root", type=Path)
    parser.add_argument("--api-url", default=DEFAULT_API_URL)
    parser.add_argument("--environment", default=DEFAULT_ENVIRONMENT)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--retries", type=int, default=4)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    try:
        originals_root = resolve_originals_root(args.originals_root)
    except Exception as exc:
        print(json.dumps({"status": "input_error", "error": str(exc)}, indent=2))
        return 2

    results = [
        verify_candidate(
            candidate,
            originals_root,
            api_url=args.api_url,
            environment=args.environment,
            timeout=args.timeout,
            retries=args.retries,
        )
        for candidate in args.candidate
    ]
    report = {"all_okay": all(item.get("okay") is True for item in results),
              "results": results}
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    print(rendered, end="")

    if any(item["status"] in {"api_error", "input_error"} for item in results):
        return 2
    if any(item.get("okay") is not True for item in results):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
