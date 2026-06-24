---
name: specification-testing
description: When implementing behavior that must match an external system (PyTorch, NumPy, or any spec), test critical branches against the reference system, not your mental model. Use proactively whenever code must be compatible with another framework.
---

# Specification Testing

When implementing behavior that must match an external system, test against the real system — not your understanding of it.

## Instructions

1. **Identify decision points.** Every `if`/`else` in your implementation encodes an assumption about the spec. List them.

2. **Write one test per critical branch.** Run it against the reference system first. Use the actual output as the expected value.

3. **Don't trust ported code.** If carrying logic from an existing branch or codebase, verify it against the reference before reusing.
