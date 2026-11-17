shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled, shadows_disabled;

// Lake / river surface: deep tinted body, animated ripple normals, strong fresnel sky reflection
// (radiance cubemap + SSR when enabled), sun glints. Mirror realm turns it into a dark obsidian mirror.

global uniform float realm_mirror_blend;
global uniform float realm_wetness;

uniform vec4 deep_color : source_color = vec4(0.04, 0.12, 0.14, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.26, 0.24, 1.0);
uniform vec4 mirror_color : source_color = vec4(0.01, 0.02, 0.06, 1.0);

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
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float waves(vec2 p, float t) {
	return vnoise(p * 0.35 + vec2(t * 0.06, t * 0.035)) * 0.6 + vnoise(p * 1.1 - vec2(t * 0.09, -t * 0.05)) * 0.3 + vnoise(p * 3.1 + t * 0.15) * 0.1;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * (1.0 + realm_wetness * 1.5);
	vec2 p = w_pos.xz;
	float e = 0.15;
	float h = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t) - h;
	float hz = waves(p + vec2(0.0, e), t) - h;
	float rough = 0.6 + realm_wetness * 1.2;
	vec3 wn = normalize(vec3(-hx * rough / e, 1.0, -hz * rough / e));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 body = mix(deep_color.rgb, shallow_color.rgb, h * 0.5);
	ALBEDO = mix(body, mirror_color.rgb, clamp(realm_mirror_blend, 0.0, 1.0)) * (1.0 - fres * 0.6);
	METALLIC = 0.0;
	ROUGHNESS = 0.04 + realm_wetness * 0.12;
	SPECULAR = 0.65;
}
