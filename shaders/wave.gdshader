// Procedural breaking wave. The mesh is a flat grid where VERTEX.x = x along the
// wave (local) and VERTEX.y = a 0..1 profile parameter. Everything else is computed
// here. The rideable face comes from wave_shape.gdshaderinc, which is mirrored in
// scripts/wave.gd and checked by tests/test_wave_parity.gd. The rest of this file
// (back of the wave, lip curtain, whitewater, colour) only affects the visuals.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/wave_shape.gdshaderinc"

uniform float x_offset = 0.0;     // mesh world x, for stable foam noise
uniform bool lip_mode = false;    // false = wave body, true = pitching lip sheet

uniform vec3 deep_color : source_color = vec3(0.02, 0.15, 0.28);
uniform vec3 face_color : source_color = vec3(0.03, 0.38, 0.50);
uniform vec3 lip_color : source_color = vec3(0.30, 0.78, 0.72);

varying float v_h;     // height ratio 0..1
varying float v_foam;
varying float v_k;
varying vec3 v_world;

vec3 body_pos(float x, float v) {
	float H = height_at(x);
	float Lf = lf_at(x);
	float Lb = 3.0 * H;
	vec3 p;
	if (v < 0.2) {
		float s = v / 0.2;
		p = vec3(x, 0.0, Lf + (1.0 - s) * 40.0);
	} else if (v < 0.6) {
		p = face_point(x, (v - 0.2) / 0.4);
	} else {
		float s = (v - 0.6) / 0.4;
		float s1 = min(s / 0.7, 1.0);
		p = vec3(x, H * 0.5 * (1.0 + cos(PI * s1)), -Lb * s1 - 40.0 * max(s - 0.7, 0.0) / 0.3);
	}
	// churning whitewater once broken
	float wx = x + x_offset;
	float b = broken_amt(x);
	float bump = b * (0.35 * sin(wx * 1.3 + TIME * 3.0 + v * 20.0) + 0.25 * sin(wx * 2.7 - TIME * 4.0 + v * 37.0));
	p.y += bump * 0.6 * smooth01(p.y / max(H, 0.01) * 3.0);
	return p;
}

vec3 lip_pos(float x, float w) {
	float H = height_at(x);
	float k = k_at(x);
	float th = w * 2.4 * k;
	return vec3(x, H - 0.55 * H * (1.0 - cos(th)), 1.15 * H * sin(th));
}

void vertex() {
	float x = VERTEX.x;
	float v = VERTEX.y;
	vec3 p; vec3 px; vec3 pv;
	if (lip_mode) {
		p = lip_pos(x, v);
		px = lip_pos(x + 0.3, v);
		pv = lip_pos(x, v + 0.01);
	} else {
		p = body_pos(x, v);
		px = body_pos(x + 0.3, v);
		pv = body_pos(x, v + 0.004);
	}
	VERTEX = p;
	vec3 n = cross(px - p, pv - p);
	NORMAL = length(n) > 1e-6 ? normalize(n) : vec3(0.0, 1.0, 0.0);

	float H = max(height_at(x), 0.01);
	v_k = k_at(x);
	v_h = clamp(p.y / H, 0.0, 1.0);
	float b = broken_amt(x);
	if (lip_mode) {
		v_foam = smooth01((v - 0.75) / 0.25) * v_k + b;
	} else {
		v_foam = b * 0.9 + smooth01((v_h - 0.93) / 0.07) * v_k * 0.6;
	}
	v_world = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	if (dot(NORMAL, VIEW) < 0.0) { NORMAL = -NORMAL; }
	vec3 col = mix(deep_color, face_color, smoothstep(0.0, 0.8, v_h));
	col = mix(col, lip_color, smoothstep(0.55, 1.0, v_h) * v_k);
	float streak = 0.75 + 0.25 * sin(v_world.x * 2.3 + v_world.y * 6.0 + TIME * 2.0) * sin(v_world.z * 3.1 - TIME);
	float foam = clamp(v_foam * streak, 0.0, 1.0);
	col = mix(col, vec3(0.94, 0.97, 1.0), foam);
	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.75, foam);
	SPECULAR = 0.6;
	// cheap subsurface glow through the thin top of the wave
	EMISSION = lip_color * 0.22 * smoothstep(0.45, 1.0, v_h) * v_k * (1.0 - foam);
}
