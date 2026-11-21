class_name WardenLook
extends RefCounted
## Dresses the Warden's KayKit Skeleton_Minion rig as a bone colossus that still reads as KayKit:
## charred-obsidian bone tint, glowing ember eyes, curved horns, shoulder spikes, a borrowed two-handed axe
## (scaled up) and a slow drift of embers off the ribcage. Everything is procedural or borrowed from the
## KayKit packs already in the project — no new files besides the Minion rig itself.

const LoadoutScript := preload("res://scripts/core/character_loadout.gd")
const BARBARIAN_GLB: String = "res://assets/models/characters/Barbarian.glb"
const BONE_TINT := Color(0.50, 0.47, 0.55, 1.0)
const CLOAK_TINT := Color(0.30, 0.27, 0.36, 1.0)
const EYE_GLOW := Color(1.0, 0.62, 0.22, 1.0)
const HORN_COLOR := Color(0.16, 0.14, 0.15, 1.0)
const HORN_TIP_GLOW := Color(0.25, 0.70, 1.0, 1.0)


static func dress(model_root: Node3D) -> void:
	if model_root == null:
		return
	var skel: Skeleton3D = model_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D if not model_root.find_children("*", "Skeleton3D", true, false).is_empty() else null
	if skel == null:
		return
	_tint(model_root)
	_add_horns(skel)
	_add_shoulder_spikes(skel)
	var axe: MeshInstance3D = LoadoutScript.arm_with_borrowed(model_root, BARBARIAN_GLB, "2H_Axe", "handslot.r")
	if axe != null:
		axe.scale = Vector3.ONE * 1.3
	_add_embers(skel)


static func _tint(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		var is_eyes: bool = String(mi.name).ends_with("_Eyes")
		var is_cloak: bool = String(mi.name).ends_with("_Cloak")
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var src: Material = mi.get_surface_override_material(s)
				if src == null:
					src = mi.mesh.surface_get_material(s)
				if not (src is StandardMaterial3D):
					continue
				var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				if is_eyes:
					m.albedo_color = EYE_GLOW
					m.emission_enabled = true
					m.emission = EYE_GLOW
					m.emission_energy_multiplier = 5.0
				else:
					m.albedo_color = m.albedo_color * (CLOAK_TINT if is_cloak else BONE_TINT)
				mi.set_surface_override_material(s, m)
	for c in node.get_children():
		_tint(c)


static func _horn_material(tip: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = HORN_COLOR
	m.roughness = 0.55
	if tip:
		m.emission_enabled = true
		m.emission = HORN_TIP_GLOW
		m.emission_energy_multiplier = 1.6
	return m


## Each horn is four tapering cones, each bent further out and back, so it curls like a ram/demon horn.
static func _add_horns(skel: Skeleton3D) -> void:
	if skel.find_bone("head") < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = "WardenHorns"
	att.bone_name = "head"
	skel.add_child(att)
	var base_mat: StandardMaterial3D = _horn_material(false)
	var tip_mat: StandardMaterial3D = _horn_material(true)
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		# KayKit skulls are oversized (chibi): the horns root on the upper sides of the cranium, not inside it.
		pivot.position = Vector3(0.40 * side, 0.78, 0.04)
		pivot.rotation = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(-68.0 * side))
		att.add_child(pivot)
		var parent: Node3D = pivot
		var radius: float = 0.13
		var seg_len: float = 0.26
		for i in range(4):
			var cone := CylinderMesh.new()
			cone.bottom_radius = radius
			cone.top_radius = radius * 0.62
			cone.height = seg_len
			cone.radial_segments = 8
			cone.rings = 1
			var mi := MeshInstance3D.new()
			mi.mesh = cone
			mi.material_override = tip_mat if i == 3 else base_mat
			mi.position = Vector3(0.0, seg_len * 0.5, 0.0)
			parent.add_child(mi)
			var joint := Node3D.new()
			joint.position = Vector3(0.0, seg_len, 0.0)
			joint.rotation = Vector3(deg_to_rad(-14.0), 0.0, deg_to_rad(30.0 * side))
			parent.add_child(joint)
			parent = joint
			radius *= 0.62
			seg_len *= 0.92
	# Spiked crown ridge between the horns.
	for k in range(3):
		var spike := CylinderMesh.new()
		spike.bottom_radius = 0.05
		spike.top_radius = 0.0
		spike.height = 0.16 + 0.06 * float(1 - absi(k - 1))
		spike.radial_segments = 6
		var smi := MeshInstance3D.new()
		smi.mesh = spike
		smi.material_override = base_mat
		smi.position = Vector3((float(k) - 1.0) * 0.16, 0.92 + spike.height * 0.5, 0.06)
		att.add_child(smi)


static func _add_shoulder_spikes(skel: Skeleton3D) -> void:
	var mat: StandardMaterial3D = _horn_material(false)
	for bone: String in ["upperarm.l", "upperarm.r"]:
		if skel.find_bone(bone) < 0:
			continue
		var att := BoneAttachment3D.new()
		att.name = "WardenSpikes_" + bone
		att.bone_name = bone
		skel.add_child(att)
		var side: float = -1.0 if bone.ends_with(".l") else 1.0
		for j in range(2):
			var cone := CylinderMesh.new()
			cone.bottom_radius = 0.07
			cone.top_radius = 0.0
			cone.height = 0.28 - 0.06 * float(j)
			cone.radial_segments = 6
			var mi := MeshInstance3D.new()
			mi.mesh = cone
			mi.material_override = mat
			mi.position = Vector3(0.04 * side, 0.10 + 0.05 * float(j), -0.06 + 0.12 * float(j))
			mi.rotation = Vector3(deg_to_rad(-20.0 + 30.0 * float(j)), 0.0, deg_to_rad(-38.0 * side))
			att.add_child(mi)


static func _add_embers(skel: Skeleton3D) -> void:
	if skel.find_bone("chest") < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = "WardenEmbers"
	att.bone_name = "chest"
	skel.add_child(att)
	var p := CPUParticles3D.new()
	p.amount = 28
	p.lifetime = 1.8
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	# Tiny soft round sprite (radial falloff texture), tinted per particle by the colour ramp.
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	var dot_tex := GradientTexture2D.new()
	dot_tex.gradient = dot
	dot_tex.fill = GradientTexture2D.FILL_RADIAL
	dot_tex.fill_from = Vector2(0.5, 0.5)
	dot_tex.fill_to = Vector2(1.0, 0.5)
	dot_tex.width = 32
	dot_tex.height = 32
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.vertex_color_use_as_albedo = true
	pm.albedo_texture = dot_tex
	q.material = pm
	p.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.7, 0.3, 0.9))
	ramp.set_color(1, Color(0.3, 0.6, 1.0, 0.0))
	p.color_ramp = ramp
	att.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = EYE_GLOW
	light.light_energy = 0.8
	light.omni_range = 2.6
	light.shadow_enabled = false
	light.position = Vector3(0, 0.45, -0.25)
	att.add_child(light)
