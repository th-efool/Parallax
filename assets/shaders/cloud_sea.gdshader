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

float fbm4(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v / 0.875;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Perf: 4 + 3 octaves (was 4 x 4-octave evaluations); the bump normal comes from screen-space
	// derivatives of the cloud height instead of two extra full fbm evaluations.
	vec2 p = w_pos.xz * scale + TIME * drift;
	float c = fbm4(p);
	float c2 = fbm3(p * 2.7 - TIME * drift * 1.7);
	float h = c * 0.75 + c2 * 0.35;
	float puff = smoothstep(0.32, 0.78, h);
	vec3 col = mix(shade_color.rgb, lit_color.rgb, puff);
	vec3 mcol = mix(mirror_shade.rgb, mirror_lit.rgb, puff * puff);
	ALBEDO = mix(col, mcol, clamp(realm_mirror_blend, 0.0, 1.0));
	ROUGHNESS = 1.0;
	// Slight self-glow so cloud tops read bright against the fogged horizon.
	EMISSION = ALBEDO * puff * 0.18;
	vec3 bump_pos = vec3(w_pos.x, h * 26.0, w_pos.z);
	vec3 wn = normalize(cross(dFdy(bump_pos), dFdx(bump_pos)));
	wn = wn.y < 0.0 ? -wn : wn;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
