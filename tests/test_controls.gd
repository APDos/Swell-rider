extends SceneTree
## Checks on the controls. Player input goes in as real touch events through
## scripts/touch.gd (left thumb points the nose, right thumb pumps), so these
## test what a thumb on the phone actually does. Pump timing checks use
## scripted riders (rider.aim / rider.pump) for exact hold lengths.
##
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_controls.gd

var _failures := 0
var main: Node
var _left := Vector2.ZERO    # where the left thumb goes down (view px)
var _right := Vector2.ZERO   # where the right thumb goes down


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	_left = Vector2(view.x * 0.2, view.y * 0.6)
	_right = Vector2(view.x * 0.8, view.y * 0.6)
	await _held_up_air_lands_clean()
	await _corner_tap_does_not_reset()
	await _corner_hold_resets()
	await _tap_after_wipeout_paddles_out()
	await _pointing_down_is_not_a_pump()
	await _right_thumb_pumps()
	await _pump_drives_then_rises()
	await _pump_tap_is_only_a_flick()
	await _pump_hold_uses_up_stroke()
	await _long_hold_settles_lower()
	await _no_input_holds_height()
	await _pointing_down_rides_out_front()
	await _straight_back_is_a_stall()
	await _reverse_c_cuts_back()
	await _rebound_off_whitewater()
	if _failures == 0:
		print("PASS test_controls")
		quit(0)
	else:
		printerr("FAIL test_controls: %d" % _failures)
		quit(1)


# ---- touch helpers ---------------------------------------------------------

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


## Left thumb down at _left, then pointing in screen direction dir (y down),
## pushed 60 px.
func _thumb_down() -> void:
	_touch(0, _left, true)


func _point(dir: Vector2) -> void:
	_drag(0, _left + dir.normalized() * 60.0)


func _thumb_up() -> void:
	_touch(0, _left, false)


## Point in dir until cond is true (or max_frames). Returns whether it came true.
func _point_until(dir: Vector2, cond: Callable, max_frames: int) -> bool:
	_point(dir)
	for i in max_frames:
		await physics_frame
		if cond.call():
			return true
	return false


func _hold_point(dir: Vector2, frames: int) -> void:
	_point(dir)
	for i in frames:
		await physics_frame


func _fresh() -> void:
	_thumb_up()
	_touch(1, _right, false)
	_touch(2, _corner(), false)
	await physics_frame   # injected touches arrive on the next frame: let the releases land first
	seed(99)
	main.rider = null
	main._reset()
	await physics_frame


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


const UP := Vector2(0, -1)
const DOWN := Vector2(0, 1)
const LEFT := Vector2(-1, 0)    # toward the curl
const RIGHT := Vector2(1, 0)    # down the line
const UP_LEFT := Vector2(-1, -1)
const UP_RIGHT := Vector2(1, -1)
const DOWN_LEFT := Vector2(-1, 1)


# ---- tests -----------------------------------------------------------------

## Pump up speed, point up to hit the lip and keep pointing up in the air: that
## must not spin you (spinning is the thumb sideways).
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
	_thumb_down()
	_point(UP)
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
	_thumb_up()
	s.wiped_out.disconnect(on_wipe)
	if not launched:
		_fail("pointing up never launched an air (state %d, v %.1f)" % [s.state, s.v])
	elif not landed:
		_fail("an air pointing straight up did not land clean: '%s'" % wipe[0])
	elif max_spin > 0.01:
		_fail("pointing up through takeoff spun the surfer %.0f degrees" % rad_to_deg(max_spin))


func _corner() -> Vector2:
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	return Vector2(view.x - 40.0, 40.0)


func _corner_tap_does_not_reset() -> void:
	await _fresh()
	for i in 60:
		await physics_frame
	var x: float = main.surfer.x
	_touch(2, _corner(), true)
	for i in 5:
		await physics_frame
	_touch(2, _corner(), false)
	await physics_frame
	if main.surfer.x < x:
		_fail("a short tap on the restart corner reset the ride")


func _corner_hold_resets() -> void:
	await _fresh()
	for i in 60:
		await physics_frame
	_touch(2, _corner(), true)
	for i in 40:
		await physics_frame
	_touch(2, _corner(), false)
	if main.ride_time > 0.5:
		_fail("holding the restart corner for 0.66 s did not reset (ride_time %.2f)" % main.ride_time)


func _tap_after_wipeout_paddles_out() -> void:
	await _fresh()
	main.surfer._wipeout("test")
	await physics_frame
	_touch(1, _right, true)
	await physics_frame
	await physics_frame
	_touch(1, _right, false)
	if main.state != main.PLAYING:
		_fail("a tap after a wipeout should paddle back out")


func _pointing_down_is_not_a_pump() -> void:
	await _fresh()
	_thumb_down()
	var pushed := false
	_point(DOWN)
	for i in 40:
		await physics_frame
		pushed = pushed or main.surfer.pump_phase != main.surfer.PUMP_IDLE
	_thumb_up()
	if pushed:
		_fail("pointing down started a pump; steering and pumping should be separate")


## The right thumb is the pump: hold, lift, one pump.
func _right_thumb_pumps() -> void:
	await _pump_setup()
	var s = main.surfer
	main.rider = null
	var pumps := [0]
	var count := func(_q, _g): pumps[0] += 1
	s.pumped.connect(count)
	_touch(1, _right, true)
	for i in 18:
		await physics_frame
	_touch(1, _right, false)
	for i in 30:
		await physics_frame
	s.pumped.disconnect(count)
	if pumps[0] != 1:
		_fail("holding then lifting the right thumb should be one pump (got %d)" % pumps[0])


## Pump-test setup: hold a steady line high on the face with the curl far
## behind, so the pump is the only thing changing speed.
func _pump_setup() -> void:
	await _fresh()
	main.rider = main.Autopilot.new("none")   # steers a steady line; we pump ourselves
	main.wave.curl_x = -1000.0
	main.surfer.t = 0.7
	main.surfer.v = 10.0
	await physics_frame


func _pump_drives_then_rises() -> void:
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
		_fail("holding the pump should eventually use up the leg stroke")


## Holding the pump a long time: the drive uses one leg stroke of drop, then the
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


## With no thumb down the board trims across at the height it's at: nothing
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


## No guardrail at the trough: pointing down carves you past it and out onto
## the flat water in front of the wave, until you've left the wave behind.
func _pointing_down_rides_out_front() -> void:
	await _ride_setup(60.0)
	var s = main.surfer
	var reason := [""]
	var on_wipe := func(r): reason[0] = r
	s.wiped_out.connect(on_wipe)
	var t_min: float = s.t
	_thumb_down()
	_point(DOWN)
	for i in 240:
		await physics_frame
		t_min = minf(t_min, s.t)
		if reason[0] != "":
			break
	_thumb_up()
	s.wiped_out.disconnect(on_wipe)
	if t_min > -0.2:
		_fail("pointing down should ride out in front of the trough (lowest t %.2f)" % t_min)
	if reason[0] != "Rode off the front of the wave":
		_fail("riding far out in front should end the ride by leaving the wave (got '%s')" % reason[0])


## Pointing straight behind you with the board running level sits you back on
## the tail: the stall, not a turn.
func _straight_back_is_a_stall() -> void:
	await _ride_setup(60.0)
	var s = main.surfer
	_thumb_down()
	await _hold_point(LEFT, 20)
	_thumb_up()
	if s.facing < 0.0:
		_fail("pointing straight back from a level board should stall, not turn you around")
	if s.tail_dig < 0.5:
		_fail("pointing straight back should dig the tail in (dig %.2f)" % s.tail_dig)


## The cutback is a reverse-C sweep of the thumb: up, up-back, back, down-back.
## The nose follows it up and round to point at the barrel, with no stall on the
## way (straight back mid-sweep keeps the turn going). Then, facing the barrel,
## straight back (now →) stalls, and a forward sweep (up, up-right, right) takes
## you back down the line: a Cutback.
func _reverse_c_cuts_back() -> void:
	await _ride_setup(60.0)
	var s = main.surfer
	var tricks := []
	var why := [""]
	var on_trick := func(n, _p): tricks.append(n)
	var on_wipe := func(r): why[0] = "%s (t=%.2f v=%.1f facing %d phi %.2f)" % [r, s.t, s.v, int(s.facing), s.phi]
	s.trick_landed.connect(on_trick)
	s.wiped_out.connect(on_wipe)
	var max_dig := 0.0
	_thumb_down()
	for dir in [UP, UP_LEFT, LEFT, DOWN_LEFT]:
		_point(dir)
		for i in 12:
			await physics_frame
			max_dig = maxf(max_dig, s.tail_dig)
	var turned: bool = s.facing < 0.0
	var x1: float = s.x
	await _hold_point(LEFT, 30)     # ← is now the way you're going: level out toward the barrel
	if not turned or s.x >= x1:
		_fail("a reverse-C sweep should turn the board to point at the barrel and ride toward it (facing %d)" % int(s.facing))
	if max_dig > 0.3:
		_fail("the reverse-C sweep shouldn't stall on the way round (tail dig reached %.2f)" % max_dig)
	if s.tail_dig > 0.3:
		_fail("facing the barrel, pointing at it shouldn't stall (dig %.2f)" % s.tail_dig)
	await _hold_point(RIGHT, 20)
	if s.facing > 0.0:
		_fail("facing the barrel with the board level, pointing straight back (→) should stall, not turn you")
	elif s.tail_dig < 0.5:
		_fail("facing the barrel, pointing straight back (→) should dig the tail in (dig %.2f)" % s.tail_dig)
	for dir in [UP, UP_RIGHT]:
		await _hold_point(dir, 12)
	var back := await _point_until(RIGHT, func(): return s.facing > 0.0, 60)
	await _hold_point(RIGHT, 20)
	_thumb_up()
	s.trick_landed.disconnect(on_trick)
	s.wiped_out.disconnect(on_wipe)
	if not back:
		_fail("a forward sweep (up, up-right, right) should take you back down the line")
	if not "Cutback" in tricks:
		_fail("turning to face the barrel and back down the line should score a Cutback (tricks %s)" % [tricks])
	if why[0] != "":
		_fail("an open-water cutback shouldn't end the ride: %s" % why[0])


## Cut back low (sweep down and back), aim at the whitewater, and sweep the
## turn off it yourself: the foam stops you, then throws you out ahead of the
## curl once you've come around (a Roundhouse Cutback). Ride into it and don't
## turn, and it buries you.
func _rebound_off_whitewater() -> void:
	await _ride_setup(14.0)
	var s = main.surfer
	var tricks := []
	var reason := [""]
	var on_trick := func(n, _p): tricks.append(n)
	var on_wipe := func(r): reason[0] = r
	s.trick_landed.connect(on_trick)
	s.wiped_out.connect(on_wipe)
	_thumb_down()
	await _hold_point(DOWN, 10)
	await _point_until(DOWN_LEFT, func(): return s.facing < 0.0, 90)
	await _hold_point(UP_LEFT, 30)            # aim up at the foam
	for dir in [UP]:
		await _hold_point(dir, 8)
	await _point_until(UP_RIGHT, func(): return s.facing > 0.0, 90)
	await _hold_point(RIGHT, 60)              # level out and get going
	_thumb_up()
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
	_thumb_down()
	await _hold_point(DOWN, 10)
	await _point_until(DOWN_LEFT, func(): return s.facing < 0.0, 90)
	await _hold_point(LEFT, 180)
	_thumb_up()
	s.wiped_out.disconnect(on_wipe)
	if reason[0] == "":
		_fail("riding into the whitewater facing back and never turning off it should end the ride")


## A player with no thumb on the stick.
class NoSteer:
	func aim(_surfer) -> Vector2:
		return Vector2.ZERO
	func pump(_surfer) -> float:
		return 0.0


## Wraps a rider: same aim, but holds the pump for hold_s seconds.
class PumpHold:
	var inner
	var hold_s: float
	var _t := 0.0
	func _init(rider, hold := 10.0) -> void:
		inner = rider
		hold_s = hold
	func aim(surfer) -> Vector2:
		return inner.aim(surfer)
	func pump(_surfer) -> float:
		_t += 1.0 / Engine.physics_ticks_per_second
		return 1.0 if _t <= hold_s else 0.0


func _fail(msg: String) -> void:
	_failures += 1
	printerr("  " + msg)
