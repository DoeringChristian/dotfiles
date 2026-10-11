# Method narrative

The diagnostic combines a data term $L_{data}$ with a smoothness term:

$$
L(\theta) = L_{data}(\theta) + \lambda \lVert \nabla \theta \rVert_2^2.
$$

This Markdown file is the authored narrative. Rendered blocks retain their
source line, so comments can point back here even as the report evolves.

!!! question "Synchronization needed"
    Confirm whether the remaining high-frequency artifact is acceptable before
    the project proceeds from feasibility testing to parameter tuning.

## Executable evidence

Plain `python` fences are display-only. A `python exec` fence runs during the
build in a shared namespace, embeds stdout, and adds every Matplotlib figure to
the report lightbox.

```python exec hide
import json
import numpy as np
import matplotlib.pyplot as plt

metadata = json.loads((REPORT_ROOT / "report.json").read_text())
x = np.linspace(0, 12, 80)
loss = 0.42 * np.exp(-x / 2.8) + 0.071
plt.figure(figsize=(7.2, 3.2))
plt.plot(x, loss, color="#176b5b", linewidth=2.5)
plt.axhline(0.071, color="#b56231", linestyle="--", label="observed plateau")
plt.xlabel("Iteration")
plt.ylabel("Residual")
plt.title(f"Executable diagnostic · {metadata['project']}")
plt.legend()
print(f"Final illustrative residual: {loss[-1]:.3f}")
```

The cell reads project data from files rather than copying experimental values
into prose. A failure raises an exception and fails the entire report build.
