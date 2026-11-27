"""Hydra callbacks for runs/<name>/<date>/ run folders.

Register them in the config:

    hydra:
      callbacks:
        git:
          _target_: utils.hydra.GitInfo
        latest:
          _target_: utils.hydra.LatestLink
"""

import os
import subprocess
from pathlib import Path
from typing import Any

from hydra.core.hydra_config import HydraConfig
from hydra.core.utils import JobReturn, JobStatus
from hydra.experimental.callback import Callback
from omegaconf import DictConfig


def _git(*args: str, cwd: str) -> str:
    try:
        return subprocess.run(["git", *args], cwd=cwd, capture_output=True,
                              text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return ""


class GitInfo(Callback):
    """Writes the commit, and the uncommitted changes if any, into the run folder."""

    def on_job_start(self, config: DictConfig, **kwargs: Any) -> None:
        hc = HydraConfig.get()
        out, cwd = Path(hc.runtime.output_dir), hc.runtime.cwd
        (out / "git_commit.txt").write_text(_git("rev-parse", "HEAD", cwd=cwd))
        diff = _git("diff", "HEAD", "--binary", cwd=cwd)
        if diff:
            (out / "git_diff.patch").write_text(diff)


class LatestLink(Callback):
    """Points runs/<name>/latest at the run folder when the job returns normally.

    A job that raises leaves the link alone; its traceback is in the job's log.
    Folder names sort by start time, so the link never moves back to an older run.
    """

    def on_job_end(self, config: DictConfig, job_return: JobReturn, **kwargs: Any) -> None:
        if job_return.status != JobStatus.COMPLETED:
            return
        out = Path(HydraConfig.get().runtime.output_dir)
        link = out.parent / "latest"
        if link.is_symlink() and os.readlink(link) > out.name:
            return
        tmp = out.parent / f".latest.tmp-{os.getpid()}"
        tmp.unlink(missing_ok=True)
        os.symlink(out.name, tmp)
        os.replace(tmp, link)
