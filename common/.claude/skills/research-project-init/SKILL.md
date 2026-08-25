---
name: research-project-init
description:
  Initialize or extend a reproducible research project managed with pixi
  (dependencies mainly from PyPI), with a flat layout, hydra-managed configs, a
  registry/build ("type" key) pattern for constructing objects from config,
  experiments tracked with cairn-track, and on-demand cairn-plot reports. Use
  when starting a new research project, setting up pixi/pixi.toml, adding
  experiment, tracking, or report scaffolding, or when the user mentions
  cairn-track, cairn-plot, experiment tracking, "reproducible report", hydra
  configs, the registry/build pattern, or pixi project setup.
---

# Research Project Init

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
6. **Graphics and images use plotly or cairn-plot** (cairn-plot is installed
   with cairn-track). During training, log scalars, images, and
   matplotlib/plotly figures with `run.track(...)`; for standalone reports,
   cairn-plot generates self-contained offline HTML and wraps plotly figures
   (`cp.Figure`), images (`cp.Image`), tables, line/scatter/heatmap plots, point
   clouds, and meshes.

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
import hydra
from omegaconf import DictConfig

from methods import Method
from util.registry import build

# config_path is relative to this file — entry points live in experiments/
@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    method = build(Method, cfg.method)
    method.run()

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
- [ ] Every result an experiment produces is tracked into cairn (metrics,
      figures, images), with the composed config logged via `run["config"]` —
      no ad-hoc results directories
- [ ] Reports (if any) live in `reports/<name>/`, reference the tracked runs
      via `cairn.Reader`, and are produced only by their script, never edited
      by hand
- [ ] A fresh clone reproduces everything with `pixi install && pixi run all`
