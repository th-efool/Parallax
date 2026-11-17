class_name SquadCommandParser
extends RefCounted
## Offline keyword parser: turns a typed (or Whisper-transcribed) utterance into the same command
## Dictionaries the LLM tool calls produce. Used whenever no API key is set, or as a fallback when the API
## fails, so the game is fully playable offline. Never throws: unknown input -> a "confused" say command.
##
## Examples: "Sera kite the brute", "everyone massacre", "Brannoc guard Ivo", "kite and nuke",
## "charge and finish the caster", "lure them into a trap", "ceasefire", "scatter!", "revive Sera",
## "jump 3 times", "dance", "follow me", "hold here", "stop", "status".

const NUMBER_WORDS: Dictionary = {
	"once": 1, "one": 1, "twice": 2, "two": 2, "thrice": 3, "three": 3, "four": 4, "five": 5, "six": 6,
	"seven": 7, "eight": 8, "nine": 9, "ten": 10, "a dozen": 12, "dozen": 12, "a hundred": 100, "hundred": 100,
}

## Ordered: first match wins (combos before their component verbs; panic before everything).
const RULES: Array = [
	["ceasefire", ["ceasefire", "cease fire", "hold fire", "stop fighting", "weapons down", "stand down", "peace", "don't attack", "do not attack"]],
	["massacre", ["massacre", "kill them all", "kill everything", "kill everyone", "go wild", "no mercy", "all out", "all-out", "slaughter", "berserk", "bloodbath"]],
	["scatter", ["scatter", "spread out", "disperse", "split up", "take cover", "run!", "get away"]],
	["combo_kite_nuke", ["kite and nuke", "kite nuke", "kite & nuke", "kite + nuke", "kite them and nuke", "kite them so", "bunch them up"]],
	["combo_charge_finish", ["charge and finish", "charge finish", "charge & finish", "knock down and finish", "charge then finish", "charge in and finish"]],
	["combo_lure_detonate", ["lure and detonate", "lure detonate", "lure them into", "trap", "lure & detonate", "lure them", "mine"]],
	["revive", ["revive", "resurrect", "pick up", "get up", "heal "]],
	["bodyguard", ["bodyguard", "guard", "protect", "cover me", "cover ", "defend", "escort", "keep me safe", "watch my back"]],
	["kite", ["kite", "run circles", "draw them", "lead them around", "distract"]],
	["nuke", ["nuke", "blast", "explode", "bomb", "fireball", "aoe", "big spell", "cast"]],
	["taunt", ["taunt", "provoke", "draw aggro", "pull aggro", "get their attention"]],
	["retreat", ["retreat", "fall back", "back off", "regroup", "get back"]],
	["stop", ["cancel", "stop", "never mind", "nevermind", "abort", "belay"]],
	["auto_off", ["don't engage", "dont engage", "passive", "no auto"]],
	["auto_on", ["auto engage", "auto-engage", "engage at will", "aggressive", "weapons free", "fight freely"]],
	["attack", ["attack", "kill", "fight", "hit", "charge", "focus", "go after", "take out", "engage", "get them", "get him", "get it"]],
	["hold", ["hold", "stay", "wait", "halt", "freeze", "don't move", "stand still", "camp"]],
	["follow", ["follow", "come", "with me", "on me", "to me", "heel"]],
	["jump", ["jump", "hop", "leap"]],
	["dance", ["dance", "boogie", "groove", "party", "celebrate"]],
	["emote", ["wave", "cheer", "sit", "bow", "salute", "spin", "flex"]],
	["status", ["status", "report", "how are you", "health", "sitrep", "how's everyone", "you ok"]],
]

const TARGET_WORDS: Dictionary = {
	"brute": "brute", "big one": "brute", "grave": "brute", "caster": "caster", "hexcaster": "caster",
	"mage": "caster", "wizard": "caster", "stalker": "stalker", "shade": "stalker", "rogue": "stalker",
	"phantom": "phantom", "ghost": "phantom", "twin": "phantom", "shield": "shield", "guard ": "shield",
	"knight": "shield", "skeleton": "skeleton", "warden": "warden", "boss": "warden",
	"strongest": "strongest", "toughest": "strongest", "weakest": "weakest", "wounded": "weakest",
	"nearest": "nearest", "closest": "nearest", "that one": "nearest", "them": "nearest",
}


## Returns an Array of command dictionaries. `ally_names` = live roster names (any case).
static func parse(text: String, ally_names: Array) -> Array:
	var out: Array = []
	var raw: String = text.strip_edges()
	if raw.is_empty():
		return out
	var t: String = " " + raw.to_lower().replace(",", " ").replace(".", " ").replace("?", " ") + " "
	# Multi-clause: "Sera kite them then Ivo nuke" -> split on then / and then / ;
	var clauses: PackedStringArray = _split_clauses(t)
	var carry_allies: Array = []
	for cl in clauses:
		var cmd: Dictionary = _parse_clause(" " + cl.strip_edges() + " ", ally_names, carry_allies)
		if cmd.is_empty():
			continue
		carry_allies = cmd.get("allies", []) as Array
		out.append(cmd)
	if out.is_empty():
		out.append({"verb": "say", "allies": _addressed(t, ally_names), "text": "", "confused": true, "utterance": raw})
	return out


static func _split_clauses(t: String) -> PackedStringArray:
	var s: String = t
	for sep in [" and then ", " then ", ";", " after that ", " afterwards "]:
		s = s.replace(sep, "|")
	return s.split("|", false)


static func _parse_clause(t: String, ally_names: Array, carry_allies: Array) -> Dictionary:
	var allies: Array = _addressed(t, ally_names)
	if allies.is_empty() and not carry_allies.is_empty():
		allies = carry_allies
	var verb: String = ""
	for rule in RULES:
		for kw in (rule[1] as Array):
			if t.contains(String(kw)):
				verb = String(rule[0])
				break
		if not verb.is_empty():
			break
	if verb.is_empty():
		return {}
	var cmd: Dictionary = {"verb": verb, "allies": allies, "utterance": t.strip_edges()}
	match verb:
		"auto_on":
			cmd["verb"] = "auto_engage"
			cmd["enabled"] = true
		"auto_off":
			cmd["verb"] = "auto_engage"
			cmd["enabled"] = false
		"jump":
			cmd["count"] = _extract_count(t)
		"emote":
			for e in ["wave", "cheer", "sit", "bow", "salute", "spin", "flex"]:
				if t.contains(e):
					cmd["text"] = e
					break
		"bodyguard", "revive":
			var who: String = _named_other(t, ally_names, allies)
			cmd["target"] = who if not who.is_empty() else ("player" if verb == "bodyguard" else "")
			if verb == "bodyguard" and (t.contains(" me ") or t.contains(" me") or t.contains("my back")):
				cmd["target"] = "player"
	if not cmd.has("target"):
		var tgt: String = _target_word(t)
		if not tgt.is_empty():
			cmd["target"] = tgt
	return cmd


static func _addressed(t: String, ally_names: Array) -> Array:
	var out: Array = []
	if t.contains("everyone") or t.contains("everybody") or t.contains(" all ") or t.contains("squad") or t.contains(" team") or t.contains("you guys") or t.contains("y'all"):
		return ["all"]
	# Names addressed at the start of the clause (or "X and Y ...") count as the recipients; a name later in
	# the sentence is usually an object ("guard Ivo"), handled by _named_other.
	var first_verb_pos: int = t.length()
	for rule in RULES:
		for kw in (rule[1] as Array):
			var p: int = t.find(String(kw))
			if p >= 0 and p < first_verb_pos:
				first_verb_pos = p
	for n in ally_names:
		var ln: String = String(n).to_lower()
		var p2: int = t.find(" " + ln + " ")
		if p2 < 0:
			p2 = t.find(" " + ln)
		if p2 >= 0 and p2 < first_verb_pos:
			out.append(String(n))
	return out


static func _named_other(t: String, ally_names: Array, addressed: Array) -> String:
	for n in ally_names:
		if addressed.has(String(n)):
			continue
		if t.contains(" " + String(n).to_lower()):
			return String(n)
	return ""


static func _target_word(t: String) -> String:
	for k in TARGET_WORDS.keys():
		if t.contains(String(k)):
			return String(TARGET_WORDS[k])
	return ""


static func _extract_count(t: String) -> int:
	var rx := RegEx.new()
	rx.compile("(\\d+)")
	var m: RegExMatch = rx.search(t)
	if m != null:
		return clampi(int(m.get_string(1)), 1, SquadCommand.MAX_JUMPS)
	for w in NUMBER_WORDS.keys():
		if t.contains(" " + String(w) + " ") or t.contains(" " + String(w)):
			return clampi(int(NUMBER_WORDS[w]), 1, SquadCommand.MAX_JUMPS)
	return 1
