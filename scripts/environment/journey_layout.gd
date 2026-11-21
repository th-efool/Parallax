class_name JourneyLayout
extends RefCounted
## Macro layout of "The Ascent" after the 2026-11-18 rework (IdiotHandOffGuide 05).
##
## GrandJourneyBuilder was authored in STORY coordinates (the old compact layout, z -61 .. 202). The rework:
##  * moved the start terrace 80 m south (OFF_S1_TERRACE);
##  * replaced the four connectors (Pilgrim's Causeway, Sunlit Stair, Windswept Rampart, Processional) with long
##    winding bridges, two bastions each (ROUTES), built straight in WORLD coordinates by _build_routes();
##  * grew the Hall of Echoes 20 -> 60 m and the clock-tower chamber 12 -> 36 m (also built in WORLD coordinates);
##  * kept Stage 03 (gallery) and Stage 05 (esplanade, colosseum, summit) in story coordinates, shifting their
##    stage roots and decor zones by OFF_S3 / OFF_S5.
## Anything that still thinks in story coordinates converts here: to_world(), to_world_z(), story_z().

const VERSION: int = 2

const OFF_S1_TERRACE: float = -80.0
const OFF_S3: float = 104.0
const OFF_S5: float = 160.0

const HALL_CENTER := Vector3(0.0, 4.0, 86.0)
const HALL_HALF: float = 30.0
const CHAMBER_CENTER := Vector3(0.0, 6.0, 210.0)
const CHAMBER_HALF: float = 18.0

## [story z, world z] breakpoints; piecewise linear, slope 1 beyond both ends.
const ZMAP: Array = [
	[-50.5, -130.5], [-15.2, -15.2], [7.6, 7.6], [24.0, 56.0], [44.0, 116.0],
	[58.0, 162.0], [87.4, 191.4], [100.6, 228.6], [116.0, 276.0],
]
## Story z ranges whose old floors were replaced by the bridges: decor / flora authored there is dropped.
const DROPPED: Array = [[-50.5, -15.2], [7.9, 23.5], [44.5, 57.5], [100.7, 115.9]]
## Story z ranges of the two 3x rooms: x widens by SCALE_X there.
const SCALED: Array = [[24.0, 44.0], [87.4, 100.6]]
const SCALE_X: float = 3.0

const BRIDGE_WIDTH: float = 6.0
## Winding bridges in WORLD coordinates (feet heights), z-monotonic. Each node is either
##   [position, bastion_radius]                  - a bastion: round platform, ring parapet, garrison
##   [position, 0.0, edge_z, edge_half_width]    - first / last node: a floor edge at z = edge_z whose opening
##                                                 (|x| <= edge_half_width) is closed by join rails out to the bridge
const ROUTES: Array = [
	["R1_PilgrimCauseway", [[Vector3(0, 0, -131), 0.0, -131.0, 6.0], [Vector3(34, 0, -97), 8.0], [Vector3(-34, 0, -49), 8.0], [Vector3(0, 0, -27), 6.0], [Vector3(0, 0, -15), 0.0, -15.0, 7.0]]],
	["R2_SunlitBridges", [[Vector3(0, 0, 8), 0.0, 8.0, 2.2], [Vector3(16, 1.1, 24), 8.0], [Vector3(-16, 2.9, 40), 8.0], [Vector3(0, 4, 56), 0.0, 55.5, 2.0]]],
	["R3_WindsweptRampart", [[Vector3(0, 4, 116), 0.0, 116.5, 2.0], [Vector3(16, 4.55, 132), 8.0], [Vector3(-16, 5.45, 148), 8.0], [Vector3(0, 6, 164), 0.0, 164.0, 3.95]]],
	["R5_Processional", [[Vector3(0, 6, 228), 0.0, 229.2, 2.0], [Vector3(16, 7.1, 244), 8.0], [Vector3(-16, 8.9, 260), 8.0], [Vector3(0, 10, 276), 0.0, 276.0, 9.0]]],
]


static func to_world_z(story: float) -> float:
	return _interp(story, 0, 1)


static func story_z(world: float) -> float:
	return _interp(world, 1, 0)


static func _interp(v: float, src: int, dst: int) -> float:
	var first: Array = ZMAP[0]
	if v <= float(first[src]):
		return float(first[dst]) + (v - float(first[src]))
	for i in range(ZMAP.size() - 1):
		var a: Array = ZMAP[i]
		var b: Array = ZMAP[i + 1]
		if v <= float(b[src]):
			var t: float = (v - float(a[src])) / maxf(0.0001, float(b[src]) - float(a[src]))
			return lerpf(float(a[dst]), float(b[dst]), t)
	var last: Array = ZMAP[ZMAP.size() - 1]
	return float(last[dst]) + (v - float(last[src]))


static func is_scaled(story_z_val: float) -> bool:
	for r in SCALED:
		if story_z_val >= float(r[0]) and story_z_val <= float(r[1]):
			return true
	return false


static func is_dropped(story_z_val: float) -> bool:
	for r in DROPPED:
		if story_z_val > float(r[0]) and story_z_val < float(r[1]):
			return true
	return false


## Story-coordinate point -> world point (x widens x3 inside the two rebuilt rooms).
static func to_world(p: Vector3) -> Vector3:
	var x: float = p.x * SCALE_X if is_scaled(p.z) else p.x
	return Vector3(x, p.y, to_world_z(p.z))


## Moves story-coordinate decor (the Dress_* set-dressing zones) onto the world layout. Nodes in a bridge region
## are freed (they would float in the air); every other node moves with to_world(). An identity-transform node
## with children is a container (its children carry the story positions); an identity MultiMesh has its
## instances moved instead.
static func remap_subtree(n: Node) -> void:
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var c3: Node3D = c as Node3D
		if c3 is MultiMeshInstance3D and c3.transform.is_equal_approx(Transform3D.IDENTITY):
			_remap_multimesh(c3 as MultiMeshInstance3D)
		elif c3.transform.is_equal_approx(Transform3D.IDENTITY) and c3.get_child_count() > 0:
			remap_subtree(c3)
		elif is_dropped(c3.position.z):
			n.remove_child(c3)
			c3.queue_free()
		else:
			c3.position = to_world(c3.position)


static func _remap_multimesh(mmi: MultiMeshInstance3D) -> void:
	var mm: MultiMesh = mmi.multimesh
	if mm == null:
		return
	var kept: Array[Transform3D] = []
	for i in range(mm.instance_count):
		var xf: Transform3D = mm.get_instance_transform(i)
		if not is_dropped(xf.origin.z):
			xf.origin = to_world(xf.origin)
			kept.append(xf)
	mm.instance_count = 0
	mm.instance_count = kept.size()
	for i in range(kept.size()):
		mm.set_instance_transform(i, kept[i])


## Objective guidance on the bridges: the next bridge node north of the player (bastion centre or the far end)
## while the player is on a bridge, `fallback` elsewhere. Bridges are z-monotonic, so "ahead" = further north.
static func guide_target(world_pos: Vector3, fallback: Vector3) -> Vector3:
	for r in ROUTES:
		var nodes: Array = r[1]
		var z0: float = ((nodes[0] as Array)[0] as Vector3).z
		var z1: float = ((nodes[nodes.size() - 1] as Array)[0] as Vector3).z
		if world_pos.z < z0 - 6.0 or world_pos.z > z1:
			continue
		for nd in nodes:
			var p: Vector3 = (nd as Array)[0]
			if p.z > world_pos.z + 3.0:
				return p
		return fallback
	return fallback
