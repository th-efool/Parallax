shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Spectral Mirror material for Phantom Twins, Mirror stepping stones and the spectral bridge (Claude Pass B).
// Rim Fresnel glow + animated spectral alpha noise (procedural; `dissolve_noise` texture optional).

uniform vec4 base_tint : source_color = vec4(0.06, 0.14, 0.30, 0.72);
uniform vec4 rim_color : source_color = vec4(0.20, 0.75, 1.00, 1.00);
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rim_strength : hint_range(0.0, 5.0) = 2.4;
uniform float scanline_density : hint_range(10.0, 150.0) = 55.0;
uniform float scanline_speed = 3.0;
uniform sampler2D dissolve_noise : hint_default_white;
uniform bool use_noise_texture = false;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float spectral_noise_strength : hint_range(0.0, 1.0) = 0.35;
uniform float spectral_noise_scale = 3.0;
uniform float spectral_noise_speed = 0.6;
uniform float min_alpha : hint_range(0.0, 1.0) = 0.18;

varying vec3 world_pos;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i + vec3(0, 0, 0)), hash31(i + vec3(1, 0, 0)), f.x),
			mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
			mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 drift = vec3(0.0, TIME * spectral_noise_speed, TIME * spectral_noise_speed * 0.37);
	float proc_n = noise3(world_pos * spectral_noise_scale + drift) * 0.65
		+ noise3(world_pos * spectral_noise_scale * 2.7 - drift * 1.8) * 0.35;
	float n = use_noise_texture ? texture(dissolve_noise, UV * 2.0).r : proc_n;
	if (n < dissolve_amount) {
		discard;
	}
	float edge = smoothstep(dissolve_amount, dissolve_amount + 0.08, n);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float scan = 0.9 + 0.1 * sin(world_pos.y * scanline_density + TIME * scanline_speed);
	float shimmer = mix(1.0, 0.55 + 0.9 * proc_n, spectral_noise_strength);

	ALBEDO = base_tint.rgb * scan;
	EMISSION = rim_color.rgb * (fresnel * rim_strength * shimmer + (1.0 - edge) * 3.0);
	ALPHA = clamp((base_tint.a + fresnel * 0.65) * shimmer, min_alpha, 1.0);
}
