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
	["scatter", ["scatter", "spread out", "disperse", "take cover", "run!"]],
	["rearguard", ["hold the rear", "guard the rear", "watch the rear", "cover the rear", "rear guard", "rearguard", "watch our back", "watch our six", "cover our back", "cover the back", "guard our back", "protect the rear", "the rear"]],
	["circle", ["circle me", "circle around me", "run around me", "run circles around me", "do laps", "lap around", "circles around me"]],
	["face", ["look at me", "face me", "look over here", "turn around", "eyes on me"]],
	["sneak", ["sneak attack", "sneak-attack", "sneak up", "sneak behind", "sneak around", "backstab", "back stab", "stab it in the back", "stab him in the back", "from behind", "behind it", "behind him", "behind her", "behind the ", "behind that", "behind them", "flank it from behind", "go for its back", "hit its back"]],
	["position", ["behind me", "get behind", "go behind", "stay behind", "fall in behind", "in front of me", "in front", "front of me", "ahead of me", "go ahead", "lead the way", "take point", "take the lead", "on my left", "to my left", "my left side", "on my right", "to my right", "my right side", "beside me", "next to me", "stay close", "keep close", "stick close", "close to me", "keep your distance", "keep distance", "stay back", "stay away", "give me space", "get away", "back away", "move away", "go away"]],
	["ranged", ["long distance", "long-distance", "long range", "long-range", "from range", "from afar", "from a distance", "from far", "at range", "ranged", "range attack", "shoot", "snipe", "throw", "pelt", "pepper", "projectile", "fire at", "poke them", "poke it"]],
	["split", ["split up", "split the squad", "flank them", "pincer", "left and right", "split"]],
	["peel", ["peel", "get it off me", "get them off me", "off me", "help me"]],
	["hit_and_run", ["hit and run", "hit-and-run", "harass", "skirmish"]],
	["assist", ["'s target", "same target", "assist", "help "]],
	["hunt", ["hunt", "wildlife", "animals", "chase the bird", "chase the deer", "go chase"]],
	["destroy", ["destroy", "smash", "wreck", "topple", "break the", "knock over"]],
	["interact", ["chest", "open the", "pull the lever", "flip the switch", "use the switch", "interact", "loot"]],
	["combo_kite_nuke", ["kite and nuke", "kite nuke", "kite & nuke", "kite + nuke", "kite them and nuke", "kite them so", "bunch them up"]],
	["combo_charge_finish", ["charge and finish", "charge finish", "charge & finish", "knock down and finish", "charge then finish", "charge in and finish"]],
	["combo_lure_detonate", ["lure and detonate", "lure detonate", "lure them into", "trap", "lure & detonate", "lure them", "mine"]],
	["kite", ["kite", "bait", "run in circles", "run circles", "running circles", "run around with", "make it chase", "make them chase", "make him chase", "draw them", "draw it", "draw him", "lead them around", "lead it around", "lead it", "keep it busy", "keep them busy", "keep him busy", "pull it away", "pull them away", "drag it", "drag them", "lure it", "lure him", "lure her", "bring it to us", "bring it here", "bring them to us", "distract", "pull em", "pull them", "pull it", "pull that", "bring", "pull here", "taunt here"]],
	["revive", ["revive", "resurrect", "pick up", "get up", "heal "]],
	["bodyguard", ["bodyguard", "guard", "protect", "cover me", "cover ", "defend", "escort", "keep me safe", "watch my back"]],
	["nuke", ["nuke", "blast", "explode", "bomb", "fireball", "aoe", "big spell", "cast"]],
	["taunt", ["taunt", "provoke", "aggro", "get their attention"]],
	["retreat", ["retreat", "fall back", "back off", "regroup", "get back"]],
	["stop", ["cancel", "stop", "never mind", "nevermind", "abort", "belay"]],
	["auto_off", ["don't engage", "dont engage", "passive", "no auto"]],
	["auto_on", ["auto engage", "auto-engage", "engage at will", "aggressive", "weapons free", "fight freely"]],
	["attack", ["attack", "kill", "fight", "hit", "charge", "focus", "go after", "take out", "engage", "get them", "get him", "get it"]],
	["hold", ["hold", "stay", "wait", "halt", "freeze", "don't move", "stand still", "camp", "pause"]],
	["follow", ["follow", "come", "with me", "on me", "to me", "heel"]],
	["jump", ["jump", "hop", "leap"]],
	["dance", ["dance", "boogie", "groove", "party", "celebrate"]],
	["emote", EMOTES],
	["status", ["status", "report", "how are you", "health", "sitrep", "how's everyone", "you ok"]],
	["chat", CHAT_WORDS],
]

## Emote words -> canonical emote (first word of each entry is what the ally plays).
const EMOTE_MAP: Dictionary = {
	"wave": "wave", "cheer": "cheer", "sit": "sit", "bow": "bow", "salute": "salute", "spin": "spin", "flex": "flex",
	"laugh": "laugh", "clap": "clap", "applaud": "clap", "point": "point", "kneel": "kneel", "nod": "nod", "shrug": "shrug",
	"backflip": "backflip", "flip": "backflip", "lie down": "lie", "sleep": "lie", "nap": "lie", "play dead": "lie",
	"pose": "flex", "high five": "wave", "facepalm": "shrug", "pray": "kneel", "cry": "shrug", "shake": "spin",
	"push up": "kneel", "pushup": "kneel", "victory": "cheer", "yay": "cheer", "hooray": "cheer",
}
const EMOTES: Array = ["wave", "cheer", " sit", " bow", "salute", "spin", "flex", " laugh", "clap", "applaud", " point at", "kneel",
	" nod", "shrug", "backflip", "do a flip", "lie down", "sleep", " nap", "play dead", " pose", "high five", "facepalm", "pray",
	" cry", "shake it", "push up", "pushup", "victory", " yay", "hooray"]
## Small talk: phrase -> topic (answered in character, no movement).
const CHAT_TOPICS: Dictionary = {
	"hello": "greet", "hi ": "greet", " hey": "greet", " yo ": "greet", "morning": "greet", " sup ": "greet",
	"thanks": "thanks", "thank you": "thanks", "good job": "praise", "well done": "praise", "nice work": "praise",
	"nice one": "praise", "great job": "praise", "good work": "praise", "you rock": "praise", "proud of": "praise",
	"joke": "joke", "funny": "joke", "who are you": "intro", "introduce": "intro",
	"tell me about yourself": "intro", "what do you think": "opinion", "your opinion": "opinion", "any ideas": "opinion",
	"what should we do": "opinion", "how's it going": "mood", "how do you feel": "mood", "are you scared": "mood",
	" sing ": "sing", " song": "sing", "story": "story", "love you": "love", "sorry": "sorry", "my bad": "sorry",
	"bored": "bored", "good night": "bye", "bye": "bye", "goodbye": "bye", "lol": "joke", "haha": "joke",
	"what's up": "greet", "whats up": "greet", "where are we": "where", "what is this place": "where",
}
const CHAT_WORDS: Array = ["hello", "hi ", " hey", " yo ", "morning", " sup ", "thanks", "thank you", "good job", "well done",
	"nice work", "nice one", "great job", "good work", "you rock", "proud of", "joke", "funny", "who are you",
	"introduce", "tell me about yourself", "what do you think", "your opinion", "any ideas", "what should we do",
	"how's it going", "how do you feel", "are you scared", " sing ", " song", "story", "love you", "sorry", "my bad", "bored",
	"good night", "bye", "goodbye", "lol", "haha", "what's up", "whats up", "where are we", "what is this place"]
## Words that start a new instruction for a different ally / group inside one sentence.
const CLAUSE_JOINERS: Array[String] = [",", "and", "&", "while", "but", "also", "plus", "meanwhile", "whereas"]
const POSITION_SPOTS: Array = [
	["behind", ["behind me", "get behind", "go behind", "stay behind", "fall in behind"]],
	["front", ["in front", "front of me", "ahead of me", "go ahead", "lead the way", "take point", "take the lead"]],
	["left", ["on my left", "to my left", "my left side"]],
	["right", ["on my right", "to my right", "my right side"]],
	["close", ["beside me", "next to me", "stay close", "keep close", "stick close", "close to me"]],
	["far", ["keep your distance", "keep distance", "stay back", "stay away", "give me space", "get away", "back away", "move away", "go away"]],
]

const TARGET_WORDS: Dictionary = {
	"brute": "brute", "big one": "brute", "grave": "brute", "caster": "caster", "hexcaster": "caster",
	"mage": "caster", "wizard": "caster", "stalker": "stalker", "shade": "stalker", "rogue": "stalker",
	"phantom": "phantom", "ghost": "phantom", "twin": "phantom", "shield": "shield",
	"knight": "shield", "skeleton": "skeleton", "warden": "warden", "boss": "warden",
	"strongest": "strongest", "toughest": "strongest", "weakest": "weakest", "wounded": "weakest",
	"nearest": "nearest", "closest": "nearest", "that one": "nearest", "them": "nearest",
}


const DESCRIPTOR_WORDS: Array[String] = ["purple", "violet", "blue", "cyan", "green", "pale", "white", "bone", "gold", "golden",
	"steel", "silver", "red", "black", "dark", "glowing", "axe", "sword", "swords", "blades", "shield", "orb", "greataxe",
	"hooded", "armored", "armoured", "big", "huge", "giant", "small", "left", "right", "behind", "near", "closest to",
	"next to", "attacking", "hitting", "chasing", "targeting", "farthest", "furthest", "stunned", "fleeing", "farther", "further", "distant"]
const PANIC_VERBS: Array[String] = ["ceasefire", "massacre", "scatter"]
const TARGETED_VERBS: Array[String] = ["attack", "ranged", "kite", "sneak", "surround", "nuke", "taunt", "hit_and_run", "skill", "strategy",
	"combo_kite_nuke", "combo_charge_finish", "combo_lure_detonate", "peel"]

static var _vocab: Dictionary = {}


## Returns an Array of command dictionaries. `ally_names` = live roster names (any case).
## `ctx` (optional, from AllySquadManager.get_parser_context()): {"skills": [{ally, id, name, aliases}]}.
static func parse(text: String, ally_names: Array, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	var raw: String = text.strip_edges()
	if raw.is_empty():
		return out
	# Sentence boundaries are clause boundaries too ("Brannoc, guard me. Sera, kite them.").
	# Commas are kept as " , " tokens until clause splitting (they separate per-ally instructions).
	var t: String = " " + raw.to_lower().replace(". ", " ; ").replace("! ", " ; ").replace("? ", " ; ").replace(",", " , ").replace(".", " ").replace("?", " ").replace("!", " ") + " "
	t = t.replace(" go n ", " and ").replace(" gon ", " and ")
	t = " " + _normalize(t, ally_names, ctx) + " "
	# Multi-clause: "Sera kite them then Ivo nuke", "Brannoc jump twice, Sera go behind me and shoot the caster,
	# everyone else hold the rear" -> split on then / ; / and between two instructions / a new addressee.
	var clauses: Array = _split_clauses(t, ally_names, ctx)
	var carry_allies: Array = []
	var mentioned: Array = []
	var last_target: String = ""
	for cl in clauses:
		var ct: String = " " + String(cl).replace(" , ", " ").strip_edges() + " "
		var cmd: Dictionary = _parse_clause(ct, ally_names, carry_allies, ctx)
		if cmd.is_empty():
			continue
		# "everyone else" / "the rest of you" / "others" = every ally not already given an order in this message.
		if _says_rest(ct):
			var rest: Array = []
			for n in ally_names:
				if not mentioned.has(String(n)):
					rest.append(String(n))
			cmd["allies"] = rest if not rest.is_empty() else ["all"]
		# Back-to-back small talk to the same person collapses into one reply (keep the most specific topic).
		if String(cmd.get("verb", "")) == "chat" and not out.is_empty() and String((out[-1] as Dictionary).get("verb", "")) == "chat":
			var prev: Dictionary = out[-1] as Dictionary
			if (prev.get("allies", []) as Array).is_empty() or prev.get("allies", []) == cmd.get("allies", []) or (cmd.get("allies", []) as Array).is_empty():
				if String(prev.get("topic", "")) in ["greet", "generic"]:
					prev["topic"] = cmd.get("topic", "generic")
				if (prev.get("allies", []) as Array).is_empty():
					prev["allies"] = cmd.get("allies", [])
				carry_allies = prev.get("allies", []) as Array
				continue
		# Pronouns ("it", "him", "that one", "the same") refer back to the enemy named earlier in the message.
		var vb: String = String(cmd.get("verb", ""))
		if (vb in TARGETED_VERBS or vb == "surround") and (not cmd.has("target") or String(cmd.get("target", "")) == "nearest") and not last_target.is_empty():
			for pr in [" it ", " him ", " her ", " that one", " the same", " same one", " that guy", " that thing", " them "]:
				if ct.contains(pr):
					cmd["target"] = last_target
					break
		if cmd.has("target") and String(cmd["target"]) != "nearest" and (vb in TARGETED_VERBS or vb == "surround"):
			last_target = String(cmd["target"])
		# "Brannoc bait the brute and run in circles" = one kite, not two.
		if not out.is_empty() and not (vb in ["jump", "emote", "dance", "say", "chat"]):
			var pv: Dictionary = out[-1] as Dictionary
			if String(pv.get("verb", "")) == vb and (pv.get("allies", []) == cmd.get("allies", []) or (cmd.get("allies", []) as Array).is_empty()):
				for k in cmd.keys():
					if not pv.has(k):
						pv[k] = cmd[k]
				continue
		carry_allies = cmd.get("allies", []) as Array
		for n2 in carry_allies:
			if not mentioned.has(String(n2)):
				mentioned.append(String(n2))
		out.append(cmd)
	if out.is_empty():
		var who: Array = _addressed(t.replace(" , ", " "), ally_names)
		# Talking to someone without an order is conversation, not confusion.
		if not who.is_empty() and not who.has("all"):
			out.append({"verb": "chat", "allies": who, "topic": "generic", "utterance": raw})
		else:
			out.append({"verb": "say", "allies": who, "text": "", "confused": true, "utterance": raw})
	return out


static func _says_rest(t: String) -> bool:
	for w in ["everyone else", "everybody else", "the rest", "rest of you", "the others", "others ", "other two", "you two", "anyone else"]:
		if t.contains(" " + w):
			return true
	return false


## True if the text holds an instruction (a verb rule, a skill / strategy name, or an enemy description).
static func _has_instruction(t: String, ctx: Dictionary) -> bool:
	var s: String = " " + t.replace(" , ", " ").strip_edges() + " "
	for rule in RULES:
		for kw in (rule[1] as Array):
			if s.contains(String(kw)):
				return true
	if not _match_skill(s, [], ctx).is_empty() or not SquadStrategies.match_text(s).is_empty():
		return true
	return false


static func _split_clauses(t: String, ally_names: Array = [], ctx: Dictionary = {}) -> Array:
	var s: String = t
	for sep in [" and then ", " , then ", " then ", ";", " after that ", " afterwards ", " after which ", " followed by ", " next , ", " finally "]:
		s = s.replace(sep, "|")
	var out: Array = []
	for part in s.split("|", false):
		for p2 in _split_joined(" " + String(part).strip_edges() + " ", ally_names, ctx):
			if not String(p2).strip_edges().replace(",", "").strip_edges().is_empty():
				out.append(p2)
	return out


## Splits "Brannoc jump , Sera dance and Ivo hold the rear" / "jump twice and wave" at a joiner (comma / and /
## while / but / also ...) when BOTH sides carry their own instruction. Multi-word rule phrases that contain a
## joiner ("kite and nuke", "hit and run", "left and right") are protected.
static func _split_joined(t: String, ally_names: Array, ctx: Dictionary) -> Array:
	var protected: String = t
	var keep: Dictionary = {}
	var k: int = 0
	for rule in RULES:
		for kw in (rule[1] as Array):
			var ks: String = String(kw)
			if (ks.contains(" and ") or ks.contains(" & ")) and protected.contains(ks):
				var tok: String = "keep%dx" % k
				keep[tok] = ks
				protected = protected.replace(ks, tok)
				k += 1
	for st in SquadStrategies.LIST:
		for al in ((st as Dictionary)["aliases"] as Array):
			var as2: String = String(al)
			if as2.contains(" and ") and protected.contains(as2):
				var tok2: String = "keep%dx" % k
				keep[tok2] = as2
				protected = protected.replace(as2, tok2)
				k += 1
	var words: PackedStringArray = protected.split(" ", false)
	var pieces: Array = []
	var cur: PackedStringArray = []
	var i: int = 0
	while i < words.size():
		var w: String = words[i]
		if w in CLAUSE_JOINERS and not cur.is_empty():
			var rest_words: PackedStringArray = words.slice(i + 1)
			# The candidate next segment runs to the next joiner.
			var nxt: PackedStringArray = []
			for r in rest_words:
				if String(r) in CLAUSE_JOINERS:
					break
				nxt.append(r)
			var left: String = _restore(" ".join(cur), keep)
			var right: String = _restore(" ".join(nxt), keep)
			var right_named: bool = not nxt.is_empty() and (_is_name(String(nxt[0]), ally_names) or String(nxt[0]) in ["everyone", "everybody", "all", "rest", "others", "the"])
			if _has_instruction(left, ctx) and _has_instruction(right, ctx) and (right_named or w != "with"):
				pieces.append(left)
				cur = []
				i += 1
				continue
			if w == ",":
				i += 1
				continue
		cur.append(w)
		i += 1
	if not cur.is_empty():
		pieces.append(_restore(" ".join(cur), keep))
	return pieces


static func _restore(s: String, keep: Dictionary) -> String:
	var o: String = s
	for tok in keep.keys():
		o = o.replace(String(tok), String(keep[tok]))
	return o


static func _is_name(w: String, ally_names: Array) -> bool:
	for n in ally_names:
		if String(n).to_lower() == w:
			return true
	return false


static func _parse_clause(t: String, ally_names: Array, carry_allies: Array, ctx: Dictionary = {}) -> Dictionary:
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
	# Panic orders always win. Otherwise a named skill of an addressed ally, then a squad strategy, then a
	# skill anyone owns, then the plain verb rules.
	if not (verb in PANIC_VERBS):
		var skill: Dictionary = _match_skill(t, allies, ctx)
		var strat: Dictionary = SquadStrategies.match_text(t)
		if not skill.is_empty() and (allies.has(String(skill["ally"])) or strat.is_empty()):
			var c1: Dictionary = {"verb": "skill", "skill": skill["id"], "allies": allies if not allies.is_empty() else [skill["ally"]], "utterance": t.strip_edges()}
			var tgt_s: String = _skill_target(t, ally_names, allies)
			if not tgt_s.is_empty():
				c1["target"] = tgt_s
			return c1
		if not strat.is_empty():
			var c2: Dictionary = {"verb": "strategy", "strategy": strat["id"], "allies": allies, "utterance": t.strip_edges()}
			if _has_descriptor(t):
				c2["target"] = "desc:" + t.strip_edges()
			else:
				var tw: String = _target_word(t)
				if not tw.is_empty():
					c2["target"] = tw
			return c2
	# Verb-less but clearly about an enemy ("the purple one!", "E3!", "that axe guy") -> attack it.
	if verb.is_empty() and (_has_descriptor(t) or not _target_word(t).is_empty() and _target_word(t) != "nearest"):
		verb = "attack"
	if verb.is_empty():
		return {}
	# Name after the verb with no other role in the sentence = who the order is for ("hold the rear Brannoc").
	if allies.is_empty() and not (verb in ["bodyguard", "revive", "assist"]):
		allies = _named_anywhere(t, ally_names)
	var cmd: Dictionary = {"verb": verb, "allies": allies, "utterance": t.strip_edges()}
	if verb in TARGETED_VERBS and _has_descriptor(t):
		cmd["target"] = "desc:" + t.strip_edges()
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
			var best_len: int = 0
			for e in EMOTE_MAP.keys():
				var es: String = String(e)
				if t.contains(es) and es.length() > best_len:
					best_len = es.length()
					cmd["text"] = String(EMOTE_MAP[e])
			if not cmd.has("text"):
				cmd["text"] = "cheer"
		"position":
			cmd["spot"] = "behind"
			for ps in POSITION_SPOTS:
				for kw2 in (ps[1] as Array):
					if t.contains(String(kw2)):
						cmd["spot"] = String(ps[0])
						break
		"chat":
			cmd["topic"] = "generic"
			var bl: int = 0
			for ck in CHAT_TOPICS.keys():
				if t.contains(String(ck)) and String(ck).length() > bl:
					bl = String(ck).length()
					cmd["topic"] = String(CHAT_TOPICS[ck])
			if allies.is_empty():
				cmd["allies"] = []
		"hold":
			var secs: int = _extract_seconds(t)
			if secs > 0:
				cmd["step_sec"] = secs
		"sneak":
			cmd["verb"] = "surround"
			cmd["side"] = "rear"
			cmd["angle"] = 180.0
			# "behind" here is the manoeuvre, not a description of which enemy.
			if String(cmd.get("target", "")).begins_with("desc:"):
				var stripped: String = t.replace(" behind ", " ").replace(" from ", " ")
				if not _has_descriptor(stripped):
					cmd.erase("target")
		"kite":
			# Bait it back to us -> circle around the squad so the others can hit it.
			for w in ["to us", "to me", "over here", " here ", "to the squad", "to the group", "into us", "towards us", "toward us", "into the ambush", "into our trap"]:
				if t.contains(w):
					cmd["lure"] = "player"
					break
		"bodyguard", "revive":
			var who: String = _named_other(t, ally_names, allies)
			cmd["target"] = who if not who.is_empty() else ("player" if verb == "bodyguard" else "")
			if verb == "bodyguard" and (t.contains(" me ") or t.contains(" me") or t.contains("my back")):
				cmd["target"] = "player"
			if verb == "bodyguard" and who.is_empty() and (t.contains("objective") or t.contains("gate") or t.contains("switch") or t.contains("lever")):
				cmd["target"] = "objective"
		"assist":
			# "attack Sera's target" / "help Brannoc" -> attack whatever that ally is fighting.
			cmd["verb"] = "attack"
			var mate: String = _named_other(t, ally_names, allies)
			cmd["target"] = "ally:" + mate if not mate.is_empty() else "nearest"
		"taunt":
			if t.contains("aggro") or t.contains("attention"):
				cmd["area"] = true
		"interact":
			if t.contains("chest") or t.contains("loot"):
				cmd["target"] = "chest"
	if not cmd.has("target"):
		var tgt: String = _target_word(t)
		if not tgt.is_empty():
			cmd["target"] = tgt
	return cmd


static func _has_descriptor(t: String) -> bool:
	var rx := RegEx.new()
	rx.compile("\\b(?:e|enemy)\\s*#?\\s*\\d+\\b")
	if rx.search(t) != null:
		return true
	for w in DESCRIPTOR_WORDS:
		if t.contains(" " + w + " ") or t.contains(" " + w + "s "):
			return true
	return false


## Skill owned by an addressed ally (preferred) or anyone: {"ally", "id"} or {}.
static func _match_skill(t: String, allies: Array, ctx: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_len: int = 0
	for s in (ctx.get("skills", []) as Array):
		var sd: Dictionary = s as Dictionary
		var phrases: Array = (sd.get("aliases", []) as Array).duplicate()
		phrases.append(String(sd.get("name", "")).to_lower())
		for p in phrases:
			var ps: String = String(p)
			if ps.length() < 3 or not t.contains(" " + ps + " ") and not t.contains(" " + ps):
				continue
			var l: int = ps.length() + (100 if allies.has(String(sd["ally"])) else 0)
			if l > best_len:
				best_len = l
				best = {"ally": String(sd["ally"]), "id": String(sd["id"])}
	return best


## Target for a skill: an enemy description, "me"/an ally (heals / wards), else blank (skill decides).
static func _skill_target(t: String, ally_names: Array, addressed: Array) -> String:
	if _has_descriptor(t):
		return "desc:" + t.strip_edges()
	var other: String = _named_other(t, ally_names, addressed)
	if not other.is_empty():
		return other
	if t.contains(" me ") or t.ends_with(" me"):
		return "me"
	var tw: String = _target_word(t)
	return tw if tw != "nearest" else ""


## Typo tolerance: words of 5+ letters that are not in the command vocabulary snap to the closest
## vocabulary word within edit distance 1 (2 for long words). "masacre" -> "massacre", "sheild" -> "shield".
static func _normalize(t: String, ally_names: Array, ctx: Dictionary) -> String:
	var vocab: Dictionary = _build_vocab(ally_names, ctx)
	var out: PackedStringArray = []
	for w in t.split(" ", false):
		var word: String = w
		if word.length() >= 5 and not vocab.has(word) and not word.is_valid_int():
			var lim: int = 1 if word.length() < 8 else 2
			var best: String = ""
			var bd: int = lim + 1
			for v in vocab.keys():
				var vs: String = String(v)
				if absi(vs.length() - word.length()) > lim:
					continue
				var d: int = _lev(word, vs, lim)
				if d < bd:
					bd = d
					best = vs
			if not best.is_empty():
				word = best
		out.append(word)
	return " ".join(out)


static func _build_vocab(ally_names: Array, ctx: Dictionary) -> Dictionary:
	if _vocab.is_empty():
		for rule in RULES:
			for kw in (rule[1] as Array):
				for w in String(kw).split(" ", false):
					_vocab[w] = true
		for k in TARGET_WORDS.keys():
			for w in String(k).split(" ", false):
				_vocab[w] = true
		for w in DESCRIPTOR_WORDS:
			_vocab[w] = true
		for s in SquadStrategies.LIST:
			for a in ((s as Dictionary)["aliases"] as Array):
				for w in String(a).split(" ", false):
					_vocab[w] = true
		for w in ["everyone", "everybody", "please", "there", "their", "these", "those", "where", "about", "right", "behind", "nearest", "closest",
				"while", "whilst", "whereas", "meanwhile", "others", "other", "rest", "else", "after", "afterwards", "seconds", "times", "front", "rear", "around"]:
			_vocab[w] = true
		for k2 in EMOTE_MAP.keys():
			for w2 in String(k2).split(" ", false):
				_vocab[w2] = true
	var v: Dictionary = _vocab.duplicate()
	for n in ally_names:
		v[String(n).to_lower()] = true
	for s in (ctx.get("skills", []) as Array):
		for a in ((s as Dictionary).get("aliases", []) as Array):
			for w in String(a).split(" ", false):
				v[w] = true
	return v


## Optimal-string-alignment distance (Levenshtein + adjacent swaps, so "sheild" -> "shield" is 1).
static func _lev(a: String, b: String, limit: int) -> int:
	var prev2: PackedInt32Array = []
	var prev: PackedInt32Array = []
	prev.resize(b.length() + 1)
	for j in range(b.length() + 1):
		prev[j] = j
	for i in range(1, a.length() + 1):
		var cur: PackedInt32Array = []
		cur.resize(b.length() + 1)
		cur[0] = i
		var row_min: int = cur[0]
		for j in range(1, b.length() + 1):
			var cost: int = 0 if a[i - 1] == b[j - 1] else 1
			cur[j] = mini(mini(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				cur[j] = mini(cur[j], prev2[j - 2] + 1)
			row_min = mini(row_min, cur[j])
		if row_min > limit:
			return limit + 1
		prev2 = prev
		prev = cur
	return prev[b.length()]


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


## First ally named in the text (in reading order) who is not one of the addressees: "guard Ivo and Sera" -> Ivo.
static func _named_other(t: String, ally_names: Array, addressed: Array) -> String:
	var best: String = ""
	var best_p: int = 1 << 30
	for n in ally_names:
		if addressed.has(String(n)):
			continue
		var p: int = t.find(" " + String(n).to_lower())
		if p >= 0 and p < best_p:
			best_p = p
			best = String(n)
	return best


## Any ally named anywhere in the clause (trailing vocatives: "hold the rear Brannoc", "hey Ivo").
static func _named_anywhere(t: String, ally_names: Array) -> Array:
	var out: Array = []
	for n in ally_names:
		if t.contains(" " + String(n).to_lower() + " "):
			out.append(String(n))
	return out


static func _target_word(t: String) -> String:
	for k in TARGET_WORDS.keys():
		if t.contains(String(k)):
			return String(TARGET_WORDS[k])
	return ""


## "wait 3 seconds" / "hold for five secs" -> 3 / 5; 0 when no duration given.
static func _extract_seconds(t: String) -> int:
	var rx := RegEx.new()
	rx.compile("(\\d+)\\s*(?:s|sec|secs|second|seconds)\\b")
	var m: RegExMatch = rx.search(t)
	if m != null:
		return clampi(int(m.get_string(1)), 1, 30)
	for w in NUMBER_WORDS.keys():
		if t.contains(" " + String(w) + " sec"):
			return clampi(int(NUMBER_WORDS[w]), 1, 30)
	if t.contains("a bit") or t.contains("a moment") or t.contains("a sec"):
		return 3
	return 0


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
