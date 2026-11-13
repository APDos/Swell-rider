extends SceneTree
## Frame-rate independence: rides exactly 5 s of game time (300 physics ticks)
## on autopilot and prints the end state. tests/run_tests.sh runs this at
## several --fixed-fps values and fails if the results differ, which would
## mean the game feels different on fast and slow machines.
##
##   godot --headless --fixed-fps 144 --path . -s res://tests/test_framerate.gd

const TICKS := 300

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.use_autopilot()   # after _ready, which reads the command line
	seed(1234)
	main._reset()
	for i in TICKS:
		await physics_frame
	var s = main.surfer
	print("STATE x=%.4f t=%.4f v=%.4f phi=%.4f score=%.2f curl=%.4f" % [s.x, s.t, s.v, s.phi, main.score, main.wave.curl_x])
	quit(0)
