class_name JourneyTerrain
extends RefCounted
## Continuous procedural landscape for the Grand Journey (replaces the old cloud-sea + isolated crag spires).
## The route rides the crest of a mountain ridge: every rock massif under the walkways sinks into ridge
## shoulders that fall into forested valleys, a river canyon (under the gatehouse gap), a dry gorge (under
## the aqueduct), and a big sunset lake to the west. Rolling mountains ring the valley (kept low on the
## sunset side so the vista stays open). Cosmetic only: no collision. The world kill plane still catches falls.
##
## Height contract: along the route band (|x - route_x| <= half_width) the ground is >= 5 m below the floor
## top, so nothing ever pokes into gameplay space.

const TERRAIN_SHADER: String = "res://assets/shaders/journey_terrain.gdshader"
const WATER_SHADER: String = "res://assets/shaders/journey_water.gdshader"
const PBR_DIR: String = "res://assets/textures/pbr/"
const PINE_MODELS: Array[String] = ["res://assets/models/flora/megakit/pine_1.glb", "res://assets/models/flora/megakit/pine_3.glb", "res://assets/models/flora/megakit/pine_5.glb"]
const BROADLEAF_MODELS: Array[String] = ["res://assets/models/flora/megakit/tree_common_1.glb", "res://assets/models/flora/megakit/tree_common_2.glb"]

const WATER_Y: float = -52.0
## World z extent of the route (JourneyLayout, 2026-11-18 rework: terrace z -141 .. summit z 362).
const Z_MIN: float = -144.0
const Z_MAX: float = 370.0
const ROUTE_CENTER := Vector2(0.0, 113.0)

var sun_heading := Vector2(-0.65, 0.76)
var _xc := PackedFloat32Array()
var _yr := PackedFloat32Array()
var _hw := PackedFloat32Array()
var _n_low := FastNoiseLite.new()
var _n_mtn := FastNoiseLite.new()
var _n_det := FastNoiseLite.new()
var _n_forest := FastNoiseLite.new()


func _init(waypoints: Array, sun: Vector3) -> void:
	sun_heading = Vector2(sun.x, sun.z).normalized()
	_n_low.seed = 11
	_n_low.frequency = 0.0035
	_n_low.fractal_octaves = 3
	_n_mtn.seed = 23
	_n_mtn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_mtn.frequency = 0.0019
	_n_mtn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_mtn.fractal_octaves = 5
	_n_mtn.fractal_gain = 0.5
	_n_det.seed = 37
	_n_det.frequency = 0.03
	_n_det.fractal_octaves = 3
	_n_forest.seed = 51
	_n_forest.frequency = 0.012
	_n_forest.fractal_octaves = 2
	_build_route_table(waypoints)


# ---------------------------------------------------------------- Route band

func _half_width(z: float) -> float:
	# World z bands (JourneyLayout). The band centre follows the waypoints, so on the winding bridges it swings
	# with the deck; 14 m covers the deck plus a bastion and its drum.
	var hw: float = 9.5
	if z > -144.0 and z < -130.0:
		hw = 9.0   # start terrace
	if z >= -130.0 and z < -15.0:
		hw = 14.0  # R1 causeway bridges + bastions
	if z > -16.0 and z < 9.0:
		hw = 13.0  # forecourt + gatehouse (piers to x +-11)
	if z >= 9.0 and z < 54.0:
		hw = 14.0  # R2 bridges + bastions
	if z >= 54.0 and z < 120.0:
		hw = 36.0  # 60 m hall + corner towers
	if z >= 120.0 and z < 161.0:
		hw = 14.0  # R3 rampart bridges
	if z >= 189.0 and z < 230.0:
		hw = 22.0  # 36 m clock tower
	if z >= 230.0 and z < 276.0:
		hw = 14.0  # R5 processional bridges
	if z >= 276.0 and z < 281.0:
		hw = 15.0  # esplanade
	if z >= 281.0 and z < 348.0:
		hw = 38.0  # colosseum facade + portal towers
	if z >= 348.0:
		hw = 13.0
	return hw


func _build_route_table(waypoints: Array) -> void:
	var pts: Array = []
	for w in waypoints:
		var p: Vector3 = w[0]
		if p.z > 301.0 and p.z < 327.0:
			continue   # arena ring detour: keep the centre line at x 0
		pts.append(p)
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	var n: int = int(Z_MAX - Z_MIN) + 1
	_xc.resize(n)
	_yr.resize(n)
	_hw.resize(n)
	for i in range(n):
		var z: float = Z_MIN + float(i)
		var x: float = (pts[0] as Vector3).x
		var y: float = (pts[0] as Vector3).y
		if z >= (pts[pts.size() - 1] as Vector3).z:
			x = (pts[pts.size() - 1] as Vector3).x
			y = (pts[pts.size() - 1] as Vector3).y
		else:
			for k in range(pts.size() - 1):
				var a: Vector3 = pts[k]
				var b: Vector3 = pts[k + 1]
				if z >= a.z and z <= b.z:
					var t: float = 0.0 if b.z - a.z < 0.001 else (z - a.z) / (b.z - a.z)
					x = lerpf(a.x, b.x, t)
					y = minf(a.y, b.y) if b.z - a.z < 0.001 else lerpf(a.y, b.y, t)
					break
		_xc[i] = x
		# The band takes the LOWEST floor within +-6 m so stair feet / lower decks are respected.
		_yr[i] = y
		_hw[i] = _half_width(z)
	var lo := _yr.duplicate()
	for i in range(n):
		var m: float = _yr[i]
		for k in range(maxi(0, i - 6), mini(n, i + 7)):
			m = minf(m, _yr[k])
		lo[i] = m
	_yr = lo


func _route_at(z: float) -> Vector3:
	var f: float = clampf(z - Z_MIN, 0.0, Z_MAX - Z_MIN)
	var i: int = mini(int(f), _xc.size() - 2)
	var t: float = f - float(i)
	return Vector3(lerpf(_xc[i], _xc[i + 1], t), lerpf(_yr[i], _yr[i + 1], t), lerpf(_hw[i], _hw[i + 1], t))


## Horizontal distance from the supported route band (0 inside it) and the band's floor height.
func route_distance(x: float, z: float) -> Vector2:
	var r: Vector3 = _route_at(z)
	var dz: float = maxf(maxf(Z_MIN - z, z - Z_MAX), 0.0)
	var dx: float = maxf(absf(x - r.x) - r.z, 0.0)
	return Vector2(sqrt(dx * dx + dz * dz), r.y)


# ---------------------------------------------------------------- Height field

static func _smax(a: float, b: float, k: float) -> float:
	var h: float = clampf(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
	return lerpf(b, a, h) + k * h * (1.0 - h)


static func _smin(a: float, b: float, k: float) -> float:
	return -_smax(-a, -b, k)


func height(x: float, z: float) -> float:
	var rd: Vector2 = route_distance(x, z)
	var d: float = rd.x
	var yr: float = rd.y
	# Ridge crest carrying the route: steep cliff-like shoulders that ease into long slopes.
	var ridge: float = yr - 3.5 - 28.0 * (1.0 - exp(-d / 15.0)) - 0.2 * d
	ridge += _n_det.get_noise_2d(x, z) * 7.0 * smoothstep(6.0, 45.0, d)
	# Valley floor with gentle undulation.
	var valley: float = -58.0 + 9.0 * _n_low.get_noise_2d(x, z)
	# Ring of mountains: ridged noise, faded in with distance and flattened on the sunset side.
	var off := Vector2(x, z) - ROUTE_CENTER
	var sunness: float = off.normalized().dot(sun_heading) if off.length() > 1.0 else 0.0
	var mtn_scale: float = lerpf(1.0, 0.16, smoothstep(0.15, 0.7, sunness))
	var ridged: float = clampf(_n_mtn.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var far: float = smoothstep(110.0, 620.0, d)
	var rolling: float = _n_low.get_noise_2d(z * 0.5, x * 0.5) * 0.5 + 0.5
	var land: float = valley + far * mtn_scale * (40.0 + 300.0 * (ridged * ridged * 0.55 + rolling * 0.45) * (0.7 + 0.3 * ridged))
	land += _n_det.get_noise_2d(x * 0.35, z * 0.35) * 10.0 * far
	var h: float = _smax(ridge, land, 24.0)
	# Sunset lake basin (west / north-west, mirror-calm water under the sun).
	var lake_c: Vector2 = ROUTE_CENTER + sun_heading * 470.0
	var ld: float = (Vector2(x, z) - lake_c).length() / 330.0
	h = lerpf(h, minf(h, -66.0 + 6.0 * _n_low.get_noise_2d(x * 2.0, z * 2.0)), 1.0 - smoothstep(0.55, 1.0, ld))
	# River canyon under the gatehouse chasm (z ~1): flows from the eastern peaks into the lake.
	var src: float = smoothstep(380.0, 700.0, d) * 220.0 if x > 0.0 else 0.0
	var river: float = -60.0 + maxf(absf(z - 1.0 - 6.0 * sin(x * 0.02)) - 4.0, 0.0) * 1.9 + src
	h = _smin(h, river, 6.0)
	# Dry gorge under the aqueduct (world z ~178): arches stand in it; descends outward to the valley.
	var gorge: float = -38.0 - 0.14 * d + maxf(absf(z - 178.0 - 4.0 * sin(x * 0.03)) - 8.0, 0.0) * 1.35
	h = _smin(h, gorge, 5.0)
	# Hard guarantee: never enter the route band's gameplay space.
	if d < 1.0:
		h = minf(h, yr - 3.5)
	return h


func slope_normal(x: float, z: float, e: float = 2.0) -> Vector3:
	var hx: float = height(x + e, z) - height(x - e, z)
	var hz: float = height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


# ---------------------------------------------------------------- Mesh building

func _grid_mesh(x0: float, z0: float, size_x: float, size_z: float, cells: int, sink_rect: Rect2 = Rect2(), heights_cache: Dictionary = {}) -> ArrayMesh:
	var n: int = cells + 1
	var dx: float = size_x / float(cells)
	var dz: float = size_z / float(cells)
	# One cell of margin so normals are continuous across chunk seams.
	var hs := PackedFloat32Array()
	hs.resize((n + 2) * (n + 2))
	for j in range(n + 2):
		for i in range(n + 2):
			var x: float = x0 + float(i - 1) * dx
			var z: float = z0 + float(j - 1) * dz
			var key := Vector2i(int(round(x * 4.0)), int(round(z * 4.0)))
			var h: float
			if heights_cache.has(key):
				h = heights_cache[key]
			else:
				h = height(x, z)
				heights_cache[key] = h
			if sink_rect.size.x > 0.0:
				# Far LOD shell: tuck under the detailed tile (fully sunk 30 m inside its border).
				var inside: float = minf(minf(x - sink_rect.position.x, sink_rect.end.x - x), minf(z - sink_rect.position.y, sink_rect.end.y - z))
				h -= smoothstep(0.0, 30.0, inside) * 14.0
			hs[j * (n + 2) + i] = h
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in range(n):
		for i in range(n):
			var c: int = (j + 1) * (n + 2) + (i + 1)
			verts[j * n + i] = Vector3(x0 + float(i) * dx, hs[c], z0 + float(j) * dz)
			var hx: float = hs[c + 1] - hs[c - 1]
			var hz: float = hs[c + (n + 2)] - hs[c - (n + 2)]
			norms[j * n + i] = Vector3(-hx * dz, 2.0 * dx * dz, -hz * dx).normalized()
	idx.resize(cells * cells * 6)
	var k: int = 0
	for j in range(cells):
		for i in range(cells):
			var a: int = j * n + i
			var b: int = a + 1
			var c2: int = a + n
			var d2: int = c2 + 1
			# Alternate the diagonal to avoid directional banding.
			if (i + j) % 2 == 0:
				idx[k] = a; idx[k + 1] = b; idx[k + 2] = d2
				idx[k + 3] = a; idx[k + 4] = d2; idx[k + 5] = c2
			else:
				idx[k] = a; idx[k + 1] = b; idx[k + 2] = c2
				idx[k + 3] = b; idx[k + 4] = d2; idx[k + 5] = c2
			k += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


func _pbr_set(m: ShaderMaterial, prefix: String, id: String) -> void:
	var base: String = PBR_DIR + id + "/" + id
	if ResourceLoader.exists(base + "_diff_2k.jpg"):
		m.set_shader_parameter(prefix + "_albedo", load(base + "_diff_2k.jpg"))
		m.set_shader_parameter(prefix + "_normal", load(base + "_nor_gl_2k.jpg"))


func make_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(TERRAIN_SHADER) as Shader
	_pbr_set(m, "rock", "rock_face")
	_pbr_set(m, "ground", "coast_sand_rocks_02")
	return m


## Builds terrain chunks, water, and forests under `parent`. `lod_fn` adds mesh LODs (builder's _with_lods).
func build(parent: Node3D, lod_fn: Callable) -> void:
	var mat: ShaderMaterial = make_material()
	var root := Node3D.new()
	root.name = "Terrain"
	parent.add_child(root)
	# Detailed tile: 720 x 760 m around the route, 4 x 4 chunks of 60 x 60 cells (3 m / 3.2 m).
	var near := Rect2(-360.0, -270.0, 720.0, 760.0)
	var cache: Dictionary = {}
	var chunks: int = 4
	for cj in range(chunks):
		for ci in range(chunks):
			var sx: float = near.size.x / float(chunks)
			var sz: float = near.size.y / float(chunks)
			var mesh: ArrayMesh = _grid_mesh(near.position.x + sx * float(ci), near.position.y + sz * float(cj), sx, sz, 60, Rect2(), cache)
			var mi := MeshInstance3D.new()
			mi.name = "TerrainChunk_%d_%d" % [ci, cj]
			mi.mesh = lod_fn.call(mesh) if lod_fn.is_valid() else mesh
			mi.material_override = mat
			# Only the ridge-adjacent chunks cast shadows (shadow distance is 140 m anyway).
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (ci == 1 or ci == 2) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
	# Mid ring: 2.4 x 2.4 km at 12 m (sunk under the detailed tile), then the far shell: 7 x 7 km at 35 m.
	var mid := Rect2(-1200.0, -1130.0, 2400.0, 2400.0)
	for mj in range(2):
		for mi2 in range(2):
			var mid_mesh: ArrayMesh = _grid_mesh(mid.position.x + 1200.0 * float(mi2), mid.position.y + 1200.0 * float(mj), 1200.0, 1200.0, 100, near.grow(-2.0))
			var mid_mi := MeshInstance3D.new()
			mid_mi.name = "TerrainMid_%d_%d" % [mi2, mj]
			mid_mi.mesh = lod_fn.call(mid_mesh) if lod_fn.is_valid() else mid_mesh
			mid_mi.material_override = mat
			mid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mid_mi)
	var far_mesh: ArrayMesh = _grid_mesh(-3500.0, -3430.0, 7000.0, 7000.0, 200, mid.grow(-2.0))
	var far_mi := MeshInstance3D.new()
	far_mi.name = "TerrainFar"
	far_mi.mesh = far_mesh
	far_mi.material_override = mat
	far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(far_mi)
	# Water: one plane fills the lake, river and low valley pools.
	var water := PlaneMesh.new()
	water.size = Vector2(6000.0, 6000.0)
	water.subdivide_width = 0
	var wm := ShaderMaterial.new()
	wm.shader = load(WATER_SHADER) as Shader
	var wmi := MeshInstance3D.new()
	wmi.name = "Water"
	wmi.mesh = water
	wmi.material_override = wm
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wmi.position = Vector3(0.0, WATER_Y, 70.0)
	root.add_child(wmi)
	_build_forest(root)


# ---------------------------------------------------------------- Forest

func _model_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return null
	var inst: Node = ps.instantiate()
	var found: Mesh = null
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		found = (mi as MeshInstance3D).mesh
		if found != null:
			break
	if inst is MeshInstance3D and found == null:
		found = (inst as MeshInstance3D).mesh
	inst.free()
	return found


## Cheap 3-tier cone pine for distant forest (≈ 70 tris), vertex-coloured.
static func _far_pine() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int = 7
	var tiers: Array = [[0.25, 2.2, 1.0], [0.45, 1.75, 0.92], [0.66, 1.25, 0.85]]
	for t in tiers:
		var y0: float = float(t[0]) * 10.0 - 1.6
		var r: float = float(t[1])
		var top: float = y0 + 4.4
		var col := Color(0.16, 0.27, 0.15) * float(t[2])
		for s in range(sides):
			var a0: float = TAU * float(s) / float(sides)
			var a1: float = TAU * float(s + 1) / float(sides)
			var p0 := Vector3(sin(a0) * r, y0, cos(a0) * r)
			var p1 := Vector3(sin(a1) * r, y0, cos(a1) * r)
			var apex := Vector3(0, top, 0)
			var nrm: Vector3 = (p1 - p0).cross(apex - p0).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			st.set_color(col * 0.8)
			st.set_normal(nrm)
			st.add_vertex(p0)
			st.set_color(col * 1.25)
			st.add_vertex(apex)
			st.set_color(col * 0.8)
			st.add_vertex(p1)
	# trunk stub
	st.set_color(Color(0.22, 0.15, 0.1))
	st.set_normal(Vector3.FORWARD)
	st.add_vertex(Vector3(-0.25, -1.0, 0))
	st.add_vertex(Vector3(0.25, -1.0, 0))
	st.add_vertex(Vector3(0, 1.4, 0))
	return st.commit()


func _build_forest(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var near_meshes: Array[Mesh] = []
	for p in PINE_MODELS:
		var m: Mesh = _model_mesh(p)
		if m != null:
			near_meshes.append(m)
	var leaf_meshes: Array[Mesh] = []
	for p in BROADLEAF_MODELS:
		var m2: Mesh = _model_mesh(p)
		if m2 != null:
			leaf_meshes.append(m2)
	var far_mesh: ArrayMesh = _far_pine()
	var far_mat := StandardMaterial3D.new()
	far_mat.vertex_color_use_as_albedo = true
	far_mat.roughness = 0.95
	var cell: float = 70.0
	var cells: Dictionary = {}   # Vector2i -> {"near": [[mesh_idx, xform]], "far": [xform]}
	var placed: int = 0
	var tries: int = 0
	while placed < 6000 and tries < 45000:
		tries += 1
		var x: float = rng.randf_range(-1100.0, 1100.0)
		var z: float = rng.randf_range(-1030.0, 1170.0)
		var rd: Vector2 = route_distance(x, z)
		if rd.x < 16.0:
			continue
		var f: float = _n_forest.get_noise_2d(x, z) * 0.5 + 0.5
		if f < 0.5 - 0.08 * (1.0 - smoothstep(0.0, 400.0, rd.x)):
			continue
		var h: float = height(x, z)
		if h < WATER_Y + 1.5 or h > 190.0:
			continue
		var nrm: Vector3 = slope_normal(x, z, 3.0)
		if nrm.y < 0.83:
			continue
		var s: float = rng.randf_range(1.6, 2.6) * lerpf(1.0, 0.7, smoothstep(60.0, 190.0, h))
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
		var pos := Vector3(x, h - 0.4, z)
		var key := Vector2i(int(floor(x / cell)), int(floor(z / cell)))
		if not cells.has(key):
			cells[key] = {"near": [], "far": []}
		var entry: Dictionary = cells[key]
		var use_leaf: bool = not leaf_meshes.is_empty() and h < -30.0 and rng.randf() < 0.55
		if rd.x < 190.0 and (not near_meshes.is_empty()):
			var mi: int = rng.randi_range(0, (leaf_meshes.size() if use_leaf else near_meshes.size()) - 1)
			(entry["near"] as Array).append([("L" if use_leaf else "P") + str(mi), Transform3D(basis, pos)])
		(entry["far"] as Array).append(Transform3D(basis.scaled(Vector3(0.85, 0.85, 0.85)), pos))
		placed += 1
	var forest := Node3D.new()
	forest.name = "Forest"
	root.add_child(forest)
	for key in cells:
		var entry: Dictionary = cells[key]
		var groups: Dictionary = {}
		for it in entry["near"]:
			if not groups.has(it[0]):
				groups[it[0]] = []
			(groups[it[0]] as Array).append(it[1])
		var has_near: bool = not groups.is_empty()
		for g in groups:
			var gid: String = g
			var mesh: Mesh = (leaf_meshes if gid.begins_with("L") else near_meshes)[int(gid.substr(1))]
			var mmi := _mm(forest, "Trees_%d_%d_%s" % [key.x, key.y, gid], mesh, null, groups[g])
			mmi.visibility_range_end = 170.0
			mmi.visibility_range_end_margin = 30.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var far_mmi := _mm(forest, "FarTrees_%d_%d" % [key.x, key.y], far_mesh, far_mat, entry["far"])
		far_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if has_near:
			far_mmi.visibility_range_begin = 150.0
			far_mmi.visibility_range_begin_margin = 30.0
			far_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		far_mmi.visibility_range_end = 2600.0


static func _mm(parent: Node, n: String, mesh: Mesh, mat: Material, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	parent.add_child(mmi)
	return mmi
