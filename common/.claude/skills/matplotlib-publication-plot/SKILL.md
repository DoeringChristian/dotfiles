---
name: matplotlib-publication-plot
description: >
  Create publication-quality matplotlib figures saved as PNG, PDF, and PGF
  with LaTeX (Computer Modern serif font, lualatex). Use when asked to create
  a plot, figure, or visualization for a thesis, paper, or publication, or
  when the user mentions textwidth, PGF, LaTeX rendering, or production-ready
  figures.
---

# Matplotlib Publication Plot

Creates publication-ready figures rendered with LaTeX (Computer Modern font),
saved as PNG (preview), PDF, and PGF (for `\includegraphics` in LaTeX documents).

## Critical pitfalls (learned the hard way)

### 1. Font must be set at figure *creation* time
`font.family` is baked into each text artist's `FontProperties` when the artist
is created — not at save time. The figure **must** be created inside the
`rc_context`, otherwise all text uses the default sans-serif font and the PGF
output emits `\sffamily` everywhere instead of `\rmfamily`.

### 2. Never use `savefig(bbox_inches=...)` with the PGF backend
Passing `bbox_inches` to `savefig` silently bypasses `print_pdf`/`print_pgf`
and falls back to matplotlib's own (non-LaTeX) PDF writer. Always call
`fig.canvas.print_pdf()` and `fig.canvas.print_pgf()` directly.

### 3. Use `lualatex`, not `pdflatex`
`pdflatex` needs `type1ec.sty` (from `texlive-fonts-extra`) for Type1 fonts.
`lualatex` does not, and handles Unicode natively.

### 4. Do not use `text.usetex=True` with the Agg backend
The Agg texmanager calls plain `latex` (not lualatex) and requires
`type1ec.sty`. Use the PGF backend for LaTeX rendering instead.

### 5. `pgf.rcfonts: False` — do NOT load fonts via fontspec
With `pgf.rcfonts: True` (default), the PGF backend injects
`\usepackage{fontspec}` and loads DejaVu Sans, overriding Computer Modern.
Set `pgf.rcfonts: False` to let the document's font (CM by default) apply.

### 6. PNG must be saved before swapping the canvas
`plt.savefig(output_png, dpi=150, bbox_inches="tight")` uses the Agg canvas
that was active when the figure was created. Swap to `FigureCanvasPgf` only
after saving the PNG.

### 7. Colorbar alignment with `constrained_layout`
If some panels have colorbars and others don't, `constrained_layout` allocates
different column widths, misaligning panel centres. Fix: add an invisible
colorbar to every panel with identical `fraction` and `pad`, and call
`cb.set_ticks([])` + `cb.ax.set_visible(False)` on the hidden one.

### 8. `set_box_aspect(1)` not `set_aspect("equal")` for equal-height panels
`set_aspect("equal")` shrinks colorbared axes relative to un-colorbared ones.
`set_box_aspect(1)` pins the axes *rectangle* aspect uniformly regardless of
colorbar presence.

### 9. Marker edge outlines with `c=` vs `color=`
Using `c="C0"` goes through the colour-array code path and renders edge
outlines. Use `color="C0"` (or `c=array`) with `edgecolors="none"` explicitly.

### 10. `tikzplotlib` is broken with recent matplotlib
`common_texification` was removed from `matplotlib.backends.backend_pgf`.
Do not use tikzplotlib; use the PGF backend directly.

---

## Standard template

```python
import matplotlib
from matplotlib.backends.backend_pgf import FigureCanvasPgf

# LaTeX document textwidth in inches (1 pt = 1/72.27 in, TeX points)
_width_in  = 418.255555 / 72.27   # replace with your \textwidth in pt
_height_in = _width_in * 0.42      # adjust ratio as needed

with matplotlib.rc_context({
    # Font — must be set here so all text artists get \rmfamily
    "font.family":      "serif",
    "pgf.texsystem":    "lualatex",
    "pgf.rcfonts":      False,       # don't override CM with DejaVu via fontspec
    # Sizes (pt) — scale to the figure width
    "font.size":        7,
    "axes.titlesize":   7,
    "axes.labelsize":   6,
    "xtick.labelsize":  5,
    "ytick.labelsize":  5,
    "legend.fontsize":  5,
    # Tight spacing
    "xtick.major.pad":  2,
    "ytick.major.pad":  2,
    "axes.labelpad":    2,
}):
    fig, axes = plt.subplots(1, N, figsize=(_width_in, _height_in),
                             layout="constrained")
    fig.get_layout_engine().set(w_pad=0.01, h_pad=0.01, hspace=0, wspace=0.05)

    # --- build each panel ---
    # Use color="C0", color="C1", ... for categorical colours (default cycle)
    # Use edgecolors="none" on every scatter call to suppress marker outlines
    # Use set_box_aspect(1) for square panels (not set_aspect("equal"))
    # For panels WITHOUT a colorbar, add an invisible one with identical
    #   fraction/pad so constrained_layout sees the same column structure:
    #
    #   _dummy = ax.scatter([], [], c=[], cmap="viridis", vmin=0, vmax=1)
    #   cb = fig.colorbar(_dummy, ax=ax, fraction=0.046, pad=0.02)
    #   cb.set_ticks([]); cb.ax.set_visible(False)
    #
    # Suppress redundant y-axis tick labels on non-leftmost panels:
    #   ax.set_yticklabels([])

    # --- save ---
    # PNG first (Agg canvas still active)
    plt.savefig(output_png, dpi=150, bbox_inches="tight")
    # PDF + PGF via PGF backend — never pass bbox_inches here
    fig.canvas = FigureCanvasPgf(fig)
    fig.canvas.print_pdf(output_pdf)
    fig.canvas.print_pgf(output_pgf)
    plt.close()
```

---

## Style conventions (this project)

| Property | Value |
|---|---|
| LaTeX textwidth | `418.255555 pt` → `5.787 in` |
| Height for 3-panel row | `_width_in / 3 * 1.2` (~2.3 in) |
| Font system | `lualatex` + Computer Modern (via `pgf.rcfonts=False`) |
| Base font size | 7 pt |
| Title size | 7–11 pt (match body or slightly larger) |
| Axis label size | 6 pt |
| Tick label size | 5 pt |
| Legend font size | 5 pt |
| Categorical colours | matplotlib default cycle: `C0`, `C1`, `C2`, … |
| Scatter marker edges | always `edgecolors="none"` |
| Grid | `alpha=0.3, linewidth=0.4` |
| Circle overlays | `linewidth=0.5, color="gray", linestyle="--"` |
| Colorbar fraction/pad | `fraction=0.046, pad=0.02` (identical for all panels) |
| Layout engine padding | `w_pad=0.01, h_pad=0.01, wspace=0.05` |

---

## How to include in LaTeX

```latex
\begin{figure}[t]
  \centering
  \includegraphics[width=\textwidth]{figures/my_figure.pdf}
  % or use the PGF file for fully embedded fonts:
  \input{figures/my_figure.pgf}
  \caption{...}
  \label{fig:my-figure}
\end{figure}
```

When using the PGF file, add to the preamble:
```latex
\usepackage{pgf}
```
