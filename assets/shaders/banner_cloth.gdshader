shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

// Hanging heraldic banner with vertex wind sway (pinned at the top edge) and a procedural emblem:
// emblem_kind 0 = radiant sun (Reality), 1 = crescent moon (Mirror).

uniform vec4 cloth_color : source_color = vec4(0.55, 0.06, 0.05, 1.0);
uniform vec4 trim_color : source_color = vec4(0.85, 0.62, 0.22, 1.0);
uniform int emblem_kind = 0;
uniform float wind_strength = 0.18;
uniform float wind_speed = 1.6;
uniform float emblem_glow = 0.0;

void vertex() {
	// UV.y: 0 at top (pinned) -> 1 at bottom (free).
	float free = UV.y * UV.y;
	float phase = TIME * wind_speed + NODE_POSITION_WORLD.x * 0.37 + NODE_POSITION_WORLD.z * 0.21;
	VERTEX.z += sin(phase + UV.y * 3.2) * wind_strength * free;
	VERTEX.x += sin(phase * 0.7 + UV.y * 2.1) * wind_strength * 0.35 * free;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = cloth_color.rgb;
	// Gold trim borders + swallow-tail darkening near the bottom
	float border = step(uv.x, 0.06) + step(0.94, uv.x) + step(uv.y, 0.04);
	col = mix(col, trim_color.rgb, clamp(border, 0.0, 1.0));
	vec2 c = vec2(0.5, 0.36);
	vec2 q = (uv - c) * vec2(1.0, 0.55);
	float r = length(q);
	float emblem = 0.0;
	if (emblem_kind == 0) {
		float disc = 1.0 - smoothstep(0.085, 0.095, r);
		float ang = atan(q.y, q.x);
		float rays = step(0.5, fract(ang * 12.0 / 6.2831853)) * (1.0 - smoothstep(0.12, 0.17, r)) * step(0.1, r);
		emblem = max(disc, rays);
	} else {
		float outer = 1.0 - smoothstep(0.12, 0.13, r);
		float inner = 1.0 - smoothstep(0.10, 0.11, length(q - vec2(0.045, -0.02)));
		emblem = clamp(outer - inner, 0.0, 1.0);
	}
	col = mix(col, trim_color.rgb, emblem);
	// Fabric weave
	float weave = 0.92 + 0.08 * sin(uv.x * 900.0) * sin(uv.y * 1400.0);
	ALBEDO = col * weave;
	ROUGHNESS = 0.85;
	SSS_STRENGTH = 0.4;
	BACKLIGHT = cloth_color.rgb * 0.6;
	EMISSION = trim_color.rgb * emblem * emblem_glow;
}
