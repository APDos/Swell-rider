// Test-only shader: evaluates the wave shape functions on the GPU and writes
// the results to pixels so tests/test_wave_parity.gd can compare them with
// scripts/wave.gd.
//
// Layout: column i samples x = x_start + i * x_step (mesh-local x).
// Row r = quantity * n_t + ti, with t = ti / (n_t - 1).
// Each pixel holds one float's 32 bits spread over RGBA (high byte in R), so
// the value comes back exactly as the GPU computed it.
shader_type canvas_item;
render_mode blend_disabled;

#include "res://shaders/wave_shape.gdshaderinc"

uniform float x_start;
uniform float x_step;
uniform int n_t;

const int Q_X = 0;        // x itself: checks decoding and column order
const int Q_FACE_Y = 1;
const int Q_FACE_Z = 2;
const int Q_K = 3;
const int Q_HEIGHT = 4;
const int Q_BROKEN = 5;

void fragment() {
	ivec2 px = ivec2(FRAGCOORD.xy);
	float x = x_start + float(px.x) * x_step;
	int q = px.y / n_t;
	float t = float(px.y % n_t) / float(n_t - 1);
	vec3 fp = face_point(x, t);
	float val = 0.0;
	if (q == Q_X) { val = x; }
	else if (q == Q_FACE_Y) { val = fp.y; }
	else if (q == Q_FACE_Z) { val = fp.z; }
	else if (q == Q_K) { val = k_at(x); }
	else if (q == Q_HEIGHT) { val = height_at(x); }
	else if (q == Q_BROKEN) { val = broken_amt(x); }
	uint b = floatBitsToUint(val);
	COLOR = vec4(float((b >> 24u) & 255u), float((b >> 16u) & 255u), float((b >> 8u) & 255u), float(b & 255u)) / 255.0;
}
