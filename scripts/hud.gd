extends CanvasLayer

var score_label: Label
var stats_label: Label
var popup_label: Label
var msg_label: Label
var barrel_label: Label
var depth_bar: ProgressBar
var pump_label: Label
var _popup_t := 0.0
var _pump_t := 0.0


func _ready() -> void:
	# On a phone, keep clear of the notch / Dynamic Island and the home bar.
	var inset: Rect2 = preload("res://scripts/touch.gd").safe_insets(get_viewport())
	var lx := inset.position.x
	var ty := inset.position.y
	score_label = _mk(40)
	score_label.position = Vector2(28 + lx, 18 + ty)
	stats_label = _mk(22)
	stats_label.position = Vector2(30 + lx, 70 + ty)
	pump_label = _mk(24)
	pump_label.position = Vector2(30 + lx, 102 + ty)
	pump_label.modulate.a = 0.0

	popup_label = _mk(46, true)
	popup_label.offset_bottom = -440
	barrel_label = _mk(40, true)
	barrel_label.offset_bottom = -320
	barrel_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.9))
	depth_bar = ProgressBar.new()
	depth_bar.show_percentage = false
	depth_bar.anchor_left = 0.5
	depth_bar.anchor_right = 0.5
	depth_bar.offset_left = -180
	depth_bar.offset_right = 180
	depth_bar.offset_top = 232
	depth_bar.offset_bottom = 248
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 1.0, 0.9)
	fill.set_corner_radius_all(8)
	depth_bar.add_theme_stylebox_override("background", bg)
	depth_bar.add_theme_stylebox_override("fill", fill)
	depth_bar.visible = false
	add_child(depth_bar)
	msg_label = _mk(38, true)

	var help := _mk(16)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 28 + lx
	help.offset_top = -44 - inset.size.y
	help.offset_bottom = -14 - inset.size.y
	help.text = "Right thumb: point the nose (sweep up and round to cut back; straight back to stall)   Left thumb: hold to pump, lift to turn up   Hold ↻: restart"
	help.modulate.a = 0.8


func _mk(size: int, centered := false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 10)
	if centered:
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(l)
	return l


func _process(dt: float) -> void:
	if _popup_t > 0.0:
		_popup_t -= dt
		popup_label.modulate.a = clampf(_popup_t / 0.4, 0.0, 1.0)
	if _pump_t > 0.0:
		_pump_t -= dt
		pump_label.modulate.a = clampf(_pump_t / 0.3, 0.0, 1.0)


## Quick read on each pump so players can learn what a good one feels like.
func pump_feedback(quality: float, _gain: float) -> void:
	if quality >= 0.9:
		pump_label.text = "Perfect pump"
		pump_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	elif quality >= 0.6:
		pump_label.text = "Good pump"
		pump_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	else:
		pump_label.text = "Pump"
		pump_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_pump_t = 0.9
	pump_label.modulate.a = 1.0


func set_stats(score: float, best: float, mult: float) -> void:
	score_label.text = "%d" % int(score)
	stats_label.text = "x%.1f   best %d" % [mult, int(best)]


func popup(text: String) -> void:
	popup_label.text = text
	_popup_t = 1.6
	popup_label.modulate.a = 1.0


func set_barrel(on: bool, secs: float, depth: float) -> void:
	barrel_label.visible = on
	depth_bar.visible = on
	if on:
		var c := Color(0.35, 1.0, 0.9).lerp(Color(1.0, 0.78, 0.2), depth)
		barrel_label.text = "IN THE BARREL  %.1fs   DEPTH %d%%" % [secs, int(depth * 100.0)]
		barrel_label.add_theme_color_override("font_color", c)
		depth_bar.value = depth * 100.0
		var sb := depth_bar.get_theme_stylebox("fill") as StyleBoxFlat
		sb.bg_color = c



func show_message(text: String) -> void:
	msg_label.text = text
	msg_label.visible = true


func hide_message() -> void:
	msg_label.visible = false
