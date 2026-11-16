shader_type canvas_item;

// Full-screen realm-shift overlay (Claude Pass B).
// Applied to `Main/RealmShiftFX/PulseOverlay` (ColorRect) by RealmEnvironmentController, which tweens
// `shift_progress` 0 -> 1 over the 0.20 s transition. Chromatic aberration and radial lens distortion
// follow sin(pi * t), so both peak exactly at t = 0.5 and vanish at the start/end of the shift.

uniform float shift_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pulse_color : source_color = vec4(0.2, 0.78, 1.0, 1.0);
uniform float thickness = 0.12;
uniform float max_aberration : hint_range(0.0, 0.05) = 0.012;
uniform float max_distortion : hint_range(-1.0, 1.0) = 0.22;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

void fragment() {
	float t = clamp(shift_progress, 0.0, 1.0);
	float peak = sin(3.14159265 * t);

	// Radial (barrel) lens distortion around screen centre.
	vec2 centered = SCREEN_UV - vec2(0.5);
	float r2 = dot(centered, centered);
	vec2 distorted = vec2(0.5) + centered * (1.0 - max_distortion * peak * r2);

	// Chromatic aberration: split R/B radially, strongest at the screen edges.
	vec2 ca_dir = centered * max_aberration * peak * 2.0;
	float r = texture(screen_tex, distorted + ca_dir).r;
	float g = texture(screen_tex, distorted).g;
	float b = texture(screen_tex, distorted - ca_dir).b;
	vec3 scene = vec3(r, g, b);

	// Expanding shockwave ring (original pulse), tinted toward the destination realm.
	float dist = distance(UV, vec2(0.5));
	float ring = smoothstep(t - thickness, t, dist) * (1.0 - smoothstep(t, t + thickness, dist));
	float ring_alpha = ring * (1.0 - t) * 0.55;

	float vignette = smoothstep(0.25, 0.85, sqrt(r2) * 1.41421356) * vignette_strength * peak;
	vec3 col = mix(scene, pulse_color.rgb, clamp(ring_alpha + vignette * 0.6, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
