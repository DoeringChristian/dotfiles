#!/usr/bin/env python3
"""Build and host all project reports behind a shared catalog."""

from __future__ import annotations

import argparse, json, mimetypes, re, subprocess, sys, uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent
SLUG = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def discover_reports():
    reports = {"main": ROOT}
    for child in sorted(ROOT.iterdir()):
        if child.is_dir() and SLUG.fullmatch(child.name) and (child / "build.py").is_file() and (child / "report.json").is_file():
            reports[child.name] = child
    return reports


def current_comments(report_root):
    latest, order = {}, []
    path = report_root / "knowledge" / "comments.jsonl"
    if path.exists():
        for line in path.read_text().splitlines():
            if line:
                row = json.loads(line); key = row["id"]
                if key not in latest: order.append(key)
                latest[key] = row
    return [latest[key] for key in order]


class Handler(BaseHTTPRequestHandler):
    reports = {}

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/reports":
            rows = []
            for slug, root in self.reports.items():
                data = json.loads((root / "report.json").read_text())
                rows.append({"slug": slug, "title": data.get("project", slug), "subtitle": data.get("subtitle", ""), "status": data.get("status", ""), "updated": data.get("updated", ""), "href": f"/reports/{slug}/"})
            return self._json(200, rows)
        route = self._comment_route(path)
        if route:
            root, action = route
            return self._json(200, current_comments(root), download=action == "export")
        if path == "/": return self._file(ROOT / "template" / "reports-index.html")
        if path in ("/reports-index.css", "/reports-index.js"): return self._file(ROOT / "template" / path[1:])
        match = re.fullmatch(r"/reports/([a-z0-9][a-z0-9-]*)(/.*)?", path)
        if match and match.group(1) in self.reports:
            relative = unquote((match.group(2) or "/").lstrip("/")) or "index.html"
            generated = (self.reports[match.group(1)] / "generated").resolve()
            candidate = (generated / relative).resolve()
            if candidate != generated and generated in candidate.parents and candidate.is_file(): return self._file(candidate)
        self.send_error(404)

    def do_POST(self):
        route = self._comment_route(urlparse(self.path).path)
        if not route: return self.send_error(404)
        root, action = route
        if action == "clear": return self._clear(root)
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size < 2 or size > 16_384: raise ValueError("invalid payload size")
            payload = json.loads(self.rfile.read(size)); text = str(payload.get("text", "")).strip(); target = str(payload.get("target", "")).strip()
            if not text or len(text) > 4_000 or not target or len(target) > 256: raise ValueError("invalid comment")
            key = str(payload.get("id", "")).strip() or str(uuid.uuid4())
            if len(key) > 128: raise ValueError("invalid comment ID")
            row = {"id": key, "timestamp": datetime.now(timezone.utc).isoformat(), "event": "upsert", "target": target, "line": payload.get("line"), "quote": str(payload.get("quote", ""))[:1_000], "text": text}
            self._append(root, row); self._json(201, row)
        except (ValueError, json.JSONDecodeError) as error: self._json(400, {"error": str(error)})

    def _comment_route(self, path):
        match = re.fullmatch(r"/api/reports/([a-z0-9][a-z0-9-]*)/comments(?:/(export|clear))?", path)
        return (self.reports[match.group(1)], match.group(2)) if match and match.group(1) in self.reports else None

    def _clear(self, root):
        size = int(self.headers.get("Content-Length", "0")); self.rfile.read(size)
        if size > 1_024: return self._json(400, {"error": "invalid payload size"})
        now = datetime.now(timezone.utc).isoformat(); rows = [{"id": row["id"], "timestamp": now, "event": "resolve", "resolution": "Cleared from the report"} for row in current_comments(root) if row.get("event") != "resolve"]
        for row in rows: self._append(root, row)
        self._json(200, {"cleared": len(rows)})

    @staticmethod
    def _append(root, row):
        path = root / "knowledge" / "comments.jsonl"; path.parent.mkdir(exist_ok=True)
        with path.open("a", encoding="utf-8") as handle: handle.write(json.dumps(row) + "\n")

    def _file(self, path):
        body = path.read_bytes(); self.send_response(200); self.send_header("Content-Type", mimetypes.guess_type(path.name)[0] or "application/octet-stream"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def _json(self, status, value, download=False):
        body = json.dumps(value).encode(); self.send_response(status); self.send_header("Content-Type", "application/json")
        if download: self.send_header("Content-Disposition", 'attachment; filename="report-comments.json"')
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--host", default="127.0.0.1"); parser.add_argument("--port", type=int, default=8000); args = parser.parse_args()
    reports = discover_reports()
    for root in reports.values(): subprocess.run([sys.executable, str(root / "build.py")], check=True)
    Handler.reports = reports; print(f"Reports: http://{args.host}:{args.port}/ ({len(reports)} available)"); ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__": main()
