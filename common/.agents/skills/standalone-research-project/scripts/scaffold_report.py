#!/usr/bin/env python3
"""Install the report tooling, the overview, and research-direction reports.

    scaffold_report.py <project>                  # tooling + overview + sample direction
    scaffold_report.py <project> --report <slug>  # add the direction reports/<slug>/
    scaffold_report.py <project> --update-tooling # replace build.py, serve.py, template/

reports/report.md is the overview (super-report, served at /). Each research
direction is reports/<slug>/ with its own report.md (front matter `summary:`),
fragments/, media/, and knowledge/comments.jsonl. Reports are never overwritten.
"""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path

SOURCE = Path(__file__).resolve().parent.parent / "assets" / "report-template"
TOOLING = ("build.py", "serve.py", "template")
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


def install_tooling(reports_root: Path, replace: bool) -> None:
    for name in TOOLING:
        target = reports_root / name
        if target.exists() and not replace:
            continue
        if target.is_dir():
            shutil.rmtree(target)
        copy_writable(SOURCE / name, target)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("project", type=Path, help="project root (the folder with pixi.toml)")
    parser.add_argument("--report", help="slug of a research direction to add")
    parser.add_argument("--update-tooling", action="store_true", help="replace the shared build.py, serve.py, and template/")
    args = parser.parse_args()

    reports_root = args.project.resolve() / "reports"
    first_install = not (reports_root / "report.md").exists()
    install_tooling(reports_root, replace=args.update_tooling)
    print(f"Shared tooling in {reports_root}: build.py, serve.py, template/")
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
    print(f"Build: python {reports_root / 'build.py'}    Serve: python {reports_root / 'serve.py'}")

if __name__ == "__main__":
    main()
