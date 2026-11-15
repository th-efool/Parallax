# PARALLAX — Level Design, Coordinates, Rooms & Visual References

> Encapsulates GDD Section 7 plus visual mapping to the 4 reference images stored in `MEMORY/reference_images/`.

---

## 1. Blockout Coordinate Convention (GDD Section 7.2)

- **Scale**: `1 Godot Unit = 1.0 Meter`, Y-up.
- **Origin `(0, 0, 0)`**: Center of **01. Entry Vestibule** floor (`Y = 0` ground plane).
- **Route Direction**: Continuous single-path linear route advancing **North along `+Z`**. Left/Right = `-X / +X`.
- **No Branching / No Loading Screens**: All 5 stages sit seamlessly in `LevelRoot` connected by short framed gate corridors.

> **Engineering Note on `+Z` vs `-Z`**: Because the level progresses along **world `+Z`**, `Vector3(0, 0, 1)` is forward through the colosseum, whereas Godot's `look_at()` defaults to `-Z`. Spawn the player at `(0, 0, -3)` rotated `PI` (`180°`) around Y so they look and walk North (`+Z`) into the first room!

---

## 2. Exact Master Blockout Coordinate Table

| Stage | X Extent | Z Extent | Key Anchors `(X, Y, Z)` | Connector to Next Stage |
| :--- | :--- | :--- | :--- | :--- |
| **01. Entry Vestibule**<br>(`12 x 10 m`) | `-6` to `+6` | `-5` to `+5` | Player Spawn `(0, 0, -3)` facing `+Z`; 3m Floor Gap centered around `Z = +1.0` (`-0.5` to `+2.5`); Mirror Stepping Stones inside gap; Switch Platform `Z = +2.5..+5.0` with Mirror Switch `(0, 0, 4.0)`. | Corridor `Z = 5..10` (Gate 1 at `Z = 5`) |
| **02. Hall of Echoes**<br>(`20 x 20 m`) | `-10` to `+10` | `10` to `30` | Cracked Central Pillar `(0, 0, 20)` (falls northward toward `+Z = 22.5..25`); Skeleton Guards `(-6, 0, 16)` & `(+6, 0, 24)`; Phantom Twins `(-6, 0, 26)` & `(+6, 0, 26)`. | Corridor `Z = 30..34` (Gate 2 at `Z = 30`) |
| **03. Collapsed Gallery**<br>(`24 x 8 m`) | `-4` to `+4` | `34` to `58` | Chasm below floor; 4m Bridge Gap `Z = 44..48` (`3m` wide, `X = -1.5..+1.5`); Weak Stone Support `(0, 0, 51)`; Anchor Switch `(0, 0, 53)` behind support; Shielded Guard `(0, 0, 56)`. | Corridor `Z = 58..62` (Gate 3 at `Z = 58`) |
| **04. Mechanism Chamber**<br>(`12 x 12 m`) | `-6` to `+6` | `62` to `74` | Raised Impact Dais `(-3, 0, 67)` (step/jump height `~1.2–1.5 m`); Suspended Mirror Weight `(0, 2.5, 68)` above Reality Pressure Plate `(0, 0, 68)`; North Gate `Z = 74`. | Corridor `Z = 74..76` (Gate 4 at `Z = 74`) |
| **05. Execution Arena**<br>(`26 m` diameter, `R = 13 m`) | `-13` to `+13` (Circle) | Center `(0, 0, 89)` (`76` to `102`) | Player Entry `(0, 0, 76)`; Warden Spawn `(0, 0, 88)` facing South toward player; Vertical Mirror Plane bisector along `X = 0`; Exit Gate at `Z = 102` leading into sunlit exit walk. | Run Ends -> Results |

*Target total first-clear time across all 5 stages: **~10–15 minutes**.*

> **Collision Greybox Scene (`scenes/environment/colosseum_greybox.tscn` + `scripts/environment/colosseum_greybox_builder.gd`)**: Instantiates the full walkable `Y = 0.0` collision layout across `Z = -5..108` (`ColosseumGreyboxBuilder.build_greybox()`, `get_key_anchors()`), including perimeter containment walls, `PitKillZone_Stage01` & `PitKillZone_Stage03`, `SectionTriggerVolume`s for all 5 stages + `Trigger_RunComplete` on `SunlitExitFloor`, `EntrySteppingStones`, `EntryMirrorSwitch`, `Gate01_EntryToHall`, `CrackedCentralPillar`, `Gate02_HallToGallery`, `GallerySpectralBridge` (`MirrorGeometry` + `RepairedGeometry`), `WeakStoneSupport`, `BridgeAnchorSwitch`, `Gate03_GalleryToMechanism`, `RaisedImpactDais`, `ChamberMechanismPuzzle`, `Gate04_MechanismToArena`, `CentralMirrorPlane`, `Gate05_ArenaExit`, and all 6 live enemies (`2x SkeletonGuard`, `2x PhantomTwin`, `1x ShieldedGuard`, `1x WardenBoss`).

---

## 3. Detailed Room-by-Room Design & Puzzle Contracts

### Stage 01 — Entry Vestibule (~1 min)
- **Camera**: **Third-person exploration** (matching all other stages; NOT first-person). Player immediately sees the missing floor gap ahead.
- **Reality**: Open 3m chasm across `Z = 1`—too wide for normal jump; north gate sealed.
- **Mirror**: Pressing `Q` reveals 3 fixed blue-rimmed spectral stepping stones spanning the gap. Switch platform at `Z = 4` holds the Mirror Switch.
- **Critical Flow**: Walk to edge -> Tutorial prompt `Q: Shift` -> Shift to Mirror -> Cross stones -> Prompt `E: Interact` on Switch -> Gate opens in **both** realms -> Proceed to Hall of Echoes.

### Stage 02 — Hall of Echoes (~2.5–3.5 min)
- **Geometry**: `20 x 20 m` stone fighting arena (circular/octagonal architectural ring inside bounds). South entry gate seals upon entry until all 4 enemies die.
- **Enemies**:
  - Wave 1 (active in Reality on start): **2 Skeleton Guards** at `(-6, 0, 16)` and `(+6, 0, 24)`.
  - Wave 2 (active only in Mirror): **2 Phantom Twins** at `(-6, 0, 26)` and `(+6, 0, 26)`. After the 1st Skeleton falls, emit a subtle Mirror pulse cue pointing player toward Mirror realm (never lock `Q`).
- **Environmental Hazard**: Central Cracked Pillar at `(0, 0, 20)` features an amber/glowing fracture seam. Striking it with Heavy Attack (`RMB`) triggers a `0.6 s` dust/glow warning, then collapses northwards onto a `2.5 m` radius impact zone (`150` dmg to enemies = guaranteed kill on both Skeletons & Phantoms + `+250 Environmental Kill`; `40` dmg to player if inside zone).
- **Exit**: All 4 enemies dead -> North gate opens -> Save Hall Exit Checkpoint.

### Stage 03 — Collapsed Gallery (~2–3 min)
- **Geometry**: Narrow `24 m x 8 m` gallery suspended over a deep chasm. Bridge gap (`Z = 44..48`, `3 m` wide) blocks crossing in Reality.
- **Critical Anti-Soft-Lock Rule**: Once the player shifts to Mirror and crosses to `Z > 48`, if they attempt to press `Q` over open void OR if the bridge hasn't been repaired yet while standing anywhere unsafe, validate strictly. Once `E` activates the Anchor Switch at `(0, 0, 53)`, it **permanently repairs the Reality bridge** (`RealmPlatform.repair_for_reality()`) so shifting back to Reality never traps or drops the player.
- **Sequence**: Shift to Mirror -> Cross Spectral Blue Bridge (`Z = 44..48`) -> Break Weak Stone Support (`(0, 0, 51)`) with `RMB` Heavy -> Interact (`E`) with Bridge Anchor (`(0, 0, 53)`) to repair Reality bridge -> Defeat **Shielded Guard** (`(0, 0, 56)`) by attacking its shieldless Mirror echo -> Exit gate opens.

### Stage 04 — Mechanism Chamber (~1–1.5 min)
- **Geometry**: Compact `12 x 12 m` chamber (`X: -6..+6`, `Z: 62..74`). Uses NO extra puzzle mechanic—strictly recombines Jump + Airborne Landing Attack (`F`).
- **Reality**: Pressure plate sits recessed at `(0, 0, 68)` before the locked north gate (`Z = 74`), weight missing.
- **Mirror**: Raised impact dais `(-3, 0, 67)` provides elevation; a glowing suspended Mirror Weight hovers near `(0, 2.5, 68)` above the plate.
- **Sequence**: Shift to Mirror -> Climb/jump onto dais -> Jump toward weight & press **`F`** in mid-air -> Landing shockwave hits weight target -> Fixed drop animation slams weight onto pressure plate -> North gate opens in **both** realms -> Save Arena Checkpoint upon exiting.
- **Failure Handling**: Missing the `F` slam deals no harm and leaves the weight intact; player simply climbs dais and retries.

### Stage 05 — Execution Arena (~3–5 min)
- **Geometry**: `26 m` diameter grand colosseum floor centered at `(0, 0, 89)`. Bisected visually/thematically by a tall translucent vertical **Mirror Plane** along `X = 0`.
- **Boss**: **The Warden** at `(0, 0, 88)` (`1,000` shared HP). See `03_COMBAT_PLAYER_AND_ENEMIES.md` for full Phase 1 (Split) -> `500 HP` Shatter -> Phase 2 (Merged) behavior.
- **Resolution**: Warden defeated -> Mirror objects dissolve, North exit gate (`Z = 102`) lifts revealing bright sunlit exterior -> Results screen + leaderboard submission.

---

## 4. Reference Images Visual Mapping (`MEMORY/reference_images/`)

All 4 user-uploaded reference JPGs live in `MEMORY/reference_images/` and define our target art direction, HUD layout, and per-room visual contrast:

1. **`00_concept_sheet_overview.jpg`**:
   - Master moodboard: protagonist identity (dark hair ponytail, tattered deep-red cape, dark leather/iron armor, steel broadsword), split Reality (warm ember limestone) vs Mirror (cobalt spectral runes) duality, 5-stage flow banner, and scoring rules summary.
2. **`01_hall_of_echoes_reality_and_mirror.jpg`**:
   - **Hall of Echoes split comparison**:
     - Top (Reality): Golden warm light shafts through ruined stone arches, red sun banners, physical Skeleton Guards, cracked central stone pillar glowing along fracture fault.
     - Bottom (Mirror): Deep indigo atmosphere, glowing cobalt rune edges on arches & pillar, blue crescent moon banners, translucent glowing spectral Phantom Twins/Skeleton reflections.
3. **`02_collapsed_gallery_pillar_and_bridge.jpg`**:
   - **Top — Breaking the Pillar (Hall of Echoes)**: Demonstrates heavy sword arc shattering the glowing fracture seam of the central pillar while Skeleton Guards stagger nearby.
   - **Bottom — Spectral Bridge (Collapsed Gallery)**: Demonstrates crossing the glowing cracked-ice-blue spectral bridge over the abyss in Mirror state toward the glowing far-side Anchor plinth (`E`).
4. **`03_shielded_guard_and_execution_arena_warden.jpg`**:
   - **Top — Shielded Guard / Armored Knight in Mirror**: Glowing cobalt spectral knight with sun/rune shield/body contrast under Mirror state.
   - **Bottom — The Warden (Execution Arena)**: Massive cloaked armored juggernaut (`THE WARDEN` bottom-center boss bar) standing before the glowing half-amber / half-cobalt circular Mirror Plane portal (`REALITY` <-> `MIRROR`), fiery ground telegraph rings on the dark stone floor.
