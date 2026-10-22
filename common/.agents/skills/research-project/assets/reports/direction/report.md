---
title: Boundary-aware smoothing
description: Feasibility study of smoothing with known boundaries.
# Imported, unchanged teaching data from this skill's assets/sample-run.
# This is demo evidence, not the output of a new completed experiment.
# For real results, verify a completed, validated producer and pin its version.
cairn:
  inputs:
    result: datasets/sample-run@v1
---

<!--
This sample direction exercises the report workflow. Replace its content,
summary, inputs, and assets/ with the direction's own material; keep the spine
(Abstract first, Conclusion last). How to write each section is in the skill's
references/writing-methods.md, with a worked Methods example in
references/example-methods.md. Write the Introduction, Background, and Methods
and publish them before the experiments finish; results follow as runs complete.
-->

```{python}
#| echo: false
#| output: false
import csv
import json
import statistics
from IPython.display import Markdown, SVG, display
from pathlib import Path
result_dir = Path("evidence")
inputs["result"].download(to=result_dir)

# The imported sample's metrics are a mapping per row, not a run metric stream.
# Actual run curves come from inputs["run"].records(), one logged dictionary per row.
scores = {}
for line in (result_dir / "metrics.jsonl").read_text().splitlines():
    scores.update(json.loads(line))
proposed = scores["boundary_residual_proposed"]
baseline = scores["boundary_residual_global"]
with (result_dir / "tables" / "cases.csv").open(newline="") as handle:
    cases = list(csv.DictReader(handle))
ours = [float(row["boundary_residual"]) for row in cases]
theirs = [float(row["global_residual"]) for row in cases]
stable = sum(row["stable"] == "true" for row in cases)
unstable = len(cases) - stable
wins = sum(a < b for a, b in zip(ours, theirs))
gain = 1 - proposed / baseline
quartiles = statistics.quantiles(ours, n=4)
```

## Abstract

<!--
Abstract: a self-contained summary of the question, approach, principal result,
important qualification, and current decision. Keep the short body summary and current status in sync with this abstract;
frontmatter description remains qualitative.
-->

Status: Feasibility in progress.

```{python}
#| echo: false
display(Markdown(f"""With the true boundaries known, smoothing that skips boundary edges ends at a
boundary residual of {proposed:.3f}, {gain:.0%} below global
smoothing; {unstable} of {len(cases)} sequences still flicker, so
tuning waits for a calibrated flicker score.

Smoothing a noisy lattice removes noise but blurs its boundaries. This
feasibility study tests the classic remedy, a smoothness penalty that skips the
neighbour pairs crossing a boundary, against smoothing everywhere. With the
boundaries taken from the ground truth, it lowers the reconstruction error near
boundaries in {wins} of {len(cases)} synthetic sequences, but
{unstable} sequences flicker in a way the evaluation cannot yet score
reliably, so the method is not ready for tuning. Whether the gain survives
estimated boundaries is untested."""))
```

```{python}
#| echo: false
display(Markdown(f"""| Measure | Value | Interpretation |
| --- | ---: | --- |
| Boundary residual, boundary-aware smoothing | {proposed:.3f} | {gain:.0%} lower than global smoothing; lower is better; mean over {len(cases)} sequences |
| Sequences without flicker | {stable} / {len(cases)} | flicker-band energy at most that of global smoothing |
"""))
```

## Introduction {#sec-introduction}

<!--
Introduction: state the project's shared target in one or two sentences (or
link the published report's checked Introduction anchor), then what this
direction contributes to it: its research question, scope, motivation, and why
this comparison matters for the target.
-->

The project reconstructs lattices from noisy measurements and judges every
method by its error near boundaries and by flicker. Global smoothing is the
standard way to suppress noise, and it fails that target where it is
strictest: it blurs boundaries. This direction asks how much of that error disappears when the
smoothing knows where the boundaries are. It uses the true boundaries, so the
answer is an upper bound on what boundary-aware smoothing can gain, measured on
a bounded set of representative and edge-case sequences before any parameter
study.

## Background and related work

<!--
Background and related work: fill from a literature and prior-art search (a
research subagent when available), with linked sources and links to related
direction reports. Flag any existing version of the idea in an explicit prior-art
callout and say what remains new. Then define every method, baseline, and
variant in a table whose first column is `Method` before results use their
names.
-->

A quadratic penalty on differences between neighbouring values is Tikhonov
regularization. Stopping the smoothing at edges is the idea of the line process
of [Geman and Geman (1984)](https://doi.org/10.1109/TPAMI.1984.4767596), which
infers binary boundary variables that switch the smoothness term off, and of
the anisotropic diffusion of
[Perona and Malik (1990)](https://doi.org/10.1109/34.56205), which lowers the
diffusion coefficient where the gradient is large.

::: {.callout}
**Close prior work: line processes and edge-stopping diffusion**

Both papers already smooth within regions and not across boundaries. This
direction is a replication on lattice sequences with known boundaries; what
it adds is the measurement of flicker, which per-image methods do not
consider.
:::

| Method | What it does | Difference from global smoothing | Held constant |
| --- | --- | --- | --- |
| Global smoothing | Penalizes the difference across every neighbour pair | Baseline | Observations, $\lambda$, solver, evaluation |
| Boundary-aware smoothing (proposed) | Penalizes the difference across every neighbour pair except those crossing a boundary | Boundary pairs unpenalized | Observations, $\lambda$, solver, evaluation |

## Methods {#sec-methods}

<!--
Methods: the method as implemented, then the experimental design, to the
standard of a good paper in the field: problem and notation first, the method
stated as equations or an algorithm, why it should work, the baselines in the
same notation, the settings that matter, and the design. Use the figures a paper
would have, computed with the project's own code.
-->

### Problem

Each sequence has $T$ frames. In frame $t$ we observe a noisy lattice
$y_t = \theta^\star_t + \varepsilon_t \in \mathbb{R}^{n}$ (one value per site),
where $\theta^\star_t$ is the ground truth, piecewise smooth with known
boundaries, and $\varepsilon_t$ is independent Gaussian noise of standard
deviation $\sigma$. Each frame is reconstructed separately. A frame is an $H \times W$
grid with $n = HW$ sites, and its neighbour pairs $P$ are the horizontally and
vertically adjacent sites. $D \in \mathbb{R}^{|P| \times n}$ has one row per
pair $(i, j)$, $(D\theta)_{(i,j)} = \theta_j - \theta_i$, and the mask $m \in
\{0, 1\}^{|P|}$ is $0$ for the pairs that cross a boundary and $1$ for all
others; $M = \mathrm{diag}(m)$.

### Boundary-aware smoothing

The reconstruction of a frame minimizes

$$
L(\theta) = \lVert \theta - y \rVert_2^2 + \lambda \lVert M D \theta \rVert_2^2 ,
$$

with weight $\lambda > 0$. The data term keeps $\theta$ close to the
observations; the penalty pulls neighbouring values together. Because the mask
removes exactly the pairs that cross a boundary, the two sides of a boundary are
smoothed independently and the step between them stays sharp. Global smoothing
is the same objective with $M = I$. Both terms are quadratic, so the minimizer
solves $(I + \lambda D^{\top} M D)\,\theta = y$, a symmetric positive definite
system, by conjugate gradients from $\theta = y$ until the relative residual is
below $10^{-6}$.

```{python}
#| echo: false
#| label: fig-boundary-aware-smoothing
#| fig-cap: "With the same λ, global smoothing spreads the step over many sites; skipping the one pair that crosses the boundary keeps it sharp while removing the noise on both sides."
# In a project, import the method from its own code here (for example
# `from reconstruction.smoothing import solve`) from captured report sources
# or a declared source artifact, instead of re-implementing it,
# so the figure shows what the code does. The sample has no project code.
import numpy as np
import matplotlib.pyplot as plt

rng = np.random.default_rng(0)
x = np.linspace(0, 1, 120)
clean = np.where(x < 0.5, 0.2, 0.8)
y = clean + rng.normal(0, 0.06, x.size)
D = np.diff(np.eye(x.size), axis=0)
crossing = np.abs(np.diff(clean)) > 0
solve = lambda mask: np.linalg.solve(np.eye(x.size) + 25.0 * D.T @ np.diag(mask) @ D, y)

figure, axis = plt.subplots(figsize=(7, 2.8), num="boundary-aware-smoothing")
axis.plot(x, y, ".", color="#9aa59e", markersize=3, label="observations y")
axis.plot(x, solve(np.ones(x.size - 1)), color="#b56231", linewidth=1.5, label="global smoothing")
axis.plot(x, solve((~crossing).astype(float)), color="#176b5b", linewidth=2, label="boundary-aware smoothing")
axis.plot(x, clean, "--", color="#202621", linewidth=1, label="ground truth θ*")
axis.set(xlabel="site position", ylabel="value", title="Smoothing across a boundary on a 1-D slice")
axis.legend(fontsize=7, loc="upper left", frameon=False)
display(figure)
plt.close(figure)
```

The figure shows the difference on a one-dimensional slice with a single
boundary: away from the boundary the two methods agree, and at the boundary
only global smoothing spreads the step.

### Why it should work

Inside a region the ground truth varies slowly while the noise is independent
between neighbours, so penalizing neighbour differences removes mostly noise.
Across a boundary the difference is mostly signal, and penalizing it is what
blurs the step; leaving those pairs out removes the blur without giving up the
denoising. The argument assumes that the mask is right: a missed boundary is
blurred as under global smoothing, and a spurious one leaves its pair noisy.
The sample uses the true boundaries, so it measures the gain when this
assumption holds. Each frame is reconstructed separately, so independent
noise in consecutive frames leaves slightly different reconstructions; this
is the possible source of flicker, measured below.

### Experimental design

```{python}
#| echo: false
display(Markdown("The " + str(len(cases)) + r""" evaluated sequences come from one synthetic generator:
$64 \times 64$ frames, $T = 32$ frames per sequence, two to five polygonal
regions per sequence, each with a linear ramp inside, whose boundaries move by
at most one site per frame, and noise with $\sigma = 0.06$; every sequence has
its own seed. Four of them are edge cases with regions narrower than three
sites, where the smoothing has little within-region support. Both methods use
the same $\lambda = 25$, chosen from $\{1, 3, 10, 25, 50, 100\}$ by the
boundary residual of global smoothing on a held-out validation sequence, so the
comparison isolates the mask and, if anything, favours the baseline. Two measures are reported for
each sequence:

1. The **boundary residual**: the root-mean-square of $\theta_t - \theta^\star_t$
   over the sites adjacent to a boundary, averaged over frames.
2. **Flicker**: the energy of the temporal spectrum of $\theta_t -
   \theta^\star_t$ in the upper quarter of temporal frequencies, averaged over
   sites. A sequence counts as stable when this energy is at most that of global
   smoothing."""))
```

## Findings

<!--
Results and discussion sections (Findings, Diagnostics, ... as the question
needs). Until its runs complete, a section holds only a note callout naming the
runs it waits for and the question it will answer. Then: findings for
decision-relevant claims only, with explicit status,
a qualitative title, and numbers generated from declared inputs in the body;
supporting figures taken from the artifacts that hold them; contradictions and
limitations stated plainly. Generated Markdown blockquotes render consistently
in the native reader and standalone export.
-->

```{python}
#| echo: false
display(Markdown(f"""> **Supported: Boundary-aware smoothing lowers the boundary residual**
>
> With the true boundaries, the mean boundary residual is
> {proposed:.3f} against {baseline:.3f} for global smoothing,
> {gain:.0%} lower; per sequence it is lower in {wins} of
> {len(cases)} sequences, with an interquartile range of
> {quartiles[0]:.3f}–{quartiles[2]:.3f} (scatter plot in
> [Diagnostics](#fig-boundary-residual)).
>
> Sources: `sample-run` (`tables/cases.csv`, `metrics.jsonl`) · Reviewed 2026-10-14"""))
```

```{python}
#| echo: false
display(Markdown(f"""> **Tentative: Flicker remains in some sequences**
>
> {unstable} sequences have more flicker-band energy than global
> smoothing. Whether that energy is visible has not been calibrated against
> viewers, so the stability count may over- or understate the problem.
>
> Sources: `sample-run` (`figures/spectrum.svg`, `tables/cases.csv`) · Reviewed 2026-10-14"""))
```

::: {.callout}
**Question: Is the remaining flicker acceptable?**

Confirm whether the flicker in the unstable sequences is acceptable before
the project moves from feasibility to parameter tuning.
:::

## Diagnostics

The scatter plot backs the first finding and the temporal spectrum the second.

```{python}
#| echo: false
#| label: fig-grid
#| fig-cap: "Representative frame. Observation, boundary-aware smoothing, ground truth, and the amplified residual of one frame."
display(SVG(filename=str(result_dir / "figures/grid.svg")))
```
```{python}
#| echo: false
#| label: fig-spectrum
#| fig-cap: "Temporal spectrum of the residual. The marked band is the flicker band of the stability measure."
display(SVG(filename=str(result_dir / "figures/spectrum.svg")))
```
```{python}
#| echo: false
#| label: fig-convergence
#| fig-cap: "Convergence. Mean boundary residual over the first conjugate-gradient iterations of both methods."
payload = json.loads((result_dir / "figures/convergence.plotly.json").read_text())
display({"application/vnd.plotly.v1+json": payload}, raw=True)
```

```{python}
#| echo: false
#| label: fig-boundary-residual
#| fig-cap: "Points below the diagonal gain from skipping boundary pairs; orange points flicker."
import matplotlib.pyplot as plt

figure = plt.figure(figsize=(7.2, 3.2), num="boundary-residual")
plt.scatter(theirs, ours, c=["#176b5b" if r["stable"] == "true" else "#b56231" for r in cases])
limit = max(theirs + ours) * 1.05
plt.plot([0, limit], [0, limit], color="#9aa59e", linewidth=1)
plt.xlabel("Boundary residual, global smoothing")
plt.ylabel("Boundary residual, boundary-aware")
plt.title("Boundary residual per sequence")
display(figure)
plt.close(figure)
```

## Limitations

The boundaries are taken from the ground truth, which a real application does
not have, so the measured gain is an upper bound; an estimated mask fails in
the two ways described in *Why it should work*.

## Conclusion

<!--
Conclusion: the answer the current evidence supports, its limits, and the next
decision or experiment. Mirror it in the short body summary, and update
the related direction reports it changes, linking their checked publication URLs.
-->

Skipping the neighbour pairs that cross a boundary lowers the boundary residual
compared with global smoothing when the boundaries are known. Two questions
remain before tuning:

```{python}
#| echo: false
display(Markdown(f"""1. Calibrate the flicker score with pairwise judgments, and inspect the
   {unstable} unstable sequences for a shared cause.
2. Measure the gain with boundaries estimated from the observations, which
   decides whether the direction is worth pursuing."""))
```
