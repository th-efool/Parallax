class_name SwordTrail
extends MeshInstance3D
## World-space ribbon that follows the real blade (base -> tip) of a weapon mesh while `emitting`.
## Samples are Catmull-Rom subdivided so a 0.1 s swing still draws a smooth crescent, and the ribbon
## freezes during hit-stop (it ages on scaled time) which sells the impact frame.

@export var max_age: float = 0.14
@export var subdivisions: int = 4
@export var base_fraction: float = 0.22

var color: Color = Color(1.0, 0.7, 0.3, 1.0)
var width_boost: float = 1.0
var emitting: bool = false:
	set(value):
		if value == emitting:
			return
		if value:
			split_stroke()
		emitting = value

var _source: Node3D = null
var _tip_local: Vector3 = Vector3(0.0, 1.0, 0.0)
var _base_local: Vector3 = Vector3.ZERO
var _samples: Array[Dictionary] = []  # {b: Vector3, t: Vector3, age: float}
var _fading_strokes: Array[Dictionary] = []  # {samples: Array[Dictionary], color: Color, max_age: float}
var _imesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_color = Color.WHITE
	material_override = _mat


## Binds the trail to a blade mesh. Blade axis = longest local AABB axis; tip = end farther from the grip.
func bind_blade(blade: Node3D) -> void:
	_source = blade
	if blade is MeshInstance3D and (blade as MeshInstance3D).mesh != null:
		var aabb: AABB = (blade as MeshInstance3D).mesh.get_aabb()
		var axis: int = 1
		if aabb.size.x >= aabb.size.y and aabb.size.x >= aabb.size.z:
			axis = 0
		elif aabb.size.z >= aabb.size.y:
			axis = 2
		var lo: Vector3 = aabb.get_center()
		var hi: Vector3 = aabb.get_center()
		lo[axis] = aabb.position[axis]
		hi[axis] = aabb.end[axis]
		# Grip sits at the attachment origin: the far end from origin is the tip.
		if lo.length() > hi.length():
			var tmp: Vector3 = lo
			lo = hi
			hi = tmp
		_tip_local = hi
		_base_local = lo.lerp(hi, base_fraction)
	else:
		_tip_local = Vector3(0.0, 1.0, 0.0)
		_base_local = Vector3(0.0, 0.25, 0.0)


func has_blade() -> bool:
	return _source != null and is_instance_valid(_source)


func get_tip_world() -> Vector3:
	if not has_blade():
		return global_position
	return _source.global_transform * _tip_local


func split_stroke() -> void:
	if _samples.size() >= 2:
		_fading_strokes.append({
			"samples": _samples.duplicate(),
			"color": color,
			"max_age": max_age,
		})
	_samples.clear()


func clear_trail() -> void:
	_samples.clear()
	_fading_strokes.clear()
	_imesh.clear_surfaces()


func _process(delta: float) -> void:
	for s in _samples:
		s["age"] = float(s["age"]) + delta
	while not _samples.is_empty() and float(_samples[0]["age"]) > max_age:
		_samples.pop_front()
	for idx in range(_fading_strokes.size() - 1, -1, -1):
		var st: Dictionary = _fading_strokes[idx]
		var arr: Array = st["samples"] as Array
		var st_max_age: float = float(st.get("max_age", max_age))
		for s in arr:
			s["age"] = float(s["age"]) + delta
		while not arr.is_empty() and float(arr[0]["age"]) > st_max_age:
			arr.pop_front()
		if arr.size() < 2:
			_fading_strokes.remove_at(idx)
	if emitting and has_blade():
		var xf: Transform3D = _source.global_transform
		var b: Vector3 = xf * _base_local
		var t: Vector3 = xf * _tip_local
		# Extend the ribbon a little past the blade so the arc reads at gameplay camera distance.
		t = b + (t - b) * (1.25 * width_boost)
		if not _samples.is_empty() and (_samples[-1]["t"] as Vector3).distance_squared_to(t) > 4.0:
			split_stroke()
		if _samples.is_empty() or (_samples[-1]["t"] as Vector3).distance_squared_to(t) > 0.0004:
			_samples.append({"b": b, "t": t, "age": 0.0})
	_rebuild()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	for st in _fading_strokes:
		_draw_stroke(st["samples"] as Array, st.get("color", color) as Color, float(st.get("max_age", max_age)))
	if _samples.size() >= 2:
		_draw_stroke(_samples, color, max_age)


func _draw_stroke(samples: Array, stroke_color: Color, stroke_max_age: float) -> void:
	var n: int = samples.size()
	if n < 2:
		return
	var pts_b: Array[Vector3] = []
	var pts_t: Array[Vector3] = []
	var ages: Array[float] = []
	for i in range(n - 1):
		var p0: Dictionary = samples[maxi(0, i - 1)]
		var p1: Dictionary = samples[i]
		var p2: Dictionary = samples[i + 1]
		var p3: Dictionary = samples[mini(n - 1, i + 2)]
		var steps: int = maxi(1, subdivisions)
		for k in range(steps):
			var u: float = float(k) / steps
			pts_b.append(_catmull(p0["b"], p1["b"], p2["b"], p3["b"], u))
			pts_t.append(_catmull(p0["t"], p1["t"], p2["t"], p3["t"], u))
			ages.append(lerpf(float(p1["age"]), float(p2["age"]), u))
	pts_b.append(samples[-1]["b"])
	pts_t.append(samples[-1]["t"])
	ages.append(float(samples[-1]["age"]))

	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count: int = pts_b.size()
	for i in range(count):
		var life: float = clampf(1.0 - ages[i] / maxf(0.01, stroke_max_age), 0.0, 1.0)
		var head: float = float(i) / maxf(1.0, float(count - 1))
		var a: float = life * life * (0.25 + 0.75 * head)
		# Hot white core near the blade edge, coloured body toward the base.
		var core: Color = stroke_color.lerp(Color.WHITE, 0.55 * life)
		_imesh.surface_set_color(Color(stroke_color.r, stroke_color.g, stroke_color.b, a * 0.35))
		_imesh.surface_add_vertex(pts_b[i])
		_imesh.surface_set_color(Color(core.r, core.g, core.b, a))
		_imesh.surface_add_vertex(pts_t[i])
	_imesh.surface_end()


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
