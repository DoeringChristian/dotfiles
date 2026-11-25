---
name: research-project
description:
  Initialize, extend, or develop a reproducible research project managed with
  pixi, Hydra-configured object construction, and Cairn (an artifact store in
  which every experiment is a recorded run and its results are versioned
  artifacts, reports the user writes and agents answer in, and a browser UI).
  Use for research project setup, experiments, method development, feasibility
  studies, baselines, parameter studies, diagnostics, cluster runs, and reports.
---

# Research Project

Build research projects whose evidence is versioned artifacts. Every experiment
process is a Cairn **run**: an artifact in the `runs` namespace that records its
config, inputs, metrics, logs, code, environment, and results. All artifacts have
permanent IDs. Write results directly to the run by default; create separately
named result artifacts only when they need an identity or lifecycle independent
of that execution. Reuse alone does not require another artifact.
Datasets and models are artifacts too. Reports live in the same repository: the
user writes theirs (the plan, the questions, the requests), agents answer in the
user's agent blocks, and each direction an agent explores gets its own agent
report under the block that asked for it.

Apply setup steps when creating or changing project setup; existing projects
need only the steps relevant to the requested work. These research/report
requirements apply to projects using the skill, not to maintenance of the
skill itself.

## Core principles

1. **pixi owns the environment.** Prefer `[pypi-dependencies]` for Python
   packages; reserve conda-forge for the interpreter, compilers, CUDA,
   and packages PyPI does not provide reliably. Commit `pixi.lock`.
2. **Hydra owns configuration and object construction; Cairn owns the run.**
   Put configs under `configs/`, construct configurable objects with `_target_`
   and `hydra.utils.instantiate`. A native `with cairn.init(...)` block starts one run
   per Hydra job and records provenance before computation. Hydra keeps job
   bookkeeping and optional scratch files in ignored `outputs/`. Recording evidence directly needs no staging directory.
3. **Entry points are standard Hydra functions.** Each executable uses
   `@hydra.main` and a `main(cfg: DictConfig)` function. Its body constructs
   components and runs the method inside `with cairn.init(...) as run:`. Pass
   `cfg.run.name` (it says what ran, `<computation>/<subject>`, so the name
   alone tells this run from the others; see Run names in project-setup.md) and the explicitly
   resolved config to `cairn.init`; use
   `run.use/log/track/add` or `cairn.*` inside the block. Use this native context
   instead of the run decorator. No Experiment base class or custom tracking
   wrapper is needed.
4. **Cairn holds the evidence; reports only embed it.** A result becomes
   evidence when its run completes and scientific validation passes. Reports
   run no code and never become a source of experimental numbers: every result
   in a report is a table, value, or figure a run recorded, embedded with a
   `cairn:` reference. Never type a result number.
5. **Store what is expensive; recompute only what is cheap.** Split the
   pipeline where the cost drops: training, fitting, rendering, simulation,
   and evaluation over the test set are expensive; plotting, tables, summary
   statistics, and report numbers are cheap. Every expensive stage records its
   complete output in its run (per-sample and per-point values, arrays, and
   tables, not only aggregates or pictures), and cheap stages (analysis runs)
   use those records. Store invariant input data once: predictions plus
   stable sample IDs can refer back to input columns without duplicating them. A figure, table, or number that cannot be redrawn or
   recomputed from stored data without rerunning the expensive stage is a
   defect: fix the recording and rerun before citing it. Recording only the
   plotting function and its settings does not satisfy this.
   Log metrics and intermediate outputs as they become available during the run,
   at a configured cadence; do not defer recording until completion. See the logging guidance in [project-setup.md](references/project-setup.md).
6. **Develop the method with the user, stage by stage.** Resolve consequential
   ambiguities and visualize intermediate behavior. First test whether the idea
   works in principle, then explore several approaches side by side, and only
   when the user has chosen one, dig into it and tune it (see "How a project
   progresses").
7. **Validation tests the claim.** Identify smoke tests and debugging proxies as
   such; do not present them as scientific evidence.
8. **Do not improve results by weakening the problem.** Configure and disclose
   approximations that may change the scientific meaning. Test the method
   under study on its own, not inside a hybrid that hands its hard parts to
   another method (see "Test the method itself" below).
9. **The user's report is the user's.** Write into their agent blocks; change
   their text only when asked, and only what was asked. In your own agent
   reports, document a direction's method like a paper: well enough for an
   expert to reimplement it, with the figures a paper would have, in the
   field's established terms (never invent names for concepts no paper has
   named), and review it against the rubric before finishing.

## Where the details are

Read the reference a step needs before doing that step; each is short and
self-contained.

| Before you | Read |
|---|---|
| create a project, change its environment, Hydra configs, run bookkeeping, logging, the repo or its remote; publish or pull artifacts; run on a cluster; plan a parameter study | [references/project-setup.md](references/project-setup.md) |
| read, write, or answer in reports; create agent reports; handle sent comments | [references/reports.md](references/reports.md) |
| write or revise the method of a direction in your agent report | [references/writing-methods.md](references/writing-methods.md), and once per project [references/example-methods.md](references/example-methods.md) |
| write Mitsuba integrators, scenes, or other plugins | [references/mitsuba.md](references/mitsuba.md) |
| hand off work that changed the setup, evidence, or reports | [references/checklist.md](references/checklist.md) |

The rubric you review your agent reports against is
[references/review.md](references/review.md).

## Organizing the work

Choose independently executable stages when work needs separate reruns, reuse,
resources, or validation. Keep tightly coupled internal steps together. Each
computational entry point is a standard Hydra function with a native Cairn run
context; shared implementation belongs in ordinary modules. No pipeline
framework, stage base class, or universal sequence is required.

A run is already an artifact. Store its outputs on the run by default;
downstream stages declare that exact run with `run.use` and read the named files,
values, or records they need. Stage boundaries and multiple consumers do not
require separate result artifacts. Give an output its own artifact identity
only for an independent publication boundary or lifecycle, preserving producer
lineage. Imported datasets may exist independently of any producing run.

A single run and a report can be sufficient when that run records the
tables and figures the report embeds. Another project might branch into
several competing runs, or use `preparation run → experiment runs → analysis run
→ report`. Omit or combine stages when the question permits; a report may embed
any run's recorded files directly. Keep expensive computation in experiment runs
and cheap analysis in analysis runs. Dependencies record provenance, not
automatic scheduling, cache hits, or permission to rerun upstream work.

**Split runs by computation, and name each run after what it ran.** A project
has a few computations, each something someone would rerun on its own. A run's
name is `<computation>/<subject>`: the computation, and what tells this run
from the others of that computation, for example:

- an expensive computation on one subject: `<method>-train/<subject>`,
  `<method>-eval/<subject>`, `dataset-prep/<dataset>`. The subject is the
  dataset or scene, the model variant, or the setting under study, built from
  the config: `cache-train/bedroom-3x128-fp32`,
  `cache-train/bedroom-3x1024-nvfp4`, `cache-eval/bedroom-3x1024-nvfp4`;
- one analysis run per figure or table, or per small group drawn from the same
  data, named after what it shows and covers (`error-maps/bedroom-main`,
  `convergence/width-sweep`). It declares the runs it reads with `run.use` and
  is cheap, so changing the figure means rerunning only it.

Someone who sees only the list of run names can tell which run is which. Runs
that will be compared, or asked for separately, have different names: every
variant and every trial of a sweep has its own. Twenty variants under one name
(`train@v1` … `@v20`) are as wrong as twenty runs called `exp1` … `exp20`,
`run-3`, `fig-7` or `test-final-2`. A version is a rerun of the same thing:
after a fix, a failure or an interruption. A figure run is named after its
content, never its position in a report. When
one run does both an expensive computation and the figures from it, split it in
two. Before starting a run, list the project's run names
(`cairn artifact list --namespace runs`); if the same thing ran before, reuse
its name. Names follow
Run names in [project-setup.md](references/project-setup.md).

Document each entry point's inputs, outputs, and command. Pin stage inputs for
reviewed evidence; after deliberately rerunning a stage, select the new version
explicitly for downstream runs. Avoid dependencies on another
script's temporary output directory. Storage/access choices and examples are in
[project-setup.md](references/project-setup.md).

## Project layout

This is an illustrative layout. Add only the entry points and modules the work
needs; filenames and stage count follow the problem.

```text
project/
├── pixi.toml, pixi.lock, .envrc, .gitignore
├── configs/                    # Hydra configs; hydra/launcher/ from each cluster's skill
├── <concept>/                  # project code, flat imports
├── experiments/
│   ├── run.py                  # standard Hydra function; add train.py, evaluate.py, etc. as needed
│   ├── research_cairn.py       # evidence checks and study summaries
│   └── cluster.sh, clusters/<cluster>.sh # scheduler files; check their Cairn compatibility
├── outputs/                    # ignored Hydra job folders; bookkeeping and optional scratch, not the evidence record
├── data/                       # ignored local data; linked archives may live elsewhere
└── .cairn/                     # ignored local repo and journals; remote backend is separate
```

Reports are not project files: they live in the Cairn repository with the runs.
Copy bundled assets by content and make the copies owner-writable (`install -m
0644 <source> <destination>`). Cairn (repo client, runs, artifacts, reports,
server, UI) is the pinned
[`cairn2` v0.16.0](https://github.com/DoeringChristian/cairn2/releases/tag/v0.16.0), imported as `cairn`: import and run it, never copy or
patch it. Use Cairn's native run context and provenance capture. Initialize Git
and commit the scaffold before the first run, and commit again before runs a
report will cite.

## Starting a project

For new projects, use this checklist; mark conditional items not applicable:

```text
Project setup:
- [ ] Read references/project-setup.md and references/reports.md
- [ ] pixi.toml pins cairn2 v0.16.0 (media, ui), Hydra separately, and the tasks; pixi install
- [ ] One repo: a local path (created on first access) OR the user's named server URL; explicit project namespace and protected login credentials
- [ ] Hydra configs, experiments/run.py, research_cairn.py; standard Hydra functions using with cairn.init(...)
- [ ] If using a cluster: scheduler files from the relevant skills; verify tracking glue against the new API before submission
- [ ] .gitignore: .pixi/, .cairn/, outputs/, data/, artifacts/
- [ ] git init and commit the scaffold
- [ ] Sample: import assets/sample-run as datasets/sample-run@v1 in the selected project; a scratch report embedding its figure renders in pixi run ui; delete the scratch report
- [ ] The comment watcher runs (references/reports.md)
```

## Exploring and exploiting

The user works in one of two modes, and the request says which; ask when it does
not.

- **Exploring.** The user asks an open question in an agent block ("why does
  it ring at the boundary?", "what else could represent the field?"). Find the
  candidate directions, create one agent report per direction under that block
  (each with the Claim / Setup where it holds / Status / Evidence header from
  [reports.md](references/reports.md)), run the small experiments that test each
  claim, and answer in the block with a short overview linking them. Breadth
  matters more than polish: several directions at comparable effort, each
  honest about where it holds. The user reads the cards, comments to steer, and
  takes over the directions worth keeping.
- **Exploiting.** The user has decided and writes what to do: the method, the
  setup, the experiments, often in their own words in their report. Implement
  exactly that. Speak up only for a clear mistake, a point that is genuinely
  unclear, or a component that is clearly better for what they want; say it in
  a reply with the reason, and implement the change only after they agree. Do
  not substitute your own design, add directions they did not ask for, or
  rewrite their text.

## How a project progresses

A project starts from an idea the user provides and usually moves through
three stages; the first two are mostly exploring, the third exploiting. Know
which one the work is in, state it in the handoff, and let the user decide when
to move on.

1. **Does the idea work in principle?** Implement a direct, naive prototype of
   the idea and run it next to the baseline on a small, inspectable problem.
   The question is whether and how it works, not whether it wins: a first
   prototype that is worse than a tuned baseline is the normal outcome, not a
   failure to fix. Report plainly what works, what does not, and where it
   breaks, with the figures that show the mechanism. Do not tune, add tricks,
   or build hybrids to close the gap at this stage.
2. **Explore the space of approaches.** Build several variations of the idea
   and the alternatives agreed with the user (other representations,
   architectures, or solvers for the same problem), each at modest and
   comparable effort, compared on the same setup. Record their trade-offs, not only a
   ranking: speed, memory, data needs, quality, and the scenarios where each
   one is better. Keep a short list of the approaches in play and why each is
   there. Do not spend the effort only on whichever variant currently scores
   best: an approach that is behind now may be the more interesting one, or
   win in a setting not yet tested, and refining only the leader is how the
   work gets stuck in a local minimum.
3. **Dig into one approach.** Only after the user has fixed on one, find out
   why it falls short of the baseline and whether that is fundamental (a
   limit of the formulation) or fixable (implementation, capacity, tuning,
   data). If fixable, improve it until it outperforms the baseline or until
   you find an application where the baseline struggles, within what the
   user specified; if fundamental, say so and why.

**Climb the scale ladder.** Answer each question at the smallest setup that
can answer it, then move up only to check that the answer holds. Typical rungs:
a 1D or flatland (2D) version, then a small 3D or low-resolution instance with
few samples and a short schedule, then the target scale. A proof of concept
should take minutes on a laptop, not hours on a cluster; stages 1 and 2 live on
the lower rungs. Before a run that takes much longer than the runs before it,
state what question it answers that no smaller setup can, and launch it only
after the small version works and a short smoke run of the large configuration
(a few steps) has passed. Check that each reduction keeps the property being
tested: a flatland version that removes the hard part of the problem shows
nothing about it.

Small-scale success is not the claim. Some effects appear only at scale
(capacity, memory, conditioning, sample counts, long-range structure,
optimization instability), so a result that matters is backed by experiments
at the scale it is claimed for. Push deliberately into the regime where the
method might break: measure how quality, cost, and failure modes change along
the ladder (a short scale sweep), and report where it stops working rather
than stopping at the size where it still does.

**Results hold for a setup.** Methods are usually specific to a setup: the
data source, scene or material class, scale, noise, budget, or the quantity
being reconstructed. A method that wins in one setup and loses in another is a
finding, not a failure, as long as the report states the setup precisely and
where each method is better and why. Report results per setup rather than
averaging setups into one ranking, and do not generalize a result beyond the
setups it was measured on. When the evidence suggests the method fits a
different or narrower application than the one being tested, that is a shift
to suggest to the user (below), with the evidence.

**The user sets the objective; you may suggest shifts.** The problem
statement, the objective, and the set of approaches belong to the user. When
they ask you to explore, the directions you test answer their question and are
theirs to keep or drop; otherwise never change these on your own: do not
reformulate the problem, swap the objective or loss, relax what must be
reproduced, or start a new approach because it looks more promising. That silently moves the work away from what the user is
investigating. You may suggest such a shift, especially when the explored
approaches share a limitation: state it in the handoff with the reasoning and
the evidence behind it, and implement it only after the user agrees.

**Notice when you are stuck.** When several iterations on one approach give
only small gains, stop and report: show where the time went, what limits the
approach, and which alternatives or reformulations you would suggest, instead
of continuing to tune.

## Developing a method

**Establish shared understanding.** Ask focused questions about ambiguities in
purpose, inputs, outputs, operations, state, update rules, objectives,
invariants, assumptions, intended advantages, and failure cases. Restate the
interpretation with equations, pseudocode, diagrams, or simple examples and ask
the user to confirm it. Record confirmed choices in config, code, and the
Methods of your agent report for the direction. Reopen the discussion when implementation exposes a
consequential ambiguity.

**Make behavior inspectable.** Create simple examples that expose important
mechanisms. Visualize inputs, intermediate states, transformations, outputs,
loss terms, update directions, small optimization trajectories, baseline
comparisons, ablations, and representative failure cases as appropriate:
enough complementary views for the user to verify the implementation, not
decorative figures. Prefer image grids for related inputs, references,
predictions, residuals, masks, or steps. Log these as images over the step on
the run itself, not only in reports (see Log results during the run in
project-setup.md).

**Show the mechanism, not only its outcome.** For each part of the method whose
behavior the claim depends on, ask what a reader would need to see to
understand how it works and to check it, and draw what the code actually does,
including where it departs from the equations. Use a setting small enough
that every relevant value is visible (a 2D or 1D version, a tiny grid, a few
iterations), labelled with the equations' symbols. What to draw depends on the
method: what one operation does to its input, how a quantity changes along a
slice or over iterations, or, for a method that works step by step, one
instance followed through its steps. Take the values from the project's own
code, adding a recording hook if internal state is needed, not from a separate
reimplementation. Final outputs and aggregates show that something happened,
not how.

**Figures the user asks for are requirements.** Make each one as asked, even
when a paper would leave it out, and don't swap in an easier figure (a final
render, a loss curve, a box diagram). Put it in the report where its mechanism
is explained, and if one can't be made, tell the user why in the handoff.

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

**Build diagnostics with Matplotlib, from stored data.** Write reusable
functions that take explicit data and return a `Figure`, with units, labels,
legends, and colorbars where needed, method colors and ordering centralized in
one module. A plotting function computes nothing expensive: its inputs are the
recorded output of an expensive stage. Track that data in full in the run
first (`cairn.track(cairn.Table(rows), key=...)`, or arrays), then the figure
under the same key with `cairn.track(cairn.Figure(figure), key=...)`. A
report's figures and tables come from an analysis run that reads that stored
data with the same functions and adds them under names the report embeds
(`cairn.add(cairn.Figure(figure), name=...)`), so any value can be checked or
replotted by rerunning only the analysis. Reject unsupported data instead of
silently dropping it. Referencing stored inputs need not duplicate their bytes.
Save files only when needed by a library or useful as a reusable added file.

**Establish baselines and feasibility.** Agree with the user which baselines
test the claimed advantage. Prefer faithful adaptations of authoritative
reference implementations: read the paper, documentation, configuration,
evaluation protocol, and the complete relevant execution path; record the
reference version and material deviations. The faithful configuration is the
default. A published baseline is sometimes tuned for its own task in ways that
do not transfer, or that make its mechanism hard to see (an intermediate state
that is never visible, an effect averaged away). Only when that matters for the
question, add a plain configuration with those choices removed, label it, and
use it to understand and visualize the mechanism; keep the faithful one for
performance claims. Begin with a bounded feasibility study,
with agreed checks, metrics, tolerances, and failure cases. Do not start
systematic tuning, large multiruns, or expensive scaling until the user has
seen the evidence and chosen the approach to pursue.

**Test the method itself, not a hybrid.** When the question is whether a
method works, the experiment uses that method everywhere it would be used, and
the baseline everywhere the baseline would be used, so each is measured on the
whole problem. Do not combine it with the baseline, a classical method, or a
known-good component to cover the parts where it struggles: splitting the work
by stage, recursion depth, iteration, region, sample, frequency band, or
condition; falling back when its confidence is low or its output looks wrong;
initializing or correcting it with the reference; or restricting it to the easy
cases. Such a hybrid hides exactly the behaviour the study exists to measure,
and its results say little about either method. If the pure method fails,
where and how it fails is the result: record and show it. A hybrid is a
separate direction, started only when the user asks for one after seeing the
pure method's results, and always reported next to the pure method and the
baseline. If a component cannot be avoided (for example a piece the method
does not define), keep it identical across all compared methods and state it
in Methods.

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
pixi run experiment --config-name <name>             # one run; cairn.use(...) records exact inputs
# Inside: record directly with cairn.log/track/add; validate before returning.
pixi run evidence runs/<name>@vN                 # lifecycle check; scientific validation is separate
pixi run experiment --config-name <figure>           # analysis run: reads runs, adds tables and figures
# In the report: ![Error per setup](cairn:runs/<figure>@latest#figures/error)
```

The native Cairn context records initial provenance and manages the run:
normal exit completes it; an exception leaving the block fails it.
Failed runs remain inspectable, and `latest` can point at failed artifacts.
Cairn finishes the run without automatically creating another result
artifact. The completion check does not assess scientific validity: record the
checks, tolerances, and outcomes in the run, and raise on validation failure.
Verify completed runs before embedding their results as evidence. Details in
[project-setup.md](references/project-setup.md).

## Reports

Reports are documents in the Cairn repository; agents read and write them as
Markdown with `cairn report`. [reports.md](references/reports.md) holds how they
work, their syntax, and the comment workflow; read it before touching one. The
rules that hold everywhere:

- **The user's report is the user's.** Write into its agent blocks. Change its
  text only when asked, and only what was asked; never add sections (Abstract,
  Background, related work) or restructure it on your own.
- **Your agent reports are yours.** One per explored direction, under the block
  that asked for it, opening with the Claim / Setup where it holds / Status /
  Evidence header. Below it, the structure the question needs: a research
  direction follows the paper-like spine in
  [writing-methods.md](references/writing-methods.md); an inspection or
  comparison uses only the sections its question needs. Write the claim, setup,
  and method before the evidence, and fill the evidence in as runs complete.
- **Numbers come from runs.** Never type a result number: every result is an
  embedded table, value, or figure that a completed, validated run recorded.
  Prose describes what it shows qualitatively. Design constants may be typed.
- **Keep each report coherent.** A report is for a reader who needs the current
  state quickly, not an activity log: integrate changes where they belong,
  remove what is stale, and re-read the whole report after substantive changes.
  After a rerun, re-read the claims that rest on it.
- **Always watch comments.** In every session in a project with reports, keep
  one `cairn comments watch 'reports/**' --json --once` running in the
  background in a way that wakes you when it exits (in Claude Code, Bash with
  `run_in_background`), and start it again after handling each batch. Requests
  in agent blocks arrive this way too. Act only on sent messages; reply, and
  resolve once done.

Copy this checklist into your reply whenever you change a report:

```text
Report change:
- [ ] Checked the owner: only agent blocks in the user's report unless asked; only what was asked
- [ ] Wrote each part with --revision of the version I read
- [ ] Results recorded by completed, validated runs; analysis runs added the tables and figures embedded
- [ ] No typed result numbers; prose describes the embedded results
- [ ] Agent report: header (Claim / Setup where it holds / Status / Evidence) matches the evidence
- [ ] Every figure the user asked for is there as asked; key mechanisms shown, not only outcomes
- [ ] Looked at every figure I added or changed, in the report
- [ ] Re-read the whole report I changed
- [ ] Replied in the thread that asked for it
```

## Finishing a turn

Before finishing a turn in which you changed an agent report, review it once
against [references/review.md](references/review.md), scoped to its question:
open it in the UI as its reader would (the embeds matter, so Markdown alone is
not enough), decide each item, fix what fails, and write it again. Fix the problem, never pad a section to pass an item. Tell the user
which items, if any, you left open and why. The user's own reports are not
reviewed against the rubric; answer what they asked.

## Handoff

The handoff states what changed or was learned, what validation supports it,
and what could still limit the conclusion. Distinguish smoke tests and proxies
from evidence. Give exact commands for reproducing experiments, the run and
artifact references (`runs/<name>@vN`, `artifacts/<name>@vN`, or full artifact
IDs, with the project) the reports embed, the URLs of the reports you wrote or
answered in (`<ui>/p/<project>/r/<name>`), and any review items you left open.
