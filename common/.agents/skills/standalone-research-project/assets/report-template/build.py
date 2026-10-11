#!/usr/bin/env python3
"""Build the canonical standalone research report."""

from __future__ import annotations

import hashlib
import html
import re
import io
import json
import shutil
import contextlib
import base64
from datetime import datetime, timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from markdown_it import MarkdownIt
from mdit_py_plugins.admon import admon_plugin
from mdit_py_plugins.dollarmath import dollarmath_plugin
from latex2mathml.converter import convert as latex_to_mathml
from plotly.offline import get_plotlyjs

ROOT = Path(__file__).resolve().parent
GENERATED = ROOT / "generated"


DELIMITERS = set("|‖()[]{}⟨⟩⌈⌉⌊⌋/∣∥")
BARE_MO = re.compile(r"<mo>(&#x([0-9A-Fa-f]+);|[^<])</mo>")


def unstretch_delimiters(mathml: str) -> str:
    """Mark bare delimiters non-stretchy: in LaTeX only \\left/\\right delimiters grow.

    latex2mathml emits e.g. \\lVert as a plain <mo>, which MathML renderers stretch
    as a fence, so the two sides of a norm render at different heights.
    """

    def fix(match):
        char = chr(int(match.group(2), 16)) if match.group(2) else match.group(1)
        return f'<mo stretchy="false">{match.group(1)}</mo>' if char in DELIMITERS else match.group(0)

    return BARE_MO.sub(fix, mathml)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render_markdown(path: Path) -> str:
    """Render Markdown and execute only fences explicitly marked python exec."""
    namespace = {"REPORT_ROOT": ROOT, "PROJECT_ROOT": ROOT.parent}
    def render_math(content, options):
        display = "block" if options.get("display_mode") else "inline"
        mathml = unstretch_delimiters(latex_to_mathml(content, display=display))
        latex = html.escape(content.strip(), quote=True)
        return f'<span class="math-tex" data-latex="{latex}">{mathml}</span>'

    md = MarkdownIt("commonmark", {"html": False}).use(
        dollarmath_plugin, renderer=render_math, allow_labels=True
    ).use(admon_plugin)
    default_fence = md.renderer.rules["fence"]

    def source_lines(state):
        for token in state.tokens:
            if token.map and token.nesting == 1:
                token.attrSet("data-source-line", str(token.map[0] + 1))

    def fence(tokens, idx, options, env):
        token = tokens[idx]
        info = token.info.split()
        if info[:2] != ["python", "exec"]:
            line = (token.map or [0])[0] + 1
            return f'<div data-source-line="{line}">' + default_fence(tokens, idx, options, env) + "</div>"
        flags = set(info[2:])
        line = (token.map or [0])[0] + 1
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exec(compile(token.content, f"{path}:line-{line}", "exec"), namespace)
        result = f'<div class="exec-block" data-source-line="{line}">'
        if "hide" not in flags:
            result += f'<pre class="src"><code>{html.escape(token.content)}</code></pre>'
        if stdout.getvalue():
            result += f'<pre class="out">{html.escape(stdout.getvalue())}</pre>'
        for number in plt.get_fignums():
            payload = io.BytesIO()
            plt.figure(number).savefig(payload, format="png", dpi=160, bbox_inches="tight")
            encoded = base64.b64encode(payload.getvalue()).decode()
            result += (
                f'<img src="data:image/png;base64,{encoded}" '
                f'alt="Executable Markdown figure from line {line}">'
            )
        plt.close("all")
        return result + "</div>"

    def with_source_line(rule):
        def render(tokens, idx, options, env):
            line = (tokens[idx].map or [0])[0] + 1
            return f'<div data-source-line="{line}">' + rule(tokens, idx, options, env) + "</div>"

        return render

    for name in ("math_block", "math_block_label"):
        if name in md.renderer.rules:
            md.renderer.rules[name] = with_source_line(md.renderer.rules[name])

    md.core.ruler.push("source_lines", source_lines)
    md.renderer.rules["fence"] = fence
    return md.render(path.read_text())


def main() -> None:
    source = ROOT / "report.json"
    data = json.loads(source.read_text())
    GENERATED.mkdir(exist_ok=True)
    for name in ("index.html", "report.css", "report-extra.css", "report.js"):
        shutil.copy2(ROOT / "template" / name, GENERATED / name)
    (GENERATED / "plotly.min.js").write_text(get_plotlyjs())
    if (ROOT / "media").exists():
        shutil.copytree(ROOT / "media", GENERATED / "media", dirs_exist_ok=True)
    (GENERATED / "report-data.json").write_text(json.dumps(data, indent=2) + "\n")
    markdown_source = ROOT / "report.md"
    (GENERATED / "narrative.html").write_text(render_markdown(markdown_source))
    manifest = {
        "built_at": datetime.now(timezone.utc).isoformat(),
        "report_source": str(source.relative_to(ROOT.parent)),
        "report_sha256": digest(source),
        "markdown_source": str(markdown_source.relative_to(ROOT.parent)),
        "markdown_sha256": digest(markdown_source),
        "source_runs": data.get("source_runs", []),
    }
    (GENERATED / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {GENERATED / 'index.html'}")


if __name__ == "__main__":
    main()
