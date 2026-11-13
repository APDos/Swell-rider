extends CanvasLayer

var score_label: Label
var speed_label: Label
var popup_label: Label
var msg_label: Label
var warn_label: Label
var barrel_label: Label
var depth_bar: ProgressBar
var _popup_t := 0.0


func _ready() -> void:
	score_label = _mk(40)
	score_label.position = Vector2(28, 18)
	speed_label = _mk(22)
	speed_label.position = Vector2(30, 70)

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
	warn_label = _mk(26, true)
	warn_label.offset_top = 380
	warn_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	warn_label.text = "Section ahead — build speed!"
	msg_label = _mk(38, true)

	var help := _mk(16)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 28
	help.offset_top = -44
	help.offset_bottom = -14
	help.text = "↑/↓ or W/S: carve up / down the face   Space: pump   In the air ←/→: spin   Hold R: restart   Esc: quit"
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


func set_stats(score: float, best: float, kmh: float, mult: float) -> void:
	score_label.text = "%d" % int(score)
	speed_label.text = "%d km/h   x%.1f   best %d" % [int(kmh), mult, int(best)]


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


func set_warning(on: bool) -> void:
	warn_label.visible = on


func show_message(text: String) -> void:
	msg_label.text = text
	msg_label.visible = true


func hide_message() -> void:
	msg_label.visible = false
