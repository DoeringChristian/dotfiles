---
name: mitsuba-testing
description: Run the Mitsuba 3 and Dr.Jit test suites in the "mitsuba3-debug" project (a debugging harness — a dir containing bin/test-mitsuba and a mitsuba3/ checkout; its location varies per machine) using the test-mitsuba / test-drjit / test-drjit-core helper commands. Use when the user wants to run, debug, or select pytest tests for mitsuba or drjit, mentions test-mitsuba/test-drjit, AddressSanitizer (asan) test runs, or running a specific mitsuba/drjit test under gdb.
---

# Testing Mitsuba 3 & Dr.Jit

The `mitsuba3-debug` project wraps the Mitsuba/Dr.Jit test suites in `bin/` helper
commands. Each helper **builds first, then tests**, so you never run against a stale
binary. The two main entry points are `test-drjit` and `test-mitsuba`.

## Step 0 — Locate the project and activate the environment (required)

The project location varies per machine. It is the directory containing a `bin/`
folder of helpers (`test-mitsuba`, `test-drjit`, …), a `mitsuba3/` checkout,
`pixi.toml`, and `.envrc`. Find the project root (`$PROJ`):

```bash
# If direnv already activated the project, MITSUBA_ROOT is set:
PROJ="${MITSUBA_ROOT:+$(dirname "$MITSUBA_ROOT")}"
# Otherwise cd to your checkout, e.g. PROJ=~/workspace/mitsuba3-debug  (adjust), or search:
#   PROJ=$(dirname "$(find ~ -maxdepth 4 -type f -path '*/bin/test-mitsuba' 2>/dev/null | head -1)")
```

The helpers must be on `PATH` along with the toolchain, and `MITSUBA_ROOT` set. If
`direnv` is active in the project, `.envrc` does this. Otherwise:

```bash
cd "$PROJ"
eval "$(pixi shell-hook)"
export PATH="$PROJ/bin:$PATH"
export MITSUBA_ROOT="$PROJ/mitsuba3"
```

Verify with `which test-drjit test-mitsuba`. All test paths below use
`$MITSUBA_ROOT`, so they work regardless of where the project lives.

## The commands

| Command | What it does |
|---|---|
| `test-drjit <pytest args>` | `build-drjit`, then `cd build-drjit && python -m pytest <args>` |
| `test-mitsuba <pytest args>` | `build-mitsuba`, `source setpath.sh`, then `python -m pytest <args>` |
| `test-drjit-core <name> <args>` | run the compiled C++ test `build-drjit-core/tests/test_<name>` |
| `test-mitsuba-asan <pytest args>` | AddressSanitizer build + `LD_PRELOAD` libasan, then pytest |
| `debug-drjit <pytest args>` | same as test-drjit but under `gdb --args python -m pytest` |
| `debug-mitsuba <pytest args>` | same as test-mitsuba but under gdb |

All arguments after the command are passed straight to `pytest` (or to the C++
test binary for `test-drjit-core`).

## test-drjit

Dr.Jit's tests live in `$MITSUBA_ROOT/ext/drjit/tests/`. `test-drjit` runs pytest
with the working directory set to `build-drjit` (so `import drjit` resolves to the
freshly built package). Pass a **test path** plus any pytest flags:

```bash
# one test file, quiet
test-drjit "$MITSUBA_ROOT/ext/drjit/tests/test_color.py" -q

# a single test by name pattern, stop on first failure, show prints
test-drjit "$MITSUBA_ROOT/ext/drjit/tests/test_freeze.py" -k frozen -x -s

# the whole suite (slow)
test-drjit "$MITSUBA_ROOT/ext/drjit/tests"
```

Dr.Jit tests are parametrized over backends; narrow with `-k llvm` / `-k cuda`
when you only care about one. Use absolute paths (or paths relative to
`build-drjit`) since the command `cd`s into the build dir.

## test-mitsuba

Mitsuba's tests live next to the plugins, e.g. `src/bsdfs/tests/`,
`src/integrators/tests/`, `src/python/python/tests/`. `test-mitsuba` builds
Mitsuba, sources `setpath.sh`, then runs pytest from `build-mitsuba`:

```bash
test-mitsuba "$MITSUBA_ROOT/src/bsdfs/tests/test_diffuse.py" -q
test-mitsuba "$MITSUBA_ROOT/src/render/tests/test_mesh.py" -k area -x
```

Mitsuba variants (selectable in tests / with `-k`):
`scalar_rgb scalar_spectral llvm_ad_rgb llvm_ad_spectral`.

> **Note — build may be broken by design.** This repo often tracks a Dr.Jit commit
> ahead of what Mitsuba's source expects (`git -C mitsuba3 status` → `M ext/drjit`).
> When so, `test-mitsuba` fails at its **build** step with C++ errors such as
> `use of undeclared identifier 'AllocType'`. That's a source/API skew, not a test
> failure — report it; don't reset the submodule to force a build. Dr.Jit tests
> (`test-drjit`) are unaffected and are the right target for Dr.Jit-side work.

## test-drjit-core (C++ unit tests)

Runs a compiled Dr.Jit-Core test binary directly:

```bash
test-drjit-core <name> <binary args>   # runs build-drjit-core/tests/test_<name>
```

Caveat: `test-drjit-core` calls `build-drjit-core`, which depends on a
`configure-drjit-core` command that is **not currently defined** in the repo — so
this path may not work out of the box. Verify/define those helpers before relying
on it, and prefer `test-drjit` for Python-level coverage.

## test-mitsuba-asan (AddressSanitizer)

Linux/GCC-oriented: builds an ASan variant and runs pytest with
`LD_PRELOAD=libasan.so libstdc++.so` and tuned `ASAN_OPTIONS`
(`protect_shadow_gap=0:replace_intrin=0:detect_leaks=0`). Caveat: the script
references a `build-mitsuba-asan` command and `$PROJECT_ROOT` that aren't defined
in the repo as-is — confirm those exist (or use `$MITSUBA_ROOT`) before relying on it.

## Debugging a failing test

Drop into gdb on the exact test:

```bash
debug-drjit  "$MITSUBA_ROOT/ext/drjit/tests/test_freeze.py" -k frozen -s
debug-mitsuba "$MITSUBA_ROOT/src/render/tests/test_mesh.py" -k area -s
```

Then in gdb: `run`, and on a crash use `bt` for the C++ backtrace. Builds are
`CMAKE_BUILD_TYPE=Debug`, so symbols are available.

## Quick reference

- Run drjit tests: `test-drjit <path> [pytest flags]`  (tests in `ext/drjit/tests/`)
- Run mitsuba tests: `test-mitsuba <path> [pytest flags]`  (tests in `src/*/tests/`)
- Common pytest flags: `-k <pattern>`, `-x` (stop on first fail), `-s` (show output), `-q`
- Under gdb: `debug-drjit` / `debug-mitsuba`
- If `test-mitsuba` fails to **build** with `AllocType`-style errors → drjit/mitsuba
  submodule skew; surface it, don't paper over it.
