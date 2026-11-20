class_name WorldIntel
extends Node
## The squad's shared knowledge base ("what is out there"). One instance lives under `AllySquadManager`.
## Every ally, the offline parser and the LLM Squad Director read the battlefield through it:
##  - stable short IDs per enemy (`E1`, `E2`...) shown as small overhead tags so the player can say "kill E3";
##  - a descriptor per enemy: type name, model ("hooded skeleton rogue"), size, colour, weapon(s), realm, HP,
##    state (stunned / fleeing / enraged...), who it is targeting, distance and bearing from the player;
##  - `resolve(selector)` turns an ID, a type word or a free-text description ("the purple caster on the left",
##    "the big guy with the axe near Sera", "whoever is hitting Ivo", "weakest") into an enemy;
##  - `describe_text()` is the battlefield table injected into the Director's prompt every request.

signal marks_changed(marked_entries: Array)

const REFRESH_SEC: float = 0.25
const RANGE_M: float = 40.0
const CAMERA_MAX_M: float = 140.0
const MARK_AIM_MAX_DIST: float = 180.0
const MARK_REGION_RADIUS: float = 18.0
const MARK_REGION_LINGER_SEC: float = 10.0
const MAX_MARKS: int = 4

## Classic enemy classes -> descriptor defaults (archetypes carry their own in EnemyArchetype).
const CLASS_LOOKS: Dictionary = {
	"skeleton": {"name": "Skeleton Guard", "color": "bone-white", "words": "skeleton bones undead"},
	"phantom": {"name": "Phantom Twin", "color": "glowing cyan, translucent", "words": "phantom ghost spectral twin mirror"},
	"shield": {"name": "Shielded Guard", "color": "steel and gold", "words": "shielded guard knight armored"},
	"warden": {"name": "The Warden", "color": "dark iron, glowing rune", "words": "warden boss giant"},
}
const PROP_WORDS: Dictionary = {
	"1H_Sword": "sword", "1H_Sword_Offhand": "second sword", "2H_Sword": "greatsword",
	"1H_Axe": "axe", "1H_Axe_Offhand": "second axe", "2H_Axe": "two-handed greataxe",
	"Badge_Shield": "crest shield", "Rectangle_Shield": "tower shield", "Round_Shield": "round shield",
	"Spike_Shield": "spiked shield", "Barbarian_Round_Shield": "round shield", "Mug": "mug",
}
const COLOR_WORDS: Array[String] = ["purple", "violet", "blue", "cyan", "green", "pale", "white", "bone", "gold", "golden",
	"steel", "silver", "red", "black", "dark", "iron", "glowing", "orange", "brown", "grey", "gray"]
const SIDE_WORDS: Dictionary = {"left": "left", "right": "right", "front": "ahead", "ahead": "ahead",
	"forward": "ahead", "behind": "behind", "back": "behind", "rear": "behind"}

var _ids: Dictionary = {}         # enemy instance_id -> "E#"
var _seq: int = 0
var _looks: Dictionary = {}       # instance_id -> descriptor dict (static part)
var _entries: Array[Dictionary] = []
var _timer: float = 0.0
var show_tags: bool = false
var _marks: Array[Dictionary] = []       # {"iid": int, "ref": WeakRef, "num": int, "marked_ms": int, "last_pos": Vector3}
var _mark_zones: Array[Dictionary] = []  # {"pos": Vector3, "expires_ms": int, "mark_num": int}
var mark_region_radius: float = MARK_REGION_RADIUS


func _ready() -> void:
	add_to_group("world_intel")


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_SEC
		refresh()


func get_entries() -> Array[Dictionary]:
	return _entries


func id_of(e: Node) -> String:
	if e == null:
		return ""
	var iid: int = e.get_instance_id()
	if not _ids.has(iid):
		_seq += 1
		_ids[iid] = "E%d" % _seq
	return String(_ids[iid])


func node_for_id(id: String) -> EnemyAI:
	var want: String = id.strip_edges().to_upper()
	for iid in _ids.keys():
		if String(_ids[iid]) == want:
			var o: Object = instance_from_id(int(iid))
			if is_instance_valid(o) and o is EnemyAI:
				var e: EnemyAI = o as EnemyAI
				if not e.is_dead and e.is_active and e.is_inside_tree():
					return e
	return null


# ------------------------------------------------------------------ scan

func is_camera_visible(e: EnemyAI) -> bool:
	if e == null or not is_instance_valid(e) or e.is_dead or not e.is_active or not e.is_inside_tree() or not e.is_hittable_now():
		return false
	if not is_inside_tree() or get_viewport() == null:
		return false
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(cam):
		return false
	if cam.global_position.distance_to(e.global_position) > CAMERA_MAX_M:
		return false
	return cam.is_position_in_frustum(e.global_position + Vector3.UP * 1.0) or cam.is_position_in_frustum(e.global_position)


func refresh() -> void:
	_entries.clear()
	prune_marks()
	if not is_inside_tree() or get_tree() == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	var pf: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or not (n is EnemyAI):
			if is_instance_valid(n):
				_hide_tag(n)
				_hide_mark_pins(n)
			continue
		var e: EnemyAI = n as EnemyAI
		if e.is_dead or not e.is_inside_tree() or not e.is_active:
			_hide_tag(e)
			_hide_mark_pins(e)
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		var m_num: int = mark_number_of(e)
		var is_m: bool = m_num > 0
		var near_num: int = 0 if is_m else _region_match_for_pos(e.global_position)
		var in_region: bool = near_num > 0
		if not e.is_hittable_now():
			_hide_tag(e)
			if is_m:
				_update_mark_pins(e, true, m_num, false, d)
			else:
				_hide_mark_pins(e)
			continue
		var cam_vis: bool = is_camera_visible(e)
		if d > RANGE_M and not cam_vis and not is_m and not in_region:
			_hide_tag(e)
			_hide_mark_pins(e)
			continue
		var entry: Dictionary = _describe(e, player, pf, d, m_num, near_num)
		_entries.append(entry)
		_update_tag(e, entry)
		_update_mark_pins(e, is_m, m_num, in_region, d)
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))


func _describe(e: EnemyAI, player: Node3D, pf: Vector3, d: float, mark_num: int = 0, near_mark_num: int = 0) -> Dictionary:
	var look: Dictionary = _look_of(e)
	var rel: Vector3 = e.global_position - player.global_position
	rel.y = 0.0
	var bearing: String = "here"
	if rel.length() > 0.8:
		var fwd: float = pf.dot(rel.normalized())
		var right: float = Vector3(-pf.z, 0.0, pf.x).dot(rel.normalized())
		var fb: String = "ahead" if fwd > 0.38 else ("behind" if fwd < -0.38 else "")
		var lr: String = "right" if right > 0.38 else ("left" if right < -0.38 else "")
		bearing = (fb + ("-" if not fb.is_empty() and not lr.is_empty() else "") + lr) if not (fb + lr).is_empty() else "ahead"
	var tgt: Node3D = e.get_current_target()
	var tname: String = "nobody"
	if tgt is PlayerController:
		tname = "player"
	elif tgt != null and tgt.has_method("get_display_name"):
		tname = String(tgt.call("get_display_name"))
	var state: String = ""
	match e.current_state:
		EnemyAI.State.STUNNED:
			state = "stunned"
		EnemyAI.State.FLEEING:
			state = "fleeing"
		EnemyAI.State.WINDUP:
			state = "winding up an attack"
		EnemyAI.State.ALERT:
			state = "searching"
		EnemyAI.State.RETURNING:
			state = "returning home"
		EnemyAI.State.IDLE:
			state = "unaware"
	if e.is_enraged():
		state = (state + ", " if not state.is_empty() else "") + "enraged"
	if e.is_taunted():
		state = (state + ", " if not state.is_empty() else "") + "taunted"
	return {
		"id": id_of(e), "node": e, "kind": look["kind"], "name": look["name"], "model": look["model"],
		"size": look["size"], "color": look["color"], "weapon": look["weapon"], "ranged": look["ranged"],
		"realm": look["realm"], "hp": e.health, "max_hp": e.max_health,
		"hp_pct": int(round(100.0 * float(e.health) / float(maxi(1, e.max_health)))),
		"dist": d, "bearing": bearing, "targeting": tname, "state": state,
		"words": String(look["words"]), "pos": e.global_position,
		"marked": mark_num > 0, "mark_num": mark_num,
		"in_mark_region": near_mark_num > 0, "near_mark_num": near_mark_num,
	}


## Static appearance, computed once per enemy from its class / archetype and the props on its rig.
func _look_of(e: EnemyAI) -> Dictionary:
	var iid: int = e.get_instance_id()
	if _looks.has(iid):
		return _looks[iid]
	var kind: String = "skeleton"
	var name_s: String = String(e.name)
	var color: String = ""
	var extra_words: String = ""
	var ranged: bool = false
	if e is ArchetypeEnemy and (e as ArchetypeEnemy).archetype != null:
		var a: EnemyArchetype = (e as ArchetypeEnemy).archetype
		kind = a.id
		name_s = a.display_name
		color = a.color_name
		extra_words = a.look_words
		ranged = a.attack_kind == "bolt"
	else:
		if e is WardenBoss:
			kind = "warden"
		elif e is ShieldedGuard:
			kind = "shield"
		elif e is PhantomTwin:
			kind = "phantom"
		var cl: Dictionary = CLASS_LOOKS.get(kind, {}) as Dictionary
		name_s = String(cl.get("name", name_s))
		color = String(cl.get("color", ""))
		extra_words = String(cl.get("words", ""))
	var model: Node = e.get_node_or_null(NodePath(String(e.visual_root_path) + "/ModelRoot"))
	var model_s: String = "skeleton warrior"
	var scale_f: float = 1.0
	var weapons: PackedStringArray = []
	if model != null:
		if model.find_child("Knight_Body", true, false) != null:
			model_s = "armored knight"
		elif model.find_child("Barbarian_Body", true, false) != null:
			model_s = "barbarian"
		elif model.find_child("Skeleton_Rogue_Body", true, false) != null:
			model_s = "hooded skeleton rogue"
		if model is Node3D:
			scale_f = (model as Node3D).scale.y
		for prop in PROP_WORDS.keys():
			for found in model.find_children(String(prop), "", true, false):
				if found is Node3D and (found as Node3D).is_visible_in_tree():
					var w: String = String(PROP_WORDS[prop])
					if not weapons.has(w):
						weapons.append(w)
					break
	if weapons.is_empty():
		weapons.append("bare hands" + (" and a glowing orb" if ranged else ""))
	var size: String = "huge" if scale_f > 1.3 else ("big" if scale_f > 1.08 else ("small" if scale_f < 0.9 else "normal"))
	var realm: String = "both realms"
	match e.realm_affinity:
		RealmReactive.Affinity.REALITY_ONLY:
			realm = "Reality only"
		RealmReactive.Affinity.MIRROR_ONLY:
			realm = "Mirror only"
	var look: Dictionary = {
		"kind": kind, "name": name_s, "model": model_s, "size": size, "color": color,
		"weapon": " and ".join(weapons), "ranged": ranged, "realm": realm,
		"words": ("%s %s %s %s %s %s %s" % [kind, name_s, model_s, size, color, " ".join(weapons), extra_words]).to_lower(),
	}
	# Rig props are dressed one frame after spawn: don't cache an empty weapon list too early.
	if model != null and not weapons[0].begins_with("bare"):
		_looks[iid] = look
	elif model != null and e.get_meta("look_checks", 0) > 8:
		_looks[iid] = look
	else:
		e.set_meta("look_checks", int(e.get_meta("look_checks", 0)) + 1)
	return look


# ------------------------------------------------------------------ text

func entry_line(en: Dictionary) -> String:
	var tag_prefix: String = ""
	if bool(en.get("marked", false)):
		tag_prefix = "[MARKED M%d] " % int(en.get("mark_num", 1))
	elif bool(en.get("in_mark_region", false)):
		tag_prefix = "[NEAR M%d] " % int(en.get("near_mark_num", 1))
	var s: String = "%s%s %s — %s %s%s, %s | %d%% HP | %.0fm %s | %s | targeting %s" % [
		tag_prefix, en["id"], en["name"], ("" if en["size"] == "normal" else String(en["size"]) + " "), en["color"],
		(" " + String(en["model"])) if not String(en["model"]).is_empty() else "", en["weapon"],
		int(en["hp_pct"]), float(en["dist"]), en["bearing"], en["realm"], en["targeting"]]
	if bool(en["ranged"]):
		s += " | ranged"
	if not String(en["state"]).is_empty():
		s += " | " + String(en["state"])
	return s


## Battlefield table for the Director prompt (marked targets & region neighbors first, then nearest).
func describe_text(max_rows: int = 18) -> String:
	if _entries.is_empty():
		return "No enemies within %dm or marked." % int(RANGE_M)
	var ordered: Array[Dictionary] = []
	for en in _entries:
		if bool(en.get("marked", false)):
			ordered.append(en)
	for en in _entries:
		if not bool(en.get("marked", false)) and bool(en.get("in_mark_region", false)):
			ordered.append(en)
	for en in _entries:
		if not bool(en.get("marked", false)) and not bool(en.get("in_mark_region", false)):
			ordered.append(en)
	var rows: PackedStringArray = []
	for i in range(mini(max_rows, ordered.size())):
		rows.append("- " + entry_line(ordered[i]))
	if ordered.size() > max_rows:
		rows.append("- (+%d more farther away)" % (ordered.size() - max_rows))
	return "\n".join(rows)


func describe_marks_text() -> String:
	prune_marks()
	var summaries: Array[Dictionary] = get_marked_summaries()
	if summaries.is_empty() and _mark_zones.is_empty():
		return "- none"
	var lines: PackedStringArray = []
	for sm in summaries:
		var m_num: int = int(sm.get("num", 1))
		var e: EnemyAI = sm.get("node", null) as EnemyAI
		var eid: String = id_of(e) if e != null else "?"
		var nearby_n: int = 0
		for en in _entries:
			if bool(en.get("in_mark_region", false)) and int(en.get("near_mark_num", 0)) == m_num:
				nearby_n += 1
		var realm_note: String = " (Mirror-only/unhittable right now)" if not bool(sm.get("hittable", true)) else ""
		lines.append("- M%d (%s): %s, %.0fm away, %d nearby in %dm region%s" % [
			m_num, eid, String(sm.get("name", "Enemy")), float(sm.get("dist", 0.0)), nearby_n, int(mark_region_radius), realm_note])
	for z in _mark_zones:
		var m_num2: int = int((z as Dictionary).get("mark_num", 1))
		var rem_s: int = maxi(1, int(ceil(float(int((z as Dictionary).get("expires_ms", 0)) - Time.get_ticks_msec()) / 1000.0)))
		var nearby_z: int = 0
		for en2 in _entries:
			if bool(en2.get("in_mark_region", false)) and int(en2.get("near_mark_num", 0)) == m_num2:
				nearby_z += 1
		lines.append("- M%d linger zone (%ds left): %d enemy(ies) inside %dm region" % [
			m_num2, rem_s, nearby_z, int(mark_region_radius)])
	return "\n".join(lines)


# ------------------------------------------------------------------ resolve

## Resolves an enemy from: "E3" | type word | "ally:<Name>" (handled by the manager) | free description |
## superlatives (nearest / farthest / strongest / weakest / biggest). `asker` biases "nearest" toward that ally.
func resolve(selector: String, asker: Node3D = null) -> EnemyAI:
	if _entries.is_empty():
		refresh()
	if _entries.is_empty():
		return null
	var s_raw: String = selector.to_lower().strip_edges()
	var s: String = " " + s_raw.trim_prefix("desc:") + " "
	var wants_region: bool = s.contains(" group") or s.contains(" area") or s.contains(" region") or s.contains(" pack") or s.contains(" cluster") or s.contains(" around ") or s.contains(" near ") or s.contains(" next to ") or s.contains(" beside ") or s.contains(" by ") or s_raw in ["marked_group", "marked_area", "marked_region"]
	var rx_mark := RegEx.new()
	rx_mark.compile("\\b(?:m|mark)\\s*#?\\s*([1-4])\\b")
	var mm: RegExMatch = rx_mark.search(s)
	if mm != null and not wants_region:
		return node_for_mark(int(mm.get_string(1)), true)
	# Explicit ID anywhere in the text ("E3", "e 3", "enemy 3").
	var rx := RegEx.new()
	rx.compile("\\b(?:e|enemy|target)\\s*#?\\s*(\\d+)\\b")
	var m: RegExMatch = rx.search(s)
	if m != null:
		var byid: EnemyAI = node_for_id("E" + m.get_string(1))
		if byid != null and byid.is_hittable_now():
			return byid
		if byid != null:
			return null
	if (s_raw.is_empty() or s_raw == "marked_or_nearest"):
		var pm_def: EnemyAI = get_primary_marked(true)
		if pm_def != null:
			return pm_def
	if (s_raw in ["marked", "mark", "tagged", "pinged", "the mark"]) and not wants_region:
		return get_primary_marked(true)
	var mark_ref_pos: Vector3 = Vector3.INF
	var mark_ref_slot: int = 0
	if mm != null and wants_region:
		mark_ref_slot = int(mm.get_string(1))
		mark_ref_pos = _position_for_mark_slot(mark_ref_slot)
		if mark_ref_pos == Vector3.INF:
			return null
	elif wants_region and (s.contains(" marked") or s.contains(" the mark ") or s.contains(" tagged") or s.contains(" pinged") or s_raw in ["marked_group", "marked_area", "marked_region"]):
		mark_ref_pos = _position_for_primary_mark_or_zone()
		if mark_ref_pos == Vector3.INF:
			return null
	var tokens: PackedStringArray = s.replace(",", " ").replace(".", " ").replace("'s", " ").split(" ", false)
	var origin: Vector3 = Vector3.ZERO
	if asker != null and is_instance_valid(asker):
		origin = asker.global_position
	elif is_inside_tree() and get_tree() != null:
		var player_node: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		if player_node != null and is_instance_valid(player_node):
			origin = player_node.global_position
	# "near Sera" / "closest to Brannoc" / "attacking Ivo" / "on me" / "hitting me".
	var ref_node: Node3D = null
	var ref_mode: String = ""
	var mgr: Node = get_parent()
	for i in range(tokens.size()):
		var t: String = tokens[i]
		var nxt: String = tokens[i + 1] if i + 1 < tokens.size() else ""
		if t in ["near", "next", "closest", "nearest", "by", "beside"] or (t == "to" and i > 0 and tokens[i - 1] in ["closest", "nearest", "next"]):
			var who: Node3D = _named_entity(nxt, mgr)
			if who != null:
				ref_node = who
				ref_mode = "near"
		if t in ["attacking", "hitting", "on", "chasing", "targeting", "hunting", "fighting"]:
			var who2: Node3D = _named_entity(nxt, mgr)
			if who2 != null:
				ref_node = who2
				ref_mode = "targeting"
	var strict_nearest: bool = s_raw == "nearest" or s_raw == "closest"
	var has_other_desc: bool = false
	for t0 in tokens:
		if t0 in COLOR_WORDS or t0 in ["axe", "sword", "shield", "orb", "blades", "caster", "mage", "brute", "rogue", "knight", "barbarian", "skeleton", "phantom", "ghost", "stalker", "hexcaster", "warden", "big", "huge", "small", "giant", "archer", "ranged", "glowing", "hooded", "armored", "greataxe", "twin", "stunned", "fleeing", "enraged", "wounded", "hurt", "dying"] or SIDE_WORDS.has(t0):
			has_other_desc = true
			break
	if not wants_region and not has_other_desc and ref_node == null and (s.contains(" marked") or s.contains(" tagged") or s.contains(" pinged") or s.contains(" the mark ")):
		return get_primary_marked(true)
	var best: EnemyAI = null
	var best_score: float = -INF
	var best_match_score: float = 0.0
	var any_desc: bool = false
	for en in _entries:
		var raw_node: Variant = en.get("node")
		if not is_instance_valid(raw_node) or not (raw_node is EnemyAI):
			continue
		var en_node: EnemyAI = raw_node as EnemyAI
		if en_node.is_dead or not en_node.is_active or not en_node.is_inside_tree() or not en_node.is_hittable_now():
			continue
		if mark_ref_pos != Vector3.INF:
			if en_node.global_position.distance_to(mark_ref_pos) > mark_region_radius + 0.5 or absf(en_node.global_position.y - mark_ref_pos.y) > 10.0:
				continue
		var match_score: float = 0.0
		var words: String = String(en["words"])
		for t in tokens:
			if t.length() < 3 or t in ["the", "one", "guy", "that", "this", "with", "and", "who", "kill", "attack", "him", "her", "them", "enemy", "please", "now", "get", "go", "hit", "marked", "mark", "tagged", "pinged", "group", "area", "region", "pack", "cluster", "around"]:
				continue
			if t in COLOR_WORDS or t in ["axe", "sword", "shield", "orb", "blades", "caster", "mage", "brute", "rogue", "knight", "barbarian", "skeleton", "phantom", "ghost", "stalker", "hexcaster", "warden", "big", "huge", "small", "giant", "archer", "ranged", "glowing", "hooded", "armored", "greataxe", "twin"]:
				any_desc = true
				if words.contains(t):
					match_score += 3.0
				elif t in ["caster", "mage", "archer", "ranged"] and bool(en["ranged"]):
					match_score += 3.0
				elif t in ["big", "huge", "giant"] and String(en["size"]) in ["big", "huge"]:
					match_score += 2.0
				elif t in ["blades"] and String(en["weapon"]).contains("sword"):
					match_score += 2.0
				else:
					match_score -= 1.5
			if SIDE_WORDS.has(t):
				any_desc = true
				match_score += 2.0 if String(en["bearing"]).contains(String(SIDE_WORDS[t])) else -1.0
			if t in ["stunned", "fleeing", "enraged", "wounded", "hurt", "dying"]:
				any_desc = true
				if t in ["wounded", "hurt", "dying"]:
					match_score += (100.0 - float(en["hp_pct"])) / 40.0
				elif String(en["state"]).contains(t):
					match_score += 3.0
		if ref_node != null and is_instance_valid(ref_node):
			any_desc = true
			if ref_mode == "targeting":
				var tn: String = String(en["targeting"]).to_lower()
				var rn: String = "player" if ref_node is PlayerController else String(ref_node.call("get_display_name")).to_lower()
				match_score += 4.0 if tn == rn else -2.0
			else:
				match_score -= en_node.global_position.distance_to(ref_node.global_position) * 0.25
		if mark_ref_pos != Vector3.INF:
			any_desc = true
			match_score += 2.0 if bool(en.get("in_mark_region", false)) or bool(en.get("marked", false)) else 1.0
			match_score -= en_node.global_position.distance_to(mark_ref_pos) * 0.04
		var score: float = match_score
		# Superlatives / default ordering.
		var d: float = en_node.global_position.distance_to(origin)
		if s.contains("farthest") or s.contains("furthest") or s.contains("farther") or s.contains("further") or s.contains("distant"):
			score += d * 0.05
		elif s.contains("strongest") or s.contains("toughest") or s.contains("biggest"):
			score += float(en["hp"]) * 0.01
		elif s.contains("weakest") or s.contains("lowest"):
			score += (100.0 - float(en["hp_pct"])) * 0.03
		elif mark_ref_pos == Vector3.INF:
			if strict_nearest or not any_desc:
				score -= d * 0.05
			else:
				score -= clampf(d * 0.015, 0.0, 2.0)
		if not strict_nearest and bool(en.get("in_mark_region", false)) and mark_ref_pos == Vector3.INF and not any_desc:
			score += 3.0
		if en_node.is_aggroed():
			score += 0.3
		if score > best_score:
			best_score = score
			best_match_score = match_score
			best = en_node
	# A description that matches nothing at all should not silently pick a random enemy far away.
	if any_desc and best_match_score < 0.5 and ref_node == null and mark_ref_pos == Vector3.INF:
		return null
	return best


## True when the text plausibly describes an enemy (used by the offline parser for verb-less orders).
func mentions_enemy(text: String) -> bool:
	var s: String = " " + text.to_lower() + " "
	var rx := RegEx.new()
	rx.compile("\\b(?:e|enemy)\\s*#?\\s*\\d+\\b")
	if rx.search(s) != null:
		return true
	for en in _entries:
		for w in String(en["words"]).split(" ", false):
			if w.length() >= 4 and s.contains(" " + w):
				return true
	return false


func _named_entity(word: String, mgr: Node) -> Node3D:
	var w: String = word.to_lower()
	if w in ["me", "player", "you", "us"]:
		return get_tree().get_first_node_in_group("player") as Node3D
	if mgr != null and mgr.has_method("find_ally") and w.length() >= 3:
		return mgr.call("find_ally", w) as Node3D
	return null


# ------------------------------------------------------------------ aiming & tactical marks

func prune_marks() -> void:
	var now_ms: int = Time.get_ticks_msec()
	var changed: bool = false
	for i in range(_mark_zones.size() - 1, -1, -1):
		if now_ms > int((_mark_zones[i] as Dictionary).get("expires_ms", 0)):
			_mark_zones.remove_at(i)
			changed = true
	for i in range(_marks.size() - 1, -1, -1):
		var rec: Dictionary = _marks[i]
		var obj: Object = (rec["ref"] as WeakRef).get_ref()
		if obj == null or not is_instance_valid(obj) or not (obj is EnemyAI):
			_marks.remove_at(i)
			changed = true
			continue
		var e: EnemyAI = obj as EnemyAI
		if e.is_dead:
			_mark_zones.append({
				"pos": e.global_position,
				"expires_ms": now_ms + int(MARK_REGION_LINGER_SEC * 1000.0),
				"mark_num": int(rec["num"]),
			})
			_hide_mark_pins(e)
			_marks.remove_at(i)
			changed = true
		elif not e.is_inside_tree() or not e.is_active:
			_hide_mark_pins(e)
			_marks.remove_at(i)
			changed = true
		else:
			rec["last_pos"] = e.global_position
	if changed:
		marks_changed.emit(get_marked_summaries())


func _next_mark_slot() -> int:
	var used: Dictionary = {}
	for rec in _marks:
		used[int((rec as Dictionary)["num"])] = true
	for n in range(1, MAX_MARKS + 1):
		if not used.has(n):
			return n
	return 1


func has_marks() -> bool:
	prune_marks()
	return not _marks.is_empty()


func has_mark_zones() -> bool:
	prune_marks()
	return not _mark_zones.is_empty()


func has_hittable_mark() -> bool:
	return get_primary_marked(true) != null


func mark_number_of(e: Node) -> int:
	if e == null or not is_instance_valid(e):
		return 0
	var iid: int = e.get_instance_id()
	for rec in _marks:
		var d: Dictionary = rec as Dictionary
		if int(d["iid"]) == iid:
			var obj: Object = (d["ref"] as WeakRef).get_ref()
			if obj == e:
				return int(d["num"])
	return 0


func is_marked(e: Node) -> bool:
	return mark_number_of(e) > 0


func is_in_mark_region(e: Node) -> bool:
	if e == null or not is_instance_valid(e) or not (e is Node3D):
		return false
	if is_marked(e):
		return false
	return _region_match_for_pos((e as Node3D).global_position) > 0


func is_marked_or_in_region(e: Node) -> bool:
	return is_marked(e) or is_in_mark_region(e)


func node_for_mark(num: int, require_hittable: bool = true) -> EnemyAI:
	prune_marks()
	for rec in _marks:
		var d: Dictionary = rec as Dictionary
		if int(d["num"]) == num:
			var obj: Object = (d["ref"] as WeakRef).get_ref()
			if is_instance_valid(obj) and obj is EnemyAI:
				var e: EnemyAI = obj as EnemyAI
				if not e.is_dead and e.is_active and e.is_inside_tree() and (not require_hittable or e.is_hittable_now()):
					return e
	return null


func get_primary_marked(require_hittable: bool = true) -> EnemyAI:
	prune_marks()
	for rec in _marks:
		var obj: Object = ((rec as Dictionary)["ref"] as WeakRef).get_ref()
		if is_instance_valid(obj) and obj is EnemyAI:
			var e: EnemyAI = obj as EnemyAI
			if not e.is_dead and e.is_active and e.is_inside_tree() and (not require_hittable or e.is_hittable_now()):
				return e
	return null


func get_marked_enemies(require_hittable: bool = true) -> Array[EnemyAI]:
	prune_marks()
	var out: Array[EnemyAI] = []
	for rec in _marks:
		var obj: Object = ((rec as Dictionary)["ref"] as WeakRef).get_ref()
		if is_instance_valid(obj) and obj is EnemyAI:
			var e: EnemyAI = obj as EnemyAI
			if not e.is_dead and e.is_active and e.is_inside_tree() and (not require_hittable or e.is_hittable_now()):
				out.append(e)
	return out


func get_marked_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if (is_inside_tree() and get_tree() != null) else null
	for rec in _marks:
		var d: Dictionary = rec as Dictionary
		var obj: Object = (d["ref"] as WeakRef).get_ref()
		if not is_instance_valid(obj) or not (obj is EnemyAI):
			continue
		var e: EnemyAI = obj as EnemyAI
		var dist: float = e.global_position.distance_to(player.global_position) if player != null else 0.0
		out.append({
			"num": int(d["num"]),
			"id": id_of(e),
			"name": String(_look_of(e).get("name", e.name)),
			"dist": dist,
			"hittable": e.is_hittable_now(),
			"node": e,
		})
	return out


func _position_for_mark_slot(slot: int) -> Vector3:
	for rec in _marks:
		var d: Dictionary = rec as Dictionary
		if int(d["num"]) == slot:
			var obj: Object = (d["ref"] as WeakRef).get_ref()
			if is_instance_valid(obj) and obj is EnemyAI and not (obj as EnemyAI).is_dead:
				return (obj as EnemyAI).global_position
	for z in _mark_zones:
		var zd: Dictionary = z as Dictionary
		if int(zd["mark_num"]) == slot:
			return zd["pos"] as Vector3
	return Vector3.INF


func _position_for_primary_mark_or_zone() -> Vector3:
	var pm: EnemyAI = get_primary_marked(false)
	if pm != null:
		return pm.global_position
	if not _mark_zones.is_empty():
		return (_mark_zones[-1] as Dictionary)["pos"] as Vector3
	return Vector3.INF


func _region_match_for_pos(pos: Vector3) -> int:
	var now_ms: int = Time.get_ticks_msec()
	for rec in _marks:
		var obj: Object = ((rec as Dictionary)["ref"] as WeakRef).get_ref()
		if not is_instance_valid(obj) or not (obj is EnemyAI):
			continue
		var me: EnemyAI = obj as EnemyAI
		if me.is_dead or not me.is_active or not me.is_inside_tree():
			continue
		if pos.distance_to(me.global_position) <= mark_region_radius and absf(pos.y - me.global_position.y) <= 10.0:
			return int((rec as Dictionary)["num"])
	for z in _mark_zones:
		var zd: Dictionary = z as Dictionary
		if now_ms <= int(zd.get("expires_ms", 0)):
			var zp: Vector3 = zd["pos"] as Vector3
			if pos.distance_to(zp) <= mark_region_radius and absf(pos.y - zp.y) <= 10.0:
				return int(zd.get("mark_num", 1))
	return 0


func mark_enemy(e: EnemyAI) -> int:
	if e == null or not is_instance_valid(e) or e.is_dead or not e.is_active or not e.is_inside_tree():
		return 0
	prune_marks()
	var existing: int = mark_number_of(e)
	if existing > 0:
		return existing
	while _marks.size() >= MAX_MARKS:
		var evicted: Dictionary = _marks.pop_front()
		var old_obj: Object = (evicted["ref"] as WeakRef).get_ref()
		if is_instance_valid(old_obj) and old_obj is Node:
			_hide_mark_pins(old_obj as Node)
	var num: int = _next_mark_slot()
	_marks.append({
		"iid": e.get_instance_id(),
		"ref": weakref(e),
		"num": num,
		"marked_ms": Time.get_ticks_msec(),
		"last_pos": e.global_position,
	})
	refresh()
	marks_changed.emit(get_marked_summaries())
	return num


func unmark_enemy(e: EnemyAI) -> bool:
	if e == null:
		return false
	var iid: int = e.get_instance_id()
	var removed: bool = false
	for i in range(_marks.size() - 1, -1, -1):
		if int((_marks[i] as Dictionary)["iid"]) == iid:
			_marks.remove_at(i)
			removed = true
	if is_instance_valid(e):
		_hide_mark_pins(e)
	if removed:
		refresh()
		marks_changed.emit(get_marked_summaries())
	return removed


func clear_marks() -> void:
	for rec in _marks:
		var obj: Object = ((rec as Dictionary)["ref"] as WeakRef).get_ref()
		if is_instance_valid(obj) and obj is Node:
			_hide_mark_pins(obj as Node)
	_marks.clear()
	_mark_zones.clear()
	refresh()
	marks_changed.emit(get_marked_summaries())


func peek_aim_candidate(max_dist: float = MARK_AIM_MAX_DIST) -> EnemyAI:
	return _pick_aim_candidate(max_dist)


func mark_enemy_at_aim(max_dist: float = MARK_AIM_MAX_DIST) -> Dictionary:
	var target: EnemyAI = _pick_aim_candidate(max_dist)
	if target == null:
		return {"action": "none", "enemy": null, "mark_num": 0, "nearby_count": 0}
	var ename: String = String(_look_of(target).get("name", target.name))
	if is_marked(target):
		unmark_enemy(target)
		return {"action": "unmarked", "enemy": target, "name": ename, "mark_num": 0, "nearby_count": 0}
	var num: int = mark_enemy(target)
	var nearby_cnt: int = 0
	for en in _entries:
		if bool(en.get("in_mark_region", false)) and int(en.get("near_mark_num", 0)) == num:
			nearby_cnt += 1
	return {"action": "marked", "enemy": target, "name": ename, "mark_num": num, "nearby_count": nearby_cnt}


func _pick_aim_candidate(max_dist: float = MARK_AIM_MAX_DIST) -> EnemyAI:
	if not is_inside_tree() or get_tree() == null or get_viewport() == null:
		return null
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(cam):
		return null
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var has_vp: bool = vp_size.x > 1.0 and vp_size.y > 1.0
	var center: Vector2 = vp_size * 0.5
	var px_tol: float = maxf(64.0, minf(vp_size.x, vp_size.y) * 0.14) if has_vp else 0.0
	var cos_tol: float = cos(deg_to_rad(9.5))
	var cam_pos: Vector3 = cam.global_position
	var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized()
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state if cam.get_world_3d() != null else null
	var base_excl: Array[RID] = []
	for p_n in get_tree().get_nodes_in_group("player"):
		if p_n is CollisionObject3D:
			base_excl.append((p_n as CollisionObject3D).get_rid())
	for a_n in get_tree().get_nodes_in_group("squad_ally"):
		if a_n is CollisionObject3D:
			base_excl.append((a_n as CollisionObject3D).get_rid())
	var best: EnemyAI = null
	var best_err: float = INF
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or not (n is EnemyAI):
			continue
		var e: EnemyAI = n as EnemyAI
		if e.is_dead or not e.is_active or not e.is_inside_tree():
			continue
		var dist: float = cam_pos.distance_to(e.global_position)
		if dist > max_dist:
			continue
		var best_pt_err: float = INF
		var any_front: bool = false
		for h_off in [1.2, 1.7, 0.7]:
			var pt: Vector3 = e.global_position + Vector3.UP * float(h_off)
			if cam.is_position_behind(pt):
				continue
			var dir_to: Vector3 = (pt - cam_pos).normalized()
			var ang_cos: float = cam_fwd.dot(dir_to)
			var px_err: float = cam.unproject_position(pt).distance_to(center) if has_vp else 0.0
			var inside_cone: bool = (has_vp and px_err <= px_tol) or ang_cos >= cos_tol
			if not inside_cone:
				continue
			any_front = true
			var err: float = (px_err / px_tol) if has_vp else ((1.0 - ang_cos) * 20.0)
			if err < best_pt_err:
				best_pt_err = err
		if not any_front:
			continue
		if space != null and not _has_mark_los(space, cam_pos, e, base_excl):
			continue
		var total_err: float = best_pt_err + dist * 0.002
		if total_err < best_err:
			best_err = total_err
			best = e
	return best


func _has_mark_los(space: PhysicsDirectSpaceState3D, from_pos: Vector3, enemy: EnemyAI, base_excl: Array[RID]) -> bool:
	var world_mask: int = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY
	if RealmManager.instance != null:
		if RealmManager.instance.is_merged:
			world_mask = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR
		elif RealmManager.instance.current_realm == RealmManager.Realm.MIRROR:
			world_mask = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_MIRROR
	var excl: Array[RID] = base_excl.duplicate()
	excl.append(enemy.get_rid())
	for h_off in [1.15, 1.75]:
		var pt: Vector3 = enemy.global_position + Vector3.UP * float(h_off)
		var q := PhysicsRayQueryParameters3D.create(from_pos, pt, world_mask, excl)
		if space.intersect_ray(q).is_empty():
			return true
	return false


# ------------------------------------------------------------------ overhead ID tags & tactical mark pins

func _update_mark_pins(e: EnemyAI, is_m: bool, mark_num: int, in_region: bool, dist: float) -> void:
	if is_m:
		var old_r: Node3D = e.get_node_or_null("MarkRegionPin") as Node3D
		if old_r != null:
			old_r.visible = false
		var pin: Label3D = e.get_node_or_null("MarkPin") as Label3D
		if pin == null:
			pin = Label3D.new()
			pin.name = "MarkPin"
			pin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			pin.no_depth_test = true
			pin.fixed_size = true
			pin.pixel_size = 0.0011
			pin.font_size = 22
			pin.outline_size = 6
			pin.outline_modulate = Color(0.02, 0.02, 0.04, 0.92)
			pin.font = UITheme.body_font()
			e.add_child(pin)
			pin.position = Vector3(0.0, 2.55, 0.0)
			WorldLabelOverlay.adopt(pin, {"px": 15, "offset": Vector2(0.0, -18.0), "max_dist": 200.0, "kind": "mark"})
		if e.is_hittable_now():
			pin.text = "M%d · %.0fm" % [mark_num, dist]
			pin.modulate = Color(1.0, 0.84, 0.34, 0.98)
		else:
			pin.text = "M%d · MIRROR" % mark_num
			pin.modulate = Color(0.45, 0.88, 1.0, 0.92)
		pin.visible = not bool(pin.get_meta("cinematic_hidden", false))
	elif in_region:
		var old_m: Node3D = e.get_node_or_null("MarkPin") as Node3D
		if old_m != null:
			old_m.visible = false
		var rpin: Label3D = e.get_node_or_null("MarkRegionPin") as Label3D
		if rpin == null:
			rpin = Label3D.new()
			rpin.name = "MarkRegionPin"
			rpin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			rpin.no_depth_test = true
			rpin.fixed_size = true
			rpin.pixel_size = 0.0011
			rpin.font_size = 18
			rpin.outline_size = 5
			rpin.outline_modulate = Color(0.02, 0.02, 0.04, 0.9)
			e.add_child(rpin)
			rpin.position = Vector3(0.0, 2.35, 0.0)
			WorldLabelOverlay.adopt(rpin, {"px": 12, "offset": Vector2(0.0, -12.0), "max_dist": 200.0, "kind": "mark_nearby"})
		rpin.text = ""
		rpin.modulate = Color(1.0, 0.70, 0.25, 0.88)
		rpin.visible = not bool(rpin.get_meta("cinematic_hidden", false))
	else:
		_hide_mark_pins(e)


func _hide_mark_pins(n: Node) -> void:
	for nm in ["MarkPin", "MarkRegionPin"]:
		var p: Node3D = n.get_node_or_null(nm) as Node3D
		if p != null:
			p.visible = false


func _update_tag(e: EnemyAI, en: Dictionary) -> void:
	if not show_tags:
		_hide_tag(e)
		return
	var tag: Label3D = e.get_node_or_null("IntelTag") as Label3D
	if tag == null:
		tag = Label3D.new()
		tag.name = "IntelTag"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.0011
		tag.font_size = 22
		tag.outline_size = 6
		tag.outline_modulate = Color(0, 0, 0, 0.9)
		tag.font = UITheme.body_font()
		tag.modulate = Color(1.0, 0.86, 0.5, 0.95)
		e.add_child(tag)
		tag.position = Vector3(0, 2.45, 0)
		WorldLabelOverlay.adopt(tag, {"px": 14, "offset": Vector2(0, -16), "max_dist": 30.0})
	# Mirror insight reveals more: exact health and the exposed weak point.
	if e.mirror_insight:
		tag.text = "%s · %d%% · WEAK" % [String(en["id"]), int(en["hp_pct"])]
		tag.modulate = Color(0.55, 0.9, 1.0, 0.95)
	else:
		tag.text = String(en["id"])
		tag.modulate = Color(1.0, 0.86, 0.5, 0.95)
	tag.visible = show_tags and not bool(tag.get_meta("cinematic_hidden", false)) and float(en["dist"]) < 28.0


func _hide_tag(n: Node) -> void:
	var tag: Node3D = n.get_node_or_null("IntelTag") as Node3D
	if tag != null:
		tag.visible = false
