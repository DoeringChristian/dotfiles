"""Project report tasks over Cairn2's public builder; copy into experiments/."""
from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import tempfile

from cairn import Client
from cairn.reports import build, export, publish

SLUG = re.compile(r"[a-z0-9][a-z0-9_-]*")


def build_report(root, slug, client):
    if not SLUG.fullmatch(slug):
        raise ValueError("Invalid report slug")
    folder = root / "reports" / slug
    entries = [folder / name for name in ("report.md", "report.qmd") if (folder / name).is_file()]
    if len(entries) != 1:
        raise ValueError(f"{slug}: expected exactly one report.md or report.qmd")
    hashes = {}
    for path in folder.rglob("*"):
        relative = path.relative_to(folder)
        if any(part.startswith(".") or part == "__pycache__" for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f"Report sources cannot be symlinks: {relative}")
        if path.is_file():
            hashes[relative.as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    builds = root / ".cairn" / "report-builds"
    builds.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix=slug + "-", dir=builds)) / "bundle"
    result = build(entries[0], output, client=client)
    captured = {entry["path"].removeprefix("sources/"): entry["digest"]
                for entry in result.manifest["files"] if entry["path"].startswith("sources/")}
    if captured != hashes:
        raise ValueError("Declare all report helpers/assets in cairn.resources; source capture must match the report folder")
    preview = root / ".cairn" / "build" / slug
    preview.parent.mkdir(parents=True, exist_ok=True)
    temporary = preview.with_name("." + slug + "-" + output.parent.name)
    temporary.symlink_to(output, target_is_directory=True)
    os.replace(temporary, preview)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("build").add_argument("--report")
    commands.add_parser("publish").add_argument("slug")
    share = commands.add_parser("share")
    share.add_argument("slug")
    share.add_argument("--out", required=True, type=Path)
    serve = commands.add_parser("serve")
    serve.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    root = Path.cwd()
    if args.command == "serve":
        from functools import partial
        handler = partial(http.server.SimpleHTTPRequestHandler, directory=str(root / ".cairn" / "build"))
        with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
            print(f"Report previews: http://127.0.0.1:{args.port}/", flush=True)
            server.serve_forever()
        return
    with Client(project=args.project) as client:
        if args.command == "share":
            print(export(f"reports/{args.slug}@latest", args.out, client=client))
            return
        slugs = ([args.report] if args.report else sorted(
            folder.name for folder in (root / "reports").iterdir()
            if folder.is_dir() and SLUG.fullmatch(folder.name)
        )) if args.command == "build" else [args.slug]
        for slug in slugs:
            result = build_report(root, slug, client)
            print(result.path)
            if args.command == "publish":
                descriptor = publish(result.path, client=client, name=slug)
                print(f"reports/{slug}@v{descriptor['number']} ({descriptor['id']})")


if __name__ == "__main__":
    main()
