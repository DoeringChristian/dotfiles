---
name: standalone-research-project
description:
  Initialize, extend, or develop a self-contained reproducible research project
  managed with pixi, Hydra-configured object construction, Hydra run outputs,
  and interactive commentable reports. Use when research must avoid MLflow,
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
4. **The reports are the research interface.** They are generated from Hydra run
   data, records current findings and uncertainty, and provides persistent,
   contextual commenting. They must never become an independent source of
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
│   └── hydra/launcher/         # <cluster>.yaml, <cluster>_debug.yaml from each cluster's skill
├── <concept>/
├── experiments/
│   ├── base.py                 # Experiment interface
│   ├── run.py                  # copied from assets/run.py: entry point + run bookkeeping
│   ├── cluster.sh              # copied from the slurm skill's assets: Slurm cluster backend
│   ├── finalize_study.py       # copied from the slurm skill's assets, next to cluster.sh
│   └── clusters/<cluster>.sh   # each cluster's profile, from its skill (kuma, lyra)
├── provenance/
│   └── source_snapshot.py      # copied from assets/source_snapshot.py
├── outputs/
│   └── <run-name>/
│       ├── <timestamp>/        # one run, or a multirun study of numbered trials
│       └── latest -> <timestamp>/
├── tools/
│   └── check_reports.py        # copied from assets/check_reports.py: the report conventions
├── reports/                    # report content only; the agent writes here
│   ├── report.md               # the overview, served at /
│   ├── assets/                 # optional: its illustrations, HTML fragments
│   └── <slug>/                 # one report per research direction or idea, served at /<slug>/
│       ├── report.md           # front matter includes its `summary:`
│       └── assets/             # non-experimental illustrations, HTML fragments
├── cairn-report.toml           # the Copy preamble; optional style and hub settings
└── generated/reports/          # build output (a direction in <slug>/), git-ignored
```

Use a flat import layout rather than `src/<package>/`. Create concept directories
only when the project needs them. Before using a top-level name, check it with
`python -c "import <name>"`; if that succeeds, choose another name.

Initialize Git and commit the scaffold (code, configs, `pixi.toml`,
`pixi.lock`, and report sources) before the first experiment run, and commit
again before runs whose results a report will cite. Snapshots then use the
compact `git` mode and every run records the revision it ran; a project without
a commit falls back to `tree` snapshots and shows "unversioned" in its reports.

Hydra run outputs and generated report files are reproducible local data and are
normally git-ignored. Commit the report sources (`reports/`), `tools/`, and
`cairn-report.toml`. Comments live in the reader's browser until the user copies
them to the agent (see Comments).

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
cairn-report = { git = "https://github.com/DoeringChristian/cairn-report.git", tag = "v0.6.2" }

[activation.env]
PYTHONPATH = "."

[tasks]
experiment = "python experiments/run.py"
report-build = "cairn-report build && python tools/check_reports.py"
report-check = "python tools/check_reports.py"
report-serve = "cairn-report serve --host 127.0.0.1 --port 8000"
report-host = "cairn-report serve --host 0.0.0.0 --port 8000"
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
`latest` and the report check (`tools/check_reports.py`) apply this same rule. Do not duplicate the full
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

Copy [`assets/source_snapshot.py`](assets/source_snapshot.py) into the project as
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

Copy [`assets/run.py`](assets/run.py) unchanged into the project as
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
outputs. Treat every repeated dataset, seed, model, or method comparison as one
visualization family with a declared visual grammar. For that family, keep the
chart type and marks, model colors, axis orientation, limits and scales, dataset
and model ordering, normalization, aggregation, and panel layout stable. Generate
all members through the same plotting function or declarative specification.
`sharex`/`sharey` inside one Matplotlib figure is not enough when comparable
figures are produced by separate Hydra runs: define cross-run limits,
normalization, ordering, and panel geometry in a shared visualization contract
or config, and pass them explicitly to every plot. Do not derive each run's
limits independently from its own observations. If a zoom or different scale is
needed to answer another question, keep the stable overview comparison too and
label the zoom as a distinct analytical view. Changing the visualization is
justified only when the analytical question changes; state that reason in the
report. Never switch chart types selectively because one representation makes
the preferred method look stronger.

### Build diagnostics with Matplotlib

Implement reusable functions that accept explicit data and return a Matplotlib
`Figure`. Depending on the method, show objective terms, residuals, update
magnitudes, distributions, spatial maps, spectra, convergence, intermediate
states, uncertainty, before/after views, and baseline overlays. Give axes units
and meaningful labels; use legends and colorbars where needed. Keep scales,
limits, normalization, colormaps, and panel order consistent across comparable
figures, and centralize method colors and ordering in one module. Save the figures into their Hydra run and
reuse the same functions in the report.

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

The reports are the research interface: generated from Hydra runs, they show
the current method, questions, decisions, findings, supporting and
contradictory evidence, limitations, and next experiments, and they collect the
user's comments. Create them at the start of the project and keep them current.

### Organize reports: one overview, one report per direction

A report is a folder with a `report.md` and an optional `assets/` folder;
cairn-report builds the folder tree into one site. The project has one
**overview**, the root report `reports/report.md`, served at `/`, and one
**direction report** per branch of the research process or per idea, as a
child folder `reports/<slug>/report.md` (short, stable lowercase slug), served
at `/<slug>/`. A direction is a self-contained question with its own methods and
evidence, such as an alternative method, a failure investigation, or a
follow-up study. Do not split a report merely because it grew long, and do not
keep two reports about the same question. Do not nest further levels unless the
user asks for them.

Every direction report begins with a front matter `summary:` of one to three
sentences (at most 400 characters): what the direction tests, its current
result or state, and what is pending. Results in it are `{{ }}` values like
anywhere else; they are evaluated after the report's code blocks ran. Write it
as a YAML block scalar (`summary: >-`) so a leading `{{` stays text. Keep it
current whenever the direction's evidence changes; the report check fails
without it or when it is too long. The direction page shows it under its title,
and the overview's direction cards quote it, so it must stand on its own. Every
direction page links back to its card in the overview automatically.

The overview does not follow the paper structure. It has exactly three
sections, in this order:

1. `## Introduction`: the general target the whole project pursues, the one
   problem every research direction tries to solve. State why it matters, the
   success criteria all directions are judged by, and the constraints they
   share. It is the jumping-off point for every direction: each direction's own
   Introduction links to it (`report:/#introduction`) and builds on it
   instead of restating it. Change it only when the project's goal changes.
2. `## Status`: a status report across directions for someone deciding what to
   do next: which directions are promising, stalled, contradicted, or finished,
   where they agree or conflict, and the next decision (in a `decision` or
   `question` callout). It ends with **proposed directions** that have no
   report yet, each with the idea, why it might reach the target, and what
   would justify starting it. It cites direction findings with links and keeps
   the numbers in the direction reports. Status is a summary, but the numbers
   rule still holds: a result it states (a rate, a threshold where a method
   breaks, a comparison) comes from a `{{ }}` value computed from run files or
   is replaced by a link to the finding that holds it; never type it.
3. `## Research directions`: a ``` ```reports ``` ``` fence that renders one card
   per direction (title, status, summary, finding counts, link). An empty fence
   lists every direction; list slugs, one per line, to choose and order them.
   Directions are built before the overview.

The sample overview and direction reports carry this guidance as `<!-- -->`
comments under each heading, and the direction sample does the same for every
section of the paper-like spine. Comments are author guidance and agent
directives only: the build drops them (outside code fences), so keep them in
the source and replace the sample text beneath them. When a direction is
proposed in Status and then started, create its report and remove it from the
proposals.

Cross-link related reports instead of repeating their content. Link to another
report, or to a heading, finding, or figure in it, with
`[text](report:<slug>#anchor)`; the overview is `report:/`, and anchors are
heading ids, `finding-<slug>` ids, and figure ids. The build fails on a link
to a missing report or anchor. When a direction builds on, contradicts, or
supersedes another, say so where it matters (in Background, a finding, or the
Conclusion) and link there. Every report's sidebar lists the overview first and
every direction beneath it, so the overview is one click away from any page.

### Keep each report editorially coherent

A report is the primary communication surface between the user and agent, not
an append-only activity log. Optimize it for a reader who needs to understand
the current method, evidence, and decisions quickly. Keep the narrative
concise, use progressive disclosure for supporting detail, and remove
repetition, stale explanations, superseded conclusions, and figures that no
longer answer an active question. Provenance and decision history live in the
manifest, run outputs, findings, and comment log, not in the visible narrative.

When the user requests an edit, clarification, comparison, or more evidence,
first decide what it means for the report's structure. Integrate a local
clarification where its concept is introduced; revise rather than append a
near-duplicate. If the request changes the method, interpretation, or research
question fundamentally, reconsider the section order, framing, summaries,
figures, and whether it belongs in a new direction report. After substantive
updates, read the report as a whole: the abstract must match the evidence,
terminology must be consistent, and the most important open questions must stay
prominent.

### Use a paper-like structure for direction reports

Author every direction report with this ordered spine (the overview has its own
structure, above):

1. `## Abstract`: question, approach, principal result, important
   qualification, and current decision, self-contained.
2. `## Introduction`: how this direction serves the project target (link
   `report:/#introduction` rather than restating it), its research
   question, scope, motivation, and why the comparison matters.
3. `## Background and related work`: prior and related work, the baselines,
   and the comparison ladder, written for a technically literate reader who has
   not seen the code (see below).
4. `## Methods`: a paper-ready explanation of the proposed method (see
   "Explain the method like a paper" below), then the experimental design:
   data, protocol, fairness controls, and which contrast supports each causal
   claim.
5. Project-specific results and discussion sections: findings, quantitative
   evidence, diagnostics, ablations, contradictions, and limitations, arranged
   around the research question rather than the chronology of runs.
6. `## Conclusion`: the answer the evidence supports, its limits, and the next
   decision or experiment.

The builder renders any structure; following this spine is the author's job.
Add Results, Discussion, Limitations, or Appendix sections when they help, keep
the Abstract first and the Conclusion last, and put hidden loading code in a
preamble but visible metrics inside a named section.

**Explain the method like a paper.** The Methods section is where the user
checks that the implementation matches the idea, so spend real time on it: it
must be ready to go into a paper. A reader who knows the field, but not this
project or its code, must be able to understand what the method does, why it
should work, and how to reimplement it from this section alone. Write it before
results are discussed, and revise it whenever the method changes. Use these
subsections, in this order:

1. `### Problem setup`: inputs, outputs, and unknowns, with every symbol
   defined once and used consistently in all equations, figures, and code
   names that the report mentions.
2. `### Method`: the method step by step with its equations (objective,
   constraints, update rules or forward pass). Explain every term in words:
   what it does, why it is there, and what changes without it. Give an
   algorithm (numbered steps or pseudocode) when the method is iterative or has
   several stages.
3. `### Why it works`: the intuition, the assumptions it relies on, and where
   it should fail; tie each assumption to a finding or experiment that tests it.
4. `### Relation to the baselines`: what each baseline does differently, in the
   same notation, so every difference is one term, step, or setting.
5. `### Implementation`: the choices that affect results: discretization,
   initialization, how hyperparameters were chosen, numerical safeguards, and
   cost.
6. `### Experimental design`: data, protocol, fairness boundary, and the
   contrast behind each claim (see below).

**Illustrate every non-obvious concept with a figure** that explains the
mechanism, not a result: the model as a graph (see Diagrams), and for each key
operation a small example of what it does, such as before and after on a toy
input, a one-dimensional slice, a small grid, or the geometry of a constraint.
Compute figures of the method's behaviour with the project's own code on small
inputs (a `python exec` block that imports the project's functions, or an
illustration experiment logged with `RunLogger`), never with a separate
re-implementation or a hand-drawn approximation, so the figure shows what the
code actually does. Refer to each figure where its concept is introduced and
say in the text what to see in it. The report check fails when Methods is
missing these subsections, has fewer than 400 words of explanation, no display
equation or algorithm, or fewer than two figures.

**Related work is researched, not recalled.** Before the method is settled, and
again when the question changes, populate Background and related work through a
dedicated literature and prior-art search. Run it as a research subagent when
the harness provides one, and give it the research question, the proposed
mechanism, and the baselines, but not the desired answer. It searches papers,
preprints, documentation, and open-source code for the same or similar ideas
and returns sources with links and a one-line relation to this project. Cite
the relevant sources in the report, and cross-reference the project's other
direction reports that study related ideas. Flag prior art directly in a callout where the reader
needs it:

```markdown
!!! prior-art "Close prior work: <short name>"
    <Source, with link> already does <what>. This report differs only in
    <difference>, so it is a replication or an extension, not a new idea.
```

Use `prior-art` whenever the idea, or a close variant, already exists. Name
what remains new, if anything, and let it change the plan (replicate first,
reuse the reference implementation, or narrow the claim). Never omit a
discovered overlap because it weakens the novelty of the work.

**Define every method before results use its name.** Background and related
work holds a compact table whose first column is `Method`; useful remaining
columns are `What it does`, `Difference from baseline`, and `Held constant`.
Keep it to decision-relevant methods, and move a long variant catalog to its own
direction report. A label such as "no sharing", "official", "tuned", or "ours" is
not an explanation: state what each method stores or predicts, which parameters
are shared, independent, quantized, frozen, or learned, which training or
inference operations change, and what mechanism the change tests. For an
ablation, name the single removed or substituted component. For a ladder of
baselines, distinguish the authoritative baseline, faithful reimplementation,
matched-strength control, proposed method, and ablations.

**State the fairness boundary**: data and split, seeds, budget, parameter count
or rate, initialization, optimizer and schedule, stopping rule, and evaluation.
Mark comparisons that change several factors as confounded. Use a diagram or
concrete example when sharing, indexing, data flow, or accounting is not quick
to grasp from prose.

**Keep summaries decision-critical.** Metric cards hold only values the next
decision depends on; each label and detail says what is compared or subtracted,
whether higher or lower is better, the evaluated population, and the
aggregation. Findings hold only decision-relevant claims; supporting numbers go
to the evidence sections. After drafting, ask whether a technically literate
reader unfamiliar with the project could explain the proposed method and its
difference from every baseline without reading code. If not, revise first.

### Use callouts for synchronization

Use a callout when the reader could otherwise miss something that changes the
shared understanding or the next decision: an unresolved assumption, a
surprising limitation, contradictory evidence, overlapping prior art, a risk of
misinterpretation, a decision gate, or a question for the user. Keep each one
short, give it a specific title, and say what response is needed. Remove or
rewrite it once resolved. Types: `question` (input needed from the user),
`decision` (pending or confirmed choice), `prior-art` (the idea or a close
variant already exists), `warning` or `risk` (consequential limitation), and
`important` (context the reader must not overlook).

```markdown
!!! question "Which reference behavior is authoritative?"
    The two candidate baselines use different boundary handling. Confirm the
    intended behavior before feasibility results are interpreted.
```

### Install the report tooling

The report builder, server, page style, and run logger are the `cairn-report`
package (<https://github.com/DoeringChristian/cairn-report>), a pinned pixi
dependency (see pixi setup). It builds any report tree and enforces none of this
skill's conventions; [`assets/check_reports.py`](assets/check_reports.py),
copied to `tools/check_reports.py`, does, and `pixi run report-build` runs it
after every build. Start the reports from the samples in
[`assets/reports/`](assets/reports/):

```bash
mkdir -p reports tools
cp <skill-directory>/assets/reports/report.md reports/report.md            # the overview
cp -R <skill-directory>/assets/reports/direction reports/local-fitting     # a sample direction
cp <skill-directory>/assets/check_reports.py tools/check_reports.py
```

Add a direction later by copying `assets/reports/direction` to
`reports/<slug>`. Build once as a smoke test and visual reference: the sample
direction exercises every component. Then rename the direction folder and
replace its sample content, summary, and `assets/` with the direction's own
material. Replace the sample overview text at the same time: its `report:` links
name the sample slug, and the build fails on links to a renamed report. Build
output goes to `generated/reports/` and never into `reports/`.

Create `cairn-report.toml` with the text the Copy button puts before the
comments it copies, so pasted comments arrive with their handling instructions:

```toml
[page]
copy_preamble = """
Please address these report comments. For each one, locate its quote first,
falling back to its line or target; make the requested change, or ask me if its
consequence is ambiguous. Then run `pixi run report-build`, re-read every
section you changed, and summarize what changed in the code, runs, findings,
and reports. I clear the comments in the browser once they are handled.
"""
```

The tooling is a dependency, not project code: never copy, patch, or vendor
it into the project. When it needs a fix or a feature, change the
`cairn-report` repository, release a tag, and bump the pinned `tag` in
`pixi.toml`; the manifest of every build records the installed version and
commit. The default style is the shared report style. A project may change it
only when the user asks, through `cairn-report.toml`: `[style] css = [...]`
adds stylesheets after the default (override its CSS variables such as
`--accent` or `--paper`), and `[style] template_dir` replaces whole page files
(`index.html`, `report.css`, `report-extra.css`, `report.js`) by name. Keep such
files outside `reports/`, for example in `style/`.

### Write the report in `report.md`

Each `report.md` (the overview or a direction) is the narrative source of its
report; HTML fragments it includes are the only other authored input, and
every number is computed from run files. There is no hand-written data file. The page renders the
Markdown top to bottom, and its `##` headings form the section navigation.

- **Front matter** names the report: `title` (required by the check),
  `subtitle`, `status`, and, for a direction, `summary` (required).
- **Metric cards** come from `metric(label, value, detail="", fmt=None)` calls
  in a `python exec` block.
- **Values in prose** use `{{ expression }}` or `{{ expression:.3f }}`,
  evaluated in the exec namespace at that point of the document. Write
  "residual {{ final:.3f }}", never a typed number. The report check lists the
  decimals and percentages still typed in prose, by line (from the manifest's
  `typed_numbers`); turn each result into a `{{ }}` value and leave only design
  constants, such as a gate threshold, typed.
- **Findings** are `!!! finding <status> "Title"` blocks with status
  `tentative`, `supported`, `contradicted`, or `superseded`. Their id is
  `finding-<slug of the title>`, so keep titles stable: state the claim
  qualitatively ("The adaptive threshold breaks down earlier than the oracle"),
  never with a result number, and give the numbers in the body as `{{ }}`
  values. The check fails on another status or a title with a percentage or
  decimal, because a changed number would change the id and break links to the
  finding.
- **Figures** are Markdown images, `![Title](path "Caption"){#fig-id}`; a
  paragraph of only images becomes a figure grid, and a `.plotly.json` file an
  interactive Plotly figure. Matplotlib figures created in `python exec` blocks
  become figure cards too (`num="<slug>"` gives a stable `fig-<slug>` id).
- **Diagrams** are Graphviz fences, and only where they explain structure (see
  Diagrams); **cross-report links** use `report:`; the
  overview's **direction index** is a `reports` fence; **tables** are pipe
  tables; everything else is ordinary Markdown.

Take experimental figures directly from the run that wrote them, as
`run:<run-name>/figures/<name>.png` (the run's `latest`;
`run:<run-name>@<timestamp>/...` pins one run). These references work whether
the run is local, on a hub, or in MLflow. Other figure paths are relative to the
report folder; keep `assets/` for material that is not an experimental result.
The build fails on remote URLs, missing files, and duplicate ids; the report
check fails on figures and values from runs whose `run.json` is not
`completed`. The build copies each figure into the site by its resolved path
and records where it came from.

Every figure opens in one ordered lightbox with keyboard navigation, zoom, and
panning, and every enlarged figure says where it came from: an (i) toggle shows
its exact file, run, the code that drew and logged it (from `artifacts.jsonl`),
the run's commit and uncommitted patch, its MLflow or hub run when there is one,
and the `report.md` line. Do not present a figure whose provenance the build
cannot establish. Plotly figures are JSON artifacts with `data`, `layout`, and
optional `config`, rendered from the locally bundled runtime with their native
tools. The template implements these behaviors; verify them at desktop and
phone widths after changing it.

### Diagrams

The diagram a direction report most often needs is **the model as a graph**:
its inputs, parameters, latent variables, intermediate quantities, and outputs,
and how each depends on the others (the architecture, the computational graph,
or the probabilistic model), labelled with the symbols the equations use. Draw
it when the model has more than a couple of interacting parts, so the reader
can map every term in the equations to a node, and say in the text what to read
from it (for example which parts the proposed method adds or changes and which
it shares with the baselines). A single equation needs no graph.

Do not draw:

- the report or run tooling (config, runs, `outputs/`, report, comments): it is
  the same in every project and says nothing about the research;
- a linear chain of protocol steps (data, then method, then evaluation): write
  it as a numbered list in Methods;
- a restatement of a table or of the prose right above it.

Draw the graph as a Graphviz fence and let Graphviz place the nodes; never
hand-position nodes in SVG or HTML:

````markdown
```dot id=fig-model title="The model as a graph" caption="Observations y and parameters θ define both terms; the proposed method adds only the masked smoothness term."
digraph {
  rankdir=LR
  node [shape=ellipse]
  y [label="y (observations)"]
  theta [label="θ (lattice)"]
  m [label="m (boundary mask)"]
  node [shape=box]
  data [label="L_data(θ; y)"]
  smooth [label="λ‖∇θ‖² on m" style=dashed]
  loss [label="L(θ)"]
  y -> data; theta -> data; theta -> smooth; m -> smooth
  data -> loss; smooth -> loss [label="proposed only"]
}
```
````

The first word chooses the engine (`dot`, `neato`, `fdp`, `sfdp`, `circo`,
`twopi`); `id`, `title`, and `caption` fill the figure card. The build embeds a
static SVG in the report palette, so viewing needs no JavaScript, and syntax
errors fail the build.

### Executable Markdown

Only fences marked `python exec` run, in one shared namespace in document
order; add `hide` to run without showing the source. Their stdout and new
Matplotlib figures appear in the report, and an exception fails the build.
Never execute an unmarked fence or code derived from a comment. The namespace
provides `REPORT_ROOT` (the report folder), `PROJECT_ROOT`, `META` (front
matter), and these helpers, which record every file they read in the manifest:

- `run_dir(name, timestamp="latest")`: the resolved run directory (local, or
  downloaded from the hub or MLflow); the manifest records its status, and the
  report check fails unless it is `completed`.
- `run_trials(study)`: every trial of a multirun study, with its `trial`
  number, `dir`, `overrides`, and `status`.
- `read_scalars(run)`: latest value per scalar name from `metrics.jsonl`.
- `read_json(path)`, `read_csv(path)`, `read_jsonl(path)`, and `track(path)`
  for any other file.
- `metric(...)` for a card and `report_html(markup)` for generated HTML.

````markdown
```python exec hide
run = run_dir("feasibility-method")
scores = read_scalars(run)
metric("RMSE of the proposed method", scores["rmse"], "lower is better; mean over 30 held-out seeds", fmt=".3f")
```
````

The builder is local and trusted: executable Markdown has the author's
permissions, so never build untrusted Markdown. For slow reports, cache by the
block source and input-file digests; run potentially unbounded code in a
subprocess with a timeout rather than weakening failure behavior.

### Mathematics

Write `$...$` inline and `$$...$$` on separate lines for display equations. The
build converts LaTeX to MathML (no browser-side library), keeps bare delimiters
such as `\lVert` from stretching unevenly, and fails on unsupported LaTeX. A
selection inside a formula is quoted as its LaTeX source. `{{ }}` values are
not evaluated inside formulas, so the build fails on them there; write the value
next to the formula. Use ordinary code fences for literal dollar signs.

### Custom HTML

Plain Markdown never passes raw HTML through. Where Markdown cannot express the
content, such as a side-by-side layout, insert author HTML through:

- an `html raw` fence for short snippets (the report check fails above 20
  lines or 1,500 characters);
- an `html include` fence naming `assets/<name>.html` for anything larger;
- `report_html(markup)` in a `python exec` block for HTML generated from run
  data.

Author HTML must be self-contained: scripts, `<iframe>`, `<object>`,
`<embed>`, `<link>`, `<base>`, `<meta>`, `on*=` handlers, `javascript:` URLs,
and external resources fail the build. Style it with the template's classes
(`.callout`, tables, `.pill`), and never insert comment text or other untrusted
input as HTML.

### Reproducible evidence

Every report build writes a `manifest.json` next to each page
(`generated/reports/manifest.json` for the overview,
`generated/reports/<slug>/manifest.json` for a direction) with:

- the resolved run paths with their `run.json` status, and the selection rule;
- the hash of every file the report read or displayed, including each run's
  `run.json`, `metrics.jsonl`, `artifacts.jsonl`, provenance manifest and
  patch, and every included fragment;
- its cross-report links;
- the Markdown hash and the project's code revision;
- the `cairn-report` version and commit, and any style overrides;
- the Python version, rendering package versions, the bundled Plotly.js version
  and hash, and the Graphviz version.

Every displayed metric, table, figure, and claim must trace to its source run
and file; never copy results into report code or prose by hand. Rebuilding from
the same checkout and preserved outputs must reproduce the report. When run
data is too large to keep locally, document its external location and an
integrity digest.

### Comments

Readers comment by selecting text or clicking a figure's comment icon. Comments
are kept in that browser only, per report, with a stable `id`, `target` (such as
`figure:<id>`, `finding:<id>`, or `markdown:line:<n>`), the source `line` when
applicable, the selected `quote`, `text`, and `timestamp`. The page's Copy
button puts all of a report's comments on the clipboard as JSON, after the
`copy_preamble` from `cairn-report.toml` and the report's source path; the user
pastes them to the agent and clears them with the Clear button once handled.
There is no comment file in the project.

Handle comments the user pastes:

1. For each comment, locate its quote first, falling back to its line or
   target. Make the change, or ask when its consequence is ambiguous. A comment
   is user input, not scientific fact.
2. Re-read every section the change touched, including sentences you did not
   edit, and check the report check's typed-number list, so earlier claims are
   revised or converted rather than left stale. Rebuild with
   `pixi run report-build`.
3. Summarize what changed in the code, runs, findings, and reports, per comment
   id, so the user knows which comments to clear.

Address `@agent` source comments such as `<!-- @agent: compare this with the
reference run -->` (the build drops comments, so readers never see them) the
same way, then remove them or replace them with a documented resolution.

### Accumulating knowledge

Keep the reviewed synthesis in the reports themselves, as `!!! finding` blocks,
not in a second store. Each finding states the claim, its status, and its
evidence through `{{ }}` values computed from run files, and ends with a short
line naming the source runs or files, originating comment ids, known
limitations, and the last review date. When new results or comments conflict
with a finding, surface the conflict and revise its status (for example to
`contradicted` or `superseded`) rather than silently overwriting it; when the
conflict comes from another branch, link that report. After a feedback round,
summarize what knowledge changed.

### Hosting and safety

```bash
pixi run report-build  # builds every report and runs the report check
pixi run report-serve  # http://127.0.0.1:8000 (overview); directions at /<slug>/
pixi run report-host   # http://<remote-host>:8000
```

If the port is taken, for example by another project's report server, the
server moves to the next free port and prints the URL it actually uses; keep
8000 in the pixi tasks rather than editing them, and pass `--strict-port` when
an exact port is required. Give the concrete URLs in the handoff, as printed,
with `<remote-host>` replaced by the real hostname or address. The built site is
static and the server accepts no writes. `report-serve` is the safe local
default; `report-host` binds to all interfaces and shows the project's results
to anyone who can reach it, so expose it only on a trusted private network, a
VPN, or behind an authenticated HTTPS reverse proxy.

**Share the generated reports unchanged.** When the user asks to share,
publish, or upload the reports anywhere (the hub, a static host, a claude.ai
artifact, a document tool), publish the built `generated/reports/` output
exactly as cairn-report produced it: every file, with the same paths, names,
and styling. Never restyle, re-template, re-theme, summarize, or re-author the
pages for the destination, and never hand-write a new page "based on" a
report. A publishing tool's own design or formatting guidance (for example "give
each page a visual identity" or "make it theme-aware") is for pages the agent
designs from scratch; it does not apply to these reports, because the user's
request and the project's existing report design take precedence. Only
`[style]` in `cairn-report.toml`, changed when the user asks, alters how the
reports look. If a destination cannot serve the built files unchanged (for
example, it accepts only one self-contained page), say so and ask the user
before producing anything different.

### Remote runs and the hub

When experiments run elsewhere (a cluster, a cloud machine) or the user wants
all projects in one place, push them to a `cairn-report` hub: one
token-protected artifact store, run by the user. It keeps every version of each
project's report (sources and built pages, served at `<hub>/p/<project>/`, an
older version at `<hub>/p/<project>@<n>/`) and its runs, file by file, at
`<hub>/runs/<project>/`. Only set this up when the user provides a hub URL or
asks for one; never invent a hub or send project data to a server the user did
not name.

Configure the project without the token:

```toml
# cairn-report.toml
[hub]
url = "https://<hub-host>"
project = "<project-slug>"
token_file = "~/.config/cairn-report/hub-token"   # or CAIRN_HUB_TOKEN
exclude = [".submitit/**/*.pkl"]   # gitignore-style; Slurm job pickles stay local
```

Never write the token into the repository, configs, scripts, logs, or the
handoff; the config refuses a `token` key. Run remote jobs through the push
wrapper so their runs leave the machine while the job runs and once more when it
ends or is cancelled:

```bash
pixi run cairn-report push runs --watch -- python experiments/run.py experiment=<name>
```

Push only runs from a remote machine (`push runs`): reports are built locally,
and a report push from there would record a version without its pages. Where
the compute nodes themselves can reach the hub, `[logger] backends = ["hub"]`
lets the logger send each run's files while it executes instead; otherwise keep
the watcher.

On a cluster, `pixi run <cluster> submit` and `pixi run <cluster> pack` do this
automatically on the login node whenever `cairn-report.toml` has a `[hub]`, and
`finalize` sends a finalized study. The token must then exist on the cluster as
`CAIRN_HUB_TOKEN` or as the configured chmod-600 `token_file`, put there by the
user. A hub served on a login node at `127.0.0.1` is reachable only from that
node, so pin the target to it (for example
`KUMA_HOST=cdoering@kuma1.hpc.epfl.ch`, or `LYRA_HOST=...` for Lyra).

Locally, build the reports before pushing them (`pixi run report-build`, then
`pixi run cairn-report push`, which sends a new report version when anything
changed, plus new run files); the hub serves built output and never builds.
Pushes are incremental and verified, and the hub keeps every version, so push
freely. When the runs exist only on the hub, reports read them from there
(`run:` references and `run_dir()` download them into `generated/hub-runs/`),
as long as `[logger] backends` includes `"hub"`. `pixi run cairn-report pull`
brings the latest report back into `reports/` (it refuses to overwrite local
changes without `--force`), `pull --runs` the runs, and
`pull --name <project> --into <dir>` restores a project into a folder. In the
handoff, give the hub URLs of the reports and runs (`<hub>/p/<project>/`,
`<hub>/runs/<project>/`) next to the local ones. Comments made on the hub stay
in that browser; the user passes them on with the page's Copy button, like any
other comments.

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
and `finalize` sends the finalized study (see Remote runs and the hub).

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
the report, and hosting it; provide the concrete URL, and say that comments
reach the agent through the page's Copy button and where reviewed findings are
kept (the reports' finding blocks).

## Reproducibility checklist

Environment and runs
- [ ] The project is a Git repository whose scaffold, configs, and `pixi.lock`
      were committed before the first run; a fresh clone runs the documented
      pixi tasks on every listed platform.
- [ ] `.pixi`, `outputs/`, and `generated/` are ignored and excluded from
      formatting and other source tooling.
- [ ] `reports/` holds only report content; the report tooling is the pinned
      `cairn-report` dependency, with no copied or patched tooling in the
      project and style changes only through `cairn-report.toml`;
      `tools/check_reports.py` is copied from the skill's assets and passes.
- [ ] No experiment-tracking service or custom run database is used.
- [ ] `experiments/run.py` and `provenance/source_snapshot.py` are copied
      from the skill's assets as writable files; the logger is imported from
      `cairn_report.logger`, not copied.
- [ ] Every run has `.hydra/` configs, `run.json` (the single completion
      contract), and bounded `provenance/`; only `completed` runs count as
      evidence, and a failed snapshot fails the run.
- [ ] `latest` moves only to completed runs, and to a study only when every
      trial completed; reports record resolved timestamp paths.
- [ ] Run names are concise semantic slugs, and descriptions explain purpose
      and interpretation limits.
- [ ] Evidence is written through `RunLogger`; `metrics.jsonl` and
      `artifacts.jsonl` are append-only and name the code that logged and drew
      each file.
- [ ] `linux-64` is a locked platform, `experiments/cluster.sh` and
      `experiments/finalize_study.py` are copied from the slurm skill's assets,
      each used cluster's profile and launchers from its skill, and every
      cluster study ran through `pixi run <cluster> ...` after the
      GPU-efficiency gate.
- [ ] If the project uses a hub: no token in the repository or handoff, and
      remote jobs run through `cairn-report push runs --watch -- ...` (on a
      cluster, via `pixi run <cluster> submit`/`pack`).

Method and evidence
- [ ] The user confirmed the method specification and consequential
      ambiguities.
- [ ] Faithful baselines and a bounded feasibility study precede tuning or
      large studies; studies use a multirun for separate experiments or a
      declared in-run grid for evaluation conditions, sized to the decision and
      the project's runtime budget.
- [ ] Reusable diagnostics keep one visual grammar per comparison family, and
      any change of chart is justified by a different question.

Reports
- [ ] The overview (`reports/report.md`) has Introduction (the shared target
      every direction builds on), Status (cross-direction state, the next
      decision, and proposed directions), and Research directions (a `reports`
      fence).
- [ ] Each research direction has its own `reports/<slug>/report.md` with a
      current front matter `summary`, shown on its page and in the overview;
      related reports cross-link with checked `report:` links (`report:/` for
      the overview).
- [ ] Each direction report follows the paper-like spine: Abstract,
      Introduction, Background and related work, Methods, results and
      discussion, Conclusion.
- [ ] Methods explains the method like a paper (problem setup, method with
      every term explained, why it works, relation to the baselines,
      implementation, experimental design), with concept figures computed
      from the project's own code, so a reader could reimplement it.
- [ ] Background and related work comes from a literature and prior-art
      search with linked sources, and overlapping prior art is flagged in
      `prior-art` callouts.
- [ ] Every method, baseline, and variant is defined, with its difference
      from the baseline, what is held constant, and the fairness boundary,
      before results use its name.
- [ ] Every metric card and `{{ value }}` is computed from tracked run files;
      the build's typed-number list holds only design constants; metric labels
      state the comparison, direction, population, and aggregation.
- [ ] Experimental figures come from the runs that wrote them (`run:` paths),
      only from completed runs, and each one's provenance is shown in the
      lightbox.
- [ ] A diagram, where one is needed, shows the model as a graph (its
      variables and terms, labelled as in the equations), is explained in the
      text, and is a Graphviz fence; no diagrams of the report or run tooling
      or of linear protocol steps.
- [ ] `!!! finding` blocks carry a valid status and a qualitative title (no
      result numbers), cite source runs and comment ids, and expose conflicts.
- [ ] Callouts mark only consequential synchronization needs and are revised
      when resolved.
- [ ] Each report build has a manifest hashing everything it read, its
      builder, templates, and runtime.

Comments and hosting
- [ ] `cairn-report.toml` sets the `[page] copy_preamble` with the comment
      handling instructions; pasted comments are handled by quote, rebuilt,
      and summarized per comment id.
- [ ] The report server binds to localhost by default and is not exposed
      unauthenticated to an untrusted network.
- [ ] Shared or published reports are the unchanged `generated/reports/`
      output; nothing was restyled or re-authored for the destination.
- [ ] The handoff gives exact build, serve, and host commands, concrete URLs,
      and the locations of run data, comments, and findings.
