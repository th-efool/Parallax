# PARALLAX — Game Design Overview, Narrative, Scope & Schedule (GDD v1.1)

> *"Same arena. Different rules."*
> A single-player, third-person action game built around one decisive verb: **SHIFT**.

---

## 1. Product Definition & Design Pillars

### 1.1 Metadata Snapshot
| Field | Value |
| :--- | :--- |
| **Project Title** | PARALLAX: A Mirror-Realm Combat Game |
| **GDD Version / Date** | Version 1.1 — 16 November 2026 |
| **Genre / Camera** | Single-player third-person action / melee combat / puzzle traversal (over-right-shoulder follow camera) |
| **Target Build** | Windows 64-bit executable; Godot 4.7+ (Forward+) |
| **Session Length** | ~10–15 minutes for a first clear |
| **Content Scope** | One continuous level, 5 connected sections, 1 weapon (sword), 7 enemy classes (incl. 1 boss; 3 data-driven archetypes added 2026-11-17), 3-ally AI squad (data-driven, 2026-11-17) |
| **Online Dependency** | **Optional only** (since 2026-11-17): the Squad AI plugin may call an AI API (Gemini preferred, OpenAI optional) when the player supplies a key. The game is 100% playable offline — typed squad orders fall back to a local keyword parser. Leaderboard, saves and settings stay local `ConfigFile`s under `user://`. |
| **Design Sources** | User-provided PARALLAX concept sheet (`reference_images/00_concept_sheet_overview.jpg`), working Mirrorrealm Combat notes, IGDC 2023 Low-Prep Game-Dev Challenge brief |

> **Core Design Rule**: When a feature does not reinforce **shifting**, **combat readability**, **traversal**, or the **score chase**, it is outside the one-week build unless required for a complete start-to-finish game.

### 1.2 Product Snapshot
- **Player fantasy**: Outthink a hostile arena by changing which version of the world is real.
- **Primary mechanic**: Instant dimension shift (`Q`) between **Reality** and **Mirror**.
- **Secondary verbs**: Move (`WASD`), jump/dodge (`Space`), light attack (`LMB`), heavy attack (`RMB`), landing attack (`F` while airborne), interact (`E`).
- **Target learning curve**:
  1. Stage 01 (Minute 1): Understand realm toggle for traversal.
  2. Stage 02: Use shift deliberately in combat + environmental kill.
  3. Stage 03: Depend on shift for bridge traversal & cross-realm repair + shieldless echo combat.
  4. Stage 04: Combine Mirror state + airborne Landing Attack (`F`) on a weight/plate puzzle.
  5. Stage 05: Boss fight examines previously taught verbs—never introduces an untaught subsystem.

### 1.3 Five Design Pillars
| Pillar | Player-Facing Rule | Design Consequence |
| :--- | :--- | :--- |
| **One arena, two rulesets** | Reality and Mirror occupy the same registered space. | Player learns one layout, then re-reads it under changed collision, visibility, and enemy rules. |
| **Shift must matter** | A shift solves an immediate combat or traversal problem. | Every major encounter requires at least one meaningful realm decision. |
| **Readable danger** | Enemy wind-ups, realm-only surfaces, and breakable hazards are clearly telegraphed. | No damage, death, or puzzle failure comes from an invisible or ambiguous rule. |
| **Short, complete run** | Level starts, teaches, escalates, tests, and resolves the mechanic. | No progression tree, optional hub, branching quest, or extra weapon. |
| **Score rewards skill** | Fast, clean, and mechanically clever play scores better. | Leaderboard scoring is deterministic and entirely local. |

---

## 2. Premise & Narrative Arc

### 2.1 Premise
The protagonist is a condemned warrior/gladiator placed inside an experimental mirror-colosseum bound to a second version of itself. Its keeper, **The Warden**, prevents escape by controlling which version of the arena is active. The mirror is not merely a visual reflection—it is a second ruleset holding routes, spectral enemies, and hidden weaknesses absent from Reality.

### 2.2 Narrative Beats
| Beat | What the Player Sees / Learns | Narrative Function |
| :--- | :--- | :--- |
| **1. Opening** | Warrior wakes in the Entry Vestibule. Shattered mirror & sealed north gate establish the curse. | Establish confinement and mirror motif without a cutscene. |
| **2. Discovery** | First shift reveals stepping stones missing in Reality. | Teach that perception and traversal depend on realm. |
| **3. Escalation** | Skeleton Guards (Reality) and Phantom Twins (Mirror) force mid-fight shifting; cracked central pillar crushes foes. | Show that Mirror changes combat rules, not just color grading. |
| **4. Understanding** | Broken Reality bridge is whole in Mirror; far-side anchor switch permanently repairs the Reality bridge. | Prove actions in one realm can permanently alter the other. |
| **5. Mastery** | Mechanism Chamber requires jumping from dais + airborne Landing Attack (`F`) onto suspended Mirror weight over pressure plate. | Recombine traversal and combat verbs into a compact puzzle. |
| **6. Confrontation** | Warden exposes a vulnerable Mirror echo during attack recovery. At 50% HP, mirror plane shatters and realms merge. | Test mastery of shifting, then strip away the split for a pure final exchange. |
| **7. Resolution** | Mirror plane shatters; north exit gate rises; daylight floods the colosseum; results and leaderboard appear. | Deliver a clean ending and replay motivation. |

### 2.3 Opening Overlay & Ending Copy
- **Opening text** (displayed over gameplay or brief static reveal <= 5 seconds, immediately dismissible; no voiceover):
  > *"They built a mirror to preserve champions. It learned to preserve their deaths."*
- **Ending sequence**: On Warden HP = 0, mirror plane fractures top-to-bottom, Mirror-only objects dissolve, arena settles into Reality, north exit gate lifts into daylight, player walks forward (or ending beat plays) -> fades to Results screen with score, time, rank, personal best, and local Top 5 leaderboard.

---

## 3. IGDC 2023 Low-Prep Brief Alignment

PARALLAX satisfies all five competition themes at bounded scope:

| Brief Theme | PARALLAX Implementation |
| :--- | :--- |
| **Everything's breakable** | 3 authored break events: Hall of Echoes cracked central pillar, Collapsed Gallery weak stone support, Execution Arena central mirror plane. |
| **Landing on things** | Dedicated airborne Landing Attack (`F`) shockwave + Mechanism Chamber weight-drop puzzle. |
| **Misdirection** | Routes, enemies, and shields hidden/present depending on realm. |
| **Symmetry** | Reality and Mirror share registered spatial coordinates and landmarks with inverted visual/combat rules. |
| **Puzzle** | Entry stepping stones, Gallery cross-realm bridge anchor, Mechanism weight/plate. |

---

## 4. Seven-Day Production Schedule & Critical Dependencies

**Production Order Lock (Never Violate):**
1. Do not build all 5 rooms before proving one safe `Q` shift between two floor states.
2. Do not build The Warden before player attack, hit reaction, and `apply_damage()` pipeline are rock solid.
3. Do not polish VFX/shaders before the level is completable from Title to Results.
4. Use **one shared `HUD.tscn`** for all rooms—never build per-room HUDs.
5. Reserve Day 7 strictly for packaging and bugfixes—no new mechanics on Day 7.

| Day | Focus | Tasks | End-of-Day Acceptance |
| :--- | :--- | :--- | :--- |
| **Day 1** | Player + Realm Foundation | Project/map setup, third-person movement, right-shoulder camera, sword placeholder, `Q` shift, `RealmManager`, 1 test floor pair. | Player moves & attacks; `Q` switches active geometry without teleporting; unsafe shift rejected. |
| **Day 2** | Combat Foundation | Light 3-hit combo, Heavy, Dodge, Landing attack, damage interface, Skeleton Guard AI, Player Health HUD. | One complete greybox fight; damage, death, and hit reactions reliable. |
| **Day 3** | Hall of Echoes | Room blockout, 2 Skeletons, 2 Phantom Twins, cracked pillar break + hazard, combat gates, score/combo. | Hall completable end-to-end with realm-specific enemies & environmental kill. |
| **Day 4** | Gallery + Mechanism | Broken/spectral bridge, weak support, anchor repair, Shielded Guard, Mechanism weight/plate landing puzzle. | Player traverses both puzzles without falling through world or soft-locking. |
| **Day 5** | Warden + Complete Route | Entry Vestibule, Execution Arena, Warden Phase 1 & 2, boss HUD, checkpoints, ending gate. | Full start-to-finish run playable from Title to Results. |
| **Day 6** | UI + Scoring + Audio | Finalize shared HUD, Pause/Results/Leaderboard/Options menus, time bonus, ranks, `ConfigFile`, SFX/music/VFX pass. | Scores persist across restarts; Top 5 sorts correctly; HUD consistent everywhere. |
| **Day 7** | QA + Package | Tune balance from playtests, fix critical bugs, verify Windows 64-bit export on a clean second machine, record <2 min demo / <10 slide deck. | Packaged `.exe` + data launches, completes, saves leaderboard cleanly. |

---

## 5. QA Test Matrix, Risk Register & Definition of Done

### 5.1 Functional Test Matrix (Must Pass Before Release)
| Area | Test Case | Pass Condition |
| :--- | :--- | :--- |
| Realm shift | Shift repeatedly on stable shared floor. | Player transform unchanged; only realm-reactive actors toggle. |
| Shift safety | Press `Q` while standing over a surface missing in destination realm. | Shift rejected with amber/red HUD pulse + sound; no teleport or fall. |
| Inactive enemy | Observe enemy in its inactive realm. | Invisible, non-colliding, no AI ticks, neither deals nor takes damage. |
| Combat | Perform Light combo, Heavy, Dodge, Landing attack. | Damage applies **once per hit**; consistent recovery; no multi-frame overlap ticks. |
| Breakable pillar | Heavy attack cracked pillar with enemy in fall zone. | Single collapse animation; 150 enemy dmg applied once; +250 Environmental Kill once. |
| Hall gate | Kill all 4 Hall enemies in any order. | Exit gate opens once; encounter no-hit check completes; checkpoint saved. |
| Gallery bridge | Cross in Mirror -> break support -> activate anchor -> shift back. | Reality bridge permanently repaired and supports player; no soft-lock. |
| Shielded Guard | Light attack in Reality, then attack echo in Mirror. | Reality shield blocks/reduces; Mirror echo staggers & takes full damage. |
| Mechanism puzzle | Miss `F` slam & retry, then hit weight target. | Miss has no destructive penalty; hit drops weight onto plate once and opens gate. |
| Warden Phase 1 | Dodge attack in Reality, shift on recovery, hit Mirror echo. | Chest rune opening is readable; shared HP decreases; staggers properly. |
| Warden Phase 2 | Cross 500 HP threshold. | Plane shatters once (<=2s); HUD displays `REALMS MERGED`; `Q` disabled; directly vulnerable in Reality. |
| Score & Leaderboard | Complete run, quit, relaunch game. | Awards & multipliers exact; Top 5 persists in `user://leaderboard.cfg` sorted Score desc, Time asc. |

### 5.2 Definition of Done
- Launches cleanly from Title -> playable Sections 01–05 in sequence -> Results -> Replay/Menu.
- Zero soft-locks, falling-through-world bugs, or stuck combat gates.
- Shared `HUD.tscn` renders identically in both realms without overlap/clipping at 1920x1080 and 1280x720.
- All third-party assets have verified licenses and attribution documented in `06_RESOURCES_AND_ASSET_CATALOG.md`.
- Clean Windows 64-bit packaged build tested on a second machine.

### 5.3 Risk Register
| Risk | Mitigation / Fallback |
| :--- | :--- |
| **Realm state bugs / soft-locks** | Single authoritative `RealmManager`; destination floor ray/shape query before committing shift; repair bridge before accepting Gallery return shift. |
| **AI complexity overrun** | Simple 6-state FSM; `NavigationAgent3D` only where room geometry requires; max 1–2 attacks per standard enemy. |
| **Physics debris instability** | Gameplay collapse uses authored `AnimationPlayer` transform + single Overlap/ShapeCast damage tick; cosmetic `RigidBody3D` debris has no gameplay collision. |
| **Boss complexity overrun** | Keep strictly 2 attacks in Phase 1 (Cleave, Lunge) and faster chain in Phase 2; no adds or extra hazards. |
| **UI drift** | Enforce single `HUD.tscn` instantiated in `Main.tscn`; data-driven signal bindings only. |

---

## 6. Scope Lock & Explicit Cut List

### Locked Quantities
- **Protagonists**: 1 | **Weapons**: 1 Sword | **Levels**: 1 Continuous Level (`5` Sections)
- **Standard Enemies**: 3 core classes (`Skeleton Guard`, `Phantom Twin`, `Shielded Guard`) + 3 data-driven archetypes (`Hollow Hexcaster`, `Grave Brute`, `Shade Stalker`, `res://data/enemies/`)
- **Allies**: 3 AI squad "Echoes" (`Brannoc`, `Sera`, `Ivo`, `res://data/allies/`) — a 4th needs only a new resource
- **Bosses**: 1 (`The Warden`, 2 phases) | **Breakables**: 3 authored events | **Leaderboard**: Local Top 5

### 6.1 Scope Change Record — 2026-11-17 (user-requested "Conversational Squad AI")
The user explicitly lifted two locks for this feature; everything else in this section still stands.
- **"No online services" → optional AI service.** `addons/parallax_squad_ai` may call Gemini (preferred, free tier) or any OpenAI-compatible endpoint for squad chat, speech-to-text and ally voices. Rules: (1) **API keys are never committed** — read from env vars, a gitignored `.env`, or `user://squad_ai.cfg` (the repo is public); (2) the game must stay fully playable with no key (offline keyword parser, canned voice lines); (3) API errors surface as in-game notifications, never crashes. No accounts, telemetry, cloud saves or online leaderboards.
- **"Single-player, no co-op" → AI companions.** A 3-ally AI squad fights beside the player (still single-player; no networked players). Voice acting remains cut — ally voices are optional runtime TTS.
- Enemy roster grew by 3 data-driven archetypes (user asked for "a few more enemy types").

### Explicitly Cut (DO NOT IMPLEMENT)
- Multiplayer, networked co-op, PvP, online leaderboards, cloud saves, accounts, telemetry. *(AI squad companions + optional AI API are allowed per §6.1.)*
- Multiple weapons, ranged weapons/bows/magic spells, parry mechanic, dedicated block button, stamina bar, inventory, loot, crafting, shops, XP, skill trees.
- Branching routes, hub worlds, side quests, secret rooms, second biome, procedural generation.
- Full systemic physics destruction of walls/props.
- Recorded voice acting, facial animation/lip sync, elaborate boss cutscenes. *(Optional runtime TTS ally voices are allowed per §6.1.)*
- Additional puzzle mechanics in Mechanism Chamber (strictly reuses airborne `F` landing attack + pressure plate).
