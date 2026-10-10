---
name: research-project
description:
  Initialize, extend, or develop a reproducible research project managed with
  pixi, Hydra-configured object construction, config-selected experiments, and
  MLflow tracking. Use for research project setup, experiment implementations,
  tracking and artifacts, parameter studies, analytical diagnostics, or
  reproducible reports. Also use when the user mentions pixi, Hydra `_target_`,
  MLflow, experiment tracking, perceptual calibration, or reproducible reports.
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
2. **Hydra owns run configuration and object construction.** Keep configs under
   `configs/`, select implementations with `_target_`, and instantiate the
   object graph with `hydra.utils.instantiate`. Do not add a parallel registry.
3. **The experiment is the executable boundary.** A config-selected
   `Experiment` is the highest-level behavior. The entry point composes config,
   starts tracking, instantiates the experiment, and invokes it; it contains no
   experiment-specific orchestration.
4. **MLflow records every meaningful run.** Log the fully resolved config,
   seeds, relevant environment facts, metrics, diagnostics, and reusable
   artifacts. Avoid ad-hoc result directories and untracked notebook state.
5. **Use a flat project layout.** Create top-level directories named for the
   concepts the project actually contains; do not add `src/<package>/` nesting.
6. **Validation tests the claim.** Debugging proxies and smoke tests are useful,
   but identify them as such and do not present them as scientific evidence.
7. **Do not improve results by weakening the problem.** Any approximation that
   may change the scientific meaning must be explicit in config, logged with the
   run, and disclosed in the handoff.
8. **Preserve comparability.** Runs being compared should differ only in the
   intended factors. Keep result keys and their semantic contracts stable across
   runs, variants, and related projects.

## Project layout

```text
project/
├── pixi.toml
├── pixi.lock
├── .envrc
├── .gitignore
├── mlflow.db           # local MLflow metadata, git-ignored
├── mlruns/             # local MLflow artifacts, git-ignored
├── configs/
├── <concept>/          # one flat directory per actual project concept
├── experiments/        # Experiment interface, variants, and run.py
└── reports/             # only when a reproducible report is requested
```

Only `configs/`, `experiments/`, and `reports/` are conventional. Create each
`<concept>` directory only when the project needs that abstraction.

The project root is the import root, so check a proposed top-level name before
using it:

```bash
python -c "import <name>"
```

If that succeeds, choose another name. Names such as `encodings`, `types`,
`io`, `copy`, `queue`, `logging`, `platform`, and `test` collide with Python or
commonly installed packages.

## pixi setup

Initialize git before pixi in a new project:

```bash
git init
pixi init --format pixi
```

Use this as a starting point, adapting platforms and dependencies to the actual
project:

```toml
[workspace]
channels = ["conda-forge"]
name = "<project>"
platforms = ["linux-64"]

[dependencies]
python = "3.12.*"

[pypi-dependencies]
numpy = "*"
hydra-core = "*"
mlflow = "*"
black = "*"

[activation.env]
PYTHONPATH = "."
MLFLOW_TRACKING_URI = "sqlite:///mlflow.db"

[tasks]
experiment = "python experiments/run.py"
mlflow-ui = "mlflow server --backend-store-uri sqlite:///mlflow.db"
format = "black ."
all = { depends-on = ["experiment"] }
```

Use an explicit SQL backend even locally. MLflow's file metadata store is a
legacy option; SQLite keeps local setup simple and permits later migration to a
shared SQL-backed tracking server. Local artifact storage may remain under
`mlruns/`. Ignore `mlflow.db`, `mlruns/`, `.pixi/`, Hydra output directories,
and caches. For shared work, point `MLFLOW_TRACKING_URI` at the managed or
self-hosted tracking server and configure its database and artifact store there;
do not encode credentials in the repository.

Add every runnable operation as a pixi task. Add packages with `pixi add --pypi
<package>` unless they specifically need conda-forge. Run `pixi install`, commit
`pixi.lock`, and run `pixi run format` after editing Python. Keep Black defaults
unless the repository already establishes another policy.

## direnv

```sh
watch_file pixi.lock
eval "$(pixi shell-hook)"
```

Then run `direnv allow`.

## Hydra configuration

Put the seed and every scientifically meaningful choice in config. Disable
Hydra's parallel output tree because MLflow owns run records and artifacts:

```yaml
# configs/config.yaml
defaults:
  - experiment: primary
  - override hydra/job_logging: stdout
  - _self_

seed: 0
tracking:
  experiment_name: <project>
  run_name: null
  tags: {}
  log_system_metrics: false

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
Use one group per configurable top-level concept. An experiment config names
its implementation and its nested object graph:

```yaml
# configs/experiment/primary.yaml
# Use for <project-specific regime and reason>.
_target_: experiments.primary.PrimaryExperiment
component:
  _target_: components.primary.PrimaryComponent
```

An `_target_` and its arguments form one semantic unit. Do not inherit a sibling
variant and replace only `_target_`: Hydra merges mappings and may retain
arguments belonging to the old implementation. Write the variant in full or
move the nested object into its own selectable config group.

Hydra recursively instantiates nested targets. Pass runtime-only resources
directly to `instantiate`; keep configurable values in config. Use `_convert_`
or `_recursive_: false` only when the target genuinely requires it. Treat
untrusted `_target_` values as executable code and apply Hydra's target controls.

## Entry point and Experiment boundary

Keep the interface small and independent of MLflow's global fluent API:

```python
# experiments/base.py
from abc import ABC, abstractmethod


class Experiment(ABC):
    @abstractmethod
    def run(self) -> None:
        """Execute and log this experiment within the active MLflow run."""
```

The entry point owns the tracking lifecycle:

```python
# experiments/run.py
import platform

import hydra
import mlflow
from hydra.utils import instantiate
from omegaconf import DictConfig, OmegaConf

from experiments.base import Experiment


@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    resolved = OmegaConf.to_container(cfg, resolve=True)
    mlflow.set_experiment(cfg.tracking.experiment_name)
    with mlflow.start_run(
        run_name=cfg.tracking.run_name,
        tags=dict(cfg.tracking.tags),
        log_system_metrics=cfg.tracking.log_system_metrics,
    ):
        mlflow.log_dict(resolved, "config/resolved.yaml")
        mlflow.log_params(
            {
                "seed": cfg.seed,
                "experiment_target": cfg.experiment._target_,
                "python_version": platform.python_version(),
            }
        )
        experiment = instantiate(cfg.experiment)
        if not isinstance(experiment, Experiment):
            raise TypeError("Configured experiment must implement Experiment")
        experiment.run()


if __name__ == "__main__":
    main()
```

MLflow parameters are immutable within a run and are best for compact values
used to filter or compare runs. The resolved YAML artifact remains the complete
source of truth; log a deliberate, stable subset of flattened values as params
rather than forcing an arbitrarily large config into the parameter store.

The configured experiment owns its construction, lifecycle, tracking cadence,
and result semantics. Represent materially different orchestration with separate
Experiment implementations, not behavior flags or branches in the entry point.
Ordinary shared operations may remain functions until multiple implementations
justify a configurable concept.

## Tracking conventions

Use the MLflow data type that matches the role:

- `log_metric(name, value, step=...)` for numeric time series and comparable
  scalar outcomes.
- `log_param`/`log_params` for compact immutable run inputs.
- `set_tag`/`set_tags` for searchable identity and organization that is not a
  model input.
- `log_image(image, key=..., step=...)` for image sequences; use
  `artifact_file=...` for a static image artifact.
- `log_figure`, `log_table`, `log_dict`, and `log_text` for their corresponding
  diagnostics and structured artifacts.
- `log_input` with an MLflow dataset object for dataset source, digest, schema,
  and context when supported by the data type.
- framework-specific `log_model` APIs for loadable models, and ordinary
  artifacts for reusable non-model outputs.

Autologging may supplement explicit tracking, but do not rely on framework
defaults for the experiment's scientific claims. Explicitly log the stable
metrics, inputs, outputs, and diagnostics required for comparison.

Record environment facts not fixed by the lockfile or config when they can
change the result: actual device, backend, precision, selected implementation,
hardware, and relevant library/driver versions. Enable MLflow system metrics
when resource behavior matters; leave them off when their overhead or noise is
not useful.

### Components own their diagnostics

A component should expose a small method such as `log_diagnostics(step: int)`
when it has internal evidence worth recording. It logs under the active run and
owns the names, representations, and cadence-specific content for its subtree.
No tracking base class is required, and components with nothing useful to show
need no method. The experiment decides *when* to ask a component to log; it
does not duplicate knowledge of *what* that component must expose.

Prefer explicit calls over reflective tree walking. MLflow does not provide a
generic component-tracking protocol, and a small explicit boundary makes costs,
steps, and active-run requirements visible. Avoid stateful "first call" logic in
components; log immutable inputs once from orchestration and changing
diagnostics at meaningful steps.

### Keys are a compatibility contract

Equivalent results must use the same fully qualified key across runs,
experiment variants, and related projects. Before introducing a key, inspect
existing projects or shared conventions for the same result. Preserve meaning,
representation, units, directionality, step semantics, and axis conventions—not
just spelling.

Use stable, semantic paths such as `validation/error` or
`diagnostics/high_frequency_energy`. Keep method names, variants, and run IDs in
config, params, or tags rather than embedding them in result keys. This lets
saved MLflow comparisons and report code work across compatible experiments.

Do not reuse a key for a genuinely different quantity. Treat renaming or
repurposing an established key as a compatibility change and disclose it. When
a migration is worthwhile, log both old and new keys for a bounded transition
when that will not create ambiguity.

Track comparison operands—references, predictions, reconstructions, and masks—
separately under corresponding stable paths. A presentation-only composite must
not replace the operands. Log meaningful derived views such as residual maps or
spectral plots under their own keys.

Choose tracking cadence and representation so observability does not distort
the experiment. Preserve full-fidelity reusable outputs as artifacts while
logging sampled diagnostics for timely inspection. Any reduction that could
weaken validation must be explicit.

## Runs, related jobs, and parameter studies

Distinguish these concepts:

- An `Experiment` is a config-selected executable strategy.
- An MLflow run is one execution of that strategy.
- A parent run groups a study; nested child runs represent comparable trials or
  subordinate executions.

When evaluation is independently runnable or consumes a produced artifact,
give it its own experiment implementation and run. Record producer run IDs,
artifact/model URIs, dataset identities, and relevant tags so lineage can be
reconstructed. Parent-child nesting organizes runs but does not by itself prove
artifact lineage.

For a declared parameter space of comparable trials, use an established search
tool when appropriate—an ordinary grid for intended finite comparisons, random
search for bounded exploration, and Optuna or another suitable optimizer when a
scalar objective justifies adaptive search. Wrap the study in a parent MLflow
run and give every trial a nested child run with the same metric and artifact
keys. Record the search strategy, space, seed, trial budget, objective key and
direction, best value, best parameters, and best child run ID on the parent.

Hydra multirun is acceptable as a launcher, but do not let it produce anonymous
or untracked jobs. Each launched job starts its own MLflow run. Use a parent run
only when the launcher can propagate its run ID safely; otherwise use stable
study tags to associate the runs. Do not write a custom optimization loop when a
maintained search library already provides the required behavior.

A parameter study is not a substitute for grouping heterogeneous jobs or for a
workflow scheduler. Do not combine incomparable objectives or materially
different orchestration strategies into one study. Set an explicit budget for
searches that do not terminate intrinsically.

## Time to first interpretable result

Produce one representative end-to-end result before spending the full budget.
Expose enough early and periodic diagnostics that a user can identify failure
and interrupt the run. Start downstream diagnostics as soon as a usable input
exists when scheduling permits, then expand concurrency after the first path is
interpretable.

Monitoring may use cheaper proxies, but label them as monitoring aids and keep
final evaluation capable of supporting or rejecting the scientific claim.

## Scientific validity and perceptual blind spots

Before treating a result as evidence, verify that the evaluation has enough
fidelity, coverage, and statistical quality to reveal the effect being studied.
Changes to procedure, workload, reference, objective, baseline, or evaluation
that could alter the claim belong in config and tracking, not in hidden code.

When the user reports an important effect that normal inspection or current
metrics miss—temporal instability, localized artifacts, high-frequency
structure, or another domain-specific failure—treat it as an evaluation blind
spot:

1. Preserve the original outputs.
2. Add an analytical visualization that isolates, localizes, aggregates, or
   amplifies the phenomenon without changing the object being judged.
3. Track a quantitative measure that is plausibly sensitive to the same effect.

Prefer a standard, established metric when one is available and its assumptions
and sensitivities fit. Do not invent a bespoke quality score merely because a
generic metric is imperfect. Adapt or devise a more specific measure only when
standard metrics are unavailable or demonstrably miss the reported effect.

Validate a candidate measure in proportion to uncertainty. A well-established
metric need not be recalibrated without evidence of mismatch. When its relation
to the user's observation is unclear, test it on known positive, negative, and
confounding cases. If disagreement remains, propose a small calibration phase
using focused ratings, rankings, or pairwise comparisons, explaining what each
question resolves. Use those responses to select, fit, or threshold the
diagnostic without imposing unnecessary questionnaire burden.

Log the original output, analytical visualization, and measure separately with
stable keys. Do not claim that a metric replaces visual or expert judgment until
the evidence supports that interpretation. Report known disagreement and blind
spots.

## Reports

Do not scaffold reports by default; MLflow's UI is the primary interactive view.
When a reproducible report is requested, create `reports/<name>/report.py`. It
queries MLflow with `MlflowClient` or `mlflow.search_runs`, loads tracked
artifacts, and writes a self-contained output such as
`reports/<name>/report.html`. Register a pixi task for it.

Report code must select runs by stable experiment identity, tags, params, and
keys rather than hard-coded local paths. Keep source operands available so a
report can change presentation without rerunning the experiment. Never hand-edit
generated report output or use transient notebook state as its source.

## Documentation and handoff

Document durable constraints and non-obvious scientific choices, not the
chronology of development. Keep comments local; update or remove them when the
design changes.

The handoff states what changed or was learned, what validation supports it,
and what could still limit the conclusion. Distinguish smoke tests and proxies
from evidence. Disclose approximations and tracking-key compatibility changes.

## Reproducibility checklist

- [ ] `pixi.lock` is committed; `.pixi/`, local MLflow state, and caches are
      ignored.
- [ ] Python files were formatted with the project's pixi formatting task.
- [ ] Config lives in `configs/`; the fully resolved config is logged as an
      MLflow artifact.
- [ ] Hydra output directories and logs are disabled; MLflow is the run record.
- [ ] Configurable objects use `_target_` and `instantiate`; no parallel registry
      exists.
- [ ] Seeds and scientifically meaningful choices are explicit and tracked.
- [ ] The entry point selects and checks an `Experiment` without knowing its
      subordinate concepts.
- [ ] Each meaningful execution has an MLflow run; compact comparison fields are
      params/tags, numeric series are metrics, and rich outputs are artifacts.
- [ ] Environment facts capable of changing results are logged.
- [ ] Equivalent results retain compatible keys, units, representations,
      directionality, and step meaning across related projects.
- [ ] Comparison operands are separate; derived diagnostics have their own keys.
- [ ] Reusable models and outputs have stable MLflow URIs and explicit producer
      lineage.
- [ ] Comparable parameter trials use a maintained search tool when appropriate,
      with child runs or stable study tags, a bounded budget, and a declared
      objective and direction.
- [ ] One representative result appears early and long runs expose useful
      periodic diagnostics.
- [ ] Validation can support the intended claim; smoke tests and proxies are not
      presented as evidence.
- [ ] User-reported blind spots receive an analytical visualization and a
      suitable metric; standard metrics are preferred when applicable, and
      calibration is used only when their perceptual meaning is uncertain.
- [ ] Approximations that could change scientific meaning are configured,
      tracked, and disclosed.
- [ ] Compared runs differ only in intended factors, or unavoidable differences
      are tracked and accounted for.
- [ ] Every config group begins with a comment describing its intended regime.
- [ ] A fresh clone can reproduce the tracked experiment with documented pixi
      commands.
