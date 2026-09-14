"""Helpers for components that log themselves into a cairn run.

A component that has something worth seeing (a model, a loss, a dataset, a
method, ...) *may* define

    log(name, run, it=None, **_)

It tracks its own diagnostics under ``name`` and delegates to its parts with
``log_part(part, sub(name, "part"), run, it, **kw)``. There is no base class
and nothing to inherit: ``log`` is a convention, not an interface. A component
with nothing to show simply does not define it, and ``log_part`` skips it, so
parents delegate unconditionally without ``hasattr`` checks of their own. An
unrelated ``log`` -- a manifold's logarithm map, say -- is skipped too: the
first parameter has to be ``name``.

Nothing outside a component calls ``run.track`` on that component's state.
"""

from __future__ import annotations

import inspect
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    import cairn


def sub(name: str, part: str) -> str:
    """Join a prefix and a part into a dotted name; an empty prefix is dropped.

    >>> sub("", "model"), sub("model", "encoding")
    ('model', 'model.encoding')
    """
    return f"{name}.{part}" if name else part


def log_part(
    part: Any, name: str, run: cairn.Run, it: int | None = None, **kw: Any
) -> None:
    """Let ``part`` log itself under ``name``, if it wants to.

    Calls ``part.log(name, run, it, **kw)`` when ``part`` defines ``log``, and
    does nothing otherwise -- including for ``None`` and for plain values such
    as floats, arrays or dicts. Parents therefore delegate to every member they
    own without caring which ones have diagnostics.

    Args:
        part: The owned object to delegate to. Anything at all.
        name: The prefix ``part`` should log under, usually ``sub(name, ...)``.
        run: The ``cairn.Run`` to track into.
        it: Iteration used as ``step=``; ``None`` for one-shot logging.
        **kw: Extra context passed down the tree (``final=True``, ...).

    Example:
        class GradientFit(Method):
            def log(self, name, run, it=None, **kw):
                run.track(self.lr, name=sub(name, "lr"), step=it)
                log_part(self.model, sub(name, "model"), run, it, **kw)
                log_part(self.loss, sub(name, "loss"), run, it, **kw)
    """
    fn = getattr(part, "log", None)
    if _is_diagnostics_log(fn):
        fn(name, run, it, **kw)


def _is_diagnostics_log(fn: Any) -> bool:
    """True when ``fn`` is a diagnostics ``log``, by its first parameter.

    ``log`` is a common name for other things -- a manifold's logarithm map
    (the inverse of ``exp``) is the usual clash in geometry code, and calling
    that with a run would be a confusing bug. Requiring the first parameter to
    be called ``name`` keeps the convention duck-typed without a base class,
    while leaving an unrelated ``log`` alone.
    """
    if not callable(fn):
        return False
    try:
        params = list(inspect.signature(fn).parameters.values())
    except (TypeError, ValueError):  # some builtins have no introspectable signature
        return False
    return bool(params) and params[0].name == "name"


def log_parts(
    parts: dict[str, Any], name: str, run: cairn.Run, it: int | None = None, **kw: Any
) -> None:
    """``log_part`` for several members at once, keyed by the name each gets.

    Example:
        log_parts({"model": self.model, "loss": self.loss}, name, run, it, **kw)
    """
    for part_name, part in parts.items():
        log_part(part, sub(name, part_name), run, it, **kw)
