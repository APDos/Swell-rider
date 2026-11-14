extends RefCounted
## Player settings: control options to try out, chosen in the ⚙ menu
## (settings_menu.gd). Saved on the device; written into each ride recording
## (`# settings ...`) so a replay rides with the same ones.
##
## Saved settings are only loaded on a real device or windowed run: headless
## runs (tests, replays checked from the command line) start from the defaults,
## or from the recording's.

const PATH := "user://settings.cfg"
const SECTION := "controls_v2"   # new section when the options change, so old saved choices don't carry over

## How far the right thumb has to travel for the steepest carve up or down.
## - long_range (default): measured from where it touched down, over a third
##   of the screen (touch.gd RANGE_PX): small moves are small.
## - short: the stick's own 80 px radius, a quick move jumping to full (the
##   original stick).
var long_range := true
var height_hold := false   # a slow thumb near level holds your height (surfer.gd HOLD_*)


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	long_range = bool(cfg.get_value(SECTION, "long_range", long_range))
	height_hold = bool(cfg.get_value(SECTION, "height_hold", height_hold))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "long_range", long_range)
	cfg.set_value(SECTION, "height_hold", height_hold)
	cfg.save(PATH)


## For the recording's header: `range=long height_hold=0`.
func describe() -> String:
	return "range=%s height_hold=%d" % ["long" if long_range else "short", int(height_hold)]


## Reads describe()'s format back (a recording's `# settings` line).
func parse(text: String) -> void:
	for part in text.split(" ", false):
		var kv := part.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"range":
				long_range = kv[1] != "short"
			"steering":   # recordings before the range setting: all the old stick
				long_range = false
			"height_hold":
				height_hold = kv[1] == "1"
