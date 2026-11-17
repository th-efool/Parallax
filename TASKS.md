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