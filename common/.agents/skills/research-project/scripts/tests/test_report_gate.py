"""Behavior checks for report freshness and bounded whole-report review."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("report_gate", Path(__file__).parents[1] / "report_gate.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class ReportGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "pixi.toml").write_text("[workspace]\nname='test'\n")
        self.env = patch.dict(os.environ, {name: "" for name in gate.QUIET_ENVS})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.serial = 0

    def report(self, extension="md", slug="study"):
        folder = self.root / "reports" / slug
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"report.{extension}").write_text("---\ntitle: Study\n---\n\n## Methods\nA method.\n")
        return folder

    def built(self, folder, status="completed"):
        """Write the documented output contract independently of gate helpers."""
        self.serial += 1
        build = self.root / ".cairn" / "report-builds" / str(self.serial)
        output = build / folder.name
        output.mkdir(parents=True)
        sources = {p.relative_to(folder).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in folder.rglob("*") if p.is_file()
                   and not any(x.startswith(".") or x == "__pycache__" for x in p.relative_to(folder).parts)}
        (output / "sources").mkdir()
        for name in sources:
            destination = output / "sources" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((folder / name).read_bytes())
        (output / "manifest.json").write_text(json.dumps({
            "status": "complete" if status == "completed" else status,
            "files": [{"path": "sources/" + name, "digest": digest} for name, digest in sources.items()],
        }))
        for name in ("index.html", "document.json", "source-map.json", "executed.ipynb"):
            (output / name).write_text("{}")
        (build / "status.json").write_text(json.dumps({"status": status}))
        preview = self.root / ".cairn" / "build" / folder.name
        preview.parent.mkdir(parents=True, exist_ok=True)
        if preview.is_symlink():
            preview.unlink()
        preview.symlink_to(output, target_is_directory=True)
        return output

    def call(self, **event):
        return gate.gate({"cwd": str(self.root), **event})

    def assert_stale(self):
        reply = self.call(stop_hook_active=True)
        self.assertEqual(reply["decision"], "block")
        self.assertIn("no successful build", reply["reason"])

    def test_md_qmd_and_nested_cwd_work_with_remote_destination_and_journal(self):
        first, second = self.report(), self.report("qmd", "other")
        self.built(first)
        self.built(second)
        with patch.dict(os.environ, {"CAIRN_REPO": "https://server.example", "CAIRN_DIR": "/unrelated/journals"}):
            self.assertIsNone(self.call(cwd=str(second), stop_hook_active=True))
        state = self.root / ".cairn" / "reviews" / "gate.json"
        self.assertEqual(set(json.loads(state.read_text())["passed"]), {"study", "other"})

    def test_explicit_root_and_nested_project_boundary(self):
        folder = self.report()
        self.built(folder)
        nested = self.root / "another-project"
        nested.mkdir()
        (nested / "pyproject.toml").write_text("")
        self.assertIsNone(gate.project(nested))
        self.assertIsNone(self.call(cwd=str(nested), project_dir="..", stop_hook_active=True))
        self.assertTrue((self.root / ".cairn/reviews/gate.json").is_file())

    def test_backdated_change_is_stale(self):
        folder = self.report()
        self.built(folder)
        self.assertIsNone(self.call(stop_hook_active=True))
        entry = folder / "report.md"
        entry.write_text(entry.read_text() + "New evidence.\n")
        os.utime(entry, (1, 1))
        self.assert_stale()

    def test_add_and_delete_helpers_are_stale(self):
        folder = self.report()
        helper = folder / "helpers" / "analysis.py"
        helper.parent.mkdir()
        self.built(folder)
        helper.write_text("VALUE = 2\n")
        os.utime(helper, (1, 1))
        self.assert_stale()
        self.built(folder)
        self.assertIsNone(self.call(stop_hook_active=True))
        helper.unlink()
        self.assert_stale()

    def test_cache_and_hidden_files_do_not_change_capture(self):
        folder = self.report()
        self.built(folder)
        (folder / ".scratch").write_text("not captured")
        (folder / "__pycache__").mkdir()
        (folder / "__pycache__" / "helper.pyc").write_bytes(b"not captured")
        self.assertIsNone(self.call(stop_hook_active=True))

    def test_failed_new_build_does_not_make_old_preview_current(self):
        folder = self.report()
        self.built(folder)
        (folder / "report.md").write_text("New source that failed to execute.\n")
        failed = self.root / ".cairn/report-builds/failed"
        failed.mkdir()
        (failed / "status.json").write_text('{"status": "failed"}')
        self.assert_stale()
        self.built(folder, status="failed")
        self.assert_stale()

    def test_missing_output_or_status_is_stale_even_after_pass(self):
        folder = self.report()
        output = self.built(folder)
        self.assertIsNone(self.call(stop_hook_active=True))
        (output / "document.json").unlink()
        self.assert_stale()
        output = self.built(folder)
        (output / "manifest.json").unlink()
        self.assert_stale()

    def test_ambiguous_entries_and_symlinks_block(self):
        folder = self.report()
        self.built(folder)
        (folder / "report.qmd").write_text("another entry")
        self.assertIn("exactly one", self.call()["reason"])
        (folder / "report.qmd").unlink()
        (folder / "helper.py").symlink_to(self.root / "pixi.toml")
        self.assertIn("symlink", self.call()["reason"])

    def test_review_requested_once_then_passed_after_review(self):
        folder = self.report()
        self.built(folder)
        review = self.call()
        self.assertEqual(review["decision"], "block")
        self.assertIn("R1-R9", review["reason"])
        self.assertIn("each whole report", review["reason"])
        self.assertIsNone(self.call(stop_hook_active=True))
        self.assertIsNone(self.call())

    def test_retry_budget_does_not_silently_mark_stale_source_passed(self):
        self.report()
        for _ in range(gate.MAX_BLOCKS):
            self.assertEqual(self.call()["decision"], "block")
        message = self.call()
        self.assertNotIn("decision", message)
        self.assertIn("still open", message["systemMessage"])
        state = json.loads((self.root / ".cairn/reviews/gate.json").read_text())
        self.assertNotIn("study", state.get("passed", {}))

    def test_review_itself_is_bounded_for_hosts_that_ignore_active_flag(self):
        self.built(self.report())
        for _ in range(gate.MAX_BLOCKS):
            self.assertEqual(self.call()["decision"], "block")
        self.assertIn("R1-R9", self.call()["systemMessage"])

    def test_unchanged_sample_skips_review_but_requires_build(self):
        folder = self.root / "reports" / "sample"
        shutil.copytree(gate.SAMPLE, folder)
        self.assert_stale()
        self.built(folder)
        self.assertIsNone(self.call())


if __name__ == "__main__":
    unittest.main()
