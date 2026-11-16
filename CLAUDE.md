# CLAUDE.md — PARALLAX Engineering & Agent Guide

> **Project**: **PARALLAX** — A Mirror-Realm Combat Game (Godot `4.7.2`, Forward+, Windows 64-bit)
> **Root Directory**: `D:\Desktop\Godot\parallax`
> **Master Knowledge Base**: Always start at `MEMORY/00_MEMORY_INDEX_AND_RULES.md`.

---

## 1. Memory First & Anti-Sprawl Discipline

Before investigating code, editing scenes, or proposing changes:
1. Read `MEMORY/00_MEMORY_INDEX_AND_RULES.md` to identify which domain file (`01` through `07`) owns your task.
2. Read **only** the relevant `MEMORY/0X_*.md` file (and `MEMORY/reference_images/` if doing visuals/UI) rather than guessing design numbers or hunting across files.
3. **NEVER create new `.md` files** for individual scripts, bugs, refactors, rooms, or minor mechanics. We strictly **club** related knowledge into the 7 domain files:
   - `01_GDD_OVERVIEW_AND_SCOPE.md` — Pillars, narrative, 7-day plan, QA matrix, scope lock / cut list
   - `02_CORE_SYSTEMS_AND_ARCHITECTURE.md` — Node contracts, `RealmManager`, safety queries, `EncounterDirector`, physics layers 1–7, checkpoints
   - `03_COMBAT_PLAYER_AND_ENEMIES.md` — Controls, camera specs, attacks, combo, breakables, Skeleton/Phantom/Shielded Guard/Warden AI & Appendix A tuning
   - `04_LEVEL_DESIGN_AND_ROOMS.md` — Master `(X, Y, Z)` blockout coordinates, Stages 01–05 room logic, reference image mapping
   - `05_UI_SCORING_AND_AUDIO.md` — Score awards, S/A/B/C ranks, `user://leaderboard.cfg`, single `HUD.tscn` layout, menus, palette, audio cues
   - `06_RESOURCES_AND_ASSET_CATALOG.md` — CC0 3D asset packs, Mixamo/Quaternius retargeting workflow, Godot 4 `.gdshader` recipes, SFX packs, Asset Register
   - `07_DEV_STATUS_AND_CHANGELOG.md` — Milestone checkboxes and brief dated changelog
4. **Update In-Place**: If you change a script contract, physics layer, room coordinate, damage value, or import an external asset, **update the matching section in `MEMORY/0X_*.md` in the same turn** and append a 1-line summary to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`.

---

## 2. Godot 4.7.2 & `godot-ai` MCP Rules

### 2.1 Live Editor MCP (`godot-ai` v4.4.1)
- Addon is installed & enabled at `addons/godot_ai` (configured for HTTP port `8000`, WebSocket port `9500`).
- **When the Godot Editor is open on `D:\Desktop\Godot\parallax` and `godot-ai` MCP tools are loaded**: prefer using the MCP tools (`editor_state`, `scene_get_hierarchy`, `scene_open`, `node_create`, `node_set_property`, `project_run`, `logs_read`, `test_run`, `editor_screenshot`) to inspect live scenes, wire nodes, run the game, and read debugger/console errors cleanly.
- Ensure only ONE Godot editor instance holds port `8000`/`9500` at a time.

### 2.2 Headless CLI Verification & Asset Import
- **Godot CLI binary**: `C:/Users/agrim/.local/bin/godot.cmd` (or `D:/Desktop/Godot/Godot/Godot_v4.7.2-stable_win64_console.exe`).
- **Asset Import Mandatory Rule**: After adding any new `.glb`, `.gltf`, `.png`, `.jpg`, `.wav`, or `.ogg` into `assets/`, ALWAYS run:
  ```powershell
  & "C:\Users\agrim\.local\bin\godot.cmd" --headless --path "D:\Desktop\Godot\parallax" --import --quit
  ```
  before loading or instantiating those resources in scripts/tests.
- **Script Syntax Verification**: Verify every new or modified GDScript file via:
  ```powershell
  & "C:\Users\agrim\.local\bin\godot.cmd" --headless --path "D:\Desktop\Godot\parallax" --check-only -s res://scripts/<path>.gd
  ```

---

## 3. Critical GDScript & Project Pitfalls (Lessons Learned)

1. **Standalone Script Checking vs `class_name`**:
   - Godot `--check-only -s <script.gd>` checks scripts in isolation where global `class_name` symbols from other files may not resolve unless explicitly preloaded.
   - Always preload sibling script dependencies (`const RealmReactiveScript := preload("res://scripts/core/realm_reactive.gd")`) or type exported node references cleanly (`CharacterBody3D`, `Node`, `CanvasLayer`) and give local variables explicit types (`var speed: float = 4.5`).
2. **Physics Layer Discipline**:
   - Use the named 3D physics layers in `project.godot` (`Player=1`, `Enemy=2`, `World_Shared=3`, `World_Reality=4`, `World_Mirror=5`, `Interactable=6`, `Hitbox=7`, `Player_Blocker=8` — invisible railing blockers the camera ignores). Never scatter raw magic bitmasks without referencing helper constants in `RealmManager`.
   - Inactive-realm actors/platforms MUST disable `CollisionShape3D` and pause AI/visibility—hiding meshes alone causes phantom hits.
3. **3D Coordinate & Forward Orientation Trap**:
   - The GDD room sequence progresses **North along `+Z`** (`(0,0,-3)` up to `(0,0,102)`). Remember Godot's `look_at()` points `-Z` forward.
   - Furthermore, many third-party GLTF character/prop models (Kenney, Quaternius, Mixamo) export facing `+Z`. **Always inspect imported GLTF local wheel/bone/face orientation first** and rotate the visual child `ModelRoot` `180°` (`PI`) on Y if it faces opposite your movement basis!
4. **One Hit Per Swing**:
   - Melee sword `Area3D` hitboxes and `CrackedPillar` collapse `2.5 m` zones must track hit targets per activation (`hit_targets`) and guard breakables with an idempotent boolean so damage/score never fire multiple ticks per swing.
5. **Single Shared `HUD.tscn`**:
   - Never build per-room HUDs. Bind one `HUD.tscn` instance via signals from `Player`, `RealmManager`, `EncounterDirector`, and `RunState`.
6. **Strict Scope Lock**:
   - Respect `MEMORY/01_GDD_OVERVIEW_AND_SCOPE.md` Section 6 (no extra weapons, no stamina, no inventory, no online services, no systemic destruction).

---

## 4. Sub-Agent Orchestration

A complete multi-agent build pipeline is defined in `workflows/parallax-build.yaml` matching the `sub-agent-orchestrator` YAML schema (`sequential`, `parallel`, and QA `loop` stages aligned to Days 1–7). Read `workflows/parallax-build.yaml` and invoke `/sub-agent-orchestrator` when ready to execute build waves.
