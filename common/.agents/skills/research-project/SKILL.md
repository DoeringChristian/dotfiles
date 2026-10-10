---
name: research-project
description:
  Initialize, extend, or develop a reproducible research project managed with
  pixi, Hydra-configured object construction, config-selected experiments, and
  MLflow tracking. Use for research project setup, experiment implementations,
  method development, tracking and artifacts, feasibility studies, baselines,
  parameter studies, analytical diagnostics, or reproducible reports. Also use
  when the user mentions pixi, Hydra `_target_`, MLflow, experiment tracking,
  perceptual calibration, or reproducible reports.
---

# Research Project

Build research projects in which every reported result can be traced to its
resolved configuration, code, inputs, environment, and artifacts, then
regenerated from a fresh checkout with documented commands.

## Core principles

1. **pixi owns the environment.** Put Python packages mainly in
   `[pypi-dependencies]`; reserve conda-forge dependencies for the interpreter,
   compilers, CUDA, and packages PyPI does not provide reliably. Commit
   `pixi.lock`.
2. **Hydra owns configuration and object construction.** Keep configs under
   `configs/`, select implementations with `_target_`, and instantiate the
   object graph with `hydra.utils.instantiate`. Do not add a parallel registry.
3. **The experiment is the executable boundary.** A config-selected
   `Experiment` is the highest-level behavior. The entry point composes config,
   starts an MLflow run, instantiates the experiment, and invokes it.
4. **MLflow is the research record.** Track what is necessary to understand,
   diagnose, compare, and reproduce a run. Do not hide important evidence, but
   do not impose a universal logging hierarchy or log noise for completeness.
5. **Develop the method with the user.** Resolve ambiguities, make intermediate
   behavior inspectable, and establish feasibility against relevant baselines
   before tuning or scaling.
6. **Use a flat project layout.** Create top-level directories named for the
   concepts the project actually contains; do not add `src/<package>/` nesting.
7. **Validation tests the claim.** Identify smoke tests and debugging proxies as
   such; do not present them as scientific evidence.
8. **Do not improve results by weakening the problem.** Configure and disclose
   approximations that may change the scientific meaning.
9. **Preserve comparability.** Compared runs should differ only in intended
   factors. Reuse established result names when that enables meaningful views
   across compatible runs, without forcing unrelated work into one schema.

## Project layout

```text
project/
├── pixi.toml
├── pixi.lock
├── .envrc
├── .gitignore
├── mlflow.db           # local MLflow metadata, git-ignored
├── mlruns/             # local artifacts, git-ignored
├── configs/
├── <concept>/          # one flat directory per actual project concept
├── experiments/        # Experiment interface, variants, and run.py
└── reports/             # reproducible MLflow-backed running reports
```

Only `configs/`, `experiments/`, and `reports/` are conventional. Create each
`<concept>` directory only when the project needs that abstraction. The project
root is the import root. Before using a top-level name, check it with
`python -c "import <name>"`; if that succeeds, choose another name.

## pixi and MLflow setup

Initialize git before pixi in a new project:

```bash
git init
pixi init --format pixi
```

Use this as a starting point and adapt it to the project:

```toml
[workspace]
channels = ["conda-forge"]
name = "<project>"
platforms = ["linux-64"]

[dependencies]
python = "3.12.*"

[pypi-dependencies]
numpy = "*"
matplotlib = "*"
hydra-core = "*"
mlflow = "*"
black = "*"

[activation.env]
PYTHONPATH = "."
MLFLOW_TRACKING_URI = "sqlite:///mlflow.db"

[tasks]
experiment = "python experiments/run.py"
report = "python reports/method-development/report.py"
mlflow-ui = "mlflow server --host 0.0.0.0 --port 5000 --backend-store-uri sqlite:///mlflow.db"
format = "black ."
all = { depends-on = ["experiment"] }
```

Run `pixi install`. Ignore `.pixi/`, `mlflow.db`, `mlruns/`, Hydra output
directories, and caches. Add every runnable operation as a pixi task, commit
`pixi.lock`, and format through pixi.

Always provide the exact MLflow server command and concrete URL for remote
access. The example task serves `http://<remote-host>:5000`; replace the
placeholder in the handoff with the actual reachable hostname or IP. Confirm
options against the installed MLflow version and configure allowed hosts, CORS,
artifact serving, and authentication or an HTTPS/VPN boundary as required.
Binding to `0.0.0.0` provides reachability, not access control.

## direnv

```sh
watch_file pixi.lock
eval "$(pixi shell-hook)"
```

Then run `direnv allow`.

## Hydra configuration

Put the seed and every scientifically meaningful choice in config. Disable
Hydra's output tree because MLflow owns the research record:

```yaml
# configs/config.yaml
defaults:
  - experiment: primary
  - override hydra/job_logging: stdout
  - _self_

seed: 0
tracking:
  experiment_name: <project>
  run_name: <short semantic purpose>
  description: <question, purpose, and interpretation constraints>
  tags: {}

hydra:
  run:
    dir: .
  sweep:
    dir: .
    subdir: .
  output_subdir: null
  job:
    chdir: false
```

Open every group config with a one-line comment explaining when to select it.
An experiment config names its implementation and nested object graph:

```yaml
# configs/experiment/primary.yaml
# Use for <project-specific regime and reason>.
_target_: experiments.primary.PrimaryExperiment
component:
  _target_: components.primary.PrimaryComponent
```

An `_target_` and its arguments form one semantic unit. Do not inherit a sibling
variant and replace only `_target_`, because Hydra may retain arguments for the
old implementation. Write the variant in full or use another config group.

## Entry point and Experiment boundary

Keep the experiment interface independent of MLflow's global fluent API:

```python
# experiments/base.py
from abc import ABC, abstractmethod

class Experiment(ABC):
    @abstractmethod
    def run(self) -> None:
        """Execute and log this experiment within the active MLflow run."""
```

```python
# experiments/run.py
import hydra
import mlflow
from hydra.utils import instantiate
from omegaconf import DictConfig, OmegaConf

from experiments.base import Experiment


@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    resolved = OmegaConf.to_container(cfg, resolve=True)
    name = str(cfg.tracking.run_name or "").strip()
    description = str(cfg.tracking.description or "").strip()
    if not name or not description:
        raise ValueError("Every MLflow run needs a semantic name and description")

    mlflow.set_experiment(cfg.tracking.experiment_name)
    with mlflow.start_run(
        run_name=name,
        description=description,
        tags=dict(cfg.tracking.tags),
    ):
        mlflow.log_dict(resolved, "config/resolved.yaml")
        experiment = instantiate(cfg.experiment)
        if not isinstance(experiment, Experiment):
            raise TypeError("Configured experiment must implement Experiment")
        experiment.run()


if __name__ == "__main__":
    main()
```

Keep run names short, readable, and based on purpose: for example,
`feasibility-method`, `reference-baseline`, or `ablation-no-<feature>`. Do not
serialize parameters, seeds, timestamps, or hashes into names; MLflow already
records config. Record a concise description of what the run tests and how it
should be interpreted in MLflow's run description.
Descriptions must add context rather than repeat the config.

The configured experiment owns construction, lifecycle, tracking cadence, and
result semantics. Put materially different orchestration in separate
`Experiment` implementations, not branches in the entry point.

## Developing a method

### Establish a shared specification

At the beginning, optimize for shared understanding. Ask focused questions
about ambiguities in purpose, inputs, outputs, operations, state, update rules,
objectives, invariants, assumptions, advantages, regimes, and failure cases.
Do not silently choose an interpretation that could change the method or its
scientific conclusion.

Expect several short dialogue rounds for a new method. Restate the current
understanding with equations, pseudocode, diagrams, or concrete examples and
ask the user to confirm it. Record confirmed choices in config, code, and the
early report. Reopen the dialogue when implementation exposes new ambiguity.
Small probes may proceed meanwhile if their assumptions are explicit.

### Make the interpretation inspectable

Create simple examples that expose important mechanisms. Visualize inputs,
intermediate states, transformations, outputs, loss terms, update directions,
and small optimization trajectories where useful. Show representative
iterations, baseline comparisons, ablations, spatial or frequency views, and
failure cases—not only polished final output.

Implement visualization generation as reusable project code. Track the views
and source values needed to interpret or regenerate them in MLflow, and use the
most informative ones in reports. Prefer image grids for related images so
corresponding inputs, references, predictions, residuals, masks, samples, or
steps can be compared together. Keep layout, normalization, labels, and order
consistent where comparison matters, while preserving important full-resolution
outputs.

### Build method diagnostics with Matplotlib

Use Matplotlib for diagnostic figures. Depending on the method, show objective
terms, residuals, update magnitudes, distributions, spatial maps, spectra,
convergence, intermediate states, uncertainty, before/after views, and baseline
overlays. Functions should accept explicit data and return a `Figure`.

Give axes units and meaningful labels; include legends and colorbars where
needed. Keep scales, limits, normalization, colormaps, and panel order
consistent across comparable figures, and show variability when relevant.
Log the figure with `mlflow.log_figure` and, when practical, its underlying
numeric values.
Reuse the same functions in reports.

### Establish baselines with the user

Identify baselines that test the claimed advantage under comparable conditions.
If several are plausible or the target comparison is unclear, discuss them with
the user before building a large comparison.

Prefer faithful adaptations of authoritative reference implementations. Read
the paper, documentation, configuration, evaluation protocol, and complete
relevant execution path. Reuse or adapt reference code when licensing and
interfaces permit; otherwise document material deviations. Record the reference
version, configuration, inputs, and deviations with the baseline run. Keep
workloads, preprocessing, budgets, stopping rules, and evaluation equivalent
unless a justified difference is part of the question.

### Pass a feasibility gate before tuning

Begin with a bounded feasibility study, not a sweep. Establish that the method
behaves as agreed on simple and representative cases, then compare it with the
chosen baselines. Agree with the user on the qualitative checks, metrics,
tolerances, and failure cases needed to pass. Do not start systematic tuning,
large sweeps, or expensive scaling until the user has seen the evidence and the
method has passed this gate. If it fails, diagnose or revise it rather than tune
until an advantage appears.

## MLflow tracking guidance

Track all sensible metrics and the configurations, inputs, diagnostics,
outputs, and environment facts needed to evaluate and reproduce the work. Use
meaningful steps for evolving quantities. Preserve model or artifact lineage
when one run consumes another run's output.

Choose MLflow representations that make the evidence easy to inspect. Scalars,
series, images, figures, tables, structured data, and artifacts should remain
in their natural useful form. Related images should be an image table or another
clear grid when practical. Autologging may supplement explicit
tracking, but it must not determine what scientific evidence is visible.

There is deliberately no required key hierarchy, component protocol, fixed
cadence, or universal list of fields. Structure logging around the actual
question and the views a reviewer needs. Reuse clear established names when
the same quantity appears across compatible runs or projects, especially when
that lets MLflow comparisons and reports be reused. Preserve units and
meaning. Do not force different quantities under the same name merely for
uniformity.

Do not hide important information through excessive aggregation, cherry-picked
examples, presentation-only composites, or final-only logging. Keep comparison
operands available where they matter, retain full-fidelity reusable artifacts,
and make sampling or reduction explicit. At the same time, avoid redundant
logging that obscures the result or materially distorts execution.

## Runs and parameter studies

An `Experiment` is a config-selected strategy; an MLflow run is one execution
of it. Parent and nested child runs may organize a coherent study. Give
independently runnable evaluation its own experiment and run when that improves
lineage or reuse.

Only after the feasibility gate, use a maintained search tool for repeated
comparable trials when appropriate. Declare the search space, seed, budget,
objective and direction, and associate every trial with an MLflow run. Record
the best result and source run. Prefer a finite grid for intentional
comparisons, random search for bounded exploration, and adaptive search only
when a scalar objective justifies it. Do not use a parameter study to group
incomparable jobs or replace a workflow scheduler.

## Scientific validity and perceptual blind spots

Verify that evaluation has enough fidelity, coverage, and statistical quality
to reveal the effect under study. Changes that could alter the claim belong in
config and tracking, not hidden code.

When the user reports an important effect that current inspection or metrics
miss—such as temporal instability, localized artifacts, or high-frequency
structure—preserve the original outputs, add an analytical visualization that
isolates the phenomenon, and track a plausible quantitative measure.

Prefer a standard established metric when its assumptions fit. Adapt or devise
a more specific measure only when standard metrics are unavailable or miss the
effect. When its relationship to perception is unclear, test it on known
positive, negative, and confounding cases. If uncertainty remains, propose a
small calibration phase using focused ratings, rankings, or pairwise
comparisons. Do not claim that a metric replaces expert judgment until evidence
supports that conclusion; report disagreement and blind spots.

## Reports

Create a running method-development report at the start of every project and
maintain it throughout the work. It is the written research record: state the
current method, questions, decisions, findings, supporting and contradictory
evidence, limitations, unresolved issues, and next experiments. Include simple
examples, intermediate behavior, Matplotlib diagnostics, feasibility evidence,
baseline comparisons, and important failure cases. Update conclusions when new
runs change the evidence; preserve enough history to explain why the current
conclusion was reached without turning the report into a chronological log.

The report must be generated from MLflow run data. Put reproducible report code
under `reports/method-development/report.py` or a more specific project
convention and add a pixi task immediately. Query MLflow with `MlflowClient` or
`mlflow.search_runs`, load recorded metrics, parameters, tags, configurations,
figures, and artifacts, and generate a self-contained result such as HTML.
Never copy numbers manually, hard-code local result paths, hand-edit generated
output, or use transient notebook state as evidence.

Each report build must record exactly which MLflow runs and artifacts support
it. Store a machine-readable manifest containing source run IDs, selection
criteria, report revision or timestamp, and relevant code revision. This
manifest makes every displayed value and finding traceable and lets the report
be regenerated after a fresh checkout.

Log the rendered report and its source manifest back to MLflow as artifacts,
normally in a dedicated report run with a clear name such as
`report-method-development`, an informative description, and a tag such as
`run_role=report`. Query source runs before opening the report run or explicitly
exclude report runs so the report cannot treat itself as experimental evidence.
The local output is a reproducible cache; the MLflow artifact is the shared
copy.

Host the report through MLflow by keeping it attached to the tracked report run
and serving the MLflow UI remotely. If the chosen output needs richer rendering
than MLflow's artifact preview provides, also add a pixi task for a report
server, but keep MLflow as the index and source of truth. The handoff must give
the concrete remote MLflow URL, report run or artifact location, and exact
hosting command.

## Documentation and handoff

Document durable constraints and non-obvious scientific choices, not the
chronology of development. The handoff states what changed or was learned, what
validation supports it, and what could still limit the conclusion. Distinguish
smoke tests and proxies from evidence. Disclose consequential approximations.
Include exact commands for reproducing experiments and rebuilding the running
report, plus the concrete MLflow URL and command that host its run data and
report artifacts for remote access.

## Reproducibility checklist

- [ ] `pixi.lock` is committed; `.pixi/`, local MLflow state, and caches are
      ignored.
- [ ] Python is formatted through pixi; a fresh clone can run documented tasks.
- [ ] Hydra config contains seeds and scientifically meaningful choices; the
      resolved config is attached to each MLflow run.
- [ ] Configurable objects use `_target_` and `instantiate`; the entry point is
      independent of experiment-specific orchestration.
- [ ] Runs have concise semantic names and useful descriptions; configuration
      values are not encoded into unreadable names.
- [ ] MLflow shows the metrics, diagnostics, inputs, outputs, environment facts,
      and lineage necessary to understand and reproduce each result without
      hiding important evidence.
- [ ] Related images use consistent grids or galleries when practical, and
      reusable Matplotlib diagnostics expose intermediate method behavior.
- [ ] The user and agent confirmed a precise shared method specification with
      simple examples and resolved consequential ambiguities.
- [ ] Relevant baselines were agreed with the user and faithfully adapted from
      fully inspected authoritative references, with deviations recorded.
- [ ] A bounded feasibility study precedes tuning and large parameter studies.
- [ ] A running findings report is maintained from the beginning, generated
      from MLflow run data, and updated as understanding evolves.
- [ ] Every report build and source manifest is logged back to MLflow, and every
      displayed result is traceable to its supporting run and artifact.
- [ ] Validation supports the intended claim; proxies are labeled as proxies.
- [ ] User-reported blind spots receive analytical views and suitable metrics;
      established measures are preferred and calibrated only when needed.
- [ ] Compared runs differ only in intended factors, or differences are tracked
      and accounted for.
- [ ] The handoff includes the exact project-correct MLflow hosting command,
      concrete remote URL, and report artifact location.
