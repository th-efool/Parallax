class_name AmbientLifeLayout
extends Node3D
## Places ambient life along "The Ascent" (GrandJourneyBuilder level) so it fits each place:
##  - Cliff Garden: a sunken terrace (Y -1.5) cradled between the two Pilgrim's Causeway spans, built
##    from the level's own realm_pbr rock / sand / castle-brick materials. Seen from both causeways and the
##    overlook (parapets keep the player out, so it never touches the route's collision). The only place
##    with trees, a meadow and herd animals: deer, a fox, butterflies, doves at the fountain, lizards on
##    the rocks; in Mirror a spectral grove with ghost stags.
##  - Everywhere else stays architectural: sun-dried wispy grass in wall corners and along parapets, ivy
##    on walls, doves and crows, rats by the braziers, lizards on sunny stone, wisps and moths in Mirror.
## Fighting floors are left clear. All of it is cosmetic: no collision on the route, no gameplay effects.
## Instanced from `scenes/main/main.tscn` as `AmbientLife`; delete that node to remove everything.

const ProcMesh := preload("res://scripts/environment/procedural_mesh_kit.gd")
const PBR_DIR: String = "res://assets/textures/pbr/"
const REALM_PBR_SHADER: String = "res://assets/shaders/realm_pbr.gdshader"
const HABITAT := preload("res://scripts/ambient/ambient_habitat.gd")
const VEG_PATCH := preload("res://scripts/ambient/vegetation_patch.gd")
const FLORA_PATCH := preload("res://scripts/ambient/flora_patch.gd")
const IVY := preload("res://scripts/ambient/wall_ivy.gd")

const LAYER_WORLD_SHARED: int = 4

## Garden terrace: floor top Y, centre and footprint (kept east of both causeway rails).
const GARDEN_Y: float = -1.5
const GARDEN_CENTER: Vector3 = Vector3(6.5, -1.5, -33.0)

## Off since 2026-11-17: playtest feedback — the sunken garden between the causeways read as out of place.
@export var build_garden: bool = false
@export var populate_route: bool = true

var _mats: Dictionary = {}


## When false, MainController builds the flora / fauna with build_progressive() under the loading screen.
@export var build_on_ready: bool = false

signal build_progress(fraction: float, label: String)


func _ready() -> void:
	if build_on_ready:
		_build.call_deferred()


func _build() -> void:
	if build_garden:
		_build_cliff_garden()
	if populate_route:
		_populate_prologue()
		_populate_hall()
		_populate_rampart_and_gallery()
		_populate_arena_and_summit()


## One section per frame with progress reporting (used by the loading screen).
func build_progressive() -> void:
	var steps: Array = []
	if build_garden:
		steps.append(["Growing the cliff garden", _build_cliff_garden])
	if populate_route:
		steps.append(["Seeding the approach", _populate_prologue])
		steps.append(["Seeding the Hall of Echoes", _populate_hall])
		steps.append(["Seeding the rampart", _populate_rampart_and_gallery])
		steps.append(["Seeding the arena", _populate_arena_and_summit])
	for i in range(steps.size()):
		build_progress.emit(float(i) / float(maxi(1, steps.size())), String((steps[i] as Array)[0]))
		await get_tree().process_frame
		((steps[i] as Array)[1] as Callable).call()
	build_progress.emit(1.0, "Flora in place")


# =====================================================================================================
# Cliff Garden
# =====================================================================================================

func _build_cliff_garden() -> void:
	var g := Node3D.new()
	g.name = "CliffGarden"
	add_child(g)
	# Rock massif under the terrace (top clamped flat just under the soil), plus collision for the soil.
	var rock_size := Vector3(15.0, 26.0, 28.0)
	var rock: ArrayMesh = ProcMesh.rock_mesh(rock_size, 4242, 0.18, 12, 0.9)
	_clamp_top(rock, rock_size.y * 0.5)
	_mesh(g, "GardenMassif", rock, _pbr("rock_face", 0.05, Color(0.92, 0.84, 0.76), {"blend_sharpness": 3.0, "macro_variation": 0.5, "rune_strength": 1.4}),
		Transform3D(Basis.IDENTITY, Vector3(GARDEN_CENTER.x, GARDEN_Y - 0.08 - rock_size.y * 0.5, GARDEN_CENTER.z)))
	var soil := _pbr("coast_sand_rocks_02", 0.16, Color(0.78, 0.82, 0.58), {"rune_strength": 0.8})
	_solid(g, "GardenSoil", Vector3(6.5, GARDEN_Y - 0.25, -33.0), Vector3(11.0, 0.5, 24.0), soil)
	_solid(g, "GardenSoilWedge", Vector3(-0.25, GARDEN_Y - 0.25, -33.0), Vector3(2.5, 0.5, 8.0), soil)
	# Low, broken castle-brick kerb along the open (east / north / south) edges: old garden walls.
	var brick := _pbr("castle_brick_07", 0.3, Color(0.95, 0.9, 0.85))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var kerb := [
		[Vector3(12.2, GARDEN_Y, -44.5), Vector3(12.2, GARDEN_Y, -21.5)],
		[Vector3(1.2, GARDEN_Y, -44.8), Vector3(12.2, GARDEN_Y, -44.8)],
		[Vector3(1.2, GARDEN_Y, -21.2), Vector3(12.2, GARDEN_Y, -21.2)],
	]
	for seg in kerb:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var n: int = int(a.distance_to(b) / 1.6)
		for i in range(n):
			if rng.randf() < 0.22:
				continue  # collapsed gaps
			var t0: float = float(i) / n
			var p: Vector3 = a.lerp(b, t0 + 0.5 / n)
			var h: float = rng.randf_range(0.45, 1.1)
			var bm := BoxMesh.new()
			bm.size = Vector3(1.5 if absf(a.x - b.x) > 0.1 else 0.55, h, 0.55 if absf(a.x - b.x) > 0.1 else 1.5)
			_mesh(g, "Kerb", bm, brick, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), p + Vector3.UP * h * 0.5))
	# Old fountain: marble basin, a broken column spout and still water (glows faintly in Mirror).
	var marble := _pbr("marble_01", 0.35, Color(1.0, 0.97, 0.93), {"roughness_bias": -0.1, "rune_strength": 1.6, "rune_threshold": 0.55})
	var fpos := Vector3(7.5, GARDEN_Y, -29.5)
	var basin := CylinderMesh.new()
	basin.top_radius = 1.5
	basin.bottom_radius = 1.65
	basin.height = 0.55
	basin.radial_segments = 24
	_mesh(g, "FountainBasin", basin, marble, Transform3D(Basis.IDENTITY, fpos + Vector3.UP * 0.275))
	_mesh(g, "FountainSpout", ProcMesh.column_mesh(0.22, 1.3, 10), marble, Transform3D(Basis.IDENTITY, fpos))
	var water := CylinderMesh.new()
	water.top_radius = 1.38
	water.bottom_radius = 1.38
	water.height = 0.02
	water.radial_segments = 24
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.18, 0.32, 0.36, 0.85)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.05
	wm.metallic_specular = 0.9
	wm.resource_name = "FountainWater"
	_mesh(g, "FountainWater", water, wm, Transform3D(Basis.IDENTITY, fpos + Vector3.UP * 0.5))
	RealmLook.apply(g.get_node("FountainWater"), "grass")
	# Cover / perch markers for the critters.
	for c in [Vector3(4.0, GARDEN_Y, -40.5), Vector3(10.5, GARDEN_Y, -26.5), Vector3(2.5, GARDEN_Y, -24.0)]:
		_marker(g, "fauna_cover", c)
	for c in [fpos + Vector3.UP * 1.35, Vector3(12.2, GARDEN_Y + 1.1, -36.0), Vector3(12.2, GARDEN_Y + 1.0, -27.0)]:
		_marker(g, "fauna_perch", c)

	# --- Plants (Reality look, luminous in Mirror; spirit growth only in Mirror) ---
	_veg(g, "GrassCarpet", Vector3(6.5, GARDEN_Y, -33.0), Vegetation.Kind.GRASS_CLUMP, [Vegetation.Kind.WISPY_GRASS, Vegetation.Kind.CLOVER], 34, 5.4, 0.8)
	_veg(g, "OliveGrove", Vector3(7.5, GARDEN_Y, -37.5), Vegetation.Kind.TREE_COMMON, [], 3, 4.0, 3.6)
	_veg(g, "Cypresses", Vector3(10.6, GARDEN_Y, -24.5), Vegetation.Kind.PINE, [], 3, 2.0, 2.2)
	_veg(g, "Meadow", Vector3(4.5, GARDEN_Y, -27.5), Vegetation.Kind.FLOWER_CLUMP, [Vegetation.Kind.CLOVER, Vegetation.Kind.GRASS_CLUMP], 18, 3.0, 0.55)
	_veg(g, "Hedges", Vector3(10.6, GARDEN_Y, -33.0), Vegetation.Kind.BUSH, [Vegetation.Kind.BUSH_FLOWERS, Vegetation.Kind.FERN], 8, 3.5, 1.1)
	_veg(g, "FernCorner", Vector3(3.2, GARDEN_Y, -41.5), Vegetation.Kind.FERN, [Vegetation.Kind.PLANT_BIG, Vegetation.Kind.MUSHROOM], 9, 1.8, 0.55)
	_veg(g, "Rocks", Vector3(6.0, GARDEN_Y, -33.0), Vegetation.Kind.GARDEN_ROCK, [], 4, 5.0, 2.5)
	_veg(g, "SpiritGrove", Vector3(6.0, GARDEN_Y, -34.0), Vegetation.Kind.SPIRIT_FERN, [Vegetation.Kind.CRYSTAL_MUSHROOM, Vegetation.Kind.SPIRIT_FERN, Vegetation.Kind.GHOST_PINE], 12, 4.5, 1.2)
	_flora(g, "GlowBlooms", fpos + Vector3(-2.2, 0, 1.0), AmbientFlora.Kind.GLOW_BLOOM, 6, 1.4, 0.45)
	_flora(g, "SporePods", Vector3(2.8, GARDEN_Y, -40.0), AmbientFlora.Kind.SPORE_POD, 4, 1.0, 0.4)

	# --- Animals ---
	_habitat(g, "Deer", Vector3(7.5, GARDEN_Y, -36.0), HABITAT.Species.DEER, 3, 3.0, HABITAT.GroupMode.ONE_GROUP, 1.3)
	_habitat(g, "Fox", Vector3(4.0, GARDEN_Y, -30.0), HABITAT.Species.FOX, 1, 3.0, HABITAT.GroupMode.ALL_LONERS, 1.4)
	_habitat(g, "Butterflies", Vector3(4.5, GARDEN_Y, -27.5), HABITAT.Species.BUTTERFLY, 6, 3.0, HABITAT.GroupMode.MIXED, 1.3)
	_habitat(g, "FountainDoves", fpos + Vector3(1.5, 0, 0), HABITAT.Species.PIGEON, 5, 2.0, HABITAT.GroupMode.ONE_GROUP, 1.6)
	_habitat(g, "RockLizards", Vector3(6.0, GARDEN_Y, -33.0), HABITAT.Species.SUN_LIZARD, 3, 4.0, HABITAT.GroupMode.ALL_LONERS, 1.0)
	_habitat(g, "GhostStags", Vector3(7.0, GARDEN_Y, -34.0), HABITAT.Species.SPECTRAL_STAG, 2, 3.0, HABITAT.GroupMode.ONE_GROUP, 1.2)
	_habitat(g, "Moths", Vector3(6.0, GARDEN_Y, -31.0), HABITAT.Species.MIRROR_MOTH, 5, 3.0, HABITAT.GroupMode.SMALL_GROUPS, 1.2)
	_habitat(g, "GardenWisps", Vector3(6.5, GARDEN_Y, -33.0), HABITAT.Species.SPIRIT_WISP, 4, 3.5, HABITAT.GroupMode.MIXED, 1.2)


# =====================================================================================================
# Route dressing (architectural spaces get architectural life)
# =====================================================================================================

func _populate_prologue() -> void:
	var z := Node3D.new()
	z.name = "Prologue"
	add_child(z)
	# Start terrace: dry grass at parapet feet, crows on the braziers.
	for p in [Vector3(-5.3, 0, -60.2), Vector3(5.3, 0, -60.2), Vector3(-5.4, 0, -52.0), Vector3(5.4, 0, -52.4)]:
		_veg(z, "ParapetGrass", p, Vegetation.Kind.WISPY_GRASS, [Vegetation.Kind.WISPY_GRASS_TALL], 5, 0.7, 0.3)
	_marker(z, "fauna_perch", Vector3(4.5, 1.7, -59.5))
	_marker(z, "fauna_perch", Vector3(-4.5, 1.7, -59.5))
	_habitat(z, "TerraceCrows", Vector3(2.5, 0, -57.0), HABITAT.Species.RUIN_CROW, 4, 2.5, HABITAT.GroupMode.ONE_GROUP, 1.6)
	# Overlook: wind-bent grass, a crow on the obelisk, Mirror spirit-ferns and the guiding spirit fox.
	for p in [Vector3(-11.0, 0, -36.0), Vector3(-11.0, 0, -30.0), Vector3(-3.0, 0, -36.0)]:
		_veg(z, "OverlookGrass", p, Vegetation.Kind.WISPY_GRASS_TALL, [Vegetation.Kind.WISPY_GRASS], 5, 0.7, 0.3)
	_veg(z, "OverlookSpiritFerns", Vector3(-10.0, 0, -32.5), Vegetation.Kind.SPIRIT_FERN, [Vegetation.Kind.CRYSTAL_MUSHROOM], 4, 1.0, 0.5)
	_marker(z, "fauna_perch", Vector3(-10.5, 6.6, -35.5))
	_habitat(z, "SpiritFox", Vector3(-6.5, 0, -33.0), HABITAT.Species.SPIRIT_FOX, 1, 2.0, HABITAT.GroupMode.ALL_LONERS, 6.0)
	_habitat(z, "OverlookWisps", Vector3(-8.0, 0, -33.0), HABITAT.Species.SPIRIT_WISP, 3, 2.0, HABITAT.GroupMode.ONE_GROUP, 2.0)
	# Gate forecourt: doves on the flagstones, lizards sunning by the braziers, grass in the corners.
	for p in [Vector3(-6.4, 0, -14.4), Vector3(6.4, 0, -14.4), Vector3(-6.4, 0, -5.6), Vector3(6.4, 0, -5.6)]:
		_veg(z, "CornerGrass", p, Vegetation.Kind.WISPY_GRASS, [Vegetation.Kind.GRASS_CLUMP], 4, 0.6, 0.3)
		_marker(z, "fauna_cover", p)
	_habitat(z, "ForecourtDoves", Vector3(2.5, 0, -11.0), HABITAT.Species.PIGEON, 6, 2.5, HABITAT.GroupMode.ONE_GROUP, 1.5)
	_habitat(z, "ForecourtLizards", Vector3(-4.5, 0, -8.0), HABITAT.Species.SUN_LIZARD, 2, 1.5, HABITAT.GroupMode.ALL_LONERS, 1.6)


func _populate_hall() -> void:
	var y: float = 4.0
	var z := Node3D.new()
	z.name = "HallOfEchoes"
	add_child(z)
	# Ivy creeping up the corners of the arcades (fighting floor stays clear).
	_ivy(z, Vector3(-9.6, y, 25.5), PI * 0.5, 2.2, 5.5, false)
	_ivy(z, Vector3(9.6, y, 42.5), -PI * 0.5, 2.2, 6.0, false)
	_ivy(z, Vector3(9.6, y, 25.5), -PI * 0.5, 1.6, 4.0, false)
	for p in [Vector3(-9.2, y, 24.8), Vector3(9.2, y, 24.8), Vector3(-9.2, y, 43.2), Vector3(9.2, y, 43.2)]:
		_veg(z, "CornerWeeds", p, Vegetation.Kind.WISPY_GRASS, [Vegetation.Kind.FERN, Vegetation.Kind.CLOVER], 5, 0.7, 0.28)
	for p in [Vector3(-8.2, y, 25.8), Vector3(8.2, y, 25.8), Vector3(-8.2, y, 42.2), Vector3(8.2, y, 42.2)]:
		_marker(z, "fauna_cover", p)
	_habitat(z, "HallRats", Vector3(8.0, y, 27.5), HABITAT.Species.RAT, 4, 1.5, HABITAT.GroupMode.ONE_GROUP, 1.5)
	_habitat(z, "HallDoves", Vector3(-6.5, y, 42.0), HABITAT.Species.PIGEON, 5, 1.8, HABITAT.GroupMode.ONE_GROUP, 2.0)
	_habitat(z, "HallMoths", Vector3(0.0, y, 30.0), HABITAT.Species.MIRROR_MOTH, 4, 3.0, HABITAT.GroupMode.SMALL_GROUPS, 1.5)


func _populate_rampart_and_gallery() -> void:
	var z := Node3D.new()
	z.name = "RampartAndGallery"
	add_child(z)
	# Windswept Rampart: ivy over the buttressed curtain wall, grass at the west balustrade, lizards.
	for wz in [50.0, 51.2, 57.0]:  # keep clear of the banner hanging at Z 53
		var yy: float = 4.0 + clampf((wz - 48.0) / 10.0, 0.0, 1.0) * 2.0
		_ivy(z, Vector3(2.5, yy, wz), -PI * 0.5, 2.2, 6.5, wz > 55.0)
		_veg(z, "RampartGrass", Vector3(-2.3, yy, wz - 1.5), Vegetation.Kind.WISPY_GRASS_TALL, [Vegetation.Kind.WISPY_GRASS], 4, 0.5, 0.25)
	# Storm zone (WeatherDirector 'storm'): no butterflies or basking lizards here — crows ride the wind.
	_marker(z, "fauna_perch", Vector3(3.6, 10.2, 49.0))
	_marker(z, "fauna_perch", Vector3(3.6, 10.6, 56.5))
	_habitat(z, "StormCrows", Vector3(0.5, 5.0, 53.0), HABITAT.Species.RUIN_CROW, 3, 2.0, HABITAT.GroupMode.ONE_GROUP, 2.0)
	# Aqueduct Gallery: ferns and grass at the colonnade bases, doves on the deck, rats by the rubble.
	for p in [Vector3(-3.0, 6, 62.5), Vector3(3.0, 6, 66.5), Vector3(-3.0, 6, 76.5), Vector3(3.0, 6, 81.0)]:
		_veg(z, "ColonnadeGrowth", p, Vegetation.Kind.WISPY_GRASS, [Vegetation.Kind.FERN, Vegetation.Kind.GRASS_CLUMP], 5, 0.6, 0.28)
	_habitat(z, "GalleryDoves", Vector3(0.0, 6, 64.0), HABITAT.Species.PIGEON, 4, 2.0, HABITAT.GroupMode.ONE_GROUP, 1.5)  # huddle under the colonnade in the storm
	_marker(z, "fauna_cover", Vector3(-2.6, 6, 78.0))
	_habitat(z, "GalleryRats", Vector3(1.5, 6, 78.5), HABITAT.Species.RAT, 3, 1.5, HABITAT.GroupMode.ONE_GROUP, 1.5)
	# Clock-tower chamber: wisps drifting under the oculus, rats in the corners.
	_habitat(z, "TowerWisps", Vector3(0.0, 6, 94.0), HABITAT.Species.SPIRIT_WISP, 3, 3.0, HABITAT.GroupMode.ONE_GROUP, 1.5)
	_marker(z, "fauna_cover", Vector3(-7.0, 6, 98.5))
	_habitat(z, "TowerRats", Vector3(-6.0, 6, 97.5), HABITAT.Species.RAT, 3, 1.2, HABITAT.GroupMode.ONE_GROUP, 1.5)


func _populate_arena_and_summit() -> void:
	var y: float = 10.0
	var z := Node3D.new()
	z.name = "ArenaAndSummit"
	add_child(z)
	# Processional esplanade: lizards on the warm flagstones, grass at the edges.
	for p in [Vector3(-4.2, y, 117.0), Vector3(4.2, y, 119.0)]:
		_veg(z, "EsplanadeGrass", p, Vegetation.Kind.WISPY_GRASS, [], 4, 0.5, 0.25)
	_habitat(z, "EsplanadeRats", Vector3(3.0, y, 118.0), HABITAT.Species.RAT, 3, 1.5, HABITAT.GroupMode.ONE_GROUP, 1.5)  # tempest zone
	# Mirror Colosseum: ivy on the podium wall, weeds at its foot, doves on the sand, crows in the stands.
	var c := Vector3(0.0, y, 154.0)
	for ang in [0.8, 2.35, 3.9, 5.5]:
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var pos: Vector3 = c + dir * 12.9
		_ivy(z, pos, atan2(dir.x, dir.z) + PI, 2.4, 3.0, false)
		_veg(z, "PodiumWeeds", c + dir * 12.6, Vegetation.Kind.WISPY_GRASS, [Vegetation.Kind.GRASS_CLUMP], 4, 0.6, 0.25)
	# Blood-rain arena: carrion crows on the sand and rats along the podium, not doves.
	_habitat(z, "ArenaCarrionCrows", c + Vector3(-7.0, 0, -3.0), HABITAT.Species.RUIN_CROW, 5, 2.5, HABITAT.GroupMode.ONE_GROUP, 1.6)
	_habitat(z, "ArenaRats", c + Vector3(-10.5, 0, 5.0), HABITAT.Species.RAT, 4, 1.5, HABITAT.GroupMode.ONE_GROUP, 1.5)
	for ang in [1.2, 2.0, 4.4]:
		_marker(z, "fauna_perch", c + Vector3(sin(ang), 0, cos(ang)) * 14.2 + Vector3.UP * 2.6)
	_habitat(z, "ArenaCrows", c + Vector3(8.0, 0, 6.0), HABITAT.Species.RUIN_CROW, 4, 2.5, HABITAT.GroupMode.ONE_GROUP, 1.6)
	_habitat(z, "ArenaWisps", c, HABITAT.Species.SPIRIT_WISP, 4, 6.0, HABITAT.GroupMode.MIXED, 1.2)
	# Sunset Summit: the reward — wildflowers, butterflies and lizards in the last light.
	_veg(z, "SummitMeadow", Vector3(-2.0, y, 195.0), Vegetation.Kind.FLOWER_CLUMP, [Vegetation.Kind.WISPY_GRASS, Vegetation.Kind.CLOVER, Vegetation.Kind.WISPY_GRASS_TALL], 18, 3.2, 0.5)
	_habitat(z, "SummitButterflies", Vector3(-1.0, y, 195.0), HABITAT.Species.BUTTERFLY, 5, 2.5, HABITAT.GroupMode.MIXED, 1.5)
	_habitat(z, "SummitLizards", Vector3(3.0, y, 192.0), HABITAT.Species.SUN_LIZARD, 2, 1.5, HABITAT.GroupMode.ALL_LONERS, 1.5)
	_veg(z, "SummitSpiritFerns", Vector3(2.5, y, 197.0), Vegetation.Kind.SPIRIT_FERN, [Vegetation.Kind.CRYSTAL_MUSHROOM], 5, 1.5, 0.5)


# =====================================================================================================
# Helpers
# =====================================================================================================

func _habitat(parent: Node3D, n: String, pos: Vector3, species: int, count: int, radius: float, mode: int, home_scale: float) -> Node3D:
	var h: Node3D = HABITAT.new() as Node3D
	h.name = n
	h.set("species", species)
	h.set("count", count)
	h.set("radius", radius)
	h.set("group_mode", mode)
	h.set("home_radius_scale", home_scale)
	parent.add_child(h)
	h.global_position = pos
	return h


func _veg(parent: Node3D, n: String, pos: Vector3, kind: int, mix: Array, count: int, radius: float, spacing: float) -> Node3D:
	var v: Node3D = VEG_PATCH.new() as Node3D
	v.name = n
	v.set("kind", kind)
	var typed: Array[Vegetation.Kind] = []
	for k in mix:
		typed.append(k)
	v.set("mix", typed)
	v.set("count", count)
	v.set("radius", radius)
	v.set("min_spacing", spacing)
	parent.add_child(v)
	v.global_position = pos
	return v


func _flora(parent: Node3D, n: String, pos: Vector3, kind: int, count: int, radius: float, spacing: float) -> Node3D:
	var f: Node3D = FLORA_PATCH.new() as Node3D
	f.name = n
	f.set("kind", kind)
	f.set("count", count)
	f.set("radius", radius)
	f.set("min_spacing", spacing)
	f.set("clump_size", 1)
	parent.add_child(f)
	f.global_position = pos
	return f


func _ivy(parent: Node3D, pos: Vector3, yaw: float, w: float, h: float, hanging: bool) -> Node3D:
	var iv: Node3D = IVY.new() as Node3D
	iv.set("width", w)
	iv.set("height", h)
	iv.set("hanging", hanging)
	iv.set("strands", int(clampf(w * 3.0, 4.0, 12.0)))
	parent.add_child(iv)
	iv.global_position = pos
	iv.rotation.y = yaw
	return iv


func _marker(parent: Node3D, group: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = group.capitalize().replace(" ", "")
	parent.add_child(m)
	m.global_position = pos
	m.add_to_group(group)


func _pbr(id: String, tile: float, tint: Color, extra: Dictionary = {}) -> ShaderMaterial:
	var key: String = "%s|%.3f|%s" % [id, tile, tint.to_html()]
	if _mats.has(key):
		return _mats[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	if ResourceLoader.exists(REALM_PBR_SHADER):
		m.shader = load(REALM_PBR_SHADER) as Shader
	var base: String = PBR_DIR + id + "/" + id
	if ResourceLoader.exists(base + "_diff_2k.jpg"):
		m.set_shader_parameter("albedo_tex", load(base + "_diff_2k.jpg"))
		m.set_shader_parameter("normal_tex", load(base + "_nor_gl_2k.jpg"))
		m.set_shader_parameter("arm_tex", load(base + "_arm_2k.jpg"))
	m.set_shader_parameter("tile_scale", tile)
	m.set_shader_parameter("tint", tint)
	for k in extra:
		m.set_shader_parameter(String(k), extra[k])
	_mats[key] = m
	return m


func _solid(parent: Node3D, n: String, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = LAYER_WORLD_SHARED
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	parent.add_child(body)
	body.global_position = pos
	return body


func _mesh(parent: Node3D, n: String, mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.global_transform = xf
	return mi


func _clamp_top(mesh: ArrayMesh, max_y: float) -> void:
	if mesh.get_surface_count() == 0:
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(v.size()):
		if v[i].y > max_y:
			v[i].y = max_y
	arrays[Mesh.ARRAY_VERTEX] = v
	var mat: Material = mesh.surface_get_material(0)
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mat != null:
		mesh.surface_set_material(0, mat)
