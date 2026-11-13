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
- A pump is a down-and-up S-turn (`_pump_accel`), as real surfers pump. Hold: drive (`PUMP_DRIVE`) points the nose down the face, capped by `DRIVE_ANGLE` and `DROP_RATE` (face heights/s, so the drop is the same share of the face on any size wave). The leg stroke (`PUSH_STROKE`) runs out if held too long: the board flattens onto the steered line where it is and `OVERHOLD_DRAG` bogs it. Release: the turn off the bottom adds the speed (`PUMP_KICK` x quality x trigger force, over `KICK_TIME`), then the rise (`PUMP_RISE`) carves back up to `rise_target_t`: the pump's starting line (`pump_line_t`) for a normal pump, less the longer you held past the stroke, and none after `SETTLE_TIME` (you chose the lower line). Pumping in a rhythm without steering (next press mid-rise or within `LINE_MEMORY`) keeps the same line, so small rise overshoots don't add up; steering or a pause picks a new one. A hold under `MIN_DRIVE` is only a flick. Drives can't start closer than `MIN_PUMP_INTERVAL` apart (presses sooner are ignored; a key still held starts the drive when it's up), and the pump after an ignored press scores `PUMP_MIN_QUALITY` (`_fumbled`): mashing must never beat a real rhythm. All of this moves the board through `pump_pitch`, added on top of the steered `phi`; physics and drawing use `heading()`.
- Never let the pump walk the surfer down the face: each normal cycle must come back to its line (`test_pump` checks this). A long hold settles on a lower line and must stay there, neither creeping nor snapping back up (`test_controls`).
- Nothing moves the surfer up or down the face except heading (steering + pump). There is no drift toward the lip: with no input the board trims across at its height (`test_controls`).
- Quality is technique, scored at the bottom turn (`_score_pump`): drive start height (`PUMP_ZONE`), drive length (`GOOD_DRIVE`) and rhythm. The range is `PUMP_MIN_QUALITY` (1/3) to 1.0, so a perfect pump is 3x a sloppy one. `quality_override` pins it in tests.
- Pumping is the main source of speed: `WAVE_PUSH` alone can't keep up with the curl (no pumping gets caught in about 20 s).
- No guardrails on the face. `t` can go below 0: the flat water in front of the trough (`face_up` is level and `slope_at` is 0 there, CPU-only), counted in face run-outs (`lf_at`). Past `FLATS_OUT` the ride ends ("Rode off the front of the wave"). Never clamp `t` at the trough.
- Heading is `phi` measured from `facing` (+1 down the line, -1 back at the curl), + up the face, so gravity, pumping and the lip work the same either way; `x` moves by `facing * cos(heading())`. Normal carving is capped at `MAX_PHI`; a turn-around (`_start_turn` / `_swing`) runs `phi` out to vertical, flips `facing`, and comes back past level by `CUTBACK_EXIT`. During it vertical motion and gravity are scaled by `CUTBACK_LIFT` and `CARVE_DRAG` bleeds speed.
- Cutback controls: ← (stall/spin_left) with ↑/↓ turns you to face the curl (the arc follows the carve: up and over, or low); → with ↑/↓ turns you back. ← alone is still the stall, and the combo never stalls. main.gd passes this as `step()`'s `side` input; riders can provide `side()`.
- Whitewater (`d < 0`): only survivable while rebounding. Facing back into it starts a rebound turn (up into the foam, or low if you hit it above mid-face); the foam holds you `FOAM_HOLD` behind the curl, stops you while facing back (`FOAM_DRAG`), and throws you out at `FOAM_SPEED` once around. Otherwise it's a wipeout, or after `FOAM_MAX` you're buried. Scores "Cutback" / "Roundhouse Cutback" (`_check_cutback`).
- The stall is physical drag on the tail: decel = `STALL_DRAG * tail_dig * v²`. Never use a flat speed penalty.
- `test_pump` locks in the balance: no pumping gets caught, sloppy pumping lasts longer, good pumping makes every wave and is clearly faster, mashing is capped and slower than a real rhythm, one pump is worth 3x from perfect to sloppy and returns you to your line, and the stall scales with v². To see the numbers after retuning, run `godot --headless --fixed-fps 60 --path . -s res://tests/test_pump.gd -- --report`.

## Tests
`tests/run_tests.sh` runs everything (under a minute). Run it before every push. GitHub Actions isn't enabled on this repo, so `.github/workflows/tests.yml` doesn't run. It needs `godot` on PATH (or `GODOT=...`), plus `xvfb-run` when there is no display. On macOS, run it with `DISPLAY=:0` set so the GPU parity test uses the real display; the runner falls back to perl when GNU `timeout` is missing.
- `test_wave_parity`: GPU vs CPU wave shape, and uniform coverage.
- `test_wave_model`: `face_up` and `slope_at` agree with `face_point`.
- `test_smoke`: the main scene rides for 5 s of game time on autopilot. The runner fails on any script error.
- `test_controls`: scripted input through the real actions. Holding up through an air doesn't spin you, restart needs a hold mid-ride, carve-down never pumps, hold-then-release drives then rises (a tap is only a flick), a long hold settles on a lower line without snapping back, no input holds height, holding down rides out in front and off the wave, ← alone stalls, ←+↑ cuts back toward the barrel and →+↑ returns (scores a Cutback), and a low cutback rebounds off the whitewater.
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
