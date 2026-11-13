extends Node3D
## Surfer controller. Physics run in "face space": x along the line, t up the face
## (0 trough .. 1 lip), v speed, phi heading (0 = straight down the line,
## + = angled up the face, - = angled down).
##
## step() advances the simulation and is called at the fixed physics rate.
## update_visual() is called every rendered frame and draws the surfer blended
## between the last two physics ticks, so motion is smooth at any frame rate.

signal trick_landed(trick_name: String, points: int)
signal wiped_out(reason: String)

enum { RIDING, AIR, WIPEOUT }

# --- tuning -------------------------------------------------------------------
const G := 11.0          # gravity along the face
const WAVE_PUSH := 5.6   # energy from the wave, strongest in the pocket
const C1 := 0.12         # linear drag
const C2 := 0.022        # quadratic drag
const TURN := 2.8        # rad/s at full steer
const TURN_RESPONSE := 9.0  # 1/s: how quickly a turn builds up and eases off
const RECENTER := 0.7    # 1/s: with no steer input, heading eases back toward straight
const MAX_PHI := 1.35
const DRIFT := 0.10      # water rising up the face carries you toward the lip (t/s)
const PUMP_BOOST := 1.3
const PUMP_COOLDOWN := 0.55
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
var _pump_ready := 0.0
var _lean := 0.0
var _wipe_pos := Vector3.ZERO
var _wipe_vel := Vector3.ZERO
var _wipe_spin := Vector3.ZERO

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


## One fixed physics tick. steer is -1..1 (carve down/up on the face, spin in the air).
func step(dt: float, steer: float, pump: bool) -> void:
	_save_prev()
	_clock += dt
	_steer = steer
	match state:
		RIDING: _step_riding(dt, steer, pump)
		AIR: _step_air(dt, steer)
		WIPEOUT: _step_wipeout(dt)


func _step_riding(dt: float, steer: float, pump: bool) -> void:
	var d: float = x - wave.curl_x
	var slope: float = wave.slope_at(x, t)
	var flen: float = wave.face_length(x)

	# Turns build up and ease off rather than switching on and off instantly.
	turn_rate = lerpf(turn_rate, steer * TURN, 1.0 - exp(-TURN_RESPONSE * dt))
	phi += turn_rate * dt
	if absf(steer) < 0.1:
		phi = lerpf(phi, 0.0, 1.0 - exp(-RECENTER * dt))
	phi = clampf(phi, -MAX_PHI, MAX_PHI)

	var pocket := 0.4 + 1.2 * exp(-maxf(d, 0.0) / 18.0)
	var a := -G * sin(slope) * sin(phi) + WAVE_PUSH * sin(slope) * pocket - C1 * v - C2 * v * v
	if t < 0.06:
		a -= 3.0  # bogging in the flats
	v = maxf(v + a * dt, 0.0)

	if pump and _clock > _pump_ready and t > 0.25 and t < 0.85:
		v += PUMP_BOOST * clampf(sin(slope) * 1.4, 0.3, 1.0)
		_pump_ready = _clock + PUMP_COOLDOWN

	t += (v * sin(phi) / flen + DRIFT) * dt
	x += v * cos(phi) * dt

	if t >= 1.0:
		if phi > 0.6 and v > 9.0:
			_launch()
			return
		t = 1.0
		if v > 8.0 and phi > 0.35 and _clock - _last_trick > 0.8:
			_last_trick = _clock
			trick_landed.emit("Off the Lip", 250)
			v *= 0.92
		phi = minf(-absf(phi) * 0.8, -0.25)
		turn_rate = 0.0
	if t <= 0.0:
		t = 0.0
		phi = maxf(phi, 0.0)

	var k: float = wave.k_at(x)
	in_barrel = d > 0.0 and d < 7.0 and t > 0.2 and t < 0.7 and k > 0.55
	if in_barrel:
		# deeper = closer behind the curtain to where the lip is landing
		var lip_cover := clampf((k - 0.55) / 0.35, 0.0, 1.0)
		barrel_depth = clampf((7.0 - d) / 6.0, 0.0, 1.0) * lerpf(0.6, 1.0, lip_cover)
	else:
		barrel_depth = 0.0

	if d < 0.0:
		_wipeout("The lip landed on you")
	elif v < MIN_SPEED:
		_wipeout("Lost the wave")


func _launch() -> void:
	state = AIR
	in_barrel = false
	barrel_depth = 0.0
	air_h = 0.0
	air_vy = 3.0 + v * sin(phi) * 0.35
	spin = 0.0
	_air_time = 0.0
	t = 1.0


func _step_air(dt: float, steer: float) -> void:
	_air_time += dt
	x += v * maxf(cos(phi), 0.45) * dt
	air_vy -= AIR_GRAVITY * dt
	air_h += air_vy * dt
	spin += steer * SPIN_RATE * dt
	if x - wave.curl_x < 0.0:
		_wipeout("Swallowed mid-air")
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
		fwd = (along * cos(phi) + up_face * sin(phi)).normalized()
		global_position = p + n * 0.05
	else:
		fwd = Vector3(1, 0.25, 0).normalized()
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

	_rig.rotation = Vector3(0, 0, _lean * 0.45 if state == RIDING else 0.0)
	_spray.emitting = state == RIDING and absf(_steer) > 0.3 and v > 7.0
	_update_highlight(delta)


## Barrel highlight: an x-ray silhouette drawn through the lip plus a halo,
## shifting cyan -> gold as you get deeper.
func _update_highlight(delta: float) -> void:
	var target := barrel_depth if in_barrel else 0.0
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
	_part(torso, suit, Vector3(0.05, 1.05, 0), Vector3(0, 0, -0.25))

	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.24
	_part(head, skin, Vector3(0.12, 1.5, -0.05))

	var arms := BoxMesh.new()
	arms.size = Vector3(0.09, 0.09, 1.25)
	_part(arms, suit, Vector3(0.05, 1.22, 0), Vector3(0.15, 0, 0))

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
