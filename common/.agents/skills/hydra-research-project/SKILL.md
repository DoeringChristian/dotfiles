---
name: hydra-research-project
description:
  Initialize, extend, or develop a reproducible research project managed with
  pixi and standard Hydra runs, where every experiment is a Hydra output folder
  (runs/<name>/<date>/, with runs/<name>/latest pointing at the newest one that
  finished), dispatched with one-line pixi commands to the local machine, ssh
  workstations, or Slurm clusters (Kuma, Lyra), and written up in reports. Use
  for research project setup, experiments, baselines, parameter studies,
  diagnostics, remote and cluster runs, and reports, when the project does not
  use Cairn or MLflow.
---

# Research project (Hydra runs)

Build research projects whose evidence is plain run folders. Every experiment
process is one Hydra job, and every job writes into its own folder:

```text
runs/<run name>/<YYYY-MM-DD_HH-MM-SS>/   one Hydra job: .hydra/, its log, git commit, outputs
runs/<run name>/latest -> <date>         the newest run of that name that finished without an error
```

These are standard Hydra runs: Hydra composes the config, creates the folder,
saves the config, and captures the log; the code writes its outputs into the
folder as ordinary files. There is no tracking service, database, or logging
API. Two small Hydra callbacks in `utils/hydra.py` record the git commit and
keep `latest`. Reports show what the folders hold. Projects not using this
layout (Cairn, MLflow) use their own skills.

Apply setup steps when creating or changing project setup; existing projects
need only the steps relevant to the requested work.

## Where the details are

Read the reference a step needs before doing that step.

| Before you                                                                                                                                                                 | Read                                     |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| create a project; change its environment, configs, run layout, what runs write; read another run's output; run a sweep; set up or use dispatch to ssh machines or clusters | [references/runs.md](references/runs.md) |

## Environment and setup

1. **pixi owns the environment.** Prefer `[pypi-dependencies]` for Python
   packages; reserve conda-forge for the interpreter, compilers, CUDA, and
   packages PyPI does not provide reliably. Commit `pixi.lock`.
2. **Hydra owns configuration and building objects.** Configs live in
   `configs/`; configurable components (models, datasets, solvers) carry
   `_target_` and are built with `hydra.utils.instantiate`. Each entry point is
   a plain `@hydra.main` function `main(cfg)` with its own pixi task. There is
   no experiment base class or tracking wrapper.
3. **Git before runs.** Initialize Git and commit the scaffold before the first
   run, and commit again before any run a report will cite. Each run records the
   commit and the uncommitted diff, but a clean tree is what makes a cited run
   reproducible.
4. **Leave the user's machine usable.** Runs on the user's own computer use at
   most half its cores unless the user asks for more: cap worker processes and
   library threads (`OMP_NUM_THREADS`, `torch.set_num_threads`) in config.
   Larger work goes to a workstation or a cluster (see Dispatching work).

## Runs and evidence

5. **Run names describe the run and what it runs on**, in the project's own
   terms: `ours-ai57_008-w64`, `baseline-ai57_008-w128`,
   `eval-ours-ai57_008-w64`, `error-maps-ai57_008-widths`. Someone who knows the
   project recognizes each run from its name alone and tells it from every other
   run.
   - Build the name in config by interpolation from the values it mentions
     (`run.name: ours-${scene.name}-w${model.width}`), so it cannot drift from
     what ran.
   - Every variant and every sweep trial gets its own name, ending in the varied
     values.
   - No counters, dates, or status words in the name (`exp3`, `run-2`, `v2`,
     `final`, `test`): the date folder already tells reruns apart.
   - Before starting, list the existing names (`ls runs/`); if the same thing
     ran before, reuse its name so the run becomes its next date folder.
6. **Split runs by computation.** Expensive runs train, fit, render, simulate,
   or evaluate. Cheap analysis runs each make one figure or table group, read
   the expensive runs they need, and are named after what they show, never after
   their place in a report. When one run does both, split it.
7. **Store what is expensive; recompute only what is cheap.** Every expensive
   run stores its complete output (per-sample and per-point values, arrays,
   tables), not only aggregates or pictures. Store invariant inputs once and
   refer to them by stable sample IDs. A figure, table, or number that cannot be
   redrawn from stored data without rerunning the expensive stage is a defect:
   fix the recording and rerun before citing it.
8. **Record during the run** at a configured cadence, as plain files in the run
   folder (a CSV of scalars or the framework's own logger, images, tables), with
   stable names and the axes in each row (`step`, `split`, `sample_id`). Each
   run can be inspected on its own: images over the steps of the output next to
   its reference and input, the error map on a fixed colour scale, image-valued
   parameters, and the intermediate quantities the claim depends on.
9. **Validation.** A run counts as evidence only when it finished and its
   scientific validation passed: the run checks its tolerances and raises on
   failure, so the job fails, `latest` does not move, and the log holds the
   reason. Smoke tests and debugging proxies are labelled as such, never
   presented as evidence.
10. **Parameter studies come after feasibility.** Use a Hydra multirun when the
    configurations are separate experiments to compare; use an in-run grid (one
    table row per cell) when they are evaluation conditions of one experiment.
    Never hide failed trials or cells; a study summary checks that every
    expected trial finished. Start coarse and size the study to the decision.

## Before starting a run

When the user asks for a run or a sweep, first show what will run as a short
table and wait for their go-ahead; start only after they confirm (they may
change values first). Build it from the composed config
(`pixi run <task> <overrides> --cfg job --resolve`), not from memory, and
describe each part in a few words, in the project's terms. Use the rows the
task has; a training run might show:

| Part        | Setting                                  | Note                       |
| ----------- | ---------------------------------------- | -------------------------- |
| Run         | `ours-ai57_008-w64` on Kuma              | 3 jobs, about 2 h each     |
| Input       | scene `ai57_008`, 64 views, 512×512      |                            |
| Model       | MLP, width 64, 4 layers, hash encoding   | width was 128 last run     |
| Objective   | L1 on RGB + 0.01 TV                      |                            |
| Optimizer   | Adam, lr 1e-3                            |                            |
| Schedule    | cosine to 1e-5, 20k steps, batch 4096    |                            |
| Seeds       | 0, 1, 2                                  | 3 trials                   |
| Validation  | PSNR ≥ 30 dB on held-out views           | the run fails otherwise    |

A renderer, a solver, or an analysis run has other parts (integrator and sample
count, mesh and tolerances, which run folders it reads); leave out parts the
task does not have. In the Note column, mark what differs from the defaults or
from the last run of the same name, and give the sweep's values and trial count.
Below the table, give the exact command that will run.

**ETAs for large experiments.** Anything longer than a few minutes (a long run,
a sweep, a cluster submission) gets a time estimate:

- **Before:** in the table, the expected duration and finish time (clock time,
  `~2 h, done about 16:30`; for a sweep, per trial and in total with how many run
  at once, plus queue wait on a cluster if known). Base it on a measured time per
  step or trial from a smoke run or an earlier run of the same name, and say
  which; if nothing was measured, say it is a guess.
- **While it runs:** whenever you report on it, give progress and an updated
  ETA (`trial 7/24, step 12k/20k, ~1.4 s/step, done about 17:10`), computed from
  the log, not from the original estimate. Say when it is running much slower
  than expected, or stuck in a queue.
- **After:** the actual duration next to the estimate, so later estimates improve.

Runs therefore log their step and elapsed time at `log_every`, so progress can
be read from the log.
Smoke tests and short debugging runs you start yourself need no table, but
say what they are. After starting, give the run folder (or the remote launch
log or job ID) so the user can find it.

## Project layout

Illustrative; add only the entry points and modules the work needs.

```text
project/
├── pixi.toml, pixi.lock, .gitignore      # .gitignore: .pixi/ runs/ data/
├── configs/                              # Hydra configs; hydra/launcher/ from the cluster skills
├── <concept>/                            # project code, flat imports
├── utils/hydra.py                        # from assets/utils/: GitInfo, LatestLink callbacks
├── experiments/
│   ├── train.py, evaluate.py, ...        # standard Hydra functions
│   ├── ssh.sh                            # from assets/dispatch/: ssh machines
│   └── cluster.sh, clusters/<cluster>.sh # from the slurm and cluster skills
├── runs/<name>/<date>/, runs/<name>/latest
└── data/                                 # ignored local data
```

Copy the bundled assets by content and make them owner-writable
(`install -m 0644 <source> <destination>`): `assets/utils/` into `utils/`, the
`run` and `hydra` blocks of `assets/configs/config.yaml` into each entry point's
config, and `assets/run.py` as the pattern for an entry point.

## Starting a project

```text
Project setup:
- [ ] Read references/runs.md
- [ ] pixi.toml: python, hydra-core, numpy, matplotlib, one task per entry point; pixi install
- [ ] utils/hydra.py from assets; PYTHONPATH activation in pixi.toml; configs with the run and hydra blocks
- [ ] .gitignore: .pixi/, runs/, data/
- [ ] git init and commit the scaffold
- [ ] One smoke run: runs/<name>/<date>/ has .hydra/, its log, git_commit.txt and its outputs, and latest points at it
- [ ] One pixi task per machine the user dispatches to (ssh hosts, clusters), smoke-tested once
- [ ] Ask the user where reports live and how agents edit them, and write it in the project's AGENTS.md
```

## Dispatching work

The user must be able to send any run anywhere with one short command, the same
task and Hydra overrides as locally. Give every machine the project uses one
pixi task (setup in [references/runs.md](references/runs.md)):

```bash
pixi run train model.width=64                    # here
pixi run fermat train model.width=64             # an ssh machine: push, start detached
pixi run fermat -g 1 train -m model.width=32,64  # on GPU 1, a sweep
pixi run fermat status                           # also: log, pull, stop <pid>
pixi run kuma smoke model.width=64 steps=10      # a Slurm cluster: tiny foreground check
pixi run kuma submit model.width=32,64,128       # one Slurm job per trial (always a multirun)
pixi run kuma status                             # also: pull
```

Each command pushes the working tree (with `.git`) and runs the same pixi task
there, so runs land in the same `runs/<name>/<date>/` layout on the remote;
`pull` copies them back. Before any Slurm `submit` or `pack`, load the `slurm`
skill and the cluster's skill (`kuma`, `lyra`) and pass their GPU-efficiency
gate. Before starting on a shared workstation, check `status` for GPUs others
are using and pick a free one with `-g`.

## Reports

Reports live wherever the project keeps them (a shared notes app, a document
server, Markdown in the repo); the project's `AGENTS.md` says where and how an
agent edits them. If it does not, ask once and write it there.

- **The user's report is the user's.** Change only what was asked, where it was
  asked; never add sections or restructure on your own. When you cannot tell
  whose a report is, treat it as the user's.
- **Change passages, not whole documents**, on a copy read right before, so
  nothing the user is typing gets lost. If the tool cannot edit a passage or
  merge, give the user the new text instead of overwriting.
- **Agent reports**: one per direction you explore, opening with **Claim** (one
  qualitative sentence), **Setup where it holds** (what it was tested on, and
  what not), **Status** (`proposed`, `running`, `supported`, `contradicted`,
  `inconclusive`, `abandoned`), and **Evidence** (which runs and figures carry
  it). Below that, only the sections the question needs.
- **Numbers come from runs.** Never type a result number: every result is a
  figure, table, or value a finished, validated run wrote, shown from (or copied
  verbatim out of) its dated run folder and named with it. Design constants may
  be typed.
- **Keep each report coherent.** It is not an activity log: integrate changes
  where they belong, remove what is stale, re-read the whole report after
  changing it, and after a rerun re-read the claims that rest on it.

## Handoff

State what changed or was learned, what validation supports it, and what could
still limit the conclusion. Distinguish smoke tests and proxies from evidence.
Give the exact commands to reproduce the runs (including the dispatch command),
the dated run folders the reports cite (`runs/<name>/<date>`, not only
`latest`), and links to the reports you wrote or changed.
