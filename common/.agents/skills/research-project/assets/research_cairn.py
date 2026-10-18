"""Small project adapter for Cairn2 0.1: initial provenance and completed evidence.

Copy beside experiments/run.py. This is project policy, not a Cairn plugin.
Run "python experiments/research_cairn.py --help" for evidence/study checks.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import re
import stat
import subprocess
import sys
import tempfile
from typing import Any, Mapping

import cairn

_NAME = re.compile(r"[a-z0-9][a-z0-9-]{0,62}")
_SOURCE_SUFFIXES = set(".py .pyi .c .h .cc .cpp .hpp .cxx .cu .cuh .rs .jl .r .sh .bash .zsh .js .jsx .ts .tsx .html .css .glsl .vert .frag .wgsl .sql .tex .md .qmd .yaml .yml .toml .json .ini .cfg .cmake".split())
_SOURCE_NAMES = {"Makefile", "CMakeLists.txt", "Dockerfile", ".gitignore", ".gitattributes"}
_DENY_DIRS = set(".git .pixi .cairn .venv venv env .env .cache __pycache__ .ipynb_checkpoints node_modules site-packages dist build outputs data .submitit .ssh .aws .azure .gcp .config .kube .local .npm .tox .mypy_cache .pytest_cache .libs .eggs .cargo .rustup".split())
_DENY_FILES = (".env*", "*.pem", "*.key", "id_rsa*", "id_ed25519*", "credentials*", "secrets*", "token*", "*-token*", "service-account*", "service_account*", "*serviceaccount*.json")
_SECRET_KEYS = {"token", "password", "secret", "api_key", "access_token", "private_key", "credentials"}
_RUNTIME_ENV = ("CUDA_VISIBLE_DEVICES", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "SLURM_JOB_ID", "SLURM_ARRAY_TASK_ID")


def _json(value: Any) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def _no_secret_settings(value: Any) -> None:
    if isinstance(value, Mapping):
        for key, item in value.items():
            if str(key).lower() in _SECRET_KEYS:
                raise ValueError("Credentials must not be stored in recorded experiment configuration")
            _no_secret_settings(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            _no_secret_settings(item)


def _name(value: Any) -> str:
    if not isinstance(value, str) or not _NAME.fullmatch(value):
        raise ValueError("Run/study names must be lowercase slugs of at most 63 characters")
    return value


def _destination(options: Mapping[str, Any], root: Path) -> dict[str, Any]:
    if set(options) - {"repo", "server"}:
        raise ValueError("cairn config accepts only repo or server; credentials belong in token files")
    target = {key: value for key, value in options.items() if value is not None}
    if len(target) > 1:
        raise ValueError("Select one Cairn repo or server")
    if "repo" in target and "://" not in str(target["repo"]):
        target["repo"] = str((root / Path(target["repo"]).expanduser()).resolve())
    return {"destination": next(iter(target.values()), None)}


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
        temporary = Path(file.name)
        file.write(_json(value))
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def capture_provenance(run, *, project_root: Path, output_dir: Path, config: Mapping[str, Any],
                       max_file_bytes: int = 1024 * 1024, max_total_bytes: int = 32 * 1024 * 1024,
                       exclude: list[str] | tuple[str, ...] = ()):
    """Capture eligible current source and mandatory runtime/config before compute.

    Git ignores are respected in a checkout. Else the same allow/deny rules
    apply to a tree walk. Symlinks and non-UTF8 source are listed as skipped;
    read failures or size limits fail the run. pixi.lock is always required.
    """
    root = project_root.resolve(strict=True)
    if max_file_bytes <= 0 or max_total_bytes <= 0:
        raise ValueError("Provenance limits must be positive")
    if not isinstance(exclude, (list, tuple)) or any(not isinstance(item, str) for item in exclude):
        raise ValueError("provenance.exclude must be a list of glob patterns")
    _no_secret_settings(config)
    files: dict[str, bytes] = {}
    skipped: list[dict[str, str]] = []
    size = 0

    def add(path: str, content: bytes) -> None:
        nonlocal size
        if len(content) > max_file_bytes or size + len(content) > max_total_bytes:
            raise ValueError(f"Provenance size limit exceeded by {path}; increase the explicit limit or exclude unrelated source")
        files[path] = content
        size += len(content)

    def read(path: Path) -> bytes:
        before = path.lstat()
        if not stat.S_ISREG(before.st_mode) or path.is_symlink() or any(
            parent.is_symlink() for parent in path.parents if parent != root and root in parent.parents
        ):
            raise ValueError(f"Required provenance must be a regular non-symlink file: {path.name}")
        with path.open("rb") as file:
            content = file.read(max_file_bytes + 1)
        after = path.stat()
        if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
            raise ValueError(f"Source changed during provenance capture: {path.name}")
        if len(content) > max_file_bytes:
            raise ValueError(f"Provenance file exceeds max_file_bytes: {path.name}")
        return content

    lock = read(root / "pixi.lock")
    lock.decode("utf-8")
    add("environment/pixi.lock", lock)
    add("config/resolved.json", _json(dict(config)))
    hydra_dir = output_dir / ".hydra"
    if hydra_dir.exists():
        for filename in ("config.yaml", "hydra.yaml", "overrides.yaml"):
            add("config/hydra/" + filename, read(hydra_dir / filename))

    try:
        listing = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                                 check=False, capture_output=True)
    except FileNotFoundError:
        listing = None
    if (listing is None or listing.returncode != 0) and any((parent / ".git").exists() for parent in (root, *root.parents)):
        raise RuntimeError("Cannot enumerate the Git checkout safely for provenance")
    git = None
    if listing is not None and listing.returncode == 0:
        candidates = sorted(set(os.fsdecode(item) for item in listing.stdout.split(b"\0") if item))
        revision = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True)
        git = {"revision": revision.stdout.strip() if revision.returncode == 0 else None}
    else:
        def fail(error):
            raise error
        candidates = []
        for directory, dirs, names in os.walk(root, followlinks=False, onerror=fail):
            dirs[:] = sorted(d for d in dirs if d not in _DENY_DIRS and not (Path(directory)/d).is_symlink())
            candidates.extend((Path(directory)/name).relative_to(root).as_posix() for name in sorted(names))
    ignored_roots = [output_dir.resolve()]
    selected_repo = (config.get("cairn") or {}).get("repo")
    if selected_repo and "://" not in str(selected_repo):
        ignored_roots.append((root / Path(selected_repo).expanduser()).resolve())
    for relative in candidates:
        path = root / relative
        rel = Path(relative)
        if relative == "pixi.lock" or any(part in _DENY_DIRS for part in rel.parts):
            continue
        if any(fnmatch.fnmatch(part.lower(), pattern) for part in rel.parts for pattern in _DENY_FILES):
            continue
        if any(fnmatch.fnmatch(relative, pattern) or rel.match(pattern) for pattern in exclude):
            continue
        if rel.suffix.lower() not in _SOURCE_SUFFIXES and rel.name not in _SOURCE_NAMES:
            continue
        if not path.exists() and not path.is_symlink():  # A deleted tracked file is not current source.
            continue
        if path.is_symlink() or any(parent.is_symlink() for parent in path.parents if parent != root and root in parent.parents):
            skipped.append({"path": relative, "reason": "symlink"})
            continue
        resolved = path.resolve()
        if root not in resolved.parents or any(resolved == item or item in resolved.parents for item in ignored_roots):
            continue
        content = read(path)
        try:
            content.decode("utf-8")
        except UnicodeDecodeError:
            skipped.append({"path": relative, "reason": "not UTF-8"})
            continue
        add("source/" + relative, content)
    if not any(path.startswith("source/") for path in files):
        raise ValueError("No eligible source captured; check project_root and provenance.exclude")
    packages = sorted({f"{dist.metadata['Name']}=={dist.version}" for dist in importlib.metadata.distributions() if dist.metadata.get("Name")})
    if not packages:
        raise ValueError("Installed package inventory is empty")
    add("environment/packages.txt", ("\n".join(packages) + "\n").encode())
    add("environment/runtime.json", _json({
        "python": sys.version, "implementation": platform.python_implementation(), "platform": platform.platform(),
        "environment": {key: os.environ[key] for key in _RUNTIME_ENV if key in os.environ}, "git": git,
    }))
    add("manifest.json", _json({
        "kind": "initial-provenance", "source_mode": "current-tree", "skipped": skipped,
        "files": {path: {"sha256": hashlib.sha256(content).hexdigest(), "size": len(content)} for path, content in sorted(files.items())},
    }))
    # A run is itself an artifact; strict provenance is a named immutable capture.
    with tempfile.TemporaryDirectory(prefix="research-provenance-") as temporary:
        folder = Path(temporary)
        for path, content in files.items():
            destination = folder / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
        run.capture(folder, name="provenance")
    return run.id


def run_experiment(cfg, experiment_type, *, project_root: Path, output_dir: Path) -> str:
    """Hydra adapter: provenance first, then configured Experiment.run(run, output_dir)."""
    from hydra.utils import instantiate
    from omegaconf import OmegaConf

    root = project_root.resolve(strict=True)
    if Path.cwd().resolve() != root:
        raise ValueError("Keep hydra.job.chdir=false so project-relative inputs keep their meaning")
    config = OmegaConf.to_container(cfg, resolve=True, throw_on_missing=True)
    if not isinstance(config, dict) or not isinstance(config.get("project"), str) or not config["project"]:
        raise ValueError("Set a nonempty project namespace in config")
    _no_secret_settings(config)
    name = _name(config["run"]["name"])
    target = _destination(config.get("cairn") or {}, root)
    output_dir = output_dir.resolve()
    receipt = output_dir / "cairn-run.json"
    if receipt.exists():
        raise FileExistsError("This Hydra output folder already has a Cairn run; choose a fresh output folder")
    with cairn.Client(project=config["project"], **target) as client:
        with client.run(name, config=config, metadata={"description": config["run"].get("description")}, provenance=False) as run:
            _write_json(receipt, {"project": config["project"], "run_id": run.id})
            capture_provenance(run, project_root=root, output_dir=output_dir, config=config,
                               **(config.get("provenance") or {}))
            experiment = instantiate(cfg.experiment)
            if not isinstance(experiment, experiment_type):
                raise TypeError("Configured experiment must implement experiments.base.Experiment")
            experiment.run(run, output_dir)
            if (output_dir / "result").is_dir():
                run.capture(output_dir / "result", name="result")
        producer = client.resolve(run.id)
        require_completed_run(producer)
        if "result" in producer.descriptor["manifest"]["captures"]:
            result = publish_result(client, producer)
            _write_json(output_dir / "cairn-result.json", {"artifact_id": result.id, "ref": exact_ref(result)})
    print(f"Cairn run: {run.id}")
    return run.id


def exact_ref(reader):
    descriptor = reader.descriptor
    return f"{descriptor['namespace']}/{descriptor['name']}@v{descriptor['number']}"


def require_completed_run(reader):
    descriptor = reader.descriptor
    if descriptor["namespace"] != "runs" or descriptor["state"] != "finished" or descriptor["manifest"]["outcome"] != "completed":
        raise ValueError(f"Run {reader.id} is not a completed producer")
    return reader


def publish_result(client, producer, *, name=None):
    """Publish captured result bytes only after the producing run completes."""
    require_completed_run(producer)
    with tempfile.TemporaryDirectory(prefix="research-result-") as temporary:
        folder = Path(temporary) / "result"
        producer.download("result", to=folder)
        result = client.start("artifacts", name or producer.descriptor["name"])
        result.use(producer.id, role="producer")
        result.finish(value=cairn.Directory(folder))
    return client.resolve(result.id)


def require_completed_artifact(client, ref: str):
    """Require immutable evidence with a completed run, not just an alias."""
    reader = client.resolve(ref)
    descriptor = reader.descriptor
    if descriptor["manifest"]["outcome"] != "completed":
        raise ValueError(f"Artifact {reader.id} has no verifiable completed producer")
    if descriptor["namespace"] == "runs":
        return require_completed_run(reader)
    producers = [item["artifact_id"] for item in descriptor["manifest"]["dependencies"] if item["role"] == "producer"]
    if len(producers) != 1:
        raise ValueError(f"Artifact {reader.id} has no verifiable completed producer")
    producer = client.resolve(producers[0])
    if producer.descriptor["project"] != descriptor["project"]:
        raise ValueError("Result and producer must belong to the same project")
    require_completed_run(producer)
    return reader


def finalize_study(roster: Mapping[str, Any], *, project_root: Path, repo=None, server=None):
    """Publish a summary only for an explicit, fully completed trial roster."""
    project, name = roster["project"], _name(roster["name"])
    expected, runs = roster["expected_trials"], roster["runs"]
    if not isinstance(expected, list) or not expected or any(not isinstance(item, str) or not item for item in expected):
        raise ValueError("expected_trials must be a nonempty list of trial labels")
    if len(expected) != len(set(expected)) or not isinstance(runs, dict) or set(runs) != set(expected):
        raise ValueError("runs must match the explicit expected_trials exactly, without duplicates")
    if any(not isinstance(ident, str) or not ident for ident in runs.values()) or len(set(runs.values())) != len(runs):
        raise ValueError("Every trial must name a distinct full Cairn run ID")
    root = project_root.resolve(strict=True)
    target = _destination({"repo": repo, "server": server}, root)
    trials = []
    with cairn.Client(project=project, **target) as client:
        for label in expected:
            trial = require_completed_run(client.resolve(runs[label]))
            if trial.id != runs[label] or trial.descriptor["project"] != project:
                raise ValueError(f"Trial {label} is missing or belongs to another project")
            trials.append({"trial": label, "run_id": trial.id, "status": "completed"})
        config = {"project": project, "run": {"name": name}, "study": dict(roster),
                  "cairn": {"repo": client.destination}}
        with client.run(name, config=config, metadata={"kind": "study"}, provenance=False) as run:
            output_dir = root / "outputs" / "studies" / run.id
            _write_json(output_dir / "cairn-run.json", {"project": project, "run_id": run.id})
            capture_provenance(run, project_root=root, output_dir=output_dir, config=config)
            result_dir = output_dir / "result"
            _write_json(result_dir / "roster.json", dict(roster))
            _write_json(result_dir / "trials.json", trials)
            for trial in trials:
                run.use(trial["run_id"], role="trial")
            run.capture(result_dir, name="result")
        result = publish_result(client, client.resolve(run.id), name=name + "-study")
        return result.descriptor


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command, argument in (("check-artifact", "ref"), ("finalize-study", "roster")):
        sub = commands.add_parser(command)
        sub.add_argument(argument)
        sub.add_argument("--project", default="default")
        destination = sub.add_mutually_exclusive_group()
        destination.add_argument("--repo")
        destination.add_argument("--server")
        if command == "finalize-study":
            sub.add_argument("--project-root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.command == "check-artifact":
        with cairn.Client(project=args.project, **_destination({"repo": args.repo, "server": args.server}, Path.cwd())) as client:
            descriptor = require_completed_artifact(client, args.ref).descriptor
    else:
        descriptor = finalize_study(json.loads(Path(args.roster).read_text()), project_root=args.project_root,
                                 repo=args.repo, server=args.server)
    print(f"{descriptor['namespace']}/{descriptor['name']}@v{descriptor['number']} ({descriptor['id']})")


if __name__ == "__main__":
    main()
