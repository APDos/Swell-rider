extends SceneTree
## Checks on the controls. Player input goes in as real touch events through
## scripts/touch.gd (right thumb points the nose, left thumb pumps), so these
## test what a thumb on the phone actually does. Pump timing checks use
## scripted riders (rider.aim / rider.pump) for exact hold lengths.
##
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_controls.gd

var _failures := 0
var main: Node
var _stick_at := Vector2.ZERO    # where the steering thumb goes down (right half) (view px)
var _pump_at := Vector2.ZERO   # where the pump thumb goes down (left half)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	_stick_at = Vector2(view.x * 0.8, view.y * 0.6)
	_pump_at = Vector2(view.x * 0.2, view.y * 0.6)
	await _held_up_air_lands_clean()
	await _corner_tap_does_not_reset()
	await _corner_hold_resets()
	await _tap_after_wipeout_paddles_out()
	await _settling_thumb_is_neutral()
	await _small_slide_is_a_small_adjustment()
	await _pointing_up_never_turns_you_round()
	await _height_hold_lines_you_up()
	await _pointing_down_is_not_a_pump()
	await _pump_thumb_pumps()
	await _pump_drives_then_rises()
	await _pump_owns_the_dive()
	await _pump_tap_is_only_a_flick()
	await _pump_hold_uses_up_stroke()
	await _long_hold_settles_lower()
	await _no_input_holds_height()
	await _pointing_down_rides_out_front()
	await _straight_back_is_a_stall()
	await _reverse_c_cuts_back()
	await _full_sweep_loops_round_the_bottom()
	await _crossing_the_stick_turns_the_short_way()
	await _rebound_off_whitewater()
	await _straight_into_whitewater_wipes_out()
	await _lip_hit_scores()
	await _over_the_lip_is_an_air_or_over_the_back()
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


## Right thumb down at _stick_at, then pointing in screen direction dir (y down),
## pushed 60 px.
func _thumb_down() -> void:
	_touch(0, _stick_at, true)


func _point(dir: Vector2) -> void:
	_drag(0, _stick_at + dir.normalized() * 60.0)


## Long range (the default): slide the thumb up (lift > 0) or down this
## fraction of touch.RANGE_PX from where it touched down, `ahead` px down the
## line, so the stick still points ahead (a carve, not a turn-around).
func _carve(lift: float, ahead := 40.0) -> void:
	_drag(0, _stick_at + Vector2(ahead, -lift * main.touch.RANGE_PX))


func _thumb_up() -> void:
	_touch(0, _stick_at, false)


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
	_touch(1, _pump_at, false)
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
const DOWN_RIGHT := Vector2(1, 1)


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
	_carve(1.0, 0.0)   # slide all the way up
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
	_touch(1, _pump_at, true)
	await physics_frame
	await physics_frame
	_touch(1, _pump_at, false)
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


## The left thumb is the pump: hold, lift, one pump.
func _pump_thumb_pumps() -> void:
	await _pump_setup()
	var s = main.surfer
	main.rider = null
	var pumps := [0]
	var count := func(_q, _g): pumps[0] += 1
	s.pumped.connect(count)
	_touch(1, _pump_at, true)
	for i in 18:
		await physics_frame
	_touch(1, _pump_at, false)
	for i in 30:
		await physics_frame
	s.pumped.disconnect(count)
	if pumps[0] != 1:
		_fail("holding then lifting the left thumb should be one pump (got %d)" % pumps[0])


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
	_carve(-1.0)   # slide all the way down
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
## a fresh touch straight back (now →) stalls, and a forward sweep (up,
## up-right, right) takes you back down the line: a Cutback. (Sliding the thumb
## straight across to → without lifting it turns you back instead:
## _crossing_the_stick_turns_the_short_way.)
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
	_thumb_up()
	await physics_frame
	await physics_frame
	_thumb_down()
	await _hold_point(RIGHT, 20)
	if s.facing > 0.0:
		_fail("facing the barrel with the board level, a fresh touch straight back (→) should stall, not turn you")
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


## The whole cutback as one quick thumb sweep, the way it's drawn on a phone:
## a reverse C (up, up-back, back, down-back) then on round the bottom (down,
## down-ahead, ahead), at a normal thumb speed (about 0.1 s per step). The
## board follows the sweep the same way round: up and over to face the curl,
## then down the face and round the bottom back down the line, not back up over
## the lip. Scores a Cutback.
func _full_sweep_loops_round_the_bottom() -> void:
	await _ride_setup(60.0)
	var s = main.surfer
	s.t = 0.4
	var tricks := []
	var on_trick := func(n, _p): tricks.append(n)
	s.trick_landed.connect(on_trick)
	var faced_back := false
	var t_turned_back := -1.0
	var t_max_after := 0.0
	_thumb_down()
	for dir in [UP, UP_LEFT, LEFT, DOWN_LEFT, DOWN, DOWN_RIGHT, RIGHT]:
		_point(dir)
		for i in 6:
			await physics_frame
			faced_back = faced_back or s.facing < 0.0
	for i in 60:
		await physics_frame
		if faced_back and s.facing > 0.0 and t_turned_back < 0.0:
			t_turned_back = s.t
		if t_turned_back >= 0.0:
			t_max_after = maxf(t_max_after, s.t)
	_thumb_up()
	s.trick_landed.disconnect(on_trick)
	if not faced_back:
		_fail("a quick reverse-C sweep should turn the board to face the curl")
	elif t_turned_back < 0.0:
		_fail("carrying the sweep on round the bottom should bring you back down the line (facing %d)" % int(s.facing))
	elif t_turned_back > 0.6:
		_fail("the return should come round the bottom of the face, not back over the top (turned back at t=%.2f)" % t_turned_back)
	if not "Cutback" in tricks:
		_fail("the full sweep should score a Cutback (tricks %s)" % [tricks])


## The cutback as played on the phone (recorded rides): the thumb sweeps round
## the stick clockwise (up, ahead, down, back) to turn you through the bottom
## to face the curl, then moves straight across to point back down the line.
## That stroke crosses the stick's centre, here 20 px above it (outside the
## dead zone), so the angle
## swings round over the top; it must still turn you back the short way, round
## the bottom, not loop you up into the lip.
func _crossing_the_stick_turns_the_short_way() -> void:
	await _ride_setup(60.0)
	var s = main.surfer
	s.t = 0.5
	_thumb_down()
	var faced_back := false
	for i in 33:   # a quarter turn every 11 ticks, radius 70 px (inside the stick, so its centre stays put)
		var a := PI / 2.0 - PI * float(i + 1) / 22.0
		_drag(0, _stick_at + Vector2(cos(a), -sin(a)) * 70.0)
		await physics_frame
		faced_back = faced_back or s.facing < 0.0
	for i in 40:
		if s.facing < 0.0 and s.heading() > -0.6:
			break
		await physics_frame
	faced_back = faced_back or s.facing < 0.0
	var t_cross: float = s.t
	for i in 8:   # straight across, left to right, passing just above the centre
		var f := float(i + 1) / 8.0
		_drag(0, _stick_at + Vector2(lerpf(-70.0, 70.0, f), lerpf(0.0, -40.0, f)))
		await physics_frame
	var t_max: float = s.t
	var flipped_phi := 99.0
	for i in 90:
		await physics_frame
		t_max = maxf(t_max, s.t)
		if s.facing > 0.0:
			flipped_phi = s.phi
			break
	_thumb_up()
	if not faced_back:
		_fail("sweeping round to point back should turn you to face the curl")
	elif flipped_phi == 99.0:
		_fail("pointing back down the line after a cutback should turn you back (facing %d)" % int(s.facing))
	elif flipped_phi > 0.0 or t_max > t_cross + 0.05:
		_fail("crossing the stick's centre should turn you back round the bottom, not over the top (came round nose %s, t %.2f -> %.2f)" % ["up" if flipped_phi > 0.0 else "down", t_cross, t_max])


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
	await _hold_point(DOWN_RIGHT, 15)         # come off the foam: drop down and out of it
	await _hold_point(RIGHT, 45)              # level out and get going
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


## Cut back and point straight at the whitewater: it hits you head on, at once,
## rather than holding you there facing it until the rebound window runs out.
func _straight_into_whitewater_wipes_out() -> void:
	await _ride_setup(14.0)
	var s = main.surfer
	var reason := [""]
	var on_wipe := func(r): reason[0] = r
	s.wiped_out.connect(on_wipe)
	_thumb_down()
	await _hold_point(DOWN, 10)
	await _point_until(DOWN_LEFT, func(): return s.facing < 0.0, 90)
	_point(LEFT)
	var in_foam := -1
	var wiped := -1
	for i in 240:
		await physics_frame
		if in_foam < 0 and s.x < main.wave.curl_x:
			in_foam = i
		if reason[0] != "":
			wiped = i
			break
	_thumb_up()
	s.wiped_out.disconnect(on_wipe)
	if in_foam < 0:
		_fail("pointing back at the curl never reached the whitewater ('%s')" % reason[0])
	elif reason[0] != "Ran straight into the whitewater":
		_fail("pointing straight into the whitewater should wipe you out head on (got '%s')" % reason[0])
	elif wiped - in_foam > 18:
		_fail("pointing straight into the whitewater took %.2f s to wipe you out; it should be at once" % ((wiped - in_foam) / 60.0))


## Carve up high on the face, then snap the nose back down: a lip hit, with
## spray. Carving up and just levelling off scores nothing.
func _lip_hit_scores() -> void:
	var lip_tricks := ["Snap", "Off the Lip"]
	for snap in [true, false]:
		await _ride_setup(25.0)
		var s = main.surfer
		var tricks := []
		var on_trick := func(n, _p): tricks.append(n)
		s.trick_landed.connect(on_trick)
		_thumb_down()
		_carve(0.55)  # slide well up: a carve of about 30°
		var high := false
		for i in 120:
			await physics_frame
			if s.t > 0.85:
				high = true
				break
		if snap:
			_carve(-0.8)   # and snap the thumb down
		else:
			_carve(0.0)    # or just back to level
		for i in 50:
			await physics_frame
		_thumb_up()
		s.trick_landed.disconnect(on_trick)
		var hit := tricks.any(func(n): return n in lip_tricks)
		if not high:
			_fail("carving up never got high on the face (t %.2f)" % s.t)
		elif snap and not hit:
			_fail("carving up to the lip and snapping down should score a lip hit (tricks %s, state %d)" % [tricks, s.state])
		elif not snap and hit:
			_fail("carving up and levelling off shouldn't score a lip hit (tricks %s)" % [tricks])


## Where the right thumb lands is neutral. On the phone a still thumb rolls
## about 30 px (upward, mostly) in the first ticks as it flattens onto the
## glass (recorded rides); that must not steer. Moving on from there steers as
## usual, and a quick flick counts in full from where the thumb landed.
func _settling_thumb_is_neutral() -> void:
	await _ride_setup(60.0)
	var s = main.surfer
	var t0: float = s.t
	_thumb_down()
	await physics_frame
	_drag(0, _stick_at + Vector2(2, -26))
	await physics_frame
	_drag(0, _stick_at + Vector2(2, -33))
	var max_aim := 0.0
	for i in 40:
		await physics_frame
		max_aim = maxf(max_aim, main.touch.aim.length())
	var drift: float = absf(s.t - t0)
	_drag(0, _stick_at + Vector2(2, -33 - 60))
	await physics_frame
	await physics_frame
	var steer_after: Vector2 = main.touch.aim
	_thumb_up()
	await physics_frame
	await physics_frame
	_thumb_down()
	_drag(0, _stick_at + Vector2(0, -60))
	await physics_frame
	await physics_frame
	var flick: Vector2 = main.touch.aim
	_thumb_up()
	if max_aim > 0.0 or drift > 0.03:
		_fail("a still thumb settling onto the glass shouldn't steer (aim %.2f, t moved %.3f)" % [max_aim, drift])
	if steer_after.y < 0.9:
		_fail("after settling, pushing the thumb up should steer up (aim %s)" % steer_after)
	if flick.y < 0.9:
		_fail("a quick flick right after touching down should steer at once (aim %s)" % flick)


## Sensitivity. From recorded rides: a slow 34 px slide down-right dove the
## board to -45° and off the bottom of the wave; a quick 64 px move up (the
## whole short stick, 7 mm) pointed it straight up the face and over the back.
## Recorded thumbs: small adjustments and a settling thumb move at most ~36 px
## in 3 ticks, real flicks 45-175 px.
## - Long range (the default): small moves are small, slow or quick; it takes
##   a long slide (touch.RANGE_PX) for the steepest carve.
## - Short (the original stick): a small slow slide is small, a quick flick
##   barely bigger is the full turn.
func _small_slide_is_a_small_adjustment() -> void:
	for mode in ["long", "short"]:
		main.settings.parse("range=" + mode)
		var result := {}
		for move in ["slow", "quick", "long"]:
			if mode == "short" and move == "long":
				continue
			await _ride_setup(60.0)
			var s = main.surfer
			var t0: float = s.t
			var dir := Vector2(0.71, 0.71)   # down the face and down the line, screen y down
			_thumb_down()
			for i in 12:   # let it settle (touch.SETTLE_TICKS), as in the recording
				await physics_frame
			if move == "quick":
				_drag(0, _stick_at + dir * 50.0)
				await physics_frame
			elif move == "slow":
				for i in 10:   # 34 px over 10 ticks
					_drag(0, _stick_at + dir * 3.4 * float(i + 1))
					await physics_frame
			else:
				for i in 20:   # all the way down, over a third of a second
					_carve(-float(i + 1) / 20.0)
					await physics_frame
			var steepest := 0.0
			for i in 45:
				await physics_frame
				steepest = minf(steepest, s.heading())
			_thumb_up()
			result[move] = [steepest, t0 - s.t]
		var slow: Array = result["slow"]
		var fast: Array = result["quick"]
		if slow[0] < deg_to_rad(-25.0):
			_fail("%s: a small slow slide down should only angle the board down a little (it went to %.0f°)" % [mode, rad_to_deg(slow[0])])
		if mode == "short":
			if fast[0] > deg_to_rad(-38.0):
				_fail("short: a quick flick should be the full turn (only reached %.0f°)" % rad_to_deg(fast[0]))
			if slow[1] > 0.6 * fast[1]:
				_fail("short: a small slow slide down should drop you down the face far less than a flick (%.2f vs %.2f)" % [slow[1], fast[1]])
		else:
			if fast[0] < deg_to_rad(-25.0):
				_fail("long: a quick 50 px flick should still be a small adjustment (it went to %.0f°)" % rad_to_deg(fast[0]))
			if result["long"][0] > deg_to_rad(-60.0):
				_fail("long: sliding all the way down should be a steep carve (only reached %.0f°)" % rad_to_deg(result["long"][0]))
	main.settings.parse("range=long")


## Lining up on the wave (height hold). From recorded rides: every 5° the
## board points up or down moves you 0.1 of the face a second, so a thumb a
## little off level drifted the rider up and down. Now a slow thumb near level
## holds your height: slightly off level stays put, a nudge up moves you up a
## bit and holds there. A snap is still a carve at the thumb's angle. A quick
## move back toward the middle is re-centring, not a full-strength flick.
func _height_hold_lines_you_up() -> void:
	main.settings.parse("range=short height_hold=1")   # the hold, on the stick it was made for
	await _ride_setup(60.0)
	var s = main.surfer
	var touch = main.touch
	var at := func(deg: float, r := 70.0) -> Vector2:
		return _stick_at + Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg))) * r
	_thumb_down()
	for i in 12:   # settle
		await physics_frame
	for i in 20:   # slide slowly out, 7° above level (3.5 px a tick)
		_drag(0, _stick_at + Vector2.from_angle(deg_to_rad(-7.0)) * 3.5 * (i + 1))
		await physics_frame
	var t0: float = s.t
	for i in 90:
		await physics_frame
	if not s.holding:
		_fail("a slow thumb near level should hold height")
	if absf(s.t - t0) > 0.04:
		_fail("a thumb 7° off level should hold your height, not drift (moved %.2f of the face in 1.5 s)" % (s.t - t0))
	var t1: float = s.t
	for i in 10:   # nudge slowly up to 22°, hold a moment, then slowly back to 7°
		_drag(0, at.call(7.0 + 1.5 * (i + 1)))
		await physics_frame
	for i in 40:
		await physics_frame
	for i in 10:
		_drag(0, at.call(22.0 - 1.5 * (i + 1)))
		await physics_frame
	for i in 20:
		await physics_frame
	var t2: float = s.t
	for i in 60:
		await physics_frame
	if t2 - t1 < 0.03:
		_fail("a slow nudge up should move you up the face a bit (moved %.2f)" % (t2 - t1))
	if absf(s.t - t2) > 0.03:
		_fail("after a nudge, back near level should hold the new height (moved %.2f in 1 s)" % (s.t - t2))
	_thumb_up()
	await physics_frame
	_thumb_down()
	for i in 12:
		await physics_frame
	_drag(0, at.call(25.0))   # snap out to 25° in one tick
	for i in 30:
		await physics_frame
	if s.holding or rad_to_deg(s.phi) < 18.0:
		_fail("a snap to 25° should carve the board up toward 25° (phi %.0f°, holding %s)" % [rad_to_deg(s.phi), s.holding])
	_drag(0, at.call(-60.0, 40.0))   # a quick move back toward the middle (70 px out to 40), ending a bit below it
	await physics_frame
	if touch.aim.length() > 0.65:
		_fail("a quick move back toward the middle is re-centring, not a full-strength flick (push %.2f)" % touch.aim.length())
	_thumb_up()
	main.settings.parse("range=long height_hold=0")


## Pointing up, a hair left of vertical, is a carve up the face, not a cutback.
## From a recorded ride: a light 35 px push at 91° turned the board round over
## the top toward the barrel. A light push, or a firm one near vertical, never
## turns you round; that takes the thumb clearly behind you.
func _pointing_up_never_turns_you_round() -> void:
	for push in [35.0, 70.0]:
		await _ride_setup(60.0)
		var s = main.surfer
		s.t = 0.4
		_thumb_down()
		for i in 12:   # let it settle
			await physics_frame
		var dir := Vector2(-0.35, -1.0).normalized() if push > 50.0 else Vector2(-0.02, -1.0).normalized()
		for i in 10:   # a slow push: 110° firm, 91° light
			_drag(0, _stick_at + dir * push * float(i + 1) / 10.0)
			await physics_frame
		var turned := false
		for i in 90:
			await physics_frame
			turned = turned or s.facing < 0.0
		_thumb_up()
		if turned:
			_fail("pointing up (%.0f°, %.0f px) should carve up the face, not turn you round" % [rad_to_deg(atan2(-dir.y, dir.x)), push])


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


## Up through the lip nose up: with the speed, an air; without it, over the
## back and the wave's gone. No bouncing off the top.
func _over_the_lip_is_an_air_or_over_the_back() -> void:
	for fast in [false, true]:
		await _ride_setup(40.0)
		var s = main.surfer
		var why := [""]
		var on_wipe := func(r): why[0] = r
		s.wiped_out.connect(on_wipe)
		s.t = 0.9
		s.phi = 0.9
		s.v = 13.0 if fast else 6.0
		_thumb_down()
		_carve(0.8)
		var reached := false
		for i in 60:
			await physics_frame
			if s.state != s.RIDING:
				reached = true
				break
		_thumb_up()
		s.wiped_out.disconnect(on_wipe)
		if fast and s.state != s.AIR:
			_fail("up through the lip at 13 m/s should be an air (state %d, %s)" % [s.state, why[0]])
		elif not fast and not "over the back" in why[0]:
			_fail("up through the lip at 6 m/s should go over the back and lose the wave (reached %s, state %d, '%s')" % [reached, s.state, why[0]])


## Pump owns the dive (settings pump_dive, on by default). Recorded: holding
## the steering thumb a little above where it touched down steered a gentle
## climb that cancelled about half of each pump's dip. With it on, the steering
## adds nothing to the pump's dip (the nose dips as far as the pump takes it);
## with it off, the climb takes a good part of the dip back.
func _pump_owns_the_dive() -> void:
	var share := {}   # how much the steering adds to the dip at its deepest (degrees, + = cancels it)
	for case in ["on", "off"]:
		main.settings.parse("pump_dive=" + ("1" if case == "on" else "0"))
		await _ride_setup(60.0)
		var s = main.surfer
		_thumb_down()
		for i in 12:   # settle
			await physics_frame
		for i in 10:   # slide slowly a little up: a gentle climb
			_carve(0.25 * float(i + 1) / 10.0, 0.0)
			await physics_frame
		for i in 30:
			await physics_frame
		var lowest := 99.0
		_touch(1, _pump_at, true)
		for i in 25:   # drive
			await physics_frame
			if s.heading() < lowest:
				lowest = s.heading()
				share[case] = rad_to_deg(s.phi)
		_touch(1, _pump_at, false)
		for i in 5:
			await physics_frame
		_thumb_up()
	main.settings.parse("pump_dive=1")
	if share["on"] > 2.0:
		_fail("pump owns the dive: a steered climb shouldn't blunt the pump's dip (steering added %+.0f° at its deepest)" % share["on"])
	if share["off"] < 6.0:
		_fail("with pump owns the dive off, a steered climb should still blunt the dip (steering added only %+.0f°)" % share["off"])
