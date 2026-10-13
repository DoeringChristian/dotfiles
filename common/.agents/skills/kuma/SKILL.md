---
name: kuma
description:
  Rules for running pixi + Hydra research projects on EPFL's Kuma GPU cluster,
  including the mandatory GPU-efficiency gate before any job is submitted. Use
  whenever work touches Kuma, the cluster, Slurm, sbatch, GPU jobs, or running
  experiments or sweeps remotely, and before any `pixi run kuma ...` command.
  The project mechanics (`pixi run kuma ...` and its assets) live in the
  standalone-research-project skill.
---

# Kuma

Kuma is EPFL SCITAS's pay-per-use GPU cluster. Every allocated GPU-hour is
billed to the lab, whether or not the GPU is used, so **idle GPU time is wasted
money**.

Projects reach Kuma only through pixi: `pixi run kuma <command>`, defined by
`experiments/kuma.sh` and `configs/hydra/launcher/kuma*.yaml` from the
`standalone-research-project` skill (section "Running on Kuma"). Any other
pixi + Hydra project adopts the same assets. It needs:

- `linux-64` in its platforms;
- the `hydra-submitit-launcher` dependency and the `kuma` task;
- an `experiments/run.py` entry point.

Never call `sbatch`, `srun`, or `module load` around pixi by hand. If a command
is missing, extend `kuma.sh` in the skill's assets.

## Cluster facts

| | |
|---|---|
| Access | `ssh kuma` (user `cdoering`, key auth; `kuma.hpc.epfl.ch` round-robins over `kuma1`/`kuma2`). pixi in `~/.pixi/bin` (`pixi run kuma setup`). Projects in `~/projects/<name>`. |
| Account | `rgl`. A partition must always be named, because Kuma has no default. |
| Partitions | **`l40s` (default)**: 8× L40S 48 GB/node, ≤ 8 cores/GPU, strong FP32/TF32/BF16, no useful FP64 · `h100`: 4× H100 94 GB/node, ≤ 16 cores/GPU · `mig12gb`/`mig24gb`: H100 slices, ≤ 2/≤ 5 cores, for debugging and measurement |
| QoS | `normal` (default, 3 d, 8 nodes) · `long` (7 d, low priority) · `debug` (1 h, ≤ 2 GPUs, one job at a time; only smoke tests and measurement, as SCITAS revokes access for misuse) · `build` (CPU only: 1 node, 16 cores, 4 h, one job) |
| Memory | Fixed 5900 MB per allocated core. `--mem` cannot raise it, so request cores. |
| Driver | 560.35, so CUDA ≤ 12.6. Use `cu126` PyTorch wheels. pixi provides CUDA. |
| Storage | `/home` (project, `outputs/`): 100 GB quota, backed up. `/scratch/cdoering`: no quota, no backup, **files older than 30 days deleted without notice**, so only re-creatable data and caches go there. `/tmp` inside a job: node-local NVMe. |
| Login nodes | Internet access. Only for pushing, `pixi install`, and the waiting Hydra launcher process; never for computation. |

Choose `h100` only when one of these holds: the job needs more than 48 GB of
GPU memory, it needs FP64, or a measured speedup outweighs the higher cost.

## GPU-efficiency gate (mandatory before every `submit` or `pack`)

Do not submit until each point is checked. In the reply to the user, state the
measured numbers.

1. **Keep non-GPU work out of GPU jobs.**
   - `pixi run kuma push` installs the environment on the login node before
     any job starts.
   - Download data and build dataset caches before submission: small ones on
     the login node, heavy CPU preprocessing as a `build`-QoS job without GPUs.
     Store them under `/scratch/cdoering/<project>/`.
   - A GPU job must never wait on an install, a download, or a cold cache.
2. **Measure one representative trial first** with `pixi run kuma smoke`. Use
   the smallest config that still shows production behaviour. Record:
   - time per step or iteration
   - total wall time
   - peak GPU memory
   - GPU utilisation while it runs (`pixi run kuma gpu <jobid>_<n>`, after
     the ~30 s of imports and CUDA start-up, which read as 0 %)

   The target is sustained utilisation of ≳ 80 %. The smoke slice is a MIG
   partition, so when the trial's behaviour depends on the full card, measure
   with a short `submit` of one trial on `l40s` instead.
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
   - Request only the cores the input pipeline uses (`hydra.launcher.cpus_per_task`).
   - Set `hydra.launcher.timeout_min` to about 1.3× the measured trial time.
     Short limits backfill sooner, and a hung trial then burns minutes, not
     days.
5. **Pack small work.** A short trial (≲ 10 min), or one that leaves the GPU
   mostly idle, should not get its own job: start-up, imports, and CUDA init
   then dominate. Instead, either vectorise seeds or configs inside one
   `Experiment` (an in-run grid, batched dims or `vmap`), or chain the sweep in
   one allocation with `pixi run kuma pack -t <total> -- <sweep>`. Use
   `submit` (one array task per trial) only when trials are long enough to
   justify separate jobs.
6. **Never hold idle allocations.**
   - No open interactive sessions while thinking or editing.
   - No placeholder jobs.
   - `pixi run kuma ssh scancel <jobid>` as soon as a running study is moot
     (a bug found, a superseded config).
7. **Audit afterwards.** Run `pixi run kuma ssh seff <jobid>_<n>` on a few
   trials and compare the elapsed time with the limit. Judge success by each
   trial's `run.json`, never by Slurm: submitit catches its timeout signal, so a
   timed-out trial is `failed` in `run.json` but `COMPLETED 0:0` in `sacct`. Report the GPU-hours
   used (trials × GPUs × elapsed) and the observed utilisation. Fix poor
   utilisation before the next study.

## Operating notes

- Pull results with `pixi run kuma pull`, promptly. Keep `outputs/` small:
  write checkpoints and other bulky, re-creatable files to
  `/scratch/cdoering/<project>/` and record their paths in the run. Check the
  quota with `pixi run kuma ssh du -sh '~'`.
- A launcher process that died leaves its study without `run.json`. Check
  `pixi run kuma status`. Once the study's jobs have left the queue, run
  `pixi run kuma finalize <study-dir>`. The launcher log name gives the login
  node it ran on, if you need to inspect that node.
- SCITAS documentation: <https://scitas-doc.epfl.ch/supercomputers/kuma/>.
