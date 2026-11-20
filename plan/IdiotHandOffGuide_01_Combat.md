# IdiotHandOffGuide 01 — Combat, Player Feel & Breakables Remediation

> **Scope**: Self-contained implementation handoff resolving all **19** combat, player-controller, feel-rig, sword-trail, hitbox, trauma, breakable-prop, and ally-sound bugs (`CMB-01` .. `CMB-19`: `2` Critical, `11` Warning, `6` Low).
> **Readiness**: `READY` (all target files, line anchors, node paths, signals, physics layers, and existing test contracts verified against the clean working tree at commit `1ca7464`).
> **Cross-Guide Application Order**: `01 -> 02 -> 03 -> 04` (apply this Guide `01` first).
> **Executor Rule**: Apply Steps 1–9 in exact order, run every verification check in Section E (`VER-01`..`VER-08`), and return the Section F completion report. Do **not** create extra `.md` files in the repo root or `MEMORY/`.

---

## A. Execution Contract

### A.1 Repository & Runtime Baseline (Observed Before Handoff)
- **Repository Root**: `D:\Desktop\Godot\parallax`
- **Branch / HEAD Commit**: `master` @ `1ca7464` (`feat(combat): implement stacked dodge consecutive chaining and execution shield piercing`)
- **Working Tree**: Clean (`nothing to commit, working tree clean`; existing untracked/modified files: none)
- **Engine Binary**: `C:/Users/agrim/.local/bin/godot.cmd` (`4.7.2.stable.official.ed1daf0bf`, Forward+, Windows 64-bit)
- **Shell**: PowerShell (Windows)
- **Author Validation Status Prior to Execution**:
  - Every defect and fix in this guide was derived by complete static source inspection across player, enemy, core, environment, ally, and test scripts, plus a baseline read-only `--check-only` parse check on `scripts/allies/squad_ally.gd` (exit `0`). **None of the patches in Section D have been applied to the workspace yet**; the executor must apply Steps 1–9 and execute Section E to verify runtime pass conditions.

### A.2 Preserved Recent Invariants & Ownership Boundaries
1. **Preserve Commit `1ca7464` / `REQ-20` / `REQ-24` Invariants**:
   - Stacked 2-charge dodge chaining (`_process_dodge_state` `t_norm > 0.45`, `start_dodge` accepting `State.DODGE`).
   - `fin_execution` (`"player_execution"`) shield piercing on `ShieldedGuard` and self-revive bypass on `SkeletonGuard`.
   - Slow passive player regen (`health_regen_seconds_to_full = 125.0`, `_health_regen_acc`).
   - Global `EnemyBase.HEALTH_SCALE = 3.25` and `EnemyAI.DAMAGE_SCALE = 1.4`.
2. **Strict File Ownership Boundaries**:
   - `scripts/player/player_controller.gd`: **ONLY combat edits**. Do **NOT** modify `respawn_at()` or `_verify_spawn_safety()` (lines `1442–1480`; owned by Guide 04).
   - `scripts/allies/squad_ally.gd`: **ONLY the 5 invalid `GameFeelScript.play_sound()` calls** at lines `:182`, `:1222`, `:1223`, `:1694`, and `:1759` (Guide 03 owns the rest of `squad_ally.gd`).
3. **Zero Unintended Artifacts**: Only the files in Section C may be modified or created (`tests/combat_bugfix_regression_test.gd` is permanent).

### A.3 Operational Sequence for the Executor
1. Confirm `git status` is clean on `master` @ `1ca7464`.
2. Apply Steps 1 through 9 in strict numerical order using the exact `Find:` -> `Replace with:` blocks (or `Create` content).
   - If any `Find:` block does not match uniquely, **STOP immediately**, do not guess or patch around it, and report the file path, step ID, and observed surrounding lines.
   - If resuming a partially applied run, verify each step's **Postcondition** from Step 1 onward and resume at the first unapplied step.
3. Run every command in Section E (`VER-01`..`VER-08`) from `D:\Desktop\Godot\parallax` in PowerShell.
4. Report the completed Section F summary.

---

## B. Requirements & Acceptance Map

### B.1 In-Scope Combat Bug Coverage (`CMB-01` .. `CMB-19`)

| Req ID | Severity | Target Location | Defect Summary & Expected Observable Behavior | Implementing Step(s) | Verification ID(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **CMB-01** | 🔴 CRIT | `scripts/player/player_controller.gd:1540, :1589` | Ground `plunge` (`F`) leaps without checking `stamina >= 50.0` or `_landing_recover_timer <= 0.0`; 0.14 s later `start_landing_attack()` fails, leaves `_pending_ground_slam = true`, and hits unconditional `return` before `move_and_slide()`, freezing the player mid-air until stamina regens to `50.0`. **Expected**: Ground `F` only leaps when `stamina >= 50.0` and `_landing_recover_timer <= 0.0`; `_pending_ground_slam` clears once `_pending_ground_slam_timer <= 0.0` (and on leaving `LOCOMOTION`), and `return` only triggers if `start_landing_attack()` returns `true`. | Step 4 (`4O`, `4P`, `4R`) | `VER-01`, `VER-02` (`cmb01`) |
| **CMB-02** | 🔴 CRIT | `scripts/environment/breakable_prop.gd:68`, `scripts/player/player_controller.gd:1321` | `CentralMirrorPlane` is in `"breakable"` with `warning_duration == 0.0`, and `trigger_break()` does not block `PropKind.CENTRAL_MIRROR_PLANE`. `F` landing slam within `2.6 m` shatters `CentralMirrorPlane` and calls `RealmManager.force_merge_realms()`, locking `Q` in Reality while `WardenBoss` stays in `PHASE_1_SPLIT`. **Expected**: `BreakableProp.trigger_break()` returns `false` for `CENTRAL_MIRROR_PLANE`, and `complete_landing_slam()` skips `CENTRAL_MIRROR_PLANE` in `"breakable"`; only `WardenBoss._trigger_phase2_transition()` (`complete_break_now()`) shatters it. | Step 3 (`3A`), Step 4 (`4A`, `4N`) | `VER-01`, `VER-02` (`cmb02`) |
| **CMB-03** | 🟡 WARN | `scripts/player/player_controller.gd:579, :833, :853` | `_update_heavy_hold()` aborts to `State.LOCOMOTION` when `ui_input_locked` becomes `true`, but `_process_attack_state()` continues running the same tick and can call `_enter_strike()` while in `LOCOMOTION`. **Expected**: `_update_heavy_hold()` zeroes horizontal velocity on `ui_input_locked` abort and `_process_attack_state()` returns immediately if `current_state` left `LIGHT_ATTACK`/`HEAVY_ATTACK`. | Step 4 (`4C`, `4F1`) | `VER-01`, `VER-02` (`cmb03`), `VER-04` |
| **CMB-04** | 🟡 WARN | `scripts/player/player_controller.gd:891` | Attack dodge-cancel in `_process_attack_state()` calls `_abort_attack()` and `_set_state(State.LOCOMOTION, 0.0)` without checking `_dodge_charges > 0` or air-dash availability, letting 0-charge dodges free-cancel attack recovery (and leak finisher invulnerability). **Expected**: `_can_dodge_from(true)` verifies `_dodge_charges > 0` and air-dash availability before aborting the attack or consuming the buffer. | Step 4 (`4F3`, `4M`) | `VER-01`, `VER-02` (`cmb04`), `VER-04` |
| **CMB-05** | 🟡 WARN | `scripts/player/player_controller.gd:929` | `_enter_strike()` (and multi-hit re-arm at `:870`) passes `"player_heavy"` for `fin_sunder`, never matching `EnemyAI.KNOCKDOWN_SOURCES` (`"fin_sunder"`). **Expected**: `_current_swing_source_type()` returns `"player_execution"` for execution finishers, `current_attack_name` (`"fin_sunder"`, `"fin_rend"`, `"fin_phantom"`, `"fin_mirror_break"`) for other finishers, and `"player_heavy"`/`"player_light"` otherwise, so `fin_sunder` applies `STUNNED` (`1.6 s`, `1.35x` dmg). | Step 4 (`4F2`, `4F4`) | `VER-01`, `VER-02` (`cmb05`) |
| **CMB-06** | 🟡 WARN | `scripts/player/player_controller.gd:1024` | `_acquire_target()` omits `not e.is_hittable_now()`, causing melee magnetism to lock onto Reality-immune `PhantomTwin`s instead of hittable targets. **Expected**: `_acquire_target()` skips enemies where `not e.is_hittable_now()`. | Step 4 (`4G`) | `VER-01`, `VER-02` (`cmb06`), `VER-03` |
| **CMB-07** | 🟡 WARN | `scripts/player/player_controller.gd:967, :1060` | `_abort_attack()` never clears `current_attack`, and `_on_sword_hit_landed()` checks `current_attack.has("execute")` without checking `source_type == "player_execution"`, letting later `player_landing` slams (`F`) inherit stale `execute = 0.35`. **Expected**: `_abort_attack()` resets `current_attack = {}` (preserving `current_attack_name` for `light_rise`/`light_5` post-checks) and `_on_sword_hit_landed()` gates execution on `source_type == "player_execution"`. | Step 4 (`4F5`, `4H`) | `VER-01`, `VER-02` (`cmb07`), `VER-08` |
| **CMB-08** | 🟡 WARN | `scripts/player/player_controller.gd:1090, :1236` | `ShieldedGuard._modify_incoming_damage()` returns `10` chip damage on deflected heavy, firing `hit_landed` -> `_try_open_finisher_window()`; `on_attack_deflected(true)` does not mark the swing deflected, allowing crits off Reality shields. **Expected**: Per-swing `_was_deflected` flag is reset in `_begin_attack()`/`_abort_attack()`, set in `on_attack_deflected()`, and blocks `_try_open_finisher_window()`. | Step 4 (`4B`, `4E`, `4F5`, `4I`, `4L`) | `VER-01`, `VER-02` (`cmb08`) |
| **CMB-09** | 🟡 WARN | `scripts/player/player_controller.gd:1112, :1141` | `open_finisher_window()` does not clear `_buffer_action`/`_buffer_timer`, so pre-crit buffered inputs auto-fire a finisher ~16 ms later before the prompt is readable. **Expected**: `open_finisher_window()` calls `_consume_buffer()` on entry so only post-window inputs trigger finishers. | Step 4 (`4J`) | `VER-01`, `VER-02` (`cmb09`), `VER-08` |
| **CMB-10** | 🟡 WARN | `scripts/player/player_controller.gd:1173` | `fin_phantom` blinks using only a horizontal ray on hardcoded mask `0b11100` (ignores `LAYER_PLAYER_BLOCKER` and active realm) and performs no downward floor check, teleporting over open pits. **Expected**: `_resolve_phantom_blink_dest()` uses `wall_mask = world_mask \| LAYER_PLAYER_BLOCKER` (respecting active realm) and verifies solid floor beneath `dest` via `world_mask` downward raycast, skipping teleport if no floor exists. | Step 4 (`4K`) | `VER-01`, `VER-02` (`cmb10`) |
| **CMB-11** | 🟡 WARN | `scripts/player/player_controller.gd:967, :1197` | `start_finisher()` clears invulnerability via unpausable real-time `create_timer(total * 0.8, true, false, true)` while `_process_attack_state()` runs on pausable scaled time, and `_abort_attack()` never clears `Hurtbox3D.is_invulnerable`. **Expected**: `_finisher_invuln_timer` ticks in `_process_attack_state(delta)` (pausable, scaled time), `is_invulnerable()` checks `_finisher_invuln_timer > 0.0`, and `_finish_attack_cleanup()`/`_abort_attack()` clear `_finisher_invuln_timer` and `Hurtbox3D.is_invulnerable`. | Step 4 (`4B`, `4D`, `4F1`, `4F5`, `4K`) | `VER-01`, `VER-02` (`cmb11`) |
| **CMB-12** | 🟡 WARN | `scripts/player/player_controller.gd:1262, :1267, :1667` | `start_dodge()` decrements `_dodge_charges -= 1` and arms cooldown before checking air-dash rejection, burning charges without dodging; `_process_dodge_state()` calls `_update_hurtbox_invulnerability(false)` before `start_dodge()`, creating a 1-frame i-frame gap on rejected mid-air chains. **Expected**: `start_dodge()` checks `_can_dodge_from(false)` before mutating `_dodge_charges` or `_dodge_cooldown_timer`, and `_process_dodge_state()` only consumes the buffer once `start_dodge()` returns `true` (removing pre-clear). | Step 4 (`4M`, `4Q1`, `4Q2`) | `VER-01`, `VER-02` (`cmb12`), `VER-04` |
| **CMB-13** | 🟡 WARN | `scripts/player/player_feel_rig.gd:94, :188` | `_ready()` caches `_base_fov = _camera.fov` (`65.0`) before `LeaderboardStore.apply_settings()` and `_update_camera()` overwrites `_camera.fov` without listening to `LeaderboardStore.settings_changed`, reverting custom `camera_fov`. **Expected**: `PlayerFeelRig` syncs `_base_fov` and `_fov_smoothed` from `LeaderboardStore.get_settings()` in `_ready()` and listens to `LeaderboardStore.settings_changed` (disconnecting in `_exit_tree()`). | Step 6 (`6A`, `6C`) | `VER-01`, `VER-02` (`cmb13`) |
| **CMB-14** | 🔵 LOW | `scripts/allies/squad_ally.gd:182, :1222, :1223, :1694, :1759` | Calls `GameFeelScript.play_sound()` with invalid keys (`"hit_metal"`, `"glass_shatter"`, `"landing_slam"`, `"enemy_hit"`) absent from `GameFeel.get_stream()`. **Expected**: Route all 5 calls via `AudioManager.instance.play_at()` when available, falling back to valid `GameFeel` keys (`"clang"`, `"land_heavy"`, `"slash_flesh"`). | Step 7 (`7A`–`7D`) | `VER-01`, `VER-02` (`cmb14`) |
| **CMB-15** | 🔵 LOW | `scripts/core/game_feel.gd:66` | `add_trauma()` checks `rig is Node3D`, but `PlayerFeelRig` extends `Node`, so distance falloff never computes and `k` always stays `1.0`. **Expected**: Resolve `ref_node` from `rig` if `Node3D`, else `rig.get_parent()` if `Node3D`, so distant trauma attenuates over `falloff_radius`. | Step 2 | `VER-01`, `VER-02` (`cmb15`) |
| **CMB-16** | 🔵 LOW | `scripts/core/hitbox_3d.gd:120` | `try_hit_target()` only calls `RunState.register_hit()` for `"player_light"` / `"player_heavy"`, skipping `"player_execution"` and `"fin_*"`. **Expected**: Include `"player_execution"` and `source_type.begins_with("fin_")` in `register_hit()` eligibility. | Step 1 | `VER-01`, `VER-02` (`cmb16`) |
| **CMB-17** | 🔵 LOW | `scripts/environment/breakable_prop.gd:288, :294, :299, :310` | Sets `CollisionShape3D.disabled` synchronously right before `set_deferred("disabled", ...)` (causing physics-flush errors on `warning_duration == 0.0` breaks) and duplicates `hb.set_deferred("monitorable", is_intact)` at `:299`. **Expected**: Remove synchronous `.disabled = ...` assignments (`:288, :294, :310`) and duplicate `:299`, keeping only `set_deferred`. | Step 3 (`3B`) | `VER-01`, `VER-02` (`cmb17`), `VER-06` |
| **CMB-18** | 🔵 LOW | `scripts/player/player_feel_rig.gd:176` | Heavy-charge rumble sets `trauma` floor directly (`0.10 + 0.45 * charge_k * charge_k`), bypassing `_pc.camera_shake_intensity` (`0.0`). **Expected**: Multiply the charge rumble floor by `clampf(_pc.camera_shake_intensity, 0.0, 1.5)`. | Step 6 (`6B`) | `VER-01`, `VER-02` (`cmb18`) |
| **CMB-19** | 🔵 LOW | `scripts/player/sword_trail.gd:78` | Resuming `emitting` before prior `_samples` expire bridges consecutive swings or `fin_phantom` blinks in one strip. **Expected**: Split completed strokes into `_fading_strokes` on `emitting` rising edge (`false -> true`) and on `> 2.0 m` blade tip jumps (`distance_squared_to > 4.0`), plus call `split_stroke()` on new attack start in `PlayerFeelRig._on_attack_started()`. | Step 5, Step 6 (`6D`) | `VER-01`, `VER-02` (`cmb19`) |

### B.2 Out-of-Scope Cross-References (Deferred to Later Guides)
- **Additional Invalid `GameFeelScript.play_sound()` Calls Outside Owned Scope**:
  - `scripts/allies/squad_ally.gd:2801` (`"enemy_hit"`), `:2987` (`"enemy_hit"`), `:3031` (`"hit_metal"`) -> Owned by **Guide 03** (only lines `:182, :1222, :1223, :1694, :1759` are in Guide 01 scope).
  - `scripts/enemies/archetype_enemy.gd:217, :261` (`"mirror_whisper"`), `:270` (`"landing_slam"`) -> Owned by **Guide 02**.
- **Player Spawn / Respawn Safety**:
  - `scripts/player/player_controller.gd:1442–1480` (`respawn_at()`, `_verify_spawn_safety()`) -> Owned by **Guide 04**.

---

## C. File-Change Manifest

| File Path (Relative to Repo Root) | Operation | Step ID(s) | Summary & Ownership Note |
| :--- | :--- | :--- | :--- |
| `scripts/core/hitbox_3d.gd` | `modify` | Step 1 | Register combo hits for `"player_execution"` and `"fin_*"` (`CMB-16`). |
| `scripts/core/game_feel.gd` | `modify` | Step 2 | Resolve parent `Node3D` position for distance trauma falloff on `Node` camera rigs (`CMB-15`). |
| `scripts/environment/breakable_prop.gd` | `modify` | Step 3 | Reject `CENTRAL_MIRROR_PLANE` in `trigger_break()` (`CMB-02`); remove sync `.disabled` writes and duplicate `set_deferred` (`CMB-17`). |
| `scripts/player/player_controller.gd` | `modify` | Step 4 | Fix ground plunge stamina/freeze (`CMB-01`), mirror-plane slam filter (`CMB-02`), heavy-hold UI-lock abort (`CMB-03`), attack dodge-cancel gating (`CMB-04`), finisher source types (`CMB-05`), hittable targeting (`CMB-06`), stale attack dict / execution guard (`CMB-07`), deflected heavy no-crit (`CMB-08`), finisher buffer clear (`CMB-09`), safe `fin_phantom` blink (`CMB-10`), pausable finisher i-frames & abort cleanup (`CMB-11`), non-destructive air-dash rejection (`CMB-12`). Does **not** touch `respawn_at()` / `_verify_spawn_safety()`. |
| `scripts/player/sword_trail.gd` | `modify` | Step 5 | Separate strokes into `_fading_strokes` on `emitting` toggle and `> 2 m` tip discontinuity (`CMB-19`). |
| `scripts/player/player_feel_rig.gd` | `modify` | Step 6 | Sync `camera_fov` from `LeaderboardStore` + `settings_changed` (`CMB-13`), scale heavy-charge rumble by `camera_shake_intensity` (`CMB-18`), split trail stroke on new attack (`CMB-19`). |
| `scripts/allies/squad_ally.gd` | `modify` | Step 7 | Route ONLY lines `:182`, `:1222`, `:1223`, `:1694`, `:1759` via `AudioManager.instance.play_at()` with valid `GameFeel` fallback (`CMB-14`). |
| `tests/combat_bugfix_regression_test.gd` | `create` | Step 8 | Dedicated 19-check headless regression test covering `CMB-01`..`CMB-19` with explicit preloads. |
| `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` | `modify` | Step 9 | Sync ground plunge, finisher/deflect/blink/i-frame contracts, and `CentralMirrorPlane` protection. |
| `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | `modify` | Step 9 | Append one dated changelog line (`AGENTS.md` Rule 1.3). |

---

## D. Ordered Implementation Steps

### Step 1 — Register Combo Hits for Execution & Finishers (`CMB-16`)

- **Prerequisites**: Baseline verified.
- **Postcondition**: `Hitbox3D.try_hit_target()` calls `RunState.register_hit()` when hitting active enemies with `"player_light"`, `"player_heavy"`, `"player_execution"`, or `"fin_*"`.

**Target:** `scripts/core/hitbox_3d.gd`
**Action:** Replace block
**Find:**
```gdscript
	if register_combo_on_enemy_hit and is_target_enemy and (source_type == "player_light" or source_type == "player_heavy"):
		var run_state: Node = _get_run_state()
		if run_state != null and run_state.has_method("register_hit"):
			run_state.call("register_hit")
```
**Replace with:**
```gdscript
	var is_player_combo_source: bool = (
		source_type == "player_light"
		or source_type == "player_heavy"
		or source_type == "player_execution"
		or source_type.begins_with("fin_")
	)
	if register_combo_on_enemy_hit and is_target_enemy and is_player_combo_source:
		var run_state: Node = _get_run_state()
		if run_state != null and run_state.has_method("register_hit"):
			run_state.call("register_hit")
```

---

### Step 2 — Fix Trauma Distance Falloff for `Node` Camera Rigs (`CMB-15`)

- **Prerequisites**: Step 1 applied.
- **Postcondition**: `GameFeel.add_trauma()` resolves world position from `rig` if `Node3D`, otherwise from `rig.get_parent()` if `Node3D` inside the scene tree, attenuating distant trauma by `falloff_radius`.

**Target:** `scripts/core/game_feel.gd`
**Action:** Replace block
**Find:**
```gdscript
		var k: float = 1.0
		if world_pos is Vector3 and rig is Node3D:
			var d: float = (rig as Node3D).global_position.distance_to(world_pos as Vector3)
			k = clampf(1.0 - d / maxf(0.1, falloff_radius), 0.0, 1.0)
		if k > 0.0:
			rig.call("add_trauma", amount * k)
```
**Replace with:**
```gdscript
		var k: float = 1.0
		if world_pos is Vector3:
			var ref_node: Node3D = null
			if rig is Node3D:
				ref_node = rig as Node3D
			elif rig is Node and (rig as Node).get_parent() is Node3D:
				ref_node = (rig as Node).get_parent() as Node3D
			if ref_node != null and ref_node.is_inside_tree():
				var d: float = ref_node.global_position.distance_to(world_pos as Vector3)
				k = clampf(1.0 - d / maxf(0.1, falloff_radius), 0.0, 1.0)
		if k > 0.0:
			rig.call("add_trauma", amount * k)
```

---

### Step 3 — Protect `CentralMirrorPlane` & Defer Breakable Collider Toggles (`CMB-02`, `CMB-17`)

- **Prerequisites**: Step 2 applied.
- **Postcondition**: `BreakableProp.trigger_break()` rejects `PropKind.CENTRAL_MIRROR_PLANE`, and `_sync_visuals_and_colliders()` / `_set_debris_colliders()` only toggle `CollisionShape3D.disabled` and `Hurtbox3D.monitorable` via `set_deferred()` without duplicate calls.

#### Edit 3A — Block `trigger_break()` on `CENTRAL_MIRROR_PLANE` (`CMB-02`)

**Target:** `scripts/environment/breakable_prop.gd`
**Action:** Replace block
**Find:**
```gdscript
func trigger_break(by_heavy_attack: bool = true) -> bool:
	if current_state != PropState.INTACT:
		return false
	if require_heavy_attack and not by_heavy_attack:
		return false
```
**Replace with:**
```gdscript
func trigger_break(by_heavy_attack: bool = true) -> bool:
	if prop_kind == PropKind.CENTRAL_MIRROR_PLANE:
		return false
	if current_state != PropState.INTACT:
		return false
	if require_heavy_attack and not by_heavy_attack:
		return false
```

#### Edit 3B — Remove Synchronous `.disabled` Writes & Duplicate `set_deferred` (`CMB-17`)

**Target:** `scripts/environment/breakable_prop.gd`
**Action:** Replace block
**Find:**
```gdscript
	for child in get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			cs.disabled = not is_intact
			cs.set_deferred("disabled", not is_intact)
		elif child is StaticBody3D:
			for sub in child.get_children():
				if sub is CollisionShape3D:
					var scs: CollisionShape3D = sub as CollisionShape3D
					scs.disabled = not is_intact
					scs.set_deferred("disabled", not is_intact)
		elif child is Hurtbox3D:
			var hb: Hurtbox3D = child as Hurtbox3D
			hb.set_deferred("monitorable", is_intact)  # may run inside a physics signal flush
			hb.set_deferred("monitorable", is_intact)

	# Debris colliders living under the broken visual are solid only once the prop is broken.
	if broken_vis != null:
		_set_debris_colliders(broken_vis, not is_intact)


func _set_debris_colliders(node: Node, enabled: bool) -> void:
	for sub in node.get_children():
		if sub is CollisionShape3D:
			var cs: CollisionShape3D = sub as CollisionShape3D
			cs.disabled = not enabled
			cs.set_deferred("disabled", not enabled)
		_set_debris_colliders(sub, enabled)
```
**Replace with:**
```gdscript
	for child in get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			cs.set_deferred("disabled", not is_intact)
		elif child is StaticBody3D:
			for sub in child.get_children():
				if sub is CollisionShape3D:
					var scs: CollisionShape3D = sub as CollisionShape3D
					scs.set_deferred("disabled", not is_intact)
		elif child is Hurtbox3D:
			var hb: Hurtbox3D = child as Hurtbox3D
			hb.set_deferred("monitorable", is_intact)  # may run inside a physics signal flush

	# Debris colliders living under the broken visual are solid only once the prop is broken.
	if broken_vis != null:
		_set_debris_colliders(broken_vis, not is_intact)


func _set_debris_colliders(node: Node, enabled: bool) -> void:
	for sub in node.get_children():
		if sub is CollisionShape3D:
			var cs: CollisionShape3D = sub as CollisionShape3D
			cs.set_deferred("disabled", not enabled)
		_set_debris_colliders(sub, enabled)
```

---

### Step 4 — Fix Player Combat, Finisher, Dodge & Plunge Bugs (`CMB-01` .. `CMB-12`)

- **Prerequisites**: Steps 1–3 applied.
- **Ownership Check**: All 22 edit blocks below (`4A`–`4R`) are non-overlapping and strictly in ascending line order; none touch `respawn_at()` or `_verify_spawn_safety()` (lines `1442–1480`).
- **Postcondition**: All 12 `PlayerController` combat/plunge/dodge/finisher invariants hold cleanly without regressing stacked 2-charge dodge chaining or `fin_execution` shield piercing.

#### Edit 4A — Preload `BreakableProp` (`CMB-02`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
const PlayerFeelRigScript := preload("res://scripts/player/player_feel_rig.gd")
const FinisherFXScript := preload("res://scripts/player/finisher_fx.gd")
```
**Replace with:**
```gdscript
const PlayerFeelRigScript := preload("res://scripts/player/player_feel_rig.gd")
const FinisherFXScript := preload("res://scripts/player/finisher_fx.gd")
const BreakablePropScript := preload("res://scripts/environment/breakable_prop.gd")
```

#### Edit 4B — Add `_was_deflected` & `_finisher_invuln_timer` State Fields (`CMB-08`, `CMB-11`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
## Heavy "hold to charge" (see _update_heavy_hold). _heavy_hold is true for the whole wind-up of a plain `heavy`.
var _heavy_hold: bool = false
var _heavy_charge_t: float = 0.0
```
**Replace with:**
```gdscript
## Heavy "hold to charge" (see _update_heavy_hold). _heavy_hold is true for the whole wind-up of a plain `heavy`.
var _heavy_hold: bool = false
var _heavy_charge_t: float = 0.0
var _was_deflected: bool = false
var _finisher_invuln_timer: float = 0.0
```

#### Edit 4C — Clear Horizontal Velocity When UI Lock Aborts Heavy Hold (`CMB-03`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	if ui_input_locked:
		_abort_attack()
		_set_state(State.LOCOMOTION, 0.0)
		return false
```
**Replace with:**
```gdscript
	if ui_input_locked:
		velocity.x = 0.0
		velocity.z = 0.0
		_abort_attack()
		_set_state(State.LOCOMOTION, 0.0)
		return false
```

#### Edit 4D — Honor `_finisher_invuln_timer` in `is_invulnerable()` (`CMB-11`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func is_invulnerable() -> bool:
	var hb: Hurtbox3D = get_hurtbox()
	if hb != null and hb.is_invulnerable:
		return true
	if current_state == State.DODGE:
		return _dodge_elapsed >= dodge_iframe_start and _dodge_elapsed <= (dodge_iframe_start + dodge_iframe_duration)
	return false
```
**Replace with:**
```gdscript
func is_invulnerable() -> bool:
	var hb: Hurtbox3D = get_hurtbox()
	if hb != null and hb.is_invulnerable:
		return true
	if _finisher_invuln_timer > 0.0:
		return true
	if current_state == State.DODGE:
		return _dodge_elapsed >= dodge_iframe_start and _dodge_elapsed <= (dodge_iframe_start + dodge_iframe_duration)
	return false
```

#### Edit 4E — Reset `_was_deflected` at Start of Each Swing (`CMB-08`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	_attack_damage = damage
	_attack_heavy = heavy
	_attack_elapsed = 0.0
	_attack_hits = 0
	_multi_tick = 0
	_heavy_hold = attack_name == "heavy"
	_heavy_charge_t = 0.0
```
**Replace with:**
```gdscript
	_attack_damage = damage
	_attack_heavy = heavy
	_attack_elapsed = 0.0
	_attack_hits = 0
	_multi_tick = 0
	_was_deflected = false
	_heavy_hold = attack_name == "heavy"
	_heavy_charge_t = 0.0
```

#### Edit 4F1 — Early-Return on Heavy-Hold Abort & Tick Scaled Finisher i-Frames (`CMB-03`, `CMB-11`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	var w: float = float(current_attack.get("windup", 0.1))
	var a: float = float(current_attack.get("active", 0.1))
	var holding: bool = _update_heavy_hold(w, delta)

	# Track the magnetised target through the wind-up (souls-like "tracking" that ends at the strike).
```
**Replace with:**
```gdscript
	var w: float = float(current_attack.get("windup", 0.1))
	var a: float = float(current_attack.get("active", 0.1))
	var holding: bool = _update_heavy_hold(w, delta)
	if current_state != State.LIGHT_ATTACK and current_state != State.HEAVY_ATTACK:
		return
	if _finisher_invuln_timer > 0.0:
		_finisher_invuln_timer = maxf(0.0, _finisher_invuln_timer - delta)
		if _finisher_invuln_timer <= 0.0:
			_update_hurtbox_invulnerability(false)

	# Track the magnetised target through the wind-up (souls-like "tracking" that ends at the strike).
```

#### Edit 4F2 — Pass Finisher Source Type on Multi-Hit Re-Arm (`CMB-05`, `CMB-16`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
				if hbm != null:
					hbm.end_swing()
					hbm.begin_swing(_attack_damage, true, "player_heavy")
```
**Replace with:**
```gdscript
				if hbm != null:
					hbm.end_swing()
					hbm.begin_swing(_attack_damage, true, _current_swing_source_type())
```

#### Edit 4F3 — Gate Attack Dodge-Cancel on `_can_dodge_from(true)` (`CMB-04`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	# Cancels: dodge any time outside the strike frames, attacks/jump inside the recovery cancel window.
	if _buffer_action == "dodge" and attack_phase != AttackPhase.ACTIVE:
		_consume_buffer()
		_abort_attack()
		_set_state(State.LOCOMOTION, 0.0)
		var cancel_dir: Vector3 = _read_move_dir()
		start_dodge(cancel_dir if cancel_dir.length_squared() > 0.001 else -get_facing_direction())
		return
```
**Replace with:**
```gdscript
	# Cancels: dodge any time outside the strike frames, attacks/jump inside the recovery cancel window.
	if _buffer_action == "dodge" and attack_phase != AttackPhase.ACTIVE and _can_dodge_from(true):
		_consume_buffer()
		_abort_attack()
		_set_state(State.LOCOMOTION, 0.0)
		var cancel_dir: Vector3 = _read_move_dir()
		start_dodge(cancel_dir if cancel_dir.length_squared() > 0.001 else -get_facing_direction())
		return
```

#### Edit 4F4 — Add `_current_swing_source_type()` & Use in `_enter_strike()` (`CMB-05`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _enter_strike() -> void:
	_set_attack_phase(AttackPhase.ACTIVE)
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		var src: String = "player_heavy" if _attack_heavy else "player_light"
		if current_attack.has("execute"):
			src = "player_execution"
		hb.begin_swing(_attack_damage, _attack_heavy, src)
```
**Replace with:**
```gdscript
func _current_swing_source_type() -> String:
	if current_attack.has("execute") or current_attack_name == "fin_execution":
		return "player_execution"
	if bool(current_attack.get("finisher_move", false)):
		return current_attack_name
	return "player_heavy" if _attack_heavy else "player_light"


func _enter_strike() -> void:
	_set_attack_phase(AttackPhase.ACTIVE)
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.begin_swing(_attack_damage, _attack_heavy, _current_swing_source_type())
```

#### Edit 4F5 — Clear `current_attack`, `_was_deflected`, & Finisher i-Frames on Attack Cleanup/Abort (`CMB-07`, `CMB-08`, `CMB-11`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _finish_attack_cleanup() -> void:
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.end_swing()


func _abort_attack() -> void:
	_finish_attack_cleanup()
	_set_attack_phase(AttackPhase.NONE)
	current_target = null
	_heavy_hold = false
	_heavy_charge_t = 0.0
```
**Replace with:**
```gdscript
func _finish_attack_cleanup() -> void:
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.end_swing()
	if _finisher_invuln_timer > 0.0:
		_finisher_invuln_timer = 0.0
		if current_state != State.DODGE:
			_update_hurtbox_invulnerability(false)


func _abort_attack() -> void:
	_finish_attack_cleanup()
	_set_attack_phase(AttackPhase.NONE)
	current_attack = {}
	current_target = null
	_heavy_hold = false
	_heavy_charge_t = 0.0
	_was_deflected = false
	if current_state != State.DODGE:
		_update_hurtbox_invulnerability(false)
```

#### Edit 4G — Filter Unhittable Enemies Out of `_acquire_target()` (`CMB-06`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyBase = n as EnemyBase
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree():
			continue
```
**Replace with:**
```gdscript
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyBase = n as EnemyBase
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree() or not e.is_hittable_now():
			continue
```

#### Edit 4H — Verify `source_type == "player_execution"` Before Instant Execution (`CMB-07`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	# Execution: anything left at or below the threshold after the plunge is finished outright.
	if not killed and current_attack.has("execute") and target is EnemyBase:
```
**Replace with:**
```gdscript
	# Execution: anything left at or below the threshold after the execution strike is finished outright.
	if not killed and source_type == "player_execution" and current_attack.has("execute") and target is EnemyBase:
```

#### Edit 4I — Block Crit / Finisher Window on Deflected Hits (`CMB-08`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
## A critical hit: the chain enders (light_5 / heavy / heavy_spin) always crit; other light hits crit at `crit_chance_light`.
func _try_open_finisher_window(target: Node3D) -> void:
	if is_finisher_window_open() or Time.get_ticks_msec() < _finisher_cooldown_end_ms:
		return
```
**Replace with:**
```gdscript
## A critical hit: the chain enders (light_5 / heavy / heavy_spin) always crit; other light hits crit at `crit_chance_light`.
func _try_open_finisher_window(target: Node3D) -> void:
	if _was_deflected:
		return
	if is_finisher_window_open() or Time.get_ticks_msec() < _finisher_cooldown_end_ms:
		return
```

#### Edit 4J — Clear Pre-Crit Buffered Input in `open_finisher_window()` (`CMB-09`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func open_finisher_window(target: Node3D) -> void:
	_finisher_target = target
	_finisher_window_end_ms = Time.get_ticks_msec() + int(finisher_window_sec * 1000.0)
```
**Replace with:**
```gdscript
func open_finisher_window(target: Node3D) -> void:
	_consume_buffer()
	_finisher_target = target
	_finisher_window_end_ms = Time.get_ticks_msec() + int(finisher_window_sec * 1000.0)
```

#### Edit 4K — Safe `fin_phantom` Blink (Realm Mask + `LAYER_PLAYER_BLOCKER` + Floor Check) & Scaled Finisher i-Frame Timer (`CMB-10`, `CMB-11`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	var tgt: Node3D = _finisher_target if is_instance_valid(_finisher_target) and not (_finisher_target as EnemyBase).is_dead else null
	if def.has("blink") and tgt != null and tgt.global_position.distance_to(global_position) < 6.0:
		# Phantom Step: vanish into a mirror afterimage and reappear behind the target.
		var from: Vector3 = global_position
		var away: Vector3 = tgt.global_position - from
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.001 else get_facing_direction()
		var dest: Vector3 = tgt.global_position + away * float(def["blink"])
		dest.y = global_position.y
		# Never blink through a wall: stop short of world geometry (World_Shared/Reality/Mirror = layers 3-5).
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var probe_from: Vector3 = Vector3(tgt.global_position.x, global_position.y + 0.9, tgt.global_position.z)
		var q := PhysicsRayQueryParameters3D.create(probe_from, dest + Vector3.UP * 0.9, 0b11100)
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			dest = Vector3((hit["position"] as Vector3).x, global_position.y, (hit["position"] as Vector3).z) - away * 0.45
		FinisherFXScript.phantom_blink(self, from, dest)
		global_position = dest
		set_facing_direction(-away)
		camera_yaw = atan2(away.x, away.z)  # swing the camera round so the target stays in view
	combo_step = 0
	_combo_window_timer = 0.0
	_begin_attack(fin_name, int(def.get("damage", 60)), true, State.HEAVY_ATTACK)
	if tgt != null:
		current_target = tgt
		var to_tgt: Vector3 = tgt.global_position - global_position
		to_tgt.y = 0.0
		if to_tgt.length_squared() > 0.001:
			set_facing_direction(to_tgt)
	_finisher_target = null
	_finisher_cooldown_end_ms = Time.get_ticks_msec() + int(finisher_cooldown_sec * 1000.0)
	_update_hurtbox_invulnerability(true)
	get_tree().create_timer(get_attack_total_duration(fin_name) * 0.8, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(self) and current_state != State.DODGE:
			_update_hurtbox_invulnerability(false))
	var rs: Node = _get_run_state()
	if rs != null and rs.has_method("add_score_event"):
		rs.call("add_score_event", "finisher", true, "")
	finisher_executed.emit(fin_name)
	return true
```
**Replace with:**
```gdscript
	var tgt: Node3D = _finisher_target if is_instance_valid(_finisher_target) and not (_finisher_target as EnemyBase).is_dead else null
	if def.has("blink") and tgt != null and tgt.global_position.distance_to(global_position) < 6.0:
		# Phantom Step: vanish into a mirror afterimage and reappear behind the target on safe floor.
		var from: Vector3 = global_position
		var away: Vector3 = tgt.global_position - from
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.001 else get_facing_direction()
		var dest: Vector3 = _resolve_phantom_blink_dest(from, tgt, away, float(def["blink"]))
		if dest.distance_squared_to(from) > 0.0025:
			FinisherFXScript.phantom_blink(self, from, dest)
			global_position = dest
			set_facing_direction(-away)
			camera_yaw = atan2(away.x, away.z)  # swing the camera round so the target stays in view
	combo_step = 0
	_combo_window_timer = 0.0
	_begin_attack(fin_name, int(def.get("damage", 60)), true, State.HEAVY_ATTACK)
	if tgt != null:
		current_target = tgt
		var to_tgt: Vector3 = tgt.global_position - global_position
		to_tgt.y = 0.0
		if to_tgt.length_squared() > 0.001:
			set_facing_direction(to_tgt)
	_finisher_target = null
	_finisher_cooldown_end_ms = Time.get_ticks_msec() + int(finisher_cooldown_sec * 1000.0)
	_finisher_invuln_timer = get_attack_total_duration(fin_name) * 0.8
	_update_hurtbox_invulnerability(true)
	var rs: Node = _get_run_state()
	if rs != null and rs.has_method("add_score_event"):
		rs.call("add_score_event", "finisher", true, "")
	finisher_executed.emit(fin_name)
	return true


func _resolve_phantom_blink_dest(from: Vector3, tgt: Node3D, away: Vector3, blink_dist: float) -> Vector3:
	if not is_inside_tree() or get_world_3d() == null or get_world_3d().direct_space_state == null:
		var raw_dest: Vector3 = tgt.global_position + away * blink_dist
		raw_dest.y = from.y
		return raw_dest
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var rm: RealmManager = RealmManager.instance as RealmManager
	var world_mask: int = rm.get_realm_world_mask(rm.current_realm) if rm != null else (RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY)
	var wall_mask: int = world_mask | RealmManager.LAYER_PLAYER_BLOCKER
	var exclude: Array[RID] = [get_rid()]
	if tgt is CollisionObject3D:
		exclude.append((tgt as CollisionObject3D).get_rid())
	var ray_from: Vector3 = Vector3(from.x, from.y + 0.9, from.z)
	for d in [blink_dist, blink_dist * 0.55]:
		var cand: Vector3 = tgt.global_position + away * float(d)
		cand.y = from.y
		var q_wall := PhysicsRayQueryParameters3D.create(ray_from, cand + Vector3.UP * 0.9, wall_mask, exclude)
		var hit_wall: Dictionary = space.intersect_ray(q_wall)
		if not hit_wall.is_empty():
			var hp: Vector3 = hit_wall["position"] as Vector3
			var delta_xz := Vector2(hp.x - from.x, hp.z - from.z)
			var safe_len: float = maxf(0.0, delta_xz.length() - 0.45)
			var flat_dir: Vector3 = Vector3(delta_xz.x, 0.0, delta_xz.y).normalized() if delta_xz.length_squared() > 0.0001 else away
			cand = Vector3(from.x + flat_dir.x * safe_len, from.y, from.z + flat_dir.z * safe_len)
		var floor_origin: Vector3 = Vector3(cand.x, cand.y + 1.0, cand.z)
		var q_floor := PhysicsRayQueryParameters3D.create(floor_origin, floor_origin + Vector3.DOWN * 2.2, world_mask, exclude)
		var hit_floor: Dictionary = space.intersect_ray(q_floor)
		if not hit_floor.is_empty():
			cand.y = (hit_floor["position"] as Vector3).y
			return cand
	return from
```

#### Edit 4L — Set `_was_deflected` on Deflected Attacks (`CMB-08`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func on_attack_deflected(is_heavy: bool, _contact: Vector3 = Vector3.ZERO) -> void:
	if current_state != State.LIGHT_ATTACK and current_state != State.HEAVY_ATTACK:
		return
	if is_heavy:
```
**Replace with:**
```gdscript
func on_attack_deflected(is_heavy: bool, _contact: Vector3 = Vector3.ZERO) -> void:
	if current_state != State.LIGHT_ATTACK and current_state != State.HEAVY_ATTACK:
		return
	_was_deflected = true
	if is_heavy:
```

#### Edit 4M — Validate Air-Dash & Dodge Charges Before Consuming Charge in `start_dodge()` (`CMB-04`, `CMB-12`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func start_dodge(input_dir: Vector3 = Vector3.ZERO) -> bool:
	if _dodge_charges <= 0:
		return false
	if current_state != State.LOCOMOTION and current_state != State.DODGE:
		return false
	_dodge_charges -= 1
	if _dodge_cooldown_timer <= 0.0:
		_dodge_cooldown_timer = dodge_cooldown
	var airborne: bool = is_currently_airborne() and _coyote_timer <= 0.0
	if airborne:
		if not allow_air_dash or _air_dash_used:
			return false
		_air_dash_used = true

	if input_dir.length_squared() > 0.001:
		set_facing_direction(input_dir)
		_dodge_direction = Vector3(input_dir.x, 0.0, input_dir.z).normalized()
	else:
		_dodge_direction = get_facing_direction()
	velocity.y = 0.0 if airborne else minf(velocity.y, 0.0)
	_dodge_elapsed = 0.0
	_perfect_dodge_spent = false
	_set_state(State.DODGE, dodge_duration)
	_update_hurtbox_invulnerability(false)
	dodge_started.emit(_dodge_direction, dodge_duration)
	return true
```
**Replace with:**
```gdscript
func _can_dodge_from(allow_attack_cancel: bool = false) -> bool:
	if _dodge_charges <= 0:
		return false
	var valid_state: bool = (current_state == State.LOCOMOTION or current_state == State.DODGE)
	if allow_attack_cancel and (current_state == State.LIGHT_ATTACK or current_state == State.HEAVY_ATTACK):
		valid_state = true
	if not valid_state:
		return false
	var airborne: bool = is_currently_airborne() and _coyote_timer <= 0.0
	if airborne and (not allow_air_dash or _air_dash_used):
		return false
	return true


func start_dodge(input_dir: Vector3 = Vector3.ZERO) -> bool:
	if not _can_dodge_from(false):
		return false
	var airborne: bool = is_currently_airborne() and _coyote_timer <= 0.0
	_dodge_charges -= 1
	if _dodge_cooldown_timer <= 0.0:
		_dodge_cooldown_timer = dodge_cooldown
	if airborne:
		_air_dash_used = true

	if input_dir.length_squared() > 0.001:
		set_facing_direction(input_dir)
		_dodge_direction = Vector3(input_dir.x, 0.0, input_dir.z).normalized()
	else:
		_dodge_direction = get_facing_direction()
	velocity.y = 0.0 if airborne else minf(velocity.y, 0.0)
	_dodge_elapsed = 0.0
	_perfect_dodge_spent = false
	_set_state(State.DODGE, dodge_duration)
	_update_hurtbox_invulnerability(dodge_iframe_start <= 0.0)
	dodge_started.emit(_dodge_direction, dodge_duration)
	return true
```

#### Edit 4N — Skip `CENTRAL_MIRROR_PLANE` During `complete_landing_slam()` (`CMB-02`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
			for n in get_tree().get_nodes_in_group("breakable"):
				tree_targets.append(n)
```
**Replace with:**
```gdscript
			for n in get_tree().get_nodes_in_group("breakable"):
				if n is BreakablePropScript and (n as BreakablePropScript).prop_kind == BreakablePropScript.PropKind.CENTRAL_MIRROR_PLANE:
					continue
				tree_targets.append(n)
```

#### Edit 4O — Clear `_pending_ground_slam` Safely and Only `return` If Plunge Starts (`CMB-01`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	if _pending_ground_slam:
		_pending_ground_slam_timer = maxf(0.0, _pending_ground_slam_timer - delta)
		if _pending_ground_slam_timer <= 0.0 and is_currently_airborne():
			start_landing_attack()
			return
		elif _pending_ground_slam_timer <= 0.0:
			_pending_ground_slam = false
```
**Replace with:**
```gdscript
	if _pending_ground_slam:
		_pending_ground_slam_timer = maxf(0.0, _pending_ground_slam_timer - delta)
		if _pending_ground_slam_timer <= 0.0:
			_pending_ground_slam = false
			if is_currently_airborne() and start_landing_attack():
				return
```

#### Edit 4P — Require `stamina >= 50.0` & Recovery Clear Before Ground `plunge` Leap (`CMB-01`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	if act == "plunge":
		_consume_buffer()
		if is_currently_airborne():
			start_landing_attack()
			return
		elif on_floor:
			velocity.y = landing_leap_velocity
			_jump_held = true
			_pending_ground_slam = true
			_pending_ground_slam_timer = 0.14
			jumped.emit()
```
**Replace with:**
```gdscript
	if act == "plunge":
		_consume_buffer()
		if is_currently_airborne():
			if start_landing_attack():
				return
		elif on_floor and stamina >= 50.0 and _landing_recover_timer <= 0.0:
			velocity.y = landing_leap_velocity
			_jump_held = true
			_pending_ground_slam = true
			_pending_ground_slam_timer = 0.14
			jumped.emit()
```

#### Edit 4Q1 — Preserve Active i-Frames When Mid-Air Chained Dodge Is Rejected (`CMB-12`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	# Chained dodge: cancel into a second dodge once past the early i-frame window if charges remain.
	if t_norm > 0.45 and _buffer_action == "dodge" and _dodge_charges > 0:
		_consume_buffer()
		_update_hurtbox_invulnerability(false)
		var d_dir: Vector3 = _read_move_dir()
		start_dodge(d_dir if d_dir.length_squared() > 0.001 else _dodge_direction)
		return
```
**Replace with:**
```gdscript
	# Chained dodge: cancel into a second dodge once past the early i-frame window if charges remain.
	if t_norm > 0.45 and _buffer_action == "dodge" and _dodge_charges > 0:
		var d_dir: Vector3 = _read_move_dir()
		if start_dodge(d_dir if d_dir.length_squared() > 0.001 else _dodge_direction):
			_consume_buffer()
			return
```

#### Edit 4Q2 — Only Consume Post-Dodge Buffer If `start_dodge()` Succeeds (`CMB-12`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
		if _buffer_action == "dodge" and _dodge_charges > 0:
			_consume_buffer()
			var d_dir: Vector3 = _read_move_dir()
			start_dodge(d_dir if d_dir.length_squared() > 0.001 else _dodge_direction)
```
**Replace with:**
```gdscript
		if _buffer_action == "dodge" and _dodge_charges > 0:
			var d_dir: Vector3 = _read_move_dir()
			if start_dodge(d_dir if d_dir.length_squared() > 0.001 else _dodge_direction):
				_consume_buffer()
```

#### Edit 4R — Clear `_pending_ground_slam` When Leaving `LOCOMOTION` (`CMB-01`)

**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _set_state(next_state: State, duration: float) -> void:
	current_state = next_state
	_state_timer = duration
	if next_state != State.HEAVY_ATTACK:
		_heavy_hold = false
		_heavy_charge_t = 0.0
```
**Replace with:**
```gdscript
func _set_state(next_state: State, duration: float) -> void:
	current_state = next_state
	_state_timer = duration
	if next_state != State.LOCOMOTION:
		_pending_ground_slam = false
	if next_state != State.HEAVY_ATTACK:
		_heavy_hold = false
		_heavy_charge_t = 0.0
```

---

### Step 5 — Split `SwordTrail` Strokes Across Swings & Blinks (`CMB-19`)

- **Prerequisites**: Step 4 applied.
- **Postcondition**: Toggling `SwordTrail.emitting` back to `true` before old samples expire (or jumping `> 2.0 m` in one frame such as `fin_phantom`) separates prior samples into `_fading_strokes` drawn as independent `PRIMITIVE_TRIANGLE_STRIP` surfaces so swings/blinks never bridge in a single strip.

#### Edit 5A — Add `emitting` Setter & `_fading_strokes` Storage

**Target:** `scripts/player/sword_trail.gd`
**Action:** Replace block
**Find:**
```gdscript
var color: Color = Color(1.0, 0.7, 0.3, 1.0)
var width_boost: float = 1.0
var emitting: bool = false

var _source: Node3D = null
var _tip_local: Vector3 = Vector3(0.0, 1.0, 0.0)
var _base_local: Vector3 = Vector3.ZERO
var _samples: Array[Dictionary] = []  # {b: Vector3, t: Vector3, age: float}
var _imesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
```
**Replace with:**
```gdscript
var color: Color = Color(1.0, 0.7, 0.3, 1.0)
var width_boost: float = 1.0
var emitting: bool = false:
	set(value):
		if value == emitting:
			return
		if value:
			split_stroke()
		emitting = value

var _source: Node3D = null
var _tip_local: Vector3 = Vector3(0.0, 1.0, 0.0)
var _base_local: Vector3 = Vector3.ZERO
var _samples: Array[Dictionary] = []  # {b: Vector3, t: Vector3, age: float}
var _fading_strokes: Array[Dictionary] = []  # {samples: Array[Dictionary], color: Color, max_age: float}
var _imesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
```

#### Edit 5B — Age Independent Strokes, Split Teleport Jumps, & Draw Separate Strips

**Target:** `scripts/player/sword_trail.gd`
**Action:** Replace block
**Find:**
```gdscript
func _process(delta: float) -> void:
	for s in _samples:
		s["age"] = float(s["age"]) + delta
	while not _samples.is_empty() and float(_samples[0]["age"]) > max_age:
		_samples.pop_front()
	if emitting and has_blade():
		var xf: Transform3D = _source.global_transform
		var b: Vector3 = xf * _base_local
		var t: Vector3 = xf * _tip_local
		# Extend the ribbon a little past the blade so the arc reads at gameplay camera distance.
		t = b + (t - b) * (1.25 * width_boost)
		if _samples.is_empty() or (_samples[-1]["t"] as Vector3).distance_squared_to(t) > 0.0004:
			_samples.append({"b": b, "t": t, "age": 0.0})
	_rebuild()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	if _samples.size() < 2:
		return
	var pts_b: Array[Vector3] = []
	var pts_t: Array[Vector3] = []
	var ages: Array[float] = []
	var n: int = _samples.size()
	for i in range(n - 1):
		var p0: Dictionary = _samples[maxi(0, i - 1)]
		var p1: Dictionary = _samples[i]
		var p2: Dictionary = _samples[i + 1]
		var p3: Dictionary = _samples[mini(n - 1, i + 2)]
		var steps: int = maxi(1, subdivisions)
		for k in range(steps):
			var u: float = float(k) / steps
			pts_b.append(_catmull(p0["b"], p1["b"], p2["b"], p3["b"], u))
			pts_t.append(_catmull(p0["t"], p1["t"], p2["t"], p3["t"], u))
			ages.append(lerpf(float(p1["age"]), float(p2["age"]), u))
	pts_b.append(_samples[-1]["b"])
	pts_t.append(_samples[-1]["t"])
	ages.append(float(_samples[-1]["age"]))

	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count: int = pts_b.size()
	for i in range(count):
		var life: float = clampf(1.0 - ages[i] / maxf(0.01, max_age), 0.0, 1.0)
		var head: float = float(i) / maxf(1.0, float(count - 1))
		var a: float = life * life * (0.25 + 0.75 * head)
		# Hot white core near the blade edge, coloured body toward the base.
		var core: Color = color.lerp(Color.WHITE, 0.55 * life)
		_imesh.surface_set_color(Color(color.r, color.g, color.b, a * 0.35))
		_imesh.surface_add_vertex(pts_b[i])
		_imesh.surface_set_color(Color(core.r, core.g, core.b, a))
		_imesh.surface_add_vertex(pts_t[i])
	_imesh.surface_end()
```
**Replace with:**
```gdscript
func split_stroke() -> void:
	if _samples.size() >= 2:
		_fading_strokes.append({
			"samples": _samples.duplicate(),
			"color": color,
			"max_age": max_age,
		})
	_samples.clear()


func clear_trail() -> void:
	_samples.clear()
	_fading_strokes.clear()
	_imesh.clear_surfaces()


func _process(delta: float) -> void:
	for s in _samples:
		s["age"] = float(s["age"]) + delta
	while not _samples.is_empty() and float(_samples[0]["age"]) > max_age:
		_samples.pop_front()
	for idx in range(_fading_strokes.size() - 1, -1, -1):
		var st: Dictionary = _fading_strokes[idx]
		var arr: Array = st["samples"] as Array
		var st_max_age: float = float(st.get("max_age", max_age))
		for s in arr:
			s["age"] = float(s["age"]) + delta
		while not arr.is_empty() and float(arr[0]["age"]) > st_max_age:
			arr.pop_front()
		if arr.size() < 2:
			_fading_strokes.remove_at(idx)
	if emitting and has_blade():
		var xf: Transform3D = _source.global_transform
		var b: Vector3 = xf * _base_local
		var t: Vector3 = xf * _tip_local
		# Extend the ribbon a little past the blade so the arc reads at gameplay camera distance.
		t = b + (t - b) * (1.25 * width_boost)
		if not _samples.is_empty() and (_samples[-1]["t"] as Vector3).distance_squared_to(t) > 4.0:
			split_stroke()
		if _samples.is_empty() or (_samples[-1]["t"] as Vector3).distance_squared_to(t) > 0.0004:
			_samples.append({"b": b, "t": t, "age": 0.0})
	_rebuild()


func _rebuild() -> void:
	_imesh.clear_surfaces()
	for st in _fading_strokes:
		_draw_stroke(st["samples"] as Array, st.get("color", color) as Color, float(st.get("max_age", max_age)))
	if _samples.size() >= 2:
		_draw_stroke(_samples, color, max_age)


func _draw_stroke(samples: Array, stroke_color: Color, stroke_max_age: float) -> void:
	var n: int = samples.size()
	if n < 2:
		return
	var pts_b: Array[Vector3] = []
	var pts_t: Array[Vector3] = []
	var ages: Array[float] = []
	for i in range(n - 1):
		var p0: Dictionary = samples[maxi(0, i - 1)]
		var p1: Dictionary = samples[i]
		var p2: Dictionary = samples[i + 1]
		var p3: Dictionary = samples[mini(n - 1, i + 2)]
		var steps: int = maxi(1, subdivisions)
		for k in range(steps):
			var u: float = float(k) / steps
			pts_b.append(_catmull(p0["b"], p1["b"], p2["b"], p3["b"], u))
			pts_t.append(_catmull(p0["t"], p1["t"], p2["t"], p3["t"], u))
			ages.append(lerpf(float(p1["age"]), float(p2["age"]), u))
	pts_b.append(samples[-1]["b"])
	pts_t.append(samples[-1]["t"])
	ages.append(float(samples[-1]["age"]))

	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count: int = pts_b.size()
	for i in range(count):
		var life: float = clampf(1.0 - ages[i] / maxf(0.01, stroke_max_age), 0.0, 1.0)
		var head: float = float(i) / maxf(1.0, float(count - 1))
		var a: float = life * life * (0.25 + 0.75 * head)
		# Hot white core near the blade edge, coloured body toward the base.
		var core: Color = stroke_color.lerp(Color.WHITE, 0.55 * life)
		_imesh.surface_set_color(Color(stroke_color.r, stroke_color.g, stroke_color.b, a * 0.35))
		_imesh.surface_add_vertex(pts_b[i])
		_imesh.surface_set_color(Color(core.r, core.g, core.b, a))
		_imesh.surface_add_vertex(pts_t[i])
	_imesh.surface_end()
```

---

### Step 6 — Fix `PlayerFeelRig` Custom FOV Sync, Charge Shake Scaling & Trail Split (`CMB-13`, `CMB-18`, `CMB-19`)

- **Prerequisites**: Step 5 applied.
- **Postcondition**: `PlayerFeelRig` initializes `_base_fov` and `_fov_smoothed` from `LeaderboardStore`, updates live on `settings_changed`, scales heavy-charge rumble by `_pc.camera_shake_intensity`, and splits the sword trail when each new attack begins.

#### Edit 6A — Sync Initial FOV from `LeaderboardStore` & Connect `settings_changed` (`CMB-13`)

**Target:** `scripts/player/player_feel_rig.gd`
**Action:** Replace block
**Find:**
```gdscript
	if _pc != null:
		_smooth_y = _pc.global_position.y if _pc.is_inside_tree() else 0.0
		_prev_yaw = _pc.get_visual_yaw()
		_connect_player()
	_setup_trail.call_deferred()
```
**Replace with:**
```gdscript
	if _pc != null:
		_smooth_y = _pc.global_position.y if _pc.is_inside_tree() else 0.0
		_prev_yaw = _pc.get_visual_yaw()
		_connect_player()
	_sync_fov_from_store(true)
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null and store.has_signal("settings_changed") and not store.is_connected("settings_changed", _on_settings_changed):
			store.connect("settings_changed", _on_settings_changed)
	_setup_trail.call_deferred()


func _exit_tree() -> void:
	if get_tree() != null and get_tree().root != null:
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null and store.has_signal("settings_changed") and store.is_connected("settings_changed", _on_settings_changed):
			store.disconnect("settings_changed", _on_settings_changed)
```

#### Edit 6B — Scale Heavy-Charge Rumble by `camera_shake_intensity` (`CMB-18`)

**Target:** `scripts/player/player_feel_rig.gd`
**Action:** Replace block
**Find:**
```gdscript
	var charge_k: float = _pc.get_heavy_charge_ratio()
	if charge_k > 0.0:
		trauma = maxf(trauma, 0.10 + 0.45 * charge_k * charge_k)
```
**Replace with:**
```gdscript
	var charge_k: float = _pc.get_heavy_charge_ratio()
	if charge_k > 0.0:
		var shake_k: float = clampf(_pc.camera_shake_intensity, 0.0, 1.5)
		trauma = maxf(trauma, (0.10 + 0.45 * charge_k * charge_k) * shake_k)
```

#### Edit 6C — Add `_sync_fov_from_store()` & `_on_settings_changed()` (`CMB-13`)

**Target:** `scripts/player/player_feel_rig.gd`
**Action:** Replace block
**Find:**
```gdscript
func kick_fov(amount: float) -> void:
	_fov_kick_vel += amount * 28.0
```
**Replace with:**
```gdscript
func kick_fov(amount: float) -> void:
	_fov_kick_vel += amount * 28.0


func _sync_fov_from_store(snap: bool = false) -> void:
	if not is_inside_tree() or get_tree() == null or get_tree().root == null:
		return
	var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
	if store == null or not store.has_method("get_settings"):
		return
	var s: Dictionary = store.call("get_settings") as Dictionary
	var fov: float = clampf(float(s.get("camera_fov", _base_fov)), 55.0, 95.0)
	_base_fov = fov
	if snap:
		_fov_smoothed = fov
		if _camera != null:
			_camera.fov = clampf(fov + _fov_kick, 40.0, 110.0)


func _on_settings_changed(settings: Dictionary) -> void:
	if settings.has("camera_fov"):
		var fov: float = clampf(float(settings.get("camera_fov", 65.0)), 55.0, 95.0)
		if not is_equal_approx(_base_fov, fov):
			_base_fov = fov
			_fov_smoothed = fov
			if _camera != null:
				_camera.fov = clampf(_fov_smoothed + _fov_kick, 40.0, 110.0)
```

#### Edit 6D — Split Sword Trail When Starting a New Attack (`CMB-19`)

**Target:** `scripts/player/player_feel_rig.gd`
**Action:** Replace block
**Find:**
```gdscript
func _on_attack_started(attack_name: String, timing: Dictionary) -> void:
	if _trail != null:
		_trail.color = _realm_color()
		_trail.width_boost = float(timing.get("trail", 1.0))
		_trail.max_age = 0.12 if not attack_name.begins_with("heavy") else 0.18
```
**Replace with:**
```gdscript
func _on_attack_started(attack_name: String, timing: Dictionary) -> void:
	if _trail != null:
		_trail.split_stroke()
		_trail.color = _realm_color()
		_trail.width_boost = float(timing.get("trail", 1.0))
		_trail.max_age = 0.12 if not attack_name.begins_with("heavy") else 0.18
```

---

### Step 7 — Route the 5 Invalid `SquadAlly` Sound Calls via `AudioManager` (`CMB-14`)

- **Prerequisites**: Step 6 applied.
- **Ownership Check**: ONLY lines `:182`, `:1222`, `:1223`, `:1694`, and `:1759` in `scripts/allies/squad_ally.gd` are edited; all other `squad_ally.gd` lines remain untouched for Guide 03.
- **Postcondition**: All 5 call sites play valid `AudioManager` cue banks when `AudioManager.instance != null` and fall back to valid `GameFeel` stream keys (`"clang"`, `"land_heavy"`, `"slash_flesh"`).

#### Edit 7A — `squad_ally.gd:182` (`"hit_metal"` -> `AudioManager` / `"clang"`)

**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	GoreFXScript.sparks(self, chest, dir.normalized() if dir.length_squared() > 0.001 else Vector3.UP, Color(1.0, 0.85, 0.5), 10)
	GameFeelScript.play_sound(self, "hit_metal", chest, -8.0, 1.1)
	if health <= 0:
```
**Replace with:**
```gdscript
	GoreFXScript.sparks(self, chest, dir.normalized() if dir.length_squared() > 0.001 else Vector3.UP, Color(1.0, 0.85, 0.5), 10)
	if AudioManager.instance != null:
		AudioManager.instance.play_at("hit_metal", chest, -8.0)
	else:
		GameFeelScript.play_sound(self, "clang", chest, -8.0, 1.1)
	if health <= 0:
```

#### Edit 7B — `squad_ally.gd:1222–1223` (`"glass_shatter"`, `"landing_slam"` -> `AudioManager` / `"clang"`, `"land_heavy"`)

**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
	GoreFXScript.dust_puff(self, at, radius * 0.6, 40, Color(col.r, col.g, col.b, 0.6), 3.0)
	GameFeelScript.play_sound(self, "glass_shatter", at, 0.0, 0.8)
	GameFeelScript.play_sound(self, "landing_slam", at, -3.0, 1.2)
	GameFeelScript.add_trauma(self, 0.3, at)
```
**Replace with:**
```gdscript
	GoreFXScript.dust_puff(self, at, radius * 0.6, 40, Color(col.r, col.g, col.b, 0.6), 3.0)
	if AudioManager.instance != null:
		AudioManager.instance.play_at("glass_shatter", at, 0.0)
		AudioManager.instance.play_at("landing_slam", at, -3.0)
	else:
		GameFeelScript.play_sound(self, "clang", at, -2.0, 1.4)
		GameFeelScript.play_sound(self, "land_heavy", at, -3.0, 1.2)
	GameFeelScript.add_trauma(self, 0.3, at)
```

#### Edit 7C — `squad_ally.gd:1694` (`"landing_slam"` -> `AudioManager` / `"land_heavy"`)

**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
		GoreFXScript.dust_puff(self, global_position, s.radius * 0.6, 30)
		GameFeelScript.play_sound(self, "landing_slam", global_position, 0.0, 0.9)
		GameFeelScript.add_trauma(self, 0.3, global_position))
```
**Replace with:**
```gdscript
		GoreFXScript.dust_puff(self, global_position, s.radius * 0.6, 30)
		if AudioManager.instance != null:
			AudioManager.instance.play_at("landing_slam", global_position, 0.0)
		else:
			GameFeelScript.play_sound(self, "land_heavy", global_position, 0.0, 0.9)
		GameFeelScript.add_trauma(self, 0.3, global_position))
```

#### Edit 7D — `squad_ally.gd:1759` (`"enemy_hit"` -> `AudioManager` / `"slash_flesh"`)

**Target:** `scripts/allies/squad_ally.gd`
**Action:** Replace block
**Find:**
```gdscript
			if is_instance_valid(self) and not is_downed and _enemy_ok(e) and global_position.distance_to(e.global_position) < s.cast_range + 1.0:
				e.apply_damage(int(round(s.power * (1.0 + _dmg_buff))), false, "ally_melee", self)
				GameFeelScript.play_sound(self, "enemy_hit", e.global_position + Vector3.UP, -8.0, 1.2))
```
**Replace with:**
```gdscript
			if is_instance_valid(self) and not is_downed and _enemy_ok(e) and global_position.distance_to(e.global_position) < s.cast_range + 1.0:
				e.apply_damage(int(round(s.power * (1.0 + _dmg_buff))), false, "ally_melee", self)
				if AudioManager.instance != null:
					AudioManager.instance.play_at("enemy_hit", e.global_position + Vector3.UP, -8.0)
				else:
					GameFeelScript.play_sound(self, "slash_flesh", e.global_position + Vector3.UP, -8.0, 1.2))
```

---

### Step 8 — Create Dedicated Regression Suite `tests/combat_bugfix_regression_test.gd` (`CMB-01` .. `CMB-19`)

- **Prerequisites**: Steps 1–7 applied.
- **Precondition**: `tests/combat_bugfix_regression_test.gd` must not already exist.
- **Postcondition**: Running `godot --headless --path "D:/Desktop/Godot/parallax" -s res://tests/combat_bugfix_regression_test.gd` executes all 19 checks (`cmb01`–`cmb19`) and exits `0` with `[combat_bugfix] SUMMARY 19 checks, 0 failed`.

**Target:** `tests/combat_bugfix_regression_test.gd`
**Action:** Create
**Content:**
```gdscript
extends SceneTree
## Dedicated headless regression suite for IdiotHandOffGuide 01 (CMB-01..CMB-19).
## Run: godot --headless --path . -s res://tests/combat_bugfix_regression_test.gd

const SquadAIConfigScript := preload("res://addons/parallax_squad_ai/squad_ai_config.gd")
const RealmManagerScript := preload("res://scripts/core/realm_manager.gd")
const EncounterDirectorScript := preload("res://scripts/core/encounter_director.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const SwordTrailScript := preload("res://scripts/player/sword_trail.gd")
const BreakablePropScript := preload("res://scripts/environment/breakable_prop.gd")
const Hitbox3DScript := preload("res://scripts/core/hitbox_3d.gd")
const GameFeelScript := preload("res://scripts/core/game_feel.gd")
const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const EnemyAIScript := preload("res://scripts/enemies/enemy_ai.gd")

var _results: Array[String] = []
var _main: Node = null


func _initialize() -> void:
	SquadAIConfigScript.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("[combat_bugfix] WATCHDOG TIMEOUT")
		quit(2))
	_run()


func _check(req_id: String, ok: bool, detail: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", req_id, detail]
	_results.append(line)
	print("[combat_bugfix] ", line)


func _wait_physics(frames: int) -> void:
	for _i in range(frames):
		await physics_frame


func _settle_player(pc: Node) -> void:
	pc.call("_abort_attack")
	pc.call("_close_finisher_window", "")
	pc.call("_consume_buffer")
	pc.call("_set_state", PlayerControllerScript.State.LOCOMOTION, 0.0)
	pc.set("velocity", Vector3.ZERO)
	pc.set("_pending_ground_slam", false)
	pc.set("_landing_recover_timer", 0.0)
	pc.set("_dodge_charges", pc.get("max_dodge_charges"))
	pc.set("_dodge_cooldown_timer", 0.0)
	pc.set("_air_dash_used", false)
	pc.set("_coyote_timer", 0.0)
	pc.set("stamina", pc.get("max_stamina"))
	pc.call("set_simulated_airborne", false)
	pc.call("_update_hurtbox_invulnerability", false)
	PlayerControllerScript.ui_input_locked = false


func _run() -> void:
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await _wait_physics(4)

	var level: Node = _main.get_node("LevelRoot")
	var pc: PlayerControllerScript = get_first_node_in_group("player") as PlayerControllerScript
	var rm: RealmManagerScript = RealmManagerScript.instance as RealmManagerScript
	var rig: Node = pc.get_node_or_null("PlayerFeelRig") if pc != null else null
	if pc == null or rm == null or rig == null:
		_check("bootstrap", false, "missing pc/rm/rig")
		quit(1)
		return

	# Ensure spawned test dummies do not kill the player during deterministic checks.
	pc.max_health = 100000
	pc.health = 100000
	_settle_player(pc)

	# --- CMB-01: Ground plunge requires >= 50 stamina and never freezes mid-air ---
	pc.global_position = Vector3(0.0, 0.0, -138.0)
	await _wait_physics(3)
	pc.stamina = 10.0
	pc.call("_buffer", "plunge")
	await _wait_physics(16)
	var no_low_leap: bool = (not bool(pc.get("_pending_ground_slam"))) and pc.current_state == PlayerControllerScript.State.LOCOMOTION and pc.velocity.y <= 0.1
	pc.call("set_simulated_airborne", true)
	pc.set("_pending_ground_slam", true)
	pc.set("_pending_ground_slam_timer", 0.005)
	pc.stamina = 0.0
	pc.velocity = Vector3(4.0, 0.0, 0.0)
	var x0: float = pc.global_position.x
	await _wait_physics(2)
	var no_midair_freeze: bool = (not bool(pc.get("_pending_ground_slam"))) and pc.global_position.x > x0 + 0.01
	_check("cmb01_ground_plunge_low_stamina_no_freeze", no_low_leap and no_midair_freeze, "no_low_leap=%s no_freeze=%s" % [str(no_low_leap), str(no_midair_freeze)])
	_settle_player(pc)

	# --- CMB-02: CentralMirrorPlane rejects trigger_break() and player F slam ---
	var plane: BreakablePropScript = level.get_node_or_null("Stage05_ExecutionArena/CentralMirrorPlane") as BreakablePropScript
	var tb_res: bool = plane.trigger_break(true) if plane != null else true
	if plane != null:
		pc.global_position = plane.global_position + Vector3(0.0, 1.5, -1.0)
		pc.call("set_simulated_airborne", true)
		pc.stamina = 200.0
		pc.start_landing_attack()
		pc.complete_landing_slam()
	_check("cmb02_central_mirror_plane_ignores_plunge_and_trigger_break", plane != null and (not tb_res) and plane.current_state == BreakablePropScript.PropState.INTACT and not rm.is_merged, "tb=%s state=%s merged=%s" % [str(tb_res), str(plane.current_state if plane != null else -1), str(rm.is_merged)])
	_settle_player(pc)

	# --- CMB-03: Heavy hold abort on ui_input_locked prevents _enter_strike in LOCOMOTION ---
	var fired_count: Array[int] = [0]
	var on_exec := func(_n: String, _s: int, _d: int, _h: bool) -> void:
		fired_count[0] += 1
	pc.attack_executed.connect(on_exec)
	pc.global_position = Vector3(0.0, 0.0, -138.0)
	pc.call("_begin_attack", "heavy", 60, true, PlayerControllerScript.State.HEAVY_ATTACK)
	var w_heavy: float = float(pc.current_attack.get("windup", 0.3))
	pc.set("_attack_elapsed", w_heavy * clampf(pc.heavy_hold_pose_u, 0.1, 0.95))
	PlayerControllerScript.ui_input_locked = true
	pc.call("_process_attack_state", 0.08)
	PlayerControllerScript.ui_input_locked = false
	pc.attack_executed.disconnect(on_exec)
	_check("cmb03_ui_lock_during_heavy_hold_no_strike", fired_count[0] == 0 and pc.current_state == PlayerControllerScript.State.LOCOMOTION and pc.attack_phase == PlayerControllerScript.AttackPhase.NONE and not pc.get_sword_hitbox().is_swing_active, "fired=%d state=%d phase=%d" % [fired_count[0], pc.current_state, pc.attack_phase])
	_settle_player(pc)

	# --- Spawn controlled test dummies on isolated terrace ---
	var sk_dummy: EnemyBaseScript = level.call("_add_roamer", level, "skeleton", "Test_cmb_sk", Vector3(0.0, 0.0, -135.0), EncounterDirectorScript.Section.ENTRY, Vector3(0.0, 0.0, -138.0)) as EnemyBaseScript
	await process_frame
	sk_dummy.set_section_enabled(true)
	sk_dummy.max_health = 5000
	sk_dummy.health = 5000
	if sk_dummy is EnemyAIScript:
		(sk_dummy as EnemyAIScript).move_speed = 0.0
		(sk_dummy as EnemyAIScript).attack_damage = 0

	# --- CMB-04: Zero-charge dodge cannot free-cancel attack or leak finisher invuln ---
	pc.global_position = Vector3(0.0, 0.0, -136.5)
	pc.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_rend")
	pc.start_finisher("fin_rend")
	pc.set("_dodge_charges", 0)
	pc.call("_buffer", "dodge")
	pc.call("_process_attack_state", 0.016)
	var stayed_attack: bool = pc.current_state == PlayerControllerScript.State.HEAVY_ATTACK
	pc.call("_abort_attack")
	var invuln_cleared: bool = (not pc.is_invulnerable()) and (not pc.get_hurtbox().is_invulnerable)
	_check("cmb04_zero_charge_dodge_cannot_cancel_attack_or_leak_invuln", stayed_attack and invuln_cleared, "stayed=%s cleared=%s" % [str(stayed_attack), str(invuln_cleared)])
	_settle_player(pc)

	# --- CMB-05: fin_sunder passes "fin_sunder" source_type and applies STUNNED knockdown ---
	pc.global_position = sk_dummy.global_position - Vector3(0.0, 0.0, 1.5)
	pc.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_sunder")
	pc.start_finisher("fin_sunder")
	await _wait_physics(40)
	var sunder_stunned: bool = (sk_dummy as EnemyAIScript).current_state == EnemyAIScript.State.STUNNED and sk_dummy.last_hit_source == "fin_sunder"
	_check("cmb05_fin_sunder_applies_stunned_knockdown", sunder_stunned, "state=%d src=%s" % [(sk_dummy as EnemyAIScript).current_state, sk_dummy.last_hit_source])
	_settle_player(pc)

	# --- CMB-06: _acquire_target ignores unhittable PhantomTwin in Reality ---
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var ph_dummy: EnemyBaseScript = level.call("_add_roamer", level, "phantom", "Test_cmb_ph", Vector3(0.0, 0.0, -136.2), EncounterDirectorScript.Section.ENTRY, Vector3(0.0, 0.0, -138.0)) as EnemyBaseScript
	await process_frame
	ph_dummy.set_section_enabled(true)
	ph_dummy.global_position = Vector3(0.0, 0.0, -136.2)
	sk_dummy.global_position = Vector3(0.0, 0.0, -134.8)
	pc.global_position = Vector3(0.0, 0.0, -138.0)
	var mag_target: Node3D = pc.call("_acquire_target", Vector3(0.0, 0.0, 1.0), 4.8) as Node3D
	_check("cmb06_acquire_target_skips_unhittable_phantom_in_reality", mag_target == sk_dummy, "got=%s" % (mag_target.name if mag_target != null else "null"))
	ph_dummy.queue_free()

	# --- CMB-07: player_landing after fin_execution does not inherit stale execute ---
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_execution")
	pc.start_finisher("fin_execution")
	pc.call("_abort_attack")
	pc.call("_set_state", PlayerControllerScript.State.LOCOMOTION, 0.0)
	var dict_cleared: bool = pc.current_attack.is_empty()
	sk_dummy.is_dead = false
	sk_dummy.health = int(floor(float(sk_dummy.max_health) * 0.25))
	pc.global_position = sk_dummy.global_position + Vector3(0.0, 1.5, 0.0)
	pc.stamina = 200.0
	pc.call("set_simulated_airborne", true)
	pc.start_landing_attack()
	var slam_hits: int = pc.complete_landing_slam([sk_dummy])
	_check("cmb07_landing_slam_after_fin_execution_no_stale_execute", dict_cleared and slam_hits == 1 and not sk_dummy.is_dead and sk_dummy.health > 0, "cleared=%s hits=%d dead=%s hp=%d" % [str(dict_cleared), slam_hits, str(sk_dummy.is_dead), sk_dummy.health])
	_settle_player(pc)

	# --- CMB-08: Deflected heavy on Reality shield never opens finisher window ---
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var sg_dummy: EnemyBaseScript = level.call("_add_roamer", level, "shield", "Test_cmb_sg", Vector3(0.0, 0.0, -130.0), EncounterDirectorScript.Section.ENTRY, Vector3(0.0, 0.0, -132.0)) as EnemyBaseScript
	await process_frame
	sg_dummy.set_section_enabled(true)
	if sg_dummy is EnemyAIScript:
		(sg_dummy as EnemyAIScript).move_speed = 0.0
		(sg_dummy as EnemyAIScript).attack_damage = 0
	sg_dummy.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	pc.global_position = sg_dummy.global_position + Vector3(0.0, 0.0, -1.6)
	pc.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.call("_close_finisher_window", "")
	var sg_hp0: int = sg_dummy.health
	pc.call("_begin_attack", "heavy", 60, true, PlayerControllerScript.State.HEAVY_ATTACK)
	pc.call("_release_heavy_charge")
	pc.current_attack["finisher"] = true
	await _wait_physics(32)
	_check("cmb08_deflected_heavy_on_reality_shield_never_opens_finisher", sg_dummy.health < sg_hp0 and not pc.is_finisher_window_open(), "hp %d->%d win=%s" % [sg_hp0, sg_dummy.health, str(pc.is_finisher_window_open())])
	sg_dummy.queue_free()
	_settle_player(pc)

	# --- CMB-09: open_finisher_window clears pre-buffered inputs ---
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.call("_buffer", "light")
	pc.open_finisher_window(sk_dummy)
	pc.call("_update_finisher_window")
	pc.call("_update_finisher_window")
	_check("cmb09_open_finisher_window_clears_prebuffered_input", pc.is_finisher_window_open() and String(pc.get("_buffer_action")) == "" and pc.current_state == PlayerControllerScript.State.LOCOMOTION, "open=%s buf=%s state=%d" % [str(pc.is_finisher_window_open()), String(pc.get("_buffer_action")), pc.current_state])
	_settle_player(pc)

	# --- CMB-10: fin_phantom respects open pits and LAYER_PLAYER_BLOCKER ---
	var iso_arena := Node3D.new()
	iso_arena.name = "IsolatedPhantomCheck"
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = RealmManagerScript.LAYER_WORLD_SHARED
	var floor_cs := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(10.0, 1.0, 10.0)
	floor_cs.shape = floor_box
	floor_cs.position = Vector3(200.0, -0.5, 0.0)
	floor_body.add_child(floor_cs)
	iso_arena.add_child(floor_body)
	var blocker_body := StaticBody3D.new()
	blocker_body.collision_layer = RealmManagerScript.LAYER_PLAYER_BLOCKER
	var blocker_cs := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(6.0, 4.0, 0.4)
	blocker_cs.shape = blocker_box
	blocker_cs.position = Vector3(200.0, 1.5, 0.6)
	blocker_body.add_child(blocker_cs)
	iso_arena.add_child(blocker_body)
	root.add_child(iso_arena)
	sk_dummy.set_physics_process(false)
	sk_dummy.global_position = Vector3(200.0, 0.0, 4.8)
	pc.global_position = Vector3(200.0, 0.0, 3.0)
	await _wait_physics(3)
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_phantom")
	pc.start_finisher("fin_phantom")
	var no_pit_tp: bool = pc.global_position.z <= 4.8
	_settle_player(pc)
	sk_dummy.global_position = Vector3(200.0, 0.0, 0.0)
	pc.global_position = Vector3(200.0, 0.0, -2.0)
	await _wait_physics(2)
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_phantom")
	pc.start_finisher("fin_phantom")
	var blocked_by_rail: bool = pc.global_position.z < 0.6
	_check("cmb10_fin_phantom_respects_pit_and_player_blocker", no_pit_tp and blocked_by_rail, "pit_z_ok=%s blocker_z_ok=%s" % [str(no_pit_tp), str(blocked_by_rail)])
	iso_arena.queue_free()
	sk_dummy.set_physics_process(true)
	sk_dummy.global_position = Vector3(0.0, 0.0, -135.0)
	pc.global_position = Vector3(0.0, 0.0, -138.0)
	_settle_player(pc)

	# --- CMB-11: Finisher i-frames pause cleanly and clear on _abort_attack() ---
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_rend")
	pc.start_finisher("fin_rend")
	var inv_start: bool = pc.is_invulnerable() and pc.get_hurtbox().is_invulnerable
	paused = true
	await create_timer(0.9, true, false, true).timeout
	var inv_paused: bool = pc.is_invulnerable() and pc.get_hurtbox().is_invulnerable
	paused = false
	pc.call("_abort_attack")
	pc.call("_set_state", PlayerControllerScript.State.LOCOMOTION, 0.0)
	var inv_aborted: bool = (not pc.is_invulnerable()) and (not pc.get_hurtbox().is_invulnerable)
	_check("cmb11_finisher_invuln_uses_scaled_time_and_clears_on_abort", inv_start and inv_paused and inv_aborted, "start=%s paused=%s abort=%s" % [str(inv_start), str(inv_paused), str(inv_aborted)])
	_settle_player(pc)

	# --- CMB-12: Rejected 2nd air-dash preserves dodge charges & active i-frames ---
	pc.call("set_simulated_airborne", true)
	pc.set("_coyote_timer", 0.0)
	pc.set("_air_dash_used", false)
	pc.set("_dodge_charges", 2)
	pc.set("_dodge_cooldown_timer", 0.0)
	var air1: bool = pc.start_dodge(Vector3.FORWARD)
	pc.set("_dodge_elapsed", pc.dodge_duration * 0.50)
	pc.call("_update_hurtbox_invulnerability", true)
	pc.call("_buffer", "dodge")
	pc.call("_process_dodge_state", 0.016)
	var kept_iframes: bool = pc.get_hurtbox().is_invulnerable
	var charges_chain: int = int(pc.get("_dodge_charges"))
	var air2: bool = pc.start_dodge(Vector3.FORWARD)
	var charges_direct: int = int(pc.get("_dodge_charges"))
	_check("cmb12_rejected_second_air_dash_preserves_charge_and_iframes", air1 and kept_iframes and charges_chain == 1 and (not air2) and charges_direct == 1, "air1=%s iframes=%s c1=%d air2=%s c2=%d" % [str(air1), str(kept_iframes), charges_chain, str(air2), charges_direct])
	_settle_player(pc)

	# --- CMB-13: Custom camera_fov persists across PlayerFeelRig updates ---
	var store: Node = root.get_node_or_null("LeaderboardStore")
	var orig_fov: float = 65.0
	var fov_ok: bool = false
	if store != null and store.has_method("get_settings") and store.has_method("save_settings"):
		orig_fov = float((store.call("get_settings") as Dictionary).get("camera_fov", 65.0))
		store.call("save_settings", {"camera_fov": 82.0})
		rig.set("_fov_kick", 0.0)
		rig.set("_fov_kick_vel", 0.0)
		var cam: Camera3D = pc.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D
		for _f in range(5):
			rig.call("_update_camera", 0.016)
		fov_ok = absf(cam.fov - 82.0) < 0.05 and absf(float(rig.get("_base_fov")) - 82.0) < 0.05
		store.call("save_settings", {"camera_fov": orig_fov})
	_check("cmb13_custom_camera_fov_persists_across_feel_rig_updates", fov_ok, "base=%s" % str(rig.get("_base_fov")))

	# --- CMB-14: SquadAlly's 5 sound sites no longer call GameFeelScript with invalid keys ---
	var ally: Node = get_first_node_in_group("squad_ally")
	var am: Node = root.get_node_or_null("GameAudio")
	var cues_valid: bool = am != null \
		and am.call("_cue_stream", "hit_metal") != null \
		and am.call("_cue_stream", "glass_shatter") != null \
		and am.call("_cue_stream", "landing_slam") != null \
		and am.call("_cue_stream", "enemy_hit") != null
	if ally != null:
		ally.call("apply_damage", 5, null)
	var gf_probe := GameFeelScript.new()
	var fallback_valid: bool = gf_probe.get_stream("clang") != null and gf_probe.get_stream("land_heavy") != null and gf_probe.get_stream("slash_flesh") != null
	gf_probe.free()
	var ally_src: String = FileAccess.get_file_as_string("res://scripts/allies/squad_ally.gd")
	var legacy_fixed: bool = not ally_src.contains("GameFeelScript.play_sound(self, \"glass_shatter\"") and not ally_src.contains("GameFeelScript.play_sound(self, \"landing_slam\"")
	_check("cmb14_squad_ally_sound_keys_valid", cues_valid and fallback_valid and legacy_fixed, "cues=%s fb=%s src=%s" % [str(cues_valid), str(fallback_valid), str(legacy_fixed)])

	# --- CMB-15: GameFeel.add_trauma() distance falloff works for Node PlayerFeelRig ---
	pc.global_position = Vector3.ZERO
	pc.camera_shake_intensity = 1.0
	rig.set("trauma", 0.0)
	GameFeelScript.add_trauma(pc, 0.8, Vector3(0.0, 0.0, 50.0), 18.0)
	var far_trauma: float = float(rig.get("trauma"))
	GameFeelScript.add_trauma(pc, 0.8, Vector3(0.0, 0.0, 9.0), 18.0)
	var mid_trauma: float = float(rig.get("trauma"))
	_check("cmb15_gamefeel_add_trauma_distance_falloff", far_trauma == 0.0 and absf(mid_trauma - 0.4) < 0.02, "far=%.3f mid=%.3f" % [far_trauma, mid_trauma])

	# --- CMB-16: Hitbox3D registers RunState combo hits for fin_* and player_execution ---
	var rs: Node = root.get_node_or_null("RunState")
	var hb: Hitbox3DScript = pc.get_sword_hitbox() as Hitbox3DScript
	sk_dummy.health = sk_dummy.max_health
	var combo_ok: bool = false
	if rs != null and hb != null:
		rs.call("start_new_run")
		hb.begin_swing(20, true, "fin_sunder")
		var h1: bool = hb.try_hit_target(sk_dummy)
		hb.end_swing()
		hb.begin_swing(20, true, "player_execution")
		var h2: bool = hb.try_hit_target(sk_dummy)
		hb.end_swing()
		combo_ok = h1 and h2 and int(rs.get("combo_hits")) == 2
	_check("cmb16_hitbox_registers_combo_for_execution_and_finishers", combo_ok, "combo=%s" % str(rs.get("combo_hits") if rs != null else -1))

	# --- CMB-17: 0s-warning breakable defers CollisionShape3D.disabled cleanly ---
	var prop: BreakablePropScript = (load("res://scenes/props/breakable_prop.tscn") as PackedScene).instantiate() as BreakablePropScript
	prop.prop_kind = BreakablePropScript.PropKind.WEAK_STONE_SUPPORT
	prop.warning_duration = 0.0
	prop.require_heavy_attack = true
	prop.position = Vector3(0.0, 0.0, -135.0)
	root.add_child(prop)
	await _wait_physics(2)
	pc.global_position = prop.global_position - Vector3(0.0, 0.0, 2.5)
	pc.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	hb.begin_swing(60, true, "player_heavy")
	await _wait_physics(1)
	pc.global_position = prop.global_position - Vector3(0.0, 0.0, 1.0)
	await _wait_physics(3)
	hb.end_swing()
	var prop_cs := prop.get_node("SolidBody/CollisionShape3D") as CollisionShape3D
	var prop_hb := prop.get_node("Hurtbox3D") as Area3D
	var prop_src: String = FileAccess.get_file_as_string("res://scripts/environment/breakable_prop.gd")
	var no_sync_disable: bool = not prop_src.contains("cs.disabled =") and not prop_src.contains("scs.disabled =")
	_check("cmb17_zero_warning_breakable_defers_colliders_cleanly", prop.current_state == BreakablePropScript.PropState.BROKEN and prop_cs.disabled and not prop_hb.monitorable and no_sync_disable, "state=%d cs=%s mon=%s sync=%s" % [prop.current_state, str(prop_cs.disabled), str(prop_hb.monitorable), str(no_sync_disable)])
	prop.queue_free()
	sk_dummy.queue_free()

	# --- CMB-18: Heavy charge rumble respects camera_shake_intensity = 0.0 ---
	pc.camera_shake_intensity = 0.0
	rig.set("trauma", 0.0)
	pc.call("_begin_attack", "heavy", 60, true, PlayerControllerScript.State.HEAVY_ATTACK)
	pc.set("_heavy_charge_t", 2.5)
	rig.call("_update_camera", 0.016)
	var zero_rumble: bool = float(rig.get("trauma")) == 0.0
	_check("cmb18_heavy_charge_respects_zero_camera_shake_intensity", zero_rumble, "trauma=%.3f" % float(rig.get("trauma")))
	_settle_player(pc)
	pc.camera_shake_intensity = 1.0

	# --- CMB-19: SwordTrail does not bridge consecutive swings across emitting toggles ---
	var blade := MeshInstance3D.new()
	blade.mesh = BoxMesh.new()
	var trail := SwordTrailScript.new()
	root.add_child(blade)
	root.add_child(trail)
	trail.bind_blade(blade)
	trail.max_age = 0.25
	trail.emitting = true
	for i in range(4):
		blade.global_position = Vector3(float(i) * 0.2, 1.0, 0.0)
		trail._process(0.016)
	trail.emitting = false
	trail._process(0.016)
	blade.global_position = Vector3(25.0, 1.0, 0.0)
	trail.emitting = true
	for i in range(4):
		blade.global_position = Vector3(25.0 + float(i) * 0.2, 1.0, 0.0)
		trail._process(0.016)
	var surf_count: int = trail.mesh.get_surface_count()
	var bridged: bool = false
	for s in range(surf_count):
		var arrays: Array = trail.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var min_x: float = INF
		var max_x: float = -INF
		for v in verts:
			min_x = minf(min_x, v.x)
			max_x = maxf(max_x, v.x)
		if min_x < 5.0 and max_x > 20.0:
			bridged = true
	_check("cmb19_sword_trail_no_bridge_across_swings_or_blink", surf_count >= 2 and not bridged, "surfaces=%d bridged=%s" % [surf_count, str(bridged)])
	trail.queue_free()
	blade.queue_free()

	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[combat_bugfix] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
```

---

### Step 9 — Synchronize `MEMORY/` Knowledge Base & Changelog (`AGENTS.md` Rule 1.3)

- **Prerequisites**: Steps 1–8 applied.
- **Postcondition**: `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` reflects the fixed plunge, dodge/finisher/deflect/blink/i-frame rules, and `CentralMirrorPlane` protection; `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` appends one dated summary bullet.

#### Edit 9A — Update `landing_attack` Rule in `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`

**Target:** `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`
**Action:** Replace block
**Find:**
```markdown
| `landing_attack` | `F` | **Airborne only**: triggers committed downward plunge; spawns single `2.2 m` radial shockwave (`60` dmg) on ground impact. No effect on ground. |
```
**Replace with:**
```markdown
| `landing_attack` | `F` | Airborne: triggers committed downward plunge (`50` stamina) spawning single `2.2 m` radial shockwave (`60` dmg). Ground: leaps into plunge only when `stamina >= 50.0` and `_landing_recover_timer <= 0.0`. |
```

#### Edit 9B — Update Finishers, Deflect, & `CentralMirrorPlane` Rules in `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`

**Target:** `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`
**Action:** Replace block
**Find:**
```markdown
- **Critical hit** (`PlayerController._try_open_finisher_window`): a non-killing sword hit by a chain ender (`light_5`, `heavy`, `heavy_spin` = defs with `finisher: true`) always crits; other light hits crit at `crit_chance_light = 0.20`, FLOW (on-rhythm) light hits at `crit_chance_flow = 0.35`. Deflected hits never crit. Cooldown `finisher_cooldown_sec = 2.5` after a finisher. Disabled entirely when the `finisher_window_enabled` setting is off (Options → Gameplay → "Critical Finisher Window").
- **Window**: `finisher_window_sec = 1.1` real seconds at `finisher_slowmo_scale = 0.35`; frame hitches > 50 ms are credited back. Press one of five inputs (read from the input buffer, so it works mid-attack):
  | Input | Finisher (`ATTACK_DEFS`) | Damage | Shape / effect |
  | :--- | :--- | :--- | :--- |
  | `light_attack` (LMB) | `fin_rend` "REND" | 4 × 28 (blade re-armed 4× across a 0.48 s active phase, `multi: 4`) | 170° arc, reach 2.9 |
  | `heavy_attack` (RMB) | `fin_sunder` "SUNDER" | 120 | 360° reach 3.6, knockback 13, 8 radial ground cracks, light pillar, double shockwave |
  | `dodge` (Shift) | `fin_phantom` "PHANTOM STEP" | 95 | Blinks 1.5 m behind the target (wall-safe ray, only if target < 6 m), cyan afterimage + streak, camera swings round |
  | `dimension_shift` (Q, buffer `"mirror"`) | `fin_mirror_break` "MIRROR BREAK" | 3 × 40 (`multi: 3`) | 360° reach 3.4 AoE, knockback 10, staggers; cyan/amber glass-shard bursts each tick. **Does not shift realm** inside the window |
  | `landing_attack` (F, buffer `"plunge"`) | `fin_execution` "EXECUTION" | 150 | Leap-chop 120° reach 3.0, crack 5.5; any target left at ≤ 35 % HP (`execute: 0.35`) dies outright (crimson starburst) |
- Finishers run as `State.HEAVY_ATTACK`, grant i-frames for 80% of their duration, score `+150 finisher` (combo-multiplied, `ScoreManager.POINTS_FINISHER`).
- Signals: `finisher_window_opened(duration, options)`, `finisher_window_closed(chosen)`, `finisher_executed(name)`. VFX in `scripts/player/finisher_fx.gd`; HUD prompt `scripts/ui/finisher_prompt.gd` (`FinisherPrompt`, auto-added under `HUD/RootControl`): 5 diamond plates with keycaps, a draining timer bar, a rotating gold lock-on reticle on `PlayerController.get_finisher_target()` (shows "EXECUTABLE" at ≤ 35 % HP), and a plain-language tutorial line for the first 2 windows of a session. Squad subtitles hide while the window is open.

### 2.3 Authored Breakables (One-Week Deterministic Pattern)
Do NOT rely on runtime physics simulation for gameplay outcomes. Use authored `AnimationPlayer` animations + explicit single-tick `Area3D` / `ShapeCast` volumes + optional non-colliding `RigidBody3D` cosmetic rubble afterward. Each break event fires **at most once** (idempotent until section reset).

| Breakable | Stage | Trigger | Outcome & Safety |
| :--- | :--- | :--- | :--- |
| **Cracked Central Pillar** | 02. Hall of Echoes `(0, 0, 20)` | Heavy attack (`RMB`) on glowing fracture point. | `0.6 s` warning telegraph (dust + fracture glow) -> falls along fixed **northward** fall zone (`2.5 m` radius). Deals **`150` dmg** to enemies (lethal to Skeleton & Phantom, awards **+250 Environmental Kill**) and **`40` dmg** to player if inside fall zone. |
| **Weak Stone Support** | 03. Collapsed Gallery `(0, 0, 51)` | Heavy attack (`RMB`) on fracture point. | Low stone barrier collapses cleanly, uncovering the Bridge Anchor Switch alcove behind it. |
| **Central Mirror Plane** | 05. Execution Arena `X = 0` | Scripted at **Warden <= 500 HP (50%)**. | Plays `<= 2.0 s` shatter sequence; dissolves Mirror split; merges realms; locks `Q`. |
```
**Replace with:**
```markdown
- **Critical hit** (`PlayerController._try_open_finisher_window`): a non-killing sword hit by a chain ender (`light_5`, `heavy`, `heavy_spin` = defs with `finisher: true`) always crits; other light hits crit at `crit_chance_light = 0.20`, FLOW (on-rhythm) light hits at `crit_chance_flow = 0.35`. Deflected hits (`_was_deflected`) never crit, including chip hits on Reality shields. Cooldown `finisher_cooldown_sec = 2.5` after a finisher. Disabled entirely when the `finisher_window_enabled` setting is off (Options → Gameplay → "Critical Finisher Window").
- **Window**: `finisher_window_sec = 1.1` real seconds at `finisher_slowmo_scale = 0.35`; frame hitches > 50 ms are credited back. Opening the window clears pre-crit buffered inputs (`_consume_buffer()`); only inputs pressed after the window opens trigger finishers:
  | Input | Finisher (`ATTACK_DEFS`) | Damage | Shape / effect |
  | :--- | :--- | :--- | :--- |
  | `light_attack` (LMB) | `fin_rend` "REND" | 4 × 28 (blade re-armed 4× across a 0.48 s active phase, `multi: 4`) | 170° arc, reach 2.9 |
  | `heavy_attack` (RMB) | `fin_sunder` "SUNDER" | 120 (`source_type = "fin_sunder"`) | 360° reach 3.6, knockback 13, `STUNNED` knockdown (`1.6 s`, `×1.35` dmg), 8 radial ground cracks, light pillar, double shockwave |
  | `dodge` (Shift) | `fin_phantom` "PHANTOM STEP" | 95 | Blinks 1.5 m behind the target (active-realm wall + `LAYER_PLAYER_BLOCKER` ray + downward floor check; skips blink if no solid floor), cyan afterimage + streak, camera swings round |
  | `dimension_shift` (Q, buffer `"mirror"`) | `fin_mirror_break` "MIRROR BREAK" | 3 × 40 (`multi: 3`) | 360° reach 3.4 AoE, knockback 10, staggers; cyan/amber glass-shard bursts each tick. **Does not shift realm** inside the window |
  | `landing_attack` (F, buffer `"plunge"`) | `fin_execution` "EXECUTION" | 150 (`source_type = "player_execution"`) | Leap-chop 120° reach 3.0, crack 5.5; pierces shields and executes any target left at ≤ 35 % HP (`execute: 0.35`, gated on `source_type == "player_execution"`) outright (crimson starburst) |
- Finishers run as `State.HEAVY_ATTACK`, grant pausable scaled-time i-frames for 80% of their duration (`_finisher_invuln_timer`, cleared on abort/cancel), register combo hits in `Hitbox3D` (`player_execution` and `fin_*`), and score `+150 finisher` (combo-multiplied, `ScoreManager.POINTS_FINISHER`).
- Signals: `finisher_window_opened(duration, options)`, `finisher_window_closed(chosen)`, `finisher_executed(name)`. VFX in `scripts/player/finisher_fx.gd`; HUD prompt `scripts/ui/finisher_prompt.gd` (`FinisherPrompt`, auto-added under `HUD/RootControl`): 5 diamond plates with keycaps, a draining timer bar, a rotating gold lock-on reticle on `PlayerController.get_finisher_target()` (shows "EXECUTABLE" at ≤ 35 % HP), and a plain-language tutorial line for the first 2 windows of a session. Squad subtitles hide while the window is open.

### 2.3 Authored Breakables (One-Week Deterministic Pattern)
Do NOT rely on runtime physics simulation for gameplay outcomes. Use authored `AnimationPlayer` animations + explicit single-tick `Area3D` / `ShapeCast` volumes + optional non-colliding `RigidBody3D` cosmetic rubble afterward. Each break event fires **at most once** (idempotent until section reset), and collider toggles use `set_deferred()` cleanly inside physics flushes.

| Breakable | Stage | Trigger | Outcome & Safety |
| :--- | :--- | :--- | :--- |
| **Cracked Central Pillar** | 02. Hall of Echoes `(0, 0, 20)` | Heavy attack (`RMB`) on glowing fracture point. | `0.6 s` warning telegraph (dust + fracture glow) -> falls along fixed **northward** fall zone (`2.5 m` radius). Deals **`150` dmg** to enemies (lethal to Skeleton & Phantom, awards **+250 Environmental Kill**) and **`40` dmg** to player if inside fall zone. |
| **Weak Stone Support** | 03. Collapsed Gallery `(0, 0, 51)` | Heavy attack (`RMB`) on fracture point. | Low stone barrier collapses cleanly (`0.0 s` warning, deferred colliders), uncovering the Bridge Anchor Switch alcove behind it. |
| **Central Mirror Plane** | 05. Execution Arena `X = 0` | Scripted at **Warden Phase 2 transition** (`complete_break_now()`). | `trigger_break()` and player landing slams explicitly reject `CENTRAL_MIRROR_PLANE`. Plays `<= 2.0 s` shatter sequence; dissolves Mirror split; merges realms; locks `Q`. |
```

#### Edit 9C — Append Dated Entry to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`

**Target:** `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`
**Action:** Replace block
**Find:**
```markdown
- 2026-11-19: Stacked Dodge Chaining & Execution Shield Pierce - Implemented consecutive stacked dodge chaining in PlayerController (_process_dodge_state allows chaining past i-frames t_norm > 0.45; start_dodge accepts State.DODGE; buffer consumes seamlessly on finish). ShieldedGuard._modify_incoming_damage allows player_execution to bypass shield deflect. Verified with charged_heavy_test (18 checks), feel_and_movement_test (13 checks), combat_rules_test (10 checks), and restart_flow_test (PASS).
```
**Replace with:**
```markdown
- 2026-11-19: Stacked Dodge Chaining & Execution Shield Pierce - Implemented consecutive stacked dodge chaining in PlayerController (_process_dodge_state allows chaining past i-frames t_norm > 0.45; start_dodge accepts State.DODGE; buffer consumes seamlessly on finish). ShieldedGuard._modify_incoming_damage allows player_execution to bypass shield deflect. Verified with charged_heavy_test (18 checks), feel_and_movement_test (13 checks), combat_rules_test (10 checks), and restart_flow_test (PASS).
- 2026-11-20: Combat & Feel Bugfix Pass (Guide 01, CMB-01..CMB-19) - Guarded ground plunge stamina/freeze & CentralMirrorPlane breakability, fixed heavy-hold UI-lock strike leak, attack dodge-cancel charge check, fin_sunder knockdown source_type, _acquire_target is_hittable_now filtering, stale execute dict cleanup, Reality shield heavy-deflect no-crit flag, finisher buffer clear, safe fin_phantom pit/blocker raycast, pausable scaled finisher i-frames, non-destructive air-dash rejection, PlayerFeelRig FOV sync & camera_shake_intensity charge scaling, SwordTrail stroke splitting, GameFeel Node-parent trauma falloff, Hitbox3D combo registration for execution/finishers, deferred BreakableProp colliders, and SquadAlly's 5 invalid sound keys; added tests/combat_bugfix_regression_test.gd (19 checks) and synced MEMORY/03.
```

---

## E. Verification & Failure Handling

Run every command below in PowerShell from `D:\Desktop\Godot\parallax`.

| Ver ID | Command | Preconditions | Expected Pass Condition | Covers |
| :--- | :--- | :--- | :--- | :--- |
| **VER-01** | `foreach ($f in @("scripts/core/hitbox_3d.gd","scripts/core/game_feel.gd","scripts/environment/breakable_prop.gd","scripts/player/player_controller.gd","scripts/player/sword_trail.gd","scripts/player/player_feel_rig.gd","scripts/allies/squad_ally.gd","tests/combat_bugfix_regression_test.gd","scripts/enemies/warden_boss.gd","scripts/enemies/shielded_guard.gd","scripts/enemies/skeleton_guard.gd","scripts/enemies/enemy_ai.gd","scripts/enemies/phantom_twin.gd","scripts/core/realm_manager.gd","scripts/core/audio_manager.gd","scripts/core/score_manager.gd","scripts/core/leaderboard_store.gd","tests/combat_rules_test.gd","tests/feel_and_movement_test.gd","tests/charged_heavy_test.gd","tests/sanity_regression_test.gd")) { Write-Host "CHECK $f"; & "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" --check-only -s "res://$f"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }` | Steps 1–8 applied | Exit `0` across all scripts with zero `SCRIPT ERROR` or parse warnings. | `CMB-01`..`CMB-19` |
| **VER-02** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/combat_bugfix_regression_test.gd` | Steps 1–8 applied | Exit `0`; prints `[combat_bugfix] SUMMARY 19 checks, 0 failed` and zero physics-flush errors. | `CMB-01`..`CMB-19` |
| **VER-03** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/combat_rules_test.gd` | Steps 1–7 applied | Exit `0`; prints `[combat] SUMMARY 10 checks, 0 failed` (`HEALTH_SCALE = 3.25`, Warden `1500` HP, Phantom Reality immunity preserved). | `CMB-06`, Regression (`1ca7464` / `REQ-24`) |
| **VER-04** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/charged_heavy_test.gd` | Step 4 applied | Exit `0`; prints `[charged] SUMMARY 18 checks, 0 failed` (`stacked_dodge_chains_twice` & hold-charge checks pass). | `CMB-03`, `CMB-04`, `CMB-12`, Invariant (`1ca7464`) |
| **VER-05** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/restart_flow_test.gd` | Steps 1–7 applied | Exit `0`; prints `=> PASS`. | Regression |
| **VER-06** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/level_props_test.gd` | Step 3 applied | Exit `0`; prints `[props] SUMMARY 12 checks, 0 failed` (`WeakStoneSupport` & props valid). | `CMB-17`, Regression |
| **VER-07** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/boot_smoke.gd` | Steps 1–7 applied | Exit `0`; prints `[boot_smoke] OK`. | Boot & signal wiring |
| **VER-08** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/feel_and_movement_test.gd` *(or windowed if GPU/display session required)* | Steps 4–6 applied | Exit `0`; prints `[feel] SUMMARY 13 checks, 0 failed` (`chain_reaches_5_distinct_moves`, `rhythm_taps_flow`, `pause_branch_rising_arc`, `q_in_window_is_mirror_break`, `f_in_window_executes` all `PASS`). | `CMB-07`, `CMB-09`, `CMB-19`, Invariant (`REQ-20`) |

### Failure Recovery Protocol
1. **Parse failure in `VER-01`**: Re-run `--check-only -s` on the reported file, compare against the corresponding Step in Section D, and restore cleanly via `git checkout -- <file>` before re-applying if needed.
2. **Stale `user://settings.cfg` after an interrupted `cmb13` check**: Verify `camera_fov` in `%APPDATA%\Godot\app_userdata\PARALLAX\settings.cfg` is restored to its pre-test value (`65.0`) if `combat_bugfix_regression_test.gd` aborted mid-run.
3. **Borderline spacing flake in `VER-08` (`follow_no_crowding` / `follow_no_wall_grinding`)**: Do not alter `PlayerController` or `SquadAlly` movement constants outside Guide 01; re-run `feel_and_movement_test.gd` windowed (`--path "D:/Desktop/Godot/parallax" -s res://tests/feel_and_movement_test.gd`) and confirm all Section 1, 2, and 4 combat/finisher assertions (`chain_*`, `rhythm_taps_flow`, `pause_branch_rising_arc`, `q_in_window_is_mirror_break`, `f_in_window_executes`) pass cleanly.

---

## F. Completion Report Contract

When execution finishes, output a report containing **only directly verified facts**:

1. **Applied Step IDs**: Exact list (`Step 1` .. `Step 9`) and any skipped or partial step.
2. **Changed Files**: Exact modified/created paths matching Section C.
3. **Verification Results Table**: Command (`VER-01` .. `VER-08`), exit code, and exact printed `SUMMARY` / pass line for every run.
4. **Remaining Unverified Items / Blockers**: Any skipped check (for example if `VER-08` could not run windowed on a headless-only host) explicitly flagged as unverified.
5. **Definition of Done**: Steps 1–9 applied cleanly, zero unintended untracked files left behind (`git status` shows only Section C files), and `VER-01` through `VER-08` exit `0` with `0 failed`.
