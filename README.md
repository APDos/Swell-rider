# Swell Rider (prototype)

Side-view wave riding in Godot 4.3+. Everything (wave, surfer, HUD) is built in code, so there are no assets to import.

## Run
1. Install Godot 4.3 or newer (standard build, not .NET).
2. In the Project Manager, click Import and pick `project.godot` in this folder.
3. Press F5.

## Controls
| Keyboard | Gamepad | Action |
|---|---|---|
| ↑ / W | Left stick up, D-pad up | Carve up the face, toward the lip |
| ↓ / S | Left stick down, D-pad down | Carve down, toward the trough |
| Space | A | Pump (tap it mid-face for speed; it has a cooldown) |
| ← / → (or ↑ / ↓) in the air | Left stick, D-pad | Spin. Land within about 40° of a full rotation or you wipe out. A carve key held through takeoff doesn't spin you until you let go of it |
| Hold R (or Enter) | Hold Start | Restart mid-ride. After a wipeout, a tap of R, Enter or Space paddles back out |
| Esc | Back | Quit |

Turns build up and ease off, and when you let go of the stick the surfer slowly straightens out. Bindings are set up in `scripts/controls.gd`. Defining an action of the same name under Project Settings > Input Map overrides it.

## How it plays
- The break peels down the line at about 9 m/s. If the curl catches you, you wipe out.
- Points come from speed, multiplied by how close you are to the pocket (up to x3).
- **Off the Lip**: hit the top fast at a moderate angle. **Air**: hit the top fast and steep (heading > ~35°, speed > ~32 km/h).
- **Barrel**: stay mid-face just ahead of the curl where the lip is pitching. When the lip covers you, your surfer glows through the water, going from cyan to gold as you get deeper. A depth meter shows the same thing. Deeper barrels score more per second.
- **Closeout sections**: a steep section appears ahead ("Section ahead"). The curl races through it at 28 m/s, so you need to be past it before the curl gets there.

## Code map
- `scripts/wave.gd` + `shaders/wave_shape.gdshaderinc`: the wave shape. The vertex shader (`shaders/wave.gdshader`) builds the wave and lip from a flat grid using the functions in the include. `wave.gd` has a CPU copy of those functions to keep the surfer on the face. The tuning values live only in `wave.gd`'s `SHAPE` table and are pushed to the shader as uniforms. **If you change a formula in one copy, change it in the other and run the tests.** The parity test will catch a mismatch.
- `scripts/surfer.gd`: face-space physics (x along the line, t up the face, speed, heading), plus airs and wipeouts. The tuning constants are at the top.
- `scripts/main.gd`: curl and closeout scheduling, scoring, camera, environment. Gameplay runs in `_physics_process` at a fixed 60 ticks per second; drawing runs in `_process`, blended between ticks.
- `scripts/controls.gd`: input actions and default keyboard and gamepad bindings.
- `scripts/hud.gd`: on-screen UI.

## Tests
Run `tests/run_tests.sh` (needs `godot` 4.3+ on PATH, plus `xvfb-run` on a machine without a display). CI runs it on every push.

## Dev flags
`godot --path . -- --autopilot` rides by itself. Add `--shot=/tmp/s.png` to save screenshots, or `--barreltest` to hold the curl just behind the surfer so you can tune the barrel.
