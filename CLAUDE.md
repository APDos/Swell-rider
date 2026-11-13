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

## Pumping and stalling (surfer.gd)
Design goals: easy to pick up, hard to master, and it should feel right to real surfers.
- Steering (carve up/down) only picks the line. The pump is its own input (the `pump` action, analog on a trigger). Never tie the pump to the carve keys: carving up is how you head for the lip and airs.
- A pump is a lift then a push (`_pump_accel`). Press: the nose lifts for `LIFT_TIME`. Keep holding: the push drives down (`PUMP_POWER`), spending the leg stroke (`PUSH_STROKE`) while heading down the steep part. Holding past the stroke adds `OVERHOLD_DRAG`. The lift and push move the board through `pump_pitch`, which is added on top of the steered `phi`. Physics and drawing use `heading()`, which is the two combined.
- Force comes from how long and how hard the key is held. Quality is technique, scored at push start (`_score_pump`): height on the face (`PUMP_ZONE`) and rhythm. The range is `PUMP_MIN_QUALITY` (1/3) to 1.0, so a perfect pump is 3x a sloppy one.
- Pumping is the main source of speed: `WAVE_PUSH` alone can't keep up with the curl.
- The stall is physical drag on the tail: decel = `STALL_DRAG * tail_dig * v²`. Never use a flat speed penalty.
- `test_pump` locks in the balance: no pumping gets caught, sloppy pumping lasts longer, good pumping makes every wave and is clearly faster, pump power is 3x, and the stall scales with v². To see the numbers after retuning, run `godot --headless --fixed-fps 60 --path . -s res://tests/test_pump.gd -- --report`.

## Tests
`tests/run_tests.sh` runs everything (under a minute). Run it before every push. GitHub Actions isn't enabled on this repo, so `.github/workflows/tests.yml` doesn't run. It needs `godot` on PATH (or `GODOT=...`), plus `xvfb-run` when there is no display.
- `test_wave_parity`: GPU vs CPU wave shape, and uniform coverage.
- `test_wave_model`: `face_up` and `slope_at` agree with `face_point`.
- `test_smoke`: the main scene rides for 5 s of game time on autopilot. The runner fails on any script error.
- `test_controls`: scripted input through the real actions. Holding up through an air doesn't spin you, restart needs a hold mid-ride, carve-down never pumps, and the pump key lifts then pushes (a tap during the lift is only a flick).
- `test_framerate`: the same 5 s ride ends in exactly the same state at 30, 60 and 144 fps.
- `test_pump`: scripted riders on the real game loop check the pump and stall balance (see above).
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
