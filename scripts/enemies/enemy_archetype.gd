class_name EnemyArchetype
extends Resource
## Data-driven enemy definition consumed by `ArchetypeEnemy` (built on EnemyBase/EnemyAI) and the level builder.
## Adding a new enemy type = a new `.tres` under `res://data/enemies/` (+ an `ENEMY_ATTACK_CLIPS` row in
## `CharacterAnimationBridge` if it uses a new attack name).

## melee  : regular token-gated swing (optionally blinks behind its target first).
## bolt   : ranged caster that holds `preferred_range` and fires a dodgeable homing-less bolt.
## slam   : heavy ground slam hitting every player/ally inside `aoe_radius` (ring telegraph on the floor).
@export_enum("melee", "bolt", "slam") var attack_kind: String = "melee"

@export_group("Identity")
@export var id: String = "archetype"
@export var display_name: String = "Archetype"
@export_file("*.glb") var model_path: String = "res://assets/models/characters/Skeleton_Warrior.glb"
@export var model_scale: float = 1.0
## Albedo multiplier applied to every surface of the rig (distinguishes reused KayKit rigs).
@export var tint: Color = Color(1, 1, 1, 1)
@export var emission_tint: Color = Color(0, 0, 0, 1)
@export var hp_bar_color: Color = Color(0.95, 0.30, 0.25, 0.95)
## Hand props to keep visible (KayKit names). Empty + `borrow_props` empty => unarmed.
@export var keep_props: Array[String] = []
## [source_glb, prop_name, bone] triples flattened: ["res://...Knight.glb", "1H_Sword", "handslot.r", ...]
@export var borrow_props: Array[String] = []
@export_enum("reality", "mirror", "both") var realm: String = "reality"

@export_group("Stats")
@export var max_health: int = 100
@export var move_speed: float = 3.2
@export var detection_range: float = 9.0
@export var attack_range: float = 1.85
@export var windup_duration: float = 0.55
@export var attack_active_duration: float = 0.22
@export var recover_duration: float = 0.8
@export var stagger_duration: float = 0.65
@export var attack_damage: int = 15
@export var attack_name: String = "melee_slash"
@export var attack_lunge_speed: float = 3.2
@export var evade_skill: float = 0.45
@export var knockback_scale: float = 1.0
@export var max_flinch_chain: int = 2
@export var flinch_on_light_hits: bool = true
@export var heavy_attack_staggers: bool = true
@export var knockdown_immune: bool = false

@export_group("Aggro")
@export var flee_health_ratio: float = 0.0
@export var flee_duration: float = 3.0
@export var threat_decay_per_sec: float = 0.10
@export var max_chase_distance: float = 22.0
@export var patrol_radius: float = 2.0
@export var ring_margin: float = 1.7

@export_group("Kind-specific")
## bolt: distance the caster tries to keep from its target.
@export var preferred_range: float = 7.0
@export var bolt_speed: float = 11.0
@export var bolt_color: Color = Color(0.75, 0.35, 1.0)
## slam: radius of the ground slam.
@export var aoe_radius: float = 3.0
## melee: blink behind the target when a token is granted (0 disables).
@export var blink_cooldown: float = 0.0
@export var backstab_bonus_mult: float = 1.0
