#!/usr/bin/env bash
# Run this project on EPFL's Kuma GPU cluster. Copy into a project as experiments/kuma.sh
# and call it through the pixi task `kuma = "bash experiments/kuma.sh"`:
#
#   pixi run kuma setup                  # once per account: pixi on Kuma, project directory
#   pixi run kuma push                   # rsync the working tree (incl. .git) and `pixi install --frozen`
#   pixi run kuma smoke <overrides>      # push, then a foreground study on a MIG slice (debug QoS)
#   pixi run kuma submit <overrides>     # push, then a detached study: one Slurm array task per trial
#   pixi run kuma pack -t 2:00:00 [sbatch options] -- <overrides>
#                                        # push, then every trial in sequence inside one GPU job
#   pixi run kuma status                 # your jobs and the newest launcher logs
#   pixi run kuma gpu <jobid>            # live GPU utilisation of a running job (or <jobid>_<n>)
#   pixi run kuma pull                   # rsync outputs/ back (no deletion)
#   pixi run kuma finalize <study-dir>   # complete a study whose launcher process died
#   pixi run kuma ssh <command...>       # any command in the remote project, pixi on PATH
#
# Overrides are Hydra overrides for experiments/run.py; every study uses the Slurm
# launcher in configs/hydra/launcher/, so nothing GPU-bound runs on the login node.
# When cairn-report.toml has a [hub], the login node runs `cairn-report push --watch`
# until every Slurm job of this project has left the queue (also when the launcher dies),
# so evidence reaches the hub while trials run; the hub token must exist on Kuma (CAIRN_HUB_TOKEN or the
# configured chmod-600 token_file), never in the repository.
# KUMA_HOST (default kuma) and KUMA_DIR (default projects/<project directory name>) override the target.
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOST="${KUMA_HOST:-kuma}"
DIR="${KUMA_DIR:-projects/$(basename "$PWD")}"

quote() {
    local out="" arg
    for arg in "$@"; do out+=" $(printf '%q' "$arg")"; done
    printf '%s' "$out"
}

# Run a shell snippet in the remote project directory with pixi on PATH.
remote() {
    ssh -q "$HOST" "export PATH=\$HOME/.pixi/bin:\$PATH; cd $(printf '%q' "$DIR") || exit 1; $1"
}

push() {
    ssh -q "$HOST" "mkdir -p $(printf '%q' "$DIR")"
    rsync -az --delete --filter=':- .gitignore' --exclude .pixi/ --exclude outputs/ --exclude generated/ \
        ./ "$HOST:$DIR/" 2> >(grep -v -e '^SCITAS EPFL' -e '^Warning! Authorized' -e '^Please read https://scitas' >&2)
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
            mkdir -p $(printf '%q' "$DIR") && \$HOME/.pixi/bin/pixi --version"
        ;;
    push)
        push
        ;;
    smoke)
        push
        remote "pixi run --frozen experiment -m hydra/launcher=kuma_debug$(quote "$@")"
        ;;
    submit)
        push
        study="python experiments/run.py -m hydra/launcher=kuma$(quote "$@")"
        remote "mkdir -p outputs/.launch; log=$(launch_log submit)
            if grep -qs '^\[hub\]' cairn-report.toml; then
                set -- cairn-report push --watch -- bash -c $(printf '%q' "$study; rc=\$?; while $PROJECT_JOBS_QUEUED; do sleep 60; done; exit \$rc")
            else
                set -- $study
            fi
            nohup setsid pixi run --frozen \"\$@\" > \$log 2>&1 < /dev/null &
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
        remote "mkdir -p outputs/.launch && id=\$(sbatch --parsable -A rgl -p l40s --gpus 1 -c 8 -J pack \
            -o outputs/.launch/pack-%j.out$(quote "${sbatch_args[@]}") \
            --wrap \"export PATH=\\\$HOME/.pixi/bin:\\\$PATH; pixi run --frozen experiment -m$(quote "$@")\") &&
            echo \"submitted job \$id, log outputs/.launch/pack-\$id.out\" &&
            if grep -qs '^\[hub\]' cairn-report.toml; then
                nohup setsid pixi run --frozen cairn-report push --watch -- \
                    bash -c $(printf '%q' "while $PROJECT_JOBS_QUEUED; do sleep 60; done") \
                    > outputs/.launch/pack-\$id-hub-\$(hostname -s).log 2>&1 < /dev/null &
            fi"
        ;;
    status)
        remote "squeue --me -o '%.18i %.9P %.20j %.2t %.10M %.10l %.5D %R'; echo;
            for f in \$(ls -t outputs/.launch/* 2>/dev/null | head -3); do echo \"== \$f\"; tail -n 4 \$f; done"
        ;;
    gpu)
        [ $# -eq 1 ] || { echo "usage: kuma gpu <jobid>[_<n>]" >&2; exit 2; }
        remote "srun --jobid $(printf '%q' "$1") --overlap nvidia-smi \
            --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv"
        ;;
    pull)
        mkdir -p outputs
        rsync -az --exclude '*.pkl' "$HOST:$DIR/outputs/" outputs/ \
            2> >(grep -v -e '^SCITAS EPFL' -e '^Warning! Authorized' -e '^Please read https://scitas' >&2)
        ;;
    finalize)
        [ $# -eq 1 ] || { echo "usage: kuma finalize outputs/<run-name>/<timestamp>" >&2; exit 2; }
        remote "pixi run --frozen python experiments/finalize_study.py$(quote "$1")"
        ;;
    ssh)
        remote "$(quote "$@")"
        ;;
    *)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
