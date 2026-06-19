---
name: mitsuba-reproducer
description: Write and run minimal bug reproducers in the "mitsuba3-debug" project (a Mitsuba 3 / Dr.Jit debugging harness — a dir containing bin/build-mitsuba and a mitsuba3/ checkout; its location varies per machine). Use when reproducing, debugging, or creating a minimal repro for a Mitsuba 3 or Dr.Jit (drjit) bug, when adding a script under debug/, or when the user mentions a mitsuba/drjit issue number (e.g. "mi498"), a frozen-function/JIT/AD bug, or "reproduce this in mitsuba".
---

# Mitsuba 3 / Dr.Jit reproducers

The `mitsuba3-debug` project is a debugging harness around Mitsuba 3 and its JIT/AD
backend **Dr.Jit**. Reproducers are minimal standalone Python scripts kept under
`debug/`, run against the **locally-built** Mitsuba/Dr.Jit so you can debug real
bugs in the C++/CUDA/LLVM code.

## Step 0 — Locate the project and activate the environment (required)

The project location varies per machine. It is the directory that contains a `bin/`
folder of helper scripts (`build-mitsuba`, `build-drjit`, …), a `mitsuba3/` checkout,
`pixi.toml`, and `.envrc`. Find the project root (`$PROJ`):

```bash
# If you're already inside the project (or direnv activated it), MITSUBA_ROOT is set:
PROJ="${MITSUBA_ROOT:+$(dirname "$MITSUBA_ROOT")}"
# Otherwise cd to wherever the repo lives, e.g.:
#   PROJ=~/workspace/mitsuba3-debug   # ← adjust to your checkout
# Or search for it:
#   PROJ=$(dirname "$(find ~ -maxdepth 4 -type f -path '*/bin/build-mitsuba' 2>/dev/null | head -1)")
```

Every command below needs the project's toolchain (pixi/conda) on `PATH`, the `bin/`
helpers on `PATH`, and `MITSUBA_ROOT` set. If `direnv` is active in the project the
`.envrc` does this automatically. Otherwise replicate it:

```bash
cd "$PROJ"
eval "$(pixi shell-hook)"          # toolchain: clang-18, cuda, python 3.12, embree…
export PATH="$PROJ/bin:$PATH"       # build-mitsuba, build-drjit, test-*, debug-* …
export MITSUBA_ROOT="$PROJ/mitsuba3"
```

Verify with `which build-drjit` and `python --version` (expect 3.12.x). All paths
below use `$MITSUBA_ROOT`, so they work regardless of where the project lives.

## Where reproducers live

`debug/` is organized by **issue id** or by **person**:

```
debug/
├── mi498/          # one dir per issue (mi### = upstream/internal Mitsuba issue)
│   ├── test.py     # the canonical minimal repro
│   └── adversarial*.py, perf.py   # variants / perf comparisons
├── mi465/
├── arno/black_stripes/test.py     # debug/<person>/<topic>/
└── doeringc/drfunc_grad/...
```

Convention for a **new** reproducer:
- Issue-driven: `debug/mi<NNN>/test.py`. People-driven: `debug/<name>/<topic>/test.py`.
- The main script is usually `test.py`. Add `adversarialN.py`, `perf.py`, etc. for variants.
- Drop a `.gitignore` in the dir for generated outputs (images, `.nsys-rep`, …) — see existing dirs.

## Writing a good reproducer

Keep it **minimal and self-contained** — the smallest program that triggers the bug:

1. Import the relevant backend explicitly (`import drjit as dr`, optionally `import mitsuba as mi`).
2. Pick a concrete variant. Dr.Jit: `dr.llvm.Float`, `dr.cuda.Float`, `dr.llvm.ad.Float`, …
   Mitsuba: `mi.set_variant("llvm_ad_rgb")` (variants: `scalar_rgb scalar_spectral llvm_ad_rgb llvm_ad_spectral`).
3. `print()` the observable that's wrong (sizes, shapes, values) **before** the failing line, so the
   discrepancy is visible even when the script aborts.
4. End with the operation that crashes / asserts, with a short comment naming the expected vs actual.

Real example (`debug/mi498/test.py`) — a Dr.Jit frozen-function size bug:

```python
import drjit as dr

def func(x, y):
    return 0.0 * y

x = dr.llvm.Float(1.5)
frozen = dr.freeze(func)

y0 = dr.llvm.Float([10.0, 20.0])
res0 = frozen(x, y0); ref0 = func(x, y0)
print("res0 size =", dr.width(res0))   # observe the state
print("ref0 size =", dr.width(ref0))

y1 = dr.llvm.Float([10.0, 20.0, 30.0])
res1 = frozen(x, y1); ref1 = func(x, y1)
print("res1 size =", dr.width(res1))   # BUG: frozen returns 2, should be 3
print("ref1 size =", dr.width(ref1))

diff = res1 - ref1   # RuntimeError: operands have incompatible sizes (2 vs 3)
```

## Running a reproducer

**Always (re)build first.** A stale build produces a confusing
`ImportError: dlopen … Symbol not found` / "Python version … incompatible" — that
means the binary is out of date, not that anything is wrong with your script. The
build helpers are incremental and ccache-backed, so rebuilding is cheap.

### Dr.Jit-only reproducer (imports only `drjit`)

Use the standalone Dr.Jit build — this is the common case (e.g. all of `mi498`):

```bash
build-drjit                                            # incremental build
PYTHONPATH="$MITSUBA_ROOT/build-drjit:$PYTHONPATH" \
  python debug/mi498/test.py
```

The `build-drjit/drjit/` package is a complete, self-consistent Dr.Jit. Putting
`build-drjit` on `PYTHONPATH` makes `import drjit` resolve to it.

### Mitsuba reproducer (imports `mitsuba`)

Build Mitsuba and source its `setpath.sh` (this adds **both** `mitsuba` and `drjit`
bindings from `build-mitsuba/python` to `PYTHONPATH`):

```bash
build-mitsuba
source "$MITSUBA_ROOT/build-mitsuba/setpath.sh"
python debug/<dir>/test.py
```

### Under a debugger

To step through the C++/CUDA side, use the `debug-*` helpers (they wrap
`gdb --args python …`) or run gdb yourself:

```bash
build-drjit && gdb --args python debug/<dir>/test.py
```

## Known gotcha: drjit ↔ mitsuba submodule skew

This repo deliberately tests **bleeding-edge Dr.Jit** against Mitsuba, so
`mitsuba3/ext/drjit` is sometimes checked out *ahead* of the commit Mitsuba's
source expects (`git -C mitsuba3 status` shows `M ext/drjit`). When that happens
`build-mitsuba` fails with C++ errors like `use of undeclared identifier 'AllocType'`
— Mitsuba's source uses a Dr.Jit API the newer Dr.Jit renamed/removed.

Implications:
- **Dr.Jit-only reproducers are unaffected** — `build-drjit` builds the standalone
  Dr.Jit and runs fine. Prefer this path for drjit bugs.
- For a Mitsuba reproducer that won't build, the fix is an API question (which Dr.Jit
  commit Mitsuba expects), **not** something to silently "fix" by resetting the
  submodule — that submodule state is usually intentional. Surface the mismatch to
  the user rather than `git checkout`-ing it away.

## Quick checklist

- [ ] Environment active (`which build-drjit` works, `MITSUBA_ROOT` set)
- [ ] Script under `debug/mi<NNN>/` or `debug/<name>/<topic>/`, minimal, prints the bad state
- [ ] Built before running (`build-drjit` or `build-mitsuba`)
- [ ] drjit-only → `PYTHONPATH=$MITSUBA_ROOT/build-drjit`; mitsuba → `source build-mitsuba/setpath.sh`
- [ ] Reproducer aborts/asserts on the documented line with the expected message
