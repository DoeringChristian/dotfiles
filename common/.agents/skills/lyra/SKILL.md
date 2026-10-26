---
name: lyra
description:
  Facts, partition choice, and the cluster profile and Hydra launchers for
  EPFL SCITAS's Lyra GPU cluster (Blackwell B200, RTX PRO 6000 and its GPU
  slices), used by the `slurm` skill's `pixi run lyra ...`. Use whenever work touches Lyra,
  together with the `slurm` skill, and before any `pixi run lyra ...` command.
---

# Lyra

Lyra is an EPFL SCITAS GPU cluster with NVIDIA Blackwell GPUs. GPU time is
billed whether or not the GPU is used. How projects run on a Slurm cluster
(setup, commands, storage principles, and the mandatory GPU-efficiency gate) is
in the `slurm` skill; load it too. This skill adds Lyra's specifics.

## Set up a project for Lyra

Follow the `slurm` skill's "Set up a project", with these files:

- [`assets/clusters/lyra.sh`](assets/clusters/lyra.sh) → `experiments/clusters/lyra.sh`
  (next to `experiments/cluster.sh`);
- [`assets/hydra-launcher/lyra.yaml`](assets/hydra-launcher/lyra.yaml) and
  [`lyra_debug.yaml`](assets/hydra-launcher/lyra_debug.yaml) → `configs/hydra/launcher/`;
- the pixi task `lyra = "bash experiments/cluster.sh lyra"`;
- PyTorch with CUDA ≥ 12.8: Blackwell GPUs (B200, RTX PRO 6000) need it, so use
  the `cu128` (or newer) wheel index. A project that also runs on Kuma (CUDA ≤
  12.6) needs a separate pixi environment per cluster.

`LYRA_HOST` and `LYRA_DIR` override the profile's host and project directory,
for example `LYRA_HOST=cdoering@lyra3.hpc.epfl.ch` to reach one login node.

## Cluster facts

Confirmed with `sinfo` and `sacctmgr` on the login node:

| | |
|---|---|
| Access | `ssh lyra` (user `cdoering`, key auth, `lyra.hpc.epfl.ch`; login nodes such as `lyra3`). pixi is installed in `~/.pixi/bin`. Projects in `~/projects/<name>`. |
| Account | `rgl`, with QoS `normal`, `long`, `debug`, `build`. |
| Partitions | **`rtx6000` (default)**: 12 nodes × 8 RTX PRO 6000 Blackwell Server Edition, 128 cores and ~770 GB RAM per node (16 cores per GPU) · `b200`: 8 nodes × 8 B200, 96 cores and ~1.5 TB RAM per node (12 cores per GPU) · `rtx6000_1g.24gb`: 1 node, 32 slices of 24 GB · `rtx6000_2g.48gb`: 1 node, 16 slices of 48 GB |
| QoS | `normal` (3 d) · `long` (7 d, low priority) · `debug` (1 h, one job at a time; only smoke tests and measurement) · `build` (4 h, one job; CPU work) |
| Login nodes | Internet access (pixi installs work). No GPUs: only for pushing, `pixi install`, and the waiting Hydra launcher process; never for computation. |
| Storage | `/home` and `/scratch` are shared filesystems; `/work/<group>` exists for paid lab storage. **`/home` holds code and pixi environments only, never data**: run outputs, downloaded inputs, checkpoints, caches, and datasets go to `/scratch/cdoering/<project>/` (`outputs/` linked there by `lyra setup`). |

Choose `b200` only when one of these holds: the job needs more GPU memory than
an RTX PRO 6000 has, it needs strong FP64, or a measured speedup outweighs the
higher cost. `smoke` runs on an `rtx6000_1g.24gb` slice; when a trial's
behaviour depends on the full card, measure with a short one-trial `submit` on
`rtx6000` instead. Request at most 16 cores per GPU on `rtx6000` and 12 on
`b200`.

## Not yet confirmed

Check these before relying on them, from the SCITAS documentation
(<https://scitas-doc.epfl.ch/supercomputers/>) or on the cluster, and then
record them in this skill:

- **The driver and its highest CUDA version.** Login nodes have no GPU; read
  it in the first `smoke` (`nvidia-smi` in a job, or `pixi run lyra gpu <jobid>`
  while it runs).
- **The `/home` quota and the `/scratch` purge rule.** The `/home` quota is
  small: on 2026-10-24 about 100 GB of run outputs and downloaded checkpoints in
  one project's `outputs/` made every write fail ("Disk quota exceeded"). Treat
  `/scratch` as purged after 30 days until the rule is confirmed.
- **Memory per core.** Whether memory is tied to allocated cores, as on Kuma.
- **Whether a partition must always be named.** The launchers and the profile
  always name one, so this does not block jobs.

## Notes

- Heavy CPU preprocessing runs as a `build`-QoS job without GPUs.
- `/work/<group>` storage only with the user's explicit consent.
