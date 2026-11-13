extends Node3D
## The wave: renders the body + pitching lip, and exposes the same shape math the
## shader uses so the surfer can sit exactly on the face.
## Coordinates: +X = down the line (direction of the peel), +Y = up, +Z = toward shore.
## Face parameter t: 0 = trough, 1 = top of the lip.

const P := 1.4
const X_BEHIND := 50.0
const X_AHEAD := 170.0
const SEG_X := 220
const SEG_V_BODY := 90
const SEG_V_LIP := 24

var base_height := 3.0
var curl_x := 0.0                              # world x of the breaking point
var closeout := Vector3(1e6, 1e6 + 1.0, 0.0)   # world x0, x1, strength

var _mat_body: ShaderMaterial
var _mat_lip: ShaderMaterial


func _ready() -> void:
	var shader: Shader = load("res://shaders/wave.gdshader")
	_mat_body = ShaderMaterial.new()
	_mat_body.shader = shader
	_mat_lip = ShaderMaterial.new()
	_mat_lip.shader = shader
	_mat_lip.set_shader_parameter("lip_mode", true)

	var body := MeshInstance3D.new()
	body.mesh = _grid(SEG_X, SEG_V_BODY)
	body.material_override = _mat_body
	add_child(body)

	var lip := MeshInstance3D.new()
	lip.mesh = _grid(SEG_X, SEG_V_LIP)
	lip.material_override = _mat_lip
	lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(lip)


func _grid(nx: int, nv: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in nv + 1:
		var v := float(j) / nv
		for i in nx + 1:
			var x := -X_BEHIND + (X_BEHIND + X_AHEAD) * float(i) / nx
			verts.append(Vector3(x, v, 0.0))
	for j in nv:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.custom_aabb = AABB(Vector3(-X_BEHIND - 5.0, -5.0, -80.0), Vector3(X_BEHIND + X_AHEAD + 10.0, 25.0, 160.0))
	return m


## Keep the mesh centred on the action. Snapped to the grid spacing so the
## vertices don't swim.
func follow(focus_x: float) -> void:
	var step := (X_BEHIND + X_AHEAD) / SEG_X
	position.x = snappedf(focus_x, step)
	for m in [_mat_body, _mat_lip]:
		m.set_shader_parameter("H0", base_height)
		m.set_shader_parameter("curl_x", curl_x - position.x)
		m.set_shader_parameter("closeout", Vector3(closeout.x - position.x, closeout.y - position.x, closeout.z))
		m.set_shader_parameter("x_offset", position.x)


# ---- shape model (mirror of wave.gdshader) ------------------------------------

static func _smooth01(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func broken_amt(x: float) -> float:
	return _smooth01(-(x - curl_x) / 6.0)

func height_at(x: float) -> float:
	var d := x - curl_x
	var ahead := 0.35 + 0.65 * exp(-maxf(d, 0.0) / 90.0)
	return base_height * lerpf(ahead, 0.4, broken_amt(x))

func k_at(x: float) -> float:
	var d := x - curl_x
	var k := exp(-maxf(d, 0.0) / 12.0)
	var inside := _smooth01((x - closeout.x) / 6.0) * (1.0 - _smooth01((x - closeout.y) / 6.0))
	k = maxf(k, inside * closeout.z)
	return k * (1.0 - broken_amt(x))

func lf_at(x: float) -> float:
	return lerpf(1.5, 0.75, k_at(x)) * height_at(x)

func face_point(x: float, t: float) -> Vector3:
	var h := height_at(x)
	return Vector3(x, h * pow(clampf(t, 0.0, 1.0), P), lf_at(x) * (1.0 - t))

## Unit tangent pointing up the face at (x, t).
func face_up(x: float, t: float) -> Vector3:
	var h := height_at(x)
	return Vector3(0.0, h * P * pow(maxf(t, 0.02), P - 1.0), -lf_at(x)).normalized()

## Face steepness angle (radians) at (x, t).
func slope_at(x: float, t: float) -> float:
	var h := height_at(x)
	return atan(h * P * pow(maxf(t, 0.02), P - 1.0) / lf_at(x))

func face_length(x: float) -> float:
	var h := height_at(x)
	var lf := lf_at(x)
	return sqrt(lf * lf + h * h)
