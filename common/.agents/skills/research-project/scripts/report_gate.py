#!/usr/bin/env python3
"""Require a current successful report build and one whole-report self-review.

The Stop hook accepts JSON on stdin with cwd (or explicit project_dir) and
stop_hook_active. Hosts without hooks run it explicitly before finishing and,
after carrying out the requested R1–R9 review, with stop_hook_active=true.
Reports are reports/<slug>/report.md or report.qmd. Their complete captured
source hashes must match .cairn/build/<slug>/manifest.json in a completed build.
Backend destinations and CAIRN_DIR client journals do not locate report state.

Blocks at most MAX_BLOCKS times in a row, then reports what remains open without
marking it passed. State is project-local .cairn/reviews/gate.json. Stdlib only.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent
RUBRIC = SKILL / "references" / "review.md"
SAMPLE = SKILL / "assets" / "reports" / "direction"
MAX_BLOCKS = 3
QUIET_ENVS = ("RESEARCH_REPORT_REVIEWER", "STANDALONE_REPORT_REVIEWER")
SLUG = re.compile(r"[a-z0-9][a-z0-9_-]{0,62}")
ENTRIES = ("report.md", "report.qmd")
OUTPUTS = ("index.html", "document.json", "source-map.json", "manifest.json", "executed.ipynb")
MARKERS = ("pixi.toml", "pyproject.toml", ".git")


class Project:
    def __init__(self, root: Path):
        self.root = root
        self.reports_dir = root / "reports"
        self.state_dir = root / ".cairn"
        self.output_dir = self.state_dir / "build"


def project(start: Path, explicit: str | None = None) -> Project | None:
    """Find the nearest report project, without crossing another project root."""
    if explicit is not None:
        root = Path(explicit).expanduser()
        candidate = Project((root if root.is_absolute() else start / root).resolve())
        return candidate if reports(candidate) else None
    for root in (start, *start.parents):
        candidate = Project(root)
        if reports(candidate):
            return candidate
        if any((root / marker).exists() for marker in MARKERS):
            break
    return None


def reports(proj: Project) -> dict[str, Path]:
    """Discover flat reports, including invalid double entries so they cannot pass."""
    if not proj.reports_dir.is_dir():
        return {}
    return {
        child.name: child for child in sorted(proj.reports_dir.iterdir())
        if child.is_dir() and SLUG.fullmatch(child.name)
        and any((child / entry).exists() or (child / entry).is_symlink() for entry in ENTRIES)
    }


def source_hashes(folder: Path) -> dict[str, str]:
    """Match Cairn's captured tree, including helpers/includes and added/deleted files."""
    if folder.is_symlink():
        raise ValueError("report source folder is a symlink")
    entries = [name for name in ENTRIES if (folder / name).is_file()]
    if len(entries) != 1:
        raise ValueError("a report needs exactly one report.md or report.qmd")
    hashes = {}
    for path in sorted(folder.rglob("*")):
        relative = path.relative_to(folder)
        if any(part.startswith(".") or part == "__pycache__" for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f"report source is a symlink: {relative.as_posix()}")
        if path.is_file():
            hashes[relative.as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def fingerprint(hashes: dict[str, str]) -> str:
    return hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()


def source_hash(folder: Path) -> str:
    return fingerprint(source_hashes(folder))


def built_is_current(proj: Project, slug: str, hashes: dict[str, str]) -> bool:
    try:
        output = (proj.output_dir / slug).resolve(strict=True)
        if not all((output / name).is_file() for name in OUTPUTS):
            return False
        manifest = json.loads((output / "manifest.json").read_text())
        captured = {
            entry["path"].removeprefix("sources/"): entry["digest"]
            for entry in manifest.get("files", [])
            if entry["path"].startswith("sources/")
        }
        return manifest.get("status") == "complete" and captured == hashes and all(
            (output / "sources" / path).is_file()
            and hashlib.sha256((output / "sources" / path).read_bytes()).hexdigest() == digest
            for path, digest in captured.items()
        )
    except (OSError, RuntimeError, ValueError):
        return False


def gate(event: dict) -> dict | None:
    if any(os.environ.get(name) for name in QUIET_ENVS):
        return None
    start = Path(event.get("cwd") or os.getcwd()).expanduser().resolve()
    proj = project(start, event.get("project_dir"))
    if proj is None:
        return None
    found = reports(proj)
    state_file = proj.state_dir / "reviews" / "gate.json"
    try:
        state = json.loads(state_file.read_text())
        if not isinstance(state, dict):
            state = {}
    except (OSError, ValueError):
        state = {}
    passed = state.get("passed")
    if not isinstance(passed, dict):
        passed = {}
    current, problems, changed = {}, [], []
    for slug, folder in found.items():
        try:
            hashes = source_hashes(folder)
        except (OSError, ValueError) as exc:
            problems.append(f"reports/{slug}: {exc}.")
            continue
        current[slug] = fingerprint(hashes)
        if passed.get(slug) != current[slug]:
            changed.append(slug)
        if not built_is_current(proj, slug, hashes):
            problems.append(f"reports/{slug}: no successful build matches all current sources. "
                            f"Run `pixi run report-build --report {slug}`.")
    review = []
    if not problems and not event.get("stop_hook_active"):
        try:
            sample = source_hash(SAMPLE)
        except (OSError, ValueError):
            sample = None
        review = [slug for slug in changed if current[slug] != sample]
    if not problems and not review:
        if changed or state.get("blocks"):
            state.update(passed=current, blocks=0)
            save(state_file, state)
        return None
    if problems:
        reason = ("The report change is not done yet (research-project report gate).\n\n"
                  + "\n\n".join(problems) + "\n\nRebuild, and finish again.")
    else:
        reason = self_review([found[slug].relative_to(proj.root).as_posix() for slug in review])
    blocks = state.get("blocks", 0)
    state["blocks"] = (blocks if isinstance(blocks, int) else 0) + 1
    if state["blocks"] > MAX_BLOCKS:
        state["blocks"] = 0
        save(state_file, state)
        return {"systemMessage": f"The report gate stopped blocking after {MAX_BLOCKS} attempts; "
                                 "still open:\n" + reason}
    save(state_file, state)
    return {"decision": "block", "reason": reason}


def self_review(names: list[str]) -> str:
    return (
        f"Before finishing, review the report(s) you changed ({', '.join(names)}) as a demanding reviewer at a good"
        f" venue would, using the rubric in {RUBRIC}. Re-read each whole report as its reader sees it"
        " (the built page under .cairn/build/<slug>/), and open every figure the Methods section"
        " relies on. Decide each item R1-R9. Fix every failed item in the report sources and rebuild"
        " (`pixi run report-build`); do not pad sections to satisfy an item. When the report's evidence"
        " or conclusions changed, publish it (`pixi run report-publish <slug>`). Then finish, and tell"
        " the user which items, if any, you left open and why."
    )


def save(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ignore = path.parent.parent / ".gitignore"
    if not ignore.exists():
        try:
            with open(ignore, "x") as handle:
                handle.write("*\n")
        except OSError:
            pass
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(path)


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if not isinstance(event, dict):
            event = {}
    except ValueError:
        event = {}
    reply = gate(event)
    if reply:
        print(json.dumps(reply))
    return 0


if __name__ == "__main__":
    sys.exit(main())
