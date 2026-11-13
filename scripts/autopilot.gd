extends RefCounted
## Scripted rider: drives the game the way a player would, through the same
## inputs the controls produce: steer (-1..1, carve up/down) and pump (0..1,
## the pump key). Used by --autopilot and by tests.
##
## Steering holds a line high in the pocket. Pumping depends on the style:
## - "good":   pumps on the steep upper face, steady rhythm, holds each push
##             until the legs are extended
## - "sloppy": rides low on the flatter part of the face, pumps with uneven
##             timing and short jabs (how beginners tend to pump)
## - "none":   never pumps

var style := "good"
var line_t := 0.6          # height on the face to hold (0 trough .. 1 lip)
var period := 1.0          # s between pumps ("good")

var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _next_pump := 0.6
var _press_until := -1.0


func _init(pump_style := "good") -> void:
	style = pump_style
	if style == "sloppy":
		line_t = 0.35
	_rng.seed = 7


func reset() -> void:
	_clock = 0.0
	_next_pump = 0.6
	_press_until = -1.0
	_rng.seed = 7


func steer(surfer) -> float:
	if surfer.state == surfer.AIR:
		return 0.0  # no spin: land it clean
	var target_phi: float = clampf((line_t - surfer.t) * 2.5, -0.7, 0.7)
	return clampf((target_phi - surfer.phi) * 3.0, -1.0, 1.0)


## Called once per physics tick, after steer().
func pump(surfer) -> float:
	_clock += 1.0 / Engine.physics_ticks_per_second
	if surfer.state != surfer.RIDING or style == "none":
		return 0.0
	if _press_until > 0.0:
		# Good riders hold until the legs are extended, then let go.
		var done: bool = _clock >= _press_until or (style == "good" and surfer.pushing and surfer.stroke <= 0.0)
		if not done:
			return 1.0
		_press_until = -1.0
		# Always let go for a moment, or the game sees one long hold.
		_next_pump = maxf(_next_pump, _clock + 0.1)
		return 0.0
	if _clock < _next_pump:
		return 0.0
	match style:
		"good":
			if surfer.t < 0.4 or surfer.t > 0.85:
				return 0.0  # wait for the steep part of the face
			_press_until = _clock + 1.0   # released early once the stroke runs out
			_next_pump = _clock + period
		"sloppy":
			_press_until = _clock + surfer.LIFT_TIME + _rng.randf_range(0.03, 0.15)
			_next_pump = _clock + _rng.randf_range(0.3, 1.8)
	return 1.0
