#!/usr/bin/env python3
"""Serve the report and persist contextual comments."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COMMENTS = ROOT / "knowledge" / "comments.jsonl"


def current_comments():
    """Fold the append-only revision log into the current comment state."""
    latest = {}
    order = []
    if COMMENTS.exists():
        for line in COMMENTS.read_text().splitlines():
            if not line:
                continue
            row = json.loads(line)
            comment_id = row["id"]
            if comment_id not in latest:
                order.append(comment_id)
            latest[comment_id] = row
    return [latest[comment_id] for comment_id in order]


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT / "generated"), **kwargs)

    def do_GET(self):
        if self.path in ("/api/comments", "/api/comments/export"):
            self._json(200, current_comments(), download=self.path.endswith("/export"))
            return
        super().do_GET()

    def do_POST(self):
        if self.path == "/api/comments/clear":
            self._clear()
            return
        if self.path != "/api/comments":
            self.send_error(404)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size < 2 or size > 16_384:
                raise ValueError("invalid payload size")
            payload = json.loads(self.rfile.read(size))
            text = str(payload.get("text", "")).strip()
            target = str(payload.get("target", "")).strip()
            if not text or len(text) > 4_000 or not target or len(target) > 256:
                raise ValueError("invalid comment")
            comment_id = str(payload.get("id", "")).strip() or str(uuid.uuid4())
            if len(comment_id) > 128:
                raise ValueError("invalid comment ID")
            row = {
                "id": comment_id,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "event": "upsert",
                "target": target,
                "line": payload.get("line"),
                "quote": str(payload.get("quote", ""))[:1_000],
                "text": text,
            }
            COMMENTS.parent.mkdir(exist_ok=True)
            with COMMENTS.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(row) + "\n")
            self._json(201, row)
        except (ValueError, json.JSONDecodeError) as error:
            self._json(400, {"error": str(error)})

    def _clear(self):
        """Resolve every open comment by appending events; history is never erased."""
        size = int(self.headers.get("Content-Length", "0"))
        if size > 1_024:
            self._json(400, {"error": "invalid payload size"})
            return
        self.rfile.read(size)
        now = datetime.now(timezone.utc).isoformat()
        rows = [
            {"id": row["id"], "timestamp": now, "event": "resolve", "resolution": "Cleared from the report"}
            for row in current_comments()
            if row.get("event") != "resolve"
        ]
        COMMENTS.parent.mkdir(exist_ok=True)
        with COMMENTS.open("a", encoding="utf-8") as handle:
            handle.writelines(json.dumps(row) + "\n" for row in rows)
        self._json(200, {"cleared": len(rows)})

    def _json(self, status, value, download=False):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        if download:
            self.send_header("Content-Disposition", 'attachment; filename="report-comments.json"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / "build.py")], check=True)
    print(f"Report: http://{args.host}:{args.port}")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
