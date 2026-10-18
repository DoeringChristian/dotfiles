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
process is a Cairn **run** (identified by its full run ID, recording its config,
inputs, metrics, logs, code, and environment); its results become **artifact
versions** (`artifacts/<name>@vN` in the selected project) with that run recorded
as their producer. Runs themselves are artifacts with permanent IDs.
Datasets and models are artifacts too. One single-page report per research
direction reads the evidence it declares, presents it as a paper would, and
holds the reviewed findings.

## Core principles

1. **pixi owns the environment.** Prefer `[pypi-dependencies]` for Python
   packages; reserve conda-forge for the interpreter, compilers, CUDA, Graphviz,
   and packages PyPI does not provide reliably. Commit `pixi.lock`.
2. **Hydra owns configuration and object construction; Cairn owns the run.**
   Put configs under `configs/`, construct configurable objects with `_target_`
   and `hydra.utils.instantiate`. The bundled entry point starts one Cairn run
   per Hydra job, records its provenance before computation, and gives the
   experiment an ordinary ignored `outputs/` folder for staging results.
3. **The experiment is the executable boundary.** A config-selected
   `Experiment` is the highest-level behavior. The entry point composes config,
   prepares the run folder, instantiates the experiment, and invokes it.
4. **Cairn holds the evidence; reports read only what they declare.** A
   result becomes evidence when a completed, validated run produces an artifact
   version. Verify its producer before pinning it in a report's `cairn.inputs:`.
   Builds capture the declared inputs; reading undeclared experimental results
   is forbidden by this workflow, although the engine does not block external
   reads. Reports never become an independent source of experimental numbers.
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
│   ├── run.py, research_cairn.py # from assets/: public-API lifecycle, provenance and evidence checks
│   ├── report_tasks.py         # flat report discovery, public build/publish/export API
│   └── cluster.sh, clusters/<cluster>.sh # scheduler files; check their Cairn compatibility
├── outputs/                    # ignored Hydra job folders; staging, not the evidence record
├── data/                       # local datasets before they are published (git-ignored)
├── tools/model_graph.py        # from assets/model_graph.py, for neural-network projects
├── reports/<slug>/             # one single-page report per research direction
│   ├── report.md
│   └── assets/, data/          # non-result material kept with the report
└── .cairn/                     # ignored local repo/journals and report builds; remote backend is separate
```

There is no overview report and no nesting: the Cairn UI's project page lists
the reports. Copy bundled assets by content and make the
copies owner-writable (`install -m 0644 <source> <destination>`). Cairn (repo
client, runs, artifacts, report builder, server, UI) is the pinned
[`cairn2` v0.1.0](https://github.com/DoeringChristian/cairn2/releases/tag/v0.1.0), imported as `cairn`: import and run it, never copy or
patch it. The skill's small Hydra adapter calls its public API. Initialize Git
and commit the scaffold before the first run, and commit again before runs a
report will cite.

## Starting a project

Copy this checklist into your reply and tick it off:

```text
Project setup:
- [ ] Read references/project-setup.md and references/reports.md
- [ ] pixi.toml pins cairn2 v0.1.0 (reports, media, ui), Hydra separately, and the tasks; pixi install
- [ ] One local repo (created on first access) OR the user's named server; explicit project namespace and protected login credentials
- [ ] Hydra configs, experiments/run.py, research_cairn.py, report_tasks.py; Experiment.run(run, output_dir)
- [ ] Cluster scheduler files from the relevant skills; verify tracking glue against the new API before submission
- [ ] .gitignore: .pixi/, .cairn/, outputs/, data/, artifacts/
- [ ] git init and commit the scaffold
- [ ] Sample: import assets/sample-run as datasets/sample-run@v1 in the selected project, copy assets/reports/direction, pixi run report-build passes
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
figures to the experiment's run with `run.track(cairn.Figure(figure), key=...)`
and to its result artifact as saved files, and reuse the same functions in the reports.

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
# Import datasets with Client.start("datasets", name).finish(value=Directory(...)).
pixi run experiment experiment=<name>             # one run; run.use(...) records exact inputs
# Inside: validate and stage output_dir/result; the adapter captures it and publishes after completion.
pixi run evidence artifacts/<result>@vN           # require a completed producer
# report.md frontmatter: cairn: {inputs: {fit: "artifacts/<result>@vN", run: "runs/<name>@vN"}}
pixi run report-build
pixi run report-publish <slug>
```

The entry point records required initial provenance and encloses the experiment
in a run context: a normal return completes the run; an exception fails it.
Failed runs remain inspectable, and `latest` can point at failed artifacts.
The adapter publishes result artifacts only after the producing run completes. Verify completed producers and pin exact versions before using
results as evidence. Details in
[project-setup.md](references/project-setup.md).

## Reports

One **direction report** per branch of the research
(`reports/<slug>/report.md`), each a paper-like report: Abstract, Introduction,
Background and related work, Methods, results and discussion, Conclusion.
[reports.md](references/reports.md) holds their structure, syntax, and
tooling; [writing-methods.md](references/writing-methods.md) holds how to write
a direction's method. The rules that hold everywhere:

- **Numbers come from inputs.** Every result in a report is generated by an
  executable Python cell from a declared input (`inputs["name"]`), and every
  figure of a result comes from its declared run or artifact snapshot.
  Only results from completed, validated producers count. Never type a result.
- **Keep each report coherent.** A report is for a reader who needs the current
  method, evidence, and decisions quickly, not an activity log: integrate
  changes where they belong, remove what is stale, and re-read the whole report
  after substantive changes.
- **Build after every change:** `pixi run report-build`; publish the report
  (`pixi run report-publish <slug>`) once its evidence or text changed.
- **Handle pasted location markers.** Alongside native report comments, the
  user may paste a line such as `reports/a/report.md:42 "quoted text"` or
  `... figure #fig-id "title" (source: file)` copied from the page. Treat each
  as pointing at that file, line, or figure (details in
  [reports.md](references/reports.md)).
- **Share the generated output unchanged.** `pixi run report-share <slug> --out
  .cairn/share/<slug>` exports the complete published bundle. Share that bundle
  on a static host or use the Cairn UI (`pixi run ui` locally, or the selected
  remote server's UI). Cairn2 v0.1.0 does not offer a standalone single-file
  export: do not re-author the page to fit a single-file destination. Never
  restyle or re-template reports for a destination; publishing-tool design
  guidance does not apply to these pages.

Copy this checklist into your reply whenever you change a report:

```text
Report change:
- [ ] Read the reference for this step (writing-methods.md for Abstract, Background, Methods)
- [ ] New evidence logged as artifacts, completed producers verified, exact refs declared under cairn.inputs:
- [ ] Edited reports/<slug>/report.md (and its sources) only; result prose and figures computed from declared inputs
- [ ] Methods still describes the method as implemented, with the figures a paper would have
- [ ] pixi run report-build succeeds
- [ ] Looked at every figure I added or changed
- [ ] Re-read the whole report: description, abstract, findings, and conclusion match the evidence
- [ ] Published it: pixi run report-publish <slug>
```

## Finishing a turn

On hosts that support its Stop hook, the skill runs `scripts/report_gate.py`
whenever you try to finish. On other hosts, run the build check and perform the
same self-review explicitly before finishing; the requirement is unchanged.
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
(`runs/<name>@vN`, `artifacts/<name>@vN`, or full artifact IDs, with the project) the reports
read, the concrete URLs, and any review items you left open. Say that the user
can paste a page's copy-location
markers to point at a line or figure, and that reviewed findings live in the
reports' finding blocks.
