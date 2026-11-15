# PARALLAX Memory Index & Documentation Rules

> **Single Source of Truth**: This `MEMORY/` folder contains the complete, locked specification, technical contracts, coordinates, balance values, visual references, and researched asset catalog for **PARALLAX** (GDD v1.1). Every AI agent and human contributor must consult the relevant file below before reading or editing code, scenes, or assets.

---

## 1. Directory Map (Clubbed Knowledge Domains)

All project knowledge is strictly encapsulated into **8 numbered files** (`00`–`07`) plus `reference_images/`:

| File | Domain Encapsulated | Read Before Touching... |
| :--- | :--- | :--- |
| [00_MEMORY_INDEX_AND_RULES.md](00_MEMORY_INDEX_AND_RULES.md) | Memory directory map, anti-sprawl rules, update workflow | Any file or planning task |
| [01_GDD_OVERVIEW_AND_SCOPE.md](01_GDD_OVERVIEW_AND_SCOPE.md) | Vision, narrative arc, opening/ending copy, 7-day schedule, QA matrix, DoD, risk register, locked scope & cut list, IGDC brief alignment | Scope decisions, planning, QA, milestones |
| [02_CORE_SYSTEMS_AND_ARCHITECTURE.md](02_CORE_SYSTEMS_AND_ARCHITECTURE.md) | Scene tree layout, script contracts, `RealmManager`, safety validation queries, `RealmReactive`, `EncounterDirector` FSM, physics layers, checkpoints, performance budget | `scripts/core/`, `main.tscn`, realm switching, collisions, checkpoints |
| [03_COMBAT_PLAYER_AND_ENEMIES.md](03_COMBAT_PLAYER_AND_ENEMIES.md) | Controls, third-person camera specs, movement/dodge/landing-attack rules, light/heavy combat, combo state, authored breakables, all 3 enemy classes, Warden 2-phase boss fight, Appendix A tuning sheet, Appendix B terminology | `scripts/player/`, `scripts/enemies/`, `scenes/player/`, `scenes/enemies/`, `scenes/props/` |
| [04_LEVEL_DESIGN_AND_ROOMS.md](04_LEVEL_DESIGN_AND_ROOMS.md) | Blockout coordinate conventions, exact `(X,Y,Z)` extents & placements, all 5 connected stages (Entry Vestibule through Execution Arena), puzzle rules, reference image visual alignment | `scenes/environment/`, `scripts/environment/`, `level_root` |
| [05_UI_SCORING_AND_AUDIO.md](05_UI_SCORING_AND_AUDIO.md) | Scoring awards & time formula, combo multipliers, S/A/B/C rank thresholds, local `user://leaderboard.cfg`, shared `HUD.tscn` anchor contract, menus, visual/audio feedback, Reality vs Mirror palette, character identity, animation sets, audio cues, accessibility | `scenes/ui/`, `scripts/ui/`, lighting, `WorldEnvironment`, `assets/audio/` |
| [06_RESOURCES_AND_ASSET_CATALOG.md](06_RESOURCES_AND_ASSET_CATALOG.md) | Researched CC0/free 3D architecture kits, PBR textures, rigged characters & animations, mixamo/retargeting workflow, ready-to-use Godot 4 shaders (`mirror_spectral`, `sword_slash_trail`, `realm_shift_pulse`), SFX/music sources, recommended Godot addons | Importing assets, writing shaders, retargeting animations |
| [07_DEV_STATUS_AND_CHANGELOG.md](07_DEV_STATUS_AND_CHANGELOG.md) | Current milestone state, completed systems, Day 1–7 checklist, chronological change log | Starting a session or finishing a task |
| `reference_images/` | 4 visual concept & in-game UI/art reference JPGs (`00`–`03`) | Modeling, lighting, VFX, UI layout |

---

## 2. Mandatory Anti-Sprawl & Clubbing Protocol for AI Agents

To prevent documentation bloat ("billions of tiny `.md` files") while keeping future AI agents fast and context-efficient:

1. **NO New `.md` Files for Minor Work**: Never create standalone markdown files for individual scripts, bugfixes, shader tweaks, room props, or single mechanics. Everything belongs in one of the existing domain files `01`–`07`.
2. **Strict Encapsulation**: Put changes only where the domain belongs:
   - Changed cooldown or damage numbers? -> Update Appendix A / attack table in `03_COMBAT_PLAYER_AND_ENEMIES.md`.
   - Moved a gate or bridge coordinate? -> Update the coordinates table in `04_LEVEL_DESIGN_AND_ROOMS.md`.
   - Added or renamed a script, node, signal, or physics layer? -> Update `02_CORE_SYSTEMS_AND_ARCHITECTURE.md`.
   - Downloaded a new CC0 model, texture, or SFX pack? -> Register its file path, source, and license in `06_RESOURCES_AND_ASSET_CATALOG.md`.
3. **Update In-Place Immediately**: Whenever you implement, refactor, or change a system, script interface, node path, or tuning value, update the corresponding section in `MEMORY/` in the **same turn** so future agents never read stale info.
4. **Log Progress Concisely**: Append one dated bullet line per completed task or milestone to `07_DEV_STATUS_AND_CHANGELOG.md`.
5. **Respect `.gdignore`**: `MEMORY/.gdignore` intentionally prevents Godot from importing the reference JPGs into `.godot/`. Do not delete `.gdignore`.
