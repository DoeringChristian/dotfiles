---
name: mitsuba-drjit
description: What Mitsuba 3 (the differentiable physically-based renderer) and Dr.Jit (its tracing JIT compiler / autodiff array library) are and how to use them correctly. Covers variants, scene XML/dicts, mi.render, inverse rendering with mi.traverse and optimizers, writing Python or C++ integrators/BSDFs, Dr.Jit's lazy evaluation, symbolic loops (@dr.syntax, dr.while_loop), autodiff, dr.freeze, debugging kernels, and building/testing mitsuba3, drjit and drjit-core from source (including the pixi debug workspace and its standalone build tasks). Use this skill whenever code imports `mitsuba` or `drjit` (`mi.`, `dr.`), the user mentions Mitsuba, Dr.Jit, drjit-core, differentiable/inverse rendering, path replay backprop (prb), rendering variants like llvm_ad_rgb/cuda_ad_rgb/metal_ad_rgb, or asks to build, test, debug or benchmark anything in a mitsuba3 checkout — even if they don't ask for an explanation. Much of the API changed recently (Dr.Jit 1.x, Mitsuba 3.6–3.10), so consult this before writing code from memory.
---

# Mitsuba 3 and Dr.Jit

**Mitsuba 3** is a research-oriented, *retargetable* physically based renderer (EPFL RGL) for
forward and **inverse** (differentiable) rendering. One C++/Python code base is compiled into
several **variants** (backend × color representation), e.g. `scalar_rgb`, `llvm_ad_rgb`,
`cuda_ad_rgb`, `metal_ad_rgb`, `*_spectral`, `*_polarized`.

**Dr.Jit** (`ext/drjit`) is the engine underneath: a **tracing JIT compiler** for array programs,
with automatic differentiation. Operations on Dr.Jit arrays are *recorded*, fused into kernels,
compiled for CPU (LLVM) or GPU (CUDA/OptiX, Metal), and launched lazily. **Dr.Jit-Core**
(`ext/drjit/ext/drjit-core`) is the C-level JIT itself (IR graph, codegen, kernel cache).

```
Mitsuba 3   plugins, scenes, integrators; templated on <Float, Spectrum> = the variant
  └ drjit       typed arrays (Array3f, Matrix4f, TensorXf), AD graph, symbolic loops/calls, nanobind bindings
      └ drjit-core  JIT: SSA IR nodes (r123), kernel fusion + hash cache (~/.drjit), LLVM/CUDA/OptiX/Metal
```

The API moved a lot recently (Dr.Jit 1.0 → 1.6, Mitsuba 3.6 → 3.10). Stale idioms from blogs,
old tutorials or training data (`enoki`, `dr.Loop`, `mi.Loop`, `vertex_positions`, `Transform4f * p`,
ray differentials) **will fail**. When unsure, check the source tree, not memory (see "Finding the
truth" below).

## Reference files — read the one that matches the task

| file | read it when |
|---|---|
| `references/drjit.md` | writing or debugging any Dr.Jit code: types, evaluation, loops/conds, AD, freeze, textures, interop, NN, error table, stale-API list |
| `references/mitsuba-usage.md` | rendering, scene XML/dicts, the plugin catalog, inverse rendering, Python integrators/BSDFs, 3.10 breaking changes |
| `references/mitsuba-internals.md` | C++ work: repo layout, variant templates, `MI_*` macros, plugin skeleton, traversal, nanobind bindings, debugging |
| `references/build-and-test.md` | building mitsuba3 / standalone drjit / standalone drjit-core (pixi tasks or plain CMake), variant config, PYTHONPATH, pytest, build-failure triage |

Each file starts with a table of contents. Read only the sections you need.

## First: establish which Mitsuba you are talking to

Before writing code, spend ten seconds on these. Each one has caused hours of confusion.

```bash
python -c "import mitsuba as mi, drjit as dr; print(mi.__version__, mi.__file__); print(dr.__version__, dr.__file__); print(mi.variants())"
```
- **Source build or pip?** A source build is imported via `<build>/python` (`source <build>/setpath.sh`);
  it ships its own matching `drjit`. Never mix it with pip `drjit`/`mitsuba`.
- **Which variants exist?** macOS builds have **no `cuda_*`**. The GPU variant there is `metal_ad_rgb`.
  Pick robustly: `mi.set_variant('cuda_ad_rgb', 'metal_ad_rgb', 'llvm_ad_rgb')` (the first one available wins).
- **Debug or Release build?** The pixi debug workspace builds Debug: correct for debugging (Trace
  logs, asserts, lldb) and far too slow for timings.
- **In a pixi workspace** (`pixi.toml` next to `mitsuba3/`), build and test through `pixi run …` tasks.
  See `references/build-and-test.md`.

## The Dr.Jit mental model (the part everything else depends on)

1. **Python is a metaprogram.** `x = a * b + 1` on Dr.Jit arrays records IR; nothing runs. Plain
   Python `for`/`if`/ints run once at trace time and only shape the kernel (`for i in range(1000)`
   *unrolls*).
2. **Evaluation is forced** by `dr.eval()`, `print(x)`, `x[i]`/`float(x)`, `.numpy()`/`.torch()`,
   horizontal reductions (`dr.sum`, `dr.any`, …) and reading a scatter target. Each forced eval may
   launch a kernel and sync. Keep forced evals out of hot loops.
3. **Arrays are wide.** `mi.Float` holds one value per lane (pixel sample, ray, …). `Array3f` has
   shape `(3, N)`. A Python `if mask:` on a multi-lane array raises. Use `dr.select`, masks, or
   `@dr.syntax` (which turns `while`/`if` on Dr.Jit conditions into `dr.while_loop`/`dr.if_stmt`).
4. **Symbolic loops and conditions** trace the body once into one megakernel. Inside them you
   cannot read values: use `dr.print(...)`, not `print`, and do no cross-lane `dr.sum`. Loop counters must
   be Dr.Jit types (`UInt32(0)`), and state must keep its type. To debug, switch to evaluated mode:
   `with dr.scoped_set_flag(dr.JitFlag.SymbolicAll, False): ...`.
5. **Literals get baked into the kernel.** A value that changes per iteration (`Float(i)`, a Python
   scalar) recompiles every iteration. Use `dr.opaque(mi.Float, i)` and `dr.eval(state, rng)` each
   iteration. `dr.kernel_history()` or `dr.set_log_level(dr.LogLevel.Info)` show cache misses.
6. **AD** needs `_ad` types or variants: `dr.enable_grad(x)` → compute → `dr.backward(y)` → `x.grad`.
   Gradients land on leaves only (traversal is destructive), `a *= 2` rebinds `a` to an interior
   node, and **reverse mode through a symbolic loop requires `dr.hint(cond, max_iterations=-1 or N)`**.
7. **No reduction needed before `dr.backward`.** `dr.backward(y)` on a *wide* array seeds every
   element's gradient with 1 if none is set, so it is equivalent to backpropagating `dr.sum(y)`.
   The forward and backward passes don't need to be split around a scalar loss. Write
   `loss = dr.square(y - y_ref); dr.backward(loss / dr.width(loss))` for a mean. Reduce only when you
   want the scalar loss value itself (logging), and remember that reading it syncs.

## Mitsuba in 30 lines

```python
import drjit as dr
import mitsuba as mi
mi.set_variant('cuda_ad_rgb', 'metal_ad_rgb', 'llvm_ad_rgb')   # BEFORE touching mi.Float etc.

scene = mi.load_dict(mi.cornell_box())        # or mi.load_file('scene.xml', spp=64), mi.load_dict({...})
img = mi.render(scene, spp=128)               # TensorXf (H, W, C), linear radiance
mi.util.write_bitmap('out.exr', img)          # .png/.jpg → sRGB 8-bit, .exr keeps HDR

# Inverse rendering: optimize one BSDF albedo
ref = mi.TensorXf(img)                        # snapshot of the reference image
scene = mi.load_dict(mi.cornell_box() | {'integrator': {'type': 'prb'}})
params = mi.traverse(scene)                   # SceneParameters; print(params) lists keys
key = 'red.reflectance.value'
params[key] = mi.Color3f(0.1, 0.1, 0.9); params.update()
opt = mi.ad.Adam(lr=0.05)                     # alias of drjit.opt.Adam
opt[key] = params[key]; params.update(opt)
for it in range(50):
    image = mi.render(scene, params, spp=8, seed=it)   # pass params; vary the seed
    loss = dr.mean(dr.square(image - ref))
    dr.backward(loss)
    opt.step()
    opt[key] = dr.clip(opt[key], 0.0, 1.0)
    params.update(opt)                        # nothing changes in the scene without update()
```
Integrator choice for AD:
- `prb` for appearance (BSDFs, textures, emission); `prbvolpath` for volumes.
- `direct_projective` / `prb_projective` when visibility changes (shape, pose, shadows).
- Plain `path` in an `_ad` variant records the whole graph and quickly runs out of memory.

## Idioms and style (write code the way Mitsuba itself does)

- **Fit the concept to the plugin type.** Implement a new method as the Mitsuba abstraction it
  belongs to: a light-transport algorithm as an *integrator*, a material as a *BSDF*, a spatially
  varying input as a *texture*, and likewise for emitters, sensors, media and phase functions.
  Register it and use it from scene dicts or XML. Don't write ad-hoc ray-tracing scripts around
  `mi.render`. This is what makes it composable with `mi.traverse`, AD and the rest of the renderer.
- **Loop structure as in `src/python/python/ad/integrators/prb.py`:** declare the state up front
  with constructors and aligned trailing comments. Keep an `active` mask as the loop condition and
  narrow it inside the body; pass the bound and a label through `dr.hint`:
  ```python
  x      = Float(a)                    # Current iterate
  it     = UInt32(0)                   # Iteration counter
  active = Bool(True)                  # Lanes still iterating

  while dr.hint(active, max_iterations=max_it, label="Newton"):
      x = dr.select(active, 0.5 * (x + a / x), x)
      it[active] += 1
      active &= (it < max_it) & (dr.abs(x * x - a) >= tol)
  ```
  Avoid stuffing compound conditions into the `while` header.
- **Initialize with the type constructor:** `UInt32(0)`, `mi.Float(1)`, `mi.Spectrum(0)`,
  `mi.Bool(active)`. A size-1 value broadcasts to the loop width. Don't use
  `dr.zeros(UInt32, dr.width(a))` for scalar-initialized loop state. Reserve `dr.zeros(T)` for
  struct-like types such as `dr.zeros(mi.SurfaceInteraction3f)`.
- **Comments explain the math or the reason** (`# x0 = max(a, 1) >= sqrt(a): monotone convergence`),
  not the mechanics of the API call.

## Pitfalls that most often produce wrong code

**Dr.Jit**
- `dr.Loop`, `mi.Loop`, `enoki`/`ek.*`, `dr.print_async` are gone. Use `@dr.syntax` + `while`, `dr.while_loop`, and `dr.print`.
- Renamed: `dr.clamp`→`dr.clip`, `dr.sqr`→`dr.square`, `dr.wrap_ad`→`dr.wrap`, and `dr.index(x)` is now `x.index`.
- `dr.sum(flat_array)` returns a size-1 array, not a float. `[0]` unboxes it, and that syncs.
- `dr.minimum`/`maximum`/`clip` propagate NaN. Use `dr.fmin`/`fmax` to sanitize.
- `break`/`continue`/`return` are unsupported inside vectorized loops. Mutating a non-PyTree `self` inside a symbolic `if` silently loses masking: use a dataclass or `DRJIT_STRUCT`.
- Don't pass `mode='auto'` to `dr.print` in Dr.Jit 1.6-dev (a parsing bug raises). Omit `mode`.
- Gather/scatter indices are unchecked. Use `dr.set_flag(dr.JitFlag.Debug, True)` to catch out-of-bounds access.

**Mitsuba**
- Call `mi.set_variant(...)` before using any `mi.*` type, and don't cache `mi.Float` at import time. `mi.Scalar*` types are non-JIT in every variant.
- Use `mi.ScalarTransform4f` in scene dicts and `mi.Transform4f` for differentiable transforms. Apply with `@`, never `*`.
- `params[k] = v` does nothing until `params.update()`.
- `load_dict`/`load_file` default to `optimize=True`, which merges meshes sharing a material, so per-mesh keys vanish from `mi.traverse`. Pass `optimize=False` to keep them.
- Misspelled or extra properties, or a float where an int is expected (`max_depth: 6.0`), are load-time errors.
- 3.10 mesh params are tensors: `shape.positions` (P,3) and `shape.faces` (F,3); `vertex_positions` is gone. Convert with `mi.Point3f(t, flip_axes=True)` and `mi.TensorXf(p, flip_axes=True)`.
- 3.10 `ray_mask` is keyword-only, and it exists only on the *long* overloads: `scene.ray_intersect(ray, ray_flags, coherent, *, ray_mask=..., active=...)` and `scene.ray_test(ray, coherent, *, ray_mask=..., active=...)`. `scene.ray_test(ray, ray_mask=...)` without `coherent` raises "incompatible function arguments", and so does passing `active` positionally after `coherent`. The short forms are `ray_intersect(ray, active)` and `ray_test(ray, active)`.
- `@dr.syntax` reads the function's source, so it fails for code run via `python -c` or `exec`. Put the code in a `.py` file.
- Since 3.9.1 there are no ray differentials: `si.bsdf()` takes no ray, and a Python `SamplingIntegrator.sample(scene, sampler, ray, medium, active)` returns `(Spectrum, Bool)`.
- 8-bit bitmap textures are not differentiable unless they have `'format': 'variant'`. Hide emitters with `visibility: 'secondary'` (`hide_emitters` is deprecated).
- Films may carry postprocess filters (tone mapping in converted Blender scenes). Compare images with `mi.render(..., postprocess=False)`.

**Source builds**
- `.py` files under `src/python/` are **copied** into the build at configure time. After editing, rebuild (`ninja -C build-mitsuba`). After adding a new file, re-run cmake first.
- The pixi workspace may pin `ext/drjit` to a newer commit than Mitsuba expects. Don't reset the submodule. Compile errors in Dr.Jit API names mean skew, not your bug.

## Finding the truth in the source tree

Training data is out of date for this fast-moving API. Before using a function or parameter you are unsure of, check the checkout:
- **Dr.Jit function semantics:** `ext/drjit/src/python/docstr.rst`. Search `.. topic:: while_loop`, `reduce`, `scatter_inc`, `JitFlag_*`.
- **Signatures:** the stubs `<build>/python/drjit/__init__.pyi` and `<build>/python/mitsuba/*.pyi`, or `help(dr.while_loop)` in the right env.
- **Plugin parameters:** the `/**! ... */` docstring at the top of `src/<category>/<plugin>.cpp`, or the Python file in `src/python/python/ad/integrators/`.
- **What changed:** `ext/drjit/docs/changelog.rst`, `docs/release_notes.rst`, `docs/porting_3_6.rst`.
- **Usage examples:** `ext/drjit/tests/test_*.py`, `src/*/tests/test_*.py`, `tutorials/**/*.ipynb`.
- **Workspace notes** (pixi debug workspace only): `../CODE_OVERVIEW.md` (deep Dr.Jit/Mitsuba debugging) and `../STYLE_GUIDE.md` (coding conventions). Read them for C++ work or JIT-level debugging.

When behaviour is in doubt, a five-line script on `llvm_ad_rgb` (or `scalar_rgb` to rule out JIT
effects) beats reasoning about it. Print shapes and widths (`dr.width(x)`, `t.shape`) before the line that fails.

## Answering "explain Mitsuba/Dr.Jit" questions

When someone asks what these tools are or how to start:
1. Lead with the layering and the tracing model above.
2. Give one runnable example matched to their goal: render, optimize, or a custom plugin.
3. Point to the matching tutorial (`tutorials/quickstart`, `tutorials/inverse_rendering/gradient_based_opt.ipynb`, `tutorials/others/custom_plugin.ipynb`).
4. Flag the stale-API traps that apply to them.
