extends Node3D
## Surfer controller. Physics run in "face space": x along the line, t up the face
## (0 trough .. 1 lip), v speed, phi heading (0 = straight down the line,
## + = angled up the face, - = angled down).
##
## Speed comes from two places, as in real surfing:
## - The wave: gravity on the face, plus a push from the breaking water that is
##   strongest in the pocket. On its own this isn't quite enough to keep up.
## - Pumping (the right thumb): one pump is a down-and-up S-turn high on the face.
##   Hold to drop and drive down the face, release to turn off the bottom of
##   the drop (that's where the speed comes from) and carve back up to the
##   height you started at. See _pump_accel below.
## Steering (the left thumb) points the nose: aim is the direction the thumb
## points (x down the line, y up the face). Ahead of the board, the nose carves
## round to it, short of vertical. Behind the board, the nose drives on round
## past vertical toward it: a cutback (sweep up and round), or back down the
## line. Pointing straight behind you while the board runs level sits you back
## on the tail instead: the stall, water drag that grows with speed squared.
## Nothing turns you unless you point. The whitewater stops you and, once
## you've turned yourself back around in it, throws you forward (the rebound).
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
const CUTBACK_TURN := 5.5     # rad/s the nose comes around at in a cutback (a normal carve is TURN)
const CARVE_DRAG := 0.03      # rail drag while turning around: decel = this * turn rate * v
const CUTBACK_LIFT := 0.3     # near vertical in a turn-around, how much of the motion goes up/down the face: the board is laid over on its rail, so the arc is wide along the line and shallow on the face
const AIM_GAIN := 4.0         # per rad off target: how eagerly the nose swings to where you point
const AIM_DEAD := 0.1         # thumb push below this is no steering
const SWEEP_PUSH := 0.95      # a thumb pushed less than this is near the stick's centre, where its angle swings with every pixel: it never counts as a sweep
const CROSS_HOLD := 0.15      # s a light push holds the turn where it was (the thumb crossing the centre); longer is a gentle steer, followed the short way
const STALL_CONE := 0.35      # rad (20°): pointing this close to straight behind you is the stall...
const STALL_PHI := 0.5        # ...as long as the nose isn't already swinging round (|phi| under this)
const CUT_BAND := 0.6         # rad (35°): to start turning round, the thumb must be this far past straight up (or down), clearly behind you: near vertical is a steep carve
const CUT_PUSH := 0.5         # ...and pushed at least this far (a light push behind is a gentle carve, not a turnaround)
const CUT_MEMORY := 0.4       # s after turning round (cutting) that carrying on the sweep needs neither: the turn is under way
const BEHIND_TIE := 0.5       # rad (30°): a turn this close to half way round goes round the bottom, whichever way is shorter
const FOAM_REACH := 1.5       # m ahead of the curl the whitewater pile already reaches: a rebound counts from here
const FOAM_HOLD := 1.0        # m behind the curl the whitewater shoves you along at, rather than letting you plough deeper
const FOAM_MAX := 2.0         # s in the whitewater before it buries you
const FOAM_DRAG := 1.5        # 1/s: pushing back into the whitewater stops you (decel = this * v)
const FOAM_SPEED := 13.0      # m/s the whitewater throws you forward at once you've rebounded (faster than the curl peels, so you get out)
const REBOUND_GRACE := 2.0    # s from hitting the foam you can stay in it while you come around and get going
const FOAM_SQUARE := 0.35     # rad: in the foam facing back, a board within this of level is pointing straight into it...
const FOAM_SQUARE_TIME := 0.12  # s ...and squared up to it this long (not turning off it) is a wipeout: the foam hits you head on
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
# hitting the lip: carve up high, then snap the nose back down
const LIP_ZONE := 0.78        # t: climbing above this, nose up, loads a lip hit
const LIP_UP := 0.45          # rad: the nose must be pointing at least this far up the face to load it
const LIP_DOWN := -0.3        # rad: ...and come back down to this...
const LIP_WINDOW := 0.7       # s ...within this of being up there, with the thumb pointing down the face
const LIP_MIN_SPEED := 8.0    # m/s: slower than this the turn throws no spray and scores nothing
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
var cutting := false      # pointing behind the board: driving the nose round past vertical
var _aim := Vector2.ZERO
var _thumb_ang := 0.0        # where the thumb points, world angle, unwrapped: a sweep round keeps adding up
var _board_ang := 0.0        # the board's heading, world angle, unwrapped
var _was_steering := false
var _since_cut := 10.0     # s since the board was last turning round (cutting)
var _was_sweeping := false   # last tick the thumb was pushed out far enough for its angle to count as a sweep
var _light_time := 0.0       # s the thumb has been near the stick's centre
var _stall_hold := false     # the thumb landed straight behind a level board: stall until it moves off
var _spin_latched := false   # the thumb was sideways at takeoff: no spin until it's let go
var _cut_back := false    # turned to face the curl since you last rode down the line
var _rebounded := false   # this cutback bounced off the whitewater
var _rebound_time := -10.0
var _foam_time := 0.0
var _was_near_foam := false
var _foam_square := 0.0   # s squared up to the whitewater, facing back and not turning off it
var _lip_loaded := -10.0  # clock when the board was last high on the face, nose up (a lip hit to come)
var _lip_peak := 0.0      # steepest the nose pointed up while loaded
var _lip_top := false     # reached the very top (t = 1): Off the Lip rather than a Snap
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
var lip_hidden := false   # the lip curtain is between the camera and the surfer (drawn x-ray)

## Surfer x as drawn this frame (blended between ticks). Use it for anything
## visual, such as the camera, so it doesn't stutter.
var vis_x := 0.0

var _rig: Node3D
var _spray: CPUParticles3D
var _lip_spray: CPUParticles3D   # the fan thrown off the tail when you hit the lip
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
	cutting = false
	_cut_back = false
	_rebounded = false
	_rebound_time = -10.0
	_foam_time = 0.0
	_was_near_foam = false
	_foam_square = 0.0
	_lip_loaded = -10.0
	_lip_top = false
	_was_steering = false
	_was_sweeping = false
	_since_cut = 10.0
	_light_time = 0.0
	_stall_hold = false
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


## One fixed physics tick. aim is where the left thumb points, in screen terms:
## x toward down the line (right), y up the face; its length (0..1) is how
## hard. pump is 0..1 (the right thumb).
func step(dt: float, aim := Vector2.ZERO, pump := 0.0) -> void:
	_save_prev()
	_clock += dt
	_aim = aim.limit_length(1.0)
	match state:
		RIDING: _step_riding(dt, _aim, pump)
		AIR: _step_air(dt, _aim)
		WIPEOUT: _step_wipeout(dt)


func _step_riding(dt: float, aim: Vector2, pump: float) -> void:
	var d: float = x - wave.curl_x
	var slope: float = wave.slope_at(x, t)
	var flen: float = wave.face_length(x)
	var in_foam := d < 0.0
	var near_foam := d < FOAM_REACH
	if near_foam and facing < 0.0 and not _was_near_foam:
		_rebound_time = _clock   # reached the whitewater facing back: you've got a moment to turn off it
	_was_near_foam = near_foam

	# Point the nose. want is the thumb's direction measured from the way the
	# board faces: 0 = ahead, + up the face, ±PI = straight behind you.
	var strength := aim.length()
	var steering := strength > AIM_DEAD
	var stall := 0.0
	var target_rate := 0.0
	cutting = false
	# World angles (x down the line, y up the face), unwrapped so a sweep of
	# the thumb round the stick keeps counting past a half turn.
	var board_world := phi if facing > 0.0 else PI - phi
	_board_ang += wrapf(board_world - _board_ang, -PI, PI)
	var sweeping := strength >= SWEEP_PUSH
	if steering:
		var raw := aim.angle()
		var step_ang := wrapf(raw - _thumb_ang, -PI, PI)
		_light_time = 0.0 if sweeping else _light_time + dt
		if not _was_steering or absf(step_ang) > PI / 2.0 or (sweeping and not _was_sweeping) \
				or _light_time > CROSS_HOLD:
			# A fresh touch, the thumb coming back out from the middle of the
			# stick, or a light push held: measure from the board the short way.
			# Crossing the middle (pointing back down the line after a cutback)
			# swings the angle round whichever side of the centre the thumb
			# passes, a few pixels either way, so it must never decide the turn.
			# Nearly straight behind, "the short way" is a coin toss: go round
			# the bottom (downhill, keeping your speed), never up into the lip.
			# Only a fresh touch can be the stall: straight behind a level
			# board, sit back on the tail.
			var rel := wrapf(raw - _board_ang, -PI, PI)
			if absf(rel) > PI - BEHIND_TIE:
				var ccw := wrapf(rel, 0.0, TAU)
				rel = ccw if wrapf(-PI / 2.0 - _board_ang, 0.0, TAU) < ccw else ccw - TAU
			_thumb_ang = _board_ang + rel
			if not _was_steering:
				_stall_hold = absf(rel) > PI - STALL_CONE and absf(phi) < STALL_PHI
		elif not sweeping:
			pass   # crossing the middle: hold the turn where it was for a moment
		else:
			_thumb_ang += step_ang
			if _stall_hold:
				var rel := wrapf(raw - _board_ang, -PI, PI)
				if absf(rel) <= PI - STALL_CONE:
					_stall_hold = false   # moved off straight back: turn the way it went
					_thumb_ang = _board_ang + rel
		var want := atan2(aim.y, aim.x * facing)
		var diff := _thumb_ang - _board_ang
		# Turning round starts only with the thumb clearly behind you (past
		# CUT_BAND beyond vertical) and pushed: straight up a pixel to the
		# left is a steep carve, not a cutback (a recorded ride turned round on
		# a light push at 91°). Once turning, it carries on as the sweep goes.
		# Starting is about where the thumb points (want), not how far the board
		# is from it: bouncing off the lip swings the nose down, and that
		# mustn't read as the thumb being behind you.
		var under_way := _since_cut < CUT_MEMORY
		var turn_round: bool = (absf(want) > PI / 2.0 + CUT_BAND and strength >= CUT_PUSH) \
				or (under_way and (absf(want) > PI / 2.0 or absf(diff) > PI / 2.0))
		if _stall_hold:
			stall = strength
		elif not turn_round:
			# Ahead of you: carve round to it, capped short of vertical. How far
			# you push is how far round: a small push angles the board part way
			# toward your thumb (a small adjustment), a full one all the way.
			# Coming out of a turn-around the nose keeps the cutback's pace.
			var cap := CUTBACK_TURN if absf(phi) > MAX_PHI else TURN
			var target := clampf(want, -MAX_PHI, MAX_PHI) * strength
			target_rate = clampf((target - phi) * AIM_GAIN, -1.0, 1.0) * cap
		else:
			# Behind you, or a sweep that's gone further round: the nose follows
			# the thumb's sweep, the same way round, past vertical. A reverse C
			# turns you up and over to face the curl; keep sweeping (down, then
			# toward the original direction) and it carries on round the bottom
			# and back down the line.
			cutting = true
			var world_rate := clampf(diff * AIM_GAIN, -1.0, 1.0) * CUTBACK_TURN * strength
			target_rate = facing * world_rate   # phi is measured from facing
	# For drawing (lean, spray), in world terms: the way the board is actually
	# turning. phi is measured from facing, so its sign flips when you pass
	# vertical in a cutback, but the turn (and the lean into it) doesn't.
	_steer = clampf(facing * target_rate / TURN, -1.0, 1.0)
	_was_steering = steering
	_since_cut = 0.0 if cutting else _since_cut + dt
	_was_sweeping = steering and sweeping
	# Turns build up and ease off rather than switching on and off instantly.
	turn_rate = lerpf(turn_rate, target_rate, 1.0 - exp(-TURN_RESPONSE * dt))
	var was_carving := absf(phi) <= MAX_PHI
	phi += turn_rate * dt
	if not cutting and was_carving:
		phi = clampf(phi, -MAX_PHI, MAX_PHI)   # a normal carve stops at the cap
	if absf(phi) >= PI / 2.0:
		# Past vertical: you're now facing the other way. phi is measured from
		# the facing direction, so mirror it, and the same rotation now runs it back.
		facing = -facing
		phi = signf(phi) * (PI - absf(phi))
		turn_rate = -turn_rate
		if facing > 0.0 and near_foam and _clock - _rebound_time < REBOUND_GRACE:
			_rebounded = true
	var turning_around := cutting or absf(phi) > MAX_PHI
	if not steering:
		phi = lerpf(phi, 0.0, 1.0 - exp(-RECENTER * dt))
	if not turning_around and absf(phi) > MAX_PHI:
		phi = move_toward(phi, signf(phi) * MAX_PHI, TURN * dt)

	# The pump adds its own small up-then-down motion on top of the steered line.
	var pump_a := _pump_accel(dt, pump, flen)
	var h := heading()

	# Laid over on the rail through a turn-around: the arc stays shallow on the face.
	var lift := lerpf(1.0, CUTBACK_LIFT, smoothstep(0.0, 0.6, absf(phi))) if turning_around else 1.0
	var pocket := 0.4 + 1.2 * exp(-maxf(d, 0.0) / 18.0)
	var a := -G * sin(slope) * sin(h) * lift + WAVE_PUSH * sin(slope) * pocket - C1 * v - C2 * v * v
	if t < 0.06:
		a -= BOG  # bogging in the trough and out on the flats
	if turning_around:
		a -= CARVE_DRAG * absf(turn_rate) * v
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

	if t >= 1.0 and turning_around:
		t = 1.0  # turning around off the top: carry on with the turn
	elif t >= 1.0:
		if h > 0.6 and v > 9.0:
			_launch()
			return
		t = 1.0
		if h > 0.35:
			_lip_top = true   # bounced off the top: scores once you snap it down (_check_lip_hit)
			v *= 0.92
		phi = minf(-absf(phi) * 0.8, -0.25)
		turn_rate = 0.0
	_check_cutback()
	_check_lip_hit(steering and atan2(aim.y, aim.x * facing) < -0.2, turning_around)

	var k: float = wave.k_at(x)
	in_barrel = d > 0.0 and d < 7.0 and t > 0.2 and t < 0.7 and k > 0.55
	if in_barrel:
		# deeper = closer behind the curtain to where the lip is landing
		var lip_cover := clampf((k - 0.55) / 0.35, 0.0, 1.0)
		barrel_depth = clampf((7.0 - d) / 6.0, 0.0, 1.0) * lerpf(0.6, 1.0, lip_cover)
	else:
		barrel_depth = 0.0

	if in_foam:
		# The whitewater only gives you a chance if you hit it facing back and
		# turn off it (low on the face) before it gets you.
		var rebounding := _clock - _rebound_time < REBOUND_GRACE
		if (t > 0.8 and not turning_around) or not rebounding:
			_wipeout("The whitewater caught you" if t < 0.3 else "The lip landed on you")
			return
		# Pointing straight into it, not turning off it: it hits you head on.
		# Bouncing up off it (nose up the face) or turning round is the rebound.
		if facing < 0.0 and not turning_around and absf(heading()) < FOAM_SQUARE:
			_foam_square += dt
			if _foam_square >= FOAM_SQUARE_TIME:
				_wipeout("Ran straight into the whitewater")
				return
		else:
			_foam_square = 0.0
		if _foam_time > FOAM_MAX:
			_wipeout("Buried in the whitewater")
			return
	else:
		_foam_square = 0.0
	if t < -FLATS_OUT:
		_wipeout("Rode off the front of the wave")
	elif v < MIN_SPEED:
		_wipeout("Buried in the whitewater" if in_foam else "Lost the wave")


## Cutback scoring: turning to face the curl, then back down the line.
func _check_cutback() -> void:
	if facing < 0.0:
		_cut_back = true
	elif _cut_back:
		_cut_back = false
		if _rebounded:
			trick_landed.emit("Roundhouse Cutback", 700)
		else:
			trick_landed.emit("Cutback", 400)
		_rebounded = false


## Hitting the lip: carve up high with the nose up, then snap it back down the
## face (thumb pointing down) before the moment's gone. That's the hit that
## throws a fan of spray off the tail. Reaching the very top first makes it an
## Off the Lip, otherwise it's a Snap. The harder you were driving up and the
## faster you're going, the more it scores.
func _check_lip_hit(thumb_down: bool, turning_around: bool) -> void:
	var h := heading()
	if turning_around:
		_lip_loaded = -10.0   # a cutback over the top scores as a cutback
		_lip_top = false
		return
	if t >= LIP_ZONE and h >= LIP_UP:
		if _clock - _lip_loaded > LIP_WINDOW:
			_lip_peak = 0.0
		_lip_loaded = _clock
		_lip_peak = maxf(_lip_peak, h)
		return
	if _clock - _lip_loaded > LIP_WINDOW:
		_lip_top = false
		return
	if h <= LIP_DOWN and thumb_down:
		_lip_loaded = -10.0
		var top := _lip_top
		_lip_top = false
		if v < LIP_MIN_SPEED:
			return
		# How hard: the arc from the steepest nose-up to now, and the speed through it.
		var arc := _lip_peak - h
		var power := clampf(arc / 1.0, 0.6, 1.3) * clampf(v / 12.0, 0.7, 1.3)
		throw_spray(power)
		trick_landed.emit("Off the Lip" if top else "Snap", int(roundf((350.0 if top else 250.0) * power / 10.0)) * 10)


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
	_lip_loaded = -10.0
	_lip_top = false
	phi = heading()
	pump_phase = PUMP_IDLE
	pushing = false
	pump_pitch = 0.0
	_kick_left = 0.0
	in_barrel = false
	barrel_depth = 0.0
	air_h = 0.0
	air_vy = 3.0 + v * sin(heading()) * 0.35
	_spin_latched = absf(_aim.x) > 0.3
	spin = 0.0
	_air_time = 0.0
	t = 1.0


## In the air, the thumb sideways spins you. If it was already sideways at
## takeoff (coming off a turn), it doesn't spin you until you let it go.
func _step_air(dt: float, aim: Vector2) -> void:
	if absf(aim.x) < 0.3:
		_spin_latched = false
	var steer := 0.0 if _spin_latched else -aim.x
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
	_spray.emitting = state == RIDING and v > 5.0 and (absf(_steer) > 0.3 or _dig_vis > 0.3 or cutting)
	_update_highlight(delta)


## Barrel highlight: an x-ray silhouette drawn through the lip plus a halo,
## shifting cyan -> gold as you get deeper. Also shown (cyan) whenever the lip
## curtain hangs between the camera and you, or you're in the whitewater during
## a rebound, so you can always see yourself.
func _update_highlight(delta: float) -> void:
	var target := barrel_depth if in_barrel else 0.0
	if state == RIDING and _foam_time > 0.0:
		target = 0.45  # in the whitewater: show the surfer through the foam
	# The lip hanging between the camera and you: show you through it.
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	lip_hidden = state != WIPEOUT and cam != null and wave.lip_hides(cam.global_position, global_position + global_transform.basis.y * 0.8)
	if lip_hidden:
		target = maxf(target, 0.45)
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

	# the fan of spray a lip hit throws off the tail, up and back over the wave
	_lip_spray = CPUParticles3D.new()
	_lip_spray.amount = 160
	_lip_spray.lifetime = 1.1
	_lip_spray.one_shot = true
	_lip_spray.explosiveness = 0.8
	_lip_spray.local_coords = false
	_lip_spray.position = Vector3(0.0, 0.05, 0.8)
	_lip_spray.direction = Vector3(0.0, 1.0, 0.7)
	_lip_spray.spread = 40.0
	_lip_spray.gravity = Vector3(0, -9.8, 0)
	_lip_spray.scale_amount_min = 0.5
	_lip_spray.scale_amount_max = 1.3
	_lip_spray.mesh = drop
	_lip_spray.emitting = false
	_rig.add_child(_lip_spray)


## Throw the lip hit's fan of spray. power ~0.5..1.5 sets how far it flies.
func throw_spray(power: float) -> void:
	_lip_spray.initial_velocity_min = 4.0 * power
	_lip_spray.initial_velocity_max = 9.0 * power
	_lip_spray.restart()
	_lip_spray.emitting = true
