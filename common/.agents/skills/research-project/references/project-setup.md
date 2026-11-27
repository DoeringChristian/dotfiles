# Project setup

Read this when creating a project, changing its environment, run bookkeeping,
the repo or server, logging evidence, publishing or downloading artifacts,
running on a cluster, or planning a parameter study.

Contents: environment; repository; Hydra entry points; stage handoffs; logging;
datasets and storage; evidence validation; cluster execution; parameter studies.

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

[pypi-dependencies]
numpy = "*"
matplotlib = "*"
hydra-core = "*"
hydra-submitit-launcher = "*"
pyyaml = "*"
plotly = "*"
black = "*"
cairn2 = { git = "https://github.com/DoeringChristian/cairn2.git", tag = "v0.18.0", extras = ["media", "ui"] }

[tasks]
experiment = "python experiments/run.py"
evidence = "python experiments/research_cairn.py check-artifact --project <project>"
finalize-study = "python experiments/research_cairn.py finalize-study"
ui = "cairn-ui"
format = "black --extend-exclude '/([.]pixi|[.]cairn|data|outputs|artifacts)/' ."
kuma = "bash experiments/cluster.sh kuma"
lyra = "bash experiments/cluster.sh lyra"
```

The pin is `cairn2[media,ui] @ git+https://github.com/DoeringChristian/cairn2.git@v0.18.0`
in pip or uv form. It installs the import and command `cairn` and the command
`cairn-ui`. Hydra stays a separate dependency. `media` supplies images, arrays,
and figures; `ui` supplies `cairn-ui`; `server` supplies `cairn server`; `all` is
all three. Logging alone needs no extra, so the environment of a compute job can
leave `ui` out.
Bump the tag only when the user asks.

Keep only tasks whose scripts exist and features the project uses. The cluster
tasks and launcher dependency are examples, not requirements for local work.

List every platform the project runs on;
`linux-64` is required for GPU clusters.

Commit `pixi.lock`; ignore `.pixi/`, `.cairn/`, `outputs/`, `artifacts/`,
caches, and `data/`. Keep the explicit Black `--extend-exclude`: every
formatter, linter, type checker, and test runner must skip environments and
generated artifacts. Do not add MLflow, W&B, TensorBoard-as-a-tracker, or a
custom run database: Cairn's repository is the project's one record.

## Cairn repo and credentials

Choose **one repo**: a local folder or the URL of the server the user named. The
project is a namespace inside it. Runs and all other artifacts share one
lifecycle. Keep the choice in `.cairn.toml`, so that entry points, `pixi run
cairn`, and `pixi run cairn-ui` agree:

```toml
repo = "http://<user-named-host>:8765"   # or a folder; .cairn/repo without
project = "<project>"                    # "default" without
token_file = "~/.config/cairn/<host>.token"
ui = "http://<user-named-host>:8767"     # the cairn-ui that report and workspace ask
```

The nearest file upward that sets a key wins; `CAIRN_REPO`, `CAIRN_PROJECT`,
`CAIRN_TOKEN`, and `CAIRN_UI` override it, and explicit arguments override those.
A `.cairn/token` beside the repository is found by itself. Never put a token in
tracked config, commands, logs, or handoffs. A Hydra key named `project` is not
applied to `cairn.run` by itself. A local repository is created on first use.

Two programs may run beside the project, and neither needs the other to log:

- **`cairn server`** serves a repository to other machines. It has no pages. It
  is the user's: use it only when they run one and name it, never invent one, and
  never stop, restart, or upgrade it on your own. Where the user does want one:
  `cairn --repo <local-path> server --host <host> --port 8765`, behind HTTPS, a
  VPN, or an SSH tunnel; it writes a token file when there is none.
- **`cairn-ui`** shows a repository, local or remote, and keeps the reports and
  workspaces in its own state folder. `pixi run ui` shows the project's repository
  at `http://127.0.0.1:8766`; `cairn-ui --repo <url>` shows a server's. When `ui`
  names one, use that one and start no other: reports live in the one they were
  written in. It may be restarted or upgraded without touching a run.

Writes to a server go through an outbox on disk
(`$CAIRN_STATE_DIR`, `~/.local/state/cairn` without), so a slow or absent server
does not stop a run. Once the outbox is full while the server is away (`outbox_gb`,
20 without), `log` raises `cairn.Full`. `run.flush(timeout=...)` waits for
delivery; `cairn recover` sends what a killed process left behind. Keep the outbox
until then. `finish` with a timeout may raise `Pending`, which is not a completed
run.

Repositories of versions before 0.18 cannot be read by this one, nor old code
run with it: there is no `init`, `track`, `value=`, `metadata=`, `annotate`, or
`cairn report/comments`. A project that still uses them is migrated only when the
user asks.

## Hydra configuration and run identity

Put every scientifically meaningful choice in config. Copy
[`assets/run.py`](../assets/run.py) and
[`assets/research_cairn.py`](../assets/research_cairn.py) into `experiments/`.
The first is a standard Hydra entry point using `with cairn.run(...)`; the second
supplies completed-evidence and study helpers, not run-lifecycle glue.

```yaml
# configs/config.yaml
defaults:
  - _self_

seed: 0
image_every: 50          # steps between logged images; scalars every step
run:
  name: feasibility-method
  description: <question, purpose, and interpretation constraints>

hydra:
  job:
    chdir: false
  run:
    dir: outputs/${hydra.job.name}/${now:%Y-%m-%d_%H-%M-%S}
  sweep:
    dir: outputs/${hydra.job.name}/study-${now:%Y-%m-%d_%H-%M-%S}
    subdir: ${hydra.job.num}
```

These directories hold Hydra bookkeeping and optional scratch files. Cairn has no
Hydra resolvers or callbacks.
Leave `hydra.job.chdir: false` so relative paths remain relative to the project
root. Use `Path(HydraConfig.get().runtime.output_dir)` for optional scratch space. Each job gets its own full Cairn run ID, even when names repeat.

### Run names

A run name describes the run and what it runs on. Cairn's lists show a run's
name and version, not its config, so someone who knows the project must
recognize each run from its name alone and tell it from every other run.

Choose names that make sense in the project's context, in the words the
project already uses. A name mentions:

- what the run is: the method or its role (`ours`, `baseline`, `reference`),
  and the computation where it is not the obvious one (`eval-...`,
  `frames-...`, or a figure's content such as `error-maps-...`);
- what it runs on: the scene or dataset as the project calls it (`ai57_008`,
  `bunny`);
- what tells it from its siblings: the few settings that differ between the
  project's runs, written short (`w64`, `fp16`, `m16`, `sigma0.1`).

For example `ours-ai57_008-w64`, `baseline-ai57_008-w128-fp32`,
`eval-ours-ai57_008-w64`, `reference-ai57_008`, `error-maps-ai57_008-widths`.

Build the name in config by interpolation from the values it mentions
(`name: ours-${scene.name}-w${model.width}`), so it cannot drift from what
ran. A run that reads another run's result repeats that run's name
(`eval-<name>`).

- Two runs that someone will compare, or ask for separately, have different
  names. Every trial of a multirun has its own name, ending in the varied
  values.
- A rerun of the same thing is the next version of the same name
  (`runs/<name>@v2`): after a bug fix, a failure or an interruption. The
  version number tells reruns apart and nothing else.
- A setting that does not tell the project's runs apart stays out of the name;
  it is in the config. The purpose goes in `run.description`.
- Never a counter, a date or a status word (`exp3`, `run-2`, `v2`, `final`,
  `fixed`, `new`, `test`), and never only a word that fits every run of its
  kind (`train`, `experiment`).

Give every run tags as well, for the facts people filter by
(`client.tag(run, "bunny", "w256", precision="fp16")`, or `cairn tag REF bunny
w256` in the shell): Cairn's lists show tags beside the name, and
`tag:bunny` finds them. Tags add to the name; they do
not replace it.

Keep the vocabulary of the names small and stable across the project. Before
starting a run, list the project's existing run names; if the same thing ran
before, reuse its name, so the run becomes its next version.

Use a config per entry point when needed (`configs/train.yaml`,
`configs/evaluate.yaml`), selected with `config_name` on its `@hydra.main`
decorator or `--config-name` on the command line. Put `_target_` on configurable
components (models, datasets, solvers), then instantiate them in the function;
there is no required `experiment._target_` or top-level class. Give each entry
point a Pixi task, for example `train = "python experiments/train.py"`.

Config groups remain useful for variants. Choose the defaults merge order
intentionally: entries after `_self_` override the current config. Inspect
`--cfg job --resolve` to verify the composed parameters.

Pass `OmegaConf.to_container(cfg, resolve=True, throw_on_missing=True)` as
`config=` to `cairn.run` so the resolved Hydra config is recorded. Add Hydra's `.hydra` folder explicitly with `run.add`
if its runtime config and override files are needed; ignored output folders
are not automatically part of the source archive. The backend
run status is the authoritative completion record. A run counts as evidence
only when it completed and its scientific validation passed; a job that raises
is failed. Do not duplicate the full resolved config into another status schema.

Name runs as in Run names above; a result artifact may share its run's name.
Put a concise description in the `cairn.run` argument
`about={"description": "..."}` so a reader understands what was tested and
how to interpret it.

### Snapshot source and runtime state

Copy bundled assets by content only and make the copies owner-writable (for
example `install -m 0644 <source> <destination>`): skill directories may come
from read-only plugin caches, shared installations, or dotfiles mounts.

Leave Cairn's native provenance and console capture enabled. It records
Python/platform/executable/cwd, launch arguments, installed packages, Git state
and a dirty diff, dependency manifests/lockfiles, and a bounded source archive.
All of it is below `_about` on the run (`run["_about"]`,
`run.files("_about/**")`), the config below `_config`, the output in `_console`.
It captures these when entering the run context, before components are constructed. Do not implement a
second source scanner, provenance store, or lifecycle wrapper in the project.

Native provenance is best-effort, not a completeness guarantee: inspect its
omissions/errors and captured files before citing a run. Verify that the method
source and exact `pixi.lock` are present. Outside Git the capture is limited to
the entry script and known dependency files; initialize and commit the project
before running it. Add required files the capture omitted through `run.add`,
and fix and rerun if the original evidence cannot be reconstructed. Keep secrets
out of configs and source; never dump the complete environment. Record system
metrics explicitly when needed. Console capture is bounded and is not a
substitute for scientific metrics or outputs.

### Where a run lives

`outputs/` holds Hydra configs and optional scratch files. The native context
does not create a project-specific `cairn-run.json` receipt. The output folder
is not the authoritative evidence/status store.
Inspect it with `pixi run cairn find 'runs/**'`, `pixi run cairn show <ref>`,
`cairn records|console|links <ref>`, or the pages. Keep failed job folders for
diagnosis; publish scientific results only from completed, validated producers.

A finished artifact can have a failed outcome; `latest` is the newest completed
version. Top-level `cairn.log/add/use` work on the run whose `with` is open. A successful
log call is not a successful experiment. Use the completed-evidence check below
before citing a result. Runs pin their inputs (`run.use` with `@vN` in configs
for reviewed evidence); reports may show `@latest` (see reports.md). Do not infer completion from a folder,
alias, or local pointer file.

## Hydra entry points: runs, inputs, and results

Use [`assets/run.py`](../assets/run.py) as the template:

```python
@hydra.main(version_base=None, config_path="../configs", config_name="config")
def main(cfg: DictConfig):
    with cairn.run(
        cfg.run.name,
        config=OmegaConf.to_container(cfg, resolve=True, throw_on_missing=True),
        about={"description": cfg.run.description},
    ) as run:
        model = hydra.utils.instantiate(cfg.model)
        # Compute, record results, and validate before leaving this block.
```

Hydra composes the config first. Open one native Cairn context inside the
function for each invocation, including each multirun job. The run name comes
from `cfg.run.name`, so config groups and CLI overrides can adjust it. Pass the
resolved config explicitly; repo/project use normal Cairn configuration discovery.
Keep component construction, computation, recording, and scientific validation
inside the block: normal exit completes the run, an exception leaving it
marks it failed, and Ctrl-C or SIGTERM (a scheduler's) marks it cancelled. Do not swallow validation failures and then exit normally.

No Experiment class or custom tracking wrapper is needed. The explicit handle and
top-level `cairn.*` API target the same current run, so helper functions can log
without receiving a handle.

Inside the run context (indent this code accordingly):

```python
import json
import matplotlib.pyplot as plt
import cairn

from pathlib import Path
from hydra.core.hydra_config import HydraConfig

output_dir = Path(HydraConfig.get().runtime.output_dir)
data = run.use("datasets/crops@v3")          # records the exact input
data.download(output_dir / "inputs" / "crops")
for step in range(cfg.steps):
    # ... perform the method and compute loss ...
    run.log(loss=loss, step=step)

# ... scientifically validate scores, cases, and errors ...
run.log(scores=scores, cases=cairn.Table(cases))
rows = error_rows(errors)                  # every value the figure plots
figure = error_histogram(rows)             # cheap: redrawable from the table
run.log(error_rows=cairn.Table(rows), error_histogram=cairn.Figure(figure))
plt.close(figure)
```

Write metrics, tables, figures, arrays, and files directly to the run with
`log` (`add(path, name)` and `use(ref, role)` are shorthand for it). Logging a key
again replaces its current value; the earlier records remain. For a library that requires a filesystem path,
use `output_dir` as optional scratch space and explicitly add the resulting
file. Hydra keeps its configuration there; Cairn does not
require evidence to pass through that directory. Cairn does not scan
`output_dir/result` or automatically create a second artifact.

A report can show what a completed run logged directly. Create a separate
result artifact only when it needs an identity or lifecycle independent of
that execution. Reuse alone is not a reason to create another artifact. For example,
explicitly add a result directory with `run.add(path, "result")`,
then after the run finishes call `publish_result(client, client.get(run_id))`.
That optional helper reuses the stored value in the same repository without
downloading or re-uploading its payload and records the run it `use`d as
`producer`. There is no need to do this for every experiment.

`use` takes completed artifacts only, so a separate artifact made from a run waits
until that run finishes. `use(ref, incomplete=True)` also takes a finished one that
did not complete: for continuing from a cancelled run's checkpoint, never to cite
it. Requiring that the science was validated is this skill's policy.

### Stage handoffs

Put the input run reference and the desired file/key in config. Inside a native
run context, consume its recorded output directly:

```python
source = run.use(cfg.input_run, role="prepared-data")
require_completed_run(source)              # plus the stage's scientific checks
with source.open("prepared.json") as stream:
    prepared = json.load(stream)
# ... compute and validate ...
run.add(checkpoint_path, "model.pkl")
```

A later stage can similarly `use` this run with role `base-model`, then open or
download `model.pkl`. Files are opaque; use the producing framework's loader for
trusted checkpoints. Persist optimizer/RNG state as well as weights when exact
continuation needs it. Multiple input runs support branches and combined models;
no extra dataset/model artifact is required to connect them.

A report shows what analysis runs recorded; each analysis run `use`s the
completed runs it reads. Store invariant inputs once and record output
values plus stable IDs where needed to join them; do not repeat whole input
arrays in every trial or store identical data in JSON, tables, and added files
without a consumer that needs those representations.

A live run can be read (`client.get("runs/a@live")`, `follow()`), also its files,
but not `use`d. Split independently reusable passes into runs that complete.
Scheduling and deciding which stages to rerun remain project tasks, not automatic
behavior inferred from Cairn's links.

### Log results during the run

Record metrics and intermediate outputs when they become available, inside the
run context. Do not buffer all results until the end or wait for a report build.
Choose a logging cadence in config: inexpensive scalars can be frequent; images,
arrays, and figures can use a coarser interval. Keep complete scientific outputs
needed to reproduce conclusions even when previews are sampled less often.

**Every run is visually inspectable on its own.** A person opening the run in
the Cairn UI, without the code or a report, sees what it did. Besides scalars,
log as images over the step, at a configured `image_every` interval (and once
at the start and the end), everything that is cheap to compute from state the
run already has:

- the current output or reconstruction next to its reference/target and the
  input, on a fixed set of samples or views, so frames compare across steps;
- the error or residual image with a fixed colour scale;
- the optimized parameters when they are images or fields (textures, weights,
  masks, density slices), and their gradients where the method uses them;
- intermediate quantities the method's claim depends on (a predicted weight
  map, an attention map, a per-pixel loss term);
- at the end, a small figure per diagnostic (loss terms over steps, a histogram
  of errors) from the logged data.

Use the same key, samples, image size, and colour scale at every step so the
UI's step slider shows a sequence. Log with `cairn.Image` (arrays scaled to
`[0, 1]` or `uint8`, tonemapped if HDR, downsampled for previews) and the
step, sample, and split in the same record. A non-iterative run still logs its inputs,
outputs, and errors as images once. Skip only what is genuinely expensive to
compute (an extra full render per step), and then log it at a coarser
interval rather than not at all.

Use stable field names, types, and units across runs. Include the coordinates
needed to interpret each observation in the same record: `step`, `epoch`,
`elapsed_seconds`, `split`, `sample_id`, or `camera`, as applicable. Use separate
records for separate samples or conditions. Avoid encoding steps or sample IDs
into field names, or logging a whole time series only as one final list.
Cairn supplies `_time` (Unix seconds); log elapsed time explicitly if needed.

```python
# Inside the run, as each observation becomes available:
run.log(step=step, split="train", loss=float(loss), elapsed_seconds=elapsed)
run.log(step=step, split="validation", loss=float(validation_loss))
run.log(step=step, sample_id=sample_id, camera=camera,
        reconstruction=cairn.Image(image_array))
run.log(step=step, split="validation", diagnostic=cairn.Figure(figure))
```

Wrap media/large arrays with `Image`, `Figure`, `Array`, or `Table`; Cairn stores
their payloads as blobs referenced by the record. Do not embed base64 images or
large numeric lists in JSON. Preserve the data behind each diagnostic figure as
well as its rendered preview. One record combines typed values, files, and scalars.
An `add`ed file has no observation axes; log it with them when it has some.
Remote writes may be queued: use `run.flush(timeout=...)` when a delivery
checkpoint is needed, rather than flushing every scalar. A live observation is
progress information; completed, validated runs are still required for evidence.

### Record evidence with the public API

```python
run.log(loss=loss, psnr=psnr, step=step)
run.log(running_rmse=cairn.Figure(plotly_figure), step=step)
run.log(reconstruction=cairn.Image(array), step=step)
run.log({"trials": cairn.Table([{"condition": c, "rmse": r} for c, r in rows])})
run.log({"preview": cairn.File("optimization.mp4"), "step": step})
run.add("checkpoints/best.pt", "best-checkpoint")
run.log(checkpoints=cairn.Directory("checkpoints"))
```

Values are null, booleans, numbers, text, bytes, lists, maps, `File`, `Directory`,
`Ref`, and the typed `Image`, `Array`, `Table`, `Figure` (Matplotlib or Plotly).
Audio and video are `File`s. Keys starting with `_` are Cairn's. Nothing is pickled.
A file may change once `log` returns; `File(path, immutable=True)` saves a copy
when it will not change before the run ends.
Preserve complete scientific tables and arrays, not just presentation subsets.
The output of every expensive stage is recorded completely enough that every
figure, table, and number derived from it can be recomputed from the record
alone (SKILL.md: "Store what is expensive; recompute only what is cheap").

```python
with cairn.Client() as client:
    run = client.get("runs/a@v1")
    run["loss"], run.config, run.outcome      # current values
    run["trials"].load(); run["reconstruction"].array()
    run.series("loss", x="step")              # pairs
    for ordinal, record in run.records(): ...
    run.files("checkpoints/**"); run.read("best-checkpoint"); run.download("copy")
    client.find("runs/ours-*", where=["min(loss) < 0.1", "_config/lr = 0.001"], order="-psnr", values=["psnr"])
```

There are no `metrics.jsonl` or `summary.json` snapshot folders. Console output is
captured by default; it does not supply scientific metrics or system
measurements, so log those explicitly.

Use stable file names, columns, and units across experiments. Record the
generating module/function and material plotting settings beside each figure
or in run metadata, in addition to the data it plots; verify that native provenance includes the generating source. Never hide
important evidence through final-only output, excessive aggregation,
cherry-picked examples, or presentation-only composites. Keep per-step series and final results in the run; reports can read both
directly. Separate result artifacts are optional.

## Artifacts: datasets, models, and results

References are `namespace/name@vN`, `namespace/name@alias`, `@live`, `@latest`
(the newest completed version, also without a selector), or an ID, inside the
selected project. Names may contain slashes. Use IDs for cross-project inputs and
exact `@vN` references for reviewed evidence a run reads. What a report shows is
not an input and may use `@latest`. A run gets its version when it finishes.

A finished artifact never changes. Tags (`client.tag`) and aliases
(`client.alias(run, "best")`, one version of a name) may. Check outcomes and
producers.

### Register and consume datasets without redundant copies

Choose storage by ownership, lifetime, and where consumers run. Importing a
small portable dataset with `add(path)` copies its bytes into Cairn. For an existing immutable archive whose files must remain in
place, use native linked-file registration instead of a JSON path/checksum
manifest. Register once, document origin/license/validation, and retain its exact
reference:

```python
import cairn

with cairn.artifact("datasets", "measurements") as dataset:
    dataset.log(files=cairn.Directory("data/measurements", link=True),
                origin="<source>", validation="<checks>")
print(dataset.ref)                           # datasets/measurements@vN
```

Consumers declare the artifact; local linked access leaves bytes in place:

```python
source = run.use(cfg.dataset, role="observations")
with source.open("files/part-01.csv") as stream:
    # Stream or parse only the needed file.
    ...
# For a library requiring a path, select one file rather than the whole archive:
[path] = source.download(output_dir / "inputs", "files/part-01.csv")
```

Dataset inspections are analysis runs too: they read the dataset with these
operations and log the tables and figures a report shows. Imported datasets need documented source and
validation, not an invented producer run. Computed results stay on the producing
run by default.

Important access and storage distinctions:

- **Linking** hashes files at registration and retains their locations instead
  of storing another copy. Keep those locations persistent and immutable: reads
  check size and time, and a changed file counts as missing. `open` reads in
  place; `download` copies.
- **Remote access** requires the server to see the paths below its `--link-root`
  folders; the client uploads anything else. `link=True` is therefore not a strict
  no-copy option. Where copying is unacceptable, verify the server's link roots
  before registration or report the constraint. Remote readers transfer bytes.
- **Deduplication** stores identical bytes once. It does not eliminate repeated
  hashing, different encodings of the same data, or downloads. Prefer
  `.open(path)` or `.download(to, pattern)` over downloading a whole dataset for
  each run.
- **Generated data** should have one durable recorded representation unless
  distinct consumers justify more. Link generated outputs only when their
  location is retained and immutable; temporary scratch is not durable storage.
- **Many files** are one `Directory`; do not shard by hand.

Ignore raw archives and generated data before the first commit and run, including
custom directory names outside `data/`, so native provenance does not copy them.
A hand-written external path manifest does not replace a linked dataset: it
bypasses native retrieval and integrity behavior. Keep path handling in the
Cairn API instead of building a second data registry.

Download a whole artifact only when needed, with
`client.get(ref).download("artifacts/dataset-v1")`. Delete one only when the user
asks: `cairn delete <ref>` hides that version (`cairn restore` brings it back),
and `cairn collect` frees the space for good, so confirm that separately.
Record experiment outputs on their run by default. If publishing a separate
result artifact, keep `use(run, role="producer")` of the completed run; do not
disguise experiment results as runless dataset imports. Register external files as stored bytes or native links before reports consume
them; do not substitute untracked filesystem reads.

### Completed evidence and lineage

`pixi run evidence runs/<name>@vN` (or `artifacts/<result>@vN`) calls
`require_completed_artifact(client, ref)`: require a finished completed result,
exactly one completed producing run in the same project, or a completed run
when the input itself is in `runs`. This is lifecycle validation, not proof
of scientific validity. Runless datasets/sample fixtures require documented
origin/validation and intentionally do not pass the scientific-results gate.
They can be valid evidence without that gate: check their completed outcome,
source, integrity, and fitness for the question. Do not fabricate producer runs
just to make an import pass a computed-results check.

Use `run.use(ref, role=...)` for inputs, `result.use(run, role="producer")` after the
run completed, and `summary.use(trial_id, role="trial")` for studies.
`reader.uses()` and `used_by()` give `(path, artifact)` pairs, where the path is
`_use/<role>`; the pages show them both ways. Reports are not part of this: their
references are resolved when shown, and may name a failed version. The project's
completed-evidence policy is intentionally stricter.

### The sample artifact

The bundled sample is synthetic demonstration evidence, not an experimental
result. Import it into the selected project, one file per name:

```python
from pathlib import Path
import cairn
root = Path("<skill-directory>/assets/sample-run")
about = {"origin": "research-project skill sample", "synthetic": True}
with cairn.artifact("datasets", "sample-run", about=about) as sample:
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        sample.add(path, path.relative_to(root).as_posix())
```

As a smoke test, open the sample in the pages and look at one of its figures.
When a cairn-ui runs, also check reports (a scratch report of your own, deleted
again):

```bash
printf '# Scratch\n\n![Sample grid](cairn:datasets/sample-run@latest#figures/grid.svg)\n' \
  | pixi run cairn-ui report write scratch
pixi run cairn-ui report delete scratch
```

The sample may remain stored, but no real report may show it.

## Running on a cluster

Projects use the `slurm` skill and the cluster's own skill (`kuma`, `lyra`)
for EPFL's Slurm GPU clusters. Load both before the first cluster command in a
session. Keep `hydra-submitit-launcher`, `linux-64`, and one task per used
cluster in `pixi.toml`; configure the scheduler to invoke the intended Hydra
entry-point task (the template defaults to `experiment`). Copy
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
own outbox and protected credentials.

**Scheduler assets may be written for an older Cairn.** The HyperQueue skill's
files still use `${cairn.run:}`, drafts, callbacks, `remote set`, and its own hub on
port 4320, none of which work with v0.18. Keep their scheduling, storage, and
GPU-efficiency rules, but adapt and test the project's tracking glue before
submitting; Cairn's `examples/` has a Hydra sweep for Slurm, PBS, and HyperQueue.
Do not edit the adjacent skills, and do not touch that hub.

Each cluster trial uses the same run/provenance/completed-evidence contract as
a local job, with its own `outputs/` bookkeeping/scratch folder. When a launcher dies,
confirm its jobs have left the queue, run `cairn recover` where they ran, and explicitly
finalize the saved expected roster. Missing or non-completed trials prevent
a successful summary. Commit before submitting runs a report will cite;
initial provenance records the actual source and Git state.

**Getting cluster runs out.** Keep the project's source and outbox on storage permitted by the cluster skill. Use an explicit remote
server for shared/network project filesystems; do not place a multi-host
SQLite repository there:

- **One server on a machine with a local disk.** The user runs `cairn --repo <path> server` on a workstation or service host, never on a compute node or
  with its local repository on a shared filesystem, behind HTTPS or a VPN.
  Use its actual configured port; the project is a separate namespace.
- **The project names it.** Set `repo` in `.cairn.toml` (or `CAIRN_REPO`) to the
  server's URL, with a protected token file.
  Never put credentials in tracked configs or job scripts.
- **Jobs keep an outbox.** It sends by itself while the job runs. What a killed
  job left is sent by `cairn recover` with the same `CAIRN_STATE_DIR`, on a host
  that reaches the server. Verify that the runs are finished before citing them. A
  node-local `CAIRN_STATE_DIR` must be recovered before the allocation deletes it.
- **Checkpoint for cancellation.** A job that the scheduler ends is `cancelled`; its
  continuation reads the checkpoint with `use(ref, incomplete=True)`.

Reports are not involved: nothing about them is built or moved.

## Parameter studies

Only after feasibility, study parameters systematically. Declare the parameter
space, seeds, budget, objective, and its direction in config. Two forms are
supported, and both must keep every configuration's result inspectable:

- **Hydra multirun** (`python experiments/run.py -m key=a,b,c`) when the
  configurations are separate experiments to compare or select from: sweeps,
  ablations, or competing settings. Each trial is a complete Cairn run with
  its own provenance, config, logs, and results recorded on the run. Save the expected
  trial roster when launching; fill in full run IDs from the backend and match each resolved config to its
  planned trial (record a trial label in config; each trial has its own run
  name ending in the varied values, see Run names). Do not infer the expected roster from only successful jobs.
  Finalize explicitly with the helper below; no automatic study callback is
  assumed. A report shows the summary run's tables or an analysis run over
  the trials. Failures stay visible and prevent a completed study summary.
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
backend (or pass `--repo <path or URL>`). Missing or extra trials,
duplicate run IDs, and non-completed backend runs fail the check. After the
scientific validation passes, the helper creates a summary run, records each
trial with `use(..., role="trial")`, and records the roster and status table on `runs/<name>@vN` itself. It does
not automatically publish a second result artifact.
Run from the project root so native provenance captures the intended project
and `pixi.lock`; `--project-root` only sets helper output/repo path resolution.
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
