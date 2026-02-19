---
name: pyexp-guide
description: Explain how to structure experiments using pyexp, including the @experiment decorator, configs, sweep, merge, Runs indexing, dependencies, and result loading. Use when the user asks about pyexp, experiment structure, config sweeps, or how to use the pyexp framework.
---

# pyexp Experiment Guide

pyexp is a Python framework for reproducible experiments with config composition, parameter sweeping, DAG-based dependencies, and result caching.

## Minimal Experiment

```python
import pyexp
from pyexp import Config, sweep
from pathlib import Path

@pyexp.experiment(name="my_experiment")
def experiment(cfg: Config, out: Path):
    result_value = train(cfg.lr, cfg.width, out=out)
    return {"score": result_value}

@experiment.configs
def configs():
    base = {"name": "run", "lr": 0.01, "width": 64}
    return [base]

if __name__ == "__main__":
    experiment.run()
```

## `@pyexp.experiment` Parameters

```python
@pyexp.experiment(
    name="exp",            # Experiment name; used as output subdirectory
    output_dir="out",      # Root directory for results (default: "out")
    executor="subprocess", # "inline", "subprocess" (default), "fork", "ray"
    retry=0,               # Number of retries on failure
    stash=True,            # Capture git state before running
    hash_configs=False,    # Use config hash instead of name for directories
)
```

**Function signature** — detected by parameter count:
- `fn(cfg)` — config only
- `fn(cfg, out)` — with output directory
- `fn(cfg, out, deps)` — with dependencies (a `Runs` collection)

The return value is stored in `Result.result`.

## `@experiment.configs`

Register a function that returns the list of configs to run:

```python
@experiment.configs
def configs():
    base = {"name": "default", "lr": 0.01, "epochs": 100}

    lrs = [
        {"name": "lr1e-2", "lr": 0.01},
        {"name": "lr1e-3", "lr": 0.001},
    ]

    return sweep([base], lrs)
    # → [{"name": "default_lr1e-2", ...}, {"name": "default_lr1e-3", ...}]
```

## Config System

### `Config` — dot-notation dict

```python
cfg.optimizer.lr          # same as cfg["optimizer"]["lr"]
cfg.get("key", default)
```

Nested dicts are automatically converted to `Config` objects.

### `merge(base, update)`

Three modes for updating nested configs:

```python
# 1. Replace (default) — replaces entire sub-dict
merge({"model": {"width": 32, "depth": 2}},
      {"model": {"width": 64}})
# → {"model": {"width": 64}}  ← depth is gone

# 2. Deep merge (**prefix) — updates keys inside sub-dict, preserves others
merge({"model": {"width": 32, "depth": 2}},
      {"**model": {"width": 64}})
# → {"model": {"width": 64, "depth": 2}}

# 3. Dot notation — navigate to a nested key
merge({"model": {"width": 32, "depth": 2}},
      {"model.width": 64})
# → {"model": {"width": 64, "depth": 2}}
```

### `sweep(configs, variations) -> Runs`

Cartesian product of configs × variations. Names are joined with `_`:

```python
cfgs = [{"name": "base", "dropout": 0.1}]
sizes = [{"name": "small", "width": 32}, {"name": "large", "width": 128}]
result = sweep(cfgs, sizes)
# → [{"name": "base_small", "dropout": 0.1, "width": 32},
#    {"name": "base_large", "dropout": 0.1, "width": 128}]
```

Compose multiple sweeps for Cartesian products over many axes:

```python
cfgs = sweep([base], method_variations)
cfgs = sweep(cfgs,   dataset_variations)
cfgs = sweep(cfgs,   lr_variations)
```

### `load_config(paths)`

Load and merge YAML files. YAML files support `imports:` for composition:

```yaml
# config.yml
imports: [base.yml]
lr: 0.001
model:
  width: 64
```

## `Runs` Collection

A flat list with flexible indexing:

```python
runs[0]                           # Integer index → single item
runs["my_run"]                    # Exact name match → single item
runs["prefix.*"]                  # Regex on name → Runs or single item
runs[{"lr": 0.01}]                # Dict filter (AND) → Runs or single item
runs[{"model.width": 32}]         # Dot notation in dict filter
```

Returns a single item when exactly one entry matches, otherwise a `Runs` collection.

## Dependencies

Declare `depends_on` in a config dict to create DAG edges between experiments:

```python
stage2_cfg = {
    "name": "finetune",
    "depends_on": "^pretrain.*",  # Regex matched against other config names
    ...
}
```

The downstream experiment receives dependencies as a `Runs` in `deps`:

```python
@pyexp.experiment(name="finetune")
def experiment(cfg: Config, out: Path, deps: Runs):
    pretrain_result = deps["pretrain_run"]
    checkpoint = pretrain_result.out / "checkpoint.pt"
    ...
```

To load results from another experiment (e.g. a prior stage defined in another file):

```python
from my_module.experiment_pretrain import experiment as pretrain_exp

match = pretrain_exp[{"cfg.dataset": cfg.dataset}]
cfg.checkpoint = str(match.out / "checkpoint.pt")
```

## `Result` Dataclass

```python
@dataclass
class Result:
    cfg: Config        # Config for this run
    name: str          # cfg.name shorthand
    out: Path          # Output directory
    result: Any        # Return value from experiment function
    error: str | None  # Full traceback if execution failed
    log: str           # Captured stdout/stderr
    finished: bool     # True after execution completes
    skipped: bool      # True if a dependency failed
```

## Loading Results

```python
results = experiment.results()              # Latest batch
results = experiment.results("2026-02-17")  # Specific timestamp

# Shorthand: index directly on the experiment (uses latest results)
r  = experiment["my_run"]
rs = experiment["prefix.*"]
rs = experiment[{"cfg.lr": 0.001}]

# Iterate
for r in results:
    if r.error:
        print(r.name, "FAILED")
    else:
        print(r.name, r.result)
```

## Output Directory Structure

```
out/
  <experiment_name>/
    <run_name>/
      <timestamp>/
        config.json      # Resolved config
        config.yml
        experiment.pkl   # Pickled Result
        log.out          # Captured output
        .finished        # Marker created after completion
        .commit          # Git commit hash
    .batches/
      <timestamp>.json   # Batch manifest
    .snapshots/
      <commit_hash>/     # Git working tree snapshot
```

## CLI Usage

```bash
python my_experiment.py                        # Run all configs
python my_experiment.py --filter "^small.*"    # Regex filter
python my_experiment.py --executor fork        # Use fork executor
python my_experiment.py --continue latest      # Resume interrupted run
python my_experiment.py --list                 # List previous runs
python my_experiment.py --graph                # Print dependency graph
python my_experiment.py -s                     # Show live subprocess output
python my_experiment.py --retry 3              # Retry failed runs 3 times
```

## Executors

| Executor | Description |
|----------|-------------|
| `inline` | Same process — no isolation, fast for debugging |
| `subprocess` | Separate process via cloudpickle (default) |
| `fork` | Unix fork — fastest isolation (Linux/macOS) |
| `ray` | Ray distributed — requires `ray` installed |

## Tips

- Use `sweep()` to build Cartesian products; compose multiple calls for multi-axis sweeps.
- Use `**` prefix in variations to safely update nested dicts without overwriting sibling keys.
- Use dot-notation dict keys (`"model.width": 64`) for targeted nested updates.
- Every config needs a unique `"name"` — `sweep()` combines names automatically.
- Index directly on the experiment object (`experiment["pattern"]`) to query the latest results.
- `experiment.results()` loads from disk and is safe to call from analysis notebooks.
