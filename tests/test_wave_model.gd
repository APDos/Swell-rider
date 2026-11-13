extends SceneTree
## CPU-only checks on scripts/wave.gd: the derived helpers (face_up, slope_at)
## must agree with face_point, which is the function shared with the shader.
## If someone edits face_point and forgets the helpers, this fails.
## Also checks lip_hides: the lip curtain hides a surfer high right by the curl
## from a shore-side camera, but never one on the open face or out front.
##
##   godot --headless --path . -s res://tests/test_wave_model.gd

const WaveScript := preload("res://scripts/wave.gd")
# Vector3 is single precision, so the step has to be big enough that rounding
# noise stays well under TOL (central differences keep truncation error tiny).
const H := 1e-3     # finite-difference step in t
const TOL := 1e-3

var _failures := 0


func _initialize() -> void:
	var wave = WaveScript.new()
	for c in [[4.8, 0.0, Vector3(1e6, 1e6 + 1.0, 0.0)], [5.2, 10.0, Vector3(60.0, 80.0, 0.95)]]:
		wave.base_height = c[0]
		wave.curl_x = c[1]
		wave.closeout = c[2]
		for i in 120:
			var x: float = wave.curl_x - 20.0 + i * 1.5
			# face_up and slope_at clamp t at 0.02 near the trough, so start above that.
			for j in 10:
				var t := 0.05 + 0.1 * j
				var tangent: Vector3 = wave.face_point(x, t + H) - wave.face_point(x, t - H)
				var up: Vector3 = wave.face_up(x, t)
				_check(up.distance_to(tangent.normalized()) < TOL, "face_up", x, t, up, tangent.normalized())
				var slope := atan2(tangent.y, -tangent.z)
				_check(absf(wave.slope_at(x, t) - slope) < TOL, "slope_at", x, t, wave.slope_at(x, t), slope)
	_check_lip_hides(wave)
	wave.free()
	if _failures == 0:
		print("PASS test_wave_model")
		quit(0)
	else:
		printerr("FAIL test_wave_model: %d mismatches" % _failures)
		quit(1)


func _check_lip_hides(wave) -> void:
	wave.base_height = 4.8
	wave.curl_x = 0.0
	wave.closeout = Vector3(1e6, 1e6 + 1.0, 0.0)
	# Camera roughly where main.gd puts it: shore side, about mid-wave height.
	var eye_for := func(x: float) -> Vector3: return Vector3(x - 1.0, 4.0, 18.0)
	var up := Vector3(0, 0.8, 0)
	var high_by_curl: Vector3 = wave.face_point(4.0, 0.85) + up
	if not wave.lip_hides(eye_for.call(4.0), high_by_curl):
		_failures += 1
		printerr("  lip_hides: a surfer high on the face right by the curl should be behind the lip")
	for p in [[40.0, 0.5], [40.0, 0.9], [4.0, -0.3], [80.0, 0.6]]:
		var pt: Vector3 = wave.face_point(p[0], p[1]) + up
		if wave.lip_hides(eye_for.call(p[0]), pt):
			_failures += 1
			printerr("  lip_hides: nothing should hide a surfer at x=%.0f t=%.2f" % [p[0], p[1]])


func _check(ok: bool, what: String, x: float, t: float, got, want) -> void:
	if ok:
		return
	_failures += 1
	if _failures <= 5:
		printerr("  %s at x=%.2f t=%.2f: %s, expected %s" % [what, x, t, got, want])
