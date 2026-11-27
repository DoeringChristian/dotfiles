#!/usr/bin/env bash
# Run this pixi + Hydra project's tasks on a machine reachable by ssh (a GPU workstation).
# Copy into the project as experiments/ssh.sh and add one pixi task per machine,
# `<host> = "bash experiments/ssh.sh <host>"` (the ssh host name, as in ~/.ssh/config):
#
#   pixi run <host> setup                         # once: pixi on the machine, the project directory
#   pixi run <host> [-g GPUS] <task> [overrides]  # push, then start `pixi run <task> <overrides>` detached
#   pixi run <host> status                        # GPUs, this project's launched tasks, newest logs
#   pixi run <host> log [file]                    # follow the newest (or the named) launch log
#   pixi run <host> stop <pid>                    # stop a launched task and everything it started
#   pixi run <host> pull                          # rsync the run folder back (no deletion)
#   pixi run <host> push                          # rsync the working tree (incl. .git), pixi install
#   pixi run <host> ssh <command...>              # any command in the remote project, pixi on PATH
#
# `-g 1` or `-g 0,1` sets CUDA_VISIBLE_DEVICES for the task. Launch logs and pid files go to
# <run folder>/.launch/. SSH_DIR (default projects/<project>) and SSH_OUTPUTS (the run folder,
# default runs) change the remote directory and the folder that is pulled.
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
help() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$SELF"; }

HOST="${1:-}"
[ $# -gt 0 ] && shift
[ -n "$HOST" ] || { help >&2; exit 2; }

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DIR="${SSH_DIR:-projects/$(basename "$PWD")}"
OUT="${SSH_OUTPUTS:-runs}"

quote() {
    local out="" arg
    for arg in "$@"; do out+=" $(printf '%q' "$arg")"; done
    printf '%s' "$out"
}

# Run a shell snippet in the remote project directory with pixi on PATH.
remote() { ssh -q "$HOST" "export PATH=\$HOME/.pixi/bin:\$PATH; cd $(printf '%q' "$DIR") || exit 1; $1"; }

push() {
    ssh -q "$HOST" "mkdir -p $(printf '%q' "$DIR")"
    rsync -az --delete --filter=':- .gitignore' --exclude .pixi/ --exclude "/$OUT" ./ "$HOST:$DIR/"
    remote "pixi install --frozen 2>&1 | tail -1"
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "note: uncommitted changes were pushed; runs record them in git_diff.patch" >&2
    fi
}

command="${1:-}"
[ $# -gt 0 ] && shift
case "$command" in
    "" | -h | --help | help)
        help
        ;;
    setup)
        ssh -q "$HOST" "test -x \$HOME/.pixi/bin/pixi || curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash
            mkdir -p $(printf '%q' "$DIR") && \$HOME/.pixi/bin/pixi --version"
        ;;
    push)
        push
        ;;
    status)
        remote "nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null || echo 'no nvidia-smi'
            echo; for f in \$(ls -t $OUT/.launch/*.pid 2>/dev/null); do
                pid=\$(cat \$f); if kill -0 \$pid 2>/dev/null; then state=running; else state=ended; fi
                echo \"\$state  pid \$pid  \${f%.pid}.log\"; done | head -10
            for f in \$(ls -t $OUT/.launch/*.log 2>/dev/null | head -2); do echo; echo \"== \$f\"; tail -n 4 \$f; done"
        ;;
    log)
        if [ $# -ge 1 ]; then f=$(printf '%q' "$1"); else f="\$(ls -t $OUT/.launch/*.log | head -1)"; fi
        remote "f=$f; echo \"== \$f\"; tail -n 40 -f \$f"
        ;;
    stop)
        [ $# -eq 1 ] || { echo "usage: $HOST stop <pid>" >&2; exit 2; }
        pid=$(printf '%q' "$1")
        # setsid made the task a process-group leader: stop the whole group, else the process.
        remote "{ kill -TERM -- -$pid 2>/dev/null || kill -TERM $pid; } && echo stopped $pid"
        ;;
    pull)
        mkdir -p "$OUT"
        rsync -az --exclude '.launch/' "$HOST:$DIR/$OUT/" "$OUT/"
        ;;
    ssh)
        remote "$(quote "$@")"
        ;;
    *)
        gpus=""
        if [ "$command" = "-g" ]; then
            [ $# -ge 1 ] || { echo "usage: $HOST -g GPUS <task> [overrides]" >&2; exit 2; }
            gpus="$1"; shift
            command="${1:-}"; [ $# -gt 0 ] && shift
        fi
        [ -n "$command" ] || { help >&2; exit 2; }
        push
        env=""
        [ -n "$gpus" ] && env="CUDA_VISIBLE_DEVICES=$(printf '%q' "$gpus") "
        remote "mkdir -p $OUT/.launch; base=$OUT/.launch/\$(date +%Y-%m-%d_%H-%M-%S)-$(printf '%q' "$command")
            ${env}nohup setsid pixi run --frozen$(quote "$command" "$@") > \$base.log 2>&1 < /dev/null &
            echo \$! > \$base.pid
            sleep 5; echo \"started pid \$(cat \$base.pid) on \$(hostname -s), log \$base.log\"; tail -n 5 \$base.log"
        ;;
esac
