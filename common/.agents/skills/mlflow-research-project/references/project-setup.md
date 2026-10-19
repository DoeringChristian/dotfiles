# Project setup and logging

## Environment and layout

The local Folio checkout is `~/workspace/folio-reports` (plural); inspect its
`pyproject.toml`, CLI and config parser before integration because this is an
actively changing extraction. Use the real checkout; do not assume the singular
path exists. Install it as a dependency rather than copying or patching its
renderer into research projects. For a portable project, use a published
version or an available repository commit supplied by the user; do not invent
a remote. A local editable dependency is suitable for local development but
must be replaced or made available on cluster machines.

A minimal pixi environment includes Python 3.12, `hydra-core`, `mlflow`,
`matplotlib`, and `folio-reports` with its `mlflow` extra. For example, adapt
this to the actual supported platforms:

```toml
[workspace]
name = "research"
channels = ["conda-forge"]
platforms = ["osx-arm64", "linux-64"]

[dependencies]
python = "3.12.*"

[pypi-dependencies]
hydra-core = "*"
mlflow = "*"
matplotlib = "*"
folio-reports = { path = "../folio-reports", editable = true, extras = ["mlflow"] }

[activation.env]
PYTHONPATH = "."

[tasks]
experiment = "python experiments/run.py"
report-build = "folio build ."
report-serve = "folio serve . --host 127.0.0.1 --port 8000"
report-share = "folio standalone . -o report.html"
```

Use Python 3.12 for this starter; Hydra 1.3 fails during argument-parser
initialization on Python 3.14. Validate compatibility before upgrading.

Run `pixi install`, commit `pixi.toml` and `pixi.lock`, and initialize Git before
experiments. Add framework dependencies as needed, Graphviz for graph fences,
and launcher plugins only for the clusters in use. Ignore `.pixi/`, `outputs/`,
`multirun/`, `.folio/`, `_site/`, `mlruns/`, `mlartifacts/`, `mlflow.db*`, local
data and exported HTML. Exclude these from formatters and source snapshots too.

```text
configs/config.yaml, configs/experiment/<name>.yaml
experiments/base.py, experiments/run.py, experiments/<method>.py
<concept>/                         # project implementation
reports/<slug>/report.md           # one report per direction
folio.toml
```

Copy [../assets/run.py](../assets/run.py) to `experiments/run.py` as a small
entry-point starting point. It logs config and lock provenance and gives the
experiment its own output folder; it is not a complete source/log capture
system. Define `Experiment.run(output_dir: Path) -> None` in `experiments/base.py`
and instantiate its subclasses through configs.

```yaml
# configs/config.yaml
defaults:
  - _self_
  - experiment: primary
seed: 0
tracking:
  experiment: research
  run_name: feasibility
hydra:
  job:
    chdir: false
  run:
    dir: outputs/${now:%Y-%m-%d}/${now:%H-%M-%S-%f}
  sweep:
    dir: multirun/${now:%Y-%m-%d}/${now:%H-%M-%S-%f}
    subdir: ${hydra.job.num}
```

`configs/experiment/primary.yaml` selects `_target_:
experiments.primary.Primary` and its constructor arguments. Pass the seed and
other shared settings explicitly, e.g. `seed: ${seed}`. The entry point does
not seed framework RNGs automatically.

## Tracking backend

Honor an existing `MLFLOW_TRACKING_URI`. Otherwise choose an explicit local
SQLite URI anchored at the project root, such as
`sqlite:////absolute/project/path/mlflow.db`, and configure artifact storage
consistently. Use that same URI for experiments, the tracking UI, and Folio
builds. Do not rely on version-dependent MLflow defaults or a relative URI
whose meaning changes with the job working directory. Configure the backend
outside scientific config when it contains credentials.

For local use, `mlflow ui --backend-store-uri <sqlite-uri> --host 127.0.0.1`
opens the tracking UI. For multiple machines, use the user's tracking server
and durable artifact store; verify connectivity and artifact upload/download
from workers and the report machine. Do not share a SQLite database across
cluster jobs on a network filesystem. MLflow is not an offline outbox: failed
uploads must be surfaced and retried deliberately before results are cited.

## What each run records

Use `with mlflow.start_run(...)` around construction and execution, so uncaught
exceptions mark the run failed. Log failures for diagnosis and re-raise them;
do not swallow exceptions and report success. Hard kills can leave stale
`RUNNING` runs; reconcile those against the scheduler before using their data.

- Log the resolved OmegaConf config as `config.yaml` and the actual Hydra
  overrides as `overrides.yaml`. Log selected compact scalar parameters for UI
  filtering; the full config artifact is authoritative and avoids parameter
  size/type limits.
- Record Git commit and dirty status. For cited evidence, commit first or
  capture the exact patch and eligible untracked source files as well. A dirty
  flag alone is not a source snapshot. Preserve the source revision through a
  durable repository or source archive.
- Record `pixi.lock`, installed package versions, Python/platform details,
  scientifically relevant runtime settings, and stdout/stderr or equivalent
  logs. Allowlist provenance files; do not archive the whole working directory
  or environment variables.
- Record input dataset identity, split, checksum/version and preprocessing;
  record parent run/artifact references for derived inputs. Use
  `mlflow.log_input` when its dataset abstraction fits; otherwise log an
  explicit input manifest. Dataset metadata alone does not archive the data.
- Log scalar histories with `mlflow.log_metric(key, value, step=step)`;
  put final JSON/CSV, per-case results, curves and figures in `evaluation/`.
  Log models/checkpoints using the framework's MLflow integration when useful,
  and record the exact model reference in evaluation metadata.

For example, inside an active run:

```python
mlflow.log_metric("rmse", float(rmse), step=step)
mlflow.log_dict({"rmse": float(rmse), "split": "test"}, "evaluation/summary.json")
mlflow.log_figure(error_figure, "evaluation/figures/errors.png")
mlflow.log_artifact(str(cases_csv), artifact_path="evaluation/tables")
```

Use reusable Matplotlib functions returning `Figure`; close figures after
logging. Log Plotly as `*.plotly.json`, not an opaque HTML page, for Folio's
interactive embedding. Preserve per-step/per-case evidence rather than only
favorable aggregates. MLflow's metrics are not a `metrics.jsonl` artifact:
export a deliberately chosen table/JSON history when reports need curves.

## Studies and remote runs

After bounded feasibility, declare the study's grid, seeds, objective,
fairness controls and runtime budget. Hydra multirun creates one MLflow run
per trial; use an explicit study tag to group them. A summary is a separate
run with a manifest of exact trial IDs, statuses, configs and selection rules,
and tables produced from those trials. Keep failures visible. Do not assume
local nested-run context propagates into scheduler-launched processes.

An in-run grid suits evaluation conditions of the same experiment: log one row
per condition and preserve the declared grid. Start coarse and extend only
where the decision needs more evidence. Profile runs that exceed the budget.
On the user's machine, default to at most half the cores and cap worker and
library threads. Use the relevant cluster skills for larger work, checking
that launchers and finalizers do not still call Cairn APIs.
