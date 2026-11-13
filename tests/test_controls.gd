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
	await _carve_down_is_not_a_pump()
	await _pump_key_lifts_then_pushes()
	await _pump_tap_is_only_a_flick()
	await _pump_hold_uses_up_stroke()
	if _failures == 0:
		print("PASS test_controls")
		quit(0)
	else:
		printerr("FAIL test_controls: %d" % _failures)
		quit(1)


func _fresh() -> void:
	seed(99)
	main.rider = null
	main._reset()
	for a in ["carve_up", "carve_down", "spin_left", "spin_right", "stall", "pump", "restart"]:
		Input.action_release(a)
	await physics_frame


## After pumping up speed, holding up to hit the lip, and still holding it in
## the air, must not spin
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
	# Airs need speed, so pump some up on autopilot first, then take over.
	main.rider = main.Autopilot.new()
	for i in 240:
		await physics_frame
	main.rider = null
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


## Pump-test setup: hold a steady line high on the face with the curl far
## behind, so the pump key is the only thing changing speed.
func _pump_setup() -> void:
	await _fresh()
	main.rider = main.Autopilot.new("none")   # steers a steady line; we press pump ourselves
	main.wave.curl_x = -1000.0
	main.surfer.t = 0.7
	main.surfer.v = 10.0
	await physics_frame


func _carve_down_is_not_a_pump() -> void:
	await _fresh()
	Input.action_press("carve_down")
	var pushed := false
	for i in 40:
		await physics_frame
		pushed = pushed or main.surfer.pump_phase != main.surfer.PUMP_IDLE
	Input.action_release("carve_down")
	if pushed:
		_fail("holding carve-down started a pump; steering and pumping should be separate")


func _pump_key_lifts_then_pushes() -> void:
	await _pump_setup()
	var s = main.surfer
	var lifted := false
	var pushed := false
	var max_pitch := 0.0
	var min_pitch := 0.0
	main.rider = PumpHold.new(main.Autopilot.new("none"))
	for i in 30:
		await physics_frame
		lifted = lifted or s.pump_phase == s.PUMP_LIFT
		pushed = pushed or s.pump_phase == s.PUMP_PUSH
		max_pitch = maxf(max_pitch, s.pump_pitch)
		min_pitch = minf(min_pitch, s.pump_pitch)
	if not (lifted and pushed):
		_fail("holding pump should lift then push (lifted %s, pushed %s)" % [lifted, pushed])
	if max_pitch < 0.15 or min_pitch > -0.15:
		_fail("pump should lift the nose up the face then drive it down (pitch %.2f..%.2f)" % [min_pitch, max_pitch])


func _pump_tap_is_only_a_flick() -> void:
	await _pump_setup()
	var s = main.surfer
	main.rider = PumpHold.new(main.Autopilot.new("none"), 0.08)   # released inside the lift
	var pushed := false
	for i in 30:
		await physics_frame
		pushed = pushed or s.pushing
	if pushed:
		_fail("a tap released during the lift should not push")


func _pump_hold_uses_up_stroke() -> void:
	await _pump_setup()
	var s = main.surfer
	main.rider = PumpHold.new(main.Autopilot.new("none"), 3.0)
	var bogged := false
	for i in 150:
		await physics_frame
		if s.pushing and s.stroke <= 0.0:
			bogged = true
			break
	if not bogged:
		_fail("holding the pump key should eventually use up the leg stroke")


## Wraps a rider: same steering, but holds the pump key for hold_s seconds.
class PumpHold:
	var inner
	var hold_s: float
	var _t := 0.0
	func _init(rider, hold := 10.0) -> void:
		inner = rider
		hold_s = hold
	func steer(surfer) -> float:
		return inner.steer(surfer)
	func pump(_surfer) -> float:
		_t += 1.0 / Engine.physics_ticks_per_second
		return 1.0 if _t <= hold_s else 0.0


func _fail(msg: String) -> void:
	_failures += 1
	printerr("  " + msg)
