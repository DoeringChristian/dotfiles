"""Hydra launcher for the lab's HyperQueue cluster (`hqc`): one HQ task per trial, on whichever node is free.

Copy into the project as hydra_plugins/hq_launcher.py (hydra_plugins/ without an __init__.py: Hydra only accepts
launchers from that namespace) and the launcher configs into configs/hydra/launcher/; `pixi run hq smoke|submit`
select them. The launcher runs on the head node (fermat) from its checkout of the project; every node has its own
checkout at `$HQ_PROJECTS/<project>` (the same tree, kept identical by `pixi run hq push`), and there is no shared
filesystem.

How a sweep stays one Cairn study: the sweep folder (`hydra.sweep.dir`, a `${cairn.run:}` or `${cairn.draft:}`
reservation inside `.cairn/drafts/`) is reserved here. Each task copies the reservation's record into its node's
checkout and runs the entry point there as a single job with `hydra.run.dir=<sweep>/<n>` and `hydra.job.num=<n>`, so
Cairn makes it the same trial it would be on a shared filesystem: a version of `runs/<run.name>` labelled
`<sweep>/<n>`, which the node syncs to the Cairn hub (every checkout's remote). When the HQ job has ended, the
launcher copies each node's part of the sweep folder back (kept trial folders; trials.jsonl lines) and removes it
there; Hydra's StudyCompletion then publishes the sweep's summary run from here, as for a local or Slurm sweep.
Each trial gets an empty placeholder folder here at submission, so a trial that left nothing (a killed task) counts as
missing instead of disappearing; placeholders of trials that ended are removed.

    python -m hydra_plugins.hq_launcher collect <sweep-dir>   # fetch the nodes' parts of a sweep (after a dead launcher)
"""

from __future__ import annotations

import base64
import json
import logging
import os
import shlex
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any, Sequence

log = logging.getLogger(__name__)

STATE = Path.home() / ".hq-cluster"
HQ = str(Path.home() / ".local/bin/hq")
TRIALS = "trials.jsonl"
# Hydra overrides of the launching process that must not reach a trial (the trial is a single job in a given folder).
LAUNCH_ONLY = ("hydra/launcher", "hydra.launcher", "hydra/sweeper", "hydra.sweeper", "hydra.sweep", "hydra.run",
               "hydra.mode", "hydra.job.num", "hydra.job.id")


def nodes() -> dict[str, str]:
    """The cluster's nodes (ssh host and worker hostname) and their project roots, from the head's nodes file."""
    found = {}
    for line in (STATE / "nodes").read_text().splitlines():
        fields = line.split()
        if fields and not fields[0].startswith("#"):
            found[fields[0]] = fields[1]
    return found


def hq(*args: str, json_output: bool = False) -> Any:
    command = [HQ, "--server-dir", str(STATE), *(["--output-mode", "json"] if json_output else []), *args]
    result = subprocess.run(command, check=True, text=True, capture_output=json_output)
    return json.loads(result.stdout) if json_output else None


def collect(sweep: Path, root: Path | None = None) -> None:
    """Copy every other node's part of `sweep` (a folder inside the project) here, append its trials.jsonl lines to
    ours, and remove it there. Then drop the placeholders of trials that trials.jsonl lists."""
    root = (root or Path.cwd()).resolve()
    sweep = sweep.resolve()
    relative = sweep.relative_to(root)
    here = socket.gethostname().split(".")[0]
    for node, projects in nodes().items():
        if node == here:
            continue  # this checkout: the node's trials wrote into the sweep folder itself
        remote = shlex.quote(f"{projects}/{root.name}/{relative}")
        quoted = shlex.quote(str(sweep))
        script = (
            f"set -o pipefail; ssh -q -o BatchMode=yes {node} "
            f"'if test -d {remote}; then tar -C {remote} --exclude=./{TRIALS} -cf - .; else tar -cf - -T /dev/null; fi' "
            f"| tar -C {quoted} -xf - && "
            f"ssh -q -o BatchMode=yes {node} 'cat {remote}/{TRIALS} 2>/dev/null; true' >> {quoted}/{TRIALS} && "
            f"ssh -q -o BatchMode=yes {node} 'rm -rf {remote} {remote}.draft.json'"
        )
        if subprocess.run(["bash", "-c", script]).returncode != 0:
            log.warning(f"could not collect {relative} from {node}; run `pixi run hq finalize {relative}` later")
    listed = set()
    if (sweep / TRIALS).is_file():
        listed = {str(json.loads(line).get("num")) for line in (sweep / TRIALS).read_text().splitlines() if line}
    for folder in sweep.iterdir():
        if folder.is_dir() and folder.name.isdigit() and folder.name in listed and not any(folder.iterdir()):
            folder.rmdir()


try:
    from hydra.core.utils import JobReturn, JobStatus, configure_log
    from hydra.plugins.launcher import Launcher
except ImportError:  # `collect` needs no Hydra
    Launcher = object  # type: ignore[assignment,misc]


class HQLauncher(Launcher):
    """Submit every trial of a multirun as one task of a HyperQueue job and wait for the job."""

    def __init__(
        self,
        name: str = "hydra",
        cpus: int = 8,
        gpus: int = 1,
        gpu_mem_gb: int = 0,
        time_limit: str = "1h",
        priority: int = 0,
        crash_limit: int = 1,
    ) -> None:
        self.name, self.cpus, self.gpus, self.gpu_mem_gb = name, cpus, gpus, gpu_mem_gb
        self.time_limit, self.priority, self.crash_limit = time_limit, priority, crash_limit

    def setup(self, *, hydra_context, task_function, config) -> None:
        self.config, self.hydra_context, self.task_function = config, hydra_context, task_function

    def launch(self, job_overrides: Sequence[Sequence[str]], initial_job_idx: int) -> Sequence[JobReturn]:
        configure_log(self.config.hydra.hydra_logging, self.config.hydra.verbose)
        root = Path.cwd().resolve()  # hydra.job.chdir stays false: the project root
        sweep = Path(str(self.config.hydra.sweep.dir)).resolve()  # the cached reservation StudyCompletion also sees
        try:
            relative = sweep.relative_to(root)
        except ValueError:
            raise RuntimeError(f"hydra.sweep.dir {sweep} must lie inside the project (is CAIRN_DIR moved?)") from None
        sweep.mkdir(parents=True, exist_ok=True)
        record = sweep.parent / f"{sweep.name}.draft.json"
        reservation = base64.b64encode(record.read_bytes()).decode() if record.is_file() else ""
        entry = Path(sys.argv[0]).resolve().relative_to(root)
        passed = [str(item) for item in self.config.hydra.overrides.hydra if not str(item).startswith(LAUNCH_ONLY)]
        lines, numbers = [], []
        for index, overrides in enumerate(job_overrides):
            number = initial_job_idx + index
            numbers.append(number)
            (sweep / str(number)).mkdir(exist_ok=True)  # the placeholder: a trial that leaves nothing is missing
            arguments = [
                "--config-name", str(self.config.hydra.job.config_name),
                *overrides, *passed,
                f"hydra.run.dir='{relative}/{number}'", f"hydra.sweep.dir='{relative}'", f"hydra.job.num={number}",
            ]
            lines.append(shlex.join(arguments))
        listing = sweep / ".hq" / f"trials-{initial_job_idx}.txt"
        listing.parent.mkdir(exist_ok=True)
        listing.write_text("\n".join(lines) + "\n")

        # On the node: its checkout, the sweep's reservation (unless the checkout already has it: the head's), the trial,
        # and a sync, so even a failed run's end reaches the hub at once.
        mirror = (
            f"if [ ! -e {shlex.quote(str(relative))}.draft.json ]; then "
            f"mkdir -p {shlex.quote(str(relative))} && echo {shlex.quote(reservation)} | base64 -d > "
            f"{shlex.quote(str(relative))}.draft.json; fi; " if reservation else ""
        )
        script = (
            f'cd "$HQ_PROJECTS"/{shlex.quote(root.name)} || {{ echo "no checkout of {root.name} on $(hostname): '
            f'pixi run hq push" >&2; exit 97; }}; {mirror}'
            f'eval "$HOME/.pixi/bin/pixi run --frozen python {shlex.quote(str(entry))} $HQ_ENTRY"; code=$?; '
            f'$HOME/.pixi/bin/pixi run --frozen cairn sync > /dev/null 2>&1; exit $code'  # a failed run's end, too
        )
        resources = ["--resource", f"gpus/nvidia={self.gpus}"] if self.gpus else []
        if self.gpu_mem_gb:  # only nodes whose GPU has this much memory (the workers' `vram` resource)
            resources += ["--resource", f"vram={self.gpu_mem_gb}"]
        submitted = hq(
            "submit", "--name", self.name, "--each-line", str(listing), "--cpus", str(self.cpus), *resources,
            "--time-limit", self.time_limit, "--priority", str(self.priority), "--crash-limit", str(self.crash_limit),
            "--cwd", "/tmp", "--stdout", "/tmp/hq-%{JOB_ID}.%{TASK_ID}.out", "--stderr", "/tmp/hq-%{JOB_ID}.%{TASK_ID}.err",
            "--", "bash", "-c", script,
            json_output=True,
        )
        job = str(submitted["id"])
        log.info(f"HQ job {job}: {len(lines)} trial(s) of {relative}; `hqc hq job progress {job}` follows it")
        try:
            subprocess.run([HQ, "--server-dir", str(STATE), "job", "wait", job], stdout=subprocess.DEVNULL)
        except KeyboardInterrupt:
            hq("job", "cancel", job)
            raise
        tasks = {task["id"]: task for task in hq("task", "list", job, json_output=True)[job]}
        workers = {w["id"]: w["configuration"]["hostname"] for w in hq("worker", "list", "--all", json_output=True)}
        collect(sweep, root)

        returns = []
        for index, (number, overrides) in enumerate(zip(numbers, job_overrides)):
            task = tasks.get(index, {})
            result = JobReturn(overrides=list(overrides), working_dir=str(sweep / str(number)), task_name=self.name)
            if task.get("state") == "finished":
                result.status = JobStatus.COMPLETED
                result.return_value = None
            else:
                node = workers.get(task.get("worker"), "?")
                result.status = JobStatus.FAILED
                result.return_value = RuntimeError(
                    f"trial {number} {task.get('state', 'missing')} on {node} (HQ job {job} task {index}): "
                    f"its run is on the hub, its kept folder at {relative}/{number} here; "
                    f"the task's own log: ssh {node} cat /tmp/hq-{job}.{index}.err"
                )
            returns.append(result)
        return returns


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "collect":
        raise SystemExit(__doc__)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    collect(Path(sys.argv[2]))
