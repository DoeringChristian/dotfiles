---
name: research-project
description:
  Initialize, extend, or develop a reproducible research project managed with
  pixi (dependencies mainly from PyPI), with a flat layout, hydra-managed
  configs, a registry/build ("type" key) pattern for constructing objects from
  config, a single top-level task object (Method/Trainer) with hierarchical
  log(name, run, it, **__) on every component, experiments tracked with
  cairn-track, and on-demand cairn-plot reports. Use when starting a new
  research project, setting up pixi/pixi.toml, adding a new method, model, or
  component, adding experiment, tracking, logging, or report scaffolding, or
  when the user mentions cairn-track, cairn-plot, experiment tracking,
  "reproducible report", hydra configs, the registry/build pattern, or pixi
  project setup.
---

# Research Project

Set up a research project so that every result — numbers, figures, and tracked
runs — can be traced to its exact config and regenerated from scratch with a
single command.

## Core principles

1. **pixi manages all dependencies.** Dependencies come mainly from PyPI
   (`[pypi-dependencies]`); use conda-forge (`[dependencies]`) only for things
   PyPI can't provide well (e.g. `python` itself, compilers, CUDA). Always
   commit `pixi.lock` — it is what makes the environment reproducible.
2. **Everything is reproducible, and every run is tracked.** Experiments are
   tracked with cairn-track: each run logs its composed hydra config, seed,
   metrics, figures, and images to the cairn repo, so any result can be traced
   to the exact config that produced it and regenerated from scratch.
3. **Flat layout.** No `src/<pkg>/` nesting: each kind of thing gets its own
   top-level directory, named for what this project actually contains (e.g.
   `methods/`, `datasets/`, `scenes/` — whatever concepts the project has).
4. **Hydra manages configs.** All run configuration lives in `configs/` and is
   composed by hydra; each run's composed config (and seed) is saved with its
   outputs so any run can be reproduced exactly.
5. **Objects are built from config via a global registry.** Constructors are
   registered with `@register` and instantiated from a config's `"type"` key
   with `build(Base, cfg)` — including nested sub-objects. See
   [registry.py](registry.py) and the sections below.
6. **Graphics use plotly or cairn-plot; images always use cairn-plot**
   (cairn-plot is installed with cairn-track). During training, log scalars,
   images, and matplotlib/plotly figures with `run.track(...)`; for standalone
   reports, cairn-plot generates self-contained offline HTML and wraps plotly
   figures (`cp.Figure`), images (`cp.Image`), tables, line/scatter/heatmap
   plots, point clouds, and meshes. For images, always use `cp.Image` (and
   `cp.Compare` for comparisons) rather than a plotly image trace: cairn-plot's
   image viewer is far more advanced — arbitrary client-side comparisons
   (side-by-side / wipe / blend, pixel-diff kernels incl. FLIP and SSIM,
   synced viewports), true-float HDR images with tone-mapping (EXR/HDR/PFM
   decoded in the browser), and HDR-FLIP.
7. **One top-level task object, and hierarchical `log()` on every component.**
   Whatever the project actually does (training, direct fitting, rendering,
   evaluation) is owned by a single top-level object (`Method`, `Trainer`,
   `Fitter`, …) selected from the config — the entry point never branches on
   *what kind* of task is running. Every component with loggable state
   implements `log(self, name, run, it, **__)` and forwards to its fields as
   `log(f"{name}.<field>", run, it)`, so logging is never assembled from the
   outside. See [Top-level task object and hierarchical logging](#top-level-task-object-and-hierarchical-logging).

## Project layout

The layout is **flat**: no `src/<pkg>/` package nesting. Each kind of thing gets
a top-level directory named after what it holds:

```
project/
├── pixi.toml          # workspace, tasks, dependencies
├── pixi.lock          # committed — reproducibility
├── .envrc             # direnv: auto-activate the pixi env
├── .gitignore         # ignore .pixi/, .cairn/, outputs/
├── .cairn/            # cairn-track repo — all results live here (git-ignored)
├── configs/           # hydra configs (config.yaml + config groups)
├── util/              # registry.py + shared helpers
├── <concept>/         # one flat dir per project concept: base class + one
├── <concept>/         #   subclass per variant — named for THIS project
├── experiments/       # entry points; every run tracks into cairn
└── reports/           # on-demand cairn-plot reports, one sub-folder each
```

Only `configs/`, `util/`, `experiments/`, and `reports/` are fixed. The
`<concept>` directories are project-specific: create one per concept the
project actually has, named for it — an ML project might have `methods/` and
`datasets/`, a rendering project `integrators/` and `scenes/`. Never copy
example names from this skill into a project they don't fit, and never nest a
package hierarchy.

## pixi setup

In a fresh project, initialize git **first**, then pixi:

```bash
git init
pixi init --format pixi    # only if no pixi.toml exists yet
```

Then configure:

```toml
[workspace]
channels = ["conda-forge"]
name = "<project>"
platforms = ["linux-64"]

[dependencies]
python = "3.12.*"        # pin the interpreter via conda-forge

[pypi-dependencies]
numpy = "*"
plotly = "*"
hydra-core = "*"         # config management (brings omegaconf)
# neither is on PyPI — install both from git; [media] → matplotlib/plotly handlers
cairn-plot = { git = "https://github.com/doeringchristian/cairn-plot" }
cairn-track = { git = "https://github.com/doeringchristian/cairn", extras = ["media"] }

[tasks]
ui = "cairn ui"          # browse tracked runs at http://localhost:4301/
```

- Add PyPI packages with `pixi add --pypi <pkg>`; conda packages with
  `pixi add <pkg>`; git packages with
  `pixi add --pypi "<pkg>[extras] @ git+https://github.com/<owner>/<repo>"`.
- Encode every runnable step as a pixi task (`experiment`, `ui`, per-report
  tasks, `all`), and chain them with `depends-on` so `pixi run all` reproduces
  everything:

```toml
[tasks]
experiment = "python experiments/run.py"
ui = "cairn ui"
all = { depends-on = ["experiment"] }
```

## direnv (.envrc)

Add a `.envrc` so entering the project directory activates the pixi environment
automatically:

```sh
watch_file pixi.lock
eval "$(pixi shell-hook)"
```

Then run `direnv allow`.

## Configs (hydra)

All configuration lives in `configs/`, composed by hydra. Entry points are
decorated with `@hydra.main`; hydra saves the fully composed config of every run
under its output dir (`.hydra/config.yaml`), which — together with fixed seeds
in the config — makes each run reproducible.

```python
import cairn
import hydra
from omegaconf import DictConfig, OmegaConf

from methods import Method
from util.registry import build

# config_path is relative to this file — entry points live in experiments/
@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    run = cairn.Run(project="<project>", name=cfg.name)
    run["config"] = OmegaConf.to_container(cfg, resolve=True)
    build(Method, cfg.method).run(run)   # the top-level task object does the rest

if __name__ == "__main__":
    main()
```

Use config groups (`configs/method/distill.yaml`, `configs/dataset/…`) so
variants are selected on the CLI (`python experiments/train.py method=distill`)
and swept (`-m method=a,b`). Put the seed in the config, not in code.

## Building objects from config (registry + `type` key)

Copy [registry.py](registry.py) into `util/registry.py`. It provides a global
registry: decorate a class with `@register`, then construct it from any config
dict whose `"type"` key names the class — remaining keys become constructor
kwargs (explicit kwargs to `build` override the config). `build(Base, cfg)`
type-checks the result and passes an existing instance through unchanged, so
nested objects are configured the same way at every level:

```yaml
# configs/config.yaml
method:
  type: Distillation
  lr: 0.01
  model:
    type: ResNet # nested object, same mechanism
    depth: 18
```

```python
from util.registry import register, build

@register
class Distillation(Method):
    def __init__(self, model: dict | Model, lr: float = 1e-3):
        self.model = build(Model, model)   # builds nested sub-config
        self.lr = lr
```

## Class organization (inheritance over flags)

Avoid parameters that switch behavior via `if`/`else` or `match` — each variant
becomes its own subclass, selected by `"type"` in the config:

```python
# ❌ one class, behavior flags, if-else in every method
class Method:
    def __init__(self, mode: str = "supervised", use_ema: bool = False): ...

# ✅ one base class per top-level concept, one subclass per variant
class Method:                      # top-level abstraction (training strategy)
    def run(self) -> None: ...

@register
class Supervised(Method): ...

@register
class Distillation(Method): ...
```

Apply this structure at the very top of the project: define a base class per
top-level concept the project actually has (e.g. `Method`, `Dataset`,
`Integrator`) in its own flat directory, one registered subclass per variant,
and let the config's `type` key pick the variant. New behavior = new subclass
+ one config line, no new flags.

## Top-level task object and hierarchical logging

### One object owns the task

There must always be a **top-most object that performs the actual task** —
training, direct fitting, rendering, evaluation, whatever the project does — and
it is selected from the config like any other object. The entry point only
builds it and calls it:

```python
@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    run = cairn.Run(project="<project>", name=cfg.name)
    run["config"] = OmegaConf.to_container(cfg, resolve=True)
    build(Method, cfg.method).run(run)     # the task object does everything
```

The task object owns the loop (or the absence of one), the model, the data, the
optimizer, and the logging. When a second kind of task appears — say the project
starts with an optimizer-driven `Training` method and later adds a closed-form
`DirectFit` — it becomes **another registered subclass of the same base**, and
the config picks it:

```python
class Method:
    def run(self, run: cairn.Run) -> None: ...
    def log(self, name: str, run: cairn.Run, it: int, **__) -> None: ...

@register
class Training(Method):            # iterates: step, log every N iterations
    def run(self, run):
        for it in range(self.iterations):
            self.step()
            if it % self.log_every == 0:
                self.log("train", run, it)

@register
class DirectFit(Method):           # no loop: solve, log once
    def run(self, run):
        self.solve()
        self.log("fit", run, 0)
```

```yaml
method:
  type: DirectFit       # or Training — nothing else in the code changes
```

❌ Never do this — it is exactly the failure mode this rule exists to prevent:

```python
def main(cfg):
    method = build(Method, cfg.method)
    if isinstance(method, Training):          # ❌ task-type branching
        for it in range(cfg.iterations):
            method.step()
            run.track(method.model.loss, name="train.loss", step=it)
            run.track(method.model.render(), name="train.render", step=it)
    elif cfg.method.type == "DirectFit":      # ❌ grows with every new method
        method.solve()
        run.track(method.model.render(), name="fit.render", step=0)
```

If the entry point, a shared helper, or a method body ever tests "are we
training or fitting?", the missing abstraction is a `Method` subclass (or a
sub-object built from config) — add it instead of the branch.

### `log(name, run, it, **__)` on every component

Logging is **performed by the object that owns the state, not assembled from
outside it**. Every class with something worth tracking (the task object, the
model, a loss, a dataset, a renderer, …) implements:

```python
def log(self, name: str, run: cairn.Run, it: int, **__) -> None:
```

- `name` — the prefix this object logs under (`"train"`, `"train.model"`, …).
- `run` — the `cairn.Run` to track into.
- `it` — the step / iteration used as `step=` in `run.track`.
- `**__` — swallows extra keyword arguments, so a caller can pass additional
  context (`subset="val"`, `final=True`, …) down the tree without every class
  having to declare or understand it.

An object logs its own scalars/images/figures under `name`, then **delegates
to its fields** with the field name appended:

```python
@register
class Training(Method):
    def log(self, name, run, it, **kw):
        run.track(self.loss_value, name=f"{name}.loss", step=it)
        self.model.log(f"{name}.model", run, it, **kw)
        self.dataset.log(f"{name}.dataset", run, it, **kw)

@register
class ResNet(Model):
    def log(self, name, run, it, **__):
        run.track(self.render(), name=f"{name}.render", step=it)
        run.track(cairn.Histogram(self.layer0.weight), name=f"{name}.w0", step=it)
```

This gives a stable, config-shaped metric namespace (`train.model.render`,
`fit.model.render`, `train.dataset.sample`, …), keeps every `run.track` call
next to the state it tracks, and means swapping a model or method in the
config swaps its logging with it — no external code needs to know what a
particular `Model` has to show. Components with nothing to log implement
`log` as a no-op (or inherit a base no-op) so parents can call it
unconditionally.

## Experiment tracking (cairn-track)

Run `cairn init` once (creates `./.cairn/`, git-ignored). Every experiment
creates a `cairn.Run`, logs the composed hydra config, and tracks metrics and
media during training; browse everything with `pixi run ui` (→
http://localhost:4301/).

```python
import cairn
from omegaconf import OmegaConf

run = cairn.Run(project="<project>", name="<experiment>")
run["config"] = OmegaConf.to_container(cfg, resolve=True)  # full run config

run.track(loss, name="train.loss", step=step)                       # scalar
run.track(loss, name="train.loss", step=step, context={"subset": "val"})
run.track(pil_image, name="predictions.sample", step=step)          # image
run.track(fig, name="training_curves", step=step)                   # mpl/plotly
run.track(cairn.Histogram(weights, bins=64), name="w0", step=step)
```

`run.track` also accepts `cairn.Tensor`, `cairn.Text`, `cairn.Audio`. The repo
is resolved via `CAIRN_REPO` / `./.cairn`; use `repo="cairn://host:port"` for a
shared server and `local_wal=True` on clusters (NFS/Slurm). Read runs back with
`cairn.Reader`.

## Reports (on demand)

Do **not** scaffold reports by default — tracked runs browsed via `cairn ui` are
the primary view of results. When the user asks for a report, create a
sub-folder per report under `reports/` (e.g. `reports/ablation/`) holding a
script that reads the tracked runs from cairn (`cairn.Reader`) and emits a
self-contained `report.html` next to itself — never hand-edited. Register a pixi
task per report (`report-ablation = "python reports/ablation/report.py"`).

```python
import cairn
import cairn.plot as cp

reader = cairn.Reader()
runs = reader.runs(project="<project>").list()
report = cp.Report(title="Ablation")
report.add(cp.Line({r.name: r.sequence("train.loss").values for r in runs}))
report.save("reports/ablation/report.html")
```

Useful components: `cp.Line`, `cp.Scatter`, `cp.Bar`, `cp.Histogram`,
`cp.Heatmap`, `cp.Image`, `cp.Table`, `cp.Figure` (plotly passthrough),
`cp.PointCloud`, `cp.Mesh`, `cp.Volume`.

## Reproducibility checklist

- [ ] `pixi.lock` committed; `.pixi/` git-ignored
- [ ] Configs in `configs/`, composed by hydra; per-run composed config saved
      (hydra's `.hydra/config.yaml`) so any run can be re-created
- [ ] Objects built from config via the registry (`type` key), including nested
      sub-objects
- [ ] Random seeds fixed in the config and recorded per run
- [ ] A single top-level task object (`Method`/`Trainer`/…) selected via the
      config's `type` key performs the task; no `if training / elif fitting`
      branching anywhere
- [ ] Every component with loggable state implements
      `log(name, run, it, **__)` and delegates to its fields as
      `log(f"{name}.<field>", …)`; `run.track` is never called on a component
      from outside it
- [ ] Every result an experiment produces is tracked into cairn (metrics,
      figures, images), with the composed config logged via `run["config"]` —
      no ad-hoc results directories
- [ ] Reports (if any) live in `reports/<name>/`, reference the tracked runs
      via `cairn.Reader`, and are produced only by their script, never edited
      by hand
- [ ] A fresh clone reproduces everything with `pixi install && pixi run all`
