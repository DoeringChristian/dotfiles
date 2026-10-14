"""Hydra entry point. Copy into a project as experiments/run.py.

    python experiments/run.py [overrides]            # one run
    python experiments/run.py -m key=a,b [overrides] # a study (Hydra multirun)

The run bookkeeping (run.json, latest, the source snapshot check) is cairn-report's
`run_experiment`; register its callbacks in configs/config.yaml (see project-setup.md).
"""

import sys
from pathlib import Path

import hydra
from omegaconf import DictConfig

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # flat imports from the project root

from cairn_report.runs import run_experiment  # noqa: E402
from experiments.base import Experiment  # noqa: E402


@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    run_experiment(cfg, Experiment)


if __name__ == "__main__":
    main()
