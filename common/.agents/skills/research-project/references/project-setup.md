# Project setup

Read this when creating a project, changing its environment, run bookkeeping,
the repo or server, logging evidence, publishing or downloading artifacts,
running on a cluster, or planning a parameter study.

## pixi setup

Start with this template, replacing `<project>` consistently with the project's
namespace in the workspace, tasks, and Hydra config:

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
cairn2 = { git = "https://github.com/DoeringChristian/cairn2.git", tag = "v0.1.0", extras = ["reports", "media", "ui"] }

[tasks]
experiment = "python experiments/run.py"
evidence = "python experiments/research_cairn.py check-artifact --project <project>"
finalize-study = "python experiments/research_cairn.py finalize-study"
report-build = "python experiments/report_tasks.py --project <project> build"
report-serve = "python experiments/report_tasks.py --project <project> serve"
report-publish = "python experiments/report_tasks.py --project <project> publish"
report-share = "python experiments/report_tasks.py --project <project> share"
ui = "cairn server"
sync = "cairn sync"
format = "black --extend-exclude '/([.]pixi|[.]cairn|data|outputs|artifacts)/' ."
kuma = "bash experiments/cluster.sh kuma"
lyra = "bash experiments/cluster.sh lyra"
```

The pin is `cairn2[reports,media,ui] @ git+https://github.com/DoeringChristian/cairn2.git@v0.1.0`
in pip or uv form. The import and command remain `cairn`. Hydra stays a separate
dependency. `reports` supplies notebook execution; `media` supplies arrays,
tables and figures; `ui` supplies the server dependencies for the bundled React UI.
Deployment extras are `postgres` and `s3`; `server` provides the API dependencies
without the UI session dependency. Bump the tag only when the user asks.

Copy `assets/report_tasks.py` into `experiments/` alongside the run adapter.
This small project helper discovers flat reports, calls the public builder,
and maintains the last successful previews. It does not copy or patch Cairn.
Pixi appends extra arguments: `pixi run report-publish direction` builds and
publishes that direction. `report-share direction --out .cairn/share/direction`
exports the unchanged complete report bundle into a new directory.

Graphviz comes from conda-forge because it is a native binary; ensure `dot`
works before generating diagrams. List every platform the project runs on;
`linux-64` is required for GPU clusters.

Commit `pixi.lock`; ignore `.pixi/`, `.cairn/`, `outputs/`, `artifacts/`,
caches, and `data/`. Keep the explicit Black `--extend-exclude`: every
formatter, linter, type checker, and test runner must skip environments and
generated artifacts. Do not add MLflow, W&B, TensorBoard-as-a-tracker, or a
custom run database: Cairn's selected backend is the project's one record.

## Cairn destinations and credentials

Choose **one destination**: a local repository or the user's named remote
server. A `cairn.Client(destination, project=...)` owns the connection; the
project namespace is separate. Runs and results share one artifact lifecycle.

```bash
export CAIRN_REPO="$PWD/.cairn/repo"
pixi run ui                         # API + UI, default http://127.0.0.1:8000
```

The repository is created on first access. `cairn init NAME` starts a run;
it is not a repository-initialization command. `Client()` selects an explicit
destination first, then `CAIRN_URL` or `CAIRN_REPO`, then the nearest ancestor
`.cairn` config/directory (using its `repo/` subdirectory), then a local `.cairn/repo`. Keep an explicit environment
setting shared by experiments and report tasks. The adapter accepts
`cairn: {repo: ...}` or `cairn: {server: ...}`, never both; those are adapter
settings translated to the public `destination` argument.

Use a server only when the user runs one and names it; never invent a server
or upload project data to an unrequested destination:

```bash
export CAIRN_REPO="https://<user-named-host>"
export CAIRN_TOKEN_FILE="/private/path/to/existing-token"
```

There is no `cairn login` command. Authentication resolves `CAIRN_TOKEN`,
`CAIRN_TOKEN_FILE`, project `.cairn/token` or config, and
`~/.config/cairn/token`. Prefer a protected token file, never a token in
tracked config, commands, logs, or handoffs. Use HTTPS, a VPN, or an SSH tunnel.

For a user-authorized host, `cairn --repo <local-path> server --host <host>
--port 8000` starts API and UI; the server creates a private token file when
needed and prints an immediate login link. Browser authentication lasts 12 hours.
Give the ordinary URL in handoffs. `--no-ui` disables UI hosting;
`--no-auth` is for explicitly selected development access. To view a remote
destination, open that server's UI; `cairn server` hosts a local backend,
not a loopback proxy to another server.

Remote writes use a durable outbox under
`$XDG_STATE_HOME/cairn/outbox/<destination-hash>` (default
`~/.local/state/cairn/outbox/...`), or an explicit `Client(outbox=...)`.
This is a retry journal, not a second queryable repository. Preserve it until
the selected server acknowledges completion. `cairn sync` retries delivery;
`Client.recover()` recovers writers. Do not assume old `CAIRN_DIR`,
`CAIRN_CACHE_DIR`, `CAIRN_SERVER`, `sync --clean`, or run-folder APIs.
A disconnected finish raises Pending; it does not prove completed evidence.

## Hydra configuration and run identity

Put every scientifically meaningful choice in config. Copy
[`assets/run.py`](../assets/run.py) and
[`assets/research_cairn.py`](../assets/research_cairn.py) into `experiments/`.
The first is the entry point; the second supplies focused provenance,
completed-evidence, and study helpers using public Cairn APIs.

```yaml
# configs/config.yaml
defaults:
  - _self_                      # first, so each experiment config can set run.name
  - experiment: primary

project: <project>
seed: 0
cairn: {}                       # normal environment/config resolution; never put a token here
provenance:
  max_file_bytes: 1048576
  max_total_bytes: 33554432
  exclude: []                   # add project-specific data/secret exclusions

hydra:
  job:
    chdir: false
  run:
    dir: outputs/${run.name}/${now:%Y-%m-%d_%H-%M-%S}
  sweep:
    dir: outputs/${run.name}/study-${now:%Y-%m-%d_%H-%M-%S}
    subdir: ${hydra.job.num}
```

These are ordinary staging directories. Do not use the removed
`${cairn.run:}` or `${cairn.draft:}` resolvers or the old Cairn Hydra callbacks.
Leave `hydra.job.chdir: false`: experiment code gets the job's folder as
`output_dir`, and relative paths in config keep meaning "from the project
root". Each job gets its own full Cairn run ID, even when names repeat.

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
silently replace every experiment's run name and mix different experiments
under one name.

The entry point records the resolved config in run metadata, and the initial
provenance capture carries Hydra's config and override files. The backend
run status is the authoritative completion record. A run counts as evidence
only when it completed and its scientific validation passed; a job that raises
is failed. Do not duplicate the full resolved config into another status schema.

Names must be short and semantic, such as `feasibility-method`,
`reference-baseline`, or `ablation-no-feature`. Use the same semantic name for
the result artifact when appropriate. Do not encode parameter lists, seeds,
timestamps, or hashes in them; keep lowercase letters, digits, and hyphens as
the project's naming convention. Put a concise description in config so a
report reader understands what was tested and how to interpret it.

### Snapshot source and runtime state

Copy bundled assets by content only and make the copies owner-writable (for
example `install -m 0644 <source> <destination>`): skill directories may come
from read-only plugin caches, shared installations, or dotfiles mounts.

The adapter captures the current eligible source tree and runtime state
synchronously before constructing the Experiment. It requires `pixi.lock`,
includes the resolved config and Hydra files, and records the capture as the
run’s named `provenance` directory capture. A missing required file or a
source/total size limit violation fails the run before experiment work. This
strict project capture is separate from Cairn's optional, best-effort source
capture; do not claim the automatic capture guarantees a complete snapshot.

The helper allowlists text source and project-definition files, respects Git
ignores, and excludes symlinks, installed libraries, environments, caches,
dependency trees, generated reports, Cairn's folders, credential stores
(`.ssh`, `.aws`, …), and credential-like files (`.env*`, `*.pem`, `*.key`,
`id_rsa*`, `credentials*`, `secrets*`, service-account JSON, tokens). Inspect
its manifest and extend the deny rules for project-specific data or secrets.
Files skipped as non-UTF-8 are listed in the manifest. The capture is of the
current source tree, not the old git/tree callback or a full repository clone.

Runtime provenance includes the exact `pixi.lock`, an inventory from installed
package metadata (so `pip` is not required), Python/platform facts, Git revision,
and a small allowlist of execution settings. Do not dump the complete process
environment or copy `.pixi`; inventories and the lock file describe installed
packages without duplicating libraries or exposing unrelated secrets. Initial
provenance is recorded before experiment code, so a later experimental failure
still retains its initial source and runtime state. Record stdout/log files and system metrics explicitly when needed; this release
does not intercept them automatically.

### Where a run lives

`outputs/` holds Hydra configs, staging files, and a `cairn-run.json` pointer
with the full run ID. It is not the authoritative evidence/status store.
Inspect the backend with `pixi run cairn --project <project> artifact list --namespace runs`,
`pixi run cairn --project <project> artifact inspect <full-run-id>`, or the UI. Keep failed job folders for
diagnosis; publish scientific results only from completed, validated producers.

A finished artifact can have a failed outcome, and `latest` is a movable alias.
The adapter publishes result artifacts only after their producer completes. A successful
log call is not a successful experiment. Use the completed-evidence check below
and pin `@vN` before citing a result. Do not infer completion from a folder,
alias, or local pointer file.

## Experiment boundary: runs, inputs, and results

Define the ordinary project interface:

```python
from abc import ABC, abstractmethod
from pathlib import Path
from cairn import Artifact

class Experiment(ABC):
    @abstractmethod
    def run(self, run: Artifact, output_dir: Path) -> None:
        """Use declared inputs, record metrics, validate, and stage result files."""
```

The Hydra entry point opens a `Client`, starts `client.run(...)`, captures
strict initial provenance, instantiates the configured Experiment, and calls
it inside the artifact context. Normal exit finishes with outcome `completed`;
exceptions finish with `failed`. The run itself is an artifact in `runs`.
There is no separate Run entity or mutable version identity. Context exit calls
`finish()` with default arguments: when finishing with a custom value or
outcome, call `finish(...)` explicitly outside an artifact context to avoid
a conflicting second finalization.

Within an experiment:

```python
import json
import matplotlib.pyplot as plt
import cairn

data = run.use("datasets/crops@v3")        # records the exact input ID
data.download(to=output_dir / "inputs" / "crops")
for step in range(self.steps):
    # ... perform the method and compute loss ...
    run.log(loss=loss, step=step)

# ... scientifically validate scores, cases, and errors ...
result = output_dir / "result"
result.mkdir(parents=True, exist_ok=True)
(result / "scores.json").write_text(json.dumps(scores, allow_nan=False))
figure = error_histogram(errors)
figure.savefig(result / "error_histogram.png")
run.track(cairn.Figure(figure), key="error_histogram")
plt.close(figure)
```

Keep complete tables, checkpoints, and figures under `output_dir/result/`.
After the experiment returns, the adapter captures that directory on the run.
Only after the run is confirmed completed does it publish `artifacts/<run-name>`
from those captured bytes, with a `producer` dependency pointing to the run.
The receipt `cairn-result.json` gives its ID and exact `@vN` reference.
A failed run does not create a result through this adapter. A manual script
can follow the same order with `publish_result(client, producer)`.
A new or unfinished run cannot be an immutable input: finish before `use`.

### Record evidence with the public API

```python
run.log({"loss": loss, "psnr": psnr}, step=step)
run.track(cairn.Figure(plotly_figure), {"step": step}, key="running_rmse")
run.track(cairn.Image(array), {"step": step}, key="reconstruction")
run.track(cairn.Table([{"condition": c, "rmse": r} for c, r in rows]), key="trials")
run.track({"solver_log": solver_log})
run.capture("checkpoints/best.pt", name="best-checkpoint")
run.capture("optimization.mp4", name="optimization")
```

`track` uses `key=`, not `name=`; metadata such as step goes in its second
argument. Audio/video/text can be captured as files; there are no `Video`,
`Audio`, or `Text` wrapper classes in this release. Typed values select
interpretation; ordinary dictionaries/lists are JSON, never implicit pickle.
Preserve complete scientific tables and arrays, not just presentation subsets.

Run records retain repeated steps. Read `client.resolve(run_id).records()`;
each row contains `data`, including metrics and optional `step`. Config is
`reader.descriptor["manifest"]["metadata"]["config"]`; named captures live
in `manifest.captures`. There are no implicit `metrics.jsonl` or
`summary.json` snapshot folders. Record logs explicitly with records or named
file captures; do not assume automatic stdout/system-metric interception.

Use stable file names, columns, and units across experiments. Record the
generating module/function and material plotting settings beside each figure
or in run metadata; strict provenance pins the generating source. Never hide
important evidence through final-only output, excessive aggregation,
cherry-picked examples, or presentation-only composites. Keep per-step series
in the run and results a report cites in its result artifact.

## Artifacts: datasets, models, and results

References are `namespace/name@vN`, `namespace/name@alias`, or full plain
artifact IDs, resolved inside the selected project. Names may contain slashes.
Use full IDs for cross-project inputs and exact `@vN` references or IDs for
reviewed evidence. A run keeps its ID when it finishes and receives a version
label like any other artifact. There are no `artifact:`/`run:` prefixes,
separate revision IDs, or snapshot-digest suffixes.

Finished content is immutable. Mutable `annotations` hold tags, titles or
review status; they do not change captured evidence. `latest` is a movable
alias, not evidence of successful validation. Check outcomes and producers.

Import datasets with documented source/license/validation:

```python
from cairn import Client, Directory
with Client(project="<project>") as client:
    dataset = client.start("datasets", "crops")
    dataset.finish(
        value=Directory("data/crops"),
        metadata={"origin": "<source>", "validation": "<checks>"},
    )
    print(dataset.id)
```

```bash
pixi run cairn --project <project> artifact list
pixi run cairn --project <project> artifact versions datasets/crops@latest
pixi run cairn --project <project> artifact inspect datasets/crops@v1
```

Download with `client.resolve(ref).download(to="artifacts/crops-v1")`.
Do not manually publish experiment outputs as runless imports: results must
carry a `producer` dependency on their completed run. Import external file
URIs as real bytes before reports consume them.

### Completed evidence and lineage

`pixi run evidence artifacts/<result>@vN` calls
`require_completed_artifact(client, ref)`: require a finished completed result,
exactly one completed producing run in the same project, or a completed run
when the input itself is in `runs`. This is lifecycle validation, not proof
of scientific validity. Runless datasets/sample fixtures require documented
origin/validation and intentionally do not pass the scientific-results gate.

Use `run.use(ref)` for exact input dependencies, `result.use(run.id,
role="producer")` after run completion, and `summary.use(trial.id, role="trial")`
for studies. The UI shows dataset → run → result → report lineage.
The report builder pins exact finished IDs, including failed outcomes; the
project's completed-evidence policy is intentionally stricter.

### The sample artifact

The bundled sample is synthetic demonstration evidence, not an experimental
result. Import it into the selected project:

```python
from cairn import Client, Directory
with Client(project="<project>") as client:
    sample = client.start("datasets", "sample-run")
    sample.finish(value=Directory("<skill-directory>/assets/sample-run"),
                  metadata={"origin": "research-project skill sample", "synthetic": True})
    print(sample.id)
```

Copy `assets/reports/direction/` into `reports/direction/`. Its
`cairn.inputs.result: datasets/sample-run@v1` assumes the first import;
otherwise use the exact ID printed above. Build it as a scaffold smoke test.
Then replace its content and input with the project's own. The sample may
remain stored, but no real project report may still declare it.

## Running on a cluster

Projects use the `slurm` skill and the cluster's own skill (`kuma`, `lyra`)
for EPFL's Slurm GPU clusters. Load both before the first cluster command in a
session. Keep `hydra-submitit-launcher`, `linux-64`, and one task per used
cluster in `pixi.toml`; the `experiment` task remains the entry point. Copy
the scheduler script, cluster profiles, and launcher configs according to
those skills, then check their tracking glue against this version before
submission. Use this skill's `finalize-study` helper for Cairn study evidence.

The `slurm` skill holds the commands and the **mandatory GPU-efficiency gate**;
the cluster's skill holds its partitions, CUDA version, and storage rules.
Clusters bill every allocated GPU-hour whether or not it is used.

The lab's own GPU workstations (fermat, kerr, gabor, arago) form a HyperQueue
cluster with no billing and no shared filesystem: the `hyperqueue` skill
supplies `pixi run hq ...` and a Hydra launcher in `hydra_plugins/`. Each
checkout must target the same user-authorized Cairn server/project, with its
own durable journal and protected credentials.

**Legacy adapter compatibility is not automatic.** Existing Slurm assets may
still use `cairn-report push` and folder `run.json` completion; HyperQueue
assets may still use old Cairn distribution/extras, `remote set`,
`${cairn.run:}`, or `finalize-study`. Those calls do not work with Cairn2 0.1.0.
Preserve their scheduling, storage, and GPU-efficiency rules, but adapt and
test the project's tracking glue with the current public helper/commands
before submitting work. Do not silently edit the adjacent skills or claim
that copying their old files produces a working integration.

Each cluster trial uses the same run/provenance/completed-evidence contract as
a local job, with its own `outputs/` staging folder. When a launcher dies,
confirm its jobs have left the queue, sync their journals, and explicitly
finalize the saved expected roster. Missing or non-completed trials prevent
a successful summary. Commit before submitting runs a report will cite;
initial provenance records the actual source and Git state.

**Getting cluster runs out.** Keep the project's source and recoverable
journals on storage permitted by the cluster skill. Use an explicit remote
server for shared/network project filesystems; do not place a multi-host
SQLite repository there:

- **One server on a machine with a local disk.** The user runs `cairn --repo <path> server` on a workstation or service host, never on a compute node or
  with its local repository on a shared filesystem, behind HTTPS or a VPN.
  Use its actual configured port; the project is a separate namespace.
- **The project names it.** Configure `CAIRN_URL` or `CAIRN_REPO` as the
  server URL and authenticate with a protected token file.
  Never put credentials in tracked configs or job scripts.
- **Jobs retain durable journals.** Each job's uploader retries automatically.
  Preserve the destination-specific outbox under `$XDG_STATE_HOME/cairn/outbox/`
  until confirmed; `pixi run cairn sync` retries on a host that can reach the
  server, using the same recovered outbox location. Verify the finished backend runs and exact artifacts before building
  or publishing evidence. A node-local scratch journal must be recovered
  before the allocation deletes it.

Build reports locally in the locked project environment; the server does not execute report cells. The evidence destination
does not move report sources or local preview files.

## Parameter studies

Only after feasibility, study parameters systematically. Declare the parameter
space, seeds, budget, objective, and its direction in config. Two forms are
supported, and both must keep every configuration's result inspectable:

- **Hydra multirun** (`python experiments/run.py -m key=a,b,c`) when the
  configurations are separate experiments to compare or select from: sweeps,
  ablations, or competing settings. Each trial is a complete Cairn run with
  its own provenance, config, logs, and result artifacts. Save the expected
  trial roster when launching; fill in the full run IDs from each job's
  `cairn-run.json`. Do not infer the expected roster from only successful jobs.
  Finalize explicitly with the helper below; no automatic study callback is
  assumed. A report declares the exact trial results and/or the summary
  artifact. Failures stay visible and prevent a completed study summary.
- **An in-run grid** when the configurations are evaluation conditions of one
  experiment, such as noise levels or contamination rates applied to the same
  methods. Declare the grid in the experiment config, log one table row per
  cell (a complete CSV/JSON artifact), and report results per cell, not only aggregates.

For example, a roster for two planned trials is:

```json
{
  "project": "<project>",
  "name": "learning-rate-study",
  "expected_trials": ["0", "1"],
  "runs": {"0": "<full-run-id-0>", "1": "<full-run-id-1>"}
}
```

Run `pixi run finalize-study outputs/<study>/roster.json` against the selected
backend (or pass `--repo <path>` / `--server <url>`). Missing or extra trials,
duplicate run IDs, and non-completed backend runs fail the check. After the
scientific validation passes, the helper creates a summary run, records each
trial with `use(..., role="trial")`, and logs `<name>-study` with the roster and status table.
Run from the project root or pass `--project-root <path>` so the summary's
initial provenance captures the intended project and `pixi.lock`.
Keep the original expected roster and inspect every result, including failures;
do not relabel a partial study as complete by deleting unsuccessful trials.

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
