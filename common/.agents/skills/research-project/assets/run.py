"""Hydra entry point. Copy into a project as experiments/run.py.

    python experiments/run.py [overrides]            # one run
    python experiments/run.py -m key=a,b [overrides] # a study (Hydra multirun)

The job is a Cairn run (`cairn.init` is called by `run_experiment`): set
`hydra.run.dir` and `hydra.sweep.dir` to `${cairn.run:${run.name}}` and register the
callbacks in configs/config.yaml (see project-setup.md). The experiment gets the run
with `cairn.run()`, records inputs with `cairn.use(ref)`, and writes its results with
`with cairn.draft("<name>") as result: result.add_*(...)`.
"""

import sys
from pathlib import Path

import hydra
from omegaconf import DictConfig

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # flat imports from the project root

from cairn.runs.hydra import run_experiment  # noqa: E402
from experiments.base import Experiment  # noqa: E402


@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    run_experiment(cfg, Experiment)


if __name__ == "__main__":
    main()
