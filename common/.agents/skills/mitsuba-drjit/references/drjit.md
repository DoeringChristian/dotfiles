# Dr.Jit reference

Source of truth: `ext/drjit` inside a mitsuba3 checkout (standalone: the `drjit` repo). Paths below
are relative to `ext/drjit/` unless stated otherwise. Docs: `docs/*.rst`; exact per-function semantics:
`src/python/docstr.rst` (search `.. topic:: <name>`); Python-side code: `drjit/*.py`; a built stub
with every signature: `<mitsuba-build>/python/drjit/__init__.pyi`.

Written against Dr.Jit 1.6.0-dev (commit `6f7cbc2e`, Oct 2026). Behaviours marked "verified" were
run on LLVM + Metal on macOS. If the checkout is much newer, re-check against `docs/changelog.rst`.

## Contents
1. What Dr.Jit is · 2. Type system · 3. Evaluation model · 4. Control flow · 5. Autodiff ·
6. Optimizers · 7. Textures · 8. Freezing · 9. Interop · 10. Coop vectors / NN ·
11. Debugging + error table · 12. Stale knowledge · 13. Snippets · 14. Where to read more

---

## 1. What Dr.Jit is

- It is a **tracing JIT** for embarrassingly parallel array programs, with optional AD. Operations on capitalized backend types (`Float`, `UInt32`, `Array3f`, ...) are *recorded* into a graph, not run. When something forces evaluation, Dr.Jit fuses the queued ops into one kernel, compiles it (or fetches it from cache), and launches it **asynchronously** (`docs/what.rst`, `docs/eval.rst`).
- **Metaprogramming model.** Plain Python (`int`, `float`, `if`, `for`) is the *metaprogram*. It runs once on the host and only shapes the generated kernel. Only Dr.Jit types are traced. A Python `for i in range(1000)` therefore **unrolls** into the kernel.
- It is *not* a tensor library. Types encode semantics (vector, matrix, complex, quaternion). Every type is implicitly an array over a trailing **dynamic (vectorized) dimension**, and that dimension is the parallel "thread" axis.
- **Backends** (`docs/types.rst`, `docs/what.rst`):
  - `drjit.scalar`: no tracing. Flat types alias Python `float`/`int`/`bool`. Use it for uniform values.
  - `drjit.llvm` / `drjit.llvm.ad`: CPU. SIMD (AVX/AVX512/NEON) plus the nanothread pool. Needs **LLVM >= 18** at runtime (ORCv2/JITLink).
  - `drjit.cuda` / `drjit.cuda.ad`: NVIDIA, PTX via the CUDA driver (no SDK needed). OptiX handles ray-tracing kernels.
  - `drjit.metal` / `drjit.metal.ad`: Apple Silicon (NEW in 1.4). There is no fp64, so `Float64` is demoted to fp32 with a warning.
  - `drjit.auto` / `drjit.auto.ad`: chooses CUDA or Metal if available, otherwise LLVM. On Apple Silicon `drjit.auto.Float` is `drjit.metal.Float`.
  - `.ad` variants track derivatives. Without `.ad` there is no AD at all. Import integer and bool types from the same `.ad` module too, for consistency.
  - Doc inconsistency: `what.rst` and the drjit-core README say CUDA CC >= 5.0, but the 1.4.0 changelog says **CC >= 7.5 (Turing+) and driver R535+** are now required.
  - `dr.has_backend(dr.JitBackend.CUDA|LLVM|Metal)`. `dr.JitBackend` members: `Invalid, CUDA, LLVM, Metal`.
- **Layering:**
  - `ext/drjit-core` (C API in `include/drjit-core/jit.h`) is the JIT itself. It holds the variable graph, codegen (`llvm_*.cpp`, `cuda_*.cpp`, `metal_*.cpp`), eval/scheduling (`eval.cpp`), symbolic loops/conds/calls (`loop.cpp`, `cond.cpp`, `call.cpp`), the kernel cache, malloc caching, and kernel history (`history.cpp`).
  - `include/drjit/*.h` is the C++ array templates (header-only for scalar/packet use).
  - `src/extra` (libdrjit-extra) is the AD graph (`autodiff.cpp`), differentiable loops (`loop.cpp`), conds, calls, and textures.
  - `src/python/*.cpp` holds the nanobind (v3, split mode) bindings.
  - `drjit/*.py` holds the Python-level functions: `ast.py` (`@dr.syntax`, `dr.hint`), `interop.py` (`dr.wrap`), `opt.py` (optimizers), `nn.py`, `random.py`, `quad.py`, `dda.py`, `hashgrid.py`, and much of `__init__.py` (`freeze`, `rng`, `suspend_grad`, `sort`, `concat`, ...).
- **Kernel cache** (`docs/eval.rst` "Kernel caching"):
  - Kernels are keyed by a hash of the generated IR.
  - A *hit* is in memory. A *soft miss* is loaded from disk. A *hard miss* means a full compile.
  - The on-disk cache is `~/.drjit` (LLVM `.o.lz4` objects, OptiX `optix7cache.db`, Metal `*.metallib.lz4`). CUDA uses the driver cache `~/.nv/ComputeCache`.
  - Env vars: `DRJIT_CACHE_DIR`, `DRJIT_CACHE_MAXSIZE` (default 1G, LRU eviction, `0` means unbounded), `DRJIT_CACHE_VERBOSE`.
  - `dr.flush_kernel_cache()` clears the in-memory cache, which is useful for benchmarking.

## 2. Type system

- **Flat arrays:** `Bool, Int8/UInt8, Int(=Int32), UInt(=UInt32), Int64, UInt64, Float16, Float(=Float32), Float64`.
- **Nested:** `Array{0..4}{b,i,u,i64,u64,f16,f,f64}` (for example `Array3f`, `Array2u`) and `ArrayXf` (dynamic outer size). They expose `.x/.y/.z/.w` and swizzles (`a.xy += a.zx`).
- **Matrices:** `Matrix2f..Matrix4f` (row-major, square, at most 4x4). `*` is matmul, `/ M` multiplies by the inverse, `rcp` inverts, and scalar construction broadcasts to the **identity**. If you want element-wise semantics with the same shape, use `Array44f` (`dr.array_t(T)`).
- `Complex2f/2f64`, `Quaternion4f/4f64`: `*` is the complex or quaternion product, and scalar construction broadcasts to the identity.
- `TensorXf, TensorXf16, TensorXi, TensorXb ...`: a flat array plus `.shape`, accessible as `t.array` and `t.shape`. They support NumPy-like slicing and advanced indexing (lowered to gather/scatter) and broadcasting. Use tensors for storage and interop, not as the main programming model: slicing across threads forces evaluation barriers (`docs/types.rst` "Limitations", `docs/faq.rst`).
- Others: `PCG32`, `Philox4x32`, `Texture{1,2,3}f{,16,64}`, `Texture{1,2,3}f8u`, `Event`, and instance arrays (`FooPtr`) for C++ classes.
- **Shape and width:**
  - `Array3f` has shape `(3, N)`. `dr.width(x)` is the size of the trailing dynamic dimension.
  - `len(x)` is the leading dimension (3 for `Array3f`).
  - Size-1 arrays broadcast to any size. Any other size mismatch raises `operands have incompatible sizes`.
  - Nested arrays may be "ragged" until they are used.
- **Printing transposes nested arrays.** `print(Array3f(...))` shows one 3-vector per row, so the display looks like `(N,3)` while `.shape` is `(3,N)`. Tensors print untransposed. Convert with `TensorXf(x, flip_axes=True)` to get `(N,3)`.
- **Promotion** follows C rules (`Float + UInt32 -> Float`). Mixing scalar Python numbers with arrays is fine. Do not mix types from different backend modules (for example `drjit.cuda.Float + drjit.llvm.Float`): pick one module, typically via `drjit.auto(.ad)`, or alias `mi.Float` etc. in Mitsuba.
- **Creation** (the dtype always comes first):
  - `dr.zeros(T, shape)`, `dr.ones`, `dr.full(T, v, shape)`, `dr.empty(T, n)`
  - `dr.arange(T, n)` or `dr.arange(T, start, stop, step)`
  - `dr.linspace(T, a, b, n, endpoint=True)`
  - `dr.zeros_like(x)`
  - `dr.opaque(T, v, shape)`
  - `dr.meshgrid(...)`
  - `dr.rng(seed).random(T, shape)`, `.normal(...)`, `.integers(...)` (Philox4x32-based Generator, newer API). `PCG32(size, initstate, initseq)` is the lower-level stateful RNG.
- **PyTrees** (`docs/misc.rst`):
  - These are `list`, `tuple`, `dict`, dataclasses, and classes with `DRJIT_STRUCT = {'field': Type, ...}` (the class must be default-constructible).
  - Subclasses of list/dict are *not* traversed. Dr.Jit types cannot be dict keys. Cycles are not allowed.
  - Almost every API traverses PyTrees: `eval`, `enable_grad`, loops/conds state, `switch` args, `gather(dtype=MyDataclass, ...)`, `zeros(MyDataclass, n)`, `freeze` args, and so on.
  - C++ equivalent: `DRJIT_STRUCT(x, y)` (`include/drjit/struct.h`, `docs/cpp.rst`).
- **Variable state:** `x.state` returns a `dr.VarState` value: `Literal, Unevaluated, Evaluated, Dirty, Symbolic, Mixed, Undefined, Invalid`.
  - `x.index` is the JIT variable id and `x.index_ad` is the AD id. These are *attributes*: `dr.index` and `dr.label` do not exist at module level.
  - `x.label = "name"` or `dr.set_label(x=x)` labels a variable.
- **Copy-on-write:** `b = Float(a)` shares storage until it is mutated. Value numbering means identical expressions share an index (`docs/optim.rst`, which covers JIT optimizations, not optimizers).

## 3. Evaluation model (`docs/eval.rst`)

- **Lazy.** Nothing runs until evaluation is forced. These things evaluate:
  1. `print(x)`, `repr`, `str(x)`
  2. Reading an element along the **trailing** dimension (`x[0]`, `float(x[0])`, `bool(mask)`, Python `if x > 0:` on a size-1 array). Indexing *nested* components (`a.x`, `a[0]` on `Array3f`) is traced and does not evaluate.
  3. `dr.gather` from an unevaluated source, which generally evaluates the source first.
  4. Reading an array after a `scatter`/`scatter_reduce` into it. The target becomes `Dirty` and the next use evaluates it to enforce ordering.
  5. Horizontal reductions over the trailing dimension: `dr.sum/prod/min/max/mean/all/any/none/count/dot` with `axis=None` or on flat arrays. These have a `mode=` parameter, covered below.
  6. Conversion to NumPy/Torch/JAX (`x.numpy()`, `x.torch()`, `x.jax()`, `np.array(x)`).
  7. `dr.eval(...)`.
- `dr.eval(*pytrees)` compiles and launches now (asynchronously) and turns its arguments into memory. **It does not evaluate literal constants.** `dr.eval(a, b)` evaluates both in one kernel, which avoids recomputing shared subexpressions. `dr.eval()` with no args flushes everything scheduled.
- `dr.schedule(*pytrees)` marks variables for inclusion in the *next* kernel launch without launching. `dr.eval(x)` is equivalent to `dr.schedule(x); dr.eval()`. Use it to batch several outputs into one kernel.
- `dr.make_opaque(*pytrees)` evaluates **in place, including literals**.
- `dr.opaque(x)` / `dr.opaque(T, value, shape)` returns an opaque copy that always gets its own storage.
- **Literals vs opaque, and recompilation.** A literal (`Float(1.5)`, `dr.full(Float, 2, n)`, a Python scalar in an expression) is baked into the IR. If a value changes every iteration, every iteration produces a new kernel (a cache miss).

  ```python
  for i in range(1000):
      y = f(y, i)                      # BAD: 'i' baked in -> 1000 compiles
      y = f(y, dr.opaque(UInt32, i))   # GOOD: one kernel, value read from memory
      dr.eval(y)
  ```

- **Growing dependency chains.** Stateful objects such as RNG state must be evaluated each iteration too (`dr.eval(y, rng)`). Otherwise every iteration replays the whole history: progressive slowdown and no cache hits.
- **Asynchrony.** `dr.eval` returns immediately. Synchronization happens automatically when data is read. `dr.sync_thread()` forces a wait. `dr.flush_thread()` (newer) pushes queued work to the GPU.
- **Element-wise loops in Python** (`for i in range(len(x)): x[i]`) cost one device-to-host transfer each. Use `dr.any(x < 0)` or `x.numpy()`.
- **Side effects:**
  - `dr.scatter(target, value, index, active=True, mode=ReduceMode.Auto)`
  - `dr.scatter_reduce(op, target, value, index, active=True, mode=...)` with `dr.ReduceOp` = `Identity, Add, Mul, Min, Max, And, Or`. Support depends on backend and dtype, and float atomic adds are non-deterministic.
  - `dr.scatter_add(target, value, index, active)`
  - `dr.scatter_inc(target_u32, index, active)` atomically increments and returns the *old* value (stream compaction). The returned index is "consumed": reusing it in a later kernel raises unless it was evaluated together with its consumers.
  - `dr.scatter_exch`, `dr.scatter_cas`
  - Side effects are traced, ordered, and run at the next eval of the target. Inside loops, conds, and calls they do not need to be declared as state.
- **Gather:** `dr.gather(dtype, source, index, active=True, mode=..., shape=None)`.
  - `dtype=Array3f` on a flat source reads 3 consecutive entries in C order.
  - Power-of-two widths become packet loads (`JitFlag.PacketOps`).
  - Reverse-mode AD of a gather is a `scatter_add`, so contention matters. `ReduceMode` values are `Auto, Direct, Local, NoConflicts, Permute, Expand` (`docs/optim.rst` "Local atomic reduction"; `Expand` replicates the target per core on LLVM). `dr.set_expand_threshold` / `dr.expand_threshold` control when `Expand` is used.
  - **Indices are unchecked.** Out-of-bounds is UB unless `JitFlag.Debug` is on.
- **Reductions** (`src/python/docstr.rst` topic `reduce`):
  - `dr.sum(x, axis=..., mode=None, keepdims=False, where=True)`.
  - For non-tensors the default axis is 0, the outer one. On `Array3f` that gives `x+y+z` (traced, no eval). On a flat `Float` it reduces the trailing dimension.
  - Reducing the trailing dimension **returns a size-1 array, not a Python float**. Index `[0]` to unbox, which syncs.
  - `mode="evaluated"` evaluates and then runs a reduction kernel. `mode="symbolic"` uses atomic scatter-reduce. `mode="simd"` pre-reduces in warps or SIMD groups via `dr.simd_reduce` (**new, latest commits**). `None` picks automatically.
  - `where=` masks (new in 1.6).
  - Also: `block_reduce/block_sum`, `prefix_sum/cumsum/prefix_reduce`, `sort/argsort/median/argmin/argmax`, `var/std`, `dot/norm/squared_norm`.
- **JIT flags:** `dr.set_flag(dr.JitFlag.X, bool)`, `dr.flag(...)`, or (preferred) `with dr.scoped_set_flag(dr.JitFlag.X, val):`. Flags are **thread-local**. Members (verified): `Debug, ReuseIndices, ConstantPropagation, ValueNumbering, FastMath, SymbolicLoops, OptimizeLoops, CompressLoops, SymbolicCalls, OptimizeCalls, PacketOps, ForceOptiX, PrintIR, KernelHistory, LaunchBlocking, ForbidSynchronization, ScatterReduceLocal, SymbolicConditionals, SymbolicScope (read-only), ShaderExecutionReordering, KernelFreezing, FreezingScope (read-only), SymbolicAll, Default`.
  - `FastMath` is on by default. It folds `a*0` to `0` and uses approximate div/sqrt on CUDA.
  - `PrintIR` dumps LLVM IR or PTX.
  - `LaunchBlocking` syncs after every kernel to localize crashes.
  - `ForbidSynchronization` raises wherever the code syncs.

## 4. Control flow (`docs/cflow.rst`; docstrings `while_loop`, `if_stmt`, `switch`, `dispatch` in `src/python/docstr.rst`; `drjit/ast.py`)

- A plain `if mask:` or `while i != 0:` on a multi-element array raises `Bool.__bool__(): implicit conversion to 'bool' requires an array with at most 1 element`.
- **`@dr.syntax`** (in `drjit/ast.py`) rewrites `while` and `if` *whose condition is a Dr.Jit array* into `dr.while_loop` and `dr.if_stmt`. It runs once at definition time. It is not a JIT wrapper like `jax.jit`.

  ```python
  @dr.syntax
  def popcnt(i: UInt32):
      j = UInt32(0)
      while i != 0:          # array condition -> dr.while_loop
          j += i & 1
          i >>= 1
      return j
  ```

- Rules and pitfalls for `@dr.syntax`:
  - It only handles `while` and `if`, never `for`. `for i in range(N)` unrolls. Write `i = UInt32(0); while i < N: ...; i += 1` to get a device loop.
  - `break`, `continue`, and `return` inside a vectorized loop are **not supported**. Use masks or flags in the condition.
  - **Type constancy.** State variables must keep their type and shape across iterations and branches. `x = 0` inside `if x < 0:` where `x` is `Int` fails. Write `x = Int(0)`. Variables assigned in a branch must be initialized before it, and `None` or an empty array as the initial value is illegal. To relax the check for a Python scalar that is not used afterwards, use `dr.hint(cond, strict=False)`.
  - **Python scalars are not tracked in symbolic mode.** `i = 0; while Bool(i < 10): i += 1` **never terminates**. Make counters Dr.Jit arrays.
  - **`self` / non-PyTree objects are not traversed.** Mutating `self.value` inside `if` silently loses the masking. Make the class a dataclass or give it `DRJIT_STRUCT`.
  - Place `@dr.syntax` *closest* to `def`, under other decorators such as `@dr.wrap`. It only transforms the outer function unless `recursive=True`. It cannot be used at the REPL top level. `print_code=True` shows the rewritten code. It warns if it is applied more than 1000 times, so do not decorate inside loops.
  - `dr.hint(cond, mode='scalar'|'symbolic'|'evaluated', max_iterations=N, label='..', include=[..], exclude=[..], strict=True)` annotates the condition inside `@dr.syntax`. `mode='scalar'` skips the transformation for Python-bool loops.
- **Explicit forms:**

  ```python
  i, x = dr.while_loop(state=(i, x), cond=lambda i, x: i < 10,
                       body=lambda i, x: (i + 1, x * x),
                       mode=None, compress=None, max_iterations=None, label=None, strict=True)
  y = dr.if_stmt(args=(a, b), cond=a < b,
                 true_fn=lambda a, b: b - a, false_fn=lambda a, b: a - b)
  ```

  - The `cond` callable must be pure. The body must only modify declared state, except for scatters and gathers, which are auto-discovered as implicit inputs and outputs.
- **Symbolic vs evaluated** (`docs/cflow.rst` "Discussion"):
  - **Symbolic (default)** traces the body once with symbolic variables and emits a real device loop or branch into a megakernel. Values stay in registers, so it is fast. Its limits:
    - You cannot read symbolic values: Python `print`, `x[0]`, `.numpy()`, and torch interop all raise "You performed an operation that tried to evaluate a *symbolic* variable".
    - `OptimizeLoops` may trace the body **twice**, so the body must not have Python side effects that assume a single trace.
    - **Horizontal reductions across lanes (`dr.sum(x)` on a flat array) inside a symbolic loop fail.** `mode=None` fails with `jit_var_schedule(...) not permitted`, and `mode="symbolic"` fails with a "Variable remains dirty" error (verified).
    - Read-after-write on a buffer scattered in the same symbolic region also fails ("dirty"). Use `dr.alloc_local` for per-thread scratch with computed indices (`docs/misc.rst` "Local memory"). `Local[i]` returns a copy, so read, modify, and write back for struct entries.
  - **Evaluated** mode runs the loop from the host. It evaluates the state every iteration and launches one kernel per iteration (cached), and branches run both sides then blend. It is debuggable (`print` works) and allows torch/numpy interop, but costs memory bandwidth. `compress=True` / `JitFlag.CompressLoops` drops inactive lanes.
  - Switching modes: per statement with `dr.hint(..., mode='evaluated')` or `mode=` on the function; globally with `JitFlag.SymbolicLoops`, `SymbolicConditionals`, `SymbolicCalls`, or all three via `SymbolicAll`.
  - You cannot nest evaluated inside symbolic.
- **Indirect calls:**
  - `dr.switch(index: UInt32, targets: list[callable], *args, mode=None, label=None, **kwargs)` calls each target at most once on its subset of lanes. Arguments and returns are PyTrees.
  - A trailing `Bool` positional argument or an `active=` kwarg masks lanes. Masked lanes return 0, and the target sees the mask as all-True.
  - Indices are **unchecked**: out of range is UB, and negatives are illegal. Debug mode adds checks.
  - `dr.dispatch(inst_array, fn, *args)` runs `fn(self_instance, *args)` once per unique instance in a C++ instance array. Use it to merge several virtual calls into one. Calls on `nullptr` instances are masked.
  - C++ uses `DRJIT_CALL_BEGIN(Foo) DRJIT_CALL_METHOD(f) DRJIT_CALL_END()` plus `jit_registry_put` (`docs/cpp.rst`). This is what Mitsuba's `BSDFPtr`/`ShapePtr` use.
- **Masking and selection:**
  - `dr.select(mask, t, f)` evaluates **both** sides. Use `if_stmt` when one side is expensive or has side effects.
  - `a & mask` zeroes the false lanes.
  - Gather and scatter take `active=`.
  - `dr.any/all/none(mask)` give host-side decisions (they sync).
- `dr.reorder_threads(key: UInt32, num_bits<=16, value)`: SER on CUDA/OptiX (`JitFlag.ShaderExecutionReordering`). It is a no-op on LLVM and returns `value` tagged so that the reorder happens when the value is used.
- `@dr.func` (new in 1.3) emits the function as a separate callable in IR instead of inlining it. This reduces compile time when one function is called from many sites. The function must be pure.

## 5. Automatic differentiation (`docs/autodiff.rst`)

- Use `.ad` types. Mark inputs with `dr.enable_grad(x, ...)` (PyTrees are fine). `dr.disable_grad`, `dr.grad_enabled`, `dr.set_grad_enabled`.
- **No reduction is needed before backpropagating.** `dr.backward(y)` on a wide array seeds each element's gradient with 1 if none is set. That equals backpropagating `dr.sum(y)` (verified: identical gradients). Use `dr.backward(loss / dr.width(loss))` for a mean-style loss, and reduce only for logging.
- Forward: `dr.forward(x)` (alias of `forward_from`), then read `y.grad`. Reverse: `dr.backward(y)` (alias of `backward_from`; seeds grad 1), then read `x.grad`.
- Generalized: `dr.forward_to(*outs)` and `dr.backward_to(*ins)` return gradients after you set seeds with `x.grad = ...` or `dr.set_grad`. Low level: `dr.enqueue(mode, ...)` + `dr.traverse(mode)`.
- Gradient accessors: `dr.grad(pytree)` (use this for PyTrees; `.grad` only exists on arrays), `dr.set_grad`, `dr.accum_grad`, `dr.clear_grad`, `dr.replace_grad(a, b)` (value of a, grad of b), `dr.detach(x)`.
- **Traversal is destructive.** Gradients only land on leaves. Interior `b.grad` reads 0 afterwards unless you pass `flags=dr.ADFlag.ClearNone`. `ADFlag` members: `ClearNone, ClearEdges, ClearInput, ClearInterior, ClearVertices, AllowNoGrad, Default`.
- **In-place mutation** (`a *= 2`) rebinds `a` to an interior node. Keep a reference to the original leaf before mutating.
- AD is traced too. `dr.backward` appends derivative kernels, and `dr.eval` of differentiable values inserts an AD checkpoint. There are **no higher-order derivatives** (`docs/faq.rst`).
- Scopes (in `drjit/__init__.py`):
  - `with dr.suspend_grad(*vars, when=True):` stops tracking, for all variables or only the listed ones.
  - `with dr.resume_grad(*vars):` re-enables inside a suspended region.
  - `with dr.isolate_grad():` keeps AD traversals from leaking outside the scope. It is used internally by loops and calls.
- **Custom ops:** subclass `dr.CustomOp` with `eval(self, ...)`, `forward(self)` (`self.grad_in('name')` then `self.set_grad_out(g)`), `backward(self)` (`self.grad_out()` then `self.set_grad_in('name', g)`), and `name(self)`. Call it as `y = dr.custom(MyOp, x, ...)`. Define the class once at module top level.
- **Loops:**
  - Forward-mode AD through `while_loop` needs nothing extra.
  - **Reverse mode requires a `max_iterations` hint** (1.4+, trajectory replay). Without it, `dr.backward` raises `LoopOp::backward(): reverse-mode differentiation of this loop requires a 'max_iterations' hint (either -1 ... or a positive upper bound...)` (verified). The `while_loop` docstring still says the default is `-1`. That is stale: the binding default is `None`, which means it must be given.
  - `max_iterations=-1` is the "sum loop" fast path. Loop state must split into non-diff variables, constant diff inputs, and outputs that accumulate `y += f(x, i)`. It needs one pass and no storage.
  - `max_iterations=N>0` is the general path. It stores the per-lane trajectory (N entries per non-invariant state variable) and replays it in reverse. Exceeding N **silently gives wrong gradients** (Debug mode warns `drjit.Local.write(): out-of-bounds`). It is incompatible with `compress=True`.

  ```python
  @dr.syntax
  def iterated_square(x: Float, n: int):
      y, i = Float(x), UInt32(0)
      while dr.hint(i < n, max_iterations=n):
          y = y * y
          i += 1
      return y
  ```

- `if_stmt`, `switch`, `dispatch`, gathers/scatters, and textures are differentiable in both modes. Pass differentiable inputs through `args` (`@dr.syntax` does this for you).
- `dr.alloc_local` reads and writes are **not** differentiated. Use a CustomOp.
- Visualize with `dr.graphviz_ad()` and `dr.whos_ad()`.

## 6. Optimizers (`drjit/opt.py`; reference.rst "Optimizers")

- Classes in `drjit.opt`: `Optimizer` (base, a `MutableMapping[str, array]`), `SGD`, `RMSProp`, `Adam`, `AdamW` (1.3+), `Muon` (1.4+, for 2D weights), `GradScaler` (AMP).
- Dr.Jit optimizers **own** the parameters. Unlike PyTorch there is no `zero_grad`. Fetch the parameter from the optimizer each iteration.

  ```python
  from drjit.opt import Adam
  opt = Adam(lr=1e-2)             # or Adam(lr=..., params={'x': x}); beta_1, beta_2, epsilon, amsgrad, ...
  opt['x'] = Float(1, 2, 3)       # registers a copy and enables grad
  for it in range(100):
      x = opt['x']
      loss = dr.sum(dr.square(x - 3))
      dr.backward(loss)
      opt.step()                  # step(eval=True, grad_scale=None, active=None)
      opt['x'] = dr.clip(opt['x'], 0, 10)   # projection; keeps optimizer state
  ```

- Other methods: `opt.set_learning_rate(...)`, `opt.learning_rate(key)`, `opt.reset(key)`, `opt.update(mapping)`.
- With `nn.Module`: call `opt.update(net)` **once**, then `net.update(opt)` at the start of every iteration. Never call `opt.update(net)` again, because it overwrites the step.
- Do not print the loss every iteration: it syncs. Use `dr.print("{}", loss)`, which is deferred.
- Mitsuba has its own `mi.ad.Adam` / `mi.ad.SGD` (in `src/python/python/ad/optimizers.py`), which follow the same idea. The `drjit.opt` versions are the newer generic ones.

## 7. Textures (`docs/textures.rst`)

- Build from a tensor: `Texture2f(tensor[H, W, C], filter_mode=dr.FilterMode.Linear, wrap_mode=dr.WrapMode.Repeat, use_accel=True)`. Query with `tex.eval(pos: Array2f in [0,1]^2)`, which returns a list or array of channels. Also `eval_cubic`, `eval_fetch`, `eval_lod`, `eval_filtered(pos, ddx, ddy)`.
- MIP and anisotropic options (1.6, new): `mip_filter=dr.MipFilter.{Disabled,Nearest,Linear}`, `max_aniso`. A Laplacian pyramid basis is available via `mip_basis=dr.MipBasis.Laplacian` (`tex.tensor(level)`, `set_tensor(level, t, rebuild=False)`, `update_inplace()`).
- 8-bit textures (`Texture2f8u`, `srgb=True`) and BC4/5/7 block-compressed data (`dr.BlockFormat`) are supported. Writable textures use `writable=True` with `tex.write([x, y], [r, g, b, a])`. `from_native_handle` / `native_handle` and `map()`/`unmap()` handle GL/Metal interop.
- With CUDA HW acceleration, data **migrates** into a texture object, and `tex.tensor()` / `value()` return *symbolic views*. Snapshot with `TensorXf(tex.tensor())` plus `dr.eval` before calling `set_value`. HW linear filtering uses 8-bit fractional weights. AD still works through a shadow non-accelerated lookup.
- Precision follows the query point type.

## 8. Function freezing (`docs/freeze.rst`; `freeze` in `drjit/__init__.py`)

- `@dr.freeze` (or `@dr.freeze(state_fn=..., limit=None, warn_after=10, backend=None, auto_opaque=True, enabled=True)`) records the kernels launched by the first call. Later compatible calls **replay** them with no Python tracing. Attributes: `f.n_recordings`, `f.n_cached_recordings`, `f.clear()`, `f.enabled`. Disable globally with `JitFlag.KernelFreezing`. Inside a recording `JitFlag.FreezingScope` is True.
- These do **not** retrace: different array *contents* or *widths*, as long as the groups of same-width inputs stay consistent. Changing a tensor's leading dimension is also fine.
- These **retrace**:
  - a different type, Python scalar value, container length, or dict keys
  - a non-PyTree object that compares unequal
  - a changed compiler flag
  - a changed grad-enabled status
  - a size-1 vs size-N switch
  - a change in a tensor's rank or a non-leading dim
- Captured globals and closures **are** detected. State reached through helpers or non-PyTree `self` is **not**: use `state_fn` or `DRJIT_STRUCT`. The latest commit "Retrace frozen functions on scalar state change" extends this.
- Changing literals such as `UInt32(i)` are auto-made opaque after one extra recording. Pass `dr.opaque(UInt32, i)` from the start.
- Sharp bits:
  - Reading values to Python inside a frozen function (`x[0]`, `.numpy()`, `print`, `dr.any(...)` used in a Python `if`) raises.
  - Width relations other than integer multiples or fractions (for example `dr.width(x) - 1`) are baked in, which gives wrong results or OOB on replay. Ambiguous size inference occurs when several inputs have different widths.
  - Tensor `t[rows, :]` with an index array of varying length is baked in.
  - Creating or updating textures or building ray-tracing acceleration structures inside a frozen function is unsupported on CUDA and Metal. Custom CUDA kernels are not captured.
  - First-call input initialization makes two recordings and **runs the body twice**, so RNG or file side effects happen twice.
- AD: calling `dr.backward()` *inside* the frozen function records primal and adjoint together. That is cheaper than backpropagating from its return value, which re-runs the primal.

## 9. Interop (`docs/interop.rst`; `drjit/interop.py`)

- Construction from NumPy, Torch, or JAX goes through DLPack and is zero-copy when possible: `Array3f(np_arr)` (from shape `(3,N)`), `TensorXf(any_shape)`.
- Export with `x.numpy()`, `x.torch()`, `x.jax()`, `x.__dlpack__()`, or `memoryview`. All of them evaluate first. **TensorFlow support was removed in 1.4.**
- These conversions do **not** carry gradients. For differentiable bridges use the `@dr.wrap(source='torch'|'jax', target='drjit')` decorator (or the reverse). It supports forward and reverse mode and PyTree args. Put it above `@dr.syntax`.
- Inside a symbolic loop, conditional, or call you cannot call Torch or JAX. Switch to evaluated mode (`docs/faq.rst`).
- JAX preallocates 75% of GPU memory, so set `XLA_PYTHON_CLIENT_PREALLOCATE=false`. `dr.flush_malloc_cache()` frees Dr.Jit's allocator cache.

## 10. Cooperative vectors and NN (`docs/coop_vec.rst`, `docs/nn.rst`; `drjit/nn.py`)

- `import drjit.nn as nn`. `nn.CoopVec(*pytrees)` is an opaque, non-indexable vector that you unpack with `x, y, *rest = vec`. Allowed ops: `+ - *`, `fma`, `minimum`, `maximum`, `log2`, `exp2`, `tanh`, `step`, `nn.matvec`.
- `A_view, b_view = nn.pack(A, b, layout='inference'|'training')` packs weights into the optimal layout and returns `MatrixView`s. The buffer is `A_view.buffer`.
  - **1.4 breaking change:** `pack` no longer returns the buffer as the first tuple element.
  - Use `layout='training'` for reverse-mode AD.
  - Compute with `nn.matvec(A, x, b, transpose=False)`.
- On CUDA, coop vectors map to the OptiX cooperative vector API (tensor cores, fp16 only, driver R570+). Metal and LLVM are supported, with LLVM mainly for testing. Divergent lanes hurt performance, so consider `dr.reorder_threads`.
- Modules: `nn.Sequential, Linear, ReLU, LeakyReLU, Exp, Exp2, Tanh, Cast, ScaleAdd, SinEncode, TriEncode, HashEncodingLayer` plus `nn.HashGridEncoding` / `nn.PermutoEncoding`.
  - Build with `net = nn.Sequential(...).alloc(TensorXf16, in_size, rng=dr.rng(0))`, then optionally `net = nn.pack(net, layout='training')`.
  - Call `net(nn.CoopVec(p))` for fused cooperative-vector mode or `net(tensor)` for tensor mode.
  - Modules are mappings with keys such as `'layers.0.weights'`, or `'weights'` once packed.
  - Use `GradScaler` for fp16: `dr.backward(scaler.scale(loss)); scaler.step(opt)`.
  - The API is marked experimental.

## 11. Debugging and profiling (`docs/debug.rst`, `docs/bench.rst`, `docs/eval.rst`)

- **`print` vs `dr.print`.** Python `print(x)` forces evaluation and raises on symbolic variables. `dr.print("x={x}", x=x, active=mask, limit=20)` (or `dr.print(x)`) prints immediately if nothing is symbolic. Otherwise it is **deferred** until the next eval and works in symbolic loops, conditionals, and calls (use `{thread_id}`).
  - The format mini-language is limited.
  - **Do not pass `mode='auto'` explicitly.** In this version a parsing bug (`src/python/print.cpp:422-431`) makes it raise "'mode' parameter must be one of ...". Valid explicit values are `'evaluate'` and `'symbolic'` (verified). `opt.py`'s docstring suggests `symbolic=True`, which is also not a valid kwarg. Omit `mode`.
  - `dr.format(...)` returns a string.
- **Logging.** `dr.set_log_level(dr.LogLevel.Info)` shows each launch: `launching <hash> (n=..., in, out, ops, jit=...) cache miss, build: ..`. Levels: `Disable, Error, Warn, Info, InfoSym, Debug, Trace`. `Debug` logs every `jit_var_new`. `dr.log_level()` reads the current level.
- `dr.whos()` lists variables, memory, and **launch stats** (hits, soft and hard misses), which is how to spot recompilation from changing literals. Also `dr.graphviz()`, `dr.graphviz_ad()`, `dr.whos_ad()`.
- **Kernel history (new API, 1.6):**

  ```python
  with dr.kernel_history() as kh:
      y = f(x); dr.eval(y)
  print(kh)                                   # table: type, size, ops, cache, codegen/compile/execute times, hash
  t = sum(k.execution_time for k in kh)       # KernelHistoryEntry attributes
  ```

  The old pattern (`with dr.scoped_set_flag(dr.JitFlag.KernelHistory, True): ... dr.kernel_history()` returning dicts with `k["execution_time"]`) still works but is **deprecated**. `dr.kernel_history_clear()` also exists.
- Benchmarking: `time.time()` around traced code measures only tracing. Even with `dr.eval` + `dr.sync_thread()` the result includes compilation and noise. Use `kernel_history`, or `Event().record()` and `elapsed_time` (CUDA and LLVM only). `dr.profile_range("name")` / `dr.profile_mark` produce NVTX or os_signpost marks, and `dr.profile_enable()` gives targeted nsys or Xcode capture.
- **Debug mode:** `dr.set_flag(dr.JitFlag.Debug, True)` at program start.
  - It adds bounds checks for gather, scatter, and switch indices (it warns and masks), activates `dr.assert_true/assert_false/assert_equal`, enables OptiX validation, and makes source-location labels available (`x.label`).
  - It is expensive and breaks caching.
  - On LLVM it emits DWARF line tables, so LLDB or GDB can break on Python lines inside kernels (**new in 1.6**; LLDB needs `settings set plugin.jit-loader.gdb.enable on`).
- To step through code, use `dr.set_flag(dr.JitFlag.SymbolicAll, False)` or `with dr.scoped_set_flag(dr.JitFlag.SymbolicAll, False):`. That switches to evaluated mode so `print` and pdb work.
- `dr.set_leak_warnings(False)` silences variable-leak warnings at exit.
- **OptiX kernels are opaque by default.** To see the final SASS: `rm -rf ~/.drjit`, re-run once, then open `~/.drjit/optix7cache.db`, which is a SQLite database holding the compiled SASS. Details in `mitsuba-internals.md` (debugging section).

### Common errors and pitfalls

| Symptom / message | Cause | Fix |
|---|---|---|
| `Bool.__bool__(): implicit conversion to 'bool' requires an array with at most 1 element` | Python `if`/`while` on an array | `@dr.syntax`, `dr.select`, `dr.if_stmt`, `dr.while_loop`, or `dr.any/all` |
| "tried to evaluate a *symbolic* variable ... not permitted" | `print`, `x[i]`, `.numpy()`, `dr.sum(x)` (flat) or other cross-lane reductions, `dr.eval` inside a symbolic loop, cond, or call | `dr.print`; move the reduction outside; evaluated mode via `dr.hint(..., mode='evaluated')` |
| "Variable rN remains dirty despite an attempt to evaluate it" | Reading a scatter target (or a symbolic-mode reduction result) inside the same symbolic region | `dr.alloc_local`; restructure; evaluated mode |
| "operands have incompatible sizes" | Width mismatch (not 1 vs N) | Fix the widths; broadcasting only works from size 1 |
| `drjit.if_stmt(): the non-array state variable 'y' of type 'int' changed` | A Python scalar is assigned differently in branches or iterations | Initialize as a Dr.Jit type (`UInt32(3)`) or use `dr.hint(..., strict=False)` |
| Loop never ends (symbolic) but works when evaluated | Python `int` counter in a symbolic loop | Use `UInt32(0)` |
| Conditional update silently unmasked | `self` is not a PyTree | Dataclass or `DRJIT_STRUCT` |
| Every iteration shows `cache miss` | Literal changes (Python scalar or `Float(i)`), or growing graph (unevaluated RNG or state) | `dr.opaque` / `dr.make_opaque`; `dr.eval(state, rng)` each iteration |
| Huge compile time | Python `for` unrolled, or `while` on a Python bool | Device loop with an array counter; `@dr.func` for repeated subroutines |
| Reverse-mode loop error requiring `max_iterations` | No hint | `dr.hint(cond, max_iterations=-1 or N)` |
| `x.grad` is 0 on an interior node | Destructive traversal | `flags=dr.ADFlag.ClearNone`, or read the grad on the leaf |
| Gradient missing after `a *= ...` | Leaf rebound | Keep the original reference |
| Crash or garbage from gather or scatter | OOB index (unchecked) | `JitFlag.Debug` |
| Mixed module error or unexpected types | Mixing `drjit.cuda`, `drjit.llvm`, `.ad`, and non-ad types | Import everything from one module (or `drjit.auto.ad`) |
| `dr.sum(x)` is not a float | Reductions keep the trailing dim (size 1) | `dr.sum(x)[0]` (this syncs) |
| `a.x[a.x < 0] = 0` has no effect | The swizzle or component returns a copy | `a.x = dr.select(a.x < 0, 0, a.x)` |
| Slow loss printing in an optimization loop | Host sync every iteration | Use `dr.print` or print every k iterations |

## 12. Stale knowledge to watch for (old Dr.Jit 0.4 / enoki vs current 1.x)

- **`enoki` / `ek.*` is gone.** It is now `import drjit as dr`. The current API is Dr.Jit 1.x. In this checkout it is 1.6.0-dev: nanobind bindings, Python >= 3.10.
- **`dr.Loop` / `dr.cuda.Loop` / `loop.put(...)` / `while loop(cond):` no longer exist** (verified: `hasattr(dr, 'Loop')` is False). Use `@dr.syntax` + `while`, or `dr.while_loop(state, cond, body)`.
- Old masked-assignment idioms (`x[mask] = v` on JIT arrays via `dr.masked`) should be replaced by `dr.select` or `@dr.syntax if`.
- `dr.print_async` was replaced by `dr.print`. `dr.all_nested`/`dr.any_nested` were replaced by `axis=` / `axis=None` on reductions.
- `dr.custom(Op, ...)` + `dr.CustomOp` still exist, but the callbacks use `grad_in('name')`, `set_grad_out`, `grad_out()`, `set_grad_in`.
- AD seeding: use `dr.forward(x)` / `dr.backward(y)` or `forward_to/backward_to`. `dr.ADFlag` replaced the old `retain_graph`-style booleans.
- Reverse-mode differentiation of symbolic loops exists only since 1.4 and **needs `max_iterations`**. Older code used evaluated loops or custom ops (Mitsuba's PRB-style integrators).
- Mixed-precision AD works across casts thanks to a single global AD graph.
- `dr.kernel_history()` is now a context manager with typed entries; the dict-based form is deprecated. `dr.rng()` / `Generator` are new alongside `PCG32`. `drjit.opt` (Adam/AdamW/Muon/GradScaler) and `drjit.nn` are newer than most online examples.
- The `nn.pack` return signature changed in 1.4. TensorFlow interop was removed in 1.4. The Metal backend is new in 1.4. CUDA requires CC 7.5+.
- `dr.minimum`/`maximum` **propagate NaN** (1.5); `dr.fmin`/`fmax` suppress it. `dr.clip` is `minimum(maximum(v, lo), hi)` and propagates NaN. `dr.frob` returns the norm, not its square (1.6). Float `%` follows Python semantics (1.6).
- New in 1.6: `mode="simd"`, `dr.simd_reduce`, `where=` masks on reductions, `dr.expm1`/`log1p`, HSV/HSL conversions, `transform_decompose_qr`, `drjit.quad` quadrature module (moved from Mitsuba), and LLDB/GDB kernel debugging.
- The `@dr.freeze` frontend was redesigned in 1.6: errors name the offending inputs, and closures and globals are detected.

## 13. Minimal correct snippets

```python
import drjit as dr
from drjit.auto.ad import Float, UInt32, Array3f, Bool, TensorXf

# Fused elementwise + reduction
x = dr.linspace(Float, 0, 1, 1_000_000)
m = dr.mean(dr.sin(x * x))           # size-1 Float; m[0] syncs to a Python float

# Gather/scatter with masks
buf = dr.zeros(Float, 16)
idx = dr.arange(UInt32, 8) * 2
dr.scatter(buf, Float(1), idx, active=idx < 10)
vals = dr.gather(Float, buf, idx)    # evaluates buf first (it is dirty)

# Avoid recompiles across iterations
y = dr.zeros(Float, 1024)
for i in range(100):
    y = y + dr.opaque(Float, i * 0.1)
    dr.eval(y)

# Vectorized control flow
@dr.syntax
def collatz_steps(n: UInt32):
    steps = UInt32(0)
    while n != 1:
        if n % 2 == 0:
            n //= 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps

# Reverse-mode through a loop (sum-style)
@dr.syntax
def integrate(theta: Float, n: int):
    acc, i = Float(0), UInt32(0)
    while dr.hint(i < n, max_iterations=-1):
        acc += dr.sin(theta * Float(i))
        i += 1
    return acc

theta = Float(0.3); dr.enable_grad(theta)
loss = integrate(theta, 16)
dr.backward(loss); print(theta.grad)

# Indirect call
out = dr.switch(UInt32(0, 1, 1), [lambda v: v + 1, lambda v: v * 10], Float(1, 2, 3))

# Debug a symbolic program
with dr.scoped_set_flag(dr.JitFlag.SymbolicAll, False):
    print(collatz_steps(dr.arange(UInt32, 1, 9)))

# Timing
with dr.kernel_history() as kh:
    dr.eval(collatz_steps(dr.arange(UInt32, 1, 1 << 20)))
print(kh)
```

## 14. Where to read more

- Concepts: `docs/what.rst`, `docs/basics.rst`, `docs/types.rst`, `docs/eval.rst`, `docs/cflow.rst`, `docs/autodiff.rst`.
- Features: `docs/freeze.rst`, `docs/textures.rst`, `docs/interop.rst`, `docs/coop_vec.rst`, `docs/nn.rst`, `docs/misc.rst` (PyTrees, local memory, transcendental accuracy, type signatures, CUDA green contexts).
- Performance, debugging, C++: `docs/optim.rst` (JIT optimizations: CoW, constant propagation, value numbering, scatter-reduce modes, packet ops, matmul perf), `docs/bench.rst` (timing, events, nsys, Instruments), `docs/debug.rst`, `docs/faq.rst`, `docs/cpp.rst` (C++ `dr::while_loop`, `dr::if_stmt`, `DRJIT_CALL_*`, `DRJIT_STRUCT`, nanobind bindings).
- Reference and history: `docs/reference.rst` (API index), `docs/changelog.rst` (what changed per version).
- Exact semantics: `src/python/docstr.rst` (search `.. topic:: <name>`, e.g. `while_loop`, `JitFlag_*`, `reduce`, `scatter_inc`, `print`) and `drjit/ast.py` (`syntax`, `hint`).
- Usage examples: `tests/test_*.py` (e.g. `test_while_loop_ad.py`, `test_freeze.py`, `test_switch.py`, `test_if_stmt.py`).
