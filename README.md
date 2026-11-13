# Swell Rider (prototype)

Side-view wave riding in Godot 4.3+. Everything (wave, surfer, HUD) is built in code, so there are no assets to import.

## Run
1. Install Godot 4.3 or newer (standard build, not .NET).
2. In the Project Manager, click Import and pick `project.godot` in this folder.
3. Press F5.

## Controls
| Input | Action |
|---|---|
| ↑ / W | Carve up the face, toward the lip |
| ↓ / S | Carve down, toward the trough |
| Space | Pump (tap it mid-face for speed; it has a cooldown) |
| ← / → (or ↑ / ↓) in the air | Spin. Land within about 40° of a full rotation or you wipe out |
| R / Enter | Paddle back out |
| Esc | Quit |

## How it plays
- The break peels down the line at about 9 m/s. If the curl catches you, you wipe out.
- Points come from speed, multiplied by how close you are to the pocket (up to x3).
- **Off the Lip**: hit the top fast at a moderate angle. **Air**: hit the top fast and steep (heading > ~35°, speed > ~32 km/h).
- **Barrel**: stay mid-face just ahead of the curl where the lip is pitching. When the lip covers you, your surfer glows through the water, going from cyan to gold as you get deeper. A depth meter shows the same thing. Deeper barrels score more per second.
- **Closeout sections**: a steep section appears ahead ("Section ahead"). The curl races through it at 28 m/s, so you need to be past it before the curl gets there.

## Code map
- `scripts/wave.gd` + `shaders/wave.gdshader`: the wave shape. The vertex shader builds the wave and lip from a flat grid. The GDScript copy of the same math keeps the surfer on the face. **If you change a formula in one, change it in the other.**
- `scripts/surfer.gd`: face-space physics (x along the line, t up the face, speed, heading), plus airs and wipeouts. The tuning constants are at the top.
- `scripts/main.gd`: curl and closeout scheduling, scoring, camera, environment.
- `scripts/hud.gd`: on-screen UI.

## Dev flags
`godot --path . -- --autopilot` rides by itself. Add `--shot=/tmp/s.png` to save screenshots, or `--barreltest` to hold the curl just behind the surfer so you can tune the barrel.
