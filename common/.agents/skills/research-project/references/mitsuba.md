# Mitsuba and Dr.Jit projects

Read this before writing integrators, scenes, or other Mitsuba plugins in a
project.

A rendering method is a Mitsuba plugin, so it works everywhere a built-in one
works: in a scene file, with `mi.render`, with the `mi.ad` machinery, and next
to the built-in baselines. The project also builds the same objects from Hydra
configs. Both paths construct the same class with the same arguments.

## Integrators: two constructors

Give each integrator two constructors, one calling the other:

- **`__init__` with the direct signature**: typed keyword arguments with
  defaults, which is what Hydra's `_target_` calls.
- **`from_props(props)`**: reads the same arguments from `mi.Properties` and
  calls `__init__`. This is what `mi.register_integrator` calls when a scene or
  `mi.load_dict` names the plugin.

`__init__` builds a `mi.Properties` from its arguments for the base class, so
the base class sees the same settings on both paths. The argument names, their
defaults, and the plugin's property names are the same.

```python
# rendering/integrators.py
import drjit as dr
import mitsuba as mi


class AmbientOcclusion(mi.SamplingIntegrator):
    """Ambient occlusion: the fraction of cosine-weighted directions not blocked within max_distance."""

    def __init__(self, max_distance: float = 1.0, hide_emitters: bool = False):
        props = mi.Properties("ambient_occlusion")
        props["hide_emitters"] = hide_emitters
        super().__init__(props)
        self.max_distance = max_distance

    @classmethod
    def from_props(cls, props: mi.Properties) -> "AmbientOcclusion":
        return cls(max_distance=props.get("max_distance", 1.0),
                   hide_emitters=props.get("hide_emitters", False))

    def sample(self, scene, sampler, ray, medium=None, active=True):
        si = scene.ray_intersect(ray, active)
        hit = active & si.is_valid()
        direction = si.sh_frame.to_world(mi.warp.square_to_cosine_hemisphere(sampler.next_2d(hit)))
        shadow = si.spawn_ray(direction)
        shadow.maxt = self.max_distance
        blocked = scene.ray_test(shadow, hit)
        value = dr.select(hit, dr.select(blocked, 0.0, 1.0), 1.0)  # background counts as open
        return mi.Spectrum(value), active, []

    def to_string(self) -> str:
        return f"AmbientOcclusion[max_distance={self.max_distance}]"


mi.register_integrator("ambient_occlusion", AmbientOcclusion.from_props)
```

A config builds it directly:

```yaml
# configs/experiment/ao.yaml
# Use to compare ambient occlusion against the path tracer on the project's scenes.
_target_: experiments.render.RenderComparison
scene:
  _target_: scenes.cornell_box
  resolution: 256
integrator:
  _target_: rendering.integrators.AmbientOcclusion
  max_distance: 0.3
spp: 64
```

A scene description builds it by name, once the module is imported:

```python
import rendering.integrators  # registers the plugins
integrator = mi.load_dict({"type": "ambient_occlusion", "max_distance": 0.3})
```

Rules that keep the two paths identical:

- **Set the variant first.** The entry point calls `mi.set_variant` from the
  config (`mitsuba.variant: cuda_ad_rgb`) before `instantiate`, because Hydra
  builds nested objects first, and plugins cannot be created without a variant.
- **Register at import.** Each module registers its plugins at import, and the
  entry point imports the modules that hold them.
- **Keep the classes small.** A differentiable method subclasses the `mi.ad`
  integrator base it extends, such as `RBIntegrator` for radiative
  backpropagation, with the same two constructors. Do not wrap an integrator in
  a project class that hides it from Mitsuba.
- **Configure baselines the same way.** A built-in integrator used as a
  baseline is configured through a small factory with the same shape
  (`rendering.baselines.path(max_depth=8)` returning
  `mi.load_dict({"type": "path", ...})`), so every method in a comparison is
  set the same way.

## Scenes: constructor functions

Scenes are built by project functions, not loaded ad hoc inside experiments:

- **One function per scene or scene family.** It takes the settings that
  matter as keyword arguments (resolution, sample count, materials, a
  parameter being studied) and returns a `mi.Scene`. Name it for its
  content, for example `cornell_box` or `glossy_spheres`.
- **Build from a dictionary.** Assemble the scene with `mi.load_dict`, starting
  from `mi.cornell_box()` or another dictionary. A scene stored as a file is
  loaded with `mi.load_file(path, **parameters)` inside such a function, so it
  is configured the same way.
- **Leave the integrator out.** The experiment passes it to `mi.render(scene,
  integrator=..., spp=...)`, so the same scene serves every method.
- **Select scenes in the config.** Choose them with `_target_` in the
  experiment config. A list of scenes is a list of such entries, so a study over
  scenes is a config change.

```python
# scenes/__init__.py
import mitsuba as mi


def cornell_box(resolution: int = 256, light_scale: float = 1.0) -> mi.Scene:
    """The standard Cornell box, square film; light_scale multiplies the area light."""
    scene = mi.cornell_box()
    scene.pop("integrator", None)
    film = scene["sensor"]["film"]
    film["width"] = film["height"] = resolution
    scene["light"]["emitter"]["radiance"]["value"] = [v * light_scale for v in (18.387, 13.9873, 6.75357)]
    return mi.load_dict(scene)
```

Differentiable scene parameters are reached through `mi.traverse(scene)` with
the parameter keys Mitsuba reports, not through copies kept beside the scene.
