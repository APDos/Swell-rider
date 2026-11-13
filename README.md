# Swell Rider (prototype)

Side-view wave riding in Godot 4.3+. Everything (wave, surfer, HUD) is built in code, so there are no assets to import.

## Run
1. Install Godot 4.3 or newer (standard build, not .NET).
2. In the Project Manager, click Import and pick `project.godot` in this folder.
3. Press F5.

## Controls
| Keyboard | Gamepad | Action |
|---|---|---|
| ↑ / W | Left stick up, D-pad up | Rise up the face, toward the lip |
| ↓ / S (hold) | Left stick down, D-pad down | Pump: drive the board down the face. See below |
| ← / A (hold) | Left stick left, D-pad left | Stall: weight on the tail, which digs in and brakes. The faster you're going, the harder it brakes |
| ← / → (or ↑ / ↓) in the air | Left stick, D-pad | Spin. Land within about 40° of a full rotation or you wipe out. Keys held through takeoff don't spin you until you let go of them |
| Hold R (or Enter) | Hold Start | Restart mid-ride. After a wipeout, tap R, Enter or Space to paddle back out |
| Esc | Back | Quit |

Turns build up and ease off, and when you let go the surfer slowly straightens out. Holding ↓ settles into a driving angle down the face rather than nose-diving. Bindings are set up in `scripts/controls.gd`. Defining an action of the same name under Project Settings > Input Map overrides it.

## How it plays
- The break peels down the line at about 9 m/s. If the curl catches you, you wipe out.
- **Pumping is how you keep up.** The wave alone won't carry you: without pumping, the curl catches you within about 20 seconds. Rise up the face with ↑, then hold ↓ to drive back down. Each push gives speed while you're heading down the steep part of the face, until your legs are fully extended (about half a second of driving). Then let go and rise again. Holding on longer just carries you into the flats, where you bog down.
- **Pump quality** is shown after each push ("Pump", "Good pump", "Perfect pump"). A perfect pump gives 3x the speed of a sloppy one. To get one:
  - start the push high on the face
  - actually rise up the face since your last push (tapping in place doesn't work)
  - keep a steady rhythm, roughly a pump every 1 to 2 seconds
- **Stall** (hold ←) to sit deeper in the pocket or wait for the barrel. The tail digs in, and the drag grows with your speed squared: a stall at full speed brakes hard, a stall when you're slow barely does anything. Stall too long and you lose the wave.
- Points come from speed, multiplied by how close you are to the pocket (up to x3).
- **Off the Lip**: hit the top fast at a moderate angle. **Air**: hit the top fast and steep (heading > ~35°, speed > ~32 km/h). You'll need to pump up that speed first.
- **Barrel**: stay mid-face just ahead of the curl where the lip is pitching. When the lip covers you, your surfer glows through the water, going from cyan to gold as you get deeper. A depth meter shows the same thing. Deeper barrels score more per second.
- **Closeout sections**: a steep section appears ahead ("Section ahead — pump for speed!"). The curl races through it at 28 m/s, so you need to have pumped your way past it before the curl gets there.

## Code map
- `scripts/wave.gd` + `shaders/wave_shape.gdshaderinc`: the wave shape. The vertex shader (`shaders/wave.gdshader`) builds the wave and lip from a flat grid using the functions in the include. `wave.gd` has a CPU copy of those functions to keep the surfer on the face. The tuning values live only in `wave.gd`'s `SHAPE` table and are pushed to the shader as uniforms. **If you change a formula in one copy, change it in the other and run the tests.** The parity test will catch a mismatch.
- `scripts/surfer.gd`: face-space physics (x along the line, t up the face, speed, heading), plus airs and wipeouts. The tuning constants are at the top.
- `scripts/main.gd`: curl and closeout scheduling, scoring, camera, environment. Gameplay runs in `_physics_process` at a fixed 60 ticks per second; drawing runs in `_process`, blended between ticks.
- `scripts/controls.gd`: input actions and default keyboard and gamepad bindings.
- `scripts/autopilot.gd`: a scripted rider that pumps in rhythm. Used by `--autopilot` and by the tests.
- `scripts/hud.gd`: on-screen UI.

## Tests
Run `tests/run_tests.sh` (needs `godot` 4.3+ on PATH, plus `xvfb-run` on a machine without a display). CI runs it on every push.

## Dev flags
`godot --path . -- --autopilot` rides by itself. Add `--shot=/tmp/s.png` to save screenshots, or `--barreltest` to hold the curl just behind the surfer so you can tune the barrel.
