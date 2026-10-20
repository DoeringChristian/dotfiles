# Worked example: a Methods section

This is the Methods section of a direction report in the sample project
(lattice reconstruction from noisy measurements). The direction replaces the
hand-set smoothness weight with one predicted by a small network. It shows the
standard the review expects; do not copy its content, sections, or length into
another project.

The executable examples assume the report's `assets/architecture.svg` and the
exact `priors/` source used by the experiment are captured under this report's
folder, or imported
from a declared, pinned source artifact. Declare `prior` as the completed,
validated model artifact. Replace the example report URLs with the actual
published version URL and verify its explicit section anchors.

What it does well:

- the problem and the notation come first, and every later equation uses them;
- the method is stated: the objective, how the weight is predicted, and how the
  network is trained through the solver (an algorithm, because it has stages);
- each non-standard part says why it is there; standard parts are only named;
- one architecture figure (drawn from the model) and one toy figure (computed
  with the project's code) explain what the text cannot show quickly;
- the baselines differ from the method by one term each, in the same notation;
- settings the result depends on are stated, and the rest is left to the
  config.

````markdown
## Methods

### Problem

We observe a noisy lattice $y = \theta^\star + \varepsilon$ on an $H \times W$
grid, where $\theta^\star$ is the clean lattice and $\varepsilon$ is i.i.d.
Gaussian noise of standard deviation $\sigma$. We estimate $\theta^\star$ by
regularized least squares,

$$
\hat\theta(w) = \arg\min_\theta \; \lVert \theta - y \rVert^2 + \sum_{e} w_e \,(D\theta)_e^2 ,
$$

where $D$ takes forward differences between neighbouring grid points (one row
per edge $e$) and $w_e \ge 0$ is the smoothness weight on edge $e$. The
[boundary-aware direction](https://cairn.example/p/study/reports/REPORT_ID?version=VERSION_ID#user-content-methods) sets $w_e = 0$ on the
edges that cross a known boundary and $w_e = \lambda$ elsewhere. Real
observations come without boundaries, so here the weights are predicted from
the observation: $w = f_\phi(y)$.

### Predicting the weights

A small convolutional network $f_\phi$ maps $y$ to one weight per edge
(Figure [Architecture](#fig-architecture)). It sees a $9 \times 9$ neighbourhood
of each edge, enough to tell a boundary (a jump much larger than $\sigma$) from
noise, and its softplus output keeps every weight non-negative, so the
objective stays convex and $\hat\theta(w)$ is unique.

```{python}
#| echo: false
#| label: fig-architecture
#| fig-cap: "Three 3×3 convolutions (receptive field 9×9) and a 1×1 head with two outputs per grid point: the weights of its right and lower edges."
from IPython.display import SVG, display
display(SVG(filename="assets/architecture.svg"))
```

Because the objective is quadratic in $\theta$, the estimate is one linear
solve, $\hat\theta(w) = (I + D^\top \operatorname{diag}(w) D)^{-1} y$, and its
derivative with respect to $w$ follows from implicit differentiation without
unrolling an optimizer. Training therefore minimizes the reconstruction error
of the solve itself:

1. Draw a clean training lattice $\theta^\star$ and noise $\varepsilon$; set
   $y = \theta^\star + \varepsilon$.
2. Predict $w = f_\phi(y)$ and solve for $\hat\theta(w)$ by conjugate
   gradients (tolerance $10^{-6}$).
3. Compute the loss $\lVert \hat\theta(w) - \theta^\star \rVert^2$ and its
   gradient with respect to $w$ by one adjoint solve with the same matrix.
4. Back-propagate through $f_\phi$ and take an Adam step on $\phi$.

The network is never told where the boundaries are: it learns weights that
lead to good reconstructions, and Figure [weights](#fig-weight-slice) shows that
these are small across jumps and large on flat regions.

```{python}
#| echo: false
#| label: fig-weight-slice
import matplotlib.pyplot as plt
from priors.checkpoints import load_checkpoint
from priors.illustrate import weight_slice_figure
figure = weight_slice_figure(load_checkpoint(inputs["prior"] / "model.pt"), num="weight-slice")
display(figure)
plt.close(figure)
```

### Why it should work

Noise is independent between neighbouring points, while the clean lattice is
piecewise smooth, so differences across flat regions are mostly noise and
differences across boundaries are mostly signal. A weight that is large on flat
regions and small at jumps removes noise without blurring the jumps.
Boundary-aware smoothing realizes this pattern only when the boundaries are
given; the network has to infer it from the observation. The approach fails when a jump is comparable to $\sigma$
(the network cannot tell it from noise, tested on the low-contrast cases in
[Edge cases](#edge-cases)) and when test lattices have structure absent from
training (tested by the held-out family in [Generalization](#generalization)).

### Baselines

All methods solve the same objective and differ only in $w$:

| Method | Weights $w_e$ | Learned |
|---|---|---|
| Data only | $0$ | — |
| Global smoothing | $\lambda$ everywhere | $\lambda$ by validation |
| Boundary-aware (known boundaries) | $0$ on edges crossing a true boundary, $\lambda$ elsewhere | $\lambda$ by validation; an upper bound, as it sees the true boundaries |
| **Learned prior** | $f_\phi(y)_e$ | $\phi$ by training |

### Experimental design

Training uses 2,000 synthetic lattices of $64 \times 64$ points with
$\sigma = 0.1$ from the generator in `data/lattices.py`; validation and test
use 200 lattices each from disjoint seeds, plus a held-out family with curved
boundaries that training never sees. All methods are evaluated on the same test
lattices with the boundary residual of the [project target](https://cairn.example/p/study/reports/REPORT_ID?version=VERSION_ID#user-content-introduction).
$\lambda$ of the baselines is chosen on the validation set
by the same grid search, so each baseline is at its best setting. The network
trains for 20 epochs with batch size 16 and learning rate $10^{-3}$; the
remaining settings are in `configs/experiment/learned-prior.yaml`. Every result
is the mean over 3 training seeds, with the spread shown.
````
