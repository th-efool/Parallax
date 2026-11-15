# PARALLAX — Controls, Player Combat, Breakables, Enemies & Tuning

> Encapsulates GDD Sections 3, 5, 6, Appendix A (Tuning Sheet), and Appendix B (Terminology).

---

## 1. Controls, Camera & Locomotion (GDD Section 3)

### 1.1 Input Map (`project.godot`)
| Action Name | Binding | Behavior Rule |
| :--- | :--- | :--- |
| `move_forward` / `move_back` / `move_left` / `move_right` | `W / S / A / D` | Character moves relative to camera yaw projected onto XZ plane. |
| *(Mouse)* | Mouse Motion | Camera yaw (unlimited) & pitch (clamped e.g. `-45°` to `+60°` to avoid floor/sky lock). Sensitivity + Invert-Y configurable. |
| `light_attack` | `Left Mouse Button` | 3-hit sword combo (`25 / 25 / 35` dmg); combo window resets after pause. |
| `heavy_attack` | `Right Mouse Button` | Committed slower strike (`60` dmg); shatters marked breakables & staggers exposed enemies. |
| `dodge` / `jump` | `Space` (plus `Shift` on `dodge`) | Contextual Jump (when stationary, in a jump zone, or when forward-downward floor probes detect a gap or raised dais step) vs Directional Ground Dodge (`0.55 s` total, `0.18 s` i-frames, `0.20 s` cooldown). `start_dodge()` zeroes any upward velocity so Jump and Dodge never double-fire on the same frame. |
| `dimension_shift` | `Q` | Toggle Reality <-> Mirror (`0.60 s` cooldown; subject to safe-floor & overlap check). |
| `landing_attack` | `F` | **Airborne only**: triggers committed downward plunge; spawns single `2.2 m` radial shockwave (`60` dmg) on ground impact. No effect on ground. |
| `interact` | `E` | Contextual interaction with Mirror Switch, Bridge Anchor, and Mechanism/Gates when in prompt range. |
| `pause` | `Escape` | Opens Pause menu and pauses `SceneTree` + run timer. |

### 1.2 Camera & Movement Targets
- **Camera**: Third-person follow camera positioned behind and slightly right-of-shoulder (`SpringArm3D` with collision push-in so walls never clip view).
  - **FOV**: `60°–70°` (start around `65°`).
  - **Follow Distance**: `350–450 cm` (`3.5 m – 4.5 m`). Player remains visible head-to-toe during combat and gap jumps.
- **Locomotion**:
  - Single default run speed: **`450 cm/s` (`4.5 m/s`)** — no sprint toggle needed for 1-week build.
  - Jump impulse: Tuned to reliably clear the `3.0 m` Entrance stepping-stone gaps and jump onto the `Mechanism Chamber` dais/weight.
  - Ground dodge: `0.55 s` duration with `~0.18 s` invulnerability frames centered in the dodge (not full animation).

---

## 2. Player Combat, Combo & Authored Breakables (GDD Section 5)

### 2.1 Player Attack Table
| Verb | Input | Damage / Radius | Gameplay Purpose |
| :--- | :--- | :--- | :--- |
| **Light Combo (3-Hit)** | `LMB` | `25` -> `25` -> `35` | Reliable DPS and combo building; short recovery; forward micro-step. |
| **Heavy Attack** | `RMB` | `60` | Slow startup + recovery; breaks authored weak props; staggers Shielded Guard echo (Mirror) & punishes Warden recovery. |
| **Dodge** | `Space` | `0 dmg` / `0.55 s` (`0.18 s` i-frames) | Evades enemy swings/cleaves/lunges. Survival reward only (no separate dodge score). |
| **Landing Attack** | `F` (in air) | `60` / `2.2 m` radius | Single radial pulse on ground contact; area damage + knockback + triggers Mechanism Chamber Mirror weight. Never auto-triggers on normal jump landing. |

> **Hitbox Contract**: Track a `hit_targets_this_swing: Array[Node]` per attack activation so a single swing or shockwave damages each target **at most once** (no per-physics-frame damage ticks).

### 2.2 Combo System
- Increment hit count on any **successful** Light or Heavy hit against an active enemy.
- Combo timer: **`4.0 s`** after last successful hit (misses do NOT increment hits or refresh timer).
- Multipliers: `0–2` hits = **x1**, `3–5` hits = **x2**, `6+` hits = **x3**.
- Resets to `x1` on timeout (`4.0 s`) OR when player takes enemy/hazard damage. **Realm shift (`Q`) preserves combo.**

### 2.3 Authored Breakables (One-Week Deterministic Pattern)
Do NOT rely on runtime physics simulation for gameplay outcomes. Use authored `AnimationPlayer` animations + explicit single-tick `Area3D` / `ShapeCast` volumes + optional non-colliding `RigidBody3D` cosmetic rubble afterward. Each break event fires **at most once** (idempotent until section reset).

| Breakable | Stage | Trigger | Outcome & Safety |
| :--- | :--- | :--- | :--- |
| **Cracked Central Pillar** | 02. Hall of Echoes `(0, 0, 20)` | Heavy attack (`RMB`) on glowing fracture point. | `0.6 s` warning telegraph (dust + fracture glow) -> falls along fixed **northward** fall zone (`2.5 m` radius). Deals **`150` dmg** to enemies (lethal to Skeleton & Phantom, awards **+250 Environmental Kill**) and **`40` dmg** to player if inside fall zone. |
| **Weak Stone Support** | 03. Collapsed Gallery `(0, 0, 51)` | Heavy attack (`RMB`) on fracture point. | Low stone barrier collapses cleanly, uncovering the Bridge Anchor Switch alcove behind it. |
| **Central Mirror Plane** | 05. Execution Arena `X = 0` | Scripted at **Warden <= 500 HP (50%)**. | Plays `<= 2.0 s` shatter sequence; dissolves Mirror split; merges realms; locks `Q`. |

---

## 3. Enemies & Boss Encounter (GDD Section 6)

### 3.1 Enemy Roster Overview
| Enemy | Count | Realm Affinity | HP | Damage | Core Counterplay |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Skeleton Guard** | 2 | `REALITY_ONLY` | `100` | `15` (melee) | Standard combat in Reality or bait into Cracked Pillar fall zone. |
| **Phantom Twin** | 2 | `MIRROR_ONLY` | `80` | `20` (lunge) | Shift to Mirror; dodge blue-telegraphed lunge; slay in Mirror (+200 Mirror Kill). |
| **Shielded Guard** | 1 | `BOTH_STATEFUL` | `250` | `20` (shield bash) | Frontal shield blocks light hits & absorbs heavy in Reality. Shift to Mirror: reflection is shieldless -> Heavy staggers & kills. |
| **The Warden (Boss)** | 1 | `BOTH_STATEFUL` -> Merged | `1,000` (shared) | `20` Cleave / `25` Lunge | Phase 1: Dodge in Reality, shift to Mirror during `1.4 s` recovery chest-rune opening. Phase 2 (`<=500 HP`): Realms merge, dodge faster chain & kill in Reality. |

### 3.2 Behavioral Details
- **Skeleton Guard** (`Hall of Echoes`):
  - Acquires player within `~9.0 m`, closes distance directly/via nav, visible melee wind-up (`15 dmg`), `~0.8 s` post-attack recovery.
  - Hidden, non-colliding, AI paused whenever `current_realm == MIRROR`.
- **Phantom Twin** (`Hall of Echoes`):
  - Active only in `MIRROR`. `9.0 m` detection, floating approach, strong blue wind-up glow before forward lunge (`20 dmg`), `~1.0 s` recovery.
  - Killing in Mirror awards base `+100` + `+200 Mirror Kill` (combo multiplied).
  - *Pacing cue*: Hall starts with 2 Skeletons in Reality; defeating 1st Skeleton pulses a subtle Mirror hint reminding player of Phantom Twins (never locks `Q`).
- **Shielded Guard** (`Collapsed Gallery`, after anchor):
  - Same world transform in both realms.
  - In **Reality**: raised frontal shield deflects light attacks cleanly (`0` or minimal chip + metallic spark) and heavily mitigates heavy attacks without staggering. Attacks via shoulder-pullback shield bash (`20 dmg`).
  - In **Mirror**: shield vanishes; vulnerable spectral torso can be staggered and burst down by Heavy (`60 dmg`) + Light combo.
  - Defeat opens Gallery exit gate (player must have already repaired Reality bridge via Anchor to pass safely if returning to Reality).
- **The Warden** (`Execution Arena`, Phase 1 & Phase 2):
  - **Shared 1,000 HP pool** across Reality and Mirror.
  - **Phase 1 (`1000 -> 501 HP`)**:
    1. Armored in Reality (heavily reduces direct Reality hits so shifting is clearly rewarded/taught).
    2. Selects **Cleave** (short frontal arc, `20 dmg`) or **Lunge** (`5.0 m` line, `25 dmg`).
    3. Plays clear **`0.8–1.0 s` wind-up telegraph** (audio sting + distinct body pose) visible in the active realm so danger is always fair.
    4. Executes strike -> enters **`1.4 s` recovery window** where Mirror reflection exposes glowing chest rune.
    5. Player shifts to Mirror (`Q`) and punishes exposed echo (Heavy / Light combo) -> staggers Warden & drains shared HP -> returns to guarded loop. Must never soft-lock if player misses a window.
  - **Phase 2 Transition (`HP <= 500`)**:
    - Stops current attack immediately -> plays `<= 2.0 s` Mirror Plane shatter sequence -> **one-way transition**.
    - HUD banner/chip changes to **`REALMS MERGED`**; `Q` is locked/disabled (`shift_locked = true`).
  - **Phase 2 (`500 -> 0 HP`)**:
    - Directly vulnerable in Reality to all player attacks (Light, Heavy, Landing). Uses faster cleave combos & shorter lunge recovery. At `0 HP`: death animation, exit gate lifts, run timer stops, Results sequence begins.

---

## 4. Appendix A: Initial Tuning Sheet & Appendix B: Terminology

### 4.1 Appendix A — Baseline Numeric Values (Playtest & Tune Log Target)
| Parameter | Baseline Value | Tune Trigger Condition |
| :--- | :--- | :--- |
| Player Max Health | `100` | First-run deaths too frequent or trivial. |
| Player Run Speed | `4.5 m/s` (`450 cm/s`) | Traversal feels sluggish or uncontrollable on stones/bridge. |
| Dodge Duration / i-frames | `0.55 s` / `0.18 s` | Player cannot reliably dodge Warden Cleave/Lunge. |
| Light Combo Damage | `25 / 25 / 35` | Standard TTK too fast/slow for 10–15 min target. |
| Heavy / Landing Damage | `60` / `60` (`2.2 m` radius) | Heavy feels unrewarding or Landing slam dominates melee. |
| Shift Cooldown / Transition | `0.60 s` / `0.15–0.25 s` | Flicker spam vs sluggish feeling during combat weaving. |
| Combo Timeout | `4.0 s` (x2 @ 3, x3 @ 6) | Impossible to keep chain across short movement/shifts. |
| Skeleton HP / Dmg | `100` / `15` (`0.8 s` rec) | Basic duel lasts outside ~10–20s. |
| Phantom HP / Dmg | `80` / `20` (`1.0 s` rec) | Mirror combat feels identical or unfair. |
| Shielded Guard HP / Dmg | `250` / `20` | Encounter drags or Reality chip too easy to brute-force. |
| Warden HP / Recovery Window | `1,000` / `1.4 s` | Boss <2 min or >6 min; Phase 1 opening too tight to shift+strike. |
| Pillar Fall Damage / Warning | `150` Enemy / `40` Player (`2.5 m` radius, `0.6 s` warn) | Enemies miss zone or player unfairly clipped. |

### 4.2 Appendix B — Locked Glossary
- **Reality**: Warm physical limestone/amber state of the arena.
- **Mirror**: Cool spectral cobalt/moonlight counterpart state.
- **Realm Shift (`Q`)**: Instant toggle preserving player world transform.
- **Realm-Reactive Actor**: Node whose mesh, collision, and AI respond to Reality/Mirror via `RealmReactive`.
- **Mirror Kill**: Killing any enemy while `MIRROR` is active (`+200` bonus, combo-multiplied).
- **Environmental Kill**: Killing blow dealt by authored hazard such as Cracked Pillar (`+250` bonus, combo-multiplied).
- **Registered Geometry**: Reality & Mirror counterparts aligned to identical world-space landmarks.
