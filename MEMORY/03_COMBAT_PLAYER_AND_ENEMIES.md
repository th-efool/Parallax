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
- **Locomotion** (game-feel pass, `feature/game-feel-combat`):
  - Run **`6.0 m/s`**, momentum ramps to **`7.6 m/s`** after ~`1.1 s` of held direction (no button, no stamina); sharp reversal at speed = skid (resets ramp, dust).
  - Accel `46`, friction `40`, air accel `20`; turning against momentum uses friction-strength accel so direction changes snap.
  - Jump `7.8` impulse (apex height unchanged ~`1.9 m`): early release = `2.3x` gravity (short hop), apex hang `0.55x` while held, fall `1.75x`, max fall `26 m/s`. Jump buffer `0.13 s`, coyote `0.12 s`. Horizontal reach ≈ old (faster run compensates faster fall) so authored gaps still clear.
  - Dodge `0.42 s` (burst `1.3x` then eased into a run), i-frames `0.03–0.29 s`, cooldown `0.14 s`. **One air-dash per airtime** (holds altitude for 60%).
  - **Perfect dodge**: an enemy hit landing inside i-frames (`Hurtbox3D.hit_blocked_invulnerable`) → `0.3x` slow-mo for `0.55 s` real time + ghosts.
  - Camera (`PlayerFeelRig`): trauma shake (real-time, respects `camera_shake_intensity`), FOV spring kicks, sprint FOV `+7°` & arm `+0.45 m`, loose vertical lag in air.

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

**Phase-based attacks** (`PlayerController.ATTACK_DEFS`): every swing is WINDUP → ACTIVE → RECOVERY. The hitbox is live only during ACTIVE, and a shape sweep (arc / line / 360° ring) runs each active frame in addition to Area3D overlaps.

| Attack | Clip (time-remapped) | Windup / Active / Recovery (s) | Shape | Hit-stop |
| :--- | :--- | :--- | :--- | :--- |
| `light_1` | `1H_Melee_Attack_Slice_Horizontal` | `0.11 / 0.10 / 0.26` | 120° arc, 2.35 m | 0.05 |
| `light_2` | `1H_Melee_Attack_Slice_Diagonal` | `0.11 / 0.10 / 0.26` | 120° arc | 0.055 |
| `light_3` finisher | `1H_Melee_Attack_Chop` | `0.17 / 0.10 / 0.36` | 90° arc + ground crack | 0.09 |
| `heavy` Cleave (neutral) | `2H_Melee_Attack_Chop` | `0.30 / 0.12 / 0.42` | 70° arc + 4.2 m line | 0.12 |
| `heavy_spin` Whirlwind (RMB mid-chain) | `2H_Melee_Attack_Spin` | `0.15 / 0.30 / 0.34` | 360°, 2.8 m | 0.085 |

- **Input buffer** `0.24 s`; attacks chain in the recovery cancel window (`cancel` fraction of recovery); dodge cancels anything except ACTIVE frames; late-dodge (`>60%`) can chain straight into an attack.
- **Magnetism**: target within `4.8 m` and ±75° of stick (or facing); stick neutral falls back to any enemy within `2.8 m`. Lunge closes to `1.25 m`, tracks target through windup.
- **Shield deflect**: a fully blocked light swing calls `on_attack_deflected()` → blade bounces (forced recovery, knock-back, sparks, clang).
- Kill = extra hit-stop; killing the last nearby enemy = `0.22x` kill-cam slow-mo for `0.42 s`.
- Contact times were measured from each clip's `hand.r` peak speed (GLB FK), so remapped clips whip exactly on the active frames.

### 2.1b Combat Game Feel (Claude Pass A, partly superseded by the game-feel pass above — `PlayerController` "Game Feel" export group)
`PlayerController` listens to its own `SwordHitbox.hit_landed` and drives all hit feedback; `CombatVFX` (`scripts/core/combat_vfx.gd`, static, preload it) builds particles/ribbons.

| Feature | Trigger | Value |
| :--- | :--- | :--- |
| **Hit-stop** (`trigger_hit_stop()`, QA-A02) | *Superseded* | Now handled by `GameFeel` / `PlayerFeelRig` / `SwordTrail` (see table above). `add_camera_trauma()` / `trigger_hit_stop()` remain as compatibility wrappers on `PlayerController`. |
| **Trauma camera shake** (`add_camera_trauma()`, QA-A03) | *Superseded* | Now handled by `GameFeel` / `PlayerFeelRig` / `SwordTrail` (see table above). `add_camera_trauma()` / `trigger_hit_stop()` remain as compatibility wrappers on `PlayerController`. |
| **Player stagger** (`State.STAGGER`, QA-A04) | *Superseded* | Now handled by `GameFeel` / `PlayerFeelRig` / `SwordTrail` (see table above). `add_camera_trauma()` / `trigger_hit_stop()` remain as compatibility wrappers on `PlayerController`. |
| **Slash ribbon** | *Superseded* | Now handled by `GameFeel` / `PlayerFeelRig` / `SwordTrail` (see table above). `add_camera_trauma()` / `trigger_hit_stop()` remain as compatibility wrappers on `PlayerController`. |
| **Impact burst** | Any accepted sword hit; Shielded Guard deflect; Pillar collapse. | One-shot `GPUParticles3D`: amber sparks (Reality / parries) or cobalt glass shards (Mirror / Warden rune strikes) + `0.14 s` omni flash; self-frees. |
| **Wind-up telegraph** | `EnemyAI.start_windup()` | Additive red `material_overlay` on all `VisualRoot` meshes + red `TelegraphGlow` omni at eye height, ramping over the wind-up; fast falloff on strike; cleared on stagger/reset/death. |
| **Warden chest rune** | `_enter_recover()` in Phase 1 (`is_chest_rune_exposed`). | Cobalt `ChestRuneGlow` (sphere + omni) on `VisualRoot`: bright pulsing in Mirror, faint hint in Reality; re-evaluated in `on_realm_changed()`. |

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
    - Directly vulnerable in Reality to all player attacks (Light, Heavy, Landing). Uses faster cleave combos & shorter lunge recovery. *Implemented (Claude Pass C)*: wind-up `0.65 s`, recovery `0.85 s`, and every Cleave **chains** straight into a Lunge with a `0.45 s` (still red-telegraphed) wind-up, skipping recovery (`phase2_chain_windup`, `phase2_chain_enabled`). At `0 HP`: death animation, exit gate lifts, run timer stops, Results sequence begins.

### 3.3 Squad Tactics, Hit Reactions & Gore (`SquadCoordinator`, `EnemyAI`, `EnemyBase`)
- **Attack tokens**: max `2` simultaneous attackers (1 if squad < 3), `0.42 s` minimum gap between attack starts. Token priority = time waited + up to `+1.2 s` for standing behind the player (pincer). Released on recovery / stagger / death.
- **Holding ring**: non-token enemies circle at `attack_range + ring_margin (1.7)` with angular spacing (62°), drift toward the player's flank, back off if crowding, separation steering, random orbit flips.
- **Alert**: first spotter taunts `0.55 s` and alerts every idle ally in the same `encounter_id` or within `14 m`.
- **Evade**: uncommitted enemies within `3.4 m` in the player's front cone may side-step a telegraphed swing (`evade_skill`: Skeleton `0.45`, Phantom `0.7`, Shielded `0.15`, Warden `0`).
- **Flinch & poise**: light hits flinch (`0.26 s`) unless ATTACK or past 50% of WINDUP (hyper-armour). After `max_flinch_chain` (2; Shielded 1) flinches → `1.6 s` poise; `70%` chance of an immediate fast counter-swing. Warden never flinches on lights.
- **Enrage**: last survivor of a squad of ≥2 moves `1.25x`, winds up `0.8x`, recovers `0.7x`.
- **Every hit**: knock-back (`knockback_scale`: Warden `0.15`, Shielded `0.55`, Phantom `1.3`), hit-lean spring on `ModelRoot`, white flash overlay, directional blood spray + floor splat decals, wound drip below 55% HP. Spectral (Mirror-only) enemies bleed emissive cyan ichor.
- **Death**: `GoreFX.dismember()` splits the rig into per-bone physics gibs posed exactly as the killing frame (meshes grouped by dominant skin bone; helmets/weapons follow their bone attachment), blood fountain + pool, gib bleed trails; gibs fade after ~7 s (cap 80, decals cap 48).
- **Loadouts** (`CharacterLoadout`): Knight player = `1H_Sword + Badge_Shield`; Knight Shielded Guard = `1H_Sword + Rectangle_Shield`; Barbarian Warden = `2H_Axe`; Skeleton Warrior borrows Barbarian `1H_Axe` + Knight `Round_Shield`; Skeleton Rogue borrows Knight `1H_Sword` + offhand.

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

> **Live code values (audited Claude Pass C, 2026-11-16)** — `_init()` of each enemy script: Skeleton `100 HP / 15 dmg / 0.55 s windup / 0.80 s rec`; Phantom `80 / 20 / 0.65 / 1.00`; Shielded Guard `250 / 20 / 0.65 / 0.90`; Warden P1 Cleave `20` / Lunge `25`, windup `0.90`, recovery `1.40`; P2 windup `0.65`, recovery `0.85`, chain windup `0.45`. Player (`player_controller.gd` export defaults; `player.tscn` doesn't override them) still uses dodge `0.48 s` / i-frames `0.24 s` and run speed `5.5`, which differ from the `0.55/0.18` and `4.5` baselines above — intentional Pass 5 feel tuning, not changed here.

### 4.2 Appendix B — Locked Glossary
- **Reality**: Warm physical limestone/amber state of the arena.
- **Mirror**: Cool spectral cobalt/moonlight counterpart state.
- **Realm Shift (`Q`)**: Instant toggle preserving player world transform.
- **Realm-Reactive Actor**: Node whose mesh, collision, and AI respond to Reality/Mirror via `RealmReactive`.
- **Mirror Kill**: Killing any enemy while `MIRROR` is active (`+200` bonus, combo-multiplied).
- **Environmental Kill**: Killing blow dealt by authored hazard such as Cracked Pillar (`+250` bonus, combo-multiplied).
- **Registered Geometry**: Reality & Mirror counterparts aligned to identical world-space landmarks.
