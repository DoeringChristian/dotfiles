"""Hydra callback that records bounded source and runtime provenance per job."""

from __future__ import annotations

import io
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

from hydra.core.hydra_config import HydraConfig
from hydra.experimental.callback import Callback
from hydra.utils import get_original_cwd

SOURCE_SUFFIXES = {
    ".bash", ".c", ".cc", ".cpp", ".cu", ".cuh", ".h", ".hpp", ".jl",
    ".json", ".md", ".py", ".pyi", ".r", ".rs", ".sh", ".toml", ".txt",
    ".yaml", ".yml", ".zsh",
}
DENIED_PARTS = {
    ".git", ".pixi", ".venv", "__pycache__", "generated", "mlruns",
    "node_modules", "outputs", "site-packages", "venv",
}
DENIED_NAMES = {
    ".env", ".envrc", "credentials", "credentials.json", "secrets.yaml",
    "secrets.yml",
}
SAFE_ENVIRONMENT = (
    "CUDA_VISIBLE_DEVICES", "OMP_NUM_THREADS", "MKL_NUM_THREADS",
    "PYTHONHASHSEED", "SLURM_JOB_ID", "SLURM_ARRAY_TASK_ID",
)


def _git(root: Path, *args: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(root), *args], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout


def _eligible(path: Path, root: Path, max_file_bytes: int) -> bool:
    relative = path.relative_to(root)
    if path.is_symlink() or any(part in DENIED_PARTS for part in relative.parts):
        return False
    if path.name.lower() in DENIED_NAMES or path.suffix.lower() not in SOURCE_SUFFIXES:
        return False
    if not path.is_file() or path.stat().st_size > max_file_bytes:
        return False
    try:
        path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    return True


def _working_files(root: Path) -> list[Path]:
    try:
        names = _git(
            root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"
        ).split(b"\0")
        return [root / os.fsdecode(name) for name in names if name]
    except (FileNotFoundError, subprocess.CalledProcessError):
        return list(root.rglob("*"))


def create_snapshot(
    root: Path,
    destination: Path,
    mode: str,
    max_file_bytes: int,
    max_total_bytes: int,
) -> None:
    files = sorted(
        path for path in _working_files(root) if _eligible(path, root, max_file_bytes)
    )
    working_total = sum(path.stat().st_size for path in files)
    if working_total > max_total_bytes:
        raise RuntimeError(
            f"eligible working source is {working_total} bytes; limit is {max_total_bytes}"
        )
    destination.mkdir(parents=True)
    manifest: dict[str, object] = {
        "mode": mode,
        "source_root": str(root),
        "working_files": [str(path.relative_to(root)) for path in files],
        "working_total_bytes": working_total,
    }

    if mode == "tree":
        for path in files:
            target = destination / "tree" / path.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    elif mode == "git":
        try:
            commit = _git(root, "rev-parse", "HEAD").decode().strip()
            tracked = {
                os.fsdecode(name)
                for name in _git(
                    root, "ls-tree", "-r", "--name-only", "-z", commit
                ).split(b"\0")
                if name
            }
        except (FileNotFoundError, subprocess.CalledProcessError) as error:
            raise RuntimeError("git mode requires a repository with a commit") from error

        committed: list[tuple[str, bytes]] = []
        for relative in sorted(tracked):
            pseudo = root / relative
            if any(part in DENIED_PARTS for part in Path(relative).parts):
                continue
            if pseudo.name.lower() in DENIED_NAMES or pseudo.suffix.lower() not in SOURCE_SUFFIXES:
                continue
            payload = _git(root, "show", f"{commit}:{relative}")
            if len(payload) > max_file_bytes:
                continue
            try:
                payload.decode("utf-8")
            except UnicodeDecodeError:
                continue
            committed.append((relative, payload))
        committed_total = sum(len(payload) for _, payload in committed)
        if committed_total + working_total > max_total_bytes:
            raise RuntimeError("git source snapshot exceeds the configured total-size limit")

        with tarfile.open(destination / "git-tree.tar.gz", "w:gz") as archive:
            for relative, payload in committed:
                info = tarfile.TarInfo(relative)
                info.size = len(payload)
                info.mtime = 0
                archive.addfile(info, io.BytesIO(payload))

        relevant = sorted(
            set(relative for relative, _ in committed)
            | {str(path.relative_to(root)) for path in files}
        )
        patch = (
            _git(root, "diff", "--no-ext-diff", "--no-color", "HEAD", "--", *relevant)
            if relevant else b""
        )
        (destination / "working-tree.patch").write_bytes(patch)
        for path in files:
            relative = str(path.relative_to(root))
            if relative not in tracked:
                target = destination / "untracked" / path.relative_to(root)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
        manifest.update(commit=commit, committed_total_bytes=committed_total)
    else:
        raise ValueError("source snapshot mode must be 'git' or 'tree'")

    (destination / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )


def capture_environment(root: Path, destination: Path) -> None:
    target = destination / "environment"
    target.mkdir(parents=True, exist_ok=True)
    facts = {
        "python": sys.version,
        "implementation": platform.python_implementation(),
        "executable": sys.executable,
        "platform": platform.platform(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "selected_environment": {
            key: os.environ[key] for key in SAFE_ENVIRONMENT if key in os.environ
        },
    }
    (target / "runtime.json").write_text(
        json.dumps(facts, indent=2) + "\n", encoding="utf-8"
    )
    freeze = subprocess.run(
        [sys.executable, "-m", "pip", "freeze", "--all"], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    ).stdout
    (target / "pip-freeze.txt").write_text(freeze, encoding="utf-8")
    lock = root / "pixi.lock"
    if lock.is_file():
        shutil.copy2(lock, target / "pixi.lock")
    try:
        (target / "git-status.txt").write_bytes(
            _git(root, "status", "--short", "--branch")
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass


class SourceSnapshotCallback(Callback):
    def __init__(
        self,
        mode: str = "git",
        source_root: str | None = None,
        capture_runtime: bool = True,
        max_file_bytes: int = 2_000_000,
        max_total_bytes: int = 50_000_000,
    ) -> None:
        self.mode = mode
        self.source_root = source_root
        self.capture_runtime = capture_runtime
        self.max_file_bytes = max_file_bytes
        self.max_total_bytes = max_total_bytes

    def on_job_start(self, config, **kwargs) -> None:
        root = Path(self.source_root or get_original_cwd()).resolve()
        output = Path(HydraConfig.get().runtime.output_dir).resolve()
        destination = output / "provenance"
        if destination.exists():
            raise RuntimeError(f"refusing to replace existing provenance: {destination}")
        temporary = Path(tempfile.mkdtemp(prefix=".provenance-", dir=output))
        try:
            create_snapshot(
                root, temporary, self.mode, self.max_file_bytes, self.max_total_bytes
            )
            if self.capture_runtime:
                capture_environment(root, temporary)
            temporary.replace(destination)
        except Exception:
            shutil.rmtree(temporary, ignore_errors=True)
            raise
