"""Exercise the scaffold against the pinned Cairn2 public API."""
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path

import cairn
import pytest
from omegaconf import OmegaConf

SPEC = importlib.util.spec_from_file_location("research_cairn", Path(__file__).parents[1] / "assets/research_cairn.py")
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


@pytest.fixture
def project(tmp_path, monkeypatch):
    root = tmp_path / "project"
    root.mkdir()
    (root / "method.py").write_text("def compute():\n    return 42\n")
    (root / "pixi.lock").write_text("version: 6\nenvironments: {}\n")
    for key in ("CAIRN_REPO", "CAIRN_TOKEN", "CAIRN_TOKEN_FILE"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.chdir(root)
    return root


def config(root, **kwargs):
    return {"project": "research-demo", "run": {"name": "trial"},
            "cairn": {"repo": str(root / ".cairn/repo")}, **kwargs}


def client(root):
    return cairn.Client(root / ".cairn/repo", project="research-demo")


def test_provenance_is_exact_and_excludes_credentials_libraries_and_symlinks(project, monkeypatch):
    subprocess.run(["git", "init", "-q", str(project)], check=True)
    (project / ".gitignore").write_text("ignored.py\n")
    (project / "ignored.py").write_text("DO_NOT_CAPTURE")
    for relative in (".env.json", "credentials.json", "secrets.yaml", "token.json",
                     "secrets/config.py", ".pixi/library.py", ".ssh/config.py", "outputs/generated.py"):
        path = project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("DO_NOT_CAPTURE")
    (project / "bad_encoding.py").write_bytes(b"\xff")
    (project / "link.py").symlink_to(project / "method.py")
    monkeypatch.setenv("UNRELATED_SECRET", "DO_NOT_CAPTURE")
    monkeypatch.setenv("OMP_NUM_THREADS", "2")
    with client(project) as c:
        with c.run("trial", provenance=False) as run:
            helper.capture_provenance(run, project_root=project, output_dir=project / "outputs/job", config=config(project))
        target = c.resolve(run.id).download("project-provenance", to=project / "outputs")
        entries = {p.relative_to(target).as_posix(): p.read_bytes() for p in target.rglob("*") if p.is_file()}
    assert entries["source/method.py"] == (project / "method.py").read_bytes()
    assert b"cairn2==0.6.0" in entries["environment/packages.txt"]
    assert not any(b"DO_NOT_CAPTURE" in content for content in entries.values())
    runtime = json.loads(entries["environment/runtime.json"])
    assert runtime["environment"]["OMP_NUM_THREADS"] == "2"
    assert "UNRELATED_SECRET" not in runtime["environment"]
    manifest = json.loads(entries["manifest.json"])
    assert {item["reason"] for item in manifest["skipped"]} == {"symlink", "not UTF-8"}
    for path, facts in manifest["files"].items():
        assert facts["sha256"] == hashlib.sha256(entries[path]).hexdigest()


@pytest.mark.parametrize("fault", ["missing_lock", "lock_symlink", "large_file", "total_limit", "empty_inventory", "secret_config"])
def test_required_provenance_fails_closed(project, monkeypatch, fault):
    cfg, kwargs = config(project), {}
    if fault == "missing_lock":
        (project / "pixi.lock").unlink()
    elif fault == "lock_symlink":
        (project / "pixi.lock").unlink()
        (project / "pixi.lock").symlink_to(project / "method.py")
    elif fault == "large_file":
        (project / "large.py").write_bytes(b"x" * (1024 * 1024 + 1))
    elif fault == "total_limit":
        kwargs["max_total_bytes"] = 10
    elif fault == "empty_inventory":
        monkeypatch.setattr(helper.importlib.metadata, "distributions", lambda: [])
    else:
        cfg["credentials"] = "must-not-be-recorded"
    with client(project) as c:
        with pytest.raises((ValueError, FileNotFoundError)):
            with c.run("trial", provenance=False) as run:
                helper.capture_provenance(run, project_root=project, output_dir=project / "outputs/job", config=cfg, **kwargs)
        assert c.resolve(run.id).descriptor["manifest"]["outcome"] == "failed"


class Experiment:
    def run(self, run, output_dir):
        raise NotImplementedError


class Example(Experiment):
    def __init__(self, root, fail=False):
        self.root, self.fail = Path(root), fail
        (self.root / "method.py").write_text("CHANGED_IN_CONSTRUCTOR")

    def run(self, run, output_dir):
        run.log(loss=0.1)
        run.add(b'{"loss":0.1}', name="scores.json")
        folder = output_dir / "result"
        folder.mkdir(parents=True)
        (folder / "result.json").write_text('{"loss":0.1}')
        if self.fail:
            raise RuntimeError("scientific validation failed")


@pytest.mark.parametrize("fail", [False, True])
def test_runner_records_directly_without_implicit_staging_or_publication(project, fail):
    cfg = OmegaConf.create(config(project, experiment={"_target_": __name__ + ".Example", "root": str(project), "fail": fail}))
    output = project / "outputs/job"
    if fail:
        with pytest.raises(RuntimeError, match="scientific validation failed"):
            helper.run_experiment(cfg, Experiment, project_root=project, output_dir=output)
    else:
        helper.run_experiment(cfg, Experiment, project_root=project, output_dir=output)
    ident = json.loads((output / "cairn-run.json").read_text())["run_id"]
    with client(project) as c:
        producer = c.resolve(ident)
        assert producer.descriptor["manifest"]["outcome"] == ("failed" if fail else "completed")
        provenance = producer.download("project-provenance", to=output)
        assert (provenance / "source/method.py").read_text() == "def compute():\n    return 42\n"
        if fail:
            with pytest.raises(cairn.NotFound):
                c.resolve("artifacts/trial@latest")
            with pytest.raises(ValueError, match="completed producer"):
                helper.require_completed_artifact(c, ident)
        else:
            result = helper.require_completed_artifact(c, ident)
            assert result.records()[0]["data"]["loss"] == 0.1
            scores = result.download("scores.json", to=output)
            assert json.loads(scores.read_text()) == {"loss": 0.1}
            assert "result" not in result.descriptor["manifest"]["captures"]
            assert not list(c.find(namespace="artifacts"))
            assert not (output / "cairn-result.json").exists()


def test_missing_lock_prevents_constructor(project):
    (project / "pixi.lock").unlink()
    cfg = OmegaConf.create(config(project, experiment={"_target_": "does.not.exist.Experiment"}))
    output = project / "outputs/job"
    with pytest.raises(FileNotFoundError):
        helper.run_experiment(cfg, Experiment, project_root=project, output_dir=output)
    with client(project) as c:
        ident = json.loads((output / "cairn-run.json").read_text())["run_id"]
        assert c.resolve(ident).descriptor["manifest"]["outcome"] == "failed"


def test_runless_and_failed_producers_cannot_certify_evidence(project):
    with client(project) as c:
        sample = c.start("datasets", "sample")
        sample.finish(value={"synthetic": True})
        with pytest.raises(ValueError, match="completed producer"):
            helper.require_completed_artifact(c, sample.id)
        failed = c.run("failed", provenance=False)
        failed.finish(outcome="failed")
        with c.start("artifacts", "manual") as result:
            result.use(failed.id, role="producer")
        with pytest.raises(ValueError, match="completed producer"):
            helper.require_completed_artifact(c, result.id)


def roster(*ids):
    return {"project": "research-demo", "name": "study", "expected_trials": [str(i) for i in range(len(ids))],
            "runs": {str(i): ident for i, ident in enumerate(ids)}}


@pytest.mark.parametrize("fault", ["missing", "extra", "duplicate_label", "duplicate_run", "missing_run", "failed", "running"])
def test_study_refuses_incomplete_or_ambiguous_roster(project, fault):
    with client(project) as c:
        first, second = c.run("first", provenance=False), c.run("second", provenance=False)
        first.finish()
        if fault != "running":
            second.finish(outcome="failed" if fault == "failed" else "completed")
        data = roster(first.id, second.id)
        if fault == "missing":
            del data["runs"]["1"]
        elif fault == "extra":
            data["runs"]["2"] = "extra"
        elif fault == "duplicate_label":
            data["expected_trials"] = ["0", "0"]
        elif fault == "duplicate_run":
            data["runs"]["1"] = first.id
        elif fault == "missing_run":
            data["runs"]["1"] = "0" * 32
        with pytest.raises((ValueError, cairn.CairnError)):
            helper.finalize_study(data, project_root=project, repo=c.repo)
        assert not list(c.find(namespace="artifacts"))


def test_study_summary_preserves_every_trial_and_public_lineage(project):
    with client(project) as c:
        ids = []
        for name in ("first", "second"):
            with c.run(name, provenance=False) as run:
                ids.append(run.id)
        descriptor = helper.finalize_study(roster(*ids), project_root=project, repo=c.repo)
        result = helper.require_completed_artifact(c, descriptor["id"])
        result.download(to=project / "outputs/summary")
        assert json.loads((project / "outputs/summary/roster.json").read_text()) == roster(*ids)
        producer = c.resolve(result.descriptor["manifest"]["dependencies"][0]["artifact_id"])
        assert {d["artifact_id"] for d in producer.descriptor["manifest"]["dependencies"]} == set(ids)


def test_separate_result_publication_is_explicit(project):
    with client(project) as c:
        folder = project / "outputs/staged"
        folder.mkdir(parents=True)
        (folder / "scores.json").write_text('{"loss":0.1}')
        with c.run("trial", provenance=False) as run:
            run.add(folder, name="result")
        assert not list(c.find(namespace="artifacts"))
        result = helper.publish_result(c, c.resolve(run.id))
        checked = helper.require_completed_artifact(c, result.id)
        assert checked.descriptor["manifest"]["dependencies"] == [
            {"artifact_id": run.id, "role": "producer"}
        ]
        checked.download(to=project / "outputs/verified")
        assert json.loads((project / "outputs/verified/scores.json").read_text()) == {"loss": 0.1}
