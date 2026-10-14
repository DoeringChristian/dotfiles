# Project setup

Read this when creating a project, changing its environment or run bookkeeping, logging evidence, running on a cluster, or planning a parameter study.

Contents:

- pixi setup
- Hydra configuration and run identity
  - Snapshot source and runtime state
  - `latest` links
- Experiment boundary and run outputs
  - Log run evidence through `RunLogger`
- Running on a cluster
- Parameter studies

## pixi setup

Start with:

```toml
[workspace]
channels = ["conda-forge"]
name = "<project>"
platforms = ["linux-64", "osx-arm64"]

[dependencies]
python = "3.12.*"
graphviz = "*"

[pypi-dependencies]
numpy = "*"
matplotlib = "*"
hydra-core = "*"
hydra-submitit-launcher = "*"
pyyaml = "*"
plotly = "*"
black = "*"
cairn-report = { git = "https://github.com/DoeringChristian/cairn-report.git", tag = "v0.8.0" }

[activation.env]
PYTHONPATH = "."

[tasks]
experiment = "python experiments/run.py"
report-build = "cairn-report build"
report-serve = "cairn-report serve --host 127.0.0.1 --port 8000"
report-host = "cairn-report serve --host 0.0.0.0 --port 8000"
report-share = "cairn-report share"
format = "black --extend-exclude '/([.]pixi|outputs|generated)/' ."
kuma = "bash experiments/cluster.sh kuma"    # one task per cluster the project uses
lyra = "bash experiments/cluster.sh lyra"
```

Graphviz comes from conda-forge because it is a native binary; the builder runs
`dot -c` once if pixi skipped conda's plugin registration. List every platform
the project runs on; `linux-64` is required for the GPU clusters (see Running on a
cluster).
Commit `pixi.lock`; ignore `.pixi/`, caches, `outputs/`,
and `generated/` in `.gitignore`, and keep the explicit Black
`--extend-exclude`, because Black does not exclude `.pixi` by itself. Every
formatter, linter, type checker, and test runner must skip environments and
generated artifacts. Do not add MLflow, Cairn, W&B, TensorBoard-as-a-tracker,
or a custom run database. When the user asks for a tracker or a central store,
use cairn-report's `mlflow` or `hub` logger backend (see Log run evidence);
the run directory stays the record either way.

## Hydra configuration and run identity

Put every scientifically meaningful choice in config. Let Hydra create distinct
run directories:

```yaml
# configs/config.yaml
defaults:
  - _self_                      # first, so each experiment config can set run.name
  - experiment: primary

seed: 0

hydra:
  callbacks:
    source_snapshot:
      _target_: provenance.source_snapshot.SourceSnapshotCallback
      mode: git                 # git or tree
      source_root: null         # Hydra's original working directory
      capture_runtime: true
    study_completion:           # multirun only: completes the study, moves latest
      _target_: experiments.run.StudyCompletion
  run:
    dir: outputs/${run.name}/${now:%Y-%m-%d_%H-%M-%S}
  sweep:
    dir: outputs/${run.name}/${now:%Y-%m-%d_%H-%M-%S}
    subdir: ${hydra.job.num}
  job:
    chdir: true
```

Each experiment config names its own runs:

```yaml
# configs/experiment/primary.yaml
# @package _global_
run:
  name: feasibility-method
  description: <question, purpose, and interpretation constraints>
experiment:
  _target_: experiments.<module>.<ExperimentClass>
  # every scientifically meaningful parameter of this experiment
```

Keep `_self_` first in `config.yaml` and do not define `run:` there. Hydra
merges the defaults list in order, so entries after `_self_` override
`config.yaml`; with `_self_` last, a `run:` block in `config.yaml` would
silently replace every experiment's run name and send different experiments
into the same `outputs/<run-name>/`.

Hydra's `.hydra/config.yaml`, `.hydra/hydra.yaml`, and
`.hydra/overrides.yaml` are the authoritative configuration record. `run.json`
is the one authoritative completion record, written by `experiments/run.py`
(below). A run counts as evidence only when `run.json` exists and says
`status: completed`; a directory without it is incomplete, whatever it contains.
`latest` and the reports apply this same rule. Do not duplicate the full
resolved config into another schema.

Names must be short and semantic—such as `feasibility-method`,
`reference-baseline`, or `ablation-no-feature`. Do not encode parameter lists,
seeds, timestamps, or hashes in them. Validate names as safe path slugs: reject
path separators, `.`/`..`, and characters outside the project's documented slug
alphabet. Put a concise description in config so a report reader understands
what was tested and how to interpret it.

### Snapshot source and runtime state

Copy bundled assets by content only and make the copies owner-writable (for
example `install -m 0644 <source> <destination>`): skill directories may come
from read-only plugin caches, shared installations, or dotfiles mounts.

Copy [`assets/source_snapshot.py`](../assets/source_snapshot.py) into the project as
`provenance/source_snapshot.py` and register it as shown above. Each Hydra job,
including every numbered multirun trial, writes `provenance/` into its own run
directory. The callback supports two modes:

- `git` stores a source-only archive of the committed tree at `HEAD`, a patch
  containing staged and unstaged changes, and eligible untracked source files.
  Prefer this compact mode when the project has a commit.
- `tree` copies the current eligible source tree as ordinary files. Use it when
  Git history is unavailable or the assembled working tree is more useful.

Both modes allowlist UTF-8 text source in common languages (Python, C/C++,
CUDA, Rust, Julia, R, shell, JavaScript/TypeScript, HTML/CSS, shaders, SQL, TeX)
and project-definition formats. They respect Git ignores when available and
exclude symlinks, installed libraries, environments, caches, dependency trees,
generated reports, run outputs, credential stores (`.ssh`, `.aws`, …), and
credential-like files (`.env*`, `*.pem`, `*.key`, `id_rsa*`, `credentials*`,
`secrets*`, service-account JSON, tokens). A source file over the per-file
limit, or a snapshot over the total limit, fails the job rather than leaving a
partial snapshot. Git mode counts each byte once (committed tree, untracked
copies, patch). Files skipped as non-UTF-8 are listed in the snapshot manifest.
Extend the deny rules for project-specific data or secrets.

With `capture_runtime: true`, `provenance/environment/` also contains
`pip-freeze.txt` (read from installed package metadata, so `pip` is not
required), Python and platform facts, a small allowlist of execution
environment settings, Git status, and an exact copy of `pixi.lock` when present.
Do not dump the complete process environment or copy `.pixi`; inventories and
the lock file describe installed packages without duplicating libraries or
exposing unrelated secrets. The callback runs before experiment code, so a
later experimental failure still retains its initial source and runtime state.

### `latest` links

`outputs/<run-name>/latest` is a relative symlink to the newest completed run of
that name, replaced atomically by `experiments/run.py`. A failed or interrupted
run stays on disk for diagnosis and never moves `latest`. In a multirun, trials
never touch it; the `StudyCompletion` callback writes the study root's
`run.json` after the last trial and moves `latest` to the study only when every
trial completed. When a trial fails, Hydra's launcher stops the study before the
callback runs, so the study root has no `run.json` and counts as incomplete.
`latest` is a convenience pointer, never provenance: reports resolve it once and
record the timestamp directory they read.

## Experiment boundary and run outputs

```python
# experiments/base.py
from abc import ABC, abstractmethod
from pathlib import Path


class Experiment(ABC):
    @abstractmethod
    def run(self, output_dir: Path) -> None:
        """Execute the experiment and write its evidence to output_dir."""
```

Copy [`assets/run.py`](../assets/run.py) unchanged into the project as
`experiments/run.py`; it is the entry point. It writes `run.json` as `running`,
calls `require_snapshot` (Hydra reports callback errors only as warnings, so
this is what makes a snapshot failure fail the run), instantiates the configured
`Experiment`, passes it the Hydra run directory, records `completed` or `failed`
with the traceback, and moves `latest`. It validates run names and knows nothing
experiment-specific; put project logic in `Experiment` subclasses.

### Log run evidence through `RunLogger`

The logger is part of the `cairn-report` dependency, the same package that
reads runs into reports, so the run file format has one definition. Import it;
never copy or reimplement it. Write all evidence of the kinds it supports
through one `RunLogger` per run directory rather than hand-rolled writers:

```python
from cairn_report.logger import RunLogger

log = RunLogger(output_dir)
log.scalar("rmse", rmse)                     # single value
log.scalar("loss", loss, step=epoch)         # series point
log.table("trials", rows)                    # tidy CSV
log.json("per_class", scores)                # structured result
log.figure("error_histogram", error_histogram, errors)   # pass the plot function
log.plotly("running_rmse", spec)
log.image("reconstruction", array)
log.artifact("model", checkpoint_path)      # models, animations, archives
log.text("solver", solver_log)
```

Each call writes one file to a fixed place in the run directory. Both indexes
are append-only JSON Lines; nothing already written is rewritten:

```text
<run>/
├── run.json               # completion record (experiments/run.py)
├── metrics.jsonl          # one event per scalar: name, value, step, time, origin
├── artifacts.jsonl        # one event per logged file: name, kind, path, time, origin, producer
├── tables/<name>.csv
├── data/<name>.json
├── figures/<name>.png     # optional .svg; figures/<name>.plotly.json
├── images/<name>.png
├── artifacts/<name>.*     # any other evidence file
└── logs/<name>.txt
```

Readers fold the logs: the latest `metrics.jsonl` event per name is a scalar's
current value (`read_scalars`, shared by the logger and the report builder), and the
latest `artifacts.jsonl` line per path describes a file. A torn final line from
a crash is ignored. Each artifact entry records its `origin` (file, line, and
function that called the logger) and, when the plotting function itself was
passed to `log.figure`, its `producer` (where the figure was drawn); with the
run's provenance commit this traces every figure to exact code. Names are
lowercase slugs without slashes, file writes are atomic, and non-finite scalars
are kept as `null` with their original value.

The logger fixes *where* evidence lives and records *which code* wrote it; it
imposes no result schema. Keep names, columns, and units stable when experiments
should share report views. Evidence the logger cannot express goes into
`log.artifact`, documented in the experiment's docstring, so it is still
indexed. Never hide important evidence through final-only output, excessive
aggregation, cherry-picked examples, or presentation-only composites.

`[logger] backends` in `cairn-report.toml` decides where the evidence also goes:
`["local"]` (the default) keeps it in the run directory only. Use `"mlflow"`
(an MLflow tracking server) or `"hub"` (a cairn-report hub, files sent while the
run executes) only when the user asks for them and names the server; both keep
writing the run directory first. Reports read runs from whichever backend holds
them, so report code does not change.


## Running on a cluster

Every project is ready for the Slurm GPU clusters (EPFL's Kuma and Lyra) from
the start, through the `slurm` skill and the cluster's own skill (`kuma`,
`lyra`). Load both before the first cluster command in a session and set the
project up by the `slurm` skill's "Set up a project": copy its `cluster.sh` and
`finalize_study.py` to `experiments/`, each cluster's profile to
`experiments/clusters/`, and its launcher configs to `configs/hydra/launcher/`,
and keep `hydra-submitit-launcher`, `linux-64`, and one task per cluster in
`pixi.toml` (see pixi setup). The `experiment` task is the entry point they run.
The `slurm` skill holds the commands and the **mandatory GPU-efficiency gate**;
the cluster's skill holds its partitions, CUDA version, and storage rules.
Clusters bill every allocated GPU-hour whether or not it is used.

Nothing in the run record changes on a cluster: `run.json`, snapshots, `latest`,
and `StudyCompletion` behave exactly as for local runs, and every trial is a
Slurm job. When a launcher died, `pixi run <cluster> finalize <study-dir>`
writes the study's `run.json` by `StudyCompletion`'s rule once the trials have
left the queue. Commit before pushing runs a report will cite; uncommitted
changes are recorded as a patch. Reports are built locally from pulled runs
(`pixi run <cluster> pull`), or from the hub. With a hub configured, `submit`
and `pack` also stream the runs to it from the login node while the trials run,
and `finalize` sends the finalized study (see "Remote runs and the hub" in [reports.md](reports.md)).

## Parameter studies

Only after feasibility, study parameters systematically. Declare the parameter
space, seeds, budget, objective, and its direction in config. Two forms are
supported, and both must keep every configuration's result inspectable:

- **Hydra multirun** (`python experiments/run.py -m key=a,b,c`) when the
  configurations are separate experiments to compare or select from: sweeps,
  ablations, or competing settings. Each trial is a complete run with its own
  `run.json`, provenance, and logs under `outputs/<run-name>/<timestamp>/<n>/`;
  `StudyCompletion` completes the study. A report reads it with
  `run_trials(run_dir("<run-name>"))`, which lists every trial with its
  overrides and status.
- **An in-run grid** when the configurations are evaluation conditions of one
  experiment, such as noise levels or contamination rates applied to the same
  methods. Declare the grid in the experiment config, log one table row per
  cell (`log.table`), and report results per cell, not only aggregates.

Choose the form by what the configurations are, not by convenience, and never
hide failed trials or cells. Use a finite grid for intentional comparisons,
random search for bounded exploration, and a Hydra sweeper plugin only when
adaptive search is justified. Do not add a tracking service to run a sweep.

**Size studies to the decision.** Start coarse: few seeds and cells to find
where the answer is clear and where it is not, then add seeds only for the
cells the decision depends on. Record each project's runtime budget (for
example the longest acceptable single run, set with the user, in the report's
Methods). When runs repeatedly exceed it, stop scaling and spend time on
performance first: profile, then vectorize, cache shared work, or run trials in
parallel through a Hydra launcher (on a cluster: `pixi run <cluster> submit`,
after the `slurm` skill's GPU-efficiency gate). Keep optimized code verified against the
slower reference implementation.
