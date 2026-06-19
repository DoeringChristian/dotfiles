---
name: mitsuba-drjit-guide
description: Explain how Dr.Jit and Mitsuba 3 work and their particularities — Dr.Jit is a just-in-time array-programming framework that traces Python code, records a computation graph, and compiles/executes it on LLVM (CPU), CUDA (GPU), or Metal. Use when writing, reading, debugging, or reasoning about Dr.Jit (drjit) or Mitsuba 3 code; when a dr.eval / kernel launch fails mysteriously; when deciding between for-loops and vectorized ops; or when the user asks how tracing, lazy evaluation, variants, autodiff, or symbolic control flow work.
---

# Dr.Jit & Mitsuba 3 — how they work and their particularities

**Dr.Jit** is a just-in-time (JIT) **array-programming** framework. **Mitsuba 3** is
a research renderer built entirely on top of Dr.Jit. Understanding Dr.Jit is the key
to understanding both. This guide explains the mental model and the non-obvious
behaviors that trip people up. For *running* code see the `mitsuba-reproducer` and
`mitsuba-testing` skills.

## The core mental model: trace → record → compile → execute

Dr.Jit does **not** run your array operations when the Python line executes. Instead:

1. **Trace / record.** Each Dr.Jit operation (`a + b`, `dr.gather`, `dr.sqrt`, …)
   appends a node to an in-memory computation graph and returns a *symbolic*
   variable — a handle to a not-yet-computed result, not actual numbers. Python is
   just the metaprogramming language that *builds* the graph.
2. **Schedule.** `dr.schedule(x)` marks variables to be part of the next kernel.
3. **Compile + execute (evaluate).** `dr.eval(x)` (or any implicit trigger, below)
   takes the scheduled graph, fuses it into a single **megakernel**, JIT-compiles it
   for the active backend, launches it, and writes back concrete results.

This fusion is why Dr.Jit is fast: thousands of operations collapse into one kernel
with no intermediate memory traffic. It is also the source of every particularity
below.

### Backends and variants

The same Python code runs on different backends, selected by the **type** you use:

- `dr.scalar.*` — plain CPU scalars (no JIT; for reference/debugging).
- `dr.llvm.*` — JIT-compiled vectorized **CPU** (via LLVM, loaded dynamically).
- `dr.cuda.*` — JIT-compiled **GPU** (NVIDIA, optionally OptiX for ray tracing).
- `dr.metal.*` — Apple GPU backend (newer; availability depends on the build).
- `dr.auto.*` — picks CUDA if a GPU is present, else LLVM.

Add `.ad` for an **autodiff-enabled** type: `dr.llvm.ad.Float`, `dr.cuda.ad.Array3f`.
Common type names: `Float`/`Float32`, `Float16`, `UInt32`, `Bool`, `Array2f`,
`Array3f`, `TensorXf`, `Texture2f`, `Matrix4f`.

**Mitsuba** wraps this in *variants* you set once with `mi.set_variant("llvm_ad_rgb")`:
`{scalar,llvm,cuda}_{ad}_{rgb,spectral,…}`. The `_ad_` variants carry gradients; the
color space (`rgb`/`spectral`/`mono`) fixes how spectra are represented. A variant
must be set before most `import mitsuba as mi; mi.<...>` usage.

## Particularity 1 — Lazy evaluation & implicit evaluation points

A variable holds a *recipe*, not a value, until something forces evaluation. Things
that **trigger evaluation** (and thus a compile+launch):

- Explicit: `dr.eval(x)`, `dr.schedule(...)` then `dr.eval()`, `x.numpy()`,
  `print(x)` / f-string formatting, `dr.sync_thread()`.
- **Side effects**: `dr.scatter(...)` / `scatter_reduce` into a buffer.
- **Reading on the host**: indexing a single element, `len()` on some shapes,
  converting to NumPy/PyTorch.
- **Control flow that branches on array contents** (unless captured symbolically —
  see Particularity 3).

Two consequences:

- `dr.width(x)` (number of lanes) is known from the graph **without** evaluating;
  the concrete *values* are not. Print sizes to debug, but know that printing values
  forces a kernel.
- Evaluating inside a hot Python loop **breaks fusion** — each `dr.eval`/`print`
  cuts the megakernel, so the program runs many tiny kernels instead of one. Keep
  evaluation out of inner loops.

## Particularity 2 — Deferred, "wrong-place" errors (most important!)

Because operations are recorded and only run later, **the line that raises is often
not the line at fault.** A failure surfaced at a `dr.eval()`, at a `print`, at the
end of an iteration, or at kernel-launch time may have been *caused by an operation
traced much earlier*. Classic symptoms:

- `RuntimeError: … operands have incompatible sizes! (sizes: 2, 3)` raised at a
  subtraction, but the real bug is an earlier op that produced the wrong width.
- A crash "inside `dr.eval`" whose stack trace points at Dr.Jit internals, not your
  code.

How to localize the true cause:

- **Evaluate eagerly to bisect.** Insert `dr.eval(x)` after suspect steps so the
  error moves to the offending operation. `dr.set_flag(dr.JitFlag.LaunchBlocking, True)`
  makes launches synchronous so errors surface at the right call.
- **Turn on debug mode**: `dr.set_flag(dr.JitFlag.Debug, True)` adds source line info,
  bounds checks on gather/scatter, and NaN/inf checks.
- **Raise log verbosity**: `dr.set_log_level(dr.LogLevel.Debug)` (or `Trace`,
  `InfoSym`) to watch tracing, kernel compilation, and cache hits.
- **Inspect the graph / kernels**: `dr.graphviz(x)` renders the computation graph;
  `dr.whos()` lists live variables and their widths; with
  `dr.set_flag(dr.JitFlag.KernelHistory, True)`, `dr.kernel_history()` reports what
  was compiled and launched; `dr.set_flag(dr.JitFlag.PrintIR, True)` dumps the IR.

## Particularity 3 — Array programming: don't loop over elements

Like NumPy/PyTorch, a single `dr.llvm.Float` represents **many values at once** (one
per SIMD lane / GPU thread). **Never iterate element-by-element in Python** — it
either fails or serializes a vectorized program into thousands of scalar ops.

```python
# BAD: Python loop over lanes
for i in range(dr.width(x)):
    y[i] = x[i] * 2          # forces host reads, destroys vectorization

# GOOD: one vectorized op over all lanes
y = x * 2
```

Replace loop idioms with vectorized primitives:

- **Indexing/permutation** → `dr.gather(Type, source, index)` /
  `dr.scatter(target, value, index)` / `dr.scatter_reduce(op, …)`.
- **Conditionals per lane** → masks + `dr.select(mask, a, b)` (compute both, pick).
- **Reductions** → `dr.sum`, `dr.prod`, `dr.min`, `dr.max`, `dr.dot`, `dr.all`,
  `dr.any` (these reduce *across* lanes and are evaluation points).
- **Index ranges** → `dr.arange`, `dr.linspace`, `dr.meshgrid`.

A Python `for` loop is only fine when it iterates over a *fixed, small, compile-time*
set (e.g. 3 color channels, N network layers) — i.e. it unrolls into the trace. It
is **not** fine for iterating over data/lanes or for data-dependent counts.

### Data-dependent control flow → make it symbolic

When a loop count or branch genuinely depends on array values, don't drop to Python.
Use Dr.Jit's recorded control flow so it stays in one kernel:

- `@dr.syntax` lets you write natural `if`/`while` over Dr.Jit variables; the
  decorator rewrites them into recorded form.
- Or call `dr.while_loop(...)`, `dr.if_stmt(...)`, `dr.dispatch(...)` directly.
- **Symbolic vs. evaluated**: with `dr.JitFlag.SymbolicLoops`/`SymbolicCalls` (default
  on), the loop/call body is recorded **once** and runs for all lanes — memory-cheap
  but the body must be uniform and not read lane values on the host. Evaluated mode
  materializes state each iteration (more memory, easier to debug). Knowing which
  mode you're in explains many "why can't I print inside this loop" issues.

## Particularity 4 — Sizes, broadcasting, and in-place updates

- **Width broadcasting**: a width-1 variable broadcasts against any width; two
  variables with different widths >1 are an **error** (the size-mismatch above).
  Keep deliberate scalars at width 1.
- **In-place vs. reassign**: `x[:] = expr` writes into the existing variable
  (preserves identity, needed for optimizer params and `dr.scatter` targets), while
  `x = expr` rebinds the Python name to a new node. Mixing these up is a frequent bug.
- `dr.make_opaque(x)` turns a literal into an opaque variable so it isn't baked into
  the kernel as a constant (avoids recompiling when only its value changes).

## Particularity 5 — Frozen functions (`dr.freeze`)

`dr.freeze` records a function's kernels **once** and replays them on later calls,
skipping re-tracing for speed. The replay assumes the *structure* (and often the
*sizes*) seen on the first call. Calling a frozen function with a different input
width or layout can silently return wrong-sized results or mismatch later — this is
exactly the `mi498` reproducer (frozen func returns width 2 when 3 is expected). When
debugging a frozen function, first reproduce **without** `dr.freeze` to separate a
tracing bug from a freezing bug.

## Particularity 6 — Autodiff is a separate layer

Automatic differentiation (the `.ad` types) is layered *on top of* the JIT graph:

- `dr.enable_grad(x)` / `dr.grad_enabled(x)`; read with `dr.grad(x)`.
- Reverse mode: `dr.backward(loss)`; forward mode: `dr.forward(x)`.
- The AD graph and the JIT graph are distinct; `dr.detach(x)` drops gradient
  tracking while keeping the value. Mixed-precision training uses
  `drjit.opt.GradScaler` (+ `Adam`/`AdamW`/`Muon` from `drjit.opt`).

In Mitsuba, differentiable rendering means the *whole renderer* is one differentiable
megakernel — gradients flow from image loss back to scene parameters
(`mi.traverse(scene)` exposes them).

## Performance & debugging cheatsheet

- Keep `dr.eval`/`print`/`.numpy()` **out of inner loops** to preserve megakernel fusion.
- Reuse compiled kernels: identical traces hit the kernel cache (watch with
  `LogLevel.Info`). Opaque-ify changing constants (`dr.make_opaque`) instead of
  baking them in.
- Bisect deferred errors with `dr.eval` + `JitFlag.LaunchBlocking`; add line info and
  bounds/NaN checks with `JitFlag.Debug`.
- Inspect with `dr.whos()`, `dr.graphviz()`, `dr.kernel_history()` (needs
  `JitFlag.KernelHistory`).
- LLVM/CPU backend loads LLVM dynamically — if `dr.llvm.*` fails to initialize, check
  `DRJIT_LIBLLVM_PATH` (set by this project's environment).

## One-paragraph summary

Dr.Jit traces Python into a fused, JIT-compiled megakernel that runs on CPU (LLVM),
GPU (CUDA), or Metal; variables are lazy graph nodes, not values, so evaluation is
deferred until `dr.eval` or an implicit trigger — which means **errors often point at
the evaluation site, not the operation that caused them**. Write vectorized,
array-programming code (no Python loops over lanes; use gather/scatter/select and
`@dr.syntax` for data-dependent control flow). Mitsuba 3 is this model applied to
rendering, with `_ad_` variants making the entire renderer differentiable.
