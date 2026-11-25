"""Standard Hydra entry point that logs one Cairn run."""

import sys
from pathlib import Path

import cairn
import hydra
from omegaconf import DictConfig, OmegaConf

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # flat project imports


@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    with cairn.run(
        cfg.run.name,
        config=OmegaConf.to_container(cfg, resolve=True, throw_on_missing=True),
        about={"description": cfg.run.description},
    ) as run:
        # Construct components with hydra.utils.instantiate(cfg.<component>).
        # Use run.use/log/add (or cairn.*) to read inputs and record results.
        # Perform scientific validation before leaving this block; raise on failure.
        raise NotImplementedError("Implement this Hydra entry point before running it")


if __name__ == "__main__":
    main()
