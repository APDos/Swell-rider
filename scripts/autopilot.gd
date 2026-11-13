extends RefCounted
## Scripted rider: drives the game the way a player would, through the same
## steer value (-1..1) the controls produce. Used by --autopilot and by tests.
##
## The pump cycle: rise at a steady angle until top_t, hold down (push) until
## the leg stroke runs out, glide on down to bottom_t without pushing, then rise
## again. Pushing from high on the face with a steady rhythm scores the best
## pumps; a low top_t gives sloppy ones.

var top_t := 0.75
var bottom_t := 0.30
var pump := true          # false: hold a line in the pocket without ever pushing
var _phase := "rise"


func _init(top := 0.75, bottom := 0.30, pumping := true) -> void:
	top_t = top
	bottom_t = bottom
	pump = pumping


func steer(surfer) -> float:
	if surfer.state == surfer.AIR:
		return 0.0  # no spin: land it clean
	# Gentle carves never cross the push threshold.
	var no_push: float = surfer.PUSH_THRESHOLD * 0.8
	if not pump:
		var target_phi: float = clampf((0.6 - surfer.t) * 2.5, -0.7, 0.7)
		return clampf((target_phi - surfer.phi) * 3.0, -no_push, 1.0)
	match _phase:
		"rise":
			if surfer.t > top_t:
				_phase = "push"
		"push":
			if surfer.stroke <= 0.0:
				_phase = "glide"
			if surfer.t < bottom_t:
				_phase = "rise"
		"glide":
			if surfer.t < bottom_t:
				_phase = "rise"
	match _phase:
		"push":
			return -1.0
		"glide":
			return clampf((-0.5 - surfer.phi) * 3.0, -no_push, 1.0)
	return clampf((0.45 - surfer.phi) * 3.0, -no_push, 1.0)


func reset() -> void:
	_phase = "rise"
