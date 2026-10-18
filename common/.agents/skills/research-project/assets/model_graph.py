"""The architecture of a PyTorch model as Graphviz source, drawn from the model itself.

Copy into the report's source folder as `model_graph.py` (needs the `torchview` and
`graphviz` PyPI packages and the Graphviz executable). Capture the model's exact source
there too, or import it from a declared source artifact. Display the graph explicitly
so it is a figure card and always matches the code:

    ```{python}
    #| echo: false
    #| label: fig-architecture
    #| fig-cap: "Tensor shapes for one 32×32 RGB image; the dashed block is what this direction adds."
    import hydra
    from graphviz import Source
    from IPython.display import display
    from model_graph import model_dot
    config = inputs["run"].config
    model = hydra.utils.instantiate(config["experiment"]["model"])
    display(Source(model_dot(model, input_size=(1, 3, 32, 32), depth=2)))
    ```

`depth` sets how far nested modules are expanded: show the level a paper figure would, where each
box is a component the text names, not every primitive layer.
"""

from __future__ import annotations


def model_dot(model, input_size=None, input_data=None, depth: int = 2, direction: str = "LR",
              hide_inner_tensors: bool = True, **options) -> str:
    """Graphviz source of `model` traced on one input (`input_size` or `input_data`)."""
    from torchview import draw_graph

    drawn = draw_graph(
        model,
        input_size=input_size,
        input_data=input_data,
        depth=depth,
        expand_nested=True,
        hide_inner_tensors=hide_inner_tensors,
        graph_dir=direction,
        device="cpu",
        save_graph=False,
        **options,
    )
    return drawn.visual_graph.source
