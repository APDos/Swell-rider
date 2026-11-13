# Swell Rider (prototype)

Side-view wave riding in Godot 4.3+. Everything (wave, surfer, HUD) is built in code, so there are no assets to import.

## Run
1. Install Godot 4.3 or newer (standard build, not .NET).
2. In the Project Manager, click Import and pick `project.godot` in this folder.
3. Press F5.

## Controls
| Keyboard | Gamepad | Action |
|---|---|---|
| ↑ / W | Left stick up, D-pad up | Carve up the face, toward the lip (for off-the-lips and airs) |
| ↓ / S | Left stick down, D-pad down | Carve down the face, toward the trough. Keep going and you ride out onto the flat water in front of the wave |
| Space | Right trigger (analog), A | Pump: hold to drive down the face, release to turn off the bottom and carve back up. See below |
| ← / A (hold) | Left stick left, D-pad left | Stall: weight on the tail, which digs in and brakes. The faster you're going, the harder it brakes |
| ← + ↑ or ← + ↓ | Stick up-left / down-left | Cutback: swing the board around (up and over with ↑, low with ↓) until it points back at the barrel |
| → + ↑ or → + ↓ | Stick up-right / down-right | When facing the barrel: swing back around down the line |
| ← / → (or ↑ / ↓) in the air | Left stick, D-pad | Spin. Land within about 40° of a full rotation or you wipe out. Keys held through takeoff don't spin you until you let go of them |
| Hold R (or Enter) | Hold Start | Restart mid-ride. After a wipeout, tap R, Enter or Space to paddle back out |
| Esc | Back | Quit |

↑/↓ only choose your line. The pump is a separate move on top of that line. Turns build up and ease off, and when you let go the surfer slowly straightens out. Bindings are set up in `scripts/controls.gd`. Defining an action of the same name under Project Settings > Input Map overrides it.

## How it plays
- The break peels down the line at about 9 m/s. If the curl catches you, you wipe out.
- **Pumping is how you keep up.** The wave alone won't carry you: without pumping, the curl catches you within about 20 seconds. One pump is a small down-and-up S-turn high on the face, the way surfers pump down the line:
  1. Hold Space: drive. The nose drops down the face and you compress, trading a bit of height for speed.
  2. Release: you turn off the bottom of that drop. That's where the pump makes its speed (up to about +14 km/h), and the board then carves back up to the height you started from, so pumping keeps you on your line.
  3. A quick tap is just a nose flick. Holding past about half a second runs your legs out of travel: the board flattens out where it is and bogs until you let go. Keep holding for a second or more and you've chosen that lower line, so you stay there when you let go.
- With no input the board trims straight across at the height it's at; ↑/↓ pick your line.
- **Pump quality** is shown after each pump with the speed it added ("Pump", "Good pump", "Perfect pump"). A perfect pump gives 3x the speed of a sloppy one. To get one:
  - pump on the steep upper half of the face, not low in the flats or right at the lip
  - drive for about a quarter second before releasing
  - keep a steady rhythm, roughly one pump a second
  - don't mash the key: you can't pump more often than about every 0.6 s (presses sooner are ignored), and mashing between pumps wrecks the next one
- **Stall** (hold ←) to sit deeper in the pocket or wait for the barrel. The tail digs in, and the drag grows with your speed squared: a stall at full speed brakes hard, a stall when you're slow barely does anything. Stall too long and you lose the wave.
- **Riding out in front.** Nothing holds you on the face. Carve down past the trough and you ride onto the flat water in front of the wave: no wave push, and the flats bog you down. Get back up the face while you still have speed; ride too far out (most of a face length) and you've left the wave behind.
- **Cutback** (← + ↑ or ← + ↓): when you've run out onto the shoulder, swing the board around to point back at the barrel, back toward the power. The swing costs some speed and is shallow on the face (the board is laid over on its rail). Turn back down the line with → + ↑/↓ for a **Cutback**. Or aim at the whitewater: hit it while facing back and the foam bounces you around and throws you out ahead of the curl, a **Roundhouse Cutback**. Hit the foam high near the lip, or sit in it too long, and it gets you.
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
