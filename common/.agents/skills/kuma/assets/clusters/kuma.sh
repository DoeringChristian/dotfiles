# Kuma (EPFL SCITAS) profile for the slurm skill's cluster.sh. Copy into the project as
# experiments/clusters/kuma.sh, next to experiments/cluster.sh; the pixi task is
# `kuma = "bash experiments/cluster.sh kuma"`.
HOST="${KUMA_HOST:-kuma}"                 # kuma.hpc.epfl.ch round-robins over kuma1/kuma2
DIR="${KUMA_DIR:-$DIR}"
ACCOUNT=rgl
PACK_ARGS="-p l40s --gpus 1 -c 8"         # one L40S, its 8 cores
BANNER='^(SCITAS EPFL|Warning! Authorized|Please read https://scitas)'
HOME_NOTE="/home (quota 100 GB)"
SCRATCH_NOTE="no quota, files older than 30 days purged"
