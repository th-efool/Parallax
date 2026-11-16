shader_type sky;
render_mode use_half_res_pass;

// Realm-reactive sky (Grand Journey).
// Reality: Poly Haven "Kloppenheim 06 (Pure Sky)" golden-hour HDRI, rotated so its sun matches the scene sun.
// Mirror:  procedural cobalt night - gradient, star field, aurora veils and a huge moon where the sun was.
// `mirror_blend` is a material uniform (not the global) so changing it re-renders the radiance cubemap.

uniform sampler2D hdri : filter_linear, repeat_enable;
uniform float sky_rotation = 0.0;        // radians added to longitude
uniform float exposure = 1.0;
uniform float mirror_blend : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_dir = vec3(-0.7, 0.3, 0.7);
uniform vec4 night_zenith : source_color = vec4(0.035, 0.06, 0.15, 1.0);
uniform vec4 night_horizon : source_color = vec4(0.17, 0.27, 0.56, 1.0);
uniform vec4 moon_color : source_color = vec4(0.75, 0.88, 1.0, 1.0);
uniform vec4 aurora_color : source_color = vec4(0.15, 0.55, 1.0, 1.0);
uniform float moon_size = 0.035;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash13(vec3(i, 1.0));
	float b = hash13(vec3(i + vec2(1.0, 0.0), 1.0));
	float c = hash13(vec3(i + vec2(0.0, 1.0), 1.0));
	float d = hash13(vec3(i + vec2(1.0, 1.0), 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec3 day_sky(vec3 d) {
	float lon = atan(d.x, -d.z) + sky_rotation;
	vec2 uv = vec2(lon / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	uv.x = fract(uv.x);
	return texture(hdri, uv).rgb * exposure;
}

vec3 night_sky(vec3 d, bool cubemap_pass) {
	float h = clamp(d.y, -0.2, 1.0);
	vec3 col = mix(night_horizon.rgb, night_zenith.rgb, smoothstep(-0.05, 0.65, h));
	vec3 s = normalize(sun_dir);
	float md = dot(d, s);
	// Moon disc + halo
	float disc = smoothstep(cos(moon_size) - 0.0006, cos(moon_size), md);
	float crater = 0.85 + 0.15 * noise2(d.xy * 180.0);
	col += moon_color.rgb * disc * 6.0 * crater;
	col += moon_color.rgb * pow(max(md, 0.0), 64.0) * 0.6 + aurora_color.rgb * pow(max(md, 0.0), 6.0) * 0.12;
	if (!cubemap_pass) {
		// Stars (skipped for the radiance pass: they are sub-texel there anyway)
		vec3 sd = d * 420.0;
		float star = hash13(floor(sd));
		float tw = 0.6 + 0.4 * sin(TIME * 2.0 + star * 50.0);
		col += vec3(0.8, 0.9, 1.0) * step(0.9975, star) * tw * smoothstep(0.0, 0.25, d.y) * 2.5;
	}
	// Aurora veils
	float band = noise2(vec2(atan(d.x, d.z) * 3.0, TIME * 0.03)) * noise2(vec2(atan(d.x, d.z) * 9.0 + TIME * 0.05, 3.0));
	float veil = smoothstep(0.08, 0.35, d.y) * (1.0 - smoothstep(0.35, 0.8, d.y));
	col += aurora_color.rgb * band * veil * 0.9;
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 day = mirror_blend < 0.999 ? day_sky(d) : vec3(0.0);
	vec3 night = mirror_blend > 0.001 ? night_sky(d, AT_CUBEMAP_PASS) : vec3(0.0);
	COLOR = mix(day, night, mirror_blend);
}
