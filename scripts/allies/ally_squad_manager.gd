class_name AllySquadManager
extends Node
## Owns the ally squad: spawns one `SquadAlly` per `AllyProfile` in `res://data/allies/` (sorted by `order`;
## a 4th ally = drop in a 4th .tres), routes every command (typed chat, Whisper voice and LLM tool calls all
## arrive here as the same Dictionary schema), enforces priority / mission lock / queues, coordinates the
## two-ally handshake combos (kite+nuke, charge+finish, lure+detonate) with graceful substitution and solo
## fallbacks, picks no-stacking targets for auto-engage, and publishes the live roster for HUD + LLM prompts.

const AllyScript := preload("res://scripts/allies/squad_ally.gd")
const ProfileScript := preload("res://scripts/allies/ally_profile.gd")
const CommandScript := preload("res://scripts/allies/squad_command.gd")
const ALLY_DIR: String = "res://data/allies/"

signal ally_spoke(ally_name: String, text: String, event: String, priority: int, voice: String)
signal roster_changed(roster: Array)
signal command_logged(entry: Dictionary)
signal combo_progress(kind: String, text: String)
signal squad_ready(allies: Array)

static var instance: AllySquadManager = null

@export var spawn_allies: bool = true
@export var max_allies: int = 6

var allies: Array[SquadAlly] = []
## Shared battlefield knowledge (enemy IDs, looks, weapons, positions) used by allies, parser and Director.
var intel: WorldIntel = null
var _combos: Dictionary = {}     # id -> combo record
var _combo_seq: int = 0
var _player: Node3D = null
var _player_was_dead: bool = false
var _roster_dirty: bool = true
var _roster_timer: float = 0.0
var _hud: Node = null


func _enter_tree() -> void:
	instance = self
	add_to_group("squad_manager")


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	intel = WorldIntel.new()
	intel.name = "WorldIntel"
	add_child(intel)
	if spawn_allies:
		call_deferred("_spawn_squad")
	call_deferred("_connect_director")


func _connect_director() -> void:
	if EncounterDirector.instance != null and not EncounterDirector.instance.player_respawned.is_connected(_on_director_player_respawned):
		EncounterDirector.instance.player_respawned.connect(_on_director_player_respawned)


func _on_director_player_respawned(_sec_id: int, _xform: Transform3D) -> void:
	regroup(true)


# ------------------------------------------------------------------ spawning

static func load_profiles() -> Array[AllyProfile]:
	var out: Array[AllyProfile] = []
	var dir := DirAccess.open(ALLY_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var path: String = f.trim_suffix(".remap")
		if not (path.ends_with(".tres") or path.ends_with(".res")):
			continue
		var res: Resource = load(ALLY_DIR + path)
		if res is AllyProfile:
			out.append(res as AllyProfile)
	out.sort_custom(func(a: AllyProfile, b: AllyProfile) -> bool: return a.order < b.order)
	return out


func _spawn_squad() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var profiles: Array[AllyProfile] = load_profiles()
	var idx: int = 0
	for p in profiles:
		if idx >= max_allies:
			break
		var a: SquadAlly = AllyScript.new() as SquadAlly
		a.setup(p, self, idx)
		add_child(a)
		var spawn: Vector3 = (a.call("_formation_point", _player) as Vector3) if _player != null else Vector3(float(idx) * 1.5, 0.0, 0.0)
		a.global_position = spawn + Vector3.UP * 0.1
		a.health_changed.connect(_on_ally_health)
		a.downed.connect(_on_ally_downed)
		a.revived.connect(_on_ally_revived)
		a.command_finished.connect(_on_ally_command_finished)
		allies.append(a)
		idx += 1
	_bind_hud()
	_roster_dirty = true
	squad_ready.emit(allies)


func _bind_hud() -> void:
	_hud = get_tree().get_first_node_in_group("hud")
	if _hud == null or not _hud.has_method("set_interact_prompt"):
		return
	for a in allies:
		if not a.prompt_changed.is_connected(_hud.set_interact_prompt):
			a.prompt_changed.connect(_hud.set_interact_prompt)


# ------------------------------------------------------------------ frame

func _physics_process(delta: float) -> void:
	_watch_player()
	_tick_rally(delta)
	_tick_combos(delta)
	_tick_banter(delta)
	_roster_timer -= delta
	if _roster_dirty and _roster_timer <= 0.0:
		_roster_dirty = false
		_roster_timer = 0.25
		roster_changed.emit(get_roster())


func _watch_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	var dead: bool = _player is PlayerController and (_player as PlayerController).current_state == PlayerController.State.DEAD
	if _player_was_dead and not dead:
		regroup(true)
	_player_was_dead = dead


# ------------------------------------------------------------------ auto-rally (protect the wounded)

## When the player or a squad-mate is low on health with enemies on them, every other able ally drops what it
## is doing (stances, finite orders — not panic orders or a revive in progress) and rushes in to bodyguard
## them until it's safe: HP back above `RALLY_SAFE_HP`, or no enemy within `RALLY_CLEAR_R` for 2.5 s. The
## interrupted orders resume afterwards. `rally_enabled` can be toggled ("stop protecting" etc. via settings).
const RALLY_PLAYER_HP: float = 0.35
const RALLY_ALLY_HP: float = 0.40
const RALLY_SAFE_HP: float = 0.55
const RALLY_DANGER_R: float = 7.0
const RALLY_CLEAR_R: float = 9.0
var rally_enabled: bool = true
var _rally_scan: float = 0.0
var _rally: Dictionary = {}          # ward Node3D -> {"clear_t": float, "allies": Array[SquadAlly]}
var _rally_cooldown: Dictionary = {} # ward Node3D -> seconds before it can trigger again


func _tick_rally(delta: float) -> void:
	for w in _rally_cooldown.keys():
		_rally_cooldown[w] = float(_rally_cooldown[w]) - delta
		if float(_rally_cooldown[w]) <= 0.0:
			_rally_cooldown.erase(w)
	_rally_scan -= delta
	# Keep active rallies honest every frame-ish; look for new ones a few times a second.
	for w2 in _rally.keys():
		_update_rally(w2 as Node3D, delta)
	if _rally_scan > 0.0 or not rally_enabled or _player == null:
		return
	_rally_scan = 0.3
	var wards: Array[Node3D] = []
	if _player is PlayerController:
		var pc: PlayerController = _player as PlayerController
		if pc.current_state != PlayerController.State.DEAD and float(pc.health) / float(maxi(1, pc.max_health)) < RALLY_PLAYER_HP:
			wards.append(_player)
	for a in get_living():
		if a.get_health_ratio() < RALLY_ALLY_HP:
			wards.append(a)
	for w3 in wards:
		if _rally.has(w3) or _rally_cooldown.has(w3):
			continue
		if _threats_on(w3, RALLY_DANGER_R).is_empty():
			continue
		_start_rally(w3)


func _threats_on(ward: Node3D, radius: float) -> Array[EnemyAI]:
	# Anything chasing the ward counts from further out (a wounded ally retreats while being chased).
	var out: Array[EnemyAI] = []
	for e in _active_enemies_near(ward.global_position, radius + 6.0):
		var d: float = e.global_position.distance_to(ward.global_position)
		if e.get_current_target() == ward or (e.is_aggroed() and d <= radius):
			out.append(e)
	return out


func _ward_name(ward: Node3D) -> String:
	if ward == _player:
		return "player"
	return (ward as SquadAlly).get_display_name() if ward is SquadAlly else ""


func _start_rally(ward: Node3D) -> void:
	var helpers: Array[SquadAlly] = []
	for a in get_living():
		if a == ward:
			continue
		var cur: SquadCommand = a.current
		if cur != null and not cur.done:
			if cur.priority >= SquadCommand.Priority.PANIC or cur.verb == "revive" or cur.combo_id != 0 or bool(cur.data.get("rally", false)):
				continue
			if cur.verb == "bodyguard" and String(cur.args.get("target", "")) == _ward_name(ward):
				continue  # already guarding them
		# ORDER priority (not mission): a fresh order from the player still takes over, and the rally resumes after.
		var cmd := SquadCommand.make("bodyguard", {"target": _ward_name(ward)}, "auto")
		cmd.priority = SquadCommand.Priority.ORDER
		if cur != null and not cur.done:
			a.enqueue(cur, true)   # resumes once the ward is safe
		a.assign(cmd)
		cmd.data["rally"] = true   # assign() resets data for non-combo commands
		helpers.append(a)
	if helpers.is_empty():
		return
	_rally[ward] = {"clear_t": 0.0, "allies": helpers}
	var line: String = "You're hurt — everyone on you, now!" if ward == _player else "%s is hurt — protect %s!" % [(ward as SquadAlly).get_display_name(), (ward as SquadAlly).get_display_name()]
	helpers[0].say(line, "rally", 2)
	_log("auto", ", ".join(_names(helpers)), "rally to " + (_ward_name(ward)), "protecting")
	_roster_dirty = true


func _update_rally(ward: Node3D, delta: float) -> void:
	var rec: Dictionary = _rally[ward] as Dictionary
	var gone: bool = not is_instance_valid(ward) or (ward is SquadAlly and (ward as SquadAlly).is_downed) \
		or (ward is PlayerController and (ward as PlayerController).current_state == PlayerController.State.DEAD)
	var hp: float = 0.0
	if not gone:
		hp = (ward as SquadAlly).get_health_ratio() if ward is SquadAlly else float((ward as PlayerController).health) / float(maxi(1, (ward as PlayerController).max_health))
		if _threats_on(ward, RALLY_CLEAR_R).is_empty():
			rec["clear_t"] = float(rec["clear_t"]) + delta
		else:
			rec["clear_t"] = 0.0
	var safe: bool = gone or hp >= RALLY_SAFE_HP or float(rec["clear_t"]) >= 2.5
	if not safe:
		return
	for a in (rec["allies"] as Array):
		var ally: SquadAlly = a as SquadAlly
		if is_instance_valid(ally) and ally.current != null and bool(ally.current.data.get("rally", false)):
			ally.finish_current("safe")
	_rally.erase(ward)
	if is_instance_valid(ward):
		_rally_cooldown[ward] = 4.0
	var helpers: Array = rec["allies"] as Array
	if not gone and not helpers.is_empty() and is_instance_valid(helpers[0]):
		(helpers[0] as SquadAlly).say("Clear. Back to it.", "rally_end", 1)
	_log("auto", "squad", "rally over", "safe" if not gone else "ward down")
	_roster_dirty = true


func is_rallying() -> bool:
	return not _rally.is_empty()


var _banter_timer: float = 45.0

## Ambient banter between two allies when no fight is on (subtitle-only chatter, personality lines only).
func _tick_banter(delta: float) -> void:
	_banter_timer -= delta
	if _banter_timer > 0.0:
		return
	_banter_timer = randf_range(50.0, 95.0)
	var living: Array[SquadAlly] = get_living()
	if living.size() < 2 or _player == null:
		return
	if not _active_enemies_near(_player.global_position, 18.0).filter(func(e: EnemyAI) -> bool: return e.is_aggroed()).is_empty():
		return
	living.shuffle()
	var a: SquadAlly = living[0]
	var b: SquadAlly = living[1]
	a.say_event("banter", 0)
	get_tree().create_timer(2.4).timeout.connect(func() -> void:
		if is_instance_valid(b) and not b.is_downed:
			b.say_event("banter_reply", 0))


## Teleport the squad to formation around the player (full heal on respawn / new run).
func regroup(full_heal: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	for a in allies:
		if not is_instance_valid(a):
			continue
		var p: Vector3 = a.call("_formation_point", _player) as Vector3
		if full_heal:
			a.reset_full(p)
		else:
			a.global_position = p
	_combos.clear()
	_roster_dirty = true


# ------------------------------------------------------------------ queries

func get_living() -> Array[SquadAlly]:
	var out: Array[SquadAlly] = []
	for a in allies:
		if is_instance_valid(a) and not a.is_downed:
			out.append(a)
	return out


func find_ally(n: String) -> SquadAlly:
	var key: String = n.strip_edges().to_lower()
	if key.is_empty():
		return null
	for a in allies:
		if a.get_display_name().to_lower() == key or a.get_role() == key:
			return a
	for a in allies:
		if a.get_display_name().to_lower().begins_with(key):
			return a
	return null


func nearest_downed(pos: Vector3, exclude: Node = null) -> SquadAlly:
	var best: SquadAlly = null
	var bd: float = INF
	for a in allies:
		if a == exclude or not a.is_downed:
			continue
		var d: float = a.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = a
	return best


func get_ally_names() -> Array:
	var out: Array = []
	for a in allies:
		out.append(a.get_display_name())
	return out


func get_roster() -> Array:
	var out: Array = []
	for a in allies:
		out.append({
			"name": a.get_display_name(),
			"role": a.get_role(),
			"hp": a.health,
			"max_hp": a.max_health,
			"downed": a.is_downed,
			"state": a.get_state_text(),
			"color": a.profile.color,
			"queued": a.queue.size(),
			"abilities": a.profile.abilities,
			"skills": a.get_skill_states(),
			"buffs": ("+DMG " if a._dmg_buff > 0.0 else "") + ("WALL " if a._dr > 0.0 else "") + ("WARD" if a._ward_hp > 0.0 else ""),
		})
	return out


## Plain-text roster for LLM system prompts (refreshed automatically on death / revive): role, look,
## HP, current order, where they stand relative to the player, and every signature skill with its cooldown.
func get_roster_text() -> String:
	var lines: PackedStringArray = []
	for a in allies:
		var st: String = "DOWN (needs revive)" if a.is_downed else "%d%% HP, doing: %s" % [int(a.get_health_ratio() * 100.0), a.get_state_text()]
		var where: String = ""
		if _player != null:
			var rel: Vector3 = a.global_position - _player.global_position
			where = ", %.0fm from you" % rel.length()
		var sk: PackedStringArray = []
		for s in a.profile.get_skills():
			var rem: float = a.skill_remaining(s)
			sk.append("%s [%s]%s" % [s.id, "ready" if rem <= 0.0 else "%ds" % int(ceil(rem)), "" if rem > 0.0 else ""])
		lines.append("- %s (%s%s): %s. Skills: %s. Base abilities: %s." % [a.get_display_name(), a.get_role(), where, st, ", ".join(sk), ", ".join(a.profile.abilities)])
	return "\n".join(lines)


## Skill catalogue for prompts: one line per skill with what it does.
func get_skills_text() -> String:
	var lines: PackedStringArray = []
	for a in allies:
		for s in a.profile.get_skills():
			lines.append("- %s.%s \"%s\" (%s target, %ds cd): %s" % [a.get_display_name(), s.id, s.display_name, s.target_kind, int(s.cooldown), s.description])
	return "\n".join(lines)


## Vocabulary the offline parser needs from live data (skills and their aliases per ally).
func get_parser_context() -> Dictionary:
	var sk: Array = []
	for a in allies:
		for s in a.profile.get_skills():
			sk.append({"ally": a.get_display_name(), "id": s.id, "name": s.display_name, "aliases": s.aliases})
	return {"skills": sk}


func get_combat_summary() -> String:
	var n: int = 0
	var kinds: Dictionary = {}
	var c: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	for node in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = node as EnemyAI
		if e == null or e.is_dead or not e.is_active or e.global_position.distance_to(c) > 25.0:
			continue
		n += 1
		var k: String = _enemy_kind(e)
		kinds[k] = int(kinds.get(k, 0)) + 1
	if n == 0:
		return "No enemies nearby."
	var parts: PackedStringArray = []
	for k in kinds.keys():
		parts.append("%d %s" % [int(kinds[k]), k])
	return "Enemies within 25 m: " + ", ".join(parts) + "."


# ------------------------------------------------------------------ enemy selection

func _enemy_kind(e: EnemyAI) -> String:
	if e is ArchetypeEnemy and (e as ArchetypeEnemy).archetype != null:
		var id: String = (e as ArchetypeEnemy).archetype.id
		if id.contains("brute"):
			return "brute"
		if id.contains("hex"):
			return "caster"
		if id.contains("stalker"):
			return "stalker"
		return id
	if e is WardenBoss:
		return "warden"
	if e is ShieldedGuard:
		return "shield"
	if e is PhantomTwin:
		return "phantom"
	return "skeleton"


func _active_enemies_near(pos: Vector3, radius: float) -> Array[EnemyAI]:
	var out: Array[EnemyAI] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = node as EnemyAI
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree() or not e.is_hittable_now():
			continue
		var in_radius: bool = e.global_position.distance_to(pos) <= radius and absf(e.global_position.y - pos.y) < 5.0
		var cam_vis: bool = radius >= 25.0 and intel != null and intel.is_camera_visible(e)
		if in_radius or cam_vis:
			out.append(e)
	return out


func resolve_enemy(selector: String, near: Vector3) -> EnemyAI:
	var sel: String = selector.strip_edges().to_lower()
	# "ally:Sera" / "Sera's target": whatever that ally is fighting.
	if sel.begins_with("ally:") or sel.ends_with("'s target"):
		var mate: SquadAlly = find_ally(sel.trim_prefix("ally:").trim_suffix("'s target"))
		if mate != null:
			var et: EnemyAI = mate._engage_target
			if (et == null or not is_instance_valid(et)) and mate.current != null:
				et = mate.current.data.get("enemy", null) as EnemyAI
			if et != null and is_instance_valid(et) and not et.is_dead and et.is_active and et.is_hittable_now():
				return et
		sel = "nearest"
	# Shared knowledge base: IDs ("E3"), types, looks, colours, weapons, sides, "near Sera", "hitting Ivo"...
	if intel != null:
		return intel.resolve(sel)
	var cands: Array[EnemyAI] = _active_enemies_near(near, 25.0)
	if cands.is_empty():
		return null
	var filtered: Array[EnemyAI] = []
	if sel in ["brute", "caster", "stalker", "phantom", "shield", "skeleton", "warden"]:
		for e in cands:
			if _enemy_kind(e) == sel:
				filtered.append(e)
	elif not (sel in ["", "nearest", "strongest", "weakest", "any", "them", "it"]):
		for e in cands:
			var dn: String = String(e.call("get_display_name")) if e.has_method("get_display_name") else String(e.name)
			if dn.to_lower().contains(sel) or String(e.name).to_lower().contains(sel):
				filtered.append(e)
	if filtered.is_empty():
		filtered = cands
	var best: EnemyAI = null
	var bs: float = INF
	for e in filtered:
		var s: float = e.global_position.distance_to(near)
		if sel == "strongest":
			s = -float(e.health)
		elif sel == "weakest":
			s = float(e.health) / float(maxi(1, e.max_health))
		if e.is_aggroed():
			s -= 0.5 if sel in ["strongest", "weakest"] else 4.0
		if s < bs:
			bs = s
			best = e
	return best


## No-stacking auto-target: prefers enemies threatening the player / this ally and penalises enemies that
## other allies already hold.
func pick_enemy_for(ally: SquadAlly, player: Node3D, radius: float, any: bool) -> EnemyAI:
	var center: Vector3 = ally.global_position
	var pool: Array[EnemyAI] = _active_enemies_near(center, radius)
	if player != null:
		for e in _active_enemies_near(player.global_position, radius):
			if not pool.has(e):
				pool.append(e)
	var best: EnemyAI = null
	var bs: float = INF
	for e in pool:
		var t: Node3D = e.get_current_target()
		if not any and not e.is_aggroed() and e.global_position.distance_to(center) > ally.profile.aggro_radius * 0.7:
			continue
		var s: float = e.global_position.distance_to(center)
		if t == player:
			s -= 3.0
		elif t == ally:
			s -= 2.0
		for o in allies:
			if o != ally and is_instance_valid(o) and o._engage_target == e:
				s += 4.0
		if s < bs:
			bs = s
			best = e
	return best


# ------------------------------------------------------------------ command intake

## Main entry for parser / LLM tool calls. Returns a short human-readable result per command.
func issue_commands(cmds: Array, source: String = "chat") -> Array[String]:
	var results: Array[String] = []
	begin_batch()
	for c in cmds:
		if c is Dictionary:
			results.append(issue(c as Dictionary, source))
	end_batch()
	return results


# ------------------------------------------------------------------ one message = one batch (chains)

## Everything said in ONE message (typed, voice, or one LLM turn) is a batch: when the same ally gets several
## orders in it, they run as a CHAIN in the order given ("jump twice, then get behind me, then shoot the
## caster"). Stances inside a chain (position / hold / follow / rear guard ...) become timed steps that
## complete on arrival (or after `step_sec`), so the next step can run; the last step keeps its normal
## behaviour. Different allies get different chains from the same sentence.
var _batch_depth: int = 0
var _batch: Dictionary = {}          # SquadAlly -> Array[SquadCommand] in issue order
const CHAIN_STEP_VERBS: Array[String] = ["follow", "hold", "position", "rearguard", "overwatch", "retreat"]


func begin_batch() -> void:
	if _batch_depth == 0:
		_batch.clear()
	_batch_depth += 1


func end_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth > 0:
		return
	for a in _batch.keys():
		var ally: SquadAlly = a as SquadAlly
		var chain: Array = _batch[a] as Array
		if chain.size() < 2 or not is_instance_valid(ally) or ally.is_downed:
			continue
		for i in range(chain.size() - 1):
			var c: SquadCommand = chain[i] as SquadCommand
			if c.verb in CHAIN_STEP_VERBS:
				c.args["chain_step"] = true
				c.finite = true
		var pending: Array = chain.filter(func(c2: SquadCommand) -> bool: return not c2.done)
		if pending.is_empty():
			continue
		# Old stances are superseded by the new chain; older finite / mission orders wait after it.
		var old: Array = ally.queue.filter(func(q: SquadCommand) -> bool: return not chain.has(q) and not q.stance)
		var cur: SquadCommand = ally.current
		var rest: Array = []
		if cur != null and not cur.done and not chain.has(cur) and cur.is_mission() and cur.priority >= (pending[0] as SquadCommand).priority:
			rest = pending   # mission lock: the whole chain waits behind it
		else:
			if cur != pending[0]:
				ally.assign(pending[0] as SquadCommand)
			rest = pending.slice(1)
		ally.queue.clear()
		for r in rest:
			ally.queue.append(r as SquadCommand)
		for o in old:
			ally.queue.append(o as SquadCommand)
		_log("chain", ally.get_display_name(), " → ".join(chain.map(func(c3: SquadCommand) -> String: return c3.describe())), "%d steps" % chain.size())
	_batch.clear()
	_roster_dirty = true


func _batch_record(a: SquadAlly, cmd: SquadCommand) -> void:
	if _batch_depth <= 0:
		return
	if not _batch.has(a):
		_batch[a] = []
	(_batch[a] as Array).append(cmd)


## Small talk: the addressed ally (or the leader) answers in character; nobody moves.
func _issue_chat(c: Dictionary, addressed: Array[SquadAlly], source: String) -> String:
	var who: SquadAlly = null
	for a in addressed:
		if not a.is_downed:
			who = a
			break
	if who == null:
		who = _leader()
	if who == null:
		return "nobody to talk to"
	var topic: String = String(c.get("topic", "generic"))
	var line: String = who.profile.line("chat_" + topic, "")
	if line.is_empty():
		var pool: Array = CHAT_LINES.get(topic, CHAT_LINES["generic"]) as Array
		line = String(pool[randi() % pool.size()])
		line = line.replace("{name}", who.get_display_name()).replace("{role}", who.get_role())
		if topic == "mood":
			line = line.replace("{hp}", str(int(who.get_health_ratio() * 100.0)))
	who.say(line, "chat", 1)
	if topic in ["joke", "praise", "love"]:
		who._play(["Cheer", "Interact"], 1.0, true)
	_log(source, who.get_display_name(), "chat " + topic, "replied")
	return "%s replied" % who.get_display_name()


const CHAT_LINES: Dictionary = {
	"greet": ["Hey. Still breathing, I see.", "Well met, again.", "Here. Always here.", "Oh — hi. Eyes up, though."],
	"thanks": ["Anytime.", "Don't mention it. Really, don't.", "That's what the mirror made me for.", "You'd do the same. Probably."],
	"praise": ["Ha! Told you I was worth summoning.", "Keep talking, I'm listening.", "We make a decent team, you and I.", "Don't get sentimental on me now."],
	"joke": ["Why did the skeleton skip the fight? No guts.", "I asked the Warden for directions. He pointed. With an axe.", "Phantoms make terrible friends. They see right through you.", "My reflection is the better-looking one. Don't tell it."],
	"intro": ["{name}. The {role}. Your echo, for better or worse.", "Name's {name}. I hit what you point at.", "{name} — {role}. The mirror spat me out next to you; here we are."],
	"opinion": ["Let's take the loud ones first and the clever ones second.", "Honestly? Stay together and let me handle the flank.", "Kill the casters, then the brute. Then lunch.", "I'd go the Mirror — it shows you where they're weak."],
	"mood": ["Running at about {hp} percent, and grumpy.", "I'm fine. Mostly. {hp} percent of fine.", "Better than the skeletons."],
	"sing": ["♪ Glass and bone, glass and bone, nobody leaves the arena alone ♪", "♪ Oh the Warden's got a hammer and a terrible mood ♪", "Absolutely not. ...Fine. La la la. Happy?"],
	"story": ["Once, a champion looked into the mirror and the mirror looked back. That's how we got here.", "Long story. Short version: arena, mirror, us. Keep walking."],
	"love": ["...Focus on the fight.", "Aw. Same. Now duck.", "Careful, my reflection gets jealous."],
	"sorry": ["Already forgotten.", "Happens. Don't do it again."],
	"bored": ["Bored? There's a skeleton over there that disagrees.", "Want me to jump around? I can jump around."],
	"bye": ["Don't go far.", "We'll be right here. Literally. We can't leave."],
	"where": ["The arena between the realms. Reality on one side, the Mirror on the other.", "Somewhere the mirror wanted us. Keep heading north."],
	"generic": ["Mm-hm. I'm listening.", "Right. And?", "Fair enough.", "If you say so, boss.", "Noted."],
}


func issue(c: Dictionary, source: String = "chat") -> String:
	var verb: String = String(c.get("verb", "")).strip_edges().to_lower()
	if verb.is_empty():
		return "ignored: empty command"
	var addressed: Array[SquadAlly] = _recipients(c)
	var desc: String = verb
	if not SquadCommand.is_known_verb(verb):
		# Unknown verb from an LLM: never crash, just let someone be confused about it.
		var who: SquadAlly = addressed[0] if not addressed.is_empty() else _leader()
		if who != null:
			who.say_event("confused", 1)
		_log(source, "?", verb, "unknown")
		return "unknown verb '%s'" % verb
	var cmd: SquadCommand = SquadCommand.make(verb, c, source)
	desc = cmd.describe()
	match verb:
		"combo_kite_nuke", "combo_charge_finish", "combo_lure_detonate":
			var r: String = _start_combo(verb, c, addressed, source)
			_log(source, ", ".join(_names(addressed)) if not addressed.is_empty() else "squad", desc, r)
			return r
		"say":
			var who2: SquadAlly = addressed[0] if not addressed.is_empty() else _leader()
			if who2 == null:
				return "nobody to speak"
			if bool(c.get("confused", false)) or String(c.get("text", "")).is_empty():
				who2.say_event("confused", 1)
				_log(source, who2.get_display_name(), "confused", "?")
				return "%s didn't understand" % who2.get_display_name()
			who2.say(String(c.get("text", "")), "say", 1)
			return "%s spoke" % who2.get_display_name()
		"status":
			for a in (addressed if not addressed.is_empty() else allies):
				if a.is_downed:
					continue
				a.say("%d%% health. %s." % [int(a.get_health_ratio() * 100.0), a.get_state_text().capitalize()], "status", 1)
			_log(source, "squad", "status", "reported")
			return "status reported"
		"auto_engage":
			var on: bool = bool(c.get("enabled", true))
			for a in addressed:
				a.auto_engage = on
				a.say_event("ack", 0)
			_log(source, ", ".join(_names(addressed)), "auto-engage " + ("on" if on else "off"), "set")
			return "auto-engage %s" % ("on" if on else "off")
		"stop":
			for a in addressed:
				a.clear_queue()
				a.finish_current("cancelled")
				a.current = null
				a.say_event("ack", 0)
			_cancel_combos_for(addressed)
			_log(source, ", ".join(_names(addressed)), "stop", "cleared")
			return "orders cancelled"
		"chat":
			return _issue_chat(c, addressed, source)
		"split":
			return _split_squad(addressed, source)
		"strategy":
			return execute_strategy(String(c.get("strategy", c.get("text", ""))), String(c.get("target", "")), addressed if _explicit_allies(c) else get_living(), source)
		"skill":
			return _issue_skill(c, source)
	# Role-based substitution: an addressed ally who is DOWN hands the order to a stand-in.
	if verb != "revive" and verb != "massacre" and verb != "ceasefire":
		var named_explicitly: bool = (c.get("allies", []) is Array) and not (c.get("allies", []) as Array).is_empty() and not ((c.get("allies", []) as Array).has("all"))
		if named_explicitly:
			var rebuilt: Array[SquadAlly] = []
			for a0 in addressed:
				if not a0.is_downed:
					rebuilt.append(a0)
					continue
				var rp: Array = ROLE_FOR_VERB.get(verb, ["", ""]) as Array
				var sub: SquadAlly = _pick_for(String(rp[1]), String(rp[0]), addressed, [])
				if sub != null and not rebuilt.has(sub):
					rebuilt.append(sub)
					sub.say("%s is down — I'll %s instead." % [a0.get_display_name(), verb.replace("_", " ")], "substitute", 2)
					_log(source, sub.get_display_name(), "substitute for " + a0.get_display_name(), verb)
				else:
					_log(source, a0.get_display_name(), desc, "dropped: ally down, no substitute")
			if rebuilt.is_empty():
				return "dropped: no ally available"
			addressed = rebuilt
	_maybe_complain(verb, c, addressed)
	var outcomes: PackedStringArray = []
	var first_spoken: bool = false
	for a in addressed:
		var own: SquadCommand = cmd.clone_for("") if addressed.size() > 1 else cmd
		var chained: bool = _batch_depth > 0 and _batch.has(a)
		var res: String = _route(a, own)
		_batch_record(a, own)
		outcomes.append("%s %s" % [a.get_display_name(), res])
		if chained:
			continue   # later steps of a chain don't re-acknowledge
		if source.ends_with("+llm"):
			continue   # the Director already voices its own `say` line for this order (no second, canned ack)
		if res == "queued (mission lock)":
			a.say_event("mission_lock", 1)
		elif not first_spoken or verb in ["massacre", "ceasefire", "scatter"]:
			var ev: String = verb if verb in ["massacre", "ceasefire", "scatter", "dance", "bodyguard", "kite", "nuke"] else "ack"
			a.say_event(ev, 2 if cmd.priority == SquadCommand.Priority.PANIC else 1, a.profile.line("ack"))
			first_spoken = true
	if verb in ["massacre", "ceasefire", "scatter"]:
		_cancel_combos_for(addressed)
	_log(source, ", ".join(_names(addressed)), desc, "; ".join(outcomes))
	_roster_dirty = true
	return "; ".join(outcomes)


func _explicit_allies(c: Dictionary) -> bool:
	var a: Variant = c.get("allies", [])
	return a is Array and not (a as Array).is_empty() and not (a as Array).has("all")


## Skill order: the named ally uses it, else whoever owns a skill matching the name.
func _issue_skill(c: Dictionary, source: String) -> String:
	var key: String = String(c.get("skill", c.get("text", "")))
	var who: SquadAlly = null
	if _explicit_allies(c):
		for n in (c.get("allies", []) as Array):
			var a: SquadAlly = find_ally(String(n))
			if a != null and a.profile.find_skill(key) != null:
				who = a
				break
	if who == null:
		for a in get_living():
			if a.profile.find_skill(key) != null:
				who = a
				break
	if who == null:
		var l: SquadAlly = _leader()
		if l != null:
			l.say("None of us knows '%s'." % key, "refuse", 1)
		_log(source, "squad", "skill " + key, "unknown")
		return "unknown skill"
	if who.is_downed:
		_log(source, who.get_display_name(), "skill " + key, "dropped: ally down")
		return "ally down"
	var s: AllySkill = who.profile.find_skill(key)
	var cmd := SquadCommand.make("skill", {"skill": s.id, "target": String(c.get("target", ""))}, source)
	# Inside a chain ("jump, then smoke bomb") the skill is a step in order, not a cut-in.
	if _batch_depth > 0 and _batch.has(who):
		_batch_record(who, cmd)
		_log(source, who.get_display_name(), "skill " + s.display_name, "chained")
		return "%s: %s (chained)" % [who.get_display_name(), s.display_name]
	_batch_record(who, cmd)
	# Skills are instant: they cut in and the interrupted order resumes right after (never queue behind it).
	var res: String = "assigned"
	if who.current != null and not who.current.done and who.current.verb != "skill":
		who.enqueue(who.current, true)
		res = "cut in (resumes %s)" % who.current.verb
	who.assign(cmd)
	_log(source, who.get_display_name(), "skill " + s.display_name, res)
	_roster_dirty = true
	return "%s: %s (%s)" % [who.get_display_name(), s.display_name, res]


## Expands a strategy (SquadStrategies.LIST) onto the living squad. Works for any ally count.
func execute_strategy(id: String, target_sel: String, list: Array[SquadAlly], source: String = "chat") -> String:
	var strat: Dictionary = SquadStrategies.get_by_id(id)
	if strat.is_empty():
		strat = SquadStrategies.match_text(id)
	if strat.is_empty():
		var l0: SquadAlly = _leader()
		if l0 != null:
			l0.say("Don't know that plan.", "refuse", 1)
		return "unknown strategy '%s'" % id
	var living: Array[SquadAlly] = []
	for a in list:
		if not a.is_downed:
			living.append(a)
	if living.is_empty():
		return "no allies standing"
	var near: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	var primary: EnemyAI = resolve_enemy(target_sel if not target_sel.is_empty() else "nearest", near)
	var primary_id: String = intel.id_of(primary) if primary != null and intel != null else "nearest"
	var by_dist: Array[EnemyAI] = []
	var by_hp: Array[EnemyAI] = []
	if intel != null:
		intel.refresh()
		for en in intel.get_entries():
			var en_node: EnemyAI = en["node"] as EnemyAI
			if en_node != null and not en_node.is_dead and en_node.is_active and en_node.is_hittable_now():
				by_dist.append(en_node)
		by_hp = by_dist.duplicate()
		by_hp.sort_custom(func(x: EnemyAI, y: EnemyAI) -> bool: return float(x.health) / float(maxi(1, x.max_health)) < float(y.health) / float(maxi(1, y.max_health)))
	var vanguard: SquadAlly = null
	for a in living:
		if a.get_role() == "vanguard":
			vanguard = a
			break
	if vanguard == null:
		vanguard = living[0]
	var weakest: String = _weakest_friend_name()
	var roles: Dictionary = strat["roles"]
	var parts: PackedStringArray = []
	var slot_i: int = 0
	var n_slot: int = 0
	for a0 in living:
		for st0 in (roles.get(a0.get_role(), roles.get("any", [])) as Array):
			if str((st0 as Dictionary).get("args", {})).contains("$slot_angle"):
				n_slot += 1
				break
	for i in range(living.size()):
		var a: SquadAlly = living[i]
		var steps: Array = (roles.get(a.get_role(), roles.get("any", [])) as Array)
		if steps.is_empty():
			continue
		a.clear_queue()
		if a.current != null and a.current.priority < SquadCommand.Priority.PANIC:
			a.finish_current("new strategy")
			a.clear_queue()
		var first: bool = true
		for st in steps:
			var args: Dictionary = ((st as Dictionary).get("args", {}) as Dictionary).duplicate(true)
			for k in args.keys():
				var v: Variant = args[k]
				if not (v is String):
					continue
				var sv: String = String(v)
				match sv:
					"$target":
						args[k] = primary_id
					"$distinct":
						args[k] = intel.id_of(by_dist[i % by_dist.size()]) if not by_dist.is_empty() else "nearest"
					"$weakest_distinct":
						args[k] = intel.id_of(by_hp[i % by_hp.size()]) if not by_hp.is_empty() else "weakest"
					"$weakest_friend":
						args[k] = weakest
					"$slot_angle":
						# Angle 0 = the player's side of the target. Pincer alternates flanks; surround spreads evenly.
						if String(strat["id"]) == "pincer":
							args[k] = 100.0 if slot_i % 2 == 0 else -100.0
						else:
							args[k] = 360.0 * float(slot_i) / float(maxi(1, n_slot)) + 180.0 / float(maxi(1, n_slot))
					"$line_spot":
						args[k] = _line_spot(i, living.size())
					"$behind_spot":
						args[k] = vanguard.global_position - (vanguard.get_facing_direction()) * 1.8 + Vector3(-vanguard.get_facing_direction().z, 0, vanguard.get_facing_direction().x) * (float(i % 2) * 2.0 - 1.0) * 1.2
					"$player_spot":
						args[k] = near
					_:
						if sv.contains("$vanguard"):
							args[k] = sv.replace("$vanguard", vanguard.get_display_name())
			if args.has("angle"):
				slot_i += 1
			var cmd := SquadCommand.make(String((st as Dictionary)["verb"]), args, source)
			if first:
				a.assign(cmd)
				first = false
			else:
				a.enqueue(cmd)
		parts.append("%s: %s" % [a.get_display_name(), a.current.describe() if a.current != null else "-"])
	var lead: SquadAlly = vanguard if not vanguard.is_downed else living[0]
	lead.say("%s! %s" % [strat["name"], _strategy_callout(strat, living)], "strategy", 2)
	var txt: String = "%s on %s — %s" % [strat["name"], primary_id, "; ".join(parts)]
	_log(source, "squad", "strategy " + String(strat["name"]), txt)
	combo_progress.emit("strategy", txt)
	active_strategy = String(strat["name"])
	_roster_dirty = true
	return txt


var active_strategy: String = ""


func _strategy_callout(strat: Dictionary, living: Array[SquadAlly]) -> String:
	var bits: PackedStringArray = []
	for a in living:
		if a.current != null:
			bits.append("%s %s" % [a.get_display_name(), a.current.describe().get_slice(" E", 0)])
	return ", ".join(bits.slice(0, 3)) + "."


func _weakest_friend_name() -> String:
	var best: String = "player"
	var br: float = 2.0
	if _player is PlayerController:
		var p: PlayerController = _player as PlayerController
		br = float(p.health) / float(maxi(1, p.max_health))
	for a in get_living():
		if a.get_health_ratio() < br:
			br = a.get_health_ratio()
			best = a.get_display_name()
	return best


func _line_spot(i: int, n: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var c: Vector3 = Vector3.INF
	if intel != null and not intel.get_entries().is_empty():
		c = Vector3.ZERO
		var k: int = 0
		for en in intel.get_entries():
			if k >= 5:
				break
			c += (en["node"] as Node3D).global_position
			k += 1
		c /= float(k)
	var f: Vector3 = (c - _player.global_position) if c != Vector3.INF else (_player.call("get_facing_direction") as Vector3)
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 0.01 else Vector3.FORWARD
	var r := Vector3(-f.z, 0.0, f.x)
	return _player.global_position + f * 3.0 + r * (float(i) - float(n - 1) * 0.5) * 2.2


## Ambush trigger: every ally lying in wait springs on the same enemy at once.
func spring_ambush(trigger: EnemyAI) -> void:
	for a in get_living():
		if a.current != null and a.current.verb == "ambush" and not bool(a.current.data.get("sprung", false)):
			a.current.data["sprung"] = true
			a.current.data["enemy"] = trigger
		elif a.current != null and a.current.verb == "kite" and a.current.args.get("lure_to", null) is Vector3:
			# The bait has done its job: turn and fight with the ambush.
			var atk := SquadCommand.make("attack", {"target": intel.id_of(trigger) if intel != null else "nearest"}, "auto")
			a.current.done = true   # replaced in place (whatever is queued after the bait still runs after the fight)
			a.assign(atk)
			atk.data["enemy"] = trigger
			a.say(["Now! Get it!", "Delivered — hit it!", "Surprise!"][randi() % 3], "ambush", 2)
	_log("event", "squad", "ambush sprung", intel.id_of(trigger) if intel != null else "")


## Split the squad across the player's left / centre / right (works for any ally count).
func _split_squad(list: Array[SquadAlly], source: String) -> String:
	if _player == null:
		return "no player"
	var f: Vector3 = _player.call("get_facing_direction") as Vector3
	var r := Vector3(-f.z, 0.0, f.x)
	var living: Array[SquadAlly] = []
	for a in list:
		if not a.is_downed:
			living.append(a)
	var lanes: Array[String] = ["left", "right", "center"]
	var parts: PackedStringArray = []
	for i in range(living.size()):
		var lane: String = lanes[i % 3]
		var depth: float = 4.0 + float(i / 3) * 2.5
		var side: float = -4.5 if lane == "left" else (4.5 if lane == "right" else 0.0)
		var spot: Vector3 = _player.global_position + f * depth + r * side
		var hold := SquadCommand.make("hold", {"spot": spot, "lane": lane}, source)
		_route(living[i], hold)
		living[i].say("Taking the %s." % lane, "ack", 1)
		parts.append("%s→%s" % [living[i].get_display_name(), lane])
	_log(source, "squad", "split", ", ".join(parts))
	return "split: " + ", ".join(parts)


## Personality flavour only: allies grumble at weird / repeated silly orders (never changes mechanics).
var _silly_count: Dictionary = {}

func _maybe_complain(verb: String, c: Dictionary, list: Array[SquadAlly]) -> void:
	if not verb in ["jump", "dance", "emote"]:
		return
	for a in list:
		var key: String = a.get_display_name()
		_silly_count[key] = int(_silly_count.get(key, 0)) + 1
		if (verb == "jump" and int(c.get("count", 1)) > 4) or int(_silly_count[key]) >= 3:
			a.say_event("complain", 1)
			_silly_count[key] = 0
			return


func _route(a: SquadAlly, cmd: SquadCommand) -> String:
	if a.is_downed and cmd.verb != "revive":
		return "is down"
	# A new stance supersedes any stance still waiting in the queue (no stale follow/hold/ceasefire pile-up).
	if cmd.stance:
		for q in a.queue.duplicate():
			if (q as SquadCommand).stance:
				a.queue.erase(q)
	var cur: SquadCommand = a.current
	if cmd.verb == "massacre" or cmd.verb == "ceasefire":
		a.clear_queue()
		a.assign(cmd)
		return "assigned"
	if cur == null or cur.done:
		a.assign(cmd)
		return "assigned"
	if cmd.priority > cur.priority:
		# Preempt; a preempted mission / finite panic resumes afterwards.
		if cur.is_mission() or (cur.finite and cur.priority >= SquadCommand.Priority.ORDER):
			a.enqueue(cur, true)
		elif cur.stance and cmd.finite:
			a.enqueue(cur, true)
		a.assign(cmd)
		return "assigned (preempted %s)" % cur.verb
	if cmd.priority == cur.priority:
		if cur.is_mission() or cur.finite:
			a.enqueue(cmd)
			return "queued (mission lock)" if cur.is_mission() else "queued"
		if cmd.finite:
			a.enqueue(cur, true)
		a.assign(cmd)
		return "assigned"
	# Lower priority than what's running.
	if cur.stance:
		# Stances (massacre / ceasefire / follow / hold) are replaced by explicit orders; finite orders resume them.
		if cmd.finite:
			a.enqueue(cur, true)
		a.assign(cmd)
		return "assigned"
	if cur.is_mission():
		a.enqueue(cmd)
		return "queued (mission lock)"
	a.enqueue(cmd)
	return "queued"


func _recipients(c: Dictionary) -> Array[SquadAlly]:
	var out: Array[SquadAlly] = []
	var raw: Variant = c.get("allies", [])
	var names: Array = []
	if raw is Array:
		names = raw as Array
	elif raw is String and not String(raw).is_empty():
		names = String(raw).split(",", false)
	for n in names:
		var s: String = String(n).strip_edges().to_lower()
		if s in ["all", "everyone", "squad", "team"]:
			out.clear()
			for a in allies:
				out.append(a)
			return out
		var a2: SquadAlly = find_ally(s)
		if a2 != null and not out.has(a2):
			out.append(a2)
	if not out.is_empty():
		return out
	# Defaults per verb.
	var verb: String = String(c.get("verb", ""))
	var role_pref: Dictionary = ROLE_FOR_VERB
	if role_pref.has(verb):
		var pick: SquadAlly = _pick_for(String(role_pref[verb][1]), String(role_pref[verb][0]), [], [])
		if pick != null:
			out.append(pick)
		return out
	if verb == "revive":
		var tgt: SquadAlly = find_ally(String(c.get("target", "")))
		var pos: Vector3 = tgt.global_position if tgt != null else (_player.global_position if _player != null else Vector3.ZERO)
		var best: SquadAlly = null
		var bd: float = INF
		for a in get_living():
			if a == tgt:
				continue
			var d: float = a.global_position.distance_to(pos)
			if a.profile.has_ability("revive"):
				d -= 3.0
			if d < bd:
				bd = d
				best = a
		if best != null:
			out.append(best)
		return out
	if verb in ["say", "status"]:
		var l: SquadAlly = _leader()
		if l != null and verb == "say":
			out.append(l)
			return out
	if verb in ["interact", "hunt"]:
		# One errand-runner: the living ally closest to the player.
		var best2: SquadAlly = null
		var bd2: float = INF
		for a in get_living():
			var d2: float = a.global_position.distance_to(_player.global_position) if _player != null else 0.0
			if d2 < bd2:
				bd2 = d2
				best2 = a
		if best2 != null:
			out.append(best2)
		return out
	for a in allies:
		out.append(a)
	return out


func _leader() -> SquadAlly:
	var living: Array[SquadAlly] = get_living()
	return living[0] if not living.is_empty() else (allies[0] if not allies.is_empty() else null)


## Best ally for an ability: prefers the given role, then anyone with the ability, then anyone free;
## skips downed allies, `exclude`, and allies locked in another mission when an alternative exists.
func _pick_for(ability: String, role: String, exclude: Array, addressed: Array) -> SquadAlly:
	var best: SquadAlly = null
	var bs: float = -INF
	for a in get_living():
		if exclude.has(a):
			continue
		var s: float = 0.0
		if addressed.has(a):
			s += 10.0
		if a.get_role() == role:
			s += 4.0
		if a.profile.has_ability(ability):
			s += 3.0
		if a.current != null and a.current.is_mission():
			s -= 5.0
		if a._retreating:
			s -= 2.0
		s += a.get_health_ratio()
		if s > bs:
			bs = s
			best = a
	return best


func _names(list: Array) -> Array[String]:
	var out: Array[String] = []
	for a in list:
		if a is SquadAlly:
			out.append((a as SquadAlly).get_display_name())
	return out


# ------------------------------------------------------------------ combos

## verb -> [preferred role, ability] for default recipients and role-based substitution.
const ROLE_FOR_VERB: Dictionary = {
	"bodyguard": ["vanguard", "bodyguard"], "kite": ["skirmisher", "kite"], "nuke": ["artillery", "nuke"],
	"taunt": ["vanguard", "taunt"], "peel": ["vanguard", "taunt"], "hit_and_run": ["skirmisher", "kite"],
	"destroy": ["vanguard", "charge"],
}

const COMBO_PARTS: Dictionary = {
	"combo_kite_nuke": [["kiter", "kite", "skirmisher"], ["nuker", "nuke", "artillery"]],
	"combo_charge_finish": [["charger", "charge", "vanguard"], ["finisher", "finisher", "skirmisher"]],
	"combo_lure_detonate": [["lurer", "lure", "skirmisher"], ["trapper", "mine", "artillery"]],
}
const COMBO_NAMES: Dictionary = {"combo_kite_nuke": "Kite + Nuke", "combo_charge_finish": "Charge + Finish", "combo_lure_detonate": "Lure + Detonate"}


func _start_combo(kind: String, args: Dictionary, addressed: Array[SquadAlly], source: String) -> String:
	var living: Array[SquadAlly] = get_living()
	if living.is_empty():
		return "no allies standing"
	var near: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	if resolve_enemy(String(args.get("target", "nearest")), near) == null:
		var l: SquadAlly = _leader()
		if l != null:
			l.say("Nothing to use that on.", "refuse", 1)
		return "no target"
	_combo_seq += 1
	var id: int = _combo_seq
	var spec: Array = COMBO_PARTS[kind]
	var rec: Dictionary = {"id": id, "kind": kind, "parts": {}, "t": 0.0, "args": args, "planted_t": -1.0, "source": source}
	var used: Array = []
	# Fill the scarcest half first (e.g. only one ally can nuke) so substitution never wastes a specialist.
	var ordered: Array = spec.duplicate()
	ordered.sort_custom(func(x: Array, y: Array) -> bool: return _scarcity(String(x[1])) < _scarcity(String(y[1])))
	for p in ordered:
		var part: String = String(p[0])
		var who: SquadAlly = _pick_for(String(p[1]), String(p[2]), used, addressed)
		if who != null:
			used.append(who)
			rec["parts"][part] = who
	var parts: Dictionary = rec["parts"]
	if parts.size() < 2:
		# Solo fallback: one ally does both halves.
		var solo: SquadAlly = parts.values()[0] as SquadAlly if not parts.is_empty() else living[0]
		parts.clear()
		parts["solo_" + kind.trim_prefix("combo_")] = solo
	_combos[id] = rec
	var assigned: PackedStringArray = []
	for part in parts.keys():
		var a: SquadAlly = parts[part] as SquadAlly
		var cmd: SquadCommand = SquadCommand.make(kind, args, source)
		cmd.combo_id = id
		cmd.combo_part = String(part)
		rec["cmd_" + String(part)] = cmd
		var r: String = _route(a, cmd)
		assigned.append("%s=%s (%s)" % [part, a.get_display_name(), r])
		if r.begins_with("queued"):
			a.say_event("mission_lock", 1)
	# Lure point: a spot just off the player's flank, away from the enemies.
	if kind == "combo_lure_detonate":
		rec["point"] = _lure_point()
	var nm: String = String(COMBO_NAMES.get(kind, kind))
	var txt: String = "%s: %s" % [nm, ", ".join(assigned)]
	if parts.size() == 1:
		var only: SquadAlly = parts.values()[0] as SquadAlly
		only.say("Just me for this one. I'll handle both halves.", "combo_go", 2)
		txt += " (solo fallback)"
	combo_progress.emit(kind, txt)
	return txt


## Parts nobody specialises in are filled last (anyone can stand in); otherwise rarest ability first.
func _scarcity(ability: String) -> int:
	var n: int = _capable_count(ability)
	return 99 if n == 0 else n


func _capable_count(ability: String) -> int:
	var n: int = 0
	for a in get_living():
		if a.profile.has_ability(ability):
			n += 1
	return n


func _lure_point() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var c := Vector3.ZERO
	var n: int = 0
	for e in _active_enemies_near(_player.global_position, 20.0):
		c += e.global_position
		n += 1
	var f: Vector3 = (_player.call("get_facing_direction") as Vector3)
	var toward: Vector3 = (c / float(n) - _player.global_position) if n > 0 else f
	toward.y = 0.0
	toward = toward.normalized() if toward.length_squared() > 0.01 else f
	var side := Vector3(-toward.z, 0.0, toward.x)
	return _player.global_position + toward * 2.0 + side * 2.5


## Handshake events posted by allies running a combo half.
func combo_event(id: int, ally: SquadAlly, part: String, event: String, data: Dictionary) -> void:
	if not _combos.has(id):
		return
	var rec: Dictionary = _combos[id]
	var kind: String = String(rec["kind"])
	var parts: Dictionary = rec["parts"]
	match event:
		"failed":
			_abort_combo(id, "%s couldn't start" % ally.get_display_name())
		"ready":
			if kind == "combo_kite_nuke" and parts.has("nuker"):
				var nk: SquadCommand = rec.get("cmd_nuker", null) as SquadCommand
				var nuker: SquadAlly = parts["nuker"] as SquadAlly
				# Posted even if the nuker is briefly busy (a skill / rally cut in): it fires when it resumes.
				if nk != null and not nk.done and is_instance_valid(nuker):
					nk.data["go_pos"] = data.get("center", ally.global_position)
					var kc: SquadCommand = rec.get("cmd_kiter", null) as SquadCommand
					if kc != null and kc.data.has("enemy"):
						nk.data["track"] = kc.data["enemy"]
					combo_progress.emit(kind, "%s: ready signal -> %s" % [ally.get_display_name(), nuker.get_display_name()])
		"casting":
			var kc2: SquadCommand = rec.get("cmd_kiter", null) as SquadCommand
			if kc2 != null:
				kc2.data["clear"] = true
			combo_progress.emit(kind, "%s channelling — kiter clearing out" % ally.get_display_name())
		"released":
			var kiter: SquadAlly = parts.get("kiter", null) as SquadAlly
			var kc3: SquadCommand = rec.get("cmd_kiter", null) as SquadCommand
			if kc3 != null:
				kc3.data["released"] = true
			if kiter != null and kc3 != null and kiter.current == kc3:
				kiter.finish_current("combo complete")
			combo_progress.emit(kind, "Nuke released!")
		"knocked":
			var fin: SquadCommand = rec.get("cmd_finisher", null) as SquadCommand
			if fin != null:
				fin.data["enemy"] = data.get("enemy", null)
				fin.data["go"] = true
			combo_progress.emit(kind, "%s knocked the target down — finisher go!" % ally.get_display_name())
		"finished":
			combo_progress.emit(kind, "Finisher landed!")
		"planted":
			rec["planted_t"] = float(rec["t"])
			rec["point"] = data.get("point", rec.get("point", ally.global_position))
			var lc: SquadCommand = rec.get("cmd_lurer", null) as SquadCommand
			if lc != null:
				lc.data["point"] = rec["point"]
			combo_progress.emit(kind, "Sigil planted — lurer go!")
		"detonated":
			var lc2: SquadCommand = rec.get("cmd_lurer", null) as SquadCommand
			if lc2 != null:
				lc2.data["done"] = true
			combo_progress.emit(kind, "Detonated! (%d hit)" % int(data.get("hits", 0)))


func _tick_combos(delta: float) -> void:
	for id in _combos.keys():
		var rec: Dictionary = _combos[id]
		rec["t"] = float(rec["t"]) + delta
		var parts: Dictionary = rec["parts"]
		var all_done: bool = true
		for part in parts.keys():
			var a: SquadAlly = parts[part] as SquadAlly
			var cmd: SquadCommand = rec.get("cmd_" + String(part), null) as SquadCommand
			if cmd == null or cmd.done:
				continue
			all_done = false
			if not is_instance_valid(a) or a.is_downed:
				_substitute(int(id), String(part))
				return
			# Self-preservation pauses the half; if it drags on, hand the half to someone healthier.
			var rkey: String = "retreat_" + String(part)
			rec[rkey] = (float(rec.get(rkey, 0.0)) + delta) if a._retreating else 0.0
			if float(rec[rkey]) > 4.0:
				rec[rkey] = 0.0
				_substitute(int(id), String(part))
				return
			if a.current != cmd and not a.queue.has(cmd):
				# Preempted by a panic order or cancelled: the combo yields.
				_abort_combo(int(id), "%s was pulled off the combo" % a.get_display_name())
				return
		if all_done:
			_combos.erase(id)
			combo_progress.emit(String(rec["kind"]), "%s complete." % String(COMBO_NAMES.get(rec["kind"], rec["kind"])))
			continue
		_combo_coordinate(rec)
		if float(rec["t"]) > 40.0:
			_abort_combo(int(id), "timed out")
			return


## Per-frame handshake plumbing (positions the waiting half, triggers detonations).
func _combo_coordinate(rec: Dictionary) -> void:
	var kind: String = String(rec["kind"])
	var parts: Dictionary = rec["parts"]
	if kind == "combo_kite_nuke" and parts.has("kiter") and parts.has("nuker"):
		var nk: SquadCommand = rec.get("cmd_nuker", null) as SquadCommand
		if nk != null:
			nk.data["watch"] = (parts["kiter"] as SquadAlly).global_position
	elif kind == "combo_charge_finish" and parts.has("charger") and parts.has("finisher"):
		var cc: SquadCommand = rec.get("cmd_charger", null) as SquadCommand
		var fc: SquadCommand = rec.get("cmd_finisher", null) as SquadCommand
		if cc != null and fc != null and cc.data.has("enemy") and not fc.data.has("enemy"):
			fc.data["enemy"] = cc.data["enemy"]
	elif kind == "combo_lure_detonate" and parts.has("trapper"):
		var tc: SquadCommand = rec.get("cmd_trapper", null) as SquadCommand
		if tc != null and not tc.data.has("point"):
			tc.data["point"] = rec.get("point", Vector3.ZERO)
		if float(rec["planted_t"]) >= 0.0 and tc != null and not tc.data.get("detonate", false):
			var trapper: SquadAlly = parts["trapper"] as SquadAlly
			var mp: Vector3 = trapper.get_mine_position()
			var lurer: SquadAlly = parts.get("lurer", null) as SquadAlly
			var trapped: int = 0
			if mp != Vector3.INF:
				for e in _active_enemies_near(mp, 3.2):
					if lurer == null or e.get_current_target() == lurer or e.is_aggroed():
						trapped += 1
			if trapped > 0 or float(rec["t"]) - float(rec["planted_t"]) > 15.0:
				tc.data["detonate"] = true
	# Solo lure: give the solo ally its sigil point.
	for part in parts.keys():
		if String(part) == "solo_lure_detonate":
			var sc: SquadCommand = rec.get("cmd_" + String(part), null) as SquadCommand
			if sc != null and not sc.data.has("point"):
				sc.data["point"] = rec.get("point", Vector3.ZERO)


## A combo participant went down: hand their half to a free ally, else collapse to a solo fallback.
func _substitute(id: int, part: String) -> void:
	var rec: Dictionary = _combos[id]
	var parts: Dictionary = rec["parts"]
	var gone: SquadAlly = parts[part] as SquadAlly
	var kind: String = String(rec["kind"])
	var used: Array = parts.values()
	var ability: String = "kite"
	var role: String = "skirmisher"
	for p in (COMBO_PARTS.get(kind, []) as Array):
		if String(p[0]) == part:
			ability = String(p[1])
			role = String(p[2])
	var sub: SquadAlly = _pick_for(ability, role, used, [])
	var old_cmd: SquadCommand = rec.get("cmd_" + part, null) as SquadCommand
	if old_cmd != null:
		old_cmd.done = true
	if sub != null and not part.begins_with("solo"):
		var cmd: SquadCommand = SquadCommand.make(kind, rec["args"] as Dictionary, String(rec["source"]))
		cmd.combo_id = id
		cmd.combo_part = part
		parts[part] = sub
		rec["cmd_" + part] = cmd
		_route(sub, cmd)
		if not gone.is_downed and gone.current != null and gone.current.combo_id == id:
			gone.finish_current("substituted")
		sub.say("%s is out — I'll take their part!" % gone.get_display_name(), "combo_go", 2)
		combo_progress.emit(kind, "Substitution: %s -> %s (%s)" % [gone.get_display_name(), sub.get_display_name(), part])
		return
	# Nobody free: survivor goes solo.
	parts.erase(part)
	rec.erase("cmd_" + part)
	if parts.size() == 1:
		var survivor_part: String = String(parts.keys()[0])
		var survivor: SquadAlly = parts[survivor_part] as SquadAlly
		var scmd: SquadCommand = rec.get("cmd_" + survivor_part, null) as SquadCommand
		if scmd != null:
			scmd.done = true
		var solo := SquadCommand.make(kind, rec["args"] as Dictionary, String(rec["source"]))
		solo.combo_id = id
		solo.combo_part = "solo_" + kind.trim_prefix("combo_")
		parts.clear()
		parts[solo.combo_part] = survivor
		rec["cmd_" + solo.combo_part] = solo
		if survivor.current == scmd:
			survivor.assign(solo)
		else:
			_route(survivor, solo)
		if not gone.is_downed and gone.current != null and gone.current.combo_id == id:
			gone.finish_current("substituted")
		survivor.say("%s is out. Doing this alone!" % gone.get_display_name(), "combo_go", 2)
		combo_progress.emit(kind, "Solo fallback: %s" % survivor.get_display_name())
	else:
		_abort_combo(id, "no one left to run it")


func _abort_combo(id: int, why: String) -> void:
	if not _combos.has(id):
		return
	var rec: Dictionary = _combos[id]
	_combos.erase(id)
	for part in (rec["parts"] as Dictionary).keys():
		var a: SquadAlly = rec["parts"][part] as SquadAlly
		var cmd: SquadCommand = rec.get("cmd_" + String(part), null) as SquadCommand
		if cmd == null or not is_instance_valid(a):
			continue
		cmd.done = true
		if a.current == cmd:
			a.finish_current("combo aborted")
		a.queue.erase(cmd)
	combo_progress.emit(String(rec["kind"]), "%s aborted: %s" % [String(COMBO_NAMES.get(rec["kind"], rec["kind"])), why])


func _cancel_combos_for(list: Array) -> void:
	for id in _combos.keys():
		var rec: Dictionary = _combos[id]
		for a in (rec["parts"] as Dictionary).values():
			if list.has(a):
				_abort_combo(int(id), "overridden")
				break


func get_active_combos() -> Array:
	var out: Array = []
	for rec in _combos.values():
		out.append({"kind": rec["kind"], "parts": _names((rec["parts"] as Dictionary).values())})
	return out


# ------------------------------------------------------------------ events

func on_ally_spoke(ally: SquadAlly, text: String, event: String, prio: int) -> void:
	ally_spoke.emit(ally.get_display_name(), text, event, prio, ally.profile.tts_voice)


func _on_ally_health(_a: SquadAlly, _hp: int, _max: int) -> void:
	_roster_dirty = true


func _on_ally_downed(a: SquadAlly) -> void:
	_roster_dirty = true
	_roster_timer = 0.0
	_log("event", a.get_display_name(), "downed", "needs revive")


func _on_ally_revived(a: SquadAlly) -> void:
	_roster_dirty = true
	_roster_timer = 0.0
	_log("event", a.get_display_name(), "revived", "back in the fight")


func _on_ally_command_finished(_a: SquadAlly, _cmd: SquadCommand, _result: String) -> void:
	_roster_dirty = true


## Public hook for allies to post a log line (phase failures etc.).
func log_event(who: String, what: String, result: String) -> void:
	_log("event", who, what, result)


func _log(source: String, who: String, what: String, result: String) -> void:
	command_logged.emit({"time": Time.get_ticks_msec(), "source": source, "who": who, "what": what, "result": result})
