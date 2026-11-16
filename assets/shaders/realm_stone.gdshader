shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// World-space triplanar masonry for shared greybox floors/walls (Claude Pass B).
// `mirror_blend` (0 = Reality, 1 = Mirror) is tweened by ColosseumGreyboxBuilder on every realm shift:
//   Reality -> warm, sun-bleached limestone blocks with dark mortar.
//   Mirror  -> deep cobalt/slate stone whose mortar seams glow as emissive runic lines.

uniform vec4 reality_tint : source_color = vec4(0.72, 0.62, 0.48, 1.0);
uniform vec4 mirror_tint : source_color = vec4(0.11, 0.15, 0.24, 1.0);
uniform vec4 rune_color : source_color = vec4(0.22, 0.70, 1.0, 1.0);
uniform float mirror_blend : hint_range(0.0, 1.0) = 0.0;
uniform vec2 block_size = vec2(1.2, 0.6);
uniform float floor_tile = 1.5;
uniform float mortar_width : hint_range(0.0, 0.2) = 0.045;
uniform float rune_strength : hint_range(0.0, 8.0) = 2.6;
uniform float rune_pulse_speed = 1.4;

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
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Returns (mortar mask, per-block random) for a running-bond brick pattern.
vec2 bricks(vec2 uv, vec2 size) {
	vec2 cell = uv / size;
	float row = floor(cell.y);
	cell.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	vec2 d = min(f, 1.0 - f) * size;
	float edge = min(d.x, d.y);
	float mortar = 1.0 - smoothstep(mortar_width * 0.5, mortar_width, edge);
	return vec2(mortar, hash12(id));
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(w_nrm);
	vec3 bw = pow(an, vec3(4.0));
	bw /= (bw.x + bw.y + bw.z + 1e-5);

	vec2 bx = bricks(w_pos.zy, block_size);
	vec2 bz = bricks(w_pos.xy, block_size);
	vec2 by = bricks(w_pos.xz, vec2(floor_tile));
	float mortar = bx.x * bw.x + by.x * bw.y + bz.x * bw.z;
	float block_rand = bx.y * bw.x + by.y * bw.y + bz.y * bw.z;

	float grain = vnoise(w_pos.xz * 3.1 + w_pos.y * 1.7) * 0.6 + vnoise(w_pos.zy * 9.0) * 0.4;
	float variation = mix(0.82, 1.12, block_rand) * mix(0.9, 1.06, grain);

	vec3 reality_col = reality_tint.rgb * variation;
	reality_col = mix(reality_col, reality_col * 0.42, mortar);
	vec3 mirror_col = mirror_tint.rgb * mix(0.85, 1.15, block_rand) * mix(0.92, 1.05, grain);
	mirror_col = mix(mirror_col, mirror_col * 0.35, mortar);

	ALBEDO = mix(reality_col, mirror_col, mirror_blend);
	ROUGHNESS = mix(mix(0.92, 0.98, mortar), mix(0.38, 0.85, mortar), mirror_blend);
	METALLIC = mix(0.0, 0.12, mirror_blend);

	float pulse = 0.75 + 0.25 * sin(TIME * rune_pulse_speed + (w_pos.x + w_pos.z) * 0.35);
	EMISSION = rune_color.rgb * mortar * rune_strength * pulse * mirror_blend;
}
