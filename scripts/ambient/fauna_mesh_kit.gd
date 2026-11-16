class_name FaunaMeshKit
extends RefCounted
## Procedural low-poly bodies + textures for ambient life, styled to sit next to the KayKit rigs
## (flat-ish shading, chunky silhouettes, warm Reality / cool Mirror palettes). No asset files needed.

static var _cache: Dictionary = {}


static func clear_caches() -> void:
	_cache.clear()


static func mat(color: Color, emissive: float = 0.0, unshaded: bool = false, alpha: bool = false) -> StandardMaterial3D:
	var key: String = "m_%s_%.2f_%s_%s" % [color.to_html(), emissive, str(unshaded), str(alpha)]
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha or color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = emissive
	_cache[key] = m
	return m


static func sphere(radius: float, segs: int = 8, rings: int = 5) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO, part_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if not part_name.is_empty():
		mi.name = part_name
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3, pivot_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = pivot_name
	n.position = pos
	parent.add_child(n)
	return n


## Soft radial glow sprite (wisp halo, firefly, spores).
static func glow_texture() -> Texture2D:
	if _cache.has("glow_tex"):
		return _cache["glow_tex"] as Texture2D
	var sz: int = 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in range(sz):
		for x in range(sz):
			var d: float = Vector2(x + 0.5 - sz * 0.5, y + 0.5 - sz * 0.5).length() / (sz * 0.5)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var tex := ImageTexture.create_from_image(img)
	_cache["glow_tex"] = tex
	return tex


static func glow_billboard(color: Color, size: float, energy: float = 2.0) -> QuadMesh:
	var key: String = "gb_%s_%.2f_%.2f" % [color.to_html(), size, energy]
	if _cache.has(key):
		return _cache[key] as QuadMesh
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = glow_texture()
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	m.no_depth_test = false
	q.material = m
	_cache[key] = q
	return q


## Wing texture: rounded fore+hind wing silhouette, vein lines, eye-spot, edge band. Unique per seed.
static func wing_texture(base: Color, accent: Color, seed_value: int) -> Texture2D:
	var key: String = "wing_%s_%s_%d" % [base.to_html(), accent.to_html(), seed_value % 6]
	if _cache.has(key):
		return _cache[key] as Texture2D
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sz: int = 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var spot := Vector2(rng.randf_range(0.55, 0.7), rng.randf_range(0.25, 0.4))
	for y in range(sz):
		for x in range(sz):
			var u: float = (x + 0.5) / sz  # 0 = body edge, 1 = wing tip
			var v: float = (y + 0.5) / sz  # 0 = front, 1 = back
			# Forewing (upper lobe) + hindwing (lower lobe) as two ellipses
			var fw: float = pow((u - 0.45) / 0.55, 2.0) + pow((v - 0.3) / 0.3, 2.0)
			var hw: float = pow((u - 0.3) / 0.38, 2.0) + pow((v - 0.72) / 0.27, 2.0)
			var inside: float = minf(fw, hw)
			if inside > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var c: Color = base.lerp(accent, clampf(u * 0.9, 0.0, 1.0))
			if inside > 0.72:
				c = c.darkened(0.55)  # edge band
			var sd: float = Vector2(u, v).distance_to(spot)
			if sd < 0.09:
				c = Color(1, 1, 1) if sd < 0.035 else accent.lightened(0.3)
			var vein: float = absf(sin(atan2(v - 0.5, u) * 7.0))
			if vein < 0.08 and inside < 0.8:
				c = c.darkened(0.35)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func wing_mesh(size: float, tex: Texture2D, emissive: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.center_offset = Vector3(size * 0.5, 0.0, 0.0)  # hinge on the body edge
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.6
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission_texture = tex
		m.emission = Color.WHITE
		m.emission_energy_multiplier = emissive
	q.material = m
	return q


## Blade tuft for grass: N crossed tapered triangles, vertex colour dark root -> light tip.
static func grass_tuft_mesh(blades: int, height: float, spread: float, root: Color, tip: Color, seed_value: int) -> ArrayMesh:
	var key: String = "grass_%d_%.2f_%d" % [blades, height, seed_value % 8]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(blades):
		var ang: float = rng.randf_range(0.0, TAU)
		var base_off := Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(0.0, spread)
		var h: float = height * rng.randf_range(0.6, 1.15)
		var w: float = 0.035 * rng.randf_range(0.8, 1.3)
		var face: float = rng.randf_range(0.0, TAU)
		var side := Vector3(cos(face), 0.0, sin(face)) * w
		var lean := Vector3(cos(ang), 0.0, sin(ang)) * h * rng.randf_range(0.1, 0.35)
		var a: Vector3 = base_off - side
		var b: Vector3 = base_off + side
		var t: Vector3 = base_off + lean + Vector3.UP * h
		st.set_color(root)
		st.set_uv(Vector2(0, 1))
		st.add_vertex(a)
		st.set_color(root)
		st.set_uv(Vector2(1, 1))
		st.add_vertex(b)
		st.set_color(tip)
		st.set_uv(Vector2(0.5, 0))
		st.add_vertex(t)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


static func grass_material() -> ShaderMaterial:
	if _cache.has("grass_mat"):
		return _cache["grass_mat"] as ShaderMaterial
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.6;
instance uniform vec3 push = vec3(0.0); // per-tuft bend away from passing actors
varying vec3 v_col;
void vertex() {
	float h = clamp(VERTEX.y / 0.5, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * wind_speed + wp.x * 0.7 + wp.z * 0.5) * 0.6 + sin(TIME * wind_speed * 2.3 + wp.z * 1.3) * 0.4;
	VERTEX.x += (w * wind_strength + push.x) * h * h;
	VERTEX.z += (w * wind_strength * 0.6 + push.z) * h * h;
	VERTEX.y -= length(push.xz) * 0.35 * h * h;
	v_col = COLOR.rgb;
}
void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_cache["grass_mat"] = m
	return m


## Petal: flattened, tapered sphere.
static func petal_mesh() -> SphereMesh:
	if _cache.has("petal"):
		return _cache["petal"] as SphereMesh
	var s := sphere(0.5, 8, 4)
	_cache["petal"] = s
	return s


static func cone(top: float, bottom: float, height: float, segs: int = 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p
