"""Example entry point: a standard Hydra function writing plain files into its
output folder."""

import logging
from pathlib import Path

import hydra
import matplotlib.pyplot as plt
import numpy as np
from hydra.core.hydra_config import HydraConfig
from omegaconf import DictConfig

log = logging.getLogger(__name__)


@hydra.main(version_base="1.3", config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    out = Path(HydraConfig.get().runtime.output_dir)
    rng = np.random.default_rng(cfg.seed)
    x = np.linspace(-1.0, 1.0, cfg.data.n)
    y = 2.0 * x + 0.5 + rng.normal(0.0, cfg.data.noise, x.shape)

    w = np.zeros(2)
    history = []
    for step in range(cfg.steps + 1):
        residual = w[0] * x + w[1] - y
        loss = float(np.mean(residual**2))
        if step % cfg.log_every == 0:
            log.info("step %d loss %.4g", step, loss)
            history.append((step, loss))
        if step < cfg.steps:
            w -= 0.5 * np.array([np.mean(2 * residual * x), np.mean(2 * residual)])

    # Complete per-sample output, so any figure can be redrawn without refitting.
    np.savetxt(out / "loss.csv", history, delimiter=",", header="step,loss", comments="")
    np.savez(out / "samples.npz", sample_id=np.arange(x.size), x=x, y=y, residual=residual)

    fig, ax = plt.subplots(figsize=(4, 3))
    ax.scatter(x, y, s=4, label="samples")
    ax.plot(x, w[0] * x + w[1], color="C1", label="fit")
    ax.legend()
    fig.savefig(out / "fit.png", dpi=150, bbox_inches="tight")
    plt.close(fig)

    # Scientific validation: raise, so the job fails and latest does not move.
    if not loss < 2 * cfg.data.noise**2:
        raise RuntimeError(f"fit did not converge: loss {loss:.3g}")


if __name__ == "__main__":
    main()
