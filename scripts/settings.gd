extends RefCounted
## Player settings: control options to try out, chosen in the ⚙ menu
## (settings_menu.gd). Saved on the device; written into each ride recording
## (`# settings ...`) so a replay rides with the same ones.
##
## Saved settings are only loaded on a real device or windowed run: headless
## runs (tests, replays checked from the command line) start from the defaults,
## or from the recording's.

const PATH := "user://settings.cfg"

## How the right thumb steers.
## - STICK: a floating stick; the thumb's direction is where the nose points
##   (touch.gd), with height hold for slow thumbs near level (surfer.gd HOLD_*).
## - FACE: the thumb's height is your height on the wave. Where you touch is
##   where you are now; the top of the screen is the lip, the bottom the trough
##   (touch.gd FACE_*). The board steers itself there.
## - SLIDER: the same, but the screen is a fixed slider: top = lip, bottom =
##   trough, wherever you touch down.
enum { STICK, FACE, SLIDER }
const STEERING_NAMES := ["stick", "face", "slider"]

var steering := STICK
var height_hold := true   # STICK: a slow thumb near level holds your height
var marker := true        # FACE / SLIDER: show the height you're steering to


func face_steering() -> bool:
	return steering != STICK


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	steering = clampi(int(cfg.get_value("controls", "steering", steering)), STICK, SLIDER)
	height_hold = bool(cfg.get_value("controls", "height_hold", height_hold))
	marker = bool(cfg.get_value("controls", "marker", marker))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "steering", steering)
	cfg.set_value("controls", "height_hold", height_hold)
	cfg.set_value("controls", "marker", marker)
	cfg.save(PATH)


## For the recording's header: `steering=face height_hold=1 marker=1`.
func describe() -> String:
	return "steering=%s height_hold=%d marker=%d" % [STEERING_NAMES[steering], int(height_hold), int(marker)]


## Reads describe()'s format back (a recording's `# settings` line).
func parse(text: String) -> void:
	for part in text.split(" ", false):
		var kv := part.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"steering":
				var i := STEERING_NAMES.find(kv[1])
				if i >= 0:
					steering = i
			"height_hold":
				height_hold = kv[1] == "1"
			"marker":
				marker = kv[1] == "1"
