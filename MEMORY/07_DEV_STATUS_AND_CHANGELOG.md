# PARALLAX — Development Status & Changelog

> Concise live tracker for project milestones. Agents must update the status block and append a brief entry here after completing any milestone or subsystem.

---

## 1. Current Project Status

- **Current Phase**: **Stage 0 — Project Initialized (Pre-Production / Ready for Day 1 Vertical Slice)**
- **Engine Version**: Godot `4.7.2.stable` (Forward+ renderer, Windows 64-bit)
- **Project Root**: `D:\Desktop\Godot\parallax`
- **Active Addons**: `res://addons/godot_ai` (v4.4.1)
- **Git Status**: Initialized with clean `.gitignore` and `.gitattributes`

### Milestone Checklist (7-Day Plan)
- [x] **Stage 0**: Initialize directory tree, `project.godot` (input map + 7 named 3D physics layers), `godot_ai` plugin, `MEMORY/` knowledge base + 4 reference images, `CLAUDE.md`, `AGENTS.md`, `/sub-agent-orchestrator` pipeline, and Git repository.
- [ ] **Day 1**: Player third-person movement, right-shoulder `SpringArm3D` camera, placeholder sword, `RealmManager` (`Q` shift + floor/overlap safety validation), 1 test Reality/Mirror floor pair.
- [ ] **Day 2**: Player combat (`LMB` 3-hit combo, `RMB` heavy, `Space` dodge/jump, `F` airborne landing slam), `EnemyBase` damage interface, `SkeletonGuard` AI, base health HUD.
- [ ] **Day 3**: Stage 02 (`Hall of Echoes`), 2 Skeletons + 2 Phantom Twins, `CrackedPillar` authored collapse + environmental kill, combat gates, `RunState` score & combo tracking.
- [ ] **Day 4**: Stage 03 (`Collapsed Gallery` bridge, weak stone support, permanent anchor repair, `ShieldedGuard`) & Stage 04 (`Mechanism Chamber` raised dais, suspended Mirror weight, pressure plate).
- [ ] **Day 5**: Stage 01 (`Entry Vestibule` stepping stones & switch), Stage 05 (`Execution Arena`, `The Warden` Phase 1/2, mirror plane shatter, ending lift gate), section checkpoints.
- [ ] **Day 6**: Full shared `HUD.tscn`, Title/Pause/Results/Leaderboard/Options menus, `user://leaderboard.cfg` Top-5 persistence, Time Bonus, S/A/B/C Ranks, shaders, SFX & music pass.
- [ ] **Day 7**: End-to-end playtest tuning (`Appendix A` checks), QA test matrix sign-off, Windows 64-bit export & clean-machine verification.

---

## 2. Chronological Changelog

- **2026-11-16 (Stage 0 Init)**: Created `D:\Desktop\Godot\parallax` folder structure, configured `project.godot` (1920x1080, Forward+, 3D physics layers 1–7, complete GDD input bindings), installed `godot_ai` MCP addon, saved 4 concept/reference JPGs with `.gdignore` under `MEMORY/reference_images/`, authored clubbed `MEMORY/00`–`07` knowledge base (incorporating full GDD v1.1 + CC0 asset & shader research), created `CLAUDE.md`, `AGENTS.md`, and `workflows/parallax-build.yaml`, and initialized Git.
