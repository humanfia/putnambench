#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "scripts" / "verify-putnambench-axle.py"
SPEC = importlib.util.spec_from_file_location("axle_verifier", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeReply:
    status = 200

    def __init__(self, response: dict):
        self.body = json.dumps(response).encode()

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return self.body


class AxleVerifierTest(unittest.TestCase):
    def test_problem_id_supports_module_and_source_names(self):
        self.assertEqual(
            MODULE.problem_id(Path("MathFlowBench/Putnam2025A1.lean")),
            "putnam_2025_a1",
        )
        self.assertEqual(
            MODULE.problem_id(Path("putnam_1988_b6.lean")),
            "putnam_1988_b6",
        )

    def test_request_compares_candidate_with_original(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            originals = root / "originals"
            originals.mkdir()
            original = originals / "putnam_2025_a1.lean"
            candidate = root / "Putnam2025A1.lean"
            original.write_text("theorem putnam_2025_a1 : True := by sorry\n")
            candidate.write_text("theorem putnam_2025_a1 : True := by trivial\n")

            seen = {}

            def fake_urlopen(request, timeout):
                seen["payload"] = json.loads(request.data)
                seen["timeout"] = timeout
                return FakeReply(
                    {
                        "okay": True,
                        "content": "echoed candidate should not be persisted",
                        "info": {"request_id": "req-1"},
                    }
                )

            with mock.patch.object(MODULE.urllib.request, "urlopen", fake_urlopen):
                result = MODULE.verify_candidate(
                    candidate,
                    originals,
                    api_url="https://example.test/verify",
                    environment="lean-test",
                    timeout=12,
                    retries=0,
                )

            self.assertTrue(result["okay"])
            self.assertEqual(result["request_id"], "req-1")
            self.assertNotIn("content", result["response"])
            self.assertEqual(seen["payload"]["content"], candidate.read_text())
            self.assertEqual(
                seen["payload"]["formal_statement"], original.read_text()
            )
            self.assertEqual(seen["payload"]["environment"], "lean-test")
            self.assertEqual(seen["timeout"], 12)

    def test_formal_statement_uses_candidate_solution_declaration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            originals = root / "originals"
            originals.mkdir()
            original = originals / "putnam_2025_a1.lean"
            candidate = root / "Putnam2025A1.lean"
            original.write_text(
                "import Mathlib\n\n"
                "abbrev putnam_2025_a1_solution : ℕ := sorry\n\n"
                "theorem putnam_2025_a1 : putnam_2025_a1_solution = 7 := by sorry\n"
            )
            candidate.write_text(
                "import Mathlib\n\n"
                "abbrev putnam_2025_a1_solution : ℕ := 7\n\n"
                "theorem putnam_2025_a1 : putnam_2025_a1_solution = 7 := by rfl\n"
            )

            seen = {}

            def fake_urlopen(request, timeout):
                seen["payload"] = json.loads(request.data)
                return FakeReply({"okay": True})

            with mock.patch.object(MODULE.urllib.request, "urlopen", fake_urlopen):
                result = MODULE.verify_candidate(
                    candidate,
                    originals,
                    api_url="https://example.test/verify",
                    environment="lean-test",
                    timeout=12,
                    retries=0,
                )

            self.assertTrue(result["formal_statement_solution_patched"])
            self.assertIn(
                "abbrev putnam_2025_a1_solution : ℕ := 7",
                seen["payload"]["formal_statement"],
            )
            self.assertNotIn(
                "abbrev putnam_2025_a1_solution : ℕ := sorry",
                seen["payload"]["formal_statement"],
            )
            self.assertEqual(
                result["original_sha256"],
                MODULE.hashlib.sha256(original.read_text().encode()).hexdigest(),
            )
            self.assertEqual(
                result["submitted_formal_statement_sha256"],
                MODULE.hashlib.sha256(
                    seen["payload"]["formal_statement"].encode()
                ).hexdigest(),
            )

    def test_formal_statement_keeps_candidate_prefix_but_original_theorem(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            originals = root / "originals"
            originals.mkdir()
            original = originals / "putnam_2025_a1.lean"
            candidate = root / "Putnam2025A1.lean"
            original.write_text(
                "import Mathlib\n\n"
                "abbrev putnam_2025_a1_solution : ℕ := sorry\n\n"
                "theorem putnam_2025_a1 : putnam_2025_a1_solution = 7 := by sorry\n"
            )
            candidate.write_text(
                "import Mathlib\n\n"
                "private def expectedAnswer : ℕ := 7\n\n"
                "abbrev putnam_2025_a1_solution : ℕ := expectedAnswer\n\n"
                "theorem putnam_2025_a1 : putnam_2025_a1_solution = 7 := by rfl\n"
            )

            seen = {}

            def fake_urlopen(request, timeout):
                seen["payload"] = json.loads(request.data)
                return FakeReply({"okay": True})

            with mock.patch.object(MODULE.urllib.request, "urlopen", fake_urlopen):
                result = MODULE.verify_candidate(
                    candidate,
                    originals,
                    api_url="https://example.test/verify",
                    environment="lean-test",
                    timeout=12,
                    retries=0,
                )

            formal_statement = seen["payload"]["formal_statement"]
            self.assertTrue(result["formal_statement_solution_patched"])
            self.assertIn("private def expectedAnswer : ℕ := 7", formal_statement)
            self.assertIn(
                "abbrev putnam_2025_a1_solution : ℕ := expectedAnswer",
                formal_statement,
            )
            self.assertIn(
                "theorem putnam_2025_a1 : putnam_2025_a1_solution = 7 := by sorry",
                formal_statement,
            )
            self.assertNotIn(
                "theorem putnam_2025_a1 : putnam_2025_a1_solution = 7 := by rfl",
                formal_statement,
            )

    def test_formal_statement_marks_solution_noncomputable_from_section(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            originals = root / "originals"
            originals.mkdir()
            original = originals / "putnam_2022_a4.lean"
            candidate = root / "Putnam2022A4.lean"
            original.write_text(
                "import Mathlib\n\n"
                "abbrev putnam_2022_a4_solution : ℝ := sorry\n\n"
                "theorem putnam_2022_a4 : True := by trivial\n"
            )
            candidate.write_text(
                "import Mathlib\n\n"
                "noncomputable section\n\n"
                "abbrev putnam_2022_a4_solution : ℝ := Real.exp (1 / 2)\n\n"
                "theorem putnam_2022_a4 : True := by trivial\n"
            )

            seen = {}

            def fake_urlopen(request, timeout):
                seen["payload"] = json.loads(request.data)
                return FakeReply({"okay": True})

            with mock.patch.object(MODULE.urllib.request, "urlopen", fake_urlopen):
                result = MODULE.verify_candidate(
                    candidate,
                    originals,
                    api_url="https://example.test/verify",
                    environment="lean-test",
                    timeout=12,
                    retries=0,
                )

            self.assertTrue(result["formal_statement_solution_patched"])
            self.assertIn("noncomputable section", seen["payload"]["formal_statement"])
            self.assertIn(
                "abbrev putnam_2022_a4_solution : ℝ := "
                "Real.exp (1 / 2)",
                seen["payload"]["formal_statement"],
            )

    def test_standalone_candidate_inlines_local_mathflowbench_imports(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            modules = root / "MathFlowBench"
            helpers = modules / "Helpers"
            helpers.mkdir(parents=True)
            (helpers / "Basic.lean").write_text(
                "import Mathlib.Algebra.Group.Basic\n\nlemma helper : True := by trivial\n"
            )
            candidate = modules / "Putnam2025A1.lean"
            candidate.write_text(
                "import Mathlib\n"
                "import MathFlowBench.Helpers.Basic\n\n"
                "theorem putnam_2025_a1 : True := helper\n"
            )

            content = MODULE.standalone_candidate(candidate)

            self.assertIn("import Mathlib.Algebra.Group.Basic", content)
            self.assertIn("import Mathlib", content)
            self.assertNotIn("import MathFlowBench.Helpers.Basic", content)
            self.assertLess(content.index("lemma helper"), content.index("theorem putnam"))

    def test_post_json_retries_response_without_boolean_okay(self):
        replies = iter(
            [
                FakeReply({"message": "temporarily unavailable"}),
                FakeReply({"okay": True}),
            ]
        )

        with mock.patch.object(
            MODULE.urllib.request, "urlopen", side_effect=lambda *_args, **_kwargs: next(replies)
        ) as urlopen, mock.patch.object(MODULE.time, "sleep"):
            response, status = MODULE.post_json(
                "https://example.test/verify",
                {"content": "proof", "formal_statement": "statement"},
                timeout=12,
                retries=1,
            )

        self.assertEqual(status, 200)
        self.assertTrue(response["okay"])
        self.assertEqual(urlopen.call_count, 2)

    def test_network_error_is_unavailable_not_false(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            originals = root / "originals"
            originals.mkdir()
            (originals / "putnam_2025_a1.lean").write_text(
                "theorem putnam_2025_a1 : True := by sorry\n"
            )
            candidate = root / "Putnam2025A1.lean"
            candidate.write_text("theorem putnam_2025_a1 : True := by trivial\n")

            with mock.patch.object(
                MODULE.urllib.request,
                "urlopen",
                side_effect=urllib.error.URLError("offline"),
            ):
                result = MODULE.verify_candidate(
                    candidate,
                    originals,
                    api_url="https://example.test/verify",
                    environment="lean-test",
                    timeout=1,
                    retries=0,
                )

            self.assertEqual(result["status"], "api_error")
            self.assertIsNone(result["okay"])

    def test_explicit_false_is_a_rejection_and_is_not_retried(self):
        with mock.patch.object(
            MODULE.urllib.request,
            "urlopen",
            return_value=FakeReply({"okay": False}),
        ) as urlopen:
            response, status = MODULE.post_json(
                "https://example.test/verify",
                {"content": "proof", "formal_statement": "statement"},
                timeout=12,
                retries=4,
            )

        self.assertEqual(status, 200)
        self.assertIs(response["okay"], False)
        self.assertEqual(urlopen.call_count, 1)


if __name__ == "__main__":
    unittest.main()
