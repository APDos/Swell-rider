extends SceneTree
## CPU-only checks on scripts/wave.gd: the derived helpers (face_up, slope_at)
## must agree with face_point, which is the function shared with the shader.
## If someone edits face_point and forgets the helpers, this fails.
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
	wave.free()
	if _failures == 0:
		print("PASS test_wave_model")
		quit(0)
	else:
		printerr("FAIL test_wave_model: %d mismatches" % _failures)
		quit(1)


func _check(ok: bool, what: String, x: float, t: float, got, want) -> void:
	if ok:
		return
	_failures += 1
	if _failures <= 5:
		printerr("  %s at x=%.2f t=%.2f: %s, expected %s" % [what, x, t, got, want])
