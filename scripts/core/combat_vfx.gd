class_name CombatVFX
extends RefCounted
## Stateless combat-feedback VFX factory (Claude Pass A).
## - `spawn_impact_burst()`: one-shot GPUParticles3D melee impact. Reality = amber sparks (fast, heavy gravity),
##   Mirror = cobalt glass shards (slower, floaty, longer-lived). Self-frees after its lifetime.
## - `build_arc_ribbon_mesh()`: flat annular-sector ribbon (UV.x along the swing, UV.y inner->outer edge)
##   consumed by `assets/shaders/sword_slash_trail.gdshader`.
## All functions are static; callers should `preload()` this script (see CLAUDE.md §3.1).

const AMBER_HOT: Color = Color(1.0, 0.86, 0.52, 1.0)
const AMBER_COOL: Color = Color(1.0, 0.36, 0.06, 0.0)
const COBALT_HOT: Color = Color(0.78, 0.94, 1.0, 1.0)
const COBALT_COOL: Color = Color(0.12, 0.38, 1.0, 0.0)


static func spawn_impact_burst(host: Node, world_pos: Vector3, mirror_style: bool, heavy: bool = false, scale_mult: float = 1.0) -> GPUParticles3D:
	if host == null or not host.is_inside_tree():
		return null

	var p := GPUParticles3D.new()
	p.name = "ImpactBurstVFX"
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.35
	p.local_coords = false
	p.amount = (30 if heavy else 16) if not mirror_style else (22 if heavy else 12)
	p.lifetime = 0.62 if mirror_style else 0.40
	p.visibility_aabb = AABB(Vector3(-4.0, -4.0, -4.0), Vector3(8.0, 8.0, 8.0))
	p.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 180.0
	pm.particle_flag_align_y = true
	var vel_scale: float = (1.35 if heavy else 1.0) * scale_mult
	if mirror_style:
		pm.initial_velocity_min = 1.8 * vel_scale
		pm.initial_velocity_max = 4.6 * vel_scale
		pm.gravity = Vector3(0.0, -2.6, 0.0)
		pm.damping_min = 1.5
		pm.damping_max = 3.0
		pm.scale_min = 0.7
		pm.scale_max = 1.4
	else:
		pm.initial_velocity_min = 3.4 * vel_scale
		pm.initial_velocity_max = 8.0 * vel_scale
		pm.gravity = Vector3(0.0, -15.0, 0.0)
		pm.damping_min = 0.5
		pm.damping_max = 1.5
		pm.scale_min = 0.6
		pm.scale_max = 1.2

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	if mirror_style:
		grad.colors = PackedColorArray([COBALT_HOT, COBALT_COOL])
	else:
		grad.colors = PackedColorArray([AMBER_HOT, AMBER_COOL])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	p.process_material = pm

	var mesh := BoxMesh.new()
	if mirror_style:
		mesh.size = Vector3(0.07, 0.15, 0.015) * scale_mult
	else:
		mesh.size = Vector3(0.025, 0.20, 0.025) * scale_mult
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.6, 1.6, 1.6, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	p.draw_pass_1 = mesh

	host.add_child(p)
	p.global_position = world_pos
	p.restart()
	p.emitting = true

	var flash := OmniLight3D.new()
	flash.name = "ImpactFlash"
	flash.light_color = COBALT_HOT if mirror_style else AMBER_HOT
	flash.omni_range = 3.2 if heavy else 2.2
	flash.light_energy = 2.6 if heavy else 1.5
	flash.shadow_enabled = false
	p.add_child(flash)
	var tw := p.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.14)

	host.get_tree().create_timer(p.lifetime + 0.6, false, false, true).timeout.connect(p.queue_free)
	return p


static func build_arc_ribbon_mesh(inner_radius: float, outer_radius: float, start_deg: float, end_deg: float, segments: int = 28) -> ArrayMesh:
	## Builds a flat ribbon in the local XZ plane. Angle 0 points at -Z (Godot forward); positive angles sweep toward +X.
	var segs: int = maxi(2, segments)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var a: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var dir := Vector3(sin(a), 0.0, -cos(a))
		# Slight taper so the ribbon is thinner at the tail and fullest at the head.
		var width_t: float = lerpf(0.55, 1.0, t)
		var inner_r: float = lerpf(outer_radius, inner_radius, width_t)
		verts.append(dir * inner_r)
		verts.append(dir * outer_radius)
		uvs.append(Vector2(t, 0.0))
		uvs.append(Vector2(t, 1.0))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

	for i in range(segs):
		var b: int = i * 2
		indices.append_array(PackedInt32Array([b, b + 1, b + 2, b + 1, b + 3, b + 2]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
