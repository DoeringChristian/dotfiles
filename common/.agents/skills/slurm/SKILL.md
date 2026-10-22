---
name: slurm
description:
  Run any pixi + Hydra project on a Slurm GPU cluster through `pixi run <cluster> ...`
  (one generic script, per-cluster profiles, and Hydra submitit launchers), with
  the mandatory GPU-efficiency gate before any job is submitted. Use whenever
  work touches a Slurm cluster, sbatch, GPU jobs, or running experiments or
  sweeps remotely. Each cluster has its own skill (for example `kuma`, `lyra`)
  with its facts, profile, and launchers; load it together with this one.
---

# Slurm

GPU clusters bill every allocated GPU-hour, whether or not the GPU is used, so
**idle GPU time is wasted money**. This skill holds what is the same on every
Slurm cluster: how a project reaches the cluster, the commands, how storage is
used, and the GPU-efficiency gate. A cluster's own skill adds its facts
(hosts, account, partitions, QoS, driver, storage paths and quotas), its profile
for the script, and its launcher configs. Load both before the first cluster
command in a session.

Projects reach a cluster only through pixi: `pixi run <cluster> <command>`,
defined by this skill's [`assets/cluster.sh`](assets/cluster.sh) with the
cluster's profile. Never call `sbatch`, `srun`, or `module load` around pixi by
hand. If a command is missing, extend `cluster.sh` in this skill's assets (and
the project's copy).

## Set up a project

Any pixi + Hydra project works. It needs:

- `linux-64` among its pixi platforms, and a committed `pixi.lock`;
- `hydra-submitit-launcher` in its dependencies;
- a pixi task `experiment` that starts its Hydra app, so overrides can be
  appended (`experiment = "python <app>.py"`); `CLUSTER_ENTRY` replaces the
  whole command when a project needs something else;
- Hydra writing its runs under `outputs/` (Hydra's default), with sweeps in
  `hydra.sweep.dir`.

Copy the assets into the project:

- [`assets/cluster.sh`](assets/cluster.sh) into a folder, for example
  `experiments/`;
- from each cluster's skill, its profile into `<that folder>/clusters/<cluster>.sh`
  and its launchers `<cluster>.yaml` and `<cluster>_debug.yaml` into
  `configs/hydra/launcher/` (the folder of the project's Hydra config);
- one pixi task per cluster: `<cluster> = "bash experiments/cluster.sh <cluster>"`.

The launchers name each Slurm job after `run.name` when the config has one,
otherwise after Hydra's job name, and keep submitit's files in
`<sweep dir>/.submitit/`.

Take the CUDA version from the cluster's skill (its driver sets the maximum).
Install PyTorch's CUDA wheels only on Linux, for example:

```toml
[target.linux-64.pypi-dependencies]
torch = { version = "*", index = "https://download.pytorch.org/whl/cu126" }  # the cluster's CUDA

[target.osx-arm64.pypi-dependencies]
torch = "*"
```

When a conda package needs CUDA, declare it on a named Linux platform,
`platforms = [{ name = "linux-64-cuda", platform = "linux-64", cuda = "12" }, "osx-arm64"]`
(`[target.linux-64.*]` tables still apply). This lets a GPU-less login node
install it. pixi ≥ 0.81 rejects the deprecated `[system-requirements]` table
and a CUDA entry named plainly `linux-64`. Never `module load` CUDA or Python:
pixi owns the environment on the cluster too. Experiment code uses `cuda` or
`cuda:0`; Slurm sets `CUDA_VISIBLE_DEVICES`. One environment serves several
clusters only when they accept the same CUDA build.

## Commands

The local checkout stays the source of truth: `pixi run <cluster> ...` pushes
the working tree (including `.git`, so a run can record the same revision;
ignored files, `outputs/`, `generated/`, and `.pixi/` stay local), runs Hydra
through a Slurm launcher, and `pull` copies `outputs/` back so results are
inspected locally. A project that logs to a tracking server (Cairn, MLflow) gets
its results from the server, reachable from the compute nodes, and needs no
`pull`.

```bash
pixi run <cluster> setup                       # once per account: pixi on the cluster, project directory
pixi run <cluster> smoke <tiny overrides>      # foreground, debug launcher (small GPU slice, debug QoS)
pixi run <cluster> submit <sweep or overrides> [hydra.launcher.timeout_min=…]
pixi run <cluster> pack -t 1:30:00 -- <sweep>  # small trials, one GPU job
pixi run <cluster> status                      # queue and launcher logs
pixi run <cluster> gpu <jobid>_<n>             # live GPU utilisation of a running trial
pixi run <cluster> pull                        # outputs/ back to the local project
pixi run <cluster> storage                     # /home and /scratch use
pixi run <cluster> ssh <command...>            # any command in the remote project
```

- `smoke` blocks until its tiny study finishes. Use it to validate plumbing and
  to measure a representative trial. It is not evidence.
- `submit` starts the Hydra launcher detached on the login node. Its log goes
  to `outputs/.launch/` and names the login node. The launcher submits one
  Slurm array task per trial and waits for all of them. If it dies, the trials
  still run.
- `pack` runs the whole multirun in sequence inside one allocation (the
  profile's `PACK_ARGS`), using Hydra's basic launcher. It needs an explicit
  `-t`.
- A single run is a one-trial study: submit it without sweep values. Never run
  the experiment on a login node.
- Commit before pushing runs whose results matter; uncommitted changes are
  pushed too. Never edit files on the cluster, because the next push overwrites
  them.
- A tracking server's token must exist on the cluster with mode 600, never in
  the repository.
- A launcher process that died leaves its study without its completion step.
  Check `status`; once the study's jobs have left the queue, complete it as the
  project or its skill says, through `ssh`. The launcher log name gives the
  login node it ran on.

## Storage

Place each kind of data by what losing it would cost; the cluster's skill gives
the paths, quotas, and purge rules:

| What | Where |
|---|---|
| Code, configs, `pixi.lock`, `outputs/` (Hydra's runs and launcher logs) | the project directory under `/home`: small, backed up, never purged |
| pixi environments (`.pixi/`) and pixi's cache (`~/.cache/rattler`) | `/home`, together: environments are hardlinked from the cache, so projects on the same versions share one copy. Never move only one of them: across filesystems every environment becomes a full copy. |
| Kernel and model caches (Dr.Jit, Triton, TorchInductor, CUDA, torch hub, Hugging Face) | the profile's `CACHE_ROOT` on `/scratch`: `cluster.sh` exports their variables for every remote command, and Slurm passes them into every job |
| Checkpoints, renders, intermediate arrays, datasets | `/scratch/$USER/<project>/`: bulky and re-creatable; record the path in the run |
| Job-local temporaries and staged inputs | `/tmp` inside the job (node-local) |

- Run `pixi run <cluster> storage` before installing a new environment, before
  a study that writes more than a few GB, and whenever a write fails.
- New tools with a cache under `~` (look for `~/.<tool>` or `~/.cache/<tool>`
  after a first run): add the tool's cache variable to `CACHES` in this skill's
  `cluster.sh` and the project's copy, and delete the copy in `/home`.
- Reuse dependency versions across projects so their environments share the
  hardlinked packages. Remove a finished project's `.pixi/`
  (`pixi run <cluster> ssh rm -rf .pixi`), then
  `pixi run <cluster> ssh pixi clean cache`; only the cache cleanup frees the
  bytes.
- Never write experiment outputs larger than a few hundred MB into `outputs/`:
  `pull` copies `outputs/` to the local machine as well.

## GPU-efficiency gate (mandatory before every `submit` or `pack`)

Do not submit until each point is checked. In the reply to the user, state the
measured numbers.

1. **Keep non-GPU work out of GPU jobs.**
   - `push` installs the environment on the login node before any job starts.
   - Download data and build dataset caches before submission: small ones on
     the login node, heavy CPU preprocessing as a CPU-only job (the cluster's
     build QoS or CPU partition). Store them under `/scratch/$USER/<project>/`.
   - A GPU job must never wait on an install, a download, or a cold cache.
2. **Measure one representative trial first** with `smoke`. Use the smallest
   config that still shows production behaviour. Record:
   - time per step or iteration
   - total wall time
   - peak GPU memory
   - GPU utilisation while it runs (`gpu <jobid>_<n>`, after the ~30 s of
     imports and CUDA start-up, which read as 0 %)

   The target is sustained utilisation of ≳ 80 %. The debug launcher usually
   uses a GPU slice, so when the trial's behaviour depends on the full card,
   measure with a short `submit` of one trial on the default partition instead.
3. **Fix the bottleneck before scaling.** In this order:
   - Keep data resident on the GPU when it fits.
   - Otherwise stage it once to `/tmp` at job start instead of streaming many
     small files from `/home` or `/scratch`.
   - Set DataLoader `num_workers ≈ cpus_per_task - 1`, `pin_memory=True`,
     `persistent_workers=True`.
   - Grow the batch until GPU memory is well used.
   - Use bf16/TF32 where it does not change the scientific question, and
     `torch.compile` for long runs.
   - Remove per-step host syncs (`.item()`, `.cpu()`, printing).
   - Move plotting, heavy evaluation, and frequent checkpointing out of the
     hot loop.
4. **Right-size the request.**
   - One GPU unless the code really is multi-GPU and scales.
   - Request only the cores the input pipeline uses (`hydra.launcher.cpus_per_task`),
     within the cluster's cores per GPU.
   - Set `hydra.launcher.timeout_min` to about 1.3× the measured trial time.
     Short limits backfill sooner, and a hung trial then burns minutes, not
     days.
   - Choose the partition by the cluster skill's rule; the most expensive GPU
     only for a stated reason.
5. **Pack small work.** A short trial (≲ 10 min), or one that leaves the GPU
   mostly idle, should not get its own job: start-up, imports, and CUDA init
   then dominate. Either vectorise seeds or configs inside one run (an in-run
   grid, batched dims or `vmap`), or chain the sweep in one allocation with
   `pack -t <total> -- <sweep>`. Use `submit` (one array task per trial) only
   when trials are long enough to justify separate jobs.
6. **Never hold idle allocations.**
   - No open interactive sessions while thinking or editing.
   - No placeholder jobs.
   - `pixi run <cluster> ssh scancel <jobid>` as soon as a running study is
     moot (a bug found, a superseded config).
7. **Audit afterwards.** Run `pixi run <cluster> ssh seff <jobid>_<n>` on a few
   trials and compare the elapsed time with the limit. Judge success by each
   trial's own completion record (its run on the tracking server, or its logs
   and outputs), never by Slurm: submitit catches its timeout signal, so a
   timed-out trial can be `COMPLETED 0:0` in `sacct` although it never finished. Report the GPU-hours used (trials × GPUs ×
   elapsed) and the observed utilisation. Fix poor utilisation before the next
   study.

## Adding a cluster

A new cluster gets its own skill, next to `kuma` and `lyra`, holding:

- the facts a job request depends on: ssh host and login nodes, account,
  partitions with their GPUs, cores and memory per GPU, QoS limits, the driver
  and the highest CUDA version it supports, internet access on login nodes, and
  storage paths, quotas, and purge rules (confirm these from the cluster's
  documentation or `sinfo`/`sacctmgr`, never guess them);
- `assets/clusters/<cluster>.sh`, a profile setting `HOST`, `ACCOUNT`,
  `PACK_ARGS`, `BANNER`, `HOME_NOTE`, and `SCRATCH_NOTE` (and `CACHE_ROOT` when
  scratch is not `/scratch/$USER`);
- `assets/hydra-launcher/<cluster>.yaml` (submitit_slurm with the account,
  default partition, QoS, timeout, GPUs, cores, `array_parallelism`, the
  `name` and `submitit_folder` lines from an existing launcher) and
  `<cluster>_debug.yaml` (a small slice or GPU on the debug QoS);
- the partition choice rule and anything the gate needs beyond this skill.
