#!/usr/bin/env python3
"""Stop hook of the standalone-research-project skill: a report change is done only when it is built
and passed an independent review.

Registered by the skill's frontmatter, so it runs whenever the agent tries to finish a turn in a
session that used the skill. It costs nothing unless a report's sources changed since the last time
the gate passed. Then it:

1. blocks when a changed report was not rebuilt (`pixi run report-build`);
2. reviews every changed direction report (a folder below reports/ with a report.md) with a fresh,
   read-only `claude -p` session that sees only the built report, its figures, and the configs, and
   answers the rubric in references/review.md; it blocks on every failed item, quoting the fix.

It blocks at most MAX_BLOCKS times in a row; after that it lets the agent stop and tells the user
what is still open. A review is recorded with the hash of the report's sources it saw, under
generated/reviews/, so an unchanged report is never reviewed twice. Stdlib only.

Manual use from a project root: `report_gate.py --review <report-key>` runs one review and prints it.
"""

from __future__ import annotations

import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent
RUBRIC = SKILL / "references" / "review.md"
SAMPLE = SKILL / "assets" / "reports" / "direction"  # a fresh scaffold's direction, replaced later
MAX_BLOCKS = 3
REVIEW_TIMEOUT = 900  # seconds per report
REVIEWER_ENV = "STANDALONE_REPORT_REVIEWER"  # set for the reviewer's own session, which never gates


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


class ReportText(HTMLParser):
    """Readable text of a built narrative: headings, prose, math as LaTeX, figures as titled entries."""

    BLOCKS = {"p", "li", "tr", "pre", "blockquote", "div", "section", "article", "h1", "h2", "h3", "h4"}

    def __init__(self, base: Path):
        super().__init__(convert_charrefs=True)
        self.base, self.out, self.skip, self.figure, self.svg, self.parents = base, [], 0, None, 0, []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if self.skip:
            self.skip += tag not in ("br", "img", "input", "meta", "hr")
            return
        if "math-tex" in (attrs.get("class") or ""):
            self.out.append(f" ${attrs.get('data-latex', '')}$ ")
            self.skip = 1
            return
        if tag in ("button", "script", "style"):
            self.skip = 1
            return
        if tag == "svg":
            self.svg += 1
        if tag == "article" and "figure-card" in (attrs.get("class") or ""):
            src = html.unescape(attrs.get("data-src", "")).split("?")[0]
            file = (self.base / src).resolve() if src and not src.startswith("data:") else None
            self.figure = {"id": attrs.get("data-figure-id", ""), "kind": attrs.get("data-figure-type", ""), "file": file}
            self.out.append("\n\n[FIGURE")
        if self.figure is not None and tag in ("h3", "p", "small"):
            self.out.append({"h3": " title:", "p": " caption:", "small": " "}[tag])
        elif tag in ("h1", "h2", "h3", "h4"):
            self.out.append("\n\n" + "#" * int(tag[1]) + " ")
        elif tag in self.BLOCKS:
            self.out.append("\n")
        elif tag in ("td", "th"):
            self.out.append(" | ")
        elif tag in ("strong", "small") and "metric" in self.parents:
            self.out.append(" — ")
        if tag == "article" and "metric" in (attrs.get("class") or "").split():
            self.out.append("\n[METRIC] ")
        self.parents.append((attrs.get("class") or "").split()[0] if attrs.get("class") else tag)

    def handle_endtag(self, tag):
        if self.skip:
            self.skip -= tag not in ("br", "img", "input", "meta", "hr")
            return
        if tag == "svg":
            self.svg -= 1
        if self.parents:
            self.parents.pop()
        if tag == "article" and self.figure is not None:
            file = self.figure["file"]
            where = f" file: {file}" if file and file.is_file() else ""
            self.out.append(f" id={self.figure['id']} kind={self.figure['kind']}{where}]\n")
            self.figure = None

    def handle_data(self, data):
        if not self.skip and not self.svg and data.strip():
            self.out.append(data if self.figure is None else " " + data.strip())

    def text(self) -> str:
        return re.sub(r"\n{3,}", "\n\n", "".join(self.out)).strip()


def review_packet(root: Path, key: str) -> Path:
    """Write what the reviewer may read: the report as text (figures listed with their files)."""
    built = root / "generated" / "reports" / key
    data = json.loads((built / "report-data.json").read_text())
    parser = ReportText(built)
    parser.feed((built / "narrative.html").read_text())
    folder = root / "generated" / "reviews" / (key.replace("/", "__") or "_overview")
    folder.mkdir(parents=True, exist_ok=True)
    header = f"# {data.get('title', key)}\n\n{data.get('subtitle', '')}\n\nSummary: {data.get('summary', '')}\n"
    manifest = built / "manifest.json"
    runs = json.loads(manifest.read_text()).get("source_runs", {}) if manifest.is_file() else {}
    if runs:  # what the reviewer needs to judge the evidence: only completed runs are evidence
        header += "\nRuns this report reads (run.json status):\n" + "".join(
            f"- {run}: {status}\n" for run, status in sorted(runs.items()))
    (folder / "report.txt").write_text(header + "\n" + parser.text() + "\n")
    return folder


def parse_review(text: str) -> dict:
    blocks = re.findall(r"```json\s*(\{.*?\})\s*```", text, re.S)
    if not blocks:
        raise ValueError("the reviewer did not end with a ```json block")
    review = json.loads(blocks[-1])
    if not isinstance(review.get("items"), list) or not review["items"]:
        raise ValueError("the review has no items")
    for item in review["items"]:
        if not isinstance(item, dict) or "id" not in item or not isinstance(item.get("pass"), bool):
            raise ValueError(f"malformed review item: {item!r}")
    return review


def run_review(root: Path, key: str) -> dict:
    """One independent review of a built direction report."""
    claude = shutil.which("claude")
    if not claude:
        raise RuntimeError("the `claude` command is not on PATH")
    folder = review_packet(root, key)
    prompt = RUBRIC.read_text().replace("{{REPORT}}", str(folder / "report.txt")).replace(
        "{{CONFIGS}}", str(root / "configs")).replace("{{SOURCE}}", str(root / "reports" / key / "report.md"))
    env = os.environ | {REVIEWER_ENV: "1"}
    result = subprocess.run(
        [claude, "-p", prompt, "--permission-mode", "default", "--allowedTools", "Read", "Glob", "Grep",
         "--disallowedTools", "Bash", "Edit", "Write", "NotebookEdit", "Skill", "Agent", "WebFetch", "WebSearch"],
        cwd=root, env=env, capture_output=True, text=True, timeout=REVIEW_TIMEOUT, stdin=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        raise RuntimeError(f"the reviewer failed: {(result.stderr or result.stdout).strip()[-500:]}")
    (folder / "review.txt").write_text(result.stdout)
    return parse_review(result.stdout)


def built_is_current(root: Path, key: str, folder: Path) -> bool:
    data = root / "generated" / "reports" / key / "report-data.json"
    if not data.is_file():
        return False
    built = data.stat().st_mtime
    return all(path.stat().st_mtime <= built for path in source_files(folder))


def failed_items(review: dict) -> list[dict]:
    return [item for item in review["items"] if not item["pass"]]


def describe(key: str, items: list[dict]) -> str:
    lines = [f"Review of reports/{key}/report.md failed {len(items)} item(s):"]
    for item in items:
        quote = f' Quote: "{item["quote"]}".' if item.get("quote") else ""
        lines.append(f"- [{item['id']}] {item.get('finding', '')}{quote} Fix: {item.get('fix', '')}")
    return "\n".join(lines)


def gate(event: dict) -> dict | None:
    """The hook's answer: None to let the agent stop, or a JSON reply."""
    if os.environ.get(REVIEWER_ENV):
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
    if not problems:
        reviews = state.setdefault("reviews", {})
        sample = source_hash(SAMPLE) if (SAMPLE / "report.md").is_file() else None
        for key in changed:
            if key == "" or current[key] == sample:
                continue  # the overview is a status page; an unchanged sample is not the project's work
            if reviews.get(key, {}).get("source") != current[key]:
                try:
                    review = run_review(root, key)
                except (RuntimeError, ValueError, subprocess.TimeoutExpired, OSError) as error:
                    return {"systemMessage": f"Report review of reports/{key} could not run ({error}); "
                                             "the report was not reviewed."}
                reviews[key] = {"source": current[key], "items": review["items"]}
            failed = failed_items(reviews[key])
            if failed:
                problems.append(describe(key, failed))
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
        + "\n\nFix these in the report sources, rebuild, and finish again; the gate re-checks only what"
        " changed. If you are sure a review item is wrong, say so to the user with your reason instead"
        " of rewriting the report to satisfy it."
    )}


def save(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(path)


def main() -> int:
    if sys.argv[1:2] == ["--review"]:
        root = project_root(Path.cwd())
        if root is None or len(sys.argv) != 3:
            print("usage (in a project): report_gate.py --review <report-key>", file=sys.stderr)
            return 2
        review = run_review(root, sys.argv[2].strip("/"))
        print(json.dumps(review, indent=2))
        return 1 if failed_items(review) else 0
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
