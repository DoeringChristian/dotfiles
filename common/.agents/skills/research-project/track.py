"""Trackable: components that log themselves into a cairn run.

Every component with something worth seeing (a model, a loss, a dataset, a
method, ...) derives from ``Trackable`` and implements

    log(name, run, it=None, **_)

It tracks its own diagnostics under ``name`` and delegates to its parts under
``sub(name, part)``. A component with nothing to show inherits the no-op, so
parents call ``log`` on every part unconditionally. Nothing outside a
component ever calls ``run.track`` on that component's state.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    import cairn


def sub(name: str, part: str) -> str:
    """Join a prefix and a part into a dotted name; an empty prefix is dropped.

    >>> sub("", "model"), sub("model", "encoding")
    ('model', 'model.encoding')
    """
    return f"{name}.{part}" if name else part


class Trackable:
    """Base class for components that log themselves.

    Subclasses override ``log`` to track their own diagnostics (a few scalars,
    a histogram, an image, ...) under ``sub(name, <last segment>)`` and to
    forward to their parts: ``self.part.log(sub(name, "part"), run, it, **kw)``.
    Call ``super().log(...)`` so a base class's parts are still reached.

    Example:
        @register
        class ResNet(Model):
            def log(self, name, run, it=None, **kw):
                run.track(self.render(), name=sub(name, "render"), step=it)
                self.encoding.log(sub(name, "encoding"), run, it, **kw)
                super().log(name, run, it, **kw)
    """

    def log(self, name: str, run: cairn.Run, it: int | None = None, **_: Any) -> None:
        """Track this object's diagnostics under ``name`` and delegate to parts.

        Args:
            name: Prefix this object logs under ("" for the top level). Each
                component only chooses the last segment of its own names.
            run: The ``cairn.Run`` to track into.
            it: Iteration used as ``step=``; ``None`` for one-shot logging.
            **_: Extra context a caller may pass down the tree
                (``subset="val"``, ``final=True``, ...). Ignored unless a
                component declares the keyword explicitly.
        """
        return None
