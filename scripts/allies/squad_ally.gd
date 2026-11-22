class_name SquadAlly
extends CharacterBody3D
## One squad "Echo" ally, fully driven by its `AllyProfile` resource and the `SquadCommand` it is running.
## The manager (`AllySquadManager`) routes commands and coordinates two-ally handshake combos; this node owns
## movement (formation follow, hazard/edge avoidance, no-stacking slots, catch-up blink), combat primitives
## (melee, taunt, charge, finisher, nuke, mine/detonate, revive), self-preservation retreat, the DOWNED state
## with manual revive (player presses Interact next to a downed ally) and silly orders (jump N / dance / emote).
##
## Contract used by enemies: group `squad_ally`, `is_targetable()`, `apply_damage(amount, source) -> bool`,
## `get_facing_direction()`, `get_display_name()`.

const GoreFXScript := preload("res://scripts/core/gore_fx.gd")
const GameFeelScript := preload("res://scripts/core/game_feel.gd")
const LoadoutScript := preload("res://scripts/core/character_loadout.gd")
const SquadCommandScript := preload("res://scripts/allies/squad_command.gd")

signal spoke(ally: SquadAlly, text: String, event: String)
signal health_changed(ally: SquadAlly, hp: int, max_hp: int)
signal downed(ally: SquadAlly)
signal revived(ally: SquadAlly)
signal command_started(ally: SquadAlly, cmd: SquadCommand)
signal command_finished(ally: SquadAlly, cmd: SquadCommand, result: String)
signal prompt_changed(show_prompt: bool, prompt_text: String)

const GRAVITY: float = 22.0
const INTERCEPT_RADIUS: float = 6.0
const LEASH_RADIUS: float = 8.5
const FOLLOW_LEASH: float = 42.0
const KITE_RADIUS: float = 5.5
const REVIVE_CHANNEL: float = 2.2
const PLAYER_REVIVE_DURATION: float = 5.0
const PLAYER_REVIVE_RANGE: float = 3.2

var profile: AllyProfile = null
var manager: Node = null
var slot_index: int = 0

var health: int = 100
var max_health: int = 100
var is_downed: bool = false
var auto_engage: bool = true
var current: SquadCommand = null
var queue: Array[SquadCommand] = []

var facing_direction: Vector3 = Vector3.FORWARD
var _bridge: CharacterAnimationBridge = null
var _name_label: Label3D = null
var _ring: MeshInstance3D = null
var _rng := RandomNumberGenerator.new()

var _attack_cd: float = 0.0
var _taunt_cd: float = 0.0
var _charge_cd: float = 0.0
var _action: String = ""
var _action_timer: float = 0.0
var _action_hit_at: float = -1.0
var _action_cb: Callable = Callable()
var _action_dur: float = 0.0
var _stagger_timer: float = 0.0
var _retreating: bool = false
var _low_hp_warned: bool = false
var _stuck_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _want_move_this_frame: bool = false
var _want_move_goal: Vector3 = Vector3.INF
var _stuck_anchor_pos: Vector3 = Vector3.ZERO
var _stuck_strikes: int = 0
var _embed_scan_t: float = 0.0
var _safe_pos_scan_t: float = 0.0
var _pit_rescue_count: int = 0
var _pit_rescue_window_ms: int = 0
var _stand_cap: CapsuleShape3D = null
var _embed_cap: CapsuleShape3D = null
var _engage_target: EnemyAI = null
var _combat_quiet: float = 0.0
var _speak_cd: float = 0.0
var _idle_chatter: float = 0.0
var _player_near_prompt: bool = false
var _reviving_by_player: bool = false
var _revive_channel_t: float = 0.0
var _mine: Node3D = null
var _cast_ring: MeshInstance3D = null
var _cast_ring_mat: StandardMaterial3D = null
var _dash_vel: Vector3 = Vector3.ZERO
var _dash_timer: float = 0.0
var _dash_hit_cb: Callable = Callable()
var _dash_target: EnemyAI = null
var _regen_acc: float = 0.0
var _last_safe_pos: Vector3 = Vector3.ZERO
var _has_safe_pos: bool = false
# Skills & buffs.
var _skill_cd: Dictionary = {}       # skill id -> seconds remaining
var _skill_scan: float = 0.0
var _skill_gap: float = 0.0
var _dmg_buff: float = 0.0
var _dmg_buff_t: float = 0.0
var _dr: float = 0.0                 # damage reduction 0..1
var _dr_t: float = 0.0
var _ward_hp: float = 0.0
var _ward_t: float = 0.0
var _ward_fx: MeshInstance3D = null
var last_skill: String = ""


func setup(p: AllyProfile, mgr: Node, slot: int) -> void:
	profile = p
	manager = mgr
	slot_index = slot
	name = "Ally_" + p.ally_name
	max_health = p.max_health
	health = p.max_health


func _ready() -> void:
	add_to_group("squad_ally")
	_rng.randomize()
	collision_layer = 0
	collision_mask = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_PLAYER_BLOCKER
	floor_snap_length = 0.45
	_build_body()
	_sync_realm_mask()
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		rm.realm_changed.connect(func(_r: int) -> void: _sync_realm_mask())
		rm.realms_merged.connect(_sync_realm_mask)
	_last_pos = global_position
	_stuck_anchor_pos = global_position
	_idle_chatter = _rng.randf_range(25.0, 50.0)


# ------------------------------------------------------------------ contract

func get_display_name() -> String:
	return profile.ally_name if profile != null else String(name)


func get_role() -> String:
	return profile.role if profile != null else "vanguard"


func is_targetable() -> bool:
	return not is_downed and is_inside_tree() and visible


func is_available() -> bool:
	return not is_downed


func get_facing_direction() -> Vector3:
	return facing_direction


func get_health_ratio() -> float:
	return float(health) / float(maxi(1, max_health))


func get_state_text() -> String:
	if is_downed:
		return "DOWN"
	if _retreating:
		return "retreating"
	if _action == "channel":
		return "casting"
	if _action == "revive":
		return "reviving"
	if current != null:
		var s: String = current.describe()
		if not current.step.is_empty() and current.step != "run":
			s += " (" + current.step + ")"
		return s
	return "follow"


func apply_damage(amount: int, source: Node = null) -> bool:
	if is_downed or amount <= 0 or not is_inside_tree():
		return false
	if _action == "dodge":
		return false
	var amt_f: float = float(amount) * profile.damage_taken_mult * (1.0 - _dr)
	if _ward_hp > 0.0:
		var absorbed: float = minf(_ward_hp, amt_f)
		_ward_hp -= absorbed
		amt_f -= absorbed
		if _ward_hp <= 0.0:
			_clear_ward()
		if amt_f <= 0.5:
			GoreFXScript.sparks(self, global_position + Vector3.UP * 1.1, Vector3.UP, Color(0.7, 0.85, 1.0), 8)
			return true
	amount = maxi(1, int(round(amt_f)))
	health = maxi(0, health - amount)
	health_changed.emit(self, health, max_health)
	_combat_quiet = 0.0
	var chest: Vector3 = global_position + Vector3.UP * 1.1
	var dir: Vector3 = Vector3.FORWARD
	if source is Node3D:
		dir = global_position - (source as Node3D).global_position
		dir.y = 0.0
	GoreFXScript.sparks(self, chest, dir.normalized() if dir.length_squared() > 0.001 else Vector3.UP, Color(1.0, 0.85, 0.5), 10)
	if AudioManager.instance != null:
		AudioManager.instance.play_at("hit_metal", chest, -8.0)
	else:
		GameFeelScript.play_sound(self, "clang", chest, -8.0, 1.1)
	if health <= 0:
		_go_down()
		return true
	if amount >= 15 and _action != "channel" and _dash_timer <= 0.0:
		_stagger_timer = 0.28
		_play(["Hit_A", "Hit_B"], 0.28, true)
	if get_health_ratio() < 0.35 and not _low_hp_warned:
		_low_hp_warned = true
		say_event("low_hp", 2)
	# Being hit pulls an idle ally into the fight (unless told to hold fire). Mission lock: an ally on a
	# mission ignores stray hits and keeps to its task.
	var on_mission: bool = current != null and current.is_mission()
	if source is EnemyAI and _engage_target == null and not _is_ceasefire() and not on_mission:
		_engage_target = source as EnemyAI
	return true


# ------------------------------------------------------------------ body / visuals

func _build_body() -> void:
	var col := CollisionShape3D.new()
	col.name = "BodyCollider"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0, 0.875, 0)
	add_child(col)
	# Enemy melee hitboxes (mask Player|Hitbox, affects_player) land on this "friendly" hurtbox, which routes to
	# apply_damage(amount, attacker). Player sweeps skip player-type hurtboxes, so there is no friendly fire.
	var hurt := Hurtbox3D.new()
	hurt.name = "Hurtbox3D"
	hurt.owner_actor_path = NodePath("..")
	hurt.is_player_hurtbox = true
	hurt.is_enemy_hurtbox = false
	hurt.collision_layer = RealmManager.LAYER_HITBOX
	hurt.collision_mask = 0
	hurt.monitoring = false
	var hcs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(0.8, 1.8, 0.8)
	hcs.shape = hbox
	hcs.position = Vector3(0, 0.9, 0)
	hurt.add_child(hcs)
	add_child(hurt)
	var vis := Node3D.new()
	vis.name = "VisualRoot"
	add_child(vis)
	if profile != null and ResourceLoader.exists(profile.model_path):
		var model: Node3D = (load(profile.model_path) as PackedScene).instantiate() as Node3D
		model.name = "ModelRoot"
		model.scale = Vector3.ONE * profile.model_scale
		vis.add_child(model)
		LoadoutScript.apply(model, profile.keep_props)
		var bp: Array[String] = profile.borrow_props
		var i: int = 0
		while i + 2 < bp.size():
			LoadoutScript.arm_with_borrowed(model, bp[i], bp[i + 1], bp[i + 2])
			i += 3
		if profile.tint != Color(1, 1, 1, 1):
			_tint(model, profile.tint)
		if profile.role == "artillery":
			_attach_staff(model, profile.color)
	_bridge = CharacterAnimationBridge.new()
	_bridge.name = "CharacterAnimationBridge"
	_bridge.actor_path = NodePath("..")
	_bridge.model_root_path = NodePath("../VisualRoot/ModelRoot")
	_bridge.apply_default_loadout = false
	add_child(_bridge)
	# Name tag + HP pips, ally coloured; and a soft gold ring at the feet so allies never read as enemies.
	_name_label = Label3D.new()
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.pixel_size = 0.0058
	_name_label.font_size = 26
	_name_label.outline_size = 7
	_name_label.outline_modulate = Color(0.02, 0.02, 0.04, 0.9)
	_name_label.font = UITheme.display_font()
	_name_label.position = Vector3(0, 2.25, 0)
	add_child(_name_label)
	WorldLabelOverlay.adopt(_name_label, {"px": 15, "font": "display", "max_dist": 45.0})
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.48
	tm.outer_radius = 0.56
	tm.rings = 32
	tm.ring_segments = 4
	_ring.mesh = tm
	_ring.scale = Vector3(1, 0.15, 1)
	_ring.position = Vector3(0, 0.04, 0)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(0.24, 0.96, 0.48, 0.50)
	_ring.material_override = rm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_refresh_label()


static var _ally_outline_mat: ShaderMaterial = null


static func _get_green_outline_mat() -> ShaderMaterial:
	if _ally_outline_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;
uniform vec4 outline_color : source_color = vec4(0.18, 0.96, 0.44, 1.0);
uniform float outline_width : hint_range(0.005, 0.08) = 0.028;
void vertex() {
	VERTEX += NORMAL * outline_width;
}
void fragment() {
	ALBEDO = outline_color.rgb;
}
"""
		_ally_outline_mat = ShaderMaterial.new()
		_ally_outline_mat.shader = sh
	return _ally_outline_mat


func _apply_green_outline(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.material_overlay = _get_green_outline_mat() if enabled else null
	for ch in node.get_children():
		_apply_green_outline(ch, enabled)


func _tint(node: Node, c: Color) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = node as MeshInstance3D
		for s in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(s)
			if src == null:
				src = mi.mesh.surface_get_material(s)
			if src is StandardMaterial3D:
				var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.albedo_color = m.albedo_color * c
				mi.set_surface_override_material(s, m)
	for ch in node.get_children():
		_tint(ch, c)


## Artillery casters hold a crystal staff instead of a sword. It is placed exactly where the rig's (hidden)
## 1H_Sword sits, so it follows the hand with the right grip; falls back to the handslot.r bone.
const STAFF_LENGTH: float = 1.45


func _attach_staff(model: Node3D, col: Color) -> void:
	var holder: Node3D = null
	var grip := Transform3D.IDENTITY
	var sword: Node3D = model.find_child("1H_Sword", true, false) as Node3D
	if sword != null and sword.get_parent() is Node3D:
		holder = sword.get_parent() as Node3D
		grip = sword.transform
	else:
		var skels: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
		if skels.is_empty():
			return
		var skel: Skeleton3D = skels[0] as Skeleton3D
		if skel.find_bone("handslot.r") < 0:
			return
		var att := BoneAttachment3D.new()
		att.name = "CasterStaffSlot"
		att.bone_name = "handslot.r"
		skel.add_child(att)
		holder = att
	var pivot := Node3D.new()
	pivot.name = "CasterStaff"
	pivot.transform = grip
	holder.add_child(pivot)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.032
	cyl.height = STAFF_LENGTH
	cyl.radial_segments = 8
	shaft.mesh = cyl
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.24, 0.14)
	wood.roughness = 0.9
	shaft.material_override = wood
	shaft.position = Vector3(0, STAFF_LENGTH * 0.25, 0)
	pivot.add_child(shaft)
	var gem := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 10
	sm.rings = 5
	gem.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = col.lightened(0.3)
	gm.emission_enabled = true
	gm.emission = col
	gm.emission_energy_multiplier = 2.5
	gem.material_override = gm
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gem.position = Vector3(0, STAFF_LENGTH * 0.75 + 0.06, 0)
	pivot.add_child(gem)
	var glow := OmniLight3D.new()
	glow.light_color = col
	glow.light_energy = 0.7
	glow.omni_range = 2.0
	glow.position = gem.position
	pivot.add_child(glow)


func _refresh_label() -> void:
	if _name_label == null or profile == null:
		return
	var pips: int = int(ceil(get_health_ratio() * 6.0))
	var bar: String = "▰".repeat(pips) + "▱".repeat(6 - pips)
	_name_label.text = "%s\n%s" % [profile.ally_name.to_upper(), bar if not is_downed else "DOWN — revive"]
	var c: Color = profile.color
	_name_label.modulate = Color(c.r, c.g, c.b, 0.95) if not is_downed else Color(1.0, 0.35, 0.3, 0.95)
	# Hide the tag when the ally is right next to the camera (it would fill the screen); the HUD roster
	# still shows everything. Cinematic mode hides it via the meta flag.
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and not bool(_name_label.get_meta("cinematic_hidden", false)):
		_name_label.visible = cam.global_position.distance_to(_name_label.global_position) > 4.2


func _sync_realm_mask() -> void:
	var rm: RealmManager = RealmManager.instance as RealmManager
	var world: int = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY
	if rm != null:
		world = rm.get_realm_world_mask(rm.current_realm)
	# A downed ally must never lose the floor beneath them when the player shifts realms (Q).
	if is_downed:
		world |= RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR
	collision_mask = world | RealmManager.LAYER_PLAYER_BLOCKER
	# Green ally outline is visible only in the Mirror (or Merged) realm.
	var in_mirror: bool = rm != null and (rm.is_merged or rm.current_realm == RealmManager.Realm.MIRROR)
	var model: Node = get_node_or_null("VisualRoot/ModelRoot")
	if model != null:
		_apply_green_outline(model, in_mirror)


func set_facing(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	facing_direction = flat.normalized()
	var vis: Node3D = get_node_or_null("VisualRoot") as Node3D
	if vis != null:
		vis.rotation.y = atan2(-facing_direction.x, -facing_direction.z) - rotation.y


func _play(clips: Array[String], dur: float = -1.0, restart: bool = false, loop: bool = false) -> void:
	if _bridge != null:
		_bridge.play_candidates(clips, dur, restart, loop)


# ------------------------------------------------------------------ speech

## Speaks a profile voice line for `event`. `prio`: 0 chatter, 1 normal, 2 important, 3 critical.
func say_event(event: String, prio: int = 1, fallback: String = "") -> void:
	if profile == null:
		return
	var line: String = profile.line(event, fallback)
	if line.is_empty():
		return
	say(line, event, prio)


func say(text: String, event: String = "say", prio: int = 1) -> void:
	if text.strip_edges().is_empty():
		return
	if prio <= 0 and _speak_cd > 0.0:
		return
	if prio == 1 and _speak_cd > 1.2:
		return
	_speak_cd = 2.5 if prio <= 0 else (2.0 if prio == 1 else 1.5)
	spoke.emit(self, text, event)
	if manager != null and manager.has_method("on_ally_spoke"):
		manager.call("on_ally_spoke", self, text, event, prio)


# ------------------------------------------------------------------ commands

func assign(cmd: SquadCommand) -> void:
	if (current != null and not current.done) or not _action.is_empty() or _dash_timer > 0.0:
		_abort_current_effects()
	current = cmd
	current.step = ""
	current.timer = 0.0
	_stuck_timer = 0.0
	_stuck_strikes = 0
	_stuck_anchor_pos = global_position
	# Combo halves keep handshake data the manager may already have posted while they were queued.
	if cmd.combo_id == 0:
		var keep_rally: bool = bool(current.data.get("rally", false)) or bool(current.args.get("rally", false))
		current.data = {}
		if keep_rally:
			current.data["rally"] = true
	_engage_target = null
	command_started.emit(self, cmd)


func enqueue(cmd: SquadCommand, front: bool = false) -> void:
	if front:
		queue.push_front(cmd)
	elif cmd.stance:
		queue.append(cmd)
	else:
		# Finite orders / missions run before any resumable stance (a stance never finishes on its own and
		# would otherwise block everything queued behind it).
		var at: int = queue.size()
		for i in range(queue.size()):
			if queue[i].stance:
				at = i
				break
		queue.insert(at, cmd)
	while queue.size() > 6:
		queue.pop_back()


func clear_queue() -> void:
	queue.clear()


func finish_current(result: String = "done") -> void:
	if current == null:
		return
	var c: SquadCommand = current
	c.done = true
	# Natural completion: let a running dance / emote / release animation play out (queued orders wait).
	current = null
	command_finished.emit(self, c, result)
	if not queue.is_empty():
		assign(queue.pop_front())


func _abort_current_effects() -> void:
	_hide_cast_ring()
	if not _action.is_empty():
		_action = ""
		_action_timer = 0.0
		_action_hit_at = -1.0
		_action_cb = Callable()
		_action_dur = 0.0
	if _dash_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
	_dash_timer = 0.0
	_dash_vel = Vector3.ZERO
	_dash_hit_cb = Callable()
	_dash_target = null
	var vis: Node3D = get_node_or_null("VisualRoot") as Node3D
	if vis != null:
		vis.rotation.x = 0.0
		vis.rotation.y = atan2(-facing_direction.x, -facing_direction.z) - rotation.y


func _is_ceasefire() -> bool:
	return current != null and current.verb == "ceasefire"


func _is_massacre() -> bool:
	return current != null and current.verb == "massacre"


## Allies executing any non-passive command (anything other than follow / ceasefire) roam freely without
## distance-teleportation back to the player.
func has_free_leash() -> bool:
	if current != null and not current.done and not (current.verb in ["follow", "ceasefire"]):
		return true
	for q in queue:
		if q != null and not q.done and not (q.verb in ["follow", "ceasefire"]):
			return true
	return false


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if profile == null or not is_inside_tree():
		return
	_want_move_this_frame = false
	_want_move_goal = Vector3.INF
	_tick_timers(delta)
	if is_downed:
		_process_downed(delta)
		return
	_record_safe_pos_if_valid(delta)
	_regen(delta)
	var player: Node3D = _player()
	if player != null:
		_catch_up(player)
	_embed_scan_t -= delta
	if _embed_scan_t <= 0.0:
		_embed_scan_t = 0.35
		if _is_embedded_in_world():
			_recover_from_embedded(player)
	if _dash_timer > 0.0:
		_process_dash(delta)
		_finish_frame(delta)
		return
	if _stagger_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		_apply_gravity_and_move(delta)
		_finish_frame(delta)
		return
	if not _action.is_empty():
		_process_action(delta)
		_finish_frame(delta)
		return
	_check_self_preservation()
	_skill_scan -= delta
	if _skill_scan <= 0.0:
		_skill_scan = 0.4
		if _auto_skills(player):
			_finish_frame(delta)
			return
	if _retreating:
		_run_retreat_self(delta, player)
		_finish_frame(delta)
		return
	var cmd: SquadCommand = current
	if cmd == null:
		_run_follow(delta, player, null)
	else:
		cmd.timer += delta
		_run_command(cmd, delta, player)
	_finish_frame(delta)


func _finish_frame(delta: float) -> void:
	_update_stuck(delta)
	_update_anim()
	_refresh_label()
	_update_revive_prompt()


func _tick_timers(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_taunt_cd = maxf(0.0, _taunt_cd - delta)
	_charge_cd = maxf(0.0, _charge_cd - delta)
	_stagger_timer = maxf(0.0, _stagger_timer - delta)
	_speak_cd = maxf(0.0, _speak_cd - delta)
	_skill_gap = maxf(0.0, _skill_gap - delta)
	for k in _skill_cd.keys():
		_skill_cd[k] = maxf(0.0, float(_skill_cd[k]) - delta)
	if _dmg_buff_t > 0.0:
		_dmg_buff_t -= delta
		if _dmg_buff_t <= 0.0:
			_dmg_buff = 0.0
	if _dr_t > 0.0:
		_dr_t -= delta
		if _dr_t <= 0.0:
			_dr = 0.0
	if _ward_t > 0.0:
		_ward_t -= delta
		if _ward_t <= 0.0:
			_clear_ward()
	_combat_quiet += delta
	_idle_chatter -= delta
	if _idle_chatter <= 0.0:
		_idle_chatter = _rng.randf_range(40.0, 80.0)
		if _combat_quiet > 20.0 and not is_downed:
			say_event("idle", 0)


func _regen(delta: float) -> void:
	if health >= max_health:
		return
	var rate: float = profile.regen_per_sec * (3.0 if _retreating else (1.0 if _combat_quiet > 4.0 else 0.0))
	if rate <= 0.0:
		return
	_regen_acc += rate * delta
	var add: int = int(_regen_acc)
	if add <= 0:
		return
	_regen_acc -= float(add)
	var before: int = health
	health = mini(max_health, health + add)
	if health != before:
		if get_health_ratio() > 0.5:
			_low_hp_warned = false
		health_changed.emit(self, health, max_health)


func _run_command(cmd: SquadCommand, delta: float, player: Node3D) -> void:
	# Timed steps: "wait 3 seconds", or a stance in the middle of a chain ("get behind me, then shoot")
	# completes on arrival (or after its time limit) so the next step runs.
	if cmd.args.has("step_sec") and cmd.timer >= float(cmd.args["step_sec"]):
		finish_current("waited")
		return
	if bool(cmd.args.get("chain_step", false)) and not cmd.args.has("step_sec"):
		var lim: float = 6.0 if cmd.verb in ["position", "rearguard", "follow", "retreat"] else 3.0
		if (bool(cmd.data.get("arrived", false)) and cmd.timer > 0.6) or cmd.timer >= lim:
			finish_current("step done")
			return
	match cmd.verb:
		"position":
			_run_position(delta, player, cmd)
		"rearguard":
			_run_rearguard(delta, player, cmd)
		"ranged":
			_run_ranged(delta, player, cmd)
		"circle":
			_run_circle(delta, player, cmd)
		"face":
			if player != null:
				set_facing(player.global_position - global_position)
			_play(["Interact", "Idle"], 0.6, true)
			_start_action("emote", 0.6, -1.0, Callable())
			finish_current("looking")
		"follow":
			_run_follow(delta, player, cmd)
		"hold":
			_run_hold(delta, cmd)
		"advance":
			_run_advance(delta, player, cmd)
		"retreat":
			_run_retreat_order(delta, player, cmd)
		"attack":
			_run_attack(delta, player, cmd)
		"taunt":
			_run_taunt_cmd(delta, player, cmd)
		"bodyguard":
			_run_bodyguard(delta, player, cmd)
		"kite":
			_run_kite(delta, player, cmd)
		"nuke":
			_run_nuke(delta, player, cmd)
		"revive":
			_run_revive(delta, player, cmd)
		"massacre":
			_run_massacre(delta, player, cmd)
		"ceasefire":
			_run_ceasefire(delta, player, cmd)
		"scatter":
			_run_scatter(delta, player, cmd)
		"jump":
			_run_jump(cmd)
		"dance":
			_start_action("dance", 3.2, -1.0, Callable())
			_play(["Cheer", "Taunt", "Dodge_Left"], 0.8, true)
			finish_current("danced")
		"emote":
			_run_emote(cmd)
		"combo_kite_nuke", "combo_charge_finish", "combo_lure_detonate":
			_run_combo_part(delta, player, cmd)
		"peel":
			_run_peel(delta, player, cmd)
		"skill":
			_run_skill(delta, player, cmd)
		"surround":
			_run_surround(delta, player, cmd)
		"overwatch":
			_run_overwatch(delta, player, cmd)
		"ambush":
			_run_ambush(delta, player, cmd)
		"hit_and_run":
			_run_hit_and_run(delta, player, cmd)
		"hunt":
			_run_hunt(delta, player, cmd)
		"destroy":
			_run_destroy(delta, player, cmd)
		"interact":
			_run_interact(delta, player, cmd)
		_:
			# say / status / stop / auto_engage are resolved instantly by the manager.
			finish_current("ok")


# ------------------------------------------------------------------ stances

func _formation_point(player: Node3D) -> Vector3:
	var f: Vector3 = Vector3.FORWARD
	if player.has_method("get_facing_direction"):
		f = player.call("get_facing_direction")
	var r := Vector3(-f.z, 0.0, f.x)
	# Flanking wedge kept out of the over-the-right-shoulder camera's centre line (x = side, y = behind).
	var offsets: Array[Vector2] = [Vector2(-2.5, 0.3), Vector2(2.7, 0.8), Vector2(-2.2, 2.4), Vector2(3.4, 2.6), Vector2(-4.0, 1.2), Vector2(4.6, 1.0)]
	var o: Vector2 = offsets[slot_index % offsets.size()]
	# Side hysteresis: an ally trailing on the other side of the camera line keeps the mirrored slot on its own
	# side instead of cutting straight across the lens to reach its nominal one.
	var rel: Vector3 = global_position - player.global_position
	var side_now: float = rel.dot(r)
	if rel.dot(f) < 0.5 and absf(side_now) > 0.6 and signf(side_now) != signf(o.x):
		var flipped: Vector3 = player.global_position - f * o.y - r * o.x
		var taken: bool = false
		for a in get_tree().get_nodes_in_group("squad_ally"):
			if a != self and a is SquadAlly and not (a as SquadAlly).is_downed and (a as SquadAlly).global_position.distance_to(flipped) < 2.0:
				taken = true
		if not taken:
			o.x = -o.x
	var want: Vector3 = player.global_position - f * o.y + r * o.x
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _form_cache_ms < 200 and _form_cache_from.distance_to(player.global_position) < 0.4:
		return _form_cache_pos
	_form_cache_ms = now_ms
	_form_cache_from = player.global_position
	_form_cache_pos = _formation_resolve(player, want, f, r)
	return _form_cache_pos


var _form_cache_ms: int = -1000
var _form_cache_from: Vector3 = Vector3.INF
var _form_cache_pos: Vector3 = Vector3.ZERO


func _formation_resolve(player: Node3D, want: Vector3, f: Vector3, r: Vector3) -> Vector3:
	# Spatial check: a slot inside a wall / over a ledge / on top of a squad-mate is pulled in toward the
	# player until it is free (keeps formation sane on narrow causeways and in corridors).
	for k in range(4):
		var cand: Vector3 = player.global_position.lerp(want, 1.0 - 0.2 * float(k))
		if _slot_free(cand, player):
			return cand
	# Blocked side (railing, waystone, ledge): try the mirrored slot on the other side of the player.
	var mirrored: Vector3 = want - 2.0 * r * (want - player.global_position).dot(r)
	for k in range(4):
		var cand2: Vector3 = player.global_position.lerp(mirrored, 1.0 - 0.2 * float(k))
		if _slot_free(cand2, player):
			return cand2
	# Last resort: validated stand spot near the player instead of raw parapet/cliff offsets.
	var s: float = 1.0 if slot_index % 2 == 0 else -1.0
	for off in [
		-f * 1.2 + r * (0.9 * s),
		-f * 1.2 - r * (0.9 * s),
		-f * 1.4,
		r * (1.0 * s),
		-r * (1.0 * s),
	]:
		var spot: Vector3 = _validate_stand_spot(player.global_position + (off as Vector3), player.global_position, true, false, 0.95)
		if spot != Vector3.INF:
			return spot
	return player.global_position


func _slot_free(p: Vector3, player: Node3D) -> bool:
	if not is_inside_tree():
		return true
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var mask: int = collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER
	var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 1.8, mask, [get_rid()])
	if space.intersect_ray(down).is_empty():
		return false
	# Never park in the player's view: too close to the camera, or on the camera->player sight line.
	if _camera_blocking_at(p, player):
		return false
	# Wall clearance: a slot hugging a railing / wall makes the ally grind along it while following.
	var mid: Vector3 = p + Vector3.UP * 0.8
	for dv in [Vector3(0.65, 0, 0), Vector3(-0.65, 0, 0), Vector3(0, 0, 0.65), Vector3(0, 0, -0.65)]:
		var cq := PhysicsRayQueryParameters3D.create(mid, mid + (dv as Vector3), collision_mask, [get_rid()])
		if not space.intersect_ray(cq).is_empty():
			return false
	var from: Vector3 = player.global_position + Vector3.UP * 0.9
	var los := PhysicsRayQueryParameters3D.create(from, p + Vector3.UP * 0.9, collision_mask, [get_rid()])
	if not space.intersect_ray(los).is_empty():
		return false
	for a in get_tree().get_nodes_in_group("squad_ally"):
		if a != self and a is SquadAlly and (a as SquadAlly).global_position.distance_to(p) < 1.2:
			return false
	return true


func _run_follow(delta: float, player: Node3D, _cmd: SquadCommand) -> void:
	if player == null:
		_halt(delta)
		return
	# Auto-engage: only peel enemies that are directly threatening the player (< 4.0m).
	# Allies following the player must stay in formation and never chase enemies across the arena.
	if auto_engage and not _is_ceasefire():
		if _engage_target == null or not _enemy_ok(_engage_target):
			_engage_target = _pick_auto_target(player, 4.0)
		if _engage_target != null:
			if _engage_target.global_position.distance_to(player.global_position) > 5.5:
				_engage_target = null
			else:
				_fight(_engage_target, delta)
				return
	var goal: Vector3 = _formation_point(player)
	if global_position.distance_to(goal) > 0.9:
		var spd: float = profile.move_speed * clampf(global_position.distance_to(goal) / 4.0, 0.45, 1.25)
		# Keep natural pace with a running player, but cap speed and ignore dodge bursts so allies
		# never rocket along as if dragged on a rigid leash.
		if player is CharacterBody3D and global_position.distance_to(goal) > 1.5:
			var player_dodging: bool = player is PlayerController and (player as PlayerController).current_state == PlayerController.State.DODGE
			if not player_dodging:
				var pv: Vector3 = (player as CharacterBody3D).velocity
				var match_spd: float = minf(Vector2(pv.x, pv.z).length() * 1.05, profile.move_speed * 1.45)
				spd = maxf(spd, match_spd)
		# In the lens: hurry out of it (straight to the flank slot) rather than drifting through.
		if _camera_blocking_at(global_position, player):
			spd = maxf(spd, profile.move_speed * 1.3)
		_move_to(goal, spd, delta)
	else:
		if _cmd != null:
			_cmd.data["arrived"] = true
		_halt(delta)
		var pf: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else facing_direction
		set_facing(_turn_toward(facing_direction, pf, 4.0 * delta))


func _run_hold(delta: float, cmd: SquadCommand) -> void:
	if not cmd.data.has("spot"):
		var tgt_s: String = String(cmd.args.get("target", "")).to_lower()
		var resolved_spot: Vector3 = Vector3.INF
		if cmd.args.has("spot") and cmd.args["spot"] is Vector3:
			resolved_spot = cmd.args["spot"] as Vector3
		elif tgt_s.contains("mark") or tgt_s.contains("ping") or tgt_s.contains("location") or tgt_s.contains("spot"):
			var wi: Node = get_tree().get_first_node_in_group("world_intel") if get_tree() != null else null
			if wi != null and wi.has_method("get_location_mark"):
				resolved_spot = wi.call("get_location_mark") as Vector3
				if not cmd.args.has("engage_r"):
					cmd.args["engage_r"] = 14.0
		if resolved_spot == Vector3.INF:
			resolved_spot = global_position
		cmd.data["spot"] = resolved_spot
		cmd.args["spot"] = resolved_spot   # survives an interruption (rally / skill) -> resumes at the same spot
		cmd.step = "holding " + String(cmd.args.get("lane", "")) if cmd.args.has("lane") else "holding"
	var spot: Vector3 = cmd.data["spot"]
	var near: EnemyAI = _nearest_enemy(global_position, float(cmd.args.get("engage_r", 3.5)))
	if near != null:
		_fight(near, delta, true)
		return
	if global_position.distance_to(spot) > 0.8:
		_move_to(spot, profile.move_speed, delta)
	else:
		cmd.data["arrived"] = true
		_halt(delta)


## March to a marked location (or ahead of the player), engaging and holding any enemies encountered along the way.
func _run_advance(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if not cmd.data.has("spot"):
		var base_spot: Vector3 = Vector3.INF
		if cmd.args.has("spot") and cmd.args["spot"] is Vector3:
			base_spot = cmd.args["spot"] as Vector3
		if base_spot == Vector3.INF and get_tree() != null:
			var wi: Node = get_tree().get_first_node_in_group("world_intel")
			if wi != null and wi.has_method("get_location_mark"):
				base_spot = wi.call("get_location_mark") as Vector3
		if base_spot == Vector3.INF and player != null:
			var fwd: Vector3 = player.call("get_facing_direction") as Vector3 if player.has_method("get_facing_direction") else -player.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
			base_spot = player.global_position + fwd * 24.0
		if base_spot == Vector3.INF:
			base_spot = global_position
		# Spread multiple allies laterally around the marked spot so they don't stack.
		var to_spot: Vector3 = base_spot - global_position
		to_spot.y = 0.0
		var dir: Vector3 = to_spot.normalized() if to_spot.length_squared() > 0.01 else Vector3.FORWARD
		var right := Vector3(-dir.z, 0.0, dir.x)
		var slot_spot: Vector3 = base_spot + right * (float(slot_index) - 1.0) * 1.4
		cmd.data["spot"] = slot_spot
		cmd.args["spot"] = slot_spot
	var spot: Vector3 = cmd.data["spot"]
	var engage_r: float = float(cmd.args.get("engage_r", 14.0))
	var near: EnemyAI = _nearest_enemy(global_position, engage_r)
	if near != null:
		cmd.step = "engaging ahead"
		_fight(near, delta, true)
		return
	if global_position.distance_to(spot) > 1.4:
		cmd.step = "advancing to mark"
		_move_to(spot, profile.move_speed, delta)
	else:
		cmd.data["arrived"] = true
		cmd.step = "holding mark"
		_halt(delta)


func _run_retreat_order(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if player == null:
		_halt(delta)
		return
	cmd.step = "falling back"
	var centroid: Vector3 = _threat_centroid(player.global_position, 15.0)
	var away: Vector3 = (player.global_position - centroid) if centroid != Vector3.INF else -(player.call("get_facing_direction") as Vector3)
	away.y = 0.0
	var goal: Vector3 = player.global_position + away.normalized() * 3.5 + Vector3(-away.z, 0, away.x).normalized() * (float(slot_index) - 1.0) * 1.6
	if global_position.distance_to(goal) > 0.8:
		_move_to(goal, profile.move_speed * 1.15, delta)
	else:
		cmd.data["arrived"] = true
		var self_threat: EnemyAI = _nearest_enemy(global_position, 2.2)
		if self_threat != null:
			_fight(self_threat, delta, true)
		else:
			_halt(delta)


func _run_attack(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.data.has("enemy"):
			finish_current("target down")
			say_event("kill", 0)
			return
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null:
			say("No target in sight.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
		say_event("engage", 0)
	cmd.step = "engaging"
	_fight(e, delta)


func _run_taunt_cmd(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	# "Take aggro": prefer enemies currently on the player, falling back to idle/ally-targeting foes nearby.
	if bool(cmd.args.get("area", false)) and player != null:
		var targets: Array[EnemyAI] = []
		var near_pool: Array[EnemyAI] = _active_enemies(player.global_position, 14.0)
		for en in near_pool:
			if en.get_current_target() == player:
				targets.append(en)
		if targets.is_empty():
			targets = near_pool
		if targets.is_empty():
			targets = _active_enemies(global_position, 14.0)
		if targets.is_empty():
			var fallback: EnemyAI = _resolve_enemy(String(cmd.args.get("target", "")), player)
			if fallback != null and _enemy_ok(fallback):
				cmd.args["area"] = false
				cmd.data["enemy"] = fallback
			else:
				say("Nothing around to taunt.", "refuse", 1)
				finish_current("no target")
				return
		else:
			var anchor: Vector3 = player.global_position if not near_pool.is_empty() else targets[0].global_position
			var reach: float = 5.0 if not near_pool.is_empty() else 7.0
			if global_position.distance_to(anchor) > reach:
				if cmd.timer > _approach_timeout(10.0, anchor, cmd):
					say("Can't reach them to take aggro.", "refuse", 1)
					finish_current("out of range")
					return
				_move_to(anchor, profile.move_speed * 1.2, delta)
				return
			_taunt_cd = profile.taunt_cooldown
			_play(["Taunt", "Cheer", "Taunt_Longer"], 0.8, true)
			_start_action("taunt", 0.55, -1.0, Callable())
			say_event("taunt", 1)
			for en in targets:
				if _enemy_ok(en):
					en.apply_taunt(self, -1.0, 4.0)
			finish_current("took aggro x%d" % targets.size())
			return
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.data.has("enemy"):
			finish_current("target gone")
			return
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null or not _enemy_ok(e):
			say("Nothing to taunt.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
	if global_position.distance_to(e.global_position) > 7.0:
		if cmd.timer > _approach_timeout(12.0, e.global_position, cmd):
			say("Can't get close enough to taunt.", "refuse", 1)
			finish_current("out of range")
			return
		_move_to(e.global_position, profile.move_speed * 1.15, delta)
		return
	_do_taunt(e, false)
	if String(cmd.args.get("lure", "")) == "player":
		cmd.verb = "kite"
		cmd.step = "sustain"
		cmd.data["enemy"] = e
		cmd.data["sustain_t"] = 0.0
		cmd.data["center"] = e.global_position
		cmd.data["ang"] = atan2(global_position.z - e.global_position.z, global_position.x - e.global_position.x)
		return
	finish_current("taunted")


# ------------------------------------------------------------------ bodyguard

func _run_bodyguard(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var ward: Node3D = cmd.data.get("ward", null) as Node3D
	if ward == null or not is_instance_valid(ward):
		ward = _resolve_ward(String(cmd.args.get("target", "player")), player)
		cmd.data["ward"] = ward
	if ward == null:
		_run_follow(delta, player, cmd)
		return
	# Ward died: stand down cleanly (no auto-revive; that is a separate order).
	var ward_dead: bool = (ward is SquadAlly and (ward as SquadAlly).is_downed) \
		or (ward is PlayerController and (ward as PlayerController).current_state == PlayerController.State.DEAD)
	if ward_dead:
		say("%s is down. Standing by." % (ward.call("get_display_name") if ward.has_method("get_display_name") else "The ward"), "bodyguard_lost", 2)
		finish_current("ward down")
		return
	if cmd.step.is_empty():
		say_event("bodyguard", 1, profile.line("ack"))
	var wpos: Vector3 = ward.global_position
	# Intercept: nearest enemy closing on the ward (prefer ones targeting the ward).
	var threat: EnemyAI = null
	var best: float = INTERCEPT_RADIUS
	for e in _active_enemies(wpos, INTERCEPT_RADIUS + 2.0):
		var d: float = e.global_position.distance_to(wpos)
		if e.get_current_target() == ward:
			d -= 2.0
		if d < best:
			best = d
			threat = e
	var my_d: float = global_position.distance_to(wpos)
	if threat != null and my_d <= LEASH_RADIUS:
		cmd.step = "intercepting"
		if threat.get_current_target() == ward and _taunt_cd <= 0.0:
			_do_taunt(threat, false)
		_fight(threat, delta)
		return
	# Hold the guard spot between the ward and the nearest threat (or just off its shoulder).
	cmd.step = "guarding"
	var centroid: Vector3 = _threat_centroid(wpos, 16.0)
	var spot: Vector3
	if centroid != Vector3.INF:
		var dir: Vector3 = centroid - wpos
		dir.y = 0.0
		spot = wpos + dir.normalized() * 1.7
	else:
		var f: Vector3 = ward.call("get_facing_direction") if ward.has_method("get_facing_direction") else Vector3.FORWARD
		spot = wpos + f * 1.4 + Vector3(-f.z, 0, f.x) * 1.0
	if global_position.distance_to(spot) > 0.6:
		_move_to(spot, profile.move_speed * (1.3 if my_d > LEASH_RADIUS else 1.0), delta)
	else:
		_halt(delta)
		if centroid != Vector3.INF:
			set_facing(centroid - global_position)


# ------------------------------------------------------------------ kite (approach -> provoke -> confirm -> sustain)

func _run_kite(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	_kite_logic(delta, player, cmd, cmd.combo_id == 0)


## Shared by plain kite and the kiter/lurer halves of combos. Returns nothing; posts combo events.
func _kite_logic(delta: float, player: Node3D, cmd: SquadCommand, standalone: bool) -> void:
	if bool(cmd.data.get("released", false)):
		finish_current("combo complete")
		return
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		var near_pos: Vector3 = global_position
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null:
			var chasing: Array[EnemyAI] = _enemies_targeting_me()
			e = chasing[0] if not chasing.is_empty() else null
		if e == null:
			if cmd.step == "sustain" or cmd.step == "clear":
				finish_current("all clear")
			else:
				say("Nothing to kite.", "refuse", 1)
				finish_current("no target")
				_post_combo(cmd, "failed", {})
			return
		cmd.data["enemy"] = e
		if cmd.step.is_empty() or cmd.step == "sustain":
			cmd.step = "approach" if cmd.step.is_empty() else cmd.step
		near_pos = e.global_position
		if not cmd.data.has("center"):
			cmd.data["center"] = near_pos
	if cmd.step.is_empty():
		cmd.step = "approach"
	match cmd.step:
		"approach":
			cmd.data["approach_t"] = float(cmd.data.get("approach_t", 0.0)) + delta
			if float(cmd.data["approach_t"]) > _approach_timeout(9.0, e.global_position, cmd):
				_kite_fallback(cmd, e, "Can't reach it — I'll fight from here.")
				return
			if global_position.distance_to(e.global_position) > 5.0:
				_move_to(e.global_position, profile.move_speed * 1.1, delta)
			else:
				cmd.step = "provoke"
		"fallback":
			# Phase failed: plain fight on the target; a combo partner still gets its signal.
			if not _enemy_ok(e):
				finish_current("fallback done")
				return
			_fight(e, delta)
		"provoke":
			if _taunt_cd <= 0.0:
				_do_taunt(e, false)
				cmd.step = "confirm"
				cmd.data["confirm_t"] = 0.0
			else:
				# Re-poke: dart in, land a hit, then confirm.
				if global_position.distance_to(e.global_position) > profile.attack_range:
					_move_to(e.global_position, profile.move_speed * 1.25, delta)
				elif _attack_cd <= 0.0:
					_melee(e)
					cmd.step = "confirm"
					cmd.data["confirm_t"] = 0.0
		"confirm":
			cmd.data["confirm_t"] = float(cmd.data.get("confirm_t", 0.0)) + delta
			_back_off(e, delta)
			if e.get_current_target() == self:
				cmd.step = "sustain"
				cmd.data["sustain_t"] = 0.0
				cmd.data["center"] = e.global_position
				cmd.data["ang"] = atan2(global_position.z - e.global_position.z, global_position.x - e.global_position.x)
				say_event("kite", 0, profile.line("taunt"))
			elif float(cmd.data["confirm_t"]) > 1.4:
				cmd.data["provoke_fails"] = int(cmd.data.get("provoke_fails", 0)) + 1
				if int(cmd.data["provoke_fails"]) >= 3:
					_kite_fallback(cmd, e, "It won't take the bait — fighting it head-on.")
				else:
					cmd.step = "provoke"
		"sustain":
			_circle_kite(delta, cmd, e)
			cmd.data["sustain_t"] = float(cmd.data.get("sustain_t", 0.0)) + delta
			# Lost the enemy's attention for a while -> re-poke it.
			if e.get_current_target() != self:
				cmd.data["lost_t"] = float(cmd.data.get("lost_t", 0.0)) + delta
				if float(cmd.data["lost_t"]) > 1.0:
					cmd.data["lost_t"] = 0.0
					cmd.step = "provoke"
			else:
				cmd.data["lost_t"] = 0.0
			if not cmd.data.get("ready_sent", false) and float(cmd.data["sustain_t"]) > 2.6:
				cmd.data["ready_sent"] = true
				_post_combo(cmd, "ready", {"center": _cluster_centroid()})
				if not standalone:
					say_event("combo_ready", 2)
			if bool(cmd.data.get("clear", false)):
				cmd.step = "clear"
				cmd.data["clear_t"] = 0.0
				say_event("clear", 2, profile.line("combo_go"))
			elif standalone and float(cmd.data["sustain_t"]) > float(cmd.args.get("duration", 45.0)):
				finish_current("kited")
		"clear":
			# Break off outward so the artillery can drop the payload on the cluster.
			cmd.data["clear_t"] = float(cmd.data.get("clear_t", 0.0)) + delta
			var cc: Vector3 = _cluster_centroid()
			var out: Vector3 = global_position - cc
			out.y = 0.0
			if out.length_squared() < 0.01:
				out = -facing_direction
			_move_dir(out.normalized(), profile.move_speed * 1.35, delta)
			if float(cmd.data["clear_t"]) > 1.6:
				cmd.step = "sustain_after"
		"sustain_after":
			# Wait for the payload, but never forever (the release signal may have been missed).
			_halt(delta)
			cmd.data["after_t"] = float(cmd.data.get("after_t", 0.0)) + delta
			if float(cmd.data["after_t"]) > 3.0:
				finish_current("combo window over")


## Report a failed tactic phase and fall back to a straight fight. In a combo the partner is still
## signalled (the payload lands on the fight instead of a kited cluster).
func _kite_fallback(cmd: SquadCommand, e: EnemyAI, why: String) -> void:
	say(why, "phase_failed", 2)
	cmd.step = "fallback"
	if manager != null and manager.has_method("log_event"):
		manager.call("log_event", get_display_name(), "kite phase failed", why)
	if cmd.combo_id > 0 and not cmd.data.get("ready_sent", false):
		cmd.data["ready_sent"] = true
		_post_combo(cmd, "ready", {"center": e.global_position if _enemy_ok(e) else global_position})


func _circle_kite(delta: float, cmd: SquadCommand, e: EnemyAI) -> void:
	var center: Vector3 = cmd.data.get("center", e.global_position)
	var lure: Variant = cmd.args.get("lure_to", null)
	if lure == null and String(cmd.args.get("lure", "")) == "player":
		var pl: Node3D = _player()
		if pl != null:
			lure = pl.global_position
	if lure is Vector3:
		# Bait: drag the chaser to the ambush / the squad and circle THERE, close enough for them to spring.
		center = center.lerp(lure as Vector3, clampf(1.6 * delta, 0.0, 1.0))
		if not cmd.data.has("lure_r"):
			cmd.data["lure_r"] = true
			cmd.data["radius"] = 3.2
	else:
		# Drift the centre slowly toward the pack so the circle stays around the enemies chasing us.
		center = center.lerp(_cluster_centroid(), clampf(0.4 * delta, 0.0, 1.0))
	cmd.data["center"] = center
	var r: float = float(cmd.data.get("radius", KITE_RADIUS))
	var dirn: float = float(cmd.data.get("dir", 1.0))
	var ang: float = float(cmd.data.get("ang", 0.0)) + dirn * (profile.move_speed * 0.85 / r) * delta
	cmd.data["ang"] = ang
	# Path recalculation every 0.4 s: probe the next waypoint; flip direction / tighten radius when blocked.
	cmd.data["repath"] = float(cmd.data.get("repath", 0.0)) - delta
	var wp: Vector3 = center + Vector3(cos(ang + dirn * 0.55), 0.0, sin(ang + dirn * 0.55)) * r
	wp.y = global_position.y
	if float(cmd.data["repath"]) <= 0.0:
		cmd.data["repath"] = 0.4
		if not _point_walkable(wp):
			# Blocked: reverse and swing wider (a tighter circle would let the chaser catch us).
			cmd.data["dir"] = -dirn
			cmd.data["radius"] = minf(8.5, r + 1.0)
			cmd.data["blocked"] = int(cmd.data.get("blocked", 0)) + 1
			# Repeatedly boxed in at max width: pull the circle toward open ground (our own position).
			if r >= 8.4:
				cmd.data["center"] = center.lerp(global_position, 0.5)
				cmd.data["radius"] = KITE_RADIUS
	_move_to(wp, profile.move_speed * 0.95, delta, false)
	# Keep one eye on the chaser.
	set_facing(e.global_position - global_position)


func _back_off(e: EnemyAI, delta: float) -> void:
	var away: Vector3 = global_position - e.global_position
	away.y = 0.0
	if away.length() < 3.5:
		_move_dir(away.normalized(), profile.move_speed, delta)
	else:
		_halt(delta)
	set_facing(e.global_position - global_position)


# ------------------------------------------------------------------ nuke / mine

func _run_nuke(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if cmd.step.is_empty():
		var e: EnemyAI = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null:
			say("No target worth the mana.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
		cmd.step = "approach"
	var tgt: EnemyAI = cmd.data["enemy"] as EnemyAI
	if cmd.step == "approach":
		if not _enemy_ok(tgt):
			finish_current("target gone")
			return
		if global_position.distance_to(tgt.global_position) > 9.0:
			_move_to(tgt.global_position, profile.move_speed, delta)
			return
		cmd.step = "channel"
		say_event("nuke", 2, profile.line("combo_go"))
		begin_nuke(tgt.global_position, Callable(), tgt)
	elif cmd.step == "channel" and _action.is_empty():
		finish_current("released")


## Channels the AoE. Artillery uses its full nuke; others throw a weaker version (profile numbers).
## `track` keeps the ring on a moving enemy until the last 0.3 s.
func begin_nuke(pos: Vector3, on_release: Callable = Callable(), track: Node3D = null, channel_override: float = -1.0, radius_override: float = -1.0, dmg_override: int = -1) -> void:
	var channel: float = profile.nuke_channel_sec if channel_override < 0.0 else channel_override
	var radius: float = profile.nuke_radius if radius_override < 0.0 else radius_override
	var dmg: int = int(round(float(profile.nuke_damage if dmg_override < 0 else dmg_override) * (1.0 + _dmg_buff)))
	set_facing(pos - global_position)
	_show_cast_ring(pos, radius, channel)
	_play(["Spellcast_Long", "Spellcasting", "Spellcast_Raise"], channel, true)
	_start_action("channel", channel, channel, func() -> void:
		var at: Vector3 = _cast_ring.global_position if _cast_ring != null and is_instance_valid(_cast_ring) else pos
		_aoe_blast(at, radius, dmg, "ally_nuke", Color(0.75, 0.5, 1.0))
		_play(["Spellcast_Shoot", "Spellcasting"], 0.4, true)
		if on_release.is_valid():
			on_release.call()
	)
	_action_data_track = track


var _action_data_track: Node3D = null


func plant_mine(pos: Vector3) -> void:
	if _mine != null and is_instance_valid(_mine):
		_mine.queue_free()
	_mine = Node3D.new()
	_mine.name = "MirrorSigil_" + profile.ally_name
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.7
	tm.outer_radius = 3.0
	tm.rings = 48
	tm.ring_segments = 4
	mi.mesh = tm
	mi.scale = Vector3(1, 0.05, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.7, 0.45, 1.0, 0.75)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mine.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(0.7, 0.45, 1.0)
	l.light_energy = 1.2
	l.omni_range = 4.0
	l.position = Vector3.UP * 0.4
	_mine.add_child(l)
	GoreFXScript.host_for(self).add_child(_mine)
	_mine.global_position = pos + Vector3.UP * 0.05
	GoreFXScript.flash_light(self, pos + Vector3.UP, Color(0.7, 0.45, 1.0), 3.0, 0.3, 5.0)


func clear_mine() -> void:
	if _mine != null and is_instance_valid(_mine):
		_mine.queue_free()
	_mine = null


func get_mine_position() -> Vector3:
	return _mine.global_position if _mine != null and is_instance_valid(_mine) else Vector3.INF


func detonate_mine() -> int:
	if _mine == null or not is_instance_valid(_mine):
		return 0
	var at: Vector3 = _mine.global_position
	clear_mine()
	_play(["Spellcast_Shoot", "Spellcasting"], 0.4, true)
	return _aoe_blast(at, 3.4, maxi(profile.nuke_damage, 40) + 10, "ally_detonate", Color(0.85, 0.45, 1.0))


func _aoe_blast(at: Vector3, radius: float, dmg: int, source: String, col: Color) -> int:
	GoreFXScript.shockwave_ring(self, at + Vector3.UP * 0.08, radius, col, 0.45, 0.4)
	GoreFXScript.flash_light(self, at + Vector3.UP * 1.0, col, 8.0, 0.35, radius * 2.5)
	GoreFXScript.dust_puff(self, at, radius * 0.6, 40, Color(col.r, col.g, col.b, 0.6), 3.0)
	if AudioManager.instance != null:
		AudioManager.instance.play_at("glass_shatter", at, 0.0)
		AudioManager.instance.play_at("landing_slam", at, -3.0)
	else:
		GameFeelScript.play_sound(self, "clang", at, -2.0, 1.4)
		GameFeelScript.play_sound(self, "land_heavy", at, -3.0, 1.2)
	GameFeelScript.add_trauma(self, 0.3, at)
	var hits: int = 0
	var dmg_mult: float = 1.3 if _is_massacre() else 1.0
	for e in _active_enemies(at, radius + 0.5):
		var d: Vector3 = e.global_position - at
		if Vector2(d.x, d.z).length() <= radius and absf(d.y) < 2.5:
			if e.apply_damage(int(round(float(dmg) * dmg_mult)), true, source, self):
				hits += 1
				var push: Vector3 = Vector3(d.x, 0, d.z).normalized() * 6.0
				e.add_knockback(push)
	var sc: SquadCoordinator = SquadCoordinator.get_instance()
	if sc != null:
		sc.broadcast_noise(at, 16.0)
	_hide_cast_ring()
	return hits


func _show_cast_ring(pos: Vector3, radius: float, dur: float) -> void:
	if _cast_ring == null or not is_instance_valid(_cast_ring):
		_cast_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9
		tm.outer_radius = 1.0
		tm.rings = 48
		tm.ring_segments = 4
		_cast_ring.mesh = tm
		_cast_ring_mat = StandardMaterial3D.new()
		_cast_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cast_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cast_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_cast_ring.material_override = _cast_ring_mat
		_cast_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		GoreFXScript.host_for(self).add_child(_cast_ring)
	_cast_ring.visible = true
	_cast_ring.global_position = pos + Vector3.UP * 0.06
	_cast_ring.scale = Vector3(radius, 0.08, radius)
	_cast_ring_mat.albedo_color = Color(0.7, 0.5, 1.0, 0.2)
	var tw := create_tween()
	tw.tween_property(_cast_ring_mat, "albedo_color:a", 0.9, maxf(0.05, dur))


func _hide_cast_ring() -> void:
	if _cast_ring != null and is_instance_valid(_cast_ring):
		_cast_ring.visible = false
	_action_data_track = null


# ------------------------------------------------------------------ combos (one half each)

func _post_combo(cmd: SquadCommand, event: String, data: Dictionary) -> void:
	if cmd.combo_id > 0 and manager != null and manager.has_method("combo_event"):
		manager.call("combo_event", cmd.combo_id, self, cmd.combo_part, event, data)


func _run_combo_part(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	match cmd.combo_part:
		"kiter":
			_kite_logic(delta, player, cmd, false)
		"nuker":
			_run_nuker(delta, player, cmd)
		"charger":
			_run_charger(delta, player, cmd)
		"finisher":
			_run_finisher(delta, player, cmd)
		"trapper":
			_run_trapper(delta, player, cmd)
		"lurer":
			_run_lurer(delta, player, cmd)
		"solo_kite_nuke":
			_run_solo_kite_nuke(delta, player, cmd)
		"solo_charge_finish":
			_run_solo_charge_finish(delta, player, cmd)
		"solo_lure_detonate":
			_run_solo_lure(delta, player, cmd)
		_:
			finish_current("unknown part")


func _run_nuker(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if cmd.step.is_empty():
		cmd.step = "waiting"
		say_event("ack", 1)
	match cmd.step:
		"waiting":
			# Stay out of the kite circle, within casting range of it.
			var center: Vector3 = cmd.data.get("watch", player.global_position if player != null else global_position)
			var to_me: Vector3 = global_position - center
			to_me.y = 0.0
			var want: float = 8.0
			if absf(to_me.length() - want) > 1.2:
				var spot: Vector3 = center + (to_me.normalized() if to_me.length_squared() > 0.01 else Vector3.BACK) * want
				_move_to(spot, profile.move_speed, delta)
			else:
				_halt(delta)
				set_facing(center - global_position)
			if cmd.data.has("go_pos"):
				cmd.step = "casting"
				var gp: Vector3 = cmd.data["go_pos"]
				_post_combo(cmd, "casting", {})
				say_event("nuke", 2, profile.line("combo_go"))
				begin_nuke(gp, func() -> void:
					_post_combo(cmd, "released", {})
				, cmd.data.get("track", null) as Node3D)
		"casting":
			if _action.is_empty():
				finish_current("released")


func _run_charger(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.step == "done":
			finish_current("charged")
			return
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null:
			say("No one to charge.", "refuse", 1)
			_post_combo(cmd, "failed", {})
			finish_current("no target")
			return
		cmd.data["enemy"] = e
		cmd.step = "approach"
	match cmd.step:
		"approach":
			var d: float = global_position.distance_to(e.global_position)
			if d > 6.5:
				_move_to(e.global_position, profile.move_speed * 1.1, delta)
			elif d < 2.2:
				_back_off(e, delta)
			else:
				cmd.step = "charging"
				say_event("charge", 2, profile.line("combo_go"))
				start_charge(e, func(hit: bool) -> void:
					if hit:
						cmd.step = "done"
						_post_combo(cmd, "knocked", {"enemy": e})
					else:
						cmd.step = "approach"
				)
		"charging":
			pass
		"done":
			# Knocked down: pile in with the finisher until it's dead (max 10 s).
			if cmd.combo_part == "solo_charge_finish":
				return   # the solo version switches to its own finisher phase
			if cmd.timer > 0.0 and not cmd.data.has("done_t"):
				cmd.data["done_t"] = cmd.timer
			if not _enemy_ok(e) or cmd.timer - float(cmd.data.get("done_t", cmd.timer)) > 10.0:
				finish_current("charged")
				return
			_fight(e, delta)


func _run_finisher(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if cmd.step.is_empty():
		cmd.step = "waiting"
		say_event("ack", 1)
	match cmd.step:
		"waiting":
			var watch: EnemyAI = e if e != null else _resolve_enemy(String(cmd.args.get("target", "")), player)
			if watch != null and _enemy_ok(watch):
				var to_me: Vector3 = global_position - watch.global_position
				to_me.y = 0.0
				if absf(to_me.length() - 4.5) > 1.0:
					_move_to(watch.global_position + (to_me.normalized() if to_me.length_squared() > 0.01 else Vector3.LEFT) * 4.5, profile.move_speed, delta)
				else:
					_halt(delta)
			else:
				_halt(delta)
			if bool(cmd.data.get("go", false)) and e != null:
				cmd.step = "finishing"
		"finishing":
			if e == null or not _enemy_ok(e):
				finish_current("target gone")
				return
			# Get behind the downed enemy, then a heavy finisher (stunned + backstab multipliers apply).
			var behind: Vector3 = e.global_position - e.get_facing_direction() * 1.2
			if global_position.distance_to(behind) > 0.9 and global_position.distance_to(e.global_position) > 1.6:
				_move_to(behind, profile.move_speed * 1.5, delta, false)
				return
			set_facing(e.global_position - global_position)
			say_event("finish", 2, profile.line("combo_go"))
			_play(["Dualwield_Melee_Attack_Chop", "2H_Melee_Attack_Chop", "1H_Melee_Attack_Jump_Chop", "1H_Melee_Attack_Chop"], 0.5, true)
			_start_action("attack", 0.55, 0.28, func() -> void:
				if _enemy_ok(e):
					e.apply_damage(55, true, "ally_finisher", self)
					GoreFXScript.flash_light(self, e.global_position + Vector3.UP, Color(1.0, 0.8, 0.4), 4.0, 0.2, 4.0)
					GameFeelScript.add_trauma(self, 0.25, e.global_position)
				_post_combo(cmd, "finished", {})
			)
			cmd.step = "done"
		"done":
			# Follow through: keep hitting it until it drops (max 10 s), don't wander off after one blow.
			if not _action.is_empty():
				return
			if e == null or not _enemy_ok(e) or float(cmd.data.get("press_t", 0.0)) > 10.0:
				finish_current("finished")
				return
			cmd.data["press_t"] = float(cmd.data.get("press_t", 0.0)) + delta
			_fight(e, delta)


func _run_trapper(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if cmd.step.is_empty():
		cmd.step = "placing"
	match cmd.step:
		"placing":
			var p: Vector3 = cmd.data.get("point", global_position)
			if global_position.distance_to(p) > 2.0:
				_move_to(p, profile.move_speed, delta)
				return
			_play(["Spellcast_Raise", "Interact", "Use_Item"], 0.8, true)
			_start_action("channel", 0.8, 0.75, func() -> void:
				plant_mine(p)
				_post_combo(cmd, "planted", {"point": p})
				say_event("sigil", 2, profile.line("combo_ready"))
			)
			cmd.step = "armed"
		"armed":
			var mp: Vector3 = get_mine_position()
			if mp == Vector3.INF:
				return
			var to_me: Vector3 = global_position - mp
			to_me.y = 0.0
			if to_me.length() < 6.0:
				_move_dir(to_me.normalized() if to_me.length_squared() > 0.01 else Vector3.BACK, profile.move_speed, delta)
			else:
				_halt(delta)
				set_facing(mp - global_position)
			if bool(cmd.data.get("detonate", false)):
				_play(["Spellcast_Shoot"], 0.4, true)
				var hits: int = detonate_mine()
				_post_combo(cmd, "detonated", {"hits": hits})
				say_event("detonate", 2, profile.line("combo_go"))
				finish_current("detonated")
	if player == null:
		return


func _run_lurer(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if bool(cmd.data.get("done", false)):
		finish_current("lured")
		return
	if not cmd.data.has("point"):
		# Wait for the sigil.
		cmd.step = "waiting"
		var ps: Vector3 = player.global_position if player != null else global_position
		if global_position.distance_to(ps) > 3.0:
			_move_to(ps, profile.move_speed, delta)
		else:
			_halt(delta)
		return
	var p: Vector3 = cmd.data["point"]
	if cmd.step == "waiting" or cmd.step.is_empty():
		cmd.step = "approach"
	if cmd.step == "approach" or cmd.step == "provoke" or cmd.step == "confirm" or cmd.step == "fallback":
		_kite_logic(delta, player, cmd, false)
		if cmd.step == "sustain":
			cmd.step = "luring"
		return
	if cmd.step == "luring":
		# Run through the sigil to its far side; the chasers follow straight across it.
		var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
		var from: Vector3 = e.global_position if e != null and _enemy_ok(e) else global_position
		var through: Vector3 = p - from
		through.y = 0.0
		var goal: Vector3 = p + (through.normalized() if through.length_squared() > 0.01 else Vector3.BACK) * 4.5
		if global_position.distance_to(goal) > 1.0:
			_move_to(goal, profile.move_speed * 1.05, delta)
		else:
			_halt(delta)
			if e != null:
				set_facing(e.global_position - global_position)


func _run_solo_kite_nuke(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if cmd.step != "casting" and cmd.step != "after":
		_kite_logic(delta, player, cmd, false)
		if cmd.step == "sustain" and float(cmd.data.get("sustain_t", 0.0)) > 2.6:
			cmd.step = "casting"
			say("No artillery left — I'll do it myself!", "combo_go", 2)
			begin_nuke(_cluster_centroid(), func() -> void: cmd.step = "after")
	elif cmd.step == "after" and _action.is_empty():
		finish_current("solo nuke")


func _run_solo_charge_finish(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if not cmd.data.has("phase"):
		cmd.data["phase"] = "charge"
		cmd.combo_part = "solo_charge_finish"
	if String(cmd.data["phase"]) == "charge":
		_run_charger(delta, player, cmd)
		if current != cmd:
			return
		if cmd.step == "done":
			cmd.data["phase"] = "finish"
			cmd.data["go"] = true
			cmd.step = "finishing"
	else:
		_run_finisher(delta, player, cmd)


func _run_solo_lure(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if not cmd.data.has("phase"):
		cmd.data["phase"] = "plant"
	match String(cmd.data["phase"]):
		"plant":
			var p: Vector3 = cmd.data.get("point", global_position)
			if global_position.distance_to(p) > 2.0:
				_move_to(p, profile.move_speed, delta)
				return
			plant_mine(p)
			cmd.data["phase"] = "lure"
			cmd.step = "approach"
		"lure":
			_run_lurer(delta, player, cmd)
			if current != cmd:
				return
			var mp: Vector3 = get_mine_position()
			var trapped: int = 0
			for e in _enemies_targeting_me():
				if mp != Vector3.INF and Vector2(e.global_position.x - mp.x, e.global_position.z - mp.z).length() < 3.0:
					trapped += 1
			if trapped > 0 or cmd.timer > 14.0:
				detonate_mine()
				say_event("combo_go", 2)
				finish_current("solo detonate")


# ------------------------------------------------------------------ signature skills (AllySkill data)

func skill_remaining(s: AllySkill) -> float:
	return float(_skill_cd.get(s.id, 0.0))


func skill_ready(s: AllySkill) -> bool:
	return s != null and skill_remaining(s) <= 0.0


## HUD helper: [{name, remaining, cooldown, color}] for every skill.
func get_skill_states() -> Array:
	var out: Array = []
	if profile == null:
		return out
	for s in profile.get_skills():
		out.append({"name": s.display_name, "remaining": skill_remaining(s), "cooldown": s.cooldown, "color": s.color})
	return out


func add_damage_buff(frac: float, dur: float) -> void:
	_dmg_buff = maxf(_dmg_buff, frac)
	_dmg_buff_t = maxf(_dmg_buff_t, dur)


func add_damage_reduction(frac: float, dur: float) -> void:
	_dr = clampf(maxf(_dr, frac), 0.0, 0.9)
	_dr_t = maxf(_dr_t, dur)


func add_ward(amount: float, dur: float) -> void:
	_ward_hp = maxf(_ward_hp, amount)
	_ward_t = dur
	if _ward_fx == null or not is_instance_valid(_ward_fx):
		_ward_fx = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.85
		sm.height = 1.9
		_ward_fx.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(0.55, 0.75, 1.0, 0.18)
		_ward_fx.material_override = m
		_ward_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ward_fx.position = Vector3(0, 0.95, 0)
		add_child(_ward_fx)
	_ward_fx.visible = true


func _clear_ward() -> void:
	_ward_hp = 0.0
	_ward_t = 0.0
	if _ward_fx != null and is_instance_valid(_ward_fx):
		_ward_fx.visible = false


## Executes a skill on `target` (enemy / ally / player / null for self & area). Returns false when it can't.
func use_skill(s: AllySkill, target: Node3D = null) -> bool:
	if s == null or is_downed or not skill_ready(s):
		return false
	var ok: bool = false
	match s.effect:
		"war_cry":
			ok = _skill_war_cry(s)
		"shield_wall":
			ok = _skill_shield_wall(s)
		"ground_breaker":
			ok = _skill_ground_breaker(s)
		"shadowstep":
			ok = _skill_shadowstep(s, target as EnemyAI)
		"fan_of_blades":
			ok = _skill_fan(s)
		"smoke_bomb":
			ok = _skill_smoke(s)
		"flurry":
			ok = _skill_flurry(s, target as EnemyAI)
		"mending_light":
			ok = _skill_mend(s, target)
		"mirror_ward":
			ok = _skill_ward(s, target)
		"chain_arc":
			ok = _skill_chain_arc(s, target as EnemyAI)
		"mirror_barrage":
			ok = _skill_barrage(s, target as EnemyAI)
	if ok:
		_skill_cd[s.id] = s.cooldown
		_skill_gap = 1.5
		last_skill = s.display_name
		_combat_quiet = 0.0
		# Only voice skill callouts on explicit player-ordered skills so auto-cast combat skills never spam repetitive lines.
		if not s.voice_line.is_empty() and current != null and current.verb == "skill":
			say(s.voice_line, "skill", 1)
		if manager != null and manager.has_method("log_event"):
			manager.call("log_event", get_display_name(), "skill " + s.display_name, (target.call("get_display_name") if target != null and target.has_method("get_display_name") else ""))
	return ok


func _skill_war_cry(s: AllySkill) -> bool:
	var es: Array[EnemyAI] = _active_enemies(global_position, s.radius)
	_play(["Taunt_Longer", "Taunt", "Cheer"], 0.9, true)
	_start_action("taunt", 0.8, -1.0, Callable())
	for e in es:
		e.apply_taunt(self, 40.0, 3.0)
		var away: Vector3 = e.global_position - global_position
		e.add_knockback(Vector3(away.x, 0, away.z).normalized() * 3.0)
	for a in get_tree().get_nodes_in_group("squad_ally"):
		if a is SquadAlly and (a as SquadAlly).global_position.distance_to(global_position) <= 8.0:
			(a as SquadAlly).add_damage_buff(s.power, s.duration)
	GoreFXScript.shockwave_ring(self, global_position + Vector3.UP * 0.1, s.radius, s.color, 0.5, 0.3)
	GameFeelScript.add_trauma(self, 0.2, global_position)
	var sc: SquadCoordinator = SquadCoordinator.get_instance()
	if sc != null:
		sc.broadcast_noise(global_position, 14.0)
	return true


func _skill_shield_wall(s: AllySkill) -> bool:
	add_damage_reduction(0.7, s.duration)
	for a in get_tree().get_nodes_in_group("squad_ally"):
		if a is SquadAlly and a != self and (a as SquadAlly).global_position.distance_to(global_position) <= s.radius:
			(a as SquadAlly).add_damage_reduction(s.power, s.duration)
	var es: Array[EnemyAI] = _active_enemies(global_position, 8.0)
	es.sort_custom(func(x: EnemyAI, y: EnemyAI) -> bool: return x.global_position.distance_to(global_position) < y.global_position.distance_to(global_position))
	for i in range(mini(3, es.size())):
		es[i].apply_taunt(self, 30.0, 3.0)
	_play(["Blocking", "Block", "Block_Hit"], 1.0, true)
	_start_action("brace", 1.0, -1.0, Callable())
	GoreFXScript.shockwave_ring(self, global_position + Vector3.UP * 0.05, s.radius, s.color, 0.6, 0.2)
	return true


func _skill_ground_breaker(s: AllySkill) -> bool:
	_play(["2H_Melee_Attack_Chop", "1H_Melee_Attack_Jump_Chop", "1H_Melee_Attack_Chop"], 0.7, true)
	_start_action("attack", 0.7, 0.35, func() -> void:
		for e in _active_enemies(global_position, s.radius):
			if e.apply_damage(int(round(s.power * (1.0 + _dmg_buff))), true, "ally_skill", self):
				e.knock_down(s.duration, self)
		GoreFXScript.shockwave_ring(self, global_position + Vector3.UP * 0.05, s.radius, s.color, 0.4, 0.4)
		GoreFXScript.ground_crack(self, global_position, facing_direction, s.radius * 1.2, Color(1.0, 0.6, 0.25))
		GoreFXScript.dust_puff(self, global_position, s.radius * 0.6, 30)
		if AudioManager.instance != null:
			AudioManager.instance.play_at("landing_slam", global_position, 0.0)
		else:
			GameFeelScript.play_sound(self, "land_heavy", global_position, 0.0, 0.9)
		GameFeelScript.add_trauma(self, 0.3, global_position))
	return true


func _skill_shadowstep(s: AllySkill, e: EnemyAI) -> bool:
	if e == null or not _enemy_ok(e) or e.global_position.distance_to(global_position) > s.cast_range:
		return false
	var fwd: Vector3 = e.get_facing_direction()
	if Vector2(fwd.x, fwd.z).length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var extra_excl: Array[RID] = [e.get_rid()]
	var spot: Vector3 = Vector3.INF
	for cand in [
		e.global_position - fwd * 1.1,
		e.global_position + side * 1.1,
		e.global_position - side * 1.1,
	]:
		spot = _validate_stand_spot(cand as Vector3, e.global_position, true, false, 1.0, false, extra_excl)
		if spot != Vector3.INF:
			break
	if spot == Vector3.INF:
		return false
	GoreFXScript.dust_puff(self, global_position, 0.5, 14, Color(s.color.r, s.color.g, s.color.b, 0.5), 1.6)
	global_position = spot
	_last_pos = global_position
	_stuck_anchor_pos = global_position
	velocity = Vector3.ZERO
	set_facing(e.global_position - global_position)
	GoreFXScript.flash_light(self, global_position + Vector3.UP, s.color, 3.5, 0.25, 4.0)
	_play(["Dualwield_Melee_Attack_Stab", "1H_Melee_Attack_Stab"], 0.45, true)
	_start_action("attack", 0.45, 0.15, func() -> void:
		if _enemy_ok(e):
			e.apply_damage(int(round(s.power * (1.0 + _dmg_buff))), true, "ally_melee", self))
	_engage_target = e
	return true


func _skill_fan(s: AllySkill) -> bool:
	var es: Array[EnemyAI] = _active_enemies(global_position, s.radius)
	if es.is_empty():
		return false
	es.sort_custom(func(x: EnemyAI, y: EnemyAI) -> bool: return x.global_position.distance_to(global_position) < y.global_position.distance_to(global_position))
	_play(["Throw", "1H_Ranged_Shoot"], 0.5, true)
	var n: int = mini(3, es.size())
	_start_action("attack", 0.5, 0.2, func() -> void:
		for i in range(n):
			var e: EnemyAI = es[i]
			if _enemy_ok(e):
				e.apply_damage(int(round(s.power * (1.0 + _dmg_buff))), false, "ally_skill", self)
				GoreFXScript.sparks(self, e.global_position + Vector3.UP, global_position - e.global_position, s.color, 12))
	return true


func _skill_smoke(s: AllySkill) -> bool:
	for e in _active_enemies(global_position, s.radius):
		e.forget(self)
	add_damage_reduction(0.5, 1.0)
	GoreFXScript.dust_puff(self, global_position, s.radius * 0.5, 60, Color(0.55, 0.58, 0.62, 0.75), 1.2)
	GoreFXScript.flash_light(self, global_position + Vector3.UP, Color(0.8, 0.8, 0.85), 2.0, 0.3, 5.0)
	_play(["Dodge_Backward", "Dodge_Left"], 0.4, true)
	_start_action("dodge", 0.4, -1.0, Callable())
	return true


func _skill_flurry(s: AllySkill, e: EnemyAI) -> bool:
	if e == null or not _enemy_ok(e) or e.global_position.distance_to(global_position) > s.cast_range + 0.5:
		return false
	set_facing(e.global_position - global_position)
	_play(["Dualwield_Melee_Attack_Slice", "2H_Melee_Attack_Spinning", "Dualwield_Melee_Attack_Chop"], 1.2, true)
	_start_action("attack", 1.25, -1.0, Callable())
	for i in range(5):
		get_tree().create_timer(0.15 + 0.2 * float(i), false, true).timeout.connect(func() -> void:
			if is_instance_valid(self) and not is_downed and _enemy_ok(e) and global_position.distance_to(e.global_position) < s.cast_range + 1.0:
				e.apply_damage(int(round(s.power * (1.0 + _dmg_buff))), false, "ally_melee", self)
				if AudioManager.instance != null:
					AudioManager.instance.play_at("enemy_hit", e.global_position + Vector3.UP, -8.0)
				else:
					GameFeelScript.play_sound(self, "slash_flesh", e.global_position + Vector3.UP, -8.0, 1.2))
	return true


func _skill_mend(s: AllySkill, target: Node3D) -> bool:
	if target == null:
		target = _lowest_friend(s.cast_range)
	if target == null or target.global_position.distance_to(global_position) > s.cast_range:
		return false
	if target is SquadAlly:
		var a: SquadAlly = target as SquadAlly
		if a.is_downed or a.health >= a.max_health:
			return false
		a.health = mini(a.max_health, a.health + int(round(float(a.max_health) * s.power)))
		a.health_changed.emit(a, a.health, a.max_health)
	elif target is PlayerController:
		var p: PlayerController = target as PlayerController
		if p.current_state == PlayerController.State.DEAD or p.health >= p.max_health:
			return false
		p.health = mini(p.max_health, p.health + int(round(float(p.max_health) * s.power)))
		p.health_changed.emit(p.health, p.max_health)
	else:
		return false
	set_facing(target.global_position - global_position)
	_play(["Spellcast_Raise", "Spellcasting"], 0.6, true)
	_start_action("emote", 0.6, -1.0, Callable())
	GoreFXScript.flash_light(self, target.global_position + Vector3.UP, s.color, 4.0, 0.5, 4.0)
	GoreFXScript.dust_puff(self, target.global_position, 0.6, 18, Color(s.color.r, s.color.g, s.color.b, 0.6), 1.8)
	return true


func _skill_ward(s: AllySkill, target: Node3D) -> bool:
	if target == null:
		target = _most_pressed_friend(s.cast_range)
	if target == null or target.global_position.distance_to(global_position) > s.cast_range:
		return false
	if target is SquadAlly:
		if (target as SquadAlly).is_downed:
			return false
		(target as SquadAlly).add_ward(s.power, s.duration)
	elif target is PlayerController:
		var pw: PlayerController = target as PlayerController
		if pw.current_state == PlayerController.State.DEAD:
			return false
		pw.add_ally_ward(int(s.power), s.duration)
	else:
		return false
	_play(["Spellcast_Raise", "Spellcasting"], 0.5, true)
	_start_action("emote", 0.5, -1.0, Callable())
	GoreFXScript.flash_light(self, target.global_position + Vector3.UP, s.color, 3.0, 0.4, 3.5)
	return true


func _skill_chain_arc(s: AllySkill, first: EnemyAI) -> bool:
	if first == null or not _enemy_ok(first) or first.global_position.distance_to(global_position) > s.cast_range:
		return false
	var hits: Array[EnemyAI] = [first]
	var last: EnemyAI = first
	for _i in range(2):
		var nxt: EnemyAI = null
		var bd: float = s.radius
		for e in _active_enemies(last.global_position, s.radius):
			if hits.has(e):
				continue
			var d: float = e.global_position.distance_to(last.global_position)
			if d < bd:
				bd = d
				nxt = e
		if nxt == null:
			break
		hits.append(nxt)
		last = nxt
	set_facing(first.global_position - global_position)
	_play(["Spellcast_Shoot", "1H_Ranged_Shoot"], 0.45, true)
	var mults: Array[float] = [1.0, 0.72, 0.5]
	_start_action("channel", 0.45, 0.2, func() -> void:
		_chain_arc_hop(s, hits, mults, 0, global_position + Vector3.UP * 1.35 + facing_direction * 0.4))
	return true


## Chain Arc: a visible bolt flies to each target in turn; damage and stun land on arrival, then the next bolt
## jumps from that enemy to the next one.
func _chain_arc_hop(s: AllySkill, hits: Array[EnemyAI], mults: Array[float], i: int, from: Vector3) -> void:
	if i >= hits.size():
		return
	var e: EnemyAI = hits[i]
	if not _enemy_ok(e):
		_chain_arc_hop(s, hits, mults, i + 1, from)
		return
	_launch_bolt(from, e, s.color, 26.0, 0.09, func() -> void:
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if not _enemy_ok(e):
			var next_from: Vector3 = (e.global_position + Vector3.UP * 1.1) if (is_instance_valid(e) and e.is_inside_tree()) else from
			_chain_arc_hop(s, hits, mults, i + 1, next_from)
			return
		var landed: bool = e.apply_damage(int(round(s.power * mults[i] * (1.0 + _dmg_buff))), false, "ally_skill", self)
		if landed and not e.is_dead and not e.knockdown_immune:
			e.enter_stunned(s.duration)
		var at: Vector3 = e.global_position + Vector3.UP * 1.1
		GoreFXScript.sparks(self, at, at - from, s.color, 16)
		GoreFXScript.flash_light(self, at, s.color, 3.0, 0.15, 3.0)
		_chain_arc_hop(s, hits, mults, i + 1, at))


## Glowing projectile from `from` that homes on `target` at `speed` m/s; `on_hit` runs when it arrives.
func _launch_bolt(from: Vector3, target: Node3D, col: Color, speed: float, radius: float, on_hit: Callable) -> void:
	var host: Node = GoreFXScript.host_for(self)
	if host == null or not is_instance_valid(target):
		on_hit.call()
		return
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.radial_segments = 8
	sph.rings = 4
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col.lightened(0.35)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	mi.global_position = from
	var dur: float = clampf(from.distance_to(target.global_position + Vector3.UP) / maxf(1.0, speed), 0.06, 0.6)
	var tw := mi.create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(mi) and is_instance_valid(target):
			mi.global_position = from.lerp(target.global_position + Vector3.UP * 1.0, k), 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free()
		on_hit.call())
	GameFeelScript.play_sound(self, "whoosh_light", from, -10.0, 1.5)


## Artillery basic attack: hold 5.5-9.5 m from the target and fire bolts (_fire_bolt); back away from
## anything on us, staff-swipe only when cornered.
func _ranged_engage(e: EnemyAI, delta: float) -> void:
	var to_e: Vector3 = e.global_position - global_position
	to_e.y = 0.0
	var d: float = to_e.length()
	var close: EnemyAI = _nearest_enemy(global_position, 2.6)
	if close != null and close.get_current_target() == self:
		var away: Vector3 = global_position - close.global_position
		away.y = 0.0
		if away.length_squared() > 0.01 and _side_open(away.normalized()):
			_move_dir(away.normalized(), profile.move_speed * 1.15, delta)
			return
		_halt(delta)
		set_facing(close.global_position - global_position)
		if _attack_cd <= 0.0:
			if global_position.distance_to(close.global_position) <= profile.attack_range + 0.3:
				_melee(close)
			else:
				_fire_bolt(close)
		return
	if d > RANGED_MAX:
		_move_to(e.global_position - to_e.normalized() * (RANGED_MAX - 1.5), profile.move_speed, delta)
		return
	if d < RANGED_MIN and d > 0.01 and _side_open(-to_e.normalized()):
		_move_dir(-to_e.normalized(), profile.move_speed, delta)
		return
	_halt(delta)
	set_facing(to_e)
	if _attack_cd <= 0.0:
		_fire_bolt(e)


func _skill_barrage(s: AllySkill, e: EnemyAI) -> bool:
	if e == null or not _enemy_ok(e) or e.global_position.distance_to(global_position) > s.cast_range:
		return false
	begin_nuke(e.global_position, Callable(), e, s.duration, s.radius, int(s.power))
	return true


## Autonomous skill use. Returns true when a skill fired this tick.
func _auto_skills(player: Node3D) -> bool:
	if profile == null or _skill_gap > 0.0 or not _action.is_empty() or _dash_timer > 0.0:
		return false
	var defensive_only: bool = _is_ceasefire()
	for s in profile.get_skills():
		if not skill_ready(s) or s.auto_use.is_empty() or s.auto_use == "never":
			continue
		var tgt: Node3D = null
		var go: bool = false
		match s.auto_use:
			"ally_low":
				tgt = _lowest_friend(s.cast_range, 0.4)
				go = tgt != null
			"ally_pressed":
				tgt = _most_pressed_friend(s.cast_range, 2)
				go = tgt != null
			"self_chased_low":
				go = get_health_ratio() < 0.5 and not _enemies_targeting_me().filter(func(e: EnemyAI) -> bool: return e.global_position.distance_to(global_position) < 3.5).is_empty()
		if not go and not defensive_only:
			match s.auto_use:
				"swarmed":
					var origin: Vector3 = player.global_position if player != null else global_position
					go = _active_enemies(global_position, 6.0).filter(func(e: EnemyAI) -> bool: return e.is_aggroed()).size() >= 3 \
						or _active_enemies(origin, 5.0).filter(func(e: EnemyAI) -> bool: return e.is_aggroed()).size() >= 3
				"protect":
					go = _most_pressed_friend(s.radius, 2) != null or _enemies_targeting_me().size() >= 3
				"cluster":
					if s.effect == "mirror_barrage":
						tgt = _best_cluster_enemy(s.cast_range, s.radius, 2)
						go = tgt != null
					else:
						go = _active_enemies(global_position, s.radius).filter(func(e: EnemyAI) -> bool: return e.is_aggroed()).size() >= 2
				"engaged":
					if _engage_target != null and _enemy_ok(_engage_target) and _engage_target.global_position.distance_to(global_position) <= s.cast_range:
						tgt = _engage_target
						go = s.effect != "shadowstep" or _engage_target.get_current_target() != self or _engage_target.global_position.distance_to(global_position) > 3.0
				"stunned_target":
					for e in _active_enemies(global_position, s.cast_range + 0.5):
						if e.is_stunned():
							tgt = e
							go = true
							break
		if go and use_skill(s, tgt):
			return true
	return false


func _friends() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var p: Node3D = _player()
	if p != null and not (p is PlayerController and (p as PlayerController).current_state == PlayerController.State.DEAD):
		out.append(p)
	for a in get_tree().get_nodes_in_group("squad_ally"):
		if a is SquadAlly and not (a as SquadAlly).is_downed:
			out.append(a as Node3D)
	return out


func _friend_ratio(n: Node3D) -> float:
	if n is SquadAlly:
		return (n as SquadAlly).get_health_ratio()
	if n is PlayerController:
		var p: PlayerController = n as PlayerController
		return float(p.health) / float(maxi(1, p.max_health))
	return 1.0


func _lowest_friend(range_m: float, below: float = 0.98) -> Node3D:
	var best: Node3D = null
	var br: float = below
	for f in _friends():
		if f.global_position.distance_to(global_position) > range_m:
			continue
		var r: float = _friend_ratio(f)
		if r < br:
			br = r
			best = f
	return best


func _most_pressed_friend(range_m: float, min_attackers: int = 1) -> Node3D:
	var best: Node3D = null
	var bn: int = min_attackers - 1
	for f in _friends():
		if f.global_position.distance_to(global_position) > range_m:
			continue
		if f is SquadAlly and (f as SquadAlly)._ward_hp > 0.0:
			continue
		var n: int = 0
		for e in _active_enemies(f.global_position, 6.0):
			if e.get_current_target() == f:
				n += 1
		if n > bn:
			bn = n
			best = f
	return best


func _best_cluster_enemy(range_m: float, radius: float, min_others: int) -> EnemyAI:
	var best: EnemyAI = null
	var bn: int = min_others - 1
	for e in _active_enemies(global_position, range_m):
		if not e.is_aggroed():
			continue
		var n: int = _active_enemies(e.global_position, radius).size() - 1
		if n > bn:
			bn = n
			best = e
	return best


## Commanded skill ("Sera, smoke bomb", "Ivo heal Brannoc", Director `use_skill`).
func _run_skill(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var s: AllySkill = profile.find_skill(String(cmd.args.get("skill", "")))
	if s == null:
		say("I don't know that move.", "refuse", 1)
		finish_current("unknown skill")
		return
	if not skill_ready(s):
		say("%s needs %ds." % [s.display_name, int(ceil(skill_remaining(s)))], "refuse", 1)
		finish_current("cooldown")
		return
	var tsel: String = String(cmd.args.get("target", ""))
	var tgt: Node3D = cmd.data.get("target_node", null) as Node3D
	var had_cached: bool = cmd.data.has("target_node")
	if had_cached:
		var cached_ok: bool = tgt != null and is_instance_valid(tgt) and tgt.is_inside_tree()
		if cached_ok and s.target_kind == "enemy":
			cached_ok = tgt is EnemyAI and _enemy_ok(tgt as EnemyAI)
		elif cached_ok and s.target_kind == "ally":
			if tgt is SquadAlly:
				cached_ok = not (tgt as SquadAlly).is_downed
			elif tgt is PlayerController:
				cached_ok = (tgt as PlayerController).current_state != PlayerController.State.DEAD
		if not cached_ok:
			finish_current("target gone")
			return
	if tgt == null or not is_instance_valid(tgt):
		match s.target_kind:
			"enemy":
				tgt = _resolve_enemy(tsel, player)
				if tgt == null and _engage_target != null and _enemy_ok(_engage_target):
					tgt = _engage_target
				if tgt == null or not (tgt is EnemyAI and _enemy_ok(tgt as EnemyAI)):
					say("No target for %s." % s.display_name, "refuse", 1)
					finish_current("no target")
					return
			"ally":
				if tsel.is_empty():
					tgt = _lowest_friend(40.0, 1.01) if s.effect == "mending_light" else _most_pressed_friend(40.0, 0)
				elif tsel in ["me", "player", "you"]:
					tgt = player
				elif manager != null and manager.has_method("find_ally"):
					tgt = manager.call("find_ally", tsel) as Node3D
				if tgt is PlayerController and (tgt as PlayerController).current_state == PlayerController.State.DEAD:
					tgt = null
				if tgt is SquadAlly and (tgt as SquadAlly).is_downed:
					say("%s is down — needs revive." % (tgt as SquadAlly).get_display_name(), "refuse", 1)
					finish_current("target down")
					return
				if tgt == null:
					var living_f: Array[Node3D] = _friends()
					tgt = living_f[0] if not living_f.is_empty() else null
				if tgt == null:
					say("No target for %s." % s.display_name, "refuse", 1)
					finish_current("no target")
					return
		cmd.data["target_node"] = tgt
	cmd.step = s.display_name
	var need: float = s.cast_range if s.target_kind in ["enemy", "ally"] else 0.0
	if tgt != null and need > 0.0 and tgt.global_position.distance_to(global_position) > need - 0.3:
		_move_to(tgt.global_position, profile.move_speed * 1.2, delta)
		if cmd.timer > _approach_timeout(10.0, tgt.global_position, cmd):
			say("Can't get in range.", "refuse", 1)
			finish_current("out of range")
		return
	if not use_skill(s, tgt):
		say("%s fizzled." % s.display_name, "refuse", 1)
	finish_current("used " + s.id)


# ------------------------------------------------------------------ strategy primitives (surround / overwatch / ambush)

## Surround slot: reach the given angle around the target (relative to the target->player axis), then fight.
func _run_surround(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.data.has("enemy"):
			finish_current("target down")
			return
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null:
			finish_current("no target")
			return
		cmd.data["enemy"] = e
	var axis: Vector3 = (player.global_position - e.global_position) if player != null else -e.get_facing_direction()
	axis.y = 0.0
	if axis.length_squared() < 0.01:
		axis = Vector3.FORWARD
	if String(cmd.args.get("side", "")) == "rear":
		_sneak_attack(delta, cmd, e)
		return
	var ang: float = deg_to_rad(float(cmd.args.get("angle", 120.0)))
	var slot: Vector3 = e.global_position + axis.normalized().rotated(Vector3.UP, ang) * maxf(1.4, profile.attack_range * 0.85)
	if not bool(cmd.data.get("in_slot", false)) and global_position.distance_to(slot) > 1.0:
		cmd.step = "flanking"
		_move_to(slot, profile.move_speed * 1.15, delta, false)
		if cmd.timer > _approach_timeout(6.0, slot, cmd):
			cmd.data["in_slot"] = true
		return
	cmd.data["in_slot"] = true
	cmd.step = "attacking from " + String(cmd.args.get("side", "flank"))
	_fight(e, delta)


## Sneak attack / backstab: work round to the side the enemy is NOT facing (relative to where it is looking
## right now — it turns while chasing a bait), swinging wide past its front, then strike its back. If it turns
## on us, slip round again; if it targets us anyway, just fight. Ends when the target dies.
func _sneak_attack(delta: float, cmd: SquadCommand, e: EnemyAI) -> void:
	var ef: Vector3 = e.get_facing_direction()
	ef.y = 0.0
	ef = ef.normalized() if ef.length_squared() > 0.001 else Vector3.FORWARD
	var rel: Vector3 = global_position - e.global_position
	rel.y = 0.0
	var dist: float = rel.length()
	var behind_dot: float = rel.normalized().dot(ef) if dist > 0.01 else 0.0
	var on_me: bool = e.get_current_target() == self
	if on_me and dist < 3.5:
		cmd.step = "spotted — fighting"
		_fight(e, delta)
		return
	var reach: float = profile.attack_range
	if behind_dot < -0.35 and dist <= reach + 0.2:
		cmd.step = "backstabbing"
		_engage_target = e
		_combat_quiet = 0.0
		_halt(delta)
		set_facing(-rel)
		if _attack_cd <= 0.0:
			if not bool(cmd.data.get("called", false)):
				cmd.data["called"] = true
				say(["From behind!", "Didn't see me, did you?", "Back's open!"][_rng.randi() % 3], "sneak", 1)
			_melee(e)
		return
	cmd.step = "sneaking behind"
	var back: Vector3 = e.global_position - ef * maxf(1.2, reach * 0.8)
	# In front of / beside it: go round on the side we're already on, wide, so we never walk across its face.
	var goal: Vector3 = back
	if behind_dot > -0.2:
		var side: Vector3 = Vector3(-ef.z, 0.0, ef.x)
		var s: float = 1.0 if rel.dot(side) >= 0.0 else -1.0
		goal = e.global_position + side * s * 3.0 - ef * 0.8
	_move_to(goal, profile.move_speed * 1.2, delta, false)


## Overwatch: hang back behind the player, never melee unless cornered, fire skills at clusters / threats.
func _run_overwatch(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	cmd.step = "overwatch"
	if player == null:
		_halt(delta)
		return
	var c: Vector3 = _threat_centroid(player.global_position, 20.0)
	var away: Vector3 = (player.global_position - c) if c != Vector3.INF else -(player.call("get_facing_direction") as Vector3)
	away.y = 0.0
	var spot: Vector3 = player.global_position + away.normalized() * 6.0
	if global_position.distance_to(spot) > 1.2:
		_move_to(spot, profile.move_speed, delta)
	else:
		_halt(delta)
		if c != Vector3.INF:
			set_facing(c - global_position)
	# Offensive skills fire from range even if their auto rule wouldn't.
	for s in profile.get_skills():
		if not skill_ready(s) or s.target_kind != "enemy" or s.cast_range < 6.0:
			continue
		var t: EnemyAI = _best_cluster_enemy(s.cast_range, maxf(s.radius, 3.0), 1)
		if t == null:
			t = _nearest_enemy(global_position, s.cast_range)
		if t != null and use_skill(s, t):
			return
	var close: EnemyAI = _nearest_enemy(global_position, 2.0)
	if close != null and _attack_cd <= 0.0:
		_melee(close)


## Ambush: hold perfectly still at a spot until an enemy walks within `radius` (or one hits a squad-mate
## nearby), then everyone in the ambush springs at once (the manager broadcasts the trigger).
func _run_ambush(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if not cmd.data.has("spot"):
		cmd.data["spot"] = cmd.args.get("spot", global_position) as Vector3
	if bool(cmd.data.get("sprung", false)):
		var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
		if e == null or not _enemy_ok(e):
			e = _nearest_enemy(global_position, 10.0)
			cmd.data["enemy"] = e
		if e == null:
			finish_current("ambush over")
			return
		cmd.step = "springing"
		_fight(e, delta)
		return
	cmd.step = "lying in wait"
	var spot: Vector3 = cmd.data["spot"]
	if global_position.distance_to(spot) > 0.8:
		_move_to(spot, profile.move_speed, delta)
	else:
		_halt(delta)
	var trigger: EnemyAI = _nearest_enemy(spot, float(cmd.args.get("radius", 4.5)))
	if trigger != null and trigger.is_aggroed():
		if manager != null and manager.has_method("spring_ambush"):
			manager.call("spring_ambush", trigger)
		else:
			cmd.data["sprung"] = true
			cmd.data["enemy"] = trigger
	if cmd.timer > 45.0:
		finish_current("ambush timed out")
	if player == null:
		return


# ------------------------------------------------------------------ peel / hit-and-run / errands

## Peel: pull the enemy that is on the player onto ourselves (taunt lock) and keep it busy.
func _run_peel(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.data.has("enemy"):
			finish_current("peeled target down")
			return
		var best: EnemyAI = null
		var bd: float = INF
		if player != null:
			for en in _active_enemies(player.global_position, 12.0):
				var d: float = en.global_position.distance_to(player.global_position) - (5.0 if en.get_current_target() == player else 0.0)
				if d < bd:
					bd = d
					best = en
		if best == null:
			say("Nothing on you to peel.", "refuse", 1)
			finish_current("nothing to peel")
			return
		cmd.data["enemy"] = best
		e = best
		say_event("peel", 2, profile.line("taunt"))
	cmd.step = "peeling"
	if e.get_current_target() != self and _taunt_cd <= 0.0 and global_position.distance_to(e.global_position) < 7.0:
		_do_taunt(e, false)
		return
	_fight(e, delta)
	if cmd.timer > 15.0:
		finish_current("peel held")


## Hit-and-run: dart in, one strike, sprint out, breathe, repeat.
func _run_hit_and_run(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.data.has("enemy"):
			say_event("kill", 0)
			finish_current("target down")
			return
		e = _resolve_enemy(String(cmd.args.get("target", "")), player)
		if e == null:
			say("No target for a raid.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
		cmd.step = "in"
	if not bool(cmd.data.get("engaged", false)):
		if global_position.distance_to(e.global_position) <= 8.0:
			cmd.data["engaged"] = true
		elif cmd.timer > _approach_timeout(16.0, e.global_position, cmd):
			say("Can't reach target for a raid.", "refuse", 1)
			finish_current("out of range")
			return
	match cmd.step:
		"in":
			if global_position.distance_to(e.global_position) > profile.attack_range:
				_move_to(e.global_position, profile.move_speed * 1.3, delta, false)
			elif _attack_cd <= 0.0:
				_melee(e)
				cmd.step = "out"
				cmd.data["out_t"] = 0.0
		"out":
			cmd.data["out_t"] = float(cmd.data.get("out_t", 0.0)) + delta
			var away: Vector3 = global_position - e.global_position
			away.y = 0.0
			if away.length() < 5.5 and float(cmd.data["out_t"]) < 2.0:
				_move_dir(away.normalized(), profile.move_speed * 1.3, delta)
			else:
				_halt(delta)
				set_facing(e.global_position - global_position)
				if float(cmd.data["out_t"]) > 2.2:
					cmd.step = "in"
	if bool(cmd.data.get("engaged", false)):
		cmd.data["raid_t"] = float(cmd.data.get("raid_t", 0.0)) + delta
		if float(cmd.data["raid_t"]) > 16.0:
			finish_current("raid over")


## Hunt wildlife: ambient creatures have no health, so a "hunt" is an exuberant chase that scatters them.
func _run_hunt(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var prey: Node3D = cmd.data.get("prey", null) as Node3D
	if prey == null or not is_instance_valid(prey):
		var best: Node3D = null
		var bd: float = 30.0
		var origin: Vector3 = player.global_position if player != null else global_position
		for n in get_tree().get_nodes_in_group("ambient_creature"):
			if n is Node3D and (n as Node3D).is_visible_in_tree():
				var d: float = (n as Node3D).global_position.distance_to(origin)
				if d < bd and absf((n as Node3D).global_position.y - origin.y) < 4.0:
					bd = d
					best = n as Node3D
		if best == null:
			say("No wildlife around here.", "refuse", 1)
			finish_current("no wildlife")
			return
		cmd.data["prey"] = best
		prey = best
		say_event("hunt", 1, "Tally-ho!")
	cmd.step = "chasing"
	if global_position.distance_to(prey.global_position) > 2.5:
		_move_to(prey.global_position, profile.move_speed * 1.2, delta)
	else:
		if prey.has_method("receive_fear"):
			prey.call("receive_fear", 1.0, global_position, 0.0)
		var fd: FaunaDirector = FaunaDirector.get_for(self)
		if fd != null:
			fd.emit_disturbance(global_position, 6.0, 1.0, "hunt")
		_play(["Cheer", "Taunt"], 0.8, true)
		_start_action("emote", 0.8, -1.0, Callable())
		finish_current("scattered the wildlife")
		return
	if cmd.timer > 12.0:
		say("Too quick for me.", "refuse", 0)
		finish_current("prey escaped")


## Destroy a prop: only safe breakables (the cracked pillar can crush enemies; crates; the gallery support).
## The boss's central mirror plane is never touched by allies.
func _run_destroy(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var prop: BreakableProp = cmd.data.get("prop", null) as BreakableProp
	if prop == null or not is_instance_valid(prop):
		var origin: Vector3 = player.global_position if player != null else global_position
		var bd: float = 20.0
		for n in get_tree().get_nodes_in_group("breakable"):
			var bp: BreakableProp = n as BreakableProp
			if bp == null or bp.current_state != BreakableProp.PropState.INTACT or not bp.is_visible_in_tree():
				continue
			if bp.prop_kind == BreakableProp.PropKind.CENTRAL_MIRROR_PLANE:
				continue
			var d: float = bp.global_position.distance_to(origin)
			if d < bd:
				bd = d
				prop = bp
		if prop == null:
			say("Nothing here I'm allowed to smash.", "refuse", 1)
			finish_current("no breakable")
			return
		cmd.data["prop"] = prop
		say_event("destroy", 1, profile.line("ack"))
	cmd.step = "smashing"
	var goal: Vector3 = prop.global_position
	if Vector2(global_position.x - goal.x, global_position.z - goal.z).length() > 2.2 or absf(global_position.y - goal.y) > 2.0:
		_move_to(goal, profile.move_speed, delta)
		if cmd.timer > 12.0:
			say("Can't get to it.", "refuse", 1)
			finish_current("unreachable")
		return
	set_facing(goal - global_position)
	_play(["2H_Melee_Attack_Chop", "1H_Melee_Attack_Chop"], 0.6, true)
	_start_action("attack", 0.6, 0.3, func() -> void:
		if is_instance_valid(prop):
			prop.trigger_break(true, self))
	finish_current("smashed")


## Interact: pull a lever / switch / chest for the player (only things that currently accept it).
func _run_interact(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var tgt: Node3D = cmd.data.get("thing", null) as Node3D
	if tgt == null or not is_instance_valid(tgt):
		var want_chest: bool = String(cmd.args.get("target", "")) == "chest"
		var groups: Array[String] = ["chest"]
		if not want_chest:
			groups.append("interactable_switch")
		var origin: Vector3 = player.global_position if player != null else global_position
		var bd: float = 18.0
		for grp in groups:
			for n in get_tree().get_nodes_in_group(grp):
				if n is SquadAlly or not (n is Node3D) or not n.has_method("interact"):
					continue
				if n.has_method("can_interact") and not bool(n.call("can_interact")):
					continue
				var d: float = (n as Node3D).global_position.distance_to(origin)
				if d < bd:
					bd = d
					tgt = n as Node3D
		if tgt == null:
			say("No chest around here." if want_chest else "Nothing here to use.", "refuse", 1)
			finish_current("nothing to interact")
			return
		cmd.data["thing"] = tgt
		say_event("interact", 1, profile.line("ack"))
	cmd.step = "using"
	if global_position.distance_to(tgt.global_position) > 1.8:
		_move_to(tgt.global_position, profile.move_speed, delta)
		if cmd.timer > 14.0:
			say("Can't reach it.", "refuse", 1)
			finish_current("unreachable")
		return
	_play(["Interact", "PickUp", "Use_Item"], 0.6, true)
	_start_action("emote", 0.6, -1.0, Callable())
	var ok: bool = bool(tgt.call("interact"))
	finish_current("used" if ok else "refused")
	if not ok:
		say("It won't budge from this side.", "refuse", 1)


# ------------------------------------------------------------------ revive

func _run_revive(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var who: SquadAlly = null
	if manager != null and manager.has_method("find_ally"):
		who = manager.call("find_ally", String(cmd.args.get("target", ""))) as SquadAlly
	if who == null or who == self:
		# No name: nearest downed ally.
		if manager != null and manager.has_method("nearest_downed"):
			who = manager.call("nearest_downed", global_position, self) as SquadAlly
	if who == null or not who.is_downed:
		say("Nobody needs reviving.", "refuse", 1)
		finish_current("nobody down")
		return
	_revive_target(who, delta, cmd)


func _revive_target(who: SquadAlly, delta: float, cmd: SquadCommand) -> void:
	if who == null or not is_instance_valid(who) or not who.is_downed:
		finish_current("nobody down")
		return
	if global_position.distance_to(who.global_position) > 1.6:
		if cmd.step != "channel" and cmd.timer > 10.0:
			say("Can't reach %s." % who.get_display_name(), "refuse", 1)
			finish_current("unreachable")
			return
		cmd.step = "moving"
		_move_to(who.global_position, profile.move_speed * 1.2, delta)
		return
	if cmd.step != "channel":
		cmd.step = "channel"
		say_event("revive_other", 2)
		set_facing(who.global_position - global_position)
		_play(["Interact", "PickUp", "Use_Item"], REVIVE_CHANNEL, true)
		_start_action("revive", REVIVE_CHANNEL, REVIVE_CHANNEL - 0.05, func() -> void:
			if is_instance_valid(who) and who.is_downed:
				who.revive(0.45)
			if current == cmd and cmd.verb == "revive":
				finish_current("revived")
		)
	elif _action != "revive" and cmd.timer > 14.0:
		finish_current("revive timed out")


# ------------------------------------------------------------------ panic stances

func _run_massacre(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	cmd.step = "berserk"
	if _engage_target == null or not _enemy_ok(_engage_target):
		_engage_target = _pick_auto_target(player, 22.0, true)
	if _engage_target != null:
		_fight(_engage_target, delta)
		cmd.data["quiet"] = 0.0
	else:
		cmd.data["quiet"] = float(cmd.data.get("quiet", 0.0)) + delta
		_run_follow(delta, player, null)


func _run_ceasefire(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	cmd.step = "holding fire"
	_engage_target = null
	# Never strike; sidestep anything swinging at us and stay on the player.
	var threat: EnemyAI = _nearest_enemy(global_position, 2.6)
	if threat != null:
		var away: Vector3 = global_position - threat.global_position
		away.y = 0.0
		_move_dir(away.normalized(), profile.move_speed, delta)
		return
	if player != null:
		var goal: Vector3 = _formation_point(player)
		if global_position.distance_to(goal) > 0.9:
			_move_to(goal, profile.move_speed, delta)
		else:
			_halt(delta)


func _run_scatter(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if not cmd.data.has("dir"):
		var origin: Vector3 = player.global_position if player != null else global_position
		var c: Vector3 = _threat_centroid(origin, 18.0)
		var away: Vector3 = (global_position - c) if c != Vector3.INF else (global_position - origin)
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3.FORWARD
		var ang: float = deg_to_rad(-55.0 + 55.0 * float(slot_index % 3))
		cmd.data["dir"] = away.normalized().rotated(Vector3.UP, ang)
		cmd.step = "scattering"
	_move_dir(cmd.data["dir"] as Vector3, profile.move_speed * 1.3, delta)
	if cmd.timer > 3.0:
		finish_current("scattered")


# ------------------------------------------------------------------ silly orders

func _run_jump(cmd: SquadCommand) -> void:
	var remaining: int = int(cmd.data.get("left", int(cmd.args.get("count", 1))))
	if remaining <= 0:
		finish_current("jumped")
		return
	if is_on_floor() or cmd.data.get("first", true):
		cmd.data["first"] = false
		cmd.data["left"] = remaining - 1
		cmd.step = "jump %d" % (int(cmd.args.get("count", 1)) - remaining + 1)
		velocity.y = 6.5
		_play(["Jump_Full_Short", "Jump_Start", "Jump_Idle"], 0.65, true)
		_start_action("jump", 0.7, -1.0, Callable())
		if remaining == int(cmd.args.get("count", 1)):
			say_event("jump", 0)


func _run_emote(cmd: SquadCommand) -> void:
	var kind: String = String(cmd.args.get("text", "cheer"))
	var pl: Node3D = _player()
	match kind:
		"sit":
			_play(["Sit_Floor_Down", "Sit_Floor_Idle"], 0.8, true)
			_start_action("emote", 3.0, -1.0, Callable())
		"lie":
			_play(["Lie_Down", "Lie_Idle", "Death_A_Pose", "Sit_Floor_Down"], 0.8, true)
			_start_action("emote", 3.5, -1.0, Callable())
		"kneel":
			_play(["Sit_Floor_Down", "PickUp", "Interact"], 0.8, true)
			_start_action("emote", 2.0, -1.0, Callable())
		"spin":
			_start_action("spin", 1.2, -1.0, Callable())
		"backflip":
			velocity.y = 7.5
			_play(["Jump_Full_Long", "Jump_Full_Short", "Jump_Start"], 0.9, true)
			_start_action("flip", 0.9, -1.0, Callable())
		"bow", "salute", "nod":
			_play(["Interact", "Use_Item"], 1.0, true)
			_start_action("emote", 1.0, -1.0, Callable())
		"point":
			if pl != null:
				var e: EnemyAI = _nearest_enemy(global_position, 25.0)
				set_facing((e.global_position if e != null else pl.global_position) - global_position)
			_play(["Throw", "Spellcast_Shoot", "Interact"], 0.9, true)
			_start_action("emote", 0.9, -1.0, Callable())
		"laugh", "clap":
			if pl != null:
				set_facing(pl.global_position - global_position)
			_play(["Cheer", "Taunt", "Taunt_Longer"], 1.6, true)
			_start_action("emote", 1.6, -1.0, Callable())
		"shrug", "wave":
			if pl != null:
				set_facing(pl.global_position - global_position)
			_play(["Interact", "Cheer", "Use_Item"], 1.2, true)
			_start_action("emote", 1.2, -1.0, Callable())
		"flex":
			_play(["Taunt_Longer", "Taunt", "Cheer"], 1.4, true)
			_start_action("emote", 1.4, -1.0, Callable())
		_:
			_play(["Cheer", "Taunt"], 1.4, true)
			_start_action("emote", 1.4, -1.0, Callable())
	if kind in ["laugh"]:
		say(["Ha! Hahaha!", "Heh. Good one.", "Pfft— ha!"][_rng.randi() % 3], "emote", 0)
	finish_current("emoted")


# ------------------------------------------------------------------ positions, rear guard, ranged, circle

## Stand at a spot relative to the player's facing and keep it as they move ("get behind me", "come in front",
## "on my left", "stay close", "keep your distance"). Squad-mates given the same spot spread out sideways.
## Defends itself if something gets in range, otherwise holds the spot.
func _run_position(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if player == null:
		_halt(delta)
		return
	var f: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD
	var r := Vector3(-f.z, 0.0, f.x)
	var lane: float = [-1.0, 1.0, 0.0, -2.0, 2.0][slot_index % 5]
	var spot: String = String(cmd.args.get("spot", "behind"))
	var off: Vector3
	match spot:
		"front":
			off = f * 3.0 + r * lane * 1.5
		"left":
			off = -r * (2.4 + absf(lane) * 1.3) - f * (lane * 0.6)
		"right":
			off = r * (2.4 + absf(lane) * 1.3) - f * (lane * 0.6)
		"close":
			off = r * (1.6 if slot_index % 2 == 0 else -1.6) - f * (0.3 + 0.9 * float(slot_index / 2))
		"far":
			off = (r * lane * 3.0 - f * 3.0).normalized() * 7.0 if lane != 0.0 else -f * 7.5
		_:  # behind: staggered off the camera line (straight behind is the lens)
			off = -f * (2.2 + 1.0 * float(slot_index / 2)) + r * (1.5 if slot_index % 2 == 0 else -1.5)
	var goal: Vector3 = _valid_spot_near(player, player.global_position + off, r, cmd)
	cmd.step = String(cmd.describe())
	var threat: EnemyAI = _nearest_enemy(global_position, 2.2)
	if threat != null:
		_fight(threat, delta, true)
		return
	# Close enough counts as "in position" for a chain (squad-mates' personal space can keep us ~1 m off),
	# and so does being pinned within 2.5 m for a second (blocked by someone standing in the spot).
	if global_position.distance_to(goal) < 1.4:
		cmd.data["arrived"] = true
	elif global_position.distance_to(goal) < 2.5 and Vector2(velocity.x, velocity.z).length() < 0.5:
		cmd.data["still_t"] = float(cmd.data.get("still_t", 0.0)) + delta
		if float(cmd.data["still_t"]) > 1.0:
			cmd.data["arrived"] = true
	else:
		cmd.data["still_t"] = 0.0
	if global_position.distance_to(goal) > 0.8:
		var spd: float = profile.move_speed * clampf(global_position.distance_to(goal) / 3.0, 0.5, 1.3)
		if player is CharacterBody3D:
			var player_dodging: bool = player is PlayerController and (player as PlayerController).current_state == PlayerController.State.DODGE
			if not player_dodging:
				var pv: Vector3 = (player as CharacterBody3D).velocity
				var match_spd: float = minf(Vector2(pv.x, pv.z).length() * 1.05, profile.move_speed * 1.45)
				spd = maxf(spd, match_spd)
		_move_to(goal, spd, delta, spot != "close")
	else:
		cmd.data["arrived"] = true
		_halt(delta)
		set_facing(_turn_toward(facing_direction, -f if spot == "far" else f, 6.0 * delta))


## A requested spot that is off the floor / inside a wall (e.g. "behind me" on a narrow causeway) is moved:
## first to the mirrored side, then pulled in toward the player until it's standable. Cached 0.25 s.
func _valid_spot_near(player: Node3D, want: Vector3, r: Vector3, cmd: SquadCommand) -> Vector3:
	var now: int = Time.get_ticks_msec()
	if now - int(cmd.data.get("spot_ms", -1000)) < 250 and (cmd.data.get("spot_from", Vector3.INF) as Vector3).distance_to(player.global_position) < 0.4:
		return cmd.data["spot_cache"] as Vector3
	var pp: Vector3 = player.global_position
	var lat: float = (want - pp).dot(r)
	var mirrored: Vector3 = want - r * lat * 2.0
	var out: Vector3 = pp + (want - pp) * 0.3
	var found: bool = false
	for base in [want, mirrored]:
		for k in range(4):
			var c: Vector3 = pp.lerp(base as Vector3, 1.0 - 0.2 * float(k))
			if _spot_standable(c):
				out = c
				found = true
				break
		if found:
			break
	cmd.data["spot_ms"] = now
	cmd.data["spot_from"] = pp
	cmd.data["spot_cache"] = out
	return out


func _spot_standable(p: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var mask: int = collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER
	var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 1.8, mask, [get_rid()])
	if space.intersect_ray(down).is_empty():
		return false
	var mid: Vector3 = p + Vector3.UP * 0.8
	for dv in [Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5)]:
		var cq := PhysicsRayQueryParameters3D.create(mid, mid + (dv as Vector3), collision_mask, [get_rid()])
		if not space.intersect_ray(cq).is_empty():
			return false
	return true


## Rear guard: trail ~3.5 m behind the player looking BACK, intercept anything coming from behind (or closing
## on the rear spot), never chase further than 9 m from the player.
func _run_rearguard(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if player == null:
		_halt(delta)
		return
	cmd.step = "guarding the rear"
	var f: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD
	var r := Vector3(-f.z, 0.0, f.x)
	var spot: Vector3 = _valid_spot_near(player, player.global_position - f * (3.6 + 0.6 * float(slot_index / 2)) + r * ([-1.8, 1.8, 0.0][slot_index % 3]), r, cmd)
	var threat: EnemyAI = null
	var best: float = INF
	for e in _active_enemies(spot, 9.0):
		var rel: Vector3 = e.global_position - player.global_position
		rel.y = 0.0
		var behind: bool = rel.normalized().dot(-f) > 0.2
		var d: float = e.global_position.distance_to(spot)
		if (behind or d < 4.0) and d < best and e.global_position.distance_to(player.global_position) < 10.0:
			best = d
			threat = e
	if threat != null:
		cmd.step = "rear contact"
		if cmd.data.get("called", null) != threat:
			cmd.data["called"] = threat
			say(["Contact rear!", "Behind us!", "I've got the back!"][_rng.randi() % 3], "rear", 1)
		_fight(threat, delta)
		return
	if global_position.distance_to(spot) > 0.9:
		_move_to(spot, profile.move_speed * 1.1, delta)
	else:
		cmd.data["arrived"] = true
		_halt(delta)
		set_facing(_turn_toward(facing_direction, -f, 6.0 * delta))


## Long-distance attack: keep 6-9 m from the target and pelt it with bolts (a thrown dagger / hex orb / stone,
## tinted in the ally's colour). Without a named target it keeps picking the nearest enemy until the area is
## clear. Backs off when something closes in.
const RANGED_MIN: float = 5.5
const RANGED_MAX: float = 9.5
func _run_ranged(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		if cmd.data.has("enemy"):
			say_event("kill", 0)
			if cmd.args.has("target") and not String(cmd.args.get("target", "")).is_empty() and String(cmd.args["target"]) != "nearest":
				finish_current("target down")
				return
		var sel: String = String(cmd.args.get("target", ""))
		e = _resolve_enemy(sel, player)
		var in_mark_scope: bool = not sel.is_empty() and sel != "nearest"
		if not in_mark_scope and e != null and manager != null:
			var intel_r: WorldIntel = manager.get("intel") as WorldIntel
			in_mark_scope = intel_r != null and intel_r.is_marked_or_in_region(e)
		if e == null or (not in_mark_scope and e.global_position.distance_to(global_position) > 28.0):
			if not cmd.data.has("enemy"):
				say("Nothing in range to shoot at.", "refuse", 1)
			finish_current("no target" if not cmd.data.has("enemy") else "area clear")
			return
		cmd.data["enemy"] = e
		if cmd.timer < 0.2:
			say(["Lining it up.", "From here, then.", "Keep it busy, I'll pepper it."][_rng.randi() % 3], "ranged", 0)
	_engage_target = e
	_combat_quiet = 0.0
	if _hazard_dodge(delta):
		return
	var to_e: Vector3 = e.global_position - global_position
	to_e.y = 0.0
	var d: float = to_e.length()
	var close: EnemyAI = _nearest_enemy(global_position, 2.6)
	if close != null and close.get_current_target() == self:
		# Something is on us: back-step away from it (fight in place if cornered).
		var away: Vector3 = global_position - close.global_position
		away.y = 0.0
		if away.length_squared() > 0.01 and _side_open(away.normalized()):
			cmd.step = "backing off"
			_move_dir(away.normalized(), profile.move_speed * 1.15, delta)
			return
		cmd.step = "fighting cornered"
		_fight(close, delta, true)
		return
	if d > RANGED_MAX:
		cmd.step = "closing to range"
		_move_to(e.global_position - to_e.normalized() * (RANGED_MAX - 1.5), profile.move_speed, delta)
		return
	if d < RANGED_MIN and d > 0.01 and _side_open(-to_e.normalized()):
		cmd.step = "opening range"
		_move_dir(-to_e.normalized(), profile.move_speed, delta)
		return
	cmd.step = "shooting"
	_halt(delta)
	set_facing(to_e)
	if _attack_cd <= 0.0:
		_fire_bolt(e)


func _fire_bolt(e: EnemyAI) -> void:
	_attack_cd = profile.attack_cooldown * 1.35
	var clips: Array[String] = ["Throw", "1H_Ranged_Shoot", "Spellcast_Shoot", "Spellcasting"]
	if profile.role == "artillery":
		clips = ["Spellcast_Shoot", "Spellcasting", "Throw"]
	_play(clips, 0.5, true)
	var dmg: int = int(round(float(profile.attack_damage) * 0.8 * (1.0 + _dmg_buff)))
	_start_action("attack", 0.45, 0.2, func() -> void:
		if not _enemy_ok(e):
			return
		var host: Node = GoreFXScript.host_for(self)
		if host == null:
			e.apply_damage(dmg, false, "ally_ranged", self)
			return
		var col: Color = profile.color
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.11
		sph.height = 0.22
		sph.radial_segments = 8
		sph.rings = 4
		mi.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col.lightened(0.35)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 3.0
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mi)
		var from: Vector3 = global_position + Vector3.UP * 1.35 + facing_direction * 0.4
		mi.global_position = from
		var to: Vector3 = e.global_position + Vector3.UP * 1.0
		var t: float = clampf(from.distance_to(to) / 24.0, 0.08, 0.5)
		var tw := mi.create_tween()
		tw.tween_property(mi, "global_position", to, t)
		tw.tween_callback(func() -> void:
			if is_instance_valid(e) and _enemy_ok(e):
				if e.apply_damage(dmg, false, "ally_ranged", self):
					GoreFXScript.sparks(self, e.global_position + Vector3.UP, (to - from).normalized(), col, 12)
					GameFeelScript.play_sound(self, "enemy_hit", e.global_position + Vector3.UP, -8.0, 1.2)
					if e.is_dead:
						say_event("kill", 0)
			mi.queue_free())
		GameFeelScript.play_sound(self, "whoosh_light", from, -10.0, 1.4))


## Fun: jog laps around the player (~5 s), then back to whatever was next.
func _run_circle(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	if player == null or cmd.timer > float(cmd.args.get("step_sec", 5.0)):
		finish_current("dizzy")
		return
	if cmd.timer < 0.05:
		say(["Wheee!", "Round and round...", "Is this tactical? This doesn't feel tactical."][_rng.randi() % 3], "circle", 0)
	cmd.step = "running circles"
	var ang: float = cmd.timer * 1.9 + float(slot_index) * TAU / 3.0
	var goal: Vector3 = player.global_position + Vector3(cos(ang), 0.0, sin(ang)) * 2.8
	_move_to(goal, profile.move_speed * 1.2, delta, false)


# ------------------------------------------------------------------ self-preservation / downed

## Priority ladder: PANIC orders > direct orders > self-preservation at critical HP > autonomous combat > idle.
## Below `retreat_threshold` an ally on autonomous duty (follow / hold / no order) falls back; a direct order
## or mission keeps it fighting until HP turns *critical* (half the threshold). Never during massacre / panic.
## The interrupted command stays current and resumes once recovered.
func _check_self_preservation() -> void:
	if _is_massacre() or (current != null and current.priority >= SquadCommand.Priority.PANIC):
		_retreating = false
		return
	var r: float = get_health_ratio()
	var direct: bool = current != null and not (current.verb in ["follow", "hold"]) and current.priority >= SquadCommand.Priority.ORDER
	var critical: bool = r < profile.retreat_threshold * 0.5
	if not _retreating and (critical or (r < profile.retreat_threshold and not direct)):
		_retreating = true
		say_event("retreat", 2)
	elif _retreating and r > profile.retreat_threshold + 0.25:
		_retreating = false
		if current != null:
			say("Back in it — resuming %s." % current.describe(), "resume", 1)


func _run_retreat_self(delta: float, player: Node3D) -> void:
	if player == null:
		_halt(delta)
		return
	# Cornered: something is right on us — swing back once instead of eating hits in the back.
	var cornered: EnemyAI = _nearest_enemy(global_position, 1.8)
	if cornered != null and cornered.get_current_target() == self and _attack_cd <= 0.0:
		set_facing(cornered.global_position - global_position)
		_melee(cornered)
		return
	var c: Vector3 = _threat_centroid(global_position, 14.0)
	var anchor: Vector3 = player.global_position
	var away: Vector3 = (anchor - c) if c != Vector3.INF else (global_position - anchor)
	away.y = 0.0
	var goal: Vector3 = anchor + (away.normalized() if away.length_squared() > 0.01 else Vector3.BACK) * 4.5
	if global_position.distance_to(goal) > 1.0:
		_move_to(goal, profile.move_speed * 1.15, delta)
	else:
		_halt(delta)


func _go_down() -> void:
	is_downed = true
	_reviving_by_player = false
	_revive_channel_t = 0.0
	_retreating = false
	_action = ""
	_action_timer = 0.0
	_action_hit_at = -1.0
	_action_cb = Callable()
	_dash_timer = 0.0
	_dash_vel = Vector3.ZERO
	_dash_hit_cb = Callable()
	_dash_target = null
	_hide_cast_ring()
	clear_mine()
	_sync_realm_mask()
	velocity = Vector3.ZERO
	_play(["Death_A", "Death_B"], -1.0, true)
	say_event("downed", 3)
	add_to_group("interactable_switch")
	downed.emit(self)
	_refresh_label()


func revive(ratio: float = 0.45) -> void:
	if not is_downed:
		return
	is_downed = false
	_reviving_by_player = false
	_revive_channel_t = 0.0
	_sync_realm_mask()
	health = maxi(1, int(round(float(max_health) * clampf(ratio, 0.05, 1.0))))
	_low_hp_warned = false
	remove_from_group("interactable_switch")
	if _player_near_prompt:
		_player_near_prompt = false
		prompt_changed.emit(false, "")
	_play(["Lie_StandUp", "Idle"], 0.7, true)
	_start_action("emote", 0.7, -1.0, Callable())
	GoreFXScript.flash_light(self, global_position + Vector3.UP, Color(1.0, 0.9, 0.5), 4.0, 0.4, 4.0)
	say_event("revived", 2)
	health_changed.emit(self, health, max_health)
	revived.emit(self)


## Manual revive: the player presses Interact next to a downed ally (PlayerController.try_interact scans
## the `interactable_switch` group within 2.6 m). Channels for 5.0 s and consumes Mirror Charge on completion.
func interact() -> bool:
	if not is_downed:
		return false
	if _reviving_by_player:
		return true
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null and not rm.has_mirror_charge(rm.revive_charge_cost):
		var hud: Node = get_tree().get_first_node_in_group("hud") if is_inside_tree() and get_tree() != null else null
		if hud != null and hud.has_method("show_toast"):
			hud.call("show_toast", "NEED MIRROR CHARGE TO REVIVE", 1.6)
		return false
	_reviving_by_player = true
	_revive_channel_t = 0.0
	if _player_near_prompt:
		_player_near_prompt = false
		prompt_changed.emit(false, "")
	GameFeelScript.play_sound(self, "whoosh_light", global_position + Vector3.UP, -8.0, 0.9)
	return true


func is_player_reviving() -> bool:
	return is_downed and _reviving_by_player


func get_revive_progress() -> Dictionary:
	var prog: float = clampf(_revive_channel_t / maxf(0.01, PLAYER_REVIVE_DURATION), 0.0, 1.0)
	var rem: float = maxf(0.0, PLAYER_REVIVE_DURATION - _revive_channel_t)
	return {
		"active": is_downed and _reviving_by_player,
		"progress": prog,
		"remaining": rem,
		"ally_name": get_display_name(),
		"world_pos": global_position + Vector3.UP * 1.45,
	}


func _is_point_in_pit_kill_zone(pos: Vector3) -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	for z in get_tree().get_nodes_in_group("pit_kill_zone"):
		if z != null and z.has_method("is_point_inside_zone") and bool(z.call("is_point_inside_zone", pos)):
			return true
	return false


func _in_pit_kill_zone() -> bool:
	return _is_point_in_pit_kill_zone(global_position)


func _process_downed(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_and_move(delta)
	var pl: Node3D = _player()
	# Never distance-teleport a downed ally back to the player; only rescue them to safe local floor on real pit/void falls.
	var pit_or_void: bool = _in_pit_kill_zone() or global_position.y < -20.0
	if pit_or_void:
		_rescue_from_pit(pl)
	if _reviving_by_player:
		var pl_alive: bool = pl != null and pl.get("is_dead") != true
		var in_range: bool = pl_alive and pl.global_position.distance_to(global_position) <= PLAYER_REVIVE_RANGE
		var rm: RealmManager = RealmManager.instance as RealmManager
		var has_charge: bool = rm == null or rm.has_mirror_charge(rm.revive_charge_cost)
		if not in_range or not has_charge:
			_reviving_by_player = false
			_revive_channel_t = 0.0
		else:
			_revive_channel_t += delta
			if _revive_channel_t >= PLAYER_REVIVE_DURATION:
				_reviving_by_player = false
				_revive_channel_t = 0.0
				if rm != null:
					rm.consume_mirror_charge(rm.revive_charge_cost)
				revive(0.65)
				return
	_update_revive_prompt()


func _update_revive_prompt() -> void:
	var p: Node3D = _player()
	var near: bool = is_downed and not _reviving_by_player and p != null and p.global_position.distance_to(global_position) <= 2.6
	if near != _player_near_prompt:
		_player_near_prompt = near
		var key: String = "E"
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null and store.has_method("get_action_display_label"):
			key = String(store.call("get_action_display_label", "interact"))
		prompt_changed.emit(near, "%s: Revive %s" % [key, get_display_name()])


## Full restore (player respawn / new run).
func reset_full(at: Vector3) -> void:
	is_downed = false
	_reviving_by_player = false
	_revive_channel_t = 0.0
	_sync_realm_mask()
	remove_from_group("interactable_switch")
	health = max_health
	_retreating = false
	_action = ""
	_action_timer = 0.0
	_action_hit_at = -1.0
	_action_cb = Callable()
	_dash_timer = 0.0
	_dash_vel = Vector3.ZERO
	_dash_hit_cb = Callable()
	_dash_target = null
	_engage_target = null
	_hide_cast_ring()
	clear_mine()
	current = null
	queue.clear()
	global_position = at
	velocity = Vector3.ZERO
	_last_pos = at
	_stuck_anchor_pos = at
	_stuck_timer = 0.0
	_stuck_strikes = 0
	_pit_rescue_count = 0
	_pit_rescue_window_ms = 0
	_last_safe_pos = at
	_has_safe_pos = true
	health_changed.emit(self, health, max_health)
	_refresh_label()


# ------------------------------------------------------------------ combat primitives

func _fight(e: EnemyAI, delta: float, hold_ground: bool = false) -> void:
	_engage_target = e
	_combat_quiet = 0.0
	if _hazard_dodge(delta):
		return
	# Casters fight from range with visible bolts (no sword); berserk massacre still wades in.
	if profile.role == "artillery" and not _is_massacre():
		if hold_ground:
			var to_t: Vector3 = e.global_position - global_position
			to_t.y = 0.0
			_halt(delta)
			set_facing(to_t)
			if _attack_cd <= 0.0:
				if to_t.length() <= profile.attack_range + 0.3:
					_melee(e)
				else:
					_fire_bolt(e)
			return
		_ranged_engage(e, delta)
		return
	# Distinct attack slot per ally around the enemy (no stacking on one spot).
	var to_e: Vector3 = e.global_position - global_position
	to_e.y = 0.0
	var reach: float = profile.attack_range
	if to_e.length() > reach:
		var slot_ang: float = float(slot_index) * TAU / 3.0
		var slot: Vector3 = e.global_position + Vector3(cos(slot_ang), 0.0, sin(slot_ang)) * (reach * 0.8)
		var goal: Vector3 = slot if to_e.length() < 4.0 else e.global_position
		_move_to(goal, profile.move_speed * (1.2 if _is_massacre() else 1.0), delta)
		return
	_halt(delta)
	set_facing(to_e)
	if _attack_cd <= 0.0:
		_melee(e)


func _melee(e: EnemyAI) -> void:
	var cd: float = profile.attack_cooldown * (0.75 if _is_massacre() else 1.0)
	_attack_cd = cd
	var clips: Array[String] = ["1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Horizontal"]
	if profile.role == "skirmisher":
		clips = ["Dualwield_Melee_Attack_Slice", "Dualwield_Melee_Attack_Stab", "1H_Melee_Attack_Stab"]
	elif profile.role == "vanguard":
		clips = ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Horizontal", "2H_Melee_Attack_Slice"]
	clips.shuffle()
	_play(clips, 0.55, true)
	var dmg: int = int(round(float(profile.attack_damage) * (1.3 if _is_massacre() else 1.0) * (1.0 + _dmg_buff)))
	_start_action("attack", 0.5, 0.24, func() -> void:
		if _enemy_ok(e) and global_position.distance_to(e.global_position) <= profile.attack_range + 0.7:
			if e.apply_damage(dmg, false, "ally_melee", self):
				GameFeelScript.play_sound(self, "enemy_hit", e.global_position + Vector3.UP, -6.0, 1.05)
				if e.is_dead:
					say_event("kill", 0)
	)


func _do_taunt(e: EnemyAI, area: bool) -> void:
	_taunt_cd = profile.taunt_cooldown
	set_facing(e.global_position - global_position)
	_play(["Taunt", "Cheer", "Taunt_Longer"], 0.8, true)
	_start_action("taunt", 0.55, 0.15, Callable())
	say_event("taunt", 1)
	e.apply_taunt(self, -1.0, 4.0)
	if area:
		for o in _active_enemies(global_position, 6.0):
			if o != e:
				o.apply_taunt(self, 30.0, 2.5)


func start_charge(e: EnemyAI, on_done: Callable) -> void:
	var dir: Vector3 = e.global_position - global_position
	dir.y = 0.0
	set_facing(dir)
	_dash_target = e
	_dash_vel = dir.normalized() * 12.5
	_dash_timer = clampf(dir.length() / 12.5 + 0.15, 0.2, 0.9)
	_dash_hit_cb = on_done
	_charge_cd = 4.0
	_play(["Running_A", "Running_B"], -1.0, true, true)


func _process_dash(delta: float) -> void:
	_dash_timer -= delta
	velocity.x = _dash_vel.x
	velocity.z = _dash_vel.z
	_apply_gravity_and_move(delta)
	var e: EnemyAI = _dash_target
	var hit: bool = false
	if e != null and _enemy_ok(e) and global_position.distance_to(e.global_position) < 1.6:
		hit = true
		_play(["1H_Melee_Attack_Chop", "Block_Attack"], 0.4, true)
		e.apply_damage(22, true, "ally_charge", self)
		e.add_knockback(_dash_vel.normalized() * 7.0)
		GameFeelScript.add_trauma(self, 0.3, e.global_position)
		GameFeelScript.play_sound(self, "hit_metal", e.global_position + Vector3.UP, 0.0, 0.8)
		GoreFXScript.dust_puff(self, e.global_position, 0.8, 20)
	if hit or _dash_timer <= 0.0:
		_dash_timer = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		var cb: Callable = _dash_hit_cb
		_dash_hit_cb = Callable()
		_dash_target = null
		if cb.is_valid():
			cb.call(hit)


## Sidestep enemy wind-ups aimed at us and brute slam rings (hazard avoidance). Returns true while dodging.
func _hazard_dodge(delta: float) -> bool:
	for e in _active_enemies(global_position, 5.0):
		if e.current_state != EnemyAI.State.WINDUP:
			continue
		var to_me: Vector3 = global_position - e.global_position
		to_me.y = 0.0
		var d: float = to_me.length()
		var slam: bool = e is ArchetypeEnemy and (e as ArchetypeEnemy).get_kind() == "slam"
		var danger_r: float = ((e as ArchetypeEnemy).archetype.aoe_radius + 0.8) if slam else e.attack_range + 0.6
		if d > danger_r:
			continue
		if not slam and e.get_facing_direction().dot(to_me.normalized()) < 0.4:
			continue
		if _massacre_brave():
			return false
		var side := Vector3(-to_me.z, 0.0, to_me.x).normalized() * (1.0 if slot_index % 2 == 0 else -1.0)
		_move_dir((to_me.normalized() + side).normalized(), profile.move_speed * 1.3, delta)
		return true
	return false


func _massacre_brave() -> bool:
	return _is_massacre() and _rng.randf() < 0.5


# ------------------------------------------------------------------ actions (timed, animation-locked)

func _start_action(kind: String, dur: float, hit_at: float, cb: Callable) -> void:
	_action = kind
	_action_timer = dur
	_action_dur = dur
	_action_hit_at = hit_at
	_action_cb = cb


func _process_action(delta: float) -> void:
	var before: float = _action_dur - _action_timer
	_action_timer -= delta
	var after: float = _action_dur - _action_timer
	if _action_hit_at >= 0.0 and before < _action_hit_at and after >= _action_hit_at:
		var cb: Callable = _action_cb
		_action_cb = Callable()
		if cb.is_valid():
			cb.call()
	match _action:
		"dance":
			var k: int = int(after / 0.55)
			var moves: Array[String] = ["Cheer", "Dodge_Left", "Dodge_Right", "Taunt", "Spellcasting", "Jump_Full_Short"]
			_play([moves[k % moves.size()], "Cheer"], 0.55, false)
			var vis: Node3D = get_node_or_null("VisualRoot") as Node3D
			if vis != null and k % 3 == 2:
				vis.rotation.y += 9.0 * delta
		"spin":
			var vis2: Node3D = get_node_or_null("VisualRoot") as Node3D
			if vis2 != null:
				vis2.rotation.y += TAU / 1.2 * delta
		"flip":
			var vis3: Node3D = get_node_or_null("VisualRoot") as Node3D
			if vis3 != null:
				vis3.rotation.x = -TAU * clampf(after / maxf(0.01, _action_dur), 0.0, 1.0)
				if _action_timer <= 0.0:
					vis3.rotation.x = 0.0
		"channel":
			if _action_data_track != null and is_instance_valid(_action_data_track) and _action_timer > 0.3 and _cast_ring != null:
				var tp: Vector3 = _action_data_track.global_position + Vector3.UP * 0.06
				_cast_ring.global_position = _cast_ring.global_position.lerp(tp, clampf(5.0 * delta, 0.0, 1.0))
	if _action != "jump":
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)
	_apply_gravity_and_move(delta)
	if _action_timer <= 0.0:
		_action = ""
		_action_cb = Callable()
		if current != null and current.verb == "jump":
			pass  # next hop starts on the next frame


# ------------------------------------------------------------------ movement

func _move_to(goal: Vector3, speed: float, delta: float, avoid_allies: bool = true) -> void:
	var to: Vector3 = goal - global_position
	to.y = 0.0
	var d: float = to.length()
	if d < 0.05:
		_halt(delta)
		return
	if d >= 0.85 and speed > 0.2:
		_want_move_this_frame = true
		_want_move_goal = goal
	# Arrival: ease in over the last metre and a half instead of slamming into the spot.
	var arrive: float = clampf(d / 1.5, 0.25, 1.0)
	_steer_toward_dir(to / d, speed * arrive, delta, avoid_allies, d)


func _move_dir(dir: Vector3, speed: float, delta: float) -> void:
	var d: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		_halt(delta)
		return
	if speed > 0.2:
		_want_move_this_frame = true
	_steer_toward_dir(d.normalized(), speed, delta, true, 99.0)


# ------------------------------------------------------------------ context steering (spatial awareness)

const STEER_DIRS: int = 12
const STEER_REFRESH: float = 0.06
const SPACE_ALLY: float = 1.5      # personal space from squad-mates
const SPACE_PLAYER: float = 1.8    # never crowd / block the player
const SPACE_ENEMY: float = 1.1     # don't body-block into enemies (except the one we're fighting)
const WALL_LOOK: float = 1.6       # wall look-ahead (scaled up with speed)

var _steer_dir: Vector3 = Vector3.ZERO
var _steer_timer: float = 0.0
var _steer_speed_k: float = 1.0
var _steer_last_goal_dist: float = 99.0


## Context steering: score STEER_DIRS headings by interest (toward the goal) minus danger (walls, ledges,
## squad-mates, the player and the camera corridor behind them, enemies and their strike cones), pick the
## best, smooth it over time, and slow down when detouring or crowded. Replaces straight-line + separation
## movement that ran allies into each other and into walls.
func _steer_toward_dir(desired: Vector3, speed: float, delta: float, social: bool, goal_dist: float) -> void:
	_steer_timer -= delta
	_steer_last_goal_dist = goal_dist
	if _steer_timer <= 0.0 or _steer_dir == Vector3.ZERO:
		_steer_timer = STEER_REFRESH
		var pick: Dictionary = _context_pick(desired, speed, social, goal_dist)
		_steer_dir = pick["dir"] as Vector3
		_steer_speed_k = float(pick["speed_k"])
	if _steer_dir == Vector3.ZERO:
		_halt(delta)
		return
	var cur_v := Vector3(velocity.x, 0.0, velocity.z)
	var target_v: Vector3 = _steer_dir * speed * _steer_speed_k
	if social:
		var push: Vector3 = _personal_space_push()
		if push.length_squared() > 0.0001 and _floor_ahead(push.normalized(), 0.7):
			var combined: Vector3 = target_v + push * 2.2
			if combined.length_squared() <= 0.0001 or _floor_ahead(combined.normalized(), 0.65):
				target_v = combined
	var cur := cur_v.move_toward(target_v, 26.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	var face: Vector3 = _steer_dir if cur.length() > 0.5 else desired
	set_facing(_turn_toward(facing_direction, face, 10.0 * delta))
	_apply_gravity_and_move(delta)


func _context_pick(desired: Vector3, speed: float, social: bool, goal_dist: float) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var wall_mask: int = collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER
	var look: float = clampf(WALL_LOOK * (0.6 + speed / 6.0), 1.0, 2.6)
	var me: Vector3 = global_position
	# Gather neighbours once.
	var others: Array = []   # [pos, radius, weight]
	if social:
		for a in get_tree().get_nodes_in_group("squad_ally"):
			if a != self and a is SquadAlly and not (a as SquadAlly).is_downed:
				others.append([(a as Node3D).global_position, SPACE_ALLY, 1.0])
	var player: Node3D = _player()
	var pf := Vector3.FORWARD
	if player != null:
		others.append([player.global_position, SPACE_PLAYER, 1.4])
		if player.has_method("get_facing_direction"):
			pf = player.call("get_facing_direction")
	var windups: Array[EnemyAI] = []
	for e in _active_enemies(me, 6.0):
		if e != _engage_target or goal_dist > 2.5:
			others.append([e.global_position, SPACE_ENEMY, 0.8])
		if e.current_state == EnemyAI.State.WINDUP:
			windups.append(e)
	var best_score: float = -INF
	var best_dir := Vector3.ZERO
	var best_danger: float = 1.0
	var prev: Vector3 = _steer_dir
	for i in range(STEER_DIRS):
		var ang: float = TAU * float(i) / float(STEER_DIRS)
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var interest: float = dir.dot(desired)
		# Slight preference to keep the previous heading (prevents left/right dithering).
		if prev != Vector3.ZERO:
			interest += 0.15 * maxf(0.0, dir.dot(prev))
		var danger: float = 0.0
		# Walls / obstacles (waist height) within the look-ahead.
		var q := PhysicsRayQueryParameters3D.create(me + Vector3.UP * 0.8, me + Vector3.UP * 0.8 + dir * look, wall_mask, [get_rid()])
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			var hd: float = me.distance_to(hit["position"] as Vector3)
			danger = maxf(danger, clampf(1.15 - hd / look, 0.0, 1.0))
		# Personal space: squad-mates, player, enemies.
		for o in others:
			var rel: Vector3 = (o[0] as Vector3) - me
			rel.y = 0.0
			var dl: float = rel.length()
			var rad: float = float(o[1])
			if dl < rad * 1.6 and dl > 0.01:
				var toward: float = dir.dot(rel / dl)
				if toward > 0.0:
					danger = maxf(danger, toward * clampf(1.0 - (dl - rad * 0.5) / rad, 0.0, 1.0) * float(o[2]))
		# Camera awareness: don't walk onto the real camera->player sight line or into the lens.
		if player != null and _camera_blocking_at(me + dir * 1.0, player):
			danger = maxf(danger, 0.5)
		# Strike cones of enemies winding up.
		for e in windups:
			var to_e: Vector3 = e.global_position - (me + dir * 0.8)
			to_e.y = 0.0
			if to_e.length() < e.attack_range + 0.8 and e.get_facing_direction().dot(-to_e.normalized()) > 0.45:
				danger = maxf(danger, 0.85)
		var score: float = interest - danger * 1.6
		if score > best_score:
			# Ledges: only probe floor for a candidate that could win (keeps ray count low).
			if not _floor_ahead(dir):
				continue
			best_score = score
			best_dir = dir
			best_danger = danger
	if best_dir == Vector3.ZERO:
		return {"dir": Vector3.ZERO, "speed_k": 0.0}
	# Detours and crowded spots slow us down; a clear straight line runs at full speed.
	var align: float = clampf(best_dir.dot(desired), 0.0, 1.0)
	var speed_k: float = clampf(0.45 + 0.55 * align, 0.35, 1.0) * (1.0 - 0.45 * best_danger)
	# Almost there but the spot is occupied/blocked: just stop instead of jittering against it.
	if goal_dist < 1.2 and best_danger > 0.55:
		return {"dir": Vector3.ZERO, "speed_k": 0.0}
	return {"dir": best_dir, "speed_k": speed_k}


## Yaw-only turn (Vector3.slerp on near-parallel vectors trips Basis axis normalisation errors).
func _turn_toward(cur: Vector3, target: Vector3, t: float) -> Vector3:
	if Vector2(target.x, target.z).length_squared() < 0.0001:
		return cur
	var a: float = lerp_angle(atan2(cur.x, cur.z), atan2(target.x, target.z), clampf(t, 0.0, 1.0))
	return Vector3(sin(a), 0.0, cos(a))


func _halt(delta: float) -> void:
	# Standing still still keeps personal space: step aside only onto confirmed floor away from drop-offs.
	var push: Vector3 = _personal_space_push()
	if push.length_squared() > 0.0025 and _floor_ahead(push.normalized(), 0.75):
		var tv: Vector3 = push * 2.4
		velocity.x = move_toward(velocity.x, tv.x, 20.0 * delta)
		velocity.z = move_toward(velocity.z, tv.z, 20.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	_apply_gravity_and_move(delta)


func _side_open(dir: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * 0.8
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1.1, collision_mask, [get_rid()])
	return space.intersect_ray(q).is_empty() and _floor_ahead(dir, 0.9)


## True when standing at `p` would block the view: within 2 m of the camera, or within 1 m of the segment
## from the camera to the player's chest.
func _camera_blocking_at(p: Vector3, player: Node3D) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or player == null:
		return false
	var c: Vector3 = cam.global_position
	var flat_p := Vector3(p.x, 0.0, p.z)
	var flat_c := Vector3(c.x, 0.0, c.z)
	if flat_p.distance_to(flat_c) < 2.0:
		# Close to the lens only matters if we're actually in frame (beside / behind the camera is off-screen).
		var local: Vector3 = cam.global_transform.affine_inverse() * (p + Vector3.UP * 1.0)
		if local.z < -0.05 and atan2(absf(local.x), -local.z) < 0.8:
			return true
	var a: Vector3 = flat_c
	var b := Vector3(player.global_position.x, 0.0, player.global_position.z)
	var ab: Vector3 = b - a
	var t: float = clampf((flat_p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
	return t < 0.92 and flat_p.distance_to(a + ab * t) < 1.0


## Push vector (0..~1.5) away from anyone inside our personal space (allies 1.25 m, player 1.45 m) and
## off the camera sight line.
func _personal_space_push() -> Vector3:
	var push := Vector3.ZERO
	var me: Vector3 = global_position
	var pl: Node3D = _player()
	if pl != null and _camera_blocking_at(me, pl):
		var cam: Camera3D = get_viewport().get_camera_3d()
		var line: Vector3 = pl.global_position - cam.global_position
		line.y = 0.0
		var side := Vector3(-line.z, 0.0, line.x).normalized()
		var rel: Vector3 = me - pl.global_position
		var first: Vector3 = side * (1.0 if rel.dot(side) >= 0.0 else -1.0)
		# Only step aside into open floor; on a narrow causeway with railings both sides, accept the line.
		# Stronger the closer we are to the lens (an ally filling the screen is the worst case).
		var cam_d: float = Vector2(me.x - cam.global_position.x, me.z - cam.global_position.z).length()
		var k: float = 1.5 if cam_d < 2.2 else 1.0
		var stepped: bool = false
		for cand in [first, -first]:
			if _side_open(cand as Vector3):
				push += (cand as Vector3) * k
				stepped = true
				break
		if not stepped and cam_d < 2.2:
			# Railings both sides: move up the line past the player instead of sitting in the lens.
			push += line.normalized() * 0.8
	var p: Node3D = _player()
	if p != null:
		var d: Vector3 = me - p.global_position
		d.y = 0.0
		var l: float = d.length()
		if l < 1.45:
			push += (d / l if l > 0.01 else Vector3(1, 0, 0)) * (1.45 - l) / 1.45 * 1.2
	for a in get_tree().get_nodes_in_group("squad_ally"):
		if a == self or not (a is SquadAlly) or (a as SquadAlly).is_downed:
			continue
		var d2: Vector3 = me - (a as Node3D).global_position
		d2.y = 0.0
		var l2: float = d2.length()
		if l2 < 1.35:
			# Deterministic tie-break when exactly overlapping so both don't pick the same side.
			var nd: Vector3 = d2 / l2 if l2 > 0.01 else Vector3(1, 0, 0).rotated(Vector3.UP, float(slot_index) * 2.1)
			push += nd * (1.35 - l2) / 1.35 * 1.5
	return push


func _apply_gravity_and_move(delta: float) -> void:
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -30.0)
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	var others: Array[Node] = get_tree().get_nodes_in_group("squad_ally")
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null:
		others.append(p)
	for o in others:
		if o == self or not (o is Node3D):
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0.0
		var l: float = d.length()
		if l < 1.3 and l > 0.001:
			push += d / l * (1.3 - l)
	return push


func _floor_ahead(dir: Vector3, dist: float = 0.85) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + dir * dist + Vector3.UP * 0.7
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.4, collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER, [get_rid()])
	return not space.intersect_ray(q).is_empty()


func _point_walkable(p: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var mask: int = collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.8, p + Vector3.DOWN * 2.0, mask, [get_rid()])
	if space.intersect_ray(q).is_empty():
		return false
	var wall := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.9, p + Vector3.UP * 0.9, collision_mask, [get_rid()])
	return space.intersect_ray(wall).is_empty()


func _has_distant_order() -> bool:
	return has_free_leash()


func _distant_order_cam_visible() -> bool:
	if current == null or manager == null:
		return false
	var intel_node: WorldIntel = manager.get("intel") as WorldIntel
	if intel_node == null:
		return false
	var en: EnemyAI = current.data.get("enemy", null) as EnemyAI
	return en != null and (intel_node.is_camera_visible(en) or intel_node.is_marked_or_in_region(en))


func _approach_timeout(base_sec: float, target_pos: Vector3, cmd: SquadCommand = null) -> float:
	if cmd != null and cmd.data.has("approach_limit"):
		return float(cmd.data["approach_limit"])
	var spd: float = maxf(profile.move_speed if profile != null else 5.0, 3.0)
	var d: float = global_position.distance_to(target_pos)
	var lim: float = clampf(maxf(base_sec, d / spd + 8.0), base_sec, 45.0)
	if cmd != null:
		cmd.data["approach_limit"] = lim
	return lim


func _get_stand_cap() -> CapsuleShape3D:
	if _stand_cap == null:
		_stand_cap = CapsuleShape3D.new()
		_stand_cap.radius = 0.36
		_stand_cap.height = 1.70
	return _stand_cap


func _get_embed_cap() -> CapsuleShape3D:
	if _embed_cap == null:
		_embed_cap = CapsuleShape3D.new()
		_embed_cap.radius = 0.28
		_embed_cap.height = 1.45
	return _embed_cap


func _validate_stand_spot(cand: Vector3, ref_pos: Vector3 = Vector3.INF, require_los: bool = false, check_allies: bool = false, max_y_diff: float = 0.95, persistent_floor_only: bool = false, extra_excl: Array[RID] = []) -> Vector3:
	if not is_inside_tree() or get_world_3d() == null:
		return Vector3.INF
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return Vector3.INF
	var floor_mask: int = (RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY) if persistent_floor_only else (collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER)
	var excl: Array[RID] = [get_rid()]
	for r_id in extra_excl:
		excl.append(r_id)
	var pl_n: Node3D = _player()
	if pl_n is CollisionObject3D:
		excl.append((pl_n as CollisionObject3D).get_rid())
	var ray_from: Vector3 = cand + Vector3.UP * 1.0
	var ray_to: Vector3 = cand + Vector3.DOWN * 2.2
	var q := PhysicsRayQueryParameters3D.create(ray_from, ray_to, floor_mask, excl)
	q.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	var floor_pos: Vector3 = hit["position"] as Vector3
	if floor_pos.distance_to(ray_from) < 0.05 or (hit["normal"] as Vector3).y < 0.78:
		return Vector3.INF
	if ref_pos != Vector3.INF and absf(floor_pos.y - ref_pos.y) > max_y_diff:
		return Vector3.INF
	if _is_point_in_pit_kill_zone(floor_pos) or floor_pos.y < -18.0:
		return Vector3.INF
	# Require at least a 0.68 m x 0.68 m continuous floor pad (rejects parapet caps and razor cliff lips).
	for off in [Vector3(0.34, 0.0, 0.34), Vector3(-0.34, 0.0, 0.34), Vector3(0.34, 0.0, -0.34), Vector3(-0.34, 0.0, -0.34)]:
		var c_from: Vector3 = floor_pos + (off as Vector3) + Vector3.UP * 0.6
		var cq := PhysicsRayQueryParameters3D.create(c_from, floor_pos + (off as Vector3) + Vector3.DOWN * 0.9, floor_mask, excl)
		cq.hit_from_inside = true
		var chit: Dictionary = space.intersect_ray(cq)
		if chit.is_empty():
			return Vector3.INF
		var ch_pos: Vector3 = chit["position"] as Vector3
		if ch_pos.distance_to(c_from) < 0.05 or (chit["normal"] as Vector3).y < 0.70 or absf(ch_pos.y - floor_pos.y) > 0.55:
			return Vector3.INF
	var spq := PhysicsShapeQueryParameters3D.new()
	spq.shape = _get_stand_cap()
	spq.transform = Transform3D(Basis.IDENTITY, floor_pos + Vector3.UP * 0.92)
	spq.collision_mask = collision_mask
	spq.exclude = excl
	if not space.intersect_shape(spq, 1).is_empty():
		return Vector3.INF
	if require_los and ref_pos != Vector3.INF:
		for h_los in [0.85, 1.45]:
			var lq := PhysicsRayQueryParameters3D.create(ref_pos + Vector3.UP * float(h_los), floor_pos + Vector3.UP * float(h_los), collision_mask, excl)
			lq.hit_from_inside = true
			if not space.intersect_ray(lq).is_empty():
				return Vector3.INF
	if check_allies and get_tree() != null:
		for a in get_tree().get_nodes_in_group("squad_ally"):
			if a != self and a is SquadAlly and not (a as SquadAlly).is_downed:
				if (a as Node3D).global_position.distance_to(floor_pos) < 0.85:
					return Vector3.INF
	return floor_pos + Vector3.UP * 0.05


func _is_embedded_in_world() -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return false
	var excl: Array[RID] = [get_rid()]
	var pl_n: Node3D = _player()
	if pl_n is CollisionObject3D:
		excl.append((pl_n as CollisionObject3D).get_rid())
	var spq := PhysicsShapeQueryParameters3D.new()
	spq.shape = _get_embed_cap()
	spq.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 0.95)
	spq.collision_mask = collision_mask
	spq.exclude = excl
	return not space.intersect_shape(spq, 1).is_empty()


func _find_safe_spot_near(origin: Vector3, radii: Array, check_allies: bool = true, ref_pos: Vector3 = Vector3.INF, require_los: bool = false, max_y_diff: float = 1.2) -> Vector3:
	var r_ref: Vector3 = ref_pos if ref_pos != Vector3.INF else origin
	for rad in radii:
		var r_m: float = float(rad)
		for i in range(12):
			var ang: float = TAU * float(i) / 12.0
			var cand: Vector3 = origin + Vector3(sin(ang) * r_m, 0.0, cos(ang) * r_m)
			var valid: Vector3 = _validate_stand_spot(cand, r_ref, require_los, check_allies, max_y_diff)
			if valid != Vector3.INF:
				return valid
	return Vector3.INF


func find_safe_spot_around(player: Node3D) -> Vector3:
	if player == null or not is_instance_valid(player) or not is_inside_tree():
		return Vector3.INF
	var pf: Vector3 = Vector3.FORWARD
	if player.has_method("get_facing_direction"):
		pf = player.call("get_facing_direction") as Vector3
	if Vector2(pf.x, pf.z).length_squared() < 0.001:
		pf = Vector3.FORWARD
	pf = Vector3(pf.x, 0.0, pf.z).normalized()
	var pr := Vector3(-pf.z, 0.0, pf.x)
	var s: float = 1.0 if slot_index % 2 == 0 else -1.0
	var ppos: Vector3 = player.global_position
	var cands: Array[Vector3] = [
		_formation_point(player),
		ppos - pf * 1.4 + pr * (1.3 * s),
		ppos - pf * 1.4 - pr * (1.3 * s),
		ppos - pf * 1.5,
		ppos + pr * (1.3 * s),
		ppos - pr * (1.3 * s),
		ppos - pf * 2.2 + pr * (1.6 * s),
		ppos - pf * 2.2 - pr * (1.6 * s),
		ppos + pf * 1.3 + pr * (1.1 * s),
		ppos + pf * 1.3 - pr * (1.1 * s),
		ppos - pf * 0.8 + pr * (0.9 * s),
		ppos - pf * 0.8 - pr * (0.9 * s),
		ppos - pf * 0.9,
	]
	for cand in cands:
		var v1: Vector3 = _validate_stand_spot(cand, ppos, true, true, 0.95)
		if v1 != Vector3.INF:
			return v1
	for cand in cands:
		var v2: Vector3 = _validate_stand_spot(cand, ppos, true, false, 0.95)
		if v2 != Vector3.INF:
			return v2
	var v_feet: Vector3 = _validate_stand_spot(ppos, ppos, false, false, 1.2)
	if v_feet != Vector3.INF:
		return v_feet
	var v_ring: Vector3 = _find_safe_spot_near(ppos, [1.5, 2.5, 3.8], false, ppos, false, 3.0)
	if v_ring != Vector3.INF:
		return v_ring
	if get_tree() != null:
		var ed: Node = get_tree().get_first_node_in_group("encounter_director")
		if ed != null:
			var cp_xf: Transform3D = ed.get("checkpoint_transform") as Transform3D
			var v_cp: Vector3 = _validate_stand_spot(cp_xf.origin, cp_xf.origin, false, false, 50.0)
			if v_cp != Vector3.INF:
				return v_cp
	return Vector3.INF


func _record_safe_pos_if_valid(delta: float) -> void:
	_safe_pos_scan_t -= delta
	if _has_safe_pos and _safe_pos_scan_t > 0.0:
		return
	if not is_on_floor() or get_floor_normal().y < 0.85 or _in_pit_kill_zone():
		return
	_safe_pos_scan_t = 0.25
	if _validate_stand_spot(global_position, global_position, false, false, 0.6, true) != Vector3.INF:
		_last_safe_pos = global_position
		_has_safe_pos = true


func _rescue_from_pit(player: Node3D) -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _pit_rescue_window_ms > 6000:
		_pit_rescue_count = 0
		_pit_rescue_window_ms = now_ms
	_pit_rescue_count += 1
	if _has_safe_pos and _pit_rescue_count < 2:
		var safe_spot: Vector3 = _validate_stand_spot(_last_safe_pos, _last_safe_pos, false, false, 0.9, false)
		if safe_spot != Vector3.INF:
			global_position = safe_spot
			velocity = Vector3.ZERO
			_last_pos = global_position
			_stuck_anchor_pos = global_position
			return
	_has_safe_pos = false
	if player != null and is_instance_valid(player):
		_blink_to(player)
	if (_in_pit_kill_zone() or global_position.y < -20.0) and get_tree() != null:
		var ed: Node = get_tree().get_first_node_in_group("encounter_director")
		if ed != null:
			var cp_xf: Transform3D = ed.get("checkpoint_transform") as Transform3D
			global_position = cp_xf.origin + Vector3.UP * 0.1
			velocity = Vector3.ZERO
			_last_pos = global_position
			_stuck_anchor_pos = global_position
	_pit_rescue_count = 0


func _recover_from_embedded(player: Node3D) -> void:
	var spot: Vector3 = _find_safe_spot_near(global_position, [0.9, 1.5, 2.2, 3.2], false, global_position, false, 1.5)
	if spot != Vector3.INF:
		global_position = spot
		velocity = Vector3.ZERO
		_last_pos = spot
		_stuck_anchor_pos = spot
		_stuck_timer = 0.0
		return
	if player != null and is_instance_valid(player):
		_blink_to(player)


func _crosses_closed_gate(from_pos: Vector3, to_pos: Vector3) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(from_pos + Vector3.UP * 1.0, to_pos + Vector3.UP * 1.0, collision_mask, [get_rid()])
	q.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return false
	var cur: Node = hit.get("collider", null) as Node
	var hops: int = 0
	while cur != null and hops < 4:
		if cur.is_in_group("encounter_gate"):
			return not bool(cur.get("is_open"))
		cur = cur.get_parent()
		hops += 1
	return false


func _unstick_bypass(goal: Vector3) -> bool:
	if goal == Vector3.INF or not is_inside_tree():
		return false
	var to_g := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	var cur_d: float = to_g.length()
	if cur_d < 1.0:
		return false
	var fwd: Vector3 = to_g / cur_d
	for check_mates in [true, false]:
		for rad in [2.2, 3.6, 5.2]:
			for deg in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
				var dir: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(float(deg)))
				var cand: Vector3 = global_position + dir * float(rad)
				var spot: Vector3 = _validate_stand_spot(cand, global_position, false, check_mates, 2.0)
				if spot == Vector3.INF:
					continue
				var new_d: float = Vector2(goal.x - spot.x, goal.z - spot.z).length()
				if new_d >= cur_d - 0.6:
					continue
				if _crosses_closed_gate(global_position, spot):
					continue
				GoreFXScript.flash_light(self, global_position + Vector3.UP, profile.color, 2.0, 0.2, 2.5)
				global_position = spot
				velocity = Vector3.ZERO
				_last_pos = spot
				_stuck_anchor_pos = spot
				_stuck_strikes = 0
				GoreFXScript.flash_light(self, global_position + Vector3.UP, profile.color, 2.5, 0.25, 2.5)
				return true
	return false


func _unstick_nudge() -> void:
	var fwd: Vector3 = facing_direction.normalized() if facing_direction.length_squared() > 0.001 else Vector3.FORWARD
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var sign_k: float = 1.0 if slot_index % 2 == 0 else -1.0
	for cand in [side * sign_k, -side * sign_k, -fwd]:
		var dir: Vector3 = cand as Vector3
		if _side_open(dir):
			velocity.x = dir.x * 3.5
			velocity.z = dir.z * 3.5
			return


func _update_stuck(delta: float) -> void:
	var moved: float = Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	var anchor_dx: float = global_position.x - _stuck_anchor_pos.x
	var anchor_dz: float = global_position.z - _stuck_anchor_pos.z
	var anchor_dist: float = Vector2(anchor_dx, anchor_dz).length()
	var wants: bool = _want_move_this_frame or Vector2(velocity.x, velocity.z).length() > 1.0
	_last_pos = global_position
	var progressed: bool = false
	if _want_move_goal != Vector3.INF:
		var gx: float = _want_move_goal.x - _stuck_anchor_pos.x
		var gz: float = _want_move_goal.z - _stuck_anchor_pos.z
		var g_dir := Vector2(gx, gz)
		if g_dir.length() > 0.5:
			progressed = Vector2(anchor_dx, anchor_dz).dot(g_dir.normalized()) > 1.0
		else:
			progressed = anchor_dist > 1.25
	else:
		progressed = anchor_dist > 1.25
	if progressed:
		_stuck_anchor_pos = global_position
		_stuck_timer = 0.0
		_stuck_strikes = 0
	elif wants:
		_stuck_timer += delta if moved < 0.75 * delta else delta * 0.85
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)
	if _stuck_timer > 1.6:
		_stuck_timer = 0.0
		_stuck_anchor_pos = global_position
		var p: Node3D = _player()
		if _in_pit_kill_zone() or global_position.y < -20.0:
			_rescue_from_pit(p)
			return
		if _is_embedded_in_world():
			_recover_from_embedded(p)
			return
		if p == null:
			return
		var player_bound_stuck: bool = not has_free_leash() or (
			_want_move_goal != Vector3.INF
			and _want_move_goal.distance_to(p.global_position) <= 5.0
			and current != null
			and current.verb in ["position", "retreat", "rearguard", "bodyguard"]
		)
		if player_bound_stuck:
			_blink_to(p)
			return
		if _stuck_strikes == 0:
			_steer_dir = Vector3.ZERO
			_steer_timer = 0.0
			if is_on_floor():
				velocity.y = 4.5
			_unstick_nudge()
			_stuck_strikes = 1
		elif _stuck_strikes == 1:
			if _unstick_bypass(_want_move_goal):
				return
			_unstick_nudge()
			_stuck_strikes = 2
		else:
			_blink_to(p)
			_stuck_strikes = 0


## Catch-up: allies are mirror echoes — passive follow/ceasefire allies blink back to the player when left behind,
## whereas allies under ANY active command (has_free_leash() == true) never distance-teleport and only rescue
## safely on real pit/void falls.
func _catch_up(player: Node3D) -> void:
	var free_leash: bool = has_free_leash()
	var in_pit: bool = _in_pit_kill_zone() or global_position.y < -20.0
	if free_leash:
		if not in_pit:
			return
		_rescue_from_pit(player)
		return
	var d: Vector3 = player.global_position - global_position
	var cam_exempt: bool = _distant_order_cam_visible()
	var far: float = 150.0 if cam_exempt else FOLLOW_LEASH
	var fallen_pit: bool = in_pit or global_position.y < player.global_position.y - 6.0
	var vertical_trap: bool = d.y > 3.0 and Vector2(d.x, d.z).length() < 10.0
	if not (d.length() > far or vertical_trap or fallen_pit):
		return
	if not fallen_pit:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null and cam.is_position_in_frustum(global_position):
			var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
			if space != null:
				var los_mask: int = collision_mask & ~RealmManager.LAYER_PLAYER_BLOCKER
				var excl: Array[RID] = [get_rid()]
				if player is CollisionObject3D:
					excl.append((player as CollisionObject3D).get_rid())
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, global_position + Vector3.UP * 0.9, los_mask, excl)
				var hit: Dictionary = space.intersect_ray(q)
				if hit.is_empty() and d.length() < (150.0 if cam_exempt else 40.0):
					return
	if player is PlayerController:
		var pc: PlayerController = player as PlayerController
		if pc.is_currently_airborne() or pc.current_state == PlayerController.State.DODGE:
			if fallen_pit:
				_rescue_from_pit(player)
			return
	_blink_to(player)


func _blink_to(player: Node3D) -> void:
	if player == null or not is_instance_valid(player) or not is_inside_tree():
		return
	var spot: Vector3 = find_safe_spot_around(player)
	if spot == Vector3.INF:
		return
	GoreFXScript.flash_light(self, global_position + Vector3.UP, profile.color, 2.5, 0.25, 3.0)
	global_position = spot
	velocity = Vector3.ZERO
	_last_pos = spot
	_stuck_anchor_pos = spot
	_stuck_timer = 0.0
	_stuck_strikes = 0
	GoreFXScript.flash_light(self, global_position + Vector3.UP, profile.color, 3.0, 0.3, 3.0)


func _update_anim() -> void:
	if not _action.is_empty() or _stagger_timer > 0.0 or is_downed or _dash_timer > 0.0:
		return
	var sp: float = Vector2(velocity.x, velocity.z).length()
	if sp > 3.4:
		_play(["Running_A", "Running_B"], -1.0, false, true)
	elif sp > 0.4:
		_play(["Walking_A", "Walking_B", "Running_A"], -1.0, false, true)
	elif _engage_target != null and _enemy_ok(_engage_target):
		_play(["Idle_Combat", "2H_Melee_Idle", "Idle"], -1.0, false, true)
	else:
		_play(["Idle", "Idle_B"], -1.0, false, true)


# ------------------------------------------------------------------ queries

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _enemy_ok(e: EnemyAI) -> bool:
	return e != null and is_instance_valid(e) and not e.is_dead and e.is_active and e.is_inside_tree() and e.is_hittable_now()


func _active_enemies(center: Vector3, radius: float) -> Array[EnemyAI]:
	var out: Array[EnemyAI] = []
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = n as EnemyAI
		if e == null or not _enemy_ok(e):
			continue
		if e.global_position.distance_to(center) <= radius and absf(e.global_position.y - center.y) < 4.0:
			out.append(e)
	return out


func _nearest_enemy(center: Vector3, radius: float) -> EnemyAI:
	var best: EnemyAI = null
	var bd: float = radius
	for e in _active_enemies(center, radius):
		var d: float = e.global_position.distance_to(center)
		if d < bd:
			bd = d
			best = e
	return best


func _enemies_targeting_me() -> Array[EnemyAI]:
	var out: Array[EnemyAI] = []
	for e in _active_enemies(global_position, 16.0):
		if e.get_current_target() == self:
			out.append(e)
	return out


func _cluster_centroid() -> Vector3:
	var chasers: Array[EnemyAI] = _enemies_targeting_me()
	if chasers.is_empty():
		var e: EnemyAI = _nearest_enemy(global_position, 12.0)
		return e.global_position if e != null else global_position
	var c := Vector3.ZERO
	for e in chasers:
		c += e.global_position
	return c / float(chasers.size())


func _threat_centroid(center: Vector3, radius: float) -> Vector3:
	var list: Array[EnemyAI] = []
	for e in _active_enemies(center, radius):
		if e.is_aggroed():
			list.append(e)
	if list.is_empty():
		return Vector3.INF
	var c := Vector3.ZERO
	for e in list:
		c += e.global_position
	return c / float(list.size())


func _pick_auto_target(player: Node3D, radius: float = -1.0, any: bool = false) -> EnemyAI:
	if manager != null and manager.has_method("pick_enemy_for"):
		return manager.call("pick_enemy_for", self, player, radius if radius > 0.0 else profile.aggro_radius, any) as EnemyAI
	return _nearest_enemy(global_position, profile.aggro_radius)


func _resolve_enemy(selector: String, player: Node3D) -> EnemyAI:
	if manager != null and manager.has_method("resolve_enemy"):
		return manager.call("resolve_enemy", selector, player.global_position if player != null else global_position, self) as EnemyAI
	return _nearest_enemy(global_position, 20.0)


func _resolve_ward(sel: String, player: Node3D) -> Node3D:
	if sel.is_empty() or sel == "player" or sel == "me":
		return player
	if sel == "objective":
		# Nearest live objective: an un-activated switch / lever, else a mechanism target.
		var best: Node3D = null
		var bd: float = 30.0
		for grp in ["interactable_switch", "mechanism_target"]:
			for n in get_tree().get_nodes_in_group(grp):
				if n is SquadAlly or not (n is Node3D):
					continue
				var d: float = (n as Node3D).global_position.distance_to(player.global_position if player != null else global_position)
				if d < bd:
					bd = d
					best = n as Node3D
		if best != null:
			return best
		say("No objective nearby — guarding you instead.", "refuse", 1)
		return player
	if manager != null and manager.has_method("find_ally"):
		var a: SquadAlly = manager.call("find_ally", sel) as SquadAlly
		if a != null and a != self:
			return a
	return player
