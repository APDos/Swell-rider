# Swell Rider

A side-view surfing game prototype in Godot 4.3+ (GDScript). The world is built entirely in code; `main.tscn` is only a root node with a script attached.

## Key invariant: the wave shape
The GPU draws the wave and gameplay needs the same shape on the CPU, so the rideable-face math is written twice:
- `shaders/wave_shape.gdshaderinc` is the GPU copy, included by `wave.gdshader`.
- The "shape model" section of `scripts/wave.gd` is the CPU copy. Its functions have the same names as the shader's.

Rules:
- **Tuning values live only in the `SHAPE` table in `wave.gd`.** `apply_to()` pushes them into the shader as uniforms. Never put a shape number in the shader: its shape uniforms deliberately have no defaults.
- **Change a formula in both copies**, then run `tests/run_tests.sh`. `test_wave_parity` runs the shader functions on the GPU and checks them against `wave.gd`. It also fails if a shape uniform and a `SHAPE` key don't match up.
- Visual-only shape (the back of the wave, the lip curtain, whitewater) stays in `wave.gdshader` and needs no CPU copy. If gameplay ever starts depending on it, move it into the include and mirror it.

## Game loop and input
- Gameplay (input, surfer physics, curl, scoring) runs only in `_physics_process`, at a fixed 60 ticks per second. Never put gameplay in `_process`: `test_framerate` fails if a ride differs between 30, 60 and 144 fps.
- `_process` only draws. `surfer.update_visual()` and the wave's drawn curl blend between the previous and current tick (`Engine.get_physics_interpolation_fraction()`). Anything visual that follows the surfer should use `surfer.vis_x`, not `surfer.x`.
- When state jumps (reset, landing), update the `_p_*` snapshots in `surfer.gd` too, or the next frame blends across the jump.
- Read input through the action names in `scripts/controls.gd` (`carve_up`, `pump`, ...), never raw keys.

## Tests
`tests/run_tests.sh` runs everything (about 15 seconds). Run it before every push. GitHub Actions isn't enabled on this repo, so `.github/workflows/tests.yml` doesn't run. It needs `godot` on PATH (or `GODOT=...`), plus `xvfb-run` when there is no display.
- `test_wave_parity`: GPU vs CPU wave shape, and uniform coverage.
- `test_wave_model`: `face_up` and `slope_at` agree with `face_point`.
- `test_smoke`: the main scene rides for 5 s of game time on autopilot. The runner fails on any script error.
- `test_controls`: scripted input through the real actions (holding up through an air doesn't spin you; restart needs a hold mid-ride).
- `test_framerate`: the same 5 s ride ends in exactly the same state at 30, 60 and 144 fps.
- The `mesh_get_surface_count` errors in headless runs come from Godot's dummy renderer and are harmless.

## Coordinates
- +X is down the line (the surfer rides right), +Y is up, +Z is toward shore (where the camera sits).
- Face parameter `t` runs from 0 (trough) to 1 (lip).
- Heading `phi` is positive when angled up the face.

## Testing without a person
- Parse check: `godot --headless --path . --import`
- Rendered screenshots: `xvfb-run godot --rendering-driver opengl3 --path . -- --autopilot --shot=/tmp/s.png`. This writes s_0, s_1 and s_2 at roughly 2.5s, 6s and 12s.
- Add `--barreltest` to hold the curl just behind the surfer so the barrel can be checked.

## Status
v0.2. Not yet tuned by hand; the tuning constants are at the top of `surfer.gd` and `main.gd`.
