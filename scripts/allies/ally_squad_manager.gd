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
	if spawn_allies:
		call_deferred("_spawn_squad")


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
	_tick_combos(delta)
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


## Teleport the squad to formation around the player (full heal on respawn / new run).
func regroup(full_heal: bool) -> void:
	for a in allies:
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
		})
	return out


## Plain-text roster for LLM system prompts (refreshed automatically on death / revive).
func get_roster_text() -> String:
	var lines: PackedStringArray = []
	for a in allies:
		var st: String = "DOWN (needs revive)" if a.is_downed else "%d%% HP, %s" % [int(a.get_health_ratio() * 100.0), a.get_state_text()]
		lines.append("- %s (%s; abilities: %s): %s" % [a.get_display_name(), a.get_role(), ", ".join(a.profile.abilities), st])
	return "\n".join(lines)


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
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree():
			continue
		if e.global_position.distance_to(pos) <= radius and absf(e.global_position.y - pos.y) < 5.0:
			out.append(e)
	return out


func resolve_enemy(selector: String, near: Vector3) -> EnemyAI:
	var sel: String = selector.strip_edges().to_lower()
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
	for c in cmds:
		if c is Dictionary:
			results.append(issue(c as Dictionary, source))
	return results


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
	var outcomes: PackedStringArray = []
	var first_spoken: bool = false
	for a in addressed:
		var res: String = _route(a, cmd.clone_for("") if addressed.size() > 1 else cmd)
		outcomes.append("%s %s" % [a.get_display_name(), res])
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


func _route(a: SquadAlly, cmd: SquadCommand) -> String:
	if a.is_downed and cmd.verb != "revive":
		return "is down"
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
	var role_pref: Dictionary = {"bodyguard": ["vanguard", "bodyguard"], "kite": ["skirmisher", "kite"], "nuke": ["artillery", "nuke"],
		"taunt": ["vanguard", "taunt"]}
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
	for p in spec:
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
				if nk != null and nuker.current == nk:
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
		sub.say("%s is down — I'll take their part!" % gone.get_display_name(), "combo_go", 2)
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
		survivor.say("%s is down. Doing this alone!" % gone.get_display_name(), "combo_go", 2)
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


func _log(source: String, who: String, what: String, result: String) -> void:
	command_logged.emit({"time": Time.get_ticks_msec(), "source": source, "who": who, "what": what, "result": result})
