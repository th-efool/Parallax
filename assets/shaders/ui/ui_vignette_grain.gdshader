shader_type canvas_item;
// Full-screen vignette + film grain + drifting ember/dust motes. Overlay on top of menus.

uniform float vignette : hint_range(0.0, 1.0) = 0.65;
uniform float grain : hint_range(0.0, 0.2) = 0.05;
uniform float motes : hint_range(0.0, 1.0) = 0.6;
uniform vec4 mote_color : source_color = vec4(1.0, 0.72, 0.38, 1.0);

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float d = distance(uv, vec2(0.5)) * 1.35;
	float v = smoothstep(0.35, 1.05, d) * vignette;
	vec3 col = vec3(0.0);
	float a = v;

	// Grain (animated at ~24 fps).
	float g = h21(uv * 900.0 + floor(TIME * 24.0)) - 0.5;
	col += vec3(g) * grain;
	a += abs(g) * grain * 2.0;

	// Rising motes in 3 parallax layers.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float scale = 14.0 + fi * 9.0;
		vec2 p = uv * vec2(scale * 1.78, scale);
		p.y += TIME * (0.25 + fi * 0.18);
		p.x += sin(TIME * 0.4 + fi * 3.0 + floor(p.y)) * 0.3;
		vec2 id = floor(p);
		vec2 f = fract(p) - 0.5;
		float rnd = h21(id + fi * 17.0);
		float live = step(0.93, rnd);
		float size = 0.05 + rnd * 0.05;
		float m = live * smoothstep(size, 0.0, length(f - (vec2(h21(id + 3.1), h21(id + 7.7)) - 0.5) * 0.5));
		float tw = 0.6 + 0.4 * sin(TIME * (1.0 + rnd * 3.0) + rnd * 20.0);
		col += mote_color.rgb * m * tw * motes;
		a += m * tw * motes * 0.8;
	}
	COLOR = vec4(col, clamp(a, 0.0, 1.0));
}
