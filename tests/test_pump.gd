extends SceneTree
## Design checks on pumping and stalling. The rides use the real main scene
## (curl speed changes, closeout sections) with scripted riders plugged in:
## - riding without pumping gets caught by the wave
## - sloppy pumping keeps you going, good pumping is clearly faster
## - mashing the key is capped at one pump per MIN_PUMP_INTERVAL and is slower than a real rhythm
## - a perfect pump is worth 3x a sloppy one, and a pump brings you back up to your line
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
	var cruise := await _rides(Autopilot.new("none"))
	var sloppy := await _rides(Autopilot.new("sloppy"))
	var good := await _rides(Autopilot.new("good"))
	var mash := await _rides(Autopilot.new("mash"))
	for r in [["cruise (no pumping)", cruise], ["sloppy pumping", sloppy], ["good pumping", good], ["mashing (5/s)", mash]]:
		_log("%-20s survived %d/%d  avg time %5.1fs  line speed %5.2f m/s  pumps/ride %3d  avg quality %.2f  %s" % [
			r[0], r[1].survived, SEEDS.size(), r[1].time, r[1].avg_v, r[1].pumps, r[1].avg_q, r[1].reasons])
	_expect(cruise.survived == 0 and cruise.time < 25.0, "riding without pumping should get caught, on average within 25 s (survived %d, avg %.1f s)" % [cruise.survived, cruise.time])
	_expect(sloppy.time > cruise.time + 5.0, "sloppy pumping should last clearly longer than not pumping (%.1f vs %.1f s)" % [sloppy.time, cruise.time])
	_expect(good.survived == SEEDS.size(), "good pumping should make every wave (made %d/%d)" % [good.survived, SEEDS.size()])
	_expect(good.avg_v > sloppy.avg_v + 0.7, "good pumping should be clearly faster than sloppy (%.2f vs %.2f m/s)" % [good.avg_v, sloppy.avg_v])
	_expect(good.avg_q > 0.85, "good pumping should score near-perfect pumps (%.2f)" % good.avg_q)
	_expect(mash.pumps <= int(RIDE_TIME / SurferScript.MIN_PUMP_INTERVAL) + 1, "mashing should be capped at one pump per MIN_PUMP_INTERVAL (%d pumps in %.0f s)" % [mash.pumps, RIDE_TIME])
	_expect(good.avg_v > mash.avg_v + 0.7, "pumping in a real rhythm should be clearly faster than mashing the key (%.2f vs %.2f m/s)" % [good.avg_v, mash.avg_v])
	_expect(good.avg_q > sloppy.avg_q + 0.2, "good pumping should score clearly better pumps than sloppy (%.2f vs %.2f)" % [good.avg_q, sloppy.avg_q])

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
	var pumps_ref := [0, 0.0]
	var on_pump := func(q: float, _gain: float):
		pumps_ref[0] += 1
		pumps_ref[1] += q
	surfer.pumped.connect(on_pump)
	while ticks * DT < RIDE_TIME and reason[0] == "":
		await physics_frame
		ticks += 1
		ticks_ref[0] = ticks
		sum_v += surfer.v
	surfer.wiped_out.disconnect(on_wipe)
	surfer.pumped.disconnect(on_pump)
	pumps = pumps_ref[0]
	sum_q = pumps_ref[1]
	# Speed down the line is what keeps you ahead of the curl; zig-zagging up
	# and down the face doesn't count.
	return {"time": ticks * DT, "avg_v": (surfer.x - x0) / (ticks * DT), "pumps": pumps,
		"avg_q": sum_q / maxi(pumps, 1), "reason": reason[0]}


func _reset_ride() -> void:
	main.rider = Autopilot.new()   # keeps main from reading the keyboard
	main._reset()
	wave.base_height = 4.8         # _reset picks a random height; compare like with like
	wave.closeout = Vector3(1e6, 1e6 + 1.0, 0.0)


## One full pump (drive 0.25 s, release, carve back up), once perfect, once
## the sloppiest, once scored zero (same board path, no kick). The speed the
## pump itself adds should differ by 3x, and the rise should bring you back up
## to the height the pump started from rather than leaving you lower.
func _check_single_pump_ratio() -> void:
	var base := _pump_cycle(0.0)
	var perfect := _pump_cycle(1.0)
	var sloppy := _pump_cycle(SurferScript.PUMP_MIN_QUALITY)
	var gp: float = perfect.dv - base.dv
	var gs: float = sloppy.dv - base.dv
	var ratio := gp / maxf(gs, 1e-6)
	_log("one pump cycle: perfect +%.2f m/s, sloppy +%.2f m/s, ratio %.2f; height %.2f -> lowest %.2f -> %.2f" % [gp, gs, ratio, perfect.t0, perfect.t_min, perfect.t_end])
	_expect(ratio > 2.8 and ratio < 3.2, "a perfect pump should be worth 3x a sloppy one (got %.2f)" % ratio)
	_expect(gp > 2.0, "a perfect pump should add clearly noticeable speed (+%.2f m/s)" % gp)
	_expect(perfect.t_min < perfect.t0 - 0.05, "the drive should drop you down the face (%.2f -> %.2f)" % [perfect.t0, perfect.t_min])
	_expect(perfect.t_end > perfect.t0 - 0.03, "after a pump the board should carve back up to its line (%.2f -> %.2f)" % [perfect.t0, perfect.t_end])


func _pump_cycle(quality: float) -> Dictionary:
	_reset_ride()
	wave.curl_x = -1000.0   # far behind: no pocket effects
	surfer.t = 0.7
	surfer.phi = 0.0
	surfer.v = 10.0
	surfer.quality_override = quality
	var t_min: float = surfer.t
	for i in 75:   # 0.25 s drive, then 1 s to turn and rise
		surfer.step(DT, Vector2.ZERO, 1.0 if i < 15 else 0.0)
		t_min = minf(t_min, surfer.t)
	surfer.quality_override = -1.0
	return {"dv": surfer.v - 10.0, "t0": 0.7, "t_min": t_min, "t_end": surfer.t}


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
		surfer.step(DT, Vector2(-stall, 0.0))   # thumb straight back, board level: the stall
		surfer.step(DT, Vector2(-stall, 0.0))
		dv.append(surfer.v - v0)
	return (dv[0] - dv[1]) / (2.0 * DT)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("  " + msg)


func _log(msg: String) -> void:
	if _report:
		print("  " + msg)
