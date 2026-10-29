"""Project evidence checks and study summaries using the Cairn2 public API.

Copy beside experiments/run.py. This is project policy, not a Cairn plugin.
Run "python experiments/research_cairn.py --help" for evidence/study checks.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import tempfile
from typing import Any, Mapping

import cairn

_NAME = re.compile(r"[a-z0-9][a-z0-9-]{0,62}")


def _json(value: Any) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def _name(value: Any) -> str:
    if not isinstance(value, str) or not _NAME.fullmatch(value):
        raise ValueError("Run/study names must be lowercase slugs of at most 63 characters")
    return value


def _repo(options: Mapping[str, Any], root: Path) -> str | None:
    if set(options) - {"repo"}:
        raise ValueError("cairn config accepts only repo (a path or URL); credentials belong in token files")
    repo = options.get("repo")
    if repo is not None and "://" not in str(repo):
        repo = str((root / Path(repo).expanduser()).resolve())
    return repo


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
        temporary = Path(file.name)
        file.write(_json(value))
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def exact_ref(reader):
    return str(reader)


def require_completed_run(reader):
    if reader.namespace != "runs" or reader.outcome != "completed":
        raise ValueError(f"Run {reader.id} is not a completed producer")
    return reader


def publish_result(client, producer, *, name=None):
    """Opt in to a separate result artifact from a run’s added "result" folder."""
    require_completed_run(producer)
    with tempfile.TemporaryDirectory(prefix="research-result-") as temporary:
        folder = producer.download("result", to=temporary)
        result = client.start("artifacts", name or producer.name)
        result.use(producer, role="producer")
        result.finish(value=cairn.Directory(folder))
    return client.get(result.id)


def require_completed_artifact(client, ref: str):
    """Require immutable evidence with a completed run, not just an alias."""
    reader = client.get(ref)
    if reader.outcome != "completed":
        raise ValueError(f"Artifact {reader.id} has no verifiable completed producer")
    if reader.namespace == "runs":
        return require_completed_run(reader)
    producers = reader.inputs(role="producer")
    if len(producers) != 1:
        raise ValueError(f"Artifact {reader.id} has no verifiable completed producer")
    if producers[0].project != reader.project:
        raise ValueError("Result and producer must belong to the same project")
    require_completed_run(producers[0])
    return reader


def finalize_study(roster: Mapping[str, Any], *, project_root: Path, repo=None):
    """Publish a summary only for an explicit, fully completed trial roster."""
    project, name = roster["project"], _name(roster["name"])
    expected, runs = roster["expected_trials"], roster["runs"]
    if not isinstance(expected, list) or not expected or any(not isinstance(item, str) or not item for item in expected):
        raise ValueError("expected_trials must be a nonempty list of trial labels")
    if len(expected) != len(set(expected)) or not isinstance(runs, dict) or set(runs) != set(expected):
        raise ValueError("runs must match the explicit expected_trials exactly, without duplicates")
    if any(not isinstance(ident, str) or not ident for ident in runs.values()) or len(set(runs.values())) != len(runs):
        raise ValueError("Every trial must name a distinct full Cairn run ID")
    root = project_root.resolve(strict=True)
    trials = []
    with cairn.Client(_repo({"repo": repo}, root), project=project) as client:
        for label in expected:
            trial = require_completed_run(client.get(runs[label]))
            if trial.id != runs[label] or trial.project != project:
                raise ValueError(f"Trial {label} is missing or belongs to another project")
            trials.append({"trial": label, "run_id": trial.id, "status": "completed"})
        config = {"project": project, "run": {"name": name}, "study": dict(roster),
                  "cairn": {"repo": client.repo}}
        with client.run(name, config=config, metadata={"kind": "study"}) as run:
            output_dir = root / "outputs" / "studies" / run.id
            _write_json(output_dir / "cairn-run.json", {"project": project, "run_id": run.id})
            result_dir = output_dir / "result"
            _write_json(result_dir / "roster.json", dict(roster))
            _write_json(result_dir / "trials.json", trials)
            for trial in trials:
                run.use(trial["run_id"], role="trial")
            run.add(result_dir, name="result")
        return publish_result(client, client.get(run.id), name=name + "-study")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command, argument in (("check-artifact", "ref"), ("finalize-study", "roster")):
        sub = commands.add_parser(command)
        sub.add_argument(argument)
        sub.add_argument("--project", default="default")
        sub.add_argument("--repo", help="Repository path or server URL")
        if command == "finalize-study":
            sub.add_argument("--project-root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.command == "check-artifact":
        with cairn.Client(_repo({"repo": args.repo}, Path.cwd()), project=args.project) as client:
            reader = require_completed_artifact(client, args.ref)
    else:
        reader = finalize_study(json.loads(Path(args.roster).read_text()), project_root=args.project_root, repo=args.repo)
    print(f"{reader} ({reader.id})")


if __name__ == "__main__":
    main()
