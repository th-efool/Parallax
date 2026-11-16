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

## 2. LIVE LEVEL: "The Ascent" — Grand Journey Layout (2026-11-16, supersedes the 2.x greybox table below)

`scenes/main/main.tscn` -> `LevelRoot` = `scenes/environment/grand_journey.tscn` (`GrandJourneyBuilder` extends `ColosseumGreyboxBuilder`, reusing its gate/switch/trigger/enemy/breakable factories). Player spawn `(0, 0, -56)` facing `+Z`. The route climbs north **and up**; all five GDD beats keep their proven internal dimensions. **Node names under each `StageNN_*` root are a hard contract** (save system in `LeaderboardStore.apply_saved_world_state()`, `MainController` -> `Stage05_ExecutionArena/Enemies/TheWarden`).

| Segment | Y | Z span | Key gameplay positions | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Prologue — Pilgrim's Causeway | 0 | -61 .. -15 | Spawn & `Trigger_Stage01_Entry` `(0,0,-56)`; overlook `(-7,0,-33)`; `Trigger_Stage01_Forecourt` checkpoint `(0,0,-7.5)` | Start terrace, two angled causeways, west overlook, gate forecourt. Parapets with 2.7 m invisible blockers (jump apex ≈ 1.94 m). |
| 01 Gate of Reflections | 0 | -5 .. 8 | **Unchanged greybox core**: gap `Z -0.5..2.5` (+`PitKillZone_Stage01`), Mirror stones `(0,0,1)`, switch `(0,0,4)`, `Gate01_EntryToHall` `Z 5` | 22 x 15 m gatehouse arch, two 10 m sword monuments on plinths `(±4.3, 2.4, 3.6)`. Massif is split around the gap so the chasm is a real drop. |
| Sunlit Stair | 0 -> 4 | 8 .. 24 | Ramp collider (16°), landing `Z 22..24` | 8 m stair, stepped cheek walls + colonnade. |
| 02 Hall of Echoes | 4 | 24 .. 44 | Pillar `(0,4,34)` falls `+Z`; Skeletons `(-6,4,30)` `(6,4,38)`; Phantoms `(-6,4,40)` `(6,4,40)`; `Gate02a_HallSouthSeal` `Z 24` (new, starts open, sealed by `Trigger_Stage02_Hall` checkpoint `(0,4,25.6)`, reopened on clear); `Gate02_HallToGallery` `Z 44` | Two-storey arcades with grilles, corner towers, mosaic ring. Pillar visual topples during its 0.6 s warning. |
| Windswept Rampart | 4 -> 6 | 44 .. 60 | Corridor `Z 44..48`, ramp `Z 48..58` | Open west (sunset) side, buttressed curtain wall east. |
| 03 Aqueduct Gallery | 6 | 60 .. 88 | Floors `Z 60..70` & `74..84`; gap `Z 70..74` (bridge `(0,6,72)`, `PitKillZone_Stage03` threshold `Y 3`); support `(0,6,77)`; anchor `(0,6,79)`; Shielded Guard `(0,6,82)`; `Gate03` `Z 84`; trigger checkpoint `(0,6,61.5)` | Deck on 46 m aqueduct arches over a gorge; ruined colonnade with collidable shafts at `x ±3.45`. |
| 04 Clock-Tower Chamber | 6 | 88 .. 100 | Centre `(0,6,94)`; dais `(-3, 7.35 top, 93)`; weight `(0,8.5,94)`; plate `(0,6,94)`; `Gate04_MechanismToArena` `Z 100`; trigger checkpoint `(0,6,89.5)` | 18 m walls, turning bronze gears, oculus at `Y 24.5`. |
| Processional Stair | 6 -> 10 | 100 .. 120 | Corridor `Z 100..102`, stair `Z 102..116`, esplanade `Z 116..120` | Four 13 m sword monuments, braziers. |
| 05 Mirror Colosseum | 10 | 120 .. 186 | Centre `(0,10,154)`, arena R 13.6; south tunnel `Z 120..140.5`; `Gate04b_ArenaSouthSeal` `Z 140.5` (new, sealed by `Trigger_Stage05_Arena` checkpoint `(0,10,142.5)`); Warden `(0,10,153)`; Mirror Plane along `X 0`, `Z 143..165`; `Gate05_ArenaExit` `Z 167.5`; north tunnel `Z 167.5..186` | Podium wall (32 collider segments), 10 seating tiers, 3-storey 44-bay facade, portal towers, 16 velarium masts. |
| Sunset Summit | 10 | 186 .. 202 | `SunlitExitFloor`; `Trigger_RunComplete` `(0,10,189)` | Overlooks the setting sun. |

- **Kill planes**: `PitKillZone_Stage01`, `PitKillZone_Stage03`, plus `Scenery/PitKillZone_World` (half-extents 700 x 19 x 700, threshold `Y -6`) catching any fall off the cliffs.
- **Collision & polish contract (2026-11-17, audited)**: zero walk-through visuals on the reachable route in either realm (trimesh audit, 0.4 m grid, flood-filled from the waypoints); zero visible coplanar overlaps (≤ 4 mm, same-facing). Breakable debris (pillar drums/stump, support rubble) uses a `DebrisBody` under `BrokenVisual` that `BreakableProp` enables only once broken; the Mirror Plane's bronze frame posts are a `FrameBody` disabled on shatter; after the anchor repair `RealmPlatform` retires the spectral span (`MirrorGeometry`) because `RepairedGeometry` replaces it. Hall gate-arch piers have colliders on both gates. Corridors 02/03/04 use visible balustrades (no invisible walls on open walkways). Gates animate (portcullis rises 0.7 s / slams 0.28 s) — colliders still switch instantly.
- **Route contract**: `GrandJourneyBuilder.get_route_waypoints()` lists the critical-path feet positions + required realm; keep it in sync when moving geometry (it drives the route verification test).
- **Scenery** (`LevelRoot/Scenery`, cosmetic): clamped-top rock massifs under every walkable region, gorge walls, ~40 tapered crag spires (MultiMesh, kept off the west/sunset side), 18 ridged distant ranges at 1.2–2.3 km, `cloud_sea.gdshader` plane at `Y -32`, Mirror-only floating crystal isles.
- **Decor** (`LevelRoot/Decor/Zone*/{Shared,RealityDressing,MirrorDressing}`): braziers (fire in Reality, cobalt spirit-flame in Mirror, `RealmTorchLight`), cloth banners (`banner_cloth.gdshader`, sun / moon emblems), crystal clusters (Mirror). No colliders.

## 2.x Legacy Greybox Coordinate Table (kept for `colosseum_greybox.tscn` / reference only)

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

### 3.6 Environmental Dressing Layer (Claude Pass B — legacy greybox only; the live level uses the Grand Journey decor in §2)
Built by `ColosseumGreyboxBuilder._dress_environment()` (toggle `dress_environment`) under `LevelRoot/EnvironmentDressing/StageNN_Dressing/{Shared, RealityDressing, MirrorDressing}`. **Adds no colliders** (`_strip_model_collisions()` zeroes every imported `CollisionObject3D`); all gameplay bodies, anchors and coordinates above are unchanged. Reality/Mirror groups are gated by a child `RealmReactive` (`manage_collisions = false`). Models are AABB-fitted at runtime (`_place_model()`), so KayKit scale/pivot differences don't matter.

| Stage | Shared (both realms) | Reality only | Mirror only |
| :--- | :--- | :--- | :--- |
| 01 Entry | KayKit wall run on S/W/E walls (`h 3.5`), barrel + crate in south corners, 2 torch lights | 2 `torch_lit`, 2 `banner_red`, dust motes | 2 crystal sconces, 2 `banner_blue`, glass flecks |
| 02 Hall | W/E wall runs, 4 `pillar_decorated` at `(±8.6, 0, 11.4/28.6)`, barrels/crate/rubble at hall corners, 4 lights | 4 torches, 2 red banners, dust | 4 sconces, 2 blue banners, flecks |
| 03 Gallery | 8 `pillar` columns on floor edges `x = ±3.5` (some broken-short), edge rubble; no walls | dust | flecks |
| 04 Mechanism | W/E wall runs (incl. `wall_gated`), barrel + crates in corners, 2 lights | 2 torches, 2 red banners, dust | 2 sconces, 2 blue banners, flecks |
| 05 Arena | W/E wall runs (`h 4.5`), 6 `pillar_decorated` at `x = ±11.6`, `z = 80/88/96`, corner rubble/crate, 6 lights | 6 torches, 4 red banners, dust | 6 sconces, 4 blue banners, flecks |

- **Surfaces**: opaque greybox boxes use `realm_stone.gdshader` (limestone ↔ cobalt slate + glowing rune seams, `mirror_blend` tweened `0.20 s`); translucent Mirror boxes use `mirror_spectral.gdshader`; gates/switch plinths/pressure plate keep plain `StandardMaterial3D`.
- **Breakables**: Cracked Pillar & Weak Stone Support get stone material + an emissive amber `FractureSeam` on the south (approach) face.
- **Torch lights**: `RealmTorchLight` (`scripts/environment/realm_torch_light.gd`) — ember flicker in Reality, steady cobalt in Mirror, violet when merged.
- **Central Mirror Plane**: `mirror_obsidian.gdshader`; cracks grow with Warden damage; on shatter `BreakableProp` spawns 28 cosmetic `RigidBody3D` glass shards (layer `0`, mask `World_Shared`) that fall, shrink and free after `4 s`, plus a cobalt burst. Shards are cleared on `reset_prop()`.

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

---

## 5. Ambient Life Placement Kit (fauna & flora — non-combat)

Ready-to-place prefabs; **not yet placed in the level** (map team owns placement). Everything is cosmetic: no collision, never damages, never counts toward encounters, hides itself in the wrong realm. Test bench: `scenes/ambient/ambient_showcase.tscn` (walk around, swing, press `Q`).

| Drop-in prefab (`scenes/ambient/habitats/`) | Spawns | Group style | Good spots |
| :--- | :--- | :--- | :--- |
| `wisp_swarm.tscn` | 7 Spirit Wisps | mixed flock + loners | Hall of Echoes, Arena edges (they gather over fresh kills) |
| `butterfly_meadow.tscn` | 6 Butterflies | mixed, courting pairs | Sunlit Exit, Entry with `bloom_bed` nearby |
| `mirror_moth_drift.tscn` | 6 luminous moths (Mirror-only) | small groups of 3 | Gallery, Mechanism Chamber |
| `crow_murder.tscn` | 6 Ruin Crows | one flock | Arena stands, broken walls — add child `Marker3D` named `Perch*` on ledges |
| `scurrier_nest.tscn` | 5 rodents | follow-the-leader line | Rubble corners — add child `Marker3D` named `Cover*` behind rubble/pillars |
| `grass_patch.tscn` / `bloom_bed.tscn` / `spore_cluster.tscn` | reactive flora | — | Cracked floors, wall bases, around pillars |

Single creatures/plants for hand placement: `scenes/ambient/creatures/*.tscn`, `scenes/ambient/flora/*.tscn` (`mirror_bloom` = Mirror-only).

**Habitat knobs**: `count`, `radius`, `group_mode` (ONE_GROUP / SMALL_GROUPS / ALL_LONERS / MIXED), `loner_chance`, `archetype_override` (force e.g. all CURIOUS), `realm_presence`, `home_radius_scale`, `debug_labels` (floating species/personality/behaviour text). **Flora knobs**: `kind`, `count`, `radius`, `min_spacing`, `clump_size`, `shyness`, `realm_presence`.

**Perf budget**: AI ticks ~8 Hz staggered; creatures/flora freeze + hide beyond ~45 m / 40 m from camera; max 10 wisp `OmniLight3D`s globally (rest are glow-only). Suggested per-room cap: ~25 creatures, ~120 flora.

### 5.1 Animated animals & MegaKit vegetation (realm rules)
| Prefab | Contents | Realm |
| :--- | :--- | :--- |
| `habitats/deer_herd`, `stag_pair` | Quaternius deer / stags (grazers: graze, glance, freeze-alert, bolt) | Reality only |
| `habitats/fox_den` | Fox (stalks rats / doves / scurriers, pounces, always misses) | Reality only |
| `habitats/pigeon_flock` | Grey **doves** (procedural `RuinCrow`, `plumage = dove`, coo) | Both (moonlit in Mirror) |
| `habitats/alpaca_herd`, `raccoon_family`, `rat_colony` | Alpacas (kick if snuck up on), raccoon scavengers, rats | Both (moonlit in Mirror) |
| `habitats/spectral_stags`, `spirit_fox` | Ghost stag / guide fox (dissolve into motes if rushed; fox runs ahead and waits) | Mirror only |
| `vegetation/olive_grove`, `cypress_stand`, `shrubland`, `fern_hollow` | Broadleaf trees, pines, bushes, ferns | Both (luminous foliage in Mirror) |
| `vegetation/wildflower_meadow` | Flower clumps, clover, grass | Flowers/clover Reality only |
| `vegetation/spirit_grove` | Spirit ferns, crystal mushrooms, ghost pines | Mirror only |

**Placement intent** (map team): trees, herds, foxes and meadows belong in open-air or garden spaces, not inside halls; inside fortifications use doves, crows, rats, wisps and small wall/crack growth.

### 5.2 LIVE placement: `AmbientLife` (`scenes/environment/ambient_life.tscn`, `AmbientLifeLayout`)
Instanced in `scenes/main/main.tscn` as `Main/AmbientLife` (delete the node to remove all ambient life). Built at runtime; never adds collision to the route.

| Zone | What lives there (Reality) | Mirror |
| :--- | :--- | :--- |
| **Cliff Garden** — new sunken terrace (floor Y `-1.5`, X `1..12`, Z `-45..-21` + wedge X `-1.5..1`) cradled between Causeway A and B; `realm_pbr` rock massif, sand-soil floor (layer 3 collider for creatures only), broken castle-brick kerb, marble fountain. Seen from both causeways + overlook; parapets keep the player out. | Olive grove (3), cypresses (3), grass carpet, wildflower meadow, hedges, fern corner, rocks, glow-blooms, spore pods; deer (3), fox, butterflies, fountain doves, rock lizards | Spirit grove (ferns, crystal mushrooms, ghost pine), ghost stags, moths, wisps |
| Start terrace / overlook / forecourt | Wispy grass at parapet feet & corners, crows on braziers + obelisk, doves on the forecourt flagstones, lizards by braziers | Spirit fox guide on the overlook, wisps, spirit ferns |
| Hall of Echoes | Ivy on arcade piers (corners only), weeds/ferns in corners, rats by braziers (cover), doves | Moths |
| Rampart / Aqueduct / Clock tower | Ivy on the curtain wall (clear of the Z 53 banner), wispy grass at the balustrade, lizards, sunset butterflies; colonnade-base growth, doves, rats | Wisps under the oculus |
| Esplanade / Colosseum / Summit | Lizards + edge grass; ivy & weeds at the podium wall, doves on the sand, crows on the stands; summit wildflowers, butterflies, lizards | Arena wisps, summit spirit ferns |

Perf (RTX 3070, 1080p, steady state, without -> with): Colosseum 78 -> 68 FPS, Hall 77 -> 67, Garden view 68 -> 56, Forecourt 66 -> 56. Cost is mostly draw calls from multi-part procedural birds / dense small plants; knobs = habitat `count`, patch `count`, creature `lod_distance`.
