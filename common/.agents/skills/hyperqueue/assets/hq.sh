#!/usr/bin/env bash
# Run this pixi + Hydra + Cairn project on the lab's HyperQueue cluster (head fermat; workers fermat, kerr, gabor,
# arago; started with `hqc up`). Copy into the project as experiments/hq.sh, with hydra_plugins/hq_launcher.py and
# configs/hydra/launcher/hq.yaml and hq_debug.yaml, and add the pixi task `hq = "bash experiments/hq.sh"`:
#
#   pixi run hq setup                  # once per project: push, then every checkout (and this one) syncs to the hub
#   pixi run hq push                   # rsync the working tree (incl. .git) to every node, `pixi install --frozen` there
#   pixi run hq smoke <overrides>      # push, then a study in the foreground (launcher hq_debug) from the head
#   pixi run hq submit <overrides>     # push, then a detached study: one HQ task per trial, on any free node
#   pixi run hq status                 # workers, this project's jobs, the newest launcher logs
#   pixi run hq gpu                    # GPU use on every node
#   pixi run hq finalize <sweep-dir>   # complete a study whose launcher died, once its tasks ended
#   pixi run hq ssh [@node] <cmd...>   # a command in the project's checkout on the head (or on that node)
#
# Overrides are Hydra overrides for the project's `experiment` task (CLUSTER_ENTRY replaces it). There is no shared
# filesystem: each node has its own checkout (`<root>/<project>`, roots in ~/.hq-cluster/nodes on the head) and its
# own .cairn/ repo, whose remote is the Cairn hub on the head; every run reaches the hub, and this checkout reads
# them from there (`pixi run pull`, `pixi run ui`). The launcher runs on the head and merges each sweep back there
# (see hq_launcher.py). HQC_HEAD overrides the head.
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
HEAD="${HQC_HEAD:-fermat}"
ENTRY="${CLUSTER_ENTRY:-pixi run --frozen experiment}"
STATE='$HOME/.hq-cluster'
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT="$(basename "$PWD")"
SCRIPT="${SELF#"$PWD"/}"

quote() {
    local out="" arg
    for arg in "$@"; do out+=" $(printf '%q' "$arg")"; done
    printf '%s' "$out"
}

# ---------------------------------------------------------------- on the head, in its checkout (`--head <command>`)
if [ "${1:-}" = --head ]; then
    shift
    export PATH="$HOME/.pixi/bin:$HOME/.local/bin:$PATH"
    STATE="$HOME/.hq-cluster"
    # shellcheck source=/dev/null
    source "$STATE/cluster.conf"
    HUB="http://$HEAD_ADDR:$HUB_PORT/$PROJECT"
    hq() { "$HOME/.hq-cluster/bin/hq" --server-dir "$STATE" "$@"; }
    others() { awk -v h="$HEAD" '!/^#/ && NF && $1 != h { print $1, $2 }' "$STATE/nodes"; }
    root_of() { awk -v n="$1" '$1 == n { print $2 }' "$STATE/nodes"; }
    install_env() { pixi install --frozen 2>&1 | tail -1 | sed "s/^/$HEAD: /"; }
    command="$1"
    shift
    case "$command" in
        push)  # from the head's checkout to every other node's, in parallel
            install_env &
            while read -r node root; do
                (
                    ssh -n -q "$node" "mkdir -p $root/$PROJECT" &&
                        rsync -az --delete --filter=':- .gitignore' --exclude /.pixi/ --exclude /.cairn/ --exclude /outputs/ \
                            ./ "$node:$root/$PROJECT/" &&
                        ssh -n -q "$node" "cd $root/$PROJECT && ~/.pixi/bin/pixi install --frozen 2>&1 | tail -1" |
                        sed "s/^/$node: /"
                ) &
            done < <(others)
            wait
            ;;
        setup)  # every checkout: a Cairn repo whose remote is the hub, with the hub's token (sent on stdin)
            connect="(test -f .cairn/config.toml || ~/.pixi/bin/pixi run --frozen cairn init > /dev/null) &&
                (umask 077 && cat > .cairn/token) && ~/.pixi/bin/pixi run --frozen cairn remote set $HUB | grep -v '^remote'"
            bash -c "$connect" < "$HUB_DIR/repo/token" | sed "s/^/$HEAD: /"
            while read -r node root; do
                ssh -q "$node" "cd $root/$PROJECT && $connect" < "$HUB_DIR/repo/token" | sed "s/^/$node: /"
            done < <(others)
            ;;
        smoke)
            $ENTRY -m hydra/launcher=hq_debug "$@"
            ;;
        submit)
            mkdir -p outputs/.launch
            log="outputs/.launch/$(date +%Y%m%d-%H%M%S)-hq-submit.log"
            nohup setsid $ENTRY -m hydra/launcher=hq "$@" > "$log" 2>&1 < /dev/null &
            sleep 20
            echo "launcher log ($HEAD): $log"
            cat "$log"
            hq job list
            ;;
        status)
            hq worker list
            hq job list --filter waiting,running,failed,canceled 2>/dev/null || hq job list
            for f in $(ls -t outputs/.launch/* 2>/dev/null | head -3); do echo "== $f"; tail -n 4 "$f"; done
            ;;
        gpu)
            query="nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader"
            echo "$HEAD: $($query)"
            while read -r node _; do echo "$node: $(ssh -n -q "$node" "$query")"; done < <(others)
            ;;
        finalize)
            [ $# -eq 1 ] || { echo "usage: hq finalize <sweep folder, as \`cairn drafts\` lists it>" >&2; exit 2; }
            pixi run --frozen python -m hydra_plugins.hq_launcher collect "$1"
            pixi run --frozen cairn finalize-study "$1"
            ;;
        ssh)
            if [ "${1:-}" != "${1#@}" ]; then
                node="${1#@}"
                shift
                ssh -q "$node" "cd $(root_of "$node")/$PROJECT && export PATH=\$HOME/.pixi/bin:\$PATH && $(quote "$@")"
            else
                eval "$(quote "$@")"
            fi
            ;;
        *)
            echo "unknown command $command" >&2
            exit 2
            ;;
    esac
    exit
fi

# ---------------------------------------------------------------- here: push to the head, then run there
help() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$SELF"; }
command="${1:-}"
[ $# -gt 0 ] && shift
case "$command" in
    setup | push | smoke | submit | status | gpu | finalize | ssh) ;;
    *) help; exit 2 ;;
esac

ROOT="$(ssh -q "$HEAD" "awk -v h=$HEAD '\$1 == h { print \$2 }' $STATE/nodes" 2>/dev/null)" || true
[ -n "$ROOT" ] || { echo "no cluster on $HEAD: run \`hqc install\` and \`hqc up\`" >&2; exit 1; }
DIR="$ROOT/$PROJECT"
TTY=""
[ -t 0 ] && [ -t 1 ] && TTY=-t  # so Ctrl-C reaches a foreground smoke test (it then cancels its HQ job)
on_head() { ssh -q $TTY "$HEAD" "cd $(printf '%q' "$DIR") && CLUSTER_ENTRY=$(printf '%q' "$ENTRY") bash $SCRIPT --head$(quote "$@")"; }

push() {
    ssh -q "$HEAD" "mkdir -p $(printf '%q' "$DIR")"
    rsync -az --delete --filter=':- .gitignore' --exclude /.pixi/ --exclude /.cairn/ --exclude /outputs/ ./ "$HEAD:$DIR/"
    on_head push
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "note: uncommitted changes were pushed; runs record them as a patch against $(git rev-parse --short HEAD 2>/dev/null || echo 'no commit')" >&2
    fi
}

case "$command" in
    setup)
        push
        on_head setup
        if ! pixi run cairn remote 2>/dev/null | grep -q '^remote'; then  # this checkout reads the runs from the hub
            port="$(ssh -q "$HEAD" "source $STATE/cluster.conf && echo \$HUB_PORT")"
            mkdir -p .cairn
            ssh -q "$HEAD" "source $STATE/cluster.conf && cat \$HUB_DIR/repo/token" | (umask 077 && cat > .cairn/token)
            pixi run cairn remote set "http://$HEAD:$port/$PROJECT"
        else
            echo "this checkout keeps its remote ($(pixi run cairn remote)); the cluster's runs are on the hub of $HEAD"
        fi
        ;;
    push) push ;;
    smoke | submit) push; on_head "$command" "$@" ;;
    *) on_head "$command" "$@" ;;
esac
