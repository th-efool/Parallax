class_name FaunaDirector
extends Node
## Lazy singleton "ecosystem" shared by all ambient creatures and flora (never an autoload).
##  - Registry + cheap spatial queries (flockmates, nearest creature of a species).
##  - Disturbances: world events with a position, radius and strength (sword swings, slams, deaths,
##    realm shifts). It hooks the player / enemies by itself, so gameplay scripts need no changes.
##  - Points of interest: fresh death sites (souls for wisps, scraps for scavengers).
##  - Play matchmaking: lets a mischievous creature pick a playmate for poke-and-chase games.
##  - Light budget so dozens of wisps never spawn dozens of OmniLights.

signal disturbance(pos: Vector3, radius: float, strength: float, kind: String)
signal realm_shifted(new_realm: int)

const MAX_LIGHTS: int = 10
const DISTURBANCE_TTL: float = 1.2

static var _instance: Node = null

var creatures: Array[Node] = []
var flora: Array[Node] = []
var _disturbances: Array[Dictionary] = []  # {pos, radius, strength, kind, t}
var _interest: Array[Dictionary] = []      # {pos, kind, t, ttl}
var _lights_in_use: int = 0
var _bound: Dictionary = {}
var _scan_timer: float = 0.0
var _player: Node3D = null


static func get_for(context: Node) -> FaunaDirector:
	if _instance != null and is_instance_valid(_instance):
		return _instance as FaunaDirector
	if context == null or not context.is_inside_tree():
		return null
	var fd: FaunaDirector = (load("res://scripts/ambient/fauna_director.gd") as GDScript).new() as FaunaDirector
	fd.name = "FaunaDirector"
	context.get_tree().root.add_child.call_deferred(fd)
	_instance = fd
	return fd


static func now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	var kit: GDScript = load("res://scripts/ambient/fauna_mesh_kit.gd") as GDScript
	if kit != null:
		kit.call("clear_caches")


func _ready() -> void:
	if RealmManager.instance != null and not RealmManager.instance.realm_changed.is_connected(_on_realm_changed):
		RealmManager.instance.realm_changed.connect(_on_realm_changed)


func register_creature(c: Node) -> void:
	if not creatures.has(c):
		creatures.append(c)


func unregister_creature(c: Node) -> void:
	creatures.erase(c)


func register_flora(f: Node) -> void:
	if not flora.has(f):
		flora.append(f)


func unregister_flora(f: Node) -> void:
	flora.erase(f)


func get_player() -> Node3D:
	if is_instance_valid(_player):
		return _player
	if is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


# ------------------------------------------------------------------ light budget

func acquire_light() -> bool:
	if _lights_in_use >= MAX_LIGHTS:
		return false
	_lights_in_use += 1
	return true


func release_light() -> void:
	_lights_in_use = maxi(0, _lights_in_use - 1)


# ------------------------------------------------------------------ disturbances & interest

## Anything can call this: "something loud / scary happened here".
func emit_disturbance(pos: Vector3, radius: float, strength: float, kind: String = "noise") -> void:
	_disturbances.append({"pos": pos, "radius": radius, "strength": strength, "kind": kind, "t": now()})
	disturbance.emit(pos, radius, strength, kind)


## Strongest active disturbance felt at `pos` (0..1+), with its kind and source position.
func sample_disturbance(pos: Vector3) -> Dictionary:
	var best: Dictionary = {"strength": 0.0, "pos": pos, "kind": ""}
	var t: float = now()
	for d in _disturbances:
		var age: float = t - float(d["t"])
		var dist: float = pos.distance_to(d["pos"] as Vector3)
		var r: float = float(d["radius"])
		if dist > r:
			continue
		var s: float = float(d["strength"]) * (1.0 - dist / r) * clampf(1.0 - age / DISTURBANCE_TTL, 0.0, 1.0)
		if s > float(best["strength"]):
			best = {"strength": s, "pos": d["pos"], "kind": d["kind"]}
	return best


func add_interest(pos: Vector3, kind: String, ttl: float) -> void:
	_interest.append({"pos": pos, "kind": kind, "t": now(), "ttl": ttl})


## Nearest live point of interest of `kind` within `radius`; returns {} when none.
func nearest_interest(pos: Vector3, kind: String, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = radius
	var t: float = now()
	for p in _interest:
		if String(p["kind"]) != kind or t - float(p["t"]) > float(p["ttl"]):
			continue
		var d: float = pos.distance_to(p["pos"] as Vector3)
		if d < best_d:
			best_d = d
			best = p
	return best


# ------------------------------------------------------------------ social queries

func flockmates(c: Node3D, species: String, radius: float, group_id: int = -1) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var r2: float = radius * radius
	for o in creatures:
		if o == c or not is_instance_valid(o):
			continue
		var oc: Node3D = o as Node3D
		if String(o.get("species")) != species:
			continue
		if group_id >= 0 and int(o.get("group_id")) != group_id:
			continue
		if not bool(o.get("is_present")):
			continue
		if oc.global_position.distance_squared_to(c.global_position) <= r2:
			out.append(oc)
	return out


## Picks a free playmate for a game of poke-and-chase. Returns null when nobody wants to play.
func find_playmate(c: Node3D, species: String, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = radius
	for o in flockmates(c, species, radius, int(c.get("group_id"))):
		if not o.has_method("can_play") or not bool(o.call("can_play")):
			continue
		var d: float = o.global_position.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = o
	return best


# ------------------------------------------------------------------ auto hooks

func _process(delta: float) -> void:
	var t: float = now()
	var i: int = _disturbances.size() - 1
	while i >= 0:
		if t - float(_disturbances[i]["t"]) > DISTURBANCE_TTL:
			_disturbances.remove_at(i)
		i -= 1
	i = _interest.size() - 1
	while i >= 0:
		if t - float(_interest[i]["t"]) > float(_interest[i]["ttl"]):
			_interest.remove_at(i)
		i -= 1
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 1.0
		_bind_world()
	_ambient_player_presence()


## The player is a walking disturbance: louder when sprinting, rolling or attacking.
func _ambient_player_presence() -> void:
	var p: Node3D = get_player()
	if p == null or not p.is_inside_tree():
		return
	var v: Vector3 = (p as CharacterBody3D).velocity if p is CharacterBody3D else Vector3.ZERO
	var speed: float = Vector2(v.x, v.z).length()
	if speed > 6.4:
		emit_disturbance(p.global_position, 4.5, 0.35, "footsteps")


func _bind_world() -> void:
	if not is_inside_tree():
		return
	var p: Node = get_player()
	if p != null and not _bound.has(p.get_instance_id()):
		_bound[p.get_instance_id()] = true
		if p.has_signal("attack_executed"):
			p.connect("attack_executed", _on_player_attack.bind(p))
		if p.has_signal("landing_slam_triggered"):
			p.connect("landing_slam_triggered", _on_player_slam)
		if p.has_signal("dodge_started"):
			p.connect("dodge_started", _on_player_dodge.bind(p))
		if p.has_signal("player_damaged"):
			p.connect("player_damaged", _on_player_hurt.bind(p))
	for e in get_tree().get_nodes_in_group("enemy"):
		if _bound.has(e.get_instance_id()):
			continue
		_bound[e.get_instance_id()] = true
		if e.has_signal("died"):
			e.connect("died", _on_enemy_died)
		if e.has_signal("attack_started"):
			e.connect("attack_started", _on_enemy_attack.bind(e))
	if RealmManager.instance != null and not RealmManager.instance.realm_changed.is_connected(_on_realm_changed):
		RealmManager.instance.realm_changed.connect(_on_realm_changed)


func _on_player_attack(_n: String, _s: int, _d: int, heavy: bool, p: Node3D) -> void:
	if is_instance_valid(p):
		emit_disturbance(p.global_position, 9.0 if heavy else 6.0, 0.9 if heavy else 0.6, "swing")


func _on_player_slam(pos: Vector3, radius: float, _dmg: int) -> void:
	emit_disturbance(pos, radius * 5.0, 1.4, "slam")


func _on_player_dodge(_dir: Vector3, _dur: float, p: Node3D) -> void:
	if is_instance_valid(p):
		emit_disturbance(p.global_position, 3.5, 0.4, "footsteps")


func _on_player_hurt(_amount: int, p: Node3D) -> void:
	if is_instance_valid(p):
		emit_disturbance(p.global_position, 7.0, 0.8, "fight")


func _on_enemy_attack(_n: String, _d: int, e: Node3D) -> void:
	if is_instance_valid(e):
		emit_disturbance(e.global_position, 6.0, 0.6, "fight")


func _on_enemy_died(enemy: Node, _ctx: Dictionary) -> void:
	if not (enemy is Node3D):
		return
	var pos: Vector3 = (enemy as Node3D).global_position
	emit_disturbance(pos, 11.0, 1.1, "death")
	# Once the noise settles: a lingering "soul" for wisps and scraps for scavengers.
	add_interest(pos + Vector3.UP * 1.0, "soul", 14.0)
	add_interest(pos, "scraps", 22.0)


func _on_realm_changed(new_realm: int) -> void:
	realm_shifted.emit(new_realm)
	var p: Node3D = get_player()
	if p != null:
		emit_disturbance(p.global_position, 14.0, 0.5, "shift")
