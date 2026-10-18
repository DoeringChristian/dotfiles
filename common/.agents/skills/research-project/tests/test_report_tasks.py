"""Build, publish, export and review the actual bundled sample with Cairn2."""
import importlib.util
from pathlib import Path
import shutil

from cairn import Client, Directory
from cairn.reports import export
import pytest

ROOT = Path(__file__).parents[1]


def module(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def test_sample_build_publication_export_and_source_gate(tmp_path):
    tasks = module("report_tasks", "assets/report_tasks.py")
    gate = module("report_gate", "scripts/report_gate.py")
    source = tmp_path / "reports/direction"
    shutil.copytree(ROOT / "assets/reports/direction", source)
    with Client(tmp_path / ".cairn/repo", project="demo") as client:
        sample = client.start("datasets", "sample-run")
        sample.finish(value=Directory(ROOT / "assets/sample-run"))
        result = tasks.build_report(tmp_path, "direction", client)
        assert gate.built_is_current(gate.Project(tmp_path), "direction", gate.source_hashes(source))
        published = tasks.publish(result.path, client=client, name="direction")
        assert published["manifest"]["dependencies"] == [{"artifact_id": sample.id, "role": "report-input:result"}]
        exported = export(published["id"], tmp_path / "export", client=client)
        assert (exported / "document.json").read_bytes() == (result.path / "document.json").read_bytes()
        (source / "uncaptured.py").write_text("value = 1")
        assert not gate.built_is_current(gate.Project(tmp_path), "direction", gate.source_hashes(source))
        with pytest.raises(ValueError, match="cairn.resources"):
            tasks.build_report(tmp_path, "direction", client)
        assert (tmp_path / ".cairn/build/direction").resolve() == result.path.resolve()
