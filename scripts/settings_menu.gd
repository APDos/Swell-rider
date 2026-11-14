extends CanvasLayer
## The ⚙ menu: pauses the game and lets you switch control options to try
## them out (settings.gd). Closing it with anything changed starts a new ride,
## so each recording is one set of settings.

const Settings := preload("res://scripts/settings.gd")

const RANGE_HELP := [
	"Long: how steeply you carve up or down is how far your thumb travels up or down from where you touched, up to a third of the screen. Small moves are small; a quick thumb turns the board faster.",
	"Short: the original stick. Its 80 px circle is the whole range, and a quick move jumps straight to the full turn.",
]

var main
var settings
var _changed := false
var _root: Control
var _range_buttons: Array[Button] = []
var _hold_buttons: Array[Button] = []
var _help: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.06, 0.1, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(900, 0)
	_root.add_child(box)

	box.add_child(_label("Settings", 36))
	box.add_child(_label("Steering range (right thumb)", 26))
	_range_buttons = _segmented(box, ["Long", "Short"], func(i):
		settings.long_range = i == 0
		_changed = true
		_refresh())
	_help = _label("", 18)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(900, 50)
	box.add_child(_help)
	box.add_child(_label("Height hold (a slow thumb near level holds your height)", 22))
	_hold_buttons = _segmented(box, ["On", "Off"], func(i):
		settings.height_hold = i == 0
		_changed = true
		_refresh())

	var done := _button("Done")
	done.custom_minimum_size = Vector2(260, 64)
	done.pressed.connect(close)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(done)
	box.add_child(row)
	# Centre the column once it knows its size.
	box.resized.connect(func(): box.position = (_root.size - box.size) * 0.5)
	_root.resized.connect(func(): box.position = (_root.size - box.size) * 0.5)
	visible = false


func open() -> void:
	_changed = false
	_refresh()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	if _changed:
		settings.save()
		main.settings_changed()


func is_open() -> bool:
	return visible


func _refresh() -> void:
	_range_buttons[0].button_pressed = settings.long_range
	_range_buttons[1].button_pressed = not settings.long_range
	_hold_buttons[0].button_pressed = settings.height_hold
	_hold_buttons[1].button_pressed = not settings.height_hold
	_help.text = RANGE_HELP[0 if settings.long_range else 1]


func _segmented(parent: Control, names: Array, on_pick: Callable) -> Array[Button]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	var out: Array[Button] = []
	for i in names.size():
		var b := _button(names[i])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(200, 60)
		b.pressed.connect(func(): on_pick.call(i))
		row.add_child(b)
		out.append(b)
	parent.add_child(row)
	return out


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 28)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.1)
	normal.set_corner_radius_all(14)
	var on := StyleBoxFlat.new()
	on.bg_color = Color(0.3, 0.85, 0.95, 0.85)
	on.set_corner_radius_all(14)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color(0.02, 0.1, 0.15))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.02, 0.1, 0.15))
	return b


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l
