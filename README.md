# Swell Rider (prototype)

Side-view wave riding in Godot 4.3+. Everything (wave, surfer, HUD) is built in code, so there are no assets to import.

## Controls (iPhone, landscape)
- **Left thumb: point the nose.** Touch anywhere on the left half (where you touch is neutral) and slide toward where you want the board to go; it carves round to follow your thumb.
  - Up / down: carve up the face (lip, airs) or down it. Keep pointing down and you ride out onto the flat water in front of the wave.
  - **Cutback**: one sweep of the thumb, like drawing a backwards S (or a 2). The reverse C (up, up-back, back, down-back) turns the nose up and round to point at the barrel; keep sweeping on round the bottom (down, down-ahead, ahead) and the board drops down the face and comes back round the bottom, down the line. The board follows the way your thumb is sweeping, so it never doubles back on you. Or, once you're facing the barrel, just slide your thumb straight across to point back down the line: the board turns back the short way, round the bottom.
  - **Stall**: point straight behind you while the board is running level. Your weight goes on the tail, which brakes harder the faster you're going.
  - In the air: thumb sideways spins you. Land within about 40° of a full rotation.
- **Right thumb: pump.** Hold anywhere on the right half to drive down the face, lift to turn off the bottom and carve back up. See below.
- After a wipeout, tap to paddle back out. Mid-ride, hold the ↻ in the top-right corner to restart.

## Build and install
Godot 4.7.2 with its iOS export template, and **Xcode 26 or later** (Godot 4.7's iOS template links against the iOS 26 SDK). Minimum iOS is 16. Sign in to your Apple account in Xcode > Settings > Accounts, plug in and unlock the phone (trust the developer profile on first install: Settings > General > VPN & Device Management), then:
```
godot --headless --path . --export-debug "iOS" build/ios/SwellRider.ipa
xcrun devicectl device install app --device <device id> build/ios/SwellRider.ipa
```
`export_presets.cfg` has the signing team and bundle id. The icon is drawn by `tools/make_icon.gd`. Running from the Godot editor on a Mac works with the mouse as a single touch (no pumping while steering).

## Ride recordings
Debug builds on the phone record every ride: one CSV per ride with both thumbs (screen position, the stick's centre, the aim and pump the game read) and the surfer (state, x, t, speed, heading, facing, cutting, stall, pump phase, distance to the curl, ...) for every physics tick, plus `# event` lines for pumps, tricks, wipeouts and restarts. The newest 60 are kept. Copy them to `rides/` (git-ignored) with the phone plugged in:
```
tools/pull_rides.sh
```
Replay one through the game to watch it (`godot --path . -- --replay=rides/ride_....csv`), or headless to check it still plays out the same after a physics change: `godot --headless --fixed-fps 60 --path . -- --replay=rides/ride_....csv` prints `REPLAY MATCHES` or the first tick where it went differently. Each ride's wave comes from a seed in the file, so the replay gets the same wave. On the Mac, `-- --record` records too.

## How it plays
- The break peels down the line at about 9 m/s. If the curl catches you, you wipe out.
- **Pumping is how you keep up.** The wave alone won't carry you: without pumping, the curl catches you within about 20 seconds. One pump is a small down-and-up S-turn high on the face, the way surfers pump down the line:
  1. Hold the right thumb: drive. The nose drops down the face and you compress, trading a bit of height for speed.
  2. Lift it: you turn off the bottom of that drop. That's where the pump makes its speed, and the board then carves back up to the height you started from, so pumping keeps you on your line.
  3. A quick tap is just a nose flick. Holding past about half a second runs your legs out of travel: the board flattens out where it is and bogs until you let go. Keep holding for a second or more and you've chosen that lower line, so you stay there when you let go.
- With no thumb on the stick the board trims straight across at the height it's at; pointing picks your line.
- **Pump quality** is shown after each pump ("Pump", "Good pump", "Perfect pump"). A perfect pump gives 3x the speed of a sloppy one. To get one:
  - pump on the steep upper half of the face, not low in the flats or right at the lip
  - drive for about a quarter second before releasing
  - keep a steady rhythm, roughly one pump a second
  - don't mash the key: you can't pump more often than about every 0.6 s (presses sooner are ignored), and mashing between pumps wrecks the next one
- **Stall** (put your thumb down pointing straight back) to sit deeper in the pocket or wait for the barrel. The tail digs in, and the drag grows with your speed squared: a stall at full speed brakes hard, a stall when you're slow barely does anything. Stall too long and you lose the wave.
- **Riding out in front.** Nothing holds you on the face. Carve down past the trough and you ride onto the flat water in front of the wave: no wave push, and the flats bog you down. Get back up the face while you still have speed; ride too far out (most of a face length) and you've left the wave behind.
- **Cutback**: when you've run out onto the shoulder, turn back toward the barrel and the power: sweep a reverse C with your left thumb and the nose follows it round. If you stop part way, the board stays where it got to. Sweep forward (up, up-ahead, ahead) to come back down the line for a **Cutback**. A cutback keeps about 75% of your speed and stays fairly low on the face (the board is laid over on its rail).
- **Rebound**: aim at the whitewater after cutting back. It stops you dead, and you have a moment to sweep the turn off it yourself; come around in the foam and it throws you out ahead of the curl, a **Roundhouse Cutback**. Don't turn, hit it high near the lip, or sit in it too long, and it gets you.
- Points come from speed, multiplied by how close you are to the pocket (up to x3).
- **Off the Lip**: hit the top fast at a moderate angle. **Air**: hit the top fast and steep (steeper than about 35°, and fast). You'll need to pump up that speed first.
- Whenever the lip hangs between the camera and you (riding high by the curl, or in the whitewater), your surfer shows through it as a glowing silhouette.
- **Barrel**: stay mid-face just ahead of the curl where the lip is pitching. When the lip covers you, your surfer glows through the water, going from cyan to gold as you get deeper. A depth meter shows the same thing. Deeper barrels score more per second.
- **Closeout sections**: a steep section appears ahead ("Section ahead — pump for speed!"). The curl races through it at 28 m/s, so you need to have pumped your way past it before the curl gets there.

## Code map
- `scripts/wave.gd` + `shaders/wave_shape.gdshaderinc`: the wave shape. The vertex shader (`shaders/wave.gdshader`) builds the wave and lip from a flat grid using the functions in the include. `wave.gd` has a CPU copy of those functions to keep the surfer on the face. The tuning values live only in `wave.gd`'s `SHAPE` table and are pushed to the shader as uniforms. **If you change a formula in one copy, change it in the other and run the tests.** The parity test will catch a mismatch.
- `scripts/surfer.gd`: face-space physics (x along the line, t up the face, speed, heading), plus airs and wipeouts. The tuning constants are at the top.
- `scripts/main.gd`: curl and closeout scheduling, scoring, camera, environment. Gameplay runs in `_physics_process` at a fixed 60 ticks per second; drawing runs in `_process`, blended between ticks.
- `scripts/touch.gd`: the thumb controls (aim, pump, taps), read by main.gd each tick.
- `scripts/autopilot.gd`: a scripted rider that pumps in rhythm. Used by `--autopilot` and by the tests.
- `scripts/hud.gd`: on-screen UI.
- `scripts/recorder.gd` / `scripts/replay.gd`: ride recordings and playing them back.

## Tests
Run `tests/run_tests.sh` (needs `godot` 4.3+ on PATH, plus `xvfb-run` on a machine without a display). CI runs it on every push.

## Dev flags
`godot --path . -- --autopilot` rides by itself. Add `--shot=/tmp/s.png` to save screenshots, or `--barreltest` to hold the curl just behind the surfer so you can tune the barrel.
