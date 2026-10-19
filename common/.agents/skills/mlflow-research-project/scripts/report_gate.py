#!/usr/bin/env python3
"""Folio adaptation of research-project's report Stop hook.

Checks changed direction reports for the paper-like spine and current builds,
then requests the original reviewer pass. State: .folio/reviews/gate.json.
Stdlib only, Python 3.8+. Does not grade scientific quality automatically.
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
MAX_BLOCKS = 3
QUIET_ENVS = ("RESEARCH_REPORT_REVIEWER", "STANDALONE_REPORT_REVIEWER")
SLUG = re.compile(r"[a-z0-9][a-z0-9_-]{0,62}")


class Project:
    def __init__(self, root: Path):
        self.root = root
        self.repo = root / ".folio"
        self.reports_dir = root / "reports"
        path = root / "folio.toml"
        output = "_site"
        if path.is_file():
            text = path.read_text()
            try:
                import tomllib
            except ImportError:
                # The system python3 used by hooks may predate 3.11. Match the
                # documented Folio [project] output-dir string convention.
                table = re.search(r"^\[project\]\s*$(.*?)(?=^\s*\[|\Z)", text, re.M | re.S)
                if table:
                    match = re.search(r"^\s*output-dir\s*=\s*[\"']([^\"']+)[\"']", table.group(1), re.M)
                    if match:
                        output = match.group(1)
            else:
                output = tomllib.loads(text).get("project", {}).get("output-dir", output)
        self.output_dir = root / output


def project(start: Path) -> Project | None:
    for root in (start, *start.parents):
        if (root / "folio.toml").is_file() or (root / "reports").is_dir():
            candidate = Project(root)
            return candidate if reports(candidate) else None
    return None


def reports(proj: Project) -> dict[str, Path]:
    """Report slug -> its source folder (flat: reports/<slug>/report.md)."""
    folder = proj.reports_dir
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


def built_is_current(proj: Project, slug: str, folder: Path) -> bool:
    payload = proj.output_dir / "reports" / slug / "report.files"
    manifest = payload / "manifest.json"
    page = payload.parent / "report.html"
    if not manifest.is_file() or not page.is_file():
        return False
    try:
        data = json.loads(manifest.read_text())
    except (ValueError, OSError):
        return False
    if data.get("markdown_sha256") != hashlib.sha256((folder / "report.md").read_bytes()).hexdigest():
        return False
    built = manifest.stat().st_mtime_ns
    return all(path.stat().st_mtime_ns <= built for path in source_files(folder))


def structure_problems(folder: Path) -> list[str]:
    """Check level-two paper sections, ignoring YAML, comments and fenced examples."""
    text = (folder / "report.md").read_text()
    text = re.sub(r"\A---\s*\n.*?\n---\s*(?:\n|$)", "", text, count=1, flags=re.S)
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    headings, fence = [], None
    for line in text.splitlines():
        match = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if match:
            marker = match.group(1)
            if fence is None:
                fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence):
                fence = None
            continue
        if fence is None:
            match = re.match(r"^## +(.+?) *#* *$", line)
            if match:
                headings.append(match.group(1).casefold())
    required = ["abstract", "introduction", "background and related work", "methods", "conclusion"]
    missing = [name for name in required if headings.count(name) != 1]
    issues = ["Require exactly one ## section for: " + ", ".join(missing)] if missing else []
    if not missing:
        positions = [headings.index(name) for name in required]
        if positions != sorted(positions) or headings[0] != "abstract" or headings[-1] != "conclusion":
            issues.append("Use the ordered paper spine; Abstract first and Conclusion last.")
        middle = headings[positions[3] + 1:positions[4]]
        if not any("results" in h for h in middle) or not any("discussion" in h for h in middle):
            issues.append("Include results and discussion between Methods and Conclusion (combined or separate).")
    return issues


def gate(event: dict) -> dict | None:
    """The hook's answer: None to let the agent stop, or a JSON reply."""
    if any(os.environ.get(name) for name in QUIET_ENVS):
        return None
    proj = project(Path(event.get("cwd") or os.getcwd()).resolve())
    if proj is None:
        return None
    found = reports(proj)
    state_file = proj.repo / "reviews" / "gate.json"
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
    stale = [slug for slug in changed if not built_is_current(proj, slug, found[slug])]
    if stale:
        problems.append("These reports changed after their last build: "
                        + ", ".join(f"reports/{slug}/report.md" for slug in stale)
                        + ". Run `pixi run report-build`.")
    for slug in changed:
        problems.extend(f"reports/{slug}/report.md: {issue}" for issue in structure_problems(found[slug]))
    review = []
    if not problems and not event.get("stop_hook_active"):
        review = changed
    if review:
        problems.append(self_review(review))
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
        "The report change is not done yet (mlflow-research-project report gate).\n\n"
        + "\n\n".join(problems)
        + "\n\nFix the report sources, rebuild, complete the requested review, and finish again."
    )}


def self_review(slugs: list[str]) -> str:
    names = ", ".join(f"reports/{slug}/report.md" for slug in slugs)
    return (
        f"Before finishing, review the report(s) you changed ({names}) as a demanding reviewer at a good"
        f" venue would, using the rubric in {RUBRIC}. Re-read each whole report as its reader sees it"
        " (the built page under the configured Folio output directory at reports/<slug>/report.html), and open every figure the Methods section"
        " relies on. Decide each item R0-R9. Fix every failed item in the report sources and rebuild"
        " (`pixi run report-build`); do not pad sections to satisfy an item. Then finish, and tell"
        " the user which items, if any, you left open and why."
    )


def save(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ignore = path.parent.parent / ".gitignore"  # .folio/.gitignore: local hook state is never committed
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
