# PARALLAX — Post-Audit Execution Tasks & Claude Prompts

> **Status**: Antigravity Passes 1–9 are 100% complete, verified with 0 failures across 10 test suites, and audited in [IdiotCheckInQualityAssessment.md](file:///D:/Desktop/Godot/parallax/IdiotCheckInQualityAssessment.md).  
> **Master Architecture & Rules**: Read [CLAUDE.md](file:///D:/Desktop/Godot/parallax/CLAUDE.md) and [MEMORY/00_MEMORY_INDEX_AND_RULES.md](file:///D:/Desktop/Godot/parallax/MEMORY/00_MEMORY_INDEX_AND_RULES.md).  
> **Persistence Hook**: Use `LeaderboardStore.set_custom_save_value()` / `get_custom_save_value()` for any custom persistence needs.

---

## Execute the IdiotHandOffGuides (01 → 05)

Five self-contained handoff guides live in [`plan/`](plan/). Each one lists its own files, exact replace blocks, and verification commands. Apply them **in order**: 04 depends on 01–03 and 05 depends on 04.

| Order | Guide | Covers |
|---|---|---|
| 1 | [IdiotHandOffGuide_01_HUD_Readability_Lighting.md](plan/IdiotHandOffGuide_01_HUD_Readability_Lighting.md) | Ally cards, bigger skill icons, hidden command log (L toggles), world-text overlay, stylized lighting |
| 2 | [IdiotHandOffGuide_02_Combat_Enemies.md](plan/IdiotHandOffGuide_02_Combat_Enemies.md) | 2.5× enemy health, Warden phase-2 fix, Mirror-only enemies, Ivo's staff and visible bolts |
| 3 | [IdiotHandOffGuide_03_Squad_Voice.md](plan/IdiotHandOffGuide_03_Squad_Voice.md) | Squad voice: no random chatter, spoken line matches subtitle, TTS voice and rate |
| 4 | [IdiotHandOffGuide_04_Gate_Support_Enemies.md](plan/IdiotHandOffGuide_04_Gate_Support_Enemies.md) | Gate stone beside the gate, gate guards, raised cracked support with parkour ledge |
| 5 | [IdiotHandOffGuide_05_Bridges_Bastions_Halls.md](plan/IdiotHandOffGuide_05_Bridges_Bastions_Halls.md) | Winding bridges with two bastions each, 3× Hall of Echoes and clock-tower chamber, `JourneyLayout` |

### Instructions for the executing agent

1. **Preconditions.** Close the Godot editor. It rewrites `main.tscn` and `project.godot` while open. Do not kill `godot-ai.exe`. Confirm `git status` is clean, or that any changes belong to the guide being applied.
2. **Back up the save.** Starting a run clears `%APPDATA%\Godot\app_userdata\PARALLAX\savegame.cfg`. Copy it aside first and restore it after tests.
3. **Per guide, in order:**
   - Read the guide's section A (contract) and B (acceptance map).
   - Check each step's postcondition before the next step. If a replace block does not match exactly once, **stop**, and report the guide, step ID and file.
   - Apply the steps in order, using the code exactly as written. The code uses tab indentation.
   - Run the guide's section E verification commands. Compare results with the stated pass conditions.
   - Report the applied step IDs, changed files, and each check's real result (section F of the guide).
4. **Do not** commit or push a guide's changes until its verification passes or its failures are reported and the user approves.
5. **Documentation.** Each guide's MEMORY step updates `MEMORY/0X_*.md` and `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`. Do this in the same turn as the code change.
6. **Scope.** Apply only what the guides say. Anything else found along the way goes in a follow-up note, not a fix.
7. **Report at the end:** guides applied, guides blocked (with the exact missing input), and the verification output that matters.

Tools: `godot.cmd` is at `E:\game making workshop\Godot\Godot_v4.7.2-stable_win64_console.exe`. Each guide's commands set `$g` to this path.

---

## Claude Prompt 1: Combat Juicing, Hit Feedback, VFX & Sound Polish (Claude Pass A)

```markdown
You are Claude executing **Claude Pass A: Combat Juicing, Hit Feedback, VFX & Gamefeel Polish** for **PARALLAX** in Godot 4.7.2 (`d:\Desktop\Godot\parallax`).

### 1. Context & Architecture
Antigravity Passes 1–9 have completed the entire functional codebase: 3-hit light combo, heavy attack, dodge with i-frames, airborne landing attack, 4 enemy classes (Skeleton, Phantom, Shielded Guard, Warden Boss), 5 stages, pause/options/rebinding, and save system. All tests pass headlessly with zero memory leaks.

Your mission in this pass is to elevate the gamefeel from "functionally solid" to "visceral, punchy, and cinematic".

### 2. Objectives & Deliverables
1. **Combat Hit-Stop & Time-Dilation (QA-A02)**:
   - In `scripts/core/hitbox_3d.gd` and `scripts/player/player_controller.gd`, implement an authentic combat hit-stop when strikes land.
   - When a Heavy Attack, Landing Slam, or Warden Cleave lands on a valid target and `hit_stop_enabled` is true, trigger a brief micro-freeze (`Engine.time_scale = 0.05` for `0.06s` before restoring to `1.0`). Ensure the pause menu and UI remain responsive (`PROCESS_MODE_ALWAYS`).
2. **Camera Shake Trauma System (QA-A03)**:
   - In `scripts/player/player_controller.gd`, implement a non-linear trauma-based camera shake (`trauma` float `0.0 -> 1.0`, trauma squared/cubed for rotational offset on `CameraPivot`).
   - Add shake impulse on: Heavy Attack hit (+0.35 trauma), Landing Slam (+0.60 trauma), Pillar collapse (+0.75 trauma), and taking damage (+0.40 trauma), scaled by `camera_shake_intensity`.
3. **Hit Spark & Slash VFX Trails**:
   - Enhance `assets/shaders/sword_slash_trail.gdshader` with an arc ribbon mesh (`RibbonTrailMesh` or `QuadMesh`) instantiated during Light/Heavy attack swings.
   - Create a lightweight CC0 GPU particle burst (`GPUParticles3D`) for melee impacts: amber sparks for Reality hits/parries, and cobalt glass shards for Mirror hits/rune strikes.
4. **Player Heavy-Damage Reaction (QA-A04)**:
   - In `scripts/player/player_controller.gd`, when incoming damage exceeds 20 HP (heavy enemy strikes or pillar hazards), briefly trigger `State.STAGGER` (`0.25s`) so `CharacterAnimationBridge` plays `"Hit_A"` / `"Hit_B"`, while keeping light hits responsive without locking locomotion.
5. **Telegraph Clarity & Visual Glow**:
   - Add a subtle red emissive eye/weapon flash to enemy wind-ups (`EnemyAI.start_windup()`), and a cobalt glow to The Warden's chest rune during his 1.4s Mirror recovery window.

### 3. Constraints & Rules
- Do NOT break existing signals or public interfaces documented in `MEMORY/02_CORE_SYSTEMS_AND_ARCHITECTURE.md`.
- Ensure Godot exits with 0 leaked instances and 0 errors (`godot.cmd --headless --path . --import --quit`).
- Update `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` and `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` with changes.
```

---

## Claude Prompt 2: Environmental Art Dressing, Realm Aesthetics & Shaders (Claude Pass B)

```markdown
You are Claude executing **Claude Pass B: Environmental Art Dressing, Realm Aesthetics & Shaders** for **PARALLAX** in Godot 4.7.2 (`d:\Desktop\Godot\parallax`).

### 1. Context & Architecture
Antigravity Passes 1–9 have assembled the complete $+Z$ colosseum greybox from Stage 01 (Entry) to Stage 05 (Execution Arena) at `scripts/environment/colosseum_greybox_builder.gd`. All colliders, gates, switches, kill zones, triggers, and anchors are positioned accurately.

Your mission in this pass is to transform the geometric greybox into an atmospheric, high-contrast dark fantasy mirror-colosseum using the imported KayKit dungeon assets and custom shaders.

### 2. Objectives & Deliverables
1. **Dungeon Tile & Prop Replacement**:
   - In `scripts/environment/colosseum_greybox_builder.gd`, decorate or replace flat CSG/box visuals with the imported KayKit models in `assets/models/dungeon/`:
     - Walls: `wall.gltf.glb`, `wall_arched.gltf.glb`, `wall_broken.gltf.glb`, `wall_pillar.gltf.glb`
     - Columns & Pillars: `column.gltf.glb`, `pillar.gltf.glb`, `pillar_decorated.gltf.glb`
     - Props & Scatter: `torch_lit.gltf.glb`, `banner_red.gltf.glb` (Reality), `banner_blue.gltf.glb` (Mirror), `rubble_large.gltf.glb`, `barrel_large.gltf.glb`, `box_large.gltf.glb`
   - Keep all gameplay collision shapes (`StaticBody3D` on Layers 3, 4, 5) exactly aligned with `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md`.
2. **Reality vs Mirror Realm Aesthetic Contrast**:
   - Reality: Warm sun-bleached limestone textures, ember torch lights (`OmniLight3D` with subtle flicker), red banners, and dry dust motes.
   - Mirror: Deep cobalt/slate textures, cold blue crystal sconces, moon banners, emissive runic floor seams, and floating glass fleck particles.
3. **Portal & Transition Shader Enhancement**:
   - Elevate `assets/shaders/realm_shift_pulse.gdshader` and `assets/shaders/mirror_spectral.gdshader`:
     - Add chromatic aberration and radial lens distortion to `realm_shift_pulse.gdshader` that peaks at `t = 0.5` of the 0.20s transition.
     - Add rim Fresnel and spectral alpha noise to `mirror_spectral.gdshader` for Phantom Twins and Mirror stepping stones.
4. **Execution Arena Central Mirror Plane**:
   - Style `Stage05_ExecutionArena/CentralMirrorPlane` (`breakable_prop.gd`) with a monolithic reflective obsidian/glass surface that cleanly shatters into physical cosmetic fragments when The Warden drops below 500 HP.

### 3. Constraints & Rules
- Do NOT alter gameplay anchor positions (`player_spawn`, `entry_gap_center`, `hall_pillar`, `bridge_anchor`, `warden_spawn`) defined in `get_key_anchors()`.
- Obey the Golden Collision Rule: any Mirror-only cosmetic mesh must be parented under a `RealmReactive` node or toggled so it does not clutter Reality.
- Update `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md`, `MEMORY/06_RESOURCES_AND_ASSET_CATALOG.md`, and `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`.
```

---

## Claude Prompt 3: Encounter Polish, Audio Mix & Release Packaging (Claude Pass C)

```markdown
You are Claude executing **Claude Pass C: Encounter Tuning, Audio Mixing, Polish & Release Packaging** for **PARALLAX** in Godot 4.7.2 (`d:\Desktop\Godot\parallax`).

### 1. Context & Architecture
Antigravity Passes 1–9 have established the entire functional and technical game foundation. Claude Passes A & B have juiced combat feel and dressed the environment.

Your mission in this final pass is to balance encounter pacing, perfect the audio landscape, resolve remaining UI/UX polish items, and package the release build.

### 2. Objectives & Deliverables
1. **OS Mouse Capture & Window Focus Integration (QA-D01 & QA-A01)**:
   - In `scripts/core/main_controller.gd`, set `Input.mouse_mode = Input.MOUSE_MODE_CAPTURED` when entering active gameplay, and release to `Input.MOUSE_MODE_VISIBLE` when entering Title Screen, Pause Menu, Options Screen, or Results Screen.
   - In `scripts/core/leaderboard_store.gd`, implement `_notification(what)` to intercept `NOTIFICATION_APPLICATION_FOCUS_OUT` and mute the `Master` bus when `mute_when_unfocused` is enabled, restoring volume on `NOTIFICATION_APPLICATION_FOCUS_IN`.
2. **Audio Mix & Dynamic Ducking**:
   - In `scripts/core/audio_manager.gd`, tune volume balances across `Master`, `Music`, and `SFX` buses so `colosseum_drone_loop.wav` ducks by -4 dB during combat encounters and boss fights.
   - Add low-pass filter tweening to the `Master` bus when the game is paused or when the player is below 25 HP.
3. **Encounter Balance & Boss Pacing**:
   - Fine-tune enemy attack cadences, telegraph timings, and damage values according to `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md` Appendix A:
     - Skeleton Guard: 100 HP, 15 dmg, 0.55s windup.
     - Phantom Twin: 80 HP, 20 dmg, 0.65s windup.
     - Shielded Guard: 250 HP, 20 dmg, 0.65s windup.
     - The Warden: Phase 1 Cleave (20 dmg) / Lunge (25 dmg) with 1.4s recovery; Phase 2 faster chains with 0.85s recovery.
4. **Export Configuration & Packaging**:
   - Review `export_presets.cfg` for Windows Desktop 64-bit export (`Forward+`).
   - Ensure the export binary and `.pck` launch cleanly, load `user://leaderboard.cfg` and `user://savegame.cfg`, and run at a stable 60 FPS at 1920x1080.
   - Validate that the complete run from Title -> Stage 01-05 -> Results -> Leaderboard completes without soft-locks or errors.

### 3. Constraints & Rules
- Do NOT add scope outside GDD Section 6 (no stamina bar, no inventory, no multiplayer, no extra weapons).
- Verify the 12-row GDD QA test matrix passes completely.
- Update `MEMORY/05_UI_SCORING_AND_AUDIO.md` and `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` with final milestone sign-off.
```

---

## 5 Low-Severity Polish Opportunities (From Quality Assessment)

These items were identified during the exhaustive quality audit ([IdiotCheckInQualityAssessment.md](file:///D:/Desktop/Godot/parallax/IdiotCheckInQualityAssessment.md)). They do not break any GDD requirement or block gameplay, but represent immediate high-value polish targets for Claude Passes A & C:

1. **`QA-D01` — OS Mouse Cursor Capture Mode (`Input.mouse_mode`)**:
   - *Issue*: Mouse cursor is not explicitly captured during gameplay. In windowed mode, the OS cursor remains visible while looking around.
   - *Fix*: In `MainController` / `PlayerController`, set `Input.mouse_mode = Input.MOUSE_MODE_CAPTURED` during gameplay, and `Input.MOUSE_MODE_VISIBLE` when in menus (`PauseMenu`, `OptionsScreen`, `TitleScreen`, `ResultsScreen`).
   - *Assigned to*: **Claude Prompt 3 (Pass C)**.

2. **`QA-A01` — Window Focus Audio Mute Notification Hook (`mute_when_unfocused`)**:
   - *Issue*: The `mute_when_unfocused` option is toggled in UI and saved to `user://settings.cfg`, but `AudioServer` focus events are not hooked.
   - *Fix*: In `scripts/core/leaderboard_store.gd`, implement `_notification(what: int)` to mute `Master` audio on `NOTIFICATION_APPLICATION_FOCUS_OUT` when `mute_when_unfocused` is true, and restore on `NOTIFICATION_APPLICATION_FOCUS_IN`.
   - *Assigned to*: **Claude Prompt 3 (Pass C)**.

3. **`QA-A02` — Combat Hit-Stop Micro-Freeze Routine (`hit_stop_enabled`)**:
   - *Issue*: `hit_stop_enabled` is persisted in settings and loaded onto `PlayerController`, but `Engine.time_scale` micro-freeze is not yet triggered on impacts.
   - *Fix*: In `Hitbox3D` / `PlayerController`, add a 0.05x time-scale freeze for ~0.06s on Heavy Attack hits, Landing Slams, and critical damage strikes when `hit_stop_enabled` is true.
   - *Assigned to*: **Claude Prompt 1 (Pass A)**.

4. **`QA-A03` — Camera Shake Trauma Calculation (`camera_shake_intensity`)**:
   - *Issue*: `camera_shake_intensity` is loaded onto `PlayerController` from store, but rotational camera shake math on `CameraPivot` / `Camera3D` is currently absent.
   - *Fix*: In `scripts/player/player_controller.gd`, add a trauma float decaying each frame to apply non-linear rotational noise to `CameraPivot` scaled by `camera_shake_intensity`.
   - *Assigned to*: **Claude Prompt 1 (Pass A)**.

5. **`QA-A04` — Player Heavy-Hit Flinch / Stagger State Transition**:
   - *Issue*: `PlayerController.State.STAGGER` is declared and bound to animations `"Hit_A"`/`"Hit_B"` in `CharacterAnimationBridge`, but `apply_damage()` never transitions into `State.STAGGER`.
   - *Fix*: In `player_controller.gd`, trigger `_set_state(State.STAGGER, 0.25)` only when incoming damage exceeds 20 HP (Heavy hits / Pillar hazard), keeping minor hits responsive without control lock.
   - *Assigned to*: **Claude Prompt 1 (Pass A)**.

---

# Execution & Verification Report (2026-11-18)

Executed **IdiotHandOffGuides `01` → `05`** strictly in sequence per the instructions above, creating one sequential commit per guide on `master`, restoring user save data between/after runs, and leaving all non-guide findings as follow-up notes (Rule 6).

## 1. Environment & Preconditions

- **Godot CLI binary used**: `D:\Desktop\Godot\Godot\Godot_v4.7.2-stable_win64_console.exe` (`4.7.2.stable`; differs from the `E:\game making workshop\Godot\...` path written in the guide templates).
- **Editor / MCP safety**: Closed `Godot_v4.7.2-stable_win64` (PID `4332`) before starting; left `godot-ai.exe` (PIDs `7220`, `27264`) running untouched throughout.
- **Save backup & restore**: Backed up `%APPDATA%\Godot\app_userdata\PARALLAX\savegame.cfg` (`*.cfg`) to `$env:TEMP\parallax_save_bk_master` before running game tests and restored it after verifications. Final SHA-256 hash of both backup and live `%APPDATA%\Godot\app_userdata\PARALLAX\savegame.cfg`: `CA9C8E6B4720557164128B3A62F189F4094D2E8A7398CCE37510676E9B74B959`.
- **Workspace hygiene**: All temporary `Set-Region` scripts and test screenshots were written to `%TEMP%\g5\` and `%TEMP%\pshots\`; no temporary artifacts remain in the repository (`git status --short` clean).

---

## 2. Sequential Commit Ledger (`master`)

| Seq | Commit | Title / Summary | Files Changed |
|---|---|---|---|
| Base | `656242c` | Add IdiotHandOffGuides 01-05 and execution tasks | — |
| 1 | `6440101` | `Apply IdiotHandOffGuide 01: HUD declutter, 2D world labels, and stylized lighting` | 19 (`+269/-85`) |
| 2 | `77cfaa2` | `Apply IdiotHandOffGuide 02: 2.5x enemy HP, Warden phase-2 safeguards, Mirror-only phantoms, and Ivo staff/bolts` | 12 (`+337/-22`) |
| 3 | `b2e7426` | `Apply IdiotHandOffGuide 03: Squad voice coherence, cloud-to-OS TTS fallback, and chatter gating` | 10 (`+256/-51`) |
| 4 | `75f6437` | `Apply IdiotHandOffGuide 04: Gate stone relocation, enlarged gate guards, support parkour ledge, and extra roamers` | 6 (`+131/-21`) |
| 5 | `2565868` | `Apply IdiotHandOffGuide 05: Winding bridges with bastions, 3x Hall of Echoes & clock-tower chamber, and JourneyLayout` | 17 (`+905/-374`) |

---

## 3. Guide-by-Guide Applied Changes & Verification Output

### Guide 01 — `IdiotHandOffGuide_01_HUD_Readability_Lighting.md` (`6440101`)
- **Steps applied**: `G1-1` through `G1-15`.
- **Files modified/created** (`19`):
  - Modified: `MEMORY/05_UI_SCORING_AND_AUDIO.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`, `addons/parallax_squad_ai/squad_ai_config.gd`, `assets/shaders/journey_sky.gdshader`, `assets/shaders/realm_pbr.gdshader`, `scripts/allies/squad_ally.gd`, `scripts/allies/world_intel.gd`, `scripts/core/leaderboard_store.gd`, `scripts/enemies/enemy_ai.gd`, `scripts/environment/colosseum_greybox_builder.gd`, `scripts/environment/grand_journey_builder.gd`, `scripts/ui/hud_controller.gd`, `scripts/ui/objective_tracker.gd`, `scripts/ui/squad_comms_hud.gd`
  - Created / `.uid`s: `scripts/ui/world_label_overlay.gd`, `scripts/ui/world_label_overlay.gd.uid`, `tests/restart_flow_test.gd.uid`, `tests/visual_check_shots.gd`, `tests/visual_check_shots.gd.uid`
- **Verification**:
  - `G1-V1`: `--headless --path . --import --quit` → exit `0`; `scripts/ui/world_label_overlay.gd.uid` created (`True`).
  - `G1-V2`: `--check-only` on all `11` Guide 01 scripts → all `ok`.
  - `G1-V3` (`tests/boot_smoke.gd`): `[boot_smoke] frames=300 allies=3 enemies=19`, `[boot_smoke] OK`.
  - `G1-V6` (`WorldLabelOverlay.adopt`): `ok count=6`.
  - `G1-V7`:
    - `tests/squad_ai_unit_test.gd`: `[unit] SUMMARY 74 checks, 0 failed`.
    - `tests/squad_ai_windowed_test.gd`: Run 1 failed `auto_rally_rushes 1 helpers within 5 m` (`53 checks, 1 failed`); Run 2 (immediate rerun) passed `53 checks, 0 failed`.
  - `G1-V8` (`tests/visual_check_shots.gd`): `40_spawn_hud.png` & `42_log_toggled_on.png` visually verified; `41_prop_hint.png` did not show `"MIRROR SWITCH / use in the Mirror (E)"` due to pre-existing deferred level loading in `aeff5fa` (see Follow-Up Note 1).
  - `G1-V9`: Save restored.

### Guide 02 — `IdiotHandOffGuide_02_Combat_Enemies.md` (`77cfaa2`)
- **Steps applied**: `G2-1` through `G2-11`.
- **Files modified/created** (`12`):
  - Modified: `MEMORY/03_COMBAT_PLAYER_AND_ENEMIES.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`, `data/allies/03_ivo.tres`, `scripts/allies/squad_ally.gd`, `scripts/core/hitbox_3d.gd`, `scripts/enemies/enemy_base.gd`, `scripts/enemies/phantom_twin.gd`, `scripts/enemies/warden_boss.gd`, `scripts/environment/pit_kill_zone.gd`, `scripts/player/player_controller.gd`
  - Created: `tests/combat_rules_test.gd`, `tests/combat_rules_test.gd.uid`
- **Verification**:
  - `G2-V1` / `G2-V2`: `--import --quit` exit `0`; `--check-only` on all `7` Guide 02 scripts → all `ok`.
  - `G2-V3` (`tests/boot_smoke.gd`): `enemies=19`, `[boot_smoke] OK`.
  - `G2-V4` (`tests/combat_rules_test.gd`): `[combat] SUMMARY 10 checks, 0 failed` (guide prose mentions 11, script contains 10 `_check` calls).
  - `G2-V5`:
    - `tests/squad_ai_unit_test.gd`: `74 checks, 0 failed`.
    - `tests/restart_flow_test.gd`: `enemies=19 killed-enemy-restored=true => PASS`.
    - `tests/squad_ai_windowed_test.gd`: `53 checks, 1 failed` (`auto_rally_rushes 1 helpers within 5 m`).
    - `tests/feel_and_movement_test.gd`: `13 checks, 1 failed` (`f_in_window_executes [["fin_execution", 0, false, ""]] dead=false hp=60`).
  - `G2-V6`: Visually verified `14_skill_fight.png` and `15_chains.png` (and later `41_prop_hint.png`): Ivo holds upright crystal staff (no sword) and fires violet bolts.
  - `G2-V7`: Save restored.

### Guide 03 — `IdiotHandOffGuide_03_Squad_Voice.md` (`b2e7426`)
- **Steps applied**: `G3-1` through `G3-7`.
- **Files modified/created** (`10`):
  - Modified: `MEMORY/05_UI_SCORING_AND_AUDIO.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`, `addons/parallax_squad_ai/openai_client.gd`, `addons/parallax_squad_ai/squad_ai_config.gd`, `addons/parallax_squad_ai/squad_comms.gd`, `addons/parallax_squad_ai/tts_player.gd`, `project.godot`, `scripts/allies/ally_squad_manager.gd`
  - Created: `tests/voice_pipeline_test.gd`, `tests/voice_pipeline_test.gd.uid`
- **Verification**:
  - `G3-V1`: `--import --quit` exit `0`; `--check-only` on all `5` Guide 03 scripts → all `ok`.
  - `G3-V2` pattern counts: `tts_count=1`, `brisk_count=2`, `subtitle_emit_count=5`.
  - `G3-V3`: `tests/boot_smoke.gd` OK; `tests/squad_ai_unit_test.gd` → `74 checks, 0 failed`.
  - `G3-V4` (`tests/voice_pipeline_test.gd`): `[voice] SUMMARY 6 checks, 0 failed`.
  - `G3-V5` (`tests/squad_ai_windowed_test.gd`): `53 checks, 3 failed`:
    - `strategy_divide_distinct_targets ["E19", "E18"]`
    - `bait_sneak_parsed Brannoc:follow, Sera:kite skeleton, Ivo:follow | CMD Sera kite skeleton Sera assigned / CMD Brannoc flank rear skeleton Brannoc assigned`
    - `bait_holds_enemy enemy on Sera 9/30 samples; Sera kite skeleton (sustain)`
    - Save restored.
  - `G3-V6` (manual listening): Not run.

### Guide 04 — `IdiotHandOffGuide_04_Gate_Support_Enemies.md` (`75f6437`)
- **Steps applied**: `G4-1` through `G4-6`.
- **Files modified/created** (`6`):
  - Modified: `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`, `scripts/environment/grand_journey_builder.gd`, `scripts/ui/objective_tracker.gd`
  - Created: `tests/level_props_test.gd`, `tests/level_props_test.gd.uid`
- **Verification**:
  - `G4-V1`: `--import --quit` exit `0`; `--check-only` on both scripts → `ok`.
  - `G4-V2` (`tests/boot_smoke.gd`): `[boot_smoke] frames=300 allies=3 enemies=26`, `[boot_smoke] OK`.
  - `G4-V3` (`tests/level_props_test.gd`): `[props] SUMMARY 13 checks, 0 failed`.
  - `G4-V4` (`tests/visual_check_shots.gd`): `41_prop_hint.png` visually inspected (`EntryMirrorSwitch` at `14m` left of gate, enlarged Shielded Guards `615/625`, `GateBrute` `554/650`, `GateHexcaster`, `ForecourtPhantom`, Ivo staff + bolts). Note: `visual_check_shots.gd` hung on `quit(0)` after saving PNGs due to OS TTS triggered by gate guards (process killed; see Follow-Up Note 3).
  - `G4-V5`:
    - `tests/restart_flow_test.gd`: `enemies=26`, `PASS`.
    - `tests/squad_ai_windowed_test.gd`: `53 checks, 8 failed` (`allies_take_enemy_melee`, `strategy_divide_distinct_targets`, `rearguard_behind`, `auto_rally_rushes`, `taunted_enemy_chases_past_leash`, `bait_sneak_parsed`, `bait_holds_enemy`, `sneak_attack_from_behind` — expected interference from new ENTRY gate guards at `z -2.6/-8.5`).
    - Save restored.

### Guide 05 — `IdiotHandOffGuide_05_Bridges_Bastions_Halls.md` (`2565868`)
- **Steps applied**: `G5-0` through `G5-18`.
- **Files modified/created** (`17`):
  - Modified: `MEMORY/02_CORE_SYSTEMS_AND_ARCHITECTURE.md`, `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`, `scenes/main/main.tscn`, `scripts/ambient/ambient_life_layout.gd`, `scripts/core/audio_manager.gd`, `scripts/core/leaderboard_store.gd`, `scripts/environment/grand_journey_builder.gd`, `scripts/environment/journey_terrain.gd`, `scripts/environment/weather_director.gd`, `scripts/ui/objective_tracker.gd`, `tests/feel_and_movement_test.gd`, `tests/squad_ai_windowed_test.gd`
  - Created: `scripts/environment/journey_layout.gd`, `scripts/environment/journey_layout.gd.uid`, `tests/layout_rework_test.gd`, `tests/layout_rework_test.gd.uid`
- **Postconditions verified**:
  - `grand_journey_builder.gd`: `Prologue_CausewayA=0`, `OverlookSkeleton_A=0`, `OverlookHexcaster=0`, `Prologue_StartTerrace=1`, `GateWarden_W=1`, `JourneyLayout.OFF_S3=7`, `Processional_Ramp=0`, `StairPhantom=0`, `Rail_Esp_SW=0`, `EsplanadeHexcaster=1`, `JourneyLayout.OFF_S5=8`.
  - `journey_terrain.gd`: `const Z_MAX: float = 370.0` (`True`), `z - 178.0` (`True`).
  - `ambient_life_layout.gd`: `JourneyLayout.to_world(pos)` count `5`.
  - `weather_director.gd`: `JourneyLayout.story_z` count `1`; `audio_manager.gd`: count `3`.
  - `objective_tracker.gd`: `JourneyLayout.` count `12`.
  - `leaderboard_store.gd`: `"layout_version"` count `3`, `JourneyLayout.VERSION` count `3` (`2` code uses + `1` comment on `"layout_version": 1`), `"SkeletonGuard_1"` count `0`.
  - `tests/squad_ai_windowed_test.gd` + `tests/feel_and_movement_test.gd`: old `-59)`, `-58)`, `-40.0)` references = `0`.
  - `scenes/main/main.tscn`: `1 insertion, 1 deletion` (`Player` z `-56` → `-136`).
- **Verification**:
  - `G5-V1`:
    - `--headless --path . --import --quit` exit `0`; `tests/layout_rework_test.gd.uid=True`.
    - `--check-only` `ok` on all `9` scripts:
      - `ok scripts/environment/journey_layout.gd`
      - `ok scripts/environment/grand_journey_builder.gd`
      - `ok scripts/environment/journey_terrain.gd`
      - `ok scripts/ambient/ambient_life_layout.gd`
      - `ok scripts/environment/weather_director.gd`
      - `ok scripts/core/audio_manager.gd`
      - `ok scripts/ui/objective_tracker.gd`
      - `ok scripts/core/leaderboard_store.gd`
      - `ok tests/layout_rework_test.gd`
  - `G5-V2` (`tests/boot_smoke.gd`):
    - `[boot_smoke] frames=300 allies=3 enemies=57` (`26` after Guide 04 `+ 24` bastion garrisons `+ 5` hall encounter `+ 3` hall roamers `+ 5` chamber `- 6` removed connector roamers)
    - `[boot_smoke] OK`
  - `G5-V3` (`tests/layout_rework_test.gd`):
    - `[layout] SUMMARY 54 checks, 0 failed` (all 54 checks passed):
      - `R1_PilgrimCauseway`: `179 m vs old 40 m (x4.5)`, bastions `34.0 m` off straight line, `2` bastions, `6` enemies, `0 of 127` centerline probes without floor, `0` leg sides without rail, rings `0` open directions.
      - `R2_SunlitBridges`: `81 m vs old 16 m (x5.1)`, bastions `16.0 m` off straight line, `2` bastions, `6` enemies, `0 of 61` floor holes, `0` missing rails, rings `0` open directions.
      - `R3_WindsweptRampart`: `81 m vs old 16 m (x5.1)`, bastions `16.0 m` off straight line, `2` bastions, `6` enemies, `0 of 61` floor holes, `0` missing rails, rings `0` open directions.
      - `R5_Processional`: `81 m vs old 16 m (x5.1)`, bastions `16.0 m` off straight line, `2` bastions, `6` enemies, `0 of 61` floor holes, `0` missing rails, rings `0` open directions.
      - `hall_3x (60.0, 0.5, 60.0)`, `hall_more_enemies 9 encounter enemies (was 4)`, `hall_encounter_count_matches`, `hall_roamers`, `chamber_3x (36.0, 0.5, 36.0)`, `chamber_more_enemies 8 (was 3)`, `puzzle_centred`, `gallery_offset`, `arena_offset`, `gallery_checkpoint_world`, `spawn_on_terrace (0.0, -0.000161, -136.0)`.
    - Save restored.
  - `G5-V4` regressions:
    - `tests/restart_flow_test.gd`:
      - `[restart_test] run 1 ready: enemies=57 killed=true`
      - `[restart_test] run 2 ready: enemies=57 (expected 57) killed-enemy-restored=true => PASS`
    - `tests/squad_ai_windowed_test.gd`:
      - `[squad_test] SUMMARY 53 checks, 4 failed`
      - Failed cases:
        1. `FAIL allies_take_enemy_melee` (with forecourt guards active around `z -2.6/-8.5` since Guide 04)
        2. `FAIL ranged_keeps_distance Sera follow at 2.1 m from target`
        3. `FAIL auto_rally_rushes 1 helpers within 5 m`
        4. `FAIL taunted_enemy_chases_past_leash 19.0 m from taunter, 9.8 m from home` (Guide 05 documented known risk: taunted enemy snagging on forecourt join rail under `22 m` threshold)
    - `tests/feel_and_movement_test.gd`:
      - `[feel] SUMMARY 13 checks, 4 failed`
      - Failed cases:
        1. `FAIL chain_reaches_5_distinct_moves ["light_1", "light_1", "light_1", "light_1", "light_1"]`
        2. `FAIL rhythm_taps_flow 1 of 4 follow-ups in FLOW`
        3. `FAIL pause_branch_rising_arc [["light_1", 1, false, ""]]`
        4. `FAIL f_in_window_executes [["fin_execution", 0, false, ""]] dead=false hp=139`
    - Save restored (`save_restored=True`).
  - `G5-V5` (manual walkthrough): Not run.

---

## 4. Follow-Up Engineering Notes (Out-of-Scope Issues Left Untouched per Rule 6)

1. **`ObjectiveTracker._refresh()` vs deferred level creation (`aeff5fa`)**:
   - On startup, `ObjectiveTracker._refresh()` sets `_labels_done = true` while `LevelRoot` is still empty on the title screen, because `aeff5fa` deferred level creation behind `MainController.level_ready`. Consequently, `41_prop_hint.png` in `tests/visual_check_shots.gd` did not show `"MIRROR SWITCH / use in the Mirror (E)"`. Re-running or gating `_label_props()` on `MainController.level_ready` requires a small fix outside Guides `01–05`.
2. **Forecourt test interference (`squad_ai_windowed_test.gd` & `feel_and_movement_test.gd`)**:
   - `feel_and_movement_test.gd` positions the player at `Vector3(0, 0, -14)` (`Gate_Forecourt`), where Guide 04's enlarged gate guards (`z -2.6/-8.5`) and `ForecourtPhantom` engage during chain/rhythm timing and where `victims` can match an ~`150 HP` forecourt enemy (`hp=139` on `f_in_window_executes`, up from `hp=60` prior to Guide 02's 2.5× HP scaling).
   - `taunted_enemy_chases_past_leash` failed at `19.0 m from taunter, 9.8 m from home`, matching the exact known risk documented in `IdiotHandOffGuide_05` (`G5-V4`) where the forecourt join rail can snag the taunted enemy under `22 m`.
3. **`tests/visual_check_shots.gd` OS TTS exit hang**:
   - `visual_check_shots.gd` does not call `SquadAIConfig.force_offline()`. After Guide 04 added forecourt guards near `z = -8`, active squad voice lines triggered Windows OS TTS (`DisplayServer.tts_speak`) and caused `quit(0)` to hang after writing the PNG screenshots.
4. **Remaining manual checks**:
   - `G3-V6` (live audio listening for OS/cloud TTS voice quality) and `G5-V5` (interactive walkthrough & frame-rate inspection on bridges/halls/clock-tower chamber) were not run in headless automation and should be checked interactively.
