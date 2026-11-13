extends SceneTree
## Checks that the GPU wave shape (shaders/wave_shape.gdshaderinc) and the CPU
## copy in scripts/wave.gd agree, and that every shape uniform gets its value
## from wave.gd's SHAPE table.
##
## Needs a real renderer (not --headless):
##   xvfb-run -a godot --rendering-driver opengl3 --path . -s res://tests/test_wave_parity.gd
## Exits 0 on pass, 1 on failure.

const WaveScript := preload("res://scripts/wave.gd")
const PROBE := preload("res://tests/wave_probe.gdshader")

const N_X := 256
const N_T := 9
const QUANTITIES := ["x", "face_y", "face_z", "k", "height", "broken", "lip_y", "lip_z"]
# Uniforms that are per-frame wave state rather than SHAPE entries.
const STATE_UNIFORMS := ["H0", "curl_x", "closeout"]
const PROBE_UNIFORMS := ["x_start", "x_step", "n_t"]
# GPU float32 against CPU float64. 1 mm, or 0.01% of the value if that is bigger.
const ABS_TOL := 1e-3
const REL_TOL := 1e-4

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_uniform_coverage()

	var vp := SubViewport.new()
	vp.size = Vector2i(N_X, N_T * QUANTITIES.size())
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(vp.size)
	var mat := ShaderMaterial.new()
	mat.shader = PROBE
	rect.material = mat
	vp.add_child(rect)
	root.add_child(vp)

	var wave = WaveScript.new()
	# name, base_height, curl_x (world), closeout (world x0, x1, strength), mesh origin x (world)
	var cases := [
		["open face", 4.8, 0.0, Vector3(1e6, 1e6 + 1.0, 0.0), 0.0],
		["closeout ahead", 5.2, 10.0, Vector3(60.0, 80.0, 0.95), 0.0],
		["mesh moved down the line", 4.2, 812.5, Vector3(900.0, 918.0, 0.95), 800.0],
	]
	for c in cases:
		wave.base_height = c[1]
		wave.curl_x = c[2]
		wave.closeout = c[3]
		var origin: float = c[4]
		# Sample from behind the curl (broken water) to well ahead of it.
		var x_start: float = wave.curl_x - origin - 30.0
		var x_step := 200.0 / N_X
		wave.apply_to(mat, origin, wave.curl_x)
		mat.set_shader_parameter("x_start", x_start)
		mat.set_shader_parameter("x_step", x_step)
		mat.set_shader_parameter("n_t", N_T)
		for i in 3:
			await RenderingServer.frame_post_draw
		_compare(c[0], vp.get_texture().get_image(), wave, origin, x_start, x_step)
	wave.free()

	if _failures == 0:
		print("PASS test_wave_parity")
		quit(0)
	else:
		printerr("FAIL test_wave_parity: %d mismatches" % _failures)
		quit(1)


func _check_uniform_coverage() -> void:
	var shape_keys: Array = WaveScript.SHAPE.keys()
	var declared := []
	for u in PROBE.get_shader_uniform_list():
		declared.append(u["name"])
	for name in declared:
		if name in PROBE_UNIFORMS:
			continue
		if name not in shape_keys and name not in STATE_UNIFORMS:
			_fail("uniform '%s' in wave_shape.gdshaderinc has no entry in wave.gd SHAPE" % name)
	for key in shape_keys:
		if key not in declared:
			_fail("wave.gd SHAPE key '%s' has no uniform in wave_shape.gdshaderinc" % key)


func _compare(label: String, img: Image, wave, origin: float, x_start: float, x_step: float) -> void:
	var shown := 0
	for qi in QUANTITIES.size():
		for ti in N_T:
			var t := float(ti) / (N_T - 1)
			var row := qi * N_T + ti
			for i in N_X:
				var x_local := x_start + i * x_step
				var x := x_local + origin
				var want: float
				match QUANTITIES[qi]:
					"x": want = x_local
					"face_y": want = wave.face_point(x, t).y
					"face_z": want = wave.face_point(x, t).z
					"k": want = wave.k_at(x)
					"height": want = wave.height_at(x)
					"broken": want = wave.broken_amt(x)
					"lip_y": want = wave.lip_pos(x, t).y
					"lip_z": want = wave.lip_pos(x, t).z
				var got := _decode(img.get_pixel(i, row))
				var tol := maxf(ABS_TOL, REL_TOL * absf(want))
				# Written so a NaN from the GPU counts as a failure.
				if not (absf(got - want) <= tol):
					_failures += 1
					if shown < 5:
						shown += 1
						printerr("  [%s] %s at x=%.3f t=%.3f: gpu=%.6f cpu=%.6f" % [label, QUANTITIES[qi], x, t, got, want])


static func _decode(c: Color) -> float:
	var b := PackedByteArray()
	b.resize(4)
	# encode_u32 is little-endian, and the shader puts the high byte in R.
	b.encode_u32(0, (c.r8 << 24) | (c.g8 << 16) | (c.b8 << 8) | c.a8)
	return b.decode_float(0)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("  " + msg)
