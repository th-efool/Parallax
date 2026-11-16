shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// Monolithic obsidian/glass surface for Stage05 `CentralMirrorPlane` (Claude Pass B).
// Near-black, mirror-smooth glass with a cobalt Fresnel sheen, a slow liquid ripple, and fracture lines
// that brighten with `crack_amount` (Warden HP -> 500). Kept translucent (`surface_alpha`) because the
// plane bisects the arena at X = 0 and The Warden spawns inside it — the boss must stay readable.

uniform vec4 obsidian_color : source_color = vec4(0.02, 0.025, 0.04, 1.0);
uniform vec4 rim_color : source_color = vec4(0.25, 0.62, 1.0, 1.0);
uniform vec4 crack_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.1;
uniform float ripple_strength : hint_range(0.0, 0.3) = 0.06;
uniform float crack_amount : hint_range(0.0, 1.0) = 0.0;
uniform float surface_alpha : hint_range(0.1, 1.0) = 0.5;

varying vec3 w_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Voronoi edge distance -> fracture lines.
float voronoi_edge(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash12(n + g), hash12(n + g + 19.19));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 plane_uv = vec2(w_pos.z, w_pos.y);
	vec2 ripple = vec2(sin(plane_uv.y * 1.7 + TIME * 0.6), cos(plane_uv.x * 1.3 - TIME * 0.45)) * ripple_strength;
	NORMAL = normalize(NORMAL + vec3(ripple.x, ripple.y, 0.0) * 0.5);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float edge = voronoi_edge(plane_uv * 0.9);
	float crack = (1.0 - smoothstep(0.0, 0.06 + 0.04 * crack_amount, edge)) * smoothstep(0.0, 0.15, crack_amount);

	ALBEDO = obsidian_color.rgb;
	METALLIC = 0.9;
	ROUGHNESS = mix(0.04, 0.3, crack);
	SPECULAR = 0.9;
	EMISSION = rim_color.rgb * fresnel * rim_strength + crack_color.rgb * crack * (1.5 + 3.0 * crack_amount);
	ALPHA = clamp(surface_alpha + fresnel * 0.35 + crack * 0.4, 0.0, 1.0);
}
