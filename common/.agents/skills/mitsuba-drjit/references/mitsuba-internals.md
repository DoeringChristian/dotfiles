# Mitsuba 3 — internals (C++ architecture, plugins, bindings, debugging)

Written against Mitsuba 3.10.0-dev (`include/mitsuba/mitsuba.h`). Paths are relative to the mitsuba3
checkout. Several upstream docs are stale relative to the source (the `Class` RTTI system,
`mitsuba::Struct`, `MI_USE_OPTIX_HEADERS`, `ninja pytest` are gone; `MI_TRAVERSE_CB` is new) —
trust headers over `docs/src/developer_guide`.

Build, variant configuration and tests are in `build-and-test.md`.

## Contents
1. Repository layout · 2. C++ architecture (variants, type macros, object system, traversal,
Properties, plugin loading, render types, masking rules, nanobind) · 3. Writing a C++ plugin ·
4. Debugging

---------------------------------------------------------------------------------------------------

## 1. Repository layout map

```
CMakeLists.txt            top-level build (options, mitsuba.conf handling, add_plugin(), ro_copy())
pyproject.toml            scikit-build-core wheel build; pins drjit==1.6.0.dev1, nanobind==3.1.0;
                          [tool.pytest.ini_options] testpaths=["src"], norecursedirs=["src/python"]
include/mitsuba/
  mitsuba.h               version macros
  core/                   variant-independent-ish infrastructure (headers only listed):
    object.h              Object, ObjectType, JitObject<CRTP>, MI_DECLARE_CLASS,
                          MI_DECLARE_PLUGIN_BASE_CLASS, MI_EXPORT_PLUGIN, ParamFlags, TraversalCallback
    fwd.h                 MI_VARIANT, MI_IMPORT_CORE_TYPES, MI_MASK_ARGUMENT, MI_MASKED_FUNCTION,
                          MI_TRAVERSE_CB / MI_DECLARE_TRAVERSE_CB / MI_IMPLEMENT_TRAVERSE_CB,
                          MI_DECLARE_ENUM_OPERATORS
    properties.h          Properties (plugin constructor args)
    plugin.h              PluginManager
    traverse.h            ParameterTable (C++ side of traverse)
    struct.h              thin wrapper over ext/struct-jit (namespace alias `sj`)
    logger.h              Log(level, ...), Throw(...), MI_ASSERT1/2
    bitmap.h, transform.h, frame.h, vector.h, spectrum.h, warp.h, distr_*.h, qmc.h, random.h,
    bbox.h, ray.h, field.h, tensor.h, profiler.h, parser.h, platform.h (MI_EXPORT...), ...
  render/                 rendering interfaces:
    fwd.h                 RenderAliases, MI_IMPORT_BASE, MI_IMPORT_TYPES, MI_IMPORT_OBJECT_TYPES
    bsdf.h emitter.h endpoint.h sensor.h film.h imageblock.h integrator.h sampler.h shape.h
    mesh.h shapegroup.h scene.h interaction.h records.h texture.h volume.h volumegrid.h
    medium.h phase.h microfacet.h fresnel.h postprocess.h kdtree.h
    accel.h accel_embree.h accel_native.h accel_optix.h accel_metal.h optix_api.h optixdenoiser.h
  python/                 python.h (MI_PY_* binding macros), docstr.h (generated docstrings D(...))
src/
  CMakeLists.txt          builds libmitsuba (= mitsuba-core + mitsuba-render), the `mitsuba`
                          executable, all plugin dirs, then src/python
  conftest.py             pytest root conftest (variant fixtures)
  core/                   *.cpp for include/mitsuba/core (parser.cpp, plugin.cpp, properties.cpp,
                          bitmap.cpp, logger.cpp, ...); core/python/ = nanobind bindings; core/tests/
  render/                 scene.cpp, shape.cpp, mesh.cpp, integrator.cpp, bsdf.cpp, ...
                          scene_{embree,native,optix,metal}.inl (accel back ends), optix/, metal/,
                          metal_accel.mm; render/python/ = bindings; render/tests/
  mitsuba/mitsuba.cpp     C++ CLI frontend
  bsdfs/ emitters/ films/ integrators/ media/ phase/ rfilters/ samplers/ sensors/ shapes/
  spectra/ textures/ volumes/   -> C++ plugins, one .cpp per plugin, each dir has CMakeLists.txt
                          and tests/ (pytest)
  python/                 Python package sources:
    __init__.py           top-level `mitsuba` package (set_variant, variants, alias machinery)
    __main__.py           `python -m mitsuba scene.xml` frontend
    main.cpp              variant-independent ext `mitsuba_ext`
    main_v.cpp            per-variant ext (compiled once per variant -> `<variant>.abi3.so`)
    python/               becomes `mitsuba.*` pure-Python submodules: util.py (traverse,
                          SceneParameters, render, variant_context), chi2.py, testing.py,
                          tensor_io.py, ad/ (integrators/, optimizers.py, projective.py,
                          largesteps.py, guiding.py, loaders/), test/
  python_tests/           extra pytest tests (largesteps, ray_loader, util)
resources/
  mitsuba.conf.template   master variant table (Float/Spectrum types per variant)
  configure.py            parses mitsuba.conf -> generated config.h + config.py
  setpath.sh/.bat/.ps1    templates; variant-stub.cmake; check-style.sh; mkdocs.py
  data/                   submodule mitsuba-data (test scenes, reference images, docs images)
docs/                     Sphinx docs; developer guide in docs/src/developer_guide.rst and
                          docs/src/developer_guide/{compiling,writing_plugin,variants_cpp,testing,
                          documentation,distributing_plugins}.rst
tutorials/                submodule mitsuba-tutorials (notebooks; render/tests/test_tutorials.py)
compile_commands.json     symlink -> build-mitsuba/compile_commands.json (clangd)
build-*/                  local build trees (see build-and-test.md)
```

### ext/ submodules (`.gitmodules`)
`drjit` (Dr.Jit; contains `ext/drjit-core` = JIT compiler, and its own `ext/nanobind`), `nanobind`,
`struct-jit` (binary struct conversion, replaces old mitsuba::Struct), `embree`, `openexr`,
`libpng`, `libjpeg-turbo`, `zlib`, `pugixml` (XML), `tinyformat`, `fastfloat`, `ittnotify`
(VTune), `rgb2spec` (spectral upsampling).
Also `resources/data` and `tutorials` are submodules.

Submodule skew: `git status` shows ` M ext/drjit` - the drjit submodule is intentionally checked
out at a newer commit (`6f7cbc2e Retrace frozen functions on scalar state change`, v1.5.0-124)
than recorded by the superproject. Do NOT reset/update submodules casually.

---------------------------------------------------------------------------------------------------

## 2. C++ architecture

### 2.1 Variants = template parameters `<Float, Spectrum>`
Nearly every class is `template <typename Float, typename Spectrum>` (shorthand macro `MI_VARIANT`,
`include/mitsuba/core/fwd.h:214`). The pair *is* the variant. From `build-mitsuba/mitsuba.conf`
and generated `build-mitsuba/include/mitsuba/core/config.h`:

| variant | Float | Spectrum |
|---|---|---|
| scalar_rgb | `float` | `Color<Float,3>` |
| scalar_spectral | `float` | `Spectrum<Float,4>` |
| llvm_ad_rgb | `dr::DiffArray<JitBackend::LLVM,float>` | `Color<Float,3>` |
| llvm_ad_spectral | `dr::DiffArray<JitBackend::LLVM,float>` | `Spectrum<Float,4>` |
| metal_ad_rgb | `dr::DiffArray<JitBackend::Metal,float>` | `Color<Float,3>` |

Name grammar: `{scalar,llvm,cuda,metal}[_ad]_{mono,rgb,spectral}[_polarized][_double]`;
polarized uses `MuellerMatrix<...>` spectra, `_double` uses double Float.

Generated macros in `config.h` (one line per enabled variant):
- `MI_VARIANTS` (string list, descending preference), `MI_INSTANTIATE_CLASS(Name)` /
  `MI_INSTANTIATE_STRUCT(Name)` (explicit instantiation in a .cpp of libmitsuba),
  `MI_EXTERN_CLASS(Name)` / `MI_EXTERN_STRUCT(Name)` (extern template in headers),
  `MI_INVOKE_VARIANT(variant, func, ...)` (runtime string -> template dispatch),
  `MI_REGISTER_PLUGIN(cb, id, Name)` (used by `MI_EXPORT_PLUGIN`),
  `MI_VARIANT_TEMPLATE()` (variant name lookup `detail::variant<Float,Spectrum>::name`).
- Consequence: every plugin .cpp compiles all enabled variants -> compile time ~ #variants.

### 2.2 Type import macros
- `MI_IMPORT_CORE_TYPES()` (`core/fwd.h:315`): `Float`-derived `Vector{2,3}f/i/u`, `Point*`,
  `Normal3f`, `Frame3f`, `Transform4f`, `BoundingBox3f`, `Mask`, `UInt32`, `ScalarFloat`,
  `ScalarVector3f`, ...
- `MI_IMPORT_TYPES(...)` (`render/fwd.h:196`): core types + render aliases from `RenderAliases`:
  `Ray3f`, `UnpolarizedSpectrum`, `Wavelength`, `Interaction3f`, `SurfaceInteraction3f`,
  `MediumInteraction3f`, `PreliminaryIntersection3f`, `PositionSample3f`, `DirectionSample3f`,
  `BSDFSample3f`, `BSDFContext`, ... Extra args (e.g. `Texture`, `Scene`, `Sampler`, `Medium`,
  `BSDFPtr`, `EmitterPtr`, `ShapePtr`) import `X = X<Float,Spectrum>`.
- `MI_IMPORT_BASE(Name, members...)` (`render/fwd.h:179`): `using Base = Name<Float,Spectrum>;`
  plus `using Base::member;` for each (needed because base members of templates are dependent).
- `MI_IMPORT_OBJECT_TYPES()` imports the plugin interface aliases only.
- `MI_MASK_ARGUMENT(active)` / `MI_MASKED_FUNCTION(ProfilerPhase::X, active)` (`core/fwd.h:320,325`):
  make `active` a compile-time true on scalar variants; the latter also opens a profiler scope.

### 2.3 Object system (no more `Class` RTTI)
`include/mitsuba/core/object.h`:
- `class Object : public drjit::TraversableBase` (line 99): intrusive refcount shared between C++
  and Python (nanobind intrusive mode). `ref<T>` is the smart pointer. Virtuals: `expand()`,
  `traverse(TraversalCallback*)`, `parameters_changed(const std::vector<std::string>& keys = {})`,
  `to_string()`, `type()`, `id()`/`set_id()`, `class_name()`, `variant_name()`.
- `enum class ObjectType` (line 31): Unknown, Scene, ReconstructionFilter, Sensor, Film,
  PostProcess, Emitter, Sampler, Shape, Texture, Volume, Medium, BSDF, PhaseFunction, Integrator.
  The parser type-checks plugins against this.
- `MI_DECLARE_CLASS(Name)` (line 208): only defines `static constexpr ClassName` and overrides
  `class_name()`. Put it in every concrete class (plugins). The old `Class*`/`MI_IMPLEMENT_CLASS`
  machinery from Mitsuba <=3.6 docs no longer exists (there is no `core/class.h`).
- `MI_DECLARE_PLUGIN_BASE_CLASS(Name)` (line 232): for interface bases (BSDF, Shape, Emitter, ...);
  adds `Variant`, `Domain`, `Type` statics and overrides `variant_name()`/`type()`.
- `template <typename Derived> class JitObject : public Object` (line 294): CRTP base of plugin
  interfaces (e.g. `class Scene final : public JitObject<Scene<Float,Spectrum>>`,
  `Shape`, `Integrator`, BSDF...). In JIT variants it registers the instance with Dr.Jit's
  registry (`jit_registry_put(Variant, Domain, this)`) -- this is what enables vectorized virtual
  calls over `BSDFPtr`/`EmitterPtr`/`ShapePtr` arrays. `unregister()` withdraws it.
- Vcall surface: each interface header ends with `DRJIT_CALL_TEMPLATE_BEGIN(mitsuba::BSDF) ...
  DRJIT_CALL_METHOD(sample) ... DRJIT_CALL_GETTER(flags) DRJIT_CALL_END()` (see `render/bsdf.h`).
  New virtual methods that must be callable on pointer arrays need to be added there.

### 2.4 Traversal: two separate mechanisms
1. `traverse(TraversalCallback *cb)` + `parameters_changed(keys)` -- the *user-facing* parameter
   API behind `mi.traverse(obj)` / `SceneParameters`. In `traverse` call
   `cb->put("name", member, ParamFlags::...)`. `ParamFlags` (`object.h:408`): `Differentiable=0`,
   `NonDifferentiable=1`, `Discontinuous=0x2`, `ReadOnly=0x4`. Putting a non-float/non-diff type
   with Differentiable throws. Objects (`ref<T>`) are recursed into (keys become dotted paths, e.g.
   `red.bsdf.reflectance.value`). `SceneParameters.update()` (`src/python/python/util.py:183`)
   writes values back and calls `parameters_changed(keys)` on owners (and parents, with key
   `"parent"`), which must recompute derived state (e.g. CDFs, accel rebuild for geometry).
2. `traverse_cb(void*, const drjit::TraverseVisitor&)` -- Dr.Jit-level traversal used by
   `@dr.freeze` (function freezing). Generated with `MI_TRAVERSE_CB(Base, m_member1, m_member2...)`
   (`core/fwd.h:419`) placed at the END of the class (it emits `public:`). It only acts for roles
   `Freeze`/`Children`. List every member holding JIT arrays or `ref<>` children; forgetting one is
   a classic frozen-function bug ("variable ... had not yet been initialized"). For classes declared
   in a header and implemented in a .cpp use `MI_DECLARE_TRAVERSE_CB(...)` +
   `MI_IMPLEMENT_TRAVERSE_CB(Type, Base)`. Plugins with no JIT state (e.g.
   `src/integrators/depth.cpp`) omit it.

### 2.5 Properties (`include/mitsuba/core/properties.h`)
Insertion-ordered typed name->value map passed to every plugin constructor.
- `props.get<T>("name")`, `props.get<T>("name", default)`, `props.has_property(name)`,
  `props.get_any<T>`, `props.set(name, value)`; iterate `for (auto &p : props)` or
  `props.objects()` with `p.try_get<BSDF>()`.
- Textures: `props.get_texture<Texture>("reflectance", .5f)` (constant-or-texture),
  `get_emissive_texture`, `get_unbounded_texture`; volumes: `get_volume<Volume>(name[, def])`.
- Query tracking: every `get` marks queried; `unqueried()` / `was_queried()` / `mark_queried()`
  -> the loader warns/errors about unused parameters (typo detection).
- Python: dict-like `mi.Properties`, `props.get('max_depth', 6)`.

### 2.6 Plugin registration and loading
- End of each plugin file: `MI_EXPORT_PLUGIN(Name)` (`object.h:390`) emits
  `extern "C" void init_plugin(std::string_view name, PluginRegisterFn fn)` that calls
  `MI_REGISTER_PLUGIN` -> one constructor lambda per enabled variant.
- `PluginManager` (`core/plugin.h`, `src/core/plugin.cpp:93-143`) dlopens
  `<build>/plugins/<name>.dylib` (`.so` on Linux) on demand; the plugin *type string* in XML/dict
  (`"type": "diffuse"`) equals the library filename = first arg of `add_plugin()`.
- Scene loading (`src/core/parser.cpp`): parse XML/dict -> flat `SceneNode` list (variant-free),
  transform (upgrades, reference resolution), instantiate per variant via
  `PluginManager::create_object(props, variant, type)`; JIT variants instantiate asynchronously
  (`mi.load_dict(d, parallel=False)` for deterministic variable order).
- Python plugins: `mi.register_bsdf/emitter/integrator/sensor/sampler/texture/shape/film/
  postprocess/rfilter/medium/phase(name, lambda props: Cls(props))`
  (bound in `src/render/python/scene_v.cpp:187-264`). AD integrators
  in `src/python/python/ad/integrators/` self-register at import; `__init__.py` there lists the
  submodules imported for non-scalar variants.

### 2.7 Key render types
- `Scene` (`render/scene.h:45`): `ray_intersect(ray, active)` or
  `ray_intersect(ray, ray_flags, coherent, ray_mask, active)`,
  `ray_intersect_preliminary(...)` -> `PreliminaryIntersection3f` (cheap; then
  `compute_surface_interaction`), `ray_test`, `sample_emitter`, `pdf_emitter`,
  `sample_emitter_direction(ref_it, sample, test_visibility, active)`, `pdf_emitter_direction`,
  `eval_emitter_direction`, `sample_emitter_ray`, `sample_silhouette`, accessors `sensors()`,
  `emitters()`, `environment()`, `shapes()`, `shapegroups()`, `integrator()`,
  `emitters_dr()/shapes_dr()/sensors_dr()` (pointer arrays for vcalls), `bbox()`.
  Accel back ends selected at compile time: Embree/native kd-tree (scalar, llvm), OptiX (cuda),
  Metal (metal) -- `src/render/scene_*.inl`.
- `ShapeGroup` (`render/shapegroup.h`): a Shape holding child shapes with its own accel; used with
  the `instance` shape plugin for instancing. Scene keeps `m_shapegroups`.
- Interactions (`render/interaction.h`): `Interaction<Float,Spectrum>` (t, time, wavelengths, p, n;
  line 176), `SurfaceInteraction` (line 317: shape, uv, sh_frame, dp_du/dv, wi in local frame,
  prim_index, instance; `bsdf()`, `emitter(scene)`, `spawn_ray(d)`, `to_local/to_world`,
  `is_valid()`), `MediumInteraction` (line 774), `PreliminaryIntersection` (line 861).
  Records: `PositionSample`, `DirectionSample` (`records.h`), `BSDFSample3f`, `BSDFContext`.
- Integrators (`render/integrator.h`): `Integrator` (37), `SamplingIntegrator` (356; implement
  `std::pair<Spectrum,Mask> sample(const Scene*, Sampler*, const Ray3f&, const Medium* = nullptr,
  Mask active = true) const`), `MonteCarloIntegrator` (492; max_depth/rr_depth), `AdjointIntegrator`
  (540; light tracing). `render()` uses spiral 32x32 blocks for scalar and a single wavefront
  (`film_w*film_h*spp` lanes) for JIT variants.
- Struct: `mitsuba::Struct`/`StructConverter` were REMOVED; `core/struct.h` wraps
  `ext/struct-jit` (`sj::Struct`, `sj::Converter`, `sj::make_converter()`, `struct_type_v<T>`).
  Used for mesh/bitmap/PLY binary layouts.

### 2.8 Masking and JIT rules for C++ code
- Never branch on per-lane values with `if`; use `dr::select`, masks, and the trailing
  `Mask active` argument. Horizontal ops (`dr::any/all/none`) sync JIT backends; prefer
  `dr::any_or<true>(m)` / `dr::none_or<false>(m)` (these short-circuit to a constant on JIT).
  Example in `src/bsdfs/diffuse.cpp`: `if (unlikely(dr::none_or<false>(active) || ...)) return {bs, 0.f};`
- `-Wdouble-promotion` is on: write float literals `0.5f`.

### 2.9 Python bindings (nanobind)
- `include/mitsuba/python/python.h`: `MI_PY_EXPORT(Name) { ... }` defines
  `python_export_Name(nb::module_ &m)`; `MI_PY_DECLARE(Name)` + `MI_PY_IMPORT(Name)` wire it into
  the module init (`src/python/main_v.cpp`, `main.cpp`). `MI_PY_IMPORT_TYPES()` imports variant
  types inside binding code. `MI_PY_CLASS`, `MI_PY_TRAMPOLINE_CLASS` (Python subclassing of
  BSDF/Emitter/... via nanobind trampolines), `MI_PY_DRJIT_STRUCT(cls, Type, fields...)` makes a
  bound struct a Dr.Jit PyTree (needed so records flow through symbolic loops/vcalls),
  `MI_PY_CHECK_ALIAS`.
- File convention: `src/{core,render}/python/*_v.cpp` = variant-specific bindings compiled into
  each `<variant>.abi3.so` (via `main_v.cpp`, with `-DMI_VARIANT_NAME/FLOAT/SPECTRUM`);
  non-`_v` files go into variant-independent `mitsuba_ext`. Docstrings `D(Class, method)` come
  from generated `include/mitsuba/python/docstr.h`.
- `src/python/main_v.cpp` `caster()` down-casts `Object*` to the most specific bound interface
  (Scene, Mesh, Shape, ..., MonteCarloIntegrator, ...). New interface types need a `PY_TRY_CAST`.
- Built in nanobind *split mode* (`MI_SPLIT_MODE=ON`): needs the `nanobind-backend` pip package at
  runtime; extensions are `*.abi3.so` (stable ABI). Stale `*.cpython-312-darwin.so` files from an
  older non-split build also sit in `build-mitsuba/python/mitsuba/` -- ignore them.
- Python package mechanics (`src/python/__init__.py`): `mi.set_variant('llvm_ad_rgb')` loads
  `<variant>.abi3.so` and copies its symbols into the `mitsuba` alias module (`mitsuba_alias`);
  the active variant is process-global. `mi.variant_context(...)` / `mi.scoped_set_variant`
  (`util.py:644,659`) scope a temporary switch. Pure-Python modules from `src/python/python/`
  appear as `mitsuba.<module>` (e.g. `mitsuba.ad.integrators.prb`).
- Python stubs (`*.pyi`) are generated at build time with `nanobind_add_stub` (targets
  `mitsuba-stub*`, `src/python/CMakeLists.txt:213-290`).

---------------------------------------------------------------------------------------------------

## 3. Writing a C++ plugin

Skeleton (mirrors `src/bsdfs/diffuse.cpp`, the canonical simple plugin):

```cpp
#include <mitsuba/core/properties.h>
#include <mitsuba/core/warp.h>
#include <mitsuba/render/bsdf.h>
#include <mitsuba/render/texture.h>

NAMESPACE_BEGIN(mitsuba)

/**!
.. _bsdf-mybsdf:
My BSDF (:monosp:`mybsdf`)
--------------------------
.. pluginparameters::
 * - reflectance
   - |spectrum| or |texture|
   - Albedo (Default: 0.5)
   - |exposed|, |differentiable|
*/
template <typename Float, typename Spectrum>
class MyBSDF final : public BSDF<Float, Spectrum> {
public:
    MI_IMPORT_BASE(BSDF, m_flags, m_components)
    MI_IMPORT_TYPES(Texture)

    MyBSDF(const Properties &props) : Base(props) {
        m_reflectance = props.get_texture<Texture>("reflectance", .5f);
        m_flags = BSDFFlags::DiffuseReflection | BSDFFlags::FrontSide;
        m_components.push_back(m_flags);
    }

    void traverse(TraversalCallback *cb) override {
        cb->put("reflectance", m_reflectance, ParamFlags::Differentiable);
    }
    // void parameters_changed(const std::vector<std::string> &keys) override { ... }

    std::pair<BSDFSample3f, Spectrum> sample(const BSDFContext &ctx,
            const SurfaceInteraction3f &si, Float sample1, const Point2f &sample2,
            Mask active) const override {
        MI_MASKED_FUNCTION(ProfilerPhase::BSDFSample, active);
        ...
    }
    Spectrum eval(const BSDFContext &ctx, const SurfaceInteraction3f &si,
                  const Vector3f &wo, Mask active) const override { ... }
    Float pdf(const BSDFContext &ctx, const SurfaceInteraction3f &si,
              const Vector3f &wo, Mask active) const override { ... }
    // optional: eval_pdf(), eval_features()

    std::string to_string() const override { ... }

    MI_DECLARE_CLASS(MyBSDF)
private:
    ref<Texture> m_reflectance;
    MI_TRAVERSE_CB(Base, m_reflectance)   // members visible to dr.freeze
};

MI_EXPORT_PLUGIN(MyBSDF)
NAMESPACE_END(mitsuba)
```

Integrator variant: derive `SamplingIntegrator<Float,Spectrum>` / `MonteCarloIntegrator`,
`MI_IMPORT_BASE(SamplingIntegrator)`, `MI_IMPORT_TYPES(Scene, Sampler, Medium)`, override
`sample(...)` -- see `src/integrators/depth.cpp` (smallest) and `path.cpp`.

Register in the directory's CMakeLists (e.g. `src/bsdfs/CMakeLists.txt`):
```cmake
add_plugin(mybsdf  mybsdf.cpp)
```
`add_plugin()` (top-level `CMakeLists.txt:420`) creates a SHARED lib linked to `mitsuba`, no
prefix, output in `${MI_BINARY_DIR}/plugins`. Re-run cmake (ninja does it automatically when a
CMakeLists changes), then `ninja -C build-mitsuba`. Use as `{'type': 'mybsdf', ...}`.

The `/**! ... */` block is parsed into the plugin reference docs (docs/), keep the format.
Python-side tests go in `src/bsdfs/tests/test_mybsdf.py` (chi2 test via `mi.chi2.BSDFAdapter`).

Python alternative (no rebuild of C++): subclass `mi.BSDF` / `mi.SamplingIntegrator` /
`mi.ad.integrators.common.ADIntegrator` and `mi.register_bsdf("name", lambda props: Cls(props))`.

---------------------------------------------------------------------------------------------------

## 4. Debugging

Dr.Jit (all from Python; enum values in `ext/drjit/ext/drjit-core/include/drjit-core/jit.h:1683-1768`):
- `dr.set_log_level(dr.LogLevel.Trace)` (levels Disable, Error, Warn, Info, InfoSym, Debug, Trace);
  output goes to stderr -> capture with `pixi run log`. Trace only exists in Debug builds.
- `dr.set_flag(dr.JitFlag.X, True)` / `with dr.scoped_set_flag(dr.JitFlag.X, True):`
  - `Debug` (bounds/NaN checks, source line labels), `ReuseIndices` (turn off for stable `r<N>`),
  - `PrintIR` (dump generated LLVM IR / PTX / Metal), `KernelHistory` (+ `dr.kernel_history()`),
  - `LaunchBlocking` (sync after every launch to localize crashes), `ForbidSynchronization`,
  - `SymbolicLoops`, `SymbolicCalls`, `SymbolicConditionals`, `OptimizeCalls` (disable to fall back
    to evaluated mode when debugging symbolic code), `KernelFreezing`,
  - `ForceOptiX` (CUDA: route all kernels through OptiX), `ShaderExecutionReordering` (OptiX SER).
- Inspection: `dr.whos()`, `dr.graphviz()`, `dr.set_label(x, "name")`, `dr.print(...)` (symbolic
  safe; builtin `print` forces eval), `dr.eval()` to bisect, `rm -rf ~/.drjit` to drop the kernel
  cache (LLVM/CUDA; Metal cache is in-memory).
- LLVM backend needs libLLVM: `DRJIT_LIBLLVM_PATH` (set by the pixi env).

Mitsuba:
- `mi.set_log_level(mi.LogLevel.Debug)`; C++ `Log(Info, "fmt %s", x)`, `Throw("...")`,
  `MI_ASSERT1/2` (`core/logger.h:168-189`). CLI: `mitsuba -v -v scene.xml`, `-m <variant>`.
- `mi.load_dict(d, parallel=False)` for reproducible variable ordering.
- `MI_THROW_TRAPS_DEBUGGER=ON` to break into the debugger at every `Throw`.
- Native: `lldb -- python script.py` (Debug symbols present), or `pixi run debug-mitsuba <test>`.
- Sanitizers: `MI_SANITIZE_ADDRESS` / `DRJIT_SANITIZE_ASAN` (Linux pixi task `build-mitsuba-asan`).
- Profiling: built-in sampling profiler phases via `MI_MASKED_FUNCTION(ProfilerPhase::...)`;
  VTune/NVTX via `MI_PROFILER_ITTNOTIFY` / `MI_PROFILER_NVTX`; on Linux pixi tasks `ncu-prof`,
  `nsys-prof`, `profile`, `lock-gpu`.
- OptiX/CUDA: code paths in `src/render/scene_optix.inl`, `src/render/optix/`,
  `include/mitsuba/render/optix_api.h` (OptiX API resolved at runtime, no SDK headers needed),
  driver >= 535. Not testable on macOS -- test CUDA on a Linux/NVIDIA machine.
  Metal: `src/render/scene_metal.inl`, `src/render/metal_accel.mm`.
- Longer debugging guide (if present in the workspace): `../CODE_OVERVIEW.md` (sections D.1–D.7: r<N> errors, freeze slot diagnosis, IR inspection) and coding conventions in `../STYLE_GUIDE.md`.
