# Project setup

Read this when creating a project, changing its environment, run bookkeeping,
the repo or its remote, logging evidence, publishing or pulling artifacts, running on a
cluster, or planning a parameter study.

Contents:

- pixi setup
- Cairn and `.cairn/`
- Hydra configuration and run identity
  - Snapshot source and runtime state
  - Where a run lives
- Experiment boundary: runs, inputs, and results
  - Record evidence with `add` and `add_*`
- Artifacts: datasets, models, and results
  - Lineage
  - The sample artifact
- Running on a cluster
- Parameter studies

## pixi setup

Start with:

```toml
[workspace]
channels = ["conda-forge"]
name = "<project>"
platforms = ["linux-64", "osx-arm64"]

[dependencies]
python = "3.12.*"
graphviz = "*"

[pypi-dependencies]
numpy = "*"
matplotlib = "*"
hydra-core = "*"
hydra-submitit-launcher = "*"
pyyaml = "*"
plotly = "*"
black = "*"
cairn = { git = "https://github.com/DoeringChristian/cairn.git", tag = "v0.14.0", extras = ["hydra", "video"] }

[activation.env]
PYTHONPATH = "."

[tasks]
experiment = "python experiments/run.py"
report-build = "cairn build"
report-serve = "cairn serve --host 127.0.0.1 --port 8000"
report-host = "cairn serve --host 0.0.0.0 --port 8000"
report-share = "cairn share"
publish = "cairn publish"
pull = "cairn pull"
ui = "cairn ui"
status = "cairn status"
sync = "cairn sync"
format = "black --extend-exclude '/([.]pixi|[.]cairn|data)/' ."
kuma = "bash experiments/cluster.sh kuma"    # one task per cluster the project uses
lyra = "bash experiments/cluster.sh lyra"
```

The pin is `cairn[hydra,video] @ git+https://github.com/DoeringChristian/cairn.git@v0.14.0`
in pip or uv form (the pixi `[pypi-dependencies]` entry above is the same). The
extras are `hydra` (the Hydra helpers), `video` (`add_video`), and `server` (only
on the machine that runs `cairn server`; the UI needs none). Bump the tag only
when the user asks.

pixi appends extra arguments to a task, so `pixi run publish data/x datasets/x`
runs `cairn publish data/x datasets/x`; any other `cairn` command runs as
`pixi run cairn ...`. Graphviz comes from conda-forge because it is a native
binary; the builder runs `dot -c` once if pixi skipped conda's plugin
registration. List every platform the project runs on; `linux-64` is required
for the GPU clusters (see Running on a cluster).

Commit `pixi.lock`; ignore `.pixi/`, caches, and `data/` in `.gitignore` (Cairn's
own folder `.cairn/` writes a `.gitignore` that ignores itself), and keep the
explicit Black `--extend-exclude`, because Black does not exclude `.pixi` by
itself. Every formatter, linter, type checker, and test runner must skip
environments, `.cairn/`, and generated artifacts. Do not add MLflow, W&B, TensorBoard-as-a-tracker, or a
custom run database: Cairn's repo is the project's one record.

## Cairn and `.cairn/`

Cairn is one package with these parts: the client (the `cairn` command and the
light Python API `cairn.init`/`run`/`use`/`draft`/`pull`/`publish`/`connect`), the run
and draft machinery, the Hydra helpers (`cairn.runs.hydra`), the report builder,
the server (`cairn server`, an API only), and the UI (`cairn ui`, which
explores the repo or a remote in a browser). A project is the folder that holds
its repo, `.cairn/`; `cairn init` creates it (Cairn finds it upward from the
working directory, as git finds `.git`) with a commented `.cairn/config.toml`,
the only settings file Cairn reads. Every key is optional:

```toml
# .cairn/config.toml
# [remote]                       # written by `cairn remote set`; only if the user runs a server
# url = "https://<host>/<project>"
[repo]
exclude = [".submitit/**/*.pkl"]   # gitignore-style; Slurm job pickles are never published
# [style]                        # only when the user asks (see reports.md)
```

`.cairn/` ignores itself in git, so these settings are local to the checkout,
like `.git/config`: on a fresh clone or a cluster, run `cairn init` and set
them again. Without a remote the repo works alone and offline. Add one only
when the user runs a server and names it; never invent one or send project data
to a server the user did not name:

```bash
pixi run cairn remote set https://<host>/<project>   # checks it; asks for the token if none is accepted
pixi run cairn remote                                # shows it; `cairn remote remove` drops it
```

The last path segment of the URL is the project; the server creates it on the
first sync. There is no push or pull: every write goes to the repo first and is
sent by itself (at every command, during and after a run); `pixi run sync`
(`cairn sync [--watch]`) sends now and `pixi run status` (`cairn status`) lists
what still waits. There is one token per server, without scopes. A client
takes the first of `$CAIRN_TOKEN`, `.cairn/token` (where `cairn remote set`
saves it), and `~/.config/cairn/token`. Never write the token into the
repository, configs, scripts, logs, or the handoff. Plain HTTP works with a
warning (the token travels unencrypted); use it only over a VPN or SSH tunnel.

The repo holds everything Cairn writes for the project: the metadata and file
contents, `versions/` (read-only copies that pulls return), `drafts/` (the
folders of open and kept runs and drafts), `outbox/` (versions on their way to
the remote), and `build/` (built reports). `CAIRN_DIR` moves it. `cairn drafts`
lists open and kept drafts and runs, and `cairn prune` trims the read-only
copies.

## Hydra configuration and run identity

Put every scientifically meaningful choice in config. Cairn's Hydra helpers
(`cairn.runs.hydra`, the `hydra` extra) make every Hydra job a run: its folder is
one version of `runs/<run.name>`, so the job's config, snapshot, logs, and
metrics are evidence that later results and reports read, not only something a
program wrote.

```yaml
# configs/config.yaml
defaults:
  - _self_                      # first, so each experiment config can set run.name
  - experiment: primary

seed: 0

hydra:
  callbacks:
    source_snapshot:
      _target_: cairn.runs.snapshot.SourceSnapshotCallback
      mode: git                 # git or tree
      source_root: null         # Hydra's original working directory
      capture_runtime: true
    study_completion:           # multirun only: publishes the sweep's summary run
      _target_: cairn.runs.hydra.StudyCompletion
  run:
    dir: ${cairn.run:${run.name}}     # the job folder IS the run's folder (.cairn/drafts/runs/...)
  sweep:
    dir: ${cairn.run:${run.name}}     # a sweep: one run per trial, plus a summary run
    subdir: ${hydra.job.num}
```

`${cairn.run:}` is an OmegaConf resolver that `cairn.runs.hydra` registers (the
experiment entry point imports it); naming the run in it (`${cairn.run:${run.name}}`)
only names the reserved folder. The run itself takes its name from `run.name`.
Leave `hydra.job.chdir` at its default (false): experiment code gets the run's
folder as `output_dir`, and relative paths in config keep meaning "from the
project root".

Each experiment config names its own runs:

```yaml
# configs/experiment/primary.yaml
# @package _global_
run:
  name: feasibility-method
  description: <question, purpose, and interpretation constraints>
experiment:
  _target_: experiments.<module>.<ExperimentClass>
  # every scientifically meaningful parameter of this experiment
```

Keep `_self_` first in `config.yaml` and do not define `run:` there. Hydra
merges the defaults list in order, so entries after `_self_` override
`config.yaml`; with `_self_` last, a `run:` block in `config.yaml` would
silently replace every experiment's run name and send different experiments
into the same `runs/<run-name>`.

The run version records the resolved config (`metadata.config`), the Hydra
overrides, and `.hydra/config.yaml`, `.hydra/hydra.yaml`, and
`.hydra/overrides.yaml` as files: these are the authoritative configuration
record. The version's status (`running`, `completed`, `failed`) is the one
authoritative completion record; there is no `run.json`. A run counts as
evidence only when it completed; Hydra jobs that raise end `failed` with
`logs/error.txt`. Do not duplicate the full resolved config into another
schema.

Names must be short and semantic, such as `feasibility-method`,
`reference-baseline`, or `ablation-no-feature`; the run name is also the
artifact name its results are written to (the run is `runs/<name>`, the result
draft `<name>`). Do not encode parameter lists, seeds, timestamps, or hashes in
them; Cairn rejects names outside lowercase letters, digits, and `-`. Put a
concise description in config so a report reader understands what was tested
and how to interpret it.

### Snapshot source and runtime state

Copy bundled assets by content only and make the copies owner-writable (for
example `install -m 0644 <source> <destination>`): skill directories may come
from read-only plugin caches, shared installations, or dotfiles mounts.

Every run records its own `code/` (the source snapshot), `environment/`
(`pip-freeze.txt`, `pixi.lock`), `logs/` (stdout and stderr), and `system/`
(host and CPU, memory, disk, and GPU metrics) automatically. For a Hydra job
the snapshot is Cairn's `cairn.runs.snapshot.SourceSnapshotCallback`,
registered as shown above; import it, never copy it. Each Hydra job, including
every numbered multirun trial, writes `provenance/` into its own run folder
(replacing `code/`), so a run carries its own source. The callback supports two
modes:

- `git` stores a source-only archive of the committed tree at `HEAD`, a patch
  containing staged and unstaged changes, and eligible untracked source files.
  Prefer this compact mode when the project has a commit.
- `tree` copies the current eligible source tree as ordinary files. Use it when
  Git history is unavailable or the assembled working tree is more useful.

Both modes allowlist UTF-8 text source in common languages (Python, C/C++,
CUDA, Rust, Julia, R, shell, JavaScript/TypeScript, HTML/CSS, shaders, SQL, TeX)
and project-definition formats. They respect Git ignores when available and
exclude symlinks, installed libraries, environments, caches, dependency trees,
generated reports, Cairn's folders, credential stores (`.ssh`, `.aws`, …), and
credential-like files (`.env*`, `*.pem`, `*.key`, `id_rsa*`, `credentials*`,
`secrets*`, service-account JSON, tokens). A source file over the per-file
limit, or a snapshot over the total limit, fails the job rather than leaving a
partial snapshot. Git mode counts each byte once (committed tree, untracked
copies, patch). Files skipped as non-UTF-8 are listed in the snapshot manifest.
Extend the deny rules for project-specific data or secrets.

With `capture_runtime: true`, `provenance/environment/` also contains
`pip-freeze.txt` (read from installed package metadata, so `pip` is not
required), Python and platform facts, a small allowlist of execution
environment settings, Git status, and an exact copy of `pixi.lock` when present.
Do not dump the complete process environment or copy `.pixi`; inventories and
the lock file describe installed packages without duplicating libraries or
exposing unrelated secrets. The callback runs before experiment code, so a
later experimental failure still retains its initial source and runtime state.

### Where a run lives

The job folder of a run is `.cairn/drafts/runs/<name>/<uid>/` while it runs; when
it ends Cairn publishes it as `runs/<name>@vN` (label: the start time) and
removes the folder, so look at a run with `cairn show runs/<name>@latest`, the
UI, or `cairn pull runs/<name>@vN`. A failed run keeps its folder for diagnosis
(`cairn drafts` lists it); do not publish it as a good version. `latest` is an
alias that only ever points at a completed version, so `runs/<name>@latest` and
`<name>@latest` are safe to resolve. Pin an exact version (`@v3`) when a finding
cites it.

A job that cannot use `${cairn.run:}` (for example one with its own
`hydra.run.dir`) still becomes a run, with a folder of its own; Cairn then
writes a `run.json` into the job folder and keeps a `latest` symlink. Prefer
the resolver.

## Experiment boundary: runs, inputs, and results

```python
# experiments/base.py
from abc import ABC, abstractmethod
from pathlib import Path


class Experiment(ABC):
    @abstractmethod
    def run(self, output_dir: Path) -> None:
        """Execute the experiment: use its inputs, add metrics, and write its results."""
```

Copy [`assets/run.py`](../assets/run.py) into the project as
`experiments/run.py`; it is the entry point, a few lines around Cairn's
`run_experiment(cfg, Experiment)` from `cairn.runs.hydra`. That function starts
the run with `cairn.init(name=cfg.run.name, config=<the resolved config>, ...)`,
requires the source snapshot (Hydra reports callback errors only as warnings, so
this is what makes a snapshot failure fail the run), instantiates the configured
`Experiment`, calls `run(output_dir)` with the run's folder, and finishes the run
(failed, with the traceback, when the experiment raises). It validates run names
and knows nothing experiment-specific; put project logic in `Experiment`
subclasses. Import it, never copy or patch it. A plain script (no Hydra) is a
run too: `cairn.init(name=..., config=...)` at the top.

An experiment uses its inputs, adds metrics, and writes its results through
the Python API:

```python
import cairn


class Primary(Experiment):
    def run(self, output_dir: Path) -> None:
        data = cairn.use(self.data_ref)                    # an input of the run: "datasets/crops@v3", exact version recorded
        crops = data.path                                  # read-only local files
        for step in range(self.steps):
            ...
            cairn.run.add({"loss": loss, "step": step})    # the current run's metrics.jsonl, from anywhere
        with cairn.draft("feasibility-method") as result:  # the result artifact: feasibility-method@vN
            result.add_json("scores", scores, {"split": "test"})
            result.add_table("cases", rows)
            result.add_figure("error_histogram", error_histogram, None, errors)
            result.add({"rmse": rmse})                     # scalars the report reads with read_scalars
```

- **`cairn.init(name=, config=)`** makes the process a version of `runs/<name>`
  that records code, environment, logs, and system metrics by itself; there is no
  `run.json`. Without the call, the first `cairn.use`, `cairn.pull`, or
  `cairn.draft` starts a run (named after the script), and a later
  `cairn.init(config=...)` adds the config to it. After that, `cairn.run` is the
  process's run from anywhere (`cairn.run.add({...})`, `cairn.run.add_*`); there
  is no run object to pass around. A non-zero exit, an uncaught exception, or
  SIGTERM marks the run failed.
- **`cairn.use("<ref>")`** records the exact version as an input of the run and
  returns the `Version` (`.path` is a read-only local copy; `.ref` the exact
  reference). Pin exact versions (`@v3`) in configs for evidence a report will
  cite; an alias is resolved at use time and the exact version is recorded
  either way. `cairn.pull(ref)` does the same and returns the path.
- **`cairn.draft("<name>")`** is a fresh folder Cairn manages; at the end of the
  `with` block it becomes `<name>@vN` with the run as its single input. An
  exception keeps the folder and publishes nothing.

### Record evidence with `add` and `add_*`

The run (`cairn.run.add`, `cairn.run.add_*`) and every draft share one writer, so write
evidence of the supported kinds through it rather than hand-rolled writers.
Import Cairn's; never reimplement it. Every `add_*` takes an optional `metadata`
dict for that item:

```python
w.add({"loss": loss, "psnr": psnr, "step": step})   # metrics.jsonl: any keys, `step` is just a key
w.add_figure("error_histogram", error_histogram, {"step": 3}, errors)   # figures/*.png; pass the plot function and its args
w.add_plotly("running_rmse", spec)                  # figures/*.plotly.json
w.add_image("reconstruction", array)                # images/*.png
w.add_video("optimization", frames, None, fps=30)   # videos/*.mp4; T×H×W[×C] frames or a file; needs the video extra
w.add_table("trials", rows)                         # tables/*.csv, tidy
w.add_json("per_class", scores)                     # data/*.json
w.add_text("solver", solver_log)                    # text/*.txt
w.add_file("checkpoints/best.pt")                   # files/best.pt (models, archives)
w.add_dir("checkpoints/", "ckpt")                   # files/ckpt/...
```

Both index files are append-only JSON Lines; nothing already written is
rewritten:

```text
<run or draft>/
├── metrics.jsonl          # w.add({...}): one entry per call, with time and origin
├── artifacts.jsonl        # one entry per add_* file: name, kind, path, time, origin, metadata
├── figures/ images/ videos/ tables/ data/ text/ files/
└── (runs only) code/ environment/ logs/ system/, and .hydra/ provenance/ for Hydra jobs
```

Readers fold the logs: `read_scalars(folder)` gives the latest value of every
key of `metrics.jsonl`, `read_series(folder, key)` every value with its step and
time, and the latest `artifacts.jsonl` line per path describes a file. Each
entry records its `origin` (file, line, function that called the writer);
with the run's snapshot this traces every figure to exact code. Names are
lowercase slugs, file writes are atomic, and non-finite numbers are kept as
`null`.

The writer fixes *where* evidence lives and records *which code* wrote it; it
imposes no result schema. Keep names, columns, and units stable when
experiments should share report views. Evidence the writer cannot express goes
into `add_file`, documented in the experiment's docstring, so it is still
indexed. Never hide important evidence through final-only output, excessive
aggregation, cherry-picked examples, or presentation-only composites. Put the
loss curve and other per-step series in the **run** (`cairn.run.add`); put the
results a report cites in the **result draft**.

## Artifacts: datasets, models, and results

The repo holds **artifacts**: named, versioned folders of the project. A name
is a slash path (`feasibility-method`, `datasets/crops`, `models/denoiser`,
`runs/feasibility-method`); reports are the artifacts `reports/<slug>`. A
completed version is immutable; publishing an unchanged folder creates no new
version. References are `name[@vN|@alias|@label|@<short id>][//file]`, with no
project prefix; every version also has a short id (7 hex digits, shown by
`cairn versions` and `cairn show`), and `cairn show <id>` finds it. `latest`
moves by itself to the newest completed version, other aliases (`best`, `paper`)
are set by hand (`cairn alias <ref> <alias>`). Runs and result drafts become
artifacts automatically; datasets and other existing folders you publish:

```bash
pixi run publish data/crops datasets/crops               # a dataset (models the same way: models/<name>)
pixi run publish data/crops datasets/crops --alias paper # and point an alias at it
pixi run cairn versions <name>                           # number, short id, status, label, created, size
pixi run cairn show <name>@latest                        # metadata, files, inputs, run, consumers
pixi run pull datasets/crops@v3                          # print a read-only local copy's path
```

Do not publish experiment outputs by hand: a folder published with
`cairn publish` has no run behind it. Whatever an experiment produces goes
through `cairn.draft` (or, for per-step series, `cairn.run.add`) so that it carries
its run. `cairn publish <folder> <name> --watch -- <command>` exists for
following a job that is not a Cairn run; it is not the experiment flow.

### Lineage

A run's inputs are every version the process used (`cairn.use`, `cairn.pull`,
also in plain subprocesses via `$CAIRN_INPUTS`). Every draft it publishes has
exactly one input, the run. So the repo records
`datasets/crops@v3 -> runs/train@v7 -> models/student@v2`, and a report version
lists the artifacts it read, so the chain dataset → run → result → report is
recorded without any extra code (`cairn show`, the UI's lineage graph, `cairn.lineage(ref)`). A multirun sweep is one run per trial plus a summary run whose inputs
are the trial runs.

### The sample artifact

The skill's sample report reads one artifact, `sample-run`, made from
[`assets/sample-run/`](../assets/sample-run/) (a folder in the writer's layout:
`metrics.jsonl`, `tables/`, `figures/`). It stands in for a result; during
setup, publish it once so the sample report builds:

```bash
pixi run publish <skill-directory>/assets/sample-run sample-run
```

The sample report declares it as `run: sample-run@latest`. When the sample
report is replaced, the artifact may stay in the repo, but no project
report may declare it.

## Running on a cluster

Every project is ready for the Slurm GPU clusters (EPFL's Kuma and Lyra) from
the start, through the `slurm` skill and the cluster's own skill (`kuma`,
`lyra`). Load both before the first cluster command in a session and set the
project up by the `slurm` skill's "Set up a project": copy its `cluster.sh` and
`finalize_study.py` to `experiments/`, each cluster's profile to
`experiments/clusters/`, and its launcher configs to `configs/hydra/launcher/`,
and keep `hydra-submitit-launcher`, `linux-64`, and one task per cluster in
`pixi.toml` (see pixi setup). The `experiment` task is the entry point they run.
The `slurm` skill holds the commands and the **mandatory GPU-efficiency gate**;
the cluster's skill holds its partitions, CUDA version, and storage rules.
Clusters bill every allocated GPU-hour whether or not it is used.

Nothing in the run record changes on a cluster: runs, snapshots, `latest`,
and `StudyCompletion` behave exactly as for local runs, and every trial is a
Slurm job and its own run. Where the slurm and cluster skills speak of
`outputs/`, this project's run folders live in `.cairn/drafts/` (the same
storage rules apply to `.cairn/`). When a launcher died, complete the study once
its trials have left the queue with `pixi run cairn finalize-study <sweep
folder>` on the cluster (the folder `cairn drafts` lists for the sweep; the same
rule as `StudyCompletion`). Commit before submitting runs a report will cite;
uncommitted changes are recorded as a patch.

**Getting cluster runs out.** The project lives on the cluster's persistent
project filesystem, and so does its `.cairn/`. That is a network filesystem
(NFS, Lustre, GPFS), where a repo has no database: Cairn refuses it without a
remote, so a cluster project needs the user's server:

- **One server on a machine with a local disk.** The user runs `cairn
  server` (which also starts the UI) on a workstation or service host, never on
  a compute node or with its repo on a shared filesystem, behind HTTPS or a VPN.
  It serves each project at `<server>/<project>`, prints its token and the
  `cairn remote set ...` line for other machines, and moves to the next free
  port when its port is taken (use the port it prints).
- **The project names it.** On the cluster, `cairn init` and `cairn remote set
  https://<host>/<project>` in the project folder; the token goes to
  `.cairn/token` (asked for by `cairn remote set`) or `~/.config/cairn/token`,
  put there by the user, never in files, configs, or job scripts in the
  repository.
- **Jobs write the outbox.** A job keeps each version it makes (its run, its
  drafts) in its own outbox entry in `.cairn/outbox/` and sends it when it can
  reach the server (a run is synced while it runs, so the UI shows it live).
  What a job could not send waits there; `pixi run cairn sync --watch` on the
  login node sends it as jobs leave it, and `cairn status` there shows anything
  still waiting, from which host, and why.

`[repo] allow_network_fs = true` (the owner's word that one process on one host
is the repo's only writer) is the exception, not the setup for jobs. Reports
are always built where they are written, from the repo, never on the server.

## Parameter studies

Only after feasibility, study parameters systematically. Declare the parameter
space, seeds, budget, objective, and its direction in config. Two forms are
supported, and both must keep every configuration's result inspectable:

- **Hydra multirun** (`python experiments/run.py -m key=a,b,c`) when the
  configurations are separate experiments to compare or select from: sweeps,
  ablations, or competing settings. With `hydra.sweep.dir: ${cairn.run:}` each
  trial is a complete run of its own (`runs/<run-name>@vN`, labelled
  `<sweep>/<n>`, with provenance and logs), and `StudyCompletion` publishes a
  summary run whose inputs are the trial runs and whose files list them
  (`trials.jsonl`). When a single report compares the trials, collect them in
  one artifact: override `hydra.sweep.dir='${cairn.draft:<name>}'` (and
  `hydra.run.dir` for a single job) so the sweep folder is an output draft, the
  experiment writes its results with `cairn.current_draft()` (the same `add_*`
  writer) instead of opening its own draft, and `StudyCompletion` publishes it as
  `<name>@vN` with the trial runs as inputs. A report reads the trials from it
  (`inputs.<name> / "<n>"`, each with its results and `.hydra/overrides.yaml`);
  trials that did not complete keep the study from being published, so failures
  stay visible.
- **An in-run grid** when the configurations are evaluation conditions of one
  experiment, such as noise levels or contamination rates applied to the same
  methods. Declare the grid in the experiment config, log one table row per
  cell (`add_table`), and report results per cell, not only aggregates.

Choose the form by what the configurations are, not by convenience, and never
hide failed trials or cells. Use a finite grid for intentional comparisons,
random search for bounded exploration, and a Hydra sweeper plugin only when
adaptive search is justified. Do not add a tracking service to run a sweep.

**Size studies to the decision.** Start coarse: few seeds and cells to find
where the answer is clear and where it is not, then add seeds only for the
cells the decision depends on. Record each project's runtime budget (for
example the longest acceptable single run, set with the user, in the report's
Methods). When runs repeatedly exceed it, stop scaling and spend time on
performance first: profile, then vectorize, cache shared work, or run trials in
parallel through a Hydra launcher (on a cluster: `pixi run <cluster> submit`,
after the `slurm` skill's GPU-efficiency gate). Keep optimized code verified
against the slower reference implementation.
