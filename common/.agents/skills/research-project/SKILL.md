---
name: research-project
description:
  Initialize, extend, or develop a reproducible research project managed with
  pixi, Hydra-configured object construction, and Cairn (an artifact store in
  which every experiment is a recorded run and its results are versioned
  artifacts, single-page paper-like reports built from pinned artifacts, and a
  browser UI). Use for research project setup, experiments, method
  development, feasibility studies, baselines, parameter studies, diagnostics,
  cluster runs, and reports.
hooks:
  Stop:
    - hooks:
        - type: command
          command: 'python3 "$HOME/.claude/skills/research-project/scripts/report_gate.py"'
          timeout: 1800
---

# Research Project

Build research projects whose evidence is versioned artifacts. Every experiment
process is a Cairn **run** (`runs/<name>@vN`, recording its config, inputs,
metrics, logs, code, and environment); its results go into **drafts** that
become artifacts (`<name>@vN`) with the run as their input; datasets and models
are artifacts too. One single-page report per research direction reads the
artifacts it declares, presents the evidence as a paper would, and holds the
reviewed findings.

## Core principles

1. **pixi owns the environment.** Prefer `[pypi-dependencies]` for Python
   packages; reserve conda-forge for the interpreter, compilers, CUDA, Graphviz,
   and packages PyPI does not provide reliably. Commit `pixi.lock`.
2. **Hydra owns configuration and object construction; Cairn owns the run.**
   Put configs under `configs/`, construct configurable objects with `_target_`
   and `hydra.utils.instantiate`, and make Hydra's job folder the run's folder
   (`hydra.run.dir: ${cairn.run:}`), so every run is self-contained in one
   artifact version.
3. **The experiment is the executable boundary.** A config-selected
   `Experiment` is the highest-level behavior. The entry point composes config,
   prepares the run folder, instantiates the experiment, and invokes it.
4. **Cairn holds the evidence; reports read only what they declare.** A
   result becomes evidence when a completed run writes it into a draft that
   becomes an artifact version. A report lists its artifacts under `inputs:`,
   the build pins each to an exact version, and any other read fails the build.
   Reports never become an independent source of experimental numbers.
5. **Develop the method with the user.** Resolve consequential ambiguities,
   visualize intermediate behavior, and establish feasibility against relevant
   baselines before tuning or scaling.
6. **Validation tests the claim.** Identify smoke tests and debugging proxies as
   such; do not present them as scientific evidence.
7. **Do not improve results by weakening the problem.** Configure and disclose
   approximations that may change the scientific meaning.
8. **Document the method like a paper.** Every direction report explains its
   method well enough for an expert to reimplement it, with the figures a paper
   would have, in the field's established terms: never invent names for
   concepts no paper has named. Before finishing, you review it against the
   rubric (see "Finishing a turn").

## Where the details are

Read the reference a step needs before doing that step; each is short and
self-contained.

| Before you | Read |
|---|---|
| create a project, change its environment, Hydra configs, run bookkeeping, logging, the repo or its remote; publish or pull artifacts; run on a cluster; plan a parameter study | [references/project-setup.md](references/project-setup.md) |
| create, restructure, build, publish, host, or share reports; handle pasted location markers | [references/reports.md](references/reports.md) |
| write or revise a direction report's Abstract, Background, or Methods | [references/writing-methods.md](references/writing-methods.md), and once per project [references/example-methods.md](references/example-methods.md) |
| write Mitsuba integrators, scenes, or other plugins | [references/mitsuba.md](references/mitsuba.md) |
| hand off work that changed the setup, evidence, or reports | [references/checklist.md](references/checklist.md) |

The rubric you review a direction report against is
[references/review.md](references/review.md).

## Project layout

```text
project/
├── pixi.toml, pixi.lock, .envrc, .gitignore
├── configs/                    # Hydra configs; hydra/launcher/ from each cluster's skill
├── <concept>/                  # project code, flat imports
├── experiments/
│   ├── base.py                 # Experiment interface
│   ├── run.py                  # from assets/run.py: the entry point (run bookkeeping is Cairn's)
│   ├── cluster.sh, finalize_study.py, clusters/<cluster>.sh   # from the slurm and cluster skills
├── data/                       # local datasets before they are published (git-ignored)
├── tools/model_graph.py        # from assets/model_graph.py, for neural-network projects
├── reports/<slug>/             # one single-page report per research direction
│   ├── report.md
│   └── assets/, data/          # non-result material kept with the report
└── .cairn/                     # the repo (`cairn init`): config.toml ([remote] url, [repo] exclude, optional [style]), artifacts, run and draft folders, outbox, built reports (ignores itself; CAIRN_DIR moves it)
```

There is no overview report and no nesting: the Cairn UI's project page and the
build's index list the reports. Copy bundled assets by content and make the
copies owner-writable (`install -m 0644 <source> <destination>`). Cairn (repo
client, runs and drafts, report builder, Hydra helpers, server, UI) is the pinned
`cairn` dependency: import and run it, never copy or patch it. Initialize Git
and commit the scaffold before the first run, and commit again before runs a
report will cite.

## Starting a project

Copy this checklist into your reply and tick it off:

```text
Project setup:
- [ ] Read references/project-setup.md and references/reports.md
- [ ] pixi.toml with the pinned cairn (extras hydra, video) and the tasks; pixi install
- [ ] cairn init; .cairn/config.toml [repo] exclude; cairn remote set <server>/<project> only if the user runs a server
- [ ] Hydra configs (hydra.run.dir ${cairn.run:}, Cairn's callbacks), experiments/run.py, Experiment base
- [ ] Cluster files from the slurm skill and each cluster's skill
- [ ] .gitignore: .pixi/, data/ (Cairn's .cairn/ ignores itself)
- [ ] git init and commit the scaffold
- [ ] Sample: publish assets/sample-run as sample-run, copy assets/reports/direction, pixi run report-build passes
- [ ] Replace the sample report and its input with the project's own
```

## Developing a method

**Establish shared understanding.** Ask focused questions about ambiguities in
purpose, inputs, outputs, operations, state, update rules, objectives,
invariants, assumptions, intended advantages, and failure cases. Restate the
interpretation with equations, pseudocode, diagrams, or simple examples and ask
the user to confirm it. Record confirmed choices in config, code, and the
report's Methods. Reopen the discussion when implementation exposes a
consequential ambiguity.

**Make behavior inspectable.** Create simple examples that expose important
mechanisms. Visualize inputs, intermediate states, transformations, outputs,
loss terms, update directions, small optimization trajectories, baseline
comparisons, ablations, and representative failure cases as appropriate:
enough complementary views for the user to verify the implementation, not
decorative figures. Prefer image grids for related inputs, references,
predictions, residuals, masks, or steps.

Treat every repeated dataset, seed, model, or method comparison as one
visualization family with a declared visual grammar: keep chart type, model
colors, axis orientation, limits and scales, ordering, normalization,
aggregation, and panel layout stable, generated by one plotting function.
Figures from separate runs need cross-run limits and ordering passed explicitly
from a shared config, not derived from each run's own data. Change a
visualization only when the analytical question changes, say why in the report,
and never switch chart types because one representation flatters the preferred
method.

**Stay inside the framework's ecosystem.** Build the method from the
framework's own abstractions and extension points, so it composes with the
framework's tools, baselines, and other people's code, instead of a parallel
structure beside them:

- **Mitsuba / Dr.Jit:** implement a rendering method as a Mitsuba plugin (an
  integrator, BSDF, emitter, sensor, or texture, registered with
  `mi.register_*` and selected in the scene or config). Render with
  `mi.render`, differentiate with Dr.Jit's autodiff and `mi.ad` integrators,
  optimize scene parameters through `mi.traverse` and `mi.ad.Adam`, and write
  array code with `dr.*` operations and symbolic loops, not Python loops over
  samples or NumPy round trips. Integrators have two constructors (Mitsuba
  properties and a direct signature for Hydra) and scenes come from constructor
  functions: see [references/mitsuba.md](references/mitsuba.md).
- **PyTorch:** models and learned components are `nn.Module`s with their
  parameters registered, losses use `torch.nn.functional` or loss modules, data
  comes through `Dataset` and `DataLoader`, and training uses `torch.optim` and
  its schedulers. Do not keep parameters in hand-made lists or write your own
  optimizer step.
- **Any other framework:** find its equivalent (a JAX/Flax module, a
  scikit-learn estimator, a solver library's problem class) before writing one.

Leave the framework only where it cannot express the method, and say so in
Methods. A baseline reimplemented outside the framework is not a faithful
adaptation.

**Build diagnostics with Matplotlib.** Write reusable functions that take
explicit data and return a `Figure`, with units, labels, legends, and colorbars
where needed, method colors and ordering centralized in one module. Add the
figures to the experiment's run or result draft with `add_figure(name, plot_function, metadata, *args)`
and reuse the same functions in the reports.

**Establish baselines and feasibility.** Agree with the user which baselines
test the claimed advantage. Prefer faithful adaptations of authoritative
reference implementations: read the paper, documentation, configuration,
evaluation protocol, and the complete relevant execution path; record the
reference version and material deviations. Begin with a bounded feasibility
study, with agreed checks, metrics, tolerances, and failure cases. Do not start
systematic tuning, large multiruns, or expensive scaling until the user has
seen the evidence and the method has passed this gate.

**Leave the user's machine usable.** Runs on the user's own computer use at
most half its cores unless the user asks for more: cap worker processes and
library threads (`OMP_NUM_THREADS`, `torch.set_num_threads`) in config, and size
a feasibility study to the budget the user gave. Larger work goes to a cluster.

**Perceptual blind spots.** When the user reports an effect that inspection or
metrics miss (temporal instability, localized artifacts, high-frequency
structure), preserve the original outputs, add a visualization that isolates
it, and record a quantitative measure: a standard metric when its assumptions
fit, otherwise one tested on known positive, negative, and confounding cases.
If its relation to perception stays unclear, propose a small calibration with
focused ratings or pairwise comparisons.

## Evidence flow

```text
pixi run publish data/x datasets/x                # datasets and models are artifacts too
pixi run experiment experiment=<name>             # a run: runs/<name>@vN; cairn.use(...) records its inputs
#   inside the experiment: with cairn.draft("<name>") as result: result.add_*(...)  ->  <name>@vN, input: the run
# reports/<slug>/report.md front matter:  inputs: {fit: <name>@latest, run: runs/<name>@latest}
pixi run report-build && pixi run publish reports/<slug>
```

The process is the run: it records code, packages, logs, and system metrics by
itself, and it is completed when the process exits. A non-zero exit or an
uncaught exception marks it failed; an open draft publishes nothing then, and only completed versions resolve through aliases such as
`latest`, so a report never reads a failed run. Details in
[project-setup.md](references/project-setup.md).

## Reports

One **direction report** per branch of the research
(`reports/<slug>/report.md`), each a paper-like report: Abstract, Introduction,
Background and related work, Methods, results and discussion, Conclusion.
[reports.md](references/reports.md) holds their structure, syntax, and
tooling; [writing-methods.md](references/writing-methods.md) holds how to write
a direction's method. The rules that hold everywhere:

- **Numbers come from inputs.** Every result in a report is a `{{ }}` value or
  metric computed from a declared input artifact (`inputs.<name>`), and every
  figure of a result comes from the artifact that holds it (`input:<name>/<file>`).
  Only completed versions count. Never type a result.
- **Keep each report coherent.** A report is for a reader who needs the current
  method, evidence, and decisions quickly, not an activity log: integrate
  changes where they belong, remove what is stale, and re-read the whole report
  after substantive changes.
- **Build after every change:** `pixi run report-build`; publish the report
  (`pixi run publish reports/<slug>`) once its evidence or text changed.
- **Handle pasted location markers.** Reports have no comment feature; the
  user may paste a line such as `reports/a/report.md:42 "quoted text"` or
  `... figure #fig-id "title" (source: file)` copied from the page. Treat each
  as pointing at that file, line, or figure (details in
  [reports.md](references/reports.md)).
- **Share the generated output unchanged.** For claude.ai or any single-file
  host, run `pixi run report-share` and publish the one file it prints as it
  is (with the Artifact tool: that `file_path` and no other files). To browse
  with the user, use the Cairn UI (`pixi run ui`). Never restyle, re-template,
  or re-author a report for a destination; a publishing tool's design guidance
  does not apply to these pages.

Copy this checklist into your reply whenever you change a report:

```text
Report change:
- [ ] Read the reference for this step (writing-methods.md for Abstract, Background, Methods)
- [ ] New evidence written by completed runs into drafts (artifacts) and declared under inputs:
- [ ] Edited reports/<slug>/report.md (and assets/) only; results as {{ }} values from inputs
- [ ] Methods still describes the method as implemented, with the figures a paper would have
- [ ] pixi run report-build succeeds
- [ ] Looked at every figure I added or changed
- [ ] Re-read the whole report: summary, abstract, findings, and conclusion match the evidence
- [ ] Published it: pixi run publish reports/<slug>
```

## Finishing a turn

The skill's Stop hook runs `scripts/report_gate.py` whenever you try to finish.
It does nothing unless a report's sources changed since it last passed. Then:

1. it blocks until the changed reports are rebuilt;
2. once, it sends you back to review each changed direction report yourself
   against [references/review.md](references/review.md): re-read the built
   report and its Methods figures, fix every failed item in the sources, and
   rebuild.

Fix the problem, never pad a section to pass an item. When you finish, tell the
user which items, if any, you left open and why. After three blocks in a row
the gate lets you stop and shows the user what is still open.

## Handoff

The handoff states what changed or was learned, what validation supports it,
and what could still limit the conclusion. Distinguish smoke tests and proxies
from evidence. Give exact commands for reproducing experiments, rebuilding
and publishing the reports, and viewing them, the run and artifact references
(`runs/<name>@vN`, `name@vN`) the reports read, the concrete URLs, and any
review items you left open. Say that the user can paste a page's copy-location
markers to point at a line or figure, and that reviewed findings live in the
reports' finding blocks.
