---
name: research-project
description:
  Initialize, extend, or develop a reproducible research project managed with
  pixi (dependencies mainly from PyPI), with a flat layout, hydra-managed
  configs, a registry/build ("type" key) pattern for constructing objects from
  config, one registered Method per way of fitting (no procedure branches on
  the kind of object it was given), components that log themselves with
  log(name, run, it), experiments tracked with cairn-track, and on-demand
  cairn-plot reports. Use when starting a new research project, setting up
  pixi/pixi.toml, adding a method, model, or component, adding experiment,
  tracking, logging, or report scaffolding, or when the user mentions
  cairn-track, cairn-plot, experiment tracking, "reproducible report", hydra
  configs, the registry/build pattern, component logging, or pixi project
  setup.
---

# Research Project

Set up and develop a research project so that every result — numbers, figures,
and tracked runs — can be traced to its exact config and regenerated from
scratch with a single command.

## Core principles

1. **pixi manages all dependencies.** Dependencies come mainly from PyPI
   (`[pypi-dependencies]`); use conda-forge (`[dependencies]`) only for things
   PyPI can't provide well (e.g. `python` itself, compilers, CUDA). Always
   commit `pixi.lock` — it is what makes the environment reproducible.
2. **Everything is reproducible, and every run is tracked.** Each run logs its
   composed hydra config, seed, metrics, figures, and images to cairn-track, so
   any result can be traced to the exact config that produced it. Nothing is
   printed or saved to disk that cairn could show.
3. **Flat layout.** No `src/<pkg>/` nesting: each kind of thing gets its own
   top-level directory, named for what this project actually contains.
4. **Hydra manages configs.** All run configuration lives in `configs/`; the
   composed config and seed of every run are saved with it.
5. **Objects are built from config via a global registry.** Classes are
   registered with `@register` and instantiated from a config's `"type"` key
   with `build(Base, cfg)`, including nested sub-objects
   ([registry.py](registry.py)).
6. **One registered `Method` per way of fitting.** The task itself — gradient
   training, a closed-form estimate, rendering, evaluation — is an object
   selected from the config. No entry point, helper, or method body ever
   branches on what kind of task or object it was given.
7. **Components log themselves.** Every component implements
   `log(name, run, it)`: it tracks what is worth seeing about itself under its
   own prefix and delegates to its parts under `sub(name, part)`
   ([track.py](track.py)). Logging is never assembled from outside.
8. **Graphics use plotly or cairn-plot; images always use cairn-plot.**
   cairn-plot's image viewer supports arbitrary client-side comparisons
   (side-by-side / wipe / blend, pixel-diff kernels incl. FLIP and SSIM, synced
   viewports) and true-float HDR with tone-mapping. Never put an image in a
   plotly trace.

## Project layout

```
project/
├── pixi.toml          # workspace, tasks, dependencies
├── pixi.lock          # committed — reproducibility
├── .envrc             # direnv: auto-activate the pixi env
├── .gitignore         # ignore .pixi/, .cairn/, outputs/
├── .cairn/            # cairn-track repo — all results live here (git-ignored)
├── configs/           # hydra configs (config.yaml + config groups)
├── util/              # registry.py, track.py, shared helpers
├── <concept>/         # one flat dir per project concept: base class + one
├── <concept>/         #   subclass per variant — named for THIS project
├── experiments/       # entry points; every run tracks into cairn
└── reports/           # on-demand cairn-plot reports, one sub-folder each
```

Only `configs/`, `util/`, `experiments/`, and `reports/` are fixed. Create one
`<concept>` directory per concept the project actually has, named for it — an
ML project might have `methods/`, `models/`, `encodings/`, `losses/`, and
`datasets/`; a rendering project `integrators/` and `scenes/`. Never copy example names from this skill
into a project they don't fit, and never nest a package hierarchy.

## pixi setup

In a fresh project, initialize git **first**, then pixi:

```bash
git init
pixi init --format pixi    # only if no pixi.toml exists yet
```

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
black = "*"              # formatter; run after every edit

[tasks]
experiment = "python experiments/run.py"
ui = "cairn ui"          # browse tracked runs at http://localhost:4301/
format = "black ."
all = { depends-on = ["experiment"] }
```

- Add PyPI packages with `pixi add --pypi <pkg>`; conda packages with
  `pixi add <pkg>`; git packages with
  `pixi add --pypi "<pkg>[extras] @ git+https://github.com/<owner>/<repo>"`.
- Encode every runnable step as a pixi task (`experiment`, `ui`, per-report
  tasks, `all`) and chain them with `depends-on`, so `pixi run all` reproduces
  everything.

## direnv (.envrc)

```sh
watch_file pixi.lock
eval "$(pixi shell-hook)"
```

Then `direnv allow`.

## Formatting (black)

`black` is a project dependency (`pixi add --pypi black`) with a `format`
task. **Run `pixi run format` after writing or editing any Python file**,
before reporting the change as done — never hand-format, and never leave a
file in a state black would rewrite. Keep black's defaults; do not add a
`[tool.black]` section unless the project already has one.

## Configs (hydra)

All configuration lives in `configs/`, composed by hydra. Entry points are
decorated with `@hydra.main`; hydra saves the fully composed config of every run
under its output dir (`.hydra/config.yaml`). Put the seed in the config, not in
code.

```python
# experiments/run.py
import cairn
import hydra
from omegaconf import DictConfig, OmegaConf

from datasets import Dataset
from methods import Method
from models import Model
from util.registry import build

# config_path is relative to this file — entry points live in experiments/
@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    with cairn.Run(project="<project>", name=cfg.name) as run:
        run.config(OmegaConf.to_container(cfg, resolve=True))
        dataset = build(Dataset, cfg.dataset)
        model = build(Model, cfg.model)
        method = build(Method, cfg.method, model=model, dataset=dataset)
        run.config(metrics=method.fit(run))

if __name__ == "__main__":
    main()
```

Use one config group per top-level concept (`configs/method/`,
`configs/model/`, `configs/dataset/`) so variants are selected on the CLI
(`python experiments/run.py method=estimate`) and swept (`-m model=a,b`):

```yaml
# configs/config.yaml
defaults:
  - method: gradient_fit   # groups that others may override come FIRST
  - model: mlp
  - dataset: image
  - _self_
name: ${model.type}-${method.type}
seed: 0
```

When a variant of one concept requires a particular variant of another (a
closed-form model needs the closed-form procedure), let its config select that
too, instead of a check in code. A `# @package _global_` group config can
carry an override of another group, provided the overridden group appears
earlier in the primary defaults list:

```yaml
# configs/model/closed_form.yaml
# @package _global_
defaults:
  - override /method: estimate
model:
  type: ClosedForm
  order: 3
```

## Building objects from config (registry + `type` key)

Copy [registry.py](registry.py) into `util/registry.py`. Decorate a class with
`@register`; `build(Base, cfg)` looks up `cfg["type"]` in the global registry,
passes the remaining keys as constructor kwargs (explicit kwargs to `build`
override the config), type-checks the result, and passes an existing instance
through unchanged. Nested objects are configured the same way at every level:

```yaml
# configs/model/mlp.yaml
type: MLP
width: 64
encoding:
  type: Fourier          # nested object, same mechanism
  bands: 8
```

```python
# models/mlp.py
from encodings import Encoding
from models.base import Model
from util.registry import build, register

@register
class MLP(Model):
    def __init__(self, encoding: dict | Encoding, width: int = 64):
        self.encoding = build(Encoding, encoding)   # builds the nested config
        self.width = width
```

## Class organization (inheritance over flags)

Avoid parameters that switch behavior via `if`/`else` or `match` — each variant
becomes its own registered subclass, selected by `"type"` in the config:

```python
# ❌ one class, behavior flags, if-else in every method
class Model:
    def __init__(self, kind: str = "mlp", use_encoding: bool = False): ...

# ✅ one base class per top-level concept, one subclass per variant
class Model(Trackable): ...

@register
class MLP(Model): ...

@register
class ClosedForm(Model): ...
```

Define a base class per top-level concept in its own flat directory, one
registered subclass per variant, and let the config's `type` key pick. New
behavior = new subclass + one config line, no new flags. Each concept's
`__init__.py` exports the base class and imports every variant module, so
`from models import Model` is enough for all `@register` decorators to run.

This applies to **procedures** as much as to models. A loop that checks what
kind of object it was given (`if isinstance(model, ...)`, `if field has
parameters ... else`) is two procedures in one; write each as its own
`Method`, each assuming exactly what it needs. Shared steps (what happens at
evaluation time) become plain functions or base-class methods both procedures
call, not branches.

## Methods: one per way of fitting

There is always a **top-most object that performs the task** — a `Method`
selected from the config. It *owns* the objects it works on
(`Method(model, dataset)`, built with
`build(Method, cfg.method, model=model, dataset=dataset)`), does the whole
task while tracking into `run`, and returns the final metrics. The entry point
builds it and calls it; it does nothing else.

Which methods `Method` has is the project's choice — `fit(run)` alone, or
`prepare`/`fit`/`evaluate`, or whatever the task naturally splits into. What
matters is where responsibilities sit, not the names:

- The **base class** holds what every variant shares: logging the static
  members once, the evaluation step (predict on the truth's lattice, let the
  dataset judge, log the changing members), and the `log` that reaches the
  owned objects.
- Each **subclass** is one complete procedure that assumes exactly what it
  needs — an iterating one tracks its own per-step curves and evaluates every
  so often; a closed-form one solves and evaluates once.

```python
# methods/base.py
import cairn

from datasets import Dataset
from models import Model
from util.track import Trackable, sub

class Method(Trackable):
    def __init__(self, model: Model, dataset: Dataset):
        self.model = model
        self.dataset = dataset

    def fit(self, run: cairn.Run) -> dict:
        raise NotImplementedError

    def evaluate(self, run: cairn.Run, it: int | None = None, **kw) -> dict:
        pred = self.model(self.dataset.grid())
        metrics = self.dataset.evaluate(pred, run, "eval", it, **kw)
        self.log("", run, it, **kw)                # changing members
        return metrics

    def log(self, name, run, it=None, **kw):
        self.model.log(sub(name, "model"), run, it, **kw)
```

```python
# methods/gradient_fit.py
from losses import Loss
from methods.base import Method
from util.registry import build, register
from util.track import sub

@register
class GradientFit(Method):
    def __init__(self, model, dataset, loss: dict | Loss, lr: float = 1e-2,
                 iterations: int = 1000, eval_every: int = 100):
        super().__init__(model, dataset)
        self.loss = build(Loss, loss)                  # nested sub-object
        self.lr, self.iterations, self.eval_every = lr, iterations, eval_every

    def fit(self, run):
        self.dataset.log("dataset", run)               # static members: once
        for it in range(self.iterations):
            value = self.step()                        # one optimizer step -> loss value
            run.track(value, name="train.loss", step=it)   # the method's own curve
            if it % self.eval_every == 0:
                self.evaluate(run, it)
        return self.evaluate(run, self.iterations, final=True)   # full-size media

    def log(self, name, run, it=None, **kw):
        run.track(self.lr, name=sub(name, "lr"), step=it)
        self.loss.log(sub(name, "loss"), run, it, **kw)
        super().log(name, run, it, **kw)              # -> model.*

# methods/estimate.py
from methods.base import Method
from util.registry import register

@register
class Estimate(Method):                                # closed form: no loop
    def fit(self, run):
        self.dataset.log("dataset", run)
        self.model.solve(self.dataset)
        return self.evaluate(run, final=True)          # once, it=None
```

```yaml
# configs/method/gradient_fit.yaml
type: GradientFit
loss:
  type: L2               # nested sub-object, built by GradientFit
lr: 0.01
iterations: 1000
eval_every: 100

# configs/method/estimate.yaml
type: Estimate           # swap on the CLI: method=estimate — no code changes
```

❌ Never do this — it is exactly the failure this rule exists to prevent:

```python
def main(cfg):
    with cairn.Run(project="<project>", name=cfg.name) as run:
        dataset = build(Dataset, cfg.dataset)
        model = build(Model, cfg.model)
        method = build(Method, cfg.method, model=model, dataset=dataset)
        if isinstance(method, GradientFit):          # ❌ task-type branching
            for it in range(cfg.method.iterations):
                method.step()
                run.track(model(dataset.grid()), name="train.pred", step=it)
        elif cfg.method.type == "Estimate":          # ❌ grows with every new method
            model.solve(dataset)
            run.track(model(dataset.grid()), name="fit.pred")
```

If any code asks "are we training or fitting?", the missing abstraction is a
`Method` subclass (or a sub-object built from config) — add it instead of the
branch.

## Components log themselves

Copy [track.py](track.py) into `util/track.py`. Every component base class
(`Method`, `Model`, `Dataset`, `Loss`, `Encoding`, …) derives from `Trackable`
and implements

```python
def log(self, name: str, run: cairn.Run, it: int | None = None, **_) -> None:
```

- `name` — the prefix this object logs under (`""` at the top level). Each
  component chooses only the **last segment** of its own names via
  `sub(name, part)`; the prefix is always what it was given.
- `run` — the `cairn.Run` to track into.
- `it` — the iteration used as `step=`; `None` for one-shot logging.
- `**_` — extra context a caller may pass down the tree (`subset="val"`,
  `final=True`, …) without every class having to declare or understand it.

An object tracks its own diagnostics under `name`, then **delegates to its
parts** with the part's name appended, and calls `super().log` so a base
class's parts are still reached:

```python
# models/mlp.py
@register
class MLP(Model):
    def log(self, name, run, it=None, final=False, **kw):
        run.track(self.rms(), name=sub(name, "rms"), step=it)
        run.track(cairn.Histogram(self.layer0.weight), name=sub(name, "w0"), step=it)
        pred = self.render(scale=1 if final else 1 / 4)     # small while fitting
        run.track(pred, name=sub(name, "pred"), step=it)
        self.encoding.log(sub(name, "encoding"), run, it, final=final, **kw)
        super().log(name, run, it, final=final, **kw)

# encodings/fourier.py
@register
class Fourier(Encoding):
    def log(self, name, run, it=None, **kw):
        run.track(self.spectrum_figure(), name=sub(name, "spectrum"), step=it)
```

Components with nothing to show inherit the no-op, so parents call `log` on
every part unconditionally — no `hasattr` or `isinstance` checks.

**When it is called.** The method calls `self.log("", run, it)` at every
**evaluation** and nowhere else, so `log` covers the members that *change*
while fitting. Static members (the dataset, the reference signal) are logged
**once**, at the start of the task, so no `log` needs a "first time" check.
Per-step curves (`train.loss`) are the method's own and are tracked directly in
its loop, between evaluations. A closed-form method evaluates once with
`it=None`.

**Names** mirror the object tree and nothing else: `model.rms`, `model.w0`,
`model.pred`, `model.encoding.spectrum`, `dataset.image`, `loss.weight`, `lr`, `eval.psnr`,
and the method's own `train.loss`. Renaming a
member renames its whole subtree, two instances of a class log under different
prefixes without collisions, and a new component brings its own diagnostics
with it instead of edits to the loop.

**What to log.** What you would want to *look at* to tell whether the component
is doing its job: a few scalars (norms, counts, a fraction), a histogram of a
table, an image of a dictionary, a spectrum, a point layout. Not the loss (the
method's), not parameters as raw tensors, not anything cairn can derive from
two things already tracked (an error image is the UI's diff of the
reconstruction and the reference).

**Keep intermediate media small.** Every tracked image, volume, or point set
travels over the network to the cairn repo and is stored per step, so
full-size media (a 4K reconstruction, a whole dataset, a dense volume) is
logged **only at the end** — the final evaluation, marked by `final=True`
passed down through `evaluate` and `log`. In between, log a crop or a
downsampled version (a quarter-resolution render, a single slice, a subset of
points), enough to see whether the fit is going the right way. The reference
data itself is static and is logged once, at full size, at the start.

**The judge: `evaluate`.** Metrics that compare a prediction to the truth
belong to the thing that judges. The ground-truth base class implements

```python
def evaluate(self, pred, run: cairn.Run, name: str = "eval", it: int | None = None, **kw) -> dict:
```

which computes the metrics, tracks them and the views that make sense for its
kind (`eval.psnr`, `eval.reconstruction`, `eval.spectrum`; a 6D signal would
track slices), and returns the metrics so the method can report them as the
run's final numbers.

## Experiment tracking (cairn-track)

Run `cairn init` once (creates `./.cairn/`, git-ignored). Every experiment
creates a `cairn.Run`, attaches the composed config with `run.config(...)`, and
tracks into it; browse everything with `pixi run ui` (→
http://localhost:4301/).

```python
run.track(loss, name="train.loss", step=it)                        # scalar
run.track(loss, name="train.loss", step=it, context={"subset": "val"})
run.track(image_array, name="eval.reconstruction", step=it)        # image
run.track(fig, name="model.encoding.spectrum", step=it)            # mpl/plotly
run.track(cairn.Histogram(weights, bins=64), name="model.w0", step=it)
```

`run.track` also accepts `cairn.Image` (with box/mask overlays),
`cairn.Tensor`, `cairn.Text`, `cairn.Audio`. The repo is resolved via
`CAIRN_REPO` / `./.cairn`; use `repo="cairn://host:port"` for a shared server
and `local_wal=True` on clusters (NFS/Slurm). Read runs back with
`cairn.Reader`.

## Reports (on demand)

Do **not** scaffold reports by default — tracked runs browsed via `cairn ui` are
the primary view of results. When the user asks for a report, create a
sub-folder per report under `reports/` (e.g. `reports/ablation/`) holding a
script that reads the tracked runs (`cairn.Reader`) and emits a self-contained
`report.html` next to itself — never hand-edited. Register a pixi task per
report (`report-ablation = "python reports/ablation/report.py"`).

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
`cp.Heatmap`, `cp.Image`, `cp.Compare`, `cp.Table`, `cp.Figure` (plotly
passthrough), `cp.Grid`, `cp.PointCloud`, `cp.Mesh`, `cp.Volume`.

## Reproducibility checklist

- [ ] `pixi.lock` committed; `.pixi/` git-ignored
- [ ] `black` in the dependencies; `pixi run format` run after every edit
- [ ] Configs in `configs/`, composed by hydra; per-run composed config saved
      (hydra's `.hydra/config.yaml`) and attached via `run.config(...)`
- [ ] Objects built from config via the registry (`type` key), including nested
      sub-objects
- [ ] Random seeds fixed in the config and recorded per run
- [ ] One registered `Method` per way of fitting, selected by config; no
      procedure branches on the kind of task or object it was given
- [ ] Every component base class is `Trackable`; components log themselves
      with `log(name, run, it)` and delegate to their parts; `run.track` is
      never called on a component's state from outside it
- [ ] Every result an experiment produces is tracked into cairn (metrics,
      figures, images) — no ad-hoc results directories, nothing printed or
      saved that cairn could show
- [ ] Reports (if any) live in `reports/<name>/`, reference the tracked runs
      via `cairn.Reader`, and are produced only by their script, never edited
      by hand
- [ ] A fresh clone reproduces everything with `pixi install && pixi run all`
