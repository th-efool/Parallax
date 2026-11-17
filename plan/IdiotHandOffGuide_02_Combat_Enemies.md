# IdiotHandOffGuide 02 — Warden death bug, enemy health ×2.5, Ivo as a real caster, Mirror-only phantoms

## A. Execution contract

- **Outcome:**
  - The Warden can no longer drop dead around half health. It is immune to the Execution finisher, its phase-2 hits are capped, it can't die from falling off the arena, and its death source is logged.
  - Every enemy has 2.5× health.
  - Ivo carries a crystal staff instead of a sword, fights at range with visible bolts, and his Chain Arc travels visibly from target to target.
  - "Dark" enemies (Phantom Twins) can only be hurt, and can only hurt anyone, while the player is in the Mirror (or the realms are merged). In Reality they are translucent ghosts.
- **Root:** `C:\Users\TLSB\Documents\Parallax`, branch `master`.
- **Baseline:** commit `2f37a1b` plus guide 01 if it was applied. None of the anchors here overlap guide 01's edits.
- **Shell:** PowerShell 5.1. `$g = "E:\game making workshop\Godot\Godot_v4.7.2-stable_win64_console.exe"`.
- **Readiness:** READY.
- **Before running tests:** close the Godot editor and back up the save first (G2-0).

Operational sequence:
1. Check the baseline (G2-0).
2. Apply G2-1 … G2-10 in order. Every "Replace block" must match exactly once. If one doesn't, stop the dependent steps and report the path and the mismatch.
3. Run G2-V1 … G2-V7.
4. Report as in section F. If the guide was partially applied, check each step's postcondition and resume at the first unapplied step.

### Root-cause note for the Warden ("half health, then dropped dead")
Three facts, observed in the source:
1. The Execution finisher (`fin_execution`, `execute: 0.35` in `scripts/player/player_controller.gd`) instantly kills any `EnemyBase` at or below 35 % HP, and the Warden was not excluded.
2. Once phase 2 starts (≤ 50 %), the Warden takes full damage from the player plus three allies: finishers 95–150, Sunder 120, nukes, stunned ×1.35 and Mirror ×1.25 where applicable. 50 % → 35 % then takes only a few seconds, and Execution ends it instantly.
3. Anything below y ≈ -6 is killed by `PitKillZone_World`, and phase 2 has 11 m/s lunges plus heavy knockback.

The fix covers all three: execution immunity, a per-hit cap in phase 2, and a "fell off the arena → snap home" rule. It also logs the death source, so a different cause would show up in the output.

## B. Requirements and acceptance map

| ID | Behaviour | Steps | Checks |
|---|---|---|---|
| R1 | All enemies have 2.5× their authored max health, applied once in `EnemyBase._ready()`, which covers scripted and data-driven (`.tres`) enemies alike. | G2-1 | V3, V5 |
| R2 | Warden: immune to Execution; phase 2 still triggers at 50 % of its (scaled) max HP; phase-2 damage per hit capped at 120; never dies by falling (snaps back to its home spot); prints `[Warden] defeated by '<source>' (phase N)` on death. | G2-2, G2-3, G2-4 | V3, V4 |
| R3 | Phantom Twin: in Reality it takes no damage (a cyan shimmer shows the hit passed through), never starts an attack, and its hitbox can't damage anyone. Allies ignore it as a target in Reality. In the Mirror or when merged, it behaves normally. In Reality it renders translucent. | G2-1, G2-5, G2-6, G2-7 | V3, V5 |
| R4 | Ivo has no sword; a crystal staff (gem in his colour) sits in his right hand. | G2-8, G2-9 | V6 |
| R5 | Artillery allies (Ivo) attack from 5.5–9.5 m with visible bolts instead of melee, and only swipe when cornered. Chain Arc fires visible bolts that hop between targets, with damage and stun landing on arrival. | G2-10 | V5, V6 |
| R6 | No regressions: unit 74/74, windowed squad test 53/53, feel test passes (the camera-sightline check may be flaky, as before). | all | V2, V5 |

## C. File-change manifest

| Path | Op | Step |
|---|---|---|
| `scripts/enemies/enemy_base.gd` | modify | G2-1 |
| `scripts/enemies/warden_boss.gd` | modify | G2-2 |
| `scripts/environment/pit_kill_zone.gd` | modify | G2-3 |
| `scripts/player/player_controller.gd` | modify | G2-4 |
| `scripts/core/hitbox_3d.gd` | modify | G2-5 |
| `scripts/enemies/phantom_twin.gd` | modify | G2-6 |
| `scripts/allies/squad_ally.gd` | modify | G2-7, G2-9, G2-10 |
| `data/allies/03_ivo.tres` | modify | G2-8 |
| `tests/combat_rules_test.gd` | create | G2-V4 |
| `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | modify | G2-11 |

## D. Ordered implementation steps

### G2-0 — Baseline and save backup
```powershell
git status --short
$sv = "$env:APPDATA\Godot\app_userdata\PARALLAX"; $bk = "$env:TEMP\parallax_save_bk_g2"; New-Item -ItemType Directory -Force $bk | Out-Null; Copy-Item "$sv\*.cfg" $bk -Force -ErrorAction SilentlyContinue
```
**Expected:** none of the files in section C are modified, except by guide 01. Guide 01 doesn't touch any section C file except `squad_ally.gd` (a different block) and the MEMORY files.

### G2-1 — EnemyBase: health ×2.5, execute immunity flag, "hittable now" hook
File `scripts/enemies/enemy_base.gd`.

Replace block:
```gdscript
@export_group("Stats")
@export var max_health: int = 100
@export var heavy_attack_staggers: bool = true
```
with:
```gdscript
@export_group("Stats")
@export var max_health: int = 100
@export var heavy_attack_staggers: bool = true
## Bosses: the Execution finisher (instant kill at low HP) does not apply.
@export var execute_immune: bool = false

## Global enemy durability multiplier (2026-11-18: "enemies need at least 2.5x the health"). Applied once to the
## authored max_health in _ready(), so scripted enemies and data-driven archetypes are all covered.
const HEALTH_SCALE: float = 2.5
var _health_scaled: bool = false
```
Replace block:
```gdscript
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		facing_direction = fwd.normalized()
	health = max_health
```
with:
```gdscript
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		facing_direction = fwd.normalized()
	if not _health_scaled:
		_health_scaled = true
		max_health = maxi(1, int(round(float(max_health) * HEALTH_SCALE)))
	health = max_health
```
Replace block:
```gdscript
func _modify_incoming_damage(amount: int, _is_heavy: bool, _source_type: String) -> int:
	return amount
```
with:
```gdscript
func _modify_incoming_damage(amount: int, _is_heavy: bool, _source_type: String) -> int:
	return amount


## Virtual: false while this enemy can't be hurt in the current realm (Mirror-only phantoms in Reality).
## Allies skip such targets.
func is_hittable_now() -> bool:
	return true
```
**Postcondition:** the file contains `HEALTH_SCALE: float = 2.5`, `execute_immune` and `func is_hittable_now`.

### G2-2 — Warden: relative phase threshold, hit cap, execute immunity, fall safety, death log
File `scripts/enemies/warden_boss.gd`.

Replace block:
```gdscript
@export var phase2_hp_threshold: int = 500
```
with:
```gdscript
## Legacy absolute value (kept for the inspector). Phase 2 now starts at 50 % of max_health (see
## _phase2_threshold), so the global HEALTH_SCALE can't shift it.
@export var phase2_hp_threshold: int = 500
## Phase 2: max damage a single hit can deal (stops 3 allies + finishers deleting the second half in seconds).
@export var phase2_max_hit: int = 120
```
Replace block:
```gdscript
	# The Warden has its own Mirror mechanic (chest rune) — no generic insight bonus.
	mirror_damage_mult = 1.0
```
with:
```gdscript
	# The Warden has its own Mirror mechanic (chest rune) — no generic insight bonus.
	mirror_damage_mult = 1.0
	# Never executed by the player's Execution finisher.
	execute_immune = true
```
Replace block:
```gdscript
func step_ai(delta: float) -> void:
	if is_dead:
		return
```
with:
```gdscript
func step_ai(delta: float) -> void:
	if is_dead:
		return
	# Fall safety: knockback or a lunge off the arena edge must never kill the boss (world kill plane below
	# y ~ -6). Snap back to the spawn spot instead.
	if global_position.y < get_home_position().y - 4.0:
		global_position = get_home_position()
		velocity = Vector3.ZERO
```
Replace block:
```gdscript
	if source_type == "environmental":
		return amount
	if is_vulnerable_to_full_damage():
		return amount
	return mini(amount, phase1_reality_armor_cap)
```
with:
```gdscript
	if source_type == "environmental":
		return amount
	if current_phase == Phase.PHASE_2_MERGED:
		return mini(amount, phase2_max_hit)
	if is_vulnerable_to_full_damage():
		return amount
	return mini(amount, phase1_reality_armor_cap)


func _phase2_threshold() -> int:
	return int(round(float(max_health) * 0.5))
```
Replace block:
```gdscript
	if current_phase == Phase.PHASE_1_SPLIT and health > 0 and health <= phase2_hp_threshold:
```
with:
```gdscript
	if current_phase == Phase.PHASE_1_SPLIT and health > 0 and health <= _phase2_threshold():
```
Replace block:
```gdscript
func _die(source_type: String) -> void:
	if is_chest_rune_exposed:
```
with:
```gdscript
func _die(source_type: String) -> void:
	print("[Warden] defeated by '%s' (phase %d, last attacker %s)" % [source_type, int(current_phase), str(_last_attacker)])
	if is_chest_rune_exposed:
```
**Postcondition:** the file contains `_phase2_threshold()` twice (definition and call), `execute_immune = true` and `[Warden] defeated by`.

### G2-3 — Kill planes never kill the boss
File `scripts/environment/pit_kill_zone.gd`. Replace block:
```gdscript
	if actor is EnemyBase:
		var eb: EnemyBase = actor as EnemyBase
		if eb.is_dead:
			return false
```
with:
```gdscript
	if actor is EnemyBase:
		var eb: EnemyBase = actor as EnemyBase
		if eb.is_dead:
			return false
		# Bosses are never killed by falling: put them back on their spawn spot.
		if eb is WardenBoss:
			var wb: WardenBoss = eb as WardenBoss
			wb.global_position = wb.get_home_position()
			wb.velocity = Vector3.ZERO
			return true
```

### G2-4 — Execution respects immunity
File `scripts/player/player_controller.gd`. Replace block:
```gdscript
		if float(eb.health) <= float(eb.max_health) * float(current_attack["execute"]):
```
with:
```gdscript
		if not eb.execute_immune and float(eb.health) <= float(eb.max_health) * float(current_attack["execute"]):
```

### G2-5 — Hitbox: an attacker may refuse a hit
File `scripts/core/hitbox_3d.gd`. Replace block:
```gdscript
	if hit_targets_this_swing.has(logical_target):
		return false
```
with:
```gdscript
	if hit_targets_this_swing.has(logical_target):
		return false
	# Owner veto (e.g. a Mirror-only phantom can't touch anyone while the player is in Reality).
	if my_owner != null and my_owner.has_method("can_damage_target") and not bool(my_owner.call("can_damage_target", logical_target)):
		return false
```

### G2-6 — Phantom Twin: Mirror-only combat, ghost in Reality
File `scripts/enemies/phantom_twin.gd`. **Replace entire file.**
- **Baseline check:** the file is 45 lines long and starts with `class_name PhantomTwin`.
- **Run:** `(Get-Content scripts/enemies/phantom_twin.gd).Count`. Expected: `45` (or 55 with trailing blank lines). If the content differs from the baseline listing (`_init` with BOTH_STATEFUL, `is_spectral`, `start_windup`, `_begin_attack_strike`), stop and report.

New full content:
```gdscript
class_name PhantomTwin
extends EnemyAI
## Hall of Echoes spectral combatant ("dark enemy"). It exists in both realms but only FIGHTS in the Mirror:
##  - Reality: translucent ghost that stalks you; it can't be hurt (hits pass through with a cyan shimmer),
##    never starts an attack, and its hitbox can't damage anyone.
##  - Mirror (or realms merged): solid, hurtable and dangerous (lunge).
## Killing it in the Mirror still earns the Mirror Kill bonus.

@export var lunge_speed: float = 9.5
@export var lunge_trigger_range: float = 4.2
## Opacity loss in Reality (GeometryInstance3D.transparency on every mesh).
@export var reality_ghost_transparency: float = 0.6

var _lunge_direction: Vector3 = Vector3.FORWARD
var _shimmer_cd: int = 0


func _init() -> void:
	realm_affinity = RealmReactive.Affinity.BOTH_STATEFUL
	max_health = 80
	health = 80
	detection_range = 9.0
	attack_range = 4.2
	move_speed = 3.8
	windup_duration = 0.65
	attack_active_duration = 0.32
	recover_duration = 1.00
	attack_damage = 20
	attack_name = "phantom_lunge"
	section_id = EncounterDirector.Section.HALL_COMBAT
	encounter_id = "hall_of_echoes"
	# Spectral duelist: light on its feet, slips out of telegraphed swings.
	evade_skill = 0.7
	knockback_scale = 1.3
	ring_margin = 1.2
	flee_health_ratio = 0.25
	flee_duration = 2.2


func _ready() -> void:
	super._ready()
	call_deferred("_apply_ghost_look")


## Still a ghost: cyan ichor and spectral gibs.
func is_spectral() -> bool:
	return true


func _mirror_now() -> bool:
	var rm: RealmManager = RealmManager.instance as RealmManager
	return rm == null or rm.is_merged or rm.current_realm == RealmManager.Realm.MIRROR


func is_hittable_now() -> bool:
	return _mirror_now()


## Hitbox3D veto: in Reality the phantom's strikes pass through everyone.
func can_damage_target(_target: Node) -> bool:
	return _mirror_now()


func _modify_incoming_damage(amount: int, _is_heavy: bool, source_type: String) -> int:
	if source_type == "environmental" or _mirror_now():
		return amount
	_phase_shimmer()
	return 0


func _phase_shimmer() -> void:
	var now: int = Time.get_ticks_msec()
	if now < _shimmer_cd or not is_inside_tree():
		return
	_shimmer_cd = now + 250
	GoreFXScript.sparks(self, global_position + Vector3.UP * 1.2, Vector3.UP, Color(0.55, 0.9, 1.0), 10)


func on_realm_changed(_active_realm: int) -> void:
	_apply_ghost_look()


func _apply_ghost_look() -> void:
	if not is_inside_tree():
		return
	var vis: Node = get_node_or_null(visual_root_path)
	if vis == null:
		return
	var t: float = 0.0 if _mirror_now() else clampf(reality_ghost_transparency, 0.0, 0.95)
	for mi in vis.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).transparency = t


func start_windup(custom_windup: float = -1.0) -> void:
	if not _mirror_now():
		# A Mirror creature can't touch anyone in Reality: give the attack token back and keep stalking.
		_release_token()
		return
	var p: Node3D = _resolve_target_player()
	if p != null:
		var dir: Vector3 = p.global_position - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			_lunge_direction = dir.normalized()
	else:
		_lunge_direction = -global_transform.basis.z.normalized()
	super.start_windup(custom_windup)


func _begin_attack_strike() -> void:
	super._begin_attack_strike()
	velocity = _lunge_direction * lunge_speed
```
**Verify these exist in `scripts/enemies/enemy_ai.gd` before relying on them:** `func _release_token`, `func _resolve_target_player`, `func _begin_attack_strike`.
```powershell
Select-String -Path scripts/enemies/enemy_ai.gd -Pattern "func _release_token|func _resolve_target_player|func _begin_attack_strike"
```
**Expected:** 3 lines. If any is missing, stop and report.

### G2-7 — Allies ignore targets they can't hurt
File `scripts/allies/squad_ally.gd`. Replace block:
```gdscript
	return e != null and is_instance_valid(e) and not e.is_dead and e.is_active and e.is_inside_tree()
```
with:
```gdscript
	return e != null and is_instance_valid(e) and not e.is_dead and e.is_active and e.is_inside_tree() and e.is_hittable_now()
```

### G2-8 — Ivo drops the sword
File `data/allies/03_ivo.tres`. Replace block:
```
keep_props = Array[String](["1H_Sword"])
```
with:
```
keep_props = Array[String]([])
```
**Postcondition:** `Select-String data/allies/03_ivo.tres "keep_props"` prints `keep_props = Array[String]([])`.

### G2-9 — Crystal staff for artillery allies
File `scripts/allies/squad_ally.gd`. Replace block:
```gdscript
		if profile.tint != Color(1, 1, 1, 1):
			_tint(model, profile.tint)
	_bridge = CharacterAnimationBridge.new()
```
(Indentation matters: the first two lines are inside the model branch at 2 and 3 tabs; the `_bridge` line is at **1 tab**.)

with:
```gdscript
		if profile.tint != Color(1, 1, 1, 1):
			_tint(model, profile.tint)
		if profile.role == "artillery":
			_attach_staff(model, profile.color)
	_bridge = CharacterAnimationBridge.new()
```
Then insert this new function directly **before** the line `func _refresh_label() -> void:` (unique anchor):
```gdscript
## Artillery casters hold a crystal staff instead of a sword. It is placed exactly where the rig's (hidden)
## 1H_Sword sits, so it follows the hand with the right grip; falls back to the handslot.r bone.
const STAFF_LENGTH: float = 1.45


func _attach_staff(model: Node3D, col: Color) -> void:
	var holder: Node3D = null
	var grip := Transform3D.IDENTITY
	var sword: Node3D = model.find_child("1H_Sword", true, false) as Node3D
	if sword != null and sword.get_parent() is Node3D:
		holder = sword.get_parent() as Node3D
		grip = sword.transform
	else:
		var skels: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
		if skels.is_empty():
			return
		var skel: Skeleton3D = skels[0] as Skeleton3D
		if skel.find_bone("handslot.r") < 0:
			return
		var att := BoneAttachment3D.new()
		att.name = "CasterStaffSlot"
		att.bone_name = "handslot.r"
		skel.add_child(att)
		holder = att
	var pivot := Node3D.new()
	pivot.name = "CasterStaff"
	pivot.transform = grip
	holder.add_child(pivot)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.032
	cyl.height = STAFF_LENGTH
	cyl.radial_segments = 8
	shaft.mesh = cyl
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.24, 0.14)
	wood.roughness = 0.9
	shaft.material_override = wood
	shaft.position = Vector3(0, STAFF_LENGTH * 0.25, 0)
	pivot.add_child(shaft)
	var gem := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 10
	sm.rings = 5
	gem.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = col.lightened(0.3)
	gm.emission_enabled = true
	gm.emission = col
	gm.emission_energy_multiplier = 2.5
	gem.material_override = gm
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gem.position = Vector3(0, STAFF_LENGTH * 0.75 + 0.06, 0)
	pivot.add_child(gem)
	var glow := OmniLight3D.new()
	glow.light_color = col
	glow.light_energy = 0.7
	glow.omni_range = 2.0
	glow.position = gem.position
	pivot.add_child(glow)


```

### G2-10 — Artillery fights at range; visible Chain Arc bolts
File `scripts/allies/squad_ally.gd`.

(a) Replace block (the start of `_fight`):
```gdscript
func _fight(e: EnemyAI, delta: float) -> void:
	_engage_target = e
	_combat_quiet = 0.0
	if _hazard_dodge(delta):
		return
```
with:
```gdscript
func _fight(e: EnemyAI, delta: float) -> void:
	_engage_target = e
	_combat_quiet = 0.0
	if _hazard_dodge(delta):
		return
	# Casters fight from range with visible bolts (no sword); berserk massacre still wades in.
	if profile.role == "artillery" and not _is_massacre():
		_ranged_engage(e, delta)
		return
```
(b) Replace the body of the Chain Arc hit. Replace block:
```gdscript
	set_facing(first.global_position - global_position)
	_play(["Spellcast_Shoot", "1H_Ranged_Shoot"], 0.45, true)
	var mults: Array[float] = [1.0, 0.72, 0.5]
	_start_action("channel", 0.45, 0.2, func() -> void:
		var from: Vector3 = global_position + Vector3.UP * 1.3
		for i in range(hits.size()):
			var e: EnemyAI = hits[i]
			if not _enemy_ok(e):
				continue
			e.apply_damage(int(round(s.power * mults[i] * (1.0 + _dmg_buff))), false, "ally_skill", self)
			if not e.knockdown_immune:
				e.enter_stunned(s.duration)
			var to: Vector3 = e.global_position + Vector3.UP * 1.1
			GoreFXScript.sparks(self, to, from - to, s.color, 16)
			GoreFXScript.flash_light(self, to, s.color, 3.0, 0.15, 3.0)
			from = to)
	return true
```
with:
```gdscript
	set_facing(first.global_position - global_position)
	_play(["Spellcast_Shoot", "1H_Ranged_Shoot"], 0.45, true)
	var mults: Array[float] = [1.0, 0.72, 0.5]
	_start_action("channel", 0.45, 0.2, func() -> void:
		_chain_arc_hop(s, hits, mults, 0, global_position + Vector3.UP * 1.35 + facing_direction * 0.4))
	return true


## Chain Arc: a visible bolt flies to each target in turn; damage and stun land on arrival, then the next bolt
## jumps from that enemy to the next one.
func _chain_arc_hop(s: AllySkill, hits: Array[EnemyAI], mults: Array[float], i: int, from: Vector3) -> void:
	if i >= hits.size():
		return
	var e: EnemyAI = hits[i]
	if not _enemy_ok(e):
		_chain_arc_hop(s, hits, mults, i + 1, from)
		return
	_launch_bolt(from, e, s.color, 26.0, 0.09, func() -> void:
		if not _enemy_ok(e):
			return
		e.apply_damage(int(round(s.power * mults[i] * (1.0 + _dmg_buff))), false, "ally_skill", self)
		if not e.knockdown_immune:
			e.enter_stunned(s.duration)
		var at: Vector3 = e.global_position + Vector3.UP * 1.1
		GoreFXScript.sparks(self, at, at - from, s.color, 16)
		GoreFXScript.flash_light(self, at, s.color, 3.0, 0.15, 3.0)
		_chain_arc_hop(s, hits, mults, i + 1, at))


## Glowing projectile from `from` that homes on `target` at `speed` m/s; `on_hit` runs when it arrives.
func _launch_bolt(from: Vector3, target: Node3D, col: Color, speed: float, radius: float, on_hit: Callable) -> void:
	var host: Node = GoreFXScript.host_for(self)
	if host == null or not is_instance_valid(target):
		on_hit.call()
		return
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.radial_segments = 8
	sph.rings = 4
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col.lightened(0.35)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	mi.global_position = from
	var dur: float = clampf(from.distance_to(target.global_position + Vector3.UP) / maxf(1.0, speed), 0.06, 0.6)
	var tw := mi.create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(mi) and is_instance_valid(target):
			mi.global_position = from.lerp(target.global_position + Vector3.UP * 1.0, k), 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free()
		on_hit.call())
	GameFeelScript.play_sound(self, "whoosh_light", from, -10.0, 1.5)


## Artillery basic attack: hold 5.5-9.5 m from the target and fire bolts (_fire_bolt); back away from
## anything on us, staff-swipe only when cornered.
func _ranged_engage(e: EnemyAI, delta: float) -> void:
	var to_e: Vector3 = e.global_position - global_position
	to_e.y = 0.0
	var d: float = to_e.length()
	var close: EnemyAI = _nearest_enemy(global_position, 2.6)
	if close != null and close.get_current_target() == self:
		var away: Vector3 = global_position - close.global_position
		away.y = 0.0
		if away.length_squared() > 0.01 and _side_open(away.normalized()):
			_move_dir(away.normalized(), profile.move_speed * 1.15, delta)
			return
		if _attack_cd <= 0.0 and global_position.distance_to(close.global_position) <= profile.attack_range + 0.3:
			set_facing(close.global_position - global_position)
			_melee(close)
		else:
			_halt(delta)
		return
	if d > RANGED_MAX:
		_move_to(e.global_position - to_e.normalized() * (RANGED_MAX - 1.5), profile.move_speed, delta)
		return
	if d < RANGED_MIN and d > 0.01:
		_move_dir(-to_e.normalized(), profile.move_speed, delta)
		return
	_halt(delta)
	set_facing(to_e)
	if _attack_cd <= 0.0:
		_fire_bolt(e)
```
**Verify these symbols exist in `squad_ally.gd`:** `const RANGED_MIN`, `const RANGED_MAX`, `func _fire_bolt`, `func _nearest_enemy`, `func _side_open`, `func _move_dir`, `func _move_to`, `func _halt`, `func _melee`, `func _is_massacre`.
```powershell
Select-String -Path scripts/allies/squad_ally.gd -Pattern "const RANGED_MIN|const RANGED_MAX|func _fire_bolt|func _nearest_enemy|func _side_open|func _move_dir|func _move_to|func _halt|func _melee|func _is_massacre"
```
**Expected:** 10 lines. If any is missing, stop and report.

### G2-11 — MEMORY
Append to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`:
```markdown
- **2026-11-18 (Combat rules pass)**: Enemy HP ×2.5 (`EnemyBase.HEALTH_SCALE`); Warden immune to Execution, phase 2 at 50 % of scaled HP, phase-2 hit cap 120, never dies by falling (snaps home; kill planes skip it), logs its death source; Phantom Twins only fight in the Mirror (immune + harmless + translucent in Reality, `Hitbox3D` owner veto `can_damage_target`); Ivo carries a crystal staff, artillery fights at range with visible bolts, Chain Arc bolts hop visibly between targets.
```
In `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`, replace block:
```markdown
| **Phantom Twin** | 2 | `BOTH_STATEFUL` (was MIRROR_ONLY; still spectral blood) |
```
with:
```markdown
| **Phantom Twin** | 2 | `BOTH_STATEFUL` — fights ONLY in the Mirror (2026-11-18): immune, harmless and translucent in Reality |
```

## E. Verification and failure handling

**G2-V1 — import.** `& $g --headless --path . --import --quit`. Pass: exit code 0.

**G2-V2 — parse.**
```powershell
foreach ($f in @("scripts/enemies/enemy_base.gd","scripts/enemies/warden_boss.gd","scripts/environment/pit_kill_zone.gd","scripts/player/player_controller.gd","scripts/core/hitbox_3d.gd","scripts/enemies/phantom_twin.gd","scripts/allies/squad_ally.gd")) { $o = & $g --headless --path . --check-only -s "res://$f" 2>&1 | Out-String; if ($o -match "SCRIPT ERROR|Parse Error") { "FAIL $f"; $o } else { "ok $f" } }
```
**Pass:** every line says `ok`.

**G2-V3 — boot smoke.** `& $g --headless --path . -s res://tests/boot_smoke.gd 2>&1 | Select-String "boot_smoke|SCRIPT ERROR"`. Pass: `[boot_smoke] OK` and no SCRIPT ERROR.

**G2-V4 — combat rules test (new).** Create `tests/combat_rules_test.gd`:
```gdscript
extends SceneTree
## Headless checks for guide 02: HP x2.5, Warden execution immunity / hit cap / fall safety / phase threshold,
## Phantom Mirror-only rules. Run: godot --headless --path . -s res://tests/combat_rules_test.gd
var _results: Array[String] = []
var _main: Node = null

func _initialize() -> void:
	SquadAIConfig.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()

func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[combat] ", line)

func _run() -> void:
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	var level: Node = _main.get_node("LevelRoot")
	# HP x2.5: a fresh skeleton (authored 100) has 250.
	var sk: EnemyBase = level.call("_add_roamer", level, "skeleton", "Test_hp", Vector3(0, 0, -10), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14)) as EnemyBase
	await process_frame
	_check("hp_scaled", sk != null and sk.max_health == 250 and sk.health == 250, "max=%d" % (sk.max_health if sk != null else -1))
	# Warden rules.
	var w: WardenBoss = level.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden") as WardenBoss
	_check("warden_found", w != null)
	if w != null:
		_check("warden_hp_scaled", w.max_health == 2500, "max=%d" % w.max_health)
		_check("warden_execute_immune", w.execute_immune)
		_check("warden_phase_threshold", w._phase2_threshold() == 1250, str(w._phase2_threshold()))
		w.set_section_enabled(true)
		w.current_phase = WardenBoss.Phase.PHASE_2_MERGED
		var hp0: int = w.health
		w.apply_damage(999, true, "player_heavy", null)
		_check("warden_phase2_hit_cap", hp0 - w.health == 120, "took %d" % (hp0 - w.health))
		w.global_position = w.get_home_position() + Vector3(0, -12, 0)
		w.step_ai(0.016)
		_check("warden_fall_snaps_home", w.global_position.distance_to(w.get_home_position()) < 0.5 and not w.is_dead)
	# Phantom: immune in Reality, hittable in Mirror.
	var ph: EnemyBase = level.call("_add_roamer", level, "phantom", "Test_ph", Vector3(2, 0, -10), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14)) as EnemyBase
	await process_frame
	if ph != null:
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)
		await process_frame
		var h1: int = ph.health
		var acc_r: bool = ph.apply_damage(30, false, "player_light", null)
		_check("phantom_immune_in_reality", not acc_r and ph.health == h1 and not ph.is_hittable_now())
		_check("phantom_harmless_in_reality", not bool(ph.call("can_damage_target", get_first_node_in_group("player"))))
		RealmManager.instance.force_realm(RealmManager.Realm.MIRROR, false)
		await process_frame
		var acc_m: bool = ph.apply_damage(30, false, "player_light", null)
		_check("phantom_hurt_in_mirror", acc_m and ph.health < h1 and ph.is_hittable_now())
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)
	else:
		_check("phantom_spawned", false)
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[combat] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
```
Run:
```powershell
& $g --headless --path . -s res://tests/combat_rules_test.gd 2>&1 | Select-String "\[combat\]|SCRIPT ERROR"
```
**Pass:** `[combat] SUMMARY 11 checks, 0 failed`.
- **Check first:** `_add_roamer` with kind `"phantom"` must exist. It is used by the level builder at `Stage05` (`_add_roamer(rg, "phantom", ...)`), so it does.
- **`RealmManager.force_realm(realm, false)`:** exists (used by `encounter_director.gd`).

**G2-V5 — regressions.** Takes about 8 minutes.
```powershell
& $g --headless --path . -s res://tests/squad_ai_unit_test.gd 2>&1 | Select-String "SUMMARY"
& $g --path . -s res://tests/squad_ai_windowed_test.gd -- --shots="$env:TEMP\pshots" 2>&1 | Select-String "FAIL|SUMMARY|SCRIPT ERROR"
& $g --path . -s res://tests/feel_and_movement_test.gd -- --shots="$env:TEMP\pshots" 2>&1 | Select-String "FAIL|SUMMARY|SCRIPT ERROR"
& $g --headless --path . -s res://tests/restart_flow_test.gd 2>&1 | Select-String "restart_test"
```
**Pass:**
- unit `74 checks, 0 failed`;
- windowed `53 checks, 0 failed`;
- feel `0 failed`, or only `follow_not_blocking_camera` failing, which is a known flaky threshold;
- restart `=> PASS`.

If a windowed check fails, the most likely reason is enemies now taking 2.5× longer to die within a fixed wait. Report the check name and detail. Don't change the test without reporting it.

**G2-V6 — visual (Ivo).**
- **Setup:** in the windowed run from V5, open screenshots `$env:TEMP\pshots\14_skill_fight.png` and `15_chains.png`.
- **Pass:** Ivo (violet tint) holds a staff with a glowing gem, with no sword visible; violet bolts are in flight in at least one screenshot.
- **If the staff points sideways or into the ground:** set `pivot.rotation_degrees = Vector3(0, 0, 0)`, adjusted by 90° steps on X, in `_attach_staff` right after `pivot.transform = grip`. Report the value used.

**G2-V7 — restore save.**
```powershell
Copy-Item "$env:TEMP\parallax_save_bk_g2\savegame.cfg" "$env:APPDATA\Godot\app_userdata\PARALLAX\savegame.cfg" -Force -ErrorAction SilentlyContinue
```

**Rollback:** `git checkout -- <files in section C>`, then delete `tests/combat_rules_test.gd`.

## F. Completion report contract
Report:
- applied step IDs;
- changed files;
- each check with PASS/FAIL and its output line;
- the staff orientation outcome;
- any pre-existing failures.

**Done means:** G2-1 … G2-11 are applied and V1–V5 pass.

**Author's validation:** the anchors were checked against the baseline source. The code has not been compiled or run by the author.
