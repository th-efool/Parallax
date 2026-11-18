# Sanity-Testing-4 — Gate Stone, Support Ledge, Extra Enemies (audits Guide 04)

> Investigator brief. Verify `IdiotHandOffGuide_04_Gate_Support_Enemies.md` in the live game. Highest risk here: SOFT-LOCKS (puzzle unsolvable, enemy unreachable, switch unreachable). Report evidence; do not fix.

## Weakest chains

1. **EntryMirrorSwitch at (-3.1, 0, 3.2)**
   - Reachable in Reality AND Mirror? Which realm is needed to see/interact? Interact prompt range, `E` works from both sides, not blocked by plinths (x = +/-5.0) or gate guards' collision.
   - Does solving it open the gate in all states: after death/checkpoint reload, after save/Continue, after replay (scene reload)? Is switch state persisted correctly in `user://savegame.cfg`?
2. **Gate guards**: 2 Shielded x1.35 (`_enlarge_enemy`) + Grave Brute + Hexcaster.
   - Enlarged collider vs. nav/geometry: do big enemies clip into plinths/gate/walls, get stuck, fall off the terrace, or become un-hittable (hurtbox not scaled with mesh)?
   - Scale applied to mesh, collision, hitbox reach, HP bar/label offset, attack range. Check each separately.
   - Encounter fairness: can the player + allies clear 4 elites (HP x2.5) at spawn with starting resources? Any way to skip (run past, `EncounterGate` seal logic, `seal_gate_for_encounter`)?
   - Realm rules: shielded block angle (80 deg half-angle) when scaled; Hexcaster bolts blocked by plinths?
3. **WeakStoneSupport on `SupportLedge` (deck +3.6 m), reached by `ParkourStep_1..3` (+1/+2/+3 m)**
   - Can the player actually jump each step (jump height vs 1/2/3 m, momentum sprint, variable jump)? Test from stationary, with and without sprint, with camera obstruction, with allies in the way.
   - Can the player fall back down and retry? Any pocket where the player/allies get trapped (ledge blockers, parapet blockers on layer 8)?
   - Anchor switch behind it on the ledge: reachable, interactable, repair persists (`RepairedGeometry`), bridge repair no-soft-lock (AGENTS.md Level Builder check). What if the player breaks/uses the support BEFORE reaching the anchor, or dies on the ledge?
   - Ally pathing: can allies follow up the parkour steps or do they teleport/stall? Camera clipping on the ledge.
4. **Extra enemies**: ShieldedGuard_1 at z 83.2, +2 gallery skeletons, +1 esplanade hexcaster. Do they stand on valid floors in the correct realm (floor exists in the realm where they spawn)? Do they register with `EncounterDirector` (encounter completes only when ALL are dead; counts correct; none counted twice or missed)? Any spawn inside geometry post-layout-rework (Guide 05 shifted Stage 03/05 by `OFF_S3`/`OFF_S5`)?
5. **Objective hints match layout**: walk the whole stretch; each objective/hint/waypoint arrow text must describe what the player sees now. Old text referencing the previous switch position or causeway is a FAIL.
6. **Interaction with Guide 05 coordinate shift**: re-verify every position in Guide 04 against `JourneyLayout.to_world`. Positions authored in story coordinates may now be wrong by the offset.
7. **Memory docs**: `MEMORY/04` section 6 must match actual in-game coordinates for these objects (spot check 10 values using `get_node_info`).

## Evidence
Position dumps from `get_node_info`, screenshots of each parkour step, soft-lock attempts and outcomes, encounter counters.

## Verdict format
PASS / FAIL / UNVERIFIED per item, repro, file:line, severity. Flag any soft-lock as BLOCKER.

---
## Findings (2026-11-18 — Live & Code Verification)

- **1. `EntryMirrorSwitch` at `(-3.1, 0, 3.2)`**:
  - **PASS** — `level_props_test.gd` confirms switch sits `>= 2.8m` left of `Gate01_EntryToHall` (`(-3.1, 0.0, -1.8)` relative). Live probe confirmed `interact()` works in Mirror and opens `Gate01_EntryToHall` (`activated=true, gate_open=true`).
- **2. Gate guards (`2x Shielded x1.35`, `GateBrute`, `GateHexcaster`)**:
  - **FAIL (MAJOR — `_enlarge_enemy()` misses `AttackHitbox`)**: `grand_journey_builder.gd:498-524` scales `VisualRoot`, `BodyCollider`, `Hurtbox3D`, `FloatingHPBar`, and `attack_range` (`1.245x` -> `2.49 m`) on `GateWarden_W/E`, **but never scales `AttackHitbox`** (`hitbox_reach = 1.90 m`). Enlarged guards initiate swings at `2.49 m` that whiff outside `1.90 m` reach.
- **3. `WeakStoneSupport` on `SupportLedge` (+3.6 m) via `ParkourStep_1..3`**:
  - **PASS** — Real `move_forward` + `jump` physics test (`_sanity_probe_4b.gd`) cleanly climbed every step (`heights=[1.00, 2.00, 3.00, 3.60]`) onto `SupportLedge`.
  - **PASS** — `BridgeAnchorSwitch.can_interact()` checks `blocking_prop_path` (`WeakStoneSupport`), returning `false` before break (`anchor_before_break=false`) and repairing `GallerySpectralBridge` into Reality (`repaired=true`) after break (`interact_switch.gd:67-70`). No soft-lock.
  - **PASS** — `ShieldedGuard_1` clearance at `z=187.20` (world) leaves `0.80 m` gap south to `SupportLedge` and `0.80 m` north to `Gate03`.
- **4. Extra roamers (`GallerySkeleton_A/B`, `EsplanadeHexcaster`)**: **PASS** — All 3 spawn under `Roamers/` (`Stage03_CollapsedGallery/Roamers/` and `Stage05_ExecutionArena/Roamers/EsplanadeHexcaster`) with `encounter_id = ""`, never blocking gates.
- **5. Objective hints match Guide 04**: **PASS** — `objective_tracker.gd:95` names Mirror Switch left of gate; `objective_tracker.gd:115` describes climbing blocks on the right to the high ledge.
- **6. Guide 05 coordinate shift parity & `MEMORY/04` sync**:
  - **FAIL (MINOR — Stale `MEMORY/04` §6 tables)**: `GrandJourneyBuilder` shifts Stage 03 (`OFF_S3`) & Stage 05 (`OFF_S5`) in-engine cleanly (`level_props_test.gd` 13/13 PASS), **but `MEMORY/04_LEVEL_DESIGN_AND_ROOMS.md` §6.1–6.4 (`lines 235-280`) still lists pre-Guide-05 story coordinates** (e.g. `Prologue_StartTerrace` at `-56`, `HallFloor 20x20`, `ShieldedGuard_1 (0,6,82)`) instead of world coordinates (`-136`, `60x60`, `z=187.20`).
