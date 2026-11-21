# 10. Testing and workflow

This page explains how tests are written and run, lists every file in `tests/`, and sets out the project's documentation and commit conventions.

## 1. How tests work

There is no test framework. Each test is a plain GDScript file that `extends SceneTree` and is run as the main loop with the Godot binary:

```
godot --headless --path . -s res://tests/<name>.gd
```

A typical test does the following:
1. In `_init()` (or `_initialize()`) it loads `res://scenes/main/main.tscn`, adds it to `root`, and usually calls `start_run_now()` or presses the title screen's start button.
2. It waits for the level to finish building by polling `main.level_ready` (the level is generated at run time under a loading screen, so this can take many seconds).
3. It drives the game (spawns, damages, issues squad orders through `SquadComms` or `AllySquadManager`, steps frames) and records PASS/FAIL lines with a `_check()` helper.
4. It calls `quit(code)`: `0` for success, `1` for any failure, `2` for a watchdog timeout.

Conventions used by the existing suites:
- Output lines are prefixed with the test tag (for example `[voice] PASS ...`). Search for `FAIL` and check the exit code.
- A watchdog timer quits with code 2 so a hung level build cannot stall CI or a terminal. New tests must include one (for example `create_timer(120.0, true, false, true).timeout.connect(...)` that prints a timeout line and calls `quit(2)`).
- Tests that touch AI or voice call `SquadAIConfig.force_offline()` first, which also silences TTS. This keeps tests deterministic and free of network calls, regardless of any `.env` on the machine.
- Regression suites are named for the handoff guide they verify (`combat_bugfix_regression_test.gd` for guide 01, and so on) and tag each check with an ID such as `CMB-01`, `ENM-07`, `ALY-12`, `SRS-03` or `MRK-05`, matching the guides in `plan/`.

### 1.1 Headless versus windowed

| Mode | How to run | Use for |
| :-- | :-- | :-- |
| Headless | `godot --headless --path . -s res://tests/x.gd` | Logic, AI decisions, level geometry, flows. No rendering, no audio output, no microphone, no OS TTS |
| Windowed | `godot --path . -s res://tests/x.gd -- --shots=<absolute dir>` | Anything visual or timing dependent: movement feel, camera, screenshots, formation spacing |

Windowed tests accept user arguments after `--`. The `--shots=<dir>` argument tells screenshot scripts where to write images. Windowed tests need a GPU and a display, are slower, and must be given a longer time budget. Features that are disabled in headless mode (microphone capture, system TTS, rendering-dependent camera checks) cannot be tested there.

### 1.2 Import before check

Godot caches imported assets and the global class list in `.godot/` (git-ignored). On a fresh clone, after pulling new assets, or after adding a `class_name`, run the import once:

```
godot --headless --path . --import --quit
```

Run this before `--check-only` or before tests that load models, images or audio. Without it, loads of new assets fail and scripts that refer to newly added `class_name` types may not resolve.

### 1.3 The class_name resolution pitfall

`--check-only -s <script>` parses a script in isolation. Global `class_name` symbols from other files (`SquadAlly`, `EnemyAI`, `SquadAIConfig`, `RealmManager`, and so on) may not resolve in that mode, producing misleading parse errors for code that works in the editor and in-game. Two practices avoid this and are used throughout the codebase:
- Preload sibling dependencies explicitly: `const SquadCommandScript := preload("res://scripts/allies/squad_command.gd")`, and use the constant instead of the global name where a check must pass standalone.
- Give variables explicit types, and type exported node references with engine classes (`CharacterBody3D`, `Node`) rather than project classes.

If `--check-only` reports "Identifier not declared" for a project class after you ran `--import`, check whether the script is only failing in isolation by running the whole game or a test that loads it. Real errors show up there as well.

### 1.4 Running a test safely

Always put a wall-clock limit on Godot CLI runs (the project rules in `AGENTS.md` require it): about 30 s for `--check-only`, 90 s for headless tests, 180 s for windowed or full-level tests. In PowerShell, start the process, wait with a timeout, kill the process tree on expiry, and report exit code 124. Example:

```powershell
$godot = "<path to Godot 4.7.2 console binary>"
$p = Start-Process -FilePath $godot -ArgumentList '--headless','--path','.','-s','res://tests/combat_rules_test.gd' -NoNewWindow -PassThru
if (-not $p.WaitForExit(90000)) { taskkill /T /F /PID $p.Id | Out-Null; "TIMEOUT"; exit 124 }
"exit code: $($p.ExitCode)"
```

Use the console build of Godot (`..._console.exe`) so output reaches the terminal.

### 1.5 Saves: back up first

Starting a run, including from a test, clears the saved run in `user://savegame.cfg`. The chain is `RunState.start_new_run()` in [score_manager.gd](../scripts/core/score_manager.gd), which calls `LeaderboardStore.clear_saved_run(true)` in [leaderboard_store.gd](../scripts/core/leaderboard_store.gd) (it preserves the profile and custom settings, but removes the run checkpoint). Tests that boot `main.tscn` and start a run will therefore erase a developer's Continue state.

Before running such tests, copy `savegame.cfg` out of the project's `user://` folder (on Windows, `%APPDATA%\Godot\app_userdata\<project name>\`), and restore it afterward. `user://squad_ai.cfg` and `user://leaderboard.cfg` live in the same folder.

## 2. Test inventory

All files are in [tests/](../tests/). "Headless" means it is designed to run with `--headless`.

| File | Mode | Purpose |
| :-- | :-- | :-- |
| [boot_smoke.gd](../tests/boot_smoke.gd) | headless | Loads the game, starts a run, simulates about 300 frames, prints ally and enemy counts, and reports script errors; quick "does it boot" check |
| [charged_heavy_test.gd](../tests/charged_heavy_test.gd) | headless | Hold-to-charge heavy attack and live-stick aiming between combo swings |
| [combat_bugfix_regression_test.gd](../tests/combat_bugfix_regression_test.gd) | headless | Regression suite for guide 01 (checks `CMB-01` to `CMB-19`) |
| [combat_rules_test.gd](../tests/combat_rules_test.gd) | headless | Enemy health scaling, Warden immunity, hit cap, fall safety and phase threshold, Mirror-only Phantom rules |
| [enemies_ai_bugfix_regression_test.gd](../tests/enemies_ai_bugfix_regression_test.gd) | headless | Regression suite for guide 02 (`ENM-01` to `ENM-26`): enemy AI fixes |
| [enemy_look_shots.gd](../tests/enemy_look_shots.gd) | windowed | Screenshots of enemy looks and the Warden arena, including a forced summon; reports flat material overrides |
| [enemy_marking_free_leash_regression_test.gd](../tests/enemy_marking_free_leash_regression_test.gd) | headless | Regression suite for enemy marking, 18 m region detection and free-leash ally orders (`MRK-01` to `MRK-12`) |
| [feel_and_movement_test.gd](../tests/feel_and_movement_test.gd) | windowed | Spin-in-place bug under frame hitches, attack chain rhythm, and ally spacing from each other, the player and walls |
| [friends_ai_bugfix_regression_test.gd](../tests/friends_ai_bugfix_regression_test.gd) | headless | Regression suite for friends and squad AI (guide 03, `ALY-01` to `ALY-24`); uses explicit preloads |
| [layout_rework_test.gd](../tests/layout_rework_test.gd) | headless | `JourneyLayout` math, bridge length and bends, bastions, garrisons, rails, the enlarged hall and chamber, stage offsets |
| [level_props_test.gd](../tests/level_props_test.gd) | headless | Checks prop placements in the built level (gate guards, columns, gallery deck) |
| [restart_flow_test.gd](../tests/restart_flow_test.gd) | headless | Start, kill an enemy, replay from results; verifies the reloaded world is complete with no leftover state |
| [sanity_regression_test.gd](../tests/sanity_regression_test.gd) | headless | Requirement checks (`REQ-xx`) run against a booted level, starting with objective label refresh |
| [spawning_save_bugfix_regression_test.gd](../tests/spawning_save_bugfix_regression_test.gd) | headless | Regression suite for guide 04 (`SRS-01` to `SRS-15`): spawning, respawn and save |
| [squad_ai_live_test.gd](../tests/squad_ai_live_test.gd) | headless, live network | Spends real API quota (about 6 requests): natural-language orders through the LLM director, streamed TTS, STT round trip. Skips itself when no key is configured |
| [squad_ai_unit_test.gd](../tests/squad_ai_unit_test.gd) | headless | No network: SSE parsing with parallel tool calls, tool-to-command mapping, offline parser coverage, and the API failure fallback (bad key, closed local port) |
| [squad_ai_windowed_test.gd](../tests/squad_ai_windowed_test.gd) | windowed | End to end squad behaviour through the typed-chat path (offline): follow, bodyguard, combos, massacre, ceasefire, silly orders, substitution, revive; writes screenshots |
| [test_phantom_hittable.gd](../tests/test_phantom_hittable.gd) | not runnable | Early scratch stub (`extends Node`, prints a hittable value); not a SceneTree test and not part of any suite |
| [test_req06.gd](../tests/test_req06.gd) | not runnable | Early scratch stub for a requirement check; prints a message only |
| [ui_menu_shots.gd](../tests/ui_menu_shots.gd) | windowed | Screenshots of title, loading screen, Warden victory outro and results screen |
| [visual_check_shots.gd](../tests/visual_check_shots.gd) | windowed | Starts a run and saves HUD screenshots at the spawn and near the first prop hint |
| [voice_pipeline_test.gd](../tests/voice_pipeline_test.gd) | headless | Voice engine selection, drop and start signals, stale line skipping, chatter gating, no canned ack on Director orders |

The `*.gd.uid` files beside them are Godot's script identifiers; commit them with the script they belong to.

A reasonable quick pass before a commit: `boot_smoke`, `squad_ai_unit_test`, `voice_pipeline_test`, `combat_rules_test`, and the regression suite for the area you touched. Run `layout_rework_test` and `level_props_test` after any level or layout change.

## 3. Godot CLI cheat sheet

Use the 4.7.2 console binary for your machine (`godot` below).

| Task | Command |
| :-- | :-- |
| Import assets and class cache | `godot --headless --path . --import --quit` |
| Syntax check one script | `godot --headless --path . --check-only -s res://scripts/<path>.gd` |
| Run a headless test | `godot --headless --path . -s res://tests/<name>.gd` |
| Run a windowed test | `godot --path . -s res://tests/<name>.gd -- --shots=<absolute dir>` |
| Open the editor | `godot --editor project.godot` |
| Bake the level preview scene | `godot --path . -s res://scripts/tools/bake_map_preview.gd` (output `scenes/main/map_preview.scn` is git-ignored) |

Rules of thumb:
- Run `--import` first whenever assets or `class_name` declarations changed.
- Check every modified GDScript with `--check-only`, but treat isolated "unknown class" errors with the pitfall in section 1.3 in mind.
- If the editor is open on the project, the editor and the CLI can both import; prefer closing the editor if you see lock or reload problems. Only one editor instance should use the Godot AI MCP ports (8000 and 9500).

## 4. Documentation convention (MEMORY/)

Design and tuning knowledge is held in numbered domain files under [MEMORY/](../MEMORY/00_MEMORY_INDEX_AND_RULES.md), with these rules from `CLAUDE.md` and `AGENTS.md`:

1. Start at `MEMORY/00_MEMORY_INDEX_AND_RULES.md`, then read only the domain file that owns your task: `01` GDD and scope, `02` core systems and physics layers, `03` combat and enemies (including tuning), `04` level design and room coordinates, `05` UI, scoring and audio, `06` assets and shaders, `07` status and changelog.
2. Do not create new `.md` files for individual scripts, bugs, rooms or mechanics. Fold the knowledge into the matching domain file.
3. Update in place in the same change: when you alter a script contract, physics layer, coordinate, damage value or imported asset, edit the matching `MEMORY/0X_*.md` section and append one dated line to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`.
4. Respect the scope lock in `MEMORY/01`: no extra weapons, stamina, inventory, online services (beyond the optional squad AI), or systemic destruction.

The pages in `docs/` are a code-oriented companion to `MEMORY/`: they explain how the code works, while `MEMORY/` records design intent and numbers. When behaviour changes, update both if both describe it.

Other project rules that affect daily work (from `CLAUDE.md`):
- Use the named physics layers (`Player=1`, `Enemy=2`, `World_Shared=3`, `World_Reality=4`, `World_Mirror=5`, `Interactable=6`, `Hitbox=7`, `Player_Blocker=8`) through the `RealmManager` helpers, not raw bitmasks.
- Inactive-realm or held actors must disable collision shapes and pause AI; hiding the mesh is not enough.
- Hitboxes and breakables must be one-hit-per-swing (track `hit_targets`, guard with an idempotent flag).
- One shared `HUD.tscn`; never per-room HUDs.
- Check imported models' forward axis (many face +Z) before wiring movement.
- After adding `.glb`, `.png`, `.wav` and similar assets, run the import command before using them.

## 5. Handoff guides in plan/

[plan/](../plan/) holds large implementation guides written by the "IdiotHandOffGuide" workflow and the audits that check them:

| File | Contents |
| :-- | :-- |
| `IdiotHandOffGuide_01_Combat.md` | Combat fixes (`CMB-xx`) |
| `IdiotHandOffGuide_02_EnemiesAI.md` | Enemy AI fixes (`ENM-xx`) |
| `IdiotHandOffGuide_03_FriendsAI.md` | Squad and voice fixes (`ALY-xx`) |
| `IdiotHandOffGuide_04_SpawningRespawningSave.md` | Spawning, respawn, save (`SRS-xx`) |
| `IdiotHandOffGuide_05_EnemyMarkingAndFreeLeash.md` | Marking and free-leash orders (`MRK-xx`). Note: `layout_rework_test.gd` and `Sanity-Testing-5.md` also call the layout rework "Guide 05", so the numbering is not fully consistent; check the file contents, not just the number |
| `Sanity-Testing-1.md` to `Sanity-Testing-5.md` | Investigator briefs: what to verify by actually playing, per guide. They ask for evidence and say not to fix |

Use them as follows:
- Each guide gives exact code changes with an ID per fix. Test files cite these IDs, so searching an ID finds both the intended change and its test.
- Treat the guides as a record of intent, not as current documentation: later commits may have changed the code. Confirm against the code and `MEMORY/`.
- `workflows/*.yaml` define orchestrated multi-agent runs (`parallax-build.yaml`, `review-changes.yaml`, UI workflows) for the `sub-agent-orchestrator` tool.

## 6. Commit hygiene

- Never commit `.env`, `.env.*` or `*.key` files (they are git-ignored; do not force-add them), nor `user://` data such as `squad_ai.cfg`, saves or the leaderboard. See [09_voice_and_llm.md](09_voice_and_llm.md).
- Never commit editor-rewritten churn. Opening the editor can rewrite `project.godot` (settings order, plugin keys) and `scenes/main/main.tscn` (reformatted or re-saved nodes, new uids). If a diff in those files is not something you intended, discard it (`git checkout -- <file>`) before committing. Stage specific files rather than `git add -A`, and review `git diff --stat` first.
- Do not commit `.godot/` (ignored), exported builds (`*.exe`, `*.pck`, `*.zip`), `scenes/main/map_preview.scn` (regenerable), or temporary scratch scripts. Delete any throwaway verification scripts before committing; the placeholder files `test_phantom_hittable.gd` and `test_req06.gd` show how these accumulate.
- Commit new `.gd.uid` files together with their scripts, and `.import` files for newly imported assets.
- Register any new third-party asset (path, source, licence) in `MEMORY/06_RESOURCES_AND_ASSET_CATALOG.md`.
- Keep commits focused, with a short imperative subject describing the behaviour change (the history uses messages such as "Three-wave fights in the Hall of Echoes and the clock-tower chamber"). Do not skip hooks.
- Before committing code changes: import if needed, `--check-only` the edited scripts, run the relevant tests, update `MEMORY/` and its changelog line, and make sure `git status` contains only what you meant to change.
