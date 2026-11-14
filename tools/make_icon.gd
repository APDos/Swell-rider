extends SceneTree
## Draws the app icon (icon.png, 1024x1024): a curling wave over a warm sky.
##   godot --headless --path . -s res://tools/make_icon.gd

const N := 1024

func _initialize() -> void:
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	var sky_top := Color(0.99, 0.62, 0.36)
	var sky_low := Color(1.0, 0.86, 0.62)
	var deep := Color(0.02, 0.18, 0.34)
	var face := Color(0.04, 0.45, 0.58)
	var lip := Color(0.35, 0.85, 0.80)
	var foam := Color(0.96, 0.98, 1.0)
	# Curl: a circle the lip wraps around, centred left of middle.
	var cc := Vector2(330, 470)
	var cr := 210.0
	for y in N:
		for x in N:
			var u := float(x) / N
			var v := float(y) / N
			var col := sky_top.lerp(sky_low, v)
			# Wave crest line: rises from the right shoulder up into the curl.
			var crest := 0.42 + 0.22 * smoothstep(0.25, 1.0, u) + 0.05 * sin(u * 9.0)
			if v > crest:
				var depth := clampf((v - crest) / 0.45, 0.0, 1.0)
				col = lip.lerp(face, smoothstep(0.0, 0.25, depth)).lerp(deep, smoothstep(0.25, 1.0, depth))
				if v - crest < 0.018:
					col = foam
			var p := Vector2(x, y)
			var dist := p.distance_to(cc)
			# The pitching lip: a thick ring around the curl, open at the bottom right.
			var ang := atan2(p.y - cc.y, p.x - cc.x)
			if dist < cr + 70.0 and dist > cr and not (ang > 0.2 and ang < 1.9):
				col = lip.lerp(face, clampf((dist - cr) / 70.0, 0.0, 1.0))
				if dist > cr + 58.0:
					col = foam
			elif dist <= cr:
				col = deep.lerp(face, 0.25 + 0.35 * (1.0 - dist / cr))
			# Foam ball tumbling at the bottom of the curl.
			if p.distance_to(Vector2(250, 720)) < 150.0 and v > crest - 0.05:
				col = foam.lerp(lip, 0.15 * (p.distance_to(Vector2(250, 720)) / 150.0))
			img.set_pixel(x, y, col)
	img.save_png("res://icon.png")
	print("wrote icon.png")
	quit()
