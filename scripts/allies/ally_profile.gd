class_name AllyProfile
extends Resource
## Data-driven definition of one squad ally ("Echo": a champion the mirror preserved, now fighting beside
## the player). `AllySquadManager` spawns one `SquadAlly` per `.tres` found in `res://data/allies/` (sorted by
## `order`), so adding a 4th ally needs only a new resource file.
##
## Roles drive which combo half an ally prefers (and how substitution picks a stand-in):
##   vanguard  : tank / bodyguard / charger      skirmisher : kiter / lurer / finisher
##   artillery : nuke / mine detonator           (any role can do a weaker version of any ability)

@export var order: int = 0
@export var ally_name: String = "Echo"
@export_enum("vanguard", "skirmisher", "artillery") var role: String = "vanguard"
@export_multiline var personality: String = "Loyal, terse, dry humour."
@export var color: Color = Color(1.0, 0.82, 0.4)

@export_group("Body")
@export_file("*.glb") var model_path: String = "res://assets/models/characters/Knight.glb"
@export var model_scale: float = 1.0
@export var keep_props: Array[String] = ["1H_Sword", "Round_Shield"]
## [source_glb, prop_name, bone] triples for rigs that ship unarmed.
@export var borrow_props: Array[String] = []
@export var tint: Color = Color(1, 1, 1, 1)

@export_group("Stats")
@export var max_health: int = 140
@export var move_speed: float = 5.6
@export var aggro_radius: float = 8.0
@export var attack_damage: int = 18
@export var attack_range: float = 1.9
@export var attack_cooldown: float = 1.0
## Health ratio below which the ally falls back to heal (disabled during MASSACRE).
@export var retreat_threshold: float = 0.3
@export var regen_per_sec: float = 3.0

@export_group("Abilities")
## Subset of: taunt, charge, bodyguard, kite, lure, nuke, mine, finisher, revive.
@export var abilities: Array[String] = ["taunt", "charge", "bodyguard", "revive"]
@export var taunt_cooldown: float = 6.0
@export var nuke_damage: int = 45
@export var nuke_radius: float = 3.6
@export var nuke_channel_sec: float = 1.4

@export_group("Voice")
## OpenAI TTS voice id (alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer, verse).
@export var tts_voice: String = "onyx"
@export var tts_instructions: String = "Gravelly, calm veteran soldier."
## event -> Array of lines. Events: ack, refuse, confused, engage, taunt, retreat, low_hp, downed, revived,
## kill, combo_ready, combo_go, massacre, ceasefire, scatter, dance, jump, idle, revive_other, mission_lock.
@export var voice_lines: Dictionary = {}


func has_ability(a: String) -> bool:
	return abilities.has(a)


func line(event: String, fallback: String = "") -> String:
	var arr: Variant = voice_lines.get(event, null)
	if arr is Array and not (arr as Array).is_empty():
		return String((arr as Array).pick_random())
	if arr is String:
		return String(arr)
	return fallback
