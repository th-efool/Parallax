shader_type canvas_item;

uniform float shift_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pulse_color : source_color = vec4(0.2, 0.78, 1.0, 1.0);
uniform float thickness = 0.12;

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);
	float ring = smoothstep(shift_progress - thickness, shift_progress, dist)
	           * (1.0 - smoothstep(shift_progress, shift_progress + thickness, dist));
	float fade = 1.0 - shift_progress;
	COLOR = vec4(pulse_color.rgb, ring * fade * 0.55);
}
