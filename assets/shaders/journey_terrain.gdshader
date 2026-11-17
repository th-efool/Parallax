shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Grand Journey landscape: world-space, slope/height-driven layers.
// Flat = meadow grass (procedural colour over sand-rock detail), mid slopes = scree, steep = triplanar rock face,
// high peaks = snow. Mirror realm: moonlit silver-blue with faint cobalt glow in the rock seams.
// Wet surfaces from the WeatherDirector `realm_wetness` global.

global uniform float realm_mirror_blend;
global uniform float realm_wetness;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_scale = 0.045;
uniform float ground_scale = 0.11;
uniform vec4 grass_dry : source_color = vec4(0.52, 0.52, 0.26, 1.0);
uniform vec4 grass_lush : source_color = vec4(0.20, 0.36, 0.12, 1.0);
uniform vec4 scree_tint : source_color = vec4(0.78, 0.68, 0.56, 1.0);
uniform vec4 rock_tint : source_color = vec4(0.90, 0.80, 0.72, 1.0);
uniform vec4 snow_color : source_color = vec4(0.95, 0.94, 0.98, 1.0);
uniform vec4 mirror_ground : source_color = vec4(0.16, 0.22, 0.36, 1.0);
uniform vec4 mirror_rock : source_color = vec4(0.32, 0.38, 0.55, 1.0);
uniform vec4 mirror_glow : source_color = vec4(0.25, 0.55, 1.0, 1.0);
uniform float snow_line = 150.0;

varying vec3 w_pos;
varying vec3 w_nrm;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.07 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 bw) {
	return texture(tex, p.zy).rgb * bw.x + texture(tex, p.xz).rgb * bw.y + texture(tex, p.xy).rgb * bw.z;
}

void fragment() {
	vec3 n = normalize(w_nrm);
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	float slope = 1.0 - n.y;                 // 0 flat .. 1 vertical
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);

	// Macro variation breaks tiling at every distance.
	float macro = fbm(w_pos.xz * 0.004);
	float meso = fbm(w_pos.xz * 0.03);

	// --- layers
	vec3 rock = triplanar(rock_albedo, w_pos * rock_scale, bw) * rock_tint.rgb;
	rock *= 0.8 + 0.4 * macro;
	vec3 ground_tex = texture(ground_albedo, w_pos.xz * ground_scale).rgb;
	float g_luma = dot(ground_tex, vec3(0.333));
	vec3 grass = mix(grass_lush.rgb, grass_dry.rgb, smoothstep(0.45, 0.85, macro + max(w_pos.y - 10.0, 0.0) * 0.003) * 0.85);
	grass *= 0.7 + 0.6 * g_luma;
	grass *= 0.85 + 0.3 * meso;
	vec3 scree = ground_tex * scree_tint.rgb;

	// Slope weights with noisy borders so layers interleave naturally.
	float edge = (meso - 0.5) * 0.18;
	float w_rock = smoothstep(0.30 + edge, 0.48 + edge, slope);
	float w_scree = smoothstep(0.14 + edge, 0.28 + edge, slope) * (1.0 - w_rock);
	vec3 col = grass;
	col = mix(col, scree, w_scree);
	col = mix(col, rock, w_rock);

	// Snow caps on the high peaks (holds on gentler slopes only).
	float snow = smoothstep(snow_line - 25.0, snow_line + 25.0, w_pos.y + macro * 60.0) * (1.0 - smoothstep(0.35, 0.62, slope));
	col = mix(col, snow_color.rgb, snow);

	// River banks / lake shore: darker damp band just above the water line (-52).
	float shore = 1.0 - smoothstep(-52.0, -48.5, w_pos.y);
	col *= 1.0 - shore * 0.35;

	// --- Mirror realm
	float mb = clamp(realm_mirror_blend, 0.0, 1.0);
	vec3 mcol = mix(mirror_ground.rgb * (0.7 + 0.6 * g_luma), mirror_rock.rgb * (0.6 + 0.8 * dot(rock, vec3(0.333))), w_rock);
	mcol = mix(mcol, vec3(0.75, 0.82, 1.0), snow);
	col = mix(col, mcol, mb);
	float seam = smoothstep(0.62, 0.7, fbm(w_pos.xz * 0.05 + w_pos.y * 0.03)) * w_rock;
	EMISSION = mirror_glow.rgb * seam * mb * 0.6;

	// --- Normals (fade detail with distance)
	float detail = 1.0 - smoothstep(60.0, 260.0, dist);
	vec3 nm_rock = triplanar(rock_normal, w_pos * rock_scale, bw) * 2.0 - 1.0;
	vec3 nm_ground = texture(ground_normal, w_pos.xz * ground_scale).rgb * 2.0 - 1.0;
	vec3 nm = mix(nm_ground, nm_rock, w_rock);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nm * 0.5 + 0.5, detail * 0.8);

	// --- Wetness
	float wet = clamp(realm_wetness, 0.0, 1.0) * (1.0 - snow);
	col *= 1.0 - wet * 0.35;
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.95, 0.82, w_rock), 0.35, wet * (1.0 - slope));
	SPECULAR = 0.3 + wet * 0.3;
}
