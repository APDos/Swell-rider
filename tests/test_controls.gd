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
	await _pump_key_drives_then_rises()
	await _pump_tap_is_only_a_flick()
	await _long_hold_settles_lower()
	await _no_input_holds_height()
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


func _pump_key_drives_then_rises() -> void:
	await _pump_setup()
	var s = main.surfer
	var pumps := [0]
	var count := func(_q, _g): pumps[0] += 1
	s.pumped.connect(count)
	var drove := false
	var rose := false
	var min_pitch := 0.0
	var max_pitch := 0.0
	main.rider = PumpHold.new(main.Autopilot.new("none"), 0.3)
	for i in 50:
		await physics_frame
		drove = drove or s.pump_phase == s.PUMP_DRIVE
		rose = rose or s.pump_phase == s.PUMP_RISE
		min_pitch = minf(min_pitch, s.pump_pitch)
		max_pitch = maxf(max_pitch, s.pump_pitch)
	s.pumped.disconnect(count)
	if not (drove and rose):
		_fail("holding then releasing pump should drive then rise (drove %s, rose %s)" % [drove, rose])
	if min_pitch > -0.15 or max_pitch < 0.1:
		_fail("pump should drive the nose down the face, then carve it back up (pitch %.2f..%.2f)" % [min_pitch, max_pitch])
	if pumps[0] != 1:
		_fail("one hold and release should be one pump (got %d)" % pumps[0])


func _pump_tap_is_only_a_flick() -> void:
	await _pump_setup()
	var s = main.surfer
	var pumps := [0]
	var count := func(_q, _g): pumps[0] += 1
	s.pumped.connect(count)
	main.rider = PumpHold.new(main.Autopilot.new("none"), 0.06)   # shorter than MIN_DRIVE
	for i in 30:
		await physics_frame
	s.pumped.disconnect(count)
	if pumps[0] != 0:
		_fail("a tap shorter than MIN_DRIVE should not count as a pump")


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


## Holding the key a long time: the drive uses one leg stroke of drop, then the
## board flattens out on that lower line. You chose that line, so it stays put
## while held and after release (no creeping or snapping back up), and it isn't
## the flats either.
func _long_hold_settles_lower() -> void:
	await _pump_setup()
	var s = main.surfer
	s.phi = 0.0
	s.turn_rate = 0.0
	s.pump_pitch = 0.0
	main.rider = PumpHold.new(NoSteer.new(), 2.0)
	var t0: float = s.t
	var t_min := t0
	var t_settled := -1.0
	for i in 120:
		await physics_frame
		t_min = minf(t_min, s.t)
		if i == 60:
			t_settled = s.t
	var t_released: float = s.t
	for i in 90:
		await physics_frame
	if t_min < t0 - 0.35:
		_fail("a long hold should level off, not drive you to the bottom (%.2f -> %.2f)" % [t0, t_min])
	if t_settled > t0 - 0.1:
		_fail("a long hold should take you down to a lower line (%.2f -> %.2f)" % [t0, t_settled])
	if absf(t_released - t_settled) > 0.03:
		_fail("while held after the stroke the board should stay on its line (%.2f -> %.2f)" % [t_settled, t_released])
	if s.t > t_released + 0.06:
		_fail("releasing after a long hold should not carve you back up to the start (%.2f, released at %.2f, now %.2f)" % [t0, t_released, s.t])


## With no input at all the board trims across at the height it's at: nothing
## pushes it up toward the lip or down to the flats.
func _no_input_holds_height() -> void:
	await _pump_setup()
	var s = main.surfer
	s.phi = 0.0
	s.turn_rate = 0.0
	s.pump_pitch = 0.0
	main.rider = NoSteer.new()
	var t0: float = s.t
	for i in 120:
		await physics_frame
	if absf(s.t - t0) > 0.02:
		_fail("riding with no input should hold its height (%.2f -> %.2f)" % [t0, s.t])


## A player who isn't touching the carve keys.
class NoSteer:
	func steer(_surfer) -> float:
		return 0.0
	func pump(_surfer) -> float:
		return 0.0


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
