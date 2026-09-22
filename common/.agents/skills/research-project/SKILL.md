---
name: research-project
description:
  Initialize, extend, or develop a reproducible research project managed with
  pixi (dependencies mainly from PyPI), with a flat layout, hydra-managed
  configs, a registry/build ("type" key) pattern for constructing objects from
  config, one registered Method per way of fitting (no procedure branches on
  the kind of object it was given), components that record themselves through
  cairn's __cairn_track__(self, scope) protocol, experiments tracked with
  cairn-track, and on-demand
  cairn-plot reports. Use when starting a new research project, setting up
  pixi/pixi.toml, adding a method, model, or component, adding experiment,
  tracking, logging, or report scaffolding, or when the user mentions
  __cairn_track__, cairn.Scope,
  cairn-track, cairn-plot, experiment tracking, "reproducible report", hydra
  configs, the registry/build pattern, component tracking, or pixi project
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
7. **Components record themselves.** A component that has something worth
   seeing implements cairn's `__cairn_track__(self, scope)` and calls
   `scope.track(value, name)`; `run.track(method, "", step=it)` then walks the
   whole tree. Nothing is inherited and nothing is required — a component with
   nothing to show simply omits the method. Tracking is never assembled from
   outside.
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
├── util/              # registry.py + shared helpers
├── <concept>/         # one flat dir per project concept: base class + one
├── <concept>/         #   subclass per variant — named for THIS project
├── experiments/       # entry points; every run tracks into cairn
└── reports/           # on-demand cairn-plot reports, one sub-folder each
```

Only `configs/`, `util/`, `experiments/`, and `reports/` are fixed. Create one
`<concept>` directory per concept the project actually has, named for it — an
ML project might have `methods/`, `models/`, `encoders/`, `losses/`, and
`datasets/`; a rendering project `integrators/` and `scenes/`.

**Check the name is free before you use it.** The project root is the import
root (see `PYTHONPATH` below), so a top-level directory shadows any stdlib
module of the same name. `encodings/` is the trap worth naming: CPython imports
`encodings` while starting up, so that one directory kills the interpreter
before it runs a line of your code. `types/`, `io/`, `copy/`, `queue/`,
`logging/`, `platform/` and `test/` are all plausible concept names and all
taken. Run `python -c "import <name>"` first; if it succeeds, pick another
name.

Never copy example names from this skill
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
# Not on PyPI, so it comes from git; its own extras pin the other halves to
# exact commits, so nothing else needs declaring here.
#   [ui]    what `cairn ui` and `cairn server --ui` need — the base install
#           ships no browser assets and says so if the extra is missing.
#           Implies [plot], which is what `import cairn.plot` needs for reports.
#   [media] the matplotlib/plotly/imageio/soundfile handlers.
# A compute node that only ever logs metrics can drop [ui].
cairn-track = { git = "https://github.com/doeringchristian/cairn", extras = ["ui", "media"] }
black = "*"              # formatter; run after every edit

[activation.env]
# The layout is flat, so the project root is the import root: `from methods
# import Method` has to resolve while the entry point lives in experiments/.
# Running a script only puts *that script's* directory on sys.path, so without
# this every import of a sibling concept fails in a fresh checkout.
PYTHONPATH = "."

[tasks]
experiment = "python experiments/run.py"
ui = "cairn ui"          # browse tracked runs at http://localhost:4301/ (needs [ui])
format = "black ."
all = { depends-on = ["experiment"] }
```

Then resolve the environment and create the cairn repo, in this order — both
are assumed by everything below:

```bash
pixi install          # writes pixi.lock; commit it
pixi run cairn init   # creates ./.cairn/ (git-ignored)
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

Open every group config with a one-line comment saying which regime that
variant is for and why you would pick it. A config group is a menu, and the
`type` alone does not say when to order it.

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
too, instead of a check in code. `# @package <path>` also gives a *sub-object*
its own group: `# @package target.scene` at the top of `configs/scene/*.yaml`
makes the scene CLI-selectable with `scene=cornell_box` while it is still built
as part of the target, so the entry point never has to know the target has a
scene. A `# @package _global_` group config can
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

### A registry config is replaced whole, never merged

A `type` and its sibling keys are one unit: the siblings only mean anything to
the class `type` names. Hydra's defaults list **merges** mappings, so inheriting
a group config and overriding a nested object silently keeps the old object's
keys:

```yaml
# configs/flow/fourier.yaml — ❌ merges, does not replace
defaults:
  - mean_velocity        # its encoder is {type: HashGrid, levels: 8}
encoder:
  type: Fourier
  bands: 6
# composes to {type: Fourier, levels: 8, bands: 6} -> Fourier(levels=8) TypeError
```

Write each variant's config out in full instead of inheriting a sibling variant,
or put the nested object in its own config group and select it. The failure is
a `TypeError` from a constructor that never heard of `levels`, far from the
config that caused it.

## Building objects from config (registry + `type` key)

Copy [registry.py](registry.py) into `util/registry.py`. Decorate a class with
`@register`; `build(Base, cfg)` looks up `cfg["type"]` in the global registry,
passes the remaining keys as constructor kwargs (explicit kwargs to `build`
override the config), type-checks the result, and passes an existing instance
through unchanged. The registry is keyed on the bare class name in one global
namespace and refuses a duplicate, so two concepts cannot both register a
`Uniform`; give one of them a qualified name. Nested objects are configured the
same way at every level:

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

**Injecting what a child cannot configure.** Keyword arguments passed to
`build` beat the config, which is how a parent hands its children a shared
object no config file could name — `build(Source, source, manifold=self.manifold)`.
Express an optional sub-object's default in the config's own vocabulary rather
than as a bare class: `build(Encoding, encoding or {"type": "Fourier"})`.

**Wiring that needs a value from another concept** — a bounding box, a vocab
size, an input dimension — does not belong in the entry point, which stays free
of task knowledge. The `Method` owns both objects, so it does that wiring
itself at the start of the task:

```python
def prepare(self, run, step):                       # called first by every fit()
    self.model.reset(self.dataset.bounds())
    run.track(self.dataset, "dataset", step=step)   # static members: once
```

**Capabilities a method requires** of the object it fits — a differentiable
representation exposing `parameters`, a closed-form one exposing `solve` —
belong on that concept's base class raising `NotImplementedError`, so an
incompatible pairing fails where the capability is declared instead of deep
inside a loop. The config is what pairs them; no code branches on the pairing.

## Class organization (inheritance over flags)

Avoid parameters that switch behavior via `if`/`else` or `match` — each variant
becomes its own registered subclass, selected by `"type"` in the config:

```python
# ❌ one class, behavior flags, if-else in every method
class Model:
    def __init__(self, kind: str = "mlp", use_encoding: bool = False): ...

# ✅ one base class per top-level concept, one subclass per variant
class Model: ...

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

**A hierarchy may be deeper than two.** "One subclass per variant" is about
the *variants*, not a ban on an intermediate: where several variants share real
machinery, an unregistered abstract class between the concept base and the
registered leaves is right. Only the leaves carry `@register`, so only the
leaves are selectable.

**A shared step with one implementation stays a function.** Wrapping it in a
base class and a registry entry before a second implementation exists is
ceremony around a single call site. Promote it to a concept when the second
implementation arrives, which is also when the config gains something to
choose between.

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

class Method:
    def __init__(self, model: Model, dataset: Dataset):
        self.model = model
        self.dataset = dataset

    def fit(self, run: cairn.Run) -> dict:
        raise NotImplementedError

    def prepare(self, run: cairn.Run, step: int) -> None:
        """Wire the parts together, then record what will not change again."""
        self.model.reset(self.dataset.bounds())
        run.track(self.dataset, "dataset", step=step)

    def finish(self, run: cairn.Run, step: int) -> dict:
        """Last evaluation, plus the artifacts too expensive to repeat."""
        metrics = self.evaluate(run, step)
        run.track(self.model.render(scale=1), name="final.render", step=step)
        return metrics

    def evaluate(self, run: cairn.Run, step: int) -> dict:
        pred = self.model(self.dataset.grid())
        metrics = self.dataset.evaluate(pred, run, "eval", step)
        run.track(self, "", step=step)          # walks the changing members
        return metrics

    def __cairn_track__(self, scope):
        scope.track(self.model, "model")
```

```python
# methods/gradient_fit.py
from losses import Loss
from methods.base import Method
from util.registry import build, register

@register
class GradientFit(Method):
    def __init__(self, model, dataset, loss: dict | Loss, lr: float = 1e-2,
                 iterations: int = 1000, eval_every: int = 100):
        super().__init__(model, dataset)
        self.loss = build(Loss, loss)                  # nested sub-object
        self.lr, self.iterations, self.eval_every = lr, iterations, eval_every

    def fit(self, run):
        self.prepare(run, step=0)                      # static members: once
        for it in range(self.iterations):
            value = self.step()                        # one optimizer step -> loss value
            run.track(value, name="train.loss", step=it)   # the method's own curve
            if it % self.eval_every == 0:
                self.evaluate(run, it)
        return self.finish(run, self.iterations)       # last eval + full-size media

    def __cairn_track__(self, scope):
        scope.track(self.loss, "loss")
        super().__cairn_track__(scope)                 # -> model.*

# methods/estimate.py
from methods.base import Method
from util.registry import register

@register
class Estimate(Method):                                # closed form: no loop
    def fit(self, run):
        self.prepare(run, step=0)
        self.model.solve(self.dataset)
        return self.finish(run, step=0)                # evaluated once, at step 0
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

## Components record themselves

Nothing is copied into the project for this: `__cairn_track__` is cairn's own
protocol. A component that has something worth seeing implements

```python
def __cairn_track__(self, scope) -> None:
```

and records through the `scope` it is handed. Nothing is inherited and nothing
is required, so components keep whatever class hierarchy their concept needs. A
`scope` is a `cairn.Run` with a name prefix, a `step` and a `context` already
bound to it, and it has one operation:

- `scope.track(value, name)` — record `value` under `name` joined onto the
  prefix. If `value` implements `__cairn_track__` it is handed a child scope and
  records itself instead, so one call covers scalars, media and sub-components
  alike. `None` is a silent skip, so an optional member needs no guard.
- `scope.scope(name)` returns that child scope directly, for the rare case you
  want it without tracking anything.
- `scope.run`, `scope.step` and `scope.name` are there for an escape hatch.

`Run` is itself the root scope, so walking a tree needs no new API:

```python
run.track(method, "", step=it)      # records method.*, model.*, model.encoding.*
```

Use `run.scope(step=it)` only where recursion cannot reach — handing a bound
scope to a plain function that is not a component, as in
`evaluate(model, run.scope(step=it))`.

```python
# models/mlp.py
@register
class MLP(Model):
    def __cairn_track__(self, scope):
        scope.track(self.rms(), "rms")
        scope.track(cairn.Histogram(self.layer0.weight), "w0")
        scope.track(self.render(scale=1 / 4), "pred")   # cheap; full size at the end
        scope.track(self.encoding, "encoding")          # recurses
        super().__cairn_track__(scope)                  # only if Model defines one

# encodings/fourier.py
@register
class Fourier(Encoding):
    def __cairn_track__(self, scope):
        scope.track(self.spectrum_figure(), "spectrum")
```

Components with nothing to show implement nothing. `scope.track` on them
records the object as a plain value, so pass a component only where you mean
its diagnostics.

**The step is always bound and always real.** `run.track` requires `step`, and
every scope beneath inherits the one named at the root. There is no
auto-increment and no `None`: a member recorded on only some iterations would
otherwise keep its own count and claim iterations that were not its own. A
closed-form method that evaluates once still names a step, `step=0`.

**When it is called.** The method walks itself at every **evaluation** and
nowhere else, so the walk covers the members that *change* while fitting.
Static members are recorded **once**, in `prepare`, so no component needs a
"first time" check. Per-step curves such as `train.loss` are the method's own
and are tracked directly in its loop, between evaluations.

**Names** mirror the object tree and nothing else: `model.rms`, `model.w0`,
`model.pred`, `model.encoding.spectrum`, `dataset.image`, `eval.psnr`, and the
method's own `train.loss`. Renaming a member renames its whole subtree, two
instances of a class record under different prefixes without collisions, and a
new component brings its own diagnostics with it instead of edits to the loop.

**What to record.** What you would want to *look at* to tell whether the
component is doing its job: a few scalars (norms, counts, a fraction), a
histogram of a table, an image of a dictionary, a spectrum, a point layout. Not
the loss (the method's), not parameters as raw tensors, and not constructor
constants such as a learning rate or a loss weight — the composed config is
already attached to the run, so re-emitting them per step just makes flat
lines.

**Keep what repeats cheap.** Every tracked image, volume or point set travels
to the cairn repo on every evaluation, so a component's `__cairn_track__`
records a *fixed, cheap* view: a quarter-resolution render, one slice, a subset
of points. The expensive full-size artifact is recorded once, by the method, in
`finish` — a component cannot know it is the last iteration, and cairn has no
flag that tells it. The reference data is static and is recorded once, at full
size, in `prepare`.

**The judge: `evaluate`.** Metrics that compare a prediction to the truth
belong to the thing that judges. The ground-truth base class implements

```python
def evaluate(self, pred, run: cairn.Run, name: str = "eval", step: int = 0) -> dict:
```

which computes the metrics, tracks them and the views that make sense for its
kind (`eval.psnr`, `eval.reconstruction`, `eval.spectrum`; a 6D signal would
track slices), and returns the metrics so the method can report them as the
run's final numbers.

**Judge on a fixed domain.** Whatever the method predicts on — a grid, a
lattice, a held-out split — has to be built once and reused for the life of the
run, from its own seed. If it is redrawn per call, the method predicts on one
draw and the judge scores against another, and the metric moves for reasons
that have nothing to do with the fit.

**Keep the map behind the metric.** Most image metrics — FLIP, SSIM, absolute
or relative error — are a per-pixel map reduced to one number. The map was
computed to get the number, so record both: the scalar says how much worse, the
map says *where*, and it costs nothing that has not already been spent. Record
it as a single-channel image so the image card renders it through a colormap,
and use magma, which is what cairn-plot's own FLIP comparison uses. The viewer
can compute some of these itself from two tracked images, but that is a second
implementation which can disagree with the number you reported; the map you
reduced cannot.

**Report the headroom, not just the score.** A number that can look excellent
because the instance was easy is a number that lies. Alongside what the method
achieved, track what was there to achieve — the best any method could do on
this instance, and the fraction of it collected. Track the diagnostics that say
whether the result is *valid at all*, separately from how good it is: the share
of the domain where the prediction is degenerate, where a density is unbounded
or a Jacobian folds. A method can score well on the part that is still valid.

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
run.track(method, "", step=it)          # a component: walks the whole tree
```

**A fitted object that something downstream loads is an artifact, not a
result.** Weights a renderer will consume, a solved table, a trained guide:
record them with `run.log_artifact(value, name)` so they stay attached to the
run that produced them, rather than in a directory beside it. "Nothing saved that cairn
could show" is about results; an artifact is not a view, it is an input to the
next thing.

**Record the environment facts the config does not fix.** Anything resolved at
startup that changes the numbers — the device, the backend or variant actually
selected, the precision, the library version — goes into `run.config(...)`
alongside the composed config. The seed is in the config; the GPU is not, and
without it two runs that disagree cannot be told apart.

`step` is required on every call. `run.track` also accepts `cairn.Image` (with box/mask overlays),
`cairn.Tensor`, `cairn.Text`, `cairn.Audio`. The repo is resolved via
`CAIRN_REPO` / `./.cairn`; use `repo="cairn://host:port"` for a shared server
and `local_wal=True` on clusters (NFS/Slurm). Read runs back with
`cairn.Reader`.

## Reports (on demand)

A **paper figure** is the one thing `cairn ui` cannot give you: a sized,
LaTeX-typeset PDF. It belongs in the same place and under the same rule — a
script under `reports/<name>/` that reads the runs back and writes the file,
never a figure edited by hand or saved from a notebook. The
`matplotlib-publication-plot` skill covers the typesetting.

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

## Writing it down

Open every module with a docstring that says **why the design is what it is**,
in the project's own scientific terms, not what the API does. The reader who
needs it is you in three months, looking at a choice that will read as a bug
without its reason: why points are stored in ambient coordinates rather than a
chart, why the head starts small, why a quadrature and not an estimator. Justify
numerical constants and cite where they come from. This is the difference
between a codebase that can be picked up and one that has to be re-derived.

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
- [ ] Components that have something worth seeing implement
      `__cairn_track__(self, scope)` and record through the scope
      they are handed; no base class is imposed to get this, and nothing
      outside a component decides what that component records
- [ ] Every result an experiment produces is tracked into cairn (metrics,
      figures, images) — no ad-hoc results directories, nothing printed or
      saved that cairn could show
- [ ] Reports (if any) live in `reports/<name>/`, reference the tracked runs
      via `cairn.Reader`, and are produced only by their script, never edited
      by hand
- [ ] Concept directory names checked against the stdlib (`python -c "import
      <name>"` fails for each)
- [ ] Environment facts resolved at startup (device, backend, precision)
      attached with `run.config(...)`; fitted objects saved with
      `run.log_artifact`, not into a results directory
- [ ] Every group config opens with a line saying which regime it is for
- [ ] A fresh clone reproduces everything with `pixi install && pixi run all`
