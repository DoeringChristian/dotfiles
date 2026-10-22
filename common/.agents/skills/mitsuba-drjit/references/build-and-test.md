# Building and testing Mitsuba 3, Dr.Jit and Dr.Jit-Core

Covers: (1) the pixi debug workspace (`mitsuba3-debug/`) with its standalone build tasks,
(2) plain CMake builds, (3) variant configuration, (4) how Python finds a build, (5) tests.

## Contents
1. The three build trees · 2. Pixi workspace tasks · 3. Plain CMake · 4. Variants (`mitsuba.conf`) ·
5. Importing a build from Python · 6. Python sources are copied · 7. Tests · 8. Build-failure triage

---

## 1. The three build trees

There are three independent CMake projects, each with its own build dir under the mitsuba3 checkout:

| build dir | source | what it is for |
|---|---|---|
| `build-mitsuba` | checkout root | the full renderer. **Also compiles its own Dr.Jit from `ext/drjit`** (`libdrjit-core`, `libdrjit-extra`, `python/drjit/`), so Dr.Jit source edits reach Mitsuba through a Mitsuba rebuild |
| `build-drjit` | `ext/drjit` | **standalone Dr.Jit** + its Python test suite (`-DDRJIT_ENABLE_TESTS=ON`). Fastest loop for Dr.Jit-only work and reproducers that don't need Mitsuba |
| `build-drjit-core` | `ext/drjit/ext/drjit-core` | **standalone Dr.Jit-Core** (the C JIT compiler) + its C++ test binaries `tests/test_<name>` (`-DDRJIT_CORE_ENABLE_TESTS=ON`) |

Choose the smallest tree that contains the bug: a pure JIT/codegen bug → `build-drjit-core`; a
Python-level Dr.Jit bug (AD, loops, freeze, bindings) → `build-drjit`; anything touching
`import mitsuba` → `build-mitsuba`.

All three default to `CMAKE_BUILD_TYPE=Debug` in the pixi workspace: `NDEBUG` is off, so Dr.Jit
`Trace` logging and internal asserts work, symbols are present for lldb, and everything is **slow**.
Don't use them for performance numbers; configure a separate `Release` dir for benchmarks.

## 2. Pixi workspace (`mitsuba3-debug/pixi.toml`)

Layout: `mitsuba3-debug/` (workspace root: `pixi.toml`, `.envrc`, `CODE_OVERVIEW.md`,
`STYLE_GUIDE.md`, `debug/` reproducers) contains the `mitsuba3/` checkout. Pixi supplies cmake 3.28, ninja,
ccache, Python 3.11, pytest, numpy, embree, lldb and LLVM 18 (and on Linux gcc/clang/mold/CUDA/nsight).
`direnv` + `.envrc` run `pixi shell-hook`; otherwise `pixi shell` or prefix commands with `pixi run`.
Activation exports `MITSUBA_ROOT=$PIXI_PROJECT_ROOT/mitsuba3`, sources
`mitsuba3/build-mitsuba/setpath.sh`, sets `CMAKE_CXX_COMPILER_LAUNCHER=ccache` and, on macOS,
`DRJIT_LIBLLVM_PATH=$CONDA_PREFIX/lib/libLLVM.dylib` (without this the LLVM backend reports
"Set the DRJIT_LIBLLVM_PATH environment variable").

Read `pixi.toml` or run `pixi task list` for the current list. As of Oct 2026:

| task | what it runs |
|---|---|
| `configure-mitsuba [dir] [flags]` | `cmake -S . -B {dir=build-mitsuba} -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` (+ `cc/c++` on macOS, `gcc/g++` + mold on Linux) + `{flags}` |
| `build-mitsuba` | configure, then `cmake --build build-mitsuba` |
| `test-mitsuba <pytest args>` | build-mitsuba, then `python -m pytest <args>` in `build-mitsuba` with its `python/` on `PYTHONPATH` |
| `debug-mitsuba <pytest args>` | same, under `lldb -- python -m pytest` |
| `build-drjit` | `cmake -S ext/drjit -B build-drjit -G Ninja -DCMAKE_BUILD_TYPE=Debug -DDRJIT_ENABLE_TESTS=ON && cmake --build build-drjit` |
| `test-drjit <pytest args>` / `debug-drjit` | build-drjit, then pytest (or lldb+pytest) in `build-drjit` (tests are copied to `build-drjit/tests/`) |
| `build-drjit-docs` | regenerate Dr.Jit docstrings (`mkdoc` target) |
| `build-drjit-core` | `cmake -S ext/drjit/ext/drjit-core -B build-drjit-core -G Ninja -DCMAKE_BUILD_TYPE=Debug -DDRJIT_CORE_ENABLE_TESTS=ON && cmake --build build-drjit-core` |
| `test-drjit-core <name> [-- args]` | build-drjit-core, then `./test_<name>` in `build-drjit-core/tests`. Binaries: `array`, `basics`, `graphviz`, `half`, `loop`, `mem`, `record`, `reductions`, `vcall`. Flags go after `--`: `-l` LLVM only, `-m` Metal only, `-v` verbose, `-t` compare against reference output (`pixi run test-drjit-core loop -- -l`; without `--`, pixi rejects the flag). There is no single-test selection: each binary runs all of its tests for the chosen backends |
| `log <file> "<cmd>"` | runs the command under `script` (a PTY) so stdout and **stderr** (where Dr.Jit logs go) stay in order |
| Linux only | `build-mitsuba-asan`/`test-mitsuba-asan`, `build-kernels` (CUDA resources → PTX), `ncu-prof`, `nsys-prof "<cmd>" [out]`, `profile` (perf), `lock-gpu "<cmd>"` |

How the tasks behave:
- **test/debug tasks rebuild first**, so a test never runs against a stale binary.
- Build/test tasks run with `cwd` inside `mitsuba3/` (or the build dir). Pass **absolute paths**
  (`"$MITSUBA_ROOT/src/bsdfs/tests/test_diffuse.py"`), or paths relative to that build dir.
  Wrapper tasks (`log`, profilers) run in the directory you invoked pixi from.
- Tasks without declared args append extra words to the command
  (`pixi run test-drjit tests/test_freeze.py -k foo -x`). Tasks with declared args
  (`configure-mitsuba`, `test-drjit-core`, `log`, `nsys-prof`, `lock-gpu`) take them positionally.

Typical loops:
```bash
# Dr.Jit-only reproducer against the standalone build
pixi run build-drjit
PYTHONPATH="$MITSUBA_ROOT/build-drjit:$PYTHONPATH" python debug/<issue>/test.py
pixi run test-drjit tests/test_while_loop_ad.py -k llvm -x -q

# Dr.Jit-Core C++ test
pixi run test-drjit-core loop

# Mitsuba
pixi run build-mitsuba && python debug/<issue>/test.py      # setpath.sh is already active in the env
pixi run test-mitsuba "$MITSUBA_ROOT/src/bsdfs/tests/test_diffuse.py" -k llvm_ad_rgb -q

# Capture a Dr.Jit trace with ordered stdout/stderr
pixi run log trace.txt "python debug/<issue>/test.py"

# Extra configure flags / alternate build dir
pixi run configure-mitsuba build-mitsuba-rel "-DCMAKE_BUILD_TYPE=Release"
```
Reproducers go under `mitsuba3-debug/debug/<issue-or-topic>/test.py` by convention.

**Intentional submodule skew.** The workspace may track an `ext/drjit` commit newer than the one
the mitsuba3 superproject records (`git status` shows ` M ext/drjit`). Do **not** reset or
`git submodule update` it. If `build-mitsuba` then fails at the compile step with errors like
`use of undeclared identifier 'AllocType'`, that is Dr.Jit/Mitsuba API skew, not your change and not
a test failure. `build-drjit` reproducers are unaffected.

## 3. Plain CMake (no pixi)

```bash
cd mitsuba3
git submodule update --init --recursive        # fresh clone only; see the skew note above
cmake -S . -B build -G Ninja                   # in-source builds are rejected
ninja -C build                                 # or: cmake --build build
ninja -C build diffuse                         # one plugin target
ninja -C build mitsuba-copy-python-src         # re-stage edited .py files only
source build/setpath.sh
```
Useful options (top-level `CMakeLists.txt`):
- `MI_ENABLE_PYTHON`
- `MI_ENABLE_EMBREE`: OFF uses Mitsuba's own kd-tree, which `_double` variants need.
- `MI_SANITIZE_ADDRESS` / `MI_SANITIZE_MEMORY`
- `MI_THROW_TRAPS_DEBUGGER`: breaks into the debugger at every `Throw`.
- `MI_PROFILER_ITTNOTIFY` / `MI_PROFILER_NVTX`
- `MI_SPLIT_MODE`: nanobind split mode, which needs the `nanobind-backend` pip package at runtime.
- `MI_NATIVE_FLAGS`

Dr.Jit options: `DRJIT_ENABLE_LLVM/CUDA/METAL`, `DRJIT_ENABLE_TESTS`, `DRJIT_SANITIZE_ASAN/UBSAN`.

Runtime requirements:
- LLVM ≥ 18 loaded at runtime. Set `DRJIT_LIBLLVM_PATH` if it is not found.
- NVIDIA driver ≥ 535 for CUDA/OptiX. OptiX ships with the driver, so no SDK is needed.
- Metal backend on Apple Silicon.

A wheel build uses `pyproject.toml` (scikit-build-core). `pip install mitsuba` gives prebuilt
variants (`scalar_*`, `llvm_ad_*`, `cuda_ad_*`), with `metal_*` on macOS.

## 4. Variants (`<build>/mitsuba.conf`)

- **The source of truth is `<build>/mitsuba.conf`**, key `"enabled": [...]`. It is a JSON file with comments.
- The CMake cache var `MI_DEFAULT_VARIANTS` is **only** used to seed that file when it does not exist yet. It copies from `resources/mitsuba.conf.template`.
  - Default on Apple: `scalar_rgb,scalar_spectral,metal_ad_rgb,llvm_ad_rgb,llvm_ad_spectral`.
  - Default elsewhere: `cuda_ad_rgb` in place of `metal_ad_rgb`.
- Passing `-DMI_DEFAULT_VARIANTS=` to an existing build dir does nothing. Edit `mitsuba.conf` or delete it instead; CMake re-runs on change.
- Fresh-dir one-liner: `cmake -S . -B build-x -G Ninja -DMI_DEFAULT_VARIANTS=scalar_rgb,llvm_ad_rgb`.
- `resources/configure.py` generates `<build>/include/mitsuba/core/config.h` and `<build>/python/mitsuba/config.py`.
- `MI_ENABLE_CUDA/LLVM/METAL` are *derived* from the variant list. They are not options you set.
- Rules:
  - `scalar_rgb` is mandatory, and at least one `_ad` variant is required.
  - Every plugin compiles once per enabled variant, so compile time and memory scale with the variant count. Keep it at 5 or fewer.
- Check what a build has: `python -c "import mitsuba as mi; print(mi.variants())"`, or read `<build>/python/mitsuba/config.py`.
- **macOS builds have no `cuda_*` variants.** Read `metal_ad_rgb` wherever docs say `cuda_ad_rgb`. CUDA/OptiX work needs a Linux NVIDIA machine.

## 5. Importing a build from Python

- `source <build>/setpath.sh` prepends `<build>/python` to `PYTHONPATH` and `<build>` to `PATH` (for the `mitsuba` CLI). In the pixi env this is done at activation.
- Manually: `PYTHONPATH=$MITSUBA_ROOT/build-mitsuba/python python script.py`.
- That path also provides the **matching `drjit`** from the same build. Never mix it with a pip-installed `drjit` or `mitsuba`.
  - Check with `python -c "import drjit, mitsuba; print(drjit.__file__, mitsuba.__file__)"`.
- The standalone Dr.Jit build is importable via `PYTHONPATH=$MITSUBA_ROOT/build-drjit`. Use it only for Dr.Jit-only scripts: a Mitsuba build needs its own drjit.
  - **Pixi activation already puts `build-mitsuba/python` on `PYTHONPATH`**, so `import drjit` gets *Mitsuba's* copy unless `build-drjit` comes first on the path, or you run from inside `build-drjit/` (the `test-drjit` task does, and the cwd wins).
  - Running pytest from `build-drjit/tests/` or elsewhere silently tests the wrong drjit. Confirm with `python -c "import drjit; print(drjit.__file__)"`.
  - `build-drjit` and `build-mitsuba` each compile their own drjit-core, separate from `build-drjit-core`. After a core edit, rebuild every tree you test against.
- A stale or mismatched build shows up as `ImportError: dlopen ... Symbol not found` or "Python version incompatible". Rebuild; don't debug the script.
- `compile_commands.json` at the repo root can symlink to `build-mitsuba/compile_commands.json` for clangd.

## 6. Python sources are COPIED into the build

`src/python/CMakeLists.txt` globs `src/python/python/**/*.py` at **configure** time and copies each one,
read-only, into `<build>/python/mitsuba/...`. So:
- **After editing a `.py` under `src/python/`, rebuild** (`ninja -C build-mitsuba`; it's cheap).
  Otherwise the old copy is imported. Never edit the read-only files under `<build>/python`.
- **A new `.py` file needs CMake re-run** (`cmake build-mitsuba`, or `pixi run configure-mitsuba`)
  before ninja picks it up. AD integrators are also auto-imported only if listed in
  `src/python/python/ad/integrators/__init__.py`.
- Alternative for quick iteration: define and `mi.register_integrator(...)` the class in a
  standalone script, or `importlib` a file by path, which skips the copy step entirely.

## 7. Tests

- **Mitsuba** tests live in `src/<dir>/tests/test_*.py`, plus `src/core/tests`, `src/render/tests` and `src/python_tests`.
  - `src/render/tests` includes `test_renders.py` (Z-tests against `resources/data/tests/scenes`), `test_freeze.py`, `test_ad.py` and `test_dispatch.py`.
  - The build dir has a generated `pytest.ini` whose `testpaths` is the absolute `src/`, so `python -m pytest` in `build-mitsuba` runs everything. That is slow; narrow it down.
  - Commands:
    ```bash
    PYTHONPATH=build-mitsuba/python python -m pytest src/bsdfs/tests/test_diffuse.py -q
    python -m pytest src/render/tests/test_scene.py -k "llvm_ad_rgb and test_name" -x -s
    ```
  - Tests are parametrized per variant (ids like `test_foo[llvm_ad_rgb]`); select with `-k`.
  - Fixtures (`src/conftest.py`):
    - `variant_<name>` (e.g. `variant_scalar_rgb`, `variant_llvm_ad_rgb`) is skipped when that variant isn't compiled.
    - Groups `variants_all`, `variants_all_rgb`, `variants_vec_rgb`, `variants_all_ad_rgb`, `variants_vec_backends_once`, `variants_any_llvm`, `variants_any_cuda`, `variants_any_metal`, …
    - `np_rng`.
    - Variant fixtures call `mi.set_variant` and clean up caches and flags on teardown.
  - Markers and options: `@pytest.mark.slow` (`-m "not slow"`), `--generate_ref`, `--collect-metrics memory,time,launches`.
  - The `ninja pytest` target mentioned in old docs no longer exists.
  - Statistical tests use `mi.chi2.ChiSquareTest` + `BSDFAdapter`/`EmitterAdapter`/…
- **Dr.Jit** tests are in `ext/drjit/tests/test_*.py`. Run them via `pixi run test-drjit …` or pytest inside `build-drjit`.
  - They are parametrized over backends: narrow with `-k llvm` / `-k metal` / `-k cuda`.
  - Fixtures use `@pytest.test_arrays(...)`.
- **Dr.Jit-Core** tests are custom C++ binaries, not pytest: `build-drjit-core/tests/test_<name>`.
- Useful pytest flags: `-x` stops at the first failure, `-s` shows prints, `-q` is quiet, `-k` filters by name or variant.

## 8. Build-failure triage

| symptom | likely cause |
|---|---|
| C++ errors in Dr.Jit API names while building Mitsuba (`undeclared identifier 'AllocType'`, …) | `ext/drjit` deliberately newer than Mitsuba expects (skew). Don't reset the submodule; ask before changing it |
| Edited `.py` has no effect | not rebuilt (copy step), or new file not globbed (re-run cmake), or wrong build on `PYTHONPATH` |
| `-DMI_DEFAULT_VARIANTS` ignored | `mitsuba.conf` already exists in the build dir |
| `cuda_ad_rgb` not available | macOS build (Metal instead) or the variant isn't in `mitsuba.conf` |
| No `Trace` output from Dr.Jit | Release build (`jitc_trace` compiles out under `NDEBUG`) |
| A codegen change "does nothing" | kernel cache: `rm -rf ~/.drjit` (Metal caches in memory only) |
| `ImportError … Symbol not found` | stale build or mixed pip/build drjit, so rebuild and check `__file__` |
