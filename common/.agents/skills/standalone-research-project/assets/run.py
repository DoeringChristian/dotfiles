"""Hydra entry point and run bookkeeping. Copy into a project as experiments/run.py.

    python experiments/run.py [overrides]            # one run
    python experiments/run.py -m key=a,b [overrides] # a study (Hydra multirun)

Every run directory gets `run.json`, the single completion record:
`running` before experiment code, then `completed` or `failed` (with the error).
Only a completed single run advances outputs/<run-name>/latest.

For a multirun, register `StudyCompletion` in configs/config.yaml:

    hydra:
      callbacks:
        study_completion:
          _target_: experiments.run.StudyCompletion

After the last trial it writes the study root's run.json (completed only when
every trial completed) and then advances `latest` to the study root. Trials never
touch `latest`, so parallel trials cannot race on it.

The entry point knows nothing experiment-specific: it instantiates the configured
`Experiment` and calls `run(output_dir)`.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import traceback
import uuid
from datetime import datetime, timezone
from pathlib import Path

import hydra
from hydra.core.hydra_config import HydraConfig
from hydra.experimental.callback import Callback
from hydra.types import RunMode
from hydra.utils import get_original_cwd, instantiate
from omegaconf import DictConfig

sys.path.insert(
    0, str(Path(__file__).resolve().parent.parent)
)  # flat imports from the project root

from experiments.base import Experiment  # noqa: E402
from provenance.source_snapshot import require_snapshot  # noqa: E402

RUN_NAME = re.compile(r"[a-z0-9][a-z0-9-]{0,62}")


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def code_revision(root: Path) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unversioned"


def validate_run_name(name: str) -> str:
    if not RUN_NAME.fullmatch(name):
        raise ValueError(
            f"run.name {name!r} must be a short lowercase slug ({RUN_NAME.pattern})"
        )
    return name


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
        raise RuntimeError(
            f"{run_dir} is {status!r}; only completed runs become latest"
        )
    link = run_dir.parent / "latest"
    if link.exists() and not link.is_symlink():
        raise RuntimeError(
            f"{link} exists and is not a symlink; resolve the conflict by hand"
        )
    temporary = run_dir.parent / f".latest-{uuid.uuid4().hex}"
    os.symlink(run_dir.name, temporary)
    if temporary.resolve() != run_dir:
        temporary.unlink()
        raise RuntimeError(f"temporary link does not resolve to {run_dir}")
    os.replace(temporary, link)
    return link


class StudyCompletion(Callback):
    """Mark a multirun study completed only when every trial completed, then move latest."""

    def on_multirun_start(self, config: DictConfig, **kwargs) -> None:
        # Hydra caches ${now:...}, so this resolves to the same directory the launcher uses.
        self.study = Path(config.hydra.sweep.dir).resolve()
        self.started = now()
        self.revision = code_revision(Path.cwd())

    def on_multirun_end(self, config: DictConfig, **kwargs) -> None:
        study = getattr(self, "study", Path(config.hydra.sweep.dir).resolve())
        trials = []
        for folder in (
            sorted(study.iterdir(), key=lambda path: (len(path.name), path.name))
            if study.is_dir()
            else []
        ):
            if folder.is_dir() and folder.name.isdigit():
                status_file = folder / "run.json"
                status = (
                    json.loads(status_file.read_text()).get("status")
                    if status_file.is_file()
                    else "missing"
                )
                trials.append({"trial": folder.name, "status": status})
        complete = bool(trials) and all(
            trial["status"] == "completed" for trial in trials
        )
        study.mkdir(parents=True, exist_ok=True)
        write_status(
            study,
            {
                "status": "completed" if complete else "failed",
                "kind": "study",
                "name": validate_run_name(str(config.run.name)),
                "started": getattr(self, "started", None),
                "ended": now(),
                "code_revision": getattr(self, "revision", code_revision(Path.cwd())),
                "trials": trials,
            },
        )
        if complete:
            update_latest(study)


@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    hydra_cfg = HydraConfig.get()
    output_dir = Path(hydra_cfg.runtime.output_dir).resolve()
    record = {
        "status": "running",
        "name": validate_run_name(str(cfg.run.name)),
        "description": str(cfg.run.get("description", "")),
        "started": now(),
        "code_revision": code_revision(Path(get_original_cwd())),
    }
    write_status(output_dir, record)
    try:
        # Hydra reports callback exceptions as warnings, so a missing snapshot must fail here.
        require_snapshot(output_dir)
        experiment = instantiate(cfg.experiment, _convert_="all")
        if not isinstance(experiment, Experiment):
            raise TypeError(
                f"{type(experiment).__name__} does not implement Experiment"
            )
        experiment.run(output_dir)
    except BaseException as error:
        write_status(
            output_dir,
            {
                **record,
                "status": "failed",
                "ended": now(),
                "error": f"{type(error).__name__}: {error}",
                "traceback": traceback.format_exc(),
            },
        )
        raise
    write_status(output_dir, {**record, "status": "completed", "ended": now()})
    if hydra_cfg.mode == RunMode.RUN:
        update_latest(output_dir)


if __name__ == "__main__":
    main()
