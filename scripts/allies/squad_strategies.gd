class_name SquadStrategies
extends RefCounted
## Squad-level strategy library. Each strategy is pure data: per-role command lists that the
## `AllySquadManager` expands onto whoever is alive (any ally count; roles fall back to `any`).
## Add a strategy = add one dictionary below (aliases make it reachable from the offline parser; the LLM
## Director sees `name` + `desc`).
##
## Step format: {"verb": <SquadCommand verb>, "args": {...}}. Arg tokens resolved at execution:
##   "$target"          the strategy's primary target (an enemy ID like "E3")
##   "$distinct"        a different enemy per ally (nearest first)
##   "$weakest_distinct" a different enemy per ally (lowest HP first)
##   "$weakest_friend"  the lowest-HP squad member or the player
##   "$vanguard"        the vanguard ally's name (e.g. for "ally:<name>" assists)
##   "$slot_angle"      evenly spaced angle for this ally around the target (surround)
##   "$line_spot"       this ally's spot on a line between the player and the threat
##   "$behind_spot"     a spot just behind the vanguard
##   "$player_spot"     the player's current position

const LIST: Array = [
	{"id": "focus_fire", "name": "Focus Fire", "desc": "Everyone hits the same target until it drops.",
		"aliases": ["focus fire", "focus", "all on", "everyone on", "gang up", "dogpile", "burn it down", "concentrate fire"],
		"roles": {"any": [{"verb": "attack", "args": {"target": "$target"}}]}},
	{"id": "pincer", "name": "Pincer", "desc": "Vanguard engages the target from the front while the others close in on both flanks.",
		"aliases": ["pincer", "flank it", "flank them", "from both sides", "squeeze"],
		"roles": {"vanguard": [{"verb": "taunt", "args": {"target": "$target"}}, {"verb": "attack", "args": {"target": "$target"}}],
			"any": [{"verb": "surround", "args": {"target": "$target", "angle": "$slot_angle", "side": "flank"}}]}},
	{"id": "surround", "name": "Surround", "desc": "Spread evenly around the target and attack from every side.",
		"aliases": ["surround", "encircle", "circle it", "box it in", "trap it"],
		"roles": {"any": [{"verb": "surround", "args": {"target": "$target", "angle": "$slot_angle", "side": "ring"}}]}},
	{"id": "hammer_and_anvil", "name": "Hammer and Anvil", "desc": "Vanguard pins the target in place (anvil) while everyone else hits it from behind (hammer).",
		"aliases": ["hammer and anvil", "anvil", "pin it", "hit it from behind"],
		"roles": {"vanguard": [{"verb": "taunt", "args": {"target": "$target"}}, {"verb": "attack", "args": {"target": "$target"}}],
			"any": [{"verb": "surround", "args": {"target": "$target", "angle": 180.0, "side": "rear"}}]}},
	{"id": "shield_wall", "name": "Shield Wall", "desc": "Vanguard raises Shield Wall at the front; the others fight from right behind it, protected.",
		"aliases": ["shield wall", "turtle", "phalanx", "behind the shield", "form up behind"],
		"roles": {"vanguard": [{"verb": "skill", "args": {"skill": "shield_wall"}}, {"verb": "hold", "args": {"engage_r": 3.5, "label": "holding the wall"}}],
			"any": [{"verb": "hold", "args": {"spot": "$behind_spot", "engage_r": 3.0, "label": "behind the wall"}}]}},
	{"id": "hold_the_line", "name": "Hold the Line", "desc": "Form a line between the player and the enemies; strike anything that reaches it.",
		"aliases": ["hold the line", "defensive line", "form a line", "line up", "nobody gets through", "hold the choke", "choke point"],
		"roles": {"any": [{"verb": "hold", "args": {"spot": "$line_spot", "engage_r": 4.0, "label": "holding the line"}}]}},
	{"id": "divide_and_conquer", "name": "Divide and Conquer", "desc": "Each ally takes a different enemy so nobody stacks.",
		"aliases": ["divide and conquer", "each take one", "split targets", "one each", "pick a target each", "spread your attacks"],
		"roles": {"any": [{"verb": "attack", "args": {"target": "$distinct"}}]}},
	{"id": "tank_and_spank", "name": "Tank and Spank", "desc": "Vanguard pulls all the aggro (taunt + War Cry); everyone else hits whatever is on the vanguard.",
		"aliases": ["tank and spank", "tank it", "you tank", "classic tank", "tank"],
		"roles": {"vanguard": [{"verb": "taunt", "args": {"area": true}}, {"verb": "skill", "args": {"skill": "war_cry"}}, {"verb": "attack", "args": {"target": "$target"}}],
			"any": [{"verb": "attack", "args": {"target": "ally:$vanguard"}}]}},
	{"id": "pick_off_wounded", "name": "Pick Off the Wounded", "desc": "Finish the most damaged enemies first, one each.",
		"aliases": ["pick off", "finish the wounded", "clean up", "cleanup", "finish them off", "execute the weak", "kill the weak ones"],
		"roles": {"any": [{"verb": "attack", "args": {"target": "$weakest_distinct"}}]}},
	{"id": "casters_first", "name": "Casters First", "desc": "Kill ranged casters before anything else.",
		"aliases": ["casters first", "kill the casters", "kill the mages", "ranged first", "take out the caster", "priority casters"],
		"roles": {"any": [{"verb": "attack", "args": {"target": "caster"}}]}},
	{"id": "protect_the_weak", "name": "Protect the Weak", "desc": "Vanguard bodyguards whoever is lowest on health, artillery wards and heals them, the skirmisher peels enemies off them.",
		"aliases": ["protect the weak", "protect the wounded", "save them", "cover the wounded", "keep them alive"],
		"roles": {"vanguard": [{"verb": "bodyguard", "args": {"target": "$weakest_friend"}}],
			"artillery": [{"verb": "skill", "args": {"skill": "mirror_ward", "target": "$weakest_friend"}}, {"verb": "skill", "args": {"skill": "mending_light", "target": "$weakest_friend"}}],
			"any": [{"verb": "peel", "args": {}}]}},
	{"id": "bait_and_ambush", "name": "Bait and Ambush", "desc": "The skirmisher drags the target back to the squad, which lies in wait and springs together.",
		"aliases": ["bait and ambush", "ambush", "bait them", "lure them to us", "set a trap", "lie in wait"],
		"roles": {"skirmisher": [{"verb": "kite", "args": {"target": "$target"}}],
			"any": [{"verb": "ambush", "args": {"spot": "$player_spot", "radius": 4.5}}]}},
	{"id": "guerrilla", "name": "Guerrilla", "desc": "Everyone hit-and-runs a different enemy: strike, sprint out, repeat.",
		"aliases": ["guerrilla", "guerilla", "harass them all", "skirmish", "poke and run", "hit and fade"],
		"roles": {"any": [{"verb": "hit_and_run", "args": {"target": "$distinct"}}]}},
	{"id": "crowd_control", "name": "Crowd Control", "desc": "Stun-lock: vanguard Ground Breaker, artillery Chain Arc, skirmisher Flurry on whatever is stunned.",
		"aliases": ["crowd control", "stun them", "stun lock", "lock them down", "cc them", "keep them down"],
		"roles": {"vanguard": [{"verb": "skill", "args": {"skill": "ground_breaker"}}, {"verb": "attack", "args": {"target": "$target"}}],
			"artillery": [{"verb": "skill", "args": {"skill": "chain_arc", "target": "$target"}}, {"verb": "overwatch", "args": {}}],
			"skirmisher": [{"verb": "skill", "args": {"skill": "flurry", "target": "$target"}}, {"verb": "attack", "args": {"target": "$target"}}],
			"any": [{"verb": "attack", "args": {"target": "$target"}}]}},
	{"id": "overwatch", "name": "Overwatch", "desc": "Artillery hangs back and bombards clusters; the others stay on the player and engage freely.",
		"aliases": ["overwatch", "cover us from range", "artillery support", "stay back and shoot", "support fire"],
		"roles": {"artillery": [{"verb": "overwatch", "args": {}}], "any": [{"verb": "follow", "args": {}}]}},
	{"id": "escort", "name": "Escort", "desc": "Everyone bodyguards the player in a tight ring.",
		"aliases": ["escort", "escort me", "everyone protect me", "ring around me", "close protection", "guard me all"],
		"roles": {"any": [{"verb": "bodyguard", "args": {"target": "player"}}]}},
	{"id": "retreat_and_regroup", "name": "Retreat and Regroup", "desc": "Fall back behind the player and heal up before re-engaging.",
		"aliases": ["retreat and regroup", "regroup and heal", "fall back and heal", "tactical retreat", "pull back"],
		"roles": {"artillery": [{"verb": "skill", "args": {"skill": "mending_light", "target": "$weakest_friend"}}, {"verb": "retreat", "args": {}}],
			"any": [{"verb": "retreat", "args": {}}]}},
	{"id": "distract_and_backstab", "name": "Distract and Backstab", "desc": "Vanguard taunts the target to turn it away, the skirmisher Shadowsteps into its back, artillery Chain Arcs it.",
		"aliases": ["distract and backstab", "backstab it", "distract it", "stab it in the back", "get behind it"],
		"roles": {"vanguard": [{"verb": "taunt", "args": {"target": "$target"}}, {"verb": "attack", "args": {"target": "$target"}}],
			"skirmisher": [{"verb": "skill", "args": {"skill": "shadowstep", "target": "$target"}}, {"verb": "attack", "args": {"target": "$target"}}],
			"artillery": [{"verb": "skill", "args": {"skill": "chain_arc", "target": "$target"}}, {"verb": "attack", "args": {"target": "$target"}}],
			"any": [{"verb": "attack", "args": {"target": "$target"}}]}},
	{"id": "kite_train", "name": "Kite Train", "desc": "The skirmisher grabs everyone's aggro and runs circles while artillery bombards and the vanguard guards the player.",
		"aliases": ["kite train", "train them", "kite them all", "run them around", "conga line"],
		"roles": {"skirmisher": [{"verb": "taunt", "args": {"area": true}}, {"verb": "kite", "args": {"target": "$target"}}],
			"artillery": [{"verb": "overwatch", "args": {}}],
			"vanguard": [{"verb": "bodyguard", "args": {"target": "player"}}],
			"any": [{"verb": "follow", "args": {}}]}},
	{"id": "berserker_rush", "name": "Berserker Rush", "desc": "War Cry, then everyone charges the biggest threat at full aggression.",
		"aliases": ["berserker rush", "charge them", "rush them", "full assault", "go berserk on"],
		"roles": {"vanguard": [{"verb": "skill", "args": {"skill": "war_cry"}}, {"verb": "attack", "args": {"target": "strongest"}}],
			"any": [{"verb": "attack", "args": {"target": "strongest"}}]}},
]


static func get_by_id(id: String) -> Dictionary:
	var k: String = id.strip_edges().to_lower().replace(" ", "_")
	for s in LIST:
		if String((s as Dictionary)["id"]) == k:
			return s as Dictionary
	for s in LIST:
		if String((s as Dictionary)["name"]).to_lower() == id.strip_edges().to_lower():
			return s as Dictionary
	return {}


## Longest alias contained in `text` (so "hold the line" beats "hold").
static func match_text(text: String) -> Dictionary:
	var t: String = " " + text.to_lower() + " "
	var best: Dictionary = {}
	var best_len: int = 0
	for s in LIST:
		for a in ((s as Dictionary)["aliases"] as Array):
			var al: String = String(a)
			if al.length() > best_len and t.contains(al):
				best = s as Dictionary
				best_len = al.length()
	return best


static func describe_all() -> String:
	var rows: PackedStringArray = []
	for s in LIST:
		rows.append("- %s (%s): %s" % [s["id"], s["name"], s["desc"]])
	return "\n".join(rows)


static func ids() -> Array[String]:
	var out: Array[String] = []
	for s in LIST:
		out.append(String((s as Dictionary)["id"]))
	return out
