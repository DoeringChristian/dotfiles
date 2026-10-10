---
name: standalone-research-project
description:
  Initialize, extend, or develop a self-contained reproducible research project
  managed with pixi, Hydra-configured object construction, Hydra run outputs,
  and an interactive commentable report. Use when research must avoid MLflow,
  Cairn, Weights & Biases, or another experiment-tracking service while retaining
  reproducible experiments, analytical diagnostics, cumulative findings, and
  structured user feedback.
---

# Standalone Research Project

Build research projects that need no tracking service. Hydra's built-in output
directories are the sole experiment record. A locally hosted interactive report
reads those runs, presents the evolving evidence, accepts user comments, and
turns confirmed feedback into durable project knowledge.

## Core principles

1. **pixi owns the environment.** Prefer `[pypi-dependencies]` for Python
   packages; reserve conda-forge for the interpreter, compilers, CUDA, and
   packages PyPI does not provide reliably. Commit `pixi.lock`.
2. **Hydra owns configuration, object construction, and run outputs.** Put
   configs under `configs/`, construct configurable objects with `_target_` and
   `hydra.utils.instantiate`, and keep every run self-contained in Hydra's output
   tree. Do not add an experiment-tracking database or service.
3. **The experiment is the executable boundary.** A config-selected
   `Experiment` is the highest-level behavior. The entry point composes config,
   prepares the Hydra run directory, instantiates the experiment, and invokes it.
4. **The report is the research interface.** It is generated from Hydra run
   data, records current findings and uncertainty, and provides persistent,
   contextual commenting. It must never become an independent source of
   experimental numbers.
5. **Develop the method with the user.** Resolve consequential ambiguities,
   visualize intermediate behavior, and establish feasibility against relevant
   baselines before tuning or scaling.
6. **Validation tests the claim.** Identify smoke tests and debugging proxies as
   such; do not present them as scientific evidence.
7. **Do not improve results by weakening the problem.** Configure and disclose
   approximations that may change the scientific meaning.

## Project layout

```text
project/
├── pixi.toml
├── pixi.lock
├── .envrc
├── .gitignore
├── configs/
├── <concept>/
├── experiments/
├── outputs/
│   └── <run-name>/
│       ├── <timestamp>/        # completed Hydra run or multirun study
│       └── latest -> <timestamp>/
└── reports/
    ├── build.py                # reads runs and builds the report
    ├── serve.py                # serves report and persists comments
    ├── generated/              # generated report, git-ignored
    └── knowledge/
        ├── comments.jsonl      # append-only user feedback
        └── findings.yaml       # reviewed cumulative knowledge
```

Use a flat import layout rather than `src/<package>/`. Create concept directories
only when the project needs them. Before using a top-level name, check it with
`python -c "import <name>"`; if that succeeds, choose another name.

Hydra run outputs and generated report files are reproducible local data and are
normally git-ignored. Commit the report source and, unless the project contains
sensitive material, the compact knowledge files. If comments cannot be
committed, document their backup and transfer path explicitly.

## pixi setup

Start with:

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
black = "*"

[activation.env]
PYTHONPATH = "."

[tasks]
experiment = "python experiments/run.py"
report-build = "python reports/build.py"
report-serve = "python reports/serve.py --host 127.0.0.1 --port 8000"
report-host = "python reports/serve.py --host 0.0.0.0 --port 8000"
format = "black ."
```

Add the smallest suitable web dependency only when implementing the report
server. Keep building, local preview, and remote hosting available through the
three report pixi tasks. The server should build the report on startup when the
generated version is absent or stale, or clearly instruct the user to run
`pixi run report-build` first. Commit `pixi.lock`; ignore `.pixi/`, caches,
`reports/generated/`, and the appropriate `outputs/` data. Do not add MLflow,
Cairn, W&B, TensorBoard-as-a-tracker, or a custom run database.

## Hydra configuration and run identity

Put every scientifically meaningful choice in config. Let Hydra create distinct
run directories:

```yaml
# configs/config.yaml
defaults:
  - experiment: primary
  - _self_

seed: 0
run:
  name: <short semantic purpose>
  description: <question, purpose, and interpretation constraints>

hydra:
  run:
    dir: outputs/${run.name}/${now:%Y-%m-%d_%H-%M-%S}
  sweep:
    dir: outputs/${run.name}/${now:%Y-%m-%d_%H-%M-%S}
    subdir: ${hydra.job.num}
  job:
    chdir: true
```

Hydra's `.hydra/config.yaml`, `.hydra/hydra.yaml`, and
`.hydra/overrides.yaml` are the authoritative configuration record. Add a small
machine-readable `run.json` only for facts Hydra does not already capture, such
as status, start and end times, code revision, actual device, or parent/source
run paths. Do not duplicate the full resolved config into another schema.

Names must be short and semantic—such as `feasibility-method`,
`reference-baseline`, or `ablation-no-feature`. Do not encode parameter lists,
seeds, timestamps, or hashes in them. Validate names as safe path slugs: reject
path separators, `.`/`..`, and characters outside the project's documented slug
alphabet. Put a concise description in config so a report reader understands
what was tested and how to interpret it.

### Maintain a per-name `latest` link

After a single run completes successfully, atomically update
`outputs/<run-name>/latest` to a **relative symlink** targeting that run's
timestamp directory. A failed or interrupted run must remain available for
diagnosis but must not advance `latest`.

For a Hydra multirun, the timestamp directory is the study root and its numbered
subdirectories are trials. Only the sweep launcher updates `latest`, and only
after the whole study reaches the project's declared successful completion
condition; individual trials must never race to update it.

Implement this in one small project helper called by the entry point or an
appropriate Hydra callback. Create a sibling temporary symlink, then replace
`latest` atomically. Resolve and verify both the run-name directory and target
before replacement; never recursively delete or follow an existing link. If an
unexpected non-symlink already occupies `latest`, stop and report the conflict
instead of overwriting it.

Treat `latest` as a convenience pointer, never as provenance. Reports and
manifests must resolve it once and record the immutable timestamp-directory path
they actually read. When discovering runs, skip the `latest` directory entry so
the same run is not counted twice.

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

The Hydra entry point obtains the current run directory through
`HydraConfig.get().runtime.output_dir`, verifies the configured object implements
`Experiment`, and passes that path explicitly. The entry point must not know
experiment-specific orchestration.

Each run directory should contain only evidence useful for understanding or
reproducing that run. Use clear formats that report code can read without
project-specific reverse engineering:

- scalar summaries and metadata as JSON or YAML;
- evolving metrics as a tidy CSV, JSONL, or another documented open format;
- tables as CSV or Parquet when the dependency is already justified;
- Matplotlib figures as PNG or SVG, with source arrays retained when useful;
- images, grids, animations, models, and other rich outputs as ordinary files;
- logs for diagnosis, while keeping scientific values in structured files.

There is no universal result schema. Preserve stable names, units, columns, and
meaning when compatible experiments should share report views. Never hide
important evidence through final-only output, excessive aggregation,
cherry-picked examples, or presentation-only composites. Avoid redundant files
that make the result harder to interpret.

Write important outputs atomically where practical. A failed run must remain
recognizably incomplete and must not be selected as valid evidence merely
because its directory exists.

## Developing a method

### Establish shared understanding

Ask focused questions about ambiguities in purpose, inputs, outputs, operations,
state, update rules, objectives, invariants, assumptions, intended advantages,
and failure cases. Restate the current interpretation with equations,
pseudocode, diagrams, or simple examples and ask the user to confirm it. Record
confirmed choices in config, code, and the running report. Reopen the discussion
when implementation exposes a consequential ambiguity.

### Make behavior inspectable

Create simple examples that expose important mechanisms. Visualize inputs,
intermediate states, transformations, outputs, loss terms, update directions,
small optimization trajectories, baseline comparisons, ablations, spatial or
frequency views, and representative failure cases as appropriate. Create enough
complementary views for the user to verify the implementation, not decorative
figures merely to increase their number.

Prefer image grids for related inputs, references, predictions, residuals,
masks, samples, or steps. Keep layout, normalization, labels, and ordering
consistent when comparison matters, while retaining important full-resolution
outputs.

### Build diagnostics with Matplotlib

Implement reusable functions that accept explicit data and return a Matplotlib
`Figure`. Depending on the method, show objective terms, residuals, update
magnitudes, distributions, spatial maps, spectra, convergence, intermediate
states, uncertainty, before/after views, and baseline overlays. Give axes units
and meaningful labels; use legends and colorbars where needed. Keep scales,
limits, normalization, colormaps, and panel order consistent across comparable
figures. Save the figures into their Hydra run and reuse the same functions in
the report.

### Establish baselines and feasibility

Agree with the user which baselines test the claimed advantage. Prefer faithful
adaptations of authoritative reference implementations: read the paper,
documentation, configuration, evaluation protocol, and complete relevant
execution path. Record the reference version and material deviations.

Begin with a bounded feasibility study. Establish that the implementation
behaves as agreed on simple and representative cases, then compare it with the
chosen baselines. Agree on the qualitative checks, metrics, tolerances, and
failure cases needed to pass. Do not start systematic tuning, large Hydra
multiruns, or expensive scaling until the user has seen the evidence and the
method has passed this gate.

## Interactive running report

Create the report at the beginning of the project and maintain it throughout.
It must show the current method, questions, decisions, findings, supporting and
contradictory evidence, limitations, unresolved issues, and proposed next
experiments. Update conclusions when evidence changes while preserving enough
decision history to explain the current understanding.

### Reproducible evidence

The report builder discovers valid Hydra run directories and reads their
`.hydra/` configs and structured outputs. It must record a machine-readable
manifest alongside every build containing the selected run paths, file hashes
or mtimes, selection criteria, report revision, and code revision. Every metric,
table, image, figure, and claim displayed from an experiment must link back to
its source run and, where feasible, source file. Never manually copy results
into report code or findings files.

Rebuilding from the same checkout, knowledge files, and preserved Hydra outputs
must reproduce the report. When run data is too large to retain locally, require
a documented external data location and integrity digest; do not silently make
the report irreproducible.

### Persistent contextual comments

Serve the report through a small project-owned web application. The user must
be able to comment on a report section, finding, figure, table, run, or data
point. Store comments server-side in `reports/knowledge/comments.jsonl`, not only
in browser local storage. Each append-only record should include a stable ID,
timestamp, author label when available, target type and stable target ID,
comment text, and optional reply-to ID. Preserve comments across report rebuilds
by keeping target IDs stable and show clearly when their target is obsolete.

Support resolution without deleting history: append a status event or retain
the original comment with resolution state and rationale. Treat comments as
user input, not automatically as scientific fact. The agent reviews new
comments, asks for clarification when their consequence is ambiguous, and
updates code, experiments, report interpretation, or planned work as warranted.

### Accumulating knowledge

Maintain `reports/knowledge/findings.yaml` as a concise reviewed synthesis, not
a second store of raw experimental data. Each finding should state the claim,
status (for example tentative, supported, contradicted, or superseded), source
run paths, relevant report anchors, originating comment IDs when applicable,
known limitations, and last review time. Claims remain traceable to Hydra run
files; comments explain user judgment and context.

When new results or comments conflict with a finding, surface the conflict in
the report and revise its status rather than silently overwriting it. The report
builder combines Hydra evidence, reviewed findings, and comments into the
current view. The agent should explicitly summarize what knowledge changed
after incorporating a feedback round.

### Hosting and safety

Always provide exact local-preview and remote-hosting commands with their
concrete URLs. The example tasks use:

```bash
pixi run report-build
pixi run report-serve  # http://127.0.0.1:8000
pixi run report-host   # http://<remote-host>:8000
```

Replace `<remote-host>` with the actual hostname or reachable IP in the
handoff. `report-serve` is the safe local default; `report-host` binds to all
interfaces. Because the report accepts writes, do not expose it directly to an
untrusted network. Use a trusted private network, VPN, or authenticated HTTPS
reverse proxy. The server must validate comment size and format, escape
untrusted text when rendering it, and restrict writes to the intended knowledge
files.

## Parameter studies

Only after feasibility, use Hydra multirun for repeated comparable trials.
Declare the parameter space, seed, budget, objective, and direction. The report
must identify all trial directories, their status, and the selected result. Use
a finite grid for intentional comparisons, random search for bounded
exploration, and an appropriate Hydra sweeper plugin only when adaptive search
is justified. Do not add a tracking service merely to run a sweep.

## Perceptual blind spots

When the user reports an important effect that current inspection or metrics
miss—such as temporal instability, localized artifacts, or high-frequency
structure—preserve the original outputs, add an analytical visualization that
isolates the phenomenon, and record a plausible quantitative measure.

Prefer a standard established metric when its assumptions fit. Adapt or devise
a specific measure only when standard metrics are unavailable or miss the
effect. When its relation to perception is unclear, test known positive,
negative, and confounding cases. If uncertainty remains, propose a small
calibration phase using focused ratings, rankings, or pairwise comparisons.
Record the resulting interpretation and limitations in the report.

## Documentation and handoff

The handoff states what changed or was learned, what validation supports it,
and what could still limit the conclusion. Distinguish smoke tests and proxies
from evidence. Include exact commands for reproducing experiments, rebuilding
the report, and hosting its commentable interface; provide the concrete URL and
explain where comments and reviewed findings are stored.

## Reproducibility checklist

- [ ] `pixi.lock` is committed and a fresh clone can run documented pixi tasks.
- [ ] No external or custom experiment-tracking service or database is used.
- [ ] Every run retains Hydra's `.hydra/` configs plus structured results and a
      recognizable completion state in its Hydra output directory.
- [ ] Runs use `outputs/<run-name>/<timestamp>/`; after successful completion,
      `outputs/<run-name>/latest` atomically points to that immutable directory.
- [ ] Failed runs do not advance `latest`; multirun trials do not race to update
      it; report manifests record resolved timestamp paths rather than symlinks.
- [ ] Run names are concise and semantic; descriptions explain their purpose.
- [ ] Reusable Matplotlib diagnostics expose intermediate behavior, and related
      images use consistent grids where practical.
- [ ] The user confirmed the method specification and consequential ambiguities.
- [ ] Relevant baselines are faithful and a bounded feasibility study precedes
      tuning or large multiruns.
- [ ] The running report is generated from Hydra run outputs and every displayed
      result links to a source run or file.
- [ ] Every report build has a source manifest sufficient to reproduce it.
- [ ] Comments persist server-side with stable targets and immutable history;
      resolving a comment does not erase it.
- [ ] Reviewed findings cite source runs and comment IDs, expose conflicts, and
      distinguish evidence from user interpretation.
- [ ] User-reported blind spots receive analytical views and suitable metrics;
      established measures are preferred and calibrated only when needed.
- [ ] The report server safely handles untrusted comment text and is not exposed
      unauthenticated to an untrusted network.
- [ ] The handoff includes exact report build, local-preview, and remote-hosting
      pixi commands, concrete URLs, and the locations of run data, comments,
      and findings.
