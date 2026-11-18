# Sanity-Testing-1 — HUD, World Text, Lighting (audits Guide 01)

> Investigator brief. Goal: PROVE or BREAK the claims of `IdiotHandOffGuide_01_HUD_Readability_Lighting.md`. Do not trust prior "tests passed". Run the real game (windowed, Godot 4.7.2, MCP `godot-ai` or desktop) and report evidence (screenshots, logs, numbers). Do NOT fix; report only. No new `.md` files except your findings appended to the report you hand back.

## Weakest chains (try to break each)

1. **`WorldLabelOverlay.adopt()` lifecycle**
   - Labels are "adopted" (3D transparency=1, drawn in 2D). What happens when the owner node is freed (enemy dies, gibs, pooled/respawned on checkpoint reload)? Look for orphaned overlay entries, leaks, errors in `logs_read(source=game)`.
   - Replay / Restart Run reloads the scene: does the overlay duplicate, stack, or keep stale labels?
   - 50+ enemies alive (Hall of Echoes 60x60, bastions): measure FPS and per-frame cost of the overlay (`time/process`). Any O(n²) behaviour?
2. **Projection edge cases**: label behind the camera, exactly at screen edge, huge distance, `max_dist` boundary flicker, camera shake / FOV change / perfect-dodge slow-mo, ultrawide and 4:3 and 1280x720 vs 1920x1080 (stretch `canvas_items` + `expand`). Do labels land on the correct entity or drift?
3. **Hidden-by-default command log (`show_command_log_v2`)**: fresh profile (delete `user://`), old profile with legacy "visible" key, toggle `L` while chat bar is focused (typing "l" must NOT toggle), persistence across restart.
4. **Squad roster under health**: 0, 1, 3, 4 allies; ally downed ("DOWN · E" pulse), ally dies permanently, name longer than bar, roster overlapping the objective tracker / HP bar at 720p.
5. **Boss bar only in arena**: enter arena, leave, die, respawn at checkpoint, Phase 2 transition, Warden killed. Bar must never linger or show in other sections; check save/load mid-boss.
6. **Stylized look regressions**: `realm_pbr.stylize 0.7`, `journey_sky.stylize`, no volumetric fog, SSAO, saturation. Check BOTH realms, Low / Medium / High presets, integrated GPU path (D3D12/OpenGL3 fallback, FSR render scale). Any shader compile errors on fallback renderers? Mirror realm still readable? Weather bands (storm/blood moon) still legible with new sky?
7. **Action icons 80 px** and keycap labels after rebinding (Options > Controls): do icons/prompts update live? Overlap with the squad mic button at 720p.
8. **Warnings noise**: the editor already reports many GDScript warnings (e.g. `hud_controller.gd` `tr` shadows `Object.tr`, unused `_last_realm_key`, INTEGER_DIVISION at line 715). Determine whether any of these is an actual bug (integer division changing a ratio, shadowed `tr` misused).

## Evidence to collect
- Screenshots at: spawn, first prop hint, near 5+ enemies, boss arena, Mirror + Reality, 720p + 1080p.
- `logs_read` game + editor, zero new errors during a 10-minute run.
- FPS min/avg via `editor_manage monitors_get`.

## Verdict format
For each item above: PASS / FAIL / UNVERIFIED, reproduction steps, file:line suspected, severity (blocker / major / minor).

---
## Findings (2026-11-18 — Live & Code Verification)

- **1. `WorldLabelOverlay` lifecycle & prop hints**:
  - **FAIL (MAJOR)** — `ObjectiveTracker._refresh()` (`scripts/ui/objective_tracker.gd:66-73`) runs `0.25s` after boot on the Title Screen when `Main/Player` and empty `Main/LevelRoot` already exist, sets `_labels_done = true` prematurely, and misses **all 5 / 5** world prop hint labels (`EntryMirrorSwitch`, `EntrySteppingStones`, `BridgeAnchorSwitch`, `WeakStoneSupport`, `CrackedCentralPillar`).
  - **PASS** — Enemy `queue_free()` cleanly drops `world_label_2d` count (`78 -> 76`) with 0 errors; scene reload (`start_run_now()`) keeps `WorldLabelOverlay` count = `1`.
  - **MINOR (Perf)** — `WorldLabelOverlay._process()` calls `queue_redraw()` unconditionally every frame (even on Title/Pause), projecting/sorting ~78 labels. At `1920x1080` High on Intel UHD 730 in Hall of Echoes Mirror: `10.0 FPS` (`time/process = 116.84 ms`).
- **2. Projection edge cases**: **PASS** (`1280x720`, `1920x1080`, `1280x960` 4:3 checked; `wlo.size=(1920,1080)` matches stretched canvas). Ultrawide `2560x1080` UNVERIFIED live (code scales by `s / vp`).
- **3. Hidden-by-default command log (`show_command_log_v2`)**: **PASS** — starts `false`, ignores legacy key (`squad_ai_config.gd:78`), `L` ignored when `_chat_open = true`.
- **4. Squad roster under health**: **PASS** — visually verified at `1280x720` (`BRANNOC`, `SERA`, `IVO` + hint below, no overlap).
- **5. Boss bar only in arena**: **PASS (code + partial live)** — `false` at spawn, in Hall, and after leaving arena (`z=120`). Teleporting straight to `z=152` bypassed `Trigger_Stage05_ExecutionArena` (`story z=140.5`), confirming visibility is gated strictly by section transition (`hud_controller.gd:721-724`).
- **6. Stylized look & fallback renderers**: **PASS** — Reality, Mirror, and Low preset + Blood Rain screenshots verified cleanly; `--rendering-driver d3d12` ran with 0 shader errors.
- **7. Action icons 80 px & rebinding**: **PASS (size/layout)** — `badge.size=(80, 80)`, no mic overlap (`[P:(1812,600), S:(64,64)]`). Rebind live check was UNVERIFIED in probe (called wrong method name; real method is `LeaderboardStore.rebind_action`).
- **8. GDScript warnings triage**: **PASS (benign)** — `hud_controller.gd:715`, `world_label_overlay.gd:116`, `squad_comms_hud.gd:420` integer divisions are intentional; `hud_controller.gd:91` (`_last_realm_key`) is dead code (`minor`).
