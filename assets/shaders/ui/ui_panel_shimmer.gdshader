shader_type canvas_item;
// Slow diagonal gold sheen that sweeps across a ColorRect/TextureRect (e.g. logo plate, rank letter).

uniform vec4 sheen_color : source_color = vec4(1.0, 0.92, 0.70, 1.0);
uniform float speed = 0.25;
uniform float band_width : hint_range(0.02, 0.5) = 0.12;
uniform float intensity : hint_range(0.0, 1.0) = 0.35;
uniform float pause_between = 1.6;

void fragment() {
	float cycle = 1.0 + pause_between;
	float t = fract(TIME * speed / cycle) * cycle;       // 0..cycle, sweep happens in 0..1
	float pos = t - 0.2 + (UV.y * 0.4);
	float x = UV.x - (pos);
	float band = smoothstep(band_width, 0.0, abs(x - 0.0));
	vec4 base = texture(TEXTURE, UV);
	float a = band * intensity * (t < 1.2 ? 1.0 : 0.0);
	COLOR = vec4(mix(base.rgb, sheen_color.rgb, a), max(base.a, a * 0.0 + base.a)) * COLOR;
}
