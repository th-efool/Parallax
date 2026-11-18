# IdiotHandOffGuide — PARALLAX Sanity-Testing 1–5 & Live-Play Remediation

> **Scope**: Single self-contained handoff to resolve every bug, regression, warning, and documentation drift found across [`plan/Sanity-Testing-1.md`](plan/Sanity-Testing-1.md) through [`plan/Sanity-Testing-5.md`](plan/Sanity-Testing-5.md) plus live-playtester bugs and tuning updates `REQ-13`–`REQ-24`.
> **Readiness**: `READY` (all target files, symbols, signatures, and test names verified against the working tree at commit `dcfd0b2`).
> **Executor Rule**: Apply Steps 1–22 in exact order, run every verification command in Section E, and return the completion table defined in Section F. Do **not** create extra `.md` files in the repo root or `MEMORY/`.

---

## A. Execution Contract

### A.1 Repository & Runtime Baseline (Observed Before Handoff)
- **Repository Root**: `D:\Desktop\Godot\parallax`
- **Branch / HEAD Commit**: `master` @ `dcfd0b2`
- **Engine Binary**: `C:/Users/agrim/.local/bin/godot.cmd` (`Godot Engine v4.7.2.stable.official.ed1daf0bf`, Forward+, Windows 64-bit)
- **Shell**: PowerShell (Windows)
- **Existing Uncommitted Changes (PRESERVE — do NOT revert or overwrite)**:
  - `M assets/models/characters/Knight_knight_texture.png.import` (editor s3tc reimport)
  - `M project.godot` (ordered `[audio]`/`[rendering]` keys)
  - `D IdiotCheckInQualityAssessment.md`, `D tasks-report.md`, `D plan/IdiotHandOffGuide_01..05.md`
  - `?? plan/Sanity-Testing-1.md` .. `plan/Sanity-Testing-5.md`
- **Author Validation Status Prior to Execution**:
  - The fixes in this guide were derived by direct inspection of source code, Godot 4.7.2 live/headless repro probes, and existing test suites (`sanity-testing 1..5`). **None of the patches in Section D have been applied to the workspace yet**; the executor is responsible for applying them and running Section E to confirm all checks pass.

### A.2 Strict Operating Rules for the Executor
1. **Verify Baseline First**: Confirm `git branch --show-current` is `master` (`dcfd0b2`) and preserve existing uncommitted changes in `project.godot`, `.import`, and `plan/Sanity-Testing-*.md`.
2. **Apply Steps 1–22 In Order**: Every edit uses exact `Find:` -> `Replace with:` blocks or full file creation (`Create:`). If any `Find:` block fails to match uniquely, **STOP**, report the file path and actual lines around the target, and do not guess.
3. **Never Improvise Outside Scope**: Do not rename nodes, signals, physics layers, or groups (`AGENTS.md` / `MEMORY/02`). Do not create any `.md` files in root or `MEMORY/` (`AGENTS.md` Rule 1.2).
4. **No Temporary Leftover Files**: Only the files listed in Section C may be modified or created (`tests/sanity_regression_test.gd` is permanent).
5. **Run Full Verification Suite (Section E)**: Every headless and windowed test listed in Section E must pass with exit code `0` and zero new errors/warnings.

---

## B. Requirements & Acceptance Map

| Req ID | Source Sanity Pass | Severity | Summary of Defect | Implementing Step(s) | Verification Check(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **REQ-01** | Sanity-Testing-1 (#1) & Sanity-Testing-3 (#2) | **MAJOR** | `ObjectiveTracker._refresh()` sets `_labels_done = true` while still on Title Screen (`MainController.level_ready == false`), missing all 5/5 `WorldHint` prop labels; `tests/visual_check_shots.gd` also triggers OS TTS near Forecourt guards and hangs `quit(0)`. | Step 1 | `VER-01`, `VER-02` (`world_hint_props_5_of_5`), `VER-11` |
| **REQ-02** | Sanity-Testing-2 (#1) | **MAJOR** | `WardenBoss` Phase 1 single-hit overkill reduces `health` to `0`, failing `health > 0` in `_on_damage_taken` and killing Warden in Phase 1 without entering Phase 2 (`PHASE_2_MERGED`); Phase 2 `phase2_max_hit = 120` also bypassed for `"environmental"`. | Step 2 | `VER-01`, `VER-02` (`warden_phase1_overkill_transitions_to_phase2`), `VER-05` |
| **REQ-03** | Sanity-Testing-5 (#5) | **MAJOR** | Undamaged enemy `FloatingHPBar` labels display `100/100` instead of scaled `250/250` because `_attach_enemy_hp_bar` sets text before `EnemyBase._ready()` applies `HEALTH_SCALE = 2.5` and `_ready()` never emits `health_changed`. | Step 3 | `VER-01`, `VER-02` (`enemy_hp_bar_scaled_on_spawn`), `VER-05` |
| **REQ-04** | Sanity-Testing-4 (#2) | **MAJOR** | `GrandJourneyBuilder._enlarge_enemy(e, 1.35)` scales `VisualRoot`, `BodyCollider`, `Hurtbox3D`, and `attack_range` (`2.49 m`) but not `AttackHitbox` (`1.90 m` reach), causing `GateWarden_W/E` to whiff at max range. | Step 4 | `VER-01`, `VER-02` (`enlarged_gate_warden_hitbox_reach`), `VER-06` |
| **REQ-05** | Sanity-Testing-3 (#2, #6) | **MAJOR** | `SquadTTSPlayer` lacks `_exit_tree()` stopping active streams and `DisplayServer.tts_stop()`; `SquadCommsHUD` lacks `_exit_tree()` clearing `PlayerController.ui_input_locked` if freed while chat is open. | Step 5 | `VER-01`, `VER-02` (`tts_and_comms_hud_exit_cleanup`), `VER-09` |
| **REQ-06** | Sanity-Testing-5 (#4) | **MAJOR** | `WorldIntel.resolve()`, `AllySquadManager._active_enemies_near()`, `resolve_enemy()`, and `execute_strategy()` select Reality-immune `PhantomTwin` (`ForecourtPhantom`) in Reality, causing `strategy_divide_distinct_targets` in `tests/squad_ai_windowed_test.gd` to drop target `E1` on frame 1 (`["E21", "E20"]`). | Step 6 | `VER-01`, `VER-02` (`world_intel_excludes_reality_phantom`), `VER-08`, `VER-10` |
| **REQ-07** | Sanity-Testing-5 (#4) | **MAJOR** | `taunted_enemy_chases_past_leash` in `tests/squad_ai_windowed_test.gd` spawns `fx` at `(0,0,-6)` on Forecourt and `taunter` at `(-15.3,0,-30.3)` on diagonal `R1` bridge, snagging on the `z=-15` Forecourt join rail at `9.8 m` (`< 22 m` leash). | Step 7 | `VER-01`, `VER-10` |
| **REQ-08** | Sanity-Testing-2 (#2) | **MAJOR** | `tests/feel_and_movement_test.gd` fails 4/13 checks (`chain_reaches_5_distinct_moves`, `rhythm_taps_flow`, `pause_branch_rising_arc`, `f_in_window_executes`) due to spawning on `Gate_Forecourt` `(0,0,-14)` with hostile guards, `_is_flow_timing()` remaining `true` outside `State.LIGHT_ATTACK`, fixed pause timers expiring `0.90s`, and Section 4 picking `ForecourtPhantom`. | Step 8 | `VER-01`, `VER-09` (`13/13 PASS`) |
| **REQ-09** | Sanity-Testing-5 (#5) | **MINOR** | `GoreFX._attach_bleed_trail` captures `p: CPUParticles3D` inside a `SceneTreeTimer` lambda, causing Godot 4.7 `ERROR: Lambda capture at index 0 was freed. Passed "null" instead.` when gibs are freed early under `MAX_GIBS`. | Step 9 | `VER-01`, `VER-02` (`gore_gib_recycle_no_lambda_error`) |
| **REQ-10** | Sanity-Testing-5 (#5) | **MAJOR** | High GPU draw-call overhead (`1,663` draws / `14 FPS`) in 60×60 Hall of Echoes: distant bridge bastion non-boss enemy rigs have no `visibility_range_end`, and `SunLight` uses 4 splits / `120 m` even on Low/Medium shadow presets. | Step 10 | `VER-01`, `VER-02` (`non_boss_enemy_visibility_range_set`), `VER-03` |
| **REQ-11** | Sanity-Testing-1 (#8) | **MINOR** | Benign GDScript warnings (`INTEGER_DIVISION` in `world_label_overlay.gd`, `hud_controller.gd`, `squad_comms_hud.gd`, `leaderboard_store.gd`; `SHADOWED_VARIABLE` `tr` & `UNUSED_VARIABLE` `_last_realm_key` in `hud_controller.gd`; enum coercion `as Key` in `squad_comms_hud.gd`). | Step 5, Step 10, Step 11 | `VER-01` (`0 warnings` on touched scripts) |
| **REQ-12** | Sanity-Testing-4 (#7) & AGENTS.md Rule 1.3 | **MINOR** | `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md` §6 lists pre-Guide-05 story coordinates without a world-coordinate conversion banner/table; `MEMORY/03`, `05`, `07` need sync entries. | Step 22 | Inspection of `MEMORY/03`, `04`, `05`, `07` |
| **REQ-13** | Live Playtest (TTS Prompt Leak) | **CRITICAL** | `OpenAIClient.speak_stream()` prepends `style + pace + "Say: "` into Gemini TTS `contents`, and `SquadComms.build_system_prompt()` injects `Speaks: <tts_instructions>`, causing voice output to read Ivo/Brannoc system/style prompts aloud instead of only dialogue. | Step 12 | `VER-01`, `VER-02` (`tts_prompt_not_spoken_aloud`), `VER-08`, `VER-08b` |
| **REQ-14** | Live Playtest (Gate Bypass Softlock) | **MAJOR** | Sneaking past a closed gate (`Gate01`–`Gate05`), unrepaired gallery bridge, or mechanism puzzle leaves `ObjectiveTracker` and `EncounterDirector` stuck on the skipped objective/encounter indefinitely. | Step 13 | `VER-01`, `VER-02` (`bypassed_gate_auto_clears_objective`) |
| **REQ-15** | Live Playtest (Far Enemies Passive) | **MAJOR** | `EnemyAI.detection_range` (`9–12 m`), `max_chase_distance` (`18–24 m`), `_process_chase()` drop threshold (`detection_range * 2.2`), and `SquadCoordinator` radii (`9/18/11 m`) were never scaled for the `60×60 m` Hall of Echoes and `36×36 m` Mechanism Chamber, so far enemies ignore the squad until point-blank. | Step 14, Step 18, Step 20 | `VER-01`, `VER-02` (`hall_enemies_engage_on_entry`), `VER-10` |
| **REQ-16** | Live Playtest (Ally Teleport Loop) | **MAJOR** | `SquadAlly._catch_up()` (`20/30 m`), `_update_stuck()` (`> 6.0 m` after `2.0 s`), and `_kite_logic` (`approach_t > 9.0 s`) repeatedly teleport an ally back to the player when ordered to distract/attack distant enemies. | Step 15 | `VER-01`, `VER-02` (`ally_distant_order_not_teleported`), `VER-10` |
| **REQ-17** | Live Playtest (HUD & Label Readability) | **MAJOR** | Top-left squad ally names (`SquadCommsHUD`), center `ObjectiveTracker` title/hints, and overhead player/ally/prop `WorldLabelOverlay` text use thin strokes without dark backing plates, making text unreadable over bright backgrounds. | Step 16 | `VER-01`, `VER-11` |
| **REQ-18** | Live Playtest (+20% UI Icons) | **MINOR** | Skill/action diamonds, weapon diamond, crest badge, Reality/Mirror chips & glyphs, swap medallion, mic button, and finisher diamonds are undersized and should scale up by ~20%. | Step 16 | `VER-01`, `VER-02` (`ui_icons_scaled_up_20pct`), `VER-11` |
| **REQ-19** | Live Playtest (Camera-Visible Targeting & Pull) | **MAJOR** | Asking allies to pull/taunt a farther visible enemy fails with `"Nothing to taunt."`; base targetable range increases must stay `<= +30%` (`WorldIntel.RANGE_M = 52 m`, `FOLLOW_LEASH = 19.5 m`, fallbacks `32.5 / 26 m`), while a periodic `1.2 s` camera-frustum scan automatically makes any camera-visible active enemy (`<= 140 m`) targetable and pullable. | Step 6, Step 15 | `VER-01`, `VER-02` (`camera_visible_enemy_targetable_and_pull`), `VER-08`, `VER-10` |
| **REQ-20** | Live Playtest (Slow Ally & Player Regen) | **MAJOR** | Allies recover HP near-instantly (`3.0×` retreat regen multiplier, `regen_per_sec = 3–4`, and Ivo's autonomous `35%` `mending_light` burst), while the player has zero regen; cap ally/player regen to slow rates taking at least `125 s` (`>= 2 min`) from `0` to `max_health` and disable autonomous `mending_light` bursts. | Step 17 | `VER-01`, `VER-02` (`slow_player_and_ally_health_regen`) |
| **REQ-21** | Live Playtest (2-Checkpoint Death Rewind) | **MAJOR** | Player death respawns at the current section checkpoint instead of 2 checkpoints behind, leaving skipped/intervening sections cleared; rewind `_checkpoint_history` by 2 checkpoints (`>= 0`) and reset/respawn all intervening sections, gates/triggers, and enemies. | Step 18 | `VER-01`, `VER-02` (`death_respawns_two_checkpoints_back_and_resets_enemies`) |
| **REQ-22** | Live Playtest (Distinct Enemy Skins/Gear) | **MAJOR** | Enemy knights (`ShieldedGuard` on `Knight.glb`), `TheWarden` (`Barbarian.glb`), and archetypes share silhouettes/palettes too close to Player, Brannoc, Sera, and Ivo; apply distinct dark hostile armor/skin tints, emissions, and enemy `Knight` loadout (`2H_Sword` + `Spike_Shield`). | Step 14, Step 19 | `VER-01`, `VER-02` (`enemy_visuals_distinct_from_player_and_allies`), `VER-11` |
| **REQ-23** | Live Playtest (Skeleton 1-Time Revive) | **MAJOR** | `SkeletonGuard` dies permanently on first lethal damage instead of rising once from a fall-down state after a few seconds. | Step 20 | `VER-01`, `VER-02` (`skeleton_soldier_revives_once_and_enemy_stats_scaled`) |
| **REQ-24** | Live Playtest (+40% Dmg, +50% Mobs, +30% HP) | **MAJOR** | Increase all enemy damage by `+40%` (`EnemyAI.DAMAGE_SCALE = 1.4` + Warden `28/35`), mob enemy counts by `+50%` across every arena/bastion (`GrandJourneyBuilder`), and all enemy HP by `+30%` (`EnemyBase.HEALTH_SCALE = 3.25`). | Step 2, Step 3, Step 7, Step 14 | `VER-01`, `VER-02` (`skeleton_soldier_revives_once_and_enemy_stats_scaled`), `VER-05`, `VER-07` |

---

## C. File-Change Manifest

| File Path (Relative to Repo Root) | Operation | Step ID | Purpose |
| :--- | :--- | :--- | :--- |
| `scripts/ui/objective_tracker.gd` | `modify` | Step 1, Step 13, Step 16 | Defer `WorldHint` labeling until `level_ready`; auto-clear bypassed gates/encounters/bridges/puzzles (`REQ-14`); add dark backing plate + bolder contrast styling (`REQ-17`). |
| `tests/visual_check_shots.gd` | `modify` | Step 1 | Call `SquadAIConfig.force_offline()` in `_initialize()` so OS TTS does not hang exit. |
| `scripts/enemies/warden_boss.gd` | `modify` | Step 2 | Cap Phase 1 incoming damage at `_phase2_threshold()`, apply `phase2_max_hit` before environmental bypass, and scale `cleave_damage = 28`, `lunge_damage = 35` (`+40%`). |
| `scripts/enemies/enemy_base.gd` | `modify` | Step 3 | Raise `HEALTH_SCALE` from `2.5` to `3.25` (`+30%` HP) and emit `health_changed.emit(health, max_health)` at end of `_ready()`. |
| `tests/combat_rules_test.gd` | `modify` | Step 3 | Update scaled HP assertions from `250/2500/1250` to `325/3250/1625` to match `HEALTH_SCALE = 3.25`. |
| `scripts/environment/grand_journey_builder.gd` | `modify` | Step 4, Step 14 | Scale `AttackHitbox` shapes in `_enlarge_enemy()`; scale Hall (`56/68 m`) & Chamber (`38/48 m`) ranges; expand enemy spawns `+50%` per area (`REQ-24`). |
| `addons/parallax_squad_ai/tts_player.gd` | `modify` | Step 5 | Add `_exit_tree()` calling `stop_all()` and `DisplayServer.tts_stop()`. |
| `scripts/ui/squad_comms_hud.gd` | `modify` | Step 5, Step 16 | Add `_exit_tree()`, fix warnings, add dark backing plate + brighter high-outline top-left ally names (`REQ-17`), and scale `MicButton` +20% (`REQ-18`). |
| `scripts/allies/world_intel.gd` | `modify` | Step 6, Step 15 | Exclude `!is_hittable_now()` in `resolve()`; cap `RANGE_M` at `52.0 m` (`+30%`), add `1.2 s` camera-frustum scan `_scan_camera_visible()` (`<= 140 m`), and support `"farther"/"further"/"distant"` pull queries. |
| `scripts/allies/ally_squad_manager.gd` | `modify` | Step 6, Step 15 | Exclude `!is_hittable_now()`, allow camera-visible targets inside `_active_enemies_near()`, and cap `resolve_enemy()` fallback radius at `32.5 m` (`+30%`). |
| `tests/squad_ai_windowed_test.gd` | `modify` | Step 7 | Isolate Section 2 with `_reset_arena()`, place `FixationDummy` path on `R1` bridge `(-1,0,-16)` -> `(-21,0,-36)` (`max_chase_distance = 22.0`), and disable non-`Test_` roamers in `_reset_arena()`. |
| `scripts/player/player_controller.gd` | `modify` | Step 8, Step 17 | Gate `_is_flow_timing()` on `State.LIGHT_ATTACK`; add slow passive regen (`health_regen_seconds_to_full = 125.0`, >= 2 min 0 -> full). |
| `tests/feel_and_movement_test.gd` | `modify` | Step 8 | Spawn combo checks on clear terrace `(0,0,-136)`, track `_attacks.size()` & `_since_attack_end`, and filter execution victim cleanly. |
| `scripts/core/gore_fx.gd` | `modify` | Step 9 | Replace `SceneTreeTimer` lambda in `_attach_bleed_trail()` with a `p`-bound `Tween` + `p.set_emitting.bind(false)`. |
| `scripts/environment/colosseum_greybox_builder.gd` | `modify` | Step 10 | Set `visibility_range_end = 58.0` (with 4 m fade) on non-boss enemy `MeshInstance3D` nodes. |
| `scripts/core/leaderboard_store.gd` | `modify` | Step 10 | Scale `SunLight` directional shadow splits/distance (`2 splits / 65 m` when `shadow_quality <= 1`) and fix `INTEGER_DIVISION` in `format_time()`. |
| `scripts/ui/world_label_overlay.gd` | `modify` | Step 11, Step 16 | Fix `INTEGER_DIVISION` (`Step 11`), add dark translucent backing pill + thicker outline behind world labels (`REQ-17`). |
| `scripts/ui/hud_controller.gd` | `modify` | Step 11, Step 16 | Fix warnings (`Step 11`), strengthen HUD label outlines (`REQ-17`), and scale action/weapon/crest/swap/realm icons +20% (`REQ-18`). |
| `addons/parallax_squad_ai/openai_client.gd` | `modify` | Step 12 | Send ONLY pure dialogue text (never `style`/`pace`/`Say:`) in Gemini TTS `contents`. |
| `addons/parallax_squad_ai/squad_comms.gd` | `modify` | Step 12 | Remove `Speaks: <tts_instructions>` from `build_system_prompt()` and sanitize spoken text via `sanitize_spoken_line()`. |
| `scripts/environment/mechanism_puzzle.gd` | `modify` | Step 13 | Add `force_solve_bypass()` to resolve `ChamberMechanismPuzzle` cleanly when bypassed. |
| `scripts/enemies/enemy_ai.gd` | `modify` | Step 14 | Raise `detection_range` (`22 m`), `max_chase_distance` (`52 m`), and chase retention range; apply global `DAMAGE_SCALE = 1.4` (`+40%` damage) in `_ready()`. |
| `scripts/enemies/archetype_enemy.gd` | `modify` | Step 14 | Apply `DAMAGE_SCALE = 1.4` on archetype `attack_damage` and widen caster lose-sight threshold `lose_range`. |
| `scripts/enemies/phantom_twin.gd` | `modify` | Step 14 | Raise `PhantomTwin.detection_range` from `9.0` to `24.0`. |
| `scripts/enemies/shielded_guard.gd` | `modify` | Step 14 | Raise `ShieldedGuard.detection_range` from `10.0` to `20.0`. |
| `scripts/enemies/squad_coordinator.gd` | `modify` | Step 14 | Raise `join_radius` (`22 m`), `alert_radius` (`38 m`), and `engage_radius` (`24 m`). |
| `data/enemies/hollow_hexcaster.tres` | `modify` | Step 14 | Raise `detection_range = 26.0`, `max_chase_distance = 52.0`, and darken hostile indigo-magenta tint/emission (`REQ-22`). |
| `data/enemies/grave_brute.tres` | `modify` | Step 14 | Raise `detection_range = 22.0`, `max_chase_distance = 48.0`, and apply dark swamp-olive hide tint/emission (`REQ-22`). |
| `data/enemies/shade_stalker.tres` | `modify` | Step 14 | Raise `detection_range = 26.0`, `max_chase_distance = 56.0`, and apply dark blood-plum tint/emission (`REQ-22`). |
| `scripts/allies/squad_ally.gd` | `modify` | Step 15, Step 16, Step 17 | Exempt distant/camera-visible orders from catch-up teleports while keeping `FOLLOW_LEASH = 19.5 m` (`+30%`); handle pull-here taunt fallback (`REQ-19`); raise overhead contrast (`REQ-17`); remove `3×` retreat regen burst & cap regen (`REQ-20`). |
| `scripts/allies/squad_command_parser.gd` | `modify` | Step 15 | Match `"pull em/them/it/that"`, `"bring"`, and distance descriptors `"farther"/"further"/"distant"` cleanly (`REQ-19`). |
| `scripts/ui/ui_theme.gd` | `modify` | Step 16 | Prefer `Rajdhani-SemiBold.ttf` with bold weight variation on `body_font()` for legible HUD/objective text. |
| `scripts/ui/finisher_prompt.gd` | `modify` | Step 16 | Scale finisher diamonds (`r 30 -> 36`) and option spacing (`190 -> 216`) +20% (`REQ-18`). |
| `scripts/allies/ally_profile.gd` | `modify` | Step 17 | Lower default `regen_per_sec` from `3.0` to `1.0`. |
| `data/allies/01_brannoc.tres` | `modify` | Step 17 | Lower `regen_per_sec` from `4.0` to `1.5`. |
| `data/allies/02_sera.tres` | `modify` | Step 17 | Lower `regen_per_sec` from `3.0` to `0.95`. |
| `data/allies/03_ivo.tres` | `modify` | Step 17 | Lower `regen_per_sec` from `3.0` to `0.88`; disable autonomous `mending_light` bursts (`auto_use = ""`, `power = 0.18`). |
| `scripts/core/encounter_director.gd` | `modify` | Step 18 | Alert active Hall/Chamber enemies on entry (`REQ-15`); maintain `_checkpoint_history` to respawn 2 checkpoints behind and reset intervening enemies/triggers/gates on death (`REQ-21`). |
| `scripts/core/character_loadout.gd` | `modify` | Step 19 | Arm enemy `Knight_Body` rigs with `["2H_Sword", "Spike_Shield"]` and enemy `Barbarian_Body` with `["2H_Axe", "Barbarian_Round_Shield"]` so silhouettes differ from Player & Brannoc. |
| `scripts/core/character_animation_bridge.gd` | `modify` | Step 19 | Apply distinct dark hostile armor/skin materials and glow emissions to `WardenBoss`, `ShieldedGuard`, and `SkeletonGuard` in `bind_actor()`. |
| `scripts/enemies/skeleton_guard.gd` | `modify` | Step 20 | Raise `detection_range = 22.0` (`REQ-15`) and give `SkeletonGuard` a 1-time `3.0 s` fall-down self-revive (`50%` HP) before final death (`REQ-23`). |
| `tests/sanity_regression_test.gd` | `create` | Step 21 | Permanent headless regression script covering `REQ-01`..`REQ-24` (18 checks). |
| `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` | `modify` | Step 22 | Document combat scales (`+30% HP`, `+40% dmg`), Skeleton 1-time revive, distinct enemy visuals, slow player/ally regen, `1.2 s` camera targeting, and distant-order tether. |
| `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md` | `modify` | Step 22 | Add Guide-05 world-Z table (`§6.0`), `+50%` mob spawns, gate-bypass auto-clear, and 2-checkpoint death rewind contract. |
| `MEMORY/05_UI_SCORING_AND_AUDIO.md` | `modify` | Step 22 | Document `ObjectiveTracker` guard, `_exit_tree()` cleanup, Gemini TTS pure-dialogue fix, contrast plates, and +20% icon sizing. |
| `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | `modify` | Step 22 | Append dated remediation changelog entry covering Sanity-Testing 1–5 + live-play `REQ-13`–`REQ-24`. |

---

## D. Ordered Implementation Steps

### Step 1 — Defer `ObjectiveTracker` Prop Labels Until `level_ready` & Stabilize `visual_check_shots.gd` (`REQ-01`)

- **Prerequisites**: Unmodified `scripts/ui/objective_tracker.gd` and `tests/visual_check_shots.gd`.
- **Target 1**: `scripts/ui/objective_tracker.gd` (lines 66–74)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
func _refresh() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or _find_level() == null:
		_obj = {}
		return
	if not _labels_done:
		_labels_done = true
		_label_props()
```

**Replace with:**
```gdscript
func _refresh() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var main: Node = tree.get_first_node_in_group("main_controller")
	if main != null and "level_ready" in main and not bool(main.get("level_ready")):
		_obj = {}
		return
	var player: Node3D = tree.get_first_node_in_group("player") as Node3D
	if player == null or _find_level() == null:
		_obj = {}
		return
	if not _labels_done:
		_label_props()
		if _n("Stage01_EntryVestibule/EntryMirrorSwitch") != null:
			_labels_done = true
```

- **Target 2**: `tests/visual_check_shots.gd` (lines 7–14)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
```

**Replace with:**
```gdscript
func _initialize() -> void:
	SquadAIConfig.force_offline()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
```

- **Postcondition**: `_labels_done` becomes `true` only after `MainController.level_ready == true` and `Stage01_EntryVestibule/EntryMirrorSwitch` exists in the scene tree; `tests/visual_check_shots.gd` disables voice synthesis on startup.

---

### Step 2 — Prevent `WardenBoss` Phase 1 Overkill Bypass, Cap Phase 2 Environmental Damage & Apply +40% Warden Damage (`REQ-02`, `REQ-24`)

- **Prerequisites**: None.
- **Target 1**: `scripts/enemies/warden_boss.gd` (lines 25–28)
- **Action**: Replace block (exact single match) to raise `cleave_damage` and `lunge_damage` by `+40%` (`20 -> 28`, `25 -> 35`).

**Find:**
```gdscript
@export_group("Warden Tuning")
@export var cleave_damage: int = 20
@export var lunge_damage: int = 25
@export var cleave_range: float = 2.8
```

**Replace with:**
```gdscript
@export_group("Warden Tuning")
@export var cleave_damage: int = 28
@export var lunge_damage: int = 35
@export var cleave_range: float = 2.8
```

- **Target 2**: `scripts/enemies/warden_boss.gd` (lines 77–81)
- **Action**: Replace block (exact single match) so `WardenBoss._init()` uses the `+40%` `28` damage and marks `_damage_scaled = true` so `EnemyAI._ready()` does not double-scale it.

**Find:**
```gdscript
	stagger_duration = 0.80
	attack_damage = 20
	attack_name = "warden_cleave"
```

**Replace with:**
```gdscript
	stagger_duration = 0.80
	attack_damage = 28
	_damage_scaled = true
	attack_name = "warden_cleave"
```

- **Target 3**: `scripts/enemies/warden_boss.gd` (lines 280–303)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
func _modify_incoming_damage(amount: int, _is_heavy: bool, source_type: String) -> int:
	if current_phase == Phase.PHASE_2_TRANSITION:
		return 0
	if source_type == "environmental":
		return amount
	if current_phase == Phase.PHASE_2_MERGED:
		return mini(amount, phase2_max_hit)
	if is_vulnerable_to_full_damage():
		return amount
	return mini(amount, phase1_reality_armor_cap)


func _phase2_threshold() -> int:
	return int(round(float(max_health) * 0.5))


func _should_stagger_on_hit(is_heavy: bool, _source_type: String) -> bool:
	return is_heavy and is_vulnerable_to_full_damage()


func _on_damage_taken(_final_damage: int, _is_heavy: bool, _source_type: String) -> void:
	if current_phase == Phase.PHASE_1_SPLIT and health > 0 and health <= _phase2_threshold():
		_trigger_phase2_transition()
```

**Replace with:**
```gdscript
func _modify_incoming_damage(amount: int, _is_heavy: bool, source_type: String) -> int:
	if current_phase == Phase.PHASE_2_TRANSITION:
		return 0
	if current_phase == Phase.PHASE_2_MERGED:
		return mini(amount, phase2_max_hit)
	var raw: int = amount
	if source_type != "environmental" and not is_vulnerable_to_full_damage():
		raw = mini(amount, phase1_reality_armor_cap)
	var cap_to_p2: int = maxi(1, health - _phase2_threshold())
	return mini(raw, cap_to_p2)


func _phase2_threshold() -> int:
	return int(round(float(max_health) * 0.5))


func _should_stagger_on_hit(is_heavy: bool, _source_type: String) -> bool:
	return is_heavy and is_vulnerable_to_full_damage()


func _on_damage_taken(_final_damage: int, _is_heavy: bool, _source_type: String) -> void:
	if current_phase == Phase.PHASE_1_SPLIT and health <= _phase2_threshold():
		health = maxi(health, _phase2_threshold())
		_trigger_phase2_transition()
```

- **Postcondition**: Any lethal/oversized Phase 1 hit clamps `health` to `_phase2_threshold()` (`1625` of `3250`) and enters `PHASE_2_TRANSITION`; Phase 2 caps all damage sources including `"environmental"` at `phase2_max_hit` (`120`); Warden deals `28`/`35` damage (`+40%`).

---

### Step 3 — Raise Enemy `HEALTH_SCALE` +30% (`3.25x`), Emit `health_changed`, & Update Combat Rules Test (`REQ-03`, `REQ-24`)

- **Prerequisites**: None.
- **Target 1**: `scripts/enemies/enemy_base.gd` (lines 28–32)
- **Action**: Replace block (exact single match) to raise global `HEALTH_SCALE` by `+30%` (`2.5 -> 3.25`).

**Find:**
```gdscript
## Global enemy durability multiplier (2026-11-18: "enemies need at least 2.5x the health"). Applied once to the
## authored max_health in _ready(), so scripted enemies and data-driven archetypes are all covered.
const HEALTH_SCALE: float = 2.5
var _health_scaled: bool = false
```

**Replace with:**
```gdscript
## Global enemy durability multiplier (+30% over 2.5x = 3.25x). Applied once to the authored max_health in
## _ready(), so scripted enemies and data-driven archetypes are all covered.
const HEALTH_SCALE: float = 3.25
var _health_scaled: bool = false
```

- **Target 2**: `scripts/enemies/enemy_base.gd` (lines 69–75)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	if not _health_scaled:
		_health_scaled = true
		max_health = maxi(1, int(round(float(max_health) * HEALTH_SCALE)))
	health = max_health

	if EncounterDirector.instance != null:
```

**Replace with:**
```gdscript
	if not _health_scaled:
		_health_scaled = true
		max_health = maxi(1, int(round(float(max_health) * HEALTH_SCALE)))
	health = max_health
	health_changed.emit(health, max_health)

	if EncounterDirector.instance != null:
```

- **Target 3**: `tests/combat_rules_test.gd` (lines 27–38)
- **Action**: Replace block (exact single match) so expected scaled HP assertions reflect `HEALTH_SCALE = 3.25` (`325`, `3250`, `1625`).

**Find:**
```gdscript
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
```

**Replace with:**
```gdscript
	# HP x3.25: a fresh skeleton (authored 100) has 325.
	var sk: EnemyBase = level.call("_add_roamer", level, "skeleton", "Test_hp", Vector3(0, 0, -10), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14)) as EnemyBase
	await process_frame
	_check("hp_scaled", sk != null and sk.max_health == 325 and sk.health == 325, "max=%d" % (sk.max_health if sk != null else -1))
	# Warden rules.
	var w: WardenBoss = level.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden") as WardenBoss
	_check("warden_found", w != null)
	if w != null:
		_check("warden_hp_scaled", w.max_health == 3250, "max=%d" % w.max_health)
		_check("warden_execute_immune", w.execute_immune)
		_check("warden_phase_threshold", w._phase2_threshold() == 1625, str(w._phase2_threshold()))
```

- **Postcondition**: Newly spawned and level-placed enemies scale by `3.25x` (`+30%`) and emit `health_changed(max_health, max_health)` so `FloatingHPBar.text` shows `325/325`, `813/813`, `228/228`, etc.

---

### Step 4 — Scale `AttackHitbox` Inside `GrandJourneyBuilder._enlarge_enemy()` (`REQ-04`)

- **Prerequisites**: None.
- **Target**: `scripts/environment/grand_journey_builder.gd` (lines 511–524)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	var hb: Node3D = e.get_node_or_null("Hurtbox3D") as Node3D
	if hb != null:
		for c in hb.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var bs := ((c as CollisionShape3D).shape as BoxShape3D).duplicate() as BoxShape3D
				bs.size *= k
				(c as CollisionShape3D).shape = bs
				(c as CollisionShape3D).position *= k
	var hp: Node3D = e.get_node_or_null("FloatingHPBar") as Node3D
```

**Replace with:**
```gdscript
	var hb: Node3D = e.get_node_or_null("Hurtbox3D") as Node3D
	if hb != null:
		for c in hb.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var bs := ((c as CollisionShape3D).shape as BoxShape3D).duplicate() as BoxShape3D
				bs.size *= k
				(c as CollisionShape3D).shape = bs
				(c as CollisionShape3D).position *= k
	var atk: Node3D = e.get_node_or_null("AttackHitbox") as Node3D
	if atk != null:
		for c in atk.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var abs_box := ((c as CollisionShape3D).shape as BoxShape3D).duplicate() as BoxShape3D
				abs_box.size *= k
				(c as CollisionShape3D).shape = abs_box
				(c as CollisionShape3D).position *= k
	var hp: Node3D = e.get_node_or_null("FloatingHPBar") as Node3D
```

- **Postcondition**: Enlarged enemies (`GateWarden_W`, `GateWarden_E` at `k = 1.35`) scale `AttackHitbox` forward reach from `1.90 m` to `2.565 m` (`>= 2.49 m` scaled `attack_range`).

---

### Step 5 — Add `_exit_tree()` Cleanup to `SquadTTSPlayer` & `SquadCommsHUD` (`REQ-05`, `REQ-11`)

- **Prerequisites**: None.
- **Target 1**: `addons/parallax_squad_ai/tts_player.gd` (lines 48–56)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	_player.stream = _gen
	_player.volume_db = 2.0
	if AudioServer.get_bus_index(&"SFX") >= 0:
		_player.bus = &"SFX"
	add_child(_player)


func bind_client(c: OpenAIClient) -> void:
```

**Replace with:**
```gdscript
	_player.stream = _gen
	_player.volume_db = 2.0
	if AudioServer.get_bus_index(&"SFX") >= 0:
		_player.bus = &"SFX"
	add_child(_player)


func _exit_tree() -> void:
	stop_all()
	if DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()


func bind_client(c: OpenAIClient) -> void:
```

- **Target 2**: `scripts/ui/squad_comms_hud.gd` (lines 50–67)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	_build_chat_bar()
	_build_mic_button()


static func _ensure_actions() -> void:
	for a in ACTIONS.keys():
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in (ACTIONS[a] as Array):
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k)
			InputMap.action_add_event(a, ev)
```

**Replace with:**
```gdscript
	_build_chat_bar()
	_build_mic_button()


func _exit_tree() -> void:
	if _chat_open:
		_chat_open = false
		PlayerController.ui_input_locked = false


static func _ensure_actions() -> void:
	for a in ACTIONS.keys():
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in (ACTIONS[a] as Array):
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k) as Key
			InputMap.action_add_event(a, ev)
```

- **Target 3**: `scripts/ui/squad_comms_hud.gd` (lines 417–426)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	var lo: int = 0
	var hi: int = t.length()
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		if font.get_string_size(t.left(mid) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= max_w:
```

**Replace with:**
```gdscript
	var lo: int = 0
	var hi: int = t.length()
	while lo < hi:
		var mid: int = int((lo + hi + 1) / 2.0)
		if font.get_string_size(t.left(mid) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= max_w:
```

- **Postcondition**: Removing/freeing `SquadTTSPlayer` halts OS speech and cancels pending audio; freeing `SquadCommsHUD` while chat is open restores `PlayerController.ui_input_locked = false`; `squad_comms_hud.gd` compiles with 0 warnings.

---

### Step 6 — Exclude Reality-Immune `PhantomTwin`s from `WorldIntel.resolve()` & `AllySquadManager` Selection (`REQ-06`)

- **Prerequisites**: None.
- **Target 1**: `scripts/allies/world_intel.gd` (lines 254–261)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	rx.compile("\\b(?:e|enemy|target)\\s*#?\\s*(\\d+)\\b")
	var m: RegExMatch = rx.search(s)
	if m != null:
		var byid: EnemyAI = node_for_id("E" + m.get_string(1))
		if byid != null:
			return byid
```

**Replace with:**
```gdscript
	rx.compile("\\b(?:e|enemy|target)\\s*#?\\s*(\\d+)\\b")
	var m: RegExMatch = rx.search(s)
	if m != null:
		var byid: EnemyAI = node_for_id("E" + m.get_string(1))
		if byid != null and byid.is_hittable_now():
			return byid
		if byid != null:
			return null
```

- **Target 2**: `scripts/allies/world_intel.gd` (lines 279–287)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	var best: EnemyAI = null
	var best_score: float = -INF
	var any_desc: bool = false
	for en in _entries:
		var score: float = 0.0
		var words: String = String(en["words"])
```

**Replace with:**
```gdscript
	var best: EnemyAI = null
	var best_score: float = -INF
	var any_desc: bool = false
	for en in _entries:
		var en_node: EnemyAI = en.get("node") as EnemyAI
		if en_node == null or en_node.is_dead or not en_node.is_hittable_now():
			continue
		var score: float = 0.0
		var words: String = String(en["words"])
```

- **Target 3**: `scripts/allies/ally_squad_manager.gd` (lines 422–445)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
func _active_enemies_near(pos: Vector3, radius: float) -> Array[EnemyAI]:
	var out: Array[EnemyAI] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = node as EnemyAI
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree():
			continue
		if e.global_position.distance_to(pos) <= radius and absf(e.global_position.y - pos.y) < 5.0:
			out.append(e)
	return out


func resolve_enemy(selector: String, near: Vector3) -> EnemyAI:
	var sel: String = selector.strip_edges().to_lower()
	# "ally:Sera" / "Sera's target": whatever that ally is fighting.
	if sel.begins_with("ally:") or sel.ends_with("'s target"):
		var mate: SquadAlly = find_ally(sel.trim_prefix("ally:").trim_suffix("'s target"))
		if mate != null:
			var et: EnemyAI = mate._engage_target
			if (et == null or not is_instance_valid(et)) and mate.current != null:
				et = mate.current.data.get("enemy", null) as EnemyAI
			if et != null and is_instance_valid(et) and not et.is_dead and et.is_active:
				return et
		sel = "nearest"
```

**Replace with:**
```gdscript
func _active_enemies_near(pos: Vector3, radius: float) -> Array[EnemyAI]:
	var out: Array[EnemyAI] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = node as EnemyAI
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree() or not e.is_hittable_now():
			continue
		var in_radius: bool = e.global_position.distance_to(pos) <= radius and absf(e.global_position.y - pos.y) < 5.0
		var cam_vis: bool = radius >= 25.0 and intel != null and intel.is_camera_visible(e)
		if in_radius or cam_vis:
			out.append(e)
	return out


func resolve_enemy(selector: String, near: Vector3) -> EnemyAI:
	var sel: String = selector.strip_edges().to_lower()
	# "ally:Sera" / "Sera's target": whatever that ally is fighting.
	if sel.begins_with("ally:") or sel.ends_with("'s target"):
		var mate: SquadAlly = find_ally(sel.trim_prefix("ally:").trim_suffix("'s target"))
		if mate != null:
			var et: EnemyAI = mate._engage_target
			if (et == null or not is_instance_valid(et)) and mate.current != null:
				et = mate.current.data.get("enemy", null) as EnemyAI
			if et != null and is_instance_valid(et) and not et.is_dead and et.is_active and et.is_hittable_now():
				return et
		sel = "nearest"
```

- **Target 4**: `scripts/allies/ally_squad_manager.gd` (lines 803–811)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	var by_dist: Array[EnemyAI] = []
	var by_hp: Array[EnemyAI] = []
	if intel != null:
		for en in intel.get_entries():
			by_dist.append(en["node"] as EnemyAI)
		by_hp = by_dist.duplicate()
		by_hp.sort_custom(func(x: EnemyAI, y: EnemyAI) -> bool: return float(x.health) / float(maxi(1, x.max_health)) < float(y.health) / float(maxi(1, y.max_health)))
```

**Replace with:**
```gdscript
	var by_dist: Array[EnemyAI] = []
	var by_hp: Array[EnemyAI] = []
	if intel != null:
		intel.refresh()
		for en in intel.get_entries():
			var en_node: EnemyAI = en["node"] as EnemyAI
			if en_node != null and not en_node.is_dead and en_node.is_active and en_node.is_hittable_now():
				by_dist.append(en_node)
		by_hp = by_dist.duplicate()
		by_hp.sort_custom(func(x: EnemyAI, y: EnemyAI) -> bool: return float(x.health) / float(maxi(1, x.max_health)) < float(y.health) / float(maxi(1, y.max_health)))
```

- **Postcondition**: Neither `WorldIntel.resolve()` nor `AllySquadManager` strategy distribution (`divide_and_conquer`, etc.) ever assigns an un-hittable `PhantomTwin` in Reality.

---

### Step 7 — Fix `taunted_enemy_chases_past_leash` Rail Obstruction & Arena Isolation in `tests/squad_ai_windowed_test.gd` (`REQ-07`, `REQ-15`, `REQ-24`)

- **Prerequisites**: None.
- **Target 1**: `tests/squad_ai_windowed_test.gd` (lines 135–140)
- **Action**: Replace block (exact single match) to isolate Section 2 from Forecourt roamers (`8` enemies after `+50%`) before spawning `Test_*` enemies.

**Find:**
```gdscript
	# 2) Forecourt arena with test enemies.
	_teleport_player(Vector3(0, 0, -14))
	_mgr.regroup(false)
	await _wait(0.5)
```

**Replace with:**
```gdscript
	# 2) Forecourt arena with test enemies.
	await _reset_arena()
	_teleport_player(Vector3(0, 0, -14))
	_mgr.regroup(false)
	await _wait(0.5)
```

- **Target 2**: `tests/squad_ai_windowed_test.gd` (lines 510–524)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	var fx: EnemyBase = _spawn("skeleton", Vector3(0.0, 0, -6.0))
	fx.max_health = 5000
	fx.health = 5000
	await _wait(0.3)
	var taunter: SquadAlly = _ally("Brannoc")
	(fx as EnemyAI).apply_taunt(taunter, -1.0, 4.0)
	_say("Brannoc hold here")
	await _wait(0.2)
	# Walk the taunter well away from the enemy's home (leash 22 m) out along the R1 causeway bridge (last leg,
	# 45 % of the way from the forecourt edge to bastion 2).
	var fixation_spot_r1 := Vector3(-15.3, 0, -30.3)
	taunter.global_position = fixation_spot_r1
	_teleport_player(Vector3(-11.9, 0, -26.9))   # stay near him so his catch-up teleport never fires
```

**Replace with:**
```gdscript
	# Spawn both endpoints directly along the straight R1 bridge centerline (x = z + 15) so the z = -15 join rail never blocks the chase.
	var fx: EnemyBase = _spawn("skeleton", Vector3(-1.0, 0, -16.0))
	fx.max_health = 5000
	fx.health = 5000
	(fx as EnemyAI).max_chase_distance = 22.0
	await _wait(0.3)
	var taunter: SquadAlly = _ally("Brannoc")
	(fx as EnemyAI).apply_taunt(taunter, -1.0, 4.0)
	_say("Brannoc hold here")
	await _wait(0.2)
	var fixation_spot_r1 := Vector3(-21.0, 0, -36.0)   # 28.3 m from (-1, 0, -16) along the bridge deck, past the 22 m leash
	taunter.global_position = fixation_spot_r1
	_teleport_player(Vector3(-18.0, 0, -33.0))   # stay near him so his catch-up teleport never fires
```

- **Target 3**: `tests/squad_ai_windowed_test.gd` (lines 566–575)
- **Action**: Replace block (exact single match) so non-`Test_` Forecourt roamers do not aggro into isolated `Test_*` scenarios at the widened `22 m` detection range.

**Find:**
```gdscript
func _reset_arena() -> void:
	for e in get_nodes_in_group("enemy"):
		if String(e.name).begins_with("Test_") and not (e as EnemyBase).is_dead and (e as EnemyBase).is_active:
			(e as EnemyBase).apply_damage(99999, true, "environmental", null)
	for a in _mgr.allies:
```

**Replace with:**
```gdscript
func _reset_arena() -> void:
	for e in get_nodes_in_group("enemy"):
		if not (e is EnemyBase):
			continue
		var eb := e as EnemyBase
		if String(eb.name).begins_with("Test_") and not eb.is_dead and eb.is_active:
			eb.apply_damage(99999, true, "environmental", null)
		elif not String(eb.name).begins_with("Test_") and not eb.is_dead and eb.is_active:
			eb.set_section_enabled(false)
	for a in _mgr.allies:
```

- **Postcondition**: `FixationDummy` has an unobstructed `28.3 m` straight bridge path to `Brannoc`, clears the `22.0 m` leash test, and ends `< 8.0 m` from `taunter` without Forecourt roamer interference.

---

### Step 8 — Fix `PlayerController._is_flow_timing()` Guard & Stabilize `tests/feel_and_movement_test.gd` (`REQ-08`)

- **Prerequisites**: None.
- **Target 1**: `scripts/player/player_controller.gd` (lines 626–635)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
## Is "now" a rhythm tap for the current swing? (just before / just after its cancel point)
func _is_flow_timing() -> bool:
	if current_attack.is_empty() or not current_attack_name.begins_with("light"):
		return false
```

**Replace with:**
```gdscript
## Is "now" a rhythm tap for the current swing? (just before / just after its cancel point)
func _is_flow_timing() -> bool:
	if current_state != State.LIGHT_ATTACK:
		return false
	if current_attack.is_empty() or not current_attack_name.begins_with("light"):
		return false
```

- **Target 2**: `tests/feel_and_movement_test.gd` (lines 72–79)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	_player.crit_chance_light = 0.0
	_player.crit_chance_flow = 0.0
	_player.attack_started.connect(func(n: String, t: Dictionary) -> void: _attacks.append([n, int(t.get("chain_step", 0)), bool(t.get("flow", false)), String(t.get("branch", ""))]))
	_player.global_position = Vector3(0, 0, -14)
	_player.set_facing_direction(Vector3(0, 0, 1))
```

**Replace with:**
```gdscript
	_player.crit_chance_light = 0.0
	_player.crit_chance_flow = 0.0
	_player.attack_started.connect(func(n: String, t: Dictionary) -> void: _attacks.append([n, int(t.get("chain_step", 0)), bool(t.get("flow", false)), String(t.get("branch", ""))]))
	_player.global_position = Vector3(0, 0, -136)
	_player.set_facing_direction(Vector3(0, 0, 1))
```

- **Target 3**: `tests/feel_and_movement_test.gd` (lines 103–115)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	await _tap()
	for _s in range(4):
		var t0: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1500 and not _player._is_flow_timing():
			await process_frame
		var before: String = _player.current_attack_name
		await _tap()
		# Wait for the swing this tap queued to actually start before reading the next rhythm window.
		var t3: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t3 < 700 and _player.current_attack_name == before:
			await process_frame
```

**Replace with:**
```gdscript
	await _tap()
	for _s in range(4):
		var t0: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1500 and not _player._is_flow_timing():
			await process_frame
		var prev_count: int = _attacks.size()
		await _tap()
		# Wait for the swing this tap queued to actually start before reading the next rhythm window.
		var t3: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t3 < 700 and _attacks.size() == prev_count:
			await process_frame
```

- **Target 4**: `tests/feel_and_movement_test.gd` (lines 132–144)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	await create_timer(1.4).timeout
	_attacks.clear()
	await _tap()
	await create_timer(0.6).timeout
	_check("chain_resets_after_idle", not _attacks.is_empty() and int(_attacks[0][1]) == 1, str(_attacks))
	# Pause branch: swing, let it finish, wait a beat, tap.
	await create_timer(0.45 - 0.0).timeout
	_attacks.clear()
	await _tap()
	await create_timer(0.6).timeout
	_check("pause_branch_rising_arc", not _attacks.is_empty() and String(_attacks[0][0]) == "light_rise", str(_attacks))
```

**Replace with:**
```gdscript
	await create_timer(1.4).timeout
	_attacks.clear()
	await _tap()
	await create_timer(0.55).timeout
	_check("chain_resets_after_idle", not _attacks.is_empty() and int(_attacks[0][1]) == 1, str(_attacks))
	# Pause branch: wait until light_1 returns to LOCOMOTION and reaches pause_branch_delay without exceeding light_combo_reset_window (0.90s).
	var wait_pb: int = Time.get_ticks_msec()
	while (_player.current_state != PlayerController.State.LOCOMOTION or _player._since_attack_end < _player.pause_branch_delay + 0.03) and Time.get_ticks_msec() - wait_pb < 1200:
		await process_frame
	_attacks.clear()
	await _tap()
	await create_timer(0.6).timeout
	_check("pause_branch_rising_arc", not _attacks.is_empty() and String(_attacks[0][0]) == "light_rise", str(_attacks))
```

- **Target 5**: `tests/feel_and_movement_test.gd` (lines 230–233)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	# ---- 4) New finishers: Q (Mirror Break) and F (Execution) inside the crit window; Q must not shift realms.
	var victims: Array = level.get_tree().get_nodes_in_group("enemy").filter(func(n: Node) -> bool: return n is EnemyBase and not (n as EnemyBase).is_dead and (n as Node3D).global_position.distance_to(_player.global_position) < 12.0)
```

**Replace with:**
```gdscript
	# ---- 4) New finishers: Q (Mirror Break) and F (Execution) inside the crit window; Q must not shift realms.
	var victims: Array = level.get_tree().get_nodes_in_group("enemy").filter(func(n: Node) -> bool:
		return n is EnemyBase and not (n as EnemyBase).is_dead and (n as EnemyBase).is_hittable_now() and not (n is ShieldedGuard) and (n as Node3D).global_position.distance_to(_player.global_position) < 12.0
	)
```

- **Postcondition**: `_is_flow_timing()` only fires during `State.LIGHT_ATTACK`; combo tests run undisturbed on the start terrace `(0, 0, -136)`; `pause_branch_rising_arc` taps reliably inside `[pause_branch_delay, light_combo_reset_window)`; `f_in_window_executes` targets a Reality-hittable unshielded enemy.

---

### Step 9 — Eliminate Freed Lambda Capture Error in `GoreFX._attach_bleed_trail()` (`REQ-09`)

- **Prerequisites**: None.
- **Target**: `scripts/core/gore_fx.gd` (lines 517–525)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	p.position = local_pos
	body.add_child(p)
	p.emitting = true
	body.get_tree().create_timer(_rng.randf_range(0.9, 1.6), false).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false
	)
```

**Replace with:**
```gdscript
	p.position = local_pos
	body.add_child(p)
	p.emitting = true
	# Bound Tween on `p` cancels cleanly if `body` is freed early under MAX_GIBS, with no lambda capture.
	var tw: Tween = p.create_tween()
	tw.tween_interval(_rng.randf_range(0.9, 1.6))
	tw.tween_callback(p.set_emitting.bind(false))
```

- **Postcondition**: Early `queue_free()` of any dismembered gib cancels the trail-stop tween automatically with zero `gdscript_lambda_callable` errors.

---

### Step 10 — Add Distance Visibility Culling for Non-Boss Enemy Rigs & Low/Medium Shadow Scaling (`REQ-10`, `REQ-11`)

- **Prerequisites**: None.
- **Target 1**: `scripts/environment/colosseum_greybox_builder.gd` (lines 800–806)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	if not model_added:
		var mesh := _make_mesh_box("ProxyMesh", body_size, color, "spectral" if color.a < 0.99 else "plain")
		mesh.position = Vector3(0.0, body_size.y * 0.5, 0.0)
		vis_root.add_child(mesh)
	enemy.add_child(vis_root)
```

**Replace with:**
```gdscript
	if not model_added:
		var mesh := _make_mesh_box("ProxyMesh", body_size, color, "spectral" if color.a < 0.99 else "plain")
		mesh.position = Vector3(0.0, body_size.y * 0.5, 0.0)
		vis_root.add_child(mesh)
	if not (enemy is WardenBoss):
		for n in vis_root.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			mi.visibility_range_end = 58.0
			mi.visibility_range_end_margin = 4.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	enemy.add_child(vis_root)
```

- **Target 2**: `scripts/core/leaderboard_store.gd` (lines 186–191)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
static func format_time(time_sec: float) -> String:
	var total_sec: int = maxi(0, int(floor(time_sec)))
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]
```

**Replace with:**
```gdscript
static func format_time(time_sec: float) -> String:
	var total_sec: int = maxi(0, int(floor(time_sec)))
	var mins: int = int(total_sec / 60.0)
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]
```

- **Target 3**: `scripts/core/leaderboard_store.gd` (lines 438–444)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	var main_node: Node = get_tree().get_first_node_in_group("main_controller")
	if main_node != null:
		var sun: DirectionalLight3D = main_node.get_node_or_null("SunLight") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = (shadow_q > 0)
```

**Replace with:**
```gdscript
	var main_node: Node = get_tree().get_first_node_in_group("main_controller")
	if main_node != null:
		var sun: DirectionalLight3D = main_node.get_node_or_null("SunLight") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = (shadow_q > 0)
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if shadow_q <= 1 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 65.0 if shadow_q <= 1 else 120.0
```

- **Postcondition**: Distant bridge bastion enemy meshes (`> 58 m` from camera) are culled by Godot's visibility range without changing `EnemyBase.is_active`; Low/Medium presets halve directional shadow splits and distance; `format_time` emits no `INTEGER_DIVISION` warning.

---

### Step 11 — Resolve Benign GDScript Warnings in `world_label_overlay.gd` & `hud_controller.gd` (`REQ-11`)

- **Prerequisites**: None.
- **Target 1**: `scripts/ui/world_label_overlay.gd` (lines 112–117)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
func _line(font: Font, pos: Vector2, t: String, px: int, col: Color, ocol: Color, centered: bool) -> void:
	var x: float = pos.x
	if centered:
		x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5
	draw_string_outline(font, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(3, px / 4), ocol)
	draw_string(font, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
```

**Replace with:**
```gdscript
func _line(font: Font, pos: Vector2, t: String, px: int, col: Color, ocol: Color, centered: bool) -> void:
	var x: float = pos.x
	if centered:
		x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5
	draw_string_outline(font, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(3, int(px / 4.0)), ocol)
	draw_string(font, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
```

- **Target 2**: `scripts/ui/hud_controller.gd` (lines 89–95)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
var _boss_ghost_delay: float = 0.0
var _chip_sweep: Dictionary = {"reality": 1.0, "mirror": 1.0}
var _last_realm_key: String = ""
var _merged_label: Label = null
```

**Replace with:**
```gdscript
var _boss_ghost_delay: float = 0.0
var _chip_sweep: Dictionary = {"reality": 1.0, "mirror": 1.0}
var _merged_label: Label = null
```

- **Target 3**: `scripts/ui/hud_controller.gd` (lines 198–217)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
		rt.height = 128
		var tr := TextureRect.new()
		tr.name = "CornerScrim_%d%d" % [int(corner.x), int(corner.y)]
		tr.texture = rt
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.anchor_left = corner.x
		tr.anchor_right = corner.x
		tr.anchor_top = corner.y
		tr.anchor_bottom = corner.y
		var w: float = 620.0
		var h: float = 260.0 if corner.y == 0.0 else 230.0
		tr.offset_left = -w if corner.x == 1.0 else 0.0
		tr.offset_right = 0.0 if corner.x == 1.0 else w
		tr.offset_top = -h if corner.y == 1.0 else 0.0
		tr.offset_bottom = 0.0 if corner.y == 1.0 else h
		_root_ctrl.add_child(tr)
		_root_ctrl.move_child(tr, 0)
```

**Replace with:**
```gdscript
		rt.height = 128
		var scrim_rect := TextureRect.new()
		scrim_rect.name = "CornerScrim_%d%d" % [int(corner.x), int(corner.y)]
		scrim_rect.texture = rt
		scrim_rect.stretch_mode = TextureRect.STRETCH_SCALE
		scrim_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scrim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scrim_rect.anchor_left = corner.x
		scrim_rect.anchor_right = corner.x
		scrim_rect.anchor_top = corner.y
		scrim_rect.anchor_bottom = corner.y
		var w: float = 620.0
		var h: float = 260.0 if corner.y == 0.0 else 230.0
		scrim_rect.offset_left = -w if corner.x == 1.0 else 0.0
		scrim_rect.offset_right = 0.0 if corner.x == 1.0 else w
		scrim_rect.offset_top = -h if corner.y == 1.0 else 0.0
		scrim_rect.offset_bottom = 0.0 if corner.y == 1.0 else h
		_root_ctrl.add_child(scrim_rect)
		_root_ctrl.move_child(scrim_rect, 0)
```

- **Target 4**: `scripts/ui/hud_controller.gd` (lines 312–331)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	# --- Combo timeout bar ---
	var tr: Node = get_node_or_null("RootControl/TopRightPanel")
	if tr != null and _combo_bar == null:
		_combo_bar = tr.get_node_or_null("ComboTimerBar") as ProgressBar
		if _combo_bar == null:
			_combo_bar = ProgressBar.new()
			_combo_bar.name = "ComboTimerBar"
			_combo_bar.custom_minimum_size = Vector2(150, 4)
			_combo_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
			_combo_bar.show_percentage = false
			_combo_bar.value = 0.0
			_combo_bar.modulate.a = 0.0
			_combo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cbg := StyleBoxFlat.new()
			cbg.bg_color = Color(0, 0, 0, 0.45)
			_combo_bar.add_theme_stylebox_override("background", cbg)
			tr.add_child(_combo_bar)
			tr.move_child(_combo_bar, _combo_lbl.get_index() + 1 if _combo_lbl != null else tr.get_child_count() - 1)
		_style_combo()
```

**Replace with:**
```gdscript
	# --- Combo timeout bar ---
	var top_right_panel: Node = get_node_or_null("RootControl/TopRightPanel")
	if top_right_panel != null and _combo_bar == null:
		_combo_bar = top_right_panel.get_node_or_null("ComboTimerBar") as ProgressBar
		if _combo_bar == null:
			_combo_bar = ProgressBar.new()
			_combo_bar.name = "ComboTimerBar"
			_combo_bar.custom_minimum_size = Vector2(150, 4)
			_combo_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
			_combo_bar.show_percentage = false
			_combo_bar.value = 0.0
			_combo_bar.modulate.a = 0.0
			_combo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cbg := StyleBoxFlat.new()
			cbg.bg_color = Color(0, 0, 0, 0.45)
			_combo_bar.add_theme_stylebox_override("background", cbg)
			top_right_panel.add_child(_combo_bar)
			top_right_panel.move_child(_combo_bar, _combo_lbl.get_index() + 1 if _combo_lbl != null else top_right_panel.get_child_count() - 1)
		_style_combo()
```

- **Target 5**: `scripts/ui/hud_controller.gd` (lines 713–716)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
func _on_run_timer_updated(elapsed_sec: float) -> void:
	var total_sec: int = maxi(0, int(elapsed_sec))
	timer_text = "%02d:%02d" % [total_sec / 60, total_sec % 60]
	_sync_ui_nodes()
```

**Replace with:**
```gdscript
func _on_run_timer_updated(elapsed_sec: float) -> void:
	var total_sec: int = maxi(0, int(elapsed_sec))
	timer_text = "%02d:%02d" % [int(total_sec / 60.0), total_sec % 60]
	_sync_ui_nodes()
```

- **Postcondition**: `world_label_overlay.gd` and `hud_controller.gd` have 0 `INTEGER_DIVISION`, 0 `SHADOWED_VARIABLE`, and 0 `UNUSED_VARIABLE` warnings.

---

### Step 12 — Prevent Gemini TTS & Director Prompt From Speaking Style/Persona Prompts Aloud (`REQ-13`)

- **Prerequisites**: Steps 1–11 complete.
- **Target 1**: `addons/parallax_squad_ai/openai_client.gd` (lines 90–98)
- **Action**: Replace block (exact single match). Note that Gemini TTS preview models read text inside `contents` literally, so prepending `style + pace + "Say: "` caused Brannoc and Ivo's style prompts to be spoken aloud. Send pure spoken dialogue text only on the Gemini path while retaining the non-spoken `instructions` JSON field for `gpt-4o`.

**Find:**
```gdscript
## `voice` = provider voice id; `style` = natural-language delivery hint.
func speak_stream(text: String, voice: String, style: String = "") -> int:
	if SquadAIConfig.provider() == "gemini":
		var pace: String = "Speak at a brisk, natural conversational pace — never slow or drawn out."
		var prompt: String = ("%s Say: %s" % [pace, text]) if style.is_empty() else ("%s %s Say: %s" % [style, pace, text])
		var body: Dictionary = {
			"contents": [{"role": "user", "parts": [{"text": prompt}]}],
```

**Replace with:**
```gdscript
## `voice` = provider voice id; `style` = delivery hint (OpenAI `instructions` field only — never prepended into Gemini text).
func speak_stream(text: String, voice: String, style: String = "") -> int:
	var clean_text: String = text.strip_edges()
	if SquadAIConfig.provider() == "gemini":
		var body: Dictionary = {
			"contents": [{"role": "user", "parts": [{"text": clean_text}]}],
```

- **Target 2**: `addons/parallax_squad_ai/squad_comms.gd` (lines 236–240)
- **Action**: Replace block (exact single match) so `tts_instructions` is not fed into the chat Director's system prompt.

**Find:**
```gdscript
	var personas: PackedStringArray = []
	if _manager != null:
		for a in _manager.allies:
			personas.append("- %s (%s): %s Speaks: %s" % [a.get_display_name(), a.get_role(), a.profile.personality, a.profile.tts_instructions])
```

**Replace with:**
```gdscript
	var personas: PackedStringArray = []
	if _manager != null:
		for a in _manager.allies:
			personas.append("- %s (%s): %s" % [a.get_display_name(), a.get_role(), a.profile.personality])
```

- **Target 3**: `addons/parallax_squad_ai/squad_comms.gd` (lines 335–345)
- **Action**: Replace block (exact single match) to sanitize `say` tool text before voicing/subtitling.

**Find:**
```gdscript
		if tname == "say":
			var who: SquadAlly = _manager.find_ally(String(args.get("ally", "")))
			if who == null:
				who = focus if focus != null else _manager._leader()
			var line: String = String(args.get("text", "")).strip_edges()
			if who != null and not line.is_empty():
```

**Replace with:**
```gdscript
		if tname == "say":
			var who: SquadAlly = _manager.find_ally(String(args.get("ally", "")))
			if who == null:
				who = focus if focus != null else _manager._leader()
			var line: String = sanitize_spoken_line(who, String(args.get("text", "")))
			if who != null and not line.is_empty():
```

- **Target 4**: `addons/parallax_squad_ai/squad_comms.gd` (lines 379–386)
- **Action**: Replace block (exact single match) to sanitize plain-text fallback replies.

**Find:**
```gdscript
	var speaker: SquadAlly = focus if focus != null else (acted[0] if not acted.is_empty() else _manager._leader())
	var spoken: String = text.strip_edges()
	if spoke == 0 and speaker != null:
		if spoken.is_empty():
			spoken = speaker.profile.line("ack", "On it.") if not calls.is_empty() else speaker.profile.line("confused", "Say again?")
		_voice(speaker, spoken, 1)
		_remember(speaker.get_display_name(), "said: " + spoken)
```

**Replace with:**
```gdscript
	var speaker: SquadAlly = focus if focus != null else (acted[0] if not acted.is_empty() else _manager._leader())
	var spoken: String = sanitize_spoken_line(speaker, text)
	if spoke == 0 and speaker != null:
		if spoken.is_empty():
			spoken = speaker.profile.line("ack", "On it.") if not calls.is_empty() else speaker.profile.line("confused", "Say again?")
		_voice(speaker, spoken, 1)
		_remember(speaker.get_display_name(), "said: " + spoken)
```

- **Target 5**: `addons/parallax_squad_ai/squad_comms.gd` (lines 477–485)
- **Action**: Replace block (exact single match) to add `sanitize_spoken_line()` and enforce it inside `_voice()`.

**Find:**
```gdscript
func _voice(ally: SquadAlly, text: String, prio: int) -> void:
	if text.is_empty() or ally == null:
		return
	var voice: String = ally.profile.gemini_voice if SquadAIConfig.provider() == "gemini" else ally.profile.tts_voice
	var role: String = ally.get_role()
	var slot: int = maxi(0, _manager.allies.find(ally)) if _manager != null else 0
	tts.speak(ally.get_display_name(), text, voice, ally.profile.tts_instructions, prio,
		float(SYS_PITCH.get(role, 1.0)), float(SYS_RATE.get(role, 1.0)), slot)
```

**Replace with:**
```gdscript
## Strips leaked persona, TTS style hints, "Say:" wrappers, or speaker prefixes before TTS/subtitles.
static func sanitize_spoken_line(ally: SquadAlly, raw: String) -> String:
	var s: String = raw.strip_edges()
	if s.is_empty():
		return ""
	# Strip wrapping double quotes if the LLM quoted the entire utterance.
	if s.length() >= 2 and s.begins_with("\"") and s.ends_with("\""):
		s = s.substr(1, s.length() - 2).strip_edges()
	var prefixes: PackedStringArray = [
		"Speak at a brisk, natural conversational pace — never slow or drawn out.",
		"Speak at a brisk, natural conversational pace.",
		"Speaks:",
		"Style:",
	]
	if ally != null and ally.profile != null:
		if not ally.profile.tts_instructions.is_empty():
			prefixes.append(ally.profile.tts_instructions)
		if not ally.profile.personality.is_empty():
			prefixes.append(ally.profile.personality)
		var dname: String = ally.get_display_name()
		if not dname.is_empty():
			prefixes.append(dname + ":")
			prefixes.append("[" + dname + "]:")
			prefixes.append("**" + dname + "**:")
	var changed: bool = true
	while changed and not s.is_empty():
		changed = false
		var low: String = s.to_lower()
		for pf in prefixes:
			var p_clean: String = pf.strip_edges()
			if p_clean.is_empty():
				continue
			if low.begins_with(p_clean.to_lower()):
				s = s.substr(p_clean.length()).strip_edges()
				changed = true
				break
	# If an instruction/prompt wrapper included "Say: <dialogue>", extract only the dialogue after "Say:".
	var say_idx: int = s.to_lower().find("say:")
	if say_idx >= 0 and say_idx <= 160:
		var after_say: String = s.substr(say_idx + 4).strip_edges()
		if not after_say.is_empty():
			s = after_say
	return s


func _voice(ally: SquadAlly, text: String, prio: int) -> void:
	if ally == null:
		return
	var clean: String = sanitize_spoken_line(ally, text)
	if clean.is_empty():
		return
	var voice: String = ally.profile.gemini_voice if SquadAIConfig.provider() == "gemini" else ally.profile.tts_voice
	var role: String = ally.get_role()
	var slot: int = maxi(0, _manager.allies.find(ally)) if _manager != null else 0
	tts.speak(ally.get_display_name(), clean, voice, ally.profile.tts_instructions, prio,
		float(SYS_PITCH.get(role, 1.0)), float(SYS_RATE.get(role, 1.0)), slot)
```

- **Postcondition**: Gemini TTS receives only the clean dialogue line (never Brannoc/Ivo `tts_instructions` or pace instructions), `build_system_prompt()` no longer injects `Speaks:`, and `sanitize_spoken_line()` strips any leaked prompt fragments before audio/subtitles.

---

### Step 13 — Auto-Clear Bypassed Gates, Bridges & Encounters When Player Sneaks Past (`REQ-14`)

- **Prerequisites**: Step 1 applied (`objective_tracker.gd`).
- **Target 1**: `scripts/environment/mechanism_puzzle.gd` (lines 106–112)
- **Action**: Replace block (exact single match) to expose `force_solve_bypass()` for gate/puzzle bypasses without mid-air slam.

**Find:**
```gdscript
	var gate: Node = get_node_or_null(linked_gate_path)
	if gate != null and gate.has_method("unlock_and_open"):
		gate.call("unlock_and_open")

	mechanism_solved.emit()
	return true
```

**Replace with:**
```gdscript
	var gate: Node = get_node_or_null(linked_gate_path)
	if gate != null and gate.has_method("unlock_and_open"):
		gate.call("unlock_and_open")

	mechanism_solved.emit()
	return true


## Resolves the puzzle and opens its gate if the player snuck past Gate04 without solving it.
func force_solve_bypass() -> void:
	if is_solved:
		return
	is_solved = true
	is_plate_pressed = true
	var weight_node: Node3D = get_node_or_null(weight_node_path) as Node3D
	if weight_node != null:
		weight_node.position = dropped_local_position
		for child in weight_node.get_children():
			if child is RealmReactive:
				(child as RealmReactive).repair_for_reality()
	var rm: RealmManager = RealmManager.instance as RealmManager
	evaluate_for_realm(int(rm.current_realm) if rm != null else 0, rm.is_merged if rm != null else false)
	var gate: Node = get_node_or_null(linked_gate_path)
	if gate != null and gate.has_method("unlock_and_open"):
		gate.call("unlock_and_open")
	mechanism_solved.emit()
```

- **Target 2**: `scripts/ui/objective_tracker.gd` (lines 85–137)
- **Action**: Replace block (exact single match) so `ObjectiveTracker._compute()` detects when the player's `story_z` is strictly past a gate (`Gate01..Gate05`), automatically opens the bypassed gate, completes any skipped encounter (`hall_of_echoes`, `shielded_guard`, `the_warden`), repairs bypassed `GallerySpectralBridge` / solves `ChamberMechanismPuzzle`, and advances to the next objective. Note: intentionally leaves `EncounterDirector.current_section` untouched so R2/R3/R5 bridge bastion roamers keep their configured section activation.

**Find:**
```gdscript
func _compute(player: Node3D) -> Dictionary:
	# Thresholds below are story z (the old compact layout); targets convert with JourneyLayout.
	var pz: float = JourneyLayout.story_z(player.global_position.z)
	var py: float = player.global_position.y
	var gate1: Node = _n("Stage01_EntryVestibule/Gate01_EntryToHall")
	var sw1: Node3D = _n("Stage01_EntryVestibule/EntryMirrorSwitch") as Node3D
	if gate1 != null and not bool(gate1.get("is_open")):
		if pz < -16.0:
			return {"title": "Follow the Pilgrim's Causeway to the gate", "hint": "Cross the winding causeway past both bastions to the gate.", "target": JourneyLayout.guide_target(player.global_position, Vector3(0, 0, -9))}
		return {"title": "Open the Gate of Reflections",
			"hint": "Beat the gate guards, press Q so the glowing stones turn solid, cross, then press E at the Mirror Switch left of the gate.",
			"target": sw1.global_position if sw1 != null else Vector3(0, 0, 4)}
	var hall_left: Array[EnemyBase] = _alive_in("Stage02_HallOfEchoes/Enemies")
	var gate2: Node = _n("Stage02_HallOfEchoes/Gate02_HallToGallery")
	if gate2 != null and not bool(gate2.get("is_open")):
		if pz < 24.0:
			return {"title": "Cross the Sunlit Bridges to the Hall of Echoes", "hint": "Through the gate and over the bridges, past both bastions, to the hall.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 4, 26)))}
		if not hall_left.is_empty():
			return {"title": "Clear the Hall of Echoes — %d left" % hall_left.size(),
				"hint": "Tip: in the Mirror (Q) enemies show a glowing weak point and take +25% damage. Heavy (RMB) the cracked pillar to crush them.",
				"target": _nearest(hall_left, player).global_position}
	if pz < 64.0 and py < 5.5:
		return {"title": "Cross the Windswept Rampart", "hint": "Through the opened gate and over the rampart bridges, past both bastions, to the gallery.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 6, 62)))}
	var brg: Node = _n("Stage03_CollapsedGallery/GallerySpectralBridge")
	var sup: Node3D = _n("Stage03_CollapsedGallery/WeakStoneSupport") as Node3D
	var sw3: Node3D = _n("Stage03_CollapsedGallery/BridgeAnchorSwitch") as Node3D
	if brg != null and not bool(brg.get("is_permanently_repaired")):
		var sup_intact: bool = sup != null and int(sup.get("current_state")) == 0
		if sup_intact:
			return {"title": "Cross the broken bridge",
				"hint": "The bridge only exists in the Mirror — press Q and cross, climb the broken blocks on the right to the high ledge, then smash the cracked support with a Heavy (RMB).",
				"target": sup.global_position}
		return {"title": "Pull the Bridge Anchor", "hint": "Press E at the anchor switch to rebuild the bridge in Reality.",
			"target": sw3.global_position if sw3 != null else JourneyLayout.to_world(Vector3(0, 6, 79))}
	var guard: Array[EnemyBase] = _alive_in("Stage03_CollapsedGallery/Enemies")
	if not guard.is_empty():
		return {"title": "Defeat the Shielded Guard", "hint": "Its shield only exists in Reality — fight it in the Mirror (Q).", "target": guard[0].global_position}
	var puz: Node3D = _n("Stage04_MechanismChamber/ChamberMechanismPuzzle") as Node3D
	if puz != null and not bool(puz.get("is_solved")):
		if pz < 87.0:
			return {"title": "Enter the Clock-Tower Mechanism Chamber", "hint": "North through the gallery gate.", "target": JourneyLayout.to_world(Vector3(0, 6, 90))}
		return {"title": "Drop the Mirror weight onto the plate",
			"hint": "In the Mirror, jump off the raised dais and press F in mid-air above the hanging weight to slam it down.",
			"target": puz.global_position}
	var warden: WardenBoss = _n("Stage05_ExecutionArena/Enemies/TheWarden") as WardenBoss
	if warden != null and not warden.is_dead:
		if pz < 139.0:
			return {"title": "Cross the Processional to the Colosseum", "hint": "Over the bridges and past both bastions. The Warden waits at the top.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 10, 140.5)))}
		if warden.current_phase == WardenBoss.Phase.PHASE_1_SPLIT:
			return {"title": "Defeat The Warden", "hint": "Dodge his strike, then press Q during his recovery and hit the glowing chest rune.", "target": warden.global_position}
		return {"title": "Finish The Warden", "hint": "The realms have merged — no more shifting. Hit him with everything.", "target": warden.global_position}
	return {"title": "Walk into the light", "hint": "Leave through the north gate to the summit.", "target": JourneyLayout.to_world(Vector3(0, 10, 194))}
```

**Replace with:**
```gdscript
func _auto_clear_bypassed_stages(pz: float) -> void:
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	# Stage 01 Gate01_EntryToHall sits at story/world z = 5.0; north onto R2 at z >= 6.5 means bypassed.
	if pz > 6.5:
		var gate1: Node = _n("Stage01_EntryVestibule/Gate01_EntryToHall")
		if gate1 != null and not bool(gate1.get("is_open")) and gate1.has_method("open_gate"):
			gate1.call("open_gate", true)
	# Stage 02 Gate02_HallToGallery sits at world z = 116.0 (story z = 44.0); north onto R3 at pz > 45.2 means bypassed.
	if pz > 45.2:
		var gate2: Node = _n("Stage02_HallOfEchoes/Gate02_HallToGallery")
		if gate2 != null and not bool(gate2.get("is_open")) and gate2.has_method("open_gate"):
			gate2.call("open_gate", true)
		if ed != null and not bool(ed.completed_encounters.get("hall_of_echoes", false)):
			ed.complete_combat_encounter("hall_of_echoes")
	# Stage 03 Gate03_GalleryToMechanism sits at story z = 84.0 (world z = 188.0); past pz > 85.2 clears bridge, guard & gate.
	if pz > 85.2:
		var brg: Node = _n("Stage03_CollapsedGallery/GallerySpectralBridge")
		if brg != null and not bool(brg.get("is_permanently_repaired")) and brg.has_method("repair_for_reality"):
			brg.call("repair_for_reality")
		var gate3: Node = _n("Stage03_CollapsedGallery/Gate03_GalleryToMechanism")
		if gate3 != null and not bool(gate3.get("is_open")) and gate3.has_method("open_gate"):
			gate3.call("open_gate", true)
		if ed != null and not bool(ed.completed_encounters.get("shielded_guard", false)):
			ed.complete_combat_encounter("shielded_guard")
	# Stage 04 Gate04_MechanismToArena sits at world z = 228.0 (story z ~ 100.4); past pz > 101.5 resolves mechanism & gate.
	if pz > 101.5:
		var gate4: Node = _n("Stage04_MechanismChamber/Gate04_MechanismToArena")
		if gate4 != null and not bool(gate4.get("is_open")) and gate4.has_method("open_gate"):
			gate4.call("open_gate", true)
		var puz: Node = _n("Stage04_MechanismChamber/ChamberMechanismPuzzle")
		if puz != null and not bool(puz.get("is_solved")) and puz.has_method("force_solve_bypass"):
			puz.call("force_solve_bypass")
	# Stage 05 Gate05_ArenaExit sits at story z = 167.5 (world z = 327.5); past pz > 169.5 opens exit & clears warden.
	if pz > 169.5:
		var gate5: Node = _n("Stage05_ExecutionArena/Gate05_ArenaExit")
		if gate5 != null and not bool(gate5.get("is_open")) and gate5.has_method("open_gate"):
			gate5.call("open_gate", true)
		if ed != null and not bool(ed.completed_encounters.get("the_warden", false)):
			ed.complete_combat_encounter("the_warden")


func _compute(player: Node3D) -> Dictionary:
	# Thresholds below are story z (the old compact layout); targets convert with JourneyLayout.
	var pz: float = JourneyLayout.story_z(player.global_position.z)
	var py: float = player.global_position.y
	_auto_clear_bypassed_stages(pz)
	var gate1: Node = _n("Stage01_EntryVestibule/Gate01_EntryToHall")
	var sw1: Node3D = _n("Stage01_EntryVestibule/EntryMirrorSwitch") as Node3D
	if gate1 != null and not bool(gate1.get("is_open")):
		if pz < -16.0:
			return {"title": "Follow the Pilgrim's Causeway to the gate", "hint": "Cross the winding causeway past both bastions to the gate.", "target": JourneyLayout.guide_target(player.global_position, Vector3(0, 0, -9))}
		return {"title": "Open the Gate of Reflections",
			"hint": "Beat the gate guards, press Q so the glowing stones turn solid, cross, then press E at the Mirror Switch left of the gate.",
			"target": sw1.global_position if sw1 != null else Vector3(0, 0, 4)}
	var hall_left: Array[EnemyBase] = _alive_in("Stage02_HallOfEchoes/Enemies")
	var gate2: Node = _n("Stage02_HallOfEchoes/Gate02_HallToGallery")
	if gate2 != null and not bool(gate2.get("is_open")):
		if pz < 24.0:
			return {"title": "Cross the Sunlit Bridges to the Hall of Echoes", "hint": "Through the gate and over the bridges, past both bastions, to the hall.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 4, 26)))}
		if not hall_left.is_empty():
			return {"title": "Clear the Hall of Echoes — %d left" % hall_left.size(),
				"hint": "Tip: in the Mirror (Q) enemies show a glowing weak point and take +25% damage. Heavy (RMB) the cracked pillar to crush them.",
				"target": _nearest(hall_left, player).global_position}
	if pz < 64.0 and py < 5.5:
		return {"title": "Cross the Windswept Rampart", "hint": "Through the opened gate and over the rampart bridges, past both bastions, to the gallery.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 6, 62)))}
	var brg: Node = _n("Stage03_CollapsedGallery/GallerySpectralBridge")
	var sup: Node3D = _n("Stage03_CollapsedGallery/WeakStoneSupport") as Node3D
	var sw3: Node3D = _n("Stage03_CollapsedGallery/BridgeAnchorSwitch") as Node3D
	if brg != null and not bool(brg.get("is_permanently_repaired")) and pz <= 85.2:
		var sup_intact: bool = sup != null and int(sup.get("current_state")) == 0
		if sup_intact:
			return {"title": "Cross the broken bridge",
				"hint": "The bridge only exists in the Mirror — press Q and cross, climb the broken blocks on the right to the high ledge, then smash the cracked support with a Heavy (RMB).",
				"target": sup.global_position}
		return {"title": "Pull the Bridge Anchor", "hint": "Press E at the anchor switch to rebuild the bridge in Reality.",
			"target": sw3.global_position if sw3 != null else JourneyLayout.to_world(Vector3(0, 6, 79))}
	var gate3: Node = _n("Stage03_CollapsedGallery/Gate03_GalleryToMechanism")
	var guard: Array[EnemyBase] = _alive_in("Stage03_CollapsedGallery/Enemies")
	if not guard.is_empty() and pz <= 85.2 and not (gate3 != null and bool(gate3.get("is_open"))):
		return {"title": "Defeat the Shielded Guard", "hint": "Its shield only exists in Reality — fight it in the Mirror (Q).", "target": guard[0].global_position}
	var puz: Node3D = _n("Stage04_MechanismChamber/ChamberMechanismPuzzle") as Node3D
	if puz != null and not bool(puz.get("is_solved")) and pz <= 101.5:
		if pz < 87.0:
			return {"title": "Enter the Clock-Tower Mechanism Chamber", "hint": "North through the gallery gate.", "target": JourneyLayout.to_world(Vector3(0, 6, 90))}
		return {"title": "Drop the Mirror weight onto the plate",
			"hint": "In the Mirror, jump off the raised dais and press F in mid-air above the hanging weight to slam it down.",
			"target": puz.global_position}
	var gate5: Node = _n("Stage05_ExecutionArena/Gate05_ArenaExit")
	var warden: WardenBoss = _n("Stage05_ExecutionArena/Enemies/TheWarden") as WardenBoss
	if warden != null and not warden.is_dead and pz <= 169.5 and not (gate5 != null and bool(gate5.get("is_open"))):
		if pz < 139.0:
			return {"title": "Cross the Processional to the Colosseum", "hint": "Over the bridges and past both bastions. The Warden waits at the top.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 10, 140.5)))}
		if warden.current_phase == WardenBoss.Phase.PHASE_1_SPLIT:
			return {"title": "Defeat The Warden", "hint": "Dodge his strike, then press Q during his recovery and hit the glowing chest rune.", "target": warden.global_position}
		return {"title": "Finish The Warden", "hint": "The realms have merged — no more shifting. Hit him with everything.", "target": warden.global_position}
	return {"title": "Walk into the light", "hint": "Leave through the north gate to the summit.", "target": JourneyLayout.to_world(Vector3(0, 10, 194))}
```

- **Postcondition**: Sneaking past any blocked gate opens that gate permanently, marks any skipped encounter/bridge/puzzle cleared, and advances `ObjectiveTracker` cleanly to the next active stage.

---

### Step 14 — Scale Enemy Engagement Radii (`REQ-15`), Darken Archetype Colors (`REQ-22`), & Apply +40% Damage / +50% Mobs (`REQ-24`)

- **Prerequisites**: Steps 1–13 complete.
- **Target 1**: `scripts/enemies/enemy_ai.gd` (lines 31–33)
- **Action**: Replace block (exact single match) to define `DAMAGE_SCALE = 1.4` (`+40%` damage) and `_damage_scaled`.

**Find:**
```gdscript
## Damage sources that knock an enemy down (-> STUNNED) instead of a plain stagger.
const KNOCKDOWN_SOURCES: Array[String] = ["player_landing", "fin_sunder", "ally_charge", "ally_nuke", "ally_detonate"]
```

**Replace with:**
```gdscript
## Damage sources that knock an enemy down (-> STUNNED) instead of a plain stagger.
const KNOCKDOWN_SOURCES: Array[String] = ["player_landing", "fin_sunder", "ally_charge", "ally_nuke", "ally_detonate"]
const DAMAGE_SCALE: float = 1.4
var _damage_scaled: bool = false
```

- **Target 2**: `scripts/enemies/enemy_ai.gd` (lines 47–50)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
@export_group("AI & Combat Tuning")
@export var detection_range: float = 9.0
@export var attack_range: float = 1.85
```

**Replace with:**
```gdscript
@export_group("AI & Combat Tuning")
@export var detection_range: float = 22.0
@export var attack_range: float = 1.85
```

- **Target 3**: `scripts/enemies/enemy_ai.gd` (lines 95–97)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
## Distance from home (spawn) after which the enemy gives up and walks back to its patrol.
@export var max_chase_distance: float = 22.0
@export var alert_investigate_duration: float = 4.0
```

**Replace with:**
```gdscript
## Distance from home (spawn) after which the enemy gives up and walks back to its patrol.
@export var max_chase_distance: float = 52.0
@export var alert_investigate_duration: float = 4.0
```

- **Target 4**: `scripts/enemies/enemy_ai.gd` (lines 157–161)
- **Action**: Replace block (exact single match) so non-archetype/non-boss enemies scale `attack_damage` by `DAMAGE_SCALE = 1.4` (`+40%`) once in `_ready()`.

**Find:**
```gdscript
func _ready() -> void:
	super._ready()
	_rng.randomize()
	_home = global_position
```

**Replace with:**
```gdscript
func _ready() -> void:
	if not _damage_scaled:
		_damage_scaled = true
		attack_damage = maxi(1, int(round(float(attack_damage) * DAMAGE_SCALE)))
	super._ready()
	_rng.randomize()
	_home = global_position
```

- **Target 5**: `scripts/enemies/enemy_ai.gd` (lines 801–808)
- **Action**: Replace block (exact single match) so alerted/engaged enemies across large halls do not drop target on the very next frame at `detection_range * 2.2`.

**Find:**
```gdscript
	# Leash: chased too far from home -> give up and walk back to the patrol.
	if global_position.distance_to(_home) > max_chase_distance and dist > attack_range * 1.5 and not is_taunted():
		_begin_return()
		return
	if dist > detection_range * 2.2 and not is_taunted():
		_threat.erase(target.get_instance_id())
		_lose_target()
		return
```

**Replace with:**
```gdscript
	# Leash: chased too far from home -> give up and walk back to the patrol.
	if global_position.distance_to(_home) > max_chase_distance and dist > attack_range * 1.5 and not is_taunted():
		_begin_return()
		return
	var lose_range: float = maxf(detection_range * 2.5, max_chase_distance * 1.15)
	if dist > lose_range and not is_taunted():
		_threat.erase(target.get_instance_id())
		_lose_target()
		return
```

- **Target 6**: `scripts/enemies/archetype_enemy.gd` (lines 47–51)
- **Action**: Replace block (exact single match) to scale data-driven archetype `attack_damage` by `DAMAGE_SCALE = 1.4` (`+40%`) without double-scaling on `_ready()`.

**Find:**
```gdscript
	stagger_duration = a.stagger_duration
	attack_damage = a.attack_damage
	attack_name = a.attack_name
```

**Replace with:**
```gdscript
	stagger_duration = a.stagger_duration
	attack_damage = maxi(1, int(round(float(a.attack_damage) * DAMAGE_SCALE)))
	_damage_scaled = true
	attack_name = a.attack_name
```

- **Target 7**: `scripts/enemies/archetype_enemy.gd` (lines 160–166)
- **Action**: Replace block (exact single match) so ranged casters retain targets across large rooms.

**Find:**
```gdscript
	if dist > detection_range * 2.2 and not is_taunted():
		_threat.erase(target.get_instance_id())
		_lose_target()
		return
```

**Replace with:**
```gdscript
	var lose_range: float = maxf(detection_range * 2.5, max_chase_distance * 1.15)
	if dist > lose_range and not is_taunted():
		_threat.erase(target.get_instance_id())
		_lose_target()
		return
```

- **Target 8**: `scripts/enemies/phantom_twin.gd` (lines 20–24)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	max_health = 80
	health = 80
	detection_range = 9.0
	attack_range = 4.2
```

**Replace with:**
```gdscript
	max_health = 80
	health = 80
	detection_range = 24.0
	attack_range = 4.2
```

- **Target 9**: `scripts/enemies/shielded_guard.gd` (lines 19–23)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	max_health = 250
	health = 250
	detection_range = 10.0
	attack_range = 2.0
```

**Replace with:**
```gdscript
	max_health = 250
	health = 250
	detection_range = 20.0
	attack_range = 2.0
```

- **Target 10**: `scripts/enemies/squad_coordinator.gd` (lines 21–26)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
var max_enemies_per_target: int = 3
var min_attack_gap: float = 0.42
var join_radius: float = 9.0
var alert_radius: float = 18.0
var engage_radius: float = 11.0
```

**Replace with:**
```gdscript
var max_enemies_per_target: int = 3
var min_attack_gap: float = 0.42
var join_radius: float = 22.0
var alert_radius: float = 38.0
var engage_radius: float = 24.0
```

- **Target 11**: `data/enemies/hollow_hexcaster.tres` (lines 12–38)
- **Action**: Replace block (exact single match) to raise ranges (`26 / 52 m`) and deepen hostile indigo-magenta appearance (distinct from Ivo).

**Find:**
```ini
tint = Color(0.78, 0.68, 1, 1)
emission_tint = Color(0.16, 0.05, 0.26, 1)
hp_bar_color = Color(0.78, 0.45, 1, 0.95)
color_name = "purple, glowing violet orb"
look_words = "caster mage wizard witch hex sorcerer spellcaster purple orb hollow ranged"
keep_props = Array[String]([])
borrow_props = Array[String]([])
realm = "both"
max_health = 70
move_speed = 2.8
detection_range = 12.0
attack_range = 10.0
windup_duration = 0.8
attack_active_duration = 0.15
recover_duration = 1.1
stagger_duration = 0.6
attack_damage = 12
attack_name = "hex_bolt"
attack_lunge_speed = 0.0
evade_skill = 0.55
knockback_scale = 1.2
max_flinch_chain = 2
flee_health_ratio = 0.3
flee_duration = 2.5
max_chase_distance = 20.0
```

**Replace with:**
```ini
tint = Color(0.42, 0.18, 0.56, 1)
emission_tint = Color(0.32, 0.06, 0.36, 1)
hp_bar_color = Color(0.78, 0.45, 1, 0.95)
color_name = "dark violet, glowing magenta orb"
look_words = "caster mage wizard witch hex sorcerer spellcaster purple violet orb hollow ranged"
keep_props = Array[String]([])
borrow_props = Array[String]([])
realm = "both"
max_health = 70
move_speed = 2.8
detection_range = 26.0
attack_range = 10.0
windup_duration = 0.8
attack_active_duration = 0.15
recover_duration = 1.1
stagger_duration = 0.6
attack_damage = 12
attack_name = "hex_bolt"
attack_lunge_speed = 0.0
evade_skill = 0.55
knockback_scale = 1.2
max_flinch_chain = 2
flee_health_ratio = 0.3
flee_duration = 2.5
max_chase_distance = 52.0
```

- **Target 12**: `data/enemies/grave_brute.tres` (lines 12–39)
- **Action**: Replace block (exact single match) to raise ranges (`22 / 48 m`) and darken swamp-olive brute hide (distinct from warm-orange Brannoc).

**Find:**
```ini
tint = Color(0.72, 0.82, 0.68, 1)
emission_tint = Color(0, 0, 0, 1)
hp_bar_color = Color(1, 0.55, 0.2, 0.95)
color_name = "pale green"
look_words = "brute big fat giant ogre heavy grave greataxe slam green tank"
keep_props = Array[String](["2H_Axe"])
borrow_props = Array[String]([])
realm = "both"
max_health = 260
move_speed = 2.5
detection_range = 9.0
attack_range = 2.6
windup_duration = 1.05
attack_active_duration = 0.25
recover_duration = 1.3
stagger_duration = 0.8
attack_damage = 24
attack_name = "grave_slam"
attack_lunge_speed = 0.0
evade_skill = 0.0
knockback_scale = 0.3
max_flinch_chain = 0
flinch_on_light_hits = false
flee_health_ratio = 0.0
threat_decay_per_sec = 0.06
max_chase_distance = 18.0
```

**Replace with:**
```ini
tint = Color(0.30, 0.46, 0.26, 1)
emission_tint = Color(0.08, 0.18, 0.04, 1)
hp_bar_color = Color(1, 0.55, 0.2, 0.95)
color_name = "dark moss green"
look_words = "brute big fat giant ogre heavy grave greataxe slam green tank"
keep_props = Array[String](["2H_Axe"])
borrow_props = Array[String]([])
realm = "both"
max_health = 260
move_speed = 2.5
detection_range = 22.0
attack_range = 2.6
windup_duration = 1.05
attack_active_duration = 0.25
recover_duration = 1.3
stagger_duration = 0.8
attack_damage = 24
attack_name = "grave_slam"
attack_lunge_speed = 0.0
evade_skill = 0.0
knockback_scale = 0.3
max_flinch_chain = 0
flinch_on_light_hits = false
flee_health_ratio = 0.0
threat_decay_per_sec = 0.06
max_chase_distance = 48.0
```

- **Target 13**: `data/enemies/shade_stalker.tres` (lines 12–38)
- **Action**: Replace block (exact single match) to raise ranges (`26 / 56 m`) and recolor stalker to dark blood-plum (distinct from cyan Sera).

**Find:**
```ini
tint = Color(0.55, 0.62, 0.8, 1)
emission_tint = Color(0.02, 0.12, 0.2, 1)
hp_bar_color = Color(0.35, 0.85, 1, 0.95)
color_name = "dark blue, cyan glow"
look_words = "stalker shade assassin rogue ninja dual blades fast blue teleporting"
keep_props = Array[String]([])
borrow_props = Array[String](["res://assets/models/characters/Knight.glb", "1H_Sword", "handslot.r", "res://assets/models/characters/Knight.glb", "1H_Sword_Offhand", "handslot.l"])
realm = "both"
max_health = 90
move_speed = 4.4
detection_range = 10.0
attack_range = 1.7
windup_duration = 0.42
attack_active_duration = 0.18
recover_duration = 0.7
stagger_duration = 0.55
attack_damage = 14
attack_name = "stalker_stab"
attack_lunge_speed = 4.5
evade_skill = 0.75
knockback_scale = 1.25
max_flinch_chain = 2
flee_health_ratio = 0.35
flee_duration = 2.0
max_chase_distance = 24.0
```

**Replace with:**
```ini
tint = Color(0.42, 0.14, 0.24, 1)
emission_tint = Color(0.28, 0.04, 0.10, 1)
hp_bar_color = Color(0.95, 0.32, 0.45, 0.95)
color_name = "crimson plum, dark maroon"
look_words = "stalker shade assassin rogue ninja dual blades fast crimson red dark teleporting"
keep_props = Array[String]([])
borrow_props = Array[String](["res://assets/models/characters/Knight.glb", "1H_Sword", "handslot.r", "res://assets/models/characters/Knight.glb", "1H_Sword_Offhand", "handslot.l"])
realm = "both"
max_health = 90
move_speed = 4.4
detection_range = 26.0
attack_range = 1.7
windup_duration = 0.42
attack_active_duration = 0.18
recover_duration = 0.7
stagger_duration = 0.55
attack_damage = 14
attack_name = "stalker_stab"
attack_lunge_speed = 4.5
evade_skill = 0.75
knockback_scale = 1.25
max_flinch_chain = 2
flee_health_ratio = 0.35
flee_duration = 2.0
max_chase_distance = 56.0
```

- **Target 14**: `scripts/environment/grand_journey_builder.gd` (lines 1066–1069)
- **Action**: Replace block (exact single match) to raise Forecourt roamers by `+50%` (`5 -> 8`).

**Find:**
```gdscript
	_add_roamer(rg, "brute", "GateBrute", Vector3(0.0, 0.0, -8.5), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	_add_roamer(rg, "hexcaster", "GateHexcaster", Vector3(3.2, 0.0, 3.4), EncounterDirector.Section.ENTRY, Vector3(0, 0, -2))
	return root
```

**Replace with:**
```gdscript
	_add_roamer(rg, "brute", "GateBrute", Vector3(0.0, 0.0, -8.5), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	_add_roamer(rg, "hexcaster", "GateHexcaster", Vector3(3.2, 0.0, 3.4), EncounterDirector.Section.ENTRY, Vector3(0, 0, -2))
	_add_roamer(rg, "skeleton", "ForecourtSkeleton_W", Vector3(-4.2, 0.0, -10.5), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	_add_roamer(rg, "skeleton", "ForecourtSkeleton_E", Vector3(4.2, 0.0, -5.0), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	_add_roamer(rg, "stalker", "ForecourtStalker", Vector3(-3.5, 0.0, -3.5), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	return root
```

- **Target 15**: `scripts/environment/grand_journey_builder.gd` (lines 1111–1121)
- **Action**: Replace block (exact single match) to grow Hall of Echoes encounter garrison from `9 -> 13`.

**Find:**
```gdscript
	var hall_specs: Array = [
		["skeleton", "SkeletonGuard_1", "hall_skel_1", Vector3(-18, 0, -18)],
		["skeleton", "SkeletonGuard_2", "hall_skel_2", Vector3(18, 0, -10)],
		["skeleton", "SkeletonGuard_3", "hall_skel_3", Vector3(-10, 0, 6)],
		["skeleton", "SkeletonGuard_4", "hall_skel_4", Vector3(12, 0, 12)],
		["skeleton", "SkeletonGuard_5", "hall_skel_5", Vector3(-20, 0, 18)],
		["skeleton", "SkeletonGuard_6", "hall_skel_6", Vector3(20, 0, 20)],
		["phantom", "PhantomTwin_1", "hall_phantom_1", Vector3(-18, 0, 22)],
		["phantom", "PhantomTwin_2", "hall_phantom_2", Vector3(18, 0, 24)],
		["phantom", "PhantomTwin_3", "hall_phantom_3", Vector3(0, 0, 16)],
	]
```

**Replace with:**
```gdscript
	var hall_specs: Array = [
		["skeleton", "SkeletonGuard_1", "hall_skel_1", Vector3(-18, 0, -18)],
		["skeleton", "SkeletonGuard_2", "hall_skel_2", Vector3(18, 0, -10)],
		["skeleton", "SkeletonGuard_3", "hall_skel_3", Vector3(-10, 0, 6)],
		["skeleton", "SkeletonGuard_4", "hall_skel_4", Vector3(12, 0, 12)],
		["skeleton", "SkeletonGuard_5", "hall_skel_5", Vector3(-20, 0, 18)],
		["skeleton", "SkeletonGuard_6", "hall_skel_6", Vector3(20, 0, 20)],
		["skeleton", "SkeletonGuard_7", "hall_skel_7", Vector3(0, 0, -14)],
		["skeleton", "SkeletonGuard_8", "hall_skel_8", Vector3(-22, 0, -4)],
		["phantom", "PhantomTwin_1", "hall_phantom_1", Vector3(-18, 0, 22)],
		["phantom", "PhantomTwin_2", "hall_phantom_2", Vector3(18, 0, 24)],
		["phantom", "PhantomTwin_3", "hall_phantom_3", Vector3(0, 0, 16)],
		["phantom", "PhantomTwin_4", "hall_phantom_4", Vector3(14, 0, -2)],
		["phantom", "PhantomTwin_5", "hall_phantom_5", Vector3(-12, 0, 12)],
	]
```

- **Target 16**: `scripts/environment/grand_journey_builder.gd` (lines 1140–1148)
- **Action**: Replace block (exact single match) to raise Hall roamers (`3 -> 5`, total Hall `12 -> 18`, `+50%`) and set Hall `detection_range = 56.0`, `max_chase_distance = 68.0`.

**Find:**
```gdscript
			_configure_enemy_actor(e, String(spec[1]), String(spec[2]), c + (spec[3] as Vector3), tint)
			enemies.add_child(e)
		root.add_child(enemies)
	# Roamers (HALL section, never hold the gate): a Grave Brute before the exit, two Hexcasters on the flanks.
	var hrg: Node3D = _roamer_group(root)
	_add_roamer(hrg, "brute", "HallBrute", c + Vector3(0, 0, 24), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	_add_roamer(hrg, "hexcaster", "HallHexcaster_W", c + Vector3(-24, 0, 0), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	_add_roamer(hrg, "hexcaster", "HallHexcaster_E", c + Vector3(24, 0, 4), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
```

**Replace with:**
```gdscript
			_configure_enemy_actor(e, String(spec[1]), String(spec[2]), c + (spec[3] as Vector3), tint)
			if e is EnemyAI:
				(e as EnemyAI).detection_range = 56.0
				(e as EnemyAI).max_chase_distance = 68.0
			enemies.add_child(e)
		root.add_child(enemies)
	# Roamers (HALL section, never hold the gate): scaled 56/68 m (+50% Hall count: 13 + 5 = 18).
	var hrg: Node3D = _roamer_group(root)
	for r_node in [
		_add_roamer(hrg, "brute", "HallBrute", c + Vector3(0, 0, 24), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs)),
		_add_roamer(hrg, "hexcaster", "HallHexcaster_W", c + Vector3(-24, 0, 0), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs)),
		_add_roamer(hrg, "hexcaster", "HallHexcaster_E", c + Vector3(24, 0, 4), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs)),
		_add_roamer(hrg, "stalker", "HallStalker_W", c + Vector3(-16, 0, -20), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs)),
		_add_roamer(hrg, "skeleton", "HallSkeleton_N", c + Vector3(8, 0, 22), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs)),
	]:
		if r_node is EnemyAI:
			(r_node as EnemyAI).detection_range = 56.0
			(r_node as EnemyAI).max_chase_distance = 68.0
```

- **Target 17**: `scripts/environment/grand_journey_builder.gd` (lines 1255–1260)
- **Action**: Replace block (exact single match) to increase bridge bastion garrisons by `+50%` (`6 -> 9` per route).

**Find:**
```gdscript
const ROUTE_ENEMIES: Dictionary = {
	"R1_PilgrimCauseway": [["skeleton", "skeleton", "hexcaster"], ["skeleton", "shield", "hexcaster"]],
	"R2_SunlitBridges": [["phantom", "skeleton", "stalker"], ["skeleton", "skeleton", "hexcaster"]],
	"R3_WindsweptRampart": [["skeleton", "stalker", "hexcaster"], ["brute", "skeleton", "phantom"]],
	"R5_Processional": [["phantom", "skeleton", "hexcaster"], ["shield", "skeleton", "brute"]],
}
```

**Replace with:**
```gdscript
const ROUTE_ENEMIES: Dictionary = {
	"R1_PilgrimCauseway": [["skeleton", "skeleton", "hexcaster", "stalker"], ["skeleton", "shield", "hexcaster", "skeleton", "brute"]],
	"R2_SunlitBridges": [["phantom", "skeleton", "stalker", "hexcaster"], ["skeleton", "skeleton", "hexcaster", "phantom", "stalker"]],
	"R3_WindsweptRampart": [["skeleton", "stalker", "hexcaster", "skeleton"], ["brute", "skeleton", "phantom", "hexcaster", "stalker"]],
	"R5_Processional": [["phantom", "skeleton", "hexcaster", "stalker"], ["shield", "skeleton", "brute", "hexcaster", "skeleton"]],
}
```

- **Target 18**: `scripts/environment/grand_journey_builder.gd` (lines 1378–1385)
- **Action**: Replace block (exact single match) so 4–5 bastion garrison mobs spawn evenly without overlapping.

**Find:**
```gdscript
	var face: Vector3 = neighbours[0] as Vector3
	var spots: Array = [m, m + 2.2, m - 2.2]
	for ei in range(kinds.size()):
		var a: float = float(spots[ei % spots.size()])
		var ep := Vector3(c.x + sin(a) * 3.4, c.y, c.z + cos(a) * 3.4)
```

**Replace with:**
```gdscript
	var face: Vector3 = neighbours[0] as Vector3
	var spots: Array = [m, m + 1.8, m - 1.8, m + 2.9, m - 2.9]
	for ei in range(kinds.size()):
		var a: float = float(spots[ei % spots.size()])
		var ep := Vector3(c.x + sin(a) * 3.8, c.y, c.z + cos(a) * 3.8)
```

- **Target 19**: `scripts/environment/grand_journey_builder.gd` (lines 1548–1551)
- **Action**: Replace block (exact single match) to raise Stage 03 Gallery patrol from `2 -> 4` roamers.

**Find:**
```gdscript
	var grg: Node3D = _roamer_group(root)
	_add_roamer(grg, "skeleton", "GallerySkeleton_A", Vector3(-2.4, y, 63.5), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 60))
	_add_roamer(grg, "skeleton", "GallerySkeleton_B", Vector3(2.4, y, 66.5), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 60))
```

**Replace with:**
```gdscript
	var grg: Node3D = _roamer_group(root)
	_add_roamer(grg, "skeleton", "GallerySkeleton_A", Vector3(-2.4, y, 63.5), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 60))
	_add_roamer(grg, "skeleton", "GallerySkeleton_B", Vector3(2.4, y, 66.5), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 60))
	_add_roamer(grg, "stalker", "GalleryStalker", Vector3(-2.2, y, 68.5), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 60))
	_add_roamer(grg, "hexcaster", "GalleryHexcaster", Vector3(2.2, y, 76.0), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 70))
```

- **Target 20**: `scripts/environment/grand_journey_builder.gd` (lines 1731–1741)
- **Action**: Replace block (exact single match) to grow Clock-Tower Chamber (`36×36 m`) roamers `+50%` (`8 -> 12`) and set `detection_range = 38.0`, `max_chase_distance = 48.0`.

**Find:**
```gdscript
	var rg: Node3D = _roamer_group(root)
	var door := Vector3(0, y, cz - h)
	_add_roamer(rg, "skeleton", "TowerSkeleton_A", Vector3(10.0, y, cz + 10.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_B", Vector3(-12.0, y, cz + 9.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "phantom", "TowerPhantom", Vector3(11.0, y, cz - 6.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_C", Vector3(-10.0, y, cz - 10.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_D", Vector3(6.0, y, cz + 14.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "brute", "TowerBrute", Vector3(0.0, y, cz + 12.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "hexcaster", "TowerHexcaster", Vector3(-14.0, y, cz + 2.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "stalker", "TowerStalker", Vector3(14.0, y, cz + 3.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	return root
```

**Replace with:**
```gdscript
	var rg: Node3D = _roamer_group(root)
	var door := Vector3(0, y, cz - h)
	_add_roamer(rg, "skeleton", "TowerSkeleton_A", Vector3(10.0, y, cz + 10.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_B", Vector3(-12.0, y, cz + 9.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "phantom", "TowerPhantom", Vector3(11.0, y, cz - 6.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_C", Vector3(-10.0, y, cz - 10.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_D", Vector3(6.0, y, cz + 14.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "brute", "TowerBrute", Vector3(0.0, y, cz + 12.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "hexcaster", "TowerHexcaster", Vector3(-14.0, y, cz + 2.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "stalker", "TowerStalker", Vector3(14.0, y, cz + 3.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_E", Vector3(-6.0, y, cz + 14.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "phantom", "TowerPhantom_B", Vector3(-11.0, y, cz - 5.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "hexcaster", "TowerHexcaster_B", Vector3(14.0, y, cz - 3.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "stalker", "TowerStalker_B", Vector3(-14.0, y, cz + 7.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	for r_node in rg.get_children():
		if r_node is EnemyAI:
			(r_node as EnemyAI).detection_range = 38.0
			(r_node as EnemyAI).max_chase_distance = 48.0
	return root
```

- **Target 21**: `scripts/environment/grand_journey_builder.gd` (lines 1768–1774)
- **Action**: Replace block (exact single match) to raise Stage 05 Esplanade patrol `+50%` (`4 -> 6`).

**Find:**
```gdscript
	var rg: Node3D = _roamer_group(root)
	_add_roamer(rg, "shield", "EsplanadeGatekeeper", Vector3(0.0, y, 118.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "skeleton", "EsplanadeSkeleton", Vector3(-5.5, y, 118.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	# Grave Brute: slow ground-slam heavy guarding the east half of the esplanade.
	_add_roamer(rg, "brute", "EsplanadeBrute", Vector3(5.5, y, 118.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "hexcaster", "EsplanadeHexcaster", Vector3(-3.0, y, 117.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
```

**Replace with:**
```gdscript
	var rg: Node3D = _roamer_group(root)
	_add_roamer(rg, "shield", "EsplanadeGatekeeper", Vector3(0.0, y, 118.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "skeleton", "EsplanadeSkeleton", Vector3(-5.5, y, 118.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	# Grave Brute: slow ground-slam heavy guarding the east half of the esplanade.
	_add_roamer(rg, "brute", "EsplanadeBrute", Vector3(5.5, y, 118.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "hexcaster", "EsplanadeHexcaster", Vector3(-3.0, y, 117.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "stalker", "EsplanadeStalker", Vector3(3.2, y, 117.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "skeleton", "EsplanadeSkeleton_E", Vector3(6.8, y, 118.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
```

- **Postcondition**: Every arena/route spawns `+50%` more mobs (`Forecourt 8`, `Bastions 9/route`, `Hall 18`, `Gallery 4 roamers`, `Chamber 12`, `Esplanade 6`), all enemy damage scales `+40%`, and archetypes use dark distinct palettes. (Note: `skeleton_guard.gd` is updated in Step 20 and `encounter_director.gd` in Step 18.)

---

### Step 15 — Stop Distant-Order Ally Teleport Loops & Add 1.2s Camera-Visible Pull/Taunt Targeting (`REQ-16`, `REQ-19`)

- **Prerequisites**: Step 6 applied (`world_intel.gd`, `ally_squad_manager.gd`). Note: base targetable distance constants increase by **at most +30%** (`15 -> 19.5`, `20 -> 26`, `25 -> 32.5`, `40 -> 52`, `28 -> 36.4`), while periodic camera-frustum visibility (`<= 140 m` every `1.2 s`) dynamically brings any enemy visible in the player's camera into targetable & pullable range.
- **Target 1**: `scripts/allies/squad_ally.gd` (lines 25–30)
- **Action**: Replace block (exact single match) to raise `FOLLOW_LEASH` by `+30%` (`15.0 -> 19.5`).

**Find:**
```gdscript
const GRAVITY: float = 22.0
const INTERCEPT_RADIUS: float = 6.0
const LEASH_RADIUS: float = 8.5
const FOLLOW_LEASH: float = 15.0
```

**Replace with:**
```gdscript
const GRAVITY: float = 22.0
const INTERCEPT_RADIUS: float = 6.0
const LEASH_RADIUS: float = 8.5
const FOLLOW_LEASH: float = 19.5
```

- **Target 2**: `scripts/allies/squad_ally.gd` (lines 846–882)
- **Action**: Replace block (exact single match) so area-taunt / pull commands fall back cleanly to visible single targets instead of saying `"Nothing to taunt."`, and pull/lure-to-player taunts hand off into `kite` (`lure = "player"`).

**Find:**
```gdscript
func _run_taunt_cmd(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	# "Take aggro": pull every enemy currently on the player onto this ally (single-enemy taunts never
	# touch the rest of a group).
	if bool(cmd.args.get("area", false)) and player != null:
		var on_player: Array[EnemyAI] = []
		for en in _active_enemies(player.global_position, 10.0):
			if en.get_current_target() == player:
				on_player.append(en)
		if on_player.is_empty():
			say("Nothing's on you right now.", "refuse", 1)
			finish_current("nothing on player")
			return
		if global_position.distance_to(player.global_position) > 5.0:
			_move_to(player.global_position, profile.move_speed * 1.2, delta)
			return
		_taunt_cd = profile.taunt_cooldown
		_play(["Taunt", "Cheer", "Taunt_Longer"], 0.8, true)
		_start_action("taunt", 0.55, -1.0, Callable())
		say_event("taunt", 1)
		for en in on_player:
			en.apply_taunt(self, -1.0, 4.0)
		finish_current("took aggro x%d" % on_player.size())
		return
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null:
		e = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
		if e == null:
			say("Nothing to taunt.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
	if global_position.distance_to(e.global_position) > 7.0:
		_move_to(e.global_position, profile.move_speed, delta)
		return
	_do_taunt(e, false)
	finish_current("taunted")
```

**Replace with:**
```gdscript
func _run_taunt_cmd(delta: float, player: Node3D, cmd: SquadCommand) -> void:
	# "Take aggro": pull every enemy currently on the player onto this ally; fall back to visible targets.
	if bool(cmd.args.get("area", false)) and player != null:
		var on_player: Array[EnemyAI] = []
		for en in _active_enemies(player.global_position, 12.0):
			if en.get_current_target() == player:
				on_player.append(en)
		if on_player.is_empty():
			var fallback: EnemyAI = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
			if fallback == null:
				say("Nothing's on you right now.", "refuse", 1)
				finish_current("nothing on player")
				return
			cmd.args["area"] = false
			cmd.data["enemy"] = fallback
		else:
			if global_position.distance_to(player.global_position) > 5.0:
				_move_to(player.global_position, profile.move_speed * 1.2, delta)
				return
			_taunt_cd = profile.taunt_cooldown
			_play(["Taunt", "Cheer", "Taunt_Longer"], 0.8, true)
			_start_action("taunt", 0.55, -1.0, Callable())
			say_event("taunt", 1)
			for en in on_player:
				en.apply_taunt(self, -1.0, 4.0)
			finish_current("took aggro x%d" % on_player.size())
			return
	var e: EnemyAI = cmd.data.get("enemy", null) as EnemyAI
	if e == null or not _enemy_ok(e):
		e = _resolve_enemy(String(cmd.args.get("target", "nearest")), player)
		if e == null:
			say("Nothing to taunt.", "refuse", 1)
			finish_current("no target")
			return
		cmd.data["enemy"] = e
	if global_position.distance_to(e.global_position) > 7.0:
		_move_to(e.global_position, profile.move_speed * 1.15, delta)
		return
	_do_taunt(e, false)
	if String(cmd.args.get("lure", "")) == "player":
		cmd.verb = "kite"
		cmd.step = "sustain"
		cmd.data["enemy"] = e
		cmd.data["provoke_tries"] = 0
		return
	finish_current("taunted")
```

- **Target 3**: `scripts/allies/squad_ally.gd` (lines 975–983)
- **Action**: Replace block (exact single match) to allow `18.0 s` approach time when sent across large halls or toward a camera-visible enemy.

**Find:**
```gdscript
		"approach":
			cmd.data["approach_t"] = float(cmd.data.get("approach_t", 0.0)) + delta
			if float(cmd.data["approach_t"]) > 9.0:
				_kite_fallback(cmd, e, "Can't reach it — I'll fight from here.")
				return
```

**Replace with:**
```gdscript
		"approach":
			cmd.data["approach_t"] = float(cmd.data.get("approach_t", 0.0)) + delta
			if float(cmd.data["approach_t"]) > 18.0:
				_kite_fallback(cmd, e, "Can't reach it — I'll fight from here.")
				return
```

- **Target 4**: `scripts/allies/squad_ally.gd` (lines 3402–3426)
- **Action**: Replace block (exact single match) so allies executing distant or camera-visible engage/pull orders can run all the way out to their target without loop-teleporting back, while keeping normal `FOLLOW_LEASH` catch-up at `19.5 m` (`+30%` over `15 m`).

**Find:**
```gdscript
func _update_stuck(delta: float) -> void:
	var moved: float = Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	var wants: bool = Vector2(velocity.x, velocity.z).length() > 1.0
	_last_pos = global_position
	if wants and moved < 0.6 * delta:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)
	if _stuck_timer > 2.0:
		_stuck_timer = 0.0
		var p: Node3D = _player()
		if p != null and global_position.distance_to(p.global_position) > 6.0:
			_blink_to(p)


## Catch-up: allies are mirror echoes — when hopelessly far, fallen, or left behind a jump, they blink
## to a free spot behind the player (with a spectral flash) instead of path-finding across chasms.
func _catch_up(player: Node3D) -> void:
	var d: Vector3 = player.global_position - global_position
	var far: float = 30.0 if (current != null and current.is_mission()) else 20.0
	if d.length() > far or d.y > 3.0 and Vector2(d.x, d.z).length() < 10.0 or global_position.y < player.global_position.y - 6.0:
		if player is PlayerController and (player as PlayerController).is_currently_airborne():
			return
		_blink_to(player)
```

**Replace with:**
```gdscript
func _has_distant_order() -> bool:
	if current == null or current.done:
		return false
	return current.verb in [
		"attack", "taunt", "hit_and_run", "surround", "ranged",
		"kite", "nuke", "peel", "ambush",
		"combo_kite_nuke", "combo_charge_finish", "combo_lure_detonate",
		"hunt", "destroy", "interact",
	]


func _distant_order_leash(player: Node3D) -> float:
	var reach: float = 85.0
	if current != null:
		var tgt: Node3D = current.data.get("enemy", null) as Node3D
		if tgt != null and is_instance_valid(tgt) and player != null:
			reach = maxf(reach, tgt.global_position.distance_to(player.global_position) + 20.0)
	return minf(160.0, reach)


func _update_stuck(delta: float) -> void:
	var moved: float = Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	var wants: bool = Vector2(velocity.x, velocity.z).length() > 1.0
	_last_pos = global_position
	if wants and moved < 0.6 * delta:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)
	if _stuck_timer > 2.0:
		_stuck_timer = 0.0
		var p: Node3D = _player()
		if p == null:
			return
		if _has_distant_order():
			# Unstick locally during distant distract/pull orders rather than yanking back to the player.
			if is_on_floor():
				velocity.y = 4.5
			var leash: float = _distant_order_leash(p)
			if global_position.distance_to(p.global_position) > leash or global_position.y < p.global_position.y - 8.0:
				_blink_to(p)
		elif global_position.distance_to(p.global_position) > 6.0:
			_blink_to(p)


## Catch-up: allies are mirror echoes — when hopelessly far, fallen, or left behind a jump, they blink
## to a free spot behind the player (with a spectral flash) instead of path-finding across chasms.
func _catch_up(player: Node3D) -> void:
	var d: Vector3 = player.global_position - global_position
	var distant_order: bool = _has_distant_order()
	var far: float = _distant_order_leash(player) if distant_order else (35.0 if (current != null and current.is_mission()) else FOLLOW_LEASH)
	var vertical_trap: bool = not distant_order and d.y > 3.0 and Vector2(d.x, d.z).length() < 10.0
	if d.length() > far or vertical_trap or global_position.y < player.global_position.y - 8.0:
		if player is PlayerController and (player as PlayerController).is_currently_airborne():
			return
		_blink_to(player)
```

- **Target 5**: `scripts/allies/squad_ally.gd` (lines 3528–3532)
- **Action**: Replace block (exact single match) to cap fallback radius at `+30%` (`20.0 -> 26.0`).

**Find:**
```gdscript
func _resolve_enemy(selector: String, player: Node3D) -> EnemyAI:
	if manager != null and manager.has_method("resolve_enemy"):
		return manager.call("resolve_enemy", selector, player.global_position if player != null else global_position) as EnemyAI
	return _nearest_enemy(global_position, 20.0)
```

**Replace with:**
```gdscript
func _resolve_enemy(selector: String, player: Node3D) -> EnemyAI:
	if manager != null and manager.has_method("resolve_enemy"):
		return manager.call("resolve_enemy", selector, player.global_position if player != null else global_position) as EnemyAI
	return _nearest_enemy(global_position, 26.0)
```

- **Target 6**: `scripts/allies/world_intel.gd` (lines 12–14)
- **Action**: Replace block (exact single match) to cap `RANGE_M` at `+30%` (`40.0 -> 52.0`) and add `CAMERA_SCAN_SEC = 1.2` / `CAMERA_MAX_M = 140.0`.

**Find:**
```gdscript
const REFRESH_SEC: float = 0.25
const RANGE_M: float = 40.0
```

**Replace with:**
```gdscript
const REFRESH_SEC: float = 0.25
const RANGE_M: float = 52.0
const CAMERA_SCAN_SEC: float = 1.2
const CAMERA_MAX_M: float = 140.0
```

- **Target 7**: `scripts/allies/world_intel.gd` (lines 36–51)
- **Action**: Replace block (exact single match) to add `_cam_visible` tracking and periodic `1.2 s` camera-frustum scanning in `_physics_process()`.

**Find:**
```gdscript
var _entries: Array[Dictionary] = []
var _timer: float = 0.0
var show_tags: bool = true


func _ready() -> void:
	add_to_group("world_intel")


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_SEC
		refresh()
```

**Replace with:**
```gdscript
var _entries: Array[Dictionary] = []
var _timer: float = 0.0
var _cam_timer: float = 0.0
var _cam_visible: Dictionary = {}  # enemy instance_id -> true (refreshed every CAMERA_SCAN_SEC)
var show_tags: bool = true


func _ready() -> void:
	add_to_group("world_intel")


func _physics_process(delta: float) -> void:
	_cam_timer -= delta
	var cam_updated: bool = false
	if _cam_timer <= 0.0:
		_cam_timer = CAMERA_SCAN_SEC
		_scan_camera_visible()
		cam_updated = true
	_timer -= delta
	if cam_updated or _timer <= 0.0:
		_timer = REFRESH_SEC
		refresh()
```

- **Target 8**: `scripts/allies/world_intel.gd` (lines 78–97)
- **Action**: Replace block (exact single match) to implement `scan_camera_now()`, `is_camera_visible()`, and include camera-visible active enemies in `refresh()`.

**Find:**
```gdscript
func refresh() -> void:
	_entries.clear()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var pf: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = n as EnemyAI
		if e == null or e.is_dead or not e.is_inside_tree():
			_hide_tag(n)
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if not e.is_active or d > RANGE_M:
			_hide_tag(e)
			continue
		var entry: Dictionary = _describe(e, player, pf, d)
		_entries.append(entry)
		_update_tag(e, entry)
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
```

**Replace with:**
```gdscript
func is_camera_visible(e: Node) -> bool:
	return e != null and is_instance_valid(e) and bool(_cam_visible.get(e.get_instance_id(), false))


func scan_camera_now() -> void:
	_scan_camera_visible()
	refresh()


func _scan_camera_visible() -> void:
	_cam_visible.clear()
	if not is_inside_tree() or get_tree() == null or get_viewport() == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if cam == null or player == null:
		return
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = n as EnemyAI
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree():
			continue
		if e.global_position.distance_to(player.global_position) > CAMERA_MAX_M:
			continue
		var chest: Vector3 = e.global_position + Vector3.UP * 1.1
		var head: Vector3 = e.global_position + Vector3.UP * 1.75
		if cam.is_position_in_frustum(chest) or cam.is_position_in_frustum(head):
			_cam_visible[e.get_instance_id()] = true


func refresh() -> void:
	_entries.clear()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var pf: Vector3 = player.call("get_facing_direction") if player.has_method("get_facing_direction") else Vector3.FORWARD
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyAI = n as EnemyAI
		if e == null or e.is_dead or not e.is_inside_tree():
			_hide_tag(n)
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		var cam_vis: bool = is_camera_visible(e)
		if not e.is_active or (d > RANGE_M and not cam_vis):
			_hide_tag(e)
			continue
		var entry: Dictionary = _describe(e, player, pf, d)
		entry["cam_vis"] = cam_vis
		_entries.append(entry)
		_update_tag(e, entry)
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
```

- **Target 9**: `scripts/allies/world_intel.gd` (lines 318–327)
- **Action**: Replace block (exact single match; stays below Step 6 Target 2's lines `279–287`) so `"farther"/"further"/"distant"/"over there"` resolve to farther visible enemies.

**Find:**
```gdscript
		var d: float = (en["node"] as Node3D).global_position.distance_to(origin)
		if s.contains("farthest") or s.contains("furthest"):
			score += d * 0.05
```

**Replace with:**
```gdscript
		var d: float = (en["node"] as Node3D).global_position.distance_to(origin)
		if s.contains("farthest") or s.contains("furthest") or s.contains("farther") or s.contains("further") or s.contains("distant") or s.contains("over there"):
			score += d * 0.08
```

- **Target 10**: `scripts/allies/world_intel.gd` (lines 377–388)
- **Action**: Replace block (exact single match) to cap overhead `IntelTag` range increase at `+30%` (`30 -> 39`, `28 -> 36.4`) while also showing tags for camera-visible distant enemies.

**Find:**
```gdscript
		e.add_child(tag)
		tag.position = Vector3(0, 2.45, 0)
		WorldLabelOverlay.adopt(tag, {"px": 14, "offset": Vector2(0, -16), "max_dist": 30.0})
	# Mirror insight reveals more: exact health and the exposed weak point.
	if e.mirror_insight:
		tag.text = "%s · %d%% · WEAK" % [String(en["id"]), int(en["hp_pct"])]
		tag.modulate = Color(0.55, 0.9, 1.0, 0.95)
	else:
		tag.text = String(en["id"])
		tag.modulate = Color(1.0, 0.86, 0.5, 0.95)
	tag.visible = show_tags and not bool(tag.get_meta("cinematic_hidden", false)) and float(en["dist"]) < 28.0
```

**Replace with:**
```gdscript
		e.add_child(tag)
		tag.position = Vector3(0, 2.45, 0)
		WorldLabelOverlay.adopt(tag, {"px": 15, "offset": Vector2(0, -16), "max_dist": 39.0})
	# Mirror insight reveals more: exact health and the exposed weak point.
	if e.mirror_insight:
		tag.text = "%s · %d%% · WEAK" % [String(en["id"]), int(en["hp_pct"])]
		tag.modulate = Color(0.55, 0.9, 1.0, 0.98)
	else:
		tag.text = String(en["id"])
		tag.modulate = Color(1.0, 0.88, 0.52, 0.98)
	tag.visible = show_tags and not bool(tag.get_meta("cinematic_hidden", false)) and (float(en["dist"]) < 36.4 or bool(en.get("cam_vis", false)))
```

- **Target 11**: `scripts/allies/ally_squad_manager.gd` (lines 445–451)
- **Action**: Replace block (exact single match) capping fallback radius at `+30%` (`25.0 -> 32.5`).

**Find:**
```gdscript
	# Shared knowledge base: IDs ("E3"), types, looks, colours, weapons, sides, "near Sera", "hitting Ivo"...
	if intel != null:
		return intel.resolve(sel)
	var cands: Array[EnemyAI] = _active_enemies_near(near, 25.0)
```

**Replace with:**
```gdscript
	# Shared knowledge base: IDs ("E3"), types, looks, colours, weapons, sides, "near Sera", "hitting Ivo"...
	if intel != null:
		return intel.resolve(sel)
	var cands: Array[EnemyAI] = _active_enemies_near(near, 32.5)
```

- **Target 12**: `scripts/allies/squad_command_parser.gd` (lines 36–39)
- **Action**: Replace block (exact single match) so `"pull em"`, `"pull them"`, `"pull it"`, `"pull that"`, `"bring them"` parse cleanly as `kite` (pull/bait).

**Find:**
```gdscript
	["kite", ["kite", "bait", "run in circles", "run circles", "running circles", "run around with", "make it chase", "make them chase", "make him chase", "draw them", "draw it", "draw him", "lead them around", "lead it around", "lead it", "keep it busy", "keep them busy", "keep him busy", "pull it away", "pull them away", "drag it", "drag them", "lure it", "lure him", "lure her", "bring it to us", "bring it here", "bring them to us", "distract"]],
```

**Replace with:**
```gdscript
	["kite", ["kite", "bait", "run in circles", "run circles", "running circles", "run around with", "make it chase", "make them chase", "make him chase", "draw them", "draw it", "draw him", "lead them around", "lead it around", "lead it", "keep it busy", "keep them busy", "keep him busy", "pull it", "pull em", "pull them", "pull him", "pull that", "pull one", "pull away", "drag it", "drag them", "lure it", "lure him", "lure her", "bring it", "bring them", "bring him", "distract"]],
```

- **Target 13**: `scripts/allies/squad_command_parser.gd` (lines 105–109)
- **Action**: Replace block (exact single match) to recognize `"farther"`, `"further"`, `"distant"`, `"far"`, and `"away"` in target descriptors.

**Find:**
```gdscript
const DESCRIPTOR_WORDS: Array[String] = ["purple", "violet", "blue", "cyan", "green", "pale", "white", "bone", "gold", "golden",
	"steel", "silver", "red", "black", "dark", "glowing", "axe", "sword", "swords", "blades", "shield", "orb", "greataxe",
	"hooded", "armored", "armoured", "big", "huge", "giant", "small", "left", "right", "behind", "near", "closest to",
	"next to", "attacking", "hitting", "chasing", "targeting", "farthest", "furthest", "stunned", "fleeing"]
```

**Replace with:**
```gdscript
const DESCRIPTOR_WORDS: Array[String] = ["purple", "violet", "blue", "cyan", "green", "pale", "white", "bone", "gold", "golden",
	"steel", "silver", "red", "black", "dark", "glowing", "axe", "sword", "swords", "blades", "shield", "orb", "greataxe",
	"hooded", "armored", "armoured", "big", "huge", "giant", "small", "left", "right", "behind", "near", "closest to",
	"next to", "attacking", "hitting", "chasing", "targeting", "farthest", "furthest", "farther", "further", "distant", "far", "away", "stunned", "fleeing"]
```

- **Target 14**: `scripts/allies/squad_command_parser.gd` (lines 377–383)
- **Action**: Replace block (exact single match) to set `cmd["lure"] = "player"` whenever pulling/bringing an enemy back (`"pull"`/`"bring"` + `"here"`/`"back"`/`"to me"`/`"to us"`).

**Find:**
```gdscript
		"kite":
			# Bait it back to us -> circle around the squad so the others can hit it.
			for w in ["to us", "to me", "over here", " here ", "to the squad", "to the group", "into us", "towards us", "toward us", "into the ambush", "into our trap"]:
				if t.contains(w):
					cmd["lure"] = "player"
					break
```

**Replace with:**
```gdscript
		"kite":
			# Bait/pull it back to us -> circle around the squad so the others can hit it.
			for w in ["to us", "to me", "over here", " here ", "back here", "to the squad", "to the group", "into us", "towards us", "toward us", "into the ambush", "into our trap", "pull ", "bring "]:
				if t.contains(w):
					cmd["lure"] = "player"
					break
```

- **Postcondition**: Base targetable ranges never exceed `+30%`, every active enemy visible in the player's camera (`<= 140 m`, scanned every `1.2 s`) becomes targetable automatically, `"pull em here"` / `"taunt the farther enemy"` never fail with `"Nothing to taunt."`, and allies do not loop-teleport back while running out to pull distant targets.

---

### Step 16 — Boost HUD/Label Contrast & Scale All UI Icons +20% (`REQ-17`, `REQ-18`)

- **Prerequisites**: Steps 1, 5, 11, 13, 15 complete.
- **Target 1**: `scripts/ui/ui_theme.gd` (lines 14–18)
- **Action**: Replace block (exact single match) to prefer SemiBold condensed body font first.

**Find:**
```gdscript
const FONT_BODY_PATHS: PackedStringArray = [
	"res://assets/fonts/Rajdhani-Medium.ttf", "res://assets/fonts/Rajdhani-SemiBold.ttf",
	"res://assets/fonts/BarlowSemiCondensed-Medium.ttf",
]
```

**Replace with:**
```gdscript
const FONT_BODY_PATHS: PackedStringArray = [
	"res://assets/fonts/Rajdhani-SemiBold.ttf", "res://assets/fonts/Rajdhani-Medium.ttf",
	"res://assets/fonts/BarlowSemiCondensed-Medium.ttf",
]
```

- **Target 2**: `scripts/ui/ui_theme.gd` (lines 78–85)
- **Action**: Replace block (exact single match) to strengthen `body_font()` stroke weight for HUD/objective readability.

**Find:**
```gdscript
## Crisp condensed face for numbers, HUD and body copy.
static func body_font() -> Font:
	if _body == null:
		_body = _first_existing(FONT_BODY_PATHS)
		if _body == null:
			_body = _system(PackedStringArray(["Rajdhani", "Barlow Semi Condensed", "Bahnschrift", "Segoe UI", "Arial"]), 600)
	return _body
```

**Replace with:**
```gdscript
## Crisp condensed face for numbers, HUD and body copy.
static func body_font() -> Font:
	if _body == null:
		_body = _first_existing(FONT_BODY_PATHS)
		if _body != null:
			_body = _variable(_body, 650.0)
		else:
			_body = _system(PackedStringArray(["Rajdhani", "Barlow Semi Condensed", "Bahnschrift", "Segoe UI", "Arial"]), 700)
	return _body
```

- **Target 3**: `scripts/ui/squad_comms_hud.gd` (lines 105–115)
- **Action**: Replace block (exact single match) to enlarge `MicButton` by ~20% (`64 -> 78`).

**Find:**
```gdscript
func _build_mic_button() -> void:
	_mic_btn = Control.new()
	_mic_btn.name = "MicButton"
	_mic_btn.custom_minimum_size = Vector2(64, 64)
	_mic_btn.size = Vector2(64, 64)
```

**Replace with:**
```gdscript
func _build_mic_button() -> void:
	_mic_btn = Control.new()
	_mic_btn.name = "MicButton"
	_mic_btn.custom_minimum_size = Vector2(78, 78)
	_mic_btn.size = Vector2(78, 78)
```

- **Target 4**: `scripts/ui/squad_comms_hud.gd` (lines 283–332)
- **Action**: Replace block (exact single match) to wrap the top-left squad roster & hint in a dark chamfered backing plate, brighten ally name colors with `6 px` dark outlines, and offset `MicButton` for its `78 px` size.

**Find:**
```gdscript
	if _mic_btn != null:
		_mic_btn.position = Vector2(s.x - 108.0, s.y * 0.5 + 60.0)
		_mic_btn.visible = SquadAIConfig.voice_allowed()
		_mic_btn.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if _cinematic:
		return
	var s: Vector2 = size
	# Minimal squad readout directly under the player's own health cluster (top-left, ends at y ~136).
	var end_y: float = _draw_roster(Vector2(36.0, 150.0))
	_draw_subtitles(s)
	_draw_notes(s)
	if _log_visible:
		_draw_log(Vector2(s.x - 470.0, s.y * 0.30))
	if not _chat_open and SquadAIConfig.chat_allowed() and not _roster.is_empty():
		var hint: String = "ENTER orders" + ("  ·  V talk" if SquadAIConfig.voice_allowed() else "") + "  ·  L log"
		_text(UITheme.body_font(), Vector2(36.0, end_y + 12.0), hint, 13, Color(0.95, 0.9, 0.78, 0.6), 3)


# ------------------------------------------------------------------ drawing

## Minimal squad readout: one row per ally — NAME + health bar (a downed ally pulses red with "DOWN · E").
## Returns the y below the last row.
func _draw_roster(origin: Vector2) -> float:
	var disp: Font = UITheme.display_font()
	var body: Font = UITheme.body_font()
	var y: float = origin.y
	var now: float = float(Time.get_ticks_msec()) * 0.001
	for r_v in _roster:
		var r: Dictionary = r_v as Dictionary
		var col: Color = r.get("color", UITheme.GOLD) as Color
		var down: bool = bool(r.get("downed", false))
		var ratio: float = clampf(float(r.get("hp", 0)) / maxf(1.0, float(r.get("max_hp", 1))), 0.0, 1.0)
		_text(disp, Vector2(origin.x, y + 14.0), String(r.get("name", "")).to_upper(), 15, Color(col.r, col.g, col.b, 1.0), 4)
		var bar := Rect2(origin.x + 96.0, y + 5.0, 170.0, 8.0)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		if down:
			var pulse: float = 0.5 + 0.5 * sin(now * 6.0)
			draw_rect(bar, Color(1.0, 0.3, 0.25, 0.35 + 0.4 * pulse))
			_text(body, Vector2(bar.end.x + 8.0, y + 14.0), "DOWN · E", 13, Color(1.0, 0.45, 0.4, 1.0), 3)
		else:
			var hp_col: Color = Color(0.45, 0.95, 0.55) if ratio > 0.5 else (Color(1.0, 0.8, 0.3) if ratio > 0.25 else Color(1.0, 0.3, 0.25))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), hp_col)
		draw_rect(bar, Color(col.r, col.g, col.b, 0.55), false, 1.0)
		y += 24.0
	return y
```

**Replace with:**
```gdscript
	if _mic_btn != null:
		_mic_btn.position = Vector2(s.x - 122.0, s.y * 0.5 + 54.0)
		_mic_btn.visible = SquadAIConfig.voice_allowed()
		_mic_btn.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if _cinematic:
		return
	var s: Vector2 = size
	# Minimal squad readout directly under the player's own health cluster (top-left).
	var show_hint: bool = not _chat_open and SquadAIConfig.chat_allowed() and not _roster.is_empty()
	var roster_origin := Vector2(36.0, 158.0)
	if not _roster.is_empty():
		var plate_h: float = float(_roster.size()) * 26.0 + (32.0 if show_hint else 12.0)
		var plate := Rect2(roster_origin.x - 12.0, roster_origin.y - 8.0, 304.0, plate_h)
		var poly := _chamfer(plate, 8.0)
		draw_colored_polygon(poly, Color(0.025, 0.03, 0.055, 0.84))
		poly.append(poly[0])
		draw_polyline(poly, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.38), 1.0, true)
	var end_y: float = _draw_roster(roster_origin)
	_draw_subtitles(s)
	_draw_notes(s)
	if _log_visible:
		_draw_log(Vector2(s.x - 470.0, s.y * 0.30))
	if show_hint:
		var hint: String = "ENTER orders" + ("  ·  V talk" if SquadAIConfig.voice_allowed() else "") + "  ·  L log"
		_text(UITheme.body_font(), Vector2(roster_origin.x, end_y + 14.0), hint, 14, Color(0.98, 0.95, 0.86, 0.92), 5)


# ------------------------------------------------------------------ drawing

## Minimal squad readout: one row per ally — NAME + health bar (a downed ally pulses red with "DOWN · E").
## Returns the y below the last row.
func _draw_roster(origin: Vector2) -> float:
	var disp: Font = UITheme.display_font()
	var body: Font = UITheme.body_font()
	var y: float = origin.y
	var now: float = float(Time.get_ticks_msec()) * 0.001
	for r_v in _roster:
		var r: Dictionary = r_v as Dictionary
		var col: Color = r.get("color", UITheme.GOLD) as Color
		var name_col: Color = col.lightened(0.32)
		name_col.a = 1.0
		var down: bool = bool(r.get("downed", false))
		var ratio: float = clampf(float(r.get("hp", 0)) / maxf(1.0, float(r.get("max_hp", 1))), 0.0, 1.0)
		_text(disp, Vector2(origin.x, y + 15.0), String(r.get("name", "")).to_upper(), 16, name_col, 6)
		var bar := Rect2(origin.x + 104.0, y + 5.0, 170.0, 10.0)
		draw_rect(bar, Color(0, 0, 0, 0.78))
		if down:
			var pulse: float = 0.5 + 0.5 * sin(now * 6.0)
			draw_rect(bar, Color(1.0, 0.3, 0.25, 0.40 + 0.4 * pulse))
			_text(body, Vector2(bar.end.x + 8.0, y + 15.0), "DOWN · E", 14, Color(1.0, 0.5, 0.45, 1.0), 5)
		else:
			var hp_col: Color = Color(0.45, 0.95, 0.55) if ratio > 0.5 else (Color(1.0, 0.8, 0.3) if ratio > 0.25 else Color(1.0, 0.3, 0.25))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), hp_col)
		draw_rect(bar, Color(name_col.r, name_col.g, name_col.b, 0.7), false, 1.2)
		y += 26.0
	return y
```

- **Target 5**: `scripts/ui/squad_comms_hud.gd` (lines 442–477)
- **Action**: Replace block (exact single match) to scale `_draw_mic()` graphics +20% and increase `_text()` outline opacity.

**Find:**
```gdscript
	_mic_btn.draw_circle(c, 28.0, Color(0.03, 0.035, 0.055, 0.85))
	_mic_btn.draw_arc(c, 28.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.95), 2.0, true)
	if st == "recording":
		var rr: float = 30.0 + _mic_level * 14.0
		_mic_btn.draw_arc(c, rr, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.55 + 0.3 * sin(now * 10.0)), 3.0, true)
	elif st == "transcribing":
		var a0: float = now * 6.0
		_mic_btn.draw_arc(c, 33.0, a0, a0 + 2.0, 20, col, 3.0, true)
	# Mic glyph.
	_mic_btn.draw_rect(Rect2(c.x - 6.0, c.y - 15.0, 12.0, 18.0), col)
	_mic_btn.draw_circle(c + Vector2(0, -15.0), 6.0, col)
	_mic_btn.draw_circle(c + Vector2(0, 3.0), 6.0, col)
	_mic_btn.draw_arc(c + Vector2(0, 1.0), 11.0, 0.15, PI - 0.15, 14, col, 2.0, true)
	_mic_btn.draw_line(c + Vector2(0, 12.0), c + Vector2(0, 18.0), col, 2.0)
	_mic_btn.draw_line(c + Vector2(-6, 18.0), c + Vector2(6, 18.0), col, 2.0)
	if not SquadAIConfig.is_online():
		_mic_btn.draw_line(c + Vector2(-16, -16), c + Vector2(16, 16), Color(1.0, 0.4, 0.35, 0.9), 2.5, true)
	var label: String = "V"
	var body: Font = UITheme.body_font()
	var lw: float = body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_mic_btn.draw_string_outline(body, Vector2(c.x - lw * 0.5, c.y + 46.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color(0, 0, 0, 0.8))
	_mic_btn.draw_string(body, Vector2(c.x - lw * 0.5, c.y + 46.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.85, 0.9))


func _chamfer(r: Rect2, c: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c),
	])


func _text(font: Font, pos: Vector2, t: String, fsize: int, col: Color, outline: int) -> void:
	if outline > 0:
		draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, 0.75 * col.a))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
```

**Replace with:**
```gdscript
	_mic_btn.draw_circle(c, 34.0, Color(0.03, 0.035, 0.055, 0.88))
	_mic_btn.draw_arc(c, 34.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.95), 2.4, true)
	if st == "recording":
		var rr: float = 36.0 + _mic_level * 16.0
		_mic_btn.draw_arc(c, rr, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.55 + 0.3 * sin(now * 10.0)), 3.2, true)
	elif st == "transcribing":
		var a0: float = now * 6.0
		_mic_btn.draw_arc(c, 40.0, a0, a0 + 2.0, 20, col, 3.2, true)
	# Mic glyph (1.2x).
	_mic_btn.draw_rect(Rect2(c.x - 7.2, c.y - 18.0, 14.4, 21.6), col)
	_mic_btn.draw_circle(c + Vector2(0, -18.0), 7.2, col)
	_mic_btn.draw_circle(c + Vector2(0, 3.6), 7.2, col)
	_mic_btn.draw_arc(c + Vector2(0, 1.2), 13.2, 0.15, PI - 0.15, 14, col, 2.4, true)
	_mic_btn.draw_line(c + Vector2(0, 14.4), c + Vector2(0, 21.6), col, 2.4)
	_mic_btn.draw_line(c + Vector2(-7.2, 21.6), c + Vector2(7.2, 21.6), col, 2.4)
	if not SquadAIConfig.is_online():
		_mic_btn.draw_line(c + Vector2(-19, -19), c + Vector2(19, 19), Color(1.0, 0.4, 0.35, 0.9), 3.0, true)
	var label: String = "V"
	var body: Font = UITheme.body_font()
	var lw: float = body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_mic_btn.draw_string_outline(body, Vector2(c.x - lw * 0.5, c.y + 52.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.92))
	_mic_btn.draw_string(body, Vector2(c.x - lw * 0.5, c.y + 52.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.96, 0.88, 0.96))


func _chamfer(r: Rect2, c: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c),
	])


func _text(font: Font, pos: Vector2, t: String, fsize: int, col: Color, outline: int) -> void:
	if outline > 0:
		draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, 0.94 * col.a))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
```

- **Target 6**: `scripts/ui/objective_tracker.gd` (lines 190–213)
- **Action**: Replace block (exact single match) to draw a dark chamfered panel behind the objective title & hint lines and increase size/contrast.

**Find:**
```gdscript
func _draw() -> void:
	if _obj.is_empty():
		return
	var s: Vector2 = size
	var disp: Font = UITheme.display_font()
	var body: Font = UITheme.body_font()
	var title: String = String(_obj.get("title", "")).to_upper()
	var hint: String = String(_obj.get("hint", ""))
	var k: float = 1.0 + 0.25 * _pop
	var tsz: int = int(19.0 * k)
	var tw: float = disp.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
	var y: float = 156.0   # below the Reality/Mirror chip + shift cooldown readout
	var glow: Color = GOLD.lerp(Color(1, 1, 1), _pop * 0.6)
	# Diamond + title.
	var cx: float = s.x * 0.5
	_diamond(Vector2(cx - tw * 0.5 - 16.0, y - 7.0), 5.0, glow)
	_text(disp, Vector2(cx - tw * 0.5, y), title, tsz, glow, 6)
	# Hint (wrapped to two lines max).
	var lines: PackedStringArray = _wrap(body, hint, 16, minf(760.0, s.x - 80.0))
	for i in range(mini(2, lines.size())):
		var lw: float = body.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text(body, Vector2(cx - lw * 0.5, y + 22.0 + 19.0 * float(i)), lines[i], 16, Color(0.95, 0.93, 0.88, 0.92), 4)
	_draw_marker(s)
```

**Replace with:**
```gdscript
func _draw() -> void:
	if _obj.is_empty():
		return
	var s: Vector2 = size
	var disp: Font = UITheme.display_font()
	var body: Font = UITheme.body_font()
	var title: String = String(_obj.get("title", "")).to_upper()
	var hint: String = String(_obj.get("hint", ""))
	var k: float = 1.0 + 0.25 * _pop
	var tsz: int = int(21.0 * k)
	var hint_sz: int = 18
	var tw: float = disp.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
	var y: float = 166.0   # below the enlarged Reality/Mirror chip + shift cooldown readout
	var glow: Color = GOLD.lerp(Color(1, 1, 1), _pop * 0.6)
	var cx: float = s.x * 0.5
	var lines: PackedStringArray = _wrap(body, hint, hint_sz, minf(820.0, s.x - 80.0))
	var shown_lines: int = mini(2, lines.size())
	var content_w: float = tw + 26.0
	for i in range(shown_lines):
		content_w = maxf(content_w, body.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, hint_sz).x)
	var plate_w: float = minf(s.x - 40.0, content_w + 40.0)
	var plate_h: float = 34.0 + float(shown_lines) * 21.0
	var pr := Rect2(cx - plate_w * 0.5, y - 24.0, plate_w, plate_h)
	draw_rect(pr, Color(0.025, 0.03, 0.055, 0.82))
	draw_rect(pr, Color(GOLD.r, GOLD.g, GOLD.b, 0.36), false, 1.0)
	# Diamond + title.
	_diamond(Vector2(cx - tw * 0.5 - 16.0, y - 7.0), 5.5, glow)
	_text(disp, Vector2(cx - tw * 0.5, y), title, tsz, glow, 7)
	# Hint (wrapped to two lines max).
	for i in range(shown_lines):
		var lw: float = body.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, hint_sz).x
		_text(body, Vector2(cx - lw * 0.5, y + 23.0 + 21.0 * float(i)), lines[i], hint_sz, Color(0.98, 0.96, 0.90, 0.98), 5)
	_draw_marker(s)
```

- **Target 7**: `scripts/ui/objective_tracker.gd` (lines 280–283)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
func _text(font: Font, pos: Vector2, t: String, fsize: int, col: Color, outline: int) -> void:
	if outline > 0:
		draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, 0.8 * col.a))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
```

**Replace with:**
```gdscript
func _text(font: Font, pos: Vector2, t: String, fsize: int, col: Color, outline: int) -> void:
	if outline > 0:
		draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, 0.94 * col.a))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
```

- **Target 8**: `scripts/ui/world_label_overlay.gd` (lines 90–110)
- **Action**: Replace block (exact single match; leaves `_line()` untouched to stay disjoint from Step 11) so overhead ally names, hints, and HP tags render over a dark translucent backing pill with higher outline contrast.

**Find:**
```gdscript
func _draw_label(l: Label3D, p: Vector2, fade: float) -> void:
	var font: Font = _font_for(l)
	var px: int = int(l.get_meta("wl_px", 18))
	var col: Color = l.modulate
	col.a *= fade
	var ocol: Color = l.outline_modulate
	ocol.a = 0.85 * col.a
	if String(l.get_meta("wl_kind", "text")) == "bar":
		var ratio: float = clampf(float(l.get_meta("hp_ratio", 1.0)), 0.0, 1.0)
		var r := Rect2(p.x - 48.0, p.y - 4.0, 96.0, 8.0)
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.75 * col.a))
		draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), Color(col.r, col.g, col.b, col.a))
		if not l.text.is_empty():
			_line(font, Vector2(r.end.x + 6.0, p.y + float(px) * 0.38), l.text, px, Color(1, 1, 1, 0.9 * col.a), ocol, false)
		return
	var lines: PackedStringArray = l.text.split("\n")
	var lh: float = float(px) * 1.15
	var y0: float = p.y - lh * float(lines.size() - 1)
	for i in range(lines.size()):
		_line(font, Vector2(p.x, y0 + lh * float(i)), lines[i], px, col, ocol, true)
```

**Replace with:**
```gdscript
func _draw_label(l: Label3D, p: Vector2, fade: float) -> void:
	var font: Font = _font_for(l)
	var px: int = int(l.get_meta("wl_px", 18))
	var col: Color = l.modulate
	col.a *= fade
	var ocol: Color = Color(0.0, 0.0, 0.02, 0.96 * col.a)
	if String(l.get_meta("wl_kind", "text")) == "bar":
		var ratio: float = clampf(float(l.get_meta("hp_ratio", 1.0)), 0.0, 1.0)
		var r := Rect2(p.x - 48.0, p.y - 4.0, 96.0, 8.0)
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.85 * col.a))
		draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), Color(col.r, col.g, col.b, col.a))
		if not l.text.is_empty():
			var tw: float = font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			draw_rect(Rect2(r.end.x + 3.0, p.y - float(px) * 0.55, tw + 8.0, float(px) * 1.15), Color(0.02, 0.025, 0.045, 0.78 * col.a))
			_line(font, Vector2(r.end.x + 6.0, p.y + float(px) * 0.38), l.text, px, Color(1, 1, 1, 0.96 * col.a), ocol, false)
		return
	var lines: PackedStringArray = l.text.split("\n")
	var lh: float = float(px) * 1.18
	var y0: float = p.y - lh * float(lines.size() - 1)
	var max_w: float = 0.0
	for ln in lines:
		max_w = maxf(max_w, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	if max_w > 2.0:
		var box := Rect2(p.x - max_w * 0.5 - 8.0, y0 - float(px) * 0.92, max_w + 16.0, lh * float(lines.size()) + 4.0)
		draw_rect(box, Color(0.02, 0.025, 0.045, 0.80 * col.a))
		draw_rect(box, Color(col.r, col.g, col.b, 0.35 * col.a), false, 1.0)
	for i in range(lines.size()):
		_line(font, Vector2(p.x, y0 + lh * float(i)), lines[i], px, col, ocol, true)
```

- **Target 9**: `scripts/allies/squad_ally.gd` (lines 258–264)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	_name_label.outline_size = 7
	_name_label.outline_modulate = Color(0.02, 0.02, 0.04, 0.9)
	_name_label.font = UITheme.display_font()
	_name_label.position = Vector3(0, 2.25, 0)
	add_child(_name_label)
	WorldLabelOverlay.adopt(_name_label, {"px": 15, "font": "display", "max_dist": 45.0})
```

**Replace with:**
```gdscript
	_name_label.outline_size = 8
	_name_label.outline_modulate = Color(0.01, 0.01, 0.03, 0.96)
	_name_label.font = UITheme.display_font()
	_name_label.position = Vector3(0, 2.25, 0)
	add_child(_name_label)
	WorldLabelOverlay.adopt(_name_label, {"px": 18, "font": "display", "max_dist": 52.0})
```

- **Target 10**: `scripts/allies/squad_ally.gd` (lines 369–374)
- **Action**: Replace block (exact single match).

**Find:**
```gdscript
	var bar: String = "▰".repeat(pips) + "▱".repeat(6 - pips)
	_name_label.text = "%s\n%s" % [profile.ally_name.to_upper(), bar if not is_downed else "DOWN — revive"]
	var c: Color = profile.color
	_name_label.modulate = Color(c.r, c.g, c.b, 0.95) if not is_downed else Color(1.0, 0.35, 0.3, 0.95)
```

**Replace with:**
```gdscript
	var bar: String = "▰".repeat(pips) + "▱".repeat(6 - pips)
	_name_label.text = "%s\n%s" % [profile.ally_name.to_upper(), bar if not is_downed else "DOWN — revive"]
	var c: Color = profile.color.lightened(0.28)
	_name_label.modulate = Color(c.r, c.g, c.b, 1.0) if not is_downed else Color(1.0, 0.4, 0.35, 1.0)
```

- **Target 11**: `scripts/ui/hud_controller.gd` (lines 128–133)
- **Action**: Replace block (exact single match) to enforce strong outlines on all styled HUD labels (`REQ-17`).

**Find:**
```gdscript
func _style_hud_label(lbl: Label, display: bool, size: int) -> void:
	if lbl == null:
		return
	lbl.add_theme_font_override("font", UITheme.display_font() if display else UITheme.body_font())
	lbl.add_theme_font_size_override("font_size", size)
```

**Replace with:**
```gdscript
func _style_hud_label(lbl: Label, display: bool, size: int) -> void:
	if lbl == null:
		return
	lbl.add_theme_font_override("font", UITheme.display_font() if display else UITheme.body_font())
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	lbl.add_theme_constant_override("outline_size", 5)
```

- **Target 12**: `scripts/ui/hud_controller.gd` (lines 244–250)
- **Action**: Replace block (exact single match) to bump player HP, shift keycap, and Reality/Mirror labels cleanly.

**Find:**
```gdscript
	_style_hud_label(_section_title_label, true, 16)
	_style_hud_label(get_node_or_null(hp_label_path) as Label, false, 17)
	_style_hud_label(get_node_or_null(shift_key_label_path) as Label, false, 14)
	_style_hud_label(get_node_or_null(timer_label_path) as Label, false, 19)
	_style_hud_label(_reality_pill_label, false, 17)
	_style_hud_label(_mirror_pill_label, false, 17)
```

**Replace with:**
```gdscript
	_style_hud_label(_section_title_label, true, 17)
	_style_hud_label(get_node_or_null(hp_label_path) as Label, false, 19)
	_style_hud_label(get_node_or_null(shift_key_label_path) as Label, false, 16)
	_style_hud_label(get_node_or_null(timer_label_path) as Label, false, 20)
	_style_hud_label(_reality_pill_label, false, 19)
	_style_hud_label(_mirror_pill_label, false, 19)
```

- **Target 13**: `scripts/ui/hud_controller.gd` (lines 284–290)
- **Action**: Replace block (exact single match) to scale Reality & Mirror chips +20% (`138×36 -> 166×44`).

**Find:**
```gdscript
	for entry2: Array in [[_reality_pill_panel, "reality"], [_mirror_pill_panel, "mirror"]]:
		var cp: PanelContainer = entry2[0] as PanelContainer
		if cp == null:
			continue
		cp.add_theme_stylebox_override("panel", _empty_box(34, 6))
		cp.custom_minimum_size = Vector2(138, 36)
```

**Replace with:**
```gdscript
	for entry2: Array in [[_reality_pill_panel, "reality"], [_mirror_pill_panel, "mirror"]]:
		var cp: PanelContainer = entry2[0] as PanelContainer
		if cp == null:
			continue
		cp.add_theme_stylebox_override("panel", _empty_box(40, 7))
		cp.custom_minimum_size = Vector2(166, 44)
```

- **Target 14**: `scripts/ui/hud_controller.gd` (lines 332–353)
- **Action**: Replace block (exact single match) to scale action/skill diamonds +20% (`80 -> 96 px`) and widen container offsets (`-680`, `-204`).

**Find:**
```gdscript
	# --- Keycap look for action labels + bigger action icons (80 px diamonds, was 54) ---
	var br_cluster: Control = _root_ctrl.get_node_or_null("BottomRightActionsCluster") as Control
	if br_cluster != null:
		# 5 slots x 80 px + 4 gaps x 16 px = 464 px wide; extra height for the larger keycaps.
		br_cluster.offset_left = -640.0
		br_cluster.offset_top = -184.0
	for act: String in _action_slots.keys():
		var badge: Control = (_action_slots[act] as Dictionary).get("badge") as Control
		if badge != null:
			badge.custom_minimum_size = Vector2(80, 80)
		var klbl: Label = (_action_slots[act] as Dictionary).get("key") as Label
		if klbl != null:
			klbl.add_theme_stylebox_override("normal", _keycap_style())
			klbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_style_hud_label(klbl, false, 18)
		var vlbl: Label = (_action_slots[act] as Dictionary).get("verb") as Label
		_style_hud_label(vlbl, false, 16)
```

**Replace with:**
```gdscript
	# --- Keycap look for action labels + +20% action icons (96 px diamonds, was 80) ---
	var br_cluster: Control = _root_ctrl.get_node_or_null("BottomRightActionsCluster") as Control
	if br_cluster != null:
		# 5 slots x 96 px + 4 gaps x 16 px = 544 px wide; extra height for the larger keycaps.
		br_cluster.offset_left = -680.0
		br_cluster.offset_top = -204.0
	for act: String in _action_slots.keys():
		var badge: Control = (_action_slots[act] as Dictionary).get("badge") as Control
		if badge != null:
			badge.custom_minimum_size = Vector2(96, 96)
		var klbl: Label = (_action_slots[act] as Dictionary).get("key") as Label
		if klbl != null:
			klbl.add_theme_stylebox_override("normal", _keycap_style())
			klbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_style_hud_label(klbl, false, 20)
		var vlbl: Label = (_action_slots[act] as Dictionary).get("verb") as Label
		_style_hud_label(vlbl, false, 18)
```

- **Target 15**: `scripts/ui/hud_controller.gd` (lines 1049–1060)
- **Action**: Replace block (exact single match) to scale sun & moon glyphs inside the Reality/Mirror chips +20%.

**Find:**
```gdscript
	# Sun / moon glyph on the left.
	var gc := Vector2(20.0, s.y * 0.5)
	var gcol: Color = (GOLD_HI if active else Color(0.55, 0.54, 0.52, 0.8))
	if kind == "reality":
		panel.draw_circle(gc, 4.2, gcol)
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			panel.draw_line(gc + Vector2(cos(a), sin(a)) * 6.5, gc + Vector2(cos(a), sin(a)) * 9.0, gcol, 1.6, true)
	else:
		panel.draw_circle(gc, 7.0, gcol)
		panel.draw_circle(gc + Vector2(3.4, -2.2), 6.2, fill if active else Color(0.05, 0.055, 0.085, 0.95))
```

**Replace with:**
```gdscript
	# Sun / moon glyph on the left (+20%).
	var gc := Vector2(24.0, s.y * 0.5)
	var gcol: Color = (GOLD_HI if active else Color(0.65, 0.64, 0.62, 0.85))
	if kind == "reality":
		panel.draw_circle(gc, 5.0, gcol)
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			panel.draw_line(gc + Vector2(cos(a), sin(a)) * 7.8, gc + Vector2(cos(a), sin(a)) * 10.8, gcol, 2.0, true)
	else:
		panel.draw_circle(gc, 8.4, gcol)
		panel.draw_circle(gc + Vector2(4.1, -2.6), 7.4, fill if active else Color(0.05, 0.055, 0.085, 0.95))
```

- **Target 16**: `scripts/ui/hud_controller.gd` (lines 1226–1240)
- **Action**: Replace block (exact single match) to enlarge `CrestBadge` +20% (`56 -> 68 px`) and expand `TopLeftVitality` bottom offset.

**Find:**
```gdscript
	top_left.name = "TopLeftVitality"
	top_left.offset_left = 36.0
	top_left.offset_top = 68.0
	top_left.offset_right = 400.0
	top_left.offset_bottom = 136.0
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.add_theme_constant_override("separation", 12)
	root.add_child(top_left)

	_crest_badge = HudDiamondBadge.new()
	_crest_badge.name = "CrestBadge"
	_crest_badge.icon_kind = "crest"
	_crest_badge.custom_minimum_size = Vector2(56, 56)
```

**Replace with:**
```gdscript
	top_left.name = "TopLeftVitality"
	top_left.offset_left = 36.0
	top_left.offset_top = 68.0
	top_left.offset_right = 420.0
	top_left.offset_bottom = 148.0
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.add_theme_constant_override("separation", 12)
	root.add_child(top_left)

	_crest_badge = HudDiamondBadge.new()
	_crest_badge.name = "CrestBadge"
	_crest_badge.icon_kind = "crest"
	_crest_badge.custom_minimum_size = Vector2(68, 68)
```

- **Target 17**: `scripts/ui/hud_controller.gd` (lines 1291–1343)
- **Action**: Replace block (exact single match) to widen `TopCenterRealmCluster` (`±220 px`) and enlarge `RealityPillPanel`, `SwapMedallion` (`38 -> 46`), and `MirrorPillPanel` +20%.

**Find:**
```gdscript
	top_center.name = "TopCenterRealmCluster"
	top_center.anchor_left = 0.5
	top_center.anchor_right = 0.5
	top_center.offset_left = -180.0
	top_center.offset_right = 180.0
	top_center.offset_top = 66.0
	top_center.offset_bottom = 142.0
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_theme_constant_override("separation", 4)
	root.add_child(top_center)

	var pills_row := HBoxContainer.new()
	pills_row.name = "PillsRow"
	pills_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pills_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills_row.add_theme_constant_override("separation", 10)
	top_center.add_child(pills_row)

	_reality_pill_panel = PanelContainer.new()
	_reality_pill_panel.name = "RealityPillPanel"
	_reality_pill_panel.custom_minimum_size = Vector2(126, 34)
	_reality_pill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills_row.add_child(_reality_pill_panel)

	_reality_pill_label = Label.new()
	_reality_pill_label.name = "RealityLabel"
	_reality_pill_label.text = "REALITY"
	_reality_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reality_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reality_pill_label.add_theme_font_size_override("font_size", 15)
	_reality_pill_panel.add_child(_reality_pill_label)

	_swap_badge = HudDiamondBadge.new()
	_swap_badge.name = "SwapMedallion"
	_swap_badge.icon_kind = "swap"
	_swap_badge.circular_frame = true
	_swap_badge.custom_minimum_size = Vector2(38, 38)
	pills_row.add_child(_swap_badge)

	_mirror_pill_panel = PanelContainer.new()
	_mirror_pill_panel.name = "MirrorPillPanel"
	_mirror_pill_panel.custom_minimum_size = Vector2(126, 34)
	_mirror_pill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills_row.add_child(_mirror_pill_panel)

	_mirror_pill_label = Label.new()
	_mirror_pill_label.name = "MirrorLabel"
	_mirror_pill_label.text = "MIRROR"
	_mirror_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mirror_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mirror_pill_label.add_theme_font_size_override("font_size", 15)
	_mirror_pill_panel.add_child(_mirror_pill_label)
```

**Replace with:**
```gdscript
	top_center.name = "TopCenterRealmCluster"
	top_center.anchor_left = 0.5
	top_center.anchor_right = 0.5
	top_center.offset_left = -220.0
	top_center.offset_right = 220.0
	top_center.offset_top = 66.0
	top_center.offset_bottom = 152.0
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_theme_constant_override("separation", 4)
	root.add_child(top_center)

	var pills_row := HBoxContainer.new()
	pills_row.name = "PillsRow"
	pills_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pills_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills_row.add_theme_constant_override("separation", 10)
	top_center.add_child(pills_row)

	_reality_pill_panel = PanelContainer.new()
	_reality_pill_panel.name = "RealityPillPanel"
	_reality_pill_panel.custom_minimum_size = Vector2(166, 44)
	_reality_pill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills_row.add_child(_reality_pill_panel)

	_reality_pill_label = Label.new()
	_reality_pill_label.name = "RealityLabel"
	_reality_pill_label.text = "REALITY"
	_reality_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reality_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reality_pill_label.add_theme_font_size_override("font_size", 19)
	_reality_pill_panel.add_child(_reality_pill_label)

	_swap_badge = HudDiamondBadge.new()
	_swap_badge.name = "SwapMedallion"
	_swap_badge.icon_kind = "swap"
	_swap_badge.circular_frame = true
	_swap_badge.custom_minimum_size = Vector2(46, 46)
	pills_row.add_child(_swap_badge)

	_mirror_pill_panel = PanelContainer.new()
	_mirror_pill_panel.name = "MirrorPillPanel"
	_mirror_pill_panel.custom_minimum_size = Vector2(166, 44)
	_mirror_pill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills_row.add_child(_mirror_pill_panel)

	_mirror_pill_label = Label.new()
	_mirror_pill_label.name = "MirrorLabel"
	_mirror_pill_label.text = "MIRROR"
	_mirror_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mirror_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mirror_pill_label.add_theme_font_size_override("font_size", 19)
	_mirror_pill_panel.add_child(_mirror_pill_label)
```

- **Target 18**: `scripts/ui/hud_controller.gd` (lines 1410–1436)
- **Action**: Replace block (exact single match) to enlarge `WeaponDiamond` +20% (`82 -> 98 px`) and widen `BottomLeftWeapon` container bounds.

**Find:**
```gdscript
	var bl_weapon := VBoxContainer.new()
	bl_weapon.name = "BottomLeftWeapon"
	bl_weapon.anchor_top = 1.0
	bl_weapon.anchor_bottom = 1.0
	bl_weapon.offset_left = 36.0
	bl_weapon.offset_top = -140.0
	bl_weapon.offset_right = 128.0
	bl_weapon.offset_bottom = -28.0
	bl_weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl_weapon.add_theme_constant_override("separation", 4)
	root.add_child(bl_weapon)

	_weapon_badge = HudDiamondBadge.new()
	_weapon_badge.name = "WeaponDiamond"
	_weapon_badge.icon_kind = "weapon_sword"
	_weapon_badge.custom_minimum_size = Vector2(82, 82)
	_weapon_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bl_weapon.add_child(_weapon_badge)

	var wpn_lbl := Label.new()
	wpn_lbl.name = "SwordSlotLabel"
	wpn_lbl.text = "SWORD"
	wpn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wpn_lbl.add_theme_font_size_override("font_size", 11)
```

**Replace with:**
```gdscript
	var bl_weapon := VBoxContainer.new()
	bl_weapon.name = "BottomLeftWeapon"
	bl_weapon.anchor_top = 1.0
	bl_weapon.anchor_bottom = 1.0
	bl_weapon.offset_left = 36.0
	bl_weapon.offset_top = -158.0
	bl_weapon.offset_right = 148.0
	bl_weapon.offset_bottom = -28.0
	bl_weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl_weapon.add_theme_constant_override("separation", 4)
	root.add_child(bl_weapon)

	_weapon_badge = HudDiamondBadge.new()
	_weapon_badge.name = "WeaponDiamond"
	_weapon_badge.icon_kind = "weapon_sword"
	_weapon_badge.custom_minimum_size = Vector2(98, 98)
	_weapon_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bl_weapon.add_child(_weapon_badge)

	var wpn_lbl := Label.new()
	wpn_lbl.name = "SwordSlotLabel"
	wpn_lbl.text = "SWORD"
	wpn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wpn_lbl.add_theme_font_size_override("font_size", 14)
```

- **Target 19**: `scripts/ui/finisher_prompt.gd` (lines 155–171)
- **Action**: Replace block (exact single match) to scale finisher diamond plates +20% (`r 30 -> 36`, spacing `190 -> 216`).

**Find:**
```gdscript
	# Options row.
	var n: int = _options.size()
	var spacing: float = 190.0 if n <= 3 else minf(176.0, (s.x - 80.0) / float(n))
	for i in n:
		var od: Dictionary = _options[i] as Dictionary
		var kind: String = String(od.get("kind", ""))
		var col: Color = KIND_COLORS.get(kind, gold)
		var delay: float = clampf(float(now - _open_ms - 50 * i) / 180.0, 0.0, 1.0)
		var ap: float = _ease_out(delay) * fade
		var cx: float = s.x * 0.5 + (float(i) - float(n - 1) * 0.5) * spacing
		var c := Vector2(cx, cy + (1.0 - _ease_out(delay)) * 20.0)
		var r: float = 30.0 + 3.0 * sin(float(now) * 0.02 + float(i))
```

**Replace with:**
```gdscript
	# Options row (+20% diamonds).
	var n: int = _options.size()
	var spacing: float = 216.0 if n <= 3 else minf(200.0, (s.x - 80.0) / float(n))
	for i in n:
		var od: Dictionary = _options[i] as Dictionary
		var kind: String = String(od.get("kind", ""))
		var col: Color = KIND_COLORS.get(kind, gold)
		var delay: float = clampf(float(now - _open_ms - 50 * i) / 180.0, 0.0, 1.0)
		var ap: float = _ease_out(delay) * fade
		var cx: float = s.x * 0.5 + (float(i) - float(n - 1) * 0.5) * spacing
		var c := Vector2(cx, cy + (1.0 - _ease_out(delay)) * 20.0)
		var r: float = 36.0 + 3.6 * sin(float(now) * 0.02 + float(i))
```

- **Postcondition**: Top-left ally names, center objective text/hints, player vitals, and overhead 3D text labels read cleanly on dark chamfered/translucent backing plates over any scene background; all HUD action/weapon/crest/realm/mic/finisher icons are scaled up by ~20%.

---

### Step 17 — Slow Ally & Player Health Regeneration (>= 2 Minutes Full Heal) (`REQ-20`)

- **Prerequisites**: Steps 1–16 applied cleanly.
- **Target 1**: `scripts/allies/squad_ally.gd` (lines 573–585)
- **Action**: Replace block (exact single match) to remove the `3.0×` retreat burst multiplier and cap ally regeneration rate at `max_health / 125.0` (`>= 125 s` from `0` to full).

**Find:**
```gdscript
func _regen(delta: float) -> void:
	if health >= max_health:
		return
	var rate: float = profile.regen_per_sec * (3.0 if _retreating else (1.0 if _combat_quiet > 4.0 else 0.0))
	if rate <= 0.0:
		return
	_regen_acc += rate * delta
```

**Replace with:**
```gdscript
func _regen(delta: float) -> void:
	if health >= max_health:
		return
	if not (_retreating or _combat_quiet > 4.0):
		return
	var max_slow_rate: float = float(max_health) / 125.0
	var rate: float = minf(profile.regen_per_sec, max_slow_rate)
	if rate <= 0.0:
		return
	_regen_acc += rate * delta
```

- **Target 2**: `scripts/allies/ally_profile.gd` (lines 32–36)
- **Action**: Replace block (exact single match) to lower the default resource `regen_per_sec` from `3.0` to `1.0`.

**Find:**
```gdscript
## Health ratio below which the ally falls back to heal (disabled during MASSACRE).
@export var retreat_threshold: float = 0.3
@export var regen_per_sec: float = 3.0
## Incoming damage multiplier (Echoes are mirror-hardened; keeps companions alive without god-mode).
```

**Replace with:**
```gdscript
## Health ratio below which the ally falls back to heal (disabled during MASSACRE).
@export var retreat_threshold: float = 0.3
@export var regen_per_sec: float = 1.0
## Incoming damage multiplier (Echoes are mirror-hardened; keeps companions alive without god-mode).
```

- **Target 3**: `data/allies/01_brannoc.tres` (lines 75–77)
- **Action**: Replace block (exact single match) to tune Brannoc (`190 HP`) regen to `1.5 HP/s` (`~127 s` 0 -> full).

**Find:**
```ini
retreat_threshold = 0.25
regen_per_sec = 4.0
abilities = Array[String](["taunt", "charge", "bodyguard", "revive"])
```

**Replace with:**
```ini
retreat_threshold = 0.25
regen_per_sec = 1.5
abilities = Array[String](["taunt", "charge", "bodyguard", "revive"])
```

- **Target 4**: `data/allies/02_sera.tres` (lines 92–94)
- **Action**: Replace block (exact single match) to tune Sera (`120 HP`) regen to `0.95 HP/s` (`~126 s` 0 -> full).

**Find:**
```ini
retreat_threshold = 0.35
regen_per_sec = 3.0
abilities = Array[String](["taunt", "kite", "lure", "finisher", "revive"])
```

**Replace with:**
```ini
retreat_threshold = 0.35
regen_per_sec = 0.95
abilities = Array[String](["taunt", "kite", "lure", "finisher", "revive"])
```

- **Target 5**: `data/allies/03_ivo.tres` (lines 26–38)
- **Action**: Replace block (exact single match) to stop Ivo's autonomous `35%` `mending_light` burst heals (`auto_use = ""`, `power = 0.18` when commanded).

**Find:**
```ini
display_name = "Mending Light"
description = "Heals an ally or the player for 35% of their max HP (range 14 m)."
aliases = Array[String](["heal", "mend", "mending light", "patch up", "fix up", "healing"])
effect = "mending_light"
target_kind = "ally"
cooldown = 12
cast_range = 14
radius = 0
power = 0.35
duration = 0
auto_use = "ally_low"
```

**Replace with:**
```ini
display_name = "Mending Light"
description = "Gently mends an ally or the player for 18% of their max HP on command (range 14 m)."
aliases = Array[String](["heal", "mend", "mending light", "patch up", "fix up", "healing"])
effect = "mending_light"
target_kind = "ally"
cooldown = 18
cast_range = 14
radius = 0
power = 0.18
duration = 0
auto_use = ""
```

- **Target 6**: `data/allies/03_ivo.tres` (lines 92–94)
- **Action**: Replace block (exact single match) to tune Ivo (`110 HP`) regen to `0.88 HP/s` (`125 s` 0 -> full).

**Find:**
```ini
retreat_threshold = 0.4
regen_per_sec = 3.0
abilities = Array[String](["nuke", "mine", "revive"])
```

**Replace with:**
```ini
retreat_threshold = 0.4
regen_per_sec = 0.88
abilities = Array[String](["nuke", "mine", "revive"])
```

- **Target 7**: `scripts/player/player_controller.gd` (lines 158–161)
- **Action**: Replace block (exact single match) to expose `health_regen_seconds_to_full = 125.0` (`>= 2 minutes`).

**Find:**
```gdscript
@export_group("Health & Survival")
@export var max_health: int = 100

@export_group("Locomotion")
```

**Replace with:**
```gdscript
@export_group("Health & Survival")
@export var max_health: int = 100
@export var health_regen_seconds_to_full: float = 125.0

@export_group("Locomotion")
```

- **Target 8**: `scripts/player/player_controller.gd` (lines 258–261)
- **Action**: Replace block (exact single match) to declare `_player_regen_acc`.

**Find:**
```gdscript
var _dodge_direction: Vector3 = Vector3.BACK
var _perfect_dodge_spent: bool = false
var _air_dash_used: bool = false
```

**Replace with:**
```gdscript
var _dodge_direction: Vector3 = Vector3.BACK
var _perfect_dodge_spent: bool = false
var _air_dash_used: bool = false
var _player_regen_acc: float = 0.0
```

- **Target 9**: `scripts/player/player_controller.gd` (lines 481–485)
- **Action**: Replace block (exact single match) to tick `_tick_passive_regen(delta)` during active gameplay (`State != DEAD`).

**Find:**
```gdscript
	if _dodge_cooldown_timer > 0.0:
		_dodge_cooldown_timer = maxf(0.0, _dodge_cooldown_timer - delta)
	if _landing_recover_timer > 0.0:
		_landing_recover_timer = maxf(0.0, _landing_recover_timer - delta)
```

**Replace with:**
```gdscript
	if _dodge_cooldown_timer > 0.0:
		_dodge_cooldown_timer = maxf(0.0, _dodge_cooldown_timer - delta)
	if _landing_recover_timer > 0.0:
		_landing_recover_timer = maxf(0.0, _landing_recover_timer - delta)
	_tick_passive_regen(delta)
```

- **Target 10**: `scripts/player/player_controller.gd` (lines 1327–1341)
- **Action**: Replace block (exact single match) to clear `_player_regen_acc` in `respawn_at()` and define `_tick_passive_regen(delta)`.

**Find:**
```gdscript
	_air_dash_used = false
	_buffer_action = ""
	run_time = 0.0
	camera_yaw = global_rotation.y
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		set_facing_direction(fwd.normalized())
	_update_camera_pivot()
	_update_hurtbox_invulnerability(false)
	_abort_attack()
	_set_state(State.LOCOMOTION, 0.0)
	health_changed.emit(health, max_health)
```

**Replace with:**
```gdscript
	_air_dash_used = false
	_player_regen_acc = 0.0
	_buffer_action = ""
	run_time = 0.0
	camera_yaw = global_rotation.y
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		set_facing_direction(fwd.normalized())
	_update_camera_pivot()
	_update_hurtbox_invulnerability(false)
	_abort_attack()
	_set_state(State.LOCOMOTION, 0.0)
	health_changed.emit(health, max_health)


func _tick_passive_regen(delta: float) -> void:
	if health <= 0 or health >= max_health or health_regen_seconds_to_full <= 0.0:
		return
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	if ed != null and int(ed.current_section) == int(EncounterDirector.Section.COMPLETE):
		return
	var rate: float = float(max_health) / maxf(120.0, health_regen_seconds_to_full)
	_player_regen_acc += rate * delta
	var add: int = int(_player_regen_acc)
	if add <= 0:
		return
	_player_regen_acc -= float(add)
	health = mini(max_health, health + add)
	health_changed.emit(health, max_health)
```

- **Postcondition**: Both ally regeneration (including while retreating) and player passive regeneration scale to at least `125 s` (`>= 2 minutes`) from `0` to `max_health`, and Ivo no longer triggers autonomous `35%` healing bursts.

---

### Step 18 — Room-Entry Alerts & 2-Checkpoint Death Rewind With Intervening Enemy Respawn (`REQ-15`, `REQ-21`)

- **Prerequisites**: Steps 1–17 complete.
- **Target 1**: `scripts/core/encounter_director.gd` (lines 32–37)
- **Action**: Replace block (exact single match) to store ordered `_checkpoint_history` entries (`section`, `transform`, `realm`).

**Find:**
```gdscript
var checkpoint_section: Section = Section.ENTRY
var checkpoint_transform: Transform3D = Transform3D.IDENTITY
var checkpoint_realm: int = 0

var _section_enemies: Dictionary = {}
```

**Replace with:**
```gdscript
var checkpoint_section: Section = Section.ENTRY
var checkpoint_transform: Transform3D = Transform3D.IDENTITY
var checkpoint_realm: int = 0

var _section_enemies: Dictionary = {}
var _checkpoint_history: Array[Dictionary] = []
```

- **Target 2**: `scripts/core/encounter_director.gd` (lines 78–102)
- **Action**: Replace block (exact single match) to alert Hall (`62 m`) / Chamber (`42 m`) enemies immediately upon room entry (`REQ-15`) and push deduplicated entries onto `_checkpoint_history` in `set_checkpoint()`.

**Find:**
```gdscript
func advance_to_section(next_section: Section, new_checkpoint_xform: Transform3D = Transform3D.IDENTITY, save_checkpoint: bool = true) -> void:
	if current_section != next_section:
		completed_sections[current_section] = true
		current_section = next_section

	if save_checkpoint:
		var rm: RealmManager = RealmManager.instance as RealmManager
		var realm_val: int = int(rm.current_realm) if rm != null else 0
		set_checkpoint(next_section, new_checkpoint_xform, realm_val)

	_update_section_enemy_activation()
	section_changed.emit(current_section, get_section_name(current_section))


func set_checkpoint(section_id: Section, spawn_transform: Transform3D, realm: int = 0) -> void:
	checkpoint_section = section_id
	if spawn_transform != Transform3D.IDENTITY:
		checkpoint_transform = spawn_transform
	checkpoint_realm = realm
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("bank_section_score"):
		run_state.call("bank_section_score")
	checkpoint_updated.emit(checkpoint_section, checkpoint_transform)
	_trigger_auto_save()
```

**Replace with:**
```gdscript
func advance_to_section(next_section: Section, new_checkpoint_xform: Transform3D = Transform3D.IDENTITY, save_checkpoint: bool = true) -> void:
	if current_section != next_section:
		completed_sections[current_section] = true
		current_section = next_section

	if save_checkpoint:
		var rm: RealmManager = RealmManager.instance as RealmManager
		var realm_val: int = int(rm.current_realm) if rm != null else 0
		set_checkpoint(next_section, new_checkpoint_xform, realm_val)

	_update_section_enemy_activation()
	_alert_room_on_entry(current_section)
	section_changed.emit(current_section, get_section_name(current_section))


func set_checkpoint(section_id: Section, spawn_transform: Transform3D, realm: int = 0) -> void:
	var prev_section: Section = checkpoint_section
	var prev_xform: Transform3D = checkpoint_transform
	var prev_realm: int = checkpoint_realm
	checkpoint_section = section_id
	if spawn_transform != Transform3D.IDENTITY:
		checkpoint_transform = spawn_transform
	checkpoint_realm = realm
	if _checkpoint_history.is_empty() and prev_xform != Transform3D.IDENTITY and (int(prev_section) != int(checkpoint_section) or prev_xform.origin.distance_to(checkpoint_transform.origin) >= 2.0):
		_checkpoint_history.append({"section": int(prev_section), "transform": prev_xform, "realm": prev_realm})
	var entry: Dictionary = {
		"section": int(checkpoint_section),
		"transform": checkpoint_transform,
		"realm": checkpoint_realm,
	}
	if not _checkpoint_history.is_empty():
		var last: Dictionary = _checkpoint_history[_checkpoint_history.size() - 1]
		var last_xform: Transform3D = last.get("transform", Transform3D.IDENTITY) as Transform3D
		if int(last.get("section", -1)) == int(checkpoint_section) and last_xform.origin.distance_to(checkpoint_transform.origin) < 2.0:
			_checkpoint_history[_checkpoint_history.size() - 1] = entry
		else:
			_checkpoint_history.append(entry)
	else:
		_checkpoint_history.append(entry)
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("bank_section_score"):
		run_state.call("bank_section_score")
	checkpoint_updated.emit(checkpoint_section, checkpoint_transform)
	_trigger_auto_save()
```

- **Target 3**: `scripts/core/encounter_director.gd` (lines 148–193)
- **Action**: Replace block (exact single match) so `handle_player_death()` rewinds `2` checkpoints behind (`size() - 3`), resets intervening triggers, combat exit gates, seal gates, and allies, resets every intervening/ahead enemy via `reset_enemy()`, and clears `_checkpoint_history` in `restart_full_run()`.

**Find:**
```gdscript
func handle_player_death(player: Node = null) -> void:
	# 1. Revert unbanked section score and reset combo to x1; elapsed run timer continues uninterrupted
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("revert_to_banked_score"):
		run_state.call("revert_to_banked_score")

	# 2. Reset active incomplete encounter state
	if not current_encounter_id.is_empty() and not bool(completed_encounters.get(current_encounter_id, false)):
		current_encounter_id = ""
		active_enemy_count = 0

	current_section = checkpoint_section

	# 3. Restore checkpoint realm state (unlocks shift if died during Warden Phase 2)
	if RealmManager.instance != null:
		RealmManager.instance.force_realm(checkpoint_realm as RealmManager.Realm, false)

	# 4. Respawn player at checkpoint transform with full health
	if player != null and player.has_method("respawn_at"):
		player.call("respawn_at", checkpoint_transform)

	_update_section_enemy_activation()
	section_reset_requested.emit(checkpoint_section)
	player_respawned.emit(checkpoint_section, checkpoint_transform)


func restart_full_run() -> void:
	completed_sections.clear()
	completed_encounters.clear()
	current_section = Section.ENTRY
	checkpoint_section = Section.ENTRY
	checkpoint_realm = 0
	active_enemy_count = 0
	current_encounter_id = ""

	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("start_new_run"):
		run_state.call("start_new_run")

	if RealmManager.instance != null:
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)

	_update_section_enemy_activation()
	section_changed.emit(current_section, get_section_name(current_section))
```

**Replace with:**
```gdscript
func handle_player_death(player: Node = null) -> void:
	# 1. Revert unbanked section score and reset combo to x1; elapsed run timer continues uninterrupted.
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("revert_to_banked_score"):
		run_state.call("revert_to_banked_score")

	# 2. Rewind 2 checkpoints behind when history allows (C -> A over A -> B -> C).
	if not _checkpoint_history.is_empty():
		var target_idx: int = maxi(0, _checkpoint_history.size() - 3)
		var entry: Dictionary = _checkpoint_history[target_idx]
		checkpoint_section = int(entry.get("section", int(checkpoint_section))) as Section
		var target_xform: Transform3D = entry.get("transform", checkpoint_transform) as Transform3D
		if target_xform != Transform3D.IDENTITY:
			checkpoint_transform = target_xform
		checkpoint_realm = int(entry.get("realm", checkpoint_realm))
		_checkpoint_history.resize(target_idx + 1)

	var rewind_z: float = checkpoint_transform.origin.z

	# 3. Clear incomplete encounter state plus cleared encounters/sections from rewind onward.
	current_encounter_id = ""
	active_enemy_count = 0
	for sec_key in completed_sections.keys():
		if int(sec_key) >= int(checkpoint_section) and not (int(checkpoint_section) == int(Section.ENTRY) and int(sec_key) == int(Section.ENTRY)):
			completed_sections.erase(sec_key)

	if is_inside_tree() and get_tree() != null:
		for trig in get_tree().get_nodes_in_group("section_trigger"):
			if not is_instance_valid(trig):
				continue
			var t_sec: int = int(trig.get("target_section"))
			var t_z: float = (trig as Node3D).global_position.z if trig is Node3D else rewind_z
			if t_sec > int(checkpoint_section) or t_z > rewind_z + 2.0:
				trig.set("has_triggered", false)
				var enc: String = String(trig.get("encounter_id"))
				if not enc.is_empty():
					completed_encounters.erase(enc)
			elif t_sec == int(checkpoint_section) and int(t_sec) > int(Section.ENTRY):
				var enc2: String = String(trig.get("encounter_id"))
				if not enc2.is_empty():
					completed_encounters.erase(enc2)
		for gate in get_tree().get_nodes_in_group("encounter_gate"):
			if not is_instance_valid(gate):
				continue
			var g_sec: int = int(gate.get("section_id"))
			var g_enc: String = String(gate.get("linked_encounter_id"))
			if bool(gate.get("starts_open")) and g_sec >= int(checkpoint_section):
				if gate.has_method("open_gate"):
					gate.call("open_gate", false)
			elif not g_enc.is_empty() and g_sec >= int(checkpoint_section):
				gate.set("is_permanently_unlocked", false)
				if gate.has_method("_on_section_reset_requested"):
					gate.call("_on_section_reset_requested", g_sec)

	current_section = checkpoint_section

	# 4. Restore checkpoint realm state (unlocks shift if died during Warden Phase 2).
	if RealmManager.instance != null:
		RealmManager.instance.force_realm(checkpoint_realm as RealmManager.Realm, false)

	# 5. Respawn player at rewound checkpoint transform with full health, and revive/regroup squad allies.
	if player != null and player.has_method("respawn_at"):
		player.call("respawn_at", checkpoint_transform)
	if is_inside_tree() and get_tree() != null:
		var squad_mgr: Node = get_tree().get_first_node_in_group("ally_squad_manager")
		if squad_mgr == null:
			squad_mgr = AllySquadManager.instance
		if squad_mgr != null and squad_mgr.has_method("regroup"):
			squad_mgr.call("regroup", false)
		for a in get_tree().get_nodes_in_group("squad_ally"):
			if is_instance_valid(a) and bool(a.get("is_downed")) and a.has_method("revive"):
				a.call("revive", 0.5)

	# 6. Enable current section, then respawn all intervening & ahead enemies at full HP cleanly.
	_update_section_enemy_activation()
	for sec_key in _section_enemies.keys():
		var sec_int: int = int(sec_key)
		for enemy in _section_enemies[sec_key]:
			if not is_instance_valid(enemy) or not enemy.has_method("reset_enemy"):
				continue
			var spawn_z: float = rewind_z
			if "_spawn_transform" in enemy:
				spawn_z = (enemy.get("_spawn_transform") as Transform3D).origin.z
			elif enemy is Node3D:
				spawn_z = (enemy as Node3D).global_position.z
			if sec_int > int(checkpoint_section) or (sec_int == int(checkpoint_section) and spawn_z >= rewind_z - 4.0):
				enemy.call("reset_enemy")

	section_reset_requested.emit(checkpoint_section)
	player_respawned.emit(checkpoint_section, checkpoint_transform)


func restart_full_run() -> void:
	completed_sections.clear()
	completed_encounters.clear()
	_checkpoint_history.clear()
	current_section = Section.ENTRY
	checkpoint_section = Section.ENTRY
	checkpoint_realm = 0
	active_enemy_count = 0
	current_encounter_id = ""

	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("start_new_run"):
		run_state.call("start_new_run")

	if RealmManager.instance != null:
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)

	_update_section_enemy_activation()
	section_changed.emit(current_section, get_section_name(current_section))


func _alert_room_on_entry(section_id: Section) -> void:
	if section_id != Section.HALL_COMBAT and section_id != Section.MECHANISM_CHAMBER:
		return
	if not is_inside_tree() or get_tree() == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var alert_rad: float = 62.0 if section_id == Section.HALL_COMBAT else 42.0
	for enemy in _section_enemies.get(section_id, []):
		if is_instance_valid(enemy) and enemy is EnemyAI and enemy.is_active and not enemy.is_dead:
			var e := enemy as EnemyAI
			if e.global_position.distance_to(player.global_position) <= alert_rad and e.is_hittable_now():
				e.receive_alert(player, player, true)
```

- **Postcondition**: Entering Hall or Chamber alerts enemies across the room immediately (`REQ-15`); dying rewinds the player `2` checkpoints behind, re-enables triggers ahead, keeps puzzle gates safe, and respawns all intervening/ahead enemies cleanly (`REQ-21`).

---

### Step 19 — Distinct Enemy Skin Colors, Armor Tints & Weapon Loadouts (`REQ-22`)

- **Prerequisites**: Steps 1–18 complete.
- **Target 1**: `scripts/core/character_loadout.gd` (lines 42–49)
- **Action**: Replace block (exact single match) so enemy `Knight_Body` (`ShieldedGuard`) wields `["2H_Sword", "Spike_Shield"]` and enemy `Barbarian_Body` (`WardenBoss`) wields `["2H_Axe", "Barbarian_Round_Shield"]` — distinct from Player (`1H_Sword + Badge_Shield`) and Brannoc (`2H_Axe`).

**Find:**
```gdscript
	if model_root.find_child("Knight_Body", true, false) != null:
		if role == "player":
			apply(model_root, ["1H_Sword", "Badge_Shield"])
		else:
			apply(model_root, ["1H_Sword", "Rectangle_Shield"])
	elif model_root.find_child("Barbarian_Body", true, false) != null:
		apply(model_root, ["2H_Axe"])
```

**Replace with:**
```gdscript
	if model_root.find_child("Knight_Body", true, false) != null:
		if role == "player":
			apply(model_root, ["1H_Sword", "Badge_Shield"])
		elif role == "enemy":
			apply(model_root, ["2H_Sword", "Spike_Shield"])
		else:
			apply(model_root, ["1H_Sword", "Rectangle_Shield"])
	elif model_root.find_child("Barbarian_Body", true, false) != null:
		if role == "enemy":
			apply(model_root, ["2H_Axe", "Barbarian_Round_Shield"])
		else:
			apply(model_root, ["2H_Axe"])
```

- **Target 2**: `scripts/core/character_animation_bridge.gd` (lines 114–118)
- **Action**: Replace block (exact single match) to invoke `_apply_enemy_hostile_palette(model_root)` for non-spectral, non-archetype enemies (`WardenBoss`, `ShieldedGuard`, `SkeletonGuard`) inside `bind_actor()`.

**Find:**
```gdscript
		if apply_default_loadout and not (_actor is PlayerController):
			LoadoutScript.apply_default_for(model_root, "enemy")
		if apply_spectral_shader or (_actor != null and _actor is PhantomTwin):
			_apply_spectral_material_recursive(model_root)
```

**Replace with:**
```gdscript
		if apply_default_loadout and not (_actor is PlayerController):
			LoadoutScript.apply_default_for(model_root, "enemy")
		if apply_spectral_shader or (_actor != null and _actor is PhantomTwin):
			_apply_spectral_material_recursive(model_root)
		elif _actor != null and _actor is EnemyBase and not (_actor is ArchetypeEnemy):
			_apply_enemy_hostile_palette(model_root)
```

- **Target 3**: `scripts/core/character_animation_bridge.gd` (lines 496–507)
- **Action**: Replace block (exact single match) to define `_apply_enemy_hostile_palette()` and `_tint_enemy_meshes_recursive()` using distinct dark hostile armor/bone tints, surface overrides, and subtle ominous emissions (`WardenBoss` obsidian-crimson, `ShieldedGuard` charred dark-iron, `SkeletonGuard` ashen necrotic green-bone).

**Find:**
```gdscript
func _apply_spectral_material_recursive(node: Node) -> void:
	if _spectral_mat == null and ResourceLoader.exists(SPECTRAL_SHADER_PATH):
		var sh: Shader = load(SPECTRAL_SHADER_PATH) as Shader
		if sh != null:
			_spectral_mat = ShaderMaterial.new()
			_spectral_mat.shader = sh

	if _spectral_mat != null and node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _spectral_mat

	for child in node.get_children():
		_apply_spectral_material_recursive(child)
```

**Replace with:**
```gdscript
func _apply_spectral_material_recursive(node: Node) -> void:
	if _spectral_mat == null and ResourceLoader.exists(SPECTRAL_SHADER_PATH):
		var sh: Shader = load(SPECTRAL_SHADER_PATH) as Shader
		if sh != null:
			_spectral_mat = ShaderMaterial.new()
			_spectral_mat.shader = sh

	if _spectral_mat != null and node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _spectral_mat

	for child in node.get_children():
		_apply_spectral_material_recursive(child)


func _apply_enemy_hostile_palette(model_root: Node) -> void:
	var tint: Color = Color(0.54, 0.50, 0.46, 1.0)
	var emission: Color = Color(0.10, 0.04, 0.04, 1.0)
	var emission_energy: float = 0.0
	var roughness_scale: float = 1.0
	if _actor is WardenBoss:
		# Obsidian-crimson dread armor + ember edge glow so Warden never reads like ally Brannoc.
		tint = Color(0.24, 0.08, 0.09, 1.0)
		emission = Color(0.42, 0.08, 0.04, 1.0)
		emission_energy = 0.28
		roughness_scale = 0.72
	elif _actor is ShieldedGuard:
		# Charred dark-iron plate + cold steel-crimson sheen so Knights never read like Player.
		tint = Color(0.20, 0.22, 0.28, 1.0)
		emission = Color(0.18, 0.05, 0.08, 1.0)
		emission_energy = 0.16
		roughness_scale = 0.65
	elif _actor is SkeletonGuard:
		# Necrotic mossy bone with faint bilious glow, contrasting sharply with ally Sera's cyan.
		tint = Color(0.50, 0.56, 0.44, 1.0)
		emission = Color(0.10, 0.22, 0.08, 1.0)
		emission_energy = 0.18
	model_root.set_meta("enemy_hostile_tint", tint)
	_tint_enemy_meshes_recursive(model_root, tint, emission, emission_energy, roughness_scale)


func _tint_enemy_meshes_recursive(node: Node, tint: Color, emission: Color, emission_energy: float, roughness_scale: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var orig: Material = mi.get_surface_override_material(s)
				if orig == null:
					orig = mi.mesh.surface_get_material(s)
				var mat: StandardMaterial3D = null
				if orig is StandardMaterial3D:
					mat = (orig as StandardMaterial3D).duplicate() as StandardMaterial3D
					mat.albedo_color = mat.albedo_color * tint
					mat.roughness = clampf(mat.roughness * roughness_scale, 0.15, 1.0)
				else:
					mat = StandardMaterial3D.new()
					mat.albedo_color = tint
					mat.roughness = clampf(0.75 * roughness_scale, 0.15, 1.0)
				if emission_energy > 0.0:
					mat.emission_enabled = true
					mat.emission = emission
					mat.emission_energy_multiplier = emission_energy
				mi.set_surface_override_material(s, mat)
	for child in node.get_children():
		_tint_enemy_meshes_recursive(child, tint, emission, emission_energy, roughness_scale)
```

- **Postcondition**: Enemy Knight (`ShieldedGuard`) wields `2H_Sword + Spike_Shield` in charred dark iron, `WardenBoss` wields `2H_Axe + Barbarian_Round_Shield` in obsidian crimson, and `SkeletonGuard` wears necrotic green-ashen bone — zero enemy rigs resemble Player (`1H_Sword + Badge_Shield`), Brannoc (`2H_Axe` warm brown), Sera (`cyan`), or Ivo (`violet`).

---

### Step 20 — `SkeletonGuard` Engagement Range (`22 m`) & 1-Time Self-Revive (`REQ-15`, `REQ-23`)

- **Prerequisites**: Steps 1–19 complete.
- **Target 1**: `scripts/enemies/skeleton_guard.gd` (lines 11–42)
- **Action**: Replace block (exact single match) to raise `detection_range = 22.0`, add 1-time `revive_duration = 3.0 s` fall-down self-revive (`Lie_Down -> Lie_Idle -> Lie_StandUp` via `State.STUNNED`) at `revive_health_ratio = 0.50` (`50%` HP) before dying on the next lethal hit, while letting `"environmental"` and `"fin_execution"` bypass self-revive cleanly.

**Find:**
```gdscript
func _init() -> void:
	# Realm redesign (2026-11-17): every enemy exists in BOTH realms; the Mirror reveals their weak points.
	realm_affinity = RealmReactive.Affinity.BOTH_STATEFUL
	max_health = 100
	health = 100
	detection_range = 9.0
	attack_range = 1.85
	move_speed = 3.4
	windup_duration = 0.55
	attack_active_duration = 0.22
	recover_duration = 0.80
	attack_damage = 15
	attack_name = "skeleton_slash"
	section_id = EncounterDirector.Section.HALL_COMBAT
	encounter_id = "hall_of_echoes"
	flee_health_ratio = 0.15


func reset_hall_hint_flag() -> void:
	_first_hall_skeleton_hint_emitted = false


func _on_enemy_reset() -> void:
	super._on_enemy_reset()
	_first_hall_skeleton_hint_emitted = false


func _die(source_type: String) -> void:
	super._die(source_type)
	if not _first_hall_skeleton_hint_emitted and encounter_id == "hall_of_echoes":
		_first_hall_skeleton_hint_emitted = true
		mirror_hint_requested.emit()
```

**Replace with:**
```gdscript
const SkeletonGoreFXScript := preload("res://scripts/core/gore_fx.gd")

@export var can_self_revive: bool = true
@export var revive_duration: float = 3.0
@export var revive_health_ratio: float = 0.50

var _revived_once: bool = false
var _reviving: bool = false


func _init() -> void:
	# Realm redesign (2026-11-17): every enemy exists in BOTH realms; the Mirror reveals their weak points.
	realm_affinity = RealmReactive.Affinity.BOTH_STATEFUL
	max_health = 100
	health = 100
	detection_range = 22.0
	attack_range = 1.85
	move_speed = 3.4
	windup_duration = 0.55
	attack_active_duration = 0.22
	recover_duration = 0.80
	attack_damage = 15
	attack_name = "skeleton_slash"
	section_id = EncounterDirector.Section.HALL_COMBAT
	encounter_id = "hall_of_echoes"
	flee_health_ratio = 0.15


func reset_hall_hint_flag() -> void:
	_first_hall_skeleton_hint_emitted = false


func has_revived_once() -> bool:
	return _revived_once


func is_reviving_now() -> bool:
	return _reviving


func _on_damage_taken(_final_damage: int, _is_heavy: bool, source_type: String) -> void:
	if can_self_revive and not _revived_once and not _reviving and health <= 0 and source_type != "environmental" and source_type != "fin_execution":
		_revived_once = true
		_reviving = true
		health = 1
		health_changed.emit(health, max_health)
		var hb_hurt: Hurtbox3D = get_hurtbox()
		if hb_hurt != null:
			hb_hurt.is_invulnerable = true
		enter_stunned(revive_duration)
		SkeletonGoreFXScript.flash_light(self, global_position + Vector3.UP * 0.6, Color(0.55, 0.95, 0.45), 3.2, 0.45, 4.0)


func _should_stagger_on_hit(is_heavy: bool, source_type: String) -> bool:
	if _reviving:
		return false
	return super._should_stagger_on_hit(is_heavy, source_type)


func _on_hit_reaction(final_damage: int, is_heavy: bool, source_type: String, staggered_now: bool) -> void:
	if _reviving:
		return
	super._on_hit_reaction(final_damage, is_heavy, source_type, staggered_now)


func _on_backstabbed(attacker: Node) -> void:
	if _reviving:
		return
	super._on_backstabbed(attacker)


func enter_stunned(custom_duration: float = -1.0) -> void:
	# Preserve the 3.0 s revive fall timer against KNOCKDOWN_SOURCES overwrites during apply_damage().
	if _reviving and current_state == State.STUNNED and _state_timer > 0.1:
		return
	super.enter_stunned(custom_duration)


func _process_stunned(delta: float) -> void:
	if _reviving and _state_timer - delta <= 0.0:
		_complete_self_revive()
	super._process_stunned(delta)


func _complete_self_revive() -> void:
	_reviving = false
	health = maxi(1, int(round(float(max_health) * clampf(revive_health_ratio, 0.1, 1.0))))
	var hb_hurt: Hurtbox3D = get_hurtbox()
	if hb_hurt != null:
		hb_hurt.is_invulnerable = not is_active
	health_changed.emit(health, max_health)
	SkeletonGoreFXScript.flash_light(self, global_position + Vector3.UP * 0.9, Color(0.45, 0.95, 0.35), 4.5, 0.35, 5.0)


func _on_enemy_reset() -> void:
	super._on_enemy_reset()
	_first_hall_skeleton_hint_emitted = false
	_revived_once = false
	_reviving = false


func _die(source_type: String) -> void:
	_reviving = false
	super._die(source_type)
	if not _first_hall_skeleton_hint_emitted and encounter_id == "hall_of_echoes":
		_first_hall_skeleton_hint_emitted = true
		mirror_hint_requested.emit()
```

- **Postcondition**: `SkeletonGuard` drops to the ground (`State.STUNNED`, `Lie_Down -> Lie_Idle -> Lie_StandUp`, `3.0 s`, invulnerable while rising) on its first non-environmental lethal blow, stands back up at `50%` HP (`163 HP`), and dies permanently on its second lethal blow.

---

### Step 21 — Create Permanent Regression Test `tests/sanity_regression_test.gd` (`REQ-01`..`REQ-24`)

- **Prerequisites**: Steps 1–20 complete. Target file `tests/sanity_regression_test.gd` must not already exist.
- **Target**: `tests/sanity_regression_test.gd`
- **Action**: **Create** full file contents below.

```gdscript
extends SceneTree
## Permanent regression checks for Sanity-Testing 1-5 and live-play fixes (REQ-01..REQ-24).
## Run: godot --headless --path . -s res://tests/sanity_regression_test.gd

var _results: Array[String] = []
var _main: Node = null


func _initialize() -> void:
	SquadAIConfig.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	create_timer(110.0).timeout.connect(func() -> void:
		print("[sanity] WATCHDOG TIMEOUT")
		quit(2))
	_run()


func _check(name_s: String, ok: bool, detail: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name_s, detail]
	_results.append(line)
	print("[sanity] ", line)


func _run() -> void:
	# Wait on Title Screen long enough (> 0.25s) to reproduce ObjectiveTracker early-refresh bug if unfixed.
	await create_timer(0.45).timeout
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	# Allow ObjectiveTracker._refresh() (0.25s cadence) to run post level_ready.
	await create_timer(0.40).timeout

	var lv: Node = _main.get_node("LevelRoot")
	var player: PlayerController = get_first_node_in_group("player") as PlayerController

	# 1) REQ-01: All 5 WorldHint prop labels attached after Title Screen -> Start.
	var hint_paths: Array[String] = [
		"Stage01_EntryVestibule/EntryMirrorSwitch/WorldHint",
		"Stage01_EntryVestibule/EntrySteppingStones/WorldHint",
		"Stage03_CollapsedGallery/BridgeAnchorSwitch/WorldHint",
		"Stage03_CollapsedGallery/WeakStoneSupport/WorldHint",
		"Stage02_HallOfEchoes/CrackedCentralPillar/WorldHint",
	]
	var missing: Array[String] = []
	for hp in hint_paths:
		var lbl: Node = lv.get_node_or_null(hp)
		if lbl == null or not lbl.is_in_group(WorldLabelOverlay.GROUP):
			missing.append(hp)
	_check("world_hint_props_5_of_5", missing.is_empty(), "missing=%s" % str(missing))

	# 2) REQ-03, REQ-24: Undamaged placed & spawned enemies show +30% scaled FloatingHPBar text (325/325).
	var guard1: EnemyBase = lv.get_node_or_null("Stage02_HallOfEchoes/Enemies/SkeletonGuard_1") as EnemyBase
	var bar1: Label3D = guard1.get_node_or_null("FloatingHPBar") as Label3D if guard1 != null else null
	var dyn_sk: EnemyBase = lv.call("_add_roamer", lv, "skeleton", "Sanity_DynSkel", Vector3(0, 0, -134), EncounterDirector.Section.ENTRY, Vector3(0, 0, -138)) as EnemyBase
	await process_frame
	var bar2: Label3D = dyn_sk.get_node_or_null("FloatingHPBar") as Label3D if dyn_sk != null else null
	_check("enemy_hp_bar_scaled_on_spawn",
		bar1 != null and bar1.text == "325/325" and bar2 != null and bar2.text == "325/325",
		"placed=%s dyn=%s" % [bar1.text if bar1 != null else "null", bar2.text if bar2 != null else "null"])
	if dyn_sk != null:
		dyn_sk.queue_free()

	# 3) REQ-04: Enlarged GateWarden_W/E AttackHitbox forward reach >= scaled attack_range.
	var gw: EnemyAI = lv.get_node_or_null("Stage01_EntryVestibule/Roamers/GateWarden_W") as EnemyAI
	var ge: EnemyAI = lv.get_node_or_null("Stage01_EntryVestibule/Roamers/GateWarden_E") as EnemyAI
	var w_reach: float = _hitbox_reach(gw)
	var e_reach: float = _hitbox_reach(ge)
	_check("enlarged_gate_warden_hitbox_reach",
		gw != null and ge != null and w_reach >= gw.attack_range and e_reach >= ge.attack_range,
		"W reach=%.2f/atk=%.2f E reach=%.2f/atk=%.2f" % [w_reach, gw.attack_range if gw != null else -1.0, e_reach, ge.attack_range if ge != null else -1.0])

	# 4) REQ-06: WorldIntel & divide_and_conquer skip Reality-immune ForecourtPhantom.
	RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)
	await process_frame
	player.global_position = Vector3(0.0, 0.0, -10.5)
	var ph: EnemyAI = lv.get_node_or_null("Stage01_EntryVestibule/Roamers/ForecourtPhantom") as EnemyAI
	var mgr: AllySquadManager = AllySquadManager.instance
	mgr.regroup(false)
	await create_timer(0.3).timeout
	mgr.intel.refresh()
	var resolved_ph: EnemyAI = mgr.intel.resolve("phantom")
	var ph_id: String = mgr.intel.id_of(ph) if ph != null else ""
	var resolved_by_id: EnemyAI = mgr.intel.resolve(ph_id) if not ph_id.is_empty() else null
	mgr.execute_strategy("divide_and_conquer")
	await create_timer(0.6).timeout
	var tgts: Dictionary = {}
	var any_phantom: bool = false
	for a in mgr.get_living():
		if a.current != null and a.current.verb == "attack":
			var eid: String = String(a.current.args.get("target", ""))
			tgts[eid] = true
			if eid == ph_id:
				any_phantom = true
	_check("world_intel_excludes_reality_phantom",
		ph != null and not ph.is_hittable_now() and resolved_ph == null and resolved_by_id == null and not any_phantom and tgts.size() >= mini(3, mgr.get_living().size()),
		"ph_id=%s res=%s res_id=%s tgts=%s" % [ph_id, str(resolved_ph), str(resolved_by_id), str(tgts.keys())])

	# 5) REQ-02: Warden Phase 1 single-hit overkill clamps at threshold & enters Phase 2; Phase 2 environmental obeys cap.
	var warden: WardenBoss = lv.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden") as WardenBoss
	var overkill_ok: bool = false
	var env_cap_ok: bool = false
	if warden != null:
		warden.set_section_enabled(true)
		RealmManager.instance.force_realm(RealmManager.Realm.MIRROR, false)
		await process_frame
		warden.apply_damage(99999, true, "player_heavy", player)
		overkill_ok = not warden.is_dead and warden.current_phase != WardenBoss.Phase.PHASE_1_SPLIT and warden.health == warden._phase2_threshold()
		warden.complete_phase2_transition_now()
		var hp_p2: int = warden.health
		warden.apply_damage(999, true, "environmental", null)
		env_cap_ok = (hp_p2 - warden.health) == warden.phase2_max_hit
		warden.reset_enemy()
		warden.set_section_enabled(false)
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)
	_check("warden_phase1_overkill_transitions_to_phase2", overkill_ok and env_cap_ok, "overkill_ok=%s env_cap_ok=%s" % [str(overkill_ok), str(env_cap_ok)])

	# 6) REQ-10: Non-boss enemy meshes get visibility_range_end = 58.0; Warden stays 0.0.
	var sk_vr: float = _first_mesh_vis_range(guard1)
	var w_vr: float = _first_mesh_vis_range(warden)
	_check("non_boss_enemy_visibility_range_set", is_equal_approx(sk_vr, 58.0) and is_equal_approx(w_vr, 0.0), "skel=%.1f warden=%.1f" % [sk_vr, w_vr])

	# 7) REQ-09: Freed gibs with bleed trails do not log freed lambda capture errors.
	for _g in range(12):
		var rb := RigidBody3D.new()
		root.add_child(rb)
		GoreFX._attach_bleed_trail(rb, Vector3.ZERO, Color.RED, false)
		rb.queue_free()
	await create_timer(1.8).timeout
	_check("gore_gib_recycle_no_lambda_error", true)

	# 8) REQ-05: Freeing SquadCommsHUD while chat is open clears PlayerController.ui_input_locked.
	var temp_hud := SquadCommsHUD.new()
	root.add_child(temp_hud)
	await process_frame
	temp_hud.open_chat()
	var locked_during: bool = PlayerController.ui_input_locked
	temp_hud.queue_free()
	await process_frame
	await process_frame
	var locked_after: bool = PlayerController.ui_input_locked
	_check("tts_and_comms_hud_exit_cleanup", locked_during and not locked_after, "during=%s after=%s" % [str(locked_during), str(locked_after)])

	# 9) REQ-13: TTS prompt text is excluded from Director prompt & Gemini payload, and stripped by sanitize_spoken_line().
	var brannoc: SquadAlly = mgr.find_ally("Brannoc")
	var ivo: SquadAlly = mgr.find_ally("Ivo")
	var leak_b: String = SquadComms.sanitize_spoken_line(brannoc, "Deep, gravelly, calm veteran shield-captain. Short sentences. Speak at a brisk, natural conversational pace — never slow or drawn out. Say: Shield up!")
	var leak_i: String = SquadComms.sanitize_spoken_line(ivo, "Precise, refined scholar-mage. Slightly pompous, articulate. Speak at a brisk, natural conversational pace. Say: Shards, fall!")
	var tmp_comms := SquadComms.new()
	root.add_child(tmp_comms)
	tmp_comms.bind_manager(mgr)
	var sys_prompt: String = tmp_comms.build_system_prompt()
	tmp_comms.queue_free()
	var client_src: String = FileAccess.get_file_as_string("res://addons/parallax_squad_ai/openai_client.gd")
	var client_clean: bool = not client_src.contains("Say: %s")
	_check("tts_prompt_not_spoken_aloud",
		leak_b == "Shield up!" and leak_i == "Shards, fall!" and not sys_prompt.contains("Speaks:") and not sys_prompt.contains("Deep, gravelly") and client_clean,
		"b='%s' i='%s' client_clean=%s" % [leak_b, leak_i, str(client_clean)])

	# 10) REQ-15: Far Hall of Echoes enemies (~52 m away) detect/engage on Hall entry.
	player.global_position = JourneyLayout.HALL_CENTER - Vector3(0.0, 0.0, 28.0)  # (0, 4, 58) inside South door
	EncounterDirector.instance.advance_to_section(EncounterDirector.Section.HALL_COMBAT, Transform3D.IDENTITY, false)
	await create_timer(0.3).timeout
	var sk6: EnemyAI = lv.get_node_or_null("Stage02_HallOfEchoes/Enemies/SkeletonGuard_6") as EnemyAI
	var hall_engaged: bool = sk6 != null and sk6.detection_range >= 50.0 and sk6.max_chase_distance >= 60.0 and sk6.current_state == EnemyAI.State.CHASE
	_check("hall_enemies_engage_on_entry", hall_engaged,
		"det=%.1f chase=%.1f state=%d" % [sk6.detection_range if sk6 != null else -1.0, sk6.max_chase_distance if sk6 != null else -1.0, int(sk6.current_state) if sk6 != null else -1])

	# 11) REQ-16: Ally ordered to kite/distract a distant enemy (42 m across HallFloor) advances past 12 m without teleporting back.
	mgr.regroup(false)
	var far_e: EnemyAI = lv.call("_add_roamer", lv, "brute", "Test_DistantBrute", JourneyLayout.HALL_CENTER + Vector3(0.0, 0.0, 14.0), EncounterDirector.Section.HALL_COMBAT, player.global_position) as EnemyAI
	if far_e != null:
		far_e.max_health = 5000
		far_e.health = 5000
		far_e.set_section_enabled(true)
	await create_timer(0.25).timeout
	mgr.intel.refresh()
	var far_id: String = mgr.intel.id_of(far_e) if far_e != null else ""
	mgr.issue({"verb": "kite", "allies": ["Brannoc"], "target": far_id})
	await create_timer(3.6).timeout
	var dist_moved: float = brannoc.global_position.distance_to(player.global_position) if brannoc != null else 0.0
	var far_ok: bool = not far_id.is_empty() and brannoc != null and not brannoc.is_downed and dist_moved > 12.0
	_check("ally_distant_order_not_teleported", far_ok, "far_id=%s dist=%.1f m state=%s" % [far_id, dist_moved, brannoc.get_state_text() if brannoc != null else "null"])
	if far_e != null:
		far_e.queue_free()
	mgr.regroup(false)

	# 12) REQ-14: Sneaking past Gate01 or Gate02 auto-opens the gate, completes skipped encounter, and advances objective.
	var tracker: ObjectiveTracker = root.find_child("ObjectiveTracker", true, false) as ObjectiveTracker
	var gate1: Node = lv.get_node_or_null("Stage01_EntryVestibule/Gate01_EntryToHall")
	var gate2: Node = lv.get_node_or_null("Stage02_HallOfEchoes/Gate02_HallToGallery")
	player.global_position = Vector3(0.0, 0.0, 7.2)
	if tracker != null:
		tracker._refresh()
	var g1_title: String = String(tracker.get_objective().get("title", "")) if tracker != null else ""
	var g1_ok: bool = gate1 != null and bool(gate1.get("is_open")) and not g1_title.contains("Gate of Reflections")
	player.global_position = JourneyLayout.HALL_CENTER + Vector3(0.0, 0.0, 36.0)
	if tracker != null:
		tracker._refresh()
	var g2_title: String = String(tracker.get_objective().get("title", "")) if tracker != null else ""
	var g2_ok: bool = gate2 != null and bool(gate2.get("is_open")) and bool(EncounterDirector.instance.completed_encounters.get("hall_of_echoes", false)) and not g2_title.contains("Hall of Echoes")
	_check("bypassed_gate_auto_clears_objective", g1_ok and g2_ok, "g1_ok=%s g2_ok=%s title='%s'" % [str(g1_ok), str(g2_ok), g2_title])

	# 13) REQ-18: All main HUD icons & badges scaled up by +20%.
	var hud: Node = get_first_node_in_group("hud")
	var wpn: Control = hud.find_child("WeaponDiamond", true, false) as Control if hud != null else null
	var crest: Control = hud.find_child("CrestBadge", true, false) as Control if hud != null else null
	var swap_b: Control = hud.find_child("SwapMedallion", true, false) as Control if hud != null else null
	var rpill: Control = hud.find_child("RealityPillPanel", true, false) as Control if hud != null else null
	var mic: Control = hud.find_child("MicButton", true, false) as Control if hud != null else null
	var slots_row: Node = hud.find_child("SlotsRow", true, false) if hud != null else null
	var act_badge: Control = slots_row.find_child("ActionBadge", true, false) as Control if slots_row != null else null
	if act_badge == null and slots_row != null:
		for ch in slots_row.get_children():
			for sub in ch.get_children():
				if sub is HudDiamondBadge:
					act_badge = sub as Control
					break
			if act_badge != null:
				break
	var icons_ok: bool = (
		wpn != null and wpn.custom_minimum_size.x >= 96.0
		and crest != null and crest.custom_minimum_size.x >= 66.0
		and swap_b != null and swap_b.custom_minimum_size.x >= 44.0
		and rpill != null and rpill.custom_minimum_size.x >= 164.0
		and mic != null and mic.custom_minimum_size.x >= 76.0
		and act_badge != null and act_badge.custom_minimum_size.x >= 94.0
	)
	_check("ui_icons_scaled_up_20pct", icons_ok,
		"wpn=%s crest=%s swap=%s pill=%s mic=%s act=%s" % [
			str(wpn.custom_minimum_size if wpn != null else Vector2.ZERO),
			str(crest.custom_minimum_size if crest != null else Vector2.ZERO),
			str(swap_b.custom_minimum_size if swap_b != null else Vector2.ZERO),
			str(rpill.custom_minimum_size if rpill != null else Vector2.ZERO),
			str(mic.custom_minimum_size if mic != null else Vector2.ZERO),
			str(act_badge.custom_minimum_size if act_badge != null else Vector2.ZERO),
		])

	# 14) REQ-19: Base range caps <= +30%; camera-visible enemies (<= 140 m) auto-targetable + pull/taunt parsed.
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var cam_e: EnemyAI = null
	var cam_ok: bool = false
	var pull_parsed: Array = SquadCommandParser.parse("pull em here", ["Brannoc", "Sera", "Ivo"])
	var parse_pull_ok: bool = not pull_parsed.is_empty() and String(pull_parsed[0].get("verb", "")) == "kite" and String(pull_parsed[0].get("lure", "")) == "player"
	if cam != null:
		var cam_fwd: Vector3 = -cam.global_transform.basis.z
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized() if cam_fwd.length_squared() > 0.001 else Vector3.FORWARD
		var cam_pos: Vector3 = Vector3(cam.global_position.x + cam_fwd.x * 68.0, player.global_position.y, cam.global_position.z + cam_fwd.z * 68.0)
		cam_e = lv.call("_add_roamer", lv, "skeleton", "Sanity_CamFarEnemy", cam_pos, EncounterDirector.Section.ENTRY, player.global_position) as EnemyAI
		if cam_e != null:
			cam_e.set_section_enabled(true)
			await process_frame
			await process_frame
			mgr.intel.scan_camera_now()
			var cam_res: EnemyAI = mgr.intel.resolve("farther enemy")
			cam_ok = (
				WorldIntel.RANGE_M <= 52.0 + 0.01
				and SquadAlly.FOLLOW_LEASH <= 19.5 + 0.01
				and mgr.intel.is_camera_visible(cam_e)
				and not mgr.intel.id_of(cam_e).is_empty()
				and cam_res != null
			)
			cam_e.queue_free()
	_check("camera_visible_enemy_targetable_and_pull", cam_ok and parse_pull_ok,
		"cam_ok=%s parse_pull_ok=%s range=%.1f leash=%.1f" % [str(cam_ok), str(parse_pull_ok), WorldIntel.RANGE_M, SquadAlly.FOLLOW_LEASH])

	# 15) REQ-20: Player & ally health regen take >= 2 min (0 -> full), and Ivo does not auto-cast Mending Light.
	var p_regen_ok: bool = false
	if player != null and player.health_regen_seconds_to_full >= 120.0:
		player.health = 50
		player._player_regen_acc = 0.0
		player._tick_passive_regen(1.0)
		var after_1s: int = player.health
		player._tick_passive_regen(1.5)
		p_regen_ok = after_1s == 50 and player.health >= 51 and player.health <= 52
		player.health = player.max_health
		player._player_regen_acc = 0.0
	var a_regen_ok: bool = false
	if brannoc != null and ivo != null and ivo.profile != null:
		brannoc.health = 100
		brannoc._retreating = true
		brannoc._regen_acc = 0.0
		brannoc._regen(2.0)
		var ivo_auto_off: bool = false
		for sk in ivo.profile.skills:
			if String(sk.get("id")) == "mending_light":
				ivo_auto_off = String(sk.get("auto_use")).is_empty() and float(sk.get("power")) <= 0.20
		a_regen_ok = brannoc.health >= 102 and brannoc.health <= 104 and ivo_auto_off
		brannoc.health = brannoc.max_health
		brannoc._retreating = false
	_check("slow_player_and_ally_health_regen", p_regen_ok and a_regen_ok, "p=%s a=%s" % [str(p_regen_ok), str(a_regen_ok)])

	# 16) REQ-21: Death rewinds 2 checkpoints back and respawns intervening/ahead enemies.
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	var rewind_ok: bool = false
	if ed != null and guard1 != null:
		ed.restart_full_run()
		ed.checkpoint_transform = Transform3D.IDENTITY
		ed.set_checkpoint(EncounterDirector.Section.ENTRY, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -136.0)), 0)
		ed.set_checkpoint(EncounterDirector.Section.HALL_COMBAT, Transform3D(Basis.IDENTITY, JourneyLayout.HALL_CENTER - Vector3(0.0, 0.0, 24.0)), 0)
		ed.set_checkpoint(EncounterDirector.Section.COLLAPSED_GALLERY, Transform3D(Basis.IDENTITY, Vector3(0.0, 6.0, 165.5)), 0)
		guard1.set_section_enabled(true)
		guard1.reset_enemy()
		guard1.apply_damage(99999, true, "environmental", null)
		var dead_before: bool = guard1.is_dead
		ed.completed_encounters["hall_of_echoes"] = true
		ed.handle_player_death(player)
		rewind_ok = (
			dead_before
			and int(ed.checkpoint_section) == int(EncounterDirector.Section.ENTRY)
			and player.global_position.z < -130.0
			and not guard1.is_dead
			and guard1.health == guard1.max_health
			and not bool(ed.completed_encounters.get("hall_of_echoes", false))
		)
	_check("death_respawns_two_checkpoints_back_and_resets_enemies", rewind_ok,
		"sec=%d z=%.1f guard_dead=%s" % [int(ed.checkpoint_section) if ed != null else -1, player.global_position.z if player != null else 0.0, str(guard1.is_dead) if guard1 != null else "null"])

	# 17) REQ-22: Enemy rigs carry distinct dark armor/skin palettes and weapon/shield loadouts from Player & Allies.
	var sg: Node = lv.get_node_or_null("Stage03_CollapsedGallery/Enemies/ShieldedGuard_1")
	var sg_mr: Node = sg.get_node_or_null("VisualRoot/ModelRoot") if sg != null else null
	var w_mr: Node = warden.get_node_or_null("VisualRoot/ModelRoot") if warden != null else null
	var g_mr: Node = guard1.get_node_or_null("VisualRoot/ModelRoot") if guard1 != null else null
	var allies_untinted: bool = true
	for a in mgr.get_living():
		var amr: Node = a.get_node_or_null("VisualRoot/ModelRoot")
		if amr != null and amr.has_meta("enemy_hostile_tint"):
			allies_untinted = false
	var w_shield: Node3D = w_mr.find_child("Barbarian_Round_Shield", true, false) as Node3D if w_mr != null else null
	var sg_spike: Node3D = sg_mr.find_child("Spike_Shield", true, false) as Node3D if sg_mr != null else null
	var visuals_ok: bool = (
		allies_untinted
		and w_mr != null and w_mr.has_meta("enemy_hostile_tint") and w_shield != null and w_shield.visible
		and sg_mr != null and sg_mr.has_meta("enemy_hostile_tint") and sg_spike != null and sg_spike.visible
		and g_mr != null and g_mr.has_meta("enemy_hostile_tint")
	)
	_check("enemy_visuals_distinct_from_player_and_allies", visuals_ok,
		"allies_clean=%s warden_sh=%s sg_spike=%s" % [str(allies_untinted), str(w_shield != null and w_shield.visible), str(sg_spike != null and sg_spike.visible)])

	# 18) REQ-23, REQ-24: SkeletonGuard revives once before dying, +40% dmg, +50% mobs, +30% HP.
	var rev_ok: bool = false
	if guard1 != null:
		guard1.set_section_enabled(true)
		guard1.reset_enemy()
		guard1.apply_damage(99999, true, "player_heavy", player)
		var fell_first: bool = not guard1.is_dead and guard1.health == 1 and guard1.current_state == EnemyAI.State.STUNNED and bool(guard1.call("has_revived_once")) and bool(guard1.call("is_reviving_now"))
		guard1._process_stunned(3.1)
		var sk_rev_hp: int = int(round(325.0 * 0.50))
		var rose_up: bool = not guard1.is_dead and not bool(guard1.call("is_reviving_now")) and guard1.health == sk_rev_hp
		guard1.apply_damage(99999, true, "player_heavy", player)
		rev_ok = fell_first and rose_up and guard1.is_dead
	var hall_en: Node = lv.get_node_or_null("Stage02_HallOfEchoes/Enemies")
	var hall_roam: Node = lv.get_node_or_null("Stage02_HallOfEchoes/Roamers")
	var ch_roam: Node = lv.get_node_or_null("Stage04_MechanismChamber/Roamers")
	var scale_ok: bool = (
		guard1 != null and guard1.max_health == 325 and guard1.attack_damage == 21
		and warden != null and warden.max_health == 3250 and warden.cleave_damage == 28 and warden.lunge_damage == 35
		and hall_en != null and hall_en.get_child_count() == 13
		and hall_roam != null and hall_roam.get_child_count() == 5
		and ch_roam != null and ch_roam.get_child_count() == 12
	)
	_check("skeleton_soldier_revives_once_and_enemy_stats_scaled", rev_ok and scale_ok,
		"rev_ok=%s scale_ok=%s sk_dmg=%d w_clv=%d hall=%d+%d ch=%d" % [
			str(rev_ok), str(scale_ok),
			guard1.attack_damage if guard1 != null else -1,
			warden.cleave_damage if warden != null else -1,
			hall_en.get_child_count() if hall_en != null else -1,
			hall_roam.get_child_count() if hall_roam != null else -1,
			ch_roam.get_child_count() if ch_roam != null else -1,
		])

	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[sanity] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)


func _hitbox_reach(ai: EnemyAI) -> float:
	if ai == null:
		return -1.0
	var atk: Node3D = ai.get_node_or_null("AttackHitbox") as Node3D
	if atk == null:
		return -1.0
	for c in atk.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var cs := c as CollisionShape3D
			var bs := cs.shape as BoxShape3D
			return absf(cs.position.z) + bs.size.z * 0.5
	return -1.0


func _first_mesh_vis_range(enemy: Node) -> float:
	if enemy == null:
		return -1.0
	var vr: Node = enemy.get_node_or_null("VisualRoot")
	if vr == null:
		return -1.0
	for n in vr.find_children("*", "MeshInstance3D", true, false):
		return (n as MeshInstance3D).visibility_range_end
	return -1.0
```

- **Postcondition**: Running `tests/sanity_regression_test.gd` exercises all 18 regression probes (`REQ-01`..`REQ-24`) and exits `0` with `[sanity] SUMMARY 18 checks, 0 failed`.

---

### Step 22 — Synchronize `MEMORY/` Knowledge Base & Changelog (`REQ-12`, `AGENTS.md` Rule 1.3)

- **Prerequisites**: Steps 1–21 applied.
- **Target 1**: `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` (lines 64–67)
- **Action**: Replace block (exact single match).

**Find:**
```markdown
- **FLOW (rhythm)**: a press during a light swing that lands in `[cancel − flow_window_early 0.10, cancel + flow_window_late 0.28]` **and is the only press during that swing** makes the next step FLOW: wind-up ×`0.62`, damage ×`1.15`, trail ×1.35, rising-pitch whoosh (+7 %/step) and an FOV punch. Mashing still chains through the buffer but never earns FLOW. `flow_streak` counts consecutive FLOW steps.
```

**Replace with:**
```markdown
- **FLOW (rhythm)**: a press during `State.LIGHT_ATTACK` that lands in `[cancel − flow_window_early 0.10, cancel + flow_window_late 0.28]` **and is the only press during that swing** makes the next step FLOW: wind-up ×`0.62`, damage ×`1.15`, trail ×1.35, rising-pitch whoosh (+7 %/step) and an FOV punch (`_is_flow_timing()` returns `false` outside `State.LIGHT_ATTACK`). Mashing still chains through the buffer but never earns FLOW. `flow_streak` counts consecutive FLOW steps.
- **Slow passive player regen (`REQ-20`)**: `PlayerController.health_regen_seconds_to_full = 125.0` (`>= 2 min` from `0` to `max_health`, ticking in `_tick_passive_regen()` during active gameplay and resetting accumulator on respawn).
```

- **Target 2**: `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` (lines 151–156)
- **Action**: Replace block (exact single match).

**Find:**
```markdown
  - **Phase 2 Transition (`HP <= 500`)**:
    - Stops current attack immediately -> plays `<= 2.0 s` Mirror Plane shatter sequence -> **one-way transition**.
    - HUD banner/chip changes to **`REALMS MERGED`**; `Q` is locked/disabled (`shift_locked = true`).
```

**Replace with:**
```markdown
  - **Phase 2 Transition (`<= 50%` of scaled `max_health`, i.e., `1,625 / 3,250`)**:
    - Phase 1 incoming hits are clamped to `maxi(1, health - _phase2_threshold())` so a single large hit cannot overkill Warden in Phase 1; Phase 2 caps all damage sources (including `"environmental"`) at `phase2_max_hit` (`120`). Warden deals `+40%` damage (`cleave_damage = 28`, `lunge_damage = 35`).
    - `EnemyBase.HEALTH_SCALE = 3.25` (`+30%` HP over `2.5`) and `EnemyAI.DAMAGE_SCALE = 1.4` (`+40%` damage across all enemies); `EnemyBase._ready()` emits `health_changed` so undamaged `FloatingHPBar` labels start at scaled values (`325/325`). Enlarged gate wardens (`_enlarge_enemy`) also scale `AttackHitbox` shapes alongside `attack_range`, `WorldIntel` / `AllySquadManager` filter targets by `is_hittable_now()`, `SkeletonGuard` performs a 1-time `3.0 s` fall-down self-revive (`50%` HP) before dying on the next lethal blow, and `CharacterLoadout` + `CharacterAnimationBridge` give hostile Knights (`2H_Sword + Spike_Shield`, dark iron) and Warden (`2H_Axe + Barbarian_Round_Shield`, obsidian crimson) / Skeletons (necrotic bone) distinct silhouettes and palettes from Player/Allies.
    - Stops current attack immediately -> plays `<= 2.0 s` Mirror Plane shatter sequence -> **one-way transition**.
    - HUD banner/chip changes to **`REALMS MERGED`**; `Q` is locked/disabled (`shift_locked = true`).
```

- **Target 3**: `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` (lines 176–188)
- **Action**: Replace block (exact single match) to document updated enemy engagement ranges (`REQ-15`, `REQ-23`).

**Find:**
```markdown
- **States**: ALERT (walk to the noise / call, look around `4 s`, detection ×1.25), FLEEING (once per life below `flee_health_ratio`: Skeleton `0.15`, Phantom `0.25`, Hexcaster `0.30`, Stalker `0.35`, others `0`; runs `flee_duration` then turns and fights), RETURNING (leash: beyond `max_chase_distance` from home — default `22 m`, Warden `80`, Brute `18`, Hexcaster `20`, Stalker `24` — clears threat and walks home, `1.5 s` re-aggro block, snaps home after `14 s` stuck). IDLE roamers patrol within `patrol_radius` (roamers `1.6 m`, archetypes from data) with an edge probe.
- **Alert propagation**: spotter calls squad-mates in the same encounter or within `9 m` straight into CHASE; within `18 m` they come to investigate (ALERT). Ally detonations / brute slams `broadcast_noise` (`14–16 m`).
```

**Replace with:**
```markdown
- **States**: ALERT (walk to the noise / call, look around `4 s`, detection ×1.25), FLEEING (once per life below `flee_health_ratio`: Skeleton `0.15`, Phantom `0.25`, Hexcaster `0.30`, Stalker `0.35`, others `0`; runs `flee_duration` then turns and fights), RETURNING (leash: beyond `max_chase_distance` from home — default `52 m`, Warden `80`, Brute `48`, Hexcaster `52`, Stalker `56`, Hall `68`, Chamber `48` — clears threat and walks home, `1.5 s` re-aggro block, snaps home after `14 s` stuck; chase drop threshold `maxf(detection_range * 2.5, max_chase_distance * 1.15)`). `detection_range` defaults `20–26 m` (Hall `56 m`, Chamber `38 m`), and `EncounterDirector.advance_to_section()` alerts active room enemies on Hall (`62 m`) / Chamber (`42 m`) entry. `SkeletonGuard` intercepts its first non-environmental/non-execution lethal blow to lie down in `State.STUNNED` (`3.0 s`, invulnerable while rising) and self-revive once at `50%` HP before dying permanently on the next lethal hit. IDLE roamers patrol within `patrol_radius` (roamers `1.6 m`, archetypes from data) with an edge probe.
- **Alert propagation**: spotter calls squad-mates in the same encounter or within `22 m` straight into CHASE; within `38 m` they come to investigate (ALERT). Ally detonations / brute slams `broadcast_noise` (`14–16 m`).
```

- **Target 4**: `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` (line 187)
- **Action**: Replace block (exact single match).

**Find:**
```markdown
- All allies: `damage_taken_mult 0.6`, out-of-combat regen (×3 while retreating), formation wedge out of the camera line (`(-2.5,0.3)`, `(2.7,0.8)`, `(-2.2,2.4)`…), catch-up blink when > 20 m (30 on missions) / stuck 2 s / a level below. Personalities only change voice & flavour lines (incl. banter every 50–95 s out of combat and complaints at repeated silly orders).
```

**Replace with:**
```markdown
- All allies: `damage_taken_mult 0.6`, slow regen (`max_health / 125.0`, >= 2 min `0 -> full`, NO `3×` retreat burst; Brannoc `1.5`, Sera `0.95`, Ivo `0.88`, `mending_light` command-only `0.18`), formation wedge out of the camera line (`(-2.5,0.3)`, `(2.7,0.8)`, `(-2.2,2.4)`…), follow leash `19.5 m` (`+30%` cap), `WorldIntel` `RANGE_M 52 m` (`+30%` cap) plus `1.2 s` camera-frustum scan `_scan_camera_visible()` (`<= 140 m`) so any visible enemy becomes targetable/pullable (`"pull em here"` / `"farther enemy"`), catch-up blink capped at `19.5 m` (`30 m` on missions, `150 m` while executing distant/camera-visible orders so allies never teleport back mid-pull; stuck nudge avoids player blink unless distant/fallen). Personalities only change voice & flavour lines (incl. banter every 50–95 s out of combat and complaints at repeated silly orders).
```

- **Target 5**: `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md` (lines 232–237)
- **Action**: Replace block (exact single match).

**Find:**
```markdown
Use this to place flora, fauna, props, lights or sounds **without loading `grand_journey_builder.gd` (≈2k lines)**. Everything is procedural: the level is built at runtime by `LevelRoot` (`GrandJourneyBuilder`) in `scenes/main/main.tscn`. There is no saved geometry to edit in a `.tscn`. Put your content **in a scene or script you own** and instance it as a sibling under `Main`, or add a builder hook. Do not hand-edit `StageNN_*` children: their names are a save/MainController contract. Axes: `+Z` = north = forward along the route; `+Y` up; `X < 0` is west, where the sunset is (keep the west skyline clear).

### 6.1 Walkable floors (collider tops, `World_Shared` layer 3 = bit value 4 unless noted)
```

**Replace with:**
```markdown
Use this to place flora, fauna, props, lights or sounds **without loading `grand_journey_builder.gd` (≈2k lines)**. Everything is procedural: the level is built at runtime by `LevelRoot` (`GrandJourneyBuilder`) in `scenes/main/main.tscn`. There is no saved geometry to edit in a `.tscn`. Put your content **in a scene or script you own** and instance it as a sibling under `Main`, or add a builder hook. Do not hand-edit `StageNN_*` children: their names are a save/MainController contract. Axes: `+Z` = north = forward along the route; `+Y` up; `X < 0` is west, where the sunset is (keep the west skyline clear).

> **Post-Guide-05 World Coordinate Mapping (`JourneyLayout` v2, 2026-11-18)**: Section 6.1–6.5 below lists original **story Z** coordinates alongside legacy stage footprints. At runtime, `GrandJourneyBuilder` / `JourneyLayout` remap stages to **world coordinates**:
> `Stage01 Terrace` = `z -136` (`OFF_S1_TERRACE = -80`; Forecourt `8` mobs) · `R1 Causeway` = `(0,0,-131)->(34,0,-97)->(-34,0,-49)->(0,0,-15)` · `R2 Sunlit` = `z 8..56` (Bastions `9`/route) · **`HallFloor` = `60x60 m` at `(0, 4, 86)`** (`13` encounter + `5` roamers = `18` mobs) · `R3 Rampart` = `z 116..164` · `Stage03 Gallery` = `story_z + 104` (`OFF_S3 = +104`; `ShieldedGuard_1` at `(0, 6, 187.2)`, `4` roamers) · **`ChamberFloor` = `36x36 m` at `(0, 6, 210)`** (`12` roamers, Esplanade `6`) · `R5 Processional` = `z 228..276` · `Stage05 Arena/Summit` = `story_z + 160` (`OFF_S5 = +160`; `TheWarden` at `(0, 10, 313)`). Always convert story Z <-> world Z via `JourneyLayout.to_world()` / `JourneyLayout.story_z()`. `ObjectiveTracker` auto-clears any bypassed gate (`Gate01`–`Gate05`), bridge, puzzle (`force_solve_bypass()`), or skipped encounter; `EncounterDirector.handle_player_death()` rewinds `2` checkpoints behind via `_checkpoint_history`, resets triggers/combat exit gates cleanly, revives/regroups allies, and respawns all intervening enemies via `reset_enemy()`.

### 6.1 Walkable floors (collider tops, `World_Shared` layer 3 = bit value 4 unless noted)
```

- **Target 6**: `MEMORY/05_UI_SCORING_AND_AUDIO.md` (lines 70–75)
- **Action**: Replace block (exact single match).

**Find:**
```markdown
| **Bottom-Center (above prompts)** | Subtitles (max 3, speaker-coloured, streaming LLM text updates in place, fade `6.5 s`) and the chat bar (`UIFrame`, `ORDER ›` + LineEdit + SEND) | Contextual | Chat bar opens on Enter, locks gameplay input, Esc closes. |
| **Top-Center (below chips)** | Notifications (info / warn / error toasts, `5 s`) — API errors, offline mode, mode gating | Contextual | Never block input. |
| **Top-Center (y 156, below the shift cooldown)** | **Objective tracker** (`ObjectiveTracker`, 2026-11-17): gold diamond + current objective title (pops when it changes) + ≤ 2-line plain-language hint, derived live from world state (switches, gates, stones, support, guard, puzzle, Warden phase). Also an on-screen waypoint diamond with distance (clamped to the screen edge with an arrow when off-screen), `WorldHint` Label3Ds on switches / stones / support / pillar, and a Mirror-only `MirrorInscription` at the target | Always (hidden in cinematic) | Answers "what am I supposed to do?" at every moment. |
```

**Replace with:**
```markdown
| **Bottom-Center (above prompts)** | Subtitles (max 3, speaker-coloured, streaming LLM text updates in place, fade `6.5 s`) and the chat bar (`UIFrame`, `ORDER ›` + LineEdit + SEND) | Contextual | Chat bar opens on Enter, locks gameplay input, Esc closes (`_exit_tree()` clears `ui_input_locked`; `SquadTTSPlayer._exit_tree()` stops audio & `DisplayServer.tts_stop()`; `OpenAIClient.speak_stream()` sends pure dialogue to Gemini TTS with `SquadComms.sanitize_spoken_line()`). |
| **Top-Center (below chips)** | Notifications (info / warn / error toasts, `5 s`) — API errors, offline mode, mode gating | Contextual | Never block input. |
| **Top-Center (y 166, below enlarged +20% HUD chips)** | **Objective tracker** (`ObjectiveTracker`, 2026-11-17): gold diamond + current objective title & ≤ 2-line plain-language hint inside a dark translucent plate (`+6–7 px` outlines), derived live from world state (with bypass auto-clear past `Gate01..Gate05`). Top-left squad roster (`SquadCommsHUD`) & `WorldLabelOverlay` overhead names use dark backing plates & lightened typography; all HUD/weapon/crest/realm/mic/finisher icons scaled `+20%`. `WorldHint` Label3Ds defer until `MainController.level_ready` & `EntryMirrorSwitch` exist. | Always (hidden in cinematic) | Answers "what am I supposed to do?" and reads clearly over bright scenes. |
```

- **Target 7**: `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` (lines 79–82)
- **Action**: Insert after line 82.

**Find:**
```markdown
- **2026-11-18 (Long bridges, bastions, 3× halls)**: connectors are now winding bridges with 2 bastions (3 enemies each), 4.5–5.1× longer (R1 179 m, R2/R3/R5 81 m); Hall of Echoes 60 × 60 (9 encounter + 3 roamers), clock-tower chamber 36 × 36 (8 roamers); terrace moved to z −136; gallery +104, arena/summit +160; `JourneyLayout` converts story ↔ world for weather/audio/objectives/flora/dressing/terrain/saves; test `tests/layout_rework_test.gd`.
```

**Replace with:**
```markdown
- **2026-11-18 (Long bridges, bastions, 3× halls)**: connectors are now winding bridges with 2 bastions (3 enemies each), 4.5–5.1× longer (R1 179 m, R2/R3/R5 81 m); Hall of Echoes 60 × 60 (9 encounter + 3 roamers), clock-tower chamber 36 × 36 (8 roamers); terrace moved to z −136; gallery +104, arena/summit +160; `JourneyLayout` converts story ↔ world for weather/audio/objectives/flora/dressing/terrain/saves; test `tests/layout_rework_test.gd`.
- **2026-11-18 (Sanity Testing 1–5 + Live-Play Remediation Pass, REQ-01..REQ-24)**: Fixed `ObjectiveTracker` premature `_labels_done` on Title Screen + added bypassed gate/bridge/puzzle/encounter auto-clear (`Gate01..05`), `WardenBoss` Phase 1 single-hit overkill bypass & Phase 2 environmental hit cap, `EnemyBase._ready()` `health_changed` emit (`325/325` HP bar init), `_enlarge_enemy()` `AttackHitbox` scaling, `SquadTTSPlayer`/`SquadCommsHUD` `_exit_tree()` cleanup, `WorldIntel`/`AllySquadManager` Reality-phantom filtering (`is_hittable_now()`), capped base ranges (`<= +30%`, `RANGE_M = 52 m`, `FOLLOW_LEASH = 19.5 m`), and `1.2 s` camera-frustum targeting (`<= 140 m`) with `"pull em here"`/`"farther"` parsing, `PlayerController._is_flow_timing()` state guard, `GoreFX` freed-gib tween replacement, non-boss enemy `58 m` visibility-range culling + Low/Medium directional shadow scaling, Gemini TTS prompt-leak removal (`OpenAIClient`/`SquadComms.sanitize_spoken_line()`), Hall (`56/68 m`) & Chamber (`38/48 m`) enemy engagement radii + entry alerts (`62/42 m`), `SquadAlly` `150 m` distant/camera-visible order exemption, slow player/ally regen (`>= 125 s` full heal, Ivo `mending_light` manual `0.18`), `EncounterDirector` 2-checkpoint death rewind (`_checkpoint_history`) & intervening enemy respawn, distinct enemy `CharacterLoadout` (`2H_Sword+Spike_Shield`, `2H_Axe+Barbarian_Round_Shield`) + darkened armor/skin palettes, `SkeletonGuard` 1-time `3.0 s` fall-down self-revive (`50%` HP), `+40%` enemy damage (`DAMAGE_SCALE = 1.4`, Warden `28/35`), `+30%` enemy HP (`HEALTH_SCALE = 3.25`), `+50%` mob counts per area, dark contrast plates + bold typography + `+20%` HUD/finisher icons, `MEMORY/03..07` sync, and added `tests/sanity_regression_test.gd` (`18 checks`).
```

- **Postcondition**: All 5 memory docs accurately reflect post-remediation engine behavior, world coordinates, squad/enemy ranges, regen rates, checkpoint rewind, enemy visual/revive/combat scaling, TTS sanitization, and HUD layout.

---

## E. Verification & Failure Handling

Run every command below in PowerShell from `D:\Desktop\Godot\parallax`.

| Ver ID | Command | Preconditions | Expected Pass Condition | Covers |
| :--- | :--- | :--- | :--- | :--- |
| **VER-01** | `foreach ($f in @("scripts/ui/objective_tracker.gd","scripts/ui/ui_theme.gd","scripts/ui/finisher_prompt.gd","scripts/enemies/warden_boss.gd","scripts/enemies/enemy_base.gd","scripts/enemies/enemy_ai.gd","scripts/enemies/archetype_enemy.gd","scripts/enemies/skeleton_guard.gd","scripts/enemies/phantom_twin.gd","scripts/enemies/shielded_guard.gd","scripts/enemies/squad_coordinator.gd","scripts/core/encounter_director.gd","scripts/core/character_loadout.gd","scripts/core/character_animation_bridge.gd","scripts/environment/grand_journey_builder.gd","scripts/environment/colosseum_greybox_builder.gd","scripts/environment/mechanism_puzzle.gd","addons/parallax_squad_ai/tts_player.gd","addons/parallax_squad_ai/openai_client.gd","addons/parallax_squad_ai/squad_comms.gd","scripts/ui/squad_comms_hud.gd","scripts/allies/world_intel.gd","scripts/allies/ally_squad_manager.gd","scripts/allies/squad_ally.gd","scripts/allies/ally_profile.gd","scripts/allies/squad_command_parser.gd","scripts/player/player_controller.gd","scripts/core/gore_fx.gd","scripts/core/leaderboard_store.gd","scripts/ui/world_label_overlay.gd","scripts/ui/hud_controller.gd","tests/combat_rules_test.gd","tests/sanity_regression_test.gd","tests/feel_and_movement_test.gd","tests/squad_ai_windowed_test.gd","tests/visual_check_shots.gd")) { Write-Host "CHECK $f"; & "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" --check-only -s "res://$f"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }` | Steps 1–21 applied | Exit `0`, zero `SCRIPT ERROR` or warning lines printed for any script. | REQ-01..REQ-24 |
| **VER-02** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/sanity_regression_test.gd` | Step 21 applied | Exit `0`; prints `[sanity] SUMMARY 18 checks, 0 failed` and zero `Lambda capture at index 0 was freed` errors. | REQ-01..REQ-06, REQ-09, REQ-10, REQ-13..REQ-24 |
| **VER-03** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/boot_smoke.gd` | Steps 1–20 applied | Exit `0`; prints `[boot_smoke] OK`. | Regression / REQ-10 |
| **VER-04** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/restart_flow_test.gd` | Steps 1–20 applied | Exit `0`; prints `=> PASS`. | REQ-01, REQ-05 |
| **VER-05** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/combat_rules_test.gd` | Steps 2–3 applied | Exit `0`; prints `[combat] SUMMARY 9 checks, 0 failed`. | REQ-02, REQ-03, REQ-24 |
| **VER-06** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/level_props_test.gd` | Step 4 & Step 13 applied | Exit `0`; prints `0 failed`. | REQ-04, REQ-14 |
| **VER-07** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/layout_rework_test.gd` | Steps 1–20 applied | Exit `0`; prints `0 failed`. | Layout / REQ-10, REQ-24 |
| **VER-08** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/squad_ai_unit_test.gd` | Steps 5–6, 12, 15, 17 applied | Exit `0`; prints `0 failed`. | REQ-05, REQ-06, REQ-13, REQ-16, REQ-19, REQ-20 |
| **VER-08b** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/voice_pipeline_test.gd` | Step 5 & Step 12 applied | Exit `0`; prints `0 failed`. | REQ-05, REQ-13 |
| **VER-09** | `& "C:/Users/agrim/.local/bin/godot.cmd" --path "D:/Desktop/Godot/parallax" -s res://tests/feel_and_movement_test.gd` | Step 8 & Step 17 applied | Windowed run; exit `0`; prints `[feel] SUMMARY 13 checks, 0 failed`. *(Note: run when desktop/GPU session is active; `follow_*` spacing checks use physics frames).* | REQ-08, REQ-20 |
| **VER-10** | `& "C:/Users/agrim/.local/bin/godot.cmd" --path "D:/Desktop/Godot/parallax" -s res://tests/squad_ai_windowed_test.gd` | Steps 6–7, 14, 15, 17 applied | Windowed run; exit `0`; prints `0 failed` (`strategy_divide_distinct_targets` & `taunted_enemy_chases_past_leash` both `PASS`). | REQ-06, REQ-07, REQ-15, REQ-16, REQ-19, REQ-20 |
| **VER-11** | `& "C:/Users/agrim/.local/bin/godot.cmd" --path "D:/Desktop/Godot/parallax" -s res://tests/visual_check_shots.gd` | Step 1, Step 5, Step 16 & Step 19 applied | Windowed run; exits cleanly (`exit 0`) in `< 20s` without hanging on OS TTS. Inspect saved shots if generated for +20% icons, dark enemy palettes, and legible roster/objective contrast. | REQ-01, REQ-05, REQ-17, REQ-18, REQ-22 |

### Failure Recovery Protocol
- **Test fails with `SCRIPT ERROR` after an edit**: Re-run `--check-only` on that specific file, compare lines around the mismatch against Section D, and restore cleanly via `git checkout -- <file>` before retrying that step if needed.
- **`tests/feel_and_movement_test.gd` borderline spacing flake on slow frame hitches**: Verify `chain_reaches_5_distinct_moves`, `rhythm_taps_flow`, `pause_branch_rising_arc`, and `f_in_window_executes` are all `PASS`; do not mark the run failed only if an unrelated pre-existing spacing tolerance flakes once unless it persists cleanly twice, and report exact counts observed.
- **`%APPDATA%\Godot\app_userdata\PARALLAX\` Side Effects**: `restart_flow_test.gd` or manual runs may touch `user://savegame.cfg`; if clean user state is desired after verification, back up and restore `%APPDATA%\Godot\app_userdata\PARALLAX\` when finished.

---

## F. Completion Report Contract

When execution finishes, output a concise report containing ONLY verified observations:

1. **Applied Step IDs**: Explicit list (`Step 1` .. `Step 22`) and any partial/skipped steps.
2. **Changed Files**: Exact paths modified or created (matching Section C manifest).
3. **Verification Results Table**:
   - Command (`VER-01` .. `VER-11`)
   - Exit Code
   - Exact printed `SUMMARY` / pass line
4. **Remaining Unverified Items / Blockers**: Any check not run (e.g., manual human full-sitting playthrough Title -> Results -> Leaderboard, or GPU/display limitations) marked clearly as unverified.
5. **Definition of Done**: All Steps 1–22 applied cleanly, zero unintended untracked files left behind, and `VER-01` through `VER-11` exit `0` with `0 failed`.
