---
name: kuma
description:
  Facts, partition choice, storage rules, and the cluster profile and Hydra
  launchers for EPFL SCITAS's Kuma GPU cluster (L40S, H100, MIG slices), used
  by the `slurm` skill's `pixi run kuma ...`. Use whenever work touches Kuma, together
  with the `slurm` skill, and before any `pixi run kuma ...` command.
---

# Kuma

Kuma is EPFL SCITAS's pay-per-use GPU cluster. Every allocated GPU-hour is
billed to the lab, whether or not the GPU is used. How projects run on a Slurm
cluster (setup, commands, storage principles, and the mandatory
GPU-efficiency gate) is in the `slurm` skill; load it too. This skill adds
Kuma's specifics.

## Set up a project for Kuma

Follow the `slurm` skill's "Set up a project", with these files:

- [`assets/clusters/kuma.sh`](assets/clusters/kuma.sh) → `experiments/clusters/kuma.sh`
  (next to `experiments/cluster.sh`);
- [`assets/hydra-launcher/kuma.yaml`](assets/hydra-launcher/kuma.yaml) and
  [`kuma_debug.yaml`](assets/hydra-launcher/kuma_debug.yaml) → `configs/hydra/launcher/`;
- the pixi task `kuma = "bash experiments/cluster.sh kuma"`;
- PyTorch from the `cu126` wheel index (Kuma's driver allows CUDA 12.6 at most).

`KUMA_HOST` and `KUMA_DIR` override the profile's host and project directory,
for example `KUMA_HOST=cdoering@kuma1.hpc.epfl.ch` to reach one login node.

## Cluster facts

| | |
|---|---|
| Access | `ssh kuma` (user `cdoering`, key auth; `kuma.hpc.epfl.ch` round-robins over `kuma1`/`kuma2`). pixi in `~/.pixi/bin` (`pixi run kuma setup`). Projects in `~/projects/<name>`. |
| Account | `rgl`. A partition must always be named, because Kuma has no default. |
| Partitions | **`l40s` (default)**: 8× L40S 48 GB/node, ≤ 8 cores/GPU, strong FP32/TF32/BF16, no useful FP64 · `h100`: 4× H100 94 GB/node, ≤ 16 cores/GPU · `mig12gb`/`mig24gb`: H100 slices, ≤ 2/≤ 5 cores, for debugging and measurement |
| QoS | `normal` (default, 3 d, 8 nodes) · `long` (7 d, low priority) · `debug` (1 h, ≤ 2 GPUs, one job at a time; only smoke tests and measurement, as SCITAS revokes access for misuse) · `build` (CPU only: 1 node, 16 cores, 4 h, one job) |
| Memory | Fixed 5900 MB per allocated core. `--mem` cannot raise it, so request cores. |
| Driver | 560.35, so CUDA ≤ 12.6. Use `cu126` PyTorch wheels. pixi provides CUDA. |
| Storage | `/home` 100 GB hard quota · `/scratch` no quota, 30-day purge · `/tmp` node-local NVMe in jobs. See Storage. |
| Login nodes | Internet access. Only for pushing, `pixi install`, and the waiting Hydra launcher process; never for computation. |

Choose `h100` only when one of these holds: the job needs more than 48 GB of
GPU memory, it needs FP64, or a measured speedup outweighs the higher cost.
`smoke` runs on a `mig12gb` slice; when a trial's behaviour depends on the full
card, measure with a short one-trial `submit` on `l40s` instead.

## Storage (check before every install and every study)

The `/home` quota is shared by everything in the account: every project, every
environment, and every cache. Hitting it breaks installs, runs, and other
sessions' work at once. The `slurm` skill's Storage table applies, with these
Kuma paths and limits:

| What | Where | Why |
|---|---|---|
| Code, configs, `pixi.lock`, `outputs/` | `~/projects/<name>` (`/home`) | small, backed up, never purged |
| pixi environments (`.pixi/`) and pixi's cache (`~/.cache/rattler`) | `/home`, together | hardlinked: one CUDA torch stack (~14 GB) is shared by all projects on the same versions |
| Kernel and model caches | `/scratch/$USER/.cache/<tool>` | re-creatable; `cluster.sh` exports their variables for every command and job. `kuma setup` links `~/.drjit` there for Dr.Jit < 1.5. |
| Checkpoints, renders, intermediate arrays, datasets | `/scratch/$USER/<project>/` | bulky and re-creatable. Pull, log to the tracking server, or regenerate anything a report needs within 30 days. |
| Job-local temporaries and staged inputs | `/tmp` inside the job | node-local NVMe, fastest, gone after the job |
| Large data that must outlive the purge | `/work/rgl/<user>` | paid lab storage, no purge. Only with the user's explicit consent. |

Keep `/home` under about 70 GB (`pixi run kuma storage`).

## Notes

- Heavy CPU preprocessing runs as a `build`-QoS job without GPUs.
- SCITAS documentation: <https://scitas-doc.epfl.ch/supercomputers/kuma/>.
