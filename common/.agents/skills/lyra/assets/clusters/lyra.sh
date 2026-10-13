# Lyra (EPFL SCITAS) profile for the slurm skill's cluster.sh. Copy into the project as
# experiments/clusters/lyra.sh, next to experiments/cluster.sh; the pixi task is
# `lyra = "bash experiments/cluster.sh lyra"`.
HOST="${LYRA_HOST:-lyra}"                 # lyra.hpc.epfl.ch (several login nodes, e.g. lyra3)
DIR="${LYRA_DIR:-$DIR}"
ACCOUNT=rgl
PACK_ARGS="-p rtx6000 --gpus 1 -c 8"      # one RTX PRO 6000 (16 cores per GPU on these nodes)
BANNER='^(SCITAS EPFL|Warning! Authorized|Please read https://scitas)'
HOME_NOTE="/home (check the quota in the SCITAS documentation)"
SCRATCH_NOTE="check the purge rule in the SCITAS documentation"
