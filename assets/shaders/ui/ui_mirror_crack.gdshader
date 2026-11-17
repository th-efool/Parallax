shader_type canvas_item;
// Diagonal jagged "mirror crack" split: Reality amber tint one side, Mirror cyan the other.
// Put on a full-screen ColorRect (mouse_filter = Ignore). realm_mix slides the split / dominance.

uniform float realm_mix : hint_range(0.0, 1.0) = 0.5;   // 0 = all Reality, 1 = all Mirror
uniform float tint_strength : hint_range(0.0, 1.0) = 0.22;
uniform float glow_width : hint_range(0.002, 0.08) = 0.018;
uniform float crack_slant = 0.28;
uniform vec4 reality_color : source_color = vec4(0.90, 0.60, 0.22, 1.0);
uniform vec4 mirror_color : source_color = vec4(0.20, 0.71, 1.0, 1.0);

float hash(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}
float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec2 uv = UV;
	float aspect = 16.0 / 9.0;
	// Crack centre line x(y): slanted + jagged.
	float jag = (vnoise(uv.y * 14.0) - 0.5) * 0.05 + (vnoise(uv.y * 41.0 + 7.0) - 0.5) * 0.018;
	float cx = mix(0.78, 0.22, realm_mix) + (uv.y - 0.5) * crack_slant + jag;
	float d = uv.x - cx;

	vec3 col = mix(reality_color.rgb, mirror_color.rgb, step(0.0, d));
	float side_a = tint_strength * (d < 0.0 ? 0.8 : 1.0);
	// Fade tint toward far edges so the centre of the screen stays readable.
	float edge = smoothstep(0.0, 0.9, abs(d));
	float a = side_a * mix(0.25, 1.0, edge);

	// Glowing crack seam.
	float seam = exp(-abs(d) / glow_width);
	float flicker = 0.85 + 0.15 * sin(TIME * 2.3 + uv.y * 9.0);
	vec3 seam_col = mix(vec3(1.0, 0.95, 0.85), mirror_color.rgb, 0.45);
	vec3 outc = mix(col, seam_col, clamp(seam, 0.0, 1.0));
	a = max(a, seam * 0.9 * flicker);

	COLOR = vec4(outc, a);
}
