---
name: mitsuba-drjit-debugging
description: Debug Dr.Jit / Mitsuba 3 JIT problems — trace logging, deferred dr.eval failures, relating internal r-variable indices to Python variables, and frozen-function (dr.freeze) slot/traversal errors. Use when a dr.eval or kernel launch fails with an opaque error, when the user mentions a variable index like "r1234" or a frozen-function slot "s12", a "variable not initialized"/"missing variable"/DRJIT_STRUCT traversal error, when capturing dr.LogLevel.Trace output, or when adding debug output inside the Dr.Jit C++ source.
---

# Debugging Dr.Jit & Mitsuba 3

The JIT/lazy nature of Dr.Jit (see the `mitsuba-drjit-guide` skill for the model)
makes debugging unusual: the line that raises is often **not** the line at fault.
Dr.Jit ships internal tooling to bridge that gap. This skill is the concrete
procedure, with references into the actual source in
`mitsuba3/ext/drjit/ext/drjit-core/src/`. For environment setup and `build-drjit`,
see `mitsuba-reproducer`.

> Paths below are relative to `$MITSUBA_ROOT/ext/drjit/ext/drjit-core/src` unless
> noted. The Dr.Jit builds in this project are `CMAKE_BUILD_TYPE=Debug` (so `NDEBUG`
> is **off**) — several diagnostics below only exist in that debug build.

## 1. Trace logging — and capturing it correctly

Raise the log verbosity to watch tracing, kernel compilation, and variable creation:

```python
import drjit as dr
dr.set_log_level(dr.LogLevel.Trace)   # setter. dr.log_level() with no args is the GETTER
```

Levels (most → least verbose): `Trace`, `Debug`, `InfoSym`, `Info`, `Warn`, `Error`,
`Disable` (`log.h`). `Trace` is only emitted by debug builds (the `jitc_trace` macro
compiles to a no-op under `NDEBUG`, `log.h:25-28`).

**Capture both streams with `script`.** Dr.Jit's log goes to **stderr** from C++
(`log.cpp:44,63` — `vfprintf(stderr, …)`), which is a different stream from Python's
stdout and is easy to lose or mis-interleave with naive `>` redirection. Use a PTY
capture tool. This project provides `bin/log` for exactly this:

```bash
# bin/log is:  script -c"<command>" <outfile>
log trace.txt "python debug/mi498/test.py"   # captures stdout+stderr in order
```

In the trace, **Dr.Jit variables are printed as `r<N>`** (e.g. `r1234`) — this `r`
index is the universal handle used in every log/error message
(`call.cpp`, `record_ts.cpp`, …).

## 2. Deferred failures: the error is often upstream

A failure surfaced at `dr.eval()` / a kernel launch / a `print` was frequently
**caused by an operation recorded earlier**. First, narrow *where* it really is:

- `dr.set_flag(dr.JitFlag.LaunchBlocking, True)` — synchronous launches, so the error
  surfaces at the right call.
- `dr.set_flag(dr.JitFlag.Debug, True)` — attaches source location to each variable
  (`var.cpp:806-807`, via `source_location_buf`) and adds gather/scatter bounds and
  NaN checks. Trace labels then show where a variable was created.
- Sprinkle `dr.eval(...)` to bisect: move the failure to the offending op.

Once you have a culprit **variable index `r<N>`**, use §3 to map it to a Python (or
C++) source location.

## 3. Relating an `r<N>` index back to the variable that created it

The index `r<N>` is meaningless across runs unless you make allocation deterministic
first. The procedure:

### 3a. Make indices reproducible

- **Dr.Jit**: `dr.set_flag(dr.JitFlag.ReuseIndices, False)`. With reuse on, freed
  slots are recycled from a free list; with it off, `jitc_var_new` always takes a
  fresh `index = state.variables.size()` (`var.cpp:747-759`), so indices are stable
  and monotonic across identical runs.
- **Mitsuba**: load scenes sequentially — `mi.load_dict(scene_dict, parallel=False)`
  (`parallel` defaults to `True`, `src/python/stubs.pat:48`). Parallel loading
  creates variables in nondeterministic order.
- **Re-run and confirm the same `r<N>` appears** before trusting it. If it moves
  between runs, allocation isn't yet deterministic (something else is still parallel
  / order-dependent).

### 3b. Trap the allocation of that exact index

`jitc_var_new` (`var.cpp:693`) is where every variable slot is created. Make it stop
when the target index is allocated, then read the backtrace.

Cleanest (no recompile) — conditional breakpoint under gdb via `debug-drjit`:

```bash
debug-drjit "$MITSUBA_ROOT/ext/drjit/tests/test_foo.py" -k case
# in gdb:
(gdb) break jitc_var_new
(gdb) condition <bpnum> index == 1234
(gdb) run
(gdb) bt            # Python + C++ frames → where r1234 is born
```

Or, as the user-described variant, edit `jitc_var_new` to fail at the index, then
`build-drjit` and run. **Use the existing logging/abort infrastructure**, not raw
`printf`/`std::cout`, so output is filtered by log level and goes to the right
stream:

```cpp
// just after `index` is assigned (~var.cpp:759), using drjit-core's own API:
if (index == 1234)
    jitc_fail("trap: created target variable r%u", index);   // aborts → backtrace
// or, non-fatal, to log every creation while hunting:
jitc_log(Debug, "jitc_var_new: created r%u (kind=%s)", index, ...);
```

Logging API (`log.h`): `jitc_log(LogLevel, fmt, …)`, the debug-only `jitc_trace(…)`
macro, `jitc_raise(fmt, …)` (throws, recoverable), `jitc_fail(fmt, …)` (noexcept,
aborts), and `jitc_assert(cond, fmt, …)`. These respect `dr.set_log_level` and use
the `r%u` convention — always prefer them over ad-hoc prints when instrumenting the
C++.

The backtrace from the trap names the C++ creation site and (through the Python
frames) the Python line responsible — that usually pins down which variable it is.

## 4. Frozen functions (`dr.freeze`) — slots `s<N>` and traversal errors

Frozen functions are harder because they don't track Dr.Jit `r` indices directly:
they identify variables by their **allocation memory address (data pointer)**. The
map is `PtrToSlot = robin_map<const void *, uint32_t>` (`record_ts.h`), populated by
`add_variable` / looked up by `get_variable` (`record_ts.cpp:2496`). Each tracked
variable gets a separate **slot index printed as `s<N>`**, distinct from `r<N>`.

### Common frozen-function errors (all in `record_ts.cpp`)

- **Missing during traversal / used-but-not-an-input** (`record_ts.cpp:2542` debug /
  `:2550` release):
  > `record(): Variable [r<N> at] slot s<M> was read by operation o<K>, but it had
  > not yet been initialized! … for example if it was not specified as a member in a
  > DRJIT_STRUCT but used in the frozen function.`
  Cause: a variable the recorded kernel reads was not declared as an input (e.g.
  missing from the `DRJIT_STRUCT` / not passed in), so the freeze machinery never
  saw it get allocated.
- `replay(): Kernel input variable s<N> not allocated!` (`record_ts.cpp:941`)
- `Failed to find the slot corresponding to the variable with data at <ptr>!`
  (`record_ts.cpp:2500`)

### Relating the failing slot `s<N>` to a Dr.Jit `r<N>`

Two ways (use either):

1. **Debug build** (this project's default). When `NDEBUG` is off, the traversal
   error already prints the `r<N>`: the code looks up the variable's data pointer in
   `state.ptr_to_variable` and includes the index in the message
   (`record_ts.cpp:2538-2548`). So a debug build directly hands you the `r`
   variable — then apply §3 to find where it was created.
2. **Trace the memory address upward.** Take the data pointer `<ptr>` (`%p`) from the
   failure and search **backward** through the `LogLevel.Trace` capture for the
   earlier allocation/operation that produced that address. Because `ptr_to_slot` and
   `ptr_to_variable` are keyed by the allocation pointer, the same `<ptr>` ties the
   slot to the `r<N>` that owns that buffer.

Tip: reproduce the bug **without** `dr.freeze` first (run the underlying function
directly). If it only fails when frozen, it's a freezing/traversal issue (missing
input, changing sizes — cf. the `mi498` reproducer); if it fails either way, it's an
ordinary tracing bug and §3 applies.

## 5. General practice

Debugging Dr.Jit is mostly **tracing a variable or failure back through the stack to
its origin**: where was this variable created, where did this pointer come from, what
recorded op first touched it. The loop is: make indices reproducible (§3a) →
raise/capture the trace (§1) → identify the `r<N>`/`s<N>`/`<ptr>` from the error →
trap its creation (§3b) or follow the address upward (§4) → read the backtrace.

### Quick reference

| Need | Action |
|---|---|
| Verbose trace | `dr.set_log_level(dr.LogLevel.Trace)`; capture with `log out.txt "python …"` |
| Errors at the right call | `dr.set_flag(dr.JitFlag.LaunchBlocking, True)` |
| Source locations on vars | `dr.set_flag(dr.JitFlag.Debug, True)` |
| Reproducible indices | `dr.set_flag(dr.JitFlag.ReuseIndices, False)` + `mi.load_dict(..., parallel=False)` |
| Find where `r<N>` is made | gdb `break jitc_var_new` / `condition … index==N`, or `jitc_fail` trap in `var.cpp:693`, then `bt` |
| Instrument C++ | `jitc_log(Debug, …)` / `jitc_trace(…)` / `jitc_fail(…)` — never raw `printf` |
| Frozen slot `s<N>` → `r<N>` | debug-build error already prints `r<N>` (`record_ts.cpp:2538`), or trace the `<ptr>` upward |
