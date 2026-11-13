extends RefCounted
## Input actions and their default bindings (keyboard + gamepad).
## Gameplay code reads these action names only, never raw keys. An action that
## is already defined in Project Settings > Input Map is left alone, so bindings
## can be changed there without touching code.

const DEADZONE := 0.2

# action: [keys, joypad buttons, joypad axes as [axis, direction]]
const BINDINGS := {
	"carve_up":   [[KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]]],
	"carve_down": [[KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]]],
	"spin_left":  [[KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]]],
	"spin_right": [[KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]]],
	# Riding toward the curl (left) puts weight on the tail. Same keys as spin_left,
	# which only applies in the air.
	"stall":      [[KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]]],
	# Press to lift the nose, keep holding to push down. The trigger is analog:
	# how far it's pulled sets the push force.
	"pump":       [[KEY_SPACE], [JOY_BUTTON_A], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]],
	"restart":    [[KEY_R, KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_START], []],
	"quit":       [[KEY_ESCAPE], [JOY_BUTTON_BACK], []],
}


static func register() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		var b: Array = BINDINGS[action]
		for key in b[0]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)
		for button in b[1]:
			var e := InputEventJoypadButton.new()
			e.button_index = button
			InputMap.action_add_event(action, e)
		for axis in b[2]:
			var e := InputEventJoypadMotion.new()
			e.axis = axis[0]
			e.axis_value = axis[1]
			InputMap.action_add_event(action, e)
