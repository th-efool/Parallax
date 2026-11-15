shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 slash_color : source_color = vec4(1.0, 0.65, 0.2, 1.0);
uniform sampler2D noise_tex : hint_default_white;
uniform float progress : hint_range(0.0, 1.0) = 0.5;
uniform float intensity : hint_range(0.5, 5.0) = 2.5;

void fragment() {
	float trail_mask = smoothstep(0.0, 0.25, UV.x) * (1.0 - smoothstep(progress - 0.15, progress + 0.05, UV.x));
	float arc_fade = sin(UV.y * 3.14159);
	float streaks = texture(noise_tex, vec2(UV.x * 2.0 - TIME * 4.0, UV.y * 3.0)).r;
	float alpha = clamp(trail_mask * arc_fade * (0.4 + 0.6 * streaks), 0.0, 1.0);
	ALBEDO = slash_color.rgb * intensity;
	ALPHA = alpha * slash_color.a;
}
