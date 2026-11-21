shader_type canvas_item;
// Title-screen backdrop: a ruined colosseum on the horizon, split by a glowing mirror seam.
// Left of the seam = Reality (amber dusk, sun); right = Mirror (cobalt night, moon, stars).
// Everything below the horizon is a still-water reflection. Fully procedural, no textures.

uniform float seam : hint_range(0.0, 1.0) = 0.68;      // seam x position (UV); tween it for the Q glimpse
uniform float horizon : hint_range(0.3, 0.9) = 0.66;   // horizon y (UV, from top)
uniform float menu_shade : hint_range(0.0, 1.0) = 0.62; // darkens the left side so menu text stays readable
uniform float intro : hint_range(0.0, 1.0) = 1.0;      // 0 = black, 1 = full scene

// Integer hash: sin()-based hashes break at cell borders (FMA rounding), which shows up as hard blocks.
float hash2(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p + 0.5)) + ivec2(32768));
	uint h = (q.x * 1597334673u) ^ (q.y * 3812015801u);
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = h ^ (h >> 13u);
	return float(h) * (1.0 / 4294967295.0);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// 1 = stone, 0 = open sky. p.x in aspect units, p.y = height above the horizon.
float colosseum(vec2 p, float aspect) {
	float cx = aspect * 0.70;
	float hw = aspect * 0.36;
	float dx = (p.x - cx) / hw;
	if (abs(dx) >= 1.0 || p.y < -0.01) {
		return 0.0;
	}
	float prof = sqrt(max(0.0, 1.0 - dx * dx));
	float top = 0.05 + 0.19 * prof;
	// The right flank has collapsed.
	float broken = smoothstep(0.05, 0.9, dx) * (0.07 + 0.07 * noise(vec2(p.x * 26.0, 3.0)));
	top -= broken;
	float solid = smoothstep(top + 0.0015, top - 0.0015, p.y);

	// Three tiers of arches wrapped around the curved wall.
	float tier_h = 0.058;
	float ty = p.y / tier_h;
	float tier = floor(ty);
	float fy = fract(ty);
	float ang = asin(clamp(dx, -0.999, 0.999));
	float fu = fract(ang * 8.0 + tier * 0.5);
	float ax = abs(fu - 0.5) * 2.0;
	float ow = 0.52;
	float r = ax / ow;
	float arch_y = 0.56 + 0.26 * sqrt(max(0.0, 1.0 - r * r));
	float hole = step(ax, ow) * step(0.12, fy) * step(fy, arch_y) * step(tier, 2.5);
	hole *= step((tier + 0.85) * tier_h, top);
	return solid * (1.0 - hole);
}

// Distant ridge behind the arena.
float ridge(vec2 p) {
	float h = 0.035 + 0.07 * fbm(vec2(p.x * 2.2, 0.5)) - 0.02;
	return step(p.y, h) * step(-0.01, p.y);
}

vec3 sky(vec2 p, float aspect, float m, float t) {
	float hn = clamp(p.y / 0.66, 0.0, 1.0);
	vec3 r_top = vec3(0.075, 0.040, 0.032);
	vec3 r_mid = vec3(0.42, 0.17, 0.08);
	vec3 r_hor = vec3(0.96, 0.56, 0.24);
	vec3 m_top = vec3(0.008, 0.014, 0.040);
	vec3 m_mid = vec3(0.035, 0.080, 0.20);
	vec3 m_hor = vec3(0.16, 0.36, 0.66);
	vec3 rc = mix(r_hor, r_mid, smoothstep(0.0, 0.35, hn));
	rc = mix(rc, r_top, smoothstep(0.30, 1.0, hn));
	vec3 mc = mix(m_hor, m_mid, smoothstep(0.0, 0.30, hn));
	mc = mix(mc, m_top, smoothstep(0.25, 1.0, hn));

	// Long drifting cloud bands.
	float cl = fbm(vec2(p.x * 1.6 + t * 0.012, p.y * 7.0));
	float band = smoothstep(0.52, 0.78, cl) * smoothstep(0.02, 0.12, p.y) * (1.0 - smoothstep(0.35, 0.6, p.y));
	rc = mix(rc, vec3(0.55, 0.24, 0.12), band * 0.55);
	mc = mix(mc, vec3(0.10, 0.17, 0.32), band * 0.6);

	// Sun (Reality) and moon (Mirror).
	vec2 sun = vec2(aspect * 0.40, 0.085);
	float ds = length(p - sun);
	rc += vec3(1.0, 0.72, 0.38) * (smoothstep(0.050, 0.044, ds) * 0.9 + exp(-ds * 9.0) * 0.55);
	vec2 moon = vec2(aspect * 0.86, 0.36);
	float dm = length(p - moon);
	float crescent = smoothstep(0.034, 0.030, dm) * smoothstep(0.024, 0.030, length(p - moon - vec2(0.012, 0.008)));
	mc += vec3(0.80, 0.90, 1.0) * crescent + vec3(0.35, 0.55, 0.95) * exp(-dm * 10.0) * 0.35;

	// Stars on the Mirror side.
	vec2 sp = p * 90.0;
	vec2 cell = floor(sp);
	float rnd = hash2(cell);
	vec2 star_pos = vec2(hash2(cell + 17.0), hash2(cell + 41.0)) * 0.7 + 0.15;
	float star_r = 0.05 + 0.09 * hash2(cell + 5.0);
	float st = step(0.94, rnd) * smoothstep(star_r, star_r * 0.2, length(fract(sp) - star_pos)) * smoothstep(0.06, 0.3, p.y);
	float tw = 0.55 + 0.45 * sin(t * 2.0 + hash2(cell + 3.0) * 30.0);
	mc += vec3(0.75, 0.85, 1.0) * st * tw;

	return mix(rc, mc, m);
}

vec3 scene(vec2 p, float aspect, float m, float t) {
	vec3 col = sky(p, aspect, m, t);
	vec3 ridge_col = mix(vec3(0.24, 0.11, 0.07), vec3(0.04, 0.08, 0.17), m);
	col = mix(col, ridge_col, ridge(p));
	float stone = colosseum(p, aspect);
	vec3 stone_col = mix(vec3(0.085, 0.040, 0.030), vec3(0.016, 0.026, 0.060), m);
	// Rim light on the upper edge of the wall.
	float rim = stone * (1.0 - colosseum(p + vec2(0.0, 0.004), aspect));
	stone_col += mix(vec3(0.75, 0.38, 0.14), vec3(0.25, 0.55, 1.0), m) * rim * 0.8;
	col = mix(col, stone_col, stone);
	// Haze sitting on the horizon.
	col += mix(vec3(0.55, 0.30, 0.15), vec3(0.10, 0.22, 0.45), m) * exp(-abs(p.y) * 28.0) * 0.35;
	return col;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv = UV;
	float t = TIME;

	// Jagged seam: two octaves of noise, very slowly breathing.
	float sx = seam
		+ 0.030 * (noise(vec2(uv.y * 7.0, 3.0 + t * 0.05)) - 0.5)
		+ 0.010 * (noise(vec2(uv.y * 38.0, 7.0)) - 0.5);
	float d = (uv.x - sx) * aspect;
	float m = smoothstep(-0.0015, 0.0015, d);

	vec2 p = vec2(uv.x * aspect, horizon - uv.y);
	vec3 col;
	if (p.y >= 0.0) {
		col = scene(p, aspect, m, t);
	} else {
		// Still water: ripple-distorted reflection.
		float depth = -p.y;
		vec2 q = vec2(p.x + 0.006 * sin(depth * 260.0 - t * 1.6) * smoothstep(0.0, 0.2, depth), depth * 1.15);
		vec3 refl = scene(q, aspect, m, t);
		vec3 water = mix(vec3(0.05, 0.025, 0.02), vec3(0.008, 0.016, 0.04), m);
		col = mix(water, refl * 0.55, exp(-depth * 4.0));
		// Glints.
		float glint = step(0.93, noise(vec2(p.x * 60.0, depth * 180.0 + t * 0.6))) * exp(-depth * 6.0);
		col += mix(vec3(1.0, 0.62, 0.30), vec3(0.45, 0.70, 1.0), m) * glint * 0.35;
	}

	// The seam itself: white-hot core, amber on one side, cyan on the other.
	float core = exp(-abs(d) * 900.0);
	float glow = exp(-abs(d) * 90.0);
	col += vec3(1.0, 0.96, 0.88) * core * 0.9;
	col += mix(vec3(1.0, 0.55, 0.20), vec3(0.25, 0.70, 1.0), m) * glow * 0.45;

	// Keep the menu column readable.
	float shade = smoothstep(0.62, 0.0, uv.x) * menu_shade;
	col *= 1.0 - shade;

	COLOR = vec4(col * intro, 1.0);
}
