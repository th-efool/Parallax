shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled, shadows_disabled;

// Endless sea of clouds far below the cliff-top journey. Cheap 4-octave world-space fbm, slowly drifting,
// lit by the scene sun and reacting to the realm global (golden cumulus -> moonlit indigo mist).

global uniform float realm_mirror_blend;

uniform vec4 lit_color : source_color = vec4(1.0, 0.86, 0.68, 1.0);
uniform vec4 shade_color : source_color = vec4(0.42, 0.40, 0.48, 1.0);
uniform vec4 mirror_lit : source_color = vec4(0.30, 0.42, 0.75, 1.0);
uniform vec4 mirror_shade : source_color = vec4(0.03, 0.05, 0.12, 1.0);
uniform float scale = 0.006;
uniform vec2 drift = vec2(0.004, 0.0015);

varying vec3 w_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = w_pos.xz * scale + TIME * drift;
	float c = fbm(p);
	float c2 = fbm(p * 2.7 - TIME * drift * 1.7);
	float puff = smoothstep(0.32, 0.78, c * 0.75 + c2 * 0.35);
	vec3 col = mix(shade_color.rgb, lit_color.rgb, puff);
	vec3 mcol = mix(mirror_shade.rgb, mirror_lit.rgb, puff * puff);
	ALBEDO = mix(col, mcol, clamp(realm_mirror_blend, 0.0, 1.0));
	ROUGHNESS = 1.0;
	// Slight self-glow so cloud tops read bright against the fogged horizon.
	EMISSION = ALBEDO * puff * 0.18;
	// Bumpy tops: fake normal from noise gradient.
	float e = 0.6;
	float cx = fbm(p + vec2(e * scale * 40.0, 0.0));
	float cz = fbm(p + vec2(0.0, e * scale * 40.0));
	vec3 wn = normalize(vec3((c - cx) * 3.0, 1.0, (c - cz) * 3.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
