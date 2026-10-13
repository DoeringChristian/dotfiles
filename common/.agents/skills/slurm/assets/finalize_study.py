"""Finish a Slurm study whose launcher process died. Copy next to cluster.sh in the project.

    pixi run <cluster> finalize outputs/<run-name>/<timestamp>

For projects whose entry point records each run's completion in `run.json` (a
`status` of running, completed, or failed) and whose launcher writes the study's
own `run.json` when the multirun ends. The submitit launcher can only do that
when its process outlives every trial; if it was killed (login-node reboot,
pkill), the trials keep running in Slurm but the study root stays incomplete.
Run this after every trial job has left the queue. It applies the same rule as
the launcher's completion step (the study is completed only when every
submitted trial completed), writes the study's `run.json` in the same format,
and points `<run-name>/latest` at the study (a relative symlink) when it
completed. Self-contained: it needs only PyYAML.
"""

from __future__ import annotations

import json
import os
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import yaml

RUN_NAME = re.compile(r"[a-z0-9][a-z0-9-]{0,62}")


def write_status(run_dir: Path, record: dict) -> None:
    """Write run.json atomically, so readers never see a partial record."""
    temporary = run_dir / f".run.json.{uuid.uuid4().hex}"
    temporary.write_text(json.dumps(record, indent=2) + "\n")
    os.replace(temporary, run_dir / "run.json")


def update_latest(run_dir: Path) -> Path:
    """Point <run-name>/latest at a completed run directory with a relative symlink."""
    run_dir = Path(run_dir).resolve(strict=True)
    status = json.loads((run_dir / "run.json").read_text()).get("status")
    if status != "completed":
        raise RuntimeError(f"{run_dir} is {status!r}; only completed runs become latest")
    link = run_dir.parent / "latest"
    if link.exists() and not link.is_symlink():
        raise RuntimeError(f"{link} exists and is not a symlink; resolve the conflict by hand")
    temporary = run_dir.parent / f".latest-{uuid.uuid4().hex}"
    os.symlink(run_dir.name, temporary)
    if temporary.resolve() != run_dir:
        temporary.unlink()
        raise RuntimeError(f"temporary link does not resolve to {run_dir}")
    os.replace(temporary, link)
    return link


def run_name(study: Path, present: set[str]) -> str:
    """The study's run name: `run.name` from a trial's Hydra config, else the study's parent folder."""
    config_file = study / min(present, key=int) / ".hydra" / "config.yaml" if present else None
    config = yaml.safe_load(config_file.read_text()) if config_file and config_file.is_file() else {}
    name = str(((config or {}).get("run") or {}).get("name") or study.parent.name)
    if not RUN_NAME.fullmatch(name):
        raise SystemExit(f"run name {name!r} must be a short lowercase slug ({RUN_NAME.pattern})")
    return name


def main(study: Path) -> None:
    study = study.resolve(strict=True)
    if (study / "run.json").exists():
        raise SystemExit(f"{study}/run.json already exists; nothing to finalize")
    submitted = {
        p.name.rsplit("_", 1)[1]
        for p in (study / ".submitit").glob("*_*")
        if p.name.rsplit("_", 1)[1].isdigit()
    }
    present = {p.name for p in study.iterdir() if p.is_dir() and p.name.isdigit()}
    trials, records = [], []
    for trial in sorted(submitted | present, key=int):
        status_file = study / trial / "run.json"
        record = json.loads(status_file.read_text()) if status_file.is_file() else {}
        if record.get("status") == "running":
            raise SystemExit(f"trial {trial} is still 'running'; confirm with squeue/sacct that its job ended first")
        records.append(record)
        trials.append({"trial": trial, "status": record.get("status", "missing")})
    if not trials:
        raise SystemExit(f"{study} has no trials")
    complete = all(trial["status"] == "completed" for trial in trials)
    write_status(
        study,
        {
            "status": "completed" if complete else "failed",
            "kind": "study",
            "name": run_name(study, present),
            "started": min((r["started"] for r in records if r.get("started")), default=None),
            "ended": datetime.now(timezone.utc).isoformat(),
            "code_revision": next((r["code_revision"] for r in records if r.get("code_revision")), "unversioned"),
            "trials": trials,
            "finalized_by": "finalize_study.py",
        },
    )
    if complete:
        update_latest(study)
    print(f"{study}: {'completed' if complete else 'failed'} ({len(trials)} trials)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(Path(sys.argv[1]))
