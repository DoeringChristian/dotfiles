#!/usr/bin/env python3
"""Stop hook of the standalone-research-project skill: a report change is done only when it is built
and the agent has reviewed it against the rubric.

Registered by the skill's frontmatter, so it runs whenever the agent tries to finish a turn in a
session that used the skill. It costs nothing unless a report's sources changed since the gate last
passed. Then it:

1. blocks when a changed report was not rebuilt (`pixi run report-build`);
2. once per stop, sends the agent back to review each changed direction report itself against
   references/review.md, fix what fails, and rebuild. When the agent finishes after that review
   (`stop_hook_active`), only the build check runs again, so the review never loops.

It blocks at most MAX_BLOCKS times in a row; after that it lets the agent stop and tells the user
what is still open. State lives in generated/reviews/gate.json. Stdlib only.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent
RUBRIC = SKILL / "references" / "review.md"
SAMPLE = SKILL / "assets" / "reports" / "direction"  # a fresh scaffold's direction, replaced later
MAX_BLOCKS = 3
QUIET_ENV = "STANDALONE_REPORT_REVIEWER"  # set by a host (e.g. cairn-agents) that gates reports itself


def project_root(start: Path) -> Path | None:
    for folder in [start, *start.parents]:
        if (folder / "reports" / "report.md").is_file() and (
            (folder / "cairn-report.toml").is_file() or (folder / "pixi.toml").is_file()
        ):
            return folder
    return None


def reports(root: Path) -> dict[str, Path]:
    """Report key ("" for the overview, "a/b" for nested ones) -> its source folder."""
    found = {}

    def walk(folder: Path, key: str) -> None:
        if (folder / "report.md").is_file():
            found[key] = folder
        for child in sorted(folder.iterdir()):
            if child.is_dir() and child.name != "assets" and not child.name.startswith(("_", ".")):
                walk(child, f"{key}/{child.name}" if key else child.name)

    walk(root / "reports", "")
    return found


def source_files(folder: Path) -> list[Path]:
    """A report's own sources: report.md and its assets/ (child reports are separate)."""
    files = [folder / "report.md"]
    if (folder / "assets").is_dir():
        files += sorted(path for path in (folder / "assets").rglob("*") if path.is_file())
    return files


def source_hash(folder: Path) -> str:
    digest = hashlib.sha256()
    for path in source_files(folder):
        digest.update(path.relative_to(folder).as_posix().encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def built_is_current(root: Path, key: str, folder: Path) -> bool:
    data = root / "generated" / "reports" / key / "report-data.json"
    if not data.is_file():
        return False
    built = data.stat().st_mtime
    return all(path.stat().st_mtime <= built for path in source_files(folder))


def gate(event: dict) -> dict | None:
    """The hook's answer: None to let the agent stop, or a JSON reply."""
    if os.environ.get(QUIET_ENV):
        return None
    root = project_root(Path(event.get("cwd") or os.getcwd()).resolve())
    if root is None:
        return None
    found = reports(root)
    state_file = root / "generated" / "reviews" / "gate.json"
    try:
        state = json.loads(state_file.read_text())
    except (OSError, ValueError):
        state = {}
    current = {key: source_hash(folder) for key, folder in found.items()}
    passed = state.get("passed", {})
    changed = [key for key in found if passed.get(key) != current[key]]
    if not changed:
        return None

    problems: list[str] = []
    stale = [key for key in changed if not built_is_current(root, key, found[key])]
    if stale:
        problems.append("These reports changed after their last build: "
                        + ", ".join(f"reports/{key or '.'}/report.md" for key in stale)
                        + ". Run `pixi run report-build`.")
    review = []
    if not problems and not event.get("stop_hook_active"):
        sample = source_hash(SAMPLE) if (SAMPLE / "report.md").is_file() else None
        review = [key for key in changed if key and current[key] != sample]  # not the overview or an unchanged sample
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
        "The report change is not done yet (standalone-research-project report gate).\n\n"
        + "\n\n".join(problems)
        + "\n\nRebuild, and finish again."
    )}


def self_review(keys: list[str]) -> str:
    names = ", ".join(f"reports/{key}/report.md" for key in keys)
    return (
        f"Before finishing, review the report(s) you changed ({names}) as a demanding reviewer at a good"
        f" venue would, using the rubric in {RUBRIC}. Re-read each whole report as its reader sees it"
        " (the built page under generated/reports/), and open every figure the Methods section relies on."
        " Decide each item R1-R9. Fix every failed item in the report sources and rebuild"
        " (`pixi run report-build`); do not pad sections to satisfy an item. Then finish, and tell the"
        " user which items, if any, you left open and why."
    )


def save(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
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
