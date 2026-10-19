"""Copy to experiments/run.py; set MLFLOW_TRACKING_URI before running."""

import subprocess
import sys
from pathlib import Path

import hydra
import mlflow
from hydra.core.hydra_config import HydraConfig
from omegaconf import DictConfig, OmegaConf

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *args], text=True
    ).strip()


@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    root = Path(hydra.utils.get_original_cwd())
    output = Path(HydraConfig.get().runtime.output_dir)
    mlflow.set_experiment(cfg.tracking.experiment)
    with mlflow.start_run(run_name=cfg.tracking.run_name) as run:
        # Keep identity visible even if instantiation or execution fails.
        print(f"MLflow run: {run.info.run_id}", flush=True)
        mlflow.log_text(OmegaConf.to_yaml(cfg, resolve=True), "config.yaml")
        mlflow.log_text(
            OmegaConf.to_yaml(HydraConfig.get().overrides.task), "overrides.yaml"
        )
        mlflow.set_tags(
            {
                "source.commit": git(root, "rev-parse", "HEAD"),
                "source.dirty": str(bool(git(root, "status", "--porcelain"))).lower(),
            }
        )
        lock = root / "pixi.lock"
        if lock.exists():
            mlflow.log_artifact(str(lock), artifact_path="provenance")
        mlflow.log_param("seed", cfg.seed)
        experiment = hydra.utils.instantiate(cfg.experiment)
        experiment.run(output_dir=output)
        print(f"Report input: runs:/{run.info.run_id}/evaluation", flush=True)


if __name__ == "__main__":
    main()
