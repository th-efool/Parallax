class_name CharacterLoadout
extends RefCounted
## KayKit character `.glb` rigs ship with EVERY prop bolted to the hands at once (Knight: 2 swords + 4
## shields; Barbarian: 3 axes + shield + mug) while the Skeleton rigs ship unarmed. This helper trims each
## rig to one readable loadout and borrows a sword mesh from `Knight.glb` for the skeletons.

const KNIGHT_GLB: String = "res://assets/models/characters/Knight.glb"
const BARBARIAN_GLB: String = "res://assets/models/characters/Barbarian.glb"

## Prop node names known to be bolted to KayKit hand slots.
const ALL_HAND_PROPS: Array[String] = [
	"1H_Sword", "1H_Sword_Offhand", "2H_Sword", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield",
	"1H_Axe", "1H_Axe_Offhand", "2H_Axe", "Mug", "Barbarian_Round_Shield",
]

static var _borrowed_meshes: Dictionary = {}


static func clear_caches() -> void:
	_borrowed_meshes.clear()


## Shows only the props listed in `keep` (others among ALL_HAND_PROPS are hidden). Returns props kept.
static func apply(model_root: Node, keep: Array[String]) -> int:
	if model_root == null:
		return 0
	var kept: int = 0
	for prop_name in ALL_HAND_PROPS:
		var n: Node = model_root.find_child(prop_name, true, false)
		if n is Node3D:
			var keep_it: bool = keep.has(prop_name)
			(n as Node3D).visible = keep_it
			if keep_it:
				kept += 1
	return kept


## Picks a loadout from the rig contents: Knight / Barbarian get trimmed, skeletons get a borrowed blade.
static func apply_default_for(model_root: Node, role: String = "") -> void:
	if model_root == null:
		return
	if model_root.find_child("Knight_Body", true, false) != null:
		if role == "player":
			apply(model_root, ["1H_Sword", "Badge_Shield"])
		else:
			apply(model_root, ["2H_Sword", "Spike_Shield"])
	elif model_root.find_child("Barbarian_Body", true, false) != null:
		apply(model_root, ["2H_Axe", "Barbarian_Round_Shield"])
	elif _has_skeleton_rig(model_root) and _count_visible_props(model_root) == 0:
		if model_root.find_child("Skeleton_Rogue_Body", true, false) != null:
			arm_with_borrowed(model_root, KNIGHT_GLB, "1H_Sword", "handslot.r")
			arm_with_borrowed(model_root, KNIGHT_GLB, "1H_Sword_Offhand", "handslot.l")
		else:
			arm_with_borrowed(model_root, BARBARIAN_GLB, "1H_Axe", "handslot.r")
			arm_with_borrowed(model_root, KNIGHT_GLB, "Round_Shield", "handslot.l")


static func _has_skeleton_rig(model_root: Node) -> bool:
	return model_root.find_child("Skeleton3D", true, false) != null or _find_skeleton(model_root) != null


static func _count_visible_props(model_root: Node) -> int:
	var c: int = 0
	for prop_name in ALL_HAND_PROPS:
		var n: Node = model_root.find_child(prop_name, true, false)
		if n is Node3D and (n as Node3D).visible:
			c += 1
	return c


## Bolts a prop mesh taken from another KayKit rig onto `bone_name` of this rig.
static func arm_with_borrowed(model_root: Node, source_glb: String, prop_name: String, bone_name: String) -> MeshInstance3D:
	var skel: Skeleton3D = _find_skeleton(model_root)
	if skel == null or skel.find_bone(bone_name) < 0:
		return null
	var data: Array = _get_borrowed(source_glb, prop_name)
	if data.is_empty():
		return null
	var att := BoneAttachment3D.new()
	att.name = "Borrowed_" + prop_name
	att.bone_name = bone_name
	skel.add_child(att)
	var mi := MeshInstance3D.new()
	mi.name = prop_name
	mi.mesh = data[0] as Mesh
	mi.transform = data[1] as Transform3D
	var mats: Array = data[2]
	for i in range(mats.size()):
		if mats[i] != null:
			mi.set_surface_override_material(i, mats[i] as Material)
	att.add_child(mi)
	return mi


static func _get_borrowed(source_glb: String, prop_name: String) -> Array:
	var key: String = source_glb + "::" + prop_name
	if _borrowed_meshes.has(key):
		return _borrowed_meshes[key]
	var result: Array = []
	if ResourceLoader.exists(source_glb):
		var packed: PackedScene = load(source_glb) as PackedScene
		if packed != null:
			var inst: Node = packed.instantiate()
			var src: MeshInstance3D = find_prop_mesh(inst, prop_name)
			if src != null and src.mesh != null:
				var mats: Array = []
				for s in range(src.mesh.get_surface_count()):
					var m: Material = src.get_surface_override_material(s)
					if m == null:
						m = src.mesh.surface_get_material(s)
					mats.append(m)
				# Local transform relative to its BoneAttachment (glTF prop offset on the hand slot).
				result = [src.mesh, src.transform, mats]
			inst.free()
	_borrowed_meshes[key] = result
	return result


## The glTF importer may name the BoneAttachment3D identically to its prop mesh, so look for the
## MeshInstance3D explicitly.
static func find_prop_mesh(root: Node, prop_name: String) -> MeshInstance3D:
	if root == null:
		return null
	var found: Array[Node] = root.find_children(prop_name, "MeshInstance3D", true, false)
	if not found.is_empty():
		return found[0] as MeshInstance3D
	var any: Node = root.find_child(prop_name, true, false)
	if any is MeshInstance3D:
		return any as MeshInstance3D
	if any != null:
		for c in any.get_children():
			if c is MeshInstance3D:
				return c as MeshInstance3D
	return null


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var s: Skeleton3D = _find_skeleton(c)
		if s != null:
			return s
	return null
