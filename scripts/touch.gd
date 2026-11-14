extends CanvasLayer
## The game's controls: thumbs on a phone.
## - Left half: a floating stick. Touch anywhere and point where you want the
##   nose to go. Ahead of the board it carves; behind it, the nose swings round
##   (sweep a reverse C up and round for a cutback); straight back with the
##   board running level is the stall. In the air, sideways spins.
## - Right half: hold to pump (drive), lift your thumb to turn off the bottom.
## - After a wipeout, a tap paddles back out. Mid-ride, hold the ↻ corner.
## main.gd reads aim, pump, restart_down and consume_tap() each physics tick.

const RADIUS := 80.0        # px (viewport): size of the drawn stick; the centre follows your thumb past it
const DEADZONE := 0.15      # of RADIUS: smaller than this is no input
const FULL := 0.45          # of RADIUS: a push this long is already full strength
const RESTART_SIZE := Vector2(120, 100)   # the ↻ hold area, top-right corner

var main   # main.gd, for its state

## Where the left thumb points: x toward down the line (right), y up the face
## (screen y flipped), length 0..1 for how far it's pushed.
var aim := Vector2.ZERO
var pump := 0.0
var restart_down := false
var _tapped := false

var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _pump_id := -1
var _pump_pos := Vector2.ZERO
var _restart_id := -1
var _canvas: Control
var _inset := Rect2()   # safe-area margins in viewport px: position = left/top, size = right/bottom


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	_inset = safe_insets(get_viewport())


## Safe-area margins (notch, Dynamic Island, home bar) in viewport pixels.
static func safe_insets(vp: Viewport) -> Rect2:
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0.0 or safe.size.x <= 0:
		return Rect2()
	var view := vp.get_visible_rect().size
	var k := view / screen
	var left := float(safe.position.x) * k.x
	var top := float(safe.position.y) * k.y
	var right := (screen.x - float(safe.end.x)) * k.x
	var bottom := (screen.y - float(safe.end.y)) * k.y
	return Rect2(left, top, right, bottom)


func _view_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## True once per touch-down since the last call (main uses it to paddle out).
func consume_tap() -> bool:
	var was := _tapped
	_tapped = false
	return was


func _in_restart(p: Vector2) -> bool:
	var view := _view_size()
	return p.x > view.x - _inset.size.x - RESTART_SIZE.x and p.y < _inset.position.y + RESTART_SIZE.y


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			_tapped = true
			if _in_restart(p):
				if _restart_id == -1:
					_restart_id = event.index
					restart_down = true   # main restarts once it's held for RESTART_HOLD
			elif p.x < _view_size().x * 0.5:
				if _stick_id == -1:
					_stick_id = event.index
					_stick_origin = p
					_stick_pos = p
			elif _pump_id == -1:
				_pump_id = event.index
				_pump_pos = p
				pump = 1.0
		else:
			if event.index == _stick_id:
				_stick_id = -1
				_set_stick(Vector2.ZERO)
			elif event.index == _pump_id:
				_pump_id = -1
				pump = 0.0
			elif event.index == _restart_id:
				_restart_id = -1
				restart_down = false
		_canvas.queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _stick_id:
			_stick_pos = event.position
			var off := _stick_pos - _stick_origin
			# Past the edge, the stick's centre follows your thumb, so turning
			# back the other way responds straight away.
			if off.length() > RADIUS:
				_stick_origin = _stick_pos - off.normalized() * RADIUS
				off = _stick_pos - _stick_origin
			_set_stick(off / RADIUS)
			_canvas.queue_redraw()
		elif event.index == _pump_id:
			_pump_pos = event.position
			_canvas.queue_redraw()


## v: stick offset in units of RADIUS, screen y down. The direction is kept
## exactly (it's where the nose should point); a short push (FULL of the
## radius) is already full strength.
func _set_stick(v: Vector2) -> void:
	var len := minf(v.length(), 1.0)
	if len < DEADZONE:
		aim = Vector2.ZERO
	else:
		aim = Vector2(v.x, -v.y).normalized() * clampf((len - DEADZONE) / (FULL - DEADZONE), 0.0, 1.0)


func _on_draw() -> void:
	var view := _view_size()
	var faint := Color(1, 1, 1, 0.12)
	var line := Color(1, 1, 1, 0.35)
	# Restart corner.
	var rc := Vector2(view.x - _inset.size.x - 44.0, _inset.position.y + 40.0)
	_canvas.draw_arc(rc, 18.0, 0.6, TAU - 0.2, 24, line, 3.0, true)
	if main == null or main.state == main.WIPEOUT:
		return
	if _stick_id != -1:
		_canvas.draw_circle(_stick_origin, RADIUS, faint)
		_canvas.draw_arc(_stick_origin, RADIUS, 0.0, TAU, 48, line, 2.0, true)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(RADIUS)
		_canvas.draw_circle(knob, 30.0, Color(1, 1, 1, 0.45))
	if _pump_id != -1:
		_canvas.draw_circle(_pump_pos, 46.0, Color(0.45, 1.0, 0.6, 0.25))
		_canvas.draw_arc(_pump_pos, 46.0, 0.0, TAU, 40, Color(0.45, 1.0, 0.6, 0.6), 3.0, true)
