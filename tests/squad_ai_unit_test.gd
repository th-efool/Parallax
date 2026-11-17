extends SceneTree
## Headless unit tests for the Squad AI plugin (no network needed):
##  1. SSE stream parsing with two PARALLEL tool calls split across chunks + text deltas.
##  2. Tool call -> squad command mapping.
##  3. Offline keyword parser coverage.
##  4. API failure path: bogus key + closed local port -> notification + offline fallback, no crash.
## Usage: godot --headless --path . -s res://tests/squad_ai_unit_test.gd

var _fails: int = 0
var _checks: int = 0


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[unit] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		print("[unit] WATCHDOG")
		quit(2))
	_run()


func _run() -> void:
	# ---- 1. SSE parsing with parallel tool calls
	var client := OpenAIClient.new()
	root.add_child(client)
	var deltas: Array[String] = []
	var calls: Array = []
	var completed: Array = []
	client.text_delta.connect(func(_id: int, d: String) -> void: deltas.append(d))
	client.tool_call_received.connect(func(_id: int, n: String, a: Dictionary, cid: String) -> void: calls.append([n, a, cid]))
	client.chat_completed.connect(func(_id: int, t: String, c: Array) -> void: completed.append([t, c]))
	var j := OpenAIClient.Job.new()
	j.id = 7
	j.kind = "chat"
	j.code = 200
	var sse: String = ""
	sse += "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"Aye, \"}}]}\n\n"
	sse += "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_A\",\"type\":\"function\",\"function\":{\"name\":\"panic_order\",\"arguments\":\"{\\\"ord\"}}]}}]}\n\n"
	sse += "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":1,\"id\":\"call_B\",\"type\":\"function\",\"function\":{\"name\":\"command_allies\",\"arguments\":\"{\\\"allies\\\":[\\\"Brannoc\\\"],\"}}]}}]}\n\n"
	sse += "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"er\\\":\\\"massacre\\\"}\"}}]}}]}\n\n"
	sse += "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":1,\"function\":{\"arguments\":\"\\\"action\\\":\\\"jump\\\",\\\"count\\\":3}\"}}]}}]}\n\n"
	sse += "data: {\"choices\":[{\"delta\":{\"content\":\"no mercy.\"},\"finish_reason\":\"tool_calls\"}]}\n\n"
	sse += "data: [DONE]\n\n"
	var bytes: PackedByteArray = sse.to_utf8_buffer()
	# Feed in awkward 37-byte chunks to exercise line reassembly.
	var i: int = 0
	while i < bytes.size():
		client._consume(j, bytes.slice(i, mini(i + 37, bytes.size())))
		i += 37
	client._finish(j)
	_check("sse_text", "".join(deltas) == "Aye, no mercy.", "".join(deltas))
	_check("sse_parallel_tool_calls", calls.size() == 2, str(calls))
	if calls.size() == 2:
		_check("sse_call0", calls[0][0] == "panic_order" and (calls[0][1] as Dictionary).get("order", "") == "massacre" and calls[0][2] == "call_A")
		_check("sse_call1", calls[1][0] == "command_allies" and int((calls[1][1] as Dictionary).get("count", 0)) == 3)
	_check("sse_completed", completed.size() == 1)

	# ---- 2. Tool -> command mapping
	var m1: Dictionary = SquadComms.tool_to_command("panic_order", {"order": "ceasefire"})
	_check("map_panic", m1.get("verb", "") == "ceasefire" and (m1.get("allies", []) as Array) == ["all"], str(m1))
	var m2: Dictionary = SquadComms.tool_to_command("start_combo", {"combo": "kite_nuke", "target": "brute"})
	_check("map_combo", m2.get("verb", "") == "combo_kite_nuke" and m2.get("target", "") == "brute", str(m2))
	var m3: Dictionary = SquadComms.tool_to_command("command_allies", {"allies": "Sera", "action": "auto_engage_off"})
	_check("map_auto", m3.get("verb", "") == "auto_engage" and m3.get("enabled", true) == false and (m3.get("allies", []) as Array) == ["Sera"], str(m3))
	_check("map_unknown_tool", SquadComms.tool_to_command("launch_missiles", {}).is_empty())

	# ---- 3. Offline parser
	var names: Array = ["Brannoc", "Sera", "Ivo"]
	var cases: Array = [
		["Sera, kite the brute", "kite", ["Sera"], "brute"],
		["everyone massacre", "massacre", ["all"], ""],
		["Brannoc guard Ivo", "bodyguard", ["Brannoc"], "Ivo"],
		["cover me", "bodyguard", [], "player"],
		["kite and nuke", "combo_kite_nuke", [], ""],
		["charge and finish the caster", "combo_charge_finish", [], "caster"],
		["lure them into a trap", "combo_lure_detonate", [], ""],
		["CEASEFIRE", "ceasefire", [], ""],
		["scatter!", "scatter", [], ""],
		["revive Sera", "revive", [], "Sera"],
		["jump 3 times", "jump", [], ""],
		["Ivo dance", "dance", ["Ivo"], ""],
		["hold here", "hold", [], ""],
		["stop", "stop", [], ""],
		["split up", "split", [], ""],
		["peel it off me", "peel", [], ""],
		["Sera, hit and run the caster", "hit_and_run", ["Sera"], "caster"],
		["Ivo, attack Sera's target", "attack", ["Ivo"], "ally:Sera"],
		["Brannoc, take aggro", "taunt", ["Brannoc"], ""],
		["guard the objective", "bodyguard", [], "objective"],
		["go hunt some wildlife", "hunt", [], ""],
		["open the chest", "interact", [], "chest"],
		["smash that pillar", "destroy", [], ""],
		["Brannoc, guard me. Sera and Ivo, kite and nuke the skeleton.", "bodyguard", ["Brannoc"], "player"],
	]
	for cs in cases:
		var out: Array = SquadCommandParser.parse(String(cs[0]), names)
		var d: Dictionary = out[0] if not out.is_empty() else {}
		var ok: bool = d.get("verb", "") == cs[1] and (d.get("allies", []) as Array) == (cs[2] as Array)
		if not String(cs[3]).is_empty():
			ok = ok and String(d.get("target", "")) == String(cs[3])
		_check("parse '%s'" % cs[0], ok, str(d))
	# Natural-language parsing with live skill vocabulary (typos, skills, strategies, descriptions).
	var ctx: Dictionary = {"skills": []}
	for prof in AllySquadManager.load_profiles():
		for s in prof.get_skills():
			(ctx["skills"] as Array).append({"ally": prof.ally_name, "id": s.id, "name": s.display_name, "aliases": s.aliases})
	_check("profiles_have_skills", (ctx["skills"] as Array).size() >= 10, "%d skills" % (ctx["skills"] as Array).size())
	var nl: Array = [
		["masacre them all", "massacre", "", ""],
		["Sera smoke bomb now", "skill", "smoke_bomb", ""],
		["heal Brannoc", "skill", "mending_light", "Brannoc"],
		["Brannoc shield wall", "skill", "shield_wall", ""],
		["shield wall", "strategy", "shield_wall", ""],
		["surround the purple caster", "strategy", "surround", "desc:"],
		["kill the purple one on the left", "attack", "", "desc:"],
		["the guy with the axe!", "attack", "", "desc:"],
		["everyone gang up on E2", "strategy", "focus_fire", "desc:"],
		["Ivo zap the big green guy", "skill", "chain_arc", "desc:"],
		["hold the line", "strategy", "hold_the_line", ""],
		["divide and conquer", "strategy", "divide_and_conquer", ""],
		["sheild wall guys", "strategy", "shield_wall", ""],
	]
	for cs in nl:
		var o: Array = SquadCommandParser.parse(String(cs[0]), names, ctx)
		var d0: Dictionary = o[0] if not o.is_empty() else {}
		var ok0: bool = d0.get("verb", "") == cs[1]
		if not String(cs[2]).is_empty():
			ok0 = ok0 and (String(d0.get("skill", "")) == String(cs[2]) or String(d0.get("strategy", "")) == String(cs[2]))
		if not String(cs[3]).is_empty():
			ok0 = ok0 and String(d0.get("target", "")).begins_with(String(cs[3]))
		_check("nl '%s'" % cs[0], ok0, str(d0))
	var jump: Array = SquadCommandParser.parse("jump 3 times", names)
	_check("parse_jump_count", int((jump[0] as Dictionary).get("count", 0)) == 3)
	var multi: Array = SquadCommandParser.parse("Sera kite the brute then Ivo nuke", names)
	_check("parse_multi_clause", multi.size() == 2 and (multi[1] as Dictionary).get("verb", "") == "nuke", str(multi))
	# Chains / per-ally chains / movement / ranged / rear guard / fun / talk in ONE message.
	var big: Array = SquadCommandParser.parse("Brannoc jump twice, Sera go behind me and shoot the caster, everyone else hold the rear", names, ctx)
	var big_s: String = JSON.stringify(big)
	_check("chain_mix_size", big.size() == 4, big_s)
	if big.size() == 4:
		_check("chain_mix_brannoc", (big[0] as Dictionary)["verb"] == "jump" and int((big[0] as Dictionary)["count"]) == 2 and (big[0] as Dictionary)["allies"] == ["Brannoc"], big_s)
		_check("chain_mix_sera", (big[1] as Dictionary)["verb"] == "position" and (big[1] as Dictionary)["spot"] == "behind" and (big[2] as Dictionary)["verb"] == "ranged" and (big[2] as Dictionary)["allies"] == ["Sera"], big_s)
		_check("chain_mix_rest", (big[3] as Dictionary)["verb"] == "rearguard" and (big[3] as Dictionary)["allies"] == ["Ivo"], big_s)
	var more: Array = [
		["Ivo come in front of me", "position", ["Ivo"], "front"],
		["everyone get away from me", "position", ["all"], "far"],
		["hold the rear Brannoc", "rearguard", ["Brannoc"], ""],
		["Ivo do long distance attacks", "ranged", ["Ivo"], ""],
		["Sera circle me", "circle", ["Sera"], ""],
		["Brannoc look at me", "face", ["Brannoc"], ""],
		["Ivo do a backflip", "emote", ["Ivo"], ""],
		["Ivo tell me a joke", "chat", ["Ivo"], ""],
		["hey Sera, how's it going?", "chat", ["Sera"], ""],
	]
	for cs2 in more:
		var o2: Array = SquadCommandParser.parse(String(cs2[0]), names, ctx)
		var d2: Dictionary = o2[0] if not o2.is_empty() else {}
		var ok2: bool = d2.get("verb", "") == cs2[1] and (d2.get("allies", []) as Array) == (cs2[2] as Array)
		if not String(cs2[3]).is_empty():
			ok2 = ok2 and String(d2.get("spot", "")) == String(cs2[3])
		_check("talk '%s'" % cs2[0], ok2, str(o2))
	var dance: Array = SquadCommandParser.parse("Brannoc and Sera dance while Ivo laughs", names, ctx)
	_check("multi_ally_split", dance.size() == 2 and (dance[0] as Dictionary)["allies"] == ["Brannoc", "Sera"] and (dance[1] as Dictionary)["verb"] == "emote" and (dance[1] as Dictionary)["allies"] == ["Ivo"], str(dance))
	var wait: Array = SquadCommandParser.parse("wait 3 seconds then attack the brute", names, ctx)
	_check("wait_then", wait.size() == 2 and int((wait[0] as Dictionary).get("step_sec", 0)) == 3 and (wait[1] as Dictionary)["verb"] == "attack", str(wait))
	_check("guard_object_order", String((SquadCommandParser.parse("Brannoc guard Ivo and Sera", names)[0] as Dictionary).get("target", "")) == "Ivo")
	var m4: Dictionary = SquadComms.tool_to_command("command_allies", {"allies": ["Sera"], "action": "position", "spot": "left"})
	_check("map_position", m4.get("verb", "") == "position" and m4.get("spot", "") == "left", str(m4))
	var m5: Dictionary = SquadComms.tool_to_command("command_allies", {"allies": ["Ivo"], "action": "wait", "seconds": 4})
	_check("map_wait", m5.get("verb", "") == "hold" and int(m5.get("step_sec", 0)) == 4, str(m5))
	var bs: Array = SquadCommandParser.parse("Sera bait the brute and run in circles, Brannoc sneak attack it", names, ctx)
	_check("bait_and_sneak", bs.size() == 2 and (bs[0] as Dictionary)["verb"] == "kite" and String((bs[0] as Dictionary).get("target", "")) == "brute" \
		and (bs[1] as Dictionary)["verb"] == "surround" and (bs[1] as Dictionary).get("side", "") == "rear" and String((bs[1] as Dictionary).get("target", "")) == "brute" \
		and (bs[1] as Dictionary)["allies"] == ["Brannoc"], str(bs))
	var lure: Array = SquadCommandParser.parse("Sera lure it to us", names, ctx)
	_check("lure_to_player", not lure.is_empty() and (lure[0] as Dictionary)["verb"] == "kite" and (lure[0] as Dictionary).get("lure", "") == "player", str(lure))
	var junk: Array = SquadCommandParser.parse("make me a sandwich", names)
	_check("parse_confused", junk.size() == 1 and bool((junk[0] as Dictionary).get("confused", false)))

	# ---- 4. API failure -> offline fallback (no crash)
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await create_timer(2.0).timeout
	var title: Node = get_first_node_in_group("title_screen")
	if title != null:
		if "show_quote_on_start" in title:
			title.set("show_quote_on_start", false)
		title.call("press_start")
	await create_timer(2.0).timeout
	var comms: SquadComms = root.find_child("SquadComms", true, false) as SquadComms
	_check("comms_present", comms != null)
	if comms != null:
		var notes: Array[String] = []
		comms.notify.connect(func(t: String, lv: String) -> void: notes.append(lv + ":" + t))
		SquadAIConfig.provider_pref = "openai"
		SquadAIConfig._env_keys["openai"] = "sk-test-not-a-real-key"
		SquadAIConfig.base_url_override = "http://127.0.0.1:9/v1"
		comms.submit_utterance("everyone ceasefire", "chat")
		var t0: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 12000 and not notes.any(func(n: String) -> bool: return n.begins_with("error")):
			await process_frame
		_check("api_error_notifies", notes.any(func(n: String) -> bool: return n.begins_with("error")), str(notes))
		var mgr: AllySquadManager = AllySquadManager.instance
		var all_c: bool = mgr != null and not mgr.get_living().is_empty()
		if mgr != null:
			for a in mgr.get_living():
				all_c = all_c and a.current != null and a.current.verb == "ceasefire"
		_check("api_error_falls_back_offline", all_c)
		# System prompt carries the live roster (and updates when an ally goes down).
		var sera: SquadAlly = mgr.find_ally("Sera")
		sera.apply_damage(99999, null)
		var prompt: String = comms.build_system_prompt(mgr.find_ally("Ivo"))
		_check("prompt_live_roster", prompt.contains("Sera (skirmisher") and prompt.contains("DOWN"), "")
		SquadAIConfig.force_offline()
		SquadAIConfig.base_url_override = ""
	print("[unit] SUMMARY %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
