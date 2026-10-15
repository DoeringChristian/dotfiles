#!/usr/bin/env python3
"""Stop hook of the research-project skill: a report change is done only when it is built and the
agent has reviewed it against the rubric.

Registered by the skill's frontmatter, so it runs whenever the agent tries to finish a turn in a
session that used the skill. It costs nothing unless a report's sources changed since the gate last
passed. Reports are single pages, `reports/<slug>/report.md` (with `assets/` and `data/`); Cairn
builds each into `<output_dir>/<slug>/` (default `.cairn/build/<slug>/`). Then it:

1. blocks when a changed report was not rebuilt (`pixi run report-build`);
2. once per stop, sends the agent back to review each changed report itself against
   references/review.md, fix what fails, and rebuild. When the agent finishes after that review
   (`stop_hook_active`), only the build check runs again, so the review never loops.

It blocks at most MAX_BLOCKS times in a row; after that it lets the agent stop and tells the user
what is still open. State lives in `<cairn dir>/reviews/gate.json`. Stdlib only (Python 3.8+).
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
SAMPLE = SKILL / "assets" / "reports" / "direction"  # a fresh scaffold's report, replaced later
MAX_BLOCKS = 3
# Set by a host (e.g. cairn-agents) that gates reports itself; the second name is the older one.
QUIET_ENVS = ("RESEARCH_REPORT_REVIEWER", "STANDALONE_REPORT_REVIEWER")
CONFIG = "cairn.toml"
SLUG = re.compile(r"[a-z0-9][a-z0-9_-]{0,62}")  # Cairn's report folder names


def config(root: Path) -> dict:
    """The top-level keys of cairn.toml that place reports (tomllib when available)."""
    path = root / CONFIG
    if not path.is_file():
        return {}
    text = path.read_text()
    try:
        import tomllib  # Python 3.11+

        return tomllib.loads(text)
    except ImportError:
        pass
    except ValueError:
        return {}
    found = {}
    for line in text.splitlines():
        if line.lstrip().startswith("["):
            break  # top-level keys come before the first table
        match = re.match(r"\s*(reports_dir|output_dir)\s*=\s*[\"']([^\"']+)[\"']", line)
        if match:
            found[match.group(1)] = match.group(2)
    table = re.search(r"^\[cairn\]\s*$(.*?)(?=^\[|\Z)", text, re.M | re.S)
    if table:
        match = re.search(r"^\s*dir\s*=\s*[\"']([^\"']+)[\"']", table.group(1), re.M)
        if match:
            found["cairn"] = {"dir": match.group(1)}
    return found


def cairn_dir(root: Path) -> Path:
    """Cairn's project folder: $CAIRN_DIR, else [cairn] dir in cairn.toml, else <root>/.cairn."""
    if os.environ.get("CAIRN_DIR"):
        return Path(os.environ["CAIRN_DIR"]).expanduser()
    configured = (config(root).get("cairn") or {}).get("dir")
    return (root / configured) if configured else root / ".cairn"


def output_dir(root: Path) -> Path:
    configured = config(root).get("output_dir")
    return (root / configured) if configured else cairn_dir(root) / "build"


def project_root(start: Path) -> Path | None:
    """The nearest folder with cairn.toml or pixi.toml that has at least one report."""
    for folder in [start, *start.parents]:
        if (folder / CONFIG).is_file() or (folder / "pixi.toml").is_file():
            return folder if reports(folder) else None
    return None


def reports_dir(root: Path) -> Path:
    return root / config(root).get("reports_dir", "reports")


def reports(root: Path) -> dict[str, Path]:
    """Report slug -> its source folder (flat: reports/<slug>/report.md)."""
    folder = reports_dir(root)
    if not folder.is_dir():
        return {}
    return {child.name: child for child in sorted(folder.iterdir())
            if child.is_dir() and SLUG.fullmatch(child.name) and (child / "report.md").is_file()}


def source_files(folder: Path) -> list[Path]:
    """A report's own sources: report.md, assets/, and data/."""
    files = [folder / "report.md"]
    for part in ("assets", "data"):
        if (folder / part).is_dir():
            files += sorted(path for path in (folder / part).rglob("*") if path.is_file())
    return files


def source_hash(folder: Path) -> str:
    digest = hashlib.sha256()
    for path in source_files(folder):
        digest.update(path.relative_to(folder).as_posix().encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def built_is_current(root: Path, slug: str, folder: Path) -> bool:
    data = output_dir(root) / slug / "report-data.json"
    if not data.is_file():
        return False
    built = data.stat().st_mtime
    return all(path.stat().st_mtime <= built for path in source_files(folder))


def gate(event: dict) -> dict | None:
    """The hook's answer: None to let the agent stop, or a JSON reply."""
    if any(os.environ.get(name) for name in QUIET_ENVS):
        return None
    root = project_root(Path(event.get("cwd") or os.getcwd()).resolve())
    if root is None:
        return None
    found = reports(root)
    state_file = cairn_dir(root) / "reviews" / "gate.json"
    try:
        state = json.loads(state_file.read_text())
    except (OSError, ValueError):
        state = {}
    current = {slug: source_hash(folder) for slug, folder in found.items()}
    passed = state.get("passed", {})
    changed = [slug for slug in found if passed.get(slug) != current[slug]]
    if not changed:
        return None

    problems: list[str] = []
    stale = [slug for slug in changed if not built_is_current(root, slug, found[slug])]
    if stale:
        problems.append("These reports changed after their last build: "
                        + ", ".join(f"reports/{slug}/report.md" for slug in stale)
                        + ". Run `pixi run report-build`.")
    review = []
    if not problems and not event.get("stop_hook_active"):
        sample = source_hash(SAMPLE) if (SAMPLE / "report.md").is_file() else None
        review = [slug for slug in changed if current[slug] != sample]  # an unchanged sample needs no review
    if review:
        state["blocks"] = 0
        save(state_file, state)
        return {"decision": "block", "reason": self_review(review)}
    if not problems:
        state["passed"] = current
        state["blocks"] = 0
        save(state_file, state)
        return None
    state["blocks"] = state.get("blocks", 0) + 1
    save(state_file, state)
    if state["blocks"] > MAX_BLOCKS:
        state["blocks"] = 0
        save(state_file, state)
        return {"systemMessage": "The report gate stopped blocking after "
                                 f"{MAX_BLOCKS} attempts; still open:\n" + "\n\n".join(problems)}
    return {"decision": "block", "reason": (
        "The report change is not done yet (research-project report gate).\n\n"
        + "\n\n".join(problems)
        + "\n\nRebuild, and finish again."
    )}


def self_review(slugs: list[str]) -> str:
    names = ", ".join(f"reports/{slug}/report.md" for slug in slugs)
    return (
        f"Before finishing, review the report(s) you changed ({names}) as a demanding reviewer at a good"
        f" venue would, using the rubric in {RUBRIC}. Re-read each whole report as its reader sees it"
        " (the built page under .cairn/build/<slug>/), and open every figure the Methods section"
        " relies on. Decide each item R1-R9. Fix every failed item in the report sources and rebuild"
        " (`pixi run report-build`); do not pad sections to satisfy an item. When the report's evidence"
        " or conclusions changed, publish it (`pixi run publish reports/<slug>`). Then finish, and tell"
        " the user which items, if any, you left open and why."
    )


def save(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ignore = path.parent.parent / ".gitignore"  # <cairn dir>/.gitignore, as Cairn writes it: never committed
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
    except ValueError:
        event = {}
    reply = gate(event)
    if reply:
        print(json.dumps(reply))
    return 0


if __name__ == "__main__":
    sys.exit(main())
