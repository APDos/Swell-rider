extends SceneTree
## Design checks on pumping and stalling. The rides use the real main scene
## (curl speed changes, closeout sections) with scripted riders plugged in:
## - riding without pumping gets caught by the wave
## - sloppy pumping keeps you going, good pumping is clearly faster
## - a perfect pump is worth 3x a sloppy one
## - the tail stall brakes harder the faster you go (drag ~ v²)
##
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_pump.gd [-- --report]

const Autopilot := preload("res://scripts/autopilot.gd")
const SurferScript := preload("res://scripts/surfer.gd")
const DT := 1.0 / 60.0
const RIDE_TIME := 45.0
const SEEDS := [11, 22, 33]

var _failures := 0
var _report := false
var main: Node
var wave
var surfer


func _initialize() -> void:
	_report = "--report" in OS.get_cmdline_user_args()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	wave = main.wave       # set in main's _ready, which runs after _initialize
	surfer = main.surfer
	var cruise := await _rides(Autopilot.new(0.75, 0.30, false))
	var sloppy := await _rides(Autopilot.new(0.45, 0.15))
	var good := await _rides(Autopilot.new(0.75, 0.30))
	for r in [["cruise (no pumping)", cruise], ["sloppy pumping", sloppy], ["good pumping", good]]:
		_log("%-20s survived %d/%d  avg time %5.1fs  line speed %5.2f m/s  pumps/ride %3d  avg quality %.2f  %s" % [
			r[0], r[1].survived, SEEDS.size(), r[1].time, r[1].avg_v, r[1].pumps, r[1].avg_q, r[1].reasons])
	_expect(cruise.survived == 0 and cruise.time < 25.0, "riding without pumping should get caught, on average within 25 s (survived %d, avg %.1f s)" % [cruise.survived, cruise.time])
	_expect(sloppy.time > cruise.time + 5.0, "sloppy pumping should last clearly longer than not pumping (%.1f vs %.1f s)" % [sloppy.time, cruise.time])
	_expect(good.survived == SEEDS.size(), "good pumping should make every wave (made %d/%d)" % [good.survived, SEEDS.size()])
	_expect(good.avg_v > sloppy.avg_v + 0.7, "good pumping should be clearly faster than sloppy (%.2f vs %.2f m/s)" % [good.avg_v, sloppy.avg_v])
	_expect(good.avg_q > 0.8, "the good rhythm should score near-perfect pumps (%.2f)" % good.avg_q)
	_expect(sloppy.avg_q < 0.55, "the sloppy rhythm should score low pumps (%.2f)" % sloppy.avg_q)

	_check_single_pump_ratio()
	_check_stall()

	if _failures == 0:
		print("PASS test_pump")
		quit(0)
	else:
		printerr("FAIL test_pump: %d" % _failures)
		quit(1)


## Ride the same waves (one per seed) with a scripted rider and average the results.
func _rides(bot) -> Dictionary:
	var total := {"time": 0.0, "avg_v": 0.0, "pumps": 0, "avg_q": 0.0, "survived": 0, "reasons": []}
	for sd in SEEDS:
		var r: Dictionary = await _ride(bot, sd)
		total.time += r.time / SEEDS.size()
		total.avg_v += r.avg_v / SEEDS.size()
		total.pumps += r.pumps / SEEDS.size()
		total.avg_q += r.avg_q / SEEDS.size()
		if r.reason == "":
			total.survived += 1
		else:
			total.reasons.append(r.reason)
	return total


func _ride(bot, sd: int) -> Dictionary:
	main.rider = bot
	seed(sd)
	main._reset()
	var reason := [""]
	var ticks_ref := [0]
	var on_wipe := func(r: String):
		reason[0] = r
		if _report:
			_log("    wipeout '%s' at %.1fs: x=%.1f t=%.2f v=%.1f phi=%.2f curl=%.1f closeout=%.0f..%.0f" % [r, ticks_ref[0] * DT, surfer.x, surfer.t, surfer.v, surfer.phi, wave.curl_x, wave.closeout.x, wave.closeout.y])
	surfer.wiped_out.connect(on_wipe)
	var ticks := 0
	var x0: float = surfer.x
	var sum_v := 0.0
	var pumps := 0
	var sum_q := 0.0
	var was_pushing := false
	while ticks * DT < RIDE_TIME and reason[0] == "":
		await physics_frame
		ticks += 1
		ticks_ref[0] = ticks
		sum_v += surfer.v
		if surfer.pushing and not was_pushing:
			pumps += 1
			sum_q += surfer.pump_quality
		was_pushing = surfer.pushing
	surfer.wiped_out.disconnect(on_wipe)
	# Speed down the line is what keeps you ahead of the curl; zig-zagging up
	# and down the face doesn't count.
	return {"time": ticks * DT, "avg_v": (surfer.x - x0) / (ticks * DT), "pumps": pumps,
		"avg_q": sum_q / maxi(pumps, 1), "reason": reason[0]}


func _reset_ride() -> void:
	main.rider = Autopilot.new()   # keeps main from reading the keyboard
	main._reset()
	wave.base_height = 4.8         # _reset picks a random height; compare like with like
	wave.closeout = Vector3(1e6, 1e6 + 1.0, 0.0)


## Same descent, once with a perfect pump and once with the sloppiest one.
## The speed gained from the pump itself should differ by 3x.
func _check_single_pump_ratio() -> void:
	var base := _descent_gain(0.0)        # same push, but scored zero: no pump power
	var perfect := _descent_gain(1.0) - base
	var sloppy := _descent_gain(SurferScript.PUMP_MIN_QUALITY) - base
	var ratio := perfect / maxf(sloppy, 1e-6)
	_log("single pump: perfect +%.2f m/s, sloppy +%.2f m/s, ratio %.2f" % [perfect, sloppy, ratio])
	# Power scales exactly 3x; the measured speed gain lands a little under because
	# a slower board takes a slightly different line down the face.
	_expect(ratio > 2.5 and ratio < 3.3, "a perfect pump should be worth about 3x a sloppy one (got %.2f)" % ratio)
	_expect(perfect > 1.0, "a perfect pump should add a real amount of speed (+%.2f m/s)" % perfect)


## Speed change over a 0.5 s push down the face from high up, with the pump's
## quality pinned. Same steering every time, so only the pump power differs.
func _descent_gain(quality: float) -> float:
	_reset_ride()
	wave.curl_x = -1000.0   # far behind: no pocket effects
	surfer.t = 0.8
	surfer.phi = -0.5
	surfer.v = 10.0
	surfer.stroke = 1.0
	var v0: float = surfer.v
	surfer.pushing = true   # already mid-push, so the scoring doesn't run
	surfer.pump_quality = quality
	for i in 30:
		surfer.step(DT, -1.0, 0.0)
		if _report and quality == 1.0 and i % 5 == 0:
			_log("    tick %2d t=%.2f phi=%.2f v=%.2f slope=%.2f stroke=%.2f" % [i, surfer.t, surfer.phi, surfer.v, wave.slope_at(surfer.x, surfer.t), surfer.stroke])
	return surfer.v - v0


func _check_stall() -> void:
	var fast := _stall_decel(14.0)
	var slow := _stall_decel(7.0)
	_log("stall: decel %.1f m/s² at 14 m/s, %.1f m/s² at 7 m/s" % [fast, slow])
	_expect(fast > 5.0, "a full stall at speed should brake hard (%.1f m/s²)" % fast)
	_expect(fast > 3.0 * slow, "stall braking should grow with speed squared (%.1f vs %.1f)" % [fast, slow])


## Extra deceleration from stalling, measured against the same ride without it.
func _stall_decel(v0: float) -> float:
	var dv := []
	for stall in [0.0, 1.0]:
		_reset_ride()
		wave.curl_x = -1000.0
		surfer.t = 0.5
		surfer.phi = 0.0
		surfer.v = v0
		surfer.tail_dig = stall   # already dug in: measure the drag, not the weight shift
		surfer.step(DT, 0.0, stall)
		surfer.step(DT, 0.0, stall)
		dv.append(surfer.v - v0)
	return (dv[0] - dv[1]) / (2.0 * DT)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("  " + msg)


func _log(msg: String) -> void:
	if _report:
		print("  " + msg)
