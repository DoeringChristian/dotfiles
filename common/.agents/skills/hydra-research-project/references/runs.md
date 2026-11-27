# Runs

Read this before creating a project, changing its environment, configs, run
layout, or what runs write, reading another run's output, or running a sweep or
on a cluster.

Runs are standard Hydra jobs. Hydra composes the config, creates the job's
output folder, saves the config and overrides in `.hydra/`, and sends Python
logging to `<script>.log` there. The code writes its outputs into that folder as
ordinary files with ordinary libraries. The only additions are two small Hydra
callbacks in `utils/hydra.py` (from `assets/utils/`): `GitInfo` records the git
commit, `LatestLink` keeps the `latest` link.

## pixi

```toml
[workspace]
name = "project"
channels = ["conda-forge"]
platforms = ["osx-arm64", "linux-64"]     # linux-64 is required for the clusters

[dependencies]
python = "3.12.*"

[pypi-dependencies]
hydra-core = ">=1.3"
numpy = "*"
matplotlib = "*"

[activation.env]
PYTHONPATH = "$PIXI_PROJECT_ROOT"      # project packages (utils/, <concept>/) import from scripts

[tasks]
train = "python experiments/train.py"
evaluate = "python experiments/evaluate.py"
```

Hydra arguments pass through the task: `pixi run train model.width=128`,
`pixi run train -m model.width=32,64,128`.

## Configs and the run folder

Hydra's default folders are named by time only (`outputs/<date>/<time>/`, and
`multirun/<date>/<time>/<job number>/` for sweeps). Every config here puts the
run's name in front (from `assets/configs/config.yaml`):

```yaml
run:
  name: ours-${scene.name}-w${model.width}

hydra:
  run:
    dir: runs/${run.name}/${now:%Y-%m-%d_%H-%M-%S}
  sweep:
    dir: runs/.sweeps/${now:%Y-%m-%d_%H-%M-%S}          # multirun.yaml of the sweep
    subdir: ../../${run.name}/${now:%Y-%m-%d_%H-%M-%S}  # each trial in runs/<its name>/
  job:
    chdir: false
  callbacks:
    git:
      _target_: utils.hydra.GitInfo
    latest:
      _target_: utils.hydra.LatestLink
```

Keep these blocks in every entry point's config: one `configs/<entry>.yaml` per
entry point, or a shared file listed in each one's `defaults`. Use config groups
for variants, and check the composed config with `--cfg job --resolve` before an
important run.

A run folder then holds:

```text
runs/<name>/<YYYY-MM-DD_HH-MM-SS>/
├── .hydra/config.yaml, overrides.yaml, hydra.yaml   # Hydra
├── <script>.log                                     # Hydra: Python logging, and the traceback if it failed
├── git_commit.txt, git_diff.patch                   # GitInfo: commit and uncommitted changes
└── ... whatever the run writes                      # metrics, figures, tables, arrays, checkpoints
runs/<name>/latest -> <YYYY-MM-DD_HH-MM-SS>          # the newest run that finished without an error
```

`latest` moves only when the job returns normally, and never back to an older
folder. A job that raises (including a failed validation) or is killed keeps its
folder but not the link. `.hydra/config.yaml` keeps interpolations as written;
turn values that come from the environment into explicit config values when
they matter for reproduction.

## An entry point

A standard Hydra function (`assets/run.py`):

```python
import logging
from pathlib import Path
import hydra
from hydra.core.hydra_config import HydraConfig
from omegaconf import DictConfig

log = logging.getLogger(__name__)

@hydra.main(version_base="1.3", config_path="../configs", config_name="train")
def main(cfg: DictConfig) -> None:
    out = Path(HydraConfig.get().runtime.output_dir)
    model = hydra.utils.instantiate(cfg.model)
    for step in range(cfg.steps):
        ...
        if step % cfg.log_every == 0:
            log.info("step %d loss %.4g", step, loss)
    ...                    # write outputs into `out`
    validate(...)          # raise on failure: the job fails and latest stays
```

Scripts run from the project root (`chdir: false`), so relative paths resolve
against the root. The root is on `PYTHONPATH` (pixi activation, below), so
`utils` and the project's own packages import from any script. Write
everything a run produces into `out`, never next to the code or into another
run's folder.

## Run names

`run.name` says what the run is and what it runs on, in the project's terms:

- what the run is: the method or its role (`ours`, `baseline`, `reference`),
  and the computation when it is not the obvious one (`eval-…`, `frames-…`, or
  a figure's content such as `error-maps-…`);
- what it runs on: the scene or dataset as the project calls it (`ai57_008`,
  `bunny`);
- what tells it from its siblings: the few settings that differ between the
  project's runs, written short (`w64`, `fp16`, `sigma0.1`).

Build it by interpolation from the config values it names, so it cannot drift
from what ran. A run that reads another run's result repeats that name
(`eval-<name>`). A rerun of the same thing (after a fix, a failure, an
interruption) keeps the name and gets a new dated folder. Keep the vocabulary
small and stable across the project.

## What a run writes

Write with the libraries the project already uses, in formats anyone can open:

- **Scalars over time**: `log.info` for the log, plus a file to plot from: a CSV
  with one row per observation (`step, split, loss, ...`), or the framework's
  own logger pointed at `out` (Lightning's `CSVLogger` or `TensorBoardLogger`
  with `save_dir=out`, a TensorBoard `SummaryWriter(out)`).
- **Per-sample results**: tables (`.csv`, `.parquet`) with a `sample_id` column,
  or arrays (`.npy`, `.npz`) with the IDs alongside.
- **Images and figures**: `.png` (`matplotlib.pyplot.imsave`, `fig.savefig`),
  `.svg` for diagrams, `.plotly.json` for interactive figures.
- **Checkpoints and state**: the framework's format (`torch.save`, ...).

Record during the run, at a cadence set in config: scalars often (`log_every`),
images more coarsely (`image_every`, plus once at the start and the end); never
buffer everything until the end. Keep file names, columns, and units stable
across runs. Put each observation's axes (`step`, `split`, `sample_id`) in its
row, not in column or file names, except a step number in an image file name
(`recon_view0_step000100.png`).

**Every run is inspectable on its own**, without the code or a report. Save as
images over the steps everything cheap to compute from state the run already
has: the output next to its reference and input on a fixed set of samples or
views; the error or residual on a fixed colour scale; optimized parameters that
are images or fields, and their gradients; the intermediate quantities the
claim depends on. Same samples, size, and colour scale at every step. Skip only
what is genuinely expensive (an extra full render per step), and then save it
less often rather than never.

## Store what is expensive

Split the pipeline where the cost drops. An expensive run (training, fitting,
rendering, simulation, evaluation over the test set) stores everything a later
figure or table could need: per-sample and per-point values, not only means;
predictions and errors keyed by stable sample IDs that refer back to the
dataset instead of copying it; the final model or state.

An analysis run reads those folders, computes summaries with cheap code, and
writes the figures and tables a report shows, named for what they show.
Plotting functions take explicit stored data and return a `Figure`; colours,
method order, and axis limits for a comparison come from one module and are
passed in explicitly, not derived from each run's own data. Changing a figure
means rerunning only its analysis run.

## Reading other runs

A run that reads another names it in its config:

```yaml
inputs:
  evaluation: runs/eval-ours-ai57_008-w64/latest     # or a dated folder, pinned
```

and logs the folder it actually read, with the link resolved:

```python
source = Path(cfg.inputs.evaluation).resolve(strict=True)
log.info("input evaluation: %s", source)
```

Pin the dated folder in config for runs a report will cite, so rerunning the
upstream run does not silently change the analysis. Read only run folders and
datasets in `data/`, never another script's temporary files.

## Parameter studies

Only after feasibility. Declare the parameter space, seeds, and budget in
config.

- **Hydra multirun** (`pixi run train -m model.width=32,64,128 seed=0,1`) when
  the configurations are separate experiments to compare or select from. Every
  trial needs its own `run.name` (the varied values are in it), so each lands in
  its own `runs/<name>/` with its own `latest`. The sweep's `multirun.yaml` is
  kept in `runs/.sweeps/<time>/`.
- **An in-run grid** when the configurations are evaluation conditions of one
  experiment (noise levels, contamination rates): declare the grid in config,
  write one table row per cell, and report per cell, not only aggregates.

A study's summary is an analysis run that lists the expected trials from the
same grid as the sweep (not from what happens to exist) and fails if any trial
has no finished run since the sweep started. Never present a partial study as
complete by dropping trials.

Start coarse: few seeds and cells to find where the answer is clear, then more
seeds only where the decision depends on it. Record the runtime budget (the
longest acceptable single run, agreed with the user). When runs keep exceeding
it, make the code faster first (profile, vectorize, cache shared work, run
trials in parallel through a Hydra launcher), keeping the fast version checked
against the slow one.

## Dispatching work

Every machine gets one pixi task, so a run goes anywhere with the same task and
overrides as locally. Commit before dispatching runs a report will cite;
uncommitted changes are pushed too and recorded in `git_diff.patch`.

```toml
[tasks]
train = "python experiments/train.py"
# ssh machines (names from ~/.ssh/config)
fermat = "bash experiments/ssh.sh fermat"
kerr = "bash experiments/ssh.sh kerr"
# Slurm clusters: the slurm skill's script, writing to runs/ instead of outputs/
kuma = { cmd = "bash experiments/cluster.sh kuma", env = { CLUSTER_OUTPUTS = "runs" } }
lyra = { cmd = "bash experiments/cluster.sh lyra", env = { CLUSTER_OUTPUTS = "runs" } }
experiment = "python experiments/train.py"   # what the cluster script runs
```

### ssh machines

`assets/dispatch/ssh.sh`, copied to `experiments/ssh.sh`:

```bash
pixi run fermat setup                        # once per machine: pixi, the project folder
pixi run fermat train model.width=64         # push, start `pixi run train ...` detached
pixi run fermat -g 1 train -m seed=0,1,2     # with CUDA_VISIBLE_DEVICES=1
pixi run fermat status                       # GPU use, launched tasks, newest logs
pixi run fermat log                          # follow the newest launch log
pixi run fermat stop <pid>                   # stop a task and what it started
pixi run fermat pull                         # copy runs/ back (keeps the latest links)
pixi run fermat ssh <command>                # anything in the remote project
```

The project lives in `~/projects/<project>` on the machine (`SSH_DIR` changes
it); `runs/` stays there and is never overwritten by a push. Launch logs and
pid files are in `runs/.launch/`. The task runs with `nohup` in its own session,
so it survives the ssh connection; a sweep runs its trials one after another
with Hydra's basic launcher. Workstations are shared: check `status` first and
use a free GPU.

### Slurm clusters

Load the `slurm` skill and the cluster's skill (`kuma`, `lyra`) before the first
cluster command, and follow their setup: `cluster.sh` and the cluster's profile
in `experiments/`, its launchers in `configs/hydra/launcher/`,
`hydra-submitit-launcher` and `linux-64` in `pixi.toml`, and the
`experiment` task the script runs. With `CLUSTER_OUTPUTS = "runs"` the script
links `runs/` to scratch on the cluster, never pushes it, and `pull` copies it
back with the `latest` links.

```bash
pixi run kuma setup                          # once per account
pixi run kuma smoke steps=10                 # foreground, debug launcher: measure a trial
pixi run kuma submit model.width=32,64       # one Slurm array task per trial (a multirun)
pixi run kuma pack -t 1:00:00 -- seed=0,1,2      # short trials in one job
pixi run kuma status                         # also: gpu <jobid>, pull
```

Every `submit` or `pack` passes the slurm skill's GPU-efficiency gate first.
Their Cairn-specific parts (tracking servers, `CAIRN_*` caches) do not apply.
A trial counts by its own run folder and log, not by Slurm's job state.
