"""Hydra entry point; copy beside research_cairn.py as experiments/run.py."""

import sys
from pathlib import Path

import hydra
from hydra.core.hydra_config import HydraConfig
from hydra.utils import get_original_cwd
from omegaconf import DictConfig

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # flat imports from the project root

from experiments.base import Experiment  # noqa: E402
from experiments.research_cairn import run_experiment  # noqa: E402


@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    run_experiment(
        cfg, Experiment, project_root=Path(get_original_cwd()),
        output_dir=Path(HydraConfig.get().runtime.output_dir),
    )


if __name__ == "__main__":
    main()
