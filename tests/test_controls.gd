extends SceneTree
## Scripted-input checks on the controls, using the real input actions.
##
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_controls.gd

var _failures := 0
var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _held_up_air_lands_clean()
	await _tap_restart_does_not_reset()
	await _hold_restart_resets()
	if _failures == 0:
		print("PASS test_controls")
		quit(0)
	else:
		printerr("FAIL test_controls: %d" % _failures)
		quit(1)


func _fresh() -> void:
	seed(99)
	main._reset()
	for a in ["carve_up", "carve_down", "spin_left", "spin_right", "pump", "restart"]:
		Input.action_release(a)
	await physics_frame


## Holding up to hit the lip, and still holding it in the air, must not spin
## you at all. (Without the latch it gives a random spin: an accidental 360 or
## an under-rotated wipeout, depending on speed.)
func _held_up_air_lands_clean() -> void:
	await _fresh()
	var s = main.surfer
	var wipe := [""]
	var on_wipe := func(reason: String): wipe[0] = reason
	s.wiped_out.connect(on_wipe)
	var launched := false
	var landed := false
	var max_spin := 0.0
	Input.action_press("carve_up")
	for i in 600:
		await physics_frame
		if s.state == s.AIR:
			launched = true
			max_spin = maxf(max_spin, absf(s.spin))
		elif launched and s.state == s.RIDING:
			landed = true
			break
		if wipe[0] != "":
			break
	Input.action_release("carve_up")
	s.wiped_out.disconnect(on_wipe)
	if not launched:
		_fail("holding up never launched an air (state %d, v %.1f)" % [s.state, s.v])
	elif not landed:
		_fail("held-up air did not land clean: '%s'" % wipe[0])
	elif max_spin > 0.01:
		_fail("holding up through takeoff spun the surfer %.0f degrees" % rad_to_deg(max_spin))


func _tap_restart_does_not_reset() -> void:
	await _fresh()
	for i in 60:
		await physics_frame
	var x: float = main.surfer.x
	Input.action_press("restart")
	for i in 5:
		await physics_frame
	Input.action_release("restart")
	await physics_frame
	if main.surfer.x < x:
		_fail("a short tap of restart reset the ride")


func _hold_restart_resets() -> void:
	await _fresh()
	for i in 60:
		await physics_frame
	Input.action_press("restart")
	for i in 40:
		await physics_frame
	Input.action_release("restart")
	if main.ride_time > 0.5:
		_fail("holding restart for 0.66 s did not reset (ride_time %.2f)" % main.ride_time)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("  " + msg)
