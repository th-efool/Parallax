class_name GoreFX
extends RefCounted
## Stateless spawners for combat impact VFX: blood/ichor bursts, floor splat decals, sparks, dust,
## shockwave rings, and full-body dismemberment of KayKit rigs into physics gibs.
## Everything is procedural (no new assets) and self-cleans with FIFO caps.

const WORLD_MASK: int = 4 | 8 | 16  # World_Shared | World_Reality | World_Mirror (layers 3-5)
const BLOOD_RED: Color = Color(0.40, 0.012, 0.018, 1.0)
const ICHOR_CYAN: Color = Color(0.22, 0.86, 1.0, 1.0)
const MAX_DECALS: int = 48
const MAX_GIBS: int = 32

static var _decals: Array[Node] = []
static var _gibs: Array[Node] = []
static var _splat_tex: Texture2D = null
static var _droplet_meshes: Dictionary = {}
static var _bind_cache: Dictionary = {}
static var _rng := RandomNumberGenerator.new()


static func cleanup_all_fx() -> void:
	for g in _gibs:
		if is_instance_valid(g):
			(g as Node).queue_free()
	_gibs.clear()
	for d in _decals:
		if is_instance_valid(d):
			(d as Node).queue_free()
	_decals.clear()


static func clear_caches() -> void:
	cleanup_all_fx()
	_splat_tex = null
	_droplet_meshes.clear()
	_bind_cache.clear()


static func host_for(context: Node) -> Node:
	if context == null or not context.is_inside_tree():
		return null
	var scene: Node = context.get_tree().current_scene
	return scene if scene != null else context.get_tree().root


static func blood_color_for(is_spectral: bool) -> Color:
	return ICHOR_CYAN if is_spectral else BLOOD_RED


static func _free_after(node: Node, seconds: float) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.get_tree().create_timer(seconds, false, false, true).timeout.connect(node.queue_free)


# ---------------------------------------------------------------- particles

static func _droplet_mesh(color: Color, emissive: bool, size: float) -> Mesh:
	var key: String = "%s_%s_%.3f" % [color.to_html(), str(emissive), size]
	if _droplet_meshes.has(key):
		return _droplet_meshes[key] as Mesh
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.18
	mat.metallic_specular = 0.8
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.2
	m.material = mat
	_droplet_meshes[key] = m
	return m


static func _scale_curve(shrink_from: float = 0.55) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(shrink_from, 0.9))
	c.add_point(Vector2(1.0, 0.0))
	return c


## Directional blood spray. `intensity` ~0.5 (nick) .. 2.5 (decapitation fountain).
static func blood_burst(context: Node, pos: Vector3, dir: Vector3, intensity: float = 1.0, color: Color = BLOOD_RED, emissive: bool = false) -> void:
	var host: Node = host_for(context)
	if host == null:
		return
	var spray_dir: Vector3 = dir
	spray_dir.y = 0.0
	spray_dir = (spray_dir.normalized() if spray_dir.length_squared() > 0.001 else Vector3.FORWARD) + Vector3.UP * 0.45

	# Fast droplets
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = int(clampf(22.0 * intensity, 8.0, 90.0))
	p.lifetime = 0.95
	p.local_coords = false
	p.mesh = _droplet_mesh(color, emissive, 0.032)
	p.direction = spray_dir.normalized()
	p.spread = 26.0 + 10.0 * intensity
	p.initial_velocity_min = 2.6 + intensity
	p.initial_velocity_max = 6.5 + 2.2 * intensity
	p.gravity = Vector3(0.0, -17.0, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.8
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.6
	p.scale_amount_curve = _scale_curve()
	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, p.lifetime + 0.4)

	# Heavy globs that arc further and fall onto the floor
	var g := CPUParticles3D.new()
	g.one_shot = true
	g.explosiveness = 0.85
	g.amount = int(clampf(7.0 * intensity, 3.0, 30.0))
	g.lifetime = 1.2
	g.local_coords = false
	g.mesh = _droplet_mesh(color, emissive, 0.06)
	g.direction = (spray_dir + Vector3.UP * 0.4).normalized()
	g.spread = 40.0
	g.initial_velocity_min = 1.5
	g.initial_velocity_max = 4.5 + intensity
	g.gravity = Vector3(0.0, -19.0, 0.0)
	g.scale_amount_min = 0.6
	g.scale_amount_max = 1.3
	g.scale_amount_curve = _scale_curve(0.8)
	host.add_child(g)
	g.global_position = pos
	g.emitting = true
	_free_after(g, g.lifetime + 0.4)

	# Floor splats land a beat later, scattered along the spray direction
	var splats: int = clampi(int(round(1.0 + intensity * 1.6)), 1, 5)
	for i in range(splats):
		var along: float = _rng.randf_range(0.2, 1.1 + intensity * 0.6)
		var side: Vector3 = Vector3(spray_dir.z, 0.0, -spray_dir.x).normalized() * _rng.randf_range(-0.5, 0.5)
		var flat_dir: Vector3 = Vector3(spray_dir.x, 0.0, spray_dir.z).normalized()
		var at: Vector3 = pos + flat_dir * along + side
		blood_decal(context, at, _rng.randf_range(0.45, 0.85) * (0.75 + intensity * 0.3), color, 0.06 + 0.05 * i)


## Persistent floor splat (Forward+ Decal). Ray-casts down to find the floor.
static func blood_decal(context: Node, near_pos: Vector3, size: float, color: Color = BLOOD_RED, delay: float = 0.0) -> void:
	var host: Node = host_for(context)
	if host == null:
		return
	var world: World3D = null
	if context is Node3D:
		world = (context as Node3D).get_world_3d()
	elif context.get_viewport() != null:
		world = context.get_viewport().find_world_3d()
	if world == null:
		return
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return
	var q := PhysicsRayQueryParameters3D.create(near_pos + Vector3.UP * 0.8, near_pos + Vector3.DOWN * 4.0, WORLD_MASK)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	var d := Decal.new()
	d.texture_albedo = _get_splat_texture()
	var c: Color = color.darkened(0.15)
	c.a = 0.0
	d.modulate = c
	d.albedo_mix = 1.0
	d.size = Vector3(size, 0.8, size)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.normal_fade = 0.4
	host.add_child(d)
	d.global_position = (hit["position"] as Vector3) + Vector3.UP * 0.05
	d.rotation.y = _rng.randf_range(0.0, TAU)
	d.scale = Vector3(0.3, 1.0, 0.3)
	var tw := d.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(d, "modulate:a", 0.92, 0.08)
	tw.tween_property(d, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(16.0)
	tw.tween_property(d, "modulate:a", 0.0, 2.5)
	tw.tween_callback(d.queue_free)
	_prune_freed(_decals)
	_decals.append(d)
	while _decals.size() > MAX_DECALS:
		var old: Variant = _decals.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()


static func _get_splat_texture() -> Texture2D:
	if _splat_tex != null:
		return _splat_tex
	var sz: int = 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var lobes: Array[Vector3] = []  # (freq, phase, amp)
	for i in range(6):
		lobes.append(Vector3(float(rng.randi_range(3, 11)), rng.randf_range(0.0, TAU), rng.randf_range(0.02, 0.07)))
	var drops: Array[Vector3] = []  # (x, y, r) in 0..1
	for i in range(14):
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(0.33, 0.47)
		drops.append(Vector3(0.5 + cos(ang) * dist, 0.5 + sin(ang) * dist, rng.randf_range(0.012, 0.035)))
	for y in range(sz):
		for x in range(sz):
			var u: float = (float(x) + 0.5) / sz
			var v: float = (float(y) + 0.5) / sz
			var dx: float = u - 0.5
			var dy: float = v - 0.5
			var r: float = sqrt(dx * dx + dy * dy)
			var ang2: float = atan2(dy, dx)
			var edge: float = 0.27
			for l in lobes:
				edge += sin(ang2 * l.x + l.y) * l.z
			var a: float = clampf((edge - r) / 0.018, 0.0, 1.0)
			for dr in drops:
				var dd: float = Vector2(u - dr.x, v - dr.y).length()
				a = maxf(a, clampf((dr.z - dd) / 0.006, 0.0, 1.0))
			# Darker, thicker centre; slightly lighter wet rim
			var shade: float = lerpf(1.0, 0.7, clampf(1.0 - r / maxf(0.01, edge), 0.0, 1.0))
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	_splat_tex = ImageTexture.create_from_image(img)
	return _splat_tex


static func sparks(context: Node, pos: Vector3, dir: Vector3, color: Color = Color(1.0, 0.78, 0.35), amount: int = 26) -> void:
	var host: Node = host_for(context)
	if host == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.42
	p.local_coords = false
	var quad := BoxMesh.new()
	quad.size = Vector3(0.025, 0.025, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	quad.material = mat
	p.mesh = quad
	p.particle_flag_align_y = true
	p.direction = (dir.normalized() + Vector3.UP * 0.3).normalized()
	p.spread = 55.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0.0, -14.0, 0.0)
	p.scale_amount_curve = _scale_curve(0.3)
	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, 0.9)
	flash_light(context, pos, color, 3.5, 0.10, 3.0)


static func flash_light(context: Node, pos: Vector3, color: Color, energy: float, duration: float, light_range: float = 4.0) -> void:
	var host: Node = host_for(context)
	if host == null:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	host.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration)
	tw.tween_callback(l.queue_free)


static func dust_puff(context: Node, pos: Vector3, radius: float = 0.6, amount: int = 14, color: Color = Color(0.62, 0.56, 0.48, 0.55), up_speed: float = 1.2) -> void:
	var host: Node = host_for(context)
	if host == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = 0.7
	p.local_coords = false
	var m := SphereMesh.new()
	m.radius = 0.12
	m.height = 0.24
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	m.material = mat
	p.mesh = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.4
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = up_speed * 0.4
	p.initial_velocity_max = up_speed * 1.4
	p.gravity = Vector3(0.0, 0.4, 0.0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.2
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	host.add_child(p)
	p.global_position = pos + Vector3.UP * 0.05
	p.emitting = true
	_free_after(p, 1.1)


static func shockwave_ring(context: Node, pos: Vector3, radius: float, color: Color, duration: float = 0.38, thickness: float = 0.3) -> void:
	var host: Node = host_for(context)
	if host == null:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0 - thickness * 0.5
	torus.outer_radius = 1.0 + thickness * 0.5
	torus.rings = 40
	torus.ring_segments = 8
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	ring.material_override = mat
	host.add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.08
	ring.scale = Vector3(0.25, 0.12, 0.25)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 0.04, radius), duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(ring.queue_free)


## Glowing fissure decal + debris chunks along a line (heavy cleave / landing slam).
static func ground_crack(context: Node, origin: Vector3, dir: Vector3, length: float, color: Color) -> void:
	var host: Node = host_for(context)
	if host == null:
		return
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length_squared() > 0.001 else Vector3.FORWARD
	var steps: int = maxi(2, int(length / 0.7))
	for i in range(steps):
		var at: Vector3 = origin + flat * (0.4 + float(i) * length / steps)
		var delay: float = 0.025 * i
		var tmr: SceneTreeTimer = host.get_tree().create_timer(delay, false, false, true)
		tmr.timeout.connect(func() -> void:
			if not is_instance_valid(host):
				return
			dust_puff(host, at, 0.25, 6, Color(0.55, 0.5, 0.44, 0.6), 2.4)
			_debris(host, at, 2 if i % 2 == 0 else 1)
		)
	blood_decal(context, origin + flat * length * 0.5, length * 0.5, color.darkened(0.6), 0.0)


static func _debris(host: Node, at: Vector3, count: int) -> void:
	for i in range(count):
		var rb := RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = WORLD_MASK
		rb.mass = 0.2
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var s: float = _rng.randf_range(0.06, 0.14)
		box.size = Vector3.ONE * s
		cs.shape = box
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * s
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.40, 0.35)
		bm.material = mat
		mi.mesh = bm
		rb.add_child(mi)
		host.add_child(rb)
		rb.global_position = at + Vector3.UP * 0.12
		rb.linear_velocity = Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(3.0, 6.0), _rng.randf_range(-1.5, 1.5))
		rb.angular_velocity = Vector3(_rng.randf_range(-10, 10), _rng.randf_range(-10, 10), _rng.randf_range(-10, 10))
		_track_gib(rb, 2.5)


# ---------------------------------------------------------------- dismemberment

## Explodes a (skinned) KayKit model into per-bone physics gibs, posed exactly as the frame of death.
## Meshes skinned mostly to one bone (head, arm, leg, torso) plus bone-attached props (helmet, weapon,
## shield) are grouped by bone so each limb flies off as one piece. Returns the number of gibs spawned.
static func dismember(context: Node, model_root: Node3D, impulse_dir: Vector3, force: float, blood: Color, emissive: bool, lifetime: float = 7.0) -> int:
	var host: Node = host_for(context)
	if host == null or model_root == null or not model_root.is_inside_tree():
		return 0
	var meshes: Array[MeshInstance3D] = []
	_collect_visible_meshes(model_root, meshes)
	if meshes.is_empty():
		return 0

	var groups: Dictionary = {}  # key -> Array of [MeshInstance3D, Transform3D]
	for mi in meshes:
		var info: Array = _posed_transform_and_key(mi)
		var key: String = String(info[1])
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append([mi, info[0]])

	var flat_dir: Vector3 = Vector3(impulse_dir.x, 0.0, impulse_dir.z)
	flat_dir = flat_dir.normalized() if flat_dir.length_squared() > 0.001 else Vector3.FORWARD
	var center: Vector3 = model_root.global_position + Vector3.UP * 0.9
	var spawned: int = 0
	var bleeders: int = 0
	for key in groups.keys():
		var parts: Array = groups[key]
		var world_center := Vector3.ZERO
		for part in parts:
			var mi_p: MeshInstance3D = part[0]
			var xf_p: Transform3D = part[1]
			world_center += xf_p * mi_p.mesh.get_aabb().get_center()
		world_center /= float(parts.size())
		var first_xf: Transform3D = parts[0][1]
		var body_xf := Transform3D(first_xf.basis.orthonormalized(), world_center)
		var inv: Transform3D = body_xf.affine_inverse()

		var rb := RigidBody3D.new()
		rb.name = "Gib_" + key.replace(".", "_")
		rb.collision_layer = 0
		rb.collision_mask = WORLD_MASK
		rb.continuous_cd = false
		rb.gravity_scale = 1.35
		rb.linear_damp = 0.15
		rb.angular_damp = 0.6
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.18
		rb.physics_material_override = pm

		var local_aabb := AABB()
		var first: bool = true
		for part in parts:
			var src: MeshInstance3D = part[0]
			var local_xf: Transform3D = inv * (part[1] as Transform3D)
			var gm := MeshInstance3D.new()
			gm.mesh = src.mesh
			gm.transform = local_xf
			if src.material_override != null:
				gm.material_override = src.material_override
			else:
				for s in range(src.mesh.get_surface_count()):
					var m: Material = src.get_active_material(s)
					if m != null:
						gm.set_surface_override_material(s, m)
			rb.add_child(gm)
			var part_aabb: AABB = local_xf * src.mesh.get_aabb()
			local_aabb = part_aabb if first else local_aabb.merge(part_aabb)
			first = false

		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(0.07, local_aabb.size.x * 0.8), maxf(0.07, local_aabb.size.y * 0.8), maxf(0.07, local_aabb.size.z * 0.8))
		cs.shape = box
		cs.position = local_aabb.get_center()
		rb.add_child(cs)
		rb.mass = clampf(box.size.x * box.size.y * box.size.z * 60.0, 0.25, 4.0)

		host.add_child(rb)
		rb.global_transform = body_xf

		var radial: Vector3 = world_center - center
		radial = radial.normalized() if radial.length_squared() > 0.0001 else Vector3.UP
		var v: Vector3 = flat_dir * force * _rng.randf_range(0.55, 1.15)
		v += radial * _rng.randf_range(0.8, 2.6) * (0.5 + force * 0.12)
		v += Vector3.UP * _rng.randf_range(1.2, 3.4) * (0.6 + force * 0.08)
		rb.linear_velocity = v
		rb.angular_velocity = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(5.0, 14.0)

		if bleeders < 3 and blood.a > 0.0 and parts.size() > 0:
			_attach_bleed_trail(rb, local_aabb.get_center(), blood, emissive)
			bleeders += 1
		_track_gib(rb, lifetime + _rng.randf_range(-0.8, 0.8))
		spawned += 1
	return spawned


static func _attach_bleed_trail(body: Node3D, local_pos: Vector3, color: Color, emissive: bool) -> void:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.55
	p.local_coords = false
	p.mesh = _droplet_mesh(color, emissive, 0.026)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0.0, -14.0, 0.0)
	p.scale_amount_curve = _scale_curve()
	p.position = local_pos
	body.add_child(p)
	p.emitting = true
	var tw: Tween = body.create_tween()
	tw.tween_property(p, "emitting", false, _rng.randf_range(0.9, 1.6)).from(true)


static func _prune_freed(list: Array) -> void:
	var i: int = list.size() - 1
	while i >= 0:
		if not is_instance_valid(list[i]):
			list.remove_at(i)
		i -= 1


static func _track_gib(body: Node3D, lifetime: float) -> void:
	_prune_freed(_gibs)
	_gibs.append(body)
	while _gibs.size() > MAX_GIBS:
		var old: Variant = _gibs.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var tw := body.create_tween()
	tw.tween_interval(maxf(0.5, lifetime))
	tw.tween_property(body, "scale", Vector3(0.01, 0.01, 0.01), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(body.queue_free)


static func _collect_visible_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			out.append(mi)
	for c in node.get_children():
		if c is Node3D and not (c as Node3D).visible:
			continue
		if c is CPUParticles3D or c is GPUParticles3D or c is Light3D:
			continue
		_collect_visible_meshes(c, out)


## Returns [posed_global_transform_of_mesh_space, group_key].
static func _posed_transform_and_key(mi: MeshInstance3D) -> Array:
	# Props rigidly attached to a bone (helmet, sword, shield) group with that bone.
	var p: Node = mi.get_parent()
	while p != null and not (p is Skeleton3D):
		if p is BoneAttachment3D:
			return [mi.global_transform, String((p as BoneAttachment3D).bone_name)]
		p = p.get_parent()
	if mi.skin == null:
		return [mi.global_transform, String(mi.name)]
	var skel: Skeleton3D = mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if skel == null:
		return [mi.global_transform, String(mi.name)]
	var bind_idx: int = _dominant_bind(mi.mesh, mi.skin)
	if bind_idx < 0:
		return [mi.global_transform, String(mi.name)]
	var bone: int = mi.skin.get_bind_bone(bind_idx)
	if bone < 0:
		bone = skel.find_bone(String(mi.skin.get_bind_name(bind_idx)))
	if bone < 0:
		return [mi.global_transform, String(mi.name)]
	var xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind_idx)
	return [xf, skel.get_bone_name(bone)]


## Bind index carrying the largest summed vertex weight (cached per mesh resource).
static func _dominant_bind(mesh: Mesh, skin: Skin) -> int:
	var key: int = mesh.get_instance_id()
	if _bind_cache.has(key):
		return int(_bind_cache[key])
	var best: int = -1
	var arrays: Array = mesh.surface_get_arrays(0) if mesh.get_surface_count() > 0 else []
	if arrays.size() > Mesh.ARRAY_WEIGHTS:
		var bones: PackedInt32Array = PackedInt32Array(arrays[Mesh.ARRAY_BONES]) if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = PackedFloat32Array(arrays[Mesh.ARRAY_WEIGHTS]) if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if bones.size() > 0 and bones.size() == weights.size():
			var sums: Dictionary = {}
			for i in range(bones.size()):
				var w: float = weights[i]
				if w > 0.0:
					sums[bones[i]] = float(sums.get(bones[i], 0.0)) + w
			var best_w: float = -1.0
			for b in sums.keys():
				if float(sums[b]) > best_w and int(b) < skin.get_bind_count():
					best_w = float(sums[b])
					best = int(b)
	_bind_cache[key] = best
	return best
