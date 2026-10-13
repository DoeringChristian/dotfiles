#!/usr/bin/env bash
# Run this pixi + Hydra project on a Slurm cluster. Copy into the project (for example as
# experiments/cluster.sh), add the cluster's profile as experiments/clusters/<cluster>.sh, and
# call it through one pixi task per cluster, `<cluster> = "bash experiments/cluster.sh <cluster>"`:
#
#   pixi run <cluster> setup                  # once per account: pixi on the cluster, project directory
#   pixi run <cluster> push                   # rsync the working tree (incl. .git) and `pixi install --frozen`
#   pixi run <cluster> smoke <overrides>      # push, then a foreground study on the debug launcher
#   pixi run <cluster> submit <overrides>     # push, then a detached study: one Slurm array task per trial
#   pixi run <cluster> pack -t 2:00:00 [sbatch options] -- <overrides>
#                                             # push, then every trial in sequence inside one GPU job
#   pixi run <cluster> status                 # your jobs and the newest launcher logs
#   pixi run <cluster> gpu <jobid>            # live GPU utilisation of a running job (or <jobid>_<n>)
#   pixi run <cluster> pull                   # rsync outputs/ back (no deletion)
#   pixi run <cluster> finalize <study-dir>   # complete a study whose launcher process died
#   pixi run <cluster> storage                # /home and /scratch use
#   pixi run <cluster> ssh <command...>       # any command in the remote project, pixi on PATH
#
# Overrides are Hydra overrides for the project's Hydra app, started through its pixi task
# `experiment` (CLUSTER_ENTRY overrides the whole command). `smoke` and `submit` use the Hydra
# launchers configs/hydra/launcher/<cluster>_debug.yaml and <cluster>.yaml, so nothing GPU-bound
# runs on the login node. Runs are written under outputs/; finalize needs finalize_study.py
# next to this script.
#
# Every remote command, and through Slurm's environment export every job, sends re-creatable
# kernel and model caches to the profile's CACHE_ROOT (on /scratch), so they never fill /home.
# pixi's own cache stays in /home on purpose: environments are hardlinked from it.
#
# When cairn-report.toml has a [hub], `submit` and `pack` also run `cairn-report push runs --watch`
# on the login node until every Slurm job of this project has left the queue (also when the
# launcher dies); the hub token must exist on the cluster, never in the repository.
#
# The profile (experiments/clusters/<cluster>.sh) is sourced and may set: HOST (ssh host),
# DIR (remote project directory), ACCOUNT (Slurm account), PACK_ARGS (sbatch arguments of a
# pack job, e.g. "-p l40s --gpus 1 -c 8"), CACHE_ROOT, BANNER (grep -E pattern of login banner
# lines to hide), and HOME_NOTE / SCRATCH_NOTE (quota and purge rules shown by `storage`). CLUSTER_HOST, CLUSTER_DIR, and
# CLUSTER_ENTRY override HOST, DIR, and the entry command for one call.
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
help() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$SELF"; }

CLUSTER="${1:-}"
[ $# -gt 0 ] && shift
PROFILE="${SELF%/*}/clusters/$CLUSTER.sh"
if [ -z "$CLUSTER" ] || [ ! -f "$PROFILE" ]; then
    help >&2
    echo "no cluster profile ${PROFILE#"$PWD"/}; copy it from the cluster's skill" >&2
    exit 2
fi

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOST="$CLUSTER"
DIR="projects/$(basename "$PWD")"
ACCOUNT=""
PACK_ARGS="--gpus 1 -c 8"
CACHE_ROOT='/scratch/$USER/.cache'
BANNER='^$'
HOME_NOTE="/home"
SCRATCH_NOTE=""
# shellcheck source=/dev/null
source "$PROFILE"
HOST="${CLUSTER_HOST:-$HOST}"
DIR="${CLUSTER_DIR:-$DIR}"
ENTRY="${CLUSTER_ENTRY:-pixi run --frozen experiment}"  # the Hydra app; overrides are appended
TOOLS="${SELF%/*}"
TOOLS="${TOOLS#"$PWD"/}"                                # this script's folder, relative to the project
LAUNCHER="$CLUSTER"
DEBUG_LAUNCHER="${CLUSTER}_debug"
SBATCH_ACCOUNT="${ACCOUNT:+-A $ACCOUNT}"

quote() {
    local out="" arg
    for arg in "$@"; do out+=" $(printf '%q' "$arg")"; done
    printf '%s' "$out"
}

quiet() { grep -v -E "$BANNER" >&2 || true; }

# Run a shell snippet in the remote project directory with pixi on PATH.
CACHES="export DRJIT_CACHE_DIR=$CACHE_ROOT/drjit \
    TRITON_CACHE_DIR=$CACHE_ROOT/triton TORCHINDUCTOR_CACHE_DIR=$CACHE_ROOT/torchinductor \
    CUDA_CACHE_PATH=$CACHE_ROOT/nv HF_HOME=$CACHE_ROOT/huggingface \
    TORCH_HOME=$CACHE_ROOT/torch"

remote() {
    ssh -q "$HOST" "export PATH=\$HOME/.pixi/bin:\$PATH; $CACHES; cd $(printf '%q' "$DIR") || exit 1; $1"
}

push() {
    ssh -q "$HOST" "mkdir -p $(printf '%q' "$DIR")"
    rsync -az --delete --filter=':- .gitignore' --exclude .pixi/ --exclude outputs/ --exclude generated/ \
        ./ "$HOST:$DIR/" 2> >(quiet)
    remote "pixi install --frozen 2>&1 | tail -1"
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "note: uncommitted changes were pushed; runs record them as a patch against $(git rev-parse --short HEAD 2>/dev/null || echo 'no commit')" >&2
    fi
}

# Remote snippet: true while a Slurm job submitted from this project directory is queued.
PROJECT_JOBS_QUEUED="squeue -h --me -o %Z | grep -qxF \"\$PWD\""

launch_log() { echo "outputs/.launch/\$(date +%Y%m%d-%H%M%S)-\$(hostname -s)-$1.log"; }

command="${1:-}"
[ $# -gt 0 ] && shift
case "$command" in
    setup)
        ssh -q "$HOST" "test -x \$HOME/.pixi/bin/pixi || curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash
            \$HOME/.pixi/bin/pixi config set --global cache.netfs-redirect never >/dev/null
            mkdir -p $CACHE_ROOT/drjit
            # Dr.Jit < 1.5 ignores DRJIT_CACHE_DIR and always uses ~/.drjit.
            if [ -d \$HOME/.drjit ] && [ ! -L \$HOME/.drjit ]; then
                echo \"warning: ~/.drjit is a real directory (\$(du -sh \$HOME/.drjit | cut -f1)); it is a re-creatable kernel cache, remove it so it can become a link to $CACHE_ROOT\" >&2
            else
                ln -sfn $CACHE_ROOT/drjit \$HOME/.drjit
            fi
            mkdir -p $(printf '%q' "$DIR") && \$HOME/.pixi/bin/pixi --version"
        ;;
    push)
        push
        ;;
    smoke)
        push
        remote "$ENTRY -m hydra/launcher=$DEBUG_LAUNCHER$(quote "$@")"
        ;;
    submit)
        push
        study="$ENTRY -m hydra/launcher=$LAUNCHER$(quote "$@")"
        remote "mkdir -p outputs/.launch; log=$(launch_log submit)
            if grep -qs '^\[hub\]' cairn-report.toml; then
                set -- pixi run --frozen cairn-report push runs --watch -- bash -c $(printf '%q' "$study; rc=\$?; while $PROJECT_JOBS_QUEUED; do sleep 60; done; exit \$rc")
            else
                set -- $study
            fi
            nohup setsid \"\$@\" > \$log 2>&1 < /dev/null &
            sleep 15; echo \"launcher log: \$log\"; cat \"\$log\" < /dev/null; squeue --me"
        ;;
    pack)
        sbatch_args=()
        while [ $# -gt 0 ] && [ "$1" != "--" ]; do sbatch_args+=("$1"); shift; done
        [ "${1:-}" = "--" ] && shift
        case " ${sbatch_args[*]-} " in
            *" -t "* | *" --time"*) ;;
            *) echo "pack needs an explicit time limit (-t HH:MM:SS) from a measured trial" >&2; exit 2 ;;
        esac
        push
        remote "mkdir -p outputs/.launch && id=\$(sbatch --parsable $SBATCH_ACCOUNT $PACK_ARGS -J pack \
            -o outputs/.launch/pack-%j.out$(quote "${sbatch_args[@]}") \
            --wrap \"export PATH=\\\$HOME/.pixi/bin:\\\$PATH; $ENTRY -m$(quote "$@")\") &&
            echo \"submitted job \$id, log outputs/.launch/pack-\$id.out\" &&
            if grep -qs '^\[hub\]' cairn-report.toml; then
                nohup setsid pixi run --frozen cairn-report push runs --watch -- \
                    bash -c $(printf '%q' "while $PROJECT_JOBS_QUEUED; do sleep 60; done") \
                    > outputs/.launch/pack-\$id-hub-\$(hostname -s).log 2>&1 < /dev/null &
            fi"
        ;;
    status)
        remote "squeue --me -o '%.18i %.9P %.20j %.2t %.10M %.10l %.5D %R'; echo;
            for f in \$(ls -t outputs/.launch/* 2>/dev/null | head -3); do echo \"== \$f\"; tail -n 4 \$f; done"
        ;;
    gpu)
        [ $# -eq 1 ] || { echo "usage: $CLUSTER gpu <jobid>[_<n>]" >&2; exit 2; }
        remote "srun --jobid $(printf '%q' "$1") --overlap nvidia-smi \
            --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv"
        ;;
    pull)
        mkdir -p outputs
        rsync -az --exclude '*.pkl' "$HOST:$DIR/outputs/" outputs/ 2> >(quiet)
        ;;
    finalize)
        [ $# -eq 1 ] || { echo "usage: $CLUSTER finalize outputs/<run-name>/<timestamp>" >&2; exit 2; }
        # The hub watcher has exited by now, so send the finalized run.json to the hub here.
        remote "pixi run --frozen python $(printf '%q' "$TOOLS/finalize_study.py")$(quote "$1") &&
            if grep -qs '^\[hub\]' cairn-report.toml; then pixi run --frozen cairn-report push runs; fi"
        ;;
    storage)
        remote "echo \"$HOME_NOTE: \$(du -sh \$HOME 2>/dev/null | cut -f1) in total\"
            du -sh \$HOME/.cache/* \$HOME/projects/* \$HOME/.[!.]* 2>/dev/null | sort -h | tail -8 | sed 's/^/  /'
            echo '  (environments are hardlinked from ~/.cache/rattler; per-folder sizes overlap)'
            echo \"/scratch/\$USER${SCRATCH_NOTE:+ ($SCRATCH_NOTE)}: \$(du -sh /scratch/\$USER 2>/dev/null | cut -f1)\""
        ;;
    ssh)
        remote "$(quote "$@")"
        ;;
    *)
        help
        exit 2
        ;;
esac
