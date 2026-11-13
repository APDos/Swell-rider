extends Node3D
## Game loop: builds the world in code, runs the curl, scoring, camera and HUD.

const WaveScript := preload("res://scripts/wave.gd")
const SurferScript := preload("res://scripts/surfer.gd")
const HudScript := preload("res://scripts/hud.gd")

enum { PLAYING, WIPEOUT }

const PEEL_BASE := 9.0       # m/s the break peels down the line
const PEEL_CLOSEOUT := 28.0  # m/s through a closeout section

var state := PLAYING
var wave
var surfer
var hud
var cam: Camera3D
var ocean: MeshInstance3D
var curl_spray: CPUParticles3D

var score := 0.0
var best := 0.0
var ride_time := 0.0
var barrel_time := 0.0
var barrel_points := 0.0
var barrel_max_depth := 0.0

# dev / testing: run with `-- --autopilot --shot=res://shot.png`
var autopilot := false
var barrel_test := false  # dev: pins the curl just behind the surfer
var _look := Vector3.ZERO
var shot_path := ""
var _shots_taken := 0
var _space_prev := false


func _ready() -> void:
	randomize()
	var args := OS.get_cmdline_user_args()
	autopilot = "--autopilot" in args
	barrel_test = "--barreltest" in args
	for a in args:
		if a.begins_with("--shot="):
			shot_path = a.substr(7)

	_build_environment()

	wave = WaveScript.new()
	add_child(wave)

	ocean = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.subdivide_width = 120
	plane.subdivide_depth = 120
	ocean.mesh = plane
	var om := ShaderMaterial.new()
	om.shader = load("res://shaders/ocean.gdshader")
	ocean.material_override = om
	add_child(ocean)

	surfer = SurferScript.new()
	surfer.wave = wave
	add_child(surfer)
	surfer.trick_landed.connect(_on_trick)
	surfer.wiped_out.connect(_on_wipeout)

	curl_spray = _make_curl_spray()
	add_child(curl_spray)

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 700.0
	add_child(cam)

	hud = HudScript.new()
	add_child(hud)

	_reset()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.47, 0.80)
	sm.sky_horizon_color = Color(0.72, 0.84, 0.93)
	sm.ground_horizon_color = Color(0.55, 0.7, 0.8)
	sm.ground_bottom_color = Color(0.05, 0.15, 0.25)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.82, 0.92)
	env.fog_density = 0.0035
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -55, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _make_curl_spray() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 140
	p.lifetime = 1.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.1
	p.direction = Vector3(-0.3, 1.0, 0.5)
	p.spread = 55.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -6.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.1
	var m := SphereMesh.new()
	m.radius = 0.14
	m.height = 0.28
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.97, 1.0)
	mat.roughness = 0.9
	m.material = mat
	p.mesh = m
	return p


func _reset() -> void:
	state = PLAYING
	score = 0.0
	ride_time = 0.0
	barrel_time = 0.0
	barrel_points = 0.0
	barrel_max_depth = 0.0
	wave.base_height = randf_range(4.2, 5.4)
	wave.curl_x = 0.0
	_schedule_closeout()
	surfer.reset(13.0)
	hud.hide_message()
	hud.set_barrel(false, 0.0, 0.0)
	_snap_camera()


func _schedule_closeout() -> void:
	var x0: float = wave.curl_x + randf_range(150.0, 280.0)
	wave.closeout = Vector3(x0, x0 + randf_range(12.0, 24.0), 0.95)


## Riding: up/down carves up/down the face. In the air any direction spins.
func _input_steer() -> float:
	var s := Input.get_axis("ui_down", "ui_up")
	if Input.is_physical_key_pressed(KEY_W):
		s += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		s -= 1.0
	if surfer.state == surfer.AIR:
		s += Input.get_axis("ui_right", "ui_left")
		if Input.is_physical_key_pressed(KEY_A):
			s += 1.0
		if Input.is_physical_key_pressed(KEY_D):
			s -= 1.0
	return clampf(s, -1.0, 1.0)


func _autopilot_steer() -> float:
	if surfer.state == surfer.AIR:
		return 1.0
	var tt := 0.45 if barrel_test else 0.62
	var target_phi: float = clampf((tt - surfer.t) * 2.5, -0.7, 0.7) - 0.1
	return clampf((target_phi - surfer.phi) * 3.0, -1.0, 1.0)


func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)

	if Input.is_physical_key_pressed(KEY_ESCAPE):
		get_tree().quit()

	if state == WIPEOUT:
		if Input.is_action_just_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_R):
			_reset()
	elif Input.is_physical_key_pressed(KEY_R) and ride_time > 0.5:
		_reset()

	var steer := _autopilot_steer() if autopilot else _input_steer()
	var space := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_action_pressed("ui_select")
	var pump := space and not _space_prev
	_space_prev = space

	if barrel_test and state == PLAYING:
		wave.curl_x = surfer.x - 3.0
	else:
		_update_curl(dt)
	surfer.step(dt, steer, pump)

	if state == PLAYING:
		ride_time += dt
		var d: float = surfer.x - wave.curl_x
		var mult := 1.0 + 2.0 * exp(-maxf(d, 0.0) / 10.0)
		score += surfer.v * mult * dt * 2.0
		if surfer.in_barrel:
			barrel_time += dt
			barrel_points += (300.0 + 1500.0 * surfer.barrel_depth) * dt
			barrel_max_depth = maxf(barrel_max_depth, surfer.barrel_depth)
		elif barrel_time > 0.0:
			if barrel_time > 0.4:
				_on_trick("Barrel %.1fs · %d%% deep" % [barrel_time, int(barrel_max_depth * 100.0)], int(barrel_points))
			barrel_time = 0.0
			barrel_points = 0.0
			barrel_max_depth = 0.0
		hud.set_barrel(surfer.in_barrel, barrel_time, surfer.barrel_depth)
		hud.set_warning(wave.closeout.x - surfer.x < 70.0 and wave.closeout.y > surfer.x)
		hud.set_stats(score, best, surfer.speed_kmh(), mult)
	else:
		hud.set_warning(false)

	wave.follow(surfer.x)
	ocean.position = Vector3(snappedf(surfer.x, 7.5), -0.06, 0.0)
	var H: float = wave.height_at(wave.curl_x)
	curl_spray.global_position = Vector3(wave.curl_x - 0.5, 0.45 * H, 0.75 * H)
	_update_camera(dt)
	_maybe_screenshot()


func _update_curl(dt: float) -> void:
	var peel := PEEL_BASE + 1.5 * sin(ride_time * 0.35)
	var c: Vector3 = wave.closeout
	if wave.curl_x > c.x - 3.0 and wave.curl_x < c.y:
		peel = PEEL_CLOSEOUT
	wave.curl_x += peel * dt
	if wave.curl_x > c.y + 5.0:
		_schedule_closeout()


## Side-on camera from the shore side: surfer rides left -> right, the curl
## chases from the left. Height is anchored to the wave, not the surfer, so the
## frame stays steady while you carve.
func _cam_target() -> Array:
	var p: Vector3 = surfer.global_position
	var H: float = wave.height_at(surfer.x)
	var dist: float = 8.0 + 0.9 * H + 0.12 * surfer.v
	var look: Vector3 = Vector3(p.x + 1.5, lerpf(H * 0.5, p.y, 0.35), lerpf(H * 0.4, p.z, 0.3))
	var eye: Vector3 = Vector3(p.x - 1.0, H * 0.55 + 1.2, look.z + dist)
	return [eye, look]


func _snap_camera() -> void:
	var tg := _cam_target()
	cam.global_position = tg[0]
	_look = tg[1]
	cam.look_at(_look)


func _update_camera(dt: float) -> void:
	var tg := _cam_target()
	var f := 1.0 - exp(-4.0 * dt)
	var e: Vector3 = cam.global_position.lerp(tg[0], f)
	e.x = lerpf(cam.global_position.x, tg[0].x, 1.0 - exp(-10.0 * dt))  # track along the line tightly
	cam.global_position = e
	_look = _look.lerp(tg[1], f)
	_look.x = tg[1].x
	cam.look_at(_look)


func _on_trick(trick_name: String, points: int) -> void:
	var d: float = surfer.x - wave.curl_x
	var mult := 1.0 + 2.0 * exp(-maxf(d, 0.0) / 10.0)
	var total := int(points * mult)
	score += total
	hud.popup("%s  +%d" % [trick_name, total])


func _on_wipeout(reason: String) -> void:
	state = WIPEOUT
	best = maxf(best, score)
	hud.set_barrel(false, 0.0, 0.0)
	hud.show_message("WIPEOUT\n%s\n\nScore %d   ·   Best %d   ·   %.0fs ride\n\nEnter / R to paddle back out" % [reason, int(score), int(best), ride_time])
	if autopilot:
		_reset()


func _maybe_screenshot() -> void:
	if shot_path == "":
		return
	var times := [2.5, 6.0, 12.0]
	if _shots_taken < times.size() and ride_time > times[_shots_taken]:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path.replace(".png", "_%d.png" % _shots_taken))
		_shots_taken += 1
		if _shots_taken == times.size():
			get_tree().quit()
