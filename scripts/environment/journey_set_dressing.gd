class_name JourneySetDressing
extends RefCounted
## Environmental set-dressing & storytelling pass for "The Ascent" (GrandJourneyBuilder).
##
## ART DIRECTION (derived from the level): the Ascent is a solar order's pilgrim fortress — sun emblems, red
## banners, fire braziers, marble greatswords — that ended as the Warden's execution ground. The two realms are
## two TIMES of the same place:
##   * REALITY  = the fortress now: abandoned after the purge. Sun-bleached, looted, wind-worn. Siege debris at
##                the gate, an overturned feast in the Hall, a dry aqueduct, a gutted clock workshop, wilted
##                offerings, scorch marks, tally marks scratched by prisoners, a lone grave at the summit.
##   * MIRROR   = the moon's memory of it at its height: things are whole, set, lit and *remembered*.
##                The feast table stands set with ghost candles, pilgrim lanterns drift along the old procession,
##                the aqueduct runs with moonlight, the clock's gears hang suspended mid-turn, every place where
##                someone died carries a glowing sigil, and a spectral knight keeps vigil at the summit grave.
## Shared geometry stays the anchor; dressing lives in each zone's RealityDressing / MirrorDressing groups
## (RealmReactive toggles them). Everything is cosmetic: no colliders except low wall-hugging clutter that
## sits outside every walk lane. Static pieces are merged by the builder's `_static_batch`; animated Mirror
## pieces (lanterns, gears, water) are excluded from batching.

const SPECTRAL_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform float energy = 1.6;
uniform float bob = 0.0;
uniform float rim_only = 0.6;
void vertex() {
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX.y += sin(TIME * 0.9 + o.x * 1.7 + o.z * 0.9) * bob;
}
void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float flick = 0.85 + 0.15 * sin(TIME * 3.0 + FRAGCOORD.y * 0.01);
	ALBEDO = color.rgb * energy * mix(1.0, rim + 0.15, rim_only) * flick;
}
"""

const WATER_FLOW_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(h(i), h(i+vec2(1,0)), f.x), mix(h(i+vec2(0,1)), h(i+vec2(1,1)), f.x), f.y); }
varying vec3 wp;
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float s = n(vec2(wp.x * 3.0, wp.z * 0.8 - TIME * 1.6)) * 0.6 + n(vec2(wp.x * 7.0, wp.z * 2.0 - TIME * 2.4)) * 0.4;
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = color.rgb * (0.35 + s * 1.4) * smoothstep(0.0, 0.35, edge);
}
"""

var b: Node   # GrandJourneyBuilder
var _rng := RandomNumberGenerator.new()
var _mats: Dictionary = {}
var _decal_tex: Dictionary = {}
var _glb_cache: Dictionary = {}
var _ghost_mat: ShaderMaterial = null


func _init(builder: Node) -> void:
	b = builder
	_rng.seed = 4242


func build() -> void:
	_dress_pilgrim_road()
	_dress_overlook_shrine()
	_dress_forecourt_siege()
	_dress_sunlit_stair()
	_dress_hall_feast()
	_dress_rampart_watch()
	_dress_aqueduct()
	_dress_clock_workshop()
	_dress_processional()
	_dress_colosseum()
	_dress_summit_grave()
	_flush_lanterns()


# =====================================================================================================
# Materials
# =====================================================================================================

func _std(key: String, c: Color, metal: float, rough: float, em: Color = Color.BLACK, em_e: float = 0.0) -> StandardMaterial3D:
	return b.call("_std", "sd_" + key, c, metal, rough, em, em_e) as StandardMaterial3D

func m_wood() -> StandardMaterial3D: return _grain("wood", Color(0.42, 0.28, 0.17))
func m_wood_old() -> StandardMaterial3D: return _grain("wood_old", Color(0.36, 0.3, 0.25))


## Wood with procedural grain: stretched noise texture in world triplanar (no UV dependency on primitives).
func _grain(key: String, tint: Color) -> StandardMaterial3D:
	if _mats.has("grain_" + key):
		return _mats["grain_" + key]
	var n := FastNoiseLite.new()
	n.seed = key.hash()
	n.frequency = 0.02
	n.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 0.55, 1.0])
	ramp.colors = PackedColorArray([tint * 0.55, tint * 0.95, tint * 1.1, tint * 0.7])
	tex.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.6, 6.0, 0.6)
	m.roughness = 0.9
	_mats["grain_" + key] = m
	return m
func m_iron() -> StandardMaterial3D: return _std("iron", Color(0.22, 0.21, 0.2), 0.85, 0.55)
func m_rust() -> StandardMaterial3D: return _std("rust", Color(0.36, 0.19, 0.1), 0.4, 0.8)
func m_bronze() -> StandardMaterial3D: return _std("bronze", Color(0.58, 0.4, 0.2), 0.9, 0.38)
func m_cloth_red() -> StandardMaterial3D: return _std("cloth_red", Color(0.42, 0.06, 0.05), 0.0, 0.9)
func m_cloth_faded() -> StandardMaterial3D: return _std("cloth_faded", Color(0.55, 0.42, 0.33), 0.0, 0.95)
func m_wax() -> StandardMaterial3D: return _std("wax", Color(0.88, 0.82, 0.66), 0.0, 0.55)
func m_flame() -> StandardMaterial3D: return _std("flame", Color(1, 0.6, 0.2), 0.0, 1.0, Color(1.0, 0.55, 0.15), 6.0)
func m_dead_flower() -> StandardMaterial3D: return _std("dead_flower", Color(0.33, 0.27, 0.16), 0.0, 1.0)
func m_flower() -> StandardMaterial3D: return _std("flower", Color(0.85, 0.75, 0.3), 0.0, 0.8)
func m_bone() -> StandardMaterial3D: return _std("bone", Color(0.8, 0.76, 0.66), 0.0, 0.7)
func m_stone() -> Material: return b.call("_m_ruin") as Material
func m_marble() -> Material: return b.call("_m_marble") as Material
func m_sand_stone() -> Material: return b.call("_m_wall") as Material


static var _spectral_shader: Shader = null


func spectral(color: Color, energy: float = 1.6, bob: float = 0.0, rim_only: float = 0.6) -> ShaderMaterial:
	var key: String = "%s|%.2f|%.2f|%.2f" % [color.to_html(), energy, bob, rim_only]
	if _mats.has(key):
		return _mats[key]
	if _spectral_shader == null:
		_spectral_shader = Shader.new()
		_spectral_shader.code = SPECTRAL_SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _spectral_shader
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("bob", bob)
	m.set_shader_parameter("rim_only", rim_only)
	_mats[key] = m
	return m

const MOON := Color(0.38, 0.66, 1.0)
const MOON_PALE := Color(0.7, 0.85, 1.0)


# =====================================================================================================
# Primitive helpers
# =====================================================================================================

func _mesh(g: Node3D, n: String, mesh: Mesh, mat: Material, xf: Transform3D, shadows: bool = false, vis: float = 70.0, batch: bool = true) -> MeshInstance3D:
	# Anything static placed directly in a zone group can be merged by the static batcher — only bobbing
	# (vertex-animated per object origin) or node-animated pieces (gear spinners) must stay separate.
	if not batch and mat != null and String(g.name) in ["Shared", "RealityDressing", "MirrorDressing"]:
		var bob: float = float((mat as ShaderMaterial).get_shader_parameter("bob")) if mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("bob") != null else 0.0
		batch = bob == 0.0
	return b.call("_mesh", g, n, mesh, mat, xf, shadows, vis, batch) as MeshInstance3D


func _box(sz: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = sz
	return m


func _cyl(r_top: float, r_bot: float, h: float, seg: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _sphere(r: float, seg: int = 10) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(4, seg / 2)
	return m


func _torus(r_in: float, r_out: float, rings: int = 16) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = r_in
	m.outer_radius = r_out
	m.rings = rings
	m.ring_segments = 6
	return m


func _yaw(deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(deg))


func _rock(size: Vector3, seed_val: int) -> ArrayMesh:
	return ProcMeshKit.rock_mesh(size, seed_val, 0.28, 6, 0.3)


## Loads a KayKit / MegaKit glb and places each of its meshes as builder meshes (so they batch).
func _glb(g: Node3D, path: String, xf: Transform3D, target_h: float, shadows: bool = false, vis: float = 70.0) -> void:
	if not ResourceLoader.exists(path):
		return
	if not _glb_cache.has(path):
		var inst: Node = (load(path) as PackedScene).instantiate()
		var parts: Array = []
		var aabb := AABB()
		var first: bool = true
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m3: MeshInstance3D = mi as MeshInstance3D
			if m3.mesh == null:
				continue
			var lx: Transform3D = Transform3D.IDENTITY
			var n: Node = m3
			while n != null and n != inst:
				if n is Node3D:
					lx = (n as Node3D).transform * lx
				n = n.get_parent()
			parts.append([m3.mesh, lx])
			var ab: AABB = lx * m3.mesh.get_aabb()
			aabb = ab if first else aabb.merge(ab)
			first = false
		inst.free()
		_glb_cache[path] = [parts, aabb]
	var entry: Array = _glb_cache[path]
	var aabb2: AABB = entry[1]
	var s: float = target_h / maxf(aabb2.size.y, 0.01)
	var base := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(-(aabb2.position.x + aabb2.size.x * 0.5) * s, -aabb2.position.y * s, -(aabb2.position.z + aabb2.size.z * 0.5) * s))
	for p in entry[0]:
		var mesh: Mesh = p[0]
		var single: bool = mesh.get_surface_count() == 1
		var mat: Material = mesh.surface_get_material(0) if single else null
		_mesh(g, "Prop_" + path.get_file().get_basename(), mesh, mat, xf * base * (p[1] as Transform3D), shadows, vis, single and mat != null)

const KK: String = "res://assets/models/dungeon/"
const MK: String = "res://assets/models/flora/megakit/"


# =====================================================================================================
# Decals (procedural textures, generated once)
# =====================================================================================================

func _decal_texture(kind: String) -> Texture2D:
	if _decal_tex.has(kind):
		return _decal_tex[kind]
	var size: int = 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = kind.hash()
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	for y in range(size):
		for x in range(size):
			var u: float = (float(x) / float(size) - 0.5) * 2.0
			var v: float = (float(y) / float(size) - 0.5) * 2.0
			var r: float = sqrt(u * u + v * v)
			var nz: float = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var c := Color(0, 0, 0, 0)
			match kind:
				"scorch":
					var a: float = clampf((1.0 - r) * 1.6 + (nz - 0.5) * 1.4, 0.0, 1.0)
					c = Color(0.03, 0.025, 0.02, a * 0.85)
				"blood":
					var a2: float = clampf((0.75 - r) * 2.5 + (nz - 0.5) * 2.2, 0.0, 1.0)
					c = Color(0.22, 0.02, 0.015, a2 * 0.8)
				"moss":
					var a3: float = clampf((1.0 - r) * 1.2 + (nz - 0.55) * 2.5, 0.0, 1.0)
					c = Color(0.16, 0.24, 0.08, a3 * 0.75)
				"grime":
					var a4: float = clampf((1.0 - r) * 0.9 + (nz - 0.5) * 1.5, 0.0, 1.0)
					c = Color(0.1, 0.08, 0.06, a4 * 0.55)
				"sigil":
					# Moon sigil: double ring + crescent + 8 ticks, emissive in the Mirror.
					var ring: float = maxf(1.0 - absf(r - 0.86) * 28.0, 0.0) + maxf(1.0 - absf(r - 0.7) * 40.0, 0.0) * 0.7
					var ang: float = atan2(v, u)
					var ticks: float = maxf(1.0 - absf(fmod(ang + TAU, TAU / 8.0) - TAU / 16.0) * 30.0, 0.0) * float(r > 0.72 and r < 0.84)
					var cres: float = float(sqrt(u * u + v * v) < 0.42 and sqrt((u - 0.16) * (u - 0.16) + (v + 0.05) * (v + 0.05)) > 0.36)
					var a5: float = clampf(ring + ticks + cres, 0.0, 1.0) * (0.75 + 0.25 * nz)
					c = Color(a5, a5, a5, a5)   # premultiplied so emission stays inside the sigil
				"tally":
					# Prisoners' tally marks: groups of 4 strokes + a slash, scratched into stone.
					var gx: float = fmod(float(x), 26.0)
					var stroke: float = float(gx < 18.0 and int(gx) % 4 == 0 and y > 30 and y < 98)
					var slash: float = float(absf((float(y) - 30.0) * 0.26 - gx) < 1.2 and y > 30 and y < 98)
					var line: float = float(int(float(x) / 26.0) < 4 + int(nz * 2.0))
					var at: float = clampf(stroke + slash, 0.0, 1.0) * line * (0.55 + 0.45 * nz)
					c = Color(0.85 * at, 0.82 * at, 0.75 * at, at)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_decal_tex[kind] = tex
	return tex


func _decal(g: Node3D, kind: String, pos: Vector3, size: Vector3, yaw: float = 0.0, normal_axis: Vector3 = Vector3.UP, emission: Color = Color.BLACK, energy: float = 0.0) -> Decal:
	var d := Decal.new()
	d.name = "Decal_" + kind
	d.texture_albedo = _decal_texture(kind)
	d.size = size
	d.cull_mask = 1   # world geometry only (not characters)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.distance_fade_enabled = true
	d.distance_fade_begin = 45.0
	d.distance_fade_length = 10.0
	if energy > 0.0:
		d.texture_emission = d.texture_albedo
		d.emission_energy = energy
		d.modulate = emission
	var basis := _yaw(yaw)
	if normal_axis != Vector3.UP:
		# Wall decal: the decal projects along its local -Y, so +Y = wall normal (pointing into the room).
		var ny: Vector3 = normal_axis.normalized()
		var nx: Vector3 = Vector3.UP.cross(ny).normalized()
		basis = Basis(nx, ny, nx.cross(ny))
	d.transform = Transform3D(basis, pos)
	g.add_child(d)
	return d


# =====================================================================================================
# Prop vocabulary
# =====================================================================================================

func candles(g: Node3D, center: Vector3, count: int, radius: float, ghost: bool, lit: bool = true) -> void:
	for i in range(count):
		var a: float = _rng.randf_range(0.0, TAU)
		var r: float = sqrt(_rng.randf()) * radius
		var h: float = _rng.randf_range(0.12, 0.42)
		var p: Vector3 = center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		if ghost:
			_mesh(g, "GhostCandle", _cyl(0.035, 0.04, h, 6), spectral(MOON_PALE, 0.7, 0.0, 0.3), Transform3D(Basis.IDENTITY, p + Vector3(0, h * 0.5, 0)), false, 60.0, false)
			_mesh(g, "GhostFlame", _sphere(0.035, 6), spectral(MOON, 4.0, 0.0, 0.0), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.8, 1)), p + Vector3(0, h + 0.05, 0)), false, 60.0, false)
		else:
			var tilt := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, 0.08)) if _rng.randf() < 0.5 else Basis.IDENTITY
			_mesh(g, "Candle", _cyl(0.035, 0.04, h, 6), m_wax(), Transform3D(tilt, p + Vector3(0, h * 0.5, 0)))
			# Wax pool around the base.
			_mesh(g, "WaxPool", _cyl(0.07, 0.09, 0.012, 8), m_wax(), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.006, 0)))
			if lit:
				_mesh(g, "CandleFlame", _sphere(0.025, 6), m_flame(), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.7, 1)), p + Vector3(0, h + 0.04, 0)), false, 50.0, false)


var _lanterns: Dictionary = {}   # group -> Array[Transform3D]

func lantern(g: Node3D, pos: Vector3, scale_k: float = 1.0) -> void:
	## Mirror pilgrim lantern: drifting (per-instance bob in the shader). Collected into one MultiMesh per zone.
	if not _lanterns.has(g):
		_lanterns[g] = []
	(_lanterns[g] as Array).append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_k), pos))


func _flush_lanterns() -> void:
	for g in _lanterns:
		var xf: Array = _lanterns[g]
		for part in [[_sphere(0.16, 8), spectral(MOON, 3.2, 0.25, 0.0), "SpiritLanterns"], [_sphere(0.42, 10), spectral(MOON, 0.5, 0.25, 0.9), "SpiritLanternHalos"]]:
			var mmi: MultiMeshInstance3D = b.call("_multimesh", g, part[2], part[0], part[1], xf, false) as MultiMeshInstance3D
			mmi.visibility_range_end = 160.0


func crate(g: Node3D, pos: Vector3, yaw: float, s: float = 0.85) -> void:
	var basis := _yaw(yaw)
	_mesh(g, "CrateBody", _box(Vector3(s, s, s) * 0.96), m_wood_old(), Transform3D(basis, pos + Vector3(0, s * 0.5, 0)), true)
	# Plank frame: edges + one diagonal brace per side.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mesh(g, "CrateEdge", _box(Vector3(0.07, s, 0.07)), m_wood(), Transform3D(basis, pos + basis * Vector3(sx * s * 0.47, s * 0.5, sz * s * 0.47)))
		_mesh(g, "CrateRim", _box(Vector3(s, 0.07, 0.07)), m_wood(), Transform3D(basis, pos + basis * Vector3(0, s * 0.97, sx * s * 0.47)))
		_mesh(g, "CrateBrace", _box(Vector3(s * 1.3, 0.06, 0.03)), m_wood(), Transform3D(basis * Basis(Vector3.FORWARD, deg_to_rad(45.0)), pos + basis * Vector3(0, s * 0.5, sx * s * 0.49)))


func crate_stack(g: Node3D, pos: Vector3, yaw: float, n: int) -> void:
	var stack: Array = [Vector3(0, 0, 0), Vector3(0.95, 0, 0.1), Vector3(0.45, 0.86, 0.05), Vector3(-0.2, 0, 0.92)]
	for i in range(mini(n, stack.size())):
		var off: Vector3 = _yaw(yaw) * (stack[i] as Vector3)
		crate(g, pos + off, yaw + _rng.randf_range(-12, 12))


func barrel(g: Node3D, pos: Vector3, tipped: bool = false, yaw: float = 0.0) -> void:
	var basis := _yaw(yaw)
	var h: float = 0.95
	if tipped:
		basis = basis * Basis(Vector3.RIGHT, deg_to_rad(90.0))
		pos += Vector3(0, 0.36, 0)
	else:
		pos += Vector3(0, h * 0.5, 0)
	# Bulged staves = two frustums back to back, iron hoops, lid.
	_mesh(g, "BarrelLower", _cyl(0.37, 0.31, h * 0.5, 14), m_wood(), Transform3D(basis, pos + basis * Vector3(0, -h * 0.25, 0)), true)
	_mesh(g, "BarrelUpper", _cyl(0.31, 0.37, h * 0.5, 14), m_wood(), Transform3D(basis, pos + basis * Vector3(0, h * 0.25, 0)), true)
	for hy in [-0.38, -0.12, 0.12, 0.38]:
		var r: float = lerpf(0.37, 0.315, absf(hy) / 0.5)
		_mesh(g, "BarrelHoop", _torus(r - 0.005, r + 0.02, 14), m_iron(), Transform3D(basis, pos + basis * Vector3(0, hy * h, 0)))
	_mesh(g, "BarrelLid", _cyl(0.3, 0.3, 0.02, 14), m_wood_old(), Transform3D(basis, pos + basis * Vector3(0, h * 0.5 - 0.02, 0)))


func rubble(g: Node3D, pos: Vector3, size: float, seed_val: int) -> void:
	_mesh(g, "Rubble", _rock(Vector3(size, size * 0.45, size * 0.8), seed_val), m_stone(), Transform3D(_yaw(_rng.randf_range(0, 360)), pos), true)
	for i in range(3):
		var p: Vector3 = pos + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * size * 0.9
		var s: float = size * _rng.randf_range(0.15, 0.3)
		_mesh(g, "RubbleChip", _rock(Vector3(s, s * 0.6, s), seed_val + i + 1), m_stone(), Transform3D(_yaw(_rng.randf_range(0, 360)), p))


func fallen_column(g: Node3D, pos: Vector3, yaw: float, length: float, radius: float) -> void:
	var col: ArrayMesh = ProcMeshKit.column_mesh(radius, length, 12)
	var basis := _yaw(yaw) * Basis(Vector3.FORWARD, deg_to_rad(90.0))
	_mesh(g, "FallenColumn", col, m_marble(), Transform3D(basis, pos + Vector3(0, radius * 0.92, 0) + _yaw(yaw) * Vector3(length * 0.5, 0, 0)), true)


func sword_stuck(g: Node3D, pos: Vector3, yaw: float, tilt_deg: float, rusty: bool = true) -> void:
	var basis := _yaw(yaw) * Basis(Vector3.RIGHT, deg_to_rad(tilt_deg))
	var mat: Material = m_rust() if rusty else m_iron()
	_mesh(g, "StuckBlade", _box(Vector3(0.07, 0.8, 0.015)), mat, Transform3D(basis, pos + basis * Vector3(0, 0.3, 0)))
	_mesh(g, "StuckGuard", _box(Vector3(0.26, 0.04, 0.05)), m_bronze(), Transform3D(basis, pos + basis * Vector3(0, 0.71, 0)))
	_mesh(g, "StuckGrip", _cyl(0.02, 0.022, 0.2, 6), m_wood_old(), Transform3D(basis, pos + basis * Vector3(0, 0.83, 0)))


func shield_down(g: Node3D, pos: Vector3, yaw: float, lean: float) -> void:
	var basis := _yaw(yaw) * Basis(Vector3.RIGHT, deg_to_rad(lean))
	_mesh(g, "ShieldDisc", _cyl(0.42, 0.42, 0.05, 14), m_wood(), Transform3D(basis, pos))
	_mesh(g, "ShieldRim", _torus(0.39, 0.45, 14), m_bronze(), Transform3D(basis, pos))
	_mesh(g, "ShieldBoss", _sphere(0.1, 8), m_bronze(), Transform3D(basis, pos + basis * Vector3(0, 0.04, 0)))


func spear(g: Node3D, pos: Vector3, dir: Vector3, length: float = 2.4) -> void:
	var up: Vector3 = dir.normalized()
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up)).orthonormalized()
	_mesh(g, "SpearShaft", _cyl(0.022, 0.025, length, 6), m_wood_old(), Transform3D(basis, pos + up * length * 0.5))
	_mesh(g, "SpearHead", _cyl(0.0, 0.045, 0.25, 4), m_rust(), Transform3D(basis, pos + up * (length + 0.12)))


func cairn(g: Node3D, pos: Vector3, seed_val: int, ghost: bool) -> void:
	var y: float = 0.0
	for i in range(4):
		var s: float = 0.32 - float(i) * 0.06
		var mat: Material = spectral(MOON_PALE, 1.1, 0.0, 0.5) if ghost else m_stone()
		_mesh(g, "CairnStone", _rock(Vector3(s, s * 0.55, s * 0.9), seed_val + i), mat, Transform3D(_yaw(_rng.randf_range(0, 360)), pos + Vector3(_rng.randf_range(-0.03, 0.03), y, 0)), false, 60.0, not ghost)
		y += s * 0.42


func wreath(g: Node3D, pos: Vector3, fresh: bool) -> void:
	var mat: Material = m_flower() if fresh else m_dead_flower()
	_mesh(g, "Wreath", _torus(0.16, 0.26, 12), mat, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-12, 12))), pos))


func long_table(g: Node3D, pos: Vector3, yaw: float, overturned: bool, length: float = 3.4) -> void:
	var basis := _yaw(yaw)
	if overturned:
		# On its side, top facing the room: a barricade someone hid behind.
		var side := basis * Basis(Vector3.RIGHT, deg_to_rad(-90.0))
		_mesh(g, "TableTop", _box(Vector3(length, 0.09, 0.95)), m_wood(), Transform3D(side, pos + Vector3(0, 0.48, 0)), true)
		for sx in [-1.0, 1.0]:
			_mesh(g, "TableLeg", _box(Vector3(0.1, 0.1, 0.72)), m_wood(), Transform3D(side, pos + basis * Vector3(sx * (length * 0.5 - 0.2), 0.5, -0.4)))
	else:
		_mesh(g, "TableTop", _box(Vector3(length, 0.09, 0.95)), m_wood(), Transform3D(basis, pos + Vector3(0, 0.76, 0)), true)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_mesh(g, "TableLeg", _box(Vector3(0.1, 0.72, 0.1)), m_wood(), Transform3D(basis, pos + basis * Vector3(sx * (length * 0.5 - 0.2), 0.36, sz * 0.36)))


func bench(g: Node3D, pos: Vector3, yaw: float, broken: bool) -> void:
	var basis := _yaw(yaw)
	if broken:
		basis = basis * Basis(Vector3.FORWARD, deg_to_rad(14.0))
	_mesh(g, "BenchSeat", _box(Vector3(2.2, 0.07, 0.36)), m_wood(), Transform3D(basis, pos + Vector3(0, 0.44 if not broken else 0.26, 0)))
	_mesh(g, "BenchLeg", _box(Vector3(0.08, 0.42, 0.3)), m_wood(), Transform3D(_yaw(yaw), pos + _yaw(yaw) * Vector3(-0.9, 0.21, 0)))
	if not broken:
		_mesh(g, "BenchLeg", _box(Vector3(0.08, 0.42, 0.3)), m_wood(), Transform3D(_yaw(yaw), pos + _yaw(yaw) * Vector3(0.9, 0.21, 0)))


func goblets(g: Node3D, center: Vector3, n: int, ghost: bool, spilled: bool) -> void:
	for i in range(n):
		var p: Vector3 = center + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-0.3, 0.3))
		var basis := Basis.IDENTITY
		if spilled and _rng.randf() < 0.6:
			basis = Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), deg_to_rad(90.0))
			p.y += 0.05
		var mat: Material = spectral(MOON_PALE, 1.2, 0.0, 0.4) if ghost else m_bronze()
		_mesh(g, "Goblet", _cyl(0.05, 0.025, 0.16, 8), mat, Transform3D(basis, p + Vector3(0, 0.08, 0)), false, 40.0, not ghost)


func chain(g: Node3D, a: Vector3, bpos: Vector3, mat: Material, sag: float = 0.3, batch: bool = true) -> void:
	var links: int = int(a.distance_to(bpos) / 0.11)
	for i in range(links):
		var t: float = float(i) / float(maxi(links - 1, 1))
		var p: Vector3 = a.lerp(bpos, t) + Vector3(0, -sin(t * PI) * sag, 0)
		var dir: Vector3 = (bpos - a).normalized()
		var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT) *Basis(Vector3.FORWARD, deg_to_rad(90.0 * float(i % 2)))
		_mesh(g, "ChainLink", _torus(0.025, 0.05, 8), mat, Transform3D(basis, p), false, 40.0, batch)


func execution_post(g_shared: Node3D, g_real: Node3D, g_mirror: Node3D, pos: Vector3, yaw: float) -> void:
	_mesh(g_shared, "ExecPost", _box(Vector3(0.28, 2.6, 0.28)), m_wood_old(), Transform3D(_yaw(yaw), pos + Vector3(0, 1.3, 0)), true)
	_mesh(g_shared, "ExecRing", _torus(0.08, 0.13, 10), m_iron(), Transform3D(_yaw(yaw) * Basis(Vector3.RIGHT, deg_to_rad(90)), pos + _yaw(yaw) * Vector3(0, 1.9, 0.16)))
	# Reality: rusted chains hanging slack to the sand, a dark stain at the foot.
	chain(g_real, pos + _yaw(yaw) * Vector3(0, 1.9, 0.18), pos + _yaw(yaw) * Vector3(0.35, 0.05, 0.55), m_rust(), 0.15)
	_decal(g_real, "blood", pos + _yaw(yaw) * Vector3(0, 0, 0.7), Vector3(1.8, 0.8, 1.8), _rng.randf_range(0, 360))
	# Mirror: chains of light, and the prisoner's sigil glowing where they knelt.
	chain(g_mirror, pos + _yaw(yaw) * Vector3(0, 1.9, 0.18), pos + _yaw(yaw) * Vector3(0, 0.6, 0.7), spectral(MOON, 2.2), 0.05, false)
	_decal(g_mirror, "sigil", pos + _yaw(yaw) * Vector3(0, 0, 0.8), Vector3(1.4, 0.8, 1.4), yaw, Vector3.UP, MOON, 3.0)


func ghost_figure(g: Node3D, pos: Vector3, yaw: float, height: float) -> void:
	var st: Node3D = b.call("_statue", g, pos, yaw, height, "Idle") as Node3D
	if st == null:
		return
	st.name = "SpectralKnight"
	b.call("_apply_override_recursive", st, spectral(MOON, 1.3, 0.0, 0.85))
	for mi in st.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func tattered_banner(g: Node3D, top: Vector3, yaw: float, w: float, l: float) -> void:
	## Reality: what is left of a sun banner — torn short, faded, on a bent rod.
	var basis := _yaw(yaw)
	_mesh(g, "TornBannerRod", _box(Vector3(w + 0.3, 0.07, 0.07)), m_rust(), Transform3D(basis * Basis(Vector3.FORWARD, deg_to_rad(4.0)), top))
	var strips: int = 3
	for i in range(strips):
		var sl: float = l * _rng.randf_range(0.35, 1.0)
		var x: float = (float(i) - float(strips - 1) * 0.5) * (w / float(strips))
		_mesh(g, "TornBannerStrip", _box(Vector3(w / float(strips) * 0.9, sl, 0.02)), m_cloth_red() if i != 1 else m_cloth_faded(), Transform3D(basis * Basis(Vector3.FORWARD, deg_to_rad(_rng.randf_range(-4, 4))), top + basis * Vector3(x, -sl * 0.5 - 0.05, 0)), false, 90.0)


func flower_tuft(g: Node3D, pos: Vector3, h: float = 0.5) -> void:
	_glb(g, MK + "flower_clumps.glb", Transform3D(_yaw(_rng.randf_range(0, 360)), pos), h)


func fern(g: Node3D, pos: Vector3, h: float = 0.7) -> void:
	_glb(g, MK + "fern_1.glb", Transform3D(_yaw(_rng.randf_range(0, 360)), pos), h)


func mushrooms(g: Node3D, pos: Vector3, h: float = 0.25) -> void:
	_glb(g, MK + "mushroom_common.glb", Transform3D(_yaw(_rng.randf_range(0, 360)), pos), h)


func zone(n: String) -> Array:
	return b.call("_zone", n)


# =====================================================================================================
# ZONES
# =====================================================================================================

## Prologue causeway: the pilgrim road. Reality = worn milestones, a pilgrim's broken handcart, cairns left by
## travellers. Mirror = the procession is still walking: a line of lanterns drifting just beyond the parapets.
func _dress_pilgrim_road() -> void:
	var g: Array = zone("Dress_PilgrimRoad")
	# Broken handcart against the start-terrace parapet (south-east corner, off the walk lane).
	var cp := Vector3(4.2, 0.0, -53.2)
	_mesh(g[1], "CartBed", _box(Vector3(1.6, 0.08, 0.9)), m_wood_old(), Transform3D(_yaw(-20) * Basis(Vector3.FORWARD, deg_to_rad(12)), cp + Vector3(0, 0.42, 0)), true)
	_mesh(g[1], "CartSide", _box(Vector3(1.6, 0.3, 0.05)), m_wood_old(), Transform3D(_yaw(-20) * Basis(Vector3.FORWARD, deg_to_rad(12)), cp + _yaw(-20) * Vector3(0, 0.58, 0.43)))
	_mesh(g[1], "CartWheel", _torus(0.3, 0.38, 14), m_wood(), Transform3D(_yaw(-20), cp + _yaw(-20) * Vector3(-0.4, 0.38, 0.5)))
	_mesh(g[1], "CartWheelFallen", _torus(0.3, 0.38, 14), m_wood(), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(88)), cp + Vector3(0.9, 0.04, -0.9)))
	barrel(g[1], cp + Vector3(-1.3, 0, 0.2), true, 30.0)
	crate_stack(g[1], Vector3(5.0, 0, -51.9), 8.0, 2)
	_mesh(g[1], "SpilledCloth", _box(Vector3(0.9, 0.02, 0.6)), m_cloth_faded(), Transform3D(_yaw(15), cp + Vector3(-0.4, 0.01, -0.9)))
	# Milestones along the causeways (on the parapet line, outer side).
	for mp in [Vector3(-6.3, 0, -46.0), Vector3(-6.3, 0, -38.5), Vector3(-6.3, 0, -25.5), Vector3(-6.3, 0, -18.0)]:
		_mesh(g[0], "Milestone", _rock(Vector3(0.45, 1.1, 0.4), int(mp.z * 3.0)), m_sand_stone(), Transform3D(_yaw(_rng.randf_range(-20, 20)), mp), true)
		cairn(g[1], mp + Vector3(0.0, 0.0, 0.8), int(mp.z), false)
		cairn(g[2], mp + Vector3(0.0, 0.0, 0.8), int(mp.z), true)
	# Mirror: the procession — lanterns floating beyond the east parapets, rising toward the gate.
	for i in range(14):
		var t: float = float(i) / 13.0
		var z: float = lerpf(-60.0, -8.0, t)
		var x: float = 3.6 + sin(t * 9.0) * 1.2 + (2.0 if z > -48.0 and z < -15.0 else 6.5)
		lantern(g[2], Vector3(x, 2.2 + sin(t * 5.0) * 0.6 + t * 1.5, z), 1.0)


## West overlook: a roadside shrine where pilgrims looked back over the valley.
## Reality = cracked stele, wilted wreath, burnt-down candles, a dropped satchel. Mirror = candles burning,
## fresh flowers, and the stele's moon rune lit.
func _dress_overlook_shrine() -> void:
	var g: Array = zone("Dress_OverlookShrine")
	var sp := Vector3(-9.7, 0.0, -33.0)
	_mesh(g[0], "ShrineStep", _box(Vector3(0.9, 0.18, 2.0)), m_marble(), Transform3D(Basis.IDENTITY, sp + Vector3(0, 0.09, 0)), true)
	_mesh(g[0], "ShrineStele", _box(Vector3(0.3, 1.5, 0.9)), m_sand_stone(), Transform3D(_yaw(0) * Basis(Vector3.FORWARD, deg_to_rad(-3)), sp + Vector3(-0.2, 0.93, 0)), true)
	_mesh(g[0], "ShrineDisc", _cyl(0.32, 0.32, 0.06, 18), m_bronze(), Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90)), sp + Vector3(-0.03, 1.25, 0)))
	_decal(g[1], "grime", sp + Vector3(0.2, 0.18, 0), Vector3(1.8, 0.6, 2.4))
	candles(g[1], sp + Vector3(0.25, 0.18, 0), 7, 0.6, false, false)
	wreath(g[1], sp + Vector3(0.3, 0.21, 0.55), false)
	_mesh(g[1], "Satchel", _box(Vector3(0.38, 0.22, 0.14)), m_wood_old(), Transform3D(_yaw(35) * Basis(Vector3.FORWARD, deg_to_rad(70)), sp + Vector3(1.1, 0.1, -0.7)))
	candles(g[2], sp + Vector3(0.25, 0.18, 0), 9, 0.65, true)
	wreath(g[2], sp + Vector3(0.3, 0.21, 0.55), true)
	_mesh(g[2], "ShrineRuneGlow", _cyl(0.24, 0.24, 0.02, 18), spectral(MOON, 3.0, 0.0, 0.0), Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90)), sp + Vector3(0.01, 1.25, 0)), false, 80.0, false)
	flower_tuft(g[0], sp + Vector3(0.0, 0.0, 1.3), 0.45)
	fern(g[0], sp + Vector3(-0.2, 0.0, -1.3), 0.6)


## Gate forecourt: the gatehouse was stormed. Reality = barricade of crates and a cart, discarded shields,
## spears and swords planted where defenders fell, scorch marks, a collapsed chunk of the gate tower.
## Mirror = the defenders' last stand, remembered: sigils where each one fell, banners whole.
func _dress_forecourt_siege() -> void:
	var g: Array = zone("Dress_ForecourtSiege")
	# Barricade (east edge, against the parapet — leaves the centre lane and phantom patrol free).
	crate_stack(g[1], Vector3(6.0, 0, -12.8), 85.0, 4)
	barrel(g[1], Vector3(5.8, 0, -10.6), false)
	barrel(g[1], Vector3(6.2, 0, -9.6), true, 70.0)
	long_table(g[1], Vector3(5.6, 0, -7.0), 90.0, true, 2.4)
	# Fallen defenders: weapons left where they fell.
	var falls: Array = [Vector3(-4.8, 0, -7.6), Vector3(-2.6, 0, -12.6), Vector3(2.9, 0, -13.9), Vector3(-5.6, 0, -11.0)]
	for i in range(falls.size()):
		var p: Vector3 = falls[i]
		if i % 2 == 0:
			sword_stuck(g[1], p, _rng.randf_range(0, 360), _rng.randf_range(8, 22))
		else:
			shield_down(g[1], p + Vector3(0, 0.03, 0), _rng.randf_range(0, 360), _rng.randf_range(0, 6))
		_decal(g[1], "scorch" if i % 2 == 0 else "blood", p, Vector3(1.6, 0.8, 1.6), _rng.randf_range(0, 360))
		_decal(g[2], "sigil", p, Vector3(1.1, 0.8, 1.1), _rng.randf_range(0, 360), Vector3.UP, MOON, 2.6)
	spear(g[1], Vector3(-6.4, 0, -14.3), Vector3(0.35, 1.0, 0.15))
	spear(g[1], Vector3(-6.0, 0, -14.6), Vector3(-0.2, 1.0, 0.3))
	# Collapsed gate-tower stones (west, by the brazier) + scorched gatehouse face.
	rubble(g[0], Vector3(-6.3, 0, -5.8), 1.4, 811)
	fallen_column(g[1], Vector3(-6.6, 0, -9.6), 75.0, 2.6, 0.35)
	_decal(g[1], "scorch", Vector3(-3.0, 3.5, 3.95), Vector3(4.0, 0.6, 4.0), 0.0, Vector3(0, 0, -1))
	_decal(g[0], "moss", Vector3(4.5, 0.02, -5.6), Vector3(3.0, 0.8, 2.0), 20.0)
	# Mirror: the gate whole — spectral sun-and-moon standard above the arch.
	_mesh(g[2], "GateStandardPole", _cyl(0.04, 0.04, 3.2, 6), spectral(MOON_PALE, 1.2, 0.0, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, 16.1, 4.5)), false, 150.0, false)
	_mesh(g[2], "GateStandardMoon", _torus(0.5, 0.62, 20), spectral(MOON, 2.8, 0.0, 0.0), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0, 17.4, 4.5)), false, 150.0, false)


## Sunlit stair: a ceremonial climb. Reality = petals long dried, a fallen marble finial on the landing,
## weeds in the treads. Mirror = votive candles burning along both sides of every flight.
func _dress_sunlit_stair() -> void:
	var g: Array = zone("Dress_SunlitStair")
	for i in range(7):
		var z: float = 9.0 + float(i) * 2.0
		var y: float = clampf((z - 7.2) / 15.0 * 4.0, 0.0, 4.0)
		for sx in [-1.0, 1.0]:
			var p := Vector3(sx * 3.55, y, z)
			candles(g[2], p, 2, 0.15, true)
			if (i + int(sx)) % 3 == 0:
				candles(g[1], p, 2, 0.12, false, false)
	# Fallen finial (a marble sphere-and-cap that once crowned the cheek wall) resting on the landing corner.
	_mesh(g[0], "FallenFinial", _sphere(0.42, 14), m_marble(), Transform3D(Basis.IDENTITY, Vector3(-3.3, 4.36, 22.9)), true)
	_mesh(g[0], "FinialCap", _cyl(0.2, 0.32, 0.3, 12), m_marble(), Transform3D(Basis(Vector3.FORWARD, deg_to_rad(80)), Vector3(-2.7, 4.17, 22.4)), true)
	_decal(g[0], "moss", Vector3(3.2, 2.4, 15.5), Vector3(1.6, 1.0, 4.0), 0.0)


## Hall of Echoes: the order's feast hall, where the purge began.
## Reality = long tables overturned into barricades, benches broken, goblets spilled, a chandelier crashed to
## the floor, tattered banners, grime. Mirror = the feast remembered: tables standing and set with ghost
## goblets and candles, the chandelier lit and hanging.
## The 20 x 20 combat floor stays clear: everything hugs the side arcades (|x| >= 8.2).
func _dress_hall_feast() -> void:
	var g: Array = zone("Dress_HallFeast")
	var y: float = 4.0
	for sx in [-1.0, 1.0]:
		var x: float = sx * 8.65
		# Reality: overturned tables + broken benches along the arcade.
		long_table(g[1], Vector3(x, y, 29.5), 90.0, true, 3.2)
		bench(g[1], Vector3(x - sx * 0.2, y, 34.6), 90.0 + sx * 8.0, true)
		long_table(g[1], Vector3(x, y, 39.0), 90.0 + sx * 6.0, sx > 0.0, 3.2)
		goblets(g[1], Vector3(x - sx * 0.9, y, 31.8), 3, false, true)
		_decal(g[1], "grime", Vector3(x, y, 34.0), Vector3(2.4, 0.8, 14.0))
		# Mirror: the same tables standing and set.
		long_table(g[2], Vector3(x, y, 29.5), 90.0, false, 3.2)
		long_table(g[2], Vector3(x, y, 39.0), 90.0, false, 3.2)
		goblets(g[2], Vector3(x, y + 0.8, 29.5), 4, true, false)
		goblets(g[2], Vector3(x, y + 0.8, 39.0), 4, true, false)
		candles(g[2], Vector3(x, y + 0.81, 29.5), 3, 0.3, true)
		candles(g[2], Vector3(x, y + 0.81, 39.0), 3, 0.3, true)
		bench(g[2], Vector3(x - sx * 0.85, y, 29.5), 90.0, false)
		bench(g[2], Vector3(x - sx * 0.85, y, 39.0), 90.0, false)
	# The crashed chandelier (Reality) near the south-west corner; hanging & lit in the Mirror.
	var cp := Vector3(-7.4, y, 25.9)
	_mesh(g[1], "ChandelierRingFallen", _torus(1.0, 1.12, 24), m_iron(), Transform3D(Basis(Vector3.FORWARD, deg_to_rad(9)), cp + Vector3(0, 0.12, 0)), true)
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		_mesh(g[1], "ChandelierCup", _cyl(0.06, 0.04, 0.08, 6), m_iron(), Transform3D(Basis.IDENTITY, cp + Vector3(cos(a), 0.05 + 0.15 * cos(a), sin(a)) * 1.06))
	chain(g[1], cp + Vector3(0.2, 0.1, 0.3), cp + Vector3(1.6, 0.03, 1.4), m_iron(), 0.0)
	_decal(g[1], "scorch", cp, Vector3(3.0, 0.8, 3.0))
	var hang := Vector3(0, y + 9.0, 34.0)
	_mesh(g[2], "ChandelierRing", _torus(1.6, 1.75, 32), spectral(MOON_PALE, 1.4, 0.0, 0.4), Transform3D(Basis.IDENTITY, hang), false, 90.0, false)
	for i in range(10):
		var a2: float = TAU * float(i) / 10.0
		_mesh(g[2], "ChandelierFlame", _sphere(0.07, 6), spectral(MOON, 4.0, 0.0, 0.0), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.7, 1)), hang + Vector3(cos(a2) * 1.67, 0.16, sin(a2) * 1.67)), false, 90.0, false)
	chain(g[2], hang + Vector3(0, 0.05, 0), Vector3(0, y + 15.5, 34.0), spectral(MOON_PALE, 1.0, 0.0, 0.3), 0.0, false)
	# Tattered sun banners on the north wall in Reality (the Mirror keeps the whole ones built by the stage).
	tattered_banner(g[1], Vector3(-8.0, y + 8.0, 43.5), 180.0, 1.6, 4.5)
	tattered_banner(g[1], Vector3(8.0, y + 8.0, 43.5), 180.0, 1.6, 4.0)
	# Forgotten corner: a rat-gnawed crate, mushrooms in the damp.
	crate_stack(g[1], Vector3(8.7, y, 42.6), 0.0, 1)
	mushrooms(g[0], Vector3(-9.2, y, 42.9))
	mushrooms(g[0], Vector3(9.3, y, 25.0))


## Windswept rampart: the watch post. Reality = abandoned arrow bundles, a toppled weapon rack, a sentry's
## cold brazier stand. Mirror = sentries' lanterns still hung on the curtain wall.
func _dress_rampart_watch() -> void:
	var g: Array = zone("Dress_Rampart")
	for z in [46.2, 50.4, 56.2]:
		var y: float = clampf(4.0 + (z - 48.0) / 10.0 * 2.0, 4.0, 6.0)
		var p := Vector3(2.55, y, z)
		# Arrow bundle leaning on the curtain wall.
		for k in range(7):
			var off := Vector3(_rng.randf_range(-0.08, 0.08), 0, _rng.randf_range(-0.12, 0.12))
			_mesh(g[1], "Arrow", _cyl(0.008, 0.008, 0.95, 4), m_wood(), Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-12.0 + _rng.randf_range(-4, 4))), p + off + Vector3(0, 0.48, 0)))
		_mesh(g[1], "ArrowTie", _torus(0.08, 0.11, 8), m_cloth_faded(), Transform3D(Basis.IDENTITY, p + Vector3(-0.06, 0.55, 0)))
		lantern(g[2], p + Vector3(0.5, 2.6, 0), 0.8)
	# Toppled weapon rack near the rampart top.
	var rp := Vector3(2.3, 6.0, 58.5)
	_mesh(g[1], "RackBeam", _box(Vector3(0.08, 0.08, 1.6)), m_wood_old(), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8)), rp + Vector3(0, 0.12, 0)))
	spear(g[1], rp + Vector3(-0.1, 0.02, -0.5), Vector3(-1.0, 0.08, 0.3), 2.0)
	spear(g[1], rp + Vector3(0.0, 0.02, 0.2), Vector3(-1.0, 0.05, -0.1), 2.0)
	_decal(g[0], "moss", Vector3(2.2, 5.0, 52.0), Vector3(1.6, 1.0, 5.0))


## Aqueduct gallery: water once ran in channels along the deck. Reality = a dry cracked channel choked with
## debris. Mirror = the channel flowing with moonlit water (animated, additive strip).
func _dress_aqueduct() -> void:
	var g: Array = zone("Dress_Aqueduct")
	var y: float = 6.0
	var flow := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WATER_FLOW_CODE
	flow.shader = sh
	for span in [[60.5, 69.6], [74.4, 83.6]]:
		for sx in [-1.0, 1.0]:
			var z0: float = span[0]
			var z1: float = span[1]
			var x: float = sx * 3.85
			var mid := Vector3(x, y + 0.012, (z0 + z1) * 0.5)
			_mesh(g[0], "ChannelLip", _box(Vector3(0.06, 0.12, z1 - z0)), m_sand_stone(), Transform3D(Basis.IDENTITY, mid + Vector3(-sx * 0.2, 0.05, 0)))
			_decal(g[1], "grime", mid, Vector3(0.45, 0.4, z1 - z0))
			for k in range(3):
				_mesh(g[1], "ChannelDebris", _rock(Vector3(0.18, 0.1, 0.16), int(z0 * 10.0) + k + int(sx * 3.0)), m_stone(), Transform3D(_yaw(_rng.randf_range(0, 360)), Vector3(x, y, _rng.randf_range(z0, z1))))
			var strip := PlaneMesh.new()
			strip.size = Vector2(0.34, z1 - z0)
			_mesh(g[2], "MoonWater", strip, flow, Transform3D(Basis.IDENTITY, mid + Vector3(0, 0.01, 0)), false, 60.0, false)
	# Reality: a toppled colonnade drum resting against the north balustrade.
	fallen_column(g[1], Vector3(2.75, y, 75.6), 270.0, 1.5, 0.3)
	mushrooms(g[0], Vector3(-3.4, y, 66.8), 0.2)


## Clock-tower chamber: the order's horologists' workshop.
## Reality = spare gears and tools heaped in the corners, a split workbench, spilled oil.
## Mirror = the great clockwork remembered: gears suspended in the air above the chamber, slowly turning.
func _dress_clock_workshop() -> void:
	var g: Array = zone("Dress_ClockWorkshop")
	var y: float = 6.0
	# Workbench in the south-east corner (roamer at (3.8, 91) patrols in front of it).
	var wp := Vector3(5.1, y, 89.2)
	long_table(g[0], wp, 0.0, false, 1.6)
	for i in range(3):
		var r: float = _rng.randf_range(0.18, 0.32)
		_mesh(g[1], "LooseGear", ProcMeshKit.gear_mesh(r, 0.05, 10, r * 0.3), m_bronze(), Transform3D(_yaw(_rng.randf_range(0, 360)), wp + Vector3(_rng.randf_range(-0.6, 0.6), 0.81 + 0.03 * float(i), _rng.randf_range(-0.25, 0.25))))
	_decal(g[1], "grime", wp + Vector3(0, 0, 0.8), Vector3(1.8, 0.8, 1.4))
	# Gear heap in the north-west corner, leaning against the wall.
	var hp := Vector3(-5.1, y, 98.9)
	for i in range(5):
		var r2: float = _rng.randf_range(0.35, 0.8)
		var lean := Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(55, 85))) * Basis(Vector3.UP, _rng.randf_range(0, TAU))
		_mesh(g[1], "HeapGear", ProcMeshKit.gear_mesh(r2, 0.09, 12, r2 * 0.25), m_rust(), Transform3D(_yaw(_rng.randf_range(-30, 30)) * lean, hp + Vector3(_rng.randf_range(-0.6, 0.6), r2 * 0.7, _rng.randf_range(-0.3, 0.3))), true)
	crate_stack(g[1], Vector3(-5.2, y, 89.3), 10.0, 2)
	# Mirror: suspended clockwork high in the shaft (above head height, never blocks the dais/plate puzzle).
	var turning: Array = []
	for i in range(7):
		var r3: float = _rng.randf_range(0.9, 2.2)
		var gp := Vector3(_rng.randf_range(-4.0, 4.0), y + 9.5 + float(i) * 1.7, 94.0 + _rng.randf_range(-4.0, 4.0))
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(60, 100)))
		var holder := Node3D.new()
		holder.name = "SuspendedGear"
		holder.position = gp
		holder.basis = _yaw(_rng.randf_range(0, 360)) * tilt
		g[2].add_child(holder)
		var spinner := Node3D.new()
		spinner.name = "Spinner"
		holder.add_child(spinner)
		_mesh(spinner, "Gear", ProcMeshKit.gear_mesh(r3, 0.16, 14 + i, r3 * 0.22), spectral(MOON_PALE, 1.3, 0.0, 0.55), Transform3D.IDENTITY, false, 120.0, false)
		turning.append([spinner, (1.0 if i % 2 == 0 else -1.0), _rng.randf_range(28.0, 70.0)])
	# Tween-driven rotation (one looping tween per gear, no per-frame script).
	for t in turning:
		var sp: Node3D = t[0]
		var tw := sp.create_tween().set_loops()
		tw.tween_property(sp, "rotation:y", TAU * float(t[1]), float(t[2])).from(0.0)


## Processional stair & esplanade: where crowds once came to watch. Reality = votive offerings at the
## monument plinths gone to dust, a trampled banner on the steps. Mirror = a field of ghost candles and
## lanterns lining the processional, the crowd's memory.
func _dress_processional() -> void:
	var g: Array = zone("Dress_Processional")
	for sx in [-1.0, 1.0]:
		var base := Vector3(sx * 6.7, 10.0, 118.4)
		candles(g[1], base, 6, 0.5, false, false)
		wreath(g[1], base + Vector3(sx * -0.4, 0.03, 0.3), false)
		flower_tuft(g[0], base + Vector3(0, 0, -1.1), 0.4)
		candles(g[2], base, 10, 0.7, true)
	_mesh(g[1], "TrampledBanner", _box(Vector3(1.2, 0.015, 2.2)), m_cloth_red(), Transform3D(_yaw(18) * Basis(Vector3.RIGHT, deg_to_rad(15)), Vector3(-4.6, 7.55, 106.5)))
	_decal(g[1], "grime", Vector3(-4.6, 7.6, 106.5), Vector3(1.8, 1.0, 2.8), 18.0)
	for i in range(8):
		var z: float = 102.5 + float(i) * 2.0
		var y: float = 6.0 + clampf((z - 101.3) / 15.0 * 4.0, 0.0, 4.0)
		for sx in [-1.0, 1.0]:
			lantern(g[2], Vector3(sx * 5.4, y + 2.2 + float(i % 2) * 0.4, z), 0.75)


## Mirror Colosseum: the execution ground.
## Reality = execution posts with slack rusted chains and stains, a heap of confiscated weapons by each tunnel
## mouth, broken spears in the sand, a toppled prisoner cage, tally marks scratched into the tunnel walls.
## Mirror = chains of light, a sigil glowing wherever someone knelt, and the tally marks shine.
func _dress_colosseum() -> void:
	var g: Array = zone("Dress_Colosseum")
	var c := Vector3(0, 10.0, 154.0)
	for deg in [52.0, 128.0, 232.0, 308.0]:
		var a: float = deg_to_rad(deg)
		var p: Vector3 = c + Vector3(sin(a), 0, cos(a)) * 12.6
		execution_post(g[0], g[1], g[2], p, rad_to_deg(a) + 180.0)
	# Confiscated weapons heaped beside both tunnel mouths (outside the arena ring, in the tunnels' side bays).
	for zc in [139.0, 169.0]:
		for sx in [-1.0, 1.0]:
			var hp := Vector3(sx * 2.45, 10.0, zc)
			for k in range(4):
				spear(g[1], hp + Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.3, 0.3)), Vector3(-sx * _rng.randf_range(0.2, 0.45), 1.0, _rng.randf_range(-0.3, 0.3)), 2.2)
			shield_down(g[1], hp + Vector3(-sx * 0.15, 0.45, 0), 90.0 * sx, 75.0)
	# Broken spears + bones scattered along the sand margin.
	for i in range(9):
		var a2: float = _rng.randf_range(0.0, TAU)
		if absf(cos(a2)) > 0.9:
			continue  # keep the tunnel axes clear
		var p2: Vector3 = c + Vector3(sin(a2), 0, cos(a2)) * _rng.randf_range(10.8, 12.4)
		spear(g[1], p2, Vector3(_rng.randf_range(-1, 1), 0.06, _rng.randf_range(-1, 1)), _rng.randf_range(0.8, 1.4))
		if i % 3 == 0:
			_mesh(g[1], "Bone", _cyl(0.025, 0.03, 0.4, 5), m_bone(), Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90)) * _yaw(_rng.randf_range(0, 360)), p2 + Vector3(0.3, 0.03, 0.2)))
	# Toppled prisoner cage against the podium wall (west).
	var cg: Vector3 = c + Vector3(-12.2, 0, 3.5)
	var cage_b := _yaw(20) * Basis(Vector3.FORWARD, deg_to_rad(80))
	for i in range(8):
		var a3: float = TAU * float(i) / 8.0
		_mesh(g[0], "CageBar", _cyl(0.025, 0.025, 1.8, 5), m_iron(), Transform3D(cage_b, cg + Vector3(0, 0.55, 0) + cage_b * Vector3(cos(a3) * 0.5, 0, sin(a3) * 0.5)))
	for ry in [-0.88, 0.88]:
		_mesh(g[0], "CageHoop", _torus(0.46, 0.54, 16), m_iron(), Transform3D(cage_b, cg + Vector3(0, 0.55, 0) + cage_b * Vector3(0, ry, 0)))
	# Tally marks in the south tunnel walls: prisoners counted days while waiting their turn.
	for z in [125.0, 129.5, 134.0]:
		for sx in [-1.0, 1.0]:
			_decal(g[1], "tally", Vector3(sx * 2.95, 11.2, z), Vector3(1.4, 0.4, 0.9), 0.0, Vector3(-sx, 0, 0))
			_decal(g[2], "tally", Vector3(sx * 2.95, 11.2, z), Vector3(1.4, 0.4, 0.9), 0.0, Vector3(-sx, 0, 0), MOON, 2.5)


## Sunset summit: the end of the pilgrimage. Reality = a lone grave of a fallen knight — helmet on a cairn,
## a wreath of fresh wildflowers (someone still visits). Mirror = the knight himself, spectral, keeping vigil
## and watching the sun he served go down.
func _dress_summit_grave() -> void:
	var g: Array = zone("Dress_SummitGrave")
	var gp := Vector3(-5.6, 10.0, 197.8)
	_mesh(g[0], "GraveMound", _rock(Vector3(1.0, 0.35, 1.8), 919), m_stone(), Transform3D(_yaw(-35), gp), true)
	sword_stuck(g[0], gp + Vector3(0.25, 0.25, -0.55), -35.0, 4.0, false)
	_mesh(g[1], "GraveHelm", _sphere(0.2, 12), m_iron(), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.1, 1)), gp + Vector3(-0.1, 0.42, 0.25)))
	_mesh(g[1], "GraveHelmCrest", _box(Vector3(0.03, 0.12, 0.3)), m_cloth_red(), Transform3D(Basis.IDENTITY, gp + Vector3(-0.1, 0.65, 0.25)))
	wreath(g[1], gp + Vector3(0.35, 0.3, 0.55), true)
	for k in range(5):
		flower_tuft(g[0], gp + Vector3(_rng.randf_range(-1.3, 1.3), 0, _rng.randf_range(-1.5, 1.5)), 0.4)
	ghost_figure(g[2], gp + Vector3(1.4, 0.0, -0.4), -115.0, 2.0)
	candles(g[2], gp + Vector3(0.4, 0.3, 0.3), 5, 0.4, true)
	_decal(g[2], "sigil", gp, Vector3(3.0, 0.8, 3.0), 0.0, Vector3.UP, MOON, 2.0)
