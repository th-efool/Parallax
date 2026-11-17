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

const REFRESH_SEC: float = 0.25
const RANGE_M: float = 40.0

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
var show_tags: bool = true


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
			if o is EnemyAI and is_instance_valid(o) and not (o as EnemyAI).is_dead:
				return o as EnemyAI
	return null


# ------------------------------------------------------------------ scan

func refresh() -> void:
	_entries.clear()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var pf: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = n as EnemyAI
		if e == null or e.is_dead or not e.is_inside_tree():
			_hide_tag(n)
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if not e.is_active or d > RANGE_M:
			_hide_tag(e)
			continue
		var entry: Dictionary = _describe(e, player, pf, d)
		_entries.append(entry)
		_update_tag(e, entry)
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))


func _describe(e: EnemyAI, player: Node3D, pf: Vector3, d: float) -> Dictionary:
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
	var s: String = "%s %s — %s %s%s, %s | %d%% HP | %.0fm %s | %s | targeting %s" % [
		en["id"], en["name"], ("" if en["size"] == "normal" else String(en["size"]) + " "), en["color"],
		(" " + String(en["model"])) if not String(en["model"]).is_empty() else "", en["weapon"],
		int(en["hp_pct"]), float(en["dist"]), en["bearing"], en["realm"], en["targeting"]]
	if bool(en["ranged"]):
		s += " | ranged"
	if not String(en["state"]).is_empty():
		s += " | " + String(en["state"])
	return s


## Battlefield table for the Director prompt (nearest first).
func describe_text(max_rows: int = 14) -> String:
	if _entries.is_empty():
		return "No enemies within %dm." % int(RANGE_M)
	var rows: PackedStringArray = []
	for i in range(mini(max_rows, _entries.size())):
		rows.append("- " + entry_line(_entries[i]))
	if _entries.size() > max_rows:
		rows.append("- (+%d more farther away)" % (_entries.size() - max_rows))
	return "\n".join(rows)


# ------------------------------------------------------------------ resolve

## Resolves an enemy from: "E3" | type word | "ally:<Name>" (handled by the manager) | free description |
## superlatives (nearest / farthest / strongest / weakest / biggest). `asker` biases "nearest" toward that ally.
func resolve(selector: String, asker: Node3D = null) -> EnemyAI:
	if _entries.is_empty():
		refresh()
	if _entries.is_empty():
		return null
	var s: String = " " + selector.to_lower().strip_edges().trim_prefix("desc:") + " "
	# Explicit ID anywhere in the text ("E3", "e 3", "enemy 3").
	var rx := RegEx.new()
	rx.compile("\\b(?:e|enemy|target)\\s*#?\\s*(\\d+)\\b")
	var m: RegExMatch = rx.search(s)
	if m != null:
		var byid: EnemyAI = node_for_id("E" + m.get_string(1))
		if byid != null:
			return byid
	var tokens: PackedStringArray = s.replace(",", " ").replace(".", " ").replace("'s", " ").split(" ", false)
	var origin: Vector3 = asker.global_position if asker != null else (get_tree().get_first_node_in_group("player") as Node3D).global_position
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
	var best: EnemyAI = null
	var best_score: float = -INF
	var any_desc: bool = false
	for en in _entries:
		var score: float = 0.0
		var words: String = String(en["words"])
		for t in tokens:
			if t.length() < 3 or t in ["the", "one", "guy", "that", "this", "with", "and", "who", "kill", "attack", "him", "her", "them", "enemy", "please", "now", "get", "go", "hit"]:
				continue
			if t in COLOR_WORDS or t in ["axe", "sword", "shield", "orb", "blades", "caster", "mage", "brute", "rogue", "knight", "barbarian", "skeleton", "phantom", "ghost", "stalker", "hexcaster", "warden", "big", "huge", "small", "giant", "archer", "ranged", "glowing", "hooded", "armored", "greataxe", "twin"]:
				any_desc = true
				if words.contains(t):
					score += 3.0
				elif t in ["caster", "mage", "archer", "ranged"] and bool(en["ranged"]):
					score += 3.0
				elif t in ["big", "huge", "giant"] and String(en["size"]) in ["big", "huge"]:
					score += 2.0
				elif t in ["blades"] and String(en["weapon"]).contains("sword"):
					score += 2.0
				else:
					score -= 1.5
			if SIDE_WORDS.has(t):
				any_desc = true
				score += 2.0 if String(en["bearing"]).contains(String(SIDE_WORDS[t])) else -1.0
			if t in ["stunned", "fleeing", "enraged", "wounded", "hurt", "dying"]:
				any_desc = true
				if t in ["wounded", "hurt", "dying"]:
					score += (100.0 - float(en["hp_pct"])) / 40.0
				elif String(en["state"]).contains(t):
					score += 3.0
		if ref_node != null:
			any_desc = true
			if ref_mode == "targeting":
				var tn: String = String(en["targeting"]).to_lower()
				var rn: String = "player" if ref_node is PlayerController else String(ref_node.call("get_display_name")).to_lower()
				score += 4.0 if tn == rn else -2.0
			else:
				score -= (en["node"] as Node3D).global_position.distance_to(ref_node.global_position) * 0.25
		# Superlatives / default ordering.
		var d: float = (en["node"] as Node3D).global_position.distance_to(origin)
		if s.contains("farthest") or s.contains("furthest"):
			score += d * 0.05
		elif s.contains("strongest") or s.contains("toughest") or s.contains("biggest"):
			score += float(en["hp"]) * 0.01
		elif s.contains("weakest") or s.contains("lowest"):
			score += (100.0 - float(en["hp_pct"])) * 0.03
		else:
			score -= d * 0.05
		if (en["node"] as EnemyAI).is_aggroed():
			score += 0.3
		if score > best_score:
			best_score = score
			best = en["node"] as EnemyAI
	# A description that matches nothing at all should not silently pick a random enemy far away.
	if any_desc and best_score < 0.5 and ref_node == null:
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


# ------------------------------------------------------------------ overhead ID tags

func _update_tag(e: EnemyAI, en: Dictionary) -> void:
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
	tag.text = String(en["id"])
	tag.visible = show_tags and not bool(tag.get_meta("cinematic_hidden", false)) and float(en["dist"]) < 28.0


func _hide_tag(n: Node) -> void:
	var tag: Node3D = n.get_node_or_null("IntelTag") as Node3D
	if tag != null:
		tag.visible = false
