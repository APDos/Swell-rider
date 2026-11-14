extends SceneTree
## The ride recorder and replay: a ride played with real touch events is
## written to a file, and replaying that file through the game gives exactly
## the same ride. If this fails, recordings from the phone can't be trusted to
## reproduce what happened.
##
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_replay.gd

const Replay := preload("res://scripts/replay.gd")
const DIR := "user://test_rides"

var _failures := 0
var main: Node
var _stick_at := Vector2.ZERO
var _pump_at := Vector2.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clear()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.recorder.dir = DIR
	main.recorder.enabled = true
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	_stick_at = Vector2(view.x * 0.8, view.y * 0.6)
	_pump_at = Vector2(view.x * 0.2, view.y * 0.6)
	for mode in ["long", "short"]:
		await _record_and_replay(mode)
	_clear()
	_end()


## Up to 8 s of riding (it may wipe out sooner): pumps, carves up and down, a cutback.
func _play() -> void:
	_touch(0, _stick_at, true)
	var dirs := [Vector2(1, 0.3), Vector2(1, -0.5), Vector2(0.2, -1), Vector2(-1, -0.4),
			Vector2(-0.6, 0.8), Vector2(0.4, 1), Vector2(1, 0.2), Vector2(1, -0.6)]
	for i in 8:
		_drag(0, _stick_at + dirs[i].normalized() * 60.0)
		_touch(1, _pump_at, true)
		for f in 30:
			await physics_frame
		_touch(1, _pump_at, false)
		for f in 30:
			await physics_frame
		if main.state != main.PLAYING:
			break
	_touch(0, _stick_at, false)
	for f in 20:
		await physics_frame


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


func _clear() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute("%s/%s" % [DIR, f])


func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL: " + msg)


func _end() -> void:
	if _failures == 0:
		print("PASS test_replay")
		quit(0)
	else:
		quit(1)


## Record a ride played with real touches under these steering settings, check
## the file, then replay it (with the other settings chosen, so the replay must
## use the recording's own) and check it comes out the same.
func _record_and_replay(mode: String) -> void:
	main.rider = null
	main.recorder.enabled = true
	main.settings.parse("range=" + mode)
	seed(4321)
	main._reset()
	var path: String = main.recorder.path
	if path == "":
		_fail("the recorder didn't start a file for a player's ride (%s)" % mode)
		return
	await _play()
	main.recorder.finish()

	var r = Replay.load_file(path)
	if r.error != "":
		_fail("couldn't read the recording back: " + r.error)
		return
	var text := FileAccess.get_file_as_string(path)
	if r.aims.size() < 120:
		_fail("expected at least 120 rows, got %d (%s)" % [r.aims.size(), mode])
	if not r.aims.any(func(a): return a.length() > 0.5):
		_fail("no steering in the recording (%s)" % mode)
	if not r.pumps.any(func(p): return p > 0.0):
		_fail("no pumping in the recording (%s)" % mode)
	if not r.events.any(func(e): return " pump " in e):
		_fail("no pump events in the recording (%s)" % mode)
	if text.find(",-1,-1,-1,-1,") < 0 or text.find("stick_x") < 0:
		_fail("the thumb columns look wrong (%s)" % mode)
	if text.find("# settings range=" + mode) < 0:
		_fail("the recording should say which settings it was played with (%s)" % mode)
	if mode == "long" and not r.lift_ons.any(func(on): return on):
		_fail("a long-range recording should have the thumb's travel (lift)")

	# Play it back on a new ride: same wave, same input, same settings, same result.
	main.recorder.enabled = false
	main.settings.parse("range=" + ("short" if mode == "long" else "long"))
	main.rider = r
	main._reset()
	while not r.done and r.diverged_at < 0 and main.state == main.PLAYING:
		await physics_frame
	r.finish_check(main.surfer)
	if r.diverged_at >= 0:
		_fail("the %s replay parted from the recording at %s" % [mode, r.diverged_detail])
	elif r.tick < r.aims.size():
		_fail("the %s replay ended early (tick %d of %d, state %d)" % [mode, r.tick, r.aims.size(), main.state])
