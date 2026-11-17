class_name AllySkill
extends Resource
## One signature skill of an ally (sub-resources inside `res://data/allies/*.tres`, `AllyProfile.skills`).
## The effect logic lives in `SquadAlly._skill_*` (one function per `effect`); everything tunable is here.
## Skills fire autonomously when `auto_use` conditions are met (off cooldown) and on command:
## "Sera, smoke bomb!", "Ivo heal Brannoc", or the Director's `use_skill` tool.

@export var id: String = "skill"
@export var display_name: String = "Skill"
@export_multiline var description: String = ""
## Phrases the offline parser recognises for this skill (lower case).
@export var aliases: Array[String] = []
## war_cry | shield_wall | ground_breaker | shadowstep | fan_of_blades | smoke_bomb | flurry |
## mending_light | mirror_ward | chain_arc | mirror_barrage
@export var effect: String = "war_cry"
## enemy | ally | self | area
@export_enum("enemy", "ally", "self", "area") var target_kind: String = "enemy"
@export var cooldown: float = 10.0
@export var cast_range: float = 8.0
@export var radius: float = 4.0
## Damage / heal / shield amount (meaning depends on effect).
@export var power: float = 20.0
@export var duration: float = 5.0
## never | swarmed | protect | cluster | ally_low | ally_pressed | self_chased_low | engaged | stunned_target
@export var auto_use: String = "never"
@export var voice_line: String = ""
@export var color: Color = Color(1.0, 0.85, 0.45)


func summary() -> String:
	return "%s (%s, %ds cd): %s" % [display_name, target_kind, int(cooldown), description]
