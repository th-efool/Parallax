shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 base_tint : source_color = vec4(0.06, 0.14, 0.30, 0.72);
uniform vec4 rim_color : source_color = vec4(0.20, 0.75, 1.00, 1.00);
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rim_strength : hint_range(0.0, 5.0) = 2.4;
uniform float scanline_density : hint_range(10.0, 150.0) = 55.0;
uniform float scanline_speed = 3.0;
uniform sampler2D dissolve_noise : hint_default_white;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float n = texture(dissolve_noise, UV * 2.0).r;
	if (n < dissolve_amount) {
		discard;
	}
	float edge = smoothstep(dissolve_amount, dissolve_amount + 0.08, n);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float scan = 0.9 + 0.1 * sin(UV.y * scanline_density + TIME * scanline_speed);

	ALBEDO = base_tint.rgb * scan;
	EMISSION = rim_color.rgb * (fresnel * rim_strength + (1.0 - edge) * 3.0);
	ALPHA = clamp(base_tint.a + fresnel * 0.65, 0.0, 1.0);
}
