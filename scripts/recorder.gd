extends Node
## Ride recorder: writes one CSV per ride with the thumbs and the surfer every
## physics tick, plus events (tricks, pumps, wipeouts) as `#` lines.
## On in debug builds on the phone, or with `-- --record` on the Mac. Never on
## for scripted riders (autopilot, replay, tests).
##
## Files: user://rides/ride_<date>_<time>.csv (on iOS, the app's Documents
## folder; tools/pull_rides.sh copies them to rides/ on the Mac). The newest
## KEEP are kept. scripts/replay.gd plays a file back through the game.
##
## The aim and pump columns are written exactly (scientific notation, round-trips
## the float), so a replay feeds the surfer the same input bit for bit.

const FORMAT := 3
const KEEP := 60

var main
var dir := "user://rides"
var enabled := false
var path := ""            # the file being written, "" when not recording
var _file: FileAccess
var _tick := 0

const COLUMNS := [
	"tick",
	# steering (right) thumb, viewport px (-1 when not touching): where it is and where the stick's centre is
	"stick_x", "stick_y", "origin_x", "origin_y",
	# what the game read from it: aim (x down the line, y up the face, length = push) and the pump
	"aim_x", "aim_y", "pump", "pump_x", "pump_y",
	# 1 while the thumb is positioning (slow), 0 just after a snap
	"fine",
	# face steering: the height the thumb asks for (-1: none), and the one being steered to
	"face_t", "face_goal",
	# the surfer after this tick
	"state", "x", "t", "v", "phi", "heading", "facing", "cutting", "stall", "tail_dig",
	"pump_phase", "pump_pitch", "turn_rate", "thumb_ang", "board_ang",
	"curl_d", "air_h", "spin", "in_barrel", "score",
	"holding", "hold_t",   # holding height (positioning) and the height held
]


## Start a new file for a ride (closing the last one). seed is the ride's
## random seed (wave height), so a replay gets the same wave.
func begin(ride_seed: int) -> void:
	finish()
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var now := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d_%02d%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]
	path = "%s/ride_%s.csv" % [dir, stamp]
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = "%s/ride_%s_%d.csv" % [dir, stamp, n]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("recorder: can't write %s" % path)
		path = ""
		return
	_tick = 0
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	_file.store_line("# swell-rider ride, format %d" % FORMAT)
	_file.store_line("# date %s" % Time.get_datetime_string_from_system())
	_file.store_line("# seed %d" % ride_seed)
	_file.store_line("# view %d %d" % [int(view.x), int(view.y)])
	_file.store_line("# wave base_height=%.3f" % main.wave.base_height)
	_file.store_line("# settings %s" % main.settings.describe())
	_file.store_line(",".join(COLUMNS))
	_prune()


## One row, after the surfer has stepped with this aim and pump.
func tick(aim: Vector2, pump: float) -> void:
	if _file == null:
		return
	_tick += 1
	var tc = main.touch
	var s = main.surfer
	var stick_on: bool = tc._stick_id != -1
	var pump_on: bool = tc._pump_id != -1
	var row := PackedStringArray([
		str(_tick),
		_px(tc._stick_pos.x, stick_on), _px(tc._stick_pos.y, stick_on),
		_px(tc._stick_origin.x, stick_on), _px(tc._stick_origin.y, stick_on),
		String.num_scientific(aim.x), String.num_scientific(aim.y), String.num_scientific(pump),
		_px(tc._pump_pos.x, pump_on), _px(tc._pump_pos.y, pump_on),
		"%d" % int(s.fine),
		String.num_scientific(s.face_t), "%.4f" % s.face_goal,
		["riding", "air", "wipeout"][s.state] if s.state < 3 else str(s.state),
		"%.3f" % s.x, "%.4f" % s.t, "%.3f" % s.v, "%.4f" % s.phi, "%.4f" % s.heading(),
		"%d" % int(s.facing), "%d" % int(s.cutting), "%d" % int(s._stall_hold), "%.3f" % s.tail_dig,
		["idle", "drive", "rise"][s.pump_phase], "%.4f" % s.pump_pitch, "%.3f" % s.turn_rate,
		"%.4f" % s._thumb_ang, "%.4f" % s._board_ang,
		"%.3f" % (s.x - main.wave.curl_x), "%.3f" % s.air_h, "%.3f" % s.spin,
		"%d" % int(s.in_barrel), "%.1f" % main.score,
		"%d" % int(s.holding), "%.4f" % s.hold_t,
	])
	_file.store_line(",".join(row))


## A `#` line between rows: `# event <tick> <kind> <details>`. Events fire
## during the step, so the line comes just before the row of its tick.
func event(kind: String, details := "") -> void:
	if _file == null:
		return
	_file.store_line("# event %d %s %s" % [_tick + 1, kind, details])


func finish() -> void:
	if _file != null:
		_file.close()
		_file = null
	path = ""


func _px(v: float, on: bool) -> String:
	return "%.1f" % v if on else "-1"


func _prune() -> void:
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.begins_with("ride_") and f.ends_with(".csv"))
	files.sort()
	while files.size() > KEEP:
		DirAccess.remove_absolute("%s/%s" % [dir, files.pop_front()])


## Make sure what's recorded so far is on disk when the app goes to the
## background or quits (swiping the app away mid-ride).
func _notification(what: int) -> void:
	if _file == null:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_file.flush()
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			finish()
