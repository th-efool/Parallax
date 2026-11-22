class_name SquadCommand
extends RefCounted
## One squad order. Created from an LLM tool call or the offline keyword parser — both produce the same
## Dictionary schema, so typed chat and voice give identical outcomes:
##   { "verb": String, "allies": Array[String] ("all" or ally names), "target": String, "count": int,
##     "text": String, "enabled": bool }
##
## Priority: PANIC (massacre / ceasefire / scatter) always wins; MISSION commands lock the ally (lower or
## equal priority orders queue behind them); ORDER stances replace each other; equal-priority finite
## commands queue.

enum Priority { AUTO = 0, ORDER = 1, MISSION = 2, PANIC = 3 }

## verb -> [priority, finite(completes on its own), is_stance]
const VERBS: Dictionary = {
	"follow": [Priority.ORDER, false, true],
	"hold": [Priority.ORDER, false, true],
	"advance": [Priority.ORDER, false, true],     # sprint to marked location / ahead (bypassing front distractions), then engage & hold
	"pull": [Priority.MISSION, true, false],      # bypass front enemies -> sprint to marked area -> taunt -> drag enemies back to player
	"distract": [Priority.MISSION, false, true],  # bypass front enemies -> sprint to marked area -> taunt & kite enemies away from player
	"flank": [Priority.ORDER, true, false],       # bypass front enemies -> wide lateral route -> strike marked area / target from behind
	"attack": [Priority.ORDER, true, false],
	"retreat": [Priority.ORDER, false, true],
	"auto_engage": [Priority.ORDER, true, false],
	"taunt": [Priority.ORDER, true, false],
	"jump": [Priority.ORDER, true, false],
	"dance": [Priority.ORDER, true, false],
	"emote": [Priority.ORDER, true, false],
	"say": [Priority.ORDER, true, false],
	"status": [Priority.ORDER, true, false],
	"stop": [Priority.ORDER, true, false],
	"split": [Priority.ORDER, false, true],
	"hit_and_run": [Priority.ORDER, true, false],
	"hunt": [Priority.ORDER, true, false],
	"destroy": [Priority.ORDER, true, false],
	"interact": [Priority.ORDER, true, false],
	"peel": [Priority.MISSION, true, false],
	"skill": [Priority.ORDER, true, false],
	"surround": [Priority.ORDER, true, false],
	"overwatch": [Priority.ORDER, false, true],
	"ambush": [Priority.MISSION, true, false],
	"strategy": [Priority.ORDER, true, false],
	"bodyguard": [Priority.MISSION, false, false],
	"kite": [Priority.MISSION, true, false],
	"nuke": [Priority.MISSION, true, false],
	"revive": [Priority.MISSION, true, false],
	"combo_kite_nuke": [Priority.MISSION, true, false],
	"combo_charge_finish": [Priority.MISSION, true, false],
	"combo_lure_detonate": [Priority.MISSION, true, false],
	"position": [Priority.ORDER, false, true],    # stand behind / in front / left / right / close / far
	"rearguard": [Priority.ORDER, false, true],   # hold the rear: trail behind facing back, intercept from behind
	"ranged": [Priority.ORDER, true, false],      # attack from 6-9 m with thrown / cast bolts
	"circle": [Priority.ORDER, true, false],      # run laps around the player (fun)
	"face": [Priority.ORDER, true, false],        # look at the player
	"chat": [Priority.ORDER, true, false],        # small talk (answered by the manager, no movement)
	"massacre": [Priority.PANIC, false, true],
	"ceasefire": [Priority.PANIC, false, true],
	"scatter": [Priority.PANIC, true, false],
}

const MAX_JUMPS: int = 12

var verb: String = "follow"
var args: Dictionary = {}
var priority: int = Priority.ORDER
var finite: bool = false
var stance: bool = false
var issued_ms: int = 0
var source: String = "chat"      # chat | voice | llm | auto
var combo_id: int = 0            # >0 when part of a two-ally handshake combo
var combo_part: String = ""      # e.g. "kiter" / "nuker"
var done: bool = false
var step: String = ""            # phased-tactic step (approach / provoke / sustain / ...)
var timer: float = 0.0
var data: Dictionary = {}        # per-execution scratch


static func is_known_verb(v: String) -> bool:
	return VERBS.has(v)


static func make(v: String, a: Dictionary = {}, src: String = "chat") -> SquadCommand:
	var c := SquadCommand.new()
	c.verb = v if VERBS.has(v) else "say"
	var spec: Array = VERBS.get(c.verb, [Priority.ORDER, true, false]) as Array
	c.priority = int(spec[0])
	c.finite = bool(spec[1])
	c.stance = bool(spec[2])
	c.args = a.duplicate(true)
	c.source = src
	c.issued_ms = Time.get_ticks_msec()
	if c.verb == "jump":
		c.args["count"] = clampi(int(a.get("count", 1)), 1, MAX_JUMPS)
	return c


func clone_for(part: String) -> SquadCommand:
	var c := SquadCommand.make(verb, args, source)
	c.combo_id = combo_id
	c.combo_part = part
	return c


func is_mission() -> bool:
	return priority == Priority.MISSION


func describe() -> String:
	var t: String = String(args.get("target", ""))
	match verb:
		"jump":
			return "jump x%d" % int(args.get("count", 1))
		"bodyguard":
			return "bodyguard %s" % (t if not t.is_empty() else "player")
		"say":
			return "say \"%s\"" % String(args.get("text", "")).left(24)
		"skill":
			return "skill %s" % String(args.get("skill", "")).replace("_", " ") + ("" if t.is_empty() else " → " + t)
		"surround":
			return "flank %s" % String(args.get("side", "")) + ("" if t.is_empty() else " " + t)
		"position":
			var sp: String = String(args.get("spot", "behind"))
			return {"behind": "behind you", "front": "in front of you", "left": "on your left", "right": "on your right", "close": "stay close", "far": "keep distance"}.get(sp, sp)
		"rearguard":
			return "rear guard"
		"ranged":
			return "ranged" + ("" if t.is_empty() else " " + t)
		"circle":
			return "run circles"
		"chat":
			return "chat"
		"hold":
			if args.has("step_sec"):
				return "wait %ds" % int(args["step_sec"])
			if args.has("lane"):
				return "hold %s" % String(args["lane"])
			if args.has("label"):
				return String(args["label"])
		"advance":
			return "advance to marked spot"
	return verb.replace("_", " ") + ("" if t.is_empty() else " " + t)
