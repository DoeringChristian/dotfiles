"""Finish a Kuma study whose launcher process died. Copy into a project as experiments/finalize_study.py.

    pixi run python experiments/finalize_study.py outputs/<run-name>/<timestamp>

The submitit launcher writes the study's run.json from StudyCompletion only when
the launcher process outlives every trial. If it was killed (login-node reboot,
pkill), the trials keep running in Slurm but the study root stays incomplete.
Run this after every trial job has left the queue: it applies StudyCompletion's
rule (completed only when every submitted trial completed) and moves `latest`.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

sys.path.insert(
    0, str(Path(__file__).resolve().parent.parent)
)  # flat imports from the project root

from experiments.run import update_latest, validate_run_name, write_status  # noqa: E402


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
            raise SystemExit(
                f"trial {trial} is still 'running'; confirm with squeue/sacct that its job ended first"
            )
        records.append(record)
        trials.append({"trial": trial, "status": record.get("status", "missing")})
    if not trials:
        raise SystemExit(f"{study} has no trials")
    config = yaml.safe_load(
        (study / min(present, key=int) / ".hydra" / "config.yaml").read_text()
    )
    complete = all(trial["status"] == "completed" for trial in trials)
    write_status(
        study,
        {
            "status": "completed" if complete else "failed",
            "kind": "study",
            "name": validate_run_name(str(config["run"]["name"])),
            "started": min(
                (r["started"] for r in records if r.get("started")), default=None
            ),
            "ended": datetime.now(timezone.utc).isoformat(),
            "code_revision": next(
                (r["code_revision"] for r in records if r.get("code_revision")),
                "unversioned",
            ),
            "trials": trials,
            "finalized_by": "experiments/finalize_study.py",
        },
    )
    if complete:
        update_latest(study)
    print(f"{study}: {'completed' if complete else 'failed'} ({len(trials)} trials)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(Path(sys.argv[1]))
