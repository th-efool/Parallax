# Sanity-Testing-2 — Combat, Warden, Phantoms, Ivo (audits Guide 02)

> Investigator brief. Verify `IdiotHandOffGuide_02_Combat_Enemies.md` actually holds in live play. Run the game, fight, read logs. Report evidence only; do not fix.

## Weakest chains

1. **Warden "half health then dropped dead" root cause**
   - Reproduce the ORIGINAL bug path: heavy/finisher/ally damage, fall off the arena edge, kill planes (`PitKillZone`), Phase 1->2 transition at 50% of SCALED HP. Does the Warden ever die before Phase 2 completes, or die with HP > 0?
   - Phase-2 hit cap 120: verify with 3 allies + Rend/Sunder/Phantom Step/Mirror Break/Execution stacked. Cap must apply to ALL damage sources (hitbox, shockwave, ally skills, ward/debuff ticks, gore/environment, pillar collapse). Find any path that bypasses `EnemyBase` damage entry.
   - Death log: does it name the source correctly for each cause?
   - Checkpoint death in Phase 2 -> `_on_enemy_reset()`: `RealmManager` un-merged, `CentralMirrorPlane` repaired, HP/phase reset, HUD boss bar reset, no double-registered kill in `EncounterDirector`.
2. **HEALTH_SCALE x2.5 applied once**
   - Archetype enemies (Hexcaster, Brute, Stalker), roamers, `_enlarge_enemy` gate guards (x1.35), reset/respawn, save-load: is HP ever scaled twice (e.g. `_ready` re-run after reparent, scene reload) or not at all? Compare max HP in `game_manage get_node_info` before/after reload.
   - Rebalance fallout: time-to-kill for Skeleton, Shielded, Brute with only light chain; softlock risk if an encounter needs a kill the player can't achieve (shield guard, Mirror-only phantoms).
   - Score/time-bonus/rank thresholds (`05`) tuned for old HP: does S-rank still reachable?
3. **Execution immunity**: `F` on Warden (must refuse, feedback shown), on phantoms in Reality, on enemies at exactly 35% boundary, and Q Mirror Break. Finisher prompt must not appear / must not consume the slow-mo window incorrectly.
4. **Phantom Twin Mirror-only combat**
   - Reality: immune, harmless (hitbox veto `can_damage_target`), translucent. Verify transparency is restored when switching to Mirror and when merged (`REALMS MERGED`). Check multiple twins sharing materials: does one's transparency leak to other enemies/skeletons (shared material resources)?
   - Encounter completion: can the Hall of Echoes encounter complete if the player never enters the Mirror? (Gate stays shut = intended hint?) Is there an objective/hint telling the player? Can allies get stuck attacking an unhittable target (`hittable now` hook)?
   - Realm switch mid-lunge, mid-hit-stop, while stunned.
5. **Hitbox owner veto**: any other attacker accidentally vetoed? Player hitboxes, ally hitboxes, enemy projectiles, environment hazards. Check `Hitbox3D.pulse_radial_targets` AoE path also respects veto.
6. **Ivo caster**: staff attaches on respawn and after `CharacterLoadout` reload; no sword remains; ranged behaviour holds range vs melee closing in, line-of-sight blocked by walls, no friendly fire, Chain Arc bolts visibly hop and terminate (no infinite hop / no hop to dead/immune targets).
7. **Allies ignoring unhittable targets**: allies must not idle forever when only unhittable enemies remain; they should still follow the player.
8. **Warnings to triage**: `enemy_base.gd:8 UNUSED_SIGNAL staggered` (is nothing listening? dead feature?), integer divisions in `breakable_prop.gd:170`, `game_feel.gd:381`, `squad_ally.gd:2590/2594/2676`.

## Evidence
Video-like screenshot sequences, HP values from `get_node_info`, game logs, death-log lines, repro steps for each FAIL.

## Verdict format
PASS / FAIL / UNVERIFIED per item, file:line, severity.

---
## Findings (2026-11-18 — Live & Code Verification)

- **1. Warden Phase 1 -> 2, Hit Cap, Fall Safety & Reset**:
  - **FAIL (MAJOR — Phase 1 Overkill Bypass)** — `warden_boss.gd:301` checks `if current_phase == Phase.PHASE_1_SPLIT and health > 0 and health <= _phase2_threshold():`. In live probe (`_sanity_probe_2.gd`), hitting Warden at `1300` HP for `1500` sets `health = 0` (`enemy_base.gd:166`), so `health > 0` fails and Warden **dies in Phase 1 (`phase=1`) skipping Phase 2 completely**. Fix needed: clamp Phase 1 lethal damage above 0 or trigger Phase 2 when `health <= _phase2_threshold()` even at 0.
  - **PASS** — Phase 2 `phase2_max_hit = 120` caps `player_heavy`, `ally_skill`, and `player_execution` (`took_ally=120, took_exec=120`). Note: `source_type == "environmental"` intentionally bypasses cap (`warden_boss.gd:283`), though `PitKillZone` intercepts Warden and teleports him home (`pit_kill_zone.gd:68-72`).
  - **PASS** — `warden_fall_snaps_home` (`combat_rules_test.gd`) and `warden_phase2_reset_restores_all` (`is_merged=false, shift_locked=false, hp=2500, phase=1`).
- **2. `HEALTH_SCALE` x2.5 & Combat Balance**:
  - **PASS** — All 57 enemies scale once: Skeleton `250`, Phantom `200`, Shielded `625`, Brute `650`, Stalker `225`, Hexcaster `175` (`70 * 2.5`), Warden `2500`.
  - **FAIL (Existing test suite regression — `tests/feel_and_movement_test.gd` 4/13 failed)**: `chain_reaches_5_distinct_moves`, `rhythm_taps_flow`, `pause_branch_rising_arc`, and `f_in_window_executes` (`dead=false hp=60` on shielded/150HP forecourt enemy) all failed in Godot 4.7.2. Note: even on empty terrace `z=-136`, a synthetic probe waiting up to 1.5s for `_is_flow_timing()` stopped at `steps=[1, 2, 3]` because `light_3` timed out/reset differently; needs dedicated verification of `light_4`/`light_5` rhythm timing under 60 FPS vs lower FPS.
- **3. Execution immunity**: **PASS** — `WardenBoss.execute_immune = true` verified in `combat_rules_test.gd` and `player_controller.gd:945`.
- **4. Phantom Twin Mirror-only combat**:
  - **PASS** — `combat_rules_test.gd` confirms `phantom_immune_in_reality`, `phantom_harmless_in_reality`, `phantom_hurt_in_mirror`. Live probe confirmed `3` twins all shift `transparency = 0.6` in Reality and restore `0.0` in Mirror with no material leakage across instances.
  - **MINOR** — `ObjectiveTracker` (`objective_tracker.gd:103-105`) shows generic Mirror weak-point tip rather than explicitly saying Phantoms are immune in Reality if only Phantoms remain.
- **5. Hitbox owner veto (`can_damage_target`)**: **PASS** — `Hitbox3D.try_hit_target` checks `my_owner.can_damage_target(logical_target)` (`hitbox_3d.gd:84`), and `pulse_radial_targets` calls `try_hit_target` (`hitbox_3d.gd:143`).
- **6. Ivo caster (`03_ivo.tres`, `squad_ally.gd`)**:
  - **PASS** on visual staff & no visible sword (`has_staff=true, sword_vis=false`), ranged hold (`RANGED_MIN`/`RANGED_MAX`), and Chain Arc termination (stops cleanly on `!_enemy_ok(e)`).
  - **MINOR** — `_launch_bolt` (`squad_ally.gd:1856-1887`) tweens linearly via `lerp` without physics/raycast line-of-sight collision, so bolts pass visually through walls/pillars.
- **7. Allies ignore unhittable targets**: **PASS (code)** — `squad_ally.gd:3465` checks `e.is_hittable_now()`, skipping Reality Phantoms cleanly.
- **8. GDScript warnings triage**: **PASS (benign)** — `EnemyBase.staggered` IS emitted by `EnemyAI` (`enemy_ai.gd:476,491`); integer divisions in `breakable_prop.gd:170`, `game_feel.gd:381`, `squad_ally.gd:2590/2594/2676` are all intentional index/sample-count math.
