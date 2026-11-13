// Wave shape model: the part of the wave that gameplay depends on.
//
// This file is the GPU half of the shape. scripts/wave.gd is the CPU half: it
// evaluates the same functions so the surfer sits on the visible face.
//
// Rules that keep the two halves in step:
// - No tuning numbers live here. Every shape parameter is a uniform with no
//   default, and wave.gd pushes the values from its SHAPE table. If a value
//   isn't pushed it reads as 0 and the wave visibly breaks, and
//   tests/test_wave_parity.gd fails.
// - Every function here has a twin in wave.gd with the same name, and
//   tests/test_wave_parity.gd checks that the two agree, sample by sample, on the GPU.
// - Shape math used only for looks (the back of the wave, the lip curtain,
//   whitewater bumps) stays in wave.gdshader, not here.

// ---- per-frame state, set by wave.gd ----
uniform float H0;          // wave height at the curl (m)
uniform float curl_x;      // breaking point, mesh-local x
uniform vec3 closeout;     // x0, x1 (mesh-local), strength

// ---- shape parameters (wave.gd SHAPE table) ----
uniform float shape_p;               // face curvature exponent
uniform float break_width;           // m behind the curl over which the wave goes from unbroken to fully broken
uniform float height_far;            // height ratio far ahead of the curl
uniform float height_decay;          // m: how fast height falls off ahead of the curl
uniform float broken_height;         // height ratio once fully broken
uniform float steep_decay;           // m: how fast steepness falls off ahead of the curl
uniform float closeout_ramp;         // m: blend at the ends of a closeout section
uniform float face_len_mellow;       // face run-out / height when k = 0
uniform float face_len_steep;        // face run-out / height when k = 1
uniform float lip_curl;              // rad the lip curtain curls over at k = 1
uniform float lip_drop;              // lip curtain drop / height per unit of (1 - cos)
uniform float lip_throw;             // lip curtain throw toward shore / height per unit of sin

float smooth01(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }

float broken_amt(float x) { return smooth01(-(x - curl_x) / break_width); }

float height_at(float x) {
	float d = x - curl_x;
	float ahead = height_far + (1.0 - height_far) * exp(-max(d, 0.0) / height_decay);
	return H0 * mix(ahead, broken_height, broken_amt(x));
}

float k_at(float x) {
	float d = x - curl_x;
	float k = exp(-max(d, 0.0) / steep_decay);
	float inside = smooth01((x - closeout.x) / closeout_ramp) * (1.0 - smooth01((x - closeout.y) / closeout_ramp));
	k = max(k, inside * closeout.z);
	return k * (1.0 - broken_amt(x));
}

float lf_at(float x) { return mix(face_len_mellow, face_len_steep, k_at(x)) * height_at(x); }

// Point on the pitching lip curtain. w: 0 = top of the lip, 1 = its tip. Drawn
// as its own sheet; the CPU uses it to tell when the lip hides the surfer.
vec3 lip_pos(float x, float w) {
	float H = height_at(x);
	float th = w * lip_curl * k_at(x);
	return vec3(x, H - lip_drop * H * (1.0 - cos(th)), lip_throw * H * sin(th));
}

// Point on the rideable face. t: 0 = trough, 1 = lip line.
vec3 face_point(float x, float t) {
	return vec3(x, height_at(x) * pow(clamp(t, 0.0, 1.0), shape_p), lf_at(x) * (1.0 - t));
}
