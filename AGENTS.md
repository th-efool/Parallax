# AGENTS.md — Multi-Agent Operating Manual for PARALLAX

> Applies to all coding agents, sub-agents, and orchestrator workers operating in `D:\Desktop\Godot\parallax`.

---

## 1. Mandatory Pre-Flight & Memory Clubbing Rules

1. **Read Before Writing**: Read `MEMORY/00_MEMORY_INDEX_AND_RULES.md` first, then read the specific `MEMORY/0X_*.md` file covering the subsystem you own.
2. **Zero File Sprawl**: NEVER create new `.md` documentation files in the repo root or `MEMORY/` (no `combat_notes.md`, `pillar_fix.md`, `todo_v2.md`, etc.). All knowledge MUST stay encapsulated inside the existing `MEMORY/01`–`07` files.
3. **Keep Memory Synchronized**: Every agent modifying scenes, scripts, physics layers, room transforms, or tuning constants must update the relevant section of `MEMORY/02`–`06` and append one dated line to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` before finishing its turn.
4. **Git Hygiene**: Never commit `.godot/` caches or raw temporary download archives. Verify downloaded assets are registered in `MEMORY/06_RESOURCES_AND_ASSET_CATALOG.md` (with license & source).

---

## 2. Role Boundaries (When Running Under `/sub-agent-orchestrator`)

When working inside `workflows/parallax-build.yaml` or delegated sub-agent tasks:

| Agent Role | Owned Directories | Read-Only Memory Refs | Required Verification |
| :--- | :--- | :--- | :--- |
| **Core Architect** | `scripts/core/`, `scenes/main/` | `02_CORE_SYSTEMS_AND_ARCHITECTURE.md` | `--check-only` on all core scripts + headless `Q` safety-shift test |
| **Combat & AI Engineer** | `scripts/player/`, `scripts/enemies/`, `scenes/player/`, `scenes/enemies/`, `scripts/environment/breakable_prop.gd`, `scenes/props/` | `03_COMBAT_PLAYER_AND_ENEMIES.md`, `06_RESOURCES_AND_ASSET_CATALOG.md` | `--check-only` + headless damage/stagger/pillar/Warden Phase 1->2 checks |
| **Level Builder** | `scenes/environment/`, `scripts/environment/` | `04_LEVEL_DESIGN_AND_ROOMS.md`, `reference_images/` | Headless collision continuity & bridge-repair no-soft-lock verification |
| **UI, Audio & VFX Artist** | `scenes/ui/`, `scripts/ui/`, `assets/shaders/`, `assets/audio/` | `05_UI_SCORING_AND_AUDIO.md`, `06_RESOURCES_AND_ASSET_CATALOG.md`, `reference_images/` | `--check-only` + `user://leaderboard.cfg` persistence test + HUD layout screenshot |
| **QA Validator** | Read-only across codebase + test scripts (cleanup temp scripts after) | `01_GDD_OVERVIEW_AND_SCOPE.md` Section 5 (Test Matrix) | Full end-to-end headless & windowed test matrix verification |

---

## 3. Technical Checklist for All Godot 4 Agents

- **Engine**: `C:/Users/agrim/.local/bin/godot.cmd` (`4.7.2.stable`, Forward+).
- **Godot AI MCP**: Addon enabled in `project.godot` (HTTP `8000`, WS `9500`). Use MCP live editor tools when connected; fall back to Godot CLI (`--headless --check-only -s ...` and `--import --quit`) otherwise.
- **Explicit Preloads**: Use `const ScriptRef := preload("res://...")` in GDScript so `--check-only -s` succeeds independently of editor class-cache state.
- **No Unbounded Loops or Dynamic Mirror Viewports**: Hitboxes track per-swing hit arrays; breakables use authored `AnimationPlayer` falls; visual effects use shaders in `assets/shaders/` to hold 60 FPS @ 1080p.
- **Third-Person Camera Lock**: Stage 01 Entry Vestibule and all subsequent rooms use the third-person over-right-shoulder follow camera (`3.5–4.5 m`, `60–70°` FOV)—never first-person.
- **Clean Cleanup**: Delete any temporary `.gd` scratch verification scripts before committing.
- **Hard Command & Test Timeouts (No Infinite Hangs)**:
  - Never run bare Godot tests/scripts without a hard wall-clock timeout.
  - Wrap every Godot CLI invocation in a bounded PowerShell timeout (`Start-Process` + `WaitForExit($timeoutSec * 1000)` + `taskkill /T /F /PID $p.Id` on expiry, returning exit code `124` and printing captured stdout/stderr):
    - `--check-only` parse checks: **30 s** per script
    - Headless unit/regression tests: **90 s** max
    - Full-level / windowed tests (`feel_and_movement_test.gd`, `squad_ai_windowed_test.gd`, `visual_check_shots.gd`): **180 s** max
  - If a `run_command` task backgrounds asynchronously, pair it with a `schedule` watchdog timer (`DurationSeconds` = budget + 15 s, `TimerCondition` = that task's `TaskId` so it auto-cancels on normal finish); if the timer fires first, immediately kill the task via `manage_task(Action="kill")`, inspect its log tail, diagnose the hang cause (e.g., missing `quit()`, infinite loop, blocked TTS/dialog), and rethink before retrying.
  - Every new test script in `tests/` must include an internal `SceneTree` watchdog (`create_timer(120.0, true, false, true).timeout.connect(func() -> void: print("[test] WATCHDOG TIMEOUT"); quit(2))`).
