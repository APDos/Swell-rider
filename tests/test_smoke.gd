extends SceneTree
## Gameplay smoke test: loads the real main scene, lets the autopilot ride for
## a few simulated seconds and checks the surfer moves down the line and scores.
## Script errors during the run are caught by tests/run_tests.sh, which fails
## on any "SCRIPT ERROR" in the output.
##
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_smoke.gd
## --fixed-fps makes every frame exactly 1/60 s, so the result does not depend
## on how fast the machine is.

const FRAMES := 300   # about 5 s of game time at 60 fps

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.use_autopilot()   # after _ready, which reads the command line
	var start_x: float = main.surfer.x
	for i in FRAMES:
		await process_frame
	var moved: float = main.surfer.x - start_x
	var ok := true
	if moved < 20.0:
		printerr("  surfer only moved %.1f m in %d frames" % [moved, FRAMES])
		ok = false
	if main.score <= 0.0 and main.best <= 0.0:
		printerr("  no score after %d frames" % FRAMES)
		ok = false
	if ok:
		print("PASS test_smoke (rode %.0f m, score %d)" % [moved, int(maxf(main.score, main.best))])
		quit(0)
	else:
		printerr("FAIL test_smoke")
		quit(1)
