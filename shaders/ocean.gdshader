shader_type spatial;

uniform vec3 deep : source_color = vec3(0.02, 0.15, 0.28);
uniform vec3 shallow : source_color = vec3(0.04, 0.28, 0.40);

varying vec3 wpos;

float h(vec2 p) {
	return 0.06 * sin(p.x * 0.35 + TIME * 1.3)
		+ 0.05 * sin(p.y * 0.5 - TIME * 1.1)
		+ 0.03 * sin((p.x + p.y) * 1.1 + TIME * 2.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += h(wpos.xz);
	float e = 0.1;
	float dx = (h(wpos.xz + vec2(e, 0.0)) - h(wpos.xz - vec2(e, 0.0))) / (2.0 * e);
	float dz = (h(wpos.xz + vec2(0.0, e)) - h(wpos.xz - vec2(0.0, e))) / (2.0 * e);
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	float n = 0.5 + 0.5 * sin(wpos.x * 0.9 + TIME) * sin(wpos.z * 0.7 - TIME * 0.8);
	ALBEDO = mix(deep, shallow, n * 0.4);
	ROUGHNESS = 0.12;
	SPECULAR = 0.5;
}
