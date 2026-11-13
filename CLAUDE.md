# Swell Rider

A side-view surfing game prototype in Godot 4.3+ (GDScript). The world is built entirely in code; `main.tscn` is only a root node with a script attached.

## Key invariant
The wave shape exists twice: once in `shaders/wave.gdshader` for rendering and once in `scripts/wave.gd` for gameplay. The two must stay identical, so any change to `P`, the `Lf` mix values, `wave_h`, `wave_k` or `broken_amt` has to go into both files.

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
