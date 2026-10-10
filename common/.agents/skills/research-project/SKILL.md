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
5. **Develop the method with the user.** Resolve ambiguities, make intermediate
   behavior inspectable, and establish feasibility against relevant baselines
   before tuning or scaling.
6. **Use a flat project layout.** Create top-level directories named for the
   concepts the project actually contains; do not add `src/<package>/` nesting.
7. **Validation tests the claim.** Debugging proxies and smoke tests are useful,
   but identify them as such and do not present them as scientific evidence.
8. **Do not improve results by weakening the problem.** Any approximation that
   may change the scientific meaning must be explicit in config, logged with the
   run, and disclosed in the handoff.
9. **Preserve comparability.** Runs being compared should differ only in the
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
└── reports/             # MLflow-backed reports, including early method review
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
mlflow-ui = "mlflow server --host 0.0.0.0 --port 5000 --backend-store-uri sqlite:///mlflow.db --allowed-hosts '<remote-host>:5000,localhost:*' --cors-allowed-origins 'http://<remote-host>:5000,http://localhost:*'"
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

Always provide an exact command that hosts the MLflow server and UI for remote
access. Prefer a pixi task so it uses the locked environment, and replace
`<remote-host>` with the machine's actual DNS name or reachable IP address.
State both the task invocation and the remote URL it serves. With the setup
above, provide:

```bash
pixi run mlflow-ui
```

This listens on all interfaces and is reached at
`http://<remote-host>:5000`. If the project does not define that task, provide
the complete equivalent `pixi run mlflow server ...` command with its actual
host, port, backend store, allowed hosts, CORS origins, and any required
artifact-store options. Never leave `<remote-host>` or another placeholder in
the delivered project or handoff.

Binding to `0.0.0.0` provides reachability, not access control. Allow only the
actual hostname or address clients use; do not use `*` for allowed hosts or CORS
in a remotely reachable deployment. For access beyond a trusted private
network, put MLflow behind the project's VPN or an HTTPS reverse proxy with
authentication. Configure the advertised tracking URI as the reachable HTTPS
or HTTP URL rather than a local database URI on remote clients.

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
  run_name: <short semantic purpose>
  description: >-
    <what this run tests, why it is being run, and how to interpret it>
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
    run_name = str(cfg.tracking.run_name or "").strip()
    description = str(cfg.tracking.description).strip()
    if not run_name:
        raise ValueError("Every MLflow run requires a non-empty semantic name")
    if not description:
        raise ValueError("Every MLflow run requires a non-empty description")
    mlflow.set_experiment(cfg.tracking.experiment_name)
    with mlflow.start_run(
        run_name=run_name,
        description=description,
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

### Name and describe every run

Every MLflow run must have a short, readable, human-chosen name that communicates
what the run is doing. Name runs by purpose and role in the study—for example, a
method feasibility check, a reference baseline, or a specific ablation—not by
serializing their configuration. Someone scanning the run list should understand
the distinction between runs without decoding a parameter string.

Do not embed learning rates, seeds, dimensions, timestamps, hashes, or long lists
of flags in run names. Those values belong in MLflow params and the resolved
config. Use the description for the fuller question and interpretation. Prefer a
few plain words with one consistent separator; avoid redundant project names,
opaque abbreviations, and autogenerated adjective-noun names.

Early method-development runs should be especially clear because their purpose
is conceptual verification rather than tuning. Suitable patterns include
`feasibility-method`, `feasibility-reference`, and `ablation-no-<feature>`,
adapted to the project's actual language. After the feasibility gate, child
trials may add a short ordinal such as `tuning-trial-007`; keep parameter values
in params and summarize only the trial's meaningful role in its description.

Every MLflow run must have a concise, human-readable description. Pass it with
the `description=` argument to `mlflow.start_run`; MLflow exposes it in the run's
Notes section through `mlflow.note.content`. Keep the description in Hydra
config when it is known before execution, validate that it is non-empty, and
allow an intentional CLI override.

Describe the question or purpose of the run, its role in a larger study, the
factor that distinguishes it from its baseline or siblings, and any important
interpretation constraint such as a proxy evaluation. Do not paste the resolved
config or restate every parameter. A run name is an identifier, not a
description.

Parent and child runs each need descriptions. A study parent describes the
overall search and objective; each child describes the trial it represents,
including the distinguishing parameter values when useful. Generate these
descriptions deterministically for programmatic trials rather than leaving
generic text such as "trial 7".

The configured experiment owns its construction, lifecycle, tracking cadence,
and result semantics. Represent materially different orchestration with separate
Experiment implementations, not behavior flags or branches in the entry point.
Ordinary shared operations may remain functions until multiple implementations
justify a configurable concept.

## Developing a method

At the beginning of a research project, optimize for shared understanding before
scale or performance. The user and agent should agree on what the proposed
method does well enough that its implementation and intermediate behavior can be
checked, not merely described in broad terms.

### Establish a shared specification

Actively elicit the method from the user. Clarify its purpose, inputs and
outputs, sequence of operations, state and update rules, invariants, objectives,
assumptions, expected advantages, relevant regimes, and known failure cases.
Identify terms that could support multiple mathematical or implementation
interpretations. Ask focused questions about every ambiguity that could change
the method, comparison, or scientific conclusion; do not silently choose a
convenient interpretation.

Expect several short dialogue rounds when the method is new or underspecified.
Periodically restate the current method in precise language, equations,
pseudocode, diagrams, or concrete examples and ask the user to confirm or
correct it. Record confirmed choices in config, code, and the early report so
later work does not drift from the agreed target. Reopen the dialogue when an
implementation detail exposes a new ambiguity.

Questions should resolve real decisions rather than delay reversible work. The
agent may build small probes while clarification continues, provided their
assumptions are explicit and they are not mistaken for the agreed method.

### Make the interpretation inspectable

Create small, deliberately simple examples that expose each important part of
the method. Visualize inputs, intermediate states, transformations, outputs,
loss terms, update directions, and small optimization trajectories where they
help the user verify the interpretation. Prefer examples for which expected
behavior can be reasoned about independently.

Create many useful visualizations throughout implementation rather than adding
a single summary figure at the end. For each material mechanism or claim,
provide enough complementary views to inspect what enters it, what it changes,
how its intermediate state evolves, and where it succeeds or fails. Useful
families include input/output comparisons, intermediate-state snapshots,
objective components, update directions, convergence traces, spatial or
frequency decompositions, baseline comparisons, ablations, and representative
failure cases. Select the views that explain the actual method; do not generate
redundant decoration merely to increase the count.

Show representative intermediate iterations rather than only initial and final
results, including small optimization sequences early in development. Use
plots, image grids, diagrams, tables, or compact animations suited to the
phenomenon. Implement visualization generation as reusable project code instead
of one-off notebook state. Save or regenerate the project-facing outputs under
the project's reporting or diagnostic structure, log the same views and their
source values to MLflow with stable keys, and surface the most informative views
in the method-development report. Update these views whenever the implementation
or shared understanding changes. Their purpose is to let the user catch
conceptual divergence early, not to decorate a finished result.

### Establish baselines with the user

Identify baselines that test the claimed advantage under comparable conditions.
When several baselines are plausible, their relevance is uncertain, or the
target comparison is ambiguous, discuss the candidates with the user and agree
which ones define the feasibility study before implementing a large comparison.

Prefer faithful adaptations of authoritative reference implementations. Read
the relevant paper, documentation, configuration, evaluation protocol, and the
reference implementation end to end along the complete execution path being
adapted; inspect surrounding code wherever it changes that path's behavior. Do
not reproduce a baseline from a summary or remembered outline. Reuse or adapt
the reference implementation when its license, dependencies, and interfaces
permit. Otherwise implement the method faithfully and document every material
deviation. Track reference version or commit, configuration, inputs, and
deviations with the baseline run.

Keep workloads, data, preprocessing, budgets, stopping rules, and evaluation
equivalent unless a justified difference is part of the question. A baseline
that is intentionally simplified is a diagnostic, not evidence against the
reference method.

### Pass a feasibility gate before tuning

Begin with a bounded feasibility study, not a parameter sweep. First establish
that the implementation behaves as the agreed method predicts on simple and
representative cases. Then compare it with the agreed baselines and determine
whether there is credible evidence of the intended advantage, tradeoff, or new
capability under relevant conditions.

Agree with the user on the evidence needed to pass this gate, including
qualitative checks, metrics, baselines, tolerances, and important failure cases.
Do not start systematic tuning, large sweeps, or expensive scaling until the
user has been shown the feasibility evidence and the method has passed this
gate. If it does not pass, diagnose or revise the method and report that result
rather than tuning until an advantage appears.

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

Log all sensible metrics that help evaluate, compare, diagnose, or monitor the
experiment. Use stable keys and include meaningful steps where the metric varies
over time.

### Prefer image grids for related images

When several images belong together, log them as an image grid whenever MLflow
and the data shape support it. Prefer `mlflow.log_table` with `mlflow.Image`
columns: use rows for samples or steps and stable columns for corresponding
roles such as input, reference, prediction, residual, or mask. Include useful
identifiers and scalar context in adjacent columns. This makes relationships
inspectable without opening a collection of unrelated artifacts.

Keep grid layout, ordering, resizing, normalization, colormaps, and labels
consistent across runs so visual comparisons remain meaningful. A grid is a
view, not a replacement for source data: preserve separately addressable
operands and full-resolution reusable outputs. For large collections, log a
representative, deterministically selected grid and retain the complete output
as artifacts.

Use time-stepped `log_image(..., key=..., step=...)` when temporal evolution is
the important structure; optionally add grids at meaningful milestones. If an
MLflow version or media type cannot render an image table well, create a
deterministic labeled contact sheet as a fallback while still preserving the
individual images. Do not force unrelated images into a grid merely to reduce
artifact count.

Autologging may supplement explicit tracking, but do not rely on framework
defaults for the experiment's scientific claims. Explicitly log the stable
metrics, inputs, outputs, and diagnostics required for comparison.

Record environment facts not fixed by the lockfile or config when they can
change the result: actual device, backend, precision, selected implementation,
hardware, and relevant library/driver versions. Enable MLflow system metrics
when resource behavior matters; leave them off when their overhead or noise is
not useful.

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

Apply the parameter-study guidance in this section only after the method has
passed the feasibility gate above. Before that point, run only the bounded
comparisons and small probes needed to establish correctness and feasibility.

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

Create an initial method-development report near the beginning of a new research
project. It is a living verification surface for the shared method
specification, simple examples, intermediate behavior, feasibility evidence,
and baseline comparisons—not a polished final narrative. Build it from the
MLflow tracking database so MLflow remains the backbone of the evidence.

Place it under `reports/method-development/report.py`, or use a more specific
name when the project already has a reporting convention. Query MLflow with
`MlflowClient` or `mlflow.search_runs`, load tracked artifacts, and generate a
self-contained output such as `report.html`. Add a pixi task immediately so the
report remains reproducible while the method evolves. Update the report after
meaningful clarification or feasibility runs.

Reports should be visually rich enough to verify the implementation. Include
the tracked simple examples, intermediate states, small optimization sequences,
baseline comparisons, diagnostics, and failure cases that bear on the current
method claims. Prefer references to or renderings of the MLflow-tracked views so
the report and run record do not become separate sources of truth.

Every generated report must also be logged to MLflow as an artifact so MLflow
remains the single place from which the research record can be inspected. After
querying the source runs and generating the report, create a dedicated MLflow
run in the same experiment with a semantic name such as
`report-method-development`, an informative description, and a stable tag such
as `run_role=report`. Log the rendered report under a stable artifact path such
as `reports/method-development/report.html`.

Alongside the report, log a small manifest containing the source run IDs, report
kind or revision, and any selection criteria needed to reproduce the view. Do
not encode those IDs or revisions into the run name. Query source runs before
starting the report run, or exclude report-role runs explicitly, so a report
does not accidentally treat itself as experimental evidence. A generated local
file is a reproducible cache; the MLflow artifact is the canonical shared copy.

Create additional focused reports under `reports/<name>/report.py` when useful.
MLflow's UI remains available for open-ended exploration, while reports capture
the stable views used to verify and communicate the method.

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
Always include the exact MLflow hosting command and the URL it serves, even when
the command was already added as a pixi task or the server is currently running.
The command must listen on a remotely reachable interface and use concrete
allowed-host and CORS values for the advertised URL.

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
- [ ] All sensible evaluation, comparison, diagnostic, and monitoring metrics
      are logged with stable keys and meaningful steps where applicable.
- [ ] Every run, including study parents and child trials, has a non-empty,
      informative MLflow description rather than only a run name.
- [ ] Every run has a concise semantic name; parameter values, seeds, hashes,
      and other configuration details remain in params instead of the name.
- [ ] Environment facts capable of changing results are logged.
- [ ] Equivalent results retain compatible keys, units, representations,
      directionality, and step meaning across related projects.
- [ ] Comparison operands are separate; derived diagnostics have their own keys.
- [ ] Related images are logged as consistent image grids when practical, while
      source operands and full-resolution outputs remain separately available.
- [ ] Reusable models and outputs have stable MLflow URIs and explicit producer
      lineage.
- [ ] Comparable parameter trials use a maintained search tool when appropriate,
      with child runs or stable study tags, a bounded budget, and a declared
      objective and direction.
- [ ] One representative result appears early and long runs expose useful
      periodic diagnostics.
- [ ] The user and agent have resolved method ambiguities and confirmed a
      precise shared specification with simple examples.
- [ ] Visualizations expose important intermediate transformations and small
      optimization trajectories, not only final results; complementary views
      are generated by reusable project code, logged to MLflow, and included in
      reports where they help verify the method.
- [ ] Relevant baselines were agreed with the user and faithfully adapted from
      fully inspected authoritative references, with deviations tracked.
- [ ] A bounded feasibility study demonstrates the method's behavior and
      intended advantage or tradeoff before tuning or large sweeps begin.
- [ ] An early method-development report is generated from MLflow runs, logged
      back to MLflow as an artifact with a source-run manifest, and updated as
      understanding and feasibility evidence evolve.
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
- [ ] The handoff includes an exact, project-correct, remotely accessible MLflow
      hosting command and URL, with concrete allowed-host and CORS values.
- [ ] A fresh clone can reproduce the tracked experiment with documented pixi
      commands.
