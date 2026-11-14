extends RefCounted
## Plays a recorded ride (scripts/recorder.gd) back through the game: a rider
## that feeds the surfer the recorded aim and pump, tick by tick, on the same
## wave (the ride's seed). Watch one on the Mac:
##
##   godot --path . -- --replay=rides/ride_20261114_101500.csv
##
## or check it headless (prints where the replay first parts from the recording):
##
##   godot --headless --fixed-fps 60 --path . -- --replay=rides/ride_....csv
##
## Each tick it compares the surfer with the recorded row; `diverged_at` is the
## first tick that differs (-1 while it matches), so a physics change shows up
## as the moment that ride would have gone differently.

var ride_seed := 0
var aims: Array[Vector2] = []
var pumps: Array[float] = []
var fines: Array[bool] = []
var expect: Array = []        # per tick: [x, t, v] as recorded
var events: Array[String] = []
var error := ""
var tick := 0                 # rows fed so far
var diverged_at := -1
var diverged_detail := ""
var done := false


static func load_file(file_path: String):
	var r = load("res://scripts/replay.gd").new()
	r._parse(file_path)
	return r


func _parse(file_path: String) -> void:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		error = "can't open %s" % file_path
		return
	var cols := {}
	while not f.eof_reached():
		var line := f.get_line()
		if line == "":
			continue
		if line.begins_with("#"):
			if line.begins_with("# seed "):
				ride_seed = int(line.substr(7))
			elif line.begins_with("# event "):
				events.append(line.substr(8))
			continue
		var cells := line.split(",")
		if cols.is_empty():
			for i in cells.size():
				cols[cells[i]] = i
			continue
		if cells.size() < cols.size():
			break   # cut off mid-row: the app was still writing when the file was copied
		aims.append(Vector2(float(cells[cols.aim_x]), float(cells[cols.aim_y])))
		pumps.append(float(cells[cols.pump]))
		fines.append(cols.has("fine") and cells[cols.fine] == "1")   # older recordings: never
		expect.append([float(cells[cols.x]), float(cells[cols.t]), float(cells[cols.v])])
	if aims.is_empty():
		error = "no rows in %s" % file_path


func reset() -> void:
	tick = 0
	diverged_at = -1
	diverged_detail = ""
	done = false


## Called each tick before the step: first check the last step against the
## recording, then hand out this tick's input.
func aim(surfer) -> Vector2:
	_check(surfer)
	if tick >= aims.size():
		done = true
		return Vector2.ZERO
	tick += 1
	return aims[tick - 1]


func pump(_surfer) -> float:
	return pumps[tick - 1] if tick >= 1 and tick <= pumps.size() and not done else 0.0


func fine(_surfer) -> bool:
	return fines[tick - 1] if tick >= 1 and tick <= fines.size() and not done else false


## At the end: check the last recorded row, unless aim() already did.
func finish_check(surfer) -> void:
	if not done:
		_check(surfer)


func _check(surfer) -> void:
	if tick == 0 or diverged_at >= 0 or tick > expect.size():
		return
	var e: Array = expect[tick - 1]
	# The file rounds x and v to 3 decimals, t to 4.
	if absf(surfer.x - e[0]) > 0.002 or absf(surfer.t - e[1]) > 0.0002 or absf(surfer.v - e[2]) > 0.002:
		diverged_at = tick
		diverged_detail = "tick %d (%.2f s): recorded x %.3f t %.4f v %.3f, replay x %.3f t %.4f v %.3f" % [
			tick, tick / 60.0, e[0], e[1], e[2], surfer.x, surfer.t, surfer.v]
