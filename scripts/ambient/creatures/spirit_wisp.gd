class_name SpiritWisp
extends AmbientCreature
## Floating spirit light. Drifts in loose flocks (or alone), circles the player at head height when
## curious and darts in for a "peek", plays tag with siblings, dims and shoots skyward when frightened,
## hovers over glow-blooms, and — after a death — gathers in a slow rising spiral over the fallen
## ("soul gathering") before dispersing. Flares and scatters on every realm shift; brighter in Mirror.

const KitScript := preload("res://scripts/ambient/fauna_mesh_kit.gd")
const GameFeelScript := preload("res://scripts/core/game_feel.gd")

@export var reality_color: Color = Color(1.0, 0.72, 0.38)
@export var mirror_color: Color = Color(0.45, 0.85, 1.0)
@export var allow_light: bool = true

var _core: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _sats: Array[MeshInstance3D] = []
var _trail: CPUParticles3D = null
var _light: OmniLight3D = null
var _has_light_slot: bool = false
var _glow: float = 1.0
var _flare: float = 0.0
var _phase: float = 0.0
var _tint_shift: float = 0.0
var _chime_cd: float = 0.0
var _peek_t: float = 0.0


func _configure() -> void:
	species = "wisp"
	flies = true
	max_speed = 2.6
	accel = 5.0
	min_altitude = 0.7
	max_altitude = 4.5
	turn_speed = 4.0
	lod_distance = 60.0
	_wander_alt = randf_range(1.2, 2.6)


func _species_traits() -> Dictionary:
	return {"bold": 0.45, "curiosity": 0.72, "sociability": 0.7, "mischief": 0.45, "energy": 0.6}


func _build_body(root: Node3D) -> void:
	_phase = randf() * TAU
	# Personality shows in the light: mischievous lean violet, skittish pale, loners deeper.
	match archetype:
		Archetype.MISCHIEVOUS:
			_tint_shift = 0.75
		Archetype.SKITTISH:
			_tint_shift = 0.25
		Archetype.LONER:
			_tint_shift = -0.4
	var c: Color = _color()
	_core = KitScript.part(root, KitScript.sphere(0.07, 10, 6), KitScript.mat(Color.WHITE, 3.0, true), Vector3.ZERO, Vector3.ONE, Vector3.ZERO, "Core")
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	_halo.mesh = KitScript.glow_billboard(Color(1, 1, 1, 0.9), 0.7, 1.4)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_halo)
	for i in range(2 + int(trait_value("energy") * 2.0)):
		var s: MeshInstance3D = MeshInstance3D.new()
		s.mesh = KitScript.glow_billboard(Color(1, 1, 1, 0.8), 0.12, 1.6)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(s)
		_sats.append(s)
	_trail = CPUParticles3D.new()
	_trail.amount = 20
	_trail.lifetime = 0.9
	_trail.local_coords = false
	_trail.mesh = KitScript.glow_billboard(Color(1, 1, 1, 0.6), 0.1, 1.2)
	_trail.direction = Vector3.UP
	_trail.spread = 180.0
	_trail.initial_velocity_min = 0.02
	_trail.initial_velocity_max = 0.15
	_trail.gravity = Vector3(0.0, 0.12, 0.0)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	_trail.scale_amount_curve = shrink
	root.add_child(_trail)
	_trail.emitting = true
	_apply_color(c)


func _ready() -> void:
	super._ready()
	if allow_light and _director != null and _director.acquire_light():
		_has_light_slot = true
		_light = OmniLight3D.new()
		_light.omni_range = 3.2
		_light.light_energy = 0.8
		_light.shadow_enabled = false
		_light.light_color = _color()
		_body.add_child(_light)


func _on_despawn() -> void:
	if _has_light_slot and _director != null and is_instance_valid(_director):
		_director.release_light()
	_has_light_slot = false


func _color() -> Color:
	var base: Color = mirror_color if in_mirror() else reality_color
	if _tint_shift > 0.5:
		return base.lerp(Color(0.85, 0.45, 1.0), 0.45)
	if _tint_shift > 0.1:
		return base.lerp(Color.WHITE, 0.45)
	if _tint_shift < 0.0:
		return base.darkened(0.15).lerp(Color(1.0, 0.45, 0.25) if not in_mirror() else Color(0.3, 0.5, 1.0), 0.3)
	return base


func _apply_color(c: Color) -> void:
	if _halo != null:
		_halo.mesh = KitScript.glow_billboard(c, 0.7, 1.4)
	for s in _sats:
		s.mesh = KitScript.glow_billboard(c, 0.12, 1.6)
	if _trail != null:
		_trail.mesh = KitScript.glow_billboard(c, 0.1, 1.2)
	if _light != null:
		_light.light_color = c


func _on_realm_shifted(new_realm: int) -> void:
	super._on_realm_shifted(new_realm)
	_apply_color(_color())
	# Everyone flares and scatters a little, then settles.
	_flare = 1.5
	velocity += Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)) * 2.5


func _disturbance_sensitivity(kind: String) -> float:
	match kind:
		"death":
			return 0.5  # spirits are drawn to death more than scared of it
		"shift":
			return 0.1
	return 1.0


func _score_extra(s: Dictionary) -> void:
	if _director == null:
		return
	var soul: Dictionary = _director.nearest_interest(global_position, "soul", 16.0)
	if not soul.is_empty() and fear < 0.45:
		s["soul_gather"] = 0.55 + trait_value("curiosity") * 0.3 + trait_value("sociability") * 0.15
		if behaviour != "soul_gather":
			focus_pos = soul["pos"] as Vector3
	if fear < 0.2 and trait_value("energy") < 0.75:
		var bloom: Node3D = _nearest_bloom(6.0)
		if bloom != null:
			s["visit_bloom"] = 0.3 + (1.0 - trait_value("energy")) * 0.25
			if behaviour != "visit_bloom":
				focus = bloom
				focus_pos = bloom.global_position + Vector3.UP * 0.7


func _nearest_bloom(radius: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = radius
	for b in get_tree().get_nodes_in_group("flora_bloom"):
		if not (b is Node3D) or not (b as Node3D).is_visible_in_tree():
			continue
		var d: float = (b as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = b as Node3D
	return best


func _act_extra(b: String, delta: float) -> Variant:
	match b:
		"soul_gather":
			# Slow rising spiral over the death site; height climbs, then they fade off.
			var c: Vector3 = focus_pos + Vector3.UP * minf(behaviour_time * 0.25, 2.5)
			var v: Vector3 = orbit(c, 0.6 + 0.25 * sin(_phase + behaviour_time), 1.0, max_speed * 0.55)
			v.y = clampf((c.y - global_position.y) * 1.5, -1.0, 1.0)
			_flare = maxf(_flare, 0.5)
			return v
		"visit_bloom":
			var v2: Vector3 = steer_to(focus_pos + Vector3(sin(behaviour_time * 1.3), 0.0, cos(behaviour_time * 1.1)) * 0.3, max_speed * 0.4, 0.8)
			v2.y = clampf((focus_pos.y - global_position.y) * 1.5, -0.6, 0.6)
			return v2
		"curious":
			if not is_instance_valid(focus):
				return null
			# Orbit at head height, occasionally dart in for a close "peek".
			_peek_t -= delta
			var r: float = 1.6 + (1.0 - trait_value("bold")) * 1.4
			if _peek_t < 0.0:
				r = 0.55
				if _peek_t < -0.6:
					_peek_t = randf_range(2.0, 5.0)
					if _chime_cd <= 0.0:
						GameFeelScript.play_sound(self, "chime", global_position, -20.0, randf_range(0.9, 1.3), 0.05)
						_chime_cd = 4.0
			var center: Vector3 = focus.global_position + Vector3.UP * 0.1
			return orbit(center, r, 1.0 if get_instance_id() % 2 == 0 else -1.0, max_speed * 0.7)
		"flee":
			var away: Vector3 = flee_from(fear_source, max_speed * (1.2 + fear))
			away.y = absf(away.y) + 1.2
			return away
	return null


func _on_behaviour_entered(b: String) -> void:
	if b == "curious":
		_peek_t = randf_range(1.5, 4.0)


func _on_play_event(kind: String) -> void:
	_flare = 1.0
	if kind == "poke" and _chime_cd <= 0.0:
		GameFeelScript.play_sound(self, "chime", global_position, -22.0, randf_range(1.3, 1.7), 0.05)
		_chime_cd = 1.5


func _animate(delta: float) -> void:
	_phase += delta
	_chime_cd = maxf(0.0, _chime_cd - delta)
	_flare = maxf(0.0, _flare - delta * 1.2)
	var mirror_k: float = 1.35 if in_mirror() else 1.0
	# Frightened wisps dim (skittish ones nearly go dark); curious ones brighten near the player.
	var target_glow: float = (1.0 - fear * (0.5 + (1.0 - trait_value("bold")) * 0.45)) * mirror_k + _flare
	if behaviour == "curious" or behaviour == "soul_gather":
		target_glow += 0.25
	_glow = lerpf(_glow, target_glow, clampf(5.0 * delta, 0.0, 1.0))
	var pulse: float = 1.0 + 0.12 * sin(_phase * (2.0 + trait_value("energy") * 2.0))
	if _body != null:
		_body.position.y = sin(_phase * 1.7) * 0.06
	if _halo != null:
		_halo.scale = Vector3.ONE * clampf(_glow * pulse, 0.15, 2.5)
	if _core != null:
		_core.scale = Vector3.ONE * clampf(0.7 + _glow * 0.4, 0.3, 1.8)
	for i in range(_sats.size()):
		var a: float = _phase * (2.0 + i * 0.7) + i * TAU / _sats.size()
		_sats[i].position = Vector3(cos(a) * 0.18, sin(a * 1.3) * 0.08, sin(a) * 0.18)
	if _light != null:
		_light.light_energy = clampf(0.7 * _glow * pulse, 0.0, 2.5)
	if _trail != null:
		_trail.speed_scale = 0.6 + velocity.length() * 0.25

func _realm_look_profile() -> String:
	return ""  # wisps recolour themselves per realm
