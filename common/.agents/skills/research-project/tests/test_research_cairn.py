"""Exercise the scaffold against the pinned Cairn2 public API."""
import importlib.util
import json
import subprocess
import sys
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


def client(root):
    return cairn.Client(root / ".cairn/repo", project="research-demo")


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
        assert not c.find("artifacts/*")


def test_study_summary_preserves_every_trial_and_public_lineage(project):
    with client(project) as c:
        ids = []
        for name in ("first", "second"):
            with c.run(name, provenance=False) as run:
                ids.append(run.id)
        study = helper.finalize_study(roster(*ids), project_root=project, repo=c.repo)
        result = helper.require_completed_artifact(c, study.id)
        result.download(to=project / "outputs/summary")
        assert json.loads((project / "outputs/summary/roster.json").read_text()) == roster(*ids)
        (producer,) = result.inputs(role="producer")
        assert {trial.id for trial in producer.inputs(role="trial")} == set(ids)


def test_separate_result_publication_is_explicit(project):
    with client(project) as c:
        folder = project / "outputs/staged"
        folder.mkdir(parents=True)
        (folder / "scores.json").write_text('{"loss":0.1}')
        with c.run("trial", provenance=False) as run:
            run.add(folder, name="result")
        assert not c.find("artifacts/*")
        result = helper.publish_result(c, c.get(run.id))
        checked = helper.require_completed_artifact(c, result.id)
        assert [producer.id for producer in checked.inputs(role="producer")] == [run.id]
        checked.download(to=project / "outputs/verified")
        assert json.loads((project / "outputs/verified/scores.json").read_text()) == {"loss": 0.1}


@pytest.mark.parametrize("fail", [False, True])
def test_native_hydra_scaffold_tracks_each_invocation(project, fail):
    assets = Path(__file__).parents[1] / "assets"
    experiments = project / "experiments"
    experiments.mkdir()
    body = 'cairn.log(seed=cfg.seed)'
    if fail:
        body += '\n        raise RuntimeError("scientific validation failed")'
    source = (assets / "run.py").read_text().replace(
        'raise NotImplementedError("Implement this Hydra entry point before running it")', body,
    )
    (experiments / "run.py").write_text(source)
    (project / ".cairn.toml").write_text('project = "research-demo"\nrepo = ".cairn/repo"\n')
    configs = project / "configs"
    configs.mkdir()
    cfg = {"seed": 0, "run": {"name": "original-name", "description": "Scaffold test"}, "hydra": {"job": {"chdir": False},
                               "sweep": {"dir": "outputs/sweep", "subdir": "${hydra.job.num}"}}}
    (configs / "config.yaml").write_text(OmegaConf.to_yaml(OmegaConf.create(cfg)))
    result = subprocess.run([sys.executable, str(experiments / "run.py"), "-m", "seed=1,2", "run.name=adjusted-name"],
                            cwd=project, capture_output=True, text=True, timeout=60)
    assert (result.returncode != 0) == fail, result.stdout + result.stderr
    with client(project) as c:
        runs = [c.get(f"runs/adjusted-name@v{n}") for n in (1, 2)]
        assert len({run.id for run in runs}) == 2
        assert all(run.config["run"]["name"] == "adjusted-name" for run in runs)
        assert {run.config["seed"] for run in runs} == {1, 2}
        assert {next(run.records())["seed"] for run in runs} == {1, 2}
        assert all(run.outcome == ("failed" if fail else "completed") for run in runs)
        assert all("provenance" in run.metadata for run in runs)
        assert not c.find("artifacts/*")
        if fail:
            with pytest.raises(ValueError, match="completed producer"):
                helper.require_completed_artifact(c, runs[0].id)
        else:
            assert helper.require_completed_artifact(c, runs[0].id).id == runs[0].id
