class_name ModelCreature
extends AmbientCreature
## Ambient animal driven by an imported, animated CC0 Quaternius model (assets/models/fauna/quaternius).
## One script, many species: pick `species_key`. Each species has a role that adds behaviours on top of
## the AmbientCreature brain, and a realm rule (Reality-only, Mirror-only spirit, or both with a
## Mirror look supplied by RealmLook).
##
## Roles
##   grazer      — herd animal: grazes (head down) with nervous head-up glances, freezes "alert" and
##                 stares at a threat before bolting in a gallop; herd panic spreads.   (deer, stag, alpaca)
##   predator    — stalks smaller critters low and slow, then dashes and pounces (always misses —
##                 nothing dies), sits and licks its pride afterwards; follows the player when curious. (fox)
##   scavenger   — forages, raids post-fight scraps, mischievous thief energy.          (raccoon)
##   skitter     — tiny ground runner: bursts, freezes, bolts from predators.           (rat)
##   ground_bird — pecks and struts in flocks; startled, the flock bursts into hop-flights. (unused — doves are procedural RuinCrow)
##   spirit      — Mirror-only ghost: curious and calm, keeps its distance, *dissolves into motes* if
##                 you rush it and re-forms elsewhere; the spirit fox runs ahead of the player and
##                 waits, like a guide.                                                  (spectral_stag, spirit_fox)

const GameFeelScript := preload("res://scripts/core/game_feel.gd")
const KitScript := preload("res://scripts/ambient/fauna_mesh_kit.gd")
const BASE: String = "res://assets/models/fauna/quaternius/"

const SPECIES: Dictionary = {
	"deer": {"model": "deer.glb", "height": 1.2, "walk": 1.3, "run": 6.8, "role": "grazer", "presence": 1, "look": "fur",
		"traits": {"bold": 0.18, "curiosity": 0.35, "sociability": 0.85, "mischief": 0.1, "energy": 0.45}},
	"stag": {"model": "stag.glb", "height": 1.55, "walk": 1.3, "run": 6.5, "role": "grazer", "presence": 1, "look": "fur",
		"traits": {"bold": 0.45, "curiosity": 0.4, "sociability": 0.7, "mischief": 0.35, "energy": 0.45}},
	"alpaca": {"model": "alpaca.glb", "height": 1.45, "walk": 1.1, "run": 4.8, "role": "grazer", "presence": 0, "look": "fur",
		"traits": {"bold": 0.55, "curiosity": 0.75, "sociability": 0.75, "mischief": 0.5, "energy": 0.35}},
	"fox": {"model": "fox.glb", "height": 0.55, "walk": 1.4, "run": 6.2, "role": "predator", "presence": 1, "look": "fur",
		"hunts": ["rat", "dove", "scurrier"],
		"traits": {"bold": 0.55, "curiosity": 0.75, "sociability": 0.2, "mischief": 0.65, "energy": 0.65}},
	"raccoon": {"model": "raccoon.glb", "height": 0.42, "walk": 1.0, "run": 3.8, "role": "scavenger", "presence": 0, "look": "fur",
		"traits": {"bold": 0.45, "curiosity": 0.65, "sociability": 0.4, "mischief": 0.85, "energy": 0.55}},
	"rat": {"model": "rat.glb", "height": 0.17, "walk": 0.9, "run": 3.6, "role": "skitter", "presence": 0, "look": "fur",
		"traits": {"bold": 0.2, "curiosity": 0.5, "sociability": 0.6, "mischief": 0.45, "energy": 0.75}},
	"spectral_stag": {"model": "stag.glb", "height": 1.7, "walk": 0.9, "run": 5.0, "role": "spirit", "presence": 2, "look": "spectral",
		"traits": {"bold": 0.7, "curiosity": 0.75, "sociability": 0.5, "mischief": 0.1, "energy": 0.3}},
	"spirit_fox": {"model": "fox.glb", "height": 0.6, "walk": 1.6, "run": 6.0, "role": "spirit", "presence": 2, "look": "spectral", "guide": true,
		"traits": {"bold": 0.75, "curiosity": 0.9, "sociability": 0.3, "mischief": 0.6, "energy": 0.7}},
}

const CLIPS: Dictionary = {
	"idle": ["Idle", "Rat_Idle", "Idle_2"],
	"graze": ["Eating", "Idle_Eating", "Idle_Headlow", "Idle_2_HeadLow"],
	"look": ["Idle_2", "Idle"],
	"walk": ["Walk", "Rat_Walk"],
	"run": ["Gallop", "Run", "Rat_Run", "Walk"],
	"jump": ["Gallop_Jump", "Jump_Loop", "Rat_Jump", "Jump", "Jump_ToIdle", "Jump_toIdle"],
	"attack": ["Attack_Headbutt", "Attack", "Headbutt", "Bite_Front", "Rat_Attack"],
	"kick": ["Attack_Kick", "Attack_Headbutt", "Attack"],
	"hit": ["Idle_HitReact_Left", "Idle_HitReact_Right", "HitRecieve"],
	"dance": ["Dance", "Yes"],
}

static var _scene_cache: Dictionary = {}


static func clear_caches() -> void:
	_scene_cache.clear()

@export_enum("deer", "stag", "alpaca", "fox", "raccoon", "rat", "spectral_stag", "spirit_fox") var species_key: String = "deer"
## Model faces +Z in most Quaternius exports; rotate so it faces the creature's -Z (Godot forward).
@export var model_yaw_offset: float = PI
## Override the species realm rule (-1 = species default, 0 both, 1 Reality-only, 2 Mirror-only).
@export var presence_override: int = -1

var role: String = "grazer"
var _spec: Dictionary = {}
var _model: Node3D = null
var _ap: AnimationPlayer = null
var _clip_map: Dictionary = {}
var _cur_clip: String = ""
var _oneshot_until: float = 0.0
var _walk_speed: float = 1.2
var _run_speed: float = 5.0
var _glance_t: float = 0.0
var _prey: Node3D = null
var _pounce_t: float = 0.0
var _hop_v: float = 0.0
var _hop_y: float = 0.0
var _guide_spot: Vector3 = Vector3.ZERO
var _fade_t: float = -1.0
var _is_spectral: bool = false
var _sound_cd: float = 0.0


func _configure() -> void:
	_spec = SPECIES.get(species_key, SPECIES["deer"])
	species = species_key
	role = String(_spec["role"])
	hunts = _spec.get("hunts", [])
	_walk_speed = float(_spec["walk"])
	_run_speed = float(_spec["run"])
	max_speed = _run_speed
	accel = _run_speed * 2.2
	turn_speed = 5.0 if float(_spec["height"]) > 1.0 else 10.0
	flies = false
	var pres: int = int(_spec["presence"]) if presence_override < 0 else presence_override
	realm_presence = pres as RealmPresence
	_is_spectral = String(_spec["look"]) == "spectral"
	lod_distance = 25.0 + float(_spec["height"]) * 40.0
	if role == "grazer" or role == "spirit":
		home_radius = maxf(home_radius, 10.0)


func _species_traits() -> Dictionary:
	return _spec.get("traits", super._species_traits())


func _build_body(root: Node3D) -> void:
	var path: String = BASE + String(_spec["model"])
	var ps: PackedScene = _scene_cache.get(path, null) as PackedScene
	if ps == null and ResourceLoader.exists(path):
		ps = load(path) as PackedScene
		_scene_cache[path] = ps
	if ps == null:
		KitScript.part(root, KitScript.box(Vector3(0.3, 0.3, 0.5)), KitScript.mat(Color.MAGENTA), Vector3(0, 0.15, 0))
		return
	_model = ps.instantiate() as Node3D
	_model.name = "Model"
	root.add_child(_model)
	_model.rotation.y = model_yaw_offset
	_normalize_height(float(_spec["height"]) * randf_range(0.9, 1.1))
	_ap = _find_ap(_model)
	_build_clip_map()
	if _is_spectral:
		RealmLook.apply_spectral(_model, Color(0.35, 0.85, 1.0) if species_key == "spectral_stag" else Color(0.75, 0.55, 1.0))
		var glow := MeshInstance3D.new()
		glow.mesh = KitScript.glow_billboard(Color(0.45, 0.8, 1.0, 0.5), float(_spec["height"]) * 1.4, 0.6)
		glow.position = Vector3.UP * float(_spec["height"]) * 0.55
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(glow)
	else:
		RealmLook.apply(_model, String(_spec["look"]))
	_play("idle", 1.0)


func _normalize_height(target_h: float) -> void:
	var aabb := AABB()
	var first: bool = true
	var inv: Transform3D = _model.global_transform.affine_inverse() if _model.is_inside_tree() else Transform3D.IDENTITY
	for mi in RealmLook._meshes(_model):
		var local_xf: Transform3D = inv * mi.global_transform if mi.is_inside_tree() else mi.transform
		var b: AABB = local_xf * mi.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if first or aabb.size.y < 0.0001:
		return
	var k: float = target_h / aabb.size.y
	_model.scale = Vector3.ONE * k
	_model.position.y = -aabb.position.y * k


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f: AnimationPlayer = _find_ap(c)
		if f != null:
			return f
	return null


## Map logical clip names to the model's real animation names (handles "Armature|Name" prefixes).
func _build_clip_map() -> void:
	if _ap == null:
		return
	var short: Dictionary = {}
	for full in _ap.get_animation_list():
		var s: String = String(full)
		var bare: String = s.get_slice("|", s.get_slice_count("|") - 1)
		if not short.has(bare) or s.length() < String(short[bare]).length():
			short[bare] = s
	for logical in CLIPS.keys():
		for cand in CLIPS[logical]:
			if short.has(cand):
				_clip_map[logical] = short[cand]
				break
	for loop_name in ["idle", "graze", "look", "walk", "run"]:
		if _clip_map.has(loop_name):
			var a: Animation = _ap.get_animation(_clip_map[loop_name])
			if a != null:
				a.loop_mode = Animation.LOOP_LINEAR


func _play(logical: String, speed: float = 1.0, oneshot: bool = false) -> void:
	if _ap == null or not _clip_map.has(logical):
		return
	if FaunaDirector.now() < _oneshot_until and not oneshot:
		return
	var clip: String = _clip_map[logical]
	_ap.speed_scale = speed
	if clip == _cur_clip and not oneshot:
		return
	_cur_clip = clip
	_ap.play(clip, 0.2 if not oneshot else 0.1)
	if oneshot:
		_ap.seek(0.0, true)
		var a: Animation = _ap.get_animation(clip)
		_oneshot_until = FaunaDirector.now() + (a.length / maxf(0.1, speed) if a != null else 0.6)


# ------------------------------------------------------------------ perception tweaks

func _disturbance_sensitivity(kind: String) -> float:
	if role == "spirit":
		return 0.25 if kind != "shift" else 0.0
	if role == "scavenger" and kind == "death":
		return 0.4
	if role == "grazer" and kind in ["swing", "slam", "footsteps"]:
		return 1.4
	return 1.0


# ------------------------------------------------------------------ scoring

func _score_extra(s: Dictionary) -> void:
	_sound_cd = maxf(0.0, _sound_cd - 1.0 / think_hz)
	if _fade_t >= 0.0:
		s.clear()
		s["fade"] = 2.0
		return
	match role:
		"grazer":
			s["graze"] = 0.42 + (1.0 - trait_value("energy")) * 0.3
			if fear > 0.18 and fear < 0.55:
				s["alert"] = 0.55 + fear  # freeze and stare first...
			if behaviour == "alert" and behaviour_time > 0.9 + trait_value("bold") * 1.2 and fear > 0.35:
				s["flee"] = 1.4  # ...then bolt
			# Mischievous alpacas kick at whoever sneaks up behind them.
			if species_key == "alpaca":
				var p: Node3D = get_player()
				if p != null and trait_value("mischief") > 0.4:
					var rel: Vector3 = p.global_position - global_position
					var behind: bool = rel.normalized().dot(-global_transform.basis.z) < -0.3
					if rel.length() < 1.7 and behind and FaunaDirector.now() > _oneshot_until:
						s["kick"] = 1.5
		"predator":
			if fear < 0.4:
				var prey: Node3D = _find_prey(9.0)
				if prey != null and trait_value("energy") > 0.3:
					s["hunt"] = 0.6 + trait_value("energy") * 0.25
					if behaviour != "hunt":
						_prey = prey
			s["sit"] = 0.25 + (1.0 - trait_value("energy")) * 0.25
			_score_scraps(s, 0.5)
		"scavenger":
			s["forage"] = 0.4 + trait_value("curiosity") * 0.2
			_score_scraps(s, 0.75)
		"skitter":
			s["forage"] = 0.35
			if fear > 0.25:
				s["flee"] = fear * 1.5
			_score_scraps(s, 0.5)
		"ground_bird":
			s["forage"] = 0.45 + trait_value("sociability") * 0.1
			if fear > 0.35:
				s["flight"] = fear * 1.5
				s.erase("flee")
			if behaviour == "flight":
				s["flight"] = 1.2 if (_hop_y > 0.02 or behaviour_time < 0.6) else float(s.get("flight", 0.0))
			_score_scraps(s, 0.45)
		"spirit":
			s.erase("flee")
			s["drift"] = 0.4
			var p2: Node3D = get_player()
			if p2 != null:
				var d: float = p2.global_position.distance_to(global_position)
				if d < 2.2 and _player_speed(p2) > 2.0:
					s["fade"] = 1.6
				if bool(_spec.get("guide", false)) and d < 14.0 and d > 2.5:
					s["guide"] = 0.7
			if behaviour in ["guide", "drift"] and behaviour_time > 12.0:
				s[behaviour] = 0.1


func _score_scraps(s: Dictionary, w: float) -> void:
	if _director == null or fear > 0.3 or trait_value("bold") < 0.3:
		return
	var scraps: Dictionary = _director.nearest_interest(global_position, "scraps", 14.0)
	if not scraps.is_empty():
		s["scavenge"] = w + trait_value("bold") * 0.2
		if behaviour != "scavenge":
			focus_pos = (scraps["pos"] as Vector3) + Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.7, 0.7))


func _find_prey(radius: float) -> Node3D:
	if _director == null:
		return null
	var best: Node3D = null
	var best_d: float = radius
	for c in _director.creatures:
		if not is_instance_valid(c) or not bool(c.get("is_present")):
			continue
		if not hunts.has(String(c.get("species"))):
			continue
		var d: float = (c as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = c as Node3D
	return best


func _on_behaviour_entered(b: String) -> void:
	match b:
		"alert":
			_play("look", 1.0)
			_sound("chirp" if role == "ground_bird" else "", -22.0)
		"kick":
			_play("kick", 1.2, true)
			if _director != null:
				_director.emit_disturbance(global_position, 3.0, 0.4, "noise")
		"hunt":
			_pounce_t = 0.0
		"flight":
			_hop_v = randf_range(3.5, 5.0)
			_sound("flutter", -14.0)
		"fade":
			_fade_t = 0.0
			_burst_motes()
		"guide":
			_guide_spot = _pick_guide_spot()


# ------------------------------------------------------------------ acting

func _act_extra(b: String, delta: float) -> Variant:
	match b:
		"graze", "forage", "sit":
			if role in ["skitter", "ground_bird", "scavenger"] and randf() < delta * 0.6:
				return wander(_walk_speed * 0.8, delta) * 3.0  # short shuffle to a new patch
			return Vector3.ZERO
		"alert":
			return Vector3.ZERO
		"kick":
			return Vector3.ZERO
		"flee":
			var v: Vector3 = flee_from(fear_source, _run_speed * (0.8 + fear * 0.3))
			return v
		"wander":
			return wander(_walk_speed, delta)
		"flock":
			return flock(delta).limit_length(_walk_speed * 1.1)
		"return":
			return steer_to(home, _walk_speed * 1.2, 1.0)
		"curious":
			if not is_instance_valid(focus):
				return Vector3.ZERO
			var keep: float = 2.2 + (1.0 - trait_value("bold")) * 2.0 + float(_spec["height"])
			var d: float = focus.global_position.distance_to(global_position)
			if d > keep + 0.6:
				return steer_to(focus.global_position, _walk_speed, 1.0)
			return Vector3.ZERO  # stand and watch
		"scavenge":
			if Vector2(focus_pos.x - global_position.x, focus_pos.z - global_position.z).length() < 0.4:
				return Vector3.ZERO
			return steer_to(focus_pos, _walk_speed * 1.4, 0.5)
		"hunt":
			return _act_hunt(delta)
		"flight":
			return _act_flight(delta)
		"drift":
			return wander(_walk_speed * 0.6, delta)
		"guide":
			var to: Vector3 = _guide_spot - global_position
			to.y = 0.0
			if to.length() < 0.5:
				return Vector3.ZERO  # sit and look back at the player
			return to.normalized() * _run_speed * 0.6
		"fade":
			return Vector3.ZERO
	return null


func _act_hunt(delta: float) -> Vector3:
	if not is_instance_valid(_prey):
		set_behaviour("sit")
		return Vector3.ZERO
	var to: Vector3 = _prey.global_position - global_position
	to.y = 0.0
	var d: float = to.length()
	_pounce_t += delta
	if d < 1.4 and _pounce_t > 0.4:
		# Pounce! (always comes up empty — prey has already bolted)
		_play("jump", 1.1, true)
		_sound("squeak", -16.0)
		if _director != null:
			_director.emit_disturbance(_prey.global_position, 4.0, 0.9, "noise")
		_prey = null
		set_behaviour("sit")
		return to.normalized() * _run_speed * 0.8
	if d > 3.5:
		return to.normalized() * _walk_speed * 0.55  # low, slow stalk
	return to.normalized() * _run_speed  # dash


func _act_flight(delta: float) -> Vector3:
	# Chained hop-flights: a burst up and away, a glide down, and again while still scared.
	_hop_v -= 9.0 * delta
	_hop_y = maxf(0.0, _hop_y + _hop_v * delta)
	if _hop_y <= 0.0 and _hop_v < 0.0:
		_hop_v = randf_range(3.5, 5.0) if fear > 0.3 else 0.0
	var away: Vector3 = flee_from(fear_source, _run_speed * 1.4)
	return away


func _pick_guide_spot() -> Vector3:
	var p: Node3D = get_player()
	if p == null:
		return global_position
	var f: Vector3 = Vector3.FORWARD
	if p.has_method("get_facing_direction"):
		f = p.call("get_facing_direction")
	var spot: Vector3 = p.global_position + f * randf_range(4.5, 6.5) + Vector3(f.z, 0.0, -f.x) * randf_range(-1.5, 1.5)
	# Stay on solid ground.
	var w: World3D = get_world_3d()
	if w != null:
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 4.0, WORLD_MASK)
		if w.direct_space_state.intersect_ray(q).is_empty():
			return global_position
	return spot


func _process(delta: float) -> void:
	super._process(delta)
	if not is_present:
		return
	if _fade_t >= 0.0:
		_process_fade(delta)
	if behaviour == "guide" and Vector2(_guide_spot.x - global_position.x, _guide_spot.z - global_position.z).length() < 0.5:
		var p: Node3D = get_player()
		if p != null and p.global_position.distance_to(global_position) < 2.5:
			_guide_spot = _pick_guide_spot()


func _post_move(delta: float) -> void:
	super._post_move(delta)
	if _hop_y > 0.0:
		global_position.y = _ground_y + ground_offset + _hop_y


func _process_fade(delta: float) -> void:
	_fade_t += delta
	if _body == null:
		return
	if _fade_t < 0.45:
		_body.scale = Vector3.ONE * maxf(0.01, 1.0 - _fade_t / 0.45)
	elif _fade_t < 2.5:
		_body.visible = false
		if _fade_t - delta < 0.45:
			# Re-form somewhere else around home, away from the player.
			var a: float = randf() * TAU
			global_position = home + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, home_radius * 0.8)
			_probe_ground()
			global_position.y = _ground_y
	else:
		_body.visible = true
		_body.scale = Vector3.ONE * minf(1.0, (_fade_t - 2.5) / 0.6)
		if _fade_t > 3.1:
			_body.scale = Vector3.ONE
			_fade_t = -1.0
			fear = 0.0
			_burst_motes()
			set_behaviour("drift")


func _burst_motes() -> void:
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 30
	p.lifetime = 1.4
	p.local_coords = false
	p.mesh = KitScript.glow_billboard(Color(0.5, 0.85, 1.0, 0.8), 0.1, 1.6)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = float(_spec["height"]) * 0.45
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0.0, 0.4, 0.0)
	host.add_child(p)
	p.global_position = global_position + Vector3.UP * float(_spec["height"]) * 0.5
	p.emitting = true
	get_tree().create_timer(1.8, false).timeout.connect(p.queue_free)
	_sound("chime", -18.0)


func _on_play_event(kind: String) -> void:
	if kind == "poke":
		_play("attack", 1.1, true)  # stags butt heads, foxes nip
	elif kind == "poked":
		_play("hit", 1.0, true)


func _sound(key: String, db: float) -> void:
	if key.is_empty() or _sound_cd > 0.0:
		return
	_sound_cd = 2.0
	GameFeelScript.play_sound(self, key, global_position, db, randf_range(0.85, 1.15))


# ------------------------------------------------------------------ animation

func _animate(_delta: float) -> void:
	if _ap == null:
		return
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if FaunaDirector.now() < _oneshot_until:
		return
	match behaviour:
		"graze", "forage", "scavenge":
			if speed > 0.25:
				_play("walk", clampf(speed / maxf(0.2, _walk_speed), 0.6, 1.6))
			else:
				# Nervous glances between mouthfuls.
				_glance_t -= _delta
				if _glance_t <= 0.0:
					_glance_t = randf_range(2.0, 6.0) * (0.6 + trait_value("bold"))
					_play("look", 1.0)
				elif _glance_t < 1.2:
					_play("look", 1.0)
				else:
					_play("graze", 1.0)
		"alert", "sit", "kick", "fade":
			_play("look" if behaviour == "alert" else "idle", 1.0)
		"flight":
			_play("jump", 1.2)
		_:
			if speed < 0.15:
				_play("idle", 1.0)
			elif speed < _walk_speed * 1.6:
				_play("walk", clampf(speed / maxf(0.2, _walk_speed), 0.6, 1.8))
			else:
				_play("run", clampf(speed / maxf(0.5, _run_speed), 0.7, 1.5))

func _realm_look_profile() -> String:
	return ""  # applied to the imported model in _build_body
