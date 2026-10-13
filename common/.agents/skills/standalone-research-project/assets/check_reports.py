#!/usr/bin/env python3
"""Check the project's reports against the standalone-research-project conventions.

Copy into a project as `tools/check_reports.py` and run it after every build
(`pixi run report-build` does both). cairn-report builds any report tree; this
script holds the project's rules, so a broken convention fails here:

- the overview (reports/report.md) has exactly Introduction, Status, and
  Research directions, and a `reports` fence;
- every research direction (reports/<slug>/report.md) has a title, a summary of
  at most 400 characters, and the paper-like spine (Abstract first, Conclusion
  last, with Introduction, Background and related work, and Methods);
- every direction's Methods explains the method like a paper: the subsections
  Problem setup, Method, Why it works, Relation to the baselines,
  Implementation, and Experimental design, at least 400 words of explanation,
  a display equation or a numbered algorithm, and at least two figures;
- findings carry one of the allowed statuses and a qualitative title (no result
  numbers, no {{ }} values);
- reports read only completed runs (run.json status "completed");
- `html raw` blocks stay short (larger HTML belongs in an `html include` file).

It also lists the numbers still typed in prose: each must be a design constant,
never a result. Exit status 1 means at least one rule is broken.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

FINDING_STATES = {"tentative", "supported", "contradicted", "superseded"}
OVERVIEW_SECTIONS = ["Introduction", "Status", "Research directions"]
SPINE_REQUIRED = [
    "Abstract",
    "Introduction",
    "Background and related work",
    "Methods",
    "Conclusion",
]
SUMMARY_MAX_CHARS = 400
METHODS_SUBSECTIONS = [
    "Problem setup",
    "Method",
    "Why it works",
    "Relation to the baselines",
    "Implementation",
    "Experimental design",
]
METHODS_MIN_WORDS = 400
METHODS_MIN_FIGURES = 2
GRAPHVIZ = ("dot", "neato", "fdp", "sfdp", "circo", "twopi")
RAW_HTML_MAX_LINES = 20
RAW_HTML_MAX_CHARS = 1_500
TYPED_NUMBER = re.compile(
    r"(?<![\w.#/-])\d+(?:\.\d+)?\s?%|(?<![\w.#/-])\d+\.\d+(?![\w.])"
)
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
COMMENT = re.compile(r"<!--.*?-->", re.S)


def project_root() -> Path:
    for folder in [Path.cwd(), *Path.cwd().parents]:
        if (folder / "pixi.toml").is_file() or (folder / "cairn-report.toml").is_file():
            return folder
    return Path.cwd()


def headings(markdown: str) -> list[str]:
    """Level-2 headings outside code fences and comments."""
    found, fence = [], None
    for line in COMMENT.sub("", markdown).splitlines():
        match = FENCE.match(line)
        if match:
            fence = (
                None
                if fence
                and match.group(1).startswith(fence[0])
                and len(match.group(1)) >= len(fence)
                else (fence or match.group(1))
            )
            continue
        if fence is None and line.startswith("## "):
            found.append(line[3:].strip())
    return found


def raw_html_blocks(markdown: str):
    """(line, text) of every `html raw` fence."""
    lines, index = markdown.splitlines(), 0
    while index < len(lines):
        match = FENCE.match(lines[index])
        if match and match.group(2).split()[:2] == ["html", "raw"]:
            start, body, index = index + 1, [], index + 1
            while index < len(lines) and not lines[index].startswith(match.group(1)):
                body.append(lines[index])
                index += 1
            yield start, "\n".join(body)
        index += 1


def section(markdown: str, title: str) -> str:
    """The text of a `## title` section, up to the next level-2 heading (fences respected)."""
    lines, out, inside, fence = COMMENT.sub("", markdown).splitlines(), [], False, None
    for line in lines:
        match = FENCE.match(line)
        if match:
            fence = (
                None
                if fence
                and match.group(1).startswith(fence[0])
                and len(match.group(1)) >= len(fence)
                else (fence or match.group(1))
            )
        elif fence is None and line.startswith("## "):
            if inside:
                break
            inside = line[3:].strip() == title
            continue
        if inside:
            out.append(line)
    return "\n".join(out)


def methods_problems(source: str, methods: str) -> list[str]:
    """What keeps a Methods section from explaining the method like a paper."""
    problems, prose, figures, fence, block = [], [], 0, None, []
    subsections = [
        line[4:].strip() for line in methods.splitlines() if line.startswith("### ")
    ]
    missing = [name for name in METHODS_SUBSECTIONS if name not in subsections]
    if missing:
        problems.append(
            f"{source}: Methods needs the subsections {METHODS_SUBSECTIONS} in this order; missing {missing}"
        )
    elif [
        name for name in subsections if name in METHODS_SUBSECTIONS
    ] != METHODS_SUBSECTIONS:
        problems.append(
            f"{source}: Methods subsections must come in the order {METHODS_SUBSECTIONS}"
        )
    for line in methods.splitlines():
        match = FENCE.match(line)
        if match and fence is None:
            fence, block = match, []
            info = match.group(2).split()
            if info[:1] and info[0] in GRAPHVIZ:
                figures += 1
            continue
        if match and fence is not None and match.group(1).startswith(fence.group(1)[0]):
            if fence.group(2).split()[:2] == ["python", "exec"] and re.search(
                r"\bplt\.|\.subplots\(|figure\(", "\n".join(block)
            ):
                figures += 1
            fence = None
            continue
        if fence is not None:
            block.append(line)
            continue
        figures += line.count("![")
        prose.append(line)
    text = "\n".join(prose)
    words = len(
        re.findall(
            r"[A-Za-z][A-Za-z'-]+",
            re.sub(r"\$\$.*?\$\$|\$[^$\n]*\$", " ", text, flags=re.S),
        )
    )
    if words < METHODS_MIN_WORDS:
        problems.append(
            f"{source}: Methods has {words} words of explanation; explain the method like a paper (at least {METHODS_MIN_WORDS})"
        )
    if "$$" not in text and not re.search(r"^\s*1\.\s", text, re.M):
        problems.append(
            f"{source}: Methods needs the method's equations (a display equation) or its algorithm (numbered steps)"
        )
    if figures < METHODS_MIN_FIGURES:
        problems.append(
            f"{source}: Methods has {figures} figure(s); illustrate the model and each key concept (at least {METHODS_MIN_FIGURES})"
        )
    return problems


def front_matter(markdown: str) -> str:
    match = re.match(r"---\n(.*?)\n---", markdown, re.S)
    return match.group(1) if match else ""


def check(root: Path) -> tuple[list[str], list[str]]:
    reports_dir, built = root / "reports", root / "generated" / "reports"
    problems, notes = [], []
    if not (reports_dir / "report.md").is_file():
        return [f"{reports_dir / 'report.md'}: the overview is missing"], notes
    directions = sorted(
        folder
        for folder in reports_dir.iterdir()
        if folder.is_dir()
        and (folder / "report.md").is_file()
        and not folder.name.startswith(("_", "."))
    )

    overview = (reports_dir / "report.md").read_text()
    if headings(overview) != OVERVIEW_SECTIONS:
        problems.append(
            f"reports/report.md: sections must be exactly {OVERVIEW_SECTIONS}, found {headings(overview)}"
        )
    if not re.search(r"^ {0,3}(`{3,}|~{3,})reports\s*$", overview, re.M):
        problems.append(
            "reports/report.md: Research directions needs a ```reports fence"
        )

    for folder in directions:
        source = f"reports/{folder.name}/report.md"
        markdown = (folder / "report.md").read_text()
        if not re.search(r"^title:\s*\S", front_matter(markdown), re.M):
            problems.append(f"{source}: front matter needs a title")
        sections = headings(markdown)
        missing = [name for name in SPINE_REQUIRED if name not in sections]
        if missing:
            problems.append(f"{source}: missing sections {missing}")
        elif sections[0] != "Abstract" or sections[-1] != "Conclusion":
            problems.append(
                f"{source}: Abstract must come first and Conclusion last (found {sections})"
            )
        if "Methods" in sections:
            problems.extend(methods_problems(source, section(markdown, "Methods")))
        data_file = built / folder.name / "report-data.json"
        if not data_file.is_file():
            problems.append(f"{source}: not built; run `pixi run report-build`")
            continue
        summary = json.loads(data_file.read_text()).get("summary", "")
        if not summary:
            problems.append(
                f"{source}: a research direction needs a front matter `summary:` (one to three sentences)"
            )
        elif len(summary) > SUMMARY_MAX_CHARS:
            problems.append(
                f"{source}: summary is {len(summary)} characters; keep it to at most {SUMMARY_MAX_CHARS}"
            )

    for folder in [reports_dir, *directions]:
        key = "" if folder == reports_dir else folder.name
        source = f"reports/{key + '/' if key else ''}report.md"
        out = built / key if key else built
        data_file, manifest_file = out / "report-data.json", out / "manifest.json"
        if not data_file.is_file() or not manifest_file.is_file():
            continue
        for finding in json.loads(data_file.read_text()).get("findings", []):
            where = f"{source}:{finding['line']}"
            if finding["state"] not in FINDING_STATES:
                problems.append(
                    f"{where}: finding status {finding['state']!r} is not one of {sorted(FINDING_STATES)}"
                )
            if TYPED_NUMBER.search(finding["title"]) or "{{" in finding["title"]:
                problems.append(
                    f"{where}: finding title {finding['title']!r} contains a result number; state the claim qualitatively"
                )
        manifest = json.loads(manifest_file.read_text())
        for run, status in manifest.get("source_runs", {}).items():
            if status != "completed":
                problems.append(
                    f"{source}: reads run {run} whose run.json status is {status!r}, not 'completed'"
                )
        for line, block in raw_html_blocks((folder / "report.md").read_text()):
            if (
                block.count("\n") + 1 > RAW_HTML_MAX_LINES
                or len(block) > RAW_HTML_MAX_CHARS
            ):
                problems.append(
                    f"{source}:{line}: html raw block is longer than {RAW_HTML_MAX_LINES} lines or "
                    f"{RAW_HTML_MAX_CHARS} characters; move it to assets/<name>.html and use an `html include` fence"
                )
        typed = manifest.get("typed_numbers", [])
        if typed:
            shown = ", ".join(f"{hit['line']}:{hit['text']}" for hit in typed[:12])
            notes.append(
                f"{source}: typed numbers (line:text) {shown}{' …' if len(typed) > 12 else ''}"
                " — results must be {{ }} values; leave only design constants typed"
            )
    return problems, notes


def main() -> int:
    problems, notes = check(project_root())
    for note in notes:
        print(f"note: {note}")
    for problem in problems:
        print(f"error: {problem}")
    if problems:
        print(f"{len(problems)} report convention(s) broken")
        return 1
    print("reports follow the project conventions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
