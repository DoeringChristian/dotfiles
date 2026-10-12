#!/usr/bin/env python3
"""Install the report tooling, the overview, and research-direction reports.

    scaffold_report.py <project>                  # tooling + overview + sample direction
    scaffold_report.py <project> --report <slug>  # add the direction reports/<slug>/
    scaffold_report.py <project> --update-tooling # replace report-tooling/ from the skill

report-tooling/ (build.py, serve.py, template/, TOOLING.json) is installed from the
skill and is not edited in the project. reports/ holds content only: report.md is
the overview (served at /); each research direction is reports/<slug>/ with its own
report.md (front matter `summary:`), fragments/, media/, and knowledge/comments.jsonl.
Reports are never overwritten. Build output goes to generated/reports/.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

SOURCE = Path(__file__).resolve().parent.parent / "assets" / "report-template"
TOOLING = ("build.py", "serve.py", "template")
TOOL_DIR = "report-tooling"
SLUG = re.compile(r"[a-z0-9][a-z0-9-]{0,62}")
RESERVED = {"overview", "template", "generated", "knowledge", "fragments", "media"}
SAMPLE_DIRECTION = "local-fitting"  # the sample overview links to this slug


def copy_writable(source: Path, destination: Path) -> None:
    """Copy contents only. Skill installs may be read-only (plugin caches, shared
    mounts, dotfiles); neither file nor directory permission bits are carried over."""
    if source.is_dir():
        destination.mkdir(parents=True, exist_ok=True)
        for child in source.iterdir():
            if child.name != "__pycache__":
                copy_writable(child, destination / child.name)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)


def install_tooling(project: Path, replace: bool) -> Path:
    """Copy build.py, serve.py, and template/ to report-tooling/ and record their hashes."""
    tool_root = project / TOOL_DIR
    if tool_root.exists() and not replace:
        return tool_root
    if tool_root.exists():
        shutil.rmtree(tool_root)
    for name in TOOLING:
        copy_writable(SOURCE / name, tool_root / name)
    files = sorted(path for path in tool_root.rglob("*") if path.is_file())
    hashes = {path.relative_to(tool_root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    version = hashlib.sha256("".join(f"{name}:{digest}" for name, digest in hashes.items()).encode()).hexdigest()[:16]
    (tool_root / "TOOLING.json").write_text(json.dumps({
        "skill_version": version,
        "source": "standalone-research-project skill, assets/report-template",
        "note": "Do not edit these files in the project; change the skill and run scaffold_report.py --update-tooling.",
        "files": hashes,
    }, indent=2) + "\n")
    return tool_root


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("project", type=Path, help="project root (the folder with pixi.toml)")
    parser.add_argument("--report", help="slug of a research direction to add")
    parser.add_argument("--update-tooling", action="store_true", help="replace the shared build.py, serve.py, and template/")
    args = parser.parse_args()

    project = args.project.resolve()
    reports_root = project / "reports"
    first_install = not (reports_root / "report.md").exists()
    tool_root = install_tooling(project, replace=args.update_tooling)
    print(f"Report tooling in {tool_root} (do not edit; update with --update-tooling)")
    stale = [name for name in TOOLING if (reports_root / name).exists()]
    if stale:
        print(f"note: old tooling inside reports/ ({', '.join(stale)}) is no longer used; remove it so reports/ holds content only")
    if first_install:
        for name in ("report.md", "knowledge"):
            copy_writable(SOURCE / "overview" / name, reports_root / name)
        print(f"Overview: {reports_root / 'report.md'}")
    slug = args.report or (SAMPLE_DIRECTION if first_install else None)
    if slug is None:
        return
    if not SLUG.fullmatch(slug) or slug in RESERVED:
        raise SystemExit(f"invalid direction slug {slug!r}: lowercase letters, digits, hyphens; not {sorted(RESERVED)}")
    destination = reports_root / slug
    if destination.exists():
        raise SystemExit(f"{destination} already exists; reports are never overwritten")
    copy_writable(SOURCE / "report", destination)
    print(f"Research direction: {destination / 'report.md'} (replace the sample content and summary)")
    print(f"Build: python {tool_root / 'build.py'}    Serve: python {tool_root / 'serve.py'}")

if __name__ == "__main__":
    main()
