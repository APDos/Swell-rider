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
	await _hold_down_rides_out_front()
	await _left_alone_is_a_stall()
	await _cutback_points_at_barrel()
	await _rebound_off_whitewater()
	await _touch_controls()
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


## Player-driven ride with the curl curl_gap metres behind, at a steady speed mid-face.
func _ride_setup(curl_gap: float) -> void:
	await _fresh()
	var s = main.surfer
	s.t = 0.6
	s.v = 14.0
	s.phi = 0.0
	s.turn_rate = 0.0
	main.wave.curl_x = s.x - curl_gap
	await physics_frame


func _press(actions: Array, frames: int) -> void:
	for a in actions:
		Input.action_press(a)
	for i in frames:
		await physics_frame
	for a in actions:
		Input.action_release(a)


## No guardrail at the trough: holding down carves you past it and out onto the
## flat water in front of the wave, until you've left the wave behind.
func _hold_down_rides_out_front() -> void:
	await _ride_setup(60.0)
	var s = main.surfer
	var reason := [""]
	var on_wipe := func(r): reason[0] = r
	s.wiped_out.connect(on_wipe)
	var t_min: float = s.t
	Input.action_press("carve_down")
	for i in 240:
		await physics_frame
		t_min = minf(t_min, s.t)
		if reason[0] != "":
			break
	Input.action_release("carve_down")
	s.wiped_out.disconnect(on_wipe)
	if t_min > -0.2:
		_fail("holding down should ride out in front of the trough (lowest t %.2f)" % t_min)
	if reason[0] != "Rode off the front of the wave":
		_fail("riding far out in front should end the ride by leaving the wave (got '%s')" % reason[0])


## The ← key presses both "stall" and "spin_left", like the real keyboard binding.
const LEFT := ["stall", "spin_left"]
const RIGHT := ["spin_right"]


## Hold keys until cond is true (or max_frames). Returns whether it came true.
func _hold_until(actions: Array, cond: Callable, max_frames: int) -> bool:
	for a in actions:
		Input.action_press(a)
	var ok := false
	for i in max_frames:
		await physics_frame
		if cond.call():
			ok = true
			break
	for a in actions:
		Input.action_release(a)
	return ok


## Riding down the line, ← (the arrow behind you) on its own digs the tail in.
func _left_alone_is_a_stall() -> void:
	await _ride_setup(60.0)
	var s = main.surfer
	await _press(LEFT, 20)
	if s.facing < 0.0:
		_fail("← on its own should stall, not turn you around")
	if s.tail_dig < 0.5:
		_fail("← on its own should dig the tail in (dig %.2f)" % s.tail_dig)


## ← + ↑ drives the nose up past vertical and around to point at the barrel,
## only while held: let go part way and the board stays where it got to. Once
## you face the barrel, → is the arrow behind you: on its own it stalls, ← no
## longer does. → + ↑ drives you back down the line: a Cutback.
func _cutback_points_at_barrel() -> void:
	await _ride_setup(60.0)
	var s = main.surfer
	var tricks := []
	var on_trick := func(n, _p): tricks.append(n)
	s.trick_landed.connect(on_trick)
	# Part way, then let go: nothing finishes the turn for you.
	await _press(LEFT + ["carve_up"], 18)
	var phi_part: float = s.phi
	for i in 10:
		await physics_frame
	if s.facing < 0.0 or s.phi < phi_part - 0.3:
		_fail("letting go part way through should leave the board where it got to (phi %.2f -> %.2f, facing %d)" % [phi_part, s.phi, int(s.facing)])
	await _ride_setup(60.0)
	var why := [""]
	var on_wipe := func(r): why[0] = "%s (t=%.2f v=%.1f facing %d phi %.2f)" % [r, s.t, s.v, int(s.facing), s.phi]
	s.wiped_out.connect(on_wipe)
	var turned := await _hold_until(LEFT + ["carve_up"], func(): return s.facing < 0.0, 120)
	if s.tail_dig > 0.3:
		_fail("← + ↑ shouldn't also stall (dig %.2f)" % s.tail_dig)
	await _press(LEFT, 20)   # ← is now the way you're going
	var x1: float = s.x
	for i in 10:
		await physics_frame
	if not turned or s.x >= x1:
		_fail("← + ↑ should turn the board to point at the barrel and ride toward it (turned %s)" % turned)
	if s.tail_dig > 0.3:
		_fail("facing the barrel, ← shouldn't stall any more (dig %.2f)" % s.tail_dig)
	await _press(RIGHT, 20)
	if s.facing > 0.0:
		_fail("facing the barrel, → on its own should stall, not turn you")
	elif s.tail_dig < 0.5:
		_fail("facing the barrel, → on its own should dig the tail in (dig %.2f)" % s.tail_dig)
	var back := await _hold_until(RIGHT + ["carve_up"], func(): return s.facing > 0.0, 120)
	for i in 20:
		await physics_frame
	s.trick_landed.disconnect(on_trick)
	s.wiped_out.disconnect(on_wipe)
	if not back:
		_fail("→ + ↑ should drive you back down the line")
	if not "Cutback" in tricks:
		_fail("turning to face the barrel and back down the line should score a Cutback (tricks %s)" % [tricks])
	if why[0] != "":
		_fail("an open-water cutback shouldn't end the ride: %s" % why[0])


## Cut back low, aim at the whitewater, and drive the turn off it yourself:
## the foam stops you, then throws you out ahead of the curl once you've come
## around (a Roundhouse Cutback). Hit it and don't turn, and it buries you.
func _rebound_off_whitewater() -> void:
	await _ride_setup(14.0)
	var s = main.surfer
	var tricks := []
	var reason := [""]
	var on_trick := func(n, _p): tricks.append(n)
	var on_wipe := func(r): reason[0] = r
	s.trick_landed.connect(on_trick)
	s.wiped_out.connect(on_wipe)
	await _hold_until(LEFT + ["carve_down"], func(): return s.facing < 0.0, 90)
	await _press(LEFT + ["carve_up"], 30)       # aim up at the foam
	await _hold_until(RIGHT + ["carve_up"], func(): return s.facing > 0.0, 90)
	await _press(RIGHT, 60)                     # level out and get going
	s.trick_landed.disconnect(on_trick)
	s.wiped_out.disconnect(on_wipe)
	if not "Roundhouse Cutback" in tricks:
		_fail("turning off the whitewater should score a Roundhouse Cutback (tricks %s, ended '%s')" % [tricks, reason[0]])
	if reason[0] != "":
		_fail("turning off the whitewater should throw you out ahead of the curl, not end the ride ('%s')" % reason[0])
	elif s.x < main.wave.curl_x:
		_fail("after a rebound you should be back out ahead of the curl")

	await _ride_setup(14.0)
	reason[0] = ""
	s.wiped_out.connect(on_wipe)
	await _hold_until(LEFT + ["carve_down"], func(): return s.facing < 0.0, 90)
	await _press(LEFT, 180)
	s.wiped_out.disconnect(on_wipe)
	if reason[0] == "":
		_fail("riding into the whitewater facing back and never turning off it should end the ride")


## Touches arrive in window pixels and Godot maps them into the game's view
## (the stretch), so tests give view positions and convert them here.
func _win(pos: Vector2) -> Vector2:
	return main.get_viewport().get_final_transform() * pos


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _win(pos)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _win(pos)
	Input.parse_input_event(e)


## The phone controls (scripts/touch.gd) with real touch events: the left thumb
## steers through the same actions as the keys (up-back drives a cutback, back
## alone stalls), the right thumb pumps, and both work at once.
func _touch_controls() -> void:
	var touch = main.TouchScript.new()
	touch.main = main
	main.add_child(touch)
	await _ride_setup(60.0)
	var s = main.surfer
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	var left := Vector2(view.x * 0.2, view.y * 0.6)
	var right := Vector2(view.x * 0.8, view.y * 0.6)
	# Back (toward the curl) alone: the stall.
	_touch(0, left, true)
	_drag(0, left + Vector2(-90, 0))
	for i in 20:
		await physics_frame
	if s.tail_dig < 0.5 or s.facing < 0.0:
		_fail("touch: dragging back alone should stall (dig %.2f, facing %d)" % [s.tail_dig, int(s.facing)])
	# Up-back: drive a cutback, while the other thumb pumps.
	_drag(0, left + Vector2(-90, -90))
	_touch(1, right, true)
	var pumped: bool = false
	var turned := false
	for i in 90:
		await physics_frame
		pumped = pumped or Input.is_action_pressed("pump")
		if s.facing < 0.0:
			turned = true
			break
	_touch(1, right, false)
	_touch(0, left, false)
	await physics_frame
	if not turned:
		_fail("touch: dragging up and back should drive the board round to face the barrel")
	if not pumped:
		_fail("touch: holding the right side should press pump, alongside the stick")
	if Input.is_action_pressed("pump") or Input.is_action_pressed("carve_up") or Input.is_action_pressed("stall"):
		_fail("touch: lifting both thumbs should release every action")
	touch.queue_free()
	await physics_frame


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
