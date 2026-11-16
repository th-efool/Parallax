shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// Arc-ribbon sword trail (Claude Pass A).
// Expects a ribbon mesh where UV.x runs along the swing (0 = start, 1 = end) and UV.y runs inner -> outer edge
// (see CombatVFX.build_arc_ribbon_mesh). Tween `progress` from 0 to (1 + trail_length) to sweep the head
// across the arc, and `fade` to 0 to dissolve.

uniform vec4 slash_color : source_color = vec4(1.0, 0.65, 0.2, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.96, 0.86, 1.0);
uniform sampler2D noise_tex : hint_default_white, repeat_enable;
uniform bool use_noise_tex = false;
uniform float progress : hint_range(0.0, 2.0) = 0.5;
uniform float trail_length : hint_range(0.05, 1.0) = 0.55;
uniform float intensity : hint_range(0.5, 5.0) = 2.5;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	// Distance behind the travelling head (positive = already swept).
	float behind = progress - UV.x;
	float head_edge = smoothstep(-0.035, 0.0, behind);
	float tail = 1.0 - smoothstep(0.0, trail_length, behind);
	float trail_mask = head_edge * tail;

	// Brightest along the outer (blade-tip) edge, soft inner edge.
	float across = smoothstep(0.0, 0.45, UV.y) * (1.0 - smoothstep(0.88, 1.0, UV.y));

	float streaks;
	if (use_noise_tex) {
		streaks = texture(noise_tex, vec2(UV.x * 2.0 - TIME * 4.0, UV.y * 3.0)).r;
	} else {
		streaks = value_noise(vec2(UV.x * 16.0 - TIME * 7.0, UV.y * 4.0));
	}

	float hot = pow(clamp(tail * UV.y, 0.0, 1.0), 3.0);
	vec3 col = mix(slash_color.rgb, core_color.rgb, hot);

	float alpha = clamp(trail_mask * across * (0.45 + 0.55 * streaks), 0.0, 1.0);
	ALBEDO = col * intensity;
	ALPHA = alpha * slash_color.a * fade;
}
