# IdiotHandOffGuide — PARALLAX Guide 02: Enemies & AI Remediation

> **Scope**: Single self-contained, execution-ready handoff resolving all **26 bugs** (`ENM-01`..`ENM-26`: `6🔴 CRIT`, `17🟡 WARN`, `3🔵 LOW`) across `scripts/enemies/*.gd`, adding the dedicated regression suite `tests/enemies_ai_bugfix_regression_test.gd`, and synchronizing `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` and `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`.
> **Readiness**: `READY` (all target scripts, scenes, `.tres` archetypes, callers, tests, and `MEMORY/` documents verified against `master` @ `1ca7464`).
> **Executor Rule**: Apply **Steps 1–10** in exact order, run every verification command in Section E, and return the completion report defined in Section F. Do **not** edit `scripts/player/player_controller.gd`, `.tscn`, `.tres`, `project.godot`, or create extra `.md` files in the repo root or `MEMORY/` (`AGENTS.md` Rule 1.2).

---

## A. Execution Contract

### A.1 Repository & Runtime Baseline (Observed Before Handoff)
- **Repository Root**: `D:\Desktop\Godot\parallax`
- **Branch / HEAD Commit**: `master` @ `1ca7464` (clean working tree)
- **Engine Binary**: `C:/Users/agrim/.local/bin/godot.cmd` (`Godot Engine v4.7.2.stable.official.ed1daf0bf`, Forward+, Windows 64-bit)
- **Shell**: PowerShell (Windows)
- **Existing Uncommitted Changes**: None (`git status -s` clean at `1ca7464` prior to cross-guide execution).
- **Recommended Cross-Guide Execution Order**: **`01 -> 02 -> 03 -> 04`**
  - Apply `plan/IdiotHandOffGuide_01_Combat.md` first, then this guide (`02`), then `03` and `04`.
  - All `scripts/enemies/*.gd` edits and `tests/enemies_ai_bugfix_regression_test.gd` in this guide are strictly owned by Guide 02 and do not overlap with Guide 01 files.
- **Author Validation Status Prior to Execution**:
  - Derived strictly by static inspection of all 8 `scripts/enemies/*.gd` scripts, `scripts/enemies/enemy_archetype.gd`, `data/enemies/*.tres`, `scenes/enemies/enemy_base.tscn`, `scripts/core/{realm_manager,encounter_director,hitbox_3d,hurtbox_3d,character_animation_bridge,audio_manager}.gd`, `scripts/environment/{pit_kill_zone,breakable_prop,encounter_gate,colosseum_greybox_builder,grand_journey_builder}.gd`, `scripts/allies/squad_ally.gd`, `scripts/player/player_controller.gd`, `MEMORY/{00,03,07}_*.md`, and `tests/*.gd`. **None of the patches in Section D have been applied or executed yet**; the executor must apply Steps 1–10 and execute Section E to verify runtime pass conditions.

### A.2 Strict Operating Rules for the Executor
1. **Verify Baseline First**: Confirm `git branch --show-current` is `master`, and check whether `plan/IdiotHandOffGuide_01_Combat.md` has already been applied (`01 -> 02 -> 03 -> 04`). Preserve all Guide 01 changes cleanly.
2. **Apply Steps 1–10 In Exact Order**: Every edit uses exact `**Target:**`, `**Action:**`, `**Find:**`, and `**Replace with:**` (or `**Content:**`) fenced blocks. If multiple edits touch the same file, each subsequent `**Find:**` matches the intermediate state left by earlier edits in that step. If any `**Find:**` fails to match uniquely (other than Step 10's documented note for `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` after Guide 01), **STOP** and report the path and actual lines around the mismatch—do not improvise.
3. **Preserve Recent Invariants (`REQ-15`, `REQ-23`, `REQ-24`, `1ca7464`)**:
   - Keep `EnemyBase.HEALTH_SCALE = 3.25`.
   - Keep `EnemyAI.DAMAGE_SCALE = 1.4` applied **once** in `EnemyAI._ready()` (never double-scaled in `ArchetypeEnemy`, and preserve `WardenBoss` pre-scaled `cleave_damage = 28`, `lunge_damage = 35`, `max_health = 1500`, `_phase2_threshold() = 999`, Phase 1 overkill clamp, `phase2_max_hit = 120`).
   - Keep Hall (`56/68 m`) & Chamber (`38/48 m`) expanded engagement constants and `SkeletonGuard` 1-time `3.0 s` fall-down self-revive (excluding `"environmental"`, `"pit"`, `"player_execution"`, `"execution"`).
4. **Respect Ownership Boundaries**: Do **not** touch `scripts/player/player_controller.gd` (`CMB-06` owns `player_controller.gd:1024`). Do **not** create scratch `.md` files in repo root or `MEMORY/`.
5. **Run Full Verification Suite (Section E)**: Every headless `--check-only`, `tests/enemies_ai_bugfix_regression_test.gd`, and existing regression suite listed in Section E must exit `0` with `0 failed`.

---

## B. Requirements & Acceptance Map

### B.1 Assigned Requirements (`ENM-01` .. `ENM-26`: `6🔴 17🟡 3🔵`)

| Req ID | Target Location | Severity | Defect Summary & Expected Observable Behavior | Implementing Step(s) | Verification ID(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ENM-01** | `scripts/enemies/enemy_ai.gd:819-826, :867-872, :985` (+ `archetype_enemy.gd`, `phantom_twin.gd`, `warden_boss.gd`) | 🔴 **CRIT** | Gravity was only applied inside `_steer_toward()`. `_process_chase()`, `_process_attack()`, `WINDUP`, `RECOVER`, `STAGGER`, `STUNNED`, stationary `IDLE`/`ALERT`, and bolt taunt pause applied zero gravity (and `_begin_attack_strike()`/`start_windup()`/`_process_evade_step()` wiped `velocity.y = 0`), while `_process_chase()` lacked a floor edge probe. **Expected**: All active enemy states apply downward gravity (`-20 * delta`, clamped `-20`) via `_apply_gravity_and_slide(delta)`, preserve `velocity.y` across horizontal velocity writes, and `_process_chase()` / `_process_evade_step()` probe `_has_floor_ahead()` before moving toward cliff/pit drops. | Step 3 (3C–3H, 3J, 3L), Step 5 (5B), Step 7 (7B), Step 8 (8B, 8D, 8F) | `VER-01`, `VER-02` (`enm_01_gravity_and_edge_probe`) |
| **ENM-02** | `scripts/enemies/phantom_twin.gd:94-98` + `scripts/enemies/enemy_ai.gd:838-851` (+ `squad_coordinator.gd`) | 🔴 **CRIT** | In Reality (`_mirror_now() == false`), `PhantomTwin` still requested/held attack tokens in `_process_chase()` at `4.2–5.9 m` (starving real enemies) and at `<= 4.2 m` got granted tokens (`min_attack_gap = 0.42 s` stamped), released them in `start_windup()`, and returned early before `move_and_slide()` — freezing in place 60×/sec. **Expected**: `EnemyAI.can_attack_now()` (overridden to `_mirror_now()` on `PhantomTwin`) gates token requests, `_process_chase()` commitment, and poise counters; shifting to Reality mid-windup/attack cancels windup/hitbox and returns to `CHASE`; Phantom keeps circling without ever touching tokens or freezing. | Step 1 (1D), Step 3 (3B, 3G, 3K), Step 5 (5A, 5B) | `VER-01`, `VER-02` (`enm_02_phantom_reality_no_token_or_freeze`), `VER-03` |
| **ENM-03** | `scripts/enemies/skeleton_guard.gd:41-55` + `scripts/enemies/enemy_ai.gd:574-577` | 🔴 **CRIT** | `SkeletonGuard` self-revive (1) failed to exclude `"environmental"`/`"pit"`, reviving mid-void on `PitKillZone` & surviving lethal Cracked Pillar hits; (2) omitted `health_changed.emit(health, max_health)`, leaving `FloatingHPBar` hidden (`visible = false`); (3) returned with `is_dead == false`, allowing `EnemyAI.apply_damage()` to overwrite the `3.0 s` revive `STUNNED` with `0.55 s` `STAGGER` (backstab) or `1.6 s` `STUNNED` (`KNOCKDOWN_SOURCES`). **Expected**: Exclude `["environmental", "pit", "player_execution", "execution"]`; set `_revived_this_hit = true`, `health = maxi(1, int(max_health * 0.5))`, emit `health_changed`, enter `3.0 s` `STUNNED`, and short-circuit `EnemyAI.apply_damage()` post-hit reactions so the `3.0 s` revive stun is preserved. | Step 3 (3A, 3D, 3E, 3L), Step 4 (4A) | `VER-01`, `VER-02` (`enm_03_skeleton_revive_rules`), `VER-05` |
| **ENM-04** | `scripts/enemies/squad_coordinator.gd:345, :81` (+ `enemy_ai.gd`) | 🔴 **CRIT** | `is_last_standing()` was only called by aggroed chasing enemies so `engaged.is_empty()` was dead code, and `reset()` omitted `_peak_engaged = 0`; `_peak_engaged >= 2` persisted session-wide after the first multi-enemy fight, permanently enraging solo enemies (`ShieldedGuard_1`, `WardenBoss`). **Expected**: `reset()` clears `_peak_engaged = 0`; `refresh_engaged_peak()` resets `_peak_engaged = 0` whenever `get_engaged(null)` becomes empty (triggered on `set_enemy_target()`, `unregister()`, `_prune()`, `_physics_process()`, and `EnemyAI` state/activity exits). | Step 1 (1A–1C, 1E), Step 3 (3M) | `VER-01`, `VER-02` (`enm_04_peak_engaged_resets`) |
| **ENM-05** | `scripts/enemies/warden_boss.gd:137-141, :339` | 🔴 **CRIT** | `start_windup()` called `select_next_move()` *after* `_process_chase()` gated on the *previous* move's `attack_range`, inverting ranges (`LUNGE` waited for `2.8 m`; `CLEAVE` fired at `5.0 m` and whiffed since hitbox reach is `~2.33 m`); `_on_enemy_reset()` left `attack_range = 5.0` stale. **Expected**: `_ready()` and `_on_enemy_reset()` call `select_next_move(BossMove.CLEAVE)`; next move is queued via `_queue_next_move()` in `_enter_recover()` (and before Phase 2 Cleave->Lunge chain) so `attack_range` always matches the upcoming move. | Step 8 (8A, 8C, 8E, 8H) | `VER-01`, `VER-02` (`enm_05_warden_move_range_sync`), `VER-03` |
| **ENM-06** | `scripts/enemies/warden_boss.gd:198-208` | 🔴 **CRIT** | Heavy punishing Phase 1 Mirror recovery triggered `enter_stagger()`, bypassing `_on_recover_finished()` and leaving `is_chest_rune_exposed = true` permanently through `CHASE`/`WINDUP`/`ATTACK` (infinite Phase 1 stagger-locking). **Expected**: Overriding `_transition_to()` clears `is_chest_rune_exposed` via `_clear_chest_rune_exposure()` whenever leaving `State.RECOVER`, and `_should_stagger_on_hit()` prevents re-staggering while already in `State.STAGGER`. | Step 8 (8E, 8G) | `VER-01`, `VER-02` (`enm_06_warden_stagger_clears_rune`) |
| **ENM-07** | `scripts/enemies/archetype_enemy.gd:48` (+ `enemy_ai.gd:161`, `warden_boss.gd:66`) | 🟡 **WARN** | `apply_archetype()` scaled `attack_damage` by `DAMAGE_SCALE`, then `super._ready()` (`EnemyAI._ready()`) scaled it by `DAMAGE_SCALE` again (`1.96×`). **Expected**: `EnemyAI._ready()` scales `attack_damage` once using `_damage_scaled` guard; `ArchetypeEnemy.apply_archetype()` assigns raw `a.attack_damage` prior to `_ready()` (and `WardenBoss._ready()` marks `_damage_scaled = true` so pre-scaled `28/35` is untouched). | Step 3 (3A), Step 7 (7A), Step 8 (8A) | `VER-01`, `VER-02` (`enm_07_single_damage_scale`) |
| **ENM-08** | `scripts/enemies/archetype_enemy.gd:150` | 🟡 **WARN** | Bolt `_process_chase()` override never decremented `_evade_timer`, leaving `is_evading() == true` permanently after any evade. **Expected**: Bolt `_process_chase()` calls shared `EnemyAI._process_evade_step(delta, dir)` to tick down `_evade_timer`, move, and apply gravity/edge-probing. | Step 3 (3G, 3J), Step 7 (7B) | `VER-01`, `VER-02` (`enm_08_bolt_evade_timer_decays`) |
| **ENM-09** | `scripts/enemies/archetype_enemy.gd:174` | 🟡 **WARN** | Bolt `_process_chase()` called `request_attack_token()` outside `[pref * 0.45, attack_range]` and never released it, starving melee teammates up to `4.0 s`. **Expected**: Only request a token when `dist <= attack_range and dist >= pref * 0.45`; otherwise call `_release_token()`. | Step 7 (7B) | `VER-01`, `VER-02` (`enm_09_bolt_token_only_in_fire_band`) |
| **ENM-10** | `scripts/enemies/archetype_enemy.gd:208` | 🟡 **WARN** | `_try_blink_behind()` cast only a downward floor ray with no horizontal wall/gate ray from the target, teleporting `Shade Stalker` into walls or past locked gates. **Expected**: Cast horizontal rays (enemy->target and target->spot against world + `LAYER_PLAYER_BLOCKER`), clamp/abort behind walls or locked gates, check downward floor ray, and verify destination capsule clearance via `intersect_shape()`. | Step 7 (7C) | `VER-01`, `VER-02` (`enm_10_stalker_blink_respects_gates_and_walls`) |
| **ENM-11** | `scripts/enemies/archetype_enemy.gd:307` | 🟡 **WARN** | `_show_slam_ring()` assigned local `_ring_mesh.position` using world-space `get_facing_direction()` once at windup start, diverging `1.6 m+` on rotated roamers and during windup tracking. **Expected**: `_update_slam_ring_transform()` updates `_ring_mesh.global_position` (`global_position + get_facing_direction() * 0.8 + Vector3.UP * 0.06`) on show and every `_process_windup()` frame. | Step 7 (7C) | `VER-01`, `VER-02` (`enm_11_slam_ring_world_aligned`) |
| **ENM-12** | `scripts/enemies/enemy_ai.gd:369` | 🟡 **WARN** | `apply_taunt()` guard omitted `sid == _taunt_lock_id`; the same ally's `< 3.0 s` splash taunt cleared `_fixated` and downgraded permanent fixation to `2.5 s`. **Expected**: Guard any `is_fixated() and lock < 3.0` nudge regardless of `sid`, only refreshing `_fixation_far_t = 0.0` when `sid == _taunt_lock_id`. | Step 3 (3B) | `VER-01`, `VER-02` (`enm_12_same_ally_nudge_keeps_fixation`), `VER-09` |
| **ENM-13** | `scripts/enemies/enemy_ai.gd:526` | 🟡 **WARN** | `consider_evade()` allowed `State.IDLE -> State.CHASE` with null target, dropping to `ALERT` with stale `_evade_timer = 0.32` (never cleared on stagger/stun/flee/windup). **Expected**: Restrict `consider_evade()` to `CHASE`/`RECOVER` with a valid `player` and non-null `get_current_target()`, and clear `_evade_timer = 0.0` in `_transition_to()` whenever `next_state != State.CHASE`. | Step 3 (3D, 3M) | `VER-01`, `VER-02` (`enm_13_evade_idle_and_timer_clear`) |
| **ENM-14** | `scripts/enemies/enemy_ai.gd:580` | 🟡 **WARN** | Opening stagger/backstab/knockdown/flinch on an `IDLE` enemy entered `STAGGER`/`STUNNED` inside `super.apply_damage()` before the `was_idle` check, skipping `_set_target()`, `_reaggro_block = 0.0`, and `_squad.alert()`. **Expected**: Always run `_set_target()`, `_reaggro_block = 0.0`, and `_squad.alert()` when `was_idle` and `attacker` is valid, while only guarding `_transition_to(State.CHASE, 0.0)` against `STUNNED`/`STAGGER`/`_should_flee()`. | Step 3 (3E) | `VER-01`, `VER-02` (`enm_14_idle_opening_stagger_alerts_squad`) |
| **ENM-15** | `scripts/enemies/enemy_ai.gd:603, :1033` | 🟡 **WARN** | `_on_backstabbed()` set `_turn_to_id` unconditionally even when `backstab_staggers == false` (`WardenBoss`) or mid-`ATTACK`, and `_finish_turn_around()` overrode taunt fixation. **Expected**: Return early in `_on_backstabbed()` if `not backstab_staggers or current_state == State.ATTACK`; skip `_finish_turn_around()` target/facing switch if `is_taunted() and o != get_taunter()`. | Step 3 (3F, 3I) | `VER-01`, `VER-02` (`enm_15_backstab_respects_boss_attack_and_taunt`), `VER-09` |
| **ENM-16** | `scripts/enemies/enemy_ai.gd:919` | 🟡 **WARN** | `_should_flee()` omitted `and not is_taunted()`, allowing taunt-fixated enemies to flee from their taunter. **Expected**: Add `and not is_taunted()` to `_should_flee()`. | Step 3 (3H) | `VER-01`, `VER-02` (`enm_16_taunted_enemy_cannot_flee`) |
| **ENM-17** | `scripts/enemies/enemy_ai.gd:1041` (+ `shielded_guard.gd:92`) | 🟡 **WARN** | `_on_stagger_triggered()` entered `STAGGER` from `STUNNED`, cancelling knockdown (`×1.35` vuln); heavy knockdown hits (`player_landing`, `fin_sunder`) also double-emitted `state_changed`/`staggered`. **Expected**: Override `_should_stagger_on_hit()` on `EnemyAI` (and update `ShieldedGuard._should_stagger_on_hit()`) to return `false` while `State.STUNNED` or on `KNOCKDOWN_SOURCES` (when not `knockdown_immune`), and guard `_on_stagger_triggered()` against `State.STUNNED`. | Step 3 (3F, 3I), Step 6 (6B) | `VER-01`, `VER-02` (`enm_17_stunned_not_cancelled_and_no_double_emit`) |
| **ENM-18** | `scripts/enemies/enemy_base.gd:105` | 🟡 **WARN** | `evaluate_for_realm()` never updated `collision_mask` via `RealmManager.update_actor_collision_mask()`, leaving invisible Mirror-only prop colliders solid to enemies & `HexBolt` rays in Reality. **Expected**: `evaluate_for_realm()` calls `RealmManager.update_actor_collision_mask()` (preserving `LAYER_PLAYER_BLOCKER`, with offline fallback when `RealmManager.instance == null`). | Step 2 (2A) | `VER-01`, `VER-02` (`enm_18_enemy_collision_mask_syncs_realm`), `VER-03` |
| **ENM-19** | `scripts/enemies/phantom_twin.gd:112` | 🟡 **WARN** | `_begin_attack_strike()` used stale `_lunge_direction` captured in `start_windup()` instead of tracked `get_facing_direction()`. **Expected**: Lunge along `get_facing_direction() * lunge_speed` (setting only `.x` and `.z` to preserve gravity). | Step 5 (5B) | `VER-01`, `VER-02` (`enm_19_phantom_lunges_along_tracked_facing`) |
| **ENM-20** | `scripts/enemies/shielded_guard.gd:43` | 🟡 **WARN** | `is_shield_raised()` omitted `current_state == State.STUNNED`, blocking frontal hits and capping heavy hits to `10` dmg while knocked down in `Lie_Idle`. **Expected**: Return `false` in `is_shield_raised()` when `current_state == State.STUNNED`. | Step 6 (6A) | `VER-01`, `VER-02` (`enm_20_stunned_shield_guard_drops_shield`) |
| **ENM-21** | `scripts/enemies/squad_coordinator.gd:234` | 🟡 **WARN** | `request_attack_token()` evicted active waiters after `2.5 s` from *first* request timestamp (`< MAX_TOKEN_HOLD_SEC = 4.0 s`), starving longest-waiting enemies. **Expected**: Track `_last_wait_touch[id]` on every `request_attack_token()` call and evict only inactive/non-`CHASE` waiters or waiters whose `_last_wait_touch` exceeds `0.35 s`. | Step 1 (1A–1D) | `VER-01`, `VER-02` (`enm_21_token_waiter_not_evicted_while_active`) |
| **ENM-22** | `scripts/enemies/warden_boss.gd:180` | 🟡 **WARN** | `_begin_attack_strike()` used stale `_lunge_dir` from `start_windup()` (and reused old `_lunge_dir` if target was null) instead of `get_facing_direction()`. **Expected**: Remove `_lunge_dir`; use `get_facing_direction() * lunge_speed` in `_begin_attack_strike()`. | Step 8 (8A, 8C, 8D) | `VER-01`, `VER-02` (`enm_22_warden_lunges_along_tracked_facing`) |
| **ENM-23** | `scripts/enemies/warden_boss.gd:310` | 🟡 **WARN** | `_trigger_phase2_transition()` omitted `_clear_telegraph_flash()`, `_release_token()`, and transitioning out of `WINDUP`/`ATTACK`/`RECOVER`. **Expected**: Clear telegraph flash, release token, end hitbox swing, zero horizontal velocity, and call `_transition_to(State.STAGGER, phase2_transition_duration)`. | Step 8 (8F) | `VER-01`, `VER-02` (`enm_23_phase2_transition_clears_windup_telegraph_token`) |
| **ENM-24** | `scripts/enemies/archetype_enemy.gd:190` | 🔵 **LOW** | `start_windup()` ran `_try_blink_behind()` and `_show_slam_ring()` without checking `is_dead or not is_active` first. **Expected**: Guard `if is_dead or not is_active: return` at start of `start_windup()` and pass `_state_duration` to `_show_slam_ring()` only when `current_state == State.WINDUP`. | Step 7 (7C) | `VER-01`, `VER-02` (`enm_24_inactive_archetype_skips_windup_fx`) |
| **ENM-25** | `scripts/enemies/enemy_ai.gd:1112` | 🔵 **LOW** | Poise counter during first 50% of `WINDUP` called `release_token(self)` and stayed in `WINDUP` even if `request_attack_token()` was denied. **Expected**: Keep existing token (`_squad.has_token(self) or _squad.request_attack_token(self, p)`) instead of dropping and re-requesting; only counter-attack if `can_attack_now()` and token held/granted. | Step 3 (3K) | `VER-01`, `VER-02` (`enm_25_poise_counter_preserves_windup_token`) |
| **ENM-26** | `scripts/enemies/enemy_base.gd:314` (+ `enemy_ai.gd:1262, :1318`) | 🔵 **LOW** | `_hit_flash()` during windup could permanently restore stale `_telegraph_mat` if `_clear_telegraph_flash()` fired during the flash (or overwrite previous material on overlapping flashes). **Expected**: Track `_flash_previous` across overlapping flashes, track `_telegraph_active` in `EnemyAI`, and verify `_is_overlay_still_valid(restore)` inside `_hit_flash()` before restoring. | Step 2 (2B), Step 3 (3A, 3N) | `VER-01`, `VER-02` (`enm_26_hit_flash_never_restores_cleared_telegraph`) |

### B.2 Out-of-Scope Cross-Reference (Do NOT Edit Here)
- **`scripts/player/player_controller.gd:1024`** (`_acquire_target()` missing `is_hittable_now()` check, causing player sword magnetism to target Reality-immune `PhantomTwin`s in Reality): Fixed in **`plan/IdiotHandOffGuide_01_Combat.md` (`CMB-06`)**. Guide 02 does **not** modify `scripts/player/player_controller.gd`.

---

## C. File-Change Manifest

| File Path (Relative to Repo Root) | Operation | Step ID(s) | Ownership Boundary & Summary |
| :--- | :--- | :--- | :--- |
| `scripts/enemies/squad_coordinator.gd` | `modify` | Step 1 | Reset `_peak_engaged` on `reset()` and empty engagement transitions (`ENM-04`); track `_last_wait_touch` heartbeats for active waiters & check `can_attack_now()` (`ENM-21`, `ENM-02`). |
| `scripts/enemies/enemy_base.gd` | `modify` | Step 2 | Sync `collision_mask` inside `evaluate_for_realm()` (`ENM-18`); validate restored overlay via `_is_overlay_still_valid()` & `_flash_previous` (`ENM-26`). |
| `scripts/enemies/enemy_ai.gd` | `modify` | Step 3 | Add `_apply_gravity_and_slide()` across all states + chase/evade edge probe (`ENM-01`, `ENM-08`), `can_attack_now()` (`ENM-02`), `_revived_this_hit` + `enter_stunned` duration preserve (`ENM-03`), `_damage_scaled` (`ENM-07`), fixation-safe `apply_taunt()` (`ENM-12`), `consider_evade()` & timer clear (`ENM-13`), idle opening aggro/alert (`ENM-14`), backstab/taunt guards (`ENM-15`), `_should_flee()` taunt guard (`ENM-16`), `STUNNED` stagger/signal guards (`ENM-17`), windup token preservation on poise (`ENM-25`), `_telegraph_active` (`ENM-26`), and `_squad.refresh_engaged_peak()` hooks (`ENM-04`). |
| `scripts/enemies/skeleton_guard.gd` | `modify` | Step 4 | Exclude `["environmental", "pit", "player_execution", "execution"]` from self-revive, set `_revived_this_hit = true`, set `health = maxi(1, int(max_health * 0.5))`, and emit `health_changed` (`ENM-03`). |
| `scripts/enemies/phantom_twin.gd` | `modify` | Step 5 | Gate `can_attack_now()` to `_mirror_now()`, cancel windup/attack & token on Reality shift (`ENM-02`), lunge via `get_facing_direction()` preserving `velocity.y` (`ENM-19`, `ENM-01`). |
| `scripts/enemies/shielded_guard.gd` | `modify` | Step 6 | Drop shield when `State.STUNNED` (`ENM-20`); defer knockdown/stunned stagger filtering (`ENM-17`). |
| `scripts/enemies/archetype_enemy.gd` | `modify` | Step 7 | Single `DAMAGE_SCALE` (`ENM-07`), bolt `_process_evade_step()` + taunt gravity (`ENM-08`, `ENM-01`), bolt fire-band token gating (`ENM-09`), horizontal LoS + behind-target wall/gate/capsule checks in `_try_blink_behind()` (`ENM-10`), world-aligned `_update_slam_ring_transform()` (`ENM-11`), and `is_dead or not is_active` guard in `start_windup()` (`ENM-24`). |
| `scripts/enemies/warden_boss.gd` | `modify` | Step 8 | Pre-select `CLEAVE` in `_ready()`/`_on_enemy_reset()` and queue next move in `_enter_recover()` (`ENM-05`, `ENM-07`), clear `is_chest_rune_exposed` on exiting `RECOVER` (`ENM-06`), lunge via `get_facing_direction()` preserving `velocity.y` (`ENM-22`, `ENM-01`), and clean telegraph/token/state in `_trigger_phase2_transition()` (`ENM-23`). |
| `tests/enemies_ai_bugfix_regression_test.gd` | `create` | Step 9 | Permanent headless regression test (`26` assertions verifying `ENM-01`..`ENM-26`, using explicit `preload()` constants per `AGENTS.md` §3). |
| `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` | `modify` | Step 10 | Sync enemy/boss state-machine, move/telegraph, revive, threat, and archetype contracts (`§3.2`–`§3.4` only; avoids `§1`/`§2` owned by Guide 01). |
| `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | `modify` | Step 10 | Append 1 concise dated bullet line summarizing Guide 02 (`ENM-01`..`ENM-26`) verification (`AGENTS.md` Rule 1.3). |

---

## D. Ordered Implementation Steps

> **Strict Anchor Note**: Every GDScript file below uses **leading tabs** (`\t`). Preserve exact indentation when applying every block. Apply Steps 1–10 sequentially.

---

### Step 1 — Fix `SquadCoordinator` Session-Sticky Enrage & Active Token Waiter Eviction (`ENM-04`, `ENM-21`, `ENM-02`)

- **Prerequisites**: Clean `master` @ `1ca7464` (plus Guide 01 if applied first).
- **Target**: `scripts/enemies/squad_coordinator.gd`

#### Edit 1A — Add `_last_wait_touch`, `refresh_engaged_peak()`, and clear `_peak_engaged` in `reset()` / `unregister()`

**Target:** `scripts/enemies/squad_coordinator.gd`
**Action:** Replace block

**Find:**
```gdscript
var _members: Array[Node] = []
var _tokens: Dictionary = {}        # enemy instance_id -> grant time (sec)
var _token_target: Dictionary = {}  # enemy instance_id -> target instance_id
var _waiting_since: Dictionary = {} # enemy instance_id -> first request time
var _enemy_target: Dictionary = {}  # enemy instance_id -> target instance_id
var _last_attack_start: Dictionary = {} # target instance_id -> sec
var _peak_engaged: int = 0
```

**Replace with:**
```gdscript
var _members: Array[Node] = []
var _tokens: Dictionary = {}        # enemy instance_id -> grant time (sec)
var _token_target: Dictionary = {}  # enemy instance_id -> target instance_id
var _waiting_since: Dictionary = {} # enemy instance_id -> first request time
var _last_wait_touch: Dictionary = {} # enemy instance_id -> most recent request time
var _enemy_target: Dictionary = {}  # enemy instance_id -> target instance_id
var _last_attack_start: Dictionary = {} # target instance_id -> sec
var _peak_engaged: int = 0
```

#### Edit 1B — Update `unregister()`, `reset()`, `_prune()`, and `_physics_process()`

**Target:** `scripts/enemies/squad_coordinator.gd`
**Action:** Replace block

**Find:**
```gdscript
func unregister(e: Node) -> void:
	_members.erase(e)
	release_token(e)
	if e != null:
		_enemy_target.erase(e.get_instance_id())


func reset() -> void:
	_tokens.clear()
	_token_target.clear()
	_waiting_since.clear()
	_enemy_target.clear()
	_last_attack_start.clear()


func get_members() -> Array[Node]:
	return _members


func _prune() -> void:
	var i: int = _members.size() - 1
	while i >= 0:
		if not is_instance_valid(_members[i]):
			_members.remove_at(i)
		i -= 1
	var now: float = _now()
	for id in _tokens.keys():
		var obj: Object = instance_from_id(int(id))
		if obj == null or not is_instance_valid(obj) or now - float(_tokens[id]) > MAX_TOKEN_HOLD_SEC:
			_tokens.erase(id)
			_token_target.erase(id)
			_waiting_since.erase(id)
		elif obj is EnemyBase and ((obj as EnemyBase).is_dead or not (obj as EnemyBase).is_active):
			_tokens.erase(id)
			_token_target.erase(id)
			_waiting_since.erase(id)
		elif obj is EnemyAI:
			var ai: EnemyAI = obj as EnemyAI
			if ai.current_state != EnemyAI.State.CHASE and ai.current_state != EnemyAI.State.WINDUP and ai.current_state != EnemyAI.State.ATTACK:
				_tokens.erase(id)
				_token_target.erase(id)
				_waiting_since.erase(id)

	for wid in _waiting_since.keys():
		var wobj: Object = instance_from_id(int(wid))
		if wobj == null or not is_instance_valid(wobj):
			_waiting_since.erase(wid)
		elif wobj is EnemyBase and ((wobj as EnemyBase).is_dead or not (wobj as EnemyBase).is_active):
			_waiting_since.erase(wid)


# ------------------------------------------------------------------ per-target bookkeeping

func set_enemy_target(e: Node, target: Node) -> void:
	if e == null:
		return
	if target == null:
		_enemy_target.erase(e.get_instance_id())
	else:
		_enemy_target[e.get_instance_id()] = target.get_instance_id()
```

**Replace with:**
```gdscript
func _physics_process(_delta: float) -> void:
	if _peak_engaged > 0 and get_engaged(null).is_empty():
		_peak_engaged = 0


func unregister(e: Node) -> void:
	_members.erase(e)
	release_token(e)
	if e != null:
		_enemy_target.erase(e.get_instance_id())
	refresh_engaged_peak()


func reset() -> void:
	_tokens.clear()
	_token_target.clear()
	_waiting_since.clear()
	_last_wait_touch.clear()
	_enemy_target.clear()
	_last_attack_start.clear()
	_peak_engaged = 0


func get_members() -> Array[Node]:
	return _members


func _prune() -> void:
	var i: int = _members.size() - 1
	while i >= 0:
		if not is_instance_valid(_members[i]):
			_members.remove_at(i)
		i -= 1
	var now: float = _now()
	for id in _tokens.keys():
		var obj: Object = instance_from_id(int(id))
		if obj == null or not is_instance_valid(obj) or now - float(_tokens[id]) > MAX_TOKEN_HOLD_SEC:
			_tokens.erase(id)
			_token_target.erase(id)
			_waiting_since.erase(id)
			_last_wait_touch.erase(id)
		elif obj is EnemyBase and ((obj as EnemyBase).is_dead or not (obj as EnemyBase).is_active):
			_tokens.erase(id)
			_token_target.erase(id)
			_waiting_since.erase(id)
			_last_wait_touch.erase(id)
		elif obj is EnemyAI:
			var ai: EnemyAI = obj as EnemyAI
			if ai.current_state != EnemyAI.State.CHASE and ai.current_state != EnemyAI.State.WINDUP and ai.current_state != EnemyAI.State.ATTACK:
				_tokens.erase(id)
				_token_target.erase(id)
				_waiting_since.erase(id)
				_last_wait_touch.erase(id)

	for wid in _waiting_since.keys():
		var wobj: Object = instance_from_id(int(wid))
		if wobj == null or not is_instance_valid(wobj) or not (wobj is EnemyAI):
			_waiting_since.erase(wid)
			_last_wait_touch.erase(wid)
		else:
			var wai: EnemyAI = wobj as EnemyAI
			var inactive_waiter: bool = wai.is_dead or not wai.is_active or wai.current_state != EnemyAI.State.CHASE
			var touch_stale: bool = now - float(_last_wait_touch.get(wid, now)) > 0.35
			if inactive_waiter or touch_stale:
				_waiting_since.erase(wid)
				_last_wait_touch.erase(wid)

	refresh_engaged_peak()


# ------------------------------------------------------------------ per-target bookkeeping

func set_enemy_target(e: Node, target: Node) -> void:
	if e == null:
		return
	if target == null:
		_enemy_target.erase(e.get_instance_id())
	else:
		_enemy_target[e.get_instance_id()] = target.get_instance_id()
	refresh_engaged_peak()
```

#### Edit 1C — Update `release_token()`, `request_attack_token()`, and `_grant()`

**Target:** `scripts/enemies/squad_coordinator.gd`
**Action:** Replace block

**Find:**
```gdscript
func release_token(e: Node) -> void:
	if e == null:
		return
	_tokens.erase(e.get_instance_id())
	_token_target.erase(e.get_instance_id())
	_waiting_since.erase(e.get_instance_id())


func _tokens_on(target_id: int) -> int:
	var n: int = 0
	for id in _tokens.keys():
		if int(_token_target.get(id, 0)) == target_id:
			n += 1
	return n


## Called every frame by an enemy that is in range and ready to swing. Returns true when it may commit.
func request_attack_token(e: EnemyAI, target: Node3D) -> bool:
	_prune()
	var id: int = e.get_instance_id()
	if _tokens.has(id):
		return true
	if target == null:
		return false
	var tid: int = target.get_instance_id()
	var now: float = _now()
	if not _waiting_since.has(id):
		_waiting_since[id] = now
	# Taunted enemies are locked on and never wait for a token.
	if e.is_taunted():
		_grant(id, tid, now)
		return true
	var engaged: Array[EnemyAI] = get_engaged(target)
	var cap: int = max_attackers if engaged.size() >= 3 else maxi(1, mini(max_attackers, engaged.size()))
	var on_target: int = _tokens_on(tid)
	if on_target >= cap:
		return false
	if now - float(_last_attack_start.get(tid, -10.0)) < min_attack_gap and on_target > 0:
		return false
	# Fairness + flanking: highest priority waiter on the same target wins.
	var my_p: float = _priority(e, target, now)
	for other_id in _waiting_since.keys():
		if int(other_id) == id or _tokens.has(other_id):
			continue
		var o: Object = instance_from_id(int(other_id))
		if o == null or not is_instance_valid(o) or not (o is EnemyAI):
			_waiting_since.erase(other_id)
			continue
		var oe: EnemyAI = o as EnemyAI
		var stale: bool = now - float(_waiting_since[other_id]) > 2.5
		if oe.is_dead or not oe.is_active or stale:
			_waiting_since.erase(other_id)
			continue
		if int(_enemy_target.get(int(other_id), 0)) != tid:
			continue
		if _priority(oe, target, now) > my_p + 0.05:
			return false
	_grant(id, tid, now)
	return true


func _grant(id: int, tid: int, now: float) -> void:
	_tokens[id] = now
	_token_target[id] = tid
	_waiting_since.erase(id)
	_last_attack_start[tid] = now
```

**Replace with:**
```gdscript
func release_token(e: Node) -> void:
	if e == null:
		return
	var id: int = e.get_instance_id()
	_tokens.erase(id)
	_token_target.erase(id)
	_waiting_since.erase(id)
	_last_wait_touch.erase(id)


func _tokens_on(target_id: int) -> int:
	var n: int = 0
	for id in _tokens.keys():
		if int(_token_target.get(id, 0)) == target_id:
			n += 1
	return n


## Called every frame by an enemy that is in range and ready to swing. Returns true when it may commit.
func request_attack_token(e: EnemyAI, target: Node3D) -> bool:
	if e == null or not e.can_attack_now():
		release_token(e)
		return false
	_prune()
	var id: int = e.get_instance_id()
	if _tokens.has(id):
		return true
	if target == null:
		return false
	var tid: int = target.get_instance_id()
	var now: float = _now()
	if not _waiting_since.has(id):
		_waiting_since[id] = now
	_last_wait_touch[id] = now
	# Taunted enemies are locked on and never wait for a token.
	if e.is_taunted():
		_grant(id, tid, now)
		return true
	var engaged: Array[EnemyAI] = get_engaged(target)
	var cap: int = max_attackers if engaged.size() >= 3 else maxi(1, mini(max_attackers, engaged.size()))
	var on_target: int = _tokens_on(tid)
	if on_target >= cap:
		return false
	if now - float(_last_attack_start.get(tid, -10.0)) < min_attack_gap and on_target > 0:
		return false
	# Fairness + flanking: highest priority waiter on the same target wins.
	var my_p: float = _priority(e, target, now)
	for other_id in _waiting_since.keys():
		if int(other_id) == id or _tokens.has(other_id):
			continue
		var o: Object = instance_from_id(int(other_id))
		if o == null or not is_instance_valid(o) or not (o is EnemyAI):
			_waiting_since.erase(other_id)
			_last_wait_touch.erase(other_id)
			continue
		var oe: EnemyAI = o as EnemyAI
		var stale: bool = oe.current_state != EnemyAI.State.CHASE or now - float(_last_wait_touch.get(other_id, 0.0)) > 0.35
		if oe.is_dead or not oe.is_active or stale:
			_waiting_since.erase(other_id)
			_last_wait_touch.erase(other_id)
			continue
		if int(_enemy_target.get(int(other_id), 0)) != tid:
			continue
		if _priority(oe, target, now) > my_p + 0.05:
			return false
	_grant(id, tid, now)
	return true


func _grant(id: int, tid: int, now: float) -> void:
	_tokens[id] = now
	_token_target[id] = tid
	_waiting_since.erase(id)
	_last_wait_touch.erase(id)
	_last_attack_start[tid] = now
```

#### Edit 1D — Update `is_last_standing()` and add `refresh_engaged_peak()`

**Target:** `scripts/enemies/squad_coordinator.gd`
**Action:** Replace block

**Find:**
```gdscript
func is_last_standing(e: EnemyAI, target: Node3D) -> bool:
	var engaged: Array[EnemyAI] = get_engaged(null)
	_peak_engaged = maxi(_peak_engaged, engaged.size())
	if engaged.is_empty():
		_peak_engaged = 0
	return _peak_engaged >= 2 and engaged.size() == 1 and engaged[0] == e and target != null
```

**Replace with:**
```gdscript
func refresh_engaged_peak() -> void:
	var count: int = get_engaged(null).size()
	if count == 0:
		_peak_engaged = 0
	else:
		_peak_engaged = maxi(_peak_engaged, count)


func is_last_standing(e: EnemyAI, target: Node3D) -> bool:
	var engaged: Array[EnemyAI] = get_engaged(null)
	if engaged.is_empty():
		_peak_engaged = 0
		return false
	_peak_engaged = maxi(_peak_engaged, engaged.size())
	return _peak_engaged >= 2 and engaged.size() == 1 and engaged[0] == e and target != null
```

- **Postcondition**: `SquadCoordinator.reset()` resets `_peak_engaged = 0` and `_last_wait_touch`, `refresh_engaged_peak()` clears `_peak_engaged` when no enemies are engaged, and active waiters in `CHASE` keep their first wait timestamp indefinitely without premature `2.5 s` eviction.

---

### Step 2 — Fix `EnemyBase` Realm `collision_mask` Sync & Hit-Flash Stale Overlay Guard (`ENM-18`, `ENM-26`)

- **Prerequisites**: Step 1 applied.
- **Target**: `scripts/enemies/enemy_base.gd`

#### Edit 2A — Add `_flash_previous` member and update `evaluate_for_realm()` (`ENM-18`, `ENM-26`)

**Target:** `scripts/enemies/enemy_base.gd`
**Action:** Replace block

**Find:**
```gdscript
var _flash_mat: StandardMaterial3D = null
var _flash_serial: int = 0
var _wound_fx: CPUParticles3D = null
```

**Replace with:**
```gdscript
var _flash_mat: StandardMaterial3D = null
var _flash_serial: int = 0
var _flash_previous: Dictionary = {}
var _wound_fx: CPUParticles3D = null
```

#### Edit 2B — Update `evaluate_for_realm()` to sync `collision_mask` (`ENM-18`)

**Target:** `scripts/enemies/enemy_base.gd`
**Action:** Replace block

**Find:**
```gdscript
func evaluate_for_realm(active_realm: int, realms_merged: bool = false) -> void:
	if realms_merged or realm_affinity == RealmReactive.Affinity.BOTH_STATEFUL:
		is_realm_enabled = true
	elif realm_affinity == RealmReactive.Affinity.REALITY_ONLY:
		is_realm_enabled = (active_realm == 0)
	elif realm_affinity == RealmReactive.Affinity.MIRROR_ONLY:
		is_realm_enabled = (active_realm == 1)

	_refresh_active_state()
	on_realm_changed(active_realm)
	# Mirror = insight: in the (unmerged) Mirror every enemy shows its weak point.
	_on_mirror_insight(active_realm == 1 and not realms_merged)
```

**Replace with:**
```gdscript
func evaluate_for_realm(active_realm: int, realms_merged: bool = false) -> void:
	if realms_merged or realm_affinity == RealmReactive.Affinity.BOTH_STATEFUL:
		is_realm_enabled = true
	elif realm_affinity == RealmReactive.Affinity.REALITY_ONLY:
		is_realm_enabled = (active_realm == 0)
	elif realm_affinity == RealmReactive.Affinity.MIRROR_ONLY:
		is_realm_enabled = (active_realm == 1)

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null and (not realms_merged or rm.is_merged):
		rm.update_actor_collision_mask(self, active_realm as RealmManager.Realm)
	else:
		var cleared_mask: int = collision_mask & ~(RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR)
		var world_mask: int = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR
		if not realms_merged:
			world_mask = RealmManager.LAYER_WORLD_SHARED | (RealmManager.LAYER_WORLD_MIRROR if active_realm == 1 else RealmManager.LAYER_WORLD_REALITY)
		collision_mask = cleared_mask | world_mask

	_refresh_active_state()
	on_realm_changed(active_realm)
	# Mirror = insight: in the (unmerged) Mirror every enemy shows its weak point.
	_on_mirror_insight(active_realm == 1 and not realms_merged)
```

#### Edit 2C — Clear `_flash_previous` in `reset_enemy()` and guard restored material in `_hit_flash()` (`ENM-26`)

**Target:** `scripts/enemies/enemy_base.gd`
**Action:** Replace block

**Find:**
```gdscript
func reset_enemy() -> void:
	is_dead = false
	health = max_health
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_last_attacker = null
	var fwd: Vector3 = -_spawn_transform.basis.z
	fwd.y = 0.0
	facing_direction = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	_clear_wound_fx()
	_on_enemy_reset()
```

**Replace with:**
```gdscript
func reset_enemy() -> void:
	is_dead = false
	health = max_health
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_last_attacker = null
	_flash_serial += 1
	_flash_previous.clear()
	var fwd: Vector3 = -_spawn_transform.basis.z
	fwd.y = 0.0
	facing_direction = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	_clear_wound_fx()
	_on_enemy_reset()
```

#### Edit 2D — Add `_is_overlay_still_valid()` and update `_hit_flash()` (`ENM-26`)

**Target:** `scripts/enemies/enemy_base.gd`
**Action:** Replace block

**Find:**
```gdscript
## Additive white overlay for a few frames (restores whatever overlay was there).
func _hit_flash(color: Color, duration: float) -> void:
	var vis: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis == null:
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = color
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(vis, meshes)
	var previous: Dictionary = {}
	for mi in meshes:
		if mi.material_overlay != _flash_mat:
			previous[mi] = mi.material_overlay
		mi.material_overlay = _flash_mat
	_flash_serial += 1
	var serial: int = _flash_serial
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		if serial != _flash_serial or not is_instance_valid(self):
			return
		for mi2 in meshes:
			if is_instance_valid(mi2) and mi2.material_overlay == _flash_mat:
				mi2.material_overlay = previous.get(mi2, null) as Material
	)
```

**Replace with:**
```gdscript
## Virtual: subclasses (e.g. EnemyAI telegraph overlay) reject stale overlays whose effect already ended.
func _is_overlay_still_valid(mat: Material) -> bool:
	return mat != null


## Additive white overlay for a few frames (restores whatever overlay was there if still valid).
func _hit_flash(color: Color, duration: float) -> void:
	var vis: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis == null:
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = color
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(vis, meshes)
	for mi in meshes:
		if mi.material_overlay != _flash_mat:
			_flash_previous[mi] = mi.material_overlay
		mi.material_overlay = _flash_mat
	_flash_serial += 1
	var serial: int = _flash_serial
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		if serial != _flash_serial or not is_instance_valid(self):
			return
		for mi2 in meshes:
			if is_instance_valid(mi2) and mi2.material_overlay == _flash_mat:
				var restore: Material = _flash_previous.get(mi2, null) as Material
				if restore != null and not _is_overlay_still_valid(restore):
					restore = null
				mi2.material_overlay = restore
		_flash_previous.clear()
	)
```

- **Postcondition**: `EnemyBase.evaluate_for_realm()` updates `collision_mask` to the active realm's world layers while preserving `LAYER_PLAYER_BLOCKER`, and `_hit_flash()` never restores a cleared telegraph overlay.

---

### Step 3 — Fix `EnemyAI` Gravity, Edge Probe, Token/Evade/Aggro/Backstab/Flee/Stagger/Telegraph Bugs (`ENM-01`..`ENM-04`, `ENM-07`, `ENM-08`, `ENM-12`..`ENM-17`, `ENM-25`, `ENM-26`)

- **Prerequisites**: Steps 1–2 applied.
- **Target**: `scripts/enemies/enemy_ai.gd`

#### Edit 3A — Add `_telegraph_active`, `_damage_scaled`, `_revived_this_hit` and guard `DAMAGE_SCALE` in `_ready()`

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
var _telegraph_mat: StandardMaterial3D = null
var _telegraph_light: OmniLight3D = null
var _telegraph_tween: Tween = null
var _telegraph_meshes: Array[MeshInstance3D] = []

# Threat / aggro bookkeeping.
var _threat: Dictionary = {}          # target instance_id -> float
var _taunt_lock_id: int = 0
var _taunt_lock_timer: float = 0.0
var _retarget_timer: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _alert_pos: Vector3 = Vector3.ZERO
var _reaggro_block: float = 0.0
var _has_fled: bool = false
var _turn_to_id: int = 0
var _patrol_goal: Vector3 = Vector3.ZERO
var _patrol_timer: float = 0.0
var _state_icon: Label3D = null


func _ready() -> void:
	super._ready()
	attack_damage = int(float(attack_damage) * DAMAGE_SCALE)
```

**Replace with:**
```gdscript
var _telegraph_mat: StandardMaterial3D = null
var _telegraph_light: OmniLight3D = null
var _telegraph_tween: Tween = null
var _telegraph_meshes: Array[MeshInstance3D] = []
var _telegraph_active: bool = false

# Threat / aggro bookkeeping.
var _threat: Dictionary = {}          # target instance_id -> float
var _taunt_lock_id: int = 0
var _taunt_lock_timer: float = 0.0
var _retarget_timer: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _alert_pos: Vector3 = Vector3.ZERO
var _reaggro_block: float = 0.0
var _has_fled: bool = false
var _damage_scaled: bool = false
var _revived_this_hit: bool = false
var _turn_to_id: int = 0
var _patrol_goal: Vector3 = Vector3.ZERO
var _patrol_timer: float = 0.0
var _state_icon: Label3D = null


func _ready() -> void:
	super._ready()
	if not _damage_scaled:
		_damage_scaled = true
		attack_damage = int(float(attack_damage) * DAMAGE_SCALE)
```

#### Edit 3B — Add `can_attack_now()` and fix `apply_taunt()` same-source splash nudge (`ENM-02`, `ENM-12`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
func is_aggroed() -> bool:
	return current_state != State.IDLE and current_state != State.ALERT and current_state != State.RETURNING and current_state != State.DEAD
```

**Replace with:**
```gdscript
func can_attack_now() -> bool:
	return true


func is_aggroed() -> bool:
	return current_state != State.IDLE and current_state != State.ALERT and current_state != State.RETURNING and current_state != State.DEAD
```

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
	var sid: int = source.get_instance_id()
	# A nudge never overrides an existing fixation on someone else.
	if _fixated and _taunt_lock_id != sid and lock < 3.0:
		return
	_taunt_lock_id = sid
```

**Replace with:**
```gdscript
	var sid: int = source.get_instance_id()
	# Short splash nudges (< 3 s) never break or downgrade an existing fixation (same or other taunter).
	if is_fixated() and lock < 3.0:
		if _taunt_lock_id == sid:
			_fixation_far_t = 0.0
		return
	_taunt_lock_id = sid
```

#### Edit 3C — Preserve `velocity.y` in `start_windup()`, `enter_stagger()`, `enter_stunned()` (`ENM-01`, `ENM-03`, `ENM-17`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
	if _enraged:
		dur *= 0.8
	velocity = Vector3.ZERO
	_transition_to(State.WINDUP, dur)
	_begin_telegraph_flash(dur)
	attack_telegraphed.emit(attack_name, dur)


func enter_stagger(custom_duration: float = -1.0) -> void:
	if is_dead:
		return
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	var dur: float = stagger_duration if custom_duration < 0.0 else custom_duration
	velocity = Vector3.ZERO
	_transition_to(State.STAGGER, dur)
	staggered.emit(dur)


func enter_stunned(custom_duration: float = -1.0) -> void:
	if is_dead or knockdown_immune:
		return
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	var dur: float = stun_duration if custom_duration < 0.0 else custom_duration
	velocity = Vector3.ZERO
	_transition_to(State.STUNNED, dur)
	knocked_down.emit(dur)
	staggered.emit(dur)
```

**Replace with:**
```gdscript
	if _enraged:
		dur *= 0.8
	velocity.x = 0.0
	velocity.z = 0.0
	_transition_to(State.WINDUP, dur)
	_begin_telegraph_flash(dur)
	attack_telegraphed.emit(attack_name, dur)


func enter_stagger(custom_duration: float = -1.0) -> void:
	if is_dead:
		return
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	var dur: float = stagger_duration if custom_duration < 0.0 else custom_duration
	velocity.x = 0.0
	velocity.z = 0.0
	_transition_to(State.STAGGER, dur)
	staggered.emit(dur)


func enter_stunned(custom_duration: float = -1.0) -> void:
	if is_dead or knockdown_immune:
		return
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	var dur: float = stun_duration if custom_duration < 0.0 else custom_duration
	if current_state == State.STUNNED:
		dur = maxf(_state_timer, dur)
	velocity.x = 0.0
	velocity.z = 0.0
	_transition_to(State.STUNNED, dur)
	knocked_down.emit(dur)
	staggered.emit(dur)
```

#### Edit 3D — Fix `consider_evade()` disallowing `State.IDLE` & requiring valid targets (`ENM-13`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
func consider_evade(player: Node3D, is_heavy: bool, windup: float) -> void:
	if is_dead or not is_active or _evade_cooldown > 0.0 or evade_skill <= 0.0:
		return
	if current_state != State.CHASE and current_state != State.RECOVER and current_state != State.IDLE:
		return
	if _squad != null and _squad.has_token(self) and current_state == State.CHASE:
		return
	var chance: float = evade_skill * (1.0 if is_heavy else 0.45)
	if windup < 0.12:
		chance *= 0.6
	if _rng.randf() > chance:
		_evade_cooldown = 0.8
		return
	var away: Vector3 = global_position - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else -get_facing_direction()
	var side: Vector3 = Vector3(-away.z, 0.0, away.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
	_evade_dir = (away * 0.55 + side * 0.85).normalized()
	_evade_timer = 0.32
	_evade_cooldown = _rng.randf_range(2.2, 3.4)
	set_facing_direction(player.global_position - global_position)
	var f: Vector3 = get_facing_direction()
	var r: Vector3 = Vector3(-f.z, 0.0, f.x)
	if absf(_evade_dir.dot(r)) > absf(_evade_dir.dot(f)):
		_evade_clip = "Dodge_Right" if _evade_dir.dot(r) > 0.0 else "Dodge_Left"
	else:
		_evade_clip = "Dodge_Backward"
	if current_state != State.CHASE:
		_transition_to(State.CHASE, 0.0)
	evaded.emit(_evade_dir)
```

**Replace with:**
```gdscript
func consider_evade(player: Node3D, is_heavy: bool, windup: float) -> void:
	if is_dead or not is_active or _evade_cooldown > 0.0 or evade_skill <= 0.0:
		return
	if current_state != State.CHASE and current_state != State.RECOVER:
		return
	if player == null or not is_instance_valid(player) or not _is_valid_target(player) or get_current_target() == null:
		return
	if _squad != null and _squad.has_token(self) and current_state == State.CHASE:
		return
	var chance: float = evade_skill * (1.0 if is_heavy else 0.45)
	if windup < 0.12:
		chance *= 0.6
	if _rng.randf() > chance:
		_evade_cooldown = 0.8
		return
	var away: Vector3 = global_position - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else -get_facing_direction()
	var side: Vector3 = Vector3(-away.z, 0.0, away.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
	_evade_dir = (away * 0.55 + side * 0.85).normalized()
	_evade_timer = 0.32
	_evade_cooldown = _rng.randf_range(2.2, 3.4)
	set_facing_direction(player.global_position - global_position)
	var f: Vector3 = get_facing_direction()
	var r: Vector3 = Vector3(-f.z, 0.0, f.x)
	if absf(_evade_dir.dot(r)) > absf(_evade_dir.dot(f)):
		_evade_clip = "Dodge_Right" if _evade_dir.dot(r) > 0.0 else "Dodge_Left"
	else:
		_evade_clip = "Dodge_Backward"
	if current_state == State.RECOVER:
		_on_recover_finished()
	if current_state != State.CHASE:
		_transition_to(State.CHASE, 0.0)
	evaded.emit(_evade_dir)
```

#### Edit 3E — Fix `apply_damage()` self-revive & idle opening aggro (`ENM-03`, `ENM-14`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
	var was_idle: bool = not is_aggroed()
	var ok: bool = super.apply_damage(int(round(amt)), is_heavy, source_type, attacker)
	if not ok or is_dead:
		return ok
	if attacker is Node3D:
		add_threat(attacker, amt * damage_threat_mult * (backstab_threat_mult if backstab else 1.0))
	if source_type in KNOCKDOWN_SOURCES and not knockdown_immune:
		enter_stunned()
	elif backstab:
		_on_backstabbed(attacker)
	if _should_flee():
		_start_flee()
	elif was_idle and attacker is Node3D and _is_valid_target(attacker as Node3D) and current_state != State.STUNNED and current_state != State.STAGGER:
		_set_target(attacker as Node3D)
		_reaggro_block = 0.0
		_transition_to(State.CHASE, 0.0)
		if _squad != null:
			_squad.alert(self, attacker as Node3D)
	return ok
```

**Replace with:**
```gdscript
	_revived_this_hit = false
	var was_idle: bool = not is_aggroed()
	var ok: bool = super.apply_damage(int(round(amt)), is_heavy, source_type, attacker)
	if not ok or is_dead:
		return ok
	if attacker is Node3D:
		add_threat(attacker, amt * damage_threat_mult * (backstab_threat_mult if backstab else 1.0))
	if was_idle and attacker is Node3D and _is_valid_target(attacker as Node3D):
		_set_target(attacker as Node3D)
		_reaggro_block = 0.0
		if _squad != null:
			_squad.alert(self, attacker as Node3D)
	if _revived_this_hit:
		_revived_this_hit = false
		_turn_to_id = 0
		return ok
	if source_type in KNOCKDOWN_SOURCES and not knockdown_immune:
		enter_stunned()
	elif backstab:
		_on_backstabbed(attacker)
	if _should_flee():
		_start_flee()
	elif was_idle and attacker is Node3D and _is_valid_target(attacker as Node3D) and current_state != State.STUNNED and current_state != State.STAGGER:
		_transition_to(State.CHASE, 0.0)
	return ok
```

#### Edit 3F — Fix `_on_backstabbed()` and add `_should_stagger_on_hit()` override (`ENM-15`, `ENM-17`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
func _on_backstabbed(attacker: Node) -> void:
	backstabbed.emit(attacker)
	_turn_to_id = attacker.get_instance_id() if attacker != null else 0
	if backstab_staggers and current_state != State.ATTACK:
		enter_stagger(backstab_stagger)
	elif attacker is Node3D:
		set_facing_direction((attacker as Node3D).global_position - global_position)
```

**Replace with:**
```gdscript
func _should_stagger_on_hit(is_heavy: bool, source_type: String) -> bool:
	if current_state == State.STUNNED:
		return false
	if source_type in KNOCKDOWN_SOURCES and not knockdown_immune:
		return false
	return super._should_stagger_on_hit(is_heavy, source_type)


func _on_backstabbed(attacker: Node) -> void:
	backstabbed.emit(attacker)
	if not backstab_staggers or current_state == State.ATTACK:
		return
	_turn_to_id = attacker.get_instance_id() if attacker != null else 0
	enter_stagger(backstab_stagger)
```

#### Edit 3G — Fix `_patrol()`, `_process_alert()`, and `_process_chase()` (`ENM-01`, `ENM-02`, `ENM-08`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
func _patrol(delta: float) -> void:
	if patrol_radius <= 0.05:
		velocity = Vector3.ZERO
		return
	_patrol_timer -= delta
	var to_goal: Vector3 = _patrol_goal - global_position
	to_goal.y = 0.0
	if _patrol_timer <= 0.0 or to_goal.length() < 0.35:
		if _patrol_timer <= 0.0:
			_patrol_timer = _rng.randf_range(3.0, 6.0)
			var ang: float = _rng.randf() * TAU
			_patrol_goal = _home + Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(0.5, patrol_radius)
		velocity = Vector3.ZERO
		return
	_steer_toward(to_goal.normalized() * move_speed * 0.42, delta, true)


func _process_alert(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	var seen: Node3D = _nearest_visible_candidate(detection_range * 1.25)
	if seen != null:
		_aggro_on(seen, false)
		return
	var to_p: Vector3 = _alert_pos - global_position
	to_p.y = 0.0
	if to_p.length() > 1.2 and global_position.distance_to(_home) < max_chase_distance:
		_steer_toward(to_p.normalized() * move_speed * 0.75, delta, true)
		set_facing_direction(to_p)
	else:
		velocity = Vector3.ZERO
		# Look around.
		set_facing_direction(get_facing_direction().rotated(Vector3.UP, sin(_state_elapsed * 2.2) * 2.4 * delta))
	if _state_timer <= 0.0:
		if global_position.distance_to(_home) > 1.5:
			_begin_return()
		else:
			_transition_to(State.IDLE, 0.0)


func _process_chase(delta: float, target: Node3D) -> void:
	if target == null:
		_lose_target()
		return

	var to_p: Vector3 = target.global_position - global_position
	to_p.y = 0.0
	var dist: float = to_p.length()
	# Leash: chased too far from home -> give up and walk back to the patrol.
	if global_position.distance_to(_home) > max_chase_distance and dist > attack_range * 1.5 and not is_taunted():
		_begin_return()
		return
	if dist > detection_range * 2.2 and not is_taunted():
		_threat.erase(target.get_instance_id())
		_lose_target()
		return
	var dir_to_p: Vector3 = to_p / dist if dist > 0.001 else get_facing_direction()

	if _taunt_timer > 0.0:
		set_facing_direction(dir_to_p)
		velocity = Vector3.ZERO
		return

	if _evade_timer > 0.0:
		_evade_timer -= delta
		var k: float = clampf(_evade_timer / 0.32, 0.0, 1.0)
		velocity = _evade_dir * lerpf(2.0, 8.5, k)
		set_facing_direction(dir_to_p)
		if is_inside_tree():
			move_and_slide()
		return

	if _squad != null:
		_enraged = _squad.is_last_standing(self, target)
	var speed: float = move_speed * (1.25 if _enraged else 1.0)
	var desired: Vector3

	var ring_r: float = attack_range + ring_margin + _ring_jitter
	if health < max_health * 0.3:
		ring_r += 1.2

	# Only request a token when within striking/commitment reach; otherwise approach without starving ring mates.
	var can_request_token: bool = dist <= ring_r + 0.5
	var has_token: bool = false
	if _squad == null:
		has_token = true
	elif can_request_token:
		has_token = _squad.request_attack_token(self, target)
	else:
		_release_token()

	if has_token:
		if dist <= attack_range:
			start_windup()
			return
		desired = dir_to_p * speed * 1.15
	else:
		# Hold a spaced ring just outside reach, circling to find a flank.
		var goal: Vector3 = _squad.get_ring_position(self, target, ring_r, _orbit_sign) if _squad != null else target.global_position
		var to_goal: Vector3 = goal - global_position
		to_goal.y = 0.0
		var g_len: float = to_goal.length()
		var move_rate: float = speed if dist > ring_r + 1.2 else speed * 0.62
		desired = to_goal / g_len * minf(move_rate, g_len * 3.0) if g_len > 0.05 else Vector3.ZERO
		# Too close while not attacking: back off.
		if dist < attack_range + 0.4:
			desired += -dir_to_p * speed * 0.8

	if _squad != null:
		desired += _squad.get_separation(self) * speed * 1.4
	set_facing_direction(dir_to_p)
	var dv: Vector3 = Vector3(desired.x, 0.0, desired.z)
	var cur: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(dv, 22.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	if is_inside_tree():
		move_and_slide()
```

**Replace with:**
```gdscript
func _patrol(delta: float) -> void:
	if patrol_radius <= 0.05:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_and_slide(delta)
		return
	_patrol_timer -= delta
	var to_goal: Vector3 = _patrol_goal - global_position
	to_goal.y = 0.0
	if _patrol_timer <= 0.0 or to_goal.length() < 0.35:
		if _patrol_timer <= 0.0:
			_patrol_timer = _rng.randf_range(3.0, 6.0)
			var ang: float = _rng.randf() * TAU
			_patrol_goal = _home + Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(0.5, patrol_radius)
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_and_slide(delta)
		return
	_steer_toward(to_goal.normalized() * move_speed * 0.42, delta, true)


func _process_alert(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	var seen: Node3D = _nearest_visible_candidate(detection_range * 1.25)
	if seen != null:
		_aggro_on(seen, false)
		return
	var to_p: Vector3 = _alert_pos - global_position
	to_p.y = 0.0
	if to_p.length() > 1.2 and global_position.distance_to(_home) < max_chase_distance:
		_steer_toward(to_p.normalized() * move_speed * 0.75, delta, true)
		set_facing_direction(to_p)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_and_slide(delta)
		# Look around.
		set_facing_direction(get_facing_direction().rotated(Vector3.UP, sin(_state_elapsed * 2.2) * 2.4 * delta))
	if _state_timer <= 0.0:
		if global_position.distance_to(_home) > 1.5:
			_begin_return()
		else:
			_transition_to(State.IDLE, 0.0)


func _process_chase(delta: float, target: Node3D) -> void:
	if target == null:
		_lose_target()
		return

	var to_p: Vector3 = target.global_position - global_position
	to_p.y = 0.0
	var dist: float = to_p.length()
	# Leash: chased too far from home -> give up and walk back to the patrol.
	if global_position.distance_to(_home) > max_chase_distance and dist > attack_range * 1.5 and not is_taunted():
		_begin_return()
		return
	if dist > detection_range * 2.2 and not is_taunted():
		_threat.erase(target.get_instance_id())
		_lose_target()
		return
	var dir_to_p: Vector3 = to_p / dist if dist > 0.001 else get_facing_direction()

	if _taunt_timer > 0.0:
		set_facing_direction(dir_to_p)
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_and_slide(delta)
		return

	if _process_evade_step(delta, dir_to_p):
		return

	if _squad != null:
		_enraged = _squad.is_last_standing(self, target)
	var speed: float = move_speed * (1.25 if _enraged else 1.0)
	var desired: Vector3

	var ring_r: float = attack_range + ring_margin + _ring_jitter
	if health < max_health * 0.3:
		ring_r += 1.2

	# Only request a token when attack-capable and within striking/commitment reach.
	var can_attack: bool = can_attack_now()
	var can_request_token: bool = can_attack and dist <= ring_r + 0.5
	var has_token: bool = false
	if not can_attack:
		_release_token()
	elif _squad == null:
		has_token = true
	elif can_request_token:
		has_token = _squad.request_attack_token(self, target)
	else:
		_release_token()

	if has_token:
		if dist <= attack_range:
			start_windup()
			return
		desired = dir_to_p * speed * 1.15
	else:
		# Hold a spaced ring just outside reach, circling to find a flank.
		var goal: Vector3 = _squad.get_ring_position(self, target, ring_r, _orbit_sign) if _squad != null else target.global_position
		var to_goal: Vector3 = goal - global_position
		to_goal.y = 0.0
		var g_len: float = to_goal.length()
		var move_rate: float = speed if dist > ring_r + 1.2 else speed * 0.62
		desired = to_goal / g_len * minf(move_rate, g_len * 3.0) if g_len > 0.05 else Vector3.ZERO
		# Too close while not attacking: back off.
		if dist < attack_range + 0.4:
			desired += -dir_to_p * speed * 0.8

	if _squad != null:
		desired += _squad.get_separation(self) * speed * 1.4
	set_facing_direction(dir_to_p)
	var dv: Vector3 = _clamp_edges(Vector3(desired.x, 0.0, desired.z))
	var cur: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(dv, 22.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	_apply_gravity_and_slide(delta)
```

#### Edit 3H — Fix `_process_returning()`, `_should_flee()`, `_process_windup()`, `_begin_attack_strike()`, `_process_attack()`, `_enter_recover()`, `_process_recover()`, `_process_stagger()`, `_process_stunned()` (`ENM-01`, `ENM-16`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
func _process_returning(delta: float) -> void:
	var to_h: Vector3 = _home - global_position
	to_h.y = 0.0
	if to_h.length() < 0.6:
		velocity = Vector3.ZERO
		_patrol_goal = _home
		_transition_to(State.IDLE, 0.0)
		return
	if _reaggro_block <= 0.0:
		var seen: Node3D = _nearest_visible_candidate(detection_range * 0.6)
		if seen != null and seen.global_position.distance_to(_home) < max_chase_distance:
			_aggro_on(seen, false)
			return
	set_facing_direction(to_h)
	_steer_toward(to_h.normalized() * move_speed * 0.95, delta, false)
	# Hopelessly stuck (e.g. dropped down a level): snap home once the timer runs long.
	if _state_elapsed > 14.0:
		global_position = _home
		velocity = Vector3.ZERO


func _should_flee() -> bool:
	return flee_health_ratio > 0.0 and not _has_fled and not is_dead and float(health) / float(maxi(1, max_health)) <= flee_health_ratio \
		and current_state != State.STUNNED


func _start_flee() -> void:
	_has_fled = true
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	_transition_to(State.FLEEING, flee_duration)
	fleeing_started.emit()


func _process_fleeing(delta: float, target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	var away: Vector3 = -get_facing_direction()
	if target != null:
		away = global_position - target.global_position
		away.y = 0.0
	# Bias toward home so fleeing never drags the enemy out of its arena.
	var to_h: Vector3 = _home - global_position
	to_h.y = 0.0
	if to_h.length() > max_chase_distance * 0.6:
		away = away.normalized() * 0.4 + to_h.normalized()
	if away.length_squared() < 0.001:
		away = Vector3.FORWARD
	set_facing_direction(away)
	_steer_toward(away.normalized() * move_speed * 1.15, delta, true)
	if _state_timer <= 0.0:
		# Cornered courage: turn and fight again.
		_taunt_timer = 0.35
		_transition_to(State.CHASE, 0.0)


func _process_windup(delta: float, target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	# Track the target through the first half of the wind-up, then commit (dodgeable).
	if target != null and _state_elapsed < _state_duration * 0.55:
		var to_p: Vector3 = target.global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.01:
			var cf: Vector3 = get_facing_direction()
			var ya: float = lerp_angle(atan2(cf.x, cf.z), atan2(to_p.x, to_p.z), clampf(8.0 * delta, 0.0, 1.0))
			set_facing_direction(Vector3(sin(ya), 0.0, cos(ya)))
	if _state_timer <= 0.0:
		_begin_attack_strike()


func _begin_attack_strike() -> void:
	_release_telegraph_flash()
	_transition_to(State.ATTACK, attack_active_duration)
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.affects_player = true
		hb.affects_enemies = false
		hb.begin_swing(attack_damage, false, "enemy_" + attack_name)
	# Step into the swing so strikes carry weight (subclasses with real lunges override velocity).
	velocity = get_facing_direction() * attack_lunge_speed
	attack_started.emit(attack_name, attack_damage)


func _process_attack(delta: float, _target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if is_inside_tree() and velocity.length_squared() > 0.001:
		move_and_slide()
	if _state_timer <= 0.0:
		_enter_recover()


func _enter_recover(custom_recover: float = -1.0) -> void:
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	velocity = Vector3.ZERO
	_release_token()
	var dur: float = recover_duration if custom_recover < 0.0 else custom_recover
	if _enraged:
		dur *= 0.7
	_transition_to(State.RECOVER, dur)
	recovery_started.emit(dur)


func _process_recover(delta: float, _target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if _state_timer <= 0.0:
		_on_recover_finished()
		_transition_to(State.CHASE, 0.0)


func _process_stagger(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if _state_timer <= 0.0:
		_finish_turn_around()
		_transition_to(State.CHASE, 0.0)


func _process_stunned(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	velocity = Vector3.ZERO
	if _state_timer <= 0.0:
		_finish_turn_around()
		_transition_to(State.CHASE, 0.0)
```

**Replace with:**
```gdscript
func _process_returning(delta: float) -> void:
	var to_h: Vector3 = _home - global_position
	to_h.y = 0.0
	if to_h.length() < 0.6:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_and_slide(delta)
		_patrol_goal = _home
		_transition_to(State.IDLE, 0.0)
		return
	if _reaggro_block <= 0.0:
		var seen: Node3D = _nearest_visible_candidate(detection_range * 0.6)
		if seen != null and seen.global_position.distance_to(_home) < max_chase_distance:
			_aggro_on(seen, false)
			return
	set_facing_direction(to_h)
	_steer_toward(to_h.normalized() * move_speed * 0.95, delta, false)
	# Hopelessly stuck (e.g. dropped down a level): snap home once the timer runs long.
	if _state_elapsed > 14.0:
		global_position = _home
		velocity = Vector3.ZERO


func _should_flee() -> bool:
	return flee_health_ratio > 0.0 and not _has_fled and not is_dead and not is_taunted() \
		and float(health) / float(maxi(1, max_health)) <= flee_health_ratio \
		and current_state != State.STUNNED


func _start_flee() -> void:
	_has_fled = true
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	_transition_to(State.FLEEING, flee_duration)
	fleeing_started.emit()


func _process_fleeing(delta: float, target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	var away: Vector3 = -get_facing_direction()
	if target != null:
		away = global_position - target.global_position
		away.y = 0.0
	# Bias toward home so fleeing never drags the enemy out of its arena.
	var to_h: Vector3 = _home - global_position
	to_h.y = 0.0
	if to_h.length() > max_chase_distance * 0.6:
		away = away.normalized() * 0.4 + to_h.normalized()
	if away.length_squared() < 0.001:
		away = Vector3.FORWARD
	set_facing_direction(away)
	_steer_toward(away.normalized() * move_speed * 1.15, delta, true)
	if _state_timer <= 0.0:
		# Cornered courage: turn and fight again.
		_taunt_timer = 0.35
		_transition_to(State.CHASE, 0.0)


func _process_windup(delta: float, target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_and_slide(delta)
	# Track the target through the first half of the wind-up, then commit (dodgeable).
	if target != null and _state_elapsed < _state_duration * 0.55:
		var to_p: Vector3 = target.global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.01:
			var cf: Vector3 = get_facing_direction()
			var ya: float = lerp_angle(atan2(cf.x, cf.z), atan2(to_p.x, to_p.z), clampf(8.0 * delta, 0.0, 1.0))
			set_facing_direction(Vector3(sin(ya), 0.0, cos(ya)))
	if _state_timer <= 0.0:
		_begin_attack_strike()


func _begin_attack_strike() -> void:
	_release_telegraph_flash()
	_transition_to(State.ATTACK, attack_active_duration)
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.affects_player = true
		hb.affects_enemies = false
		hb.begin_swing(attack_damage, false, "enemy_" + attack_name)
	# Step into the swing so strikes carry weight (subclasses with real lunges override horizontal velocity).
	var lunge_vel: Vector3 = get_facing_direction() * attack_lunge_speed
	velocity.x = lunge_vel.x
	velocity.z = lunge_vel.z
	attack_started.emit(attack_name, attack_damage)


func _process_attack(delta: float, _target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	_apply_gravity_and_slide(delta)
	if _state_timer <= 0.0:
		_enter_recover()


func _enter_recover(custom_recover: float = -1.0) -> void:
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	velocity.x = 0.0
	velocity.z = 0.0
	_release_token()
	var dur: float = recover_duration if custom_recover < 0.0 else custom_recover
	if _enraged:
		dur *= 0.7
	_transition_to(State.RECOVER, dur)
	recovery_started.emit(dur)


func _process_recover(delta: float, _target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_and_slide(delta)
	if _state_timer <= 0.0:
		_on_recover_finished()
		_transition_to(State.CHASE, 0.0)


func _process_stagger(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_and_slide(delta)
	if _state_timer <= 0.0:
		_finish_turn_around()
		_transition_to(State.CHASE, 0.0)


func _process_stunned(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_and_slide(delta)
	if _state_timer <= 0.0:
		_finish_turn_around()
		_transition_to(State.CHASE, 0.0)
```

#### Edit 3I — Guard `_finish_turn_around()` against taunt fixation and `_on_stagger_triggered()` against `State.STUNNED` (`ENM-15`, `ENM-17`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
## Backstab reaction: whip around to face whoever stabbed us (and make them the target).
func _finish_turn_around() -> void:
	if _turn_to_id == 0:
		return
	var o: Object = instance_from_id(_turn_to_id)
	_turn_to_id = 0
	if o is Node3D and is_instance_valid(o) and _is_valid_target(o as Node3D):
		set_facing_direction((o as Node3D).global_position - global_position)
		_set_target(o as Node3D)
		_taunt_timer = 0.2


func _on_recover_finished() -> void:
	pass


func _on_stagger_triggered() -> void:
	enter_stagger()
```

**Replace with:**
```gdscript
## Backstab reaction: whip around to face whoever stabbed us (unless pinned on another taunter).
func _finish_turn_around() -> void:
	if _turn_to_id == 0:
		return
	var o: Object = instance_from_id(_turn_to_id)
	_turn_to_id = 0
	if is_taunted() and o != get_taunter():
		return
	if o is Node3D and is_instance_valid(o) and _is_valid_target(o as Node3D):
		set_facing_direction((o as Node3D).global_position - global_position)
		_set_target(o as Node3D)
		_taunt_timer = 0.2


func _on_recover_finished() -> void:
	pass


func _on_stagger_triggered() -> void:
	if current_state == State.STUNNED:
		return
	enter_stagger()
```

#### Edit 3J — Add `_clamp_edges()`, `_process_evade_step()`, and `_apply_gravity_and_slide()` helpers; update `_steer_toward()` (`ENM-01`, `ENM-08`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
## Steering helper with an edge probe so wandering / fleeing never walks off a ledge.
func _steer_toward(desired: Vector3, delta: float, probe_edges: bool) -> void:
	var dv: Vector3 = Vector3(desired.x, 0.0, desired.z)
	if probe_edges and dv.length_squared() > 0.01 and not _has_floor_ahead(dv.normalized()):
		var side := Vector3(-dv.z, 0.0, dv.x)
		dv = side if _has_floor_ahead(side.normalized()) else Vector3.ZERO
	if _squad != null:
		dv += _squad.get_separation(self) * move_speed
	var cur: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(dv, 18.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	if not is_on_floor():
		velocity.y = maxf(velocity.y - 20.0 * delta, -20.0)
	else:
		velocity.y = 0.0
	if is_inside_tree():
		move_and_slide()
```

**Replace with:**
```gdscript
func _clamp_edges(dv: Vector3) -> Vector3:
	if dv.length_squared() <= 0.01 or _has_floor_ahead(dv.normalized()):
		return dv
	var side := Vector3(-dv.z, 0.0, dv.x)
	if _has_floor_ahead(side.normalized()):
		return side
	if _has_floor_ahead(-side.normalized()):
		return -side
	return Vector3.ZERO


func _process_evade_step(delta: float, dir_to_p: Vector3) -> bool:
	if _evade_timer <= 0.0:
		return false
	_evade_timer = maxf(0.0, _evade_timer - delta)
	var k: float = clampf(_evade_timer / 0.32, 0.0, 1.0)
	var evade_vel: Vector3 = _evade_dir * lerpf(2.0, 8.5, k)
	if evade_vel.length_squared() > 0.01 and not _has_floor_ahead(evade_vel.normalized()):
		evade_vel = Vector3.ZERO
	velocity.x = evade_vel.x
	velocity.z = evade_vel.z
	set_facing_direction(dir_to_p)
	_apply_gravity_and_slide(delta)
	return true


func _apply_gravity_and_slide(delta: float) -> void:
	if not is_inside_tree():
		return
	if not is_on_floor():
		velocity.y = maxf(velocity.y - 20.0 * delta, -20.0)
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()


## Steering helper with an edge probe so wandering / fleeing never walks off a ledge.
func _steer_toward(desired: Vector3, delta: float, probe_edges: bool) -> void:
	var dv: Vector3 = Vector3(desired.x, 0.0, desired.z)
	if probe_edges:
		dv = _clamp_edges(dv)
	if _squad != null:
		dv += _squad.get_separation(self) * move_speed
		if probe_edges:
			dv = _clamp_edges(dv)
	var cur: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(dv, 18.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	_apply_gravity_and_slide(delta)
```

#### Edit 3K — Preserve existing token during `WINDUP` poise counter (`ENM-25`, `ENM-02`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
	if _flinch_chain > max_flinch_chain:
		# Broke free of the stun-lock: brace, then punish the button-masher.
		_flinch_chain = 0
		_poise_timer = poise_duration
		if _rng.randf() < counter_attack_chance:
			var p: Node3D = _resolve_target_player()
			if p != null and global_position.distance_to(p.global_position) <= attack_range + 0.9:
				var got_token: bool = true
				if _squad != null:
					_squad.release_token(self)
					got_token = _squad.request_attack_token(self, p)
				if got_token:
					start_windup(windup_duration * 0.65)
		return
```

**Replace with:**
```gdscript
	if _flinch_chain > max_flinch_chain:
		# Broke free of the stun-lock: brace, then punish the button-masher.
		_flinch_chain = 0
		_poise_timer = poise_duration
		if can_attack_now() and _rng.randf() < counter_attack_chance:
			var p: Node3D = _resolve_target_player()
			if p != null and global_position.distance_to(p.global_position) <= attack_range + 0.9:
				var got_token: bool = true
				if _squad != null:
					got_token = _squad.has_token(self) or _squad.request_attack_token(self, p)
				if got_token:
					start_windup(windup_duration * 0.65)
		return
```

#### Edit 3L — Reset `_revived_this_hit` in `_on_enemy_reset()` (`ENM-03`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
	_has_fled = false
	_turn_to_id = 0
```

**Replace with:**
```gdscript
	_has_fled = false
	_revived_this_hit = false
	_turn_to_id = 0
```

#### Edit 3M — Refresh squad engaged peak & clear `_evade_timer` on transitions (`ENM-04`, `ENM-13`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
func _transition_to(next_state: State, duration: float) -> void:
	current_state = next_state
	_state_timer = duration
	_state_duration = duration
	_state_elapsed = 0.0
	state_changed.emit(current_state)
```

**Replace with:**
```gdscript
func _refresh_active_state() -> void:
	super._refresh_active_state()
	if not is_active and _squad != null and is_instance_valid(_squad):
		_squad.refresh_engaged_peak()


func _transition_to(next_state: State, duration: float) -> void:
	if next_state != State.CHASE:
		_evade_timer = 0.0
	current_state = next_state
	_state_timer = duration
	_state_duration = duration
	_state_elapsed = 0.0
	if not is_aggroed() and _squad != null and is_instance_valid(_squad):
		_squad.refresh_engaged_peak()
	state_changed.emit(current_state)
```

#### Edit 3N — Track `_telegraph_active` and validate telegraph overlay restore (`ENM-26`)

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
	_telegraph_meshes.clear()
	_collect_meshes(vis_root, _telegraph_meshes)
	for mi in _telegraph_meshes:
		mi.material_overlay = _telegraph_mat
```

**Replace with:**
```gdscript
	_telegraph_active = true
	_telegraph_meshes.clear()
	_collect_meshes(vis_root, _telegraph_meshes)
	for mi in _telegraph_meshes:
		mi.material_overlay = _telegraph_mat
```

**Target:** `scripts/enemies/enemy_ai.gd`
**Action:** Replace block

**Find:**
```gdscript
func _clear_telegraph_flash() -> void:
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	_telegraph_tween = null
	for mi in _telegraph_meshes:
		if is_instance_valid(mi) and mi.material_overlay == _telegraph_mat:
			mi.material_overlay = null
	_telegraph_meshes.clear()
	if _telegraph_light != null and is_instance_valid(_telegraph_light):
		_telegraph_light.light_energy = 0.0
		_telegraph_light.visible = false
```

**Replace with:**
```gdscript
func _is_overlay_still_valid(mat: Material) -> bool:
	if mat == _telegraph_mat:
		return _telegraph_active
	return mat != null


func _clear_telegraph_flash() -> void:
	_telegraph_active = false
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	_telegraph_tween = null
	for mi in _telegraph_meshes:
		if is_instance_valid(mi) and mi.material_overlay == _telegraph_mat:
			mi.material_overlay = null
	_telegraph_meshes.clear()
	if _telegraph_light != null and is_instance_valid(_telegraph_light):
		_telegraph_light.light_energy = 0.0
		_telegraph_light.visible = false
```

- **Postcondition**: All `EnemyAI` states apply gravity + floor edge probing, evade/token/aggro/backstab/flee/stagger/telegraph state invariants hold, and subclasses inherit shared helpers cleanly.

---

### Step 4 — Fix `SkeletonGuard` Self-Revive Exclusions, `FloatingHPBar` Signal, & `3.0 s` Stun Retention (`ENM-03`)

- **Prerequisites**: Step 3 applied.
- **Target**: `scripts/enemies/skeleton_guard.gd`

#### Edit 4A — Exclude `"environmental"`/`"pit"`, emit `health_changed`, and mark `_revived_this_hit`

**Target:** `scripts/enemies/skeleton_guard.gd`
**Action:** Replace block

**Find:**
```gdscript
func _die(source_type: String) -> void:
	if not _has_revived and source_type != "player_execution" and source_type != "execution":
		_has_revived = true
		health = int(max_health * 0.5)
		enter_stunned(3.0)
		return
	super._die(source_type)
```

**Replace with:**
```gdscript
func _die(source_type: String) -> void:
	if not _has_revived and source_type not in ["environmental", "pit", "player_execution", "execution"]:
		_has_revived = true
		_revived_this_hit = true
		health = maxi(1, int(max_health * 0.5))
		health_changed.emit(health, max_health)
		enter_stunned(3.0)
		return
	super._die(source_type)
```

- **Postcondition**: `SkeletonGuard` dies cleanly on `"environmental"` (Cracked Pillar & `PitKillZone`), `"pit"`, `"player_execution"`, and `"execution"`; on first normal lethal hit it sets `50%` HP, updates `FloatingHPBar` via `health_changed`, and enters a full `3.0 s` `STUNNED` revive state even on knockdown or backstab blows.

---

### Step 5 — Fix `PhantomTwin` Reality Token/Freeze Lock & Tracked Lunge Direction (`ENM-02`, `ENM-19`, `ENM-01`)

- **Prerequisites**: Step 3 applied.
- **Target**: `scripts/enemies/phantom_twin.gd`

#### Edit 5A — Remove unused `_lunge_direction` and override `can_attack_now()` + Reality shift cleanup

**Target:** `scripts/enemies/phantom_twin.gd`
**Action:** Replace block

**Find:**
```gdscript
@export var reality_ghost_transparency: float = 0.6

var _lunge_direction: Vector3 = Vector3.FORWARD
var _shimmer_cd: int = 0
```

**Replace with:**
```gdscript
@export var reality_ghost_transparency: float = 0.6

var _shimmer_cd: int = 0
```

#### Edit 5B — Cancel active attack/windup on Reality shift, gate `can_attack_now()`, and lunge via `get_facing_direction()`

**Target:** `scripts/enemies/phantom_twin.gd`
**Action:** Replace block

**Find:**
```gdscript
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

**Replace with:**
```gdscript
func is_hittable_now() -> bool:
	return _mirror_now()


func can_attack_now() -> bool:
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
	if not _mirror_now():
		_release_token()
		if current_state == State.WINDUP or current_state == State.ATTACK:
			_clear_telegraph_flash()
			var hb: Hitbox3D = get_attack_hitbox()
			if hb != null:
				hb.end_swing()
			velocity.x = 0.0
			velocity.z = 0.0
			_transition_to(State.CHASE, 0.0)


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
	super.start_windup(custom_windup)


func _begin_attack_strike() -> void:
	super._begin_attack_strike()
	var lunge_vel: Vector3 = get_facing_direction() * lunge_speed
	velocity.x = lunge_vel.x
	velocity.z = lunge_vel.z
```

- **Postcondition**: `PhantomTwin` never requests/holds attack tokens or freezes in Reality, cleanly cancels any windup/attack when shifted back to Reality, and lunges along its tracked `get_facing_direction()` while preserving `velocity.y`.

---

### Step 6 — Fix `ShieldedGuard` Shield Drop While Stunned & Knockdown Stagger Filtering (`ENM-20`, `ENM-17`)

- **Prerequisites**: Step 3 applied.
- **Target**: `scripts/enemies/shielded_guard.gd`

#### Edit 6A — Drop shield when `current_state == State.STUNNED` (`ENM-20`)

**Target:** `scripts/enemies/shielded_guard.gd`
**Action:** Replace block

**Find:**
```gdscript
func is_shield_raised() -> bool:
	if is_dead or current_state == State.STAGGER:
		return false
```

**Replace with:**
```gdscript
func is_shield_raised() -> bool:
	if is_dead or current_state == State.STAGGER or current_state == State.STUNNED:
		return false
```

#### Edit 6B — Defer `State.STUNNED` & `KNOCKDOWN_SOURCES` in `_should_stagger_on_hit()` (`ENM-17`)

**Target:** `scripts/enemies/shielded_guard.gd`
**Action:** Replace block

**Find:**
```gdscript
func _should_stagger_on_hit(is_heavy: bool, source_type: String) -> bool:
	if source_type == "environmental":
		return true
	if is_shield_raised() and is_attacker_in_front(_last_attacker):
		return false
	return is_heavy
```

**Replace with:**
```gdscript
func _should_stagger_on_hit(is_heavy: bool, source_type: String) -> bool:
	if current_state == State.STUNNED:
		return false
	if source_type in KNOCKDOWN_SOURCES and not knockdown_immune:
		return false
	if source_type == "environmental":
		return true
	if is_shield_raised() and is_attacker_in_front(_last_attacker):
		return false
	return super._should_stagger_on_hit(is_heavy, source_type)
```

- **Postcondition**: Knocked-down `ShieldedGuard`s no longer deflect frontal attacks (`is_shield_raised() == false`), and knockdown sources emit `state_changed`/`staggered` only once.

---

### Step 7 — Fix `ArchetypeEnemy` Damage Scaling, Bolt Evade/Tokens, Stalker Blink LoS/Wall Checks, Slam Ring Alignment & Inactive Guard (`ENM-07`..`ENM-11`, `ENM-24`, `ENM-01`)

- **Prerequisites**: Step 3 applied.
- **Target**: `scripts/enemies/archetype_enemy.gd`

#### Edit 7A — Remove duplicate `DAMAGE_SCALE` multiplication in `apply_archetype()` (`ENM-07`)

**Target:** `scripts/enemies/archetype_enemy.gd`
**Action:** Replace block

**Find:**
```gdscript
	stagger_duration = a.stagger_duration
	attack_damage = int(float(a.attack_damage) * DAMAGE_SCALE)
	attack_name = a.attack_name
```

**Replace with:**
```gdscript
	stagger_duration = a.stagger_duration
	attack_damage = int(float(a.attack_damage) * DAMAGE_SCALE) if _damage_scaled else a.attack_damage
	attack_name = a.attack_name
```

#### Edit 7B — Fix bolt `_process_chase()` gravity, evade timer decay, and fire-band token gating (`ENM-01`, `ENM-08`, `ENM-09`)

**Target:** `scripts/enemies/archetype_enemy.gd`
**Action:** Replace block

**Find:**
```gdscript
	var dir: Vector3 = to_p / dist if dist > 0.001 else get_facing_direction()
	set_facing_direction(dir)
	if _taunt_timer > 0.0:
		velocity = Vector3.ZERO
		return
	var pref: float = archetype.preferred_range
	var has_token: bool = _squad == null or _squad.request_attack_token(self, target)
	if has_token and dist <= attack_range and dist >= pref * 0.45:
		start_windup()
		return
```

**Replace with:**
```gdscript
	var dir: Vector3 = to_p / dist if dist > 0.001 else get_facing_direction()
	set_facing_direction(dir)
	if _taunt_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_and_slide(delta)
		return
	if _process_evade_step(delta, dir):
		return
	var pref: float = archetype.preferred_range
	var in_fire_band: bool = dist <= attack_range and dist >= pref * 0.45
	var has_token: bool = false
	if in_fire_band:
		has_token = _squad == null or _squad.request_attack_token(self, target)
	else:
		_release_token()
	if has_token:
		start_windup()
		return
```

#### Edit 7C — Guard `start_windup()`, add wall/gate/capsule checks in `_try_blink_behind()`, and align slam ring in world space (`ENM-10`, `ENM-11`, `ENM-24`)

**Target:** `scripts/enemies/archetype_enemy.gd`
**Action:** Replace block

**Find:**
```gdscript
func start_windup(custom_windup: float = -1.0) -> void:
	var t: Node3D = _resolve_target_player()
	if get_kind() == "melee" and archetype != null and archetype.blink_cooldown > 0.0 and _blink_cd <= 0.0 and t != null:
		_try_blink_behind(t)
	super.start_windup(custom_windup)
	if get_kind() == "slam":
		_show_slam_ring(windup_duration if custom_windup < 0.0 else custom_windup)


## Shade step: reappear behind the target (floor-checked), so the stab lands as a backstab.
func _try_blink_behind(t: Node3D) -> void:
	var f: Vector3 = Vector3.FORWARD
	if t.has_method("get_facing_direction"):
		f = t.call("get_facing_direction")
	var spot: Vector3 = t.global_position - f.normalized() * 1.3
	if not is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 1.6, collision_mask & (RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR), [get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Color = archetype.bolt_color
	GoreFXScript.flash_light(self, global_position + Vector3.UP, col, 3.0, 0.25, 4.0)
	GoreFXScript.dust_puff(self, global_position, 0.5, 12, Color(col.r, col.g, col.b, 0.5), 1.5)
	global_position = (hit["position"] as Vector3)
	GoreFXScript.dust_puff(self, global_position, 0.5, 12, Color(col.r, col.g, col.b, 0.5), 1.5)
	GameFeelScript.play_sound(self, "mirror_whisper", global_position, -4.0, 1.4)
	_blink_cd = archetype.blink_cooldown
	set_facing_direction(t.global_position - global_position)
```

**Replace with:**
```gdscript
func start_windup(custom_windup: float = -1.0) -> void:
	if is_dead or not is_active:
		return
	var t: Node3D = _resolve_target_player()
	if get_kind() == "melee" and archetype != null and archetype.blink_cooldown > 0.0 and _blink_cd <= 0.0 and t != null:
		_try_blink_behind(t)
	super.start_windup(custom_windup)
	if get_kind() == "slam" and current_state == State.WINDUP:
		_show_slam_ring(_state_duration)


func _process_windup(delta: float, target: Node3D) -> void:
	super._process_windup(delta, target)
	_update_slam_ring_transform()


## Shade step: reappear behind the target (wall/gate/blocker & floor-checked), so the stab lands as a backstab.
func _try_blink_behind(t: Node3D) -> void:
	if not is_inside_tree() or get_world_3d() == null:
		return
	var f: Vector3 = Vector3.FORWARD
	if t.has_method("get_facing_direction"):
		f = t.call("get_facing_direction")
	var flat_f := Vector3(f.x, 0.0, f.z)
	if flat_f.length_squared() < 0.0001:
		flat_f = Vector3.FORWARD
	var back_dir: Vector3 = -flat_f.normalized()
	var spot: Vector3 = t.global_position + back_dir * 1.3
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return
	var floor_mask: int = collision_mask & (RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR)
	var wall_mask: int = floor_mask | RealmManager.LAYER_PLAYER_BLOCKER
	var excl: Array[RID] = [get_rid()]
	if t is CollisionObject3D:
		excl.append((t as CollisionObject3D).get_rid())
	var los_q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.9, t.global_position + Vector3.UP * 0.9, wall_mask, excl)
	if not space.intersect_ray(los_q).is_empty():
		return
	var probe_from: Vector3 = t.global_position + Vector3.UP * 0.9
	var probe_to: Vector3 = spot + Vector3.UP * 0.9
	var wall_q := PhysicsRayQueryParameters3D.create(probe_from, probe_to, wall_mask, excl)
	var wall_hit: Dictionary = space.intersect_ray(wall_q)
	if not wall_hit.is_empty():
		var hit_pos: Vector3 = wall_hit["position"] as Vector3
		var clear_dist: float = Vector2(hit_pos.x - t.global_position.x, hit_pos.z - t.global_position.z).length() - 0.55
		if clear_dist < 0.55:
			return
		spot = t.global_position + back_dir * clear_dist
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 1.6, floor_mask, [get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	var dest: Vector3 = hit["position"] as Vector3
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.6
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, dest + Vector3.UP * 0.95)
	sq.collision_mask = wall_mask
	sq.exclude = excl
	if not space.intersect_shape(sq, 1).is_empty():
		return
	var col: Color = archetype.bolt_color
	GoreFXScript.flash_light(self, global_position + Vector3.UP, col, 3.0, 0.25, 4.0)
	GoreFXScript.dust_puff(self, global_position, 0.5, 12, Color(col.r, col.g, col.b, 0.5), 1.5)
	global_position = dest
	GoreFXScript.dust_puff(self, global_position, 0.5, 12, Color(col.r, col.g, col.b, 0.5), 1.5)
	GameFeelScript.play_sound(self, "mirror_whisper", global_position, -4.0, 1.4)
	_blink_cd = archetype.blink_cooldown
	set_facing_direction(t.global_position - global_position)
```

#### Edit 7D — Update `_show_slam_ring()` and add `_update_slam_ring_transform()` (`ENM-11`)

**Target:** `scripts/enemies/archetype_enemy.gd`
**Action:** Replace block

**Find:**
```gdscript
	_ring_mesh.position = get_facing_direction() * 0.8 + Vector3.UP * 0.06
	_ring_mesh.scale = Vector3(archetype.aoe_radius * 0.3, 0.25, archetype.aoe_radius * 0.3)
	_ring_mesh.visible = true
```

**Replace with:**
```gdscript
	_ring_mesh.scale = Vector3(archetype.aoe_radius * 0.3, 0.25, archetype.aoe_radius * 0.3)
	_ring_mesh.visible = true
	_update_slam_ring_transform()
```

**Target:** `scripts/enemies/archetype_enemy.gd`
**Action:** Replace block

**Find:**
```gdscript
func _hide_slam_ring() -> void:
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
	if _ring_mesh != null and is_instance_valid(_ring_mesh):
		_ring_mesh.visible = false
```

**Replace with:**
```gdscript
func _update_slam_ring_transform() -> void:
	if _ring_mesh == null or not is_instance_valid(_ring_mesh) or not _ring_mesh.visible:
		return
	var target_world: Vector3 = global_position + get_facing_direction() * 0.8 + Vector3.UP * 0.06
	if is_inside_tree():
		_ring_mesh.global_position = target_world
	else:
		_ring_mesh.position = to_local(target_world)


func _hide_slam_ring() -> void:
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
	if _ring_mesh != null and is_instance_valid(_ring_mesh):
		_ring_mesh.visible = false
```

- **Postcondition**: Archetype `attack_damage` scales once (`1.4×`), bolt evades decay and never hoard tokens out of range, `Shade Stalker` never blinks through walls or locked gates, `Grave Brute` slam ring aligns to world-space impact center across rotated roamers and windup tracking, and inactive/dead archetypes ignore `start_windup()`.

---

### Step 8 — Fix `WardenBoss` Move Range Sync, Chest Rune Exposure Lifecycle, Tracked Lunge, & Phase 2 Transition (`ENM-05`, `ENM-06`, `ENM-07`, `ENM-22`, `ENM-23`, `ENM-01`)

- **Prerequisites**: Step 3 applied.
- **Target**: `scripts/enemies/warden_boss.gd`

#### Edit 8A — Remove `_lunge_dir` and set `_damage_scaled = true` + initial `CLEAVE` selection in `_ready()` (`ENM-05`, `ENM-07`, `ENM-22`)

**Target:** `scripts/enemies/warden_boss.gd`
**Action:** Replace block

**Find:**
```gdscript
var _transition_timer: float = 0.0
var _move_counter: int = 0
var _lunge_dir: Vector3 = Vector3.BACK


func _ready() -> void:
	_health_scaled = true
	super._ready()
```

**Replace with:**
```gdscript
var _transition_timer: float = 0.0
var _move_counter: int = 0


func _ready() -> void:
	_health_scaled = true
	_damage_scaled = true
	super._ready()
	select_next_move(BossMove.CLEAVE)
```

#### Edit 8B — Apply gravity during `PHASE_2_TRANSITION` (`ENM-01`)

**Target:** `scripts/enemies/warden_boss.gd`
**Action:** Replace block

**Find:**
```gdscript
	if current_phase == Phase.PHASE_2_TRANSITION:
		_transition_timer = maxf(0.0, _transition_timer - delta)
		if _transition_timer <= 0.0:
			complete_phase2_transition_now()
		return
```

**Replace with:**
```gdscript
	if current_phase == Phase.PHASE_2_TRANSITION:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_and_slide(delta)
		_transition_timer = maxf(0.0, _transition_timer - delta)
		if _transition_timer <= 0.0:
			complete_phase2_transition_now()
		return
```

#### Edit 8C — Add `_queue_next_move()` and avoid re-selecting move inside `start_windup()` (`ENM-05`, `ENM-22`)

**Target:** `scripts/enemies/warden_boss.gd`
**Action:** Replace block

**Find:**
```gdscript
func start_windup(custom_windup: float = -1.0) -> void:
	if current_phase == Phase.PHASE_2_TRANSITION:
		return

	if _move_counter % 2 == 0:
		select_next_move(BossMove.CLEAVE)
	else:
		select_next_move(BossMove.LUNGE)
	_move_counter += 1

	var p: Node3D = _resolve_target_player()
	if p != null:
		var dir: Vector3 = p.global_position - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			_lunge_dir = dir.normalized()

	var w_dur: float = phase1_windup_duration if current_phase == Phase.PHASE_1_SPLIT else phase2_windup_duration
	if custom_windup >= 0.0:
		w_dur = custom_windup
	super.start_windup(w_dur)
```

**Replace with:**
```gdscript
func _queue_next_move() -> void:
	_move_counter += 1
	select_next_move(BossMove.CLEAVE if _move_counter % 2 == 0 else BossMove.LUNGE)


func start_windup(custom_windup: float = -1.0) -> void:
	if current_phase == Phase.PHASE_2_TRANSITION or is_dead or not is_active:
		return

	var w_dur: float = phase1_windup_duration if current_phase == Phase.PHASE_1_SPLIT else phase2_windup_duration
	if custom_windup >= 0.0:
		w_dur = custom_windup
	super.start_windup(w_dur)
```

#### Edit 8D — Lunge along tracked `get_facing_direction()` preserving `velocity.y` (`ENM-22`, `ENM-01`)

**Target:** `scripts/enemies/warden_boss.gd`
**Action:** Replace block

**Find:**
```gdscript
func _begin_attack_strike() -> void:
	super._begin_attack_strike()
	if current_move == BossMove.LUNGE:
		velocity = _lunge_dir * lunge_speed
	else:
		velocity = Vector3.ZERO
```

**Replace with:**
```gdscript
func _begin_attack_strike() -> void:
	super._begin_attack_strike()
	if current_move == BossMove.LUNGE:
		var lunge_vel: Vector3 = get_facing_direction() * lunge_speed
		velocity.x = lunge_vel.x
		velocity.z = lunge_vel.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0
```

#### Edit 8E — Queue next move in `_enter_recover()` and clear `is_chest_rune_exposed` on exiting `RECOVER` (`ENM-05`, `ENM-06`)

**Target:** `scripts/enemies/warden_boss.gd`
**Action:** Replace block

**Find:**
```gdscript
func _enter_recover(custom_recover: float = -1.0) -> void:
	if phase2_chain_enabled and custom_recover < 0.0 and current_phase == Phase.PHASE_2_MERGED and current_move == BossMove.CLEAVE and not is_dead:
		var hb: Hitbox3D = get_attack_hitbox()
		if hb != null:
			hb.end_swing()
		velocity = Vector3.ZERO
		start_windup(phase2_chain_windup) # _move_counter alternation guarantees the follow-up is a Lunge
		return
	var r_dur: float = phase1_recovery_window if current_phase == Phase.PHASE_1_SPLIT else phase2_recovery_window
	if custom_recover >= 0.0:
		r_dur = custom_recover
	super._enter_recover(r_dur)
	if current_phase == Phase.PHASE_1_SPLIT:
		is_chest_rune_exposed = true
		_update_rune_glow()
		chest_rune_exposed_changed.emit(true, r_dur)


func _on_recover_finished() -> void:
	if is_chest_rune_exposed:
		is_chest_rune_exposed = false
		_update_rune_glow()
		chest_rune_exposed_changed.emit(false, 0.0)
```

**Replace with:**
```gdscript
func _clear_chest_rune_exposure() -> void:
	if is_chest_rune_exposed:
		is_chest_rune_exposed = false
		_update_rune_glow()
		chest_rune_exposed_changed.emit(false, 0.0)


func _transition_to(next_state: State, duration: float) -> void:
	if next_state != State.RECOVER:
		_clear_chest_rune_exposure()
	super._transition_to(next_state, duration)


func _enter_recover(custom_recover: float = -1.0) -> void:
	if phase2_chain_enabled and custom_recover < 0.0 and current_phase == Phase.PHASE_2_MERGED and current_move == BossMove.CLEAVE and not is_dead:
		var hb: Hitbox3D = get_attack_hitbox()
		if hb != null:
			hb.end_swing()
		velocity.x = 0.0
		velocity.z = 0.0
		_queue_next_move()
		start_windup(phase2_chain_windup) # _move_counter alternation guarantees the follow-up is a Lunge
		return
	var r_dur: float = phase1_recovery_window if current_phase == Phase.PHASE_1_SPLIT else phase2_recovery_window
	if custom_recover >= 0.0:
		r_dur = custom_recover
	super._enter_recover(r_dur)
	if current_phase == Phase.PHASE_1_SPLIT:
		is_chest_rune_exposed = true
		_update_rune_glow()
		chest_rune_exposed_changed.emit(true, r_dur)
	_queue_next_move()


func _on_recover_finished() -> void:
	_clear_chest_rune_exposure()
```

#### Edit 8F — Guard `_should_stagger_on_hit()` against `STAGGER -> STAGGER` & clean up `_trigger_phase2_transition()` (`ENM-06`, `ENM-23`)

**Target:** `scripts/enemies/warden_boss.gd`
**Action:** Replace block

**Find:**
```gdscript
func _should_stagger_on_hit(is_heavy: bool, _source_type: String) -> bool:
	return is_heavy and is_vulnerable_to_full_damage()


func _on_damage_taken(_final_damage: int, _is_heavy: bool, _source_type: String) -> void:
	if current_phase == Phase.PHASE_1_SPLIT and health <= _phase2_threshold():
		health = maxi(health, _phase2_threshold())
		_trigger_phase2_transition()


func _trigger_phase2_transition() -> void:
	current_phase = Phase.PHASE_2_TRANSITION
	_transition_timer = phase2_transition_duration
	velocity = Vector3.ZERO

	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()

	if is_chest_rune_exposed:
		is_chest_rune_exposed = false
		_update_rune_glow()
		chest_rune_exposed_changed.emit(false, 0.0)
```

**Replace with:**
```gdscript
func _should_stagger_on_hit(is_heavy: bool, _source_type: String) -> bool:
	return is_heavy and is_vulnerable_to_full_damage() and current_state != State.STAGGER


func _on_damage_taken(_final_damage: int, _is_heavy: bool, _source_type: String) -> void:
	if current_phase == Phase.PHASE_1_SPLIT and health <= _phase2_threshold():
		health = maxi(health, _phase2_threshold())
		_trigger_phase2_transition()


func _trigger_phase2_transition() -> void:
	_clear_telegraph_flash()
	_release_token()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()

	current_phase = Phase.PHASE_2_TRANSITION
	_transition_timer = phase2_transition_duration
	velocity.x = 0.0
	velocity.z = 0.0
	_transition_to(State.STAGGER, phase2_transition_duration)
```

#### Edit 8G — Reset `select_next_move(BossMove.CLEAVE)` in `_on_enemy_reset()` and reuse `_clear_chest_rune_exposure()` in `_die()` (`ENM-05`, `ENM-06`)

**Target:** `scripts/enemies/warden_boss.gd`
**Action:** Replace block

**Find:**
```gdscript
func _on_enemy_reset() -> void:
	var was_phase1: bool = (current_phase == Phase.PHASE_1_SPLIT)
	var was_exposed: bool = is_chest_rune_exposed
	current_phase = Phase.PHASE_1_SPLIT
	current_move = BossMove.CLEAVE
	is_chest_rune_exposed = false
	_transition_timer = 0.0
	_move_counter = 0
	windup_duration = phase1_windup_duration
	recover_duration = phase1_recovery_window
```

**Replace with:**
```gdscript
func _on_enemy_reset() -> void:
	var was_phase1: bool = (current_phase == Phase.PHASE_1_SPLIT)
	var was_exposed: bool = is_chest_rune_exposed
	current_phase = Phase.PHASE_1_SPLIT
	_transition_timer = 0.0
	_move_counter = 0
	select_next_move(BossMove.CLEAVE)
	is_chest_rune_exposed = false
	windup_duration = phase1_windup_duration
	recover_duration = phase1_recovery_window
```

**Target:** `scripts/enemies/warden_boss.gd`
**Action:** Replace block

**Find:**
```gdscript
func _die(source_type: String) -> void:
	print("[Warden] defeated by '%s' (phase %d, last attacker %s)" % [source_type, int(current_phase), str(_last_attacker)])
	if is_chest_rune_exposed:
		is_chest_rune_exposed = false
		chest_rune_exposed_changed.emit(false, 0.0)
	_update_rune_glow()
	super._die(source_type)
```

**Replace with:**
```gdscript
func _die(source_type: String) -> void:
	print("[Warden] defeated by '%s' (phase %d, last attacker %s)" % [source_type, int(current_phase), str(_last_attacker)])
	_clear_chest_rune_exposure()
	_update_rune_glow()
	super._die(source_type)
```

- **Postcondition**: `WardenBoss` always chases to the exact `attack_range` (`2.8 m` Cleave / `5.0 m` Lunge) matching its queued move, clears `is_chest_rune_exposed` when staggered out of Phase 1 `RECOVER`, lunges along tracked `get_facing_direction()`, resets cleanly to `CLEAVE` (`2.8 m`), and clears telegraph/token/windup on Phase 2 transition.

---

### Step 9 — Create Dedicated Enemies & AI Regression Test (`ENM-01` .. `ENM-26`)

- **Prerequisites**: Steps 1–8 applied (`tests/enemies_ai_bugfix_regression_test.gd` must not exist beforehand).
- **Target:** `tests/enemies_ai_bugfix_regression_test.gd`
- **Action:** Create

**Content:**
```gdscript
extends SceneTree
## Headless regression test for Guide 02 (ENM-01..ENM-26).
## Exercises all 26 Enemies & AI fixes without editor class-cache dependency.
## Run: godot --headless --path . -s res://tests/enemies_ai_bugfix_regression_test.gd

const SquadAIConfigScript := preload("res://addons/parallax_squad_ai/squad_ai_config.gd")
const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const EnemyAIScript := preload("res://scripts/enemies/enemy_ai.gd")
const ArchetypeEnemyScript := preload("res://scripts/enemies/archetype_enemy.gd")
const PhantomTwinScript := preload("res://scripts/enemies/phantom_twin.gd")
const ShieldedGuardScript := preload("res://scripts/enemies/shielded_guard.gd")
const SkeletonGuardScript := preload("res://scripts/enemies/skeleton_guard.gd")
const SquadCoordinatorScript := preload("res://scripts/enemies/squad_coordinator.gd")
const WardenBossScript := preload("res://scripts/enemies/warden_boss.gd")
const RealmManagerScript := preload("res://scripts/core/realm_manager.gd")
const EncounterDirectorScript := preload("res://scripts/core/encounter_director.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const AllySquadManagerScript := preload("res://scripts/allies/ally_squad_manager.gd")
const SquadAllyScript := preload("res://scripts/allies/squad_ally.gd")

var _results: Array[String] = []
var _main: Node = null
var _level: Node = null
var _player: Node3D = null
var _mgr: Node = null
var _coord: SquadCoordinator = null
var _spawned: Array[EnemyBase] = []
var _idx: int = 0


func _initialize() -> void:
	SquadAIConfigScript.force_offline()
	create_timer(150.0).timeout.connect(func() -> void:
		print("[enm_reg] WATCHDOG TIMEOUT")
		quit(2))
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()


func _check(id_name: String, ok: bool, detail: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", id_name, detail]
	_results.append(line)
	print("[enm_reg] ", line)


func _spawn(kind: String, pos: Vector3, face_toward: Vector3 = Vector3(0, 0, -140)) -> EnemyBase:
	_idx += 1
	var e: EnemyBase = _level.call("_add_roamer", _level, kind, "Test_%s_%d" % [kind, _idx], pos, EncounterDirectorScript.Section.ENTRY, face_toward) as EnemyBase
	if e != null:
		_spawned.append(e)
	return e


func _cleanup_test_enemies() -> void:
	for e in _spawned:
		if is_instance_valid(e):
			e.is_dead = true
			e.set_section_enabled(false)
			e.queue_free()
	_spawned.clear()
	if _coord != null and is_instance_valid(_coord):
		_coord.reset()
		_coord.max_attackers = 2
	await process_frame


func _step_physics(obj: EnemyBase, frames: int, dt: float = 0.05) -> void:
	for _i in range(frames):
		if is_instance_valid(obj) and obj.is_active and not obj.is_dead:
			obj._physics_process(dt)
		await physics_frame


func _run() -> void:
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await physics_frame

	_level = _main.get_node("LevelRoot")
	_player = get_first_node_in_group("player") as Node3D
	_mgr = AllySquadManagerScript.instance
	_coord = SquadCoordinatorScript.get_for(_level)
	if _player != null:
		_player.set("max_health", 100000)
		_player.set("health", 100000)
		_player.global_position = Vector3(0.0, 0.0, -136.0)
	if _mgr != null:
		_mgr.set("rally_enabled", false)
		for a in _mgr.get("allies"):
			if is_instance_valid(a):
				a.set("auto_engage", false)
				a.call("cancel_orders")
				(a as Node3D).global_position = Vector3(-4.0, 0.0, -139.0)

	# Disable pre-placed ENTRY roamers so tests remain isolated.
	for n in get_nodes_in_group("enemy"):
		if n is EnemyBaseScript and not String(n.name).begins_with("Test_") and not (n is WardenBossScript):
			(n as EnemyBase).set_section_enabled(false)

	var rm: RealmManager = RealmManagerScript.instance as RealmManager
	var brannoc: SquadAlly = _mgr.call("find_ally", "Brannoc") as SquadAlly if _mgr != null else null
	var sera: SquadAlly = _mgr.call("find_ally", "Sera") as SquadAlly if _mgr != null else null

	# --- ENM-01: Gravity across states + chase edge probe ---
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var e1: EnemyAI = _spawn("skeleton", Vector3(0.0, 3.0, -136.0)) as EnemyAI
	await process_frame
	var states_to_check: Array[int] = [
		EnemyAIScript.State.CHASE,
		EnemyAIScript.State.WINDUP,
		EnemyAIScript.State.ATTACK,
		EnemyAIScript.State.RECOVER,
		EnemyAIScript.State.STAGGER,
		EnemyAIScript.State.STUNNED,
	]
	var gravity_ok: bool = true
	for st in states_to_check:
		e1.global_position = Vector3(0.0, 3.0, -136.0)
		e1.velocity = Vector3.ZERO
		e1._set_target(_player)
		e1._transition_to(st, 2.0)
		await _step_physics(e1, 3, 0.05)
		if e1.velocity.y >= -0.2 or e1.global_position.y >= 3.0:
			gravity_ok = false
			break
	# Chase edge probe at Stage 01 stepping-stone chasm (floor ends at z = -0.5 in Reality).
	var edge_sk: EnemyAI = _spawn("skeleton", Vector3(0.0, 0.0, -1.0), Vector3(0, 0, 4)) as EnemyAI
	await process_frame
	_player.global_position = Vector3(0.0, 0.0, 3.6)
	edge_sk._set_target(_player)
	edge_sk._transition_to(EnemyAIScript.State.CHASE, 0.0)
	await _step_physics(edge_sk, 25, 0.03)
	_check("enm_01_gravity_and_edge_probe", gravity_ok and edge_sk.global_position.z < -0.2, "grav=%s z=%.2f" % [str(gravity_ok), edge_sk.global_position.z])
	_player.global_position = Vector3(0.0, 0.0, -136.0)
	await _cleanup_test_enemies()

	# --- ENM-02: PhantomTwin in Reality never holds/starves tokens or freezes ---
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var ph2: PhantomTwin = _spawn("phantom", Vector3(0.0, 0.0, -133.5)) as PhantomTwin
	var sk2: SkeletonGuard = _spawn("skeleton", Vector3(2.0, 0.0, -133.5)) as SkeletonGuard
	await process_frame
	ph2._set_target(_player)
	sk2._set_target(_player)
	ph2._transition_to(EnemyAIScript.State.CHASE, 0.0)
	sk2._transition_to(EnemyAIScript.State.CHASE, 0.0)
	await _step_physics(ph2, 10, 0.03)
	var ph_moved: bool = ph2.velocity.length_squared() > 0.01 and not _coord.has_token(ph2)
	var sk_got: bool = _coord.request_attack_token(sk2, _player)
	# Also verify shifting to Reality cancels active Mirror windup.
	rm.force_realm(RealmManagerScript.Realm.MIRROR, false)
	await process_frame
	ph2.start_windup(0.65)
	var was_windup: bool = ph2.current_state == EnemyAIScript.State.WINDUP
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	await process_frame
	_check("enm_02_phantom_reality_no_token_or_freeze", ph_moved and sk_got and was_windup and ph2.current_state == EnemyAIScript.State.CHASE and not _coord.has_token(ph2), "moved=%s sk_got=%s state=%d" % [str(ph_moved), str(sk_got), ph2.current_state])
	await _cleanup_test_enemies()

	# --- ENM-03: SkeletonGuard self-revive exclusions, FloatingHPBar, and 3.0s stun retention ---
	var sk_env: SkeletonGuard = _spawn("skeleton", Vector3(-2.0, 0.0, -134.0)) as SkeletonGuard
	var sk_pit: SkeletonGuard = _spawn("skeleton", Vector3(2.0, 0.0, -134.0)) as SkeletonGuard
	var sk_rev: SkeletonGuard = _spawn("skeleton", Vector3(0.0, 0.0, -133.0), Vector3(0.0, 0.0, -125.0)) as SkeletonGuard
	await process_frame
	sk_env.apply_damage(9999, true, "environmental", _player)
	sk_pit.apply_damage(9999, true, "pit", _player)
	# Hit from behind (backstab) with a knockdown source ("player_landing") to verify 3.0s revive stun is preserved.
	_player.global_position = Vector3(0.0, 0.0, -136.0)
	sk_rev.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	sk_rev.apply_damage(9999, true, "player_landing", _player)
	var hp_lbl: Label3D = sk_rev.get_node_or_null("FloatingHPBar") as Label3D
	var revive_ok: bool = (not sk_rev.is_dead) and sk_rev.current_state == EnemyAIScript.State.STUNNED \
		and absf(sk_rev.get_state_duration() - 3.0) < 0.05 \
		and sk_rev.health == maxi(1, int(sk_rev.max_health * 0.5)) \
		and hp_lbl != null and hp_lbl.visible and hp_lbl.text == "%d/%d" % [sk_rev.health, sk_rev.max_health]
	sk_rev.apply_damage(9999, true, "player_heavy", _player)
	_check("enm_03_skeleton_revive_rules", sk_env.is_dead and sk_pit.is_dead and revive_ok and sk_rev.is_dead, "env=%s pit=%s rev=%s second_kill=%s" % [str(sk_env.is_dead), str(sk_pit.is_dead), str(revive_ok), str(sk_rev.is_dead)])
	await _cleanup_test_enemies()

	# --- ENM-04: SquadCoordinator _peak_engaged resets across encounters and reset() ---
	var sq_a: EnemyAI = _spawn("skeleton", Vector3(-1.5, 0.0, -134.0)) as EnemyAI
	var sq_b: EnemyAI = _spawn("skeleton", Vector3(1.5, 0.0, -134.0)) as EnemyAI
	await process_frame
	sq_a._set_target(_player)
	sq_b._set_target(_player)
	sq_a._transition_to(EnemyAIScript.State.CHASE, 0.0)
	sq_b._transition_to(EnemyAIScript.State.CHASE, 0.0)
	var multi_not_enraged: bool = not _coord.is_last_standing(sq_a, _player)
	sq_a.apply_damage(9999, true, "environmental", _player)
	var last_enraged: bool = _coord.is_last_standing(sq_b, _player)
	sq_b.apply_damage(9999, true, "environmental", _player)
	var solo_sg: EnemyAI = _spawn("shield", Vector3(0.0, 0.0, -134.0)) as EnemyAI
	await process_frame
	solo_sg._set_target(_player)
	solo_sg._transition_to(EnemyAIScript.State.CHASE, 0.0)
	await _step_physics(solo_sg, 2, 0.02)
	var solo_calm: bool = not solo_sg.is_enraged()
	_coord._peak_engaged = 3
	_coord.reset()
	_check("enm_04_peak_engaged_resets", multi_not_enraged and last_enraged and solo_calm and _coord._peak_engaged == 0, "multi=%s last=%s solo_calm=%s" % [str(multi_not_enraged), str(last_enraged), str(solo_calm)])
	await _cleanup_test_enemies()

	# --- ENM-05, ENM-06, ENM-22, ENM-23: WardenBoss range sync, rune exposure clear, tracked lunge, Phase 2 cleanup ---
	var warden: WardenBoss = _level.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden") as WardenBoss
	if warden != null:
		warden.auto_finalize_run_on_death = false
		warden.set_section_enabled(true)
		warden.reset_enemy()
		await process_frame
		var init_cleave: bool = warden.current_move == WardenBossScript.BossMove.CLEAVE and absf(warden.attack_range - warden.cleave_range) < 0.05
		warden._set_target(_player)
		warden.start_windup(0.05)
		warden._begin_attack_strike()
		warden._enter_recover()
		var next_lunge: bool = warden.current_move == WardenBossScript.BossMove.LUNGE and absf(warden.attack_range - warden.lunge_range) < 0.05 and warden.is_chest_rune_exposed
		# ENM-06: Heavy punish Phase 1 Mirror recovery must clear is_chest_rune_exposed on entering STAGGER.
		rm.force_realm(RealmManagerScript.Realm.MIRROR, false)
		await process_frame
		warden.apply_damage(60, true, "player_heavy", _player)
		var cleared_on_stagger: bool = warden.current_state == EnemyAIScript.State.STAGGER and not warden.is_chest_rune_exposed
		warden._transition_to(EnemyAIScript.State.CHASE, 0.0)
		var armored_in_chase: bool = not warden.is_vulnerable_to_full_damage()
		_check("enm_05_warden_move_range_sync", init_cleave and next_lunge, "init=%s next=%s" % [str(init_cleave), str(next_lunge)])
		_check("enm_06_warden_stagger_clears_rune", cleared_on_stagger and armored_in_chase, "stagger_clear=%s armored=%s" % [str(cleared_on_stagger), str(armored_in_chase)])

		# ENM-22: Warden lunge uses get_facing_direction() even with null target during start_windup.
		warden._set_target(null)
		warden.select_next_move(WardenBossScript.BossMove.LUNGE)
		warden.start_windup(0.2)
		warden.set_facing_direction(Vector3.LEFT)
		warden._begin_attack_strike()
		var w_dir: Vector2 = Vector2(warden.velocity.x, warden.velocity.z).normalized()
		_check("enm_22_warden_lunges_along_tracked_facing", w_dir.dot(Vector2(-1.0, 0.0)) > 0.98, "vel=%s" % str(warden.velocity))

		# ENM-23: Phase 2 transition clears telegraph, token, and windup state.
		warden.reset_enemy()
		warden._set_target(_player)
		_coord.request_attack_token(warden, _player)
		warden.start_windup(0.9)
		warden.apply_damage(600, true, "environmental", _player)
		var p2_clean: bool = warden.current_phase == WardenBossScript.Phase.PHASE_2_TRANSITION \
			and warden.current_state != EnemyAIScript.State.WINDUP \
			and not warden._telegraph_active and not _coord.has_token(warden)
		_check("enm_23_phase2_transition_clears_windup_telegraph_token", p2_clean, "phase=%d state=%d tel=%s" % [int(warden.current_phase), warden.current_state, str(warden._telegraph_active)])
		# Verify reset restores CLEAVE range.
		warden.reset_enemy()
		_check("enm_05_reset_restores_cleave", warden.current_move == WardenBossScript.BossMove.CLEAVE and absf(warden.attack_range - warden.cleave_range) < 0.05)
		warden.set_section_enabled(false)
		rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	else:
		_check("enm_05_warden_move_range_sync", false, "TheWarden missing")
		_check("enm_06_warden_stagger_clears_rune", false, "TheWarden missing")
		_check("enm_22_warden_lunges_along_tracked_facing", false, "TheWarden missing")
		_check("enm_23_phase2_transition_clears_windup_telegraph_token", false, "TheWarden missing")
	_coord.reset()

	# --- ENM-07: Single DAMAGE_SCALE (1.4x) on archetypes ---
	var hx7: ArchetypeEnemy = _spawn("hexcaster", Vector3(-3.0, 0.0, -133.0)) as ArchetypeEnemy
	var br7: ArchetypeEnemy = _spawn("brute", Vector3(0.0, 0.0, -133.0)) as ArchetypeEnemy
	var st7: ArchetypeEnemy = _spawn("stalker", Vector3(3.0, 0.0, -133.0)) as ArchetypeEnemy
	await process_frame
	var exp_hx: int = int(float(hx7.archetype.attack_damage) * EnemyAIScript.DAMAGE_SCALE)
	var exp_br: int = int(float(br7.archetype.attack_damage) * EnemyAIScript.DAMAGE_SCALE)
	var exp_st: int = int(float(st7.archetype.attack_damage) * EnemyAIScript.DAMAGE_SCALE)
	_check("enm_07_single_damage_scale", hx7.attack_damage == exp_hx and br7.attack_damage == exp_br and st7.attack_damage == exp_st, "%d/%d/%d" % [hx7.attack_damage, br7.attack_damage, st7.attack_damage])

	# --- ENM-08 & ENM-09: Bolt evade decay and fire-band token gating ---
	hx7._set_target(_player)
	hx7._transition_to(EnemyAIScript.State.CHASE, 0.0)
	hx7.consider_evade(_player, true, 0.3)
	var ev_started: bool = hx7.is_evading()
	await _step_physics(hx7, 12, 0.04)
	var ev_ended: bool = not hx7.is_evading()
	_check("enm_08_bolt_evade_timer_decays", ev_started and ev_ended, "started=%s ended=%s" % [str(ev_started), str(ev_ended)])

	hx7.global_position = Vector3(0.0, 0.0, -118.0) # 18 m > attack_range 10.0
	await _step_physics(hx7, 3, 0.03)
	var far_no_tok: bool = not _coord.has_token(hx7)
	hx7.global_position = Vector3(0.0, 0.0, -134.5) # 1.5 m < pref * 0.45 (3.15)
	await _step_physics(hx7, 3, 0.03)
	var close_no_tok: bool = not _coord.has_token(hx7)
	_check("enm_09_bolt_token_only_in_fire_band", far_no_tok and close_no_tok, "far=%s close=%s" % [str(far_no_tok), str(close_no_tok)])

	# --- ENM-10: Shade Stalker blink respects closed Gate01_EntryToHall ---
	_player.global_position = Vector3(0.0, 0.0, 5.8) # north of closed Gate01 (z=5.0)
	_player.call("set_facing_direction", Vector3(0.0, 0.0, -1.0))
	st7.global_position = Vector3(0.0, 0.0, 3.8) # south of closed Gate01
	st7._blink_cd = 0.0
	st7._try_blink_behind(_player)
	var blocked_across_gate: bool = st7.global_position.z < 4.9
	_player.global_position = Vector3(0.0, 0.0, 4.3)
	_player.call("set_facing_direction", Vector3(0.0, 0.0, -1.0)) # back toward Gate01
	st7.global_position = Vector3(0.0, 0.0, 3.2)
	st7._blink_cd = 0.0
	st7._try_blink_behind(_player)
	var blocked_into_gate: bool = st7.global_position.z < 4.9
	_check("enm_10_stalker_blink_respects_gates_and_walls", blocked_across_gate and blocked_into_gate, "across=%s into=%s" % [str(blocked_across_gate), str(blocked_into_gate)])
	_player.global_position = Vector3(0.0, 0.0, -136.0)

	# --- ENM-11: Grave Brute slam ring aligned in world space across rotation & tracking ---
	br7.global_position = Vector3(0.0, 0.0, -132.0)
	br7.rotation.y = PI
	br7.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	br7._set_target(_player)
	br7.start_windup(0.6)
	var ring_m: MeshInstance3D = br7.get_node_or_null("SlamTelegraph") as MeshInstance3D
	var expected_pos: Vector3 = br7.global_position + br7.get_facing_direction() * 0.8 + Vector3.UP * 0.06
	var rot_ok: bool = ring_m != null and ring_m.global_position.distance_to(expected_pos) < 0.05
	br7.set_facing_direction(Vector3.RIGHT)
	br7._process_windup(0.02, _player)
	expected_pos = br7.global_position + br7.get_facing_direction() * 0.8 + Vector3.UP * 0.06
	var track_ok: bool = ring_m != null and ring_m.global_position.distance_to(expected_pos) < 0.05
	_check("enm_11_slam_ring_world_aligned", rot_ok and track_ok, "rot=%s track=%s" % [str(rot_ok), str(track_ok)])

	# --- ENM-24: Inactive/dead archetype skips windup FX ---
	br7.is_active = false
	br7._hide_slam_ring()
	br7.start_windup(0.6)
	var ring_hidden: bool = ring_m == null or not ring_m.visible
	st7.is_dead = true
	var pre_blink_pos: Vector3 = st7.global_position
	st7._blink_cd = 0.0
	st7._set_target(_player)
	st7.start_windup(0.4)
	_check("enm_24_inactive_archetype_skips_windup_fx", ring_hidden and st7.global_position.distance_to(pre_blink_pos) < 0.01)
	await _cleanup_test_enemies()

	# --- ENM-12, ENM-13, ENM-14, ENM-15, ENM-16, ENM-17, ENM-25, ENM-26 ---
	var sk12: EnemyAI = _spawn("skeleton", Vector3(0.0, 0.0, -133.0)) as EnemyAI
	var sk_buddy: EnemyAI = _spawn("skeleton", Vector3(5.0, 0.0, -133.0)) as EnemyAI
	await process_frame
	if brannoc != null and sera != null:
		brannoc.global_position = Vector3(-2.5, 0.0, -133.0)
		sera.global_position = Vector3(2.5, 0.0, -133.0)
		sk12.apply_taunt(brannoc, -1.0, 4.0)
		sk12.apply_taunt(brannoc, 30.0, 2.5)
		_check("enm_12_same_ally_nudge_keeps_fixation", sk12.is_fixated() and sk12._taunt_lock_timer >= 3.9, "fix=%s t=%.2f" % [str(sk12.is_fixated()), sk12._taunt_lock_timer])
	else:
		_check("enm_12_same_ally_nudge_keeps_fixation", false, "Allies missing")

	sk_buddy.target_player = null
	sk_buddy._transition_to(EnemyAIScript.State.IDLE, 0.0)
	sk_buddy.consider_evade(_player, true, 0.3)
	var idle_no_evade: bool = sk_buddy.current_state == EnemyAIScript.State.IDLE and not sk_buddy.is_evading()
	sk12.consider_evade(_player, true, 0.3)
	sk12.enter_stagger(0.4)
	_check("enm_13_evade_idle_and_timer_clear", idle_no_evade and not sk12.is_evading(), "idle_no=%s cleared=%s" % [str(idle_no_evade), str(not sk12.is_evading())])

	# ENM-14: Opening heavy on IDLE enemy sets target, clears reaggro block, and alerts squadmate.
	sk12.reset_enemy()
	sk_buddy.reset_enemy()
	sk12._reaggro_block = 1.5
	sk12.apply_damage(10, true, "player_heavy", _player)
	_check("enm_14_idle_opening_stagger_alerts_squad", sk12.get_current_target() == _player and sk12._reaggro_block == 0.0 and sk12.current_state == EnemyAIScript.State.STAGGER and sk_buddy.is_aggroed(), "tgt=%s buddy=%s" % [str(sk12.get_current_target() == _player), str(sk_buddy.is_aggroed())])

	# ENM-15: Backstab during ATTACK does not queue turn_around, and _finish_turn_around respects taunt fixation.
	sk12.reset_enemy()
	sk12._transition_to(EnemyAIScript.State.ATTACK, 0.3)
	sk12.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	sk12.apply_damage(10, false, "player_light", _player)
	var atk_no_turn: bool = sk12._turn_to_id == 0
	var taunt_kept: bool = false
	if brannoc != null and sera != null:
		sk12.reset_enemy()
		sk12.apply_taunt(brannoc, -1.0, 4.0)
		sk12.set_facing_direction((brannoc.global_position - sk12.global_position))
		sera.global_position = sk12.global_position - sk12.get_facing_direction() * 1.5
		sk12.apply_damage(10, false, "player_light", sera)
		sk12._finish_turn_around()
		taunt_kept = sk12.get_current_target() == brannoc
	_check("enm_15_backstab_respects_boss_attack_and_taunt", atk_no_turn and taunt_kept, "atk=%s taunt=%s" % [str(atk_no_turn), str(taunt_kept)])

	# ENM-16: Taunted enemy cannot flee even below flee_health_ratio.
	sk12.health = 10
	sk12._has_fled = false
	sk12.apply_damage(1, false, "player_light", _player)
	_check("enm_16_taunted_enemy_cannot_flee", sk12.current_state != EnemyAIScript.State.FLEEING, "state=%d" % sk12.current_state)

	# ENM-17: Heavy hit does not cancel STUNNED into STAGGER, and heavy knockdown emits staggered once.
	sk12.reset_enemy()
	sk12.enter_stunned(1.6)
	sk12.apply_damage(10, true, "player_heavy", _player)
	var stayed_stunned: bool = sk12.current_state == EnemyAIScript.State.STUNNED
	sk12.reset_enemy()
	var stag_count: Array[int] = [0]
	var conn_cb: Callable = func(_d: float) -> void: stag_count[0] += 1
	sk12.staggered.connect(conn_cb)
	sk12.apply_damage(10, true, "player_landing", _player)
	sk12.staggered.disconnect(conn_cb)
	_check("enm_17_stunned_not_cancelled_and_no_double_emit", stayed_stunned and stag_count[0] == 1, "stayed=%s emits=%d" % [str(stayed_stunned), stag_count[0]])

	# ENM-18: Realm collision mask sync + ENM-20 ShieldedGuard STUNNED shield drop.
	var sg20: ShieldedGuard = _spawn("shield", Vector3(2.0, 0.0, -133.0)) as ShieldedGuard
	await process_frame
	sg20.evaluate_for_realm(0, false)
	var mask_reality: bool = (sg20.collision_mask & RealmManagerScript.LAYER_WORLD_MIRROR) == 0 and (sg20.collision_mask & RealmManagerScript.LAYER_WORLD_REALITY) != 0
	sg20.evaluate_for_realm(1, false)
	var mask_mirror: bool = (sg20.collision_mask & RealmManagerScript.LAYER_WORLD_REALITY) == 0 and (sg20.collision_mask & RealmManagerScript.LAYER_WORLD_MIRROR) != 0
	_check("enm_18_enemy_collision_mask_syncs_realm", mask_reality and mask_mirror, "real=%s mir=%s" % [str(mask_reality), str(mask_mirror)])

	sg20.evaluate_for_realm(0, false)
	sg20.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	_player.global_position = sg20.global_position + Vector3(0.0, 0.0, -1.5)
	sg20.enter_stunned(1.6)
	var hp_pre: int = sg20.health
	var accepted_stun: bool = sg20.apply_damage(20, false, "player_light", _player)
	_check("enm_20_stunned_shield_guard_drops_shield", not sg20.is_shield_raised() and accepted_stun and (hp_pre - sg20.health) >= 20, "dmg=%d" % (hp_pre - sg20.health))

	# ENM-19: PhantomTwin lunge uses tracked get_facing_direction().
	var ph19: PhantomTwin = _spawn("phantom", Vector3(-3.0, 0.0, -133.0)) as PhantomTwin
	await process_frame
	rm.force_realm(RealmManagerScript.Realm.MIRROR, false)
	await process_frame
	ph19.set_facing_direction(Vector3.BACK)
	ph19.start_windup(0.5)
	ph19.set_facing_direction(Vector3.RIGHT)
	ph19._begin_attack_strike()
	var ph_dir: Vector2 = Vector2(ph19.velocity.x, ph19.velocity.z).normalized()
	_check("enm_19_phantom_lunges_along_tracked_facing", ph_dir.dot(Vector2(1.0, 0.0)) > 0.98, "vel=%s" % str(ph19.velocity))
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)

	# ENM-21: Active waiter is not evicted at >2.5s while still requesting tokens.
	_coord.reset()
	_coord.max_attackers = 1
	var blocker: EnemyAI = _spawn("skeleton", Vector3(-4.0, 0.0, -133.0)) as EnemyAI
	var waiter_a: EnemyAI = _spawn("skeleton", Vector3(4.0, 0.0, -133.0)) as EnemyAI
	var waiter_b: EnemyAI = _spawn("skeleton", Vector3(4.5, 0.0, -133.0)) as EnemyAI
	await process_frame
	for w_e in [blocker, waiter_a, waiter_b]:
		w_e._set_target(_player)
		w_e._transition_to(EnemyAIScript.State.CHASE, 0.0)
	_coord.request_attack_token(blocker, _player)
	_coord.request_attack_token(waiter_a, _player)
	var aid: int = waiter_a.get_instance_id()
	var now_t: float = SquadCoordinatorScript._now()
	_coord._waiting_since[aid] = now_t - 2.8
	_coord._last_wait_touch[aid] = now_t
	_coord.release_token(blocker)
	var b_stole: bool = _coord.request_attack_token(waiter_b, _player)
	var a_kept: bool = _coord._waiting_since.has(aid)
	var a_won: bool = _coord.request_attack_token(waiter_a, _player)
	_check("enm_21_token_waiter_not_evicted_while_active", not b_stole and a_kept and a_won, "b_stole=%s a_kept=%s a_won=%s" % [str(b_stole), str(a_kept), str(a_won)])

	# ENM-25: Poise counter in WINDUP retains existing token even under cap pressure.
	_coord.reset()
	_coord.max_attackers = 1
	sk12.reset_enemy()
	sk12._set_target(_player)
	sk12._transition_to(EnemyAIScript.State.CHASE, 0.0)
	_coord.request_attack_token(sk12, _player)
	sk12.start_windup(0.6)
	sk12.counter_attack_chance = 1.0
	sk12._flinch_chain = sk12.max_flinch_chain
	sk12.global_position = _player.global_position + Vector3(0.0, 0.0, 1.0)
	sk12.apply_damage(10, false, "player_light", _player)
	_check("enm_25_poise_counter_preserves_windup_token", _coord.has_token(sk12) and sk12.current_state == EnemyAIScript.State.WINDUP, "has=%s state=%d" % [str(_coord.has_token(sk12)), sk12.current_state])

	# ENM-26: _hit_flash during windup never restores cleared _telegraph_mat.
	sk12.reset_enemy()
	sk12._set_target(_player)
	sk12.start_windup(0.9)
	sk12._hit_flash(Color.WHITE, 0.08)
	sk12._clear_telegraph_flash()
	await create_timer(0.14).timeout
	var vis_root: Node3D = sk12.get_node_or_null("VisualRoot") as Node3D
	var stale_found: bool = false
	if vis_root != null:
		for m in vis_root.find_children("*", "MeshInstance3D", true, false):
			if (m as MeshInstance3D).material_overlay != null:
				stale_found = true
	_check("enm_26_hit_flash_never_restores_cleared_telegraph", not stale_found, "stale=%s" % str(stale_found))

	await _cleanup_test_enemies()
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[enm_reg] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
```

- **Postcondition**: `tests/enemies_ai_bugfix_regression_test.gd` exists cleanly and passes `--check-only` and headless execution with `0 failed`.

---

### Step 10 — Synchronize `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` and `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` (`AGENTS.md` Rule 1.3)

- **Prerequisites**: Steps 1–9 applied.
- **Collision Avoidance**: Targets only `§3.2`–`§3.4` (`lines 130–180`) in `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`, leaving `§1`–`§2` untouched for Guide 01.

#### Edit 10A — Update `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` §3.2 (`SkeletonGuard`, `PhantomTwin`, `ShieldedGuard`, `The Warden`)

**Target:** `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`
**Action:** Replace block

**Find:**
```markdown
- **Skeleton Guard** (`Hall of Echoes`):
  - Acquires player within `~22.0 m`, closes distance directly/via nav, visible melee wind-up (`15 dmg`), `~0.8 s` post-attack recovery.
  - Features 1-time `3.0s` fall-down self-revive at `50%` HP before final death.
  - Hidden, non-colliding, AI paused whenever `current_realm == MIRROR`.
- **Phantom Twin** (`Hall of Echoes`):
  - Active only in `MIRROR`. `9.0 m` detection, floating approach, strong blue wind-up glow before forward lunge (`20 dmg`), `~1.0 s` recovery.
  - Killing in Mirror awards base `+100` + `+200 Mirror Kill` (combo multiplied).
  - *Pacing cue*: Hall starts with 2 Skeletons in Reality; defeating 1st Skeleton pulses a subtle Mirror hint reminding player of Phantom Twins (never locks `Q`).
- **Shielded Guard** (`Collapsed Gallery`, after anchor):
  - Same world transform in both realms.
  - In **Reality**: raised frontal shield deflects light attacks cleanly (`0` or minimal chip + metallic spark) and heavily mitigates heavy attacks without staggering. Attacks via shoulder-pullback shield bash (`20 dmg`).
  - In **Mirror**: shield vanishes; vulnerable spectral torso can be staggered and burst down by Heavy (`60 dmg`) + Light combo.
  - Defeat opens Gallery exit gate (player must have already repaired Reality bridge via Anchor to pass safely if returning to Reality).
- **The Warden** (`Execution Arena`, Phase 1 & Phase 2):
  - **Shared 1,000 HP pool** across Reality and Mirror.
  - **Phase 1 (`1000 -> 501 HP`)**:
    1. Armored in Reality (heavily reduces direct Reality hits so shifting is clearly rewarded/taught).
    2. Selects **Cleave** (short frontal arc, `28 dmg`) or **Lunge** (`5.0 m` line, `35 dmg`).
    3. Plays clear **`0.8–1.0 s` wind-up telegraph** (audio sting + distinct body pose) visible in the active realm so danger is always fair.
    4. Executes strike -> enters **`1.4 s` recovery window** where Mirror reflection exposes glowing chest rune.
    5. Player shifts to Mirror (`Q`) and punishes exposed echo (Heavy / Light combo) -> staggers Warden & drains shared HP -> returns to guarded loop. Must never soft-lock if player misses a window.
  - **Phase 2 Transition (`HP <= 500`)**:
    - Stops current attack immediately -> plays `<= 2.0 s` Mirror Plane shatter sequence -> **one-way transition**.
    - HUD banner/chip changes to **`REALMS MERGED`**; `Q` is locked/disabled (`shift_locked = true`).
```

**Replace with:**
```markdown
- **Skeleton Guard** (`Hall of Echoes`):
  - Acquires player within `~22.0 m`, closes distance directly/via nav, visible melee wind-up (`21` scaled dmg), `~0.8 s` post-attack recovery.
  - Features 1-time `3.0 s` fall-down self-revive (`State.STUNNED`) at `50%` HP (`health_changed` emitted to update `FloatingHPBar`, preserved across knockdown/backstab post-hit hooks; bypassed by `"environmental"`, `"pit"`, `"player_execution"`, `"execution"`) before final death.
- **Phantom Twin** (`Hall of Echoes`):
  - `BOTH_STATEFUL`, translucent and harmless in `REALITY` (`can_attack_now() == _mirror_now()`, `is_hittable_now() == _mirror_now()`): circles without requesting attack tokens or freezing, cancels any windup/attack immediately when shifting to Reality, and lunges along its tracked `get_facing_direction()` (`28` scaled dmg, `~1.0 s` recovery) in `MIRROR` or merged realms.
  - Killing in Mirror awards base `+100` + `+200 Mirror Kill` (combo multiplied).
  - *Pacing cue*: Hall starts with 2 Skeletons in Reality; defeating 1st Skeleton pulses a subtle Mirror hint reminding player of Phantom Twins (never locks `Q`).
- **Shielded Guard** (`Collapsed Gallery`, after anchor):
  - Same world transform in both realms.
  - In **Reality**: raised frontal shield (`is_shield_raised() == false` when `STAGGER`, `STUNNED`, `MIRROR`, or merged) deflects light attacks cleanly (`0` chip + metallic spark) and mitigates heavy attacks without staggering (`player_execution` pierces block). Attacks via shoulder-pullback shield bash (`28` scaled dmg).
  - In **Mirror**: shield vanishes; vulnerable spectral torso can be staggered and burst down by Heavy (`60 dmg`) + Light combo.
  - Defeat opens Gallery exit gate (player must have already repaired Reality bridge via Anchor to pass safely if returning to Reality).
- **The Warden** (`Execution Arena`, Phase 1 & Phase 2):
  - **Shared 1,500 HP pool** (`_phase2_threshold() = 999`) across Reality and Mirror; Phase 1 incoming hits clamp to `maxi(1, health - _phase2_threshold())`, and Phase 2 caps single hits at `phase2_max_hit = 120`.
  - **Phase 1 (`1500 -> 1000 HP`)**:
    1. Armored in Reality (`phase1_reality_armor_cap = 5`) so shifting is rewarded.
    2. Pre-queues alternating **Cleave** (`2.8 m`, `28 dmg`) or **Lunge** (`5.0 m`, `35 dmg`, tracked `get_facing_direction()`) at the end of recovery / reset so chase distance always matches the upcoming move.
    3. Plays clear **`0.90 s` wind-up telegraph** visible in the active realm.
    4. Executes strike -> enters **`1.4 s` recovery window** where Mirror reflection exposes glowing chest rune (`is_chest_rune_exposed` clears cleanly whenever leaving `State.RECOVER`, including on heavy-punish `STAGGER`, preventing infinite Phase 1 stagger-locking).
    5. Player shifts to Mirror (`Q`) and punishes exposed echo (Heavy / Light combo) -> staggers Warden & drains shared HP -> returns to guarded loop. Must never soft-lock if player misses a window.
  - **Phase 2 Transition (`HP <= 999`)**:
    - Clears telegraph flash & attack token, ends active hitbox swing, transitions to `State.STAGGER` during `1.60 s` shatter sequence -> plays Mirror Plane shatter -> **one-way transition**.
    - HUD banner/chip changes to **`REALMS MERGED`**; `Q` is locked/disabled (`shift_locked = true`).
```

#### Edit 10B — Update `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` §3.3 & §3.4 (Squad Coordinator, Archetypes, Threat & State Invariants)

**Target:** `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`
**Action:** Replace block

**Find:**
```markdown
- **Attack tokens**: max `2` simultaneous attackers (1 if squad < 3), `0.42 s` minimum gap between attack starts. Token priority = time waited + up to `+1.2 s` for standing behind the player (pincer). Released on recovery / stagger / death.
- **Holding ring**: non-token enemies circle at `attack_range + ring_margin (1.7)` with angular spacing (62°), drift toward the player's flank, back off if crowding, separation steering, random orbit flips.
- **Alert**: first spotter taunts `0.55 s` and alerts every idle ally in the same `encounter_id` or within `14 m`.
- **Evade**: uncommitted enemies within `3.4 m` in the player's front cone may side-step a telegraphed swing (`evade_skill`: Skeleton `0.45`, Phantom `0.7`, Shielded `0.15`, Warden `0`).
- **Flinch & poise**: light hits flinch (`0.26 s`) unless ATTACK or past 50% of WINDUP (hyper-armour). After `max_flinch_chain` (2; Shielded 1) flinches → `1.6 s` poise; `70%` chance of an immediate fast counter-swing. Warden never flinches on lights.
- **Enrage**: last survivor of a squad of ≥2 moves `1.25x`, winds up `0.8x`, recovers `0.7x`.
```

**Replace with:**
```markdown
- **Attack tokens**: max `2` simultaneous attackers (1 if squad < 3), `0.42 s` minimum gap between attack starts. Token priority = time waited (active waiters keep their first-request timestamp via `_last_wait_touch` heartbeats) + up to `+1.2 s` for standing behind the player (pincer). Released on recovery / stagger / death; ranged (`bolt`) enemies request tokens only inside `[preferred_range * 0.45, attack_range]`, and poise counters preserve held `WINDUP` tokens.
- **Holding ring**: non-token enemies circle at `attack_range + ring_margin (1.7)` with angular spacing (62°), drift toward the player's flank, back off if crowding, separation steering, random orbit flips; `_process_chase()` applies gravity and probes `_has_floor_ahead()` along with all active `EnemyAI` states.
- **Alert**: first spotter taunts `0.55 s` and alerts every idle ally in the same `encounter_id` or within `join_radius (22 m)` (`alert_radius = 38 m`); opening stagger/backstab/knockdown hits on an idle enemy still set target, clear `_reaggro_block`, and alert squadmates.
- **Evade**: uncommitted `CHASE`/`RECOVER` enemies (never `IDLE` with null target) within `3.4 m` in the player's front cone may side-step (`_evade_timer` decays in `CHASE`/`bolt` and clears on exiting `CHASE`).
- **Flinch & poise**: light hits flinch (`0.26 s`) unless ATTACK or past 50% of WINDUP (hyper-armour). After `max_flinch_chain` (2; Shielded 1) flinches → `1.6 s` poise; `70%` chance of an immediate fast counter-swing (gated on `can_attack_now()` and token ownership). Warden never flinches on lights. `_hit_flash()` validates overlays via `_is_overlay_still_valid()` so cleared windup telegraphs are never restored.
- **Enrage**: last survivor of a squad of ≥2 moves `1.25x`, winds up `0.8x`, recovers `0.7x`; `_peak_engaged` resets to `0` on `SquadCoordinator.reset()` and whenever active engagement drops to empty (`refresh_engaged_peak()`).
```

**Target:** `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`
**Action:** Replace block

**Find:**
```markdown
- **Taunt FIXATION** (2026-11-17, `taunt_fixation = true`): any real taunt (lock ≥ `3 s`: ally taunts, War Cry, Shield Wall, take aggro) pins the enemy on the taunter **with no expiry** — it ignores its home leash and its lose-sight range and chases forever. It ends only when the taunter is down / untargetable, another real taunt replaces it, `forget()` (Smoke Bomb) wipes it, or the taunter stays > `60 m` away for `5 s`. Short "nudge" taunts (< 3 s, the splash of an area taunt) still expire and never override a fixation. A fleeing enemy that is taunted turns back to CHASE. Queries: `is_fixated()`, `get_taunter()`.
- **Backstab** (attacker in the rear arc, facing·to_attacker < −0.35): damage `×1.25`, threat `×1.8`, stagger `0.55 s` (Shielded `0.4`; Warden never), then a **turn-around** (snaps to face and targets the stabber with a `0.2 s` roar) before it can counter.
- **Knock-down** (`KNOCKDOWN_SOURCES`: `player_landing`, `fin_sunder`, `ally_charge`, `ally_nuke`, `ally_detonate`): STUNNED `1.6 s` (Lie_Down → Lie_Idle → Lie_StandUp), incoming damage `×1.35` while stunned. Warden is `knockdown_immune`.
```

**Replace with:**
```markdown
- **Taunt FIXATION** (2026-11-17, `taunt_fixation = true`): any real taunt (lock ≥ `3 s`: ally taunts, War Cry, Shield Wall, take aggro) pins the enemy on the taunter **with no expiry** — it ignores its home leash and its lose-sight range and chases forever. It ends only when the taunter is down / untargetable, another real taunt replaces it, `forget()` (Smoke Bomb) wipes it, or the taunter stays > `60 m` away for `5 s`. Short "nudge" taunts (< 3 s, the splash of an area taunt) never override or downgrade an existing fixation (same or different taunter). Taunted enemies cannot flee (`_should_flee()` checks `not is_taunted()`); a fleeing enemy that is taunted turns back to CHASE. Queries: `is_fixated()`, `get_taunter()`.
- **Backstab** (attacker in the rear arc, facing·to_attacker < −0.35): damage `×1.25`, threat `×1.8`, stagger `0.55 s` (Shielded `0.4`; skipped when `backstab_staggers == false` or mid-`ATTACK`), then a **turn-around** (snaps to face and targets the stabber with a `0.2 s` roar unless pinned on another taunter).
- **Knock-down** (`KNOCKDOWN_SOURCES`: `player_landing`, `fin_sunder`, `ally_charge`, `ally_nuke`, `ally_detonate`): STUNNED `1.6 s` (Lie_Down → Lie_Idle → Lie_StandUp), incoming damage `×1.35` while stunned; heavy hits do not cancel `STUNNED` into `STAGGER`, and heavy knockdown sources emit `state_changed`/`staggered` once. Warden is `knockdown_immune`.
- **Realm physics & archetype scaling**: `EnemyBase.evaluate_for_realm()` updates `collision_mask` via `RealmManager.update_actor_collision_mask()` (keeping `HexBolt` & blink rays realm-accurate); `EnemyAI.DAMAGE_SCALE = 1.4` applies once in `EnemyAI._ready()`; `ArchetypeEnemy._try_blink_behind()` checks horizontal wall/gate/blocker LoS + capsule clearance; slam rings track `get_facing_direction()` in world space.
```

#### Edit 10C — Append 1 dated changelog bullet to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`

> **Executor Note for Sequential Guide Execution (`01 -> 02 -> 03 -> 04`)**: If Guide 01 has already appended its changelog bullet below the `2026-11-19: Stacked Dodge Chaining...` line, preserve Guide 01's line and append the new Guide 02 bullet at the end of `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` after the latest bullet line.

**Target:** `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`
**Action:** Replace block

**Find:**
```markdown
- 2026-11-19: Stacked Dodge Chaining & Execution Shield Pierce - Implemented consecutive stacked dodge chaining in PlayerController (_process_dodge_state allows chaining past i-frames t_norm > 0.45; start_dodge accepts State.DODGE; buffer consumes seamlessly on finish). ShieldedGuard._modify_incoming_damage allows player_execution to bypass shield deflect. Verified with charged_heavy_test (18 checks), feel_and_movement_test (13 checks), combat_rules_test (10 checks), and restart_flow_test (PASS).
```

**Replace with:**
```markdown
- 2026-11-19: Stacked Dodge Chaining & Execution Shield Pierce - Implemented consecutive stacked dodge chaining in PlayerController (_process_dodge_state allows chaining past i-frames t_norm > 0.45; start_dodge accepts State.DODGE; buffer consumes seamlessly on finish). ShieldedGuard._modify_incoming_damage allows player_execution to bypass shield deflect. Verified with charged_heavy_test (18 checks), feel_and_movement_test (13 checks), combat_rules_test (10 checks), and restart_flow_test (PASS).
- 2026-11-20 (Guide 02 — Enemies & AI Remediation, ENM-01..ENM-26): Fixed `EnemyAI` gravity + floor edge probing across all states, `PhantomTwin` Reality token/freeze & tracked lunge (`can_attack_now()`, `on_realm_changed()`), `SkeletonGuard` self-revive exclusions (`environmental`/`pit`/`player_execution`/`execution`), `FloatingHPBar` `health_changed` emit, and `3.0 s` stun preservation, `SquadCoordinator` `_peak_engaged` resets & `_last_wait_touch` active waiter fairness, `WardenBoss` pre-queued move range sync, Phase 1 chest-rune clear on stagger, tracked lunge, and Phase 2 transition cleanup, `ArchetypeEnemy` single `1.4×` `DAMAGE_SCALE`, bolt evade decay & fire-band token gating, wall/gate-safe `Shade Stalker` blink, world-aligned `Grave Brute` slam ring, and inactive windup guard, `ShieldedGuard` `STUNNED` shield drop, `EnemyBase` realm `collision_mask` sync & `_hit_flash()` overlay validation, and `EnemyAI` taunt/evade/idle-opening/backstab/flee/stagger/poise-token bugs; added `tests/enemies_ai_bugfix_regression_test.gd` (`26 checks`).
```

- **Postcondition**: `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` and `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` accurately document all post-Guide-02 enemy & AI behaviors without conflicting with Guide 01.

---

## E. Verification & Failure Handling

Run every command below in PowerShell from `D:\Desktop\Godot\parallax` **after** Steps 1–10 are applied.

| Ver ID | PowerShell Command | Preconditions | Expected Pass Condition | Covers |
| :--- | :--- | :--- | :--- | :--- |
| **VER-01** | `foreach ($f in @("scripts/enemies/squad_coordinator.gd","scripts/enemies/enemy_base.gd","scripts/enemies/enemy_ai.gd","scripts/enemies/skeleton_guard.gd","scripts/enemies/phantom_twin.gd","scripts/enemies/shielded_guard.gd","scripts/enemies/archetype_enemy.gd","scripts/enemies/warden_boss.gd","tests/enemies_ai_bugfix_regression_test.gd")) { Write-Host "CHECK $f"; & "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" --check-only -s "res://$f"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }` | Steps 1–9 applied | Exit `0`, zero `SCRIPT ERROR` or parser warnings on any touched enemy or test script. | ENM-01..ENM-26 |
| **VER-02** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/enemies_ai_bugfix_regression_test.gd` | Steps 1–9 applied | Exit `0`; prints `[enm_reg] SUMMARY 26 checks, 0 failed` (all `enm_01`..`enm_26` `PASS`). | ENM-01..ENM-26 |
| **VER-03** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/combat_rules_test.gd` | Steps 1–8 applied | Exit `0`; prints `[combat] SUMMARY 9 checks, 0 failed` (preserves `325` HP scale, Warden `1500` HP / `999` threshold / `120` hit cap / fall safety, Phantom Mirror rules). | ENM-02, ENM-05, ENM-18 |
| **VER-04** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/boot_smoke.gd` | Steps 1–8 applied | Exit `0`; prints `[boot_smoke] OK`. | Regression |
| **VER-05** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/restart_flow_test.gd` | Steps 1–8 applied | Exit `0`; prints `=> PASS` (`"environmental"` kill in `restart_flow_test.gd` kills immediately without triggering `SkeletonGuard` revive). | ENM-03 |
| **VER-06** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/level_props_test.gd` | Steps 1–8 applied | Exit `0`; prints `0 failed`. | Regression |
| **VER-07** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/squad_ai_unit_test.gd` | Steps 1–8 applied | Exit `0`; prints `[unit] SUMMARY ... 0 failed`. | Regression |
| **VER-08** | `& "C:/Users/agrim/.local/bin/godot.cmd" --path "D:/Desktop/Godot/parallax" -s res://tests/feel_and_movement_test.gd` | Desktop/GPU session, Steps 1–8 applied | Windowed run; exit `0`; prints `[feel] SUMMARY 13 checks, 0 failed`. | Regression (`ENM-02`, `ENM-03`) |
| **VER-09** | `& "C:/Users/agrim/.local/bin/godot.cmd" --path "D:/Desktop/Godot/parallax" -s res://tests/squad_ai_windowed_test.gd` | Desktop/GPU session, Steps 1–8 applied | Windowed run; exit `0`; prints `0 failed` (`bait_holds_enemy`, `taunt_fixation_persists`, `taunted_enemy_chases_past_leash` all `PASS`). | ENM-12, ENM-15 |

### Failure Recovery Protocol
1. **`--check-only` reports `SCRIPT ERROR` or unexpected indent**: Check that tabs (`\t`) in the edited `scripts/enemies/*.gd` match surrounding functions. To restore any single script cleanly before retrying: `git checkout -- <file>`.
2. **`enemies_ai_bugfix_regression_test.gd` fails on a specific `enm_XX` check**: Inspect the printed failure line (`PASS`/`FAIL` detail) and verify the corresponding Step 1–8 block was applied completely without dropping a helper or variable.
3. **`feel_and_movement_test.gd` or `squad_ai_windowed_test.gd` headless display error**: Run `VER-08` and `VER-09` from a windowed desktop session (non-`--headless`) since both capture/exercise active viewport/physics timing.
4. **Save side effects**: If `restart_flow_test.gd` writes `user://savegame.cfg` under `%APPDATA%\Godot\app_userdata\PARALLAX\`, clear or restore user save state afterward if a clean baseline is required.

---

## F. Completion Report Contract

When execution of Guide 02 finishes, output a concise report containing ONLY directly observed results:
1. **Applied Step IDs**: `Step 1` through `Step 10` (note any skipped or blocked step).
2. **Changed Files**: Exact list matching Section C (`scripts/enemies/*.gd`, `tests/enemies_ai_bugfix_regression_test.gd`, `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`).
3. **Verification Results Table**: Each check `VER-01` through `VER-09`, exact exit code, and exact printed `SUMMARY` / pass line.
4. **Remaining Unverified Items / Blockers**: Clearly flag any check not run (e.g., `VER-08`/`VER-09` if running in a headless-only environment) or out-of-scope dependencies (`player_controller.gd:1024` owned by Guide 01 `CMB-06`).
5. **Definition of Done**: All 10 steps applied cleanly, zero unintended files created, and `VER-01`..`VER-09` exit `0` with `0 failed`.
