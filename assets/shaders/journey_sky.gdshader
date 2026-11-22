shader_type sky;

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
// Weather (driven per zone by WeatherDirector): storm overcast, blood-moon tint, lightning flash.
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
uniform vec4 storm_color : source_color = vec4(0.32, 0.33, 0.38, 1.0);
uniform float blood : hint_range(0.0, 1.0) = 0.0;
uniform vec4 blood_color : source_color = vec4(0.75, 0.05, 0.03, 1.0);
uniform float flash : hint_range(0.0, 4.0) = 0.0;
// Stylized day sky: 0 = photographic HDRI, 1 = painted gradient (horizon -> zenith + soft sun glow).
uniform float stylize : hint_range(0.0, 1.0) = 0.7;
uniform vec4 day_zenith : source_color = vec4(0.32, 0.52, 0.86, 1.0);
uniform vec4 day_horizon : source_color = vec4(1.0, 0.80, 0.58, 1.0);
uniform vec4 sun_tint : source_color = vec4(1.0, 0.85, 0.6, 1.0);

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

// --- Drifting cloud layer: a few sun-lit cumulus + high cirrus streaks on a curved sky plane.
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.3;
uniform vec2 cloud_wind = vec2(0.010, 0.004);
uniform vec4 cloud_lit : source_color = vec4(1.0, 0.86, 0.70, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.46, 0.44, 0.52, 1.0);

float cnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash13(vec3(i, 7.0));
	float b = hash13(vec3(i + vec2(1.0, 0.0), 7.0));
	float c = hash13(vec3(i + vec2(0.0, 1.0), 7.0));
	float e = hash13(vec3(i + vec2(1.0, 1.0), 7.0));
	return mix(mix(a, b, u.x), mix(c, e, u.x), u.y);
}

float cfbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= oct) break;
		v += cnoise(p) * a;
		p = p * 2.02 + vec2(11.3, 4.7);
		a *= 0.5;
	}
	return v;
}

// Returns rgb = cloud colour, a = coverage alpha.
vec4 sky_clouds(vec3 d, vec3 s, bool cubemap_pass) {
	if (d.y <= 0.005) return vec4(0.0);
	vec2 uv = d.xz / (d.y + 0.12);
	float t = TIME;
	float cov = mix(cloud_coverage, 0.85, overcast);
	// Cumulus: large shapes, eroded edges, slow drift; evolve over time so shapes keep changing.
	vec2 cp = uv * 1.1 + t * cloud_wind;
	int oct = cubemap_pass ? 3 : 5;
	float shape = cfbm(cp + vec2(0.0, t * 0.003), oct);
	float thr = 1.0 - cov;
	float dens = smoothstep(thr * 0.62, thr * 0.62 + 0.22, shape);
	// Self-shadow: sample toward the sun -> thinner side facing the sun gets lit.
	vec2 sun_uv = normalize(s.xz + vec2(1e-4)) * 0.06;
	float toward = cfbm(cp + sun_uv, oct);
	float lit = clamp(0.55 + (shape - toward) * 6.0, 0.0, 1.0);
	float sd = max(dot(d, s), 0.0);
	vec3 col = mix(cloud_shade.rgb, cloud_lit.rgb * 1.5, lit);
	// Silver lining around the sun and on thin edges.
	col += cloud_lit.rgb * pow(sd, 12.0) * (1.0 - dens) * 3.0;
	// High cirrus streaks.
	float ci = cfbm(vec2(uv.x * 0.35 + t * cloud_wind.x * 2.5, uv.y * 2.2), cubemap_pass ? 2 : 4);
	float cirrus = smoothstep(0.55, 0.85, ci) * 0.35 * (1.0 - overcast);
	float a = max(dens, cirrus);
	// Fade toward the horizon (distance haze) and very overhead stretching.
	a *= smoothstep(0.0, 0.18, d.y);
	col = mix(cloud_lit.rgb * 1.2 + pow(sd, 6.0) * 0.6, col, dens / max(a, 1e-3));
	return vec4(col, clamp(a, 0.0, 1.0));
}

vec3 day_sky(vec3 d) {
	float lon = atan(d.x, -d.z) + sky_rotation;
	vec2 uv = vec2(lon / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	uv.x = fract(uv.x);
	vec3 photo = texture(hdri, uv).rgb;
	vec3 grad = mix(day_horizon.rgb, day_zenith.rgb, smoothstep(-0.02, 0.6, d.y));
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	grad += sun_tint.rgb * (pow(sd, 6.0) * 0.6 + pow(sd, 200.0) * 6.0);
	grad *= mix(0.55, 1.0, smoothstep(-0.3, 0.0, d.y));
	return mix(photo, grad, stylize) * exposure;
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
	vec3 col = mix(day, night, mirror_blend);
	{
		vec4 cl = sky_clouds(d, normalize(sun_dir), AT_CUBEMAP_PASS);
		// Mirror: moonlit indigo clouds rim-lit by the moon.
		vec3 ccol = mix(cl.rgb, vec3(0.16, 0.22, 0.42) * (0.6 + 0.8 * cl.rgb.r), mirror_blend);
		col = mix(col, ccol, cl.a * 0.92);
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	// Storm: desaturate + darken toward a heavy grey deck, with rolling cloud bands near the horizon.
	float band = noise2(vec2(atan(d.x, d.z) * 4.0 + TIME * 0.02, d.y * 9.0));
	vec3 storm = storm_color.rgb * (0.35 + 0.65 * smoothstep(-0.1, 0.5, d.y)) * (0.75 + 0.5 * band);
	col = mix(col, storm * (0.6 + luma * 0.4), overcast);
	// Blood moon: crimson wash, darker zenith, glowing red horizon and a bleeding moon/sun disc.
	vec3 s = normalize(sun_dir);
	float sd = max(dot(d, s), 0.0);
	vec3 bloodsky = blood_color.rgb * (0.25 + 0.9 * (1.0 - smoothstep(-0.05, 0.6, d.y)));
	bloodsky += vec3(1.0, 0.15, 0.08) * pow(sd, 400.0) * 18.0 + blood_color.rgb * pow(sd, 8.0) * 1.2;
	bloodsky *= 0.75 + 0.5 * band;
	col = mix(col, bloodsky + luma * blood_color.rgb * 0.3, blood);
	// Lightning: brief sheet flash, brightest toward the horizon.
	col += vec3(0.75, 0.82, 1.0) * flash * (0.4 + 0.6 * (1.0 - clamp(d.y, 0.0, 1.0)));
	COLOR = col;
}
