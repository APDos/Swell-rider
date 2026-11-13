// Procedural breaking wave. The mesh is a flat grid where VERTEX.x = x along the
// wave (local) and VERTEX.y = a 0..1 profile parameter. Everything else is computed
// here. The same math lives in scripts/wave.gd so gameplay matches the visuals —
// if you change a formula here, change it there too.
shader_type spatial;
render_mode cull_disabled;

uniform float H0 = 3.0;           // wave height at the curl (m)
uniform float curl_x = 0.0;       // breaking point, mesh-local x
uniform vec3 closeout = vec3(10000.0, 10001.0, 0.0); // x0, x1 (local), strength
uniform float x_offset = 0.0;     // mesh world x, for stable foam noise
uniform bool lip_mode = false;    // false = wave body, true = pitching lip sheet

uniform vec3 deep_color : source_color = vec3(0.02, 0.15, 0.28);
uniform vec3 face_color : source_color = vec3(0.03, 0.38, 0.50);
uniform vec3 lip_color : source_color = vec3(0.30, 0.78, 0.72);

const float P = 1.4;

varying float v_h;     // height ratio 0..1
varying float v_foam;
varying float v_k;
varying vec3 v_world;

float smooth01(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }
float broken_amt(float d) { return smooth01(-d / 6.0); }

float wave_h(float x) {
	float d = x - curl_x;
	float ahead = 0.35 + 0.65 * exp(-max(d, 0.0) / 90.0);
	return H0 * mix(ahead, 0.4, broken_amt(d));
}

float wave_k(float x) {
	float d = x - curl_x;
	float k = exp(-max(d, 0.0) / 12.0);
	float inside = smooth01((x - closeout.x) / 6.0) * (1.0 - smooth01((x - closeout.y) / 6.0));
	k = max(k, inside * closeout.z);
	return k * (1.0 - broken_amt(d));
}

vec3 body_pos(float x, float v) {
	float d = x - curl_x;
	float H = wave_h(x);
	float k = wave_k(x);
	float Lf = mix(1.5, 0.75, k) * H;
	float Lb = 3.0 * H;
	vec3 p;
	if (v < 0.2) {
		float s = v / 0.2;
		p = vec3(x, 0.0, Lf + (1.0 - s) * 40.0);
	} else if (v < 0.6) {
		float t = (v - 0.2) / 0.4;
		p = vec3(x, H * pow(t, P), Lf * (1.0 - t));
	} else {
		float s = (v - 0.6) / 0.4;
		float s1 = min(s / 0.7, 1.0);
		p = vec3(x, H * 0.5 * (1.0 + cos(PI * s1)), -Lb * s1 - 40.0 * max(s - 0.7, 0.0) / 0.3);
	}
	// churning whitewater once broken
	float wx = x + x_offset;
	float b = broken_amt(d);
	float bump = b * (0.35 * sin(wx * 1.3 + TIME * 3.0 + v * 20.0) + 0.25 * sin(wx * 2.7 - TIME * 4.0 + v * 37.0));
	p.y += bump * 0.6 * smooth01(p.y / max(H, 0.01) * 3.0);
	return p;
}

vec3 lip_pos(float x, float w) {
	float H = wave_h(x);
	float k = wave_k(x);
	float th = w * 2.4 * k;
	return vec3(x, H - 0.55 * H * (1.0 - cos(th)), 1.15 * H * sin(th));
}

void vertex() {
	float x = VERTEX.x;
	float v = VERTEX.y;
	float d = x - curl_x;
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

	float H = max(wave_h(x), 0.01);
	v_k = wave_k(x);
	v_h = clamp(p.y / H, 0.0, 1.0);
	float b = broken_amt(d);
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
