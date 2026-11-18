# Sanity-Testing-5 — Bridges, Bastions, 3x Halls, Layout Rework (audits Guide 05)

> Investigator brief. This is the biggest and riskiest change (99 KB guide, new `JourneyLayout` story<->world coordinate conversion touching weather, audio, objectives, flora, dressing, terrain, saves). Verify by actually traversing the whole route, in both realms, with saves. Report evidence; do not fix.

## Weakest chains

1. **Story<->world conversion (`JourneyLayout.to_world`, `to_world_z`, `story_z`)**
   - Piecewise-linear breakpoints: check monotonicity, round-trip `story_z(to_world_z(z)) == z` at every breakpoint and +/- epsilon, behaviour beyond both ends (slope 1).
   - Every consumer: weather bands, music/ambience zones, objective thresholds, flora/fauna, set dressing, terrain band. Walk the route and log which weather/music/objective is active vs expected at each stage boundary. Off-by-offset errors = wrong storm, wrong music, wrong objective.
2. **Save system migration (G5-14)**
   - Old save (pre-rework, layout version missing) -> Continue: converted correctly? Player not placed in void/inside geometry? Checkpoints, killed enemies, switch states, gates, bridge repairs all restored?
   - New save mid-bridge, in a bastion, in the 60x60 hall with enemies half dead ("all hall enemies restored"), in the 36x36 chamber. Reload and compare enemy counts/positions.
   - Corrupt / partially written save file, save while falling.
3. **Winding bridges (R1 179 m, R2/R3/R5 81 m, two bastions each)**
   - Walkable centre line unbroken: sweep a capsule along the entire path in BOTH realms (floors are realm-specific: layers 4/5). Any realm where a gap exists with no way to cross = soft-lock.
   - Rails: can the player/allies/enemies fall through at bends, at bastion joins, at first/last node edge closures (`join rails`)? Can the camera (layer 8 `Player_Blocker`) clip?
   - Kill planes below: confirm falling respawns at last checkpoint, not in the void; checkpoints exist at each bastion and stage entry; no checkpoint underground.
   - Long-bridge fatigue: R1 is 179 m with 2 bastions. Are checkpoints spaced sensibly? Is traversal time acceptable?
4. **Bastion garrisons (3 enemies each)**
   - Do they spawn on bastion floor (not in parapet ring), at correct Y, asleep until approached (perf), and wake correctly? Ring parapet vs enemy projectile (Hexcaster) and ally pathing: allies stuck on the ring?
   - Roamers have `encounter_id = ""`: confirm they never block a gate and never count toward `EncounterDirector`.
   - Allies/enemies leashing across a 180 m bridge: `RETURNING` leash logic, enemies walking off the bridge to chase.
5. **3x Hall of Echoes (60x60, 9 encounter + 3 roamers) and 3x clock-tower chamber (36x36, 8 roamers)**
   - Encounter completion with 9 enemies including Mirror-only Phantom Twins (Guide 02): winnable? Gates (`Gate02a_HallSouthSeal`, `Gate04b_ArenaSouthSeal`) open/close correctly, seal behind player, no early open.
   - Puzzle internals preserved: cracked pillar, mechanism puzzle (suspended weight, pressure plate, raised dais) still work at 3x scale; clock-tower gears etc. Mechanism node paths unchanged?
   - Perf: FPS min/avg through the hall with all enemies awake, on integrated GPU (Intel UHD 730 is the dev machine), 1080p and 720p. Record draw calls, primitives, VRAM. Compare with prior documented ~240 FPS flythrough (that was a different GPU).
6. **Stage offsets `OFF_S1_TERRACE`, `OFF_S3`, `OFF_S5`**: every previously-authored coordinate (MEMORY/04 sec 2 and 6, ally/enemy spawns, checkpoints, braziers, weather band triggers, summit sword, Warden spawn, ending lift) matches the shifted positions. Spot check 20 nodes; list mismatches.
7. **Terrain follows layout (`JourneyTerrain`)**: route band not poking through bridges, no floating bridges over empty space, no terrain covering the path, river canyon/gorge still under the right gaps, tree/instance counts and load time. Loading screen step progress still reaches 100% and loading time acceptable.
8. **Set dressing and ambient life after remap**: nodes in bridge regions freed; nothing floating mid-air; nothing inside bridge geometry; ambient creatures not spawned on the bridge deck blocking the path; MultiMesh instances moved correctly.
9. **Objective tracker arrow (G5-13)**: follows next bastion centre then far end; no wrong arrow at bridge start, at bastion, after realm switch, after respawn, after loading save. Distance numbers sane.
10. **Start position (G5-15) + Replay/Restart**: spawn on terrace (z about -136), after finishing a run Restart gives full fresh world (gates, enemies, checkpoints, bridge repair state).
11. **Regression of earlier systems**: run `tests/layout_rework_test.gd` (claimed 128/128), `tests/restart_flow_test.gd`, `tests/squad_ai_unit_test.gd`, `tests/feel_and_movement_test.gd`, `tests/boot_smoke.gd`. Any test hard-coding old coordinates must be flagged. Then do a manual full run Title -> Results -> Leaderboard end to end, in one sitting, no cheats, recording time and every anomaly.
12. **Allies on long routes**: formation, pathing around bends, falling off bridges, teleport-to-player thresholds, camera-safe formation slots on narrow 7.5 m bridges, stairs.

## Evidence
Per-stage tables (expected vs actual weather/music/objective), position dumps, FPS numbers, soft-lock attempt log, save/load before-after diffs, full-run notes.

## Verdict format
PASS / FAIL / UNVERIFIED per item, repro, file:line, severity. Any soft-lock, fall-through-world, or unwinnable encounter is a BLOCKER.

---
## Findings (2026-11-18 — Live & Code Verification)

- **1. Story<->world conversion (`JourneyLayout`)**:
  - **PASS** — `journeylayout_roundtrip_breakpoints` max error `0.00000` across all 9 `ZMAP` breakpoints `+/- 0.01` and `-200..+250` extremes (`_sanity_probe_5.gd`). `layout_rework_test.gd` 54/54 PASS.
  - **PASS** — `WeatherDirector` (`weather_band=blood` at Arena), `AudioManager` (`story_z` footsteps & interior), and `ObjectiveTracker` (`guide_target` targeting Bastion 2 `(-34, 0, -49)` from Bastion 1) all align with world coordinates.
- **2. Save system migration (`layout_version` G5-14)**:
  - **PASS** — `restart_flow_test.gd` PASS (`enemies=57, killed-enemy-restored=true`). All 7 real v1 checkpoints migrate onto solid floor (`missing_floor=0 / 7`).
  - **MINOR (Legacy edge case)** — Any hypothetical v1 save whose `checkpoint_position` was inside a replaced connector (e.g. old `Overlook (-7, 0, -33)`) would migrate onto an empty Z where the new bridge swings sideways (`+34` / `-34`), though real checkpoints were only placed at the 7 stage entries.
- **3. Winding bridges (`R1`, `R2`, `R3`, `R5`) & floor continuity**:
  - **PASS** — Capsule/ray sweeps across all 4 bridges in BOTH Reality and Mirror found `0` floor holes (`floor_holes=0`); `R5_Processional` to `ChamberFloor` edge (`z=228.5`) continuous (`hit_at_228.5=true`). `layout_rework_test.gd` verified 0 open rail gaps & 0 open bastion ring directions.
- **4. Bastion garrisons & squad behavior on bridges**:
  - **FAIL (Existing test regression — `tests/squad_ai_windowed_test.gd` 2/53 failed)**: `strategy_divide_distinct_targets ["E21", "E20"]` and `taunted_enemy_chases_past_leash` (`19.0 m from taunter, 9.8 m from home`, snagged on forecourt join rail under `22 m`).
- **5. 3x Hall of Echoes (60x60) & 3x Clock-Tower Chamber (36x36)**:
  - **FAIL (MAJOR — Performance on Intel UHD 730)**: At `1280x720` High in the 60x60 Hall (`s5_hall_60x60.png`), FPS dropped to **`14.0 FPS`** with **`1,663` draw calls** and **`834.0 MB` VRAM** (far above the 414 draw calls / 60 FPS target).
  - **FAIL (MAJOR — Undamaged Enemy HP Bars Show `100/100`)**: Visual inspection of `s5_chamber_36x36.png` revealed undamaged enemies display **`100/100`** instead of `250/250` (`175/175`, etc.) because `_attach_enemy_hp_bar` (`colosseum_greybox_builder.gd:881`) initializes the label *before* `EnemyBase._ready()` applies `HEALTH_SCALE = 2.5` and `EnemyBase._ready()` never emits `health_changed`.
  - **FAIL (MINOR — Freed Lambda Capture Error)**: Killing all 9 Hall enemies triggered `ERROR: Lambda capture at index 0 was freed. Passed "null" instead. (gdscript_lambda_callable.cpp:110)`.
  - **PASS** — `CrackedCentralPillar` centered at `(0.0, 4.0, 86.0)`, killing all 9 Hall enemies opens `Gate02_HallToGallery`, and `ChamberMechanismPuzzle` slam in Mirror solves and opens `Gate04_MechanismToArena` (`solved=true, gate4_open=true`).
- **6. Stage offsets (`OFF_S3`, `OFF_S5`)**: **PASS** — `Trigger_RunComplete` sits at `z=349.0` (`189 + 160`); `gallery_offset`, `arena_offset`, `spawn_on_terrace` (`-136.0`) all verified.
- **7. `JourneyTerrain`**: **PASS** — Terrain remains `>= 2 m` below all bridge & bastion nodes (`pokes=0`).
- **8. Set dressing remap**: **PASS** — `floating_dress_nodes=0` in `DROPPED` story-Z regions.
- **9. Objective tracker arrow**: **PASS** — Visually verified in `s5_r1_bastion1.png` (`83m >` pointing toward Bastion 2 `(-34, 0, -49)`).
- **10. Full manual Title -> Results -> Leaderboard playthrough**: **UNVERIFIED** interactively in one continuous human sitting (individual stages, puzzles, Warden reset, and `Trigger_RunComplete` verified piecewise).
