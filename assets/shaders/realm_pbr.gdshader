shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// World-space triplanar PBR for the Grand Journey level (Poly Haven CC0 albedo / GL-normal / ARM sets).
// No mesh UVs needed, so procedural geometry (extrusions, displaced rocks, ring tiers) texture correctly.
// Realm reaction comes from ONE global uniform (project.godot [shader_globals]) set by RealmEnvironmentController:
//   0 = Reality (sun-warmed stone)  ->  1 = Mirror (cobalt slate whose cracks & mortar glow as runes).

global uniform float realm_mirror_blend;
global uniform float realm_wetness; // 0 dry .. 1 soaked (WeatherDirector rain)

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_scale = 0.25;          // texture repeats per metre
uniform vec4 tint : source_color = vec4(1.0);
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float blend_sharpness : hint_range(1.0, 16.0) = 6.0;
uniform float macro_variation : hint_range(0.0, 1.0) = 0.25;
uniform float roughness_bias : hint_range(-1.0, 1.0) = 0.0;
uniform float metallic_override : hint_range(-1.0, 1.0) = -1.0; // < 0 = use texture
uniform vec4 mirror_tint : source_color = vec4(0.17, 0.23, 0.38, 1.0);
uniform vec4 rune_color : source_color = vec4(0.25, 0.62, 1.0, 1.0);
uniform float rune_strength : hint_range(0.0, 8.0) = 2.2;
uniform float rune_threshold : hint_range(0.0, 1.0) = 0.42;

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

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 bw = pow(abs(n), vec3(blend_sharpness));
	bw /= max(dot(bw, vec3(1.0)), 1e-5);
	vec3 axis_sign = sign(n);

	vec2 uvx = w_pos.zy * tile_scale;
	vec2 uvy = w_pos.xz * tile_scale;
	vec2 uvz = w_pos.xy * tile_scale;
	uvx.x *= axis_sign.x;
	uvy.x *= axis_sign.y;
	uvz.x *= -axis_sign.z;

	vec3 alb = vec3(0.0);
	vec3 arm = vec3(0.0);
	vec3 wn = vec3(0.0);
	// Skip projections that contribute almost nothing (most surfaces are axis-aligned).
	if (bw.x > 0.02) {
		vec3 tn = texture(normal_tex, uvx).xyz * 2.0 - 1.0;
		tn.x *= axis_sign.x;
		tn = vec3(tn.xy + n.zy, abs(tn.z) * n.x);
		wn += tn.zyx * bw.x;
		alb += texture(albedo_tex, uvx).rgb * bw.x;
		arm += texture(arm_tex, uvx).rgb * bw.x;
	}
	if (bw.y > 0.02) {
		vec3 tn = texture(normal_tex, uvy).xyz * 2.0 - 1.0;
		tn.x *= axis_sign.y;
		tn = vec3(tn.xy + n.xz, abs(tn.z) * n.y);
		wn += tn.xzy * bw.y;
		alb += texture(albedo_tex, uvy).rgb * bw.y;
		arm += texture(arm_tex, uvy).rgb * bw.y;
	}
	if (bw.z > 0.02) {
		vec3 tn = texture(normal_tex, uvz).xyz * 2.0 - 1.0;
		tn.x *= -axis_sign.z;
		tn = vec3(tn.xy + n.xy, abs(tn.z) * n.z);
		wn += tn.xyz * bw.z;
		alb += texture(albedo_tex, uvz).rgb * bw.z;
		arm += texture(arm_tex, uvz).rgb * bw.z;
	}
	float wsum = bw.x * step(0.02, bw.x) + bw.y * step(0.02, bw.y) + bw.z * step(0.02, bw.z);
	alb /= max(wsum, 1e-4);
	arm /= max(wsum, 1e-4);
	wn = normalize(mix(n, normalize(wn), normal_strength));

	// Macro variation breaks visible tiling over large surfaces.
	float macro = vnoise(w_pos.xz * 0.045 + w_pos.y * 0.03) * 0.6 + vnoise(w_pos.xz * 0.17) * 0.4;
	alb *= tint.rgb * mix(1.0, 0.72 + 0.56 * macro, macro_variation);

	float mb = clamp(realm_mirror_blend, 0.0, 1.0);
	float luma = dot(alb, vec3(0.299, 0.587, 0.114));
	vec3 mirror_alb = mirror_tint.rgb * (0.55 + luma * 1.1);
	ALBEDO = mix(alb, mirror_alb, mb);

	float rough = clamp(arm.g + roughness_bias, 0.04, 1.0);
	// Rain: up-facing surfaces darken and turn glossy; puddles collect in cavities.
	float wet = clamp(realm_wetness, 0.0, 1.0) * smoothstep(0.2, 0.9, n.y);
	float puddle = wet * smoothstep(0.55, 0.25, arm.r * (0.6 + macro * 0.6));
	ALBEDO *= mix(1.0, 0.62, wet) * mix(1.0, 0.85, puddle);
	rough = mix(rough, 0.18, wet * 0.75);
	rough = mix(rough, 0.03, puddle);
	ROUGHNESS = mix(rough, rough * 0.55, mb);
	METALLIC = metallic_override >= 0.0 ? metallic_override : arm.b;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Cavities (low AO * dark albedo) become glowing cobalt rune seams in the Mirror.
	float cavity = 1.0 - smoothstep(rune_threshold * 0.5, rune_threshold, arm.r * (0.4 + luma));
	float pulse = 0.7 + 0.3 * sin(TIME * 1.3 + (w_pos.x + w_pos.z) * 0.21);
	EMISSION = rune_color.rgb * cavity * rune_strength * pulse * mb;
}
