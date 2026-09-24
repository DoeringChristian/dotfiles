---
name: research-project
description:
  Initialize, extend, or develop a reproducible research project managed with
  pixi (dependencies mainly from PyPI), with a flat layout, hydra-managed
  configs, a registry/build ("type" key) pattern for constructing objects from
  config, a registered Experiment as the highest-level executable object,
  components that record themselves through
  cairn's __cairn_track__(self, scope) protocol, experiments tracked with
  cairn-track, and on-demand
  cairn-plot reports. Use when starting a new research project, setting up
  pixi/pixi.toml, adding an experiment or component,
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
   composed hydra config, seed, results, and artifacts to cairn-track, so
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
6. **The experiment is a registered class.** The highest-level executable
   behavior is represented by a registered `Experiment` selected from config.
   Each experiment defines its own object graph, dependencies, and execution
   lifecycle; this skill imposes no fixed concepts or stages beneath it. The
   entry point only composes the config, builds the selected experiment, and
   invokes it. If two runs require materially different orchestration,
   represent them as different `Experiment` implementations rather than
   branching inside the entry point.
7. **Components record themselves.** A component that has something worth
   seeing implements cairn's `__cairn_track__(self, scope)` and calls
   `scope.track(value, name)`; tracking a component then walks its object tree.
   Nothing is inherited and nothing is required — a component with nothing to
   show simply omits the method. Tracking is never assembled from outside.
8. **Validation must test the actual claim.** Validation conditions must be
   capable of supporting or rejecting the experiment's intended claim. A
   cheaper proxy may be used for debugging or smoke testing, but it must be
   identified as a proxy and must not be presented as scientific evidence.
9. **Never improve results by weakening the problem.** Do not silently
   simplify the procedure, inputs, reference, objective, workload, or
   evaluation to make an experiment faster, easier, or more favorable. Any
   approximation that could change the scientific meaning of a result must be
   explicit in config, recorded with the run, and disclosed in the handoff.
10. **Preserve comparability.** Comparisons differ only in the factors they are
    intended to study. Keep evaluation conditions equivalent, record
    unavoidable differences, and check that implementation changes have not
    changed the question being measured.

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
├── experiments/       # Experiment base, registered variants, and run.py
└── reports/           # on-demand cairn-plot reports, one sub-folder each
```

Only `configs/`, `util/`, `experiments/`, and `reports/` are fixed. Create one
`<concept>` directory per concept the project actually has. Do not introduce a
concept merely because it appeared in another project or in an example.

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
#   [plot]  `import cairn.plot`, which the reports use. Listed explicitly
#           rather than relied on through [ui]: the viewer does not need a
#           renderer, so [ui] is not a promise of [plot].
#   [media] the matplotlib/plotly/imageio/soundfile handlers.
# A compute node that only ever logs metrics can drop [ui].
cairn-track = { git = "https://github.com/doeringchristian/cairn", extras = ["ui", "plot", "media"] }
black = "*"              # formatter; run after every edit

[activation.env]
# The layout is flat, so the project root is the import root: imports of sibling
# concept directories have to resolve while the entry point lives in experiments/.
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

from experiments import Experiment
from util.registry import build

# config_path is relative to this file — entry points live in experiments/
@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig) -> None:
    with cairn.Run(project="<project>", name=cfg.name) as run:
        run.config(OmegaConf.to_container(cfg, resolve=True))
        experiment = build(Experiment, cfg.experiment)
        experiment.run(run)

if __name__ == "__main__":
    main()
```

Open every group config with a one-line comment saying which regime that
variant is for and why you would pick it. A config group is a menu, and the
`type` alone does not say when to order it.

Use one config group per top-level concept so variants are selected on the CLI
and can be swept without code changes. The root config selects the experiment;
that experiment's config contains the object graph it needs:

```yaml
# configs/config.yaml
defaults:
  - experiment: primary
  - _self_
name: ${experiment.type}
seed: 0
```

When one variant requires particular subordinate variants, express that
composition in its config instead of checking it in code. Hydra packages can
place a separately selectable group under the owning experiment's config. A
`# @package _global_` group may override another group provided the overridden
group appears earlier in the root defaults list.

### A registry config is replaced whole, never merged

A `type` and its sibling keys are one unit: the siblings only mean anything to
the class `type` names. Hydra's defaults list **merges** mappings, so inheriting
a group config and overriding a nested object silently keeps the old object's
keys:

```yaml
# ❌ merges the old and new registry configs instead of replacing the object
defaults:
  - existing_variant    # component has {type: Existing, old_option: 8}
component:
  type: Replacement
  new_option: 6
# composes to {type: Replacement, old_option: 8, new_option: 6}
```

Write each variant's config out in full instead of inheriting a sibling variant,
or put the nested object in its own config group and select it. Otherwise the
failure appears later as a constructor receiving options that belonged to the
replaced type.

## Building objects from config (registry + `type` key)

Copy [registry.py](registry.py) into `util/registry.py`. Decorate a class with
`@register`; `build(Base, cfg)` looks up `cfg["type"]` in the global registry,
passes the remaining keys as constructor kwargs (explicit kwargs to `build`
override the config), type-checks the result, and passes an existing instance
through unchanged. The registry is keyed on the bare class name in one global
namespace and refuses a duplicate, so two concepts cannot both register a
`Uniform`; give one of them a qualified name. Nested objects use the same
mechanism at every level: the owning object accepts a config or existing
instance and calls `build` for that child's base class.

Keyword arguments passed directly to `build` override config values. Use this
only for runtime objects a config cannot name, such as a resource shared by a
parent and child. Express configurable defaults in the config's own vocabulary
rather than hiding them in entry-point wiring.

The registered `Experiment` owns all experiment-specific construction and
wiring. The entry point must not know which subordinate concepts exist. Put a
required capability on the relevant base class so an incompatible composition
fails at the declared interface rather than deep inside execution.

## Class organization (inheritance over flags)

Avoid parameters that select materially different behavior with `if`/`else` or
`match`. Give each real variant its own registered subclass selected by
`"type"` in config.

Define a base class per top-level concept in its own flat directory, one
registered subclass per variant, and let the config's `type` key pick. New
behavior = new subclass + one config line, no new flags. Each concept's
`__init__.py` exports the base class and imports every variant module so one
import is enough for all `@register` decorators to run.

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

This applies to orchestration as well as subordinate concepts. When two runs
require different control flow, make them separate `Experiment` variants.
Share genuinely common operations through ordinary functions, components, or
base-class methods; do not recover experiment-specific branching in a helper.

## Experiments: the executable strategy

`Experiment` is the only project-level interface the entry point knows. Keep
that interface minimal:

```python
# experiments/base.py
import cairn


class Experiment:
    def run(self, run: cairn.Run) -> None:
        raise NotImplementedError
```

Each registered subclass defines its own constructor, object graph, lifecycle,
tracking cadence, and result semantics. It may expose internal phases when
those phases fit the project, but this skill does not prescribe them. The
subclass records its results into the supplied run. The entry point neither
interprets its config nor inspects its type.

## Scientific validity

Remain self-sufficient on choices that preserve the experiment's claim.
Proceed with reversible implementation details and with clearly labeled smoke
tests used only to debug execution. Do not draw scientific conclusions from
those proxies.

Before treating a result as evidence, check that the evaluation regime has
enough fidelity and statistical quality to reveal the effect under study. A
change to the procedure, workload, reference, objective, baseline, or
evaluation that may alter the claim is not an implementation detail: represent
it explicitly in config, track it, and disclose it. When its validity is
uncertain, test the uncertainty or report the limitation instead of assuming it
away.

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
run.track(experiment, "", step=step)
```

Use `run.scope(step=step)` only where recursion cannot reach — handing a bound
scope to a plain function that is not a component.

Components with nothing to show implement nothing. `scope.track` on them
records the object as a plain value, so pass a component only where you mean
its diagnostics.

**The step is always bound and always real.** `run.track` requires `step`, and
every scope beneath inherits the one named at the root. There is no
auto-increment and no `None`: a member recorded on only some iterations would
otherwise keep its own count and claim iterations that were not its own. A
single-pass experiment still names a step, usually `step=0`.

**When it is called.** The experiment chooses a tracking cadence appropriate
to its lifecycle. Record immutable inputs or reference information once;
record changing diagnostics only at the points where they can be interpreted.
Do not add stateful "first time" checks to components to compensate for unclear
orchestration.

**Names** mirror the object tree. Renaming a member renames its subtree, two
instances of one class receive different prefixes, and a new component brings
its diagnostics with it instead of requiring edits to orchestration code.

**What to record.** What you would want to *look at* to tell whether the
component is doing its job. Do not re-emit constructor values already present
in the composed config, and do not record raw internal state when a meaningful
diagnostic would communicate more clearly.

**Keep repeated tracking proportionate.** Choose a cadence and representation
whose cost does not distort the experiment. Preserve full-fidelity results or
reusable outputs as artifacts when appropriate. Performance-driven reductions
in tracked diagnostics must not also weaken the validation used to support the
experiment's claim.

## Experiment tracking (cairn-track)

Run `cairn init` once (creates `./.cairn/`, git-ignored). Every experiment
creates a `cairn.Run`, attaches the composed config with `run.config(...)`, and
tracks into it; browse everything with `pixi run ui` (→
http://localhost:4301/).

```python
run.track(value, name="diagnostic", step=step)
run.track(value, name="diagnostic", step=step, context={"subset": "validation"})
run.track(component, name="component", step=step)  # walks its tracked subtree
```

**A reusable output that something downstream loads is an artifact, not a
result view.** Record it with `run.log_artifact(value, name)` so it stays
attached to the run that produced it rather than in a directory beside it.

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

A derived presentation of tracked results belongs under `reports/<name>/` as a
script that reads runs back and regenerates the output. Do not hand-edit a
report or use an untracked notebook state as its source.

Do **not** scaffold reports by default — tracked runs browsed via `cairn ui` are
the primary view of results. When the user asks for a report, create a
sub-folder per report under `reports/` (e.g. `reports/comparison/`) holding a
script that reads the tracked runs (`cairn.Reader`) and emits a self-contained
`report.html` next to itself — never hand-edited. Register a pixi task per
report (`report-comparison = "python reports/comparison/report.py"`).

```python
import cairn
import cairn.plot as cp

reader = cairn.Reader()
runs = reader.runs(project="<project>").list()
report = cp.Report(title="Comparison")
report.add(cp.Line({r.name: r.sequence("metric").values for r in runs}))
report.save("reports/comparison/report.html")
```

Useful components: `cp.Line`, `cp.Scatter`, `cp.Bar`, `cp.Histogram`,
`cp.Heatmap`, `cp.Image`, `cp.Compare`, `cp.Table`, `cp.Figure` (plotly
passthrough), `cp.Grid`, `cp.PointCloud`, `cp.Mesh`, `cp.Volume`.

## Documentation and handoff

**Document durable decisions, not the development process.** Add comments or
docstrings only when they preserve information that cannot be expressed clearly
by names, types, config, or structure. Explain stable constraints and
non-obvious scientific choices, not reasoning history, temporary special cases,
or predictions about future changes. Keep documentation local and concise.
When the design changes, update or remove comments that no longer describe the
code. Do not use comments to justify avoidable complexity.

**Report briefly and disclose material limitations.** The handoff states what
changed or was learned, what validation supports it, and what could still limit
or invalidate the conclusion. Distinguish smoke tests and proxies from evidence,
and disclose every approximation or deviation that could affect interpretation.
Do not provide a chronological work log or repeat details already clear from
the code and config.

## Reproducibility checklist

- [ ] `pixi.lock` committed; `.pixi/` git-ignored
- [ ] `black` in the dependencies; `pixi run format` run after every edit
- [ ] Configs in `configs/`, composed by hydra; per-run composed config saved
      (hydra's `.hydra/config.yaml`) and attached via `run.config(...)`
- [ ] Objects built from config via the registry (`type` key), including nested
      sub-objects
- [ ] Random seeds fixed in the config and recorded per run
- [ ] A registered `Experiment` is selected by config; the entry point only
      builds and invokes it, with no experiment-specific wiring or branching
- [ ] Components that have something worth seeing implement
      `__cairn_track__(self, scope)` and record through the scope
      they are handed; no base class is imposed to get this, and nothing
      outside a component decides what that component records
- [ ] Every result an experiment produces is tracked into cairn — no ad-hoc
      results directories, nothing printed or saved that cairn could show
- [ ] Reports (if any) live in `reports/<name>/`, reference the tracked runs
      via `cairn.Reader`, and are produced only by their script, never edited
      by hand
- [ ] Concept directory names checked against the stdlib (`python -c "import
      <name>"` fails for each)
- [ ] Environment facts resolved at startup and capable of changing results are
      attached with `run.config(...)`; reusable outputs are stored with
      `run.log_artifact`, not in a results directory
- [ ] Validation conditions can support the intended claim; smoke tests and
      proxies are labeled and are not presented as evidence
- [ ] Approximations that could change scientific meaning are explicit in
      config, recorded with the run, and disclosed in the handoff
- [ ] Compared runs differ only in the intended factors, or unavoidable
      differences are recorded and accounted for
- [ ] Every group config opens with a line saying which regime it is for
- [ ] A fresh clone reproduces everything with `pixi install && pixi run all`
