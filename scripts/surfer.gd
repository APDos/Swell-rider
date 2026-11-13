extends Node3D
## Surfer controller. Physics run in "face space": x along the line, t up the face
## (0 trough .. 1 lip), v speed, phi heading (0 = straight down the line,
## + = angled up the face, - = angled down).
##
## Speed comes from two places, as in real surfing:
## - The wave: gravity on the face, plus a push from the breaking water that is
##   strongest in the pocket. On its own this isn't quite enough to keep up.
## - Pumping, on its own key: one pump is a down-and-up S-turn high on the face.
##   Hold to drop and drive down the face, release to turn off the bottom of
##   the drop (that's where the speed comes from) and carve back up to the
##   height you started at. See _pump_accel below.
## Steering (carve up/down) only chooses your line; it isn't part of the pump.
## The tail stall (stall action, toward the curl) digs the tail in: water drag
## that grows with speed squared, so it brakes hard when you're fast.
## Cutbacks: ← with ↑ (or ↓) swings the board up and around (or low) until it
## points back at the curl; → with ↑/↓ swings it back down the line. Hit the
## whitewater while facing back and the foam bounces you around (the rebound).
## Nothing holds you on the face: carve down past the trough and you ride out
## onto the flat water in front of the wave, until you've gone too far to get back.
##
## step() advances the simulation and is called at the fixed physics rate.
## update_visual() is called every rendered frame and draws the surfer blended
## between the last two physics ticks, so motion is smooth at any frame rate.

signal trick_landed(trick_name: String, points: int)
signal wiped_out(reason: String)
signal pumped(quality: float, gain: float)   # a pump turned off the bottom; quality is PUMP_MIN_QUALITY..1, gain the speed it adds (m/s)

enum { RIDING, AIR, WIPEOUT }

# --- tuning -------------------------------------------------------------------
const G := 11.0          # gravity along the face
const WAVE_PUSH := 3.0   # free push from the breaking wave, strongest in the pocket; not enough without pumping
const C1 := 0.12         # linear drag
const C2 := 0.022        # quadratic drag
const TURN := 2.8        # rad/s at full steer
const TURN_RESPONSE := 9.0  # 1/s: how quickly a turn builds up and eases off
const RECENTER := 0.7    # 1/s: with no steer input, heading eases back toward straight
const MAX_PHI := 1.35       # rad: steepest normal carve up/down the face (a turn-around goes past it)
# cutbacks and the flats
const CUTBACK_TURN := 3.2     # rad/s the board swings around in a cutback or a rebound
const CARVE_DRAG := 0.06      # rail drag while swinging around: decel = this * swing rate * v
const CUTBACK_LIFT := 0.4     # how much of a turn-around's swing goes up/down the face: the board is laid over on its rail, so the arc is wide along the line and shallow on the face
const FOAM_HOLD := 1.0        # m behind the curl the whitewater shoves you along at, rather than letting you plough deeper
const FOAM_MAX := 2.0         # s in the whitewater before it buries you
const FOAM_DRAG := 1.5        # 1/s: pushing back into the whitewater stops you (decel = this * v)
const FOAM_SPEED := 13.0      # m/s the whitewater throws you forward at once you've rebounded (faster than the curl peels, so you get out)
const REBOUND_GRACE := 2.0    # s from hitting the foam you can stay in it while you come around and get going
const CUTBACK_EXIT := 0.35    # rad past level a swing finishes on: an up-and-around ends aimed down (at the foam), a low one aimed up
const FLATS_OUT := 0.8        # face run-outs out in front of the trough before you've left the wave behind
const BOG := 3.0              # m/s²: bogging low in the trough and out on the flats
# pumping
const PUMP_PRESS := 0.2       # pump input beyond this counts as pressed (a gamepad trigger is analog)
const DRIVE_ANGLE := 0.35     # rad (max) the drive points the nose down the face
const DROP_RATE := 0.45       # face heights/s (max) the drive drops you: a pump uses part of the face, on any size wave
const RISE_ANGLE := 0.5       # rad (max) the nose comes up the face carving back to your line
const RISE_RATE := 1.0        # face heights/s (max) the rise climbs
const RISE_GAIN := 8.0        # rad per unit of t below your line: how eagerly the rise climbs
const RISE_MAX := 1.0         # s: the rise gives up after this (e.g. you steered away)
const LINE_MEMORY := 1.5      # s between pumps (without steering) that the next pump keeps the same line
const SETTLE_TIME := Vector2(0.2, 0.5)  # s held past the leg stroke: from x the carve back up shrinks, by y you've chosen the lower line
const PITCH_RATE := 12.0      # 1/s: how quickly the board follows the drive and the rise
const PUMP_KICK := 4.0        # m/s a perfect pump adds turning off the bottom (a sloppy one: a third)
const KICK_TIME := 0.15       # s the kick is spread over, as the rail loads up through the turn
const MIN_PUMP_INTERVAL := 0.6  # s from one drive to the next: the legs have to carve back up and reload. Presses sooner are ignored; a key still held then starts the drive
const MIN_DRIVE := 0.1        # s: a shorter hold is only a nose flick, no pump
const GOOD_DRIVE := Vector2(0.2, 0.3)  # s of drive for full timing credit: ramps up to x, full by y
const PUSH_STROKE := 0.5      # s of driving before the legs run out of travel
const OVERHOLD_DRAG := 0.12   # 1/s: staying compressed after the stroke runs out bogs the board (decel = this * v)
const PUMP_MIN_QUALITY := 1.0 / 3.0  # sloppiest pump; a perfect one is 1.0 (3x)
const PUMP_ZONE := Vector4(0.25, 0.55, 0.85, 0.97)  # drive start height (t): credit ramps up x..y, full y..z (the steep upper face), gone by w
const PUMP_RHYTHM_RANGE := Vector2(0.5, 2.0)  # s between pumps that counts as a rhythm
# tail stall
const STALL_DRAG := 0.055     # 1/m: tail drag coefficient (decel = STALL_DRAG * dig * v²)
const STALL_DIG_TIME := 0.18  # s to shift weight back and sink the tail
const AIR_GRAVITY := 14.0
const SPIN_RATE := 7.5
const MIN_SPEED := 3.0

var wave  # wave.gd instance
var state := RIDING
var x := 0.0
var t := 0.5
var v := 11.0
var phi := 0.0
var in_barrel := false
var barrel_depth := 0.0   # 0 = just inside the lip line, 1 = deep in the pocket

var air_h := 0.0
var air_vy := 0.0
var spin := 0.0
var _air_time := 0.0

var _clock := 0.0
var _last_trick := -10.0
enum { PUMP_IDLE, PUMP_DRIVE, PUMP_RISE }
var pump_phase := PUMP_IDLE
var pushing := false          # in the drive (down) part of a pump
var stroke := 1.0             # leg travel left for this drive (0..1)
var pump_quality := 0.0       # quality of the last pump, PUMP_MIN_QUALITY..1
var pump_pitch := 0.0         # rad the pump adds to the heading: + nose up the face, - nose down
var pump_line_t := 0.6        # the line this pump started from (where a normal pump carves back to)
var rise_target_t := 0.6      # the height the current rise is carving up to
var quality_override := -1.0  # tests: >= 0 pins the pump quality
var _drive_time := 0.0
var _drive_start_t := 0.6
var _drive_force := 0.0       # hardest the trigger was pulled during this drive
var _rise_time := 0.0
var _idle_time := 0.0
var _last_drive_start := -10.0
var _fumbled := false         # pressed again before MIN_PUMP_INTERVAL: wiggling the board breaks your rhythm
var _was_held := false
var _kick_left := 0.0         # m/s of the current kick still to be added
var tail_dig := 0.0           # 0..1, how far the tail is sunk
var _last_push_start := -10.0
var _last_interval := -1.0
var _lean := 0.0
var _wipe_pos := Vector3.ZERO
var _wipe_vel := Vector3.ZERO
var _wipe_spin := Vector3.ZERO

var facing := 1.0         # +1 riding down the line (right), -1 turned back toward the curl
var turning := 0          # 0, or a turn-around in progress: +1 swinging up and around, -1 low
var _turn_to := 1.0       # facing the current turn-around ends on
var _cut_back := false    # turned to face the curl since you last rode down the line
var _rebounded := false   # this cutback bounced off the whitewater
var _rebound_time := -10.0
var _foam_time := 0.0
var turn_rate := 0.0      # rad/s, eases toward steer * TURN
var _steer := 0.0
var _wipe_rot := Vector3.ZERO

# Previous physics tick, for blending in update_visual().
var _p_x := 0.0
var _p_t := 0.5
var _p_air_h := 0.0
var _p_spin := 0.0
var _p_wipe_pos := Vector3.ZERO
var _p_wipe_rot := Vector3.ZERO
var _snap_visual := true  # skip smoothing on the next frame (after a reset)
var _overlay_on := false

## Surfer x as drawn this frame (blended between ticks). Use it for anything
## visual, such as the camera, so it doesn't stutter.
var vis_x := 0.0

var _rig: Node3D
var _spray: CPUParticles3D
var _parts: Array[MeshInstance3D] = []
var _xray: StandardMaterial3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _glow := 0.0
var _upper: Array = []    # [node, rest position] for torso, head, arms: they crouch and lean
var _crouch := 0.0
var _dig_vis := 0.0


func _ready() -> void:
	_build_rig()


func reset(start_x: float) -> void:
	state = RIDING
	x = start_x
	t = 0.55
	v = 11.0
	phi = -0.1
	spin = 0.0
	turn_rate = 0.0
	facing = 1.0
	turning = 0
	_turn_to = 1.0
	_cut_back = false
	_rebounded = false
	_rebound_time = -10.0
	_foam_time = 0.0
	pump_phase = PUMP_IDLE
	pushing = false
	stroke = 1.0
	pump_quality = 0.0
	pump_pitch = 0.0
	pump_line_t = t
	rise_target_t = t
	_idle_time = LINE_MEMORY
	_drive_time = 0.0
	_drive_force = 0.0
	_rise_time = 0.0
	_kick_left = 0.0
	tail_dig = 0.0
	_last_push_start = -10.0
	_last_drive_start = -10.0
	_fumbled = false
	_last_interval = -1.0
	in_barrel = false
	barrel_depth = 0.0
	_wipe_rot = Vector3.ZERO
	_rig.rotation = Vector3.ZERO
	_rig.position = Vector3.ZERO
	_save_prev()
	vis_x = x
	_snap_visual = true


func _save_prev() -> void:
	_p_x = x
	_p_t = t
	_p_air_h = air_h
	_p_spin = spin
	_p_wipe_pos = _wipe_pos
	_p_wipe_rot = _wipe_rot


## One fixed physics tick. steer is -1..1 (carve down/up on the face, spin in
## the air). stall is 0..1 (weight on the tail). pump is 0..1 (the pump key or
## trigger; how hard it's held sets the push force). side is -1..1: ← (toward
## the curl) or → (toward the shoulder); with a carve it turns you around.
func step(dt: float, steer: float, stall := 0.0, pump := 0.0, side := 0.0) -> void:
	_save_prev()
	_clock += dt
	_steer = steer
	match state:
		RIDING: _step_riding(dt, steer, stall, pump, side)
		AIR: _step_air(dt, steer)
		WIPEOUT: _step_wipeout(dt)


func _step_riding(dt: float, steer: float, stall: float, pump: float, side: float) -> void:
	var d: float = x - wave.curl_x
	var slope: float = wave.slope_at(x, t)
	var flen: float = wave.face_length(x)
	var in_foam := d < 0.0

	# ← or → together with a carve turns you around: a cutback toward the curl,
	# or back down the line. The carve picks the arc (↑ up and around, ↓ low).
	var combo := absf(side) > 0.5 and absf(steer) > 0.3
	if combo and turning == 0 and signf(side) != facing:
		_start_turn(signf(side), int(signf(steer)))
	# Facing back when you reach the whitewater: the foam bounces you around.
	# It swings you up into the foam, or round low if you hit it high on the face.
	if in_foam and facing < 0.0 and turning == 0:
		_start_turn(1.0, 1 if t < 0.5 else -1)
		_rebounded = true
		_rebound_time = _clock
	var swing := 0.0
	var rebound_turn := _turn_to > 0.0 and _clock - _rebound_time < REBOUND_GRACE
	if turning != 0 and (combo or rebound_turn):
		swing = _swing(dt)
	elif turning != 0:
		turning = 0  # let go mid-turn: the board carries on from where it got to
	if combo:
		stall = 0.0  # the back hand is turning you, not stalling

	if swing == 0.0:
		# Turns build up and ease off rather than switching on and off instantly.
		turn_rate = lerpf(turn_rate, steer * TURN, 1.0 - exp(-TURN_RESPONSE * dt))
		phi += turn_rate * dt
		if absf(steer) < 0.1:
			phi = lerpf(phi, 0.0, 1.0 - exp(-RECENTER * dt))
		if absf(phi) > MAX_PHI:
			phi = move_toward(phi, signf(phi) * MAX_PHI, TURN * dt)  # ease back from a half-finished turn-around

	# The pump adds its own small up-then-down motion on top of the steered line.
	var pump_a := _pump_accel(dt, pump, flen)
	var h := heading()

	var lift := CUTBACK_LIFT if turning != 0 else 1.0
	var pocket := 0.4 + 1.2 * exp(-maxf(d, 0.0) / 18.0)
	var a := -G * sin(slope) * sin(h) * lift + WAVE_PUSH * sin(slope) * pocket - C1 * v - C2 * v * v
	if t < 0.06:
		a -= BOG  # bogging in the trough and out on the flats
	a -= CARVE_DRAG * absf(swing) * v
	if in_foam and facing < 0.0:
		a -= FOAM_DRAG * v
	a += pump_a

	tail_dig = move_toward(tail_dig, clampf(stall, 0.0, 1.0), dt / STALL_DIG_TIME)
	a -= STALL_DRAG * tail_dig * v * v
	v = maxf(v + a * dt, 0.0)
	if in_foam and facing > 0.0 and _clock - _rebound_time < REBOUND_GRACE:
		v = maxf(v, FOAM_SPEED)  # bounced off the foam: it throws you forward

	# Out on the flats, t keeps counting in face run-outs in front of the trough.
	t += v * sin(h) * lift / (flen if t >= 0.0 else wave.lf_at(x)) * dt
	x += facing * v * cos(h) * dt
	if in_foam:
		x = maxf(x, wave.curl_x - FOAM_HOLD)  # the whitewater shoves you along with it
		_foam_time += dt
	else:
		_foam_time = 0.0

	if t >= 1.0 and turning != 0:
		t = 1.0  # swinging around off the top: carry on with the turn
	elif t >= 1.0:
		if h > 0.6 and v > 9.0:
			_launch()
			return
		t = 1.0
		if v > 8.0 and h > 0.35 and _clock - _last_trick > 0.8:
			_last_trick = _clock
			trick_landed.emit("Off the Lip", 250)
			v *= 0.92
		phi = minf(-absf(phi) * 0.8, -0.25)
		turn_rate = 0.0
	_check_cutback()

	var k: float = wave.k_at(x)
	in_barrel = d > 0.0 and d < 7.0 and t > 0.2 and t < 0.7 and k > 0.55
	if in_barrel:
		# deeper = closer behind the curtain to where the lip is landing
		var lip_cover := clampf((k - 0.55) / 0.35, 0.0, 1.0)
		barrel_depth = clampf((7.0 - d) / 6.0, 0.0, 1.0) * lerpf(0.6, 1.0, lip_cover)
	else:
		barrel_depth = 0.0

	if in_foam:
		# The whitewater only gives you a chance when you're turning off it low
		# on the face: rebounding, or just after while you get going again.
		var rebounding := turning != 0 or _clock - _rebound_time < REBOUND_GRACE
		if (t > 0.8 and turning == 0) or not rebounding:
			_wipeout("The whitewater caught you" if t < 0.3 else "The lip landed on you")
			return
		if _foam_time > FOAM_MAX:
			_wipeout("Buried in the whitewater")
			return
	if t < -FLATS_OUT:
		_wipeout("Rode off the front of the wave")
	elif v < MIN_SPEED:
		_wipeout("Lost the wave")


## Start swinging the board around to face to (+1 down the line, -1 at the
## curl). arc +1 goes up and around (through pointing up the face), -1 low.
func _start_turn(to: float, arc: int) -> void:
	if arc == 0:
		arc = 1
	_turn_to = to
	turning = arc


## One tick of a turn-around. phi is measured from the facing direction, so the
## swing runs phi out to vertical, flips facing, then brings phi back to level.
## Returns the swing rate (rad/s, signed) for drag and drawing.
func _swing(dt: float) -> float:
	var dir := float(turning) if facing != _turn_to else -float(turning)
	phi += dir * CUTBACK_TURN * dt
	if facing != _turn_to and absf(phi) >= PI / 2.0:
		facing = _turn_to
		phi = signf(phi) * (PI - absf(phi))   # mirror past vertical into the new facing
		turn_rate = 0.0
	elif facing == _turn_to and float(turning) * phi <= -CUTBACK_EXIT:
		turning = 0
	turn_rate = dir * CUTBACK_TURN
	return dir * CUTBACK_TURN


## Cutback scoring: turning to face the curl, then back down the line.
func _check_cutback() -> void:
	if facing < 0.0:
		_cut_back = true
	elif _cut_back and turning == 0:
		_cut_back = false
		if _rebounded:
			trick_landed.emit("Roundhouse Cutback", 700)
		else:
			trick_landed.emit("Cutback", 400)
		_rebounded = false


## The board's actual heading on the face, measured from the facing direction
## (+ up the face): the steered line plus the pump's motion.
func heading() -> float:
	var lim := maxf(MAX_PHI, absf(phi))
	return clampf(phi + pump_pitch, -lim, lim)


## Pumping, on its own key. One pump is a down-and-up S-turn high on the face,
## the way surfers pump down the line:
## 1. Hold: drive. The nose drops down the face and you compress, trading a
##    little height for speed. The legs have PUSH_STROKE of travel; hold past it
##    and the board levels off and bogs (OVERHOLD_DRAG).
## 2. Release: turn off the bottom. Extending through the bottom of the turn is
##    where a pump makes its speed (PUMP_KICK, spread over KICK_TIME), and the
##    board then carves back up the face to the height the pump started from,
##    so pumping keeps you on your line instead of walking you to the flats.
##    Press again during the rise and the next pump keeps the same line.
## 3. Keep holding past the leg stroke and the board flattens out where it is
##    and bogs. Hold on for SETTLE_TIME and you've chosen that lower line: the
##    release still gives the bottom turn, but doesn't carve you back up.
## A hold shorter than MIN_DRIVE is only a nose flick: no kick.
## You can't pump faster than once per MIN_PUMP_INTERVAL: mashing the key just
## gets ignored presses, not a wiggling board full of speed, and the next pump
## after an ignored press scores PUMP_MIN_QUALITY.
##
## How good a pump is gets decided at the bottom turn (_score_pump):
## - height: drive from the steep upper face, not the flats or right at the lip
## - timing: drive for GOOD_DRIVE, not a jab and not past the leg stroke
## - rhythm: keep a steady interval between pumps
## The sloppiest pump still gets PUMP_MIN_QUALITY, a perfect one 1.0 (3x).
func _pump_accel(dt: float, pump: float, flen: float) -> float:
	var held := pump > PUMP_PRESS
	var ready := _clock - _last_drive_start >= MIN_PUMP_INTERVAL - 1e-6
	if held and not _was_held and not ready:
		_fumbled = true
	_was_held = held
	if held and pump_phase != PUMP_DRIVE and ready:
		# Pumping in a rhythm keeps the line you were carving back up to, so small
		# overshoots don't add up. Steering, or a pause, picks a new line.
		pump_line_t = rise_target_t if pump_phase == PUMP_RISE or _idle_time < LINE_MEMORY else t
		pump_phase = PUMP_DRIVE
		_drive_time = 0.0
		_drive_force = 0.0
		_drive_start_t = t
		_last_drive_start = _clock
		stroke = 1.0
	elif not held and pump_phase == PUMP_DRIVE:
		if _drive_time >= MIN_DRIVE:
			pump_quality = _score_pump()
			var gain := PUMP_KICK * pump_quality * _drive_force
			_kick_left += gain
			pumped.emit(pump_quality, gain)
		# Carve back up by the drop the pump made, less the more you settled low.
		var overhold := maxf(_drive_time - PUSH_STROKE, 0.0)
		var back := maxf(pump_line_t - t, 0.0) * (1.0 - smoothstep(SETTLE_TIME.x, SETTLE_TIME.y, overhold))
		rise_target_t = minf(t + back, 0.95)
		pump_phase = PUMP_RISE
		_rise_time = 0.0
	elif pump_phase == PUMP_RISE:
		_rise_time += dt
		# Done once on the line and the board has levelled off, so it doesn't sail past.
		if (t >= rise_target_t - 0.005 and pump_pitch < 0.03) or _rise_time >= RISE_MAX:
			pump_phase = PUMP_IDLE
	pushing = pump_phase == PUMP_DRIVE
	if pump_phase == PUMP_IDLE:
		_idle_time += dt
		if absf(_steer) > 0.1:
			_idle_time = LINE_MEMORY
	else:
		_idle_time = 0.0

	var pitch_target := 0.0
	var a := 0.0
	match pump_phase:
		PUMP_DRIVE:
			_drive_time += dt
			_drive_force = maxf(_drive_force, clampf(pump, 0.0, 1.0))
			stroke = maxf(stroke - dt / PUSH_STROKE, 0.0)
			if stroke > 0.0:
				pitch_target = -_face_angle(DRIVE_ANGLE, DROP_RATE, flen) * clampf(pump, 0.0, 1.0)
			else:
				# Legs fully extended: the board flattens out onto your steered line and bogs.
				pitch_target = 0.0
				a -= OVERHOLD_DRAG * v
		PUMP_RISE:
			# Proportional, and allowed to dip slightly, so it settles onto the line.
			pitch_target = clampf((rise_target_t - t) * RISE_GAIN, -0.1, _face_angle(RISE_ANGLE, RISE_RATE, flen))
	pump_pitch = lerpf(pump_pitch, pitch_target, 1.0 - exp(-PITCH_RATE * dt))

	if _kick_left > 0.0:
		var k := minf(_kick_left, PUMP_KICK / KICK_TIME * dt)
		_kick_left -= k
		a += k / dt
	return a


## The steepest angle up/down the face, at most max_angle, that moves you no
## faster than rate face-heights per second at the current speed.
func _face_angle(max_angle: float, rate: float, flen: float) -> float:
	return minf(max_angle, asin(clampf(rate * flen / maxf(v, 1.0), 0.0, 1.0)))


func _score_pump() -> float:
	if quality_override >= 0.0:
		return quality_override
	var height := smoothstep(PUMP_ZONE.x, PUMP_ZONE.y, _drive_start_t) * (1.0 - smoothstep(PUMP_ZONE.z, PUMP_ZONE.w, _drive_start_t))
	var over := maxf(_drive_time - PUSH_STROKE, 0.0)
	var timing := smoothstep(MIN_DRIVE, GOOD_DRIVE.x, _drive_time) * (1.0 - smoothstep(0.0, 0.4, over))
	if _drive_time > GOOD_DRIVE.y:
		timing *= lerpf(1.0, 0.8, clampf((_drive_time - GOOD_DRIVE.y) / (PUSH_STROKE - GOOD_DRIVE.y), 0.0, 1.0))
	var interval := _clock - _last_push_start
	_last_push_start = _clock
	if _fumbled:
		# Mashed the key since the last pump: the board was wiggling, not
		# pumping, so this one is as sloppy as it gets and the rhythm restarts.
		_fumbled = false
		_last_interval = -1.0
		return PUMP_MIN_QUALITY
	var rhythm := 0.5  # first pump of a run: neutral
	if interval > PUMP_RHYTHM_RANGE.y:
		_last_interval = -1.0
	elif interval >= PUMP_RHYTHM_RANGE.x:
		if _last_interval > 0.0:
			rhythm = 1.0 - clampf(absf(interval - _last_interval) / (0.5 * _last_interval), 0.0, 1.0)
		_last_interval = interval
	else:
		rhythm = 0.0  # pumping faster than a real rhythm
	var score := height * (0.4 + 0.3 * timing + 0.3 * rhythm)
	return lerpf(PUMP_MIN_QUALITY, 1.0, score)


func _launch() -> void:
	state = AIR
	phi = heading()
	pump_phase = PUMP_IDLE
	pushing = false
	pump_pitch = 0.0
	_kick_left = 0.0
	in_barrel = false
	barrel_depth = 0.0
	air_h = 0.0
	air_vy = 3.0 + v * sin(heading()) * 0.35
	spin = 0.0
	_air_time = 0.0
	t = 1.0


func _step_air(dt: float, steer: float) -> void:
	_air_time += dt
	x += facing * v * maxf(cos(phi), 0.45) * dt
	air_vy -= AIR_GRAVITY * dt
	air_h += air_vy * dt
	spin += steer * SPIN_RATE * dt
	if x - wave.curl_x < 0.0:
		_wipeout("Swallowed mid-air")
		return
		return
	if air_h <= 0.0 and air_vy < 0.0:
		var rem := fposmod(spin, TAU)
		var clean := rem < 0.7 or rem > TAU - 0.7
		if not clean:
			_wipeout("Over-rotated the landing" if rem < PI else "Under-rotated the landing")
			return
		var spins := int(round(absf(spin) / TAU))
		var trick_name := "Air" if spins == 0 else "Air %d" % (spins * 360)
		trick_landed.emit(trick_name, 400 + spins * 900 + int(_air_time * 200.0))
		state = RIDING
		t = 0.96
		phi = -0.55
		turn_rate = 0.0
		v *= 0.9
		pump_line_t = t
		rise_target_t = t
		_idle_time = LINE_MEMORY
		spin = 0.0
		_p_spin = 0.0  # landing re-bases the spin; don't blend across it


func _wipeout(reason: String) -> void:
	state = WIPEOUT
	in_barrel = false
	barrel_depth = 0.0
	_wipe_pos = global_position
	_wipe_vel = Vector3(v * 0.4, 3.0, 3.5)
	_wipe_spin = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-8, 8))
	_wipe_rot = _rig.rotation
	_p_wipe_pos = _wipe_pos
	_p_wipe_rot = _wipe_rot
	_spray.emitting = false
	wiped_out.emit(reason)


func _step_wipeout(dt: float) -> void:
	_wipe_vel.y -= 9.8 * dt
	_wipe_vel *= 1.0 - 0.8 * dt
	_wipe_pos += _wipe_vel * dt
	_wipe_pos.y = maxf(_wipe_pos.y, -0.4)
	_wipe_rot += _wipe_spin * dt
	_wipe_spin *= 1.0 - 1.5 * dt


## Called every rendered frame. Draws the surfer blended between the previous
## and current physics tick.
func update_visual(delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	_lean = lerpf(_lean, _steer, 1.0 - exp(-8.0 * delta))
	vis_x = lerpf(_p_x, x, f)

	if state == WIPEOUT:
		global_position = _p_wipe_pos.lerp(_wipe_pos, f)
		_rig.rotation = _p_wipe_rot.lerp(_wipe_rot, f)
		_update_highlight(delta)
		return

	var tt := lerpf(_p_t, t, f) if state == RIDING else 1.0
	var p: Vector3 = wave.face_point(vis_x, tt)
	var up_face: Vector3 = wave.face_up(vis_x, tt)
	var along := Vector3(1, 0, 0)
	var n := along.cross(up_face).normalized()  # face normal (up + shoreward)

	var fwd: Vector3
	if state == RIDING:
		var hd := heading()
		fwd = (along * facing * cos(hd) + up_face * sin(hd)).normalized()
		global_position = p + n * 0.05
	else:
		fwd = Vector3(facing, 0.25, 0).normalized()
		n = Vector3.UP
		global_position = p + Vector3(0, lerpf(_p_air_h, air_h, f) + 0.1, -0.2)
	var right := fwd.cross(n).normalized()
	var up := (-fwd).cross(right).normalized()
	var b := Basis(right, up, -fwd)
	if state == AIR:
		# Exact in the air: the player judges the landing by what they see.
		b = Basis(Vector3.UP, -lerpf(_p_spin, spin, f)) * b
		global_transform.basis = b.orthonormalized()
	else:
		# On the face, ease toward the target so the heading flips at the lip
		# and on landing turn quickly instead of snapping in one frame.
		var target := b.orthonormalized().get_rotation_quaternion()
		var q := target if _snap_visual else global_transform.basis.get_rotation_quaternion().slerp(target, 1.0 - exp(-18.0 * delta))
		global_transform.basis = Basis(q)
	_snap_visual = false

	# Pumping: crouch while the legs are driving. Stalling: nose up, weight back.
	var driving := state == RIDING and pushing and stroke > 0.0
	_crouch = lerpf(_crouch, 1.0 if driving else 0.0, 1.0 - exp(-14.0 * delta))
	_dig_vis = lerpf(_dig_vis, tail_dig if state == RIDING else 0.0, 1.0 - exp(-14.0 * delta))
	for u in _upper:
		u[0].position = u[1] + Vector3(0.0, -0.22 * _crouch - 0.08 * _dig_vis, 0.18 * _dig_vis)
	_rig.rotation = Vector3(0.26 * _dig_vis, 0, _lean * 0.45 if state == RIDING else 0.0)
	_spray.emitting = state == RIDING and v > 5.0 and (absf(_steer) > 0.3 or _dig_vis > 0.3 or turning != 0)
	_update_highlight(delta)


## Barrel highlight: an x-ray silhouette drawn through the lip plus a halo,
## shifting cyan -> gold as you get deeper. Also shown (cyan) while you're in
## the whitewater during a rebound, so you can see yourself through the foam.
func _update_highlight(delta: float) -> void:
	var target := barrel_depth if in_barrel else 0.0
	if state == RIDING and _foam_time > 0.0:
		target = 0.3  # in the whitewater: show the surfer through the foam
	_glow = lerpf(_glow, target, 1.0 - exp(-13.0 * delta))
	var on := _glow > 0.02
	if on != _overlay_on:
		_overlay_on = on
		for m in _parts:
			m.material_overlay = _xray if on else null
		_halo.visible = on
	if not on:
		return
	var c := Color(0.35, 1.0, 0.9).lerp(Color(1.0, 0.78, 0.2), _glow)
	_xray.albedo_color = Color(c.r, c.g, c.b, 0.35 + 0.5 * _glow)
	_halo_mat.albedo_color = Color(c.r, c.g, c.b, 0.5 + 0.5 * _glow)
	var sc := 2.2 + 1.8 * _glow
	_halo.scale = Vector3(sc, sc, sc)


func speed_kmh() -> float:
	return v * 3.6


# ---- visuals -------------------------------------------------------------------

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_rig.add_child(mi)
	_parts.append(mi)
	return mi


func _build_rig() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	var suit := _mat(Color(0.05, 0.05, 0.07))
	var skin := _mat(Color(0.85, 0.62, 0.45))

	# board (nose points -Z)
	var board := BoxMesh.new()
	board.size = Vector3(0.52, 0.07, 1.95)
	_part(board, _mat(Color(0.98, 0.95, 0.88)), Vector3(0, 0.04, 0))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.12, 0.075, 1.9)
	_part(stripe, _mat(Color(1.0, 0.42, 0.12)), Vector3(0, 0.045, 0))

	# legs: wide stance along the board, knees bent
	var leg := CapsuleMesh.new()
	leg.radius = 0.09
	leg.height = 0.85
	_part(leg, suit, Vector3(0, 0.42, -0.32), Vector3(-0.35, 0, 0))
	_part(leg, suit, Vector3(0, 0.42, 0.32), Vector3(0.35, 0, 0))

	var torso := CapsuleMesh.new()
	torso.radius = 0.17
	torso.height = 0.7
	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.24
	var arms := BoxMesh.new()
	arms.size = Vector3(0.09, 0.09, 1.25)
	for m in [_part(torso, suit, Vector3(0.05, 1.05, 0), Vector3(0, 0, -0.25)),
			_part(head, skin, Vector3(0.12, 1.5, -0.05)),
			_part(arms, suit, Vector3(0.05, 1.22, 0), Vector3(0.15, 0, 0))]:
		_upper.append([m, m.position])

	# barrel highlight materials (drawn on top of everything, incl. the lip)
	_xray = StandardMaterial3D.new()
	_xray.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_xray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_xray.no_depth_test = true
	_xray.render_priority = 10

	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.no_depth_test = true
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.albedo_texture = tex
	_halo_mat.render_priority = 9
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_halo = MeshInstance3D.new()
	_halo.mesh = quad
	_halo.material_override = _halo_mat
	_halo.position = Vector3(0, 0.9, 0)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.visible = false
	add_child(_halo)

	# rooster-tail spray off the rail
	_spray = CPUParticles3D.new()
	_spray.amount = 90
	_spray.lifetime = 0.7
	_spray.local_coords = false
	_spray.position = Vector3(0.15, 0.05, 0.75)
	_spray.direction = Vector3(0.7, 1.0, 0.3)
	_spray.spread = 30.0
	_spray.initial_velocity_min = 3.0
	_spray.initial_velocity_max = 6.5
	_spray.gravity = Vector3(0, -9.8, 0)
	_spray.scale_amount_min = 0.4
	_spray.scale_amount_max = 1.0
	var drop := SphereMesh.new()
	drop.radius = 0.06
	drop.height = 0.12
	drop.radial_segments = 6
	drop.rings = 3
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.95, 0.98, 1.0)
	drop.material = dm
	_spray.mesh = drop
	_spray.emitting = false
	_rig.add_child(_spray)
