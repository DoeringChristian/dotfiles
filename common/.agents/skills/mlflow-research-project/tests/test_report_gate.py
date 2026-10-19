"""Behavior checks for the Folio report gate; stdlib unittest only."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "report_gate", Path(__file__).resolve().parents[1] / "scripts/report_gate.py"
)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)
PAPER = "\n\n".join("## " + title for title in (
    "Abstract", "Introduction", "Background and related work", "Methods",
    "Results and discussion", "Conclusion",
)) + "\n"


class ReportGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / "reports/method"
        self.folder.mkdir(parents=True)
        self.source = self.folder / "report.md"
        self.source.write_text(PAPER)
        (self.root / "folio.toml").write_text('[project]\noutput-dir = "custom-site"\n')
        self.proj = gate.Project(self.root)
        self.event = {"cwd": str(self.root)}
        self.quiet = patch.dict(os.environ, {key: "" for key in gate.QUIET_ENVS})
        self.quiet.start()
        self.addCleanup(self.quiet.stop)

    def built(self):
        payload = self.proj.output_dir / "reports/method/report.files"
        payload.mkdir(parents=True, exist_ok=True)
        (payload.parent / "report.html").write_text("built page")
        (payload / "manifest.json").write_text(json.dumps({
            "markdown_sha256": hashlib.sha256(self.source.read_bytes()).hexdigest()
        }))

    def test_no_project_does_nothing(self):
        with tempfile.TemporaryDirectory() as unrelated:
            self.assertIsNone(gate.gate({"cwd": unrelated}))

    def test_build_review_then_pass(self):
        self.assertIn("last build", gate.gate(self.event)["reason"])
        self.built()
        self.assertIn("R0-R9", gate.gate(self.event)["reason"])
        self.assertIsNone(gate.gate(dict(self.event, stop_hook_active=True)))
        self.assertIsNone(gate.gate(self.event))

    def test_unrebuilt_change_cannot_pass_active_hook(self):
        self.built()
        self.source.write_text(PAPER + "Changed conclusion.\n")
        self.assertEqual(gate.gate(dict(self.event, stop_hook_active=True))["decision"], "block")

    def test_asset_change_invalidates_review(self):
        self.built()
        self.assertIsNone(gate.gate(dict(self.event, stop_hook_active=True)))
        assets = self.folder / "assets"
        assets.mkdir()
        (assets / "diagram.svg").write_text("new diagram")
        self.assertIn("last build", gate.gate(self.event)["reason"])

    def test_structure_and_fenced_examples(self):
        self.assertFalse(gate.structure_problems(self.folder))
        self.source.write_text('---\ntitle: Paper\n---\n<!-- ## Ignored -->\n'
                               + PAPER.replace("## Methods", "```markdown\n## Fake\n```\n\n## Methods"))
        self.assertFalse(gate.structure_problems(self.folder))
        self.source.write_text(PAPER.replace("## Methods", "## Implementation"))
        self.built()
        self.assertIn("methods", gate.gate(dict(self.event, stop_hook_active=True))["reason"])
        self.source.write_text(PAPER + "\n## Abstract\n")
        self.assertTrue(gate.structure_problems(self.folder))

    def test_bounded_retries(self):
        for _ in range(gate.MAX_BLOCKS):
            self.assertEqual(gate.gate(self.event)["decision"], "block")
        self.assertIn("systemMessage", gate.gate(self.event))


if __name__ == "__main__":
    unittest.main()
