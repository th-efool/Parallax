# IdiotHandOffGuide (Guide 04) — Spawning, Respawning, Section Reset, UI Gating, Audio Singleton & Save Persistence

> **Scope**: Single self-contained handoff to resolve all **15 assigned bugs** (`SRS-01`..`SRS-15`: `8🔴 CRIT`, `6🟡 WARN`, `1🔵 LOW`) across Spawning/Loading race conditions, Death-Rewind & Section Resets, Continue/Save Persistence, Ally Startup Spawning, Title/Results/Pause UI Gating, Duplicate AudioManager Singleton, Player Respawn State Reset, Options Rebind Preservation, and WeatherDirector Warden Binding.
> **Readiness**: `READY` (all target files, line anchors, node paths, signals, physics layers, and existing test contracts verified by static inspection against the working tree at commit `1ca7464`).
> **Execution Order Across Guides**: Apply in strict sequence **`01 -> 02 -> 03 -> 04`**. Ownership boundaries prevent collisions with Guide 01 (`player_controller.gd` outside `:1442-1481`), Guide 02 (`archetype_enemy.gd`, `skeleton_guard.gd`), and Guide 03 (`ally_squad_manager.gd` `:217..1509`, `squad_ally.gd`).
> **Executor Rule**: Apply Steps 1–11 in exact order, run every verification check in Section E (`VER-01`..`VER-06`), and return the Section F completion report. Do **not** create extra `.md` files in the repo root or `MEMORY/`.

---

## A. Execution Contract

### A.1 Repository & Runtime Baseline (Observed Before Handoff)
- **Repository Root**: `D:\Desktop\Godot\parallax`
- **Branch / HEAD Commit**: `master` @ `1ca7464`
- **Engine Binary**: `C:/Users/agrim/.local/bin/godot.cmd` (`Godot Engine v4.7.2.stable.official.ed1daf0bf`, Forward+, Windows 64-bit)
- **Shell**: PowerShell (Windows)
- **Working Tree State at `1ca7464`**: Clean tracked working tree (only untracked `plan/IdiotHandOffGuide_01_Combat.md`, `plan/IdiotHandOffGuide_02_EnemiesAI.md`, and `plan/IdiotHandOffGuide_03_FriendsAI.md` present prior to writing this guide).
- **Cross-Guide Predecessors**:
  - `plan/IdiotHandOffGuide_01_Combat.md` (`CMB-01..19`)
  - `plan/IdiotHandOffGuide_02_EnemiesAI.md` (`ENM-01..26`)
  - `plan/IdiotHandOffGuide_03_FriendsAI.md` (`ALY-01..24`)
- **Author Validation Status Prior to Execution**:
  - Derived entirely from **static inspection** of source scripts, scene files (`scenes/main/main.tscn`), `project.godot`, `MEMORY/02`–`07`, existing tests (`tests/restart_flow_test.gd`, `tests/sanity_regression_test.gd`, `tests/boot_smoke.gd`), and sibling Guides 01–03. **None of the patches in Section D have been applied to the workspace yet**; the executor is responsible for applying them and running Section E to verify all checks pass.

### A.2 Preserved Design Invariants (`REQ-14`, `REQ-15`, `REQ-20`, `REQ-21`, `1ca7464`)
1. Preserve `EncounterDirector.handle_player_death()` **2-checkpoint rewind** (`_checkpoint_history` index `size - 3`, clamped `>= 0`) while fixing `SRS-02` cleanly across every rewound section (`checkpoint_section .. failed_section`).
2. Preserve `HEALTH_SCALE = 3.25`, `DAMAGE_SCALE = 1.4`, 2-charge stacked dodge chaining, `player_execution` shield pierce, slow `125 s` regen, `WorldIntel` camera-visible targeting (`<= 140 m`), and `SkeletonGuard` 1-time `3.0 s` self-revive.
3. Preserve passing behavior of `tests/restart_flow_test.gd`, `tests/sanity_regression_test.gd`, and `tests/boot_smoke.gd`.

### A.3 Strict Operating Rules for the Executor
1. **Verify Baseline First**: Confirm `git branch --show-current` is `master`, and apply Guides `01 -> 02 -> 03` before running this guide (`04`).
2. **Apply Steps 1–11 In Exact Order**: Every edit uses exact `**Target:**`, `**Action:**`, `**Find:**`, and `**Replace with:**` (or `**Content:**`) fenced blocks. If multiple edits touch the same file, each subsequent `**Find:**` matches the intermediate state left by earlier edits in the same file. If any `**Find:**` fails to match uniquely, **STOP**, report the file path and actual surrounding lines, and do not guess.
3. **Strict Ownership Boundaries**:
   - In `scripts/player/player_controller.gd`, edit **ONLY** `respawn_at()` and `_verify_spawn_safety()` (`:1442-1481`). Guide 01 owns all other regions.
   - In `scripts/allies/ally_squad_manager.gd`, edit **ONLY** lines `:47-86` (`_ready()` / `_maybe_initial_spawn()` / `spawn_squad()` / `_spawn_squad()` entry guard). Guide 03 owns lines `:217..1509`.
   - Do **not** touch `scripts/enemies/archetype_enemy.gd`, `scripts/enemies/skeleton_guard.gd`, or `scripts/allies/squad_ally.gd`.
   - Never create extra `.md` files in repo root or `MEMORY/` (`AGENTS.md` Rule 1.2).
4. **No Temporary Leftover Files**: Only files listed in Section C may be modified or created (`tests/spawning_save_bugfix_regression_test.gd` is permanent). Ensure any temporary `user://_test_srs_*` artifacts created by the regression test are deleted cleanly by the test itself.
5. **Preserve `MEMORY/07` Anchor Line**: Step 11 (`Edit 11F`) matches line 153 of `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` verbatim (`- 2026-11-19: Stacked Dodge Chaining & Execution Shield Pierce - ...`) and appends immediately below it without altering that line.

---

## B. Requirements & Acceptance Map

### B.1 In-Scope Assigned Requirements (`SRS-01` .. `SRS-15`: `8🔴 CRIT`, `6🟡 WARN`, `1🔵 LOW`)

| Req ID | Severity | Target Location | Defect Summary & Expected Observable Behavior | Implementing Step(s) | Verification ID(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **SRS-01** | 🔴 CRIT | `scripts/core/main_controller.gd`<br>`scripts/environment/section_trigger_volume.gd` | Continuing a saved run calls `build_greybox_progressive()` before `apply_saved_world_state()`, allowing `Trigger_Stage01_Entry` to overlap inactive `Player` at `(0, 0, -136)` and fire `advance_to_section(ENTRY, ..., true)` -> `_trigger_auto_save()`, overwriting `user://savegame.cfg`. **Expected**: `SectionTriggerVolume` blocks triggers until `MainController.level_ready` is `true` and `player.process_mode != PROCESS_MODE_DISABLED`; `MainController._begin_run_loading()` also disables `EncounterDirector.auto_save_on_checkpoint` across build/load. | Step 3 (`3E`), Step 8 (`8C`) | `VER-01`, `VER-02` (`srs01`), `VER-03` |
| **SRS-02** | 🔴 CRIT | `scripts/core/encounter_director.gd`<br>`scripts/environment/encounter_gate.gd`<br>`scripts/environment/interact_switch.gd`<br>`scripts/environment/mechanism_puzzle.gd`<br>`scripts/environment/realm_platform.gd`<br>`scripts/core/score_manager.gd` | `handle_player_death()` overwrites `current_section` before collecting `sections_to_clear`, only emits `section_reset_requested` for `completed_sections` + double-emits `checkpoint_section`, never emits for `failed_section`, leaves `completed_encounters` stale, and leaves `EncounterGate` (`is_permanently_unlocked`), `InteractSwitch`, `MechanismPuzzle`, and `RealmPlatform` unreset across rewound sections. **Expected**: Deduplicated ascending reset signals emit once per section across `checkpoint_section .. max(completed, failed_section)` before realm restore & respawn; rewound `completed_encounters` and `ScoreManager.current_active_encounter` clear; gates, switches, puzzles, breakables, enemies, and spectral bridge reset cleanly. | Step 2 (`2B`), Step 3 (`3A`–`3D`), Step 4 (`4B`) | `VER-01`, `VER-02` (`srs02`), `VER-03`, `VER-04` |
| **SRS-03** | 🔴 CRIT | `scripts/core/leaderboard_store.gd`<br>`scripts/core/encounter_director.gd` | `capture_and_save_world_state()` omits `_checkpoint_history` and `apply_saved_world_state()` leaves `_checkpoint_history` with only Stage 01 `(0, 0, -136)`, so first death or Restart Section after Continue rewinds Stage 02–05 all the way to Stage 01. **Expected**: Save snapshot persists `checkpoint_history` (`section`, `position`, `rotation_y`, `realm`) with `JourneyLayout.to_world()` migration for `layout_version < VERSION`, and `EncounterDirector.restore_checkpoint_history()` restores saved checkpoints (and synthesizes missing intermediate entries for legacy saves). | Step 4 (`4C`), Step 5 (`5B`, `5C`, `5D`) | `VER-01`, `VER-02` (`srs03`), `VER-03` |
| **SRS-04** | 🔴 CRIT | `scripts/environment/section_trigger_volume.gd` | `_on_section_reset_requested()` sets `has_triggered = false` AND immediately calls `ed.begin_combat_encounter()`, causing the next physics tick inside the trigger to double-save and double-start combat (wave-clear soft-lock / premature Hall start). **Expected**: `_on_section_reset_requested()` only re-arms `has_triggered = false` for the matching reset section (`reset_sec_id == target_section`) when the encounter is incomplete, never calling `begin_combat_encounter()`. | Step 3 (`3E`) | `VER-01`, `VER-02` (`srs04`) |
| **SRS-05** | 🔴 CRIT | `scripts/allies/ally_squad_manager.gd`<br>`scripts/core/main_controller.gd`<br>`scripts/core/encounter_director.gd`<br>`scripts/core/leaderboard_store.gd` | `AllySquad._ready()` runs before `MainController._ready()` and spawns allies via `call_deferred("_spawn_squad")` before floors exist (void fall behind Title/Loading), and `restart_full_run()` / `apply_saved_world_state()` omit `regroup(true)`. **Expected**: `MainController._enter_tree()` registers `"main_controller"` before child `_ready()`, `AllySquadManager._maybe_initial_spawn()` skips spawning until `MainController.level_ready` (while standalone tests without `MainController` still spawn), `MainController._begin_run_loading()` calls `spawn_squad()` after floor build & checkpoint placement, and both `restart_full_run()` and `apply_saved_world_state()` call `regroup(true)` when allies already exist. | Step 4 (`4D`), Step 5 (`5D`), Step 7 (`7A`), Step 8 (`8C`) | `VER-01`, `VER-02` (`srs05`), `VER-03`, `VER-05` |
| **SRS-06** | 🔴 CRIT | `scripts/core/main_controller.gd`<br>`scripts/core/realm_manager.gd`<br>`scripts/ui/title_screen_controller.gd`<br>`scripts/ui/results_screen_controller.gd` | Returning to Title / presenting Results leaves world unpaused & player killable behind Title, `TitleScreenController` lets `KEY_Q` leak through to `RealmManager`, and typing initials on Results drives live player movement/attacks. **Expected**: Returning to Title or presenting Results pauses `SceneTree`, disables `Player`, and hides `HUD`; `ResultsScreenController` sets `PlayerController.ui_input_locked = true` while shown and clears it on exit; `TitleScreenController` calls `set_input_as_handled()` on `KEY_Q`; `RealmManager._unhandled_input()` rejects shifts when `MainController.is_gameplay_active()` is `false` (including during LoadingScreen) or `ui_input_locked` is `true`. | Step 8 (`8A`, `8C`), Step 9 (`9A`, `9D`) | `VER-01`, `VER-02` (`srs06`) |
| **SRS-07** | 🔴 CRIT | `scripts/ui/pause_menu_controller.gd`<br>`scripts/core/main_controller.gd` | `Esc` toggle works on Title, Loading, Results, and Dead screens, corrupting saves, timer state, and respawns. **Expected**: `PauseMenuController._can_toggle_pause()` blocks pausing whenever Title/Results/Loading is active, `MainController.level_ready` is `false` / `_building` / `_loading != null`, or `Player` is `DEAD`/disabled. | Step 8 (`8C`), Step 9 (`9B`) | `VER-01`, `VER-02` (`srs07`) |
| **SRS-08** | 🔴 CRIT | `scripts/core/score_manager.gd` | `ScoreManager.finalize_run()` has no idempotency guard, so `WardenBoss._die()` + `Trigger_RunComplete` double-finalize, double-incrementing `total_runs_completed` and double-emitting `run_finalized`. **Expected**: `_run_finalized: bool` + `_final_summary: Dictionary` ensure `finalize_run()` executes once per run (reset in `start_new_run()`) and returns cached summary on repeat calls. | Step 2 (`2A`, `2C`) | `VER-01`, `VER-02` (`srs08`) |
| **SRS-09** | 🟡 WARN | `scenes/main/main.tscn`<br>`scripts/core/main_controller.gd`<br>`scripts/core/audio_manager.gd` | `scenes/main/main.tscn` instances a duplicate `Main/AudioManager` alongside `GameAudio` autoload, playing SFX twice and breaking realm/world binding across `reload_current_scene()`. **Expected**: Remove `Main/AudioManager` & `ExtResource("5_audio")` (`load_steps=16`) from `main.tscn`, guard `AudioManager._ready()` against duplicate non-singleton instances, resolve `GameAudio` / `AudioManager.instance` in `MainController._get_audio_manager()`, and reset `_warden_dead` in `AudioManager.bind_to_world()` unless a dead `WardenBoss` is present. | Step 1 (`1A`–`1C`), Step 8 (`8C`) | `VER-01`, `VER-02` (`srs09`), `VER-03`, `VER-05` |
| **SRS-10** | 🟡 WARN | `scripts/core/encounter_director.gd` | `_enter_tree()` and `restart_full_run()` initialize `_checkpoint_history` with `default_spawn` `(0, 0, -136)` while leaving `checkpoint_transform` at `Transform3D.IDENTITY` `(0, 0, 0)` above Stage 01 pit. **Expected**: Set `checkpoint_transform = default_spawn` in both `_enter_tree()` and `restart_full_run()`. | Step 4 (`4A`, `4D`) | `VER-01`, `VER-02` (`srs10`) |
| **SRS-11** | 🟡 WARN | `scripts/core/leaderboard_store.gd`<br>`scripts/ui/pause_menu_controller.gd` | `capture_and_save_world_state()` only persists `banked_score` (dropping live unbanked `score` + `awarded_event_ids`), and `_save_*_to_disk()` ignore `cfg.save()` errors while Pause unconditionally displays `"CHECKPOINT SAVED"`. **Expected**: Save & restore both `score`/`awarded_event_ids` and `banked_score`/`_banked_event_ids`; propagate `cfg.save()` errors via `last_save_error` and `_save_ok`; Pause shows `"SAVE FAILED"` on disk errors. | Step 5 (`5A`–`5E`), Step 9 (`9B`) | `VER-01`, `VER-02` (`srs11`) |
| **SRS-12** | 🟡 WARN | `scripts/core/leaderboard_store.gd` | `apply_saved_world_state()` omits `force_solve_bypass()` on `ChamberMechanismPuzzle`, omits `completed_encounters["the_warden"]` restoration (`TheWarden`, `CentralMirrorPlane`, `Gate05_ArenaExit`), never marks passed `SectionTriggerVolume`s `has_triggered = true`, and leaves active mid-encounter saves unsealed. **Expected**: Restore `force_solve_bypass()`, Warden defeat state, passed trigger `has_triggered = true`, and active uncompleted encounter seal/count on Continue. | Step 5 (`5D`) | `VER-01`, `VER-02` (`srs12`) |
| **SRS-13** | 🟡 WARN | `scripts/player/player_controller.gd` | `_verify_spawn_safety()` raycasts `0xFFFFFFFF` without excluding `[get_rid()]` or guarding `get_world_3d()`; `respawn_at()` leaves `stamina`, `_health_regen_acc`, `_flow_streak`, `_flow_tap`, `_ally_ward_hp`, `_ally_ward_until_ms`, `_finisher_cooldown_end_ms`, and `_jump_buffer_timer` unreset. **Expected**: Guard `_verify_spawn_safety()` against null world space, use active realm world collision mask + `[get_rid()]` exclude, and reset all stamina/flow/ward/cooldown/buffer fields in `respawn_at()`. | Step 6 (`6A`) | `VER-01`, `VER-02` (`srs13`) |
| **SRS-14** | 🟡 WARN | `scripts/ui/options_screen_controller.gd` | `try_rebind_action()` and `press_reset_controls()` overwrite all of `working_settings` with `store.get_settings()`, discarding unsaved Display/Graphics/Sound/Gameplay changes. **Expected**: Refresh only `working_settings["keybindings"]` on rebind/reset while keeping unsaved non-keybind changes intact until `press_apply()`. | Step 9 (`9C`) | `VER-01`, `VER-02` (`srs14`) |
| **SRS-15** | 🔵 LOW | `scripts/environment/weather_director.gd`<br>`scripts/core/main_controller.gd` | `WeatherDirector._ready()` runs `call_deferred("_bind_warden")` on Title Screen before `TheWarden` exists and never retries, so Phase 2 `blood_frenzy` and post-kill `aftermath` weather never activate. **Expected**: Add `bind_warden(warden_override)` with named idempotent handlers and group/`_process()` fallback, invoked explicitly from `MainController._wire_level_dependent()`. | Step 8 (`8B`, `8C`) | `VER-01`, `VER-02` (`srs15`) |

### B.2 Explicit Cross-Guide Notes (Out-of-Scope Symbols Owned Elsewhere)
- `scripts/enemies/archetype_enemy.gd:48` (`DAMAGE_SCALE` double-apply/fix) and `scripts/enemies/skeleton_guard.gd:41` (`self-revive` exclusions) are owned and fixed in **Guide 02** (`ENM-07`, `ENM-03`).
- `scripts/allies/squad_ally.gd:3431` (ally AI/navigation/revive/heal/combat fixes) is owned and fixed in **Guide 03** (`ALY-05`).
- None of those 3 files are modified by this guide.

---

## C. File-Change Manifest

| File Path (Relative to Repo Root) | Operation | Step ID | Purpose / Scope |
| :--- | :--- | :--- | :--- |
| `scenes/main/main.tscn` | `modify` | Step 1 | Remove duplicate `[node name="AudioManager"]` & `ExtResource("5_audio")`; decrement `load_steps` `17 -> 16` (`SRS-09`). |
| `scripts/core/audio_manager.gd` | `modify` | Step 1 | Guard duplicate non-singleton `_ready()`, reset `_warden_dead` cleanly on `bind_to_world()` (`SRS-09`). |
| `scripts/core/score_manager.gd` | `modify` | Step 2 | Add `_run_finalized` idempotency guard (`SRS-08`); clear `current_active_encounter` on `revert_to_banked_score()` (`SRS-02`). |
| `scripts/environment/encounter_gate.gd` | `modify` | Step 3 | Allow `_on_section_reset_requested()` to reset `is_permanently_unlocked = false` for rewound sections (`SRS-02`). |
| `scripts/environment/interact_switch.gd` | `modify` | Step 3 | Add `section_id` inference and `section_reset_requested` listener resetting switch state (`SRS-02`). |
| `scripts/environment/mechanism_puzzle.gd` | `modify` | Step 3 | Add `section_id = 3` and `section_reset_requested` listener invoking `reset_puzzle()` (`SRS-02`). |
| `scripts/environment/realm_platform.gd` | `modify` | Step 3 | Add `section_id` inference and `section_reset_requested` listener resetting `is_permanently_repaired` (`SRS-02`). |
| `scripts/environment/section_trigger_volume.gd` | `modify` | Step 3 | Gate triggers on `MainController.level_ready` & active player (`SRS-01`); remove `begin_combat_encounter()` from `_on_section_reset_requested()` (`SRS-04`). |
| `scripts/core/encounter_director.gd` | `modify` | Step 4 | Set `checkpoint_transform = default_spawn` (`SRS-10`); deduplicated `checkpoint_section..failed_section` resets + encounter clear + realm order fix (`SRS-02`); `restore_checkpoint_history()` (`SRS-03`); `regroup(true)` on `restart_full_run()` (`SRS-05`). |
| `scripts/core/leaderboard_store.gd` | `modify` | Step 5 | Serialize/restore `checkpoint_history` with layout migration (`SRS-03`); persist live `score`/`awarded_event_ids` (`SRS-11`); propagate `cfg.save()` errors (`SRS-11`); restore `force_solve_bypass()`, `the_warden`, passed triggers, active mid-section encounter (`SRS-12`), and ally `regroup(true)` (`SRS-05`). |
| `scripts/player/player_controller.gd` | `modify` | Step 6 | **ONLY `:1442-1481`**: harden `_verify_spawn_safety()` world mask + `[get_rid()]` + null guard; reset remaining stamina/flow/ward/cooldown/buffer fields in `respawn_at()` (`SRS-13`). |
| `scripts/allies/ally_squad_manager.gd` | `modify` | Step 7 | **ONLY `:47-86`**: defer squad spawn until `MainController.level_ready` via `_maybe_initial_spawn()` & `spawn_squad()` (`SRS-05`). |
| `scripts/core/realm_manager.gd` | `modify` | Step 8 | Gate `dimension_shift` input on `MainController.is_gameplay_active()` and `not PlayerController.ui_input_locked` (`SRS-06`). |
| `scripts/environment/weather_director.gd` | `modify` | Step 8 | Add idempotent `bind_warden()` with named handlers, group lookup, initial state sync, and `_process()` fallback (`SRS-15`). |
| `scripts/core/main_controller.gd` | `modify` | Step 8 | Add `_enter_tree()` group (`SRS-05`); `level_ready` / `_loading` check in `is_gameplay_active()` (`SRS-06`, `SRS-07`); `_get_audio_manager()` (`SRS-09`); `WeatherDirector.bind_warden()` (`SRS-15`); autosave suppression & `spawn_squad()` in `_begin_run_loading()` (`SRS-01`, `SRS-05`); pause/freeze on Results & Return-to-Title (`SRS-06`). |
| `scripts/ui/title_screen_controller.gd` | `modify` | Step 9 | Mark `KEY_Q` handled (`set_input_as_handled()`) on Title Screen (`SRS-06`). |
| `scripts/ui/pause_menu_controller.gd` | `modify` | Step 9 | Add `_can_toggle_pause()` blocking Title/Loading/Results/Dead (`SRS-07`); display `"SAVE FAILED"` on disk save error (`SRS-11`). |
| `scripts/ui/options_screen_controller.gd` | `modify` | Step 9 | Merge only `keybindings` into `working_settings` on `try_rebind_action()` / `press_reset_controls()` (`SRS-14`). |
| `scripts/ui/results_screen_controller.gd` | `modify` | Step 9 | Lock/unlock `PlayerController.ui_input_locked` while Results screen is shown (`SRS-06`). |
| `tests/spawning_save_bugfix_regression_test.gd` | `create` | Step 10 | Headless regression suite covering all 15 fixes `SRS-01`..`SRS-15` using isolated temp `user://` files. |
| `MEMORY/02_CORE_SYSTEMS_AND_ARCHITECTURE.md` | `modify` | Step 11 | Sync Main scene hierarchy (`GameAudio` autoload), checkpoint rewind, squad spawn gating, and save/restore lifecycle contracts. |
| `MEMORY/05_UI_SCORING_AND_AUDIO.md` | `modify` | Step 11 | Sync `finalize_run` idempotency, Pause/Results/Options input & error feedback contracts, and `GameAudio` singleton reload contract. |
| `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | `modify` | Step 11 | Append dated Guide 04 changelog summary preserving line 153 verbatim. |

---

## D. Ordered Implementation Steps

### Step 1 — Remove Duplicate `Main/AudioManager` & Harden `AudioManager` Singleton Binding (`SRS-09`)

- **Prerequisite**: Clean `1ca7464` tree (or after Guides 01–03).
- **Postcondition**: `scenes/main/main.tscn` relies solely on the `GameAudio` autoload; `AudioManager._ready()` skips duplicate initialization if `instance` is already live; `bind_to_world()` resets `_warden_dead` safely across `reload_current_scene()`.

#### Edit 1A — Remove `5_audio` `ExtResource` & Decrement `load_steps` in `scenes/main/main.tscn`
**Target:** `scenes/main/main.tscn`
**Action:** Replace block
**Find:**
```ini
[gd_scene load_steps=17 format=3]

[ext_resource type="Script" path="res://scripts/core/main_controller.gd" id="1_main"]
[ext_resource type="Script" path="res://scripts/core/realm_manager.gd" id="2_rm"]
[ext_resource type="Script" path="res://scripts/core/encounter_director.gd" id="3_ed"]
[ext_resource type="Script" path="res://scripts/environment/realm_environment_controller.gd" id="4_env"]
[ext_resource type="Script" path="res://scripts/core/audio_manager.gd" id="5_audio"]
[ext_resource type="PackedScene" path="res://scenes/environment/ambient_life.tscn" id="20_ambient"]
```
**Replace with:**
```ini
[gd_scene load_steps=16 format=3]

[ext_resource type="Script" path="res://scripts/core/main_controller.gd" id="1_main"]
[ext_resource type="Script" path="res://scripts/core/realm_manager.gd" id="2_rm"]
[ext_resource type="Script" path="res://scripts/core/encounter_director.gd" id="3_ed"]
[ext_resource type="Script" path="res://scripts/environment/realm_environment_controller.gd" id="4_env"]
[ext_resource type="PackedScene" path="res://scenes/environment/ambient_life.tscn" id="20_ambient"]
```

#### Edit 1B — Remove `[node name="AudioManager"]` from `scenes/main/main.tscn`
**Target:** `scenes/main/main.tscn`
**Action:** Replace block
**Find:**
```ini
mouse_filter = 2

[node name="AudioManager" type="Node" parent="."]
script = ExtResource("5_audio")

[node name="LevelRoot" parent="." instance=ExtResource("6_level")]
```
**Replace with:**
```ini
mouse_filter = 2

[node name="LevelRoot" parent="." instance=ExtResource("6_level")]
```

#### Edit 1C — Guard Duplicate `_ready()` & Reset Per-Run State in `scripts/core/audio_manager.gd`
**Target:** `scripts/core/audio_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("audio_manager")
	_ensure_buses()
	_load_streams()
	_build_players()
	if instance == null or not is_instance_valid(instance):
		instance = self
	bind_singletons()
	if instance == self:
		_ensure_master_lowpass()
		if is_inside_tree() and get_tree() != null:
			if not get_tree().node_added.is_connected(_bind_recursive):
				get_tree().node_added.connect(_bind_recursive)
		call_deferred("_deferred_bind_tree")
		if auto_start_music:
			start_ambient_drone()
```
**Replace with:**
```gdscript
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if instance != null and instance != self and is_instance_valid(instance):
		return
	add_to_group("audio_manager")
	_ensure_buses()
	_load_streams()
	_build_players()
	instance = self
	bind_singletons()
	_ensure_master_lowpass()
	if is_inside_tree() and get_tree() != null:
		if not get_tree().node_added.is_connected(_bind_recursive):
			get_tree().node_added.connect(_bind_recursive)
	call_deferred("_deferred_bind_tree")
	if auto_start_music:
		start_ambient_drone()
```

#### Edit 1D — Reset `_warden_dead` on World Bind & Preserve Dead-Warden State on Continue in `scripts/core/audio_manager.gd`
**Target:** `scripts/core/audio_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
func bind_to_world(root_node: Node) -> void:
	bind_singletons()
	if root_node == null:
		return
	_bind_recursive(root_node)
```
**Replace with:**
```gdscript
func bind_to_world(root_node: Node) -> void:
	bind_singletons()
	if root_node == null:
		return
	_warden_dead = false
	_player_hp = 100
	_bind_recursive(root_node)
```

#### Edit 1E — Sync Dead-Warden State Inside `_bind_recursive()` in `scripts/core/audio_manager.gd`
**Target:** `scripts/core/audio_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
		if node is WardenBoss:
			var wb: WardenBoss = node as WardenBoss
			if not wb.mirror_plane_shattered.is_connected(_on_mirror_plane_shattered):
				wb.mirror_plane_shattered.connect(_on_mirror_plane_shattered)
```
**Replace with:**
```gdscript
		if node is WardenBoss:
			var wb: WardenBoss = node as WardenBoss
			if wb.is_dead:
				_warden_dead = true
			if not wb.mirror_plane_shattered.is_connected(_on_mirror_plane_shattered):
				wb.mirror_plane_shattered.connect(_on_mirror_plane_shattered)
```

---

### Step 2 — Add `ScoreManager.finalize_run()` Idempotency & Clear Stale Encounter State on Revert (`SRS-08`, `SRS-02`)

- **Prerequisite**: Step 1 complete.
- **Postcondition**: Calling `finalize_run()` twice in one run returns the cached summary without double-incrementing `total_runs_completed` or re-emitting `run_finalized`; `revert_to_banked_score()` clears `current_active_encounter` and `encounter_damaged`.

#### Edit 2A — Add Finalization Guard State & Reset in `scripts/core/score_manager.gd`
**Target:** `scripts/core/score_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
var awarded_event_ids: Dictionary = {}
var _banked_event_ids: Dictionary = {}
var warden_defeat_awarded: bool = false
```
**Replace with:**
```gdscript
var awarded_event_ids: Dictionary = {}
var _banked_event_ids: Dictionary = {}
var warden_defeat_awarded: bool = false
var _run_finalized: bool = false
var _final_summary: Dictionary = {}
```

#### Edit 2B — Reset Guard in `start_new_run()` & Clear Encounter State in `revert_to_banked_score()` (`scripts/core/score_manager.gd`)
**Target:** `scripts/core/score_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
	awarded_event_ids.clear()
	_banked_event_ids.clear()
	warden_defeat_awarded = false
	score_changed.emit(score, 0, "reset")
	combo_changed.emit(1, 0, 0.0)
```
**Replace with:**
```gdscript
	awarded_event_ids.clear()
	_banked_event_ids.clear()
	warden_defeat_awarded = false
	_run_finalized = false
	_final_summary.clear()
	score_changed.emit(score, 0, "reset")
	combo_changed.emit(1, 0, 0.0)
```

#### Edit 2C — Guard `finalize_run()` & Clear `current_active_encounter` in `scripts/core/score_manager.gd`
**Target:** `scripts/core/score_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
func revert_to_banked_score() -> void:
	score = banked_score
	combo_hits = 0
	combo_timer = 0.0
	awarded_event_ids = _banked_event_ids.duplicate()
	score_changed.emit(score, 0, "checkpoint_revert")
	combo_changed.emit(1, 0, 0.0)
```
**Replace with:**
```gdscript
func revert_to_banked_score() -> void:
	score = banked_score
	combo_hits = 0
	combo_timer = 0.0
	current_active_encounter = ""
	encounter_damaged.clear()
	awarded_event_ids = _banked_event_ids.duplicate()
	score_changed.emit(score, 0, "checkpoint_revert")
	combo_changed.emit(1, 0, 0.0)
```

#### Edit 2D — Make `finalize_run()` Idempotent in `scripts/core/score_manager.gd`
**Target:** `scripts/core/score_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
func finalize_run(award_warden_bonus: bool = true) -> Dictionary:
	timer_running = false
	var warden_bonus: int = 0
	if award_warden_bonus and not warden_defeat_awarded:
		warden_defeat_awarded = true
		warden_bonus = add_score_event("warden_defeat", false, "warden_defeat_once")

	var time_bonus: int = calculate_time_bonus(elapsed_seconds)
	if time_bonus > 0 and not bool(awarded_event_ids.get("time_bonus_once", false)):
		awarded_event_ids["time_bonus_once"] = true
		score += time_bonus
		score_changed.emit(score, time_bonus, "time_bonus")

	banked_score = score
	_banked_event_ids = awarded_event_ids.duplicate()
	var final_rank: String = calculate_rank(score)
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null:
			if store.has_method("update_profile_stat"):
				store.call("update_profile_stat", "total_runs_completed", 1, true)
			if store.has_method("clear_saved_run"):
				store.call("clear_saved_run", true)

	var summary: Dictionary = {
		"score": score,
		"time_sec": elapsed_seconds,
		"time_bonus": time_bonus,
		"warden_bonus": warden_bonus,
		"rank": final_rank,
		"max_combo": max_combo_multiplier_reached,
	}
	run_finalized.emit(summary)
	return summary
```
**Replace with:**
```gdscript
func finalize_run(award_warden_bonus: bool = true) -> Dictionary:
	if _run_finalized:
		return _final_summary.duplicate(true)
	_run_finalized = true
	timer_running = false
	var warden_bonus: int = 0
	if award_warden_bonus and not warden_defeat_awarded:
		warden_defeat_awarded = true
		warden_bonus = add_score_event("warden_defeat", false, "warden_defeat_once")

	var time_bonus: int = calculate_time_bonus(elapsed_seconds)
	if time_bonus > 0 and not bool(awarded_event_ids.get("time_bonus_once", false)):
		awarded_event_ids["time_bonus_once"] = true
		score += time_bonus
		score_changed.emit(score, time_bonus, "time_bonus")

	banked_score = score
	_banked_event_ids = awarded_event_ids.duplicate()
	var final_rank: String = calculate_rank(score)
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null:
			if store.has_method("update_profile_stat"):
				store.call("update_profile_stat", "total_runs_completed", 1, true)
			if store.has_method("clear_saved_run"):
				store.call("clear_saved_run", true)

	var summary: Dictionary = {
		"score": score,
		"time_sec": elapsed_seconds,
		"time_bonus": time_bonus,
		"warden_bonus": warden_bonus,
		"rank": final_rank,
		"max_combo": max_combo_multiplier_reached,
	}
	_final_summary = summary.duplicate(true)
	run_finalized.emit(summary)
	return summary
```

---

### Step 3 — Add Reset Listeners to Gates/Switches/Puzzles/Platforms & Guard Section Triggers (`SRS-01`, `SRS-02`, `SRS-04`)

- **Prerequisite**: Step 2 complete.
- **Postcondition**: `EncounterGate` unlocks/closes reliably on section rewind; `InteractSwitch`, `MechanismPuzzle`, and `RealmPlatform` subscribe to `section_reset_requested` and restore their unsolved/unrepaired state; `SectionTriggerVolume` never fires while `MainController.level_ready == false` or `player.process_mode == PROCESS_MODE_DISABLED` and never starts combat inside `_on_section_reset_requested()`.

#### Edit 3A — Reset `is_permanently_unlocked` on Rewound Section in `scripts/environment/encounter_gate.gd`
**Target:** `scripts/environment/encounter_gate.gd`
**Action:** Replace block
**Find:**
```gdscript
func _on_section_reset_requested(reset_sec_id: int) -> void:
	if reset_sec_id == section_id and not is_permanently_unlocked:
		is_open = starts_open
		_apply_gate_state()
```
**Replace with:**
```gdscript
func _on_section_reset_requested(reset_sec_id: int) -> void:
	if reset_sec_id == section_id:
		is_permanently_unlocked = false
		is_open = starts_open
		_apply_gate_state()
```

#### Edit 3B — Add `section_id` & Reset Listener to `scripts/environment/interact_switch.gd`
**Target:** `scripts/environment/interact_switch.gd`
**Action:** Replace block
**Find:**
```gdscript
@export var switch_role: SwitchRole = SwitchRole.GATE_OPENER
@export var required_realm: int = 1 # 1 = MIRROR, 0 = REALITY, -1 = ANY
@export var linked_gate_path: NodePath
@export var linked_platform_path: NodePath
@export var blocking_prop_path: NodePath
@export var prompt_text: String = "E: Interact"

var is_activated: bool = false
var _player_inside: bool = false


func _exit_tree() -> void:
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_signal("controls_rebound"):
		if store.is_connected("controls_rebound", _on_controls_rebound):
			store.disconnect("controls_rebound", _on_controls_rebound)


func _ready() -> void:
	add_to_group("interactable_switch")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	var store: Node = _get_leaderboard_store()
	if store != null and store.has_signal("controls_rebound"):
		if not store.is_connected("controls_rebound", _on_controls_rebound):
			store.connect("controls_rebound", _on_controls_rebound)
```
**Replace with:**
```gdscript
@export var switch_role: SwitchRole = SwitchRole.GATE_OPENER
@export var required_realm: int = 1 # 1 = MIRROR, 0 = REALITY, -1 = ANY
@export var section_id: int = -1
@export var linked_gate_path: NodePath
@export var linked_platform_path: NodePath
@export var blocking_prop_path: NodePath
@export var prompt_text: String = "E: Interact"

var is_activated: bool = false
var _player_inside: bool = false


func _exit_tree() -> void:
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_signal("controls_rebound"):
		if store.is_connected("controls_rebound", _on_controls_rebound):
			store.disconnect("controls_rebound", _on_controls_rebound)
	if EncounterDirector.instance != null and EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
		EncounterDirector.instance.section_reset_requested.disconnect(_on_section_reset_requested)


func _ready() -> void:
	add_to_group("interactable_switch")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	var store: Node = _get_leaderboard_store()
	if store != null and store.has_signal("controls_rebound"):
		if not store.is_connected("controls_rebound", _on_controls_rebound):
			store.connect("controls_rebound", _on_controls_rebound)
	_connect_director()
	call_deferred("_connect_director")


func _connect_director() -> void:
	if EncounterDirector.instance != null and not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
		EncounterDirector.instance.section_reset_requested.connect(_on_section_reset_requested)


func _resolved_section_id() -> int:
	if section_id >= 0:
		return section_id
	var cur: Node = get_parent()
	while cur != null:
		var n: String = String(cur.name)
		if n.begins_with("Stage01"):
			return 0
		if n.begins_with("Stage02"):
			return 1
		if n.begins_with("Stage03"):
			return 2
		if n.begins_with("Stage04"):
			return 3
		if n.begins_with("Stage05"):
			return 4
		cur = cur.get_parent()
	return 0


func reset_switch() -> void:
	is_activated = false
	if _player_inside and can_interact():
		prompt_changed.emit(true, get_formatted_prompt_text())
	elif _player_inside:
		prompt_changed.emit(false, "")


func _on_section_reset_requested(reset_sec_id: int) -> void:
	if reset_sec_id == _resolved_section_id():
		reset_switch()
```

#### Edit 3C — Connect `MechanismPuzzle` to `EncounterDirector.section_reset_requested` (`scripts/environment/mechanism_puzzle.gd`)
**Target:** `scripts/environment/mechanism_puzzle.gd`
**Action:** Replace block
**Find:**
```gdscript
@export var require_mirror_realm: bool = true
@export var linked_gate_path: NodePath
@export var weight_node_path: NodePath = NodePath("SuspendedWeight")
@export var plate_node_path: NodePath = NodePath("PressurePlate")
@export var dropped_local_position: Vector3 = Vector3(0.0, 0.2, 0.0)

var is_solved: bool = false
var is_plate_pressed: bool = false
var _initial_weight_position: Vector3 = Vector3(0.0, 2.5, 0.0)
var _drop_tween: Tween = null


func _ready() -> void:
	add_to_group("mechanism_target")
	add_to_group("realm_reactive")
	var weight_node: Node3D = get_node_or_null(weight_node_path) as Node3D
	if weight_node != null:
		_initial_weight_position = weight_node.position

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(_on_realm_changed):
			rm.realm_changed.connect(_on_realm_changed)
		if not rm.realms_merged.is_connected(_on_realms_merged):
			rm.realms_merged.connect(_on_realms_merged)
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)
```
**Replace with:**
```gdscript
@export var require_mirror_realm: bool = true
@export var section_id: int = 3
@export var linked_gate_path: NodePath
@export var weight_node_path: NodePath = NodePath("SuspendedWeight")
@export var plate_node_path: NodePath = NodePath("PressurePlate")
@export var dropped_local_position: Vector3 = Vector3(0.0, 0.2, 0.0)

var is_solved: bool = false
var is_plate_pressed: bool = false
var _initial_weight_position: Vector3 = Vector3(0.0, 2.5, 0.0)
var _drop_tween: Tween = null


func _exit_tree() -> void:
	if EncounterDirector.instance != null and EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
		EncounterDirector.instance.section_reset_requested.disconnect(_on_section_reset_requested)


func _ready() -> void:
	add_to_group("mechanism_target")
	add_to_group("realm_reactive")
	var weight_node: Node3D = get_node_or_null(weight_node_path) as Node3D
	if weight_node != null:
		_initial_weight_position = weight_node.position

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(_on_realm_changed):
			rm.realm_changed.connect(_on_realm_changed)
		if not rm.realms_merged.is_connected(_on_realms_merged):
			rm.realms_merged.connect(_on_realms_merged)
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)
	_connect_director()
	call_deferred("_connect_director")


func _connect_director() -> void:
	if EncounterDirector.instance != null and not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
		EncounterDirector.instance.section_reset_requested.connect(_on_section_reset_requested)


func _on_section_reset_requested(reset_sec_id: int) -> void:
	if reset_sec_id == section_id:
		reset_puzzle()
```

#### Edit 3D — Add `section_id` & Reset Listener to `scripts/environment/realm_platform.gd`
**Target:** `scripts/environment/realm_platform.gd`
**Action:** Replace block
**Find:**
```gdscript
@export var reality_node_path: NodePath = NodePath("RealityGeometry")
@export var mirror_node_path: NodePath = NodePath("MirrorGeometry")
@export var repaired_node_path: NodePath = NodePath("RepairedGeometry")
@export var is_permanently_repaired: bool = false

var reality_node: Node = null
var mirror_node: Node = null
var repaired_node: Node = null


func _ready() -> void:
	add_to_group("realm_reactive")
	reality_node = get_node_or_null(reality_node_path)
	mirror_node = get_node_or_null(mirror_node_path)
	repaired_node = get_node_or_null(repaired_node_path)

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(on_realm_changed):
			rm.realm_changed.connect(on_realm_changed)
		if not rm.realms_merged.is_connected(_on_realms_merged):
			rm.realms_merged.connect(_on_realms_merged)
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)
```
**Replace with:**
```gdscript
@export var reality_node_path: NodePath = NodePath("RealityGeometry")
@export var mirror_node_path: NodePath = NodePath("MirrorGeometry")
@export var repaired_node_path: NodePath = NodePath("RepairedGeometry")
@export var is_permanently_repaired: bool = false
@export var section_id: int = -1

var reality_node: Node = null
var mirror_node: Node = null
var repaired_node: Node = null


func _exit_tree() -> void:
	if EncounterDirector.instance != null and EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
		EncounterDirector.instance.section_reset_requested.disconnect(_on_section_reset_requested)


func _ready() -> void:
	add_to_group("realm_reactive")
	reality_node = get_node_or_null(reality_node_path)
	mirror_node = get_node_or_null(mirror_node_path)
	repaired_node = get_node_or_null(repaired_node_path)

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(on_realm_changed):
			rm.realm_changed.connect(on_realm_changed)
		if not rm.realms_merged.is_connected(_on_realms_merged):
			rm.realms_merged.connect(_on_realms_merged)
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)
	_connect_director()
	call_deferred("_connect_director")


func _connect_director() -> void:
	if EncounterDirector.instance != null and not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
		EncounterDirector.instance.section_reset_requested.connect(_on_section_reset_requested)


func _resolved_section_id() -> int:
	if section_id >= 0:
		return section_id
	var cur: Node = get_parent()
	while cur != null:
		var n: String = String(cur.name)
		if n.begins_with("Stage01"):
			return 0
		if n.begins_with("Stage02"):
			return 1
		if n.begins_with("Stage03"):
			return 2
		if n.begins_with("Stage04"):
			return 3
		if n.begins_with("Stage05"):
			return 4
		cur = cur.get_parent()
	return 2 if String(name).contains("Bridge") else -1


func reset_platform() -> void:
	is_permanently_repaired = false
	var cur_realm: int = int(RealmManager.instance.current_realm) if RealmManager.instance != null else 0
	var merged: bool = bool(RealmManager.instance.is_merged) if RealmManager.instance != null else false
	evaluate_for_realm(cur_realm, merged)


func _on_section_reset_requested(reset_sec_id: int) -> void:
	var resolved_id: int = _resolved_section_id()
	if resolved_id >= 0 and reset_sec_id == resolved_id:
		reset_platform()
```

#### Edit 3E — Guard Trigger Readiness (`SRS-01`) & Remove Double Encounter Start (`SRS-04`) in `scripts/environment/section_trigger_volume.gd`
**Target:** `scripts/environment/section_trigger_volume.gd`
**Action:** Replace block
**Find:**
```gdscript
func _physics_process(_delta: float) -> void:
	if has_triggered or not check_position_bounds_each_frame or get_tree() == null:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node3D:
			if is_point_inside_trigger((p as Node3D).global_position):
				trigger_for_player(p)
				return
```
**Replace with:**
```gdscript
func _is_world_ready_for_trigger(player: Node = null) -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	var mc: Node = get_tree().get_first_node_in_group("main_controller")
	if mc != null and not bool(mc.get("level_ready")):
		return false
	if player != null and player.process_mode == Node.PROCESS_MODE_DISABLED:
		return false
	return true


func _physics_process(_delta: float) -> void:
	if has_triggered or not check_position_bounds_each_frame or get_tree() == null:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node3D and _is_world_ready_for_trigger(p):
			if is_point_inside_trigger((p as Node3D).global_position):
				trigger_for_player(p)
				return
```

#### Edit 3F — Guard `trigger_for_player()` / `_on_body_entered()` & Fix `_on_section_reset_requested()` in `scripts/environment/section_trigger_volume.gd`
**Target:** `scripts/environment/section_trigger_volume.gd`
**Action:** Replace block
**Find:**
```gdscript
func trigger_for_player(player: Node = null) -> bool:
	if has_triggered:
		return false
	if player != null and not player.is_in_group("player") and not (player is PlayerController):
		return false

	has_triggered = true
```
**Replace with:**
```gdscript
func trigger_for_player(player: Node = null) -> bool:
	if has_triggered:
		return false
	if player != null and not player.is_in_group("player") and not (player is PlayerController):
		return false
	if not _is_world_ready_for_trigger(player):
		return false

	has_triggered = true
```

#### Edit 3G — Guard `_on_body_entered()` & Remove `begin_combat_encounter()` from `_on_section_reset_requested()` in `scripts/environment/section_trigger_volume.gd`
**Target:** `scripts/environment/section_trigger_volume.gd`
**Action:** Replace block
**Find:**
```gdscript
func _on_body_entered(body: Node3D) -> void:
	if body != null and (body.is_in_group("player") or body is PlayerController):
		call_deferred("trigger_for_player", body)


func _on_encounter_cleared(cleared_id: String, _sec_id: int) -> void:
	if not reopen_entry_gate_on_clear or encounter_id.is_empty() or cleared_id != encounter_id:
		return
	if not entry_gate_to_seal_path.is_empty():
		var gate: EncounterGate = get_node_or_null(entry_gate_to_seal_path) as EncounterGate
		if gate != null:
			gate.open_gate(true)


func _on_section_reset_requested(reset_sec_id: int) -> void:
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	if reset_sec_id <= target_section:
		if ed != null and not bool(ed.completed_encounters.get(encounter_id, false)):
			has_triggered = false
	if reset_sec_id != target_section:
		return
	if ed != null and not encounter_id.is_empty() and encounter_enemy_count > 0:
		if not bool(ed.completed_encounters.get(encounter_id, false)):
			ed.begin_combat_encounter(encounter_id, encounter_enemy_count)
```
**Replace with:**
```gdscript
func _on_body_entered(body: Node3D) -> void:
	if body != null and (body.is_in_group("player") or body is PlayerController) and _is_world_ready_for_trigger(body):
		call_deferred("trigger_for_player", body)


func _on_encounter_cleared(cleared_id: String, _sec_id: int) -> void:
	if not reopen_entry_gate_on_clear or encounter_id.is_empty() or cleared_id != encounter_id:
		return
	if not entry_gate_to_seal_path.is_empty():
		var gate: EncounterGate = get_node_or_null(entry_gate_to_seal_path) as EncounterGate
		if gate != null:
			gate.open_gate(true)


func _on_section_reset_requested(reset_sec_id: int) -> void:
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	if reset_sec_id == target_section:
		if ed == null or encounter_id.is_empty() or not bool(ed.completed_encounters.get(encounter_id, false)):
			has_triggered = false
```

---

### Step 4 — Fix `EncounterDirector` Default Spawn, 2-Checkpoint Death Rewind, History Restore & Regroup (`SRS-02`, `SRS-03`, `SRS-05`, `SRS-10`)

- **Prerequisite**: Step 3 complete.
- **Postcondition**: `checkpoint_transform` starts at `default_spawn` `(0, 0, -136)` on `_enter_tree()` and `restart_full_run()`; `handle_player_death()` emits `section_reset_requested` deduplicated once per rewound section across `checkpoint_section .. max(completed, failed_section)` before restoring `checkpoint_realm` and calling `player.respawn_at()`; `restore_checkpoint_history()` reconstructs multi-checkpoint history on Continue; `restart_full_run()` regroups any spawned squad allies.

#### Edit 4A — Initialize `checkpoint_transform` in `EncounterDirector._enter_tree()` (`scripts/core/encounter_director.gd`)
**Target:** `scripts/core/encounter_director.gd`
**Action:** Replace block
**Find:**
```gdscript
func _enter_tree() -> void:
	instance = self
	add_to_group("encounter_director")
	# Initialize history with Entry Vestibule at start terrace
	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	_checkpoint_history.append({"section": Section.ENTRY, "transform": default_spawn, "realm": 0})
```
**Replace with:**
```gdscript
func _enter_tree() -> void:
	instance = self
	add_to_group("encounter_director")
	# Initialize history with Entry Vestibule at start terrace
	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	checkpoint_section = Section.ENTRY
	checkpoint_transform = default_spawn
	checkpoint_realm = 0
	_checkpoint_history.clear()
	_checkpoint_history.append({"section": Section.ENTRY, "transform": default_spawn, "realm": 0})
```

#### Edit 4B — Fix Rewind Reset Scope, History Restore, Default Spawn & Regroup in `scripts/core/encounter_director.gd`
**Target:** `scripts/core/encounter_director.gd`
**Action:** Replace block
**Find:**
```gdscript
	# 2. Reset active incomplete encounter state
	if not current_encounter_id.is_empty() and not bool(completed_encounters.get(current_encounter_id, false)):
		current_encounter_id = ""
		active_enemy_count = 0

	# 3. Death Rewind: Respawn 2 checkpoints behind
	var target_idx = _checkpoint_history.size() - 3
	if target_idx < 0:
		target_idx = 0
	
	var target_cp = _checkpoint_history[target_idx]
	current_section = target_cp.section
	checkpoint_section = target_cp.section
	checkpoint_transform = target_cp.transform
	checkpoint_realm = target_cp.realm
	_checkpoint_history.resize(target_idx + 1)
	
	# Clear progress for sections ahead of the rewind
	var sections_to_clear = []
	for sec in completed_sections.keys():
		if int(sec) >= current_section:
			sections_to_clear.append(sec)
	for sec in sections_to_clear:
		completed_sections.erase(sec)
		section_reset_requested.emit(int(sec))

	# Clean up leftover combat gibs, decals, and particles from failed encounter
	var gore_script = load("res://scripts/core/gore_fx.gd")
	if gore_script != null and gore_script.has_method("cleanup_all_fx"):
		gore_script.call("cleanup_all_fx")

	# Reset squad coordinator attack tokens
	var squad_coord = get_tree().root.get_node_or_null("SquadCoordinator")
	if squad_coord != null and squad_coord.has_method("reset"):
		squad_coord.call("reset")

	var game_feel = load("res://scripts/core/game_feel.gd")
	if game_feel != null and game_feel.has_method("reset_time_scale"):
		game_feel.call("reset_time_scale")

	# 4. Restore checkpoint realm state (unlocks shift if died during Warden Phase 2)
	if RealmManager.instance != null:
		RealmManager.instance.force_realm(checkpoint_realm as RealmManager.Realm, false)

	# 5. Respawn player at checkpoint transform with full health
	if player != null and player.has_method("respawn_at"):
		player.call("respawn_at", checkpoint_transform)

	_update_section_enemy_activation()
	alert_section_enemies(current_section)
	section_reset_requested.emit(checkpoint_section)
	player_respawned.emit(checkpoint_section, checkpoint_transform)
	_is_processing_death = false


func restart_full_run() -> void:
	completed_sections.clear()
	completed_encounters.clear()
	current_section = Section.ENTRY
	checkpoint_section = Section.ENTRY
	checkpoint_realm = 0
	active_enemy_count = 0
	current_encounter_id = ""

	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	_checkpoint_history.clear()
	_checkpoint_history.append({"section": Section.ENTRY, "transform": default_spawn, "realm": 0})

	var gore_script = load("res://scripts/core/gore_fx.gd")
	if gore_script != null and gore_script.has_method("cleanup_all_fx"):
		gore_script.call("cleanup_all_fx")

	var squad_coord = get_tree().root.get_node_or_null("SquadCoordinator")
	if squad_coord != null and squad_coord.has_method("reset"):
		squad_coord.call("reset")

	var game_feel = load("res://scripts/core/game_feel.gd")
	if game_feel != null and game_feel.has_method("reset_time_scale"):
		game_feel.call("reset_time_scale")

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
	var failed_section: int = int(current_section)

	# 2. Reset active encounter state
	current_encounter_id = ""
	active_enemy_count = 0

	# 3. Death Rewind: Respawn 2 checkpoints behind
	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	if _checkpoint_history.is_empty():
		_checkpoint_history.append({"section": Section.ENTRY, "transform": default_spawn, "realm": 0})

	var target_idx: int = _checkpoint_history.size() - 3
	if target_idx < 0:
		target_idx = 0

	var target_cp: Dictionary = _checkpoint_history[target_idx]
	current_section = int(target_cp.get("section", Section.ENTRY)) as Section
	checkpoint_section = int(target_cp.get("section", Section.ENTRY)) as Section
	checkpoint_transform = target_cp.get("transform", default_spawn) as Transform3D
	checkpoint_realm = int(target_cp.get("realm", 0))
	_checkpoint_history.resize(target_idx + 1)

	# Collect deduplicated ascending sections from checkpoint_section through failed_section and any cleared ahead sections.
	var reset_set: Dictionary = {}
	for sec_i in range(int(checkpoint_section), maxi(int(checkpoint_section), failed_section) + 1):
		reset_set[sec_i] = true
	for sec_key in completed_sections.keys():
		var sec_val: int = int(sec_key)
		if sec_val >= int(checkpoint_section):
			reset_set[sec_val] = true
	var sections_to_reset: Array[int] = []
	for sec_key in reset_set.keys():
		sections_to_reset.append(int(sec_key))
	sections_to_reset.sort()

	for sec_val in sections_to_reset:
		completed_sections.erase(sec_val)
	_clear_completed_encounters_for_sections(sections_to_reset)

	# Clean up lingering physics bodies / blood / attack tokens / time scale
	var gore_script = load("res://scripts/core/gore_fx.gd")
	if gore_script != null and gore_script.has_method("cleanup_all_fx"):
		gore_script.call("cleanup_all_fx")

	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		var squad_coord = get_tree().root.get_node_or_null("SquadCoordinator")
		if squad_coord != null and squad_coord.has_method("reset"):
			squad_coord.call("reset")

	var game_feel = load("res://scripts/core/game_feel.gd")
	if game_feel != null and game_feel.has_method("reset_time_scale"):
		game_feel.call("reset_time_scale")

	# 4. Reset rewound sections (gates, switches, triggers, breakables, enemies, puzzles, platforms) once per section
	for sec_val in sections_to_reset:
		section_reset_requested.emit(sec_val)

	# 5. Restore realm to checkpoint realm AFTER Warden/puzzle resets so checkpoint_realm is authoritative
	if RealmManager.instance != null:
		RealmManager.instance.force_realm(checkpoint_realm, false)

	# 6. Respawn player at checkpoint transform with full health
	if player != null and player.has_method("respawn_at"):
		player.call("respawn_at", checkpoint_transform)

	_update_section_enemy_activation()
	alert_section_enemies(current_section)
	section_changed.emit(current_section, get_section_name(current_section))
	player_respawned.emit(checkpoint_section, checkpoint_transform)
	_is_processing_death = false


func _clear_completed_encounters_for_sections(sections_to_reset: Array[int]) -> void:
	const SECTION_ENCOUNTER_MAP: Dictionary = {
		1: ["hall_of_echoes"],
		2: ["shielded_guard"],
		4: ["the_warden"],
	}
	for sec_val in sections_to_reset:
		for enc_name in SECTION_ENCOUNTER_MAP.get(sec_val, []):
			completed_encounters.erase(enc_name)
	if not is_inside_tree() or get_tree() == null:
		return
	for trig in get_tree().get_nodes_in_group("section_trigger"):
		if trig != null and int(trig.get("target_section")) in sections_to_reset:
			var eid: String = String(trig.get("encounter_id"))
			if not eid.is_empty():
				completed_encounters.erase(eid)
	for gate in get_tree().get_nodes_in_group("encounter_gate"):
		if gate != null and int(gate.get("section_id")) in sections_to_reset:
			var gid: String = String(gate.get("linked_encounter_id"))
			if not gid.is_empty():
				completed_encounters.erase(gid)


func restore_checkpoint_history(entries: Array, fallback_section: int, fallback_xform: Transform3D, fallback_realm: int) -> void:
	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	_checkpoint_history.clear()
	for item in entries:
		if item is Dictionary:
			var d: Dictionary = item as Dictionary
			var sec_i: int = int(d.get("section", Section.ENTRY))
			var xform: Transform3D = d.get("transform", default_spawn) as Transform3D
			var r_i: int = int(d.get("realm", 0))
			_checkpoint_history.append({"section": sec_i, "transform": xform, "realm": r_i})
	if _checkpoint_history.is_empty():
		var section_xforms: Dictionary = {int(Section.ENTRY): default_spawn}
		if is_inside_tree() and get_tree() != null:
			for trig in get_tree().get_nodes_in_group("section_trigger"):
				if trig is Node3D and not bool(trig.get("complete_run_on_enter")):
					var t_sec: int = int(trig.get("target_section"))
					if not section_xforms.has(t_sec):
						var spos: Variant = trig.get("checkpoint_spawn_position")
						var cp_pos: Vector3 = spos if (spos is Vector3 and (spos as Vector3) != Vector3.ZERO) else (trig as Node3D).global_position
						cp_pos.y = (trig as Node3D).global_position.y - 1.25 if spos == Vector3.ZERO else cp_pos.y
						section_xforms[t_sec] = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), cp_pos)
		for sec_i in range(0, maxi(0, fallback_section)):
			if section_xforms.has(sec_i):
				_checkpoint_history.append({"section": sec_i, "transform": section_xforms[sec_i], "realm": 0})
		_checkpoint_history.append({"section": fallback_section, "transform": fallback_xform, "realm": fallback_realm})
	else:
		if int(_checkpoint_history.back().get("section", -1)) != fallback_section:
			_checkpoint_history.append({"section": fallback_section, "transform": fallback_xform, "realm": fallback_realm})
		else:
			_checkpoint_history[_checkpoint_history.size() - 1] = {"section": fallback_section, "transform": fallback_xform, "realm": fallback_realm}
	while _checkpoint_history.size() > MAX_HISTORY:
		_checkpoint_history.remove_at(0)


func restart_full_run() -> void:
	completed_sections.clear()
	completed_encounters.clear()
	current_section = Section.ENTRY
	checkpoint_section = Section.ENTRY
	checkpoint_realm = 0
	active_enemy_count = 0
	current_encounter_id = ""

	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	checkpoint_transform = default_spawn
	_checkpoint_history.clear()
	_checkpoint_history.append({"section": Section.ENTRY, "transform": default_spawn, "realm": 0})

	var gore_script = load("res://scripts/core/gore_fx.gd")
	if gore_script != null and gore_script.has_method("cleanup_all_fx"):
		gore_script.call("cleanup_all_fx")

	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		var squad_coord = get_tree().root.get_node_or_null("SquadCoordinator")
		if squad_coord != null and squad_coord.has_method("reset"):
			squad_coord.call("reset")

	var game_feel = load("res://scripts/core/game_feel.gd")
	if game_feel != null and game_feel.has_method("reset_time_scale"):
		game_feel.call("reset_time_scale")

	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("start_new_run"):
		run_state.call("start_new_run")

	if RealmManager.instance != null:
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)

	_update_section_enemy_activation()
	if is_inside_tree() and get_tree() != null:
		var squad: Node = get_tree().get_first_node_in_group("squad_manager")
		if squad != null and squad.has_method("regroup"):
			var ally_list: Variant = squad.get("allies")
			if ally_list is Array and not (ally_list as Array).is_empty():
				squad.call("regroup", true)
	section_changed.emit(current_section, get_section_name(current_section))
```

---

### Step 5 — Fix `LeaderboardStore` Checkpoint History, Live Score, Disk Error Handling & World Restore (`SRS-03`, `SRS-05`, `SRS-11`, `SRS-12`)

- **Prerequisite**: Step 4 complete.
- **Postcondition**: Saves include `checkpoint_history`, live `score`, and `awarded_event_ids`; disk write helpers return `Error` and update `last_save_error`; Continue restores `checkpoint_history`, live score, solved `ChamberMechanismPuzzle` (`force_solve_bypass()`), `the_warden` completion (`TheWarden`, `CentralMirrorPlane`, `Gate05_ArenaExit`), passed/current `SectionTriggerVolume` states + active encounter seals, and already-spawned squad allies via `regroup(true)`.

#### Edit 5A — Add `last_save_error` Field in `scripts/core/leaderboard_store.gd`
**Target:** `scripts/core/leaderboard_store.gd`
**Action:** Replace block
**Find:**
```gdscript
var _entries: Array[Dictionary] = []
var _settings: Dictionary = {}
var _save_data: Dictionary = {}
var _muted_by_focus: bool = false
```
**Replace with:**
```gdscript
var _entries: Array[Dictionary] = []
var _settings: Dictionary = {}
var _save_data: Dictionary = {}
var _muted_by_focus: bool = false
var last_save_error: Error = OK
```

#### Edit 5B — Extend `get_default_save_data()` & `save_run_checkpoint()` Disk Result Reporting in `scripts/core/leaderboard_store.gd`
**Target:** `scripts/core/leaderboard_store.gd`
**Action:** Replace block
**Find:**
```gdscript
		"banked_score": 0,
		"elapsed_seconds": 0.0,
		"encounter_no_hit_awarded": {},
		"banked_event_ids": {},
		"player_health": 100,
		"layout_version": 1,   # JourneyLayout.VERSION of the save; files without the key are the old layout
```
**Replace with:**
```gdscript
		"score": 0,
		"banked_score": 0,
		"elapsed_seconds": 0.0,
		"encounter_no_hit_awarded": {},
		"awarded_event_ids": {},
		"banked_event_ids": {},
		"checkpoint_history": [],
		"player_health": 100,
		"layout_version": 1,   # JourneyLayout.VERSION of the save; files without the key are the old layout
```

#### Edit 5C — Propagate Disk Save Error Status & Capture `_checkpoint_history` + Live `score` in `scripts/core/leaderboard_store.gd`
**Target:** `scripts/core/leaderboard_store.gd`
**Action:** Replace block
**Find:**
```gdscript
	_save_data["timestamp"] = Time.get_datetime_string_from_system(false, true)
	_save_savegame_to_disk()
	game_saved.emit(get_saved_run_data())
	return get_saved_run_data()
```
**Replace with:**
```gdscript
	_save_data["timestamp"] = Time.get_datetime_string_from_system(false, true)
	var err: Error = _save_savegame_to_disk()
	var saved_copy: Dictionary = get_saved_run_data()
	saved_copy["_save_ok"] = (err == OK)
	if err == OK:
		game_saved.emit(saved_copy)
	return saved_copy
```

#### Edit 5D — Serialize `_checkpoint_history` & Live `score` in `capture_and_save_world_state()` (`scripts/core/leaderboard_store.gd`)
**Target:** `scripts/core/leaderboard_store.gd`
**Action:** Replace block
**Find:**
```gdscript
	if ed != null:
		var cur_sec: int = int(ed.get("current_section"))
		var chk_sec: int = int(ed.get("checkpoint_section"))
		var chk_xform: Transform3D = ed.get("checkpoint_transform") as Transform3D
		snapshot["current_section"] = cur_sec
		snapshot["checkpoint_section"] = chk_sec
		snapshot["checkpoint_position"] = chk_xform.origin
		snapshot["checkpoint_rotation_y"] = chk_xform.basis.get_euler().y
		snapshot["checkpoint_realm"] = int(ed.get("checkpoint_realm"))
		snapshot["completed_sections"] = (ed.get("completed_sections") as Dictionary).duplicate()
		snapshot["completed_encounters"] = (ed.get("completed_encounters") as Dictionary).duplicate()
		if cur_sec == 5: # COMPLETE
			snapshot["has_active_run"] = false

	if rm != null and ed == null:
		snapshot["checkpoint_realm"] = int(rm.get("current_realm"))

	if run_state != null:
		snapshot["banked_score"] = int(run_state.get("banked_score"))
		snapshot["elapsed_seconds"] = float(run_state.get("elapsed_seconds"))
		var no_hit: Variant = run_state.get("encounter_no_hit_awarded")
		if no_hit is Dictionary:
			snapshot["encounter_no_hit_awarded"] = (no_hit as Dictionary).duplicate()
		var banked_ids: Variant = run_state.get("_banked_event_ids")
		if banked_ids is Dictionary:
			snapshot["banked_event_ids"] = (banked_ids as Dictionary).duplicate()
```
**Replace with:**
```gdscript
	if ed != null:
		var cur_sec: int = int(ed.get("current_section"))
		var chk_sec: int = int(ed.get("checkpoint_section"))
		var chk_xform: Transform3D = ed.get("checkpoint_transform") as Transform3D
		snapshot["current_section"] = cur_sec
		snapshot["checkpoint_section"] = chk_sec
		snapshot["checkpoint_position"] = chk_xform.origin
		snapshot["checkpoint_rotation_y"] = chk_xform.basis.get_euler().y
		snapshot["checkpoint_realm"] = int(ed.get("checkpoint_realm"))
		snapshot["completed_sections"] = (ed.get("completed_sections") as Dictionary).duplicate()
		snapshot["completed_encounters"] = (ed.get("completed_encounters") as Dictionary).duplicate()
		var raw_hist: Variant = ed.get("_checkpoint_history")
		var serialized_hist: Array = []
		if raw_hist is Array:
			for item in (raw_hist as Array):
				if item is Dictionary:
					var hd: Dictionary = item as Dictionary
					var hx: Transform3D = hd.get("transform", Transform3D.IDENTITY) as Transform3D
					serialized_hist.append({
						"section": int(hd.get("section", 0)),
						"position": hx.origin,
						"rotation_y": hx.basis.get_euler().y,
						"realm": int(hd.get("realm", 0)),
					})
		snapshot["checkpoint_history"] = serialized_hist
		if cur_sec == 5: # COMPLETE
			snapshot["has_active_run"] = false

	if rm != null and ed == null:
		snapshot["checkpoint_realm"] = int(rm.get("current_realm"))

	if run_state != null:
		snapshot["score"] = int(run_state.get("score"))
		snapshot["banked_score"] = int(run_state.get("banked_score"))
		snapshot["elapsed_seconds"] = float(run_state.get("elapsed_seconds"))
		var no_hit: Variant = run_state.get("encounter_no_hit_awarded")
		if no_hit is Dictionary:
			snapshot["encounter_no_hit_awarded"] = (no_hit as Dictionary).duplicate()
		var live_ids: Variant = run_state.get("awarded_event_ids")
		if live_ids is Dictionary:
			snapshot["awarded_event_ids"] = (live_ids as Dictionary).duplicate()
		var banked_ids: Variant = run_state.get("_banked_event_ids")
		if banked_ids is Dictionary:
			snapshot["banked_event_ids"] = (banked_ids as Dictionary).duplicate()
```

#### Edit 5E — Restore Score, History, Puzzle/Warden/Triggers & Ally Regroup in `apply_saved_world_state()` (`scripts/core/leaderboard_store.gd`)
**Target:** `scripts/core/leaderboard_store.gd`
**Action:** Replace block
**Find:**
```gdscript
	if run_state != null:
		if run_state.has_method("start_new_run"):
			run_state.call("start_new_run")
		var b_score: int = int(_save_data.get("banked_score", 0))
		run_state.set("banked_score", b_score)
		run_state.set("score", b_score)
		run_state.set("elapsed_seconds", float(_save_data.get("elapsed_seconds", 0.0)))
		var saved_no_hit: Variant = _save_data.get("encounter_no_hit_awarded", {})
		if saved_no_hit is Dictionary:
			run_state.set("encounter_no_hit_awarded", (saved_no_hit as Dictionary).duplicate())
		var saved_ids: Variant = _save_data.get("banked_event_ids", {})
		if saved_ids is Dictionary:
			run_state.set("_banked_event_ids", (saved_ids as Dictionary).duplicate())
			run_state.set("awarded_event_ids", (saved_ids as Dictionary).duplicate())
		if run_state.has_signal("score_changed"):
			run_state.emit_signal("score_changed", b_score, 0, "loaded_save")

	if rm != null and rm.has_method("force_realm"):
		rm.call("force_realm", saved_realm, false)

	if ed != null:
		ed.set("completed_sections", (_save_data.get("completed_sections", {}) as Dictionary).duplicate())
		ed.set("completed_encounters", (_save_data.get("completed_encounters", {}) as Dictionary).duplicate())
		ed.set("checkpoint_section", saved_sec)
		ed.set("checkpoint_transform", spawn_xform)
		ed.set("checkpoint_realm", saved_realm)
		if ed.has_method("advance_to_section"):
			ed.call("advance_to_section", saved_sec, spawn_xform, false)

	if tree_root != null:
		var level_root: Node = tree_root.get_node_or_null("LevelRoot")
		if level_root == null and tree_root.has_method("build_greybox"):
			level_root = tree_root
		if level_root != null:
			var flags: Dictionary = _save_data.get("world_flags", {}) as Dictionary
			if bool(flags.get("entry_switch_activated", false)):
				var sw1: Node = level_root.get_node_or_null("Stage01_EntryVestibule/EntryMirrorSwitch")
				var gate1: Node = level_root.get_node_or_null("Stage01_EntryVestibule/Gate01_EntryToHall")
				if sw1 != null:
					sw1.set("is_activated", true)
				if gate1 != null and gate1.has_method("unlock_and_open"):
					gate1.call("unlock_and_open")
			if bool(flags.get("hall_pillar_broken", false)):
				var pil: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/CrackedCentralPillar")
				if pil != null and pil.has_method("complete_break_now"):
					pil.call("complete_break_now", [], false)
			if bool(flags.get("gallery_support_broken", false)):
				var sup: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/WeakStoneSupport")
				if sup != null and sup.has_method("complete_break_now"):
					sup.call("complete_break_now", [], false)
			if bool(flags.get("gallery_bridge_repaired", false)):
				var brg: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/GallerySpectralBridge")
				var sw3: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/BridgeAnchorSwitch")
				if brg != null and brg.has_method("repair_for_reality"):
					brg.call("repair_for_reality")
				if sw3 != null:
					sw3.set("is_activated", true)
			if bool(flags.get("mechanism_puzzle_solved", false)):
				var puz: Node = level_root.get_node_or_null("Stage04_MechanismChamber/ChamberMechanismPuzzle")
				var gate4: Node = level_root.get_node_or_null("Stage04_MechanismChamber/Gate04_MechanismToArena")
				if puz != null:
					puz.set("is_solved", true)
					puz.set("is_plate_pressed", true)
				if gate4 != null and gate4.has_method("unlock_and_open"):
					gate4.call("unlock_and_open")

			# Mark cleared enemies as dead in already-completed encounters
			if ed != null:
				var comp_enc: Dictionary = ed.get("completed_encounters") as Dictionary
				if bool(comp_enc.get("hall_of_echoes", false)):
					var hall_enemies: Array = []
					var hall_group: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/Enemies")
					if hall_group != null:
						hall_enemies = hall_group.get_children()
					for en in hall_enemies:
						if en != null:
							en.set("is_dead", true)
							if en.has_method("_refresh_active_state"):
								en.call("_refresh_active_state")
					var gate2: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/Gate02_HallToGallery")
					if gate2 != null and gate2.has_method("unlock_and_open"):
						gate2.call("unlock_and_open")
				if bool(comp_enc.get("shielded_guard", false)):
					var sg: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/Enemies/ShieldedGuard_1")
					if sg != null:
						sg.set("is_dead", true)
						if sg.has_method("_refresh_active_state"):
							sg.call("_refresh_active_state")
					var gate3: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/Gate03_GalleryToMechanism")
					if gate3 != null and gate3.has_method("unlock_and_open"):
						gate3.call("unlock_and_open")

	if player != null:
		if player.has_method("respawn_at"):
			player.call("respawn_at", spawn_xform)
		var saved_hp: int = clampi(int(_save_data.get("player_health", 100)), 1, 100)
		player.set("health", saved_hp)
		if player.has_signal("health_changed"):
			player.emit_signal("health_changed", saved_hp, int(player.get("max_health")))
```
**Replace with:**
```gdscript
	if run_state != null:
		if run_state.has_method("start_new_run"):
			run_state.call("start_new_run")
		var b_score: int = int(_save_data.get("banked_score", 0))
		var live_score: int = maxi(b_score, int(_save_data.get("score", b_score)))
		run_state.set("banked_score", b_score)
		run_state.set("score", live_score)
		run_state.set("elapsed_seconds", float(_save_data.get("elapsed_seconds", 0.0)))
		var saved_no_hit: Variant = _save_data.get("encounter_no_hit_awarded", {})
		if saved_no_hit is Dictionary:
			run_state.set("encounter_no_hit_awarded", (saved_no_hit as Dictionary).duplicate())
		var saved_ids: Variant = _save_data.get("banked_event_ids", {})
		var saved_live_ids: Variant = _save_data.get("awarded_event_ids", saved_ids)
		if saved_ids is Dictionary:
			run_state.set("_banked_event_ids", (saved_ids as Dictionary).duplicate())
		if saved_live_ids is Dictionary:
			run_state.set("awarded_event_ids", (saved_live_ids as Dictionary).duplicate())
		elif saved_ids is Dictionary:
			run_state.set("awarded_event_ids", (saved_ids as Dictionary).duplicate())
		if run_state.has_signal("score_changed"):
			run_state.emit_signal("score_changed", live_score, 0, "loaded_save")

	if rm != null and rm.has_method("force_realm"):
		rm.call("force_realm", saved_realm, false)

	var legacy_save: bool = int(_save_data.get("layout_version", 1)) < JourneyLayout.VERSION
	var restored_hist: Array = []
	var raw_hist: Variant = _save_data.get("checkpoint_history", [])
	if raw_hist is Array:
		for item in (raw_hist as Array):
			if item is Dictionary:
				var hd: Dictionary = item as Dictionary
				var h_pos: Vector3 = hd.get("position", Vector3(0.0, 0.0, -136.0))
				if legacy_save:
					h_pos = JourneyLayout.to_world(h_pos)
				var h_rot: float = float(hd.get("rotation_y", PI))
				restored_hist.append({
					"section": int(hd.get("section", 0)),
					"transform": Transform3D(Basis.IDENTITY.rotated(Vector3.UP, h_rot), h_pos),
					"realm": int(hd.get("realm", 0)),
				})

	if ed != null:
		ed.set("completed_sections", (_save_data.get("completed_sections", {}) as Dictionary).duplicate())
		ed.set("completed_encounters", (_save_data.get("completed_encounters", {}) as Dictionary).duplicate())
		ed.set("checkpoint_section", saved_sec)
		ed.set("checkpoint_transform", spawn_xform)
		ed.set("checkpoint_realm", saved_realm)
		if ed.has_method("advance_to_section"):
			ed.call("advance_to_section", saved_sec, spawn_xform, false)
		if ed.has_method("restore_checkpoint_history"):
			ed.call("restore_checkpoint_history", restored_hist, saved_sec, spawn_xform, saved_realm)

	if tree_root != null:
		var level_root: Node = tree_root.get_node_or_null("LevelRoot")
		if level_root == null and tree_root.has_method("build_greybox"):
			level_root = tree_root
		if level_root != null:
			var flags: Dictionary = _save_data.get("world_flags", {}) as Dictionary
			if bool(flags.get("entry_switch_activated", false)):
				var sw1: Node = level_root.get_node_or_null("Stage01_EntryVestibule/EntryMirrorSwitch")
				var gate1: Node = level_root.get_node_or_null("Stage01_EntryVestibule/Gate01_EntryToHall")
				if sw1 != null:
					sw1.set("is_activated", true)
				if gate1 != null and gate1.has_method("unlock_and_open"):
					gate1.call("unlock_and_open")
			if bool(flags.get("hall_pillar_broken", false)):
				var pil: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/CrackedCentralPillar")
				if pil != null and pil.has_method("complete_break_now"):
					pil.call("complete_break_now", [], false)
			if bool(flags.get("gallery_support_broken", false)):
				var sup: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/WeakStoneSupport")
				if sup != null and sup.has_method("complete_break_now"):
					sup.call("complete_break_now", [], false)
			if bool(flags.get("gallery_bridge_repaired", false)):
				var brg: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/GallerySpectralBridge")
				var sw3: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/BridgeAnchorSwitch")
				if brg != null and brg.has_method("repair_for_reality"):
					brg.call("repair_for_reality")
				if sw3 != null:
					sw3.set("is_activated", true)
			if bool(flags.get("mechanism_puzzle_solved", false)):
				var puz: Node = level_root.get_node_or_null("Stage04_MechanismChamber/ChamberMechanismPuzzle")
				var gate4: Node = level_root.get_node_or_null("Stage04_MechanismChamber/Gate04_MechanismToArena")
				if puz != null:
					if puz.has_method("force_solve_bypass"):
						puz.call("force_solve_bypass")
					else:
						puz.set("is_solved", true)
						puz.set("is_plate_pressed", true)
				if gate4 != null and gate4.has_method("unlock_and_open"):
					gate4.call("unlock_and_open")

			# Mark cleared enemies as dead in already-completed encounters
			if ed != null:
				var comp_enc: Dictionary = ed.get("completed_encounters") as Dictionary
				if bool(comp_enc.get("hall_of_echoes", false)):
					var hall_enemies: Array = []
					var hall_group: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/Enemies")
					if hall_group != null:
						hall_enemies = hall_group.get_children()
					for en in hall_enemies:
						if en != null:
							en.set("is_dead", true)
							if en.has_method("_refresh_active_state"):
								en.call("_refresh_active_state")
					var gate2: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/Gate02_HallToGallery")
					if gate2 != null and gate2.has_method("unlock_and_open"):
						gate2.call("unlock_and_open")
				if bool(comp_enc.get("shielded_guard", false)):
					var sg: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/Enemies/ShieldedGuard_1")
					if sg != null:
						sg.set("is_dead", true)
						if sg.has_method("_refresh_active_state"):
							sg.call("_refresh_active_state")
					var gate3: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/Gate03_GalleryToMechanism")
					if gate3 != null and gate3.has_method("unlock_and_open"):
						gate3.call("unlock_and_open")
				if bool(comp_enc.get("the_warden", false)):
					var warden: Node = level_root.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden")
					if warden != null:
						warden.set("is_dead", true)
						if warden.has_method("_refresh_active_state"):
							warden.call("_refresh_active_state")
					var mplane: Node = level_root.get_node_or_null("Stage05_ExecutionArena/CentralMirrorPlane")
					if mplane != null and mplane.has_method("complete_break_now"):
						mplane.call("complete_break_now", [], false)
					var gate5: Node = level_root.get_node_or_null("Stage05_ExecutionArena/Gate05_ArenaExit")
					if gate5 != null and gate5.has_method("unlock_and_open"):
						gate5.call("unlock_and_open")

				# Prevent passed triggers from re-firing; seal and resume an active mid-section encounter if saved inside one.
				if is_inside_tree() and get_tree() != null:
					for trig in get_tree().get_nodes_in_group("section_trigger"):
						if trig == null:
							continue
						if bool(trig.get("complete_run_on_enter")) and saved_sec < 5:
							continue
						var t_sec: int = int(trig.get("target_section"))
						var enc_id: String = String(trig.get("encounter_id"))
						if t_sec < saved_sec:
							trig.set("has_triggered", true)
						elif t_sec == saved_sec:
							var inside_or_past: bool = false
							if trig is Node3D:
								inside_or_past = (trig as Node3D).global_position.z <= saved_pos.z + 2.0
							if not inside_or_past and trig.has_method("is_point_inside_trigger"):
								inside_or_past = bool(trig.call("is_point_inside_trigger", saved_pos))
							if not enc_id.is_empty() and bool(comp_enc.get(enc_id, false)):
								trig.set("has_triggered", true)
							elif inside_or_past:
								trig.set("has_triggered", true)
								if not enc_id.is_empty() and not bool(comp_enc.get(enc_id, false)):
									var seal_path: NodePath = trig.get("entry_gate_to_seal_path") as NodePath
									if not seal_path.is_empty():
										var seal_gate: Node = trig.get_node_or_null(seal_path)
										if seal_gate != null and seal_gate.has_method("seal_gate_for_encounter"):
											seal_gate.call("seal_gate_for_encounter")
									var e_cnt: int = int(trig.get("encounter_enemy_count"))
									if e_cnt > 0 and ed.has_method("begin_combat_encounter"):
										ed.call("begin_combat_encounter", enc_id, e_cnt)

	if player != null:
		if player.has_method("respawn_at"):
			player.call("respawn_at", spawn_xform)
		var saved_hp: int = clampi(int(_save_data.get("player_health", 100)), 1, 100)
		player.set("health", saved_hp)
		if player.has_signal("health_changed"):
			player.emit_signal("health_changed", saved_hp, int(player.get("max_health")))

	if is_inside_tree() and get_tree() != null:
		var squad: Node = get_tree().get_first_node_in_group("squad_manager")
		if squad != null and squad.has_method("regroup"):
			var ally_list: Variant = squad.get("allies")
			if ally_list is Array and not (ally_list as Array).is_empty():
				squad.call("regroup", true)
```

#### Edit 5F — Propagate Disk Save Errors in `_save_*_to_disk()` Helpers (`scripts/core/leaderboard_store.gd`)
**Target:** `scripts/core/leaderboard_store.gd`
**Action:** Replace block
**Find:**
```gdscript
func _save_leaderboard_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "count", _entries.size())
	for i in range(_entries.size()):
		var sec: String = "entry_%d" % i
		var e: Dictionary = _entries[i]
		cfg.set_value(sec, "initials", String(e.get("initials", "WAR")))
		cfg.set_value(sec, "score", int(e.get("score", 0)))
		cfg.set_value(sec, "time_sec", float(e.get("time_sec", 0.0)))
		cfg.set_value(sec, "rank", String(e.get("rank", "C")))
		cfg.set_value(sec, "timestamp", String(e.get("timestamp", "")))
	cfg.save(leaderboard_path)
```
**Replace with:**
```gdscript
func _save_leaderboard_to_disk() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "count", _entries.size())
	for i in range(_entries.size()):
		var sec: String = "entry_%d" % i
		var e: Dictionary = _entries[i]
		cfg.set_value(sec, "initials", String(e.get("initials", "WAR")))
		cfg.set_value(sec, "score", int(e.get("score", 0)))
		cfg.set_value(sec, "time_sec", float(e.get("time_sec", 0.0)))
		cfg.set_value(sec, "rank", String(e.get("rank", "C")))
		cfg.set_value(sec, "timestamp", String(e.get("timestamp", "")))
	var err: Error = cfg.save(leaderboard_path)
	last_save_error = err
	if err != OK:
		push_warning("Failed to save leaderboard to '%s' (err=%d)" % [leaderboard_path, int(err)])
	return err
```

#### Edit 5G — Propagate Errors in `_save_settings_to_disk()` & `_save_savegame_to_disk()` (`scripts/core/leaderboard_store.gd`)
**Target:** `scripts/core/leaderboard_store.gd`
**Action:** Replace block
**Find:**
```gdscript
func _save_settings_to_disk() -> void:
	var cfg := ConfigFile.new()
	for k in _settings.keys():
		if k == "keybindings":
			var binds: Dictionary = _settings["keybindings"] as Dictionary
			for act in binds.keys():
				cfg.set_value("keybindings", String(act), String(binds[act]))
		else:
			cfg.set_value("settings", k, _settings[k])
	cfg.save(settings_path)
```
**Replace with:**
```gdscript
func _save_settings_to_disk() -> Error:
	var cfg := ConfigFile.new()
	for k in _settings.keys():
		if k == "keybindings":
			var binds: Dictionary = _settings["keybindings"] as Dictionary
			for act in binds.keys():
				cfg.set_value("keybindings", String(act), String(binds[act]))
		else:
			cfg.set_value("settings", k, _settings[k])
	var err: Error = cfg.save(settings_path)
	last_save_error = err
	if err != OK:
		push_warning("Failed to save settings to '%s' (err=%d)" % [settings_path, int(err)])
	return err
```

#### Edit 5H — Propagate Errors in `_save_savegame_to_disk()` (`scripts/core/leaderboard_store.gd`)
**Target:** `scripts/core/leaderboard_store.gd`
**Action:** Replace block
**Find:**
```gdscript
func _save_savegame_to_disk() -> void:
	var cfg := ConfigFile.new()
	for k in _save_data.keys():
		if k == "custom_claude_data":
			var custom: Dictionary = _save_data["custom_claude_data"] as Dictionary
			for ck in custom.keys():
				cfg.set_value("custom", String(ck), custom[ck])
		elif k == "profile_stats":
			var stats: Dictionary = _save_data["profile_stats"] as Dictionary
			for pk in stats.keys():
				cfg.set_value("profile", String(pk), stats[pk])
		else:
			cfg.set_value("run", k, _save_data[k])
	cfg.save(savegame_path)
```
**Replace with:**
```gdscript
func _save_savegame_to_disk() -> Error:
	var cfg := ConfigFile.new()
	for k in _save_data.keys():
		if k == "custom_claude_data":
			var custom: Dictionary = _save_data["custom_claude_data"] as Dictionary
			for ck in custom.keys():
				cfg.set_value("custom", String(ck), custom[ck])
		elif k == "profile_stats":
			var stats: Dictionary = _save_data["profile_stats"] as Dictionary
			for pk in stats.keys():
				cfg.set_value("profile", String(pk), stats[pk])
		else:
			cfg.set_value("run", k, _save_data[k])
	var err: Error = cfg.save(savegame_path)
	last_save_error = err
	if err != OK:
		push_warning("Failed to save run data to '%s' (err=%d)" % [savegame_path, int(err)])
	return err
```

---

### Step 6 — Fix `PlayerController.respawn_at()` & `_verify_spawn_safety()` (`SRS-13`)

- **Prerequisite**: Step 5 complete (and Guide 01 applied cleanly outside `:1442-1481`).
- **Ownership Boundary**: Touches **ONLY** lines `:1442-1481` (`respawn_at()` and `_verify_spawn_safety()`) in `scripts/player/player_controller.gd`.
- **Postcondition**: `_verify_spawn_safety()` checks tree/world availability, uses active realm world collision mask, and excludes `[get_rid()]`; `respawn_at()` resets `stamina`, `_health_regen_acc`, `_flow_streak`, `_flow_tap`, `_ally_ward_hp`, `_ally_ward_until_ms`, `_finisher_cooldown_end_ms`, `_jump_buffer_timer`, `_jump_held`, `_buffer_timer`, `_presses_this_swing`, `_since_attack_end`, `_pending_ground_slam_timer`, and `_plunge_hang_timer`.

#### Edit 6A — Complete `respawn_at()` Reset & Harden `_verify_spawn_safety()` (`scripts/player/player_controller.gd`)
**Target:** `scripts/player/player_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func respawn_at(spawn_transform: Transform3D) -> void:
	var safe_pos = _verify_spawn_safety(spawn_transform.origin)
	global_transform.origin = safe_pos
	global_transform.basis = spawn_transform.basis
	velocity = Vector3.ZERO
	health = max_health
	combo_step = 0
	_combo_window_timer = 0.0
	_dodge_elapsed = 0.0
	_dodge_charges = max_dodge_charges
	_dodge_cooldown_timer = 0.0
	_coyote_timer = 0.0
	_pending_ground_slam = false
	_landing_recover_timer = 0.0
	_simulated_airborne = false
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
	_close_finisher_window("")
	_set_state(State.LOCOMOTION, 0.0)
	health_changed.emit(health, max_health)

func _verify_spawn_safety(pos: Vector3) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var ray_query = PhysicsRayQueryParameters3D.create(pos + Vector3(0, 2, 0), pos - Vector3(0, 5, 0))
	var result = space_state.intersect_ray(ray_query)
	
	if result.is_empty():
		push_warning("Respawn position invalid! Using fallback.")
		return Vector3(0.0, 0.5, -136.0)
	return pos
```
**Replace with:**
```gdscript
func respawn_at(spawn_transform: Transform3D) -> void:
	var safe_pos = _verify_spawn_safety(spawn_transform.origin)
	global_transform.origin = safe_pos
	global_transform.basis = spawn_transform.basis
	velocity = Vector3.ZERO
	health = max_health
	stamina = max_stamina
	_health_regen_acc = 0.0
	combo_step = 0
	_combo_window_timer = 0.0
	_flow_tap = false
	_flow_streak = 0
	_presses_this_swing = 0
	_since_attack_end = 99.0
	_ally_ward_hp = 0
	_ally_ward_until_ms = 0
	_finisher_cooldown_end_ms = 0
	_dodge_elapsed = 0.0
	_dodge_charges = max_dodge_charges
	_dodge_cooldown_timer = 0.0
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_jump_held = false
	_pending_ground_slam = false
	_pending_ground_slam_timer = 0.0
	_plunge_hang_timer = 0.0
	_landing_recover_timer = 0.0
	_simulated_airborne = false
	_air_dash_used = false
	_buffer_action = ""
	_buffer_timer = 0.0
	run_time = 0.0
	camera_yaw = global_rotation.y
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		set_facing_direction(fwd.normalized())
	_update_camera_pivot()
	_update_hurtbox_invulnerability(false)
	_abort_attack()
	_close_finisher_window("")
	_set_state(State.LOCOMOTION, 0.0)
	health_changed.emit(health, max_health)

func _verify_spawn_safety(pos: Vector3) -> Vector3:
	if not is_inside_tree() or get_world_3d() == null or get_world_3d().direct_space_state == null:
		return pos
	var space_state := get_world_3d().direct_space_state
	var world_mask: int = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR
	if RealmManager.instance != null and RealmManager.instance.has_method("get_realm_world_mask"):
		world_mask = RealmManager.instance.get_realm_world_mask(RealmManager.instance.current_realm)
	var ray_query := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 2, 0), pos - Vector3(0, 5, 0), world_mask, [get_rid()])
	var result := space_state.intersect_ray(ray_query)

	if result.is_empty():
		push_warning("Respawn position invalid! Using fallback.")
		return Vector3(0.0, 0.5, -136.0)
	return pos
```

---

### Step 7 — Gate `AllySquadManager` Startup Spawning on `MainController.level_ready` (`SRS-05`)

- **Prerequisite**: Step 6 complete (and Guide 03 applied cleanly to `:217..1509`).
- **Ownership Boundary**: Touches **ONLY** lines `:47-86` of `scripts/allies/ally_squad_manager.gd`.
- **Postcondition**: When running under `MainController`, allies do not spawn on Title/Loading before walkable floors exist; calling `spawn_squad()` spawns once or regroups/heals if already spawned; standalone unit tests without `MainController` still auto-spawn normally.

#### Edit 7A — Gate Deferred Spawn & Expose `spawn_squad()` in `scripts/allies/ally_squad_manager.gd`
**Target:** `scripts/allies/ally_squad_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
func _ready() -> void:
	intel = WorldIntel.new()
	intel.name = "WorldIntel"
	add_child(intel)
	if spawn_allies:
		call_deferred("_spawn_squad")
	call_deferred("_connect_director")


func _connect_director() -> void:
	if EncounterDirector.instance != null and not EncounterDirector.instance.player_respawned.is_connected(_on_director_player_respawned):
		EncounterDirector.instance.player_respawned.connect(_on_director_player_respawned)


func _on_director_player_respawned(_sec_id: int, _xform: Transform3D) -> void:
	regroup(true)


# ------------------------------------------------------------------ spawning

static func load_profiles() -> Array[AllyProfile]:
	var out: Array[AllyProfile] = []
	var dir := DirAccess.open(ALLY_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var path: String = f.trim_suffix(".remap")
		if not (path.ends_with(".tres") or path.ends_with(".res")):
			continue
		var res: Resource = load(ALLY_DIR + path)
		if res is AllyProfile:
			out.append(res as AllyProfile)
	out.sort_custom(func(a: AllyProfile, b: AllyProfile) -> bool: return a.order < b.order)
	return out


func _spawn_squad() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
```
**Replace with:**
```gdscript
func _ready() -> void:
	intel = WorldIntel.new()
	intel.name = "WorldIntel"
	add_child(intel)
	if spawn_allies:
		call_deferred("_maybe_initial_spawn")
	call_deferred("_connect_director")


func _maybe_initial_spawn() -> void:
	if not spawn_allies or not allies.is_empty() or not is_inside_tree() or get_tree() == null:
		return
	var mc: Node = get_tree().get_first_node_in_group("main_controller")
	if mc != null and not bool(mc.get("level_ready")):
		return
	_spawn_squad()


func spawn_squad() -> void:
	if not spawn_allies:
		return
	if allies.is_empty():
		_spawn_squad()
	else:
		regroup(true)


func _connect_director() -> void:
	if EncounterDirector.instance != null and not EncounterDirector.instance.player_respawned.is_connected(_on_director_player_respawned):
		EncounterDirector.instance.player_respawned.connect(_on_director_player_respawned)


func _on_director_player_respawned(_sec_id: int, _xform: Transform3D) -> void:
	regroup(true)


# ------------------------------------------------------------------ spawning

static func load_profiles() -> Array[AllyProfile]:
	var out: Array[AllyProfile] = []
	var dir := DirAccess.open(ALLY_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var path: String = f.trim_suffix(".remap")
		if not (path.ends_with(".tres") or path.ends_with(".res")):
			continue
		var res: Resource = load(ALLY_DIR + path)
		if res is AllyProfile:
			out.append(res as AllyProfile)
	out.sort_custom(func(a: AllyProfile, b: AllyProfile) -> bool: return a.order < b.order)
	return out


func _spawn_squad() -> void:
	if not allies.is_empty():
		regroup(true)
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
```

---

### Step 8 — Harden `RealmManager`, `WeatherDirector`, and `MainController` (`SRS-01`, `SRS-05`, `SRS-06`, `SRS-09`, `SRS-15`)

- **Prerequisite**: Step 7 complete.
- **Postcondition**: `RealmManager` blocks gameplay realm shifts outside active gameplay (`is_gameplay_active()` / `ui_input_locked`); `WeatherDirector.bind_warden()` binds reliably when `TheWarden` finishes building and retries in `_process()` if unbound; `MainController` registers `"main_controller"` in `_enter_tree()`, blocks `is_gameplay_active()` until `level_ready and not _building and _loading == null`, resolves `GameAudio` autoload cleanly, suppresses `auto_save_on_checkpoint` during loading, spawns squad allies after floor/save setup, and freezes world/player/HUD on Results and Return-to-Title.

#### Edit 8A — Gate `RealmManager._unhandled_input()` on Active Gameplay (`scripts/core/realm_manager.gd`)
**Target:** `scripts/core/realm_manager.gd`
**Action:** Replace block
**Find:**
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not handle_input_directly:
		return
	if event.is_action_pressed("dimension_shift"):
		# Inside the critical-hit window Q is the Mirror Break finisher, not a realm shift.
		if player_ref != null and player_ref.has_method("is_finisher_window_open") and bool(player_ref.call("is_finisher_window_open")):
			return
		if request_shift():
			get_viewport().set_input_as_handled()
```
**Replace with:**
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not handle_input_directly:
		return
	if event.is_action_pressed("dimension_shift"):
		if is_inside_tree() and get_tree() != null:
			var mc: Node = get_tree().get_first_node_in_group("main_controller")
			if mc != null and mc.has_method("is_gameplay_active") and not bool(mc.call("is_gameplay_active")):
				return
		if PlayerController.ui_input_locked:
			return
		# Inside the critical-hit window Q is the Mirror Break finisher, not a realm shift.
		if player_ref != null and player_ref.has_method("is_finisher_window_open") and bool(player_ref.call("is_finisher_window_open")):
			return
		if request_shift():
			get_viewport().set_input_as_handled()
```

#### Edit 8B — Make `WeatherDirector` Warden Binding Idempotent & Retried (`scripts/environment/weather_director.gd`)
**Target:** `scripts/environment/weather_director.gd`
**Action:** Replace block
**Find:**
```gdscript
var _rain_light: AudioStreamPlayer = null
var _rain_heavy: AudioStreamPlayer = null
var _wind: AudioStreamPlayer = null
var _thunder: Array[AudioStream] = []
var _thunder_player: AudioStreamPlayer = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = 100 # after RealmEnvironmentController
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	add_to_group("weather_director")
	_cur = (PROFILES["golden"] as Dictionary).duplicate()
	_build_rain()
	_build_audio()
	_bind_warden.call_deferred()


func _bind_warden() -> void:
	var w: Node = get_node_or_null(warden_path)
	if w == null:
		return
	if w.has_signal("boss_defeated"):
		w.connect("boss_defeated", func() -> void: warden_dead = true)
	if w.has_signal("boss_phase_changed"):
		w.connect("boss_phase_changed", func(p: int) -> void: warden_phase2 = p >= 2)
	if w.has_signal("health_changed"):
		# Reset/respawn restores HP -> weather returns to the Phase 1 blood storm.
		w.connect("health_changed", func(hp: int, max_hp: int) -> void:
			if hp >= max_hp:
				warden_phase2 = false
				warden_dead = false)
```
**Replace with:**
```gdscript
var _rain_light: AudioStreamPlayer = null
var _rain_heavy: AudioStreamPlayer = null
var _wind: AudioStreamPlayer = null
var _thunder: Array[AudioStream] = []
var _thunder_player: AudioStreamPlayer = null
var _rng := RandomNumberGenerator.new()
var _bound_warden: Node = null


func _ready() -> void:
	process_priority = 100 # after RealmEnvironmentController
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	add_to_group("weather_director")
	_cur = (PROFILES["golden"] as Dictionary).duplicate()
	_build_rain()
	_build_audio()
	_bind_warden.call_deferred()


func _bind_warden() -> void:
	bind_warden()


func bind_warden(warden_override: Node = null) -> bool:
	var w: Node = warden_override
	if w == null:
		w = get_node_or_null(warden_path)
	if w == null and is_inside_tree() and get_tree() != null:
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is WardenBoss:
				w = e
				break
	if w == null or not is_instance_valid(w):
		return false
	if _bound_warden == w and is_instance_valid(_bound_warden):
		return true
	_bound_warden = w
	if w.has_signal("boss_defeated") and not w.is_connected("boss_defeated", _on_warden_defeated):
		w.connect("boss_defeated", _on_warden_defeated)
	if w.has_signal("boss_phase_changed") and not w.is_connected("boss_phase_changed", _on_warden_phase_changed):
		w.connect("boss_phase_changed", _on_warden_phase_changed)
	if w.has_signal("health_changed") and not w.is_connected("health_changed", _on_warden_health_changed):
		w.connect("health_changed", _on_warden_health_changed)
	warden_dead = bool(w.get("is_dead"))
	warden_phase2 = int(w.get("current_phase")) >= 2
	return true


func _on_warden_defeated() -> void:
	warden_dead = true


func _on_warden_phase_changed(p: int) -> void:
	warden_phase2 = p >= 2


func _on_warden_health_changed(hp: int, max_hp: int) -> void:
	if hp >= max_hp:
		warden_phase2 = false
		warden_dead = false
```

#### Edit 8C — Retry `bind_warden()` in `WeatherDirector._process()` (`scripts/environment/weather_director.gd`)
**Target:** `scripts/environment/weather_director.gd`
**Action:** Replace block
**Find:**
```gdscript
func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
```
**Replace with:**
```gdscript
func _process(delta: float) -> void:
	if _bound_warden == null or not is_instance_valid(_bound_warden):
		bind_warden()
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
```

#### Edit 8D — Register `main_controller` in `_enter_tree()`, Guard `is_gameplay_active()` & Add `_get_audio_manager()` in `scripts/core/main_controller.gd`
**Target:** `scripts/core/main_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _ready() -> void:
	add_to_group("main_controller")
	# NOTE: Main is the scene root, so we must NOT set PROCESS_MODE_ALWAYS here (every child would ignore pause).
	# SceneTree.process_frame keeps firing while paused, which is exactly what cursor management needs.
	if get_tree() != null and not get_tree().process_frame.is_connected(_on_tree_process_frame):
		get_tree().process_frame.connect(_on_tree_process_frame)
	call_deferred("_wire_all_subsystems")
	if get_node_or_null("PerformanceGovernor") == null:
		var gov: Node = (load("res://scripts/core/performance_governor.gd") as GDScript).new()
		gov.name = "PerformanceGovernor"
		add_child(gov)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().process_frame.is_connected(_on_tree_process_frame):
		get_tree().process_frame.disconnect(_on_tree_process_frame)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_tree_process_frame() -> void:
	if manage_mouse_capture:
		_update_mouse_mode()


func is_gameplay_active() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	if get_tree().paused:
		return false
	for grp in MENU_GROUPS:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				return false
	var player: PlayerController = get_node_or_null(player_path) as PlayerController
	if player != null and player.current_state == PlayerController.State.DEAD:
		return false
	return true
```
**Replace with:**
```gdscript
func _enter_tree() -> void:
	add_to_group("main_controller")


func _ready() -> void:
	add_to_group("main_controller")
	# NOTE: Main is the scene root, so we must NOT set PROCESS_MODE_ALWAYS here (every child would ignore pause).
	# SceneTree.process_frame keeps firing while paused, which is exactly what cursor management needs.
	if get_tree() != null and not get_tree().process_frame.is_connected(_on_tree_process_frame):
		get_tree().process_frame.connect(_on_tree_process_frame)
	call_deferred("_wire_all_subsystems")
	if get_node_or_null("PerformanceGovernor") == null:
		var gov: Node = (load("res://scripts/core/performance_governor.gd") as GDScript).new()
		gov.name = "PerformanceGovernor"
		add_child(gov)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().process_frame.is_connected(_on_tree_process_frame):
		get_tree().process_frame.disconnect(_on_tree_process_frame)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_tree_process_frame() -> void:
	if manage_mouse_capture:
		_update_mouse_mode()


func is_gameplay_active() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	if get_tree().paused or not level_ready or _building or _loading != null:
		return false
	for grp in MENU_GROUPS:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				return false
	var player: PlayerController = get_node_or_null(player_path) as PlayerController
	if player != null and (player.current_state == PlayerController.State.DEAD or player.process_mode == Node.PROCESS_MODE_DISABLED):
		return false
	return true


func _get_audio_manager() -> AudioManager:
	var audio_mgr: AudioManager = get_node_or_null(audio_manager_path) as AudioManager
	if audio_mgr == null and is_inside_tree() and get_tree() != null and get_tree().root != null:
		audio_mgr = get_tree().root.get_node_or_null("GameAudio") as AudioManager
	if audio_mgr == null:
		audio_mgr = AudioManager.instance as AudioManager
	return audio_mgr
```

#### Edit 8E — Resolve `GameAudio`, Wire `results_presented`, Bind `WeatherDirector`, Suppress Autosave on Load, Spawn Squad & Freeze Title/Results in `scripts/core/main_controller.gd`
**Target:** `scripts/core/main_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _wire_all_subsystems() -> void:
	var player: Node = get_node_or_null(player_path)
	var level_root: Node = get_node_or_null(level_root_path)
	var hud: HUDController = get_node_or_null(hud_path) as HUDController
	var audio_mgr: AudioManager = get_node_or_null(audio_manager_path) as AudioManager
	var death_ui: DeathOverlayController = get_node_or_null(death_overlay_path) as DeathOverlayController
	var title_ui: TitleScreenController = get_node_or_null(title_screen_path) as TitleScreenController
	var pause_ui: PauseMenuController = get_node_or_null(pause_menu_path) as PauseMenuController
	var results_ui: ResultsScreenController = get_node_or_null(results_screen_path) as ResultsScreenController
	var lb_ui: LeaderboardScreenController = get_node_or_null(leaderboard_screen_path) as LeaderboardScreenController
	var opts_ui: OptionsScreenController = get_node_or_null(options_screen_path) as OptionsScreenController
```
**Replace with:**
```gdscript
func _wire_all_subsystems() -> void:
	PlayerController.ui_input_locked = false
	var player: Node = get_node_or_null(player_path)
	var level_root: Node = get_node_or_null(level_root_path)
	var hud: HUDController = get_node_or_null(hud_path) as HUDController
	var audio_mgr: AudioManager = _get_audio_manager()
	var death_ui: DeathOverlayController = get_node_or_null(death_overlay_path) as DeathOverlayController
	var title_ui: TitleScreenController = get_node_or_null(title_screen_path) as TitleScreenController
	var pause_ui: PauseMenuController = get_node_or_null(pause_menu_path) as PauseMenuController
	var results_ui: ResultsScreenController = get_node_or_null(results_screen_path) as ResultsScreenController
	var lb_ui: LeaderboardScreenController = get_node_or_null(leaderboard_screen_path) as LeaderboardScreenController
	var opts_ui: OptionsScreenController = get_node_or_null(options_screen_path) as OptionsScreenController
```

#### Edit 8F — Wire `results_presented`, `WeatherDirector.bind_warden()`, Loading Protection, Squad Spawn & Title/Results Freeze in `scripts/core/main_controller.gd`
**Target:** `scripts/core/main_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	if results_ui != null:
		if not results_ui.leaderboard_requested.is_connected(_on_open_leaderboard.bind(results_ui)):
			results_ui.leaderboard_requested.connect(_on_open_leaderboard.bind(results_ui))
		if not results_ui.main_menu_requested.is_connected(_on_return_to_title):
			results_ui.main_menu_requested.connect(_on_return_to_title)
		if not results_ui.replay_requested.is_connected(_on_start_run_requested):
			results_ui.replay_requested.connect(_on_start_run_requested)
```
**Replace with:**
```gdscript
	if results_ui != null:
		if not results_ui.results_presented.is_connected(_on_results_presented):
			results_ui.results_presented.connect(_on_results_presented)
		if not results_ui.leaderboard_requested.is_connected(_on_open_leaderboard.bind(results_ui)):
			results_ui.leaderboard_requested.connect(_on_open_leaderboard.bind(results_ui))
		if not results_ui.main_menu_requested.is_connected(_on_return_to_title):
			results_ui.main_menu_requested.connect(_on_return_to_title)
		if not results_ui.replay_requested.is_connected(_on_start_run_requested):
			results_ui.replay_requested.connect(_on_start_run_requested)
```

#### Edit 8G — Bind `GameAudio` + `WeatherDirector`, Suppress Autosave During Load, Spawn Squad & Freeze Title/Results in `scripts/core/main_controller.gd`
**Target:** `scripts/core/main_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	var audio_mgr: AudioManager = get_node_or_null(audio_manager_path) as AudioManager
	if audio_mgr != null:
		audio_mgr.bind_to_world(self)
```
**Replace with:**
```gdscript
	var audio_mgr: AudioManager = _get_audio_manager()
	if audio_mgr != null:
		audio_mgr.bind_to_world(self)
	var wd: Node = get_node_or_null("WeatherDirector")
	if wd == null and get_tree() != null:
		wd = get_tree().get_first_node_in_group("weather_director")
	if wd != null and wd.has_method("bind_warden"):
		wd.call("bind_warden", warden)
```

#### Edit 8H — Harden `_begin_run_loading()`, Add `_on_results_presented()`, & Freeze World on `_on_return_to_title()` (`scripts/core/main_controller.gd`)
**Target:** `scripts/core/main_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _begin_run_loading() -> void:
	if _building or level_ready:
		return
	_building = true
	_run_started_once = true
	_set_player_active(false)
	_loading = LoadingScreen.new()
	add_child(_loading)
	_loading.set_progress(0.0, "Stepping through the mirror")
	await get_tree().process_frame
	await get_tree().process_frame

	var level: Node = get_node_or_null(level_root_path)
	if level != null and level.has_method("build_greybox_progressive"):
		var on_level := func(frac: float, text: String) -> void:
			_loading.set_progress(frac * 0.85, text)
		level.connect("build_progress", on_level)
		await level.call("build_greybox_progressive")
		level.disconnect("build_progress", on_level)

	var amb: Node = get_node_or_null("AmbientLife")
	if amb != null and amb.has_method("build_progressive"):
		var on_amb := func(frac: float, text: String) -> void:
			_loading.set_progress(0.85 + frac * 0.12, text)
		amb.connect("build_progress", on_amb)
		await amb.call("build_progressive")
		amb.disconnect("build_progress", on_amb)

	_wire_level_dependent()
	_loading.set_progress(0.97, "Waking the squad")

	var ed: Node = get_tree().get_first_node_in_group("encounter_director") if get_tree() != null else null
	if _pending_continue:
		_pending_continue = false
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null and store.has_method("apply_saved_world_state"):
			store.call("apply_saved_world_state")
	elif ed != null and ed.has_method("restart_full_run"):
		# Now that the enemies exist, set their section activation and the run state.
		ed.call("restart_full_run")

	_set_player_active(true)
	var hud_node: HUDController = get_node_or_null(hud_path) as HUDController
	if hud_node != null:
		hud_node.visible = true
	level_ready = true
	_building = false
	level_ready_changed.emit(true)
	await _loading.finish()
	_loading = null
```
**Replace with:**
```gdscript
func _begin_run_loading() -> void:
	if _building or level_ready:
		return
	_building = true
	_run_started_once = true
	PlayerController.ui_input_locked = false
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false
	_set_player_active(false)

	var ed_early: Node = get_tree().get_first_node_in_group("encounter_director") if get_tree() != null else null
	var prev_auto_save: bool = bool(ed_early.get("auto_save_on_checkpoint")) if ed_early != null else true
	if ed_early != null:
		ed_early.set("auto_save_on_checkpoint", false)

	_loading = LoadingScreen.new()
	add_child(_loading)
	_loading.set_progress(0.0, "Stepping through the mirror")
	await get_tree().process_frame
	await get_tree().process_frame

	var level: Node = get_node_or_null(level_root_path)
	if level != null and level.has_method("build_greybox_progressive"):
		var on_level := func(frac: float, text: String) -> void:
			_loading.set_progress(frac * 0.85, text)
		level.connect("build_progress", on_level)
		await level.call("build_greybox_progressive")
		level.disconnect("build_progress", on_level)

	var amb: Node = get_node_or_null("AmbientLife")
	if amb != null and amb.has_method("build_progressive"):
		var on_amb := func(frac: float, text: String) -> void:
			_loading.set_progress(0.85 + frac * 0.12, text)
		amb.connect("build_progress", on_amb)
		await amb.call("build_progressive")
		amb.disconnect("build_progress", on_amb)

	_wire_level_dependent()
	_loading.set_progress(0.97, "Waking the squad")

	var ed: Node = get_tree().get_first_node_in_group("encounter_director") if get_tree() != null else null
	if _pending_continue:
		_pending_continue = false
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null and store.has_method("apply_saved_world_state"):
			store.call("apply_saved_world_state")
	elif ed != null and ed.has_method("restart_full_run"):
		# Now that the enemies exist, set their section activation and the run state.
		ed.call("restart_full_run")

	var squad: Node = get_tree().get_first_node_in_group("squad_manager") if get_tree() != null else null
	if squad != null and squad.has_method("spawn_squad"):
		squad.call("spawn_squad")

	_set_player_active(true)
	var hud_node: HUDController = get_node_or_null(hud_path) as HUDController
	if hud_node != null:
		hud_node.visible = true
	if ed != null:
		ed.set("auto_save_on_checkpoint", prev_auto_save)
	level_ready = true
	_building = false
	level_ready_changed.emit(true)
	await _loading.finish()
	_loading = null
```

#### Edit 8I — Freeze World on Results Presented & Return-to-Title in `scripts/core/main_controller.gd`
**Target:** `scripts/core/main_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _on_return_to_title() -> void:
	var title_ui: TitleScreenController = get_node_or_null(title_screen_path) as TitleScreenController
	if title_ui != null:
		title_ui._sync_ui_nodes()
		title_ui.visible = true
```
**Replace with:**
```gdscript
func _on_results_presented(_summary: Dictionary) -> void:
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = true
	_set_player_active(false)
	var hud_node: HUDController = get_node_or_null(hud_path) as HUDController
	if hud_node != null:
		hud_node.visible = false


func _on_return_to_title() -> void:
	PlayerController.ui_input_locked = false
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = true
		if get_tree().root != null:
			var run_state: Node = get_tree().root.get_node_or_null("RunState")
			if run_state != null and run_state.has_method("pause_timer"):
				run_state.call("pause_timer")
	_set_player_active(false)
	var hud_node: HUDController = get_node_or_null(hud_path) as HUDController
	if hud_node != null:
		hud_node.visible = false
	var title_ui: TitleScreenController = get_node_or_null(title_screen_path) as TitleScreenController
	if title_ui != null:
		title_ui._sync_ui_nodes()
		title_ui.visible = true
```

---

### Step 9 — Fix Title `Q`, Pause `Esc`/Save Status, Options Keybind Merge, & Results Input Lock (`SRS-06`, `SRS-07`, `SRS-11`, `SRS-14`)

- **Prerequisite**: Step 8 complete.
- **Postcondition**: `TitleScreenController` consumes `KEY_Q`; `PauseMenuController` only toggles pause during active alive gameplay and renders `"SAVE FAILED"` in red on disk write failure; `OptionsScreenController` preserves unsaved non-keybind settings across `try_rebind_action()` / `press_reset_controls()`; `ResultsScreenController` locks `PlayerController.ui_input_locked` while visible.

#### Edit 9A — Mark `KEY_Q` Handled in `scripts/ui/title_screen_controller.gd` (`SRS-06`)
**Target:** `scripts/ui/title_screen_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if visible and not quote_overlay_visible and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_Q:
		_toggle_realm_glimpse()
		return
```
**Replace with:**
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if visible and not quote_overlay_visible and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_Q:
		_toggle_realm_glimpse()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return
```

#### Edit 9B — Guard `PauseMenuController` Toggle Input & Report Disk Save Failures (`scripts/ui/pause_menu_controller.gd`)
**Target:** `scripts/ui/pause_menu_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not handle_escape_input:
		return
	if event.is_action_pressed("pause"):
		# Do not toggle pause off while Options or Leaderboard subscreen is open on top
		if _is_subscreen_visible():
			return
		toggle_pause()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	set_paused(not is_paused_state)
```
**Replace with:**
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not handle_escape_input:
		return
	if event.is_action_pressed("pause"):
		# Do not toggle pause off while Options or Leaderboard subscreen is open on top
		# or when Title, Loading, Results, or Player death screen is active.
		if _is_subscreen_visible() or not _can_toggle_pause():
			return
		toggle_pause()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if not is_paused_state and not _can_toggle_pause():
		return
	set_paused(not is_paused_state)
```

#### Edit 9C — Display Save Failure Status & Add `_can_toggle_pause()` in `scripts/ui/pause_menu_controller.gd`
**Target:** `scripts/ui/pause_menu_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func press_save_checkpoint() -> Dictionary:
	var store: Node = _get_leaderboard_store()
	var saved: Dictionary = {}
	if store != null and store.has_method("capture_and_save_world_state"):
		saved = store.call("capture_and_save_world_state") as Dictionary
	last_save_status_text = "CHECKPOINT SAVED"
	_sync_ui_nodes()
	checkpoint_saved.emit(saved)
	return saved
```
**Replace with:**
```gdscript
func press_save_checkpoint() -> Dictionary:
	var store: Node = _get_leaderboard_store()
	var saved: Dictionary = {}
	if store != null and store.has_method("capture_and_save_world_state"):
		saved = store.call("capture_and_save_world_state") as Dictionary
	var save_ok: bool = false
	if store != null:
		if saved.has("_save_ok"):
			save_ok = bool(saved.get("_save_ok", false))
		elif "last_save_error" in store:
			save_ok = int(store.get("last_save_error")) == OK
		else:
			save_ok = not saved.is_empty()
	last_save_status_text = "CHECKPOINT SAVED" if save_ok else "SAVE FAILED"
	_sync_ui_nodes()
	checkpoint_saved.emit(saved)
	return saved
```

#### Edit 9D — Add Save-Status Color Feedback & `_can_toggle_pause()` Helper (`scripts/ui/pause_menu_controller.gd`)
**Target:** `scripts/ui/pause_menu_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	if not save_status_label_path.is_empty():
		var slbl: Label = get_node_or_null(save_status_label_path) as Label
		if slbl != null:
			slbl.text = last_save_status_text
			slbl.visible = not last_save_status_text.is_empty()


func _is_subscreen_visible() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	for grp in ["options_screen", "leaderboard_screen"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).visible:
				return true
	return false
```
**Replace with:**
```gdscript
	if not save_status_label_path.is_empty():
		var slbl: Label = get_node_or_null(save_status_label_path) as Label
		if slbl != null:
			slbl.text = last_save_status_text
			slbl.visible = not last_save_status_text.is_empty()
			var col: Color = Color(0.95, 0.35, 0.30) if last_save_status_text == "SAVE FAILED" else Color(0.48, 0.90, 0.55)
			slbl.add_theme_color_override("font_color", col)


func _can_toggle_pause() -> bool:
	if _is_subscreen_visible():
		return false
	if is_inside_tree() and get_tree() != null:
		for grp in ["title_screen", "results_screen"]:
			for n in get_tree().get_nodes_in_group(grp):
				if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
					return false
		var mc: Node = get_tree().get_first_node_in_group("main_controller")
		if mc != null and (not bool(mc.get("level_ready")) or bool(mc.get("_building")) or mc.get("_loading") != null):
			return false
		var player: Node = get_tree().get_first_node_in_group("player")
		if not is_paused_state and player != null:
			if player.process_mode == Node.PROCESS_MODE_DISABLED or int(player.get("current_state")) == PlayerController.State.DEAD:
				return false
	return true


func _is_subscreen_visible() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	for grp in ["options_screen", "leaderboard_screen"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).visible:
				return true
	return false
```

#### Edit 9E — Preserve Non-Keybind Unsaved Settings on Rebind/Reset in `scripts/ui/options_screen_controller.gd` (`SRS-14`)
**Target:** `scripts/ui/options_screen_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	var res: Dictionary = store.call("rebind_action", action_name, binding_code, swap_on_conflict) as Dictionary
	if bool(res.get("valid", false)):
		conflict_warning_text = ""
		if store.has_method("get_settings"):
			working_settings = (store.call("get_settings") as Dictionary).duplicate(true)
		var new_lbl: String = String(store.call("get_action_display_label", action_name))
```
**Replace with:**
```gdscript
	var res: Dictionary = store.call("rebind_action", action_name, binding_code, swap_on_conflict) as Dictionary
	if bool(res.get("valid", false)):
		conflict_warning_text = ""
		if store.has_method("get_settings"):
			var store_settings: Dictionary = store.call("get_settings") as Dictionary
			if store_settings.get("keybindings") is Dictionary:
				working_settings["keybindings"] = (store_settings["keybindings"] as Dictionary).duplicate(true)
		var new_lbl: String = String(store.call("get_action_display_label", action_name))
```

#### Edit 9F — Preserve Non-Keybind Unsaved Settings in `press_reset_controls()` (`scripts/ui/options_screen_controller.gd`)
**Target:** `scripts/ui/options_screen_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	var store: Node = _get_leaderboard_store()
	var labels: Dictionary = {}
	if store != null and store.has_method("reset_keybindings_to_default"):
		labels = store.call("reset_keybindings_to_default") as Dictionary
		working_settings = (store.call("get_settings") as Dictionary).duplicate(true)
	_sync_keybind_buttons()
```
**Replace with:**
```gdscript
	var store: Node = _get_leaderboard_store()
	var labels: Dictionary = {}
	if store != null and store.has_method("reset_keybindings_to_default"):
		labels = store.call("reset_keybindings_to_default") as Dictionary
		if store.has_method("get_settings"):
			var store_settings: Dictionary = store.call("get_settings") as Dictionary
			if store_settings.get("keybindings") is Dictionary:
				working_settings["keybindings"] = (store_settings["keybindings"] as Dictionary).duplicate(true)
	_sync_keybind_buttons()
```

#### Edit 9G — Lock & Unlock `PlayerController.ui_input_locked` Around `ResultsScreenController` (`SRS-06`)
**Target:** `scripts/ui/results_screen_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("results_screen")
```
**Replace with:**
```gdscript
func _exit_tree() -> void:
	if visible:
		PlayerController.ui_input_locked = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("results_screen")
```

#### Edit 9H — Set `ui_input_locked = true` on `populate_from_summary()` & Clear on Replay/Main Menu (`scripts/ui/results_screen_controller.gd`)
**Target:** `scripts/ui/results_screen_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
	visible = true
	_sync_ui_nodes()
	_play_reveal.call_deferred()
	results_presented.emit(summary)
```
**Replace with:**
```gdscript
	visible = true
	PlayerController.ui_input_locked = true
	_sync_ui_nodes()
	_play_reveal.call_deferred()
	results_presented.emit(summary)
```

#### Edit 9I — Release `PlayerController.ui_input_locked` on `press_replay()` / `press_main_menu()` (`scripts/ui/results_screen_controller.gd`)
**Target:** `scripts/ui/results_screen_controller.gd`
**Action:** Replace block
**Find:**
```gdscript
func press_replay() -> void:
	visible = false
	# MainController reloads the level for a fresh run (the world is rebuilt, not just the director reset).
	replay_requested.emit()


func press_main_menu() -> void:
	visible = false
	main_menu_requested.emit()
```
**Replace with:**
```gdscript
func press_replay() -> void:
	visible = false
	PlayerController.ui_input_locked = false
	# MainController reloads the level for a fresh run (the world is rebuilt, not just the director reset).
	replay_requested.emit()


func press_main_menu() -> void:
	visible = false
	PlayerController.ui_input_locked = false
	main_menu_requested.emit()
```

---

### Step 10 — Create Dedicated Regression Test `tests/spawning_save_bugfix_regression_test.gd`

- **Prerequisite**: Steps 1–9 complete.
- **Postcondition**: `tests/spawning_save_bugfix_regression_test.gd` exists, passes `godot --check-only`, runs cleanly in headless mode, isolates temp `user://_test_srs_*.cfg` files without mutating real user save/settings/leaderboard files, and verifies all 15 fixes (`SRS-01`..`SRS-15`).

**Target:** `tests/spawning_save_bugfix_regression_test.gd`
**Action:** Create
**Content:**
```gdscript
extends SceneTree
## Dedicated regression suite verifying Guide 04 fixes (SRS-01 .. SRS-15).
## Usage: godot --headless --path . -s res://tests/spawning_save_bugfix_regression_test.gd

const MainScene := preload("res://scenes/main/main.tscn")
const AudioManagerScript := preload("res://scripts/core/audio_manager.gd")
const EncounterDirectorScript := preload("res://scripts/core/encounter_director.gd")
const LeaderboardStoreScript := preload("res://scripts/core/leaderboard_store.gd")
const MainControllerScript := preload("res://scripts/core/main_controller.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const RealmManagerScript := preload("res://scripts/core/realm_manager.gd")
const ScoreManagerScript := preload("res://scripts/core/score_manager.gd")
const AllySquadManagerScript := preload("res://scripts/allies/ally_squad_manager.gd")
const EncounterGateScript := preload("res://scripts/environment/encounter_gate.gd")
const InteractSwitchScript := preload("res://scripts/environment/interact_switch.gd")
const MechanismPuzzleScript := preload("res://scripts/environment/mechanism_puzzle.gd")
const RealmPlatformScript := preload("res://scripts/environment/realm_platform.gd")
const SectionTriggerScript := preload("res://scripts/environment/section_trigger_volume.gd")
const WeatherDirectorScript := preload("res://scripts/environment/weather_director.gd")
const OptionsScreenScript := preload("res://scripts/ui/options_screen_controller.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu_controller.gd")
const ResultsScreenScript := preload("res://scripts/ui/results_screen_controller.gd")
const TitleScreenScript := preload("res://scripts/ui/title_screen_controller.gd")

const TEST_LB_PATH: String = "user://_test_srs_lb.cfg"
const TEST_SETTINGS_PATH: String = "user://_test_srs_settings.cfg"
const TEST_SAVE_PATH: String = "user://_test_srs_save.cfg"

var _checks: int = 0
var _fails: int = 0
var _orig_lb_path: String = ""
var _orig_settings_path: String = ""
var _orig_save_path: String = ""


func _check(id: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[srs_test] %s %s %s" % ["PASS" if ok else "FAIL", id, detail])


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("[srs_test] WATCHDOG TIMEOUT")
		_cleanup_temp_store()
		quit(2))
	_run.call_deferred()


func _cleanup_temp_store() -> void:
	var store: Node = root.get_node_or_null("LeaderboardStore")
	if store != null and not _orig_save_path.is_empty():
		store.set("leaderboard_path", _orig_lb_path)
		store.set("settings_path", _orig_settings_path)
		store.set("savegame_path", _orig_save_path)
		if store.has_method("_load_leaderboard_from_disk"):
			store.call("_load_leaderboard_from_disk")
		if store.has_method("_load_settings_from_disk"):
			store.call("_load_settings_from_disk")
		if store.has_method("_load_savegame_from_disk"):
			store.call("_load_savegame_from_disk")
	for p in [TEST_LB_PATH, TEST_SETTINGS_PATH, TEST_SAVE_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _await_level_ready(mc: Node, timeout_ms: int = 45000) -> bool:
	var t0: int = Time.get_ticks_msec()
	while is_instance_valid(mc) and not bool(mc.get("level_ready")) and Time.get_ticks_msec() - t0 < timeout_ms:
		await process_frame
	await process_frame
	return is_instance_valid(mc) and bool(mc.get("level_ready"))


func _run() -> void:
	var store: Node = root.get_node_or_null("LeaderboardStore")
	var run_state: Node = root.get_node_or_null("RunState")
	if store != null:
		_orig_lb_path = String(store.get("leaderboard_path"))
		_orig_settings_path = String(store.get("settings_path"))
		_orig_save_path = String(store.get("savegame_path"))
		store.set("leaderboard_path", TEST_LB_PATH)
		store.set("settings_path", TEST_SETTINGS_PATH)
		store.set("savegame_path", TEST_SAVE_PATH)
		store.set("_entries", ([] as Array[Dictionary]))
		if store.has_method("get_default_settings"):
			store.set("_settings", (store.call("get_default_settings") as Dictionary).duplicate(true))
		if store.has_method("get_default_save_data"):
			store.set("_save_data", (store.call("get_default_save_data") as Dictionary).duplicate(true))

	# ---- Unit checks for SRS-14 & SRS-08 & SRS-11 error path
	var opts := OptionsScreenScript.new() as Control
	opts.build_default_ui_if_empty = false
	root.add_child(opts)
	await process_frame
	var ws: Dictionary = (opts.get("working_settings") as Dictionary).duplicate(true)
	ws["master_volume"] = 0.42
	ws["mouse_sensitivity"] = 0.0091
	opts.set("working_settings", ws)
	var rebind_res: Dictionary = opts.call("try_rebind_action", "interact", "KEY:%d" % KEY_T, false) as Dictionary
	var ws_after_rebind: Dictionary = opts.get("working_settings") as Dictionary
	var srs14_rebind: bool = bool(rebind_res.get("valid", false)) and absf(float(ws_after_rebind.get("master_volume", 0.0)) - 0.42) < 0.001 and absf(float(ws_after_rebind.get("mouse_sensitivity", 0.0)) - 0.0091) < 0.0001
	opts.call("press_reset_controls")
	var ws_after_reset: Dictionary = opts.get("working_settings") as Dictionary
	var srs14_reset: bool = absf(float(ws_after_reset.get("master_volume", 0.0)) - 0.42) < 0.001
	_check("srs14", srs14_rebind and srs14_reset, "master=%s" % str(ws_after_reset.get("master_volume")))
	opts.queue_free()

	# ---- Instantiate Main on Title Screen
	var main := MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	for _i in range(6):
		await process_frame

	# SRS-09: Only GameAudio active; no Main/AudioManager node in scene
	var dup_audio: Node = main.get_node_or_null("AudioManager")
	var audio_mgr: AudioManager = AudioManagerScript.instance as AudioManager
	_check("srs09_no_duplicate", dup_audio == null and audio_mgr != null and audio_mgr == root.get_node_or_null("GameAudio"), "dup=%s" % str(dup_audio))

	# SRS-05 (pre-start): Allies did NOT spawn on Title Screen before floors exist
	var squad := main.get_node_or_null("AllySquad")
	var allies_on_title: Array = squad.get("allies") if squad != null else []
	_check("srs05_title_no_allies", allies_on_title.is_empty(), "allies_on_title=%d" % allies_on_title.size())

	# SRS-10: EncounterDirector checkpoint_transform initialized to Start Terrace (z = -136)
	var ed := EncounterDirectorScript.instance as EncounterDirector
	var init_pos_ok: bool = ed != null and ed.checkpoint_transform.origin.distance_to(Vector3(0.0, 0.0, -136.0)) < 0.1
	_check("srs10_default_spawn", init_pos_ok, "origin=%s" % str(ed.checkpoint_transform.origin if ed != null else Vector3.ZERO))

	# SRS-07: PauseMenu toggle rejected on Title Screen
	var pause_ui := main.get_node_or_null("MenusLayer/PauseMenu") as Control
	if pause_ui != null:
		pause_ui.call("toggle_pause")
	_check("srs07_pause_blocked_on_title", pause_ui != null and not bool(pause_ui.get("is_paused_state")) and not paused, "paused=%s" % str(paused))

	# SRS-06: Title Q does not shift RealmManager
	var rm := RealmManagerScript.instance as RealmManager
	var title_ui := main.get_node_or_null("MenusLayer/TitleScreen") as Control
	var realm_before_q: int = int(rm.current_realm) if rm != null else 0
	if title_ui != null:
		title_ui.set("quote_overlay_visible", false)
		var q_ev := InputEventKey.new()
		q_ev.keycode = KEY_Q
		q_ev.pressed = true
		if rm != null:
			rm._unhandled_input(q_ev)
	_check("srs06_realm_locked_on_title", rm != null and int(rm.current_realm) == realm_before_q, "realm=%d" % (int(rm.current_realm) if rm != null else -1))

	# ---- Start run
	if title_ui != null:
		title_ui.set("show_quote_on_start", false)
		title_ui.call("press_start")
	var ready_ok: bool = await _await_level_ready(main)
	_check("srs05_allies_spawned_after_load", ready_ok and squad != null and (squad.get("allies") as Array).size() >= 3, "allies=%d" % ((squad.get("allies") as Array).size() if squad != null else -1))

	# SRS-15: WeatherDirector bound to TheWarden
	var wd := main.get_node_or_null("WeatherDirector")
	var warden := main.get_node_or_null("LevelRoot/Stage05_ExecutionArena/Enemies/TheWarden")
	var bound_ok: bool = wd != null and warden != null and wd.get("_bound_warden") == warden
	if wd != null and warden != null:
		wd.call("_on_warden_phase_changed", 3)
		var p2_prof: String = String(wd.call("get_profile_for", 150.0))
		wd.call("_on_warden_defeated")
		var dead_prof: String = String(wd.call("get_profile_for", 150.0))
		wd.call("_on_warden_health_changed", int(warden.get("max_health")), int(warden.get("max_health")))
		var reset_prof: String = String(wd.call("get_profile_for", 150.0))
		bound_ok = bound_ok and p2_prof == "blood_frenzy" and dead_prof == "aftermath" and reset_prof == "blood"
	_check("srs15_weather_bound", bound_ok, "wd=%s" % str(wd))

	# SRS-13: Player respawn_at resets full combat/stamina/buffer state & _verify_spawn_safety guards null/self
	var player := main.get_node_or_null("Player") as CharacterBody3D
	if player != null:
		player.set("stamina", 12.0)
		player.set("_flow_streak", 4)
		player.set("_flow_tap", true)
		player.set("_ally_ward_hp", 25)
		player.set("_finisher_cooldown_end_ms", 99999999)
		player.set("_jump_buffer_timer", 0.3)
		player.call("respawn_at", Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0)))
		var safe_null := Vector3(1.0, 2.0, 3.0)
		var temp_player := PlayerControllerScript.new() as Node3D
		var out_of_tree_pos: Vector3 = temp_player.call("_verify_spawn_safety", safe_null) as Vector3
		temp_player.free()
		var srs13_ok: bool = absf(float(player.get("stamina")) - float(player.get("max_stamina"))) < 0.01 \
			and int(player.get("_flow_streak")) == 0 and not bool(player.get("_flow_tap")) \
			and int(player.get("_ally_ward_hp")) == 0 and int(player.get("_finisher_cooldown_end_ms")) == 0 \
			and absf(float(player.get("_jump_buffer_timer"))) < 0.001 and out_of_tree_pos.is_equal_approx(safe_null)
		_check("srs13_player_respawn_reset", srs13_ok)

	# SRS-02 + SRS-04: Death rewind across 3 checkpoints resets failed_section, gates, switches, puzzle, bridge & does NOT auto-begin combat inside _on_section_reset_requested
	var reset_counts: Dictionary = {}
	if ed != null:
		ed.section_reset_requested.connect(func(sec_i: int) -> void:
			reset_counts[sec_i] = int(reset_counts.get(sec_i, 0)) + 1)
		var hall_xform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 4.0, 58.0))
		var gal_xform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 6.0, 165.5))
		var arena_xform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 10.0, 300.0))
		ed.advance_to_section(EncounterDirectorScript.Section.HALL_COMBAT, hall_xform, true)
		ed.advance_to_section(EncounterDirectorScript.Section.COLLAPSED_GALLERY, gal_xform, true)
		ed.advance_to_section(EncounterDirectorScript.Section.EXECUTION_ARENA, arena_xform, true)

		var sw3 := main.get_node_or_null("LevelRoot/Stage03_CollapsedGallery/BridgeAnchorSwitch")
		var brg := main.get_node_or_null("LevelRoot/Stage03_CollapsedGallery/GallerySpectralBridge")
		var gate2a := main.get_node_or_null("LevelRoot/Stage02_HallOfEchoes/Gate02a_HallSouthSeal")
		var gate2 := main.get_node_or_null("LevelRoot/Stage02_HallOfEchoes/Gate02_HallToGallery")
		var gate4b := main.get_node_or_null("LevelRoot/Stage05_ExecutionArena/Gate04b_ArenaSouthSeal")
		var puz := main.get_node_or_null("LevelRoot/Stage04_MechanismChamber/ChamberMechanismPuzzle")
		if sw3 != null:
			sw3.set("is_activated", true)
		if brg != null:
			brg.call("repair_for_reality")
		if gate2a != null:
			gate2a.call("seal_gate_for_encounter")
		if gate2 != null:
			gate2.call("unlock_and_open")
		if gate4b != null:
			gate4b.call("seal_gate_for_encounter")
		if puz != null:
			puz.call("force_solve_bypass")
		ed.completed_encounters["hall_of_echoes"] = true
		ed.completed_encounters["the_warden"] = true

		# Trigger reset test for SRS-04: Hall trigger reset must NOT start encounter immediately
		var trig2 := main.get_node_or_null("LevelRoot/Stage02_HallOfEchoes/Trigger_Stage02_Hall")
		if trig2 != null:
			ed.completed_encounters.erase("hall_of_echoes")
			trig2.set("has_triggered", true)
			ed.current_encounter_id = ""
			trig2.call("_on_section_reset_requested", EncounterDirectorScript.Section.HALL_COMBAT)
			var srs04_ok: bool = not bool(trig2.get("has_triggered")) and String(ed.current_encounter_id).is_empty()
			_check("srs04_no_immediate_encounter_on_reset", srs04_ok, "enc=%s" % String(ed.current_encounter_id))

		ed.completed_encounters["hall_of_echoes"] = true
		reset_counts.clear()
		ed.handle_player_death(player)
		var dedup_ok: bool = int(reset_counts.get(1, 0)) == 1 and int(reset_counts.get(2, 0)) == 1 and int(reset_counts.get(3, 0)) == 1 and int(reset_counts.get(4, 0)) == 1
		var world_reset_ok: bool = int(ed.current_section) == EncounterDirectorScript.Section.HALL_COMBAT \
			and (gate2a == null or bool(gate2a.get("is_open"))) \
			and (gate2 == null or not bool(gate2.get("is_open"))) \
			and (gate4b == null or bool(gate4b.get("is_open"))) \
			and (sw3 == null or not bool(sw3.get("is_activated"))) \
			and (brg == null or not bool(brg.get("is_permanently_repaired"))) \
			and (puz == null or not bool(puz.get("is_solved"))) \
			and not ed.completed_encounters.has("hall_of_echoes") \
			and not ed.completed_encounters.has("the_warden")
		_check("srs02_dedup_and_full_section_reset", dedup_ok and world_reset_ok, "counts=%s sec=%d" % [str(reset_counts), int(ed.current_section)])

	# SRS-11: Live unbanked score saved + Save error status shown
	if run_state != null and store != null:
		run_state.call("start_new_run")
		run_state.set("banked_score", 300)
		run_state.set("score", 650)
		var bad_path: String = "user://__missing_dir__/fail.cfg"
		store.set("savegame_path", bad_path)
		if pause_ui != null:
			var fail_res: Dictionary = pause_ui.call("press_save_checkpoint") as Dictionary
			_check("srs11_save_error_reported", String(pause_ui.get("last_save_status_text")) == "SAVE FAILED" and not bool(fail_res.get("_save_ok", true)))
		store.set("savegame_path", TEST_SAVE_PATH)

	# SRS-01 + SRS-03 + SRS-12: Save multi-checkpoint Stage 04 run, test Continue reload without overwrite
	if ed != null and store != null and run_state != null:
		ed.restart_full_run()
		run_state.set("banked_score", 400)
		run_state.set("score", 775)
		var cp1 := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 4.0, 58.0))
		var cp2 := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 6.0, 165.5))
		var cp3 := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 6.0, 194.0))
		ed.advance_to_section(EncounterDirectorScript.Section.HALL_COMBAT, cp1, true)
		ed.advance_to_section(EncounterDirectorScript.Section.COLLAPSED_GALLERY, cp2, true)
		ed.advance_to_section(EncounterDirectorScript.Section.MECHANISM_CHAMBER, cp3, true)
		ed.completed_encounters["hall_of_echoes"] = true
		ed.completed_encounters["shielded_guard"] = true
		ed.completed_encounters["the_warden"] = true
		var puz_s := main.get_node_or_null("LevelRoot/Stage04_MechanismChamber/ChamberMechanismPuzzle")
		if puz_s != null:
			puz_s.call("force_solve_bypass")
		store.call("capture_and_save_world_state", main)

		# Simulate Continue reload sequence
		main.call("_on_continue_requested")
		var old_id: int = main.get_instance_id()
		var t_wait: int = 0
		while t_wait < 600:
			await process_frame
			t_wait += 1
			var cur_mc: Node = get_first_node_in_group("main_controller")
			if cur_mc != null and cur_mc.get_instance_id() != old_id:
				main = cur_mc
				break
		var cont_ready: bool = await _await_level_ready(main)
		var ed2 := EncounterDirectorScript.instance as EncounterDirector
		var puz2 := main.get_node_or_null("LevelRoot/Stage04_MechanismChamber/ChamberMechanismPuzzle")
		var gate5_2 := main.get_node_or_null("LevelRoot/Stage05_ExecutionArena/Gate05_ArenaExit")
		var warden2 := main.get_node_or_null("LevelRoot/Stage05_ExecutionArena/Enemies/TheWarden")
		var trig1_2 := main.get_node_or_null("LevelRoot/Stage01_EntryVestibule/Trigger_Stage01_Entry")
		var hist2: Array = ed2.get("_checkpoint_history") if ed2 != null else []
		_check("srs01_continue_not_overwritten", cont_ready and ed2 != null and int(ed2.current_section) == EncounterDirectorScript.Section.MECHANISM_CHAMBER, "sec=%d" % (int(ed2.current_section) if ed2 != null else -1))
		_check("srs03_checkpoint_history_restored", hist2.size() >= 3, "hist_size=%d" % hist2.size())
		_check("srs11_live_score_restored", run_state != null and int(run_state.get("score")) >= 775, "score=%d" % int(run_state.get("score")))
		_check("srs12_world_and_triggers_restored", puz2 != null and bool(puz2.get("is_solved")) and bool(puz2.get("is_plate_pressed")) and warden2 != null and bool(warden2.get("is_dead")) and gate5_2 != null and bool(gate5_2.get("is_open")) and trig1_2 != null and bool(trig1_2.get("has_triggered")))

	# SRS-08: ScoreManager.finalize_run() idempotency
	if run_state != null and store != null:
		run_state.call("start_new_run")
		var finalized_emits: int = 0
		var cb := func(_s: Dictionary) -> void: finalized_emits += 1
		run_state.connect("run_finalized", cb)
		var before_runs: int = int(((store.call("get_saved_run_data") as Dictionary).get("profile_stats", {}) as Dictionary).get("total_runs_completed", 0))
		run_state.call("finalize_run", true)
		run_state.call("finalize_run", true)
		var after_runs: int = int(((store.call("get_saved_run_data") as Dictionary).get("profile_stats", {}) as Dictionary).get("total_runs_completed", 0))
		if run_state.is_connected("run_finalized", cb):
			run_state.disconnect("run_finalized", cb)
		_check("srs08_finalize_idempotent", finalized_emits == 1 and (after_runs - before_runs) == 1, "emits=%d delta=%d" % [finalized_emits, after_runs - before_runs])

	# SRS-06: Results screen + Return to Title freeze SceneTree & lock player/HUD/input
	var results_ui := main.get_node_or_null("MenusLayer/ResultsScreen") as Control
	var hud_node := main.get_node_or_null("HUD") as CanvasItem
	var player2 := main.get_node_or_null("Player")
	if results_ui != null:
		results_ui.call("populate_from_summary", {"score": 1200, "time_sec": 45.0, "time_bonus": 300, "warden_bonus": 1000, "rank": "B"})
		var res_frozen: bool = paused and PlayerControllerScript.ui_input_locked and player2 != null and player2.process_mode == Node.PROCESS_MODE_DISABLED and hud_node != null and not hud_node.visible
		_check("srs06_results_freezes_world", res_frozen)
		results_ui.call("press_main_menu")
		var title_frozen: bool = paused and not PlayerControllerScript.ui_input_locked and player2 != null and player2.process_mode == Node.PROCESS_MODE_DISABLED and hud_node != null and not hud_node.visible
		_check("srs06_return_to_title_freezes_world", title_frozen)

	paused = false
	PlayerControllerScript.ui_input_locked = false
	_cleanup_temp_store()
	print("[srs_test] SUMMARY %d checks, %d failed" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
```

---

### Step 11 — Synchronize `MEMORY/02`, `MEMORY/05`, and `MEMORY/07` (`AGENTS.md` Rule 1.3)

- **Prerequisite**: Steps 1–10 complete and verified.
- **Postcondition**: `MEMORY/02`, `MEMORY/05`, and `MEMORY/07` reflect all Guide 04 architectural, audio singleton, save/restore, and UI gating updates; no extra `.md` files created.

#### Edit 11A — Sync `MEMORY/02_CORE_SYSTEMS_AND_ARCHITECTURE.md` (§1.1 Main Scene Hierarchy)
**Target:** `MEMORY/02_CORE_SYSTEMS_AND_ARCHITECTURE.md`
**Action:** Replace block
**Find:**
```markdown
**Autoloads (`project.godot`)**:
- `RunState` (`scripts/core/score_manager.gd`): Holds score, combo chain, elapsed run timer, per-encounter no-hit flags, and checkpoint banked score.
- `LeaderboardStore` (`scripts/core/leaderboard_store.gd` — or accessed statically/autoloaded): Handles `user://leaderboard.cfg` Top 5 persistence & settings.
- `_mcp_game_helper` (`addons/godot_ai/runtime/game_helper.gd`): Already enabled for `godot-ai` MCP testing.
```
**Replace with:**
```markdown
**Autoloads (`project.godot`)**:
- `RunState` (`scripts/core/score_manager.gd`): Holds score, combo chain, elapsed run timer, per-encounter no-hit flags, checkpoint banked score, and idempotent `_run_finalized` state for `finalize_run()`.
- `LeaderboardStore` (`scripts/core/leaderboard_store.gd` — or accessed statically/autoloaded): Handles `user://leaderboard.cfg` Top 5 persistence, settings, `user://savegame.cfg` state + `checkpoint_history`, and `last_save_error` disk error tracking.
- `GameAudio` (`scripts/core/audio_manager.gd`): Single authoritative `AudioManager` singleton across scene reloads (`Main/AudioManager` removed from `main.tscn`; `MainController._get_audio_manager()` binds `GameAudio` per loaded run and resets `_warden_dead`).
- `_mcp_game_helper` (`addons/godot_ai/runtime/game_helper.gd`): Already enabled for `godot-ai` MCP testing.
```

#### Edit 11B — Sync `MEMORY/02_CORE_SYSTEMS_AND_ARCHITECTURE.md` (§5.2 Save & Load Lifecycle Hooks)
**Target:** `MEMORY/02_CORE_SYSTEMS_AND_ARCHITECTURE.md`
**Action:** Replace block
**Find:**
```markdown
### 5.2 Save & Load Lifecycle Hooks
- **Auto-Save**: `EncounterDirector.set_checkpoint()` and `EncounterDirector.complete_combat_encounter()` automatically call `LeaderboardStore.capture_and_save_world_state()`.
- **Manual Save**: `PauseMenuController.press_save_checkpoint()` (`SaveCheckpointButton`) and `PauseMenuController.press_main_menu(true)` (`Save & Main Menu`) capture and save the live world state to `user://savegame.cfg`.
- **Continue Run**: `TitleScreenController` automatically shows `ContinueButton` when `has_saved_run()` is true; `press_continue()` invokes `LeaderboardStore.apply_saved_world_state()`, restoring section, checkpoint transform, active realm, banked score, elapsed timer, player HP, solved switches/bridges/puzzles, and cleared encounters/gates.
- **Run Completion**: `ScoreManager.finalize_run(true)` updates `[profile]` lifetime statistics and clears `has_active_run` while preserving `[profile]` and `[custom]`.
```
**Replace with:**
```markdown
### 5.2 Save & Load Lifecycle Hooks
- **Startup & Squad Gating**: `MainController._enter_tree()` registers `"main_controller"` before child `_ready()`, keeping `AllySquadManager` deferred until `MainController._begin_run_loading()` builds floors, restores saves/restarts run (with `auto_save_on_checkpoint` suppressed and `SectionTriggerVolume` blocked until `level_ready`), and spawns/regroups allies via `spawn_squad()`. `WeatherDirector.bind_warden()` is invoked after level build and retried in `_process()`.
- **Death Rewind & Reset Contract**: `EncounterDirector` initializes `checkpoint_transform = default_spawn` (`z = -136`). `handle_player_death()` rewinds `2` checkpoints via `_checkpoint_history`, deduplicates and emits `section_reset_requested` once per rewound section across `checkpoint_section .. max(completed, failed_section)`, clears rewound `completed_encounters` and `ScoreManager.current_active_encounter`, and resets `EncounterGate` (`is_permanently_unlocked = false`), `InteractSwitch`, `MechanismPuzzle`, `RealmPlatform`, `SectionTriggerVolume` (`has_triggered = false` without re-starting combat), `BreakableProp`, `EnemyBase`, and `WardenBoss`.
- **Auto-Save**: `EncounterDirector.set_checkpoint()` and `EncounterDirector.complete_combat_encounter()` automatically call `LeaderboardStore.capture_and_save_world_state()`.
- **Manual Save**: `PauseMenuController.press_save_checkpoint()` and `press_main_menu(true)` capture live `score`, `awarded_event_ids`, `banked_score`, `checkpoint_history`, and world flags, showing `"CHECKPOINT SAVED"` or `"SAVE FAILED"` based on `last_save_error`.
- **Continue Run**: `TitleScreenController.press_continue()` sets `pending_continue`; `MainController` builds the level with `auto_save_on_checkpoint` suppressed and invokes `LeaderboardStore.apply_saved_world_state()`, restoring `checkpoint_history` (with legacy synthesis), live `score`, `banked_score`, active realm, `ChamberMechanismPuzzle.force_solve_bypass()`, cleared `the_warden` state (`CentralMirrorPlane`, `Gate05_ArenaExit`), passed `SectionTriggerVolume` states, active mid-section encounter seals, and squad `regroup(true)`.
- **Run Completion & UI Freeze**: `ScoreManager.finalize_run(true)` is idempotent via `_run_finalized`, updating `[profile]` once and clearing `has_active_run`. Showing Results or returning to Title pauses `SceneTree`, disables `Player`, hides `HUD`, and guards `PauseMenu`/`RealmManager` inputs.
```

#### Edit 11C — Sync `MEMORY/05_UI_SCORING_AND_AUDIO.md` (§1 Submission Rule & §2.2 Screens)
**Target:** `MEMORY/05_UI_SCORING_AND_AUDIO.md`
**Action:** Replace block
**Find:**
```markdown
- **Submission rule**: Recorded **only** after defeating The Warden and reaching Results. Abandoned runs are not saved. Leaderboard reset allowed only via confirmation dialog inside Options menu.
```
**Replace with:**
```markdown
- **Submission rule**: Recorded **only** after defeating The Warden and reaching Results (`ScoreManager.finalize_run()` is idempotent via `_run_finalized`). Abandoned runs are not saved. Leaderboard reset allowed only via confirmation dialog inside Options menu.
```

#### Edit 11D — Sync `MEMORY/05_UI_SCORING_AND_AUDIO.md` (§2.2 Screens 2, 5, 7)
**Target:** `MEMORY/05_UI_SCORING_AND_AUDIO.md`
**Action:** Replace block
**Find:**
```markdown
2. **Pause Menu (`Esc`)** (`scripts/ui/pause_menu_controller.gd` — `PauseMenuController`): `PROCESS_MODE_ALWAYS`, freezes `SceneTree.paused` and `RunState` timer; auto-builds interactive UI if empty; actions: `Resume`, `Save Checkpoint` (with `SaveStatusLabel` feedback), `Restart Section`, `Restart Run` *(confirm)*, `Options & Controls`, `Save & Main Menu` *(confirm + auto-save)*. Ignores `Esc` toggle while `OptionsScreen` or `LeaderboardScreen` subscreen is open on top.
3. **Tutorial Prompts** (`scripts/ui/hud_controller.gd` — `HUDController`): Compact inline prompt near action (`get_tutorial_prompt_text()` dynamically reflects live keybindings for `WASD`, `Q: Shift`, `E: Interact`, `F in Air: Landing Attack`) -> auto-dismisses on first successful execution (`mark_tutorial_completed()`).
4. **Death Overlay** (`scripts/ui/death_overlay_controller.gd` — `DeathOverlayController`): Brief `0.65s` non-blocking fade + automatic respawn at current section checkpoint (no extra confirmation clicks).
5. **Results Screen** (`scripts/ui/results_screen_controller.gd` — `ResultsScreenController`): Breakdown of Score, Time, Time Bonus, Rank (`S/A/B/C`), 3-letter Initials entry if Top 5 qualified -> `Submit`, `Leaderboard`, `Replay`, `Main Menu`.
6. **Leaderboard Screen** (`scripts/ui/leaderboard_screen_controller.gd` — `LeaderboardScreenController`): Top 5 table (`#`, Initials, Score, Time, Rank) + `Back`.
7. **Options & Settings Screen** (`scripts/ui/options_screen_controller.gd` — `OptionsScreenController`): `PROCESS_MODE_ALWAYS`, auto-builds a 4-tab interactive UI (`Display_Graphics`, `Sound`, `Controls`, `Gameplay_Save`) when empty:
   - **Display & Graphics Tab**: Screen Type (`Windowed`, `Borderless`, `Fullscreen`), Resolution (`1280x720`..`3840x2160`), VSync (`Disabled`, `Enabled`, `Adaptive`), Graphics Preset (`Low`, `Medium`, `High`, `Ultra`, `Custom`), 3D Anti-Aliasing (`Off`, `2x`, `4x`, `8x MSAA`), Shadow Quality (`Off`, `Low`, `Medium`, `High`), Bloom/Glow toggle, Atmospheric Fog toggle, Brightness/Exposure slider (`0.5..1.5`), **3D Render Scale** slider (`0.5..1.0`, FSR below 1.0; presets low 0.7 / medium 0.85 / high+ 1.0) and **Adaptive Resolution** toggle (`PerformanceGovernor`) — 2026-11-17.
   - **Sound Tab**: Master, Music, and SFX volume sliders (`0..1`), Mute When Unfocused.
   - **Controls Tab**: Interactive key/mouse rebinding buttons (`BindBtn_<action>`) for all 11 gameplay actions with live `PRESS KEY / MOUSE...` listening state (`_input()`), `ConflictWarningLabel` displaying validation errors when a duplicate or reserved key (`ESC`) is pressed, and `Reset Controls to Default` button.
```
**Replace with:**
```markdown
2. **Pause Menu (`Esc`)** (`scripts/ui/pause_menu_controller.gd` — `PauseMenuController`): `PROCESS_MODE_ALWAYS`, freezes `SceneTree.paused` and `RunState` timer; auto-builds interactive UI if empty; actions: `Resume`, `Save Checkpoint` (with `SaveStatusLabel` feedback displaying `"CHECKPOINT SAVED"` or `"SAVE FAILED"` on disk errors), `Restart Section`, `Restart Run` *(confirm)*, `Options & Controls`, `Save & Main Menu` *(confirm + auto-save)*. `_can_toggle_pause()` blocks toggling when Title, Results, Loading (`not level_ready` / `_building`), `OptionsScreen`, `LeaderboardScreen`, or Player death/disabled state is active.
3. **Tutorial Prompts** (`scripts/ui/hud_controller.gd` — `HUDController`): Compact inline prompt near action (`get_tutorial_prompt_text()` dynamically reflects live keybindings for `WASD`, `Q: Shift`, `E: Interact`, `F in Air: Landing Attack`) -> auto-dismisses on first successful execution (`mark_tutorial_completed()`).
4. **Death Overlay** (`scripts/ui/death_overlay_controller.gd` — `DeathOverlayController`): Brief `0.65s` non-blocking fade + automatic respawn at current section checkpoint (no extra confirmation clicks).
5. **Results Screen** (`scripts/ui/results_screen_controller.gd` — `ResultsScreenController`): Breakdown of Score, Time, Time Bonus, Rank (`S/A/B/C`), 3-letter Initials entry if Top 5 qualified -> `Submit`, `Leaderboard`, `Replay`, `Main Menu`. Locks `PlayerController.ui_input_locked` while visible; `MainController` freezes world & hides `HUD` on `results_presented` and return-to-title (`TitleScreenController` consumes `KEY_Q`).
6. **Leaderboard Screen** (`scripts/ui/leaderboard_screen_controller.gd` — `LeaderboardScreenController`): Top 5 table (`#`, Initials, Score, Time, Rank) + `Back`.
7. **Options & Settings Screen** (`scripts/ui/options_screen_controller.gd` — `OptionsScreenController`): `PROCESS_MODE_ALWAYS`, auto-builds a 4-tab interactive UI (`Display_Graphics`, `Sound`, `Controls`, `Gameplay_Save`) when empty:
   - **Display & Graphics Tab**: Screen Type (`Windowed`, `Borderless`, `Fullscreen`), Resolution (`1280x720`..`3840x2160`), VSync (`Disabled`, `Enabled`, `Adaptive`), Graphics Preset (`Low`, `Medium`, `High`, `Ultra`, `Custom`), 3D Anti-Aliasing (`Off`, `2x`, `4x`, `8x MSAA`), Shadow Quality (`Off`, `Low`, `Medium`, `High`), Bloom/Glow toggle, Atmospheric Fog toggle, Brightness/Exposure slider (`0.5..1.5`), **3D Render Scale** slider (`0.5..1.0`, FSR below 1.0; presets low 0.7 / medium 0.85 / high+ 1.0) and **Adaptive Resolution** toggle (`PerformanceGovernor`) — 2026-11-17.
   - **Sound Tab**: Master, Music, and SFX volume sliders (`0..1`), Mute When Unfocused.
   - **Controls Tab**: Interactive key/mouse rebinding buttons (`BindBtn_<action>`) for all 11 gameplay actions with live `PRESS KEY / MOUSE...` listening state (`_input()`), `ConflictWarningLabel` displaying validation errors when a duplicate or reserved key (`ESC`) is pressed, and `Reset Controls to Default` button (merges only `keybindings` into `working_settings`, preserving unsaved Display/Graphics/Sound/Gameplay edits).
```

#### Edit 11E — Sync `MEMORY/05_UI_SCORING_AND_AUDIO.md` (§3.6 Audio Routing Contract Singleton Note)
**Target:** `MEMORY/05_UI_SCORING_AND_AUDIO.md`
**Action:** Replace block
**Find:**
```markdown
### 3.6 Audio Routing Contract (2026-11-17 overhaul — `scripts/core/audio_manager.gd`)
```
**Replace with:**
```markdown
### 3.6 Audio Routing Contract (2026-11-17 overhaul — `scripts/core/audio_manager.gd`, single `GameAudio` autoload bound per reload by `MainController._get_audio_manager()`)
```

#### Edit 11F — Append Dated Changelog Entry in `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`
**Target:** `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`
**Action:** Replace block
**Find:**
```markdown
- 2026-11-19: Stacked Dodge Chaining & Execution Shield Pierce - Implemented consecutive stacked dodge chaining in PlayerController (_process_dodge_state allows chaining past i-frames t_norm > 0.45; start_dodge accepts State.DODGE; buffer consumes seamlessly on finish). ShieldedGuard._modify_incoming_damage allows player_execution to bypass shield deflect. Verified with charged_heavy_test (18 checks), feel_and_movement_test (13 checks), combat_rules_test (10 checks), and restart_flow_test (PASS).
```
**Replace with:**
```markdown
- 2026-11-19: Stacked Dodge Chaining & Execution Shield Pierce - Implemented consecutive stacked dodge chaining in PlayerController (_process_dodge_state allows chaining past i-frames t_norm > 0.45; start_dodge accepts State.DODGE; buffer consumes seamlessly on finish). ShieldedGuard._modify_incoming_damage allows player_execution to bypass shield deflect. Verified with charged_heavy_test (18 checks), feel_and_movement_test (13 checks), combat_rules_test (10 checks), and restart_flow_test (PASS).
- 2026-11-20 (Guide 04 — Spawning, Respawning, Audio & Save Remediation, SRS-01..15): Protected Continue saves from `Trigger_Stage01_Entry` mid-load overwrites (`MainController` autosave suppression + `SectionTriggerVolume._is_world_ready_for_trigger()`); fixed 2-checkpoint death rewind reset scope across `checkpoint_section .. max(completed, failed_section)`, cleared rewound `completed_encounters`, removed premature `begin_combat_encounter()` in `SectionTriggerVolume._on_section_reset_requested()`, and added `section_reset_requested` reset handlers to `InteractSwitch`, `MechanismPuzzle`, `RealmPlatform`, and `EncounterGate`; persisted/restored `_checkpoint_history`, live `score`/`awarded_event_ids`, `last_save_error`, `force_solve_bypass()`, `the_warden`, passed triggers, and mid-section seals in `LeaderboardStore`; gated `AllySquadManager` spawning on `level_ready` + called `regroup(true)` on restart/continue; initialized `EncounterDirector.checkpoint_transform` to `(0, 0, -136)`; removed duplicate `Main/AudioManager` in `main.tscn` and bound `GameAudio` cleanly across reloads; added `ScoreManager.finalize_run()` `_run_finalized` idempotency; froze world/player/HUD on Results & Title Return, blocked `Esc`/`Q` outside active gameplay, preserved non-keybind `working_settings` on rebind/reset, reset remaining combat/stamina/buffer state in `PlayerController.respawn_at()` + hardened `_verify_spawn_safety()`, added `WeatherDirector.bind_warden()` retry wiring, added `tests/spawning_save_bugfix_regression_test.gd`, and synced `MEMORY/02`, `05`, `07`.
```

---

## E. Verification & Failure Handling

Run every command below in PowerShell from `D:\Desktop\Godot\parallax`.

| Ver ID | Command | Preconditions | Expected Pass Condition | Covers |
| :--- | :--- | :--- | :--- | :--- |
| **VER-01** | `foreach ($f in @("scripts/core/audio_manager.gd","scripts/core/score_manager.gd","scripts/core/encounter_director.gd","scripts/core/leaderboard_store.gd","scripts/core/main_controller.gd","scripts/core/realm_manager.gd","scripts/player/player_controller.gd","scripts/allies/ally_squad_manager.gd","scripts/environment/encounter_gate.gd","scripts/environment/interact_switch.gd","scripts/environment/mechanism_puzzle.gd","scripts/environment/realm_platform.gd","scripts/environment/section_trigger_volume.gd","scripts/environment/weather_director.gd","scripts/ui/title_screen_controller.gd","scripts/ui/pause_menu_controller.gd","scripts/ui/options_screen_controller.gd","scripts/ui/results_screen_controller.gd","tests/spawning_save_bugfix_regression_test.gd")) { Write-Host "CHECK $f"; & "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" --check-only -s "res://$f"; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }` | Steps 1–10 applied | Exit `0`, zero `SCRIPT ERROR` or parser errors across all 19 checked GDScript files. | `SRS-01`..`SRS-15` |
| **VER-02** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/spawning_save_bugfix_regression_test.gd` | Steps 1–10 applied | Exit `0`; prints `[srs_test] SUMMARY <N> checks, 0 failed` with all checks (`srs01`..`srs15`) `PASS` and leaves no `user://_test_srs_*` files behind. | `SRS-01`..`SRS-15` |
| **VER-03** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/restart_flow_test.gd` | Steps 1–9 applied | Exit `0`; prints `=> PASS`. | `SRS-01`, `SRS-02`, `SRS-03`, `SRS-05`, `SRS-09` |
| **VER-04** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/sanity_regression_test.gd` | Steps 1–9 applied | Exit `0`; prints `[sanity_regression] Regression tests completed. Result: PASSED`. | `REQ-14`, `REQ-15`, `REQ-20`, `REQ-21` |
| **VER-05** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/boot_smoke.gd` | Steps 1–9 applied | Exit `0`; prints `[boot_smoke] OK` with `allies >= 3` and `enemies > 0`. | `SRS-05`, `SRS-09`, boot regression |
| **VER-06** | `& "C:/Users/agrim/.local/bin/godot.cmd" --headless --path "D:/Desktop/Godot/parallax" -s res://tests/level_props_test.gd` | Step 3 & Step 4 applied | Exit `0`; `0 failed` across gate, switch, puzzle, and realm platform resets. | `SRS-02`, `SRS-04` |

### Failure Recovery Protocol
- **A `Find:` block fails to match**: Inspect the actual lines around the target method, verify Guides 01–03 were already applied (or standalone baseline matches `1ca7464`), and report exact mismatch rather than guessing.
- **Headless `main.tscn` load error after editing `scenes/main/main.tscn`**: Verify `load_steps=16` in line 1 of `scenes/main/main.tscn` and ensure neither `ExtResource("5_audio")` nor `[node name="AudioManager"]` remains.
- **Test fails with `SCRIPT ERROR`**: Re-run `VER-01` on the reported script to isolate any indentation/symbol issue; restore individual file cleanly with `git checkout -- <path>` if reverting a failed partial edit.

---

## F. Completion Report Contract

When execution finishes, output a concise report containing ONLY verified observations:

1. **Author Validation Status**: Confirm this guide was authored via static inspection (`READY`), and report executor-run runtime results separately.
2. **Applied Step IDs**: Explicit list (`Step 1` .. `Step 11`) and any partial/skipped steps.
3. **Changed Files**: Exact modified/created paths matching Section C (plus confirmation of zero unintended untracked `.md` or temporary `user://_test_srs_*` artifacts).
4. **Verification Results Table**:
   - Check ID (`VER-01` .. `VER-06`)
   - Exact Exit Code
   - Printed summary / pass line observed
5. **Remaining Unverified Items / Blockers**: Note any interactive windowed checks (e.g., manual Title -> Continue -> Results keyboard typing playtest) not automated in headless CLI.
6. **Definition of Done**: Steps 1–11 applied cleanly, `VER-01` through `VER-06` exit `0` with `0 failed`, and all invariants (`REQ-15`, `REQ-19..24`, `1ca7464`) preserved.
