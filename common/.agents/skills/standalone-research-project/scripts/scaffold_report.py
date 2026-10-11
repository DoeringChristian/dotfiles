#!/usr/bin/env python3
"""Install the canonical interactive report template into a project."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path, help="Project root")
    parser.add_argument("--report", help="Optional additional report slug")
    parser.add_argument("--force", action="store_true", help="Replace reports/")
    args = parser.parse_args()

    source = Path(__file__).resolve().parent.parent / "assets" / "report-template"
    reports_root = args.project.resolve() / "reports"
    if args.report and (not args.report[0].isalnum() or any(character not in "abcdefghijklmnopqrstuvwxyz0123456789-" for character in args.report)):
        raise SystemExit("report slug must contain lowercase letters, digits, and hyphens")
    destination = reports_root / args.report if args.report else reports_root
    if destination.exists() and not args.force:
        raise SystemExit(f"{destination} exists; merge it or pass --force")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    print(f"Installed report template at {destination}")
    print(f"Build: python {destination / 'build.py'}")
    print(f"Serve all reports: python {reports_root / 'serve_reports.py'} --host 127.0.0.1 --port 8000")


if __name__ == "__main__":
    main()
