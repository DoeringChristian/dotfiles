---
name: hyperqueue
description:
  Run pixi + Hydra + Cairn projects on the lab's HyperQueue cluster of GPU workstations (head fermat; workers
  fermat, kerr, gabor, arago) through `pixi run hq ...`, and start or stop the cluster with `hqc`. Use whenever work
  should run on fermat, kerr, gabor, or arago, on "the HQ cluster" or HyperQueue, or when a sweep is too big for the
  local machine but does not need Kuma or Lyra.
---

# HyperQueue cluster

Four lab workstations form one HyperQueue (HQ) cluster. The HQ server and the Cairn hub run on fermat (the head),
and every node runs one worker. A Hydra multirun becomes one HQ job, and each trial is a task that runs on whichever
GPU is free. Runs are ordinary Cairn runs and sweeps, recorded exactly as for a local or Slurm sweep. The machines
are free to use, but people work on them too. Read the project skill (`research-project`) for how runs, drafts, and
reports work; this skill only adds how they get onto the cluster.

| Node | GPU | Cores, RAM | Project root | Reached |
|---|---|---|---|---|
| fermat (head) | RTX 5090, 32 GB | 32, 62 GB | `/media/data/doeringc/hq` | ssh `fermat` (Tailscale) |
| kerr | RTX 3090, 24 GB | 64, 60 GB | `/home/doeringc/hq` | ssh `kerr` (Tailscale) |
| gabor | RTX 4090, 24 GB | 32, 61 GB | `/home/doeringc/hq` | ssh `gabor` (Tailscale) |
| arago | RTX 4090, 24 GB | 32, 62 GB | `/media/data/christian/hq` (user `christian`) | only from fermat (`ssh arago` there) |

All drivers are ≥ 595, so use CUDA 12.8+ PyTorch wheels (`cu128`), the oldest that supports the 5090. There is
**no shared filesystem**: each node has its own checkout of a project and its own `.cairn/` repo, and every repo's
remote is the hub on fermat.

## The cluster: `hqc`

[`assets/hqc`](assets/hqc) is linked as `~/.local/bin/hqc`. It runs on any machine that reaches fermat and runs
everything from there:

```bash
hqc status              # server, workers (with cpus, gpus, vram), unfinished jobs, hub
hqc up [node...]        # start the server and the hub when down, and workers (default: all four)
hqc down [node...]      # stop these workers (their running tasks are requeued); no node: every worker and the server
hqc down --hub          # ... and the hub (it holds every project's results: normally leave it up)
hqc hq <args...>        # any hq command: hqc hq job list --all, hqc hq task list <job>, hqc hq job cancel <job>
hqc log [node]          # tail of the server's (or that node's worker's) log
hqc install             # one-time setup, idempotent (hq on every node, access files, the hub's environment)
```

Before submitting, run `hqc status`. If the server is down, run `hqc up`. Starting workers is cheap and
harmless. Never stop workers or the server while someone else's jobs run, and never take a node out without the
user's word. The server's journal restores unfinished jobs after `hqc down` and `hqc up`.

State: `~/.hq-cluster/` on fermat (`cluster.conf`, `nodes`, the access files, the journal, `server.log`), and the
worker's access file and `worker.log` on each node. The hub is `cairn server` on fermat port 4320 (UI on 4321). Its
pixi environment and repo are in `/media/data/doeringc/cairn-hub`. fermat's EPFL address comes from DHCP: when it
changes, `hqc up` writes new access files, and each project needs `pixi run hq setup` again.

## Set up a project

Any project set up by the `research-project` skill works (Hydra with `${cairn.run:}` folders and Cairn's
callbacks). It also needs `linux-64` among its pixi platforms, a committed `pixi.lock`, and an `experiment` task
that starts the Hydra app (`python experiments/run.py`). Copy:

- [`assets/hq.sh`](assets/hq.sh) → `experiments/hq.sh`, plus the pixi task `hq = "bash experiments/hq.sh"`;
- [`assets/hq_launcher.py`](assets/hq_launcher.py) → `hydra_plugins/hq_launcher.py`. `hydra_plugins/` gets **no**
  `__init__.py`, because Hydra accepts launchers only from that namespace package;
- [`assets/hydra-launcher/hq.yaml`](assets/hydra-launcher/hq.yaml) and
  [`hq_debug.yaml`](assets/hydra-launcher/hq_debug.yaml) → `configs/hydra/launcher/`.

Use `install -m 0644` (`0755` for `hq.sh`). `hydra-submitit-launcher` is not needed for this cluster. Commit, then
run `pixi run hq setup` once. It pushes the project to every node, installs its environment there, makes each
checkout's `.cairn/` sync to the hub (`http://<fermat>:4320/<project>`), and points this checkout's repo at the hub
too, unless the repo already has a remote. The hub project is named after the project folder.

## Commands

```bash
pixi run hq push                      # rsync the working tree (incl. .git) to every node, pixi install --frozen there
pixi run hq smoke <tiny overrides>    # push, then the study in the foreground (hq_debug: 15 min, high priority)
pixi run hq submit <sweep or overrides> [hydra.launcher.time_limit=2h ...]   # push, then a detached study
pixi run hq status                    # workers, this cluster's jobs, the newest launcher logs (outputs/.launch/ on fermat)
pixi run hq gpu                       # GPU use on every node
pixi run hq finalize <sweep folder>   # complete a study whose launcher died or whose trial failed
pixi run hq ssh [@node] <command...>  # in the project's checkout on fermat (or on that node)
```

- **Results come through Cairn, not files.** Every trial is a run that its node syncs to the hub. Read runs here
  with `pixi run cairn versions runs/<name>`, `pixi run pull <ref>`, `pixi run ui`, or the hub's UI at
  `http://fermat:4321`. A report reads them as usual.
- Launcher options per study: `hydra.launcher.cpus=` (default 8), `gpus=` (1; 0 for CPU-only trials, which then
  share nodes), `gpu_mem_gb=` (only GPUs with at least this much memory: `30` means fermat only), `time_limit=`
  (`1h`; HQ kills the trial after it), and `priority=`.
- A single run is a one-trial study: submit it without sweep values. Both sweep forms of `research-project` work:
  a `${cairn.run:}` sweep (one run per trial plus a summary run), and `hydra.sweep.dir='${cairn.draft:<name>}'`
  (all trials collected in one artifact).
- Commit before runs a report will cite: uncommitted changes are pushed and recorded as a patch. Never edit files
  on a node, because the next push overwrites them. The nodes' `.cairn/` is never pushed or deleted.
- Never run experiments directly on a node over `ssh`; go through HQ, so the GPUs are not oversubscribed.

### How a sweep stays one study

The launcher runs on fermat and reserves the sweep folder in fermat's checkout. Each task copies that reservation
into its node's checkout and runs the trial there as a single Hydra job in `<sweep>/<n>`. Cairn then records it as
the same trial it would be on a shared filesystem, and the task syncs it to the hub. When the HQ job ends, the
launcher copies every node's part of the sweep folder back (kept trial folders and `trials.jsonl` lines), removes it
there, and Hydra's `StudyCompletion` publishes the summary as usual.

A failed trial makes Hydra raise (as with submitit), so the summary is not published by itself. The failed trial's
run is on the hub as `failed`, and its kept folder is in the sweep folder on fermat. Diagnose the failure first;
`pixi run hq finalize <sweep folder>` then records the study as failed. Use the same command after a launcher
died: it fetches the nodes' parts of the sweep, then runs `cairn finalize-study`. `pixi run hq ssh pixi run
--frozen cairn drafts` lists the open sweep folders on fermat.

## Using the cluster well (before every `submit`)

The GPUs are not billed, but they are shared with interactive work, and HQ cannot see processes outside HQ.

1. **Check the GPUs** (`pixi run hq gpu`). A node whose GPU is busy with someone's interactive work will run
   trials into out-of-memory errors. Ask the user whether to take it out (`hqc down <node>`) instead of
   submitting into it.
2. **Measure one representative trial with `smoke`**: time per step, wall time, peak GPU memory, and utilisation
   (`pixi run hq gpu` while it runs). The GPUs differ (3090 < 4090 < 5090), so set `time_limit` to about 1.3× the
   time on the slowest node a trial can land on. Use `gpu_mem_gb` when a trial needs more memory than 24 GB.
3. **Keep non-GPU work out of trials.** `push` installs environments before any task starts. Download datasets
   once per node (in its checkout's `data/` or a `cairn.use` of a published dataset), never inside each trial.
4. **Pack small work.** Trials shorter than a few minutes are dominated by start-up (pixi, imports, CUDA). Batch
   seeds or configs inside one run (an in-run grid) instead of many tiny tasks.
5. **Right-size `cpus`.** Ask for what the data pipeline uses; with `gpus=0`, `cpus` decides how many trials share
   a node.
6. **Stop what is moot**: `hqc hq job cancel <job>` as soon as a study is superseded or a bug is found.

## Troubleshooting

- A task failed before Cairn started (missing checkout, pixi error): `ssh <node> cat /tmp/hq-<job>.<task>.err`
  (for arago: `ssh fermat ssh arago cat ...`). `hqc hq task list <job>` shows each task's state and worker.
- `no checkout of <project> on <node>`: run `pixi run hq push`. A node added later also needs `pixi run hq setup`.
- Workers missing in `hqc status`: `hqc up`, then `hqc log <node>`.
- `cairn status` on a node (`pixi run hq ssh @<node> pixi run --frozen cairn status`) shows versions still waiting
  for the hub. The hub is plain HTTP inside EPFL's network, and Cairn warns about it on every call.
