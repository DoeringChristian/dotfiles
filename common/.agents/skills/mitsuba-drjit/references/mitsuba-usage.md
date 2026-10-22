# Mitsuba 3 — usage reference (Python)

Written against Mitsuba 3.10.0-dev (Oct 2026) on Dr.Jit 1.6-dev. Items marked "verified" were run
on `llvm_ad_rgb`. 3.10 has API-breaking changes (mesh params, ray masks, removed ray differentials):
code from older tutorials, blogs or pip releases ≤3.9 may be wrong for a source checkout and vice
versa — check `mi.__version__` and `docs/release_notes.rst`. Paths are relative to the mitsuba3 checkout.

## Contents
1. What Mitsuba is · 2. Variants · 3. Scene description (XML, dict, transforms) · 4. Plugin catalog ·
5. Rendering · 6. Inverse rendering · 7. Writing plugins in Python (integrator, AD integrators, BSDF) ·
8. Dr.Jit essentials for Mitsuba users · 9. Pitfalls · 10. Example scenes · 11. Tutorials index

Key doc files to read more:
- `README.md` — intro, pip install, requirements
- `docs/src/quickstart/mitsuba_quickstart.ipynb`, `drjit_quickstart.ipynb`
- `docs/src/key_topics/{variants,scene_format,file_formats,animation,polarization,differences}.rst`
- `docs/src/how_to_guides/*.ipynb` (image I/O, mesh I/O, transformation toolbox, optimizers)
- `docs/src/plugin_reference/section_*.rst` (+ docstrings at the top of each `src/<category>/*.cpp`)
- `docs/porting_3_6.rst`, `docs/release_notes.rst`, `docs/src/optix_setup.rst` (WSL2 OptiX)
- `docs/src/developer_guide/{compiling,writing_plugin,distributing_plugins,variants_cpp}.rst`
- `tutorials/` (same notebooks as docs): `quickstart/`, `rendering/`, `inverse_rendering/`, `others/`, `how_to_guides/`, `scenes/`
- Python package source: `src/python/python/` (`util.py` = render/traverse/SceneParameters/write_bitmap/cornell_box; `ad/integrators/*.py` = Python AD integrators; `ad/optimizers.py`; `ad/largesteps.py`)

---------------------------------------------------------------------------------

## 1. What Mitsuba 3 is

- Research-oriented, *retargetable* physically based renderer (EPFL RGL) for
  forward and **inverse** (differentiable) light transport. Core library + plugins
  (BSDFs, emitters, shapes, integrators, ...).
- Built on **Dr.Jit** (`import drjit as dr`), a tracing JIT compiler. In JIT
  variants, Python code operating on Mitsuba/Dr.Jit arrays is *traced*, fused into
  kernels, and compiled for CPU (LLVM) or GPU (CUDA/OptiX, Metal). Python plugins
  therefore run at native speed in JIT variants (Python executes once per kernel
  trace, not per ray).
- "Python first": materials, textures, shapes, emitters and full integrators can be
  written in Python and differentiated.
- Install: `pip install mitsuba` (wheels ship 13 variants: `scalar_rgb`,
  `scalar_spectral`, `scalar_spectral_polarized`, `llvm_ad_{rgb,mono,mono_polarized,spectral,spectral_polarized}`,
  `cuda_ad_{rgb,mono,mono_polarized,spectral,spectral_polarized}`).
  Requirements (README): Python >= 3.10, NVIDIA driver >= 535 for GPU (OptiX 8.0 ABI),
  LLVM >= 18 for the `llvm` backend (loaded at runtime).
  3.9 added `metal_*`/`metal_ad_*` variants for Apple Silicon.

## 2. Variants

Name = `<backend>[_ad]_<color>[_polarized][_double]`:
- backend: `scalar` (one ray at a time, CPU, easiest to debug), `llvm` (JIT vectorized CPU),
  `cuda` (JIT GPU + OptiX ray tracing; Turing+ ideal), `metal` (Apple GPU).
- `_ad`: automatic differentiation (only for JIT backends). Required for `mi.render(..., params)` gradients.
- color: `mono`, `rgb`, `spectral` (360–830 nm, RGB inputs are spectrally upsampled via Jakob–Hanika; output still RGB unless `specfilm`).
- `_polarized`: Stokes vectors / Mueller matrices (~1.5–2x cost). `mi.Spectrum` becomes a Mueller matrix type.
- `_double`: FP64 (Embree/OptiX still trace in FP32; ~1/64 throughput on NVIDIA GPUs).

Python API:
```python
import mitsuba as mi
mi.variants()                                   # compiled variants
mi.set_variant('cuda_ad_rgb', 'metal_ad_rgb', 'llvm_ad_rgb')  # first one that loads wins
mi.variant()                                    # active variant name, e.g. 'llvm_ad_rgb'
with mi.variant_context('scalar_rgb'): ...      # temporary switch (alias mi.scoped_set_variant)
mi.is_scalar, mi.is_llvm, mi.is_cuda, mi.is_metal, mi.is_jit, mi.is_ad,
mi.is_monochromatic, mi.is_rgb, mi.is_spectral, mi.is_polarized   # flags (after set_variant)
from mitsuba.scalar_rgb import Transform4f as T   # explicit per-variant submodule import also works
```
Rules:
- **Call `mi.set_variant()` before touching any type or loading anything.** Types
  such as `mi.Float`, `mi.UInt32`, `mi.Point3f`, `mi.Color3f`, `mi.Spectrum`,
  `mi.TensorXf`, `mi.Ray3f`, `mi.SurfaceInteraction3f` are *variant-dependent
  aliases* resolved at attribute access (e.g. in `llvm_ad_rgb`, `mi.Float` is
  `drjit.llvm.ad.Float`, `mi.Spectrum` is `mi.Color3f`). Objects created under one
  variant must not be mixed with another variant's objects; re-load scenes after switching.
  Don't cache `mi.Float` at module import time before the variant is set.
- `mi.Scalar*` types (`mi.ScalarFloat`, `mi.ScalarPoint3f`, `mi.ScalarTransform4f`)
  are plain (non-JIT) types in every variant.
- `scalar_rgb` must always be compiled, plus at least one `_ad` variant (build requirement).

Build-time configuration (source builds): variants are listed in `build/mitsuba.conf`
(generated on first CMake run from `resources/mitsuba.conf.template`), key `"enabled": [...]`.
CMake cache var `MI_DEFAULT_VARIANTS` (comma list) seeds it when no `mitsuba.conf`
exists (default `scalar_rgb,scalar_spectral,cuda_ad_rgb,llvm_ad_rgb,llvm_ad_spectral`;
on macOS `metal_ad_rgb` replaces `cuda_ad_rgb`). Compile time/memory scale with
the number of variants (keep ≤5). Build: `mkdir build && cd build && cmake -GNinja .. && ninja`,
then `source setpath.sh`. Other CMake options: `MI_ENABLE_PYTHON`, `MI_ENABLE_EMBREE`.
See `docs/src/developer_guide/compiling.rst`.

## 3. Scene description

### 3.1 Loading
```python
scene = mi.load_file('scene.xml', spp=64, res=256)   # kwargs replace <default name=...> / $params
obj   = mi.load_string('<bsdf type="diffuse" version="3.0.0"/>')
obj   = mi.load_dict({'type': 'diffuse', 'reflectance': {'type': 'rgb', 'value': [0.2, 0.25, 0.7]}})
scene = mi.load_dict(mi.cornell_box())               # built-in test scene dict (util.py)
```
Signatures (src/core/python/parser.cpp): `load_file(path, parallel=True, optimize=True, **kwargs)`,
`load_string(value, parallel=True, optimize=True, **kwargs)`, `load_dict(dict, parallel=True, optimize=True)`.
Returns a single object or a list when there are several top-level entries.
- `optimize=True` (default) **merges identical plugin instances and merges meshes that share
  a material into one mesh** (log: "Collapsed N into M meshes"). Consequence: per-shape
  parameter keys can disappear (e.g. `a.positions`, `b.positions` become
  `Mesh_0.positions`) (verified). Pass `optimize=False` when you need to address individual meshes
  via `mi.traverse` (shape optimization, per-object edits).
- Unknown/misspelled properties are an **error** ("Found 1 unreferenced property ..."),
  and property types are strict: `'max_depth': 6.0` fails ("expected integer, got float") (verified).

### 3.2 XML format (`docs/src/key_topics/scene_format.rst`)
```xml
<scene version="3.0.0">
    <default name="spp" value="128"/>          <!-- overridable via -Dspp=.. or load_file(spp=..) -->
    <integrator type="path"><integer name="max_depth" value="8"/></integrator>
    <sensor type="perspective">
        <float name="fov" value="45"/>
        <transform name="to_world"><lookat origin="0,0,4" target="0,0,0" up="0,1,0"/></transform>
        <sampler type="independent"><integer name="sample_count" value="$spp"/></sampler>
        <film type="hdrfilm">
            <integer name="width" value="1920"/><integer name="height" value="1080"/>
            <rfilter type="gaussian"/>
        </film>
    </sensor>
    <bsdf type="diffuse" id="mat"><rgb name="reflectance" value="0.8, 0.1, 0.1"/></bsdf>
    <shape type="obj">
        <string name="filename" value="mesh.obj"/>
        <ref id="mat"/>
    </shape>
    <shape type="rectangle">
        <transform name="to_world"><translate value="0, 2, 0"/><scale value="0.5"/></transform>
        <emitter type="area"><rgb name="radiance" value="10"/></emitter>
    </shape>
    <emitter type="envmap"><string name="filename" value="sky.exr"/></emitter>
</scene>
```
- Object tags: `integrator, sensor, film, sampler, rfilter, shape, bsdf, emitter, texture,
  medium, phase, volume, spectrum, postprocess`. Each needs `type="plugin_name"`.
- Property tags: `integer, float, boolean, string, point, vector, rgb, spectrum
  (value="400:0.5, 500:0.8" | value="0.5" | filename="x.spd"), transform, animation, ref`.
- Transforms: `<translate value=".."/>` (or x/y/z attrs), `<rotate x|y|z="1" angle="deg"/>` /
  `<rotate value="axis" angle=".."/>`, `<scale value="s"|"sx,sy,sz"/>`, `<matrix value="16 or 9 numbers, row-major"/>`,
  `<lookat origin target up/>`. Each command is **left-multiplied** onto the current one
  (so listed order = application order).
- `<animation name="to_world"><transform time="0">..</transform><transform time="1">..</transform></animation>`
  for motion blur (3.10; ≥2 keyframes, no shear; Python: `mi.AnimatedTransform4f({0.0: T1, 1.0: T2})`).
- `id`/`<ref id="..."/>` reuse materials/textures/media (not geometry → use `shapegroup` + `instance`).
  `<alias id="a" as="b"/>`, `<include filename="sub.xml"/>`, `<path value="../res"/>` (search path),
  `<import filename="plugins/my_bsdf.py"/>` (3.10: scene-bundled Python plugins; requires
  `python -m mitsuba` or `mi.load_file`, not the C++ binary).
- `$name` substitution must be satisfied by `<default>` or `-D`/kwargs, otherwise load error.

### 3.3 Python dict format
- Every dict needs `"type"`. Keys = property names; values typed by Python type
  (`int`→integer, `float`→float, `bool`, `str`, list/array→point/vector, `mi.ScalarTransform4f`→transform,
  nested dict → child object, existing Mitsuba object → child object).
- Child objects (bsdf, film, sampler, rfilter, emitter ...) can use **any key name** except
  dots; their category is inferred from the plugin. `'film': {...}`, `'myfilm': {...}`, `'filter': {...}` all work.
- Colors: `{'type': 'rgb', 'value': [r,g,b] or scalar}`, `{'type': 'spectrum', 'value': [(400., .5), (500., .8)]}`
  or `'filename'`. A bare float for `reflectance` is also accepted.
- References: give an object `'id': 'my_material'`, then `{'type': 'ref', 'id': 'my_material'}`.
  Implicit IDs = dict path (`my_shape.my_material.reflectance`) — these become `mi.traverse` key prefixes.
  Keys may not contain `.`. Forward refs allowed.
- Search path: `'foo': {'type': 'resources', 'path': '/abs/or/rel'}`. Python ext: `'ext': {'type': 'import', 'filename': 'x.py'}`.
```python
T = mi.ScalarTransform4f
scene = mi.load_dict({
    'type': 'scene',
    'integrator': {'type': 'path', 'max_depth': 8},
    'sensor': {
        'type': 'perspective', 'fov': 45,
        'to_world': T().look_at(origin=[0, -5, 5], target=[0, 0, 0], up=[0, 0, 1]),
        'film': {'type': 'hdrfilm', 'width': 512, 'height': 512, 'rfilter': {'type': 'gaussian'}},
        'sampler': {'type': 'independent', 'sample_count': 64},
    },
    'light': {'type': 'constant', 'radiance': {'type': 'rgb', 'value': 1.0}},
    'sphere': {'type': 'sphere', 'to_world': T().translate([0, 0, 1]).scale(0.5),
               'bsdf': {'type': 'roughconductor', 'material': 'Au', 'alpha': 0.1}},
    'floor': {'type': 'rectangle', 'to_world': T().scale(5),
              'bsdf': {'type': 'diffuse', 'reflectance': {'type': 'bitmap', 'filename': 'tex.png'}}},
})
```

### 3.4 Transforms (src/core/python/transform_v.cpp)
- Since 3.6/3.7 `Transform4f` is split into `AffineTransform{3,4}{f,d}` and
  `ProjectiveTransform{3,4}{f,d}` (+ `Scalar*` versions). Aliases kept:
  `mi.Transform4f = mi.AffineTransform4f`, `mi.ScalarTransform4f = mi.ScalarAffineTransform4f`.
- Builder methods (chain, each **right-multiplies**, i.e. `T().translate(t).scale(s)` = translate∘scale, scale applied first):
  `translate(v)`, `scale(v)`, `rotate(axis, angle_deg)`, `look_at(origin, target, up)`,
  `from_frame(f)`, `to_frame(f)`, `perspective(fov, near, far)` / `orthographic(near, far)` (projective).
  Both `T.translate(...)` and `T().translate(...)` work (3.7+).
- Apply with `@` (not `*`; `*` raises): `T @ point`, `T @ vector`, `T @ normal`, `T @ ray`, `T1 @ T2`.
  `.inverse()`, `.translation()`, `.matrix`.
- Use **`mi.ScalarTransform4f` in scene dicts**; use `mi.Transform4f` (JIT/differentiable) when
  building transforms from optimized variables (e.g. pose estimation).

## 4. Plugin catalog (names as used in `type=`)

| Category | Plugins |
|---|---|
| integrator (C++) | `path` (max_depth, rr_depth, clamp_direct/indirect), `direct` (emitter_samples, bsdf_samples), `volpath`, `volpathmis` (spectral MIS), `ptracer` (particle tracer), `aov` (`aovs="dd:depth,nn:sh_normal,..."` + nested integrator), `depth`, `moment`, `stokes` (polarized) |
| integrator (Python, `src/python/python/ad/integrators/`) | `prb` (Path Replay Backprop, NEE+MIS+RR), `prb_basic` (didactic), `prbvolpath` (volumes), `direct_projective`, `prb_projective` (projective sampling for visibility discontinuities; params `sppc, sppp, sppi, guiding ('none'/'grid'/'octree'), guiding_proj, guiding_rounds`), `volprim_rf_basic` (ellipsoid/Gaussian radiance fields). (Feature branches may add more, e.g. `restirpt*.py`; check `ad/integrators/__init__.py`.) |
| sensor | `perspective` (fov, fov_axis, focal_length, near_clip, far_clip, principal_point_offset_x/y, to_world), `thinlens` (aperture_radius, focus_distance), `orthographic`, `radiancemeter`, `irradiancemeter`, `distant`, `batch` (several sensors side-by-side into one film) |
| film | `hdrfilm` (width, height, file_format, pixel_format, component_format, crop_*, sample_border), `specfilm` (spectral channels) |
| sampler | `independent`, `stratified`, `multijitter`, `orthogonal`, `ldsampler` (sample_count, seed) |
| rfilter | `box`, `tent`, `gaussian` (default of hdrfilm), `mitchell`, `catmullrom`, `lanczos` |
| bsdf | `diffuse`, `dielectric`, `thindielectric`, `roughdielectric`, `conductor`, `roughconductor` (material="Au"/eta,k, alpha/alpha_u/alpha_v, distribution), `plastic`, `roughplastic`, `principled`, `principledthin`, `hair`, `measured`, `measured_polarized`, `pplastic`, `polarizer`, `retarder`, `circular`, adapters: `twosided`, `bumpmap`, `normalmap`, `mask` (opacity), `blendbsdf` (weight), `null` |
| emitter | `area` (on a shape; radiance, `sample_texture`), `point`, `spot`, `projector`, `directional`, `directionalarea`, `constant`, `envmap` (filename, scale), `sunsky`, `timed_sunsky`, `portal` |
| shape | meshes: `obj`, `ply`, `serialized` (legacy), `packed` (3.10 `.packed` container); analytic: `sphere`, `disk`, `rectangle`, `cube`, `cylinder`; curves: `linearcurve`, `bsplinecurve`; `sdfgrid`, `ellipsoids`, `ellipsoidsmesh` (Gaussian splats), `displace`, `shapegroup` + `instance`; `merge` is internal (parser-generated) |
| texture | `bitmap` (filename, filter_type, wrap_mode, `format` ('variant' to keep full precision), raw, to_uv), `checkerboard`, `mesh_attribute`, `volume`, `lut`, `math` (expr) |
| spectrum | `srgb`, `uniform`, `regular`, `irregular`, `blackbody`, `d65`, `rawconstant` |
| medium | `homogeneous`, `heterogeneous` (albedo, sigma_t, scale) — attach via shape `interior`/`exterior` |
| phase | `isotropic`, `hg` (g), `rayleigh`, `sggx`, `tabphase`, `blendphase` |
| volume | `constvolume`, `gridvolume` (.vol file / data) |
| postprocess | Python-only plugins (`mi.register_postprocess`); film runs them in `develop()` |

Shapes/emitters accept `visibility` ∈ {`all`, `primary`, `secondary`, `hidden`} (3.10), which
replaces the deprecated integrator `hide_emitters` (use `visibility: 'secondary'` on an emitter to hide it from the camera).
Parameter lists: docstring at top of each `src/<category>/<plugin>.cpp` / `.py`.

## 5. Rendering

```python
img = mi.render(scene, spp=256)              # mi.TensorXf (H, W, C), linear RGB (+AOV channels)
mi.util.write_bitmap('out.png', img)        # LDR → sRGB-tonemapped uint8; .exr keeps float
mi.util.write_bitmap('out.exr', img)
bmp = mi.Bitmap(img); bmp.write('out.exr')  # Bitmap <-> tensor/numpy: mi.TensorXf(bmp), np.array(bmp)
bmp.convert(mi.Bitmap.PixelFormat.RGB, mi.Struct.Type.UInt8, srgb_gamma=True)
mi.util.convert_to_bitmap(img)              # uint8 sRGB Bitmap (handy in notebooks)
import numpy as np; arr = np.array(img)     # tensors convert to NumPy / PyTorch (dlpack)
```
`mi.render(scene, params=None, sensor=0, integrator=None, seed=0, seed_grad=0, spp=0, spp_grad=0, postprocess=True)`
(`src/python/python/util.py`):
- `sensor`: index or `mi.Sensor` object (can be a sensor loaded separately via `mi.load_dict`).
- `integrator`: override the scene's integrator (e.g. `mi.load_dict({'type': 'prb'})`).
- `spp=0` → use the sampler's `sample_count`. `seed`: **vary per call** (e.g. iteration index) for independent noise.
- `params`: `SceneParameters` for differentiation (see §6). `spp_grad`/`seed_grad`: for the adjoint pass (seed_grad must differ from seed).
- `postprocess=False` returns the raw linear image (skips the film's postprocess filters, e.g. tonemapping that
  some converted scenes attach). Compare means/errors on linear images.
- Lower level: `scene.integrator().render(scene, sensor, seed=0, spp=0, develop=True, evaluate=True)`;
  `film = scene.sensors()[0].film(); film.develop()` → tensor, `film.bitmap()` → Bitmap with channel names,
  `film.write('x.exr')`.
- Very high spp in one launch can overflow sample indices (≈2^32 samples per kernel); accumulate
  several renders with different `seed` instead.
- AOVs: wrap an integrator: `{'type': 'aov', 'aovs': 'dd:depth,nn:sh_normal,pp:position,uv:uv,gn:geo_normal,id:prim_index', 'img': {'type': 'path'}}`
  → channels `R,G,B,(A),dd.T,nn.X,nn.Y,nn.Z,...` concatenated in the last tensor axis (verified: shape (256,256,7)).
- Multi-view: pass different `sensor=` objects, or a `batch` sensor (single JIT trace for all views).
- `scene.sensors()`, `scene.emitters()`, `scene.shapes()`, `scene.integrator()`, `scene.bbox()`, `scene.environment()`.

Command line (`src/mitsuba/mitsuba.cpp`): `mitsuba [options] scene.xml`
- `-m <variant>`, `-o out.exr`, `-D key=value` (fills `$key`), `-s <sensor index>`, `-t <threads>`,
  `-a path1;path2` (search paths), `-v` (verbose, repeatable), `-S` (dump PTX/LLVM IR), `-h`.
- `python -m mitsuba scene.xml` — same options, Python frontend; required for scenes with `<import>`ed Python plugins
  (pip's `mitsuba` command is this frontend).

## 6. Inverse / differentiable rendering

Needs an `_ad` variant. Workflow (`tutorials/inverse_rendering/gradient_based_opt.ipynb`):
```python
import drjit as dr, mitsuba as mi
mi.set_variant('cuda_ad_rgb', 'metal_ad_rgb', 'llvm_ad_rgb')

scene = mi.load_file('cbox.xml', res=128, integrator='prb')
image_ref = mi.render(scene, spp=512)

params = mi.traverse(scene)                 # SceneParameters (dict-like, keys "id.child.param")
key = 'red.reflectance.value'
params[key] = mi.Color3f(0.01, 0.2, 0.9); params.update()

opt = mi.ad.Adam(lr=0.05)                   # = dr.opt.Adam (also SGD, AdamW, RMSProp)
opt[key] = params[key]                      # optimizer holds a COPY with grad enabled
params.update(opt)                          # push optimizer values into the scene

for it in range(50):
    image = mi.render(scene, params, spp=4, seed=it)   # pass params so gradients are tracked
    loss = dr.mean(dr.square(image - image_ref))
    dr.backward(loss)                       # routed to integrator.render_backward
    opt.step()                              # gradient step, zeroes grads
    opt[key] = dr.clip(opt[key], 0.0, 1.0)  # enforce legal range
    params.update(opt)                      # MUST call after every step
```
`SceneParameters` (`util.py`): `print(params)` shows key, flags (`∂` differentiable, `D`
discontinuous — changes visibility), type, owner. Methods: `params[key]`, `params[key] = v`,
`keys()/items()`, `keep(regex_or_list)`, `update(values=None)` (applies pending writes,
calls each owner's `parameters_changed`, rebuilds BVH if geometry changed), `flags(key)`, `owner(key)`, `set_dirty(key)`, `copy()`.
- Writing `params[k] = v` alone does nothing until `params.update()`.
- `params[k]` returns a live view; `dr.copy(params[k])` / `mi.Float(params[k])` to keep a snapshot.
- Typical keys: `<bsdf_id>.reflectance.value` (rgb), `<bsdf>.reflectance.data` (bitmap tensor),
  `<shape>.to_world`, `<emitter>.radiance.value`, `sensor.to_world`, `sensor.x_fov`, `<medium>.sigma_t.data`.
- **3.10 mesh keys** (breaking): `<mesh>.positions` (P,3) TensorXf, `<mesh>.normals` (N,3),
  `<mesh>.texcoords` (V,2), `<mesh>.faces` (F,3) TensorXu, plus `position_index`/`normal_index`
  (old `vertex_positions` flat buffers are gone). Converting for transforms:
  ```python
  v = mi.Point3f(params['bunny.positions'], flip_axes=True)          # SoA view
  params['bunny.positions'] = mi.TensorXf(trafo @ v, flip_axes=True)
  params['teapot.positions'] += mi.TensorXf([[0, 0, 0.5]])          # broadcast row
  params.update()
  ```
  Meshes can be built directly: `mi.Mesh("name", faces=TensorXu(F,3), positions=TensorXf(P,3), normals=..., texcoords=...)`.

Optimizer (Dr.Jit `drjit.opt`, re-exported in `mi.ad`; Mitsuba's own optimizers were removed in 3.7):
`Adam(lr, params=None, *, beta_1=0.9, beta_2=0.999, epsilon=1e-8, mask_updates=False, promote_fp16=True, uniform=False, amsgrad=False)`,
`SGD(lr, params=None, *, momentum=0., nesterov=False, mask_updates=False)`, `AdamW(..., weight_decay=0.01)`, `RMSProp`.
Dict-like; `opt = mi.ad.Adam(lr=.05, params=params)` takes all differentiable entries (filter first with `params.keep(...)`);
`opt.set_learning_rate({'x': .1})`, `opt.reset(key)`, `opt.step()`. Assignment copies (`opt['y'] = y` detaches from `y`).

Latent variables: optimize something else and map it to scene params each iteration:
```python
opt['angle'] = mi.Float(0.25); opt['trans'] = mi.Point2f(0.1, -0.25)
init = mi.Point3f(params['bunny.positions'], flip_axes=True)
def apply(params, opt):
    trafo = mi.Transform4f().translate([opt['trans'].x, opt['trans'].y, 0.0]).rotate([0, 1, 0], opt['angle'] * 100)
    params['bunny.positions'] = mi.TensorXf(trafo @ init, flip_axes=True)
    params.update()
```
`mi.ad.LargeSteps(params['shape.positions'], params['shape.faces'], lambda_)` (needs `cholespy`):
`opt['u'] = ls.to_differential(positions)`; each iter `params['shape.positions'] = ls.from_differential(opt['u'])`
with `mi.ad.Adam(lr=1e-1, uniform=True)` (`tutorials/inverse_rendering/shape_optimization.ipynb`).

Forward-mode (gradient images):
```python
dr.enable_grad(params[key]); params.update()
image = mi.render(scene, params, spp=128)
dr.forward(params[key]); grad_img = dr.grad(image)
# with a latent theta: dr.enable_grad(theta); params[key] = f(theta); params.update();
# dr.forward(theta, dr.ADFlag.ClearEdges); image = mi.render(scene, params); dr.forward_to(image)
```
`mi.render` won't enable gradients for you: either use an optimizer (enables them) or `dr.enable_grad`.

Integrator choice for AD:
- `prb`: default for appearance (BSDF params, textures, emission, volumes via `prbvolpath`). Memory-efficient
  (path replay, O(1) memory in path length). **Ignores visibility discontinuities** → biased gradients for
  geometry/pose/silhouette changes. Detached sampling (can't optimize IOR of specular objects).
- `direct_projective` / `prb_projective`: projective sampling (Zhang et al. 2023) for discontinuities
  (moving shapes, shadows, silhouettes). `sppc` continuous, `sppp` primary-visibility, `sppi` indirect-visibility
  samples; `sppi=0` to skip indirect visibility when cheap is fine. Use for shape/pose optimization.
  Only shapes support silhouette sampling (`silhouette_sampling_weight`). Not supported in polarized variants.
- C++ integrators (`path`, `direct`, ...) are differentiable via naive AD in `_ad` variants — works for tiny
  scenes but records the whole graph; quickly runs out of memory.
- Losses are plain Dr.Jit ops: `dr.mean(dr.square(img - ref))`, `dr.mean(dr.abs(...))`.
- Gradients are noisy MC estimates: use low spp (e.g. 4–16), new `seed` each iteration, clamp parameters,
  keep reference images low-noise. With `mask_updates=True` the optimizer skips state updates for params
  that got no gradient this step.
- Textures from 8-bit images are stored `uint8`/fp16 and are **non-differentiable** (3.9); add `'format': 'variant'`
  (XML `<string name="format" value="variant"/>`) to the bitmap to optimize it.
- PyTorch interop: `@dr.wrap(source='torch', target='drjit')` (see `pytorch_mitsuba_interoperability.ipynb`).
- `@dr.freeze` can freeze a function calling `mi.render` so later calls replay compiled kernels (3.7+).

## 7. Writing plugins in Python

Registration functions (src/render/python/scene_v.cpp): `mi.register_integrator, register_bsdf,
register_emitter, register_sensor, register_sampler, register_texture, register_shape, register_film,
register_postprocess, register_rfilter, register_medium, register_phase` — `(name, constructor)`,
constructor is `lambda props: MyClass(props)` or the class itself. Register at module scope, then use
`'type': name` in dicts/XML. Work best in JIT variants (scalar would run Python per ray).
Packaging: entry point `[project.entry-points.mitsuba]` (`docs/src/developer_guide/distributing_plugins.rst`)
or ship `.py` files with `<import>` in the scene.

Common plugin conventions:
- `__init__(self, props)`: call base `__init__` first (`super().__init__(props)`). Read properties with
  `props.get('name', default)`, `'name' in props`, `props['name']`. Unread properties raise at load time.
- `traverse(self, cb)`: `cb.put('name', value, mi.ParamFlags.Differentiable | NonDifferentiable | Discontinuous)`
  exposes parameters to `mi.traverse`; `parameters_changed(self, keys)` reacts to updates; `to_string(self)`.

### 7.1 Custom SamplingIntegrator (primal only) — verified to match `path` (mean 0.1446 vs 0.1446 on cornell box, llvm_ad_rgb)

Python `SamplingIntegrator.sample(scene, sampler, ray, medium=None, active=True)` must return
`(Spectrum, Bool valid)` (3.9.1+: plain `mi.Ray3f`, no ray differentials; AOVs need a
`sample_channels()` override + `aov_names(self, film=None)` — it is called with a film argument, so a zero-arg override raises `TypeError`).
```python
import drjit as dr
import mitsuba as mi
mi.set_variant('llvm_ad_rgb')

def mis_weight(a, b):
    a2, b2 = dr.square(a), dr.square(b)
    return dr.detach(dr.select(a2 > 0, a2 / (a2 + b2), 0))

class MyPath(mi.SamplingIntegrator):
    def __init__(self, props):
        super().__init__(props)
        self.max_depth = props.get('max_depth', 6)

    @dr.syntax                       # lets Python while/if on JIT values become symbolic loops
    def sample(self, scene, sampler, ray, medium=None, active=True):
        bsdf_ctx = mi.BSDFContext()
        ray = mi.Ray3f(ray)
        L, beta = mi.Spectrum(0.0), mi.Spectrum(1.0)
        depth = mi.UInt32(0)
        active = mi.Bool(active)
        valid = mi.Bool(False)
        prev_si = dr.zeros(mi.SurfaceInteraction3f)
        prev_pdf, prev_delta = mi.Float(1.0), mi.Bool(True)
        ray_mask = mi.UInt32(mi.RayMask.Primary)          # camera rays: Primary; others: Secondary

        while active:
            si = scene.ray_intersect(ray, ray_flags=mi.RayFlags.Default,
                                     coherent=(depth == 0), ray_mask=ray_mask, active=active)
            valid |= (depth == 0) & si.is_valid()

            # Emitter hit by BSDF sampling, MIS-weighted against emitter sampling
            ds = mi.DirectionSample3f(scene, si=si, ref=prev_si, ray_mask=ray_mask)
            w = mis_weight(prev_pdf, scene.pdf_emitter_direction(prev_si, ds, ~prev_delta))
            L += beta * w * ds.emitter.eval(si, active)

            active &= si.is_valid() & (depth + 1 < self.max_depth)
            bsdf = si.bsdf()

            # Next-event estimation (em_weight = Le * visibility / pdf)
            active_em = active & mi.has_flag(bsdf.flags(), mi.BSDFFlags.Smooth)
            ds, em_weight = scene.sample_emitter_direction(
                si, sampler.next_2d(), test_visibility=True, active=active_em)
            active_em &= ds.pdf != 0
            bsdf_val, bsdf_pdf = bsdf.eval_pdf(bsdf_ctx, si, si.to_local(ds.d), active_em)
            w_em = dr.select(ds.delta, 1.0, mis_weight(ds.pdf, bsdf_pdf))
            L[active_em] += beta * w_em * bsdf_val * em_weight

            # BSDF sampling (bsdf_weight = f * cos / pdf)
            bs, bsdf_weight = bsdf.sample(bsdf_ctx, si, sampler.next_1d(), sampler.next_2d(), active)
            beta *= bsdf_weight
            ray = si.spawn_ray(si.to_world(bs.wo))
            prev_si = dr.detach(si)
            prev_pdf = bs.pdf
            prev_delta = mi.has_flag(bs.sampled_type, mi.BSDFFlags.Delta)
            ray_mask[~prev_delta] = mi.RayMask.Secondary
            depth[si.is_valid()] += 1
            active &= dr.any(beta != 0)

        return L, valid

mi.register_integrator('mypath', lambda props: MyPath(props))
scene = mi.load_dict(mi.cornell_box())
img = mi.render(scene, integrator=mi.load_dict({'type': 'mypath', 'max_depth': 6}), spp=256)
```
(Simplifications vs `prb.py`: no Russian roulette, no null-surface crossing handling.)

Key API used (all present in this tree):
- `mi.Ray3f(o, d)`, `si.spawn_ray(d_world)`, `si.spawn_ray_to(p)`; `si.to_local(v)`, `si.to_world(v)`,
  `si.wi` (local), `si.p`, `si.n`, `si.sh_frame`, `si.uv`, `si.t`, `si.is_valid()`, `si.shape`, `si.bsdf()` (no ray arg since 3.9.1),
  `si.emitter(scene, ray_mask=..., active=...)`.
- `scene.ray_intersect(ray)` / `scene.ray_intersect(ray, ray_flags, coherent=False, *, ray_mask=mi.RayMask.Secondary, active=True, reorder=False, reorder_hint=0, reorder_hint_bits=0)`;
  `scene.ray_intersect_preliminary(...)` + `scene.compute_surface_interaction(ray, pi, ray_flags)`;
  `scene.ray_test(ray, coherent, *, ray_mask, active)`; `scene.ray_test_tr` / `ray_intersect_tr` (skip null surfaces, return transmittance);
  `scene.sample_emitter_direction(ref, sample, test_visibility=True, active=True)` → `(DirectionSample3f, Spectrum weight)`;
  `scene.pdf_emitter_direction(ref, ds, active)`, `scene.eval_emitter_direction(ref, ds, active)`, `scene.sample_emitter_ray(...)`,
  `scene.has_null_shapes()`.
  ⚠ 3.10: `ray_mask` is **keyword-only** and only exists on the long overloads. `ray_intersect(ray, ray_flags, coherent, *, ray_mask, active)` and `ray_test(ray, coherent, *, ray_mask, active)` require `coherent` (and `ray_flags`) **positionally**. `scene.ray_test(ray, ray_mask=...)` alone raises "incompatible function arguments" (verified). The short forms are `ray_intersect(ray, active)` and `ray_test(ray, active)`.
- `mi.BSDFContext()`; `bsdf.sample(ctx, si, s1, s2, active)` → `(BSDFSample3f bs, weight)`; `bs.wo, bs.pdf, bs.eta, bs.sampled_type, bs.is_delta(), bs.is_null()`;
  `bsdf.eval(ctx, si, wo, active)` (includes cosine), `bsdf.pdf(...)`, `bsdf.eval_pdf(...)`, `bsdf.flags()`, `bsdf.eval_null(si, active)`;
  `mi.has_flag(flags, mi.BSDFFlags.X)`. Flags: `Null, DiffuseReflection, GlossyReflection, DeltaReflection, ... , Smooth, Delta, All`.
- `mi.RayFlags`: `Minimal, Shading, NormalPartials, Default, FollowShape, DetachShape` (no `All`).
  `mi.RayMask`: `Opaque, Null, Primary, Secondary, All`.
- `sampler.next_1d()`, `sampler.next_2d()`; `mi.Spectrum`, `mi.unpolarized_spectrum(x)`; `mi.warp.square_to_cosine_hemisphere(...)` etc.
- `dr.select`, `dr.detach`, `dr.zeros(Type)`, masked assignment `x[mask] = y`, `dr.hint(cond, max_iterations=..., label=...)`.

### 7.2 Differentiable Python integrators (`src/python/python/ad/integrators/common.py`)
- `ADIntegrator(mi.CppADIntegrator)`: reads `max_depth` (-1 = ∞), `rr_depth`; implements `render`,
  `render_forward`, `render_backward`, `sample_rays`, `prepare`.
- `RBIntegrator(ADIntegrator)`: radiative-backprop / PRB driver. Subclasses implement
  `sample(self, mode, scene, sampler, ray, δL, state_in, active, **kwargs) -> (L_or_δL, valid, aovs_list, state_out)`.
  `mode` is `dr.ADMode.Primal|Forward|Backward`; primal pass runs detached; the differential pass
  re-runs the path with the same seed and uses `with dr.resume_grad(when=not primal):` around differentiable
  evaluations, then `dr.backward_from(δL * Lo)` (backward) or `δL += dr.forward_to(Lo)` (forward).
  Helpers: `mis_weight`, `reattach_wi`, `reattach_wo` (moving-geometry terms, 3.7+).
- `PSIntegrator(ADIntegrator)`: projective-sampling base (`direct_projective`, `prb_projective`).
- Start from `prb_basic.py` (minimal, ~200 lines) → `prb.py` (NEE/MIS/RR) → `prb_projective.py`.

### 7.3 Custom BSDF (`tutorials/others/custom_plugin.ipynb`) — verified: identical mean to `diffuse` on cornell box (0.146962), key `red.tint` appears in traverse
```python
class MyBSDF(mi.BSDF):
    def __init__(self, props):
        mi.BSDF.__init__(self, props)
        self.tint = mi.Color3f(props['tint'])
        flags = mi.BSDFFlags.DiffuseReflection | mi.BSDFFlags.FrontSide
        self.m_components = [flags]; self.m_flags = flags
    def sample(self, ctx, si, sample1, sample2, active):
        bs = mi.BSDFSample3f()
        bs.wo = mi.warp.square_to_cosine_hemisphere(sample2)
        bs.pdf = mi.warp.square_to_cosine_hemisphere_pdf(bs.wo)
        bs.eta = 1.0
        bs.sampled_type = mi.UInt32(+mi.BSDFFlags.DiffuseReflection)
        bs.sampled_component = mi.UInt32(0)
        active &= (mi.Frame3f.cos_theta(si.wi) > 0) & (bs.pdf > 0)
        return bs, dr.select(active, mi.Color3f(self.tint), 0.0)   # weight = f*cos/pdf
    def eval(self, ctx, si, wo, active):
        ok = active & (mi.Frame3f.cos_theta(si.wi) > 0) & (mi.Frame3f.cos_theta(wo) > 0)
        return dr.select(ok, self.tint * dr.inv_pi * mi.Frame3f.cos_theta(wo), 0.0)
    def pdf(self, ctx, si, wo, active):
        return mi.warp.square_to_cosine_hemisphere_pdf(wo)
    def eval_pdf(self, ctx, si, wo, active):
        return self.eval(ctx, si, wo, active), self.pdf(ctx, si, wo, active)
    def traverse(self, cb):
        cb.put('tint', self.tint, mi.ParamFlags.Differentiable)
    def parameters_changed(self, keys): pass
mi.register_bsdf('mybsdf', lambda props: MyBSDF(props))
```
- All BSDF quantities are in the local shading frame (`si.wi`, `wo`); `eval` includes the cosine foreshortening.
- BSDFs advertising `BSDFFlags.Null` must implement `eval_null()` (shadow rays evaluate it in 3.10).
- Phase functions: `sample(ctx, mei, s1, s2, active) -> (wo, weight, pdf)` (see `src/phase/tests/test_trampoline.py`).
- Custom shapes in Python (3.10): subclass `mi.Shape`, implement `ray_intersect_preliminary` etc.; see
  `tutorials/others/custom_shape.ipynb`; call `self.initialize()` at end of ctor if it carries an emitter/sensor.

## 8. Dr.Jit essentials for Mitsuba users

- JIT arrays are lazy: operations build a graph; evaluation happens on `dr.eval(x)`, printing, NumPy conversion,
  indexing to Python scalars, or `dr.schedule`. Call `dr.eval()` strategically (e.g. once per optimization
  iteration on big intermediates) — not inside traced loops; excessive evals = many small kernels.
- Control flow: decorate functions with `@dr.syntax` to write `while`/`if` on JIT masks (replaces `mi.Loop`,
  removed in 3.6). `dr.select` is cheaper for simple value choices; symbolic `if` pays off for expensive branches.
- AD: `dr.enable_grad`, `dr.grad`, `dr.set_grad`, `dr.backward`, `dr.forward`, `dr.backward_from`, `dr.forward_to`,
  `dr.detach`, `dr.suspend_grad()` / `dr.resume_grad()` contexts, `dr.replace_grad`, `dr.ADFlag.ClearEdges`.
- Renames (porting): `dr.clamp`→`dr.clip`, `dr.sqr`→`dr.square`, `dr.wrap_ad`→`dr.wrap`, `ek.hsum`→`dr.sum`,
  `ek.hmax`→`dr.max`, `ek.max`→`dr.maximum`, `ek.zero`→`dr.zeros`; constants snake_case (`dr.pi`, `dr.inv_pi`).
  Since 3.9.1 (Dr.Jit 1.5) `dr.minimum/maximum/clip` **propagate NaNs**; use `dr.fmin/dr.fmax` to sanitize.
- Reductions on tensors (`dr.mean(t)`, `dr.sum(t)`) reduce over all elements (verified; `axis=` available, NumPy-like).
- Struct-of-arrays: `mi.Point3f` is 3 JIT arrays; `dr.ravel`/`dr.unravel` convert flat buffers;
  `mi.Point3f(tensor, flip_axes=True)` / `mi.TensorXf(point, flip_axes=True)` convert (P,3) tensors.
- `dr.opaque(...)` avoids baking constants into kernels (less recompilation); `dr.set_flag(dr.JitFlag.KernelHistory, True)` + `dr.kernel_history()` for profiling;
  `dr.JitFlag.ShaderExecutionReordering` toggles SER (CUDA); `dr.JitFlag.SymbolicLoops/SymbolicCalls` for debugging (evaluated mode);
  `dr.JitFlag.Debug`; `dr.print(...)` prints inside symbolic code. `dr.flush_malloc_cache()`, `dr.sync_thread()`.
- `mi.set_log_level(mi.LogLevel.Warn)` to silence Info/Debug logs.

## 9. Practical tips and pitfalls

1. Set the variant first; prefer `cuda_ad_rgb` (NVIDIA), `metal_ad_rgb` (Apple), `llvm_ad_rgb` (CPU). `scalar_*` is for
   debugging/one-off renders; Python plugins in scalar mode are very slow.
2. `mi.ScalarTransform4f` for scene construction; `mi.Transform4f` for differentiable/vectorized transforms. Use `@`, not `*`.
3. After any `params[...] = ...`, call `params.update()` (or `params.update(opt)`). Forgetting it = scene unchanged / stale BVH.
4. Pass `params` to `mi.render` for differentiation and use a fresh `seed` each iteration; use `spp_grad`/`seed_grad` to tune the adjoint pass.
5. Use `prb` for appearance; `direct_projective`/`prb_projective` when visibility changes (geometry, pose, shadows). Plain `path` in AD mode = memory blow-up.
6. Mesh merging: `load_dict/load_file(..., optimize=False)` to keep individual mesh keys.
7. 3.10 breaking changes to watch in old code: mesh params (`vertex_positions`→`positions` tensors), `mi.Mesh(...)` constructor,
   method renames (`vertex_positions_buffer()`→`positions()`, `faces_buffer()`→`faces()`, `has_vertex_normals()`→`has_normals()`,
   `recompute_vertex_normals()`→`recompute_normals()`, `write_serialized()`→`write_packed()`), keyword-only `ray_mask`,
   `mi.quad`→`dr.quad` (`dr.quad.gauss_legendre(mi.Float, n)`), point emitter `position` no longer traversable (use `to_world`),
   textured area emitters uniformly sampled unless `sample_texture`.
   3.9.1: `RayDifferential3f`, `sample_ray_differential`, `si.duv_dx/duv_dy`, `BSDFFlags.NeedsDifferentials` removed; `si.bsdf()` takes no ray.
   3.9: 8-bit bitmaps stay uint8 (non-differentiable; `format='variant'`), Metal backend.
   3.7: Mitsuba optimizers → `drjit.opt` aliases; `Transform4f` split into affine/projective; SER via `reorder=`; `@dr.freeze`.
   3.6 (`docs/porting_3_6.rst`): Dr.Jit 1.0 — `mi.Loop` removed (use `@dr.syntax` / `dr.while_loop`), symbolic `if` via `dr.syntax`/`dr.if_stmt`,
   bitmap textures default to half precision for ≤16-bit data (`format='variant'` to opt out), C++: `dr::eq/neq` removed (`==` is elementwise; use `dr::all`),
   `dr::Matrix` row-major, `dr::set_attr` gone (`DRJIT_CALL_GETTER`), LLVM ≥ 11 (README now says ≥18).
8. Emitters: area lights must be nested in a shape; envmap/constant are top-level; to hide a light from the camera use
   `visibility: 'secondary'` (not `hide_emitters`, deprecated).
9. Images are linear; `.png/.jpg` writes tonemap to sRGB 8-bit; `.exr` keeps HDR. `mi.render` returns (H, W, C) tensor; index channels `img[..., :3]`.
   Films may carry postprocess filters (e.g. tonemapping in converted Blender scenes): use `postprocess=False` for linear comparisons.
10. GPU: CUDA variants need NVIDIA driver ≥ 535 (OptiX 8 ABI, OptiX ships with the driver); no separate OptiX SDK install for users.
    WSL2 needs the manual driver-file copy in `docs/src/optix_setup.rst` (and is slower). LLVM variant needs a discoverable `libLLVM` (≥18); set `DRJIT_LIBLLVM_PATH` if not found.
11. Memory: GPU kernels keep all live JIT arrays; delete large tensors (`del img`), avoid accumulating graphs across iterations
    (e.g. `errors.append(dr.slice(err))` / `loss.array[0]` instead of keeping AD-attached values), reduce spp or resolution,
    render in passes. Naive AD of long paths is the main OOM cause.
12. Property strictness: misspelled keys or wrong numeric type (int vs float) raise at load; inspect the plugin docstring.
13. Polarized variants: `prb`, `direct_projective`, `prb_projective` are not supported; use `stokes` integrator for Stokes AOVs.
14. Debug tips: `print(obj)` shows plugin state; `print(params)` lists traversable keys; switch to `scalar_rgb`/`_double` to rule out JIT/precision issues;
    `mitsuba -S` / `dr.JitFlag.PrintIR` dumps IR.

## 10. Example scenes in the tree
- `resources/data/scenes/`: `hello.xml`, `cbox/{cbox.xml, cbox-rgb.xml, cbox-spectral.xml}`, `matpreview/matpreview.xml`.
- `tutorials/scenes/`: `cbox.xml` (defaults spp/res/max_depth/integrator; BSDF ids `gray, white, green, red, box`... → keys like `red.reflectance.value`),
  `simple.xml`, `cbox_pol.xml`, `polarizers.xml`, `shadow_art.xml` (curve + projective tutorial), `lego/`, `meshes/`, `textures/`, `volume.vol`, `references/`.
- `mi.cornell_box()` returns a ready dict (keys: `integrator`, `sensor` (film 256x256, gaussian), `white`, `green`, `red` (BSDFs), `light`, `floor`, `ceiling`, `back`, `green-wall`, `red-wall`, `small-box`, `large-box`). Replace e.g. `d['red'] = {...}` to swap a material.

## 11. Tutorials index (`tutorials/`, mirrored in `docs/src/`)
- quickstart: `mitsuba_quickstart`, `drjit_quickstart`
- rendering: `editing_a_scene` (traverse/update), `multi_view_rendering`, `polarized_rendering`, `scripting_renderer` (custom ray tracing in Python)
- inverse_rendering: `gradient_based_opt`, `forward_inverse_rendering`, `caustics_optimization`, `object_pose_estimation`,
  `projective_sampling_integrators`, `volume_optimization`, `shape_optimization`, `radiance_field_reconstruction`,
  `polarizer_optimization`, `pytorch_mitsuba_interoperability`
- others: `custom_plugin` (BSDF), `custom_shape` (Python shape, Mandelbulb), `bsdf_deep_dive`, `granular_phase_function`
- how_to_guides: `image_io_and_manipulation`, `mesh_io_and_manipulation`, `transformation_toolbox`, `use_optimizers`
