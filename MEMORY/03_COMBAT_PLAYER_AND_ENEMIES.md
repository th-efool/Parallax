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
| `dodge` / `jump` | `Space` (plus `Shift` on `dodge`) | Contextual Jump (when stationary, in a jump zone, or when forward-downward floor probes detect a gap or raised dais step) vs Directional Ground Dodge (`0.55 s` total, `0.18 s` i-frames, `2` charges, `0.70 s` cooldown). `start_dodge()` zeroes any upward velocity so Jump and Dodge never double-fire on the same frame. |
| `dimension_shift` | `Q` | Toggle Reality <-> Mirror (`0.60 s` cooldown; subject to safe-floor & overlap check). |
| `landing_attack` | `F` | Airborne: triggers committed downward plunge (`50` stamina) spawning single `2.2 m` radial shockwave (`60` dmg). Ground: leaps into plunge only when `stamina >= 50.0` and `_landing_recover_timer <= 0.0`. |
| `interact` | `E` | Contextual interaction with Mirror Switch, Bridge Anchor, and Mechanism/Gates when in prompt range. |
| `pause` | `Escape` | Opens Pause menu and pauses `SceneTree` + run timer. |
| `squad_chat` | `Enter` (+ keypad Enter) | Opens the squad chat bar (Enter sends, Esc closes). Gameplay input is locked while typing. Registered at runtime by `SquadCommsHUD`. |
| `push_to_talk` | `V` (hold) — or hold the on-screen mic button | Records a voice order (needs an API key); release to transcribe -> same path as chat. |
| `mark_enemy` | `T` / `MMB` | Aim-marks / unmarks an enemy up to `180 m` (`M1..M4`) & detects all foes within `18 m` of it (`SquadCommsHUD` -> `WorldIntel`). |
| `clear_marks` | `X` | Clears all active enemy marks & lingering detection zones. |
| `toggle_command_log` | `L` | Shows / hides the squad command-history log. |
| `cinematic_mode` | `F10` | Hide-all: HUD + enemy / ally overhead labels & mark pins. |

### 1.2 Camera & Movement Targets
- **Camera**: Third-person follow camera positioned behind and slightly right-of-shoulder (`SpringArm3D` with collision push-in so walls never clip view).
  - **FOV**: `60°–70°` (start around `65°`).
  - **Follow Distance**: `350–450 cm` (`3.5 m – 4.5 m`). Player remains visible head-to-toe during combat and gap jumps.
- **Locomotion** (game-feel pass, `feature/game-feel-combat`):
  - Run **`6.0 m/s`**, momentum ramps to **`7.6 m/s`** after ~`1.1 s` of held direction (no button, no stamina); sharp reversal at speed = skid (resets ramp, dust).
  - Accel `46`, friction `40`, air accel `20`; turning against momentum uses friction-strength accel so direction changes snap.
  - Jump `7.8` impulse (apex height unchanged ~`1.9 m`): early release = `2.3x` gravity (short hop), apex hang `0.55x` while held, fall `1.75x`, max fall `26 m/s`. Jump buffer `0.13 s`, coyote `0.12 s`. Horizontal reach ≈ old (faster run compensates faster fall) so authored gaps still clear.
  - Dodge `0.42 s` (burst `1.3x` then eased into a run), i-frames `0.03–0.29 s`, **2 stacked charges** (recharge `0.7 s`). Supports consecutive chained dodges past early i-frames (`t_norm > 0.45`). Execution attacks (`player_execution`) pierce ShieldedGuard block. **One air-dash per airtime** (holds altitude for 60%).
  - **Perfect dodge**: an enemy hit landing inside i-frames (`Hurtbox3D.hit_blocked_invulnerable`) → `0.3x` slow-mo for `0.55 s` real time + ghosts.
  - Camera (`PlayerFeelRig`): trauma shake (real-time, respects `camera_shake_intensity`), FOV spring kicks, sprint FOV `+7°` & arm `+0.45 m`, loose vertical lag in air.

---

## 2. Player Combat, Combo & Authored Breakables (GDD Section 5)

### 2.1 Player Attack Table
| Verb | Input | Damage / Radius | Gameplay Purpose |
| :--- | :--- | :--- | :--- |
| **Light Chain (5-Hit, 2026-11-17)** | `LMB` | `20` -> `22` -> `26` -> `30` -> `44` (FLOW ×1.15); pause-branch Rising Arc `30` | Five distinct moves; rhythm taps chain faster (FLOW); pausing mid-chain branches. Resets `0.9 s` after the last swing. |
| **Heavy Attack** | `RMB` | `60` | Slow startup + recovery; breaks authored weak props; staggers Shielded Guard echo (Mirror) & punishes Warden recovery. |
| **Dodge** | `Space` | `0 dmg` / `0.55 s` (`0.18 s` i-frames) | Evades enemy swings/cleaves/lunges. Survival reward only (no separate dodge score). |
| **Landing Attack** | `F` (in air) | `60` / `2.2 m` radius | Single radial pulse on ground contact; area damage + knockback + triggers Mechanism Chamber Mirror weight. Never auto-triggers on normal jump landing. |

> **Hitbox Contract**: Track a `hit_targets_this_swing: Array[Node]` per attack activation so a single swing or shockwave damages each target **at most once** (no per-physics-frame damage ticks).

**Phase-based attacks** (`PlayerController.ATTACK_DEFS`): every swing is WINDUP → ACTIVE → RECOVERY. The hitbox is live only during ACTIVE, and a shape sweep (arc / line / 360° ring) runs each active frame in addition to Area3D overlaps.

| Attack | Clip (time-remapped) | Windup / Active / Recovery (s) | Shape | Hit-stop |
| :--- | :--- | :--- | :--- | :--- |
| `light_1` SLICE | `1H_Melee_Attack_Slice_Horizontal` | `0.10 / 0.09 / 0.24`, cancel 0.18 | 120° arc, 2.35 m | 0.045 |
| `light_2` BACKHAND | `1H_Melee_Attack_Slice_Diagonal` | `0.09 / 0.09 / 0.24`, cancel 0.18 | 120° arc | 0.05 |
| `light_3` THRUST | `1H_Melee_Attack_Stab` | `0.08 / 0.08 / 0.26`, cancel 0.20 | 50° arc + 3.4 m line, 2.1 m lunge | 0.06 |
| `light_4` WHIRL | `2H_Melee_Attack_Spin` | `0.10 / 0.22 / 0.28`, cancel 0.25 | 360°, 2.6 m + ring | 0.06 |
| `light_5` SKYFALL (chain ender, always crits) | `1H_Melee_Attack_Chop` | `0.16 / 0.10 / 0.38`, cancel 0.42 | 100° arc + ground crack | 0.10 |
| `light_rise` RISING ARC (pause branch, heavy/stagger) | `2H_Melee_Attack_Slice` | `0.12 / 0.12 / 0.30` | 160° arc | 0.08 |
| `heavy` Cleave (neutral) | `2H_Melee_Attack_Chop` | `0.30 / 0.12 / 0.42` | 70° arc + 4.2 m line | 0.12 |
| `heavy_spin` Whirlwind (RMB mid-chain) | `2H_Melee_Attack_Spin` | `0.15 / 0.30 / 0.34` | 360°, 2.8 m | 0.085 |

- **FLOW (rhythm)**: a press during a light swing that lands in `[cancel − flow_window_early 0.10, cancel + flow_window_late 0.28]` **and is the only press during that swing** makes the next step FLOW: wind-up ×`0.62`, damage ×`1.15`, trail ×1.35, rising-pitch whoosh (+7 %/step) and an FOV punch. Mashing still chains through the buffer but never earns FLOW. `flow_streak` counts consecutive FLOW steps.
- **Pause branch**: in LOCOMOTION with the chain still open, waiting `pause_branch_delay 0.28 s` after a swing ends and then tapping plays `light_rise` (heavy, staggers); the chain then continues from where it was.
- **Chain HUD** (`scripts/ui/chain_counter.gd`, `ChainCounter`, in the shared HUD): roman step + move name, 5 pips, `FLOW ×n` or `BRANCH`; fades 1.1 s after the last swing. Reads `attack_started` timing keys `chain_step`, `flow`, `flow_streak`, `branch`, `display`.
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

### 2.2b Critical Hits & Finishers (2026-11-17)
- **Critical hit** (`PlayerController._try_open_finisher_window`): a non-killing sword hit by a chain ender (`light_5`, `heavy`, `heavy_spin` = defs with `finisher: true`) always crits; other light hits crit at `crit_chance_light = 0.20`, FLOW (on-rhythm) light hits at `crit_chance_flow = 0.35`. Deflected hits (`_was_deflected`) never crit, including chip hits on Reality shields. Cooldown `finisher_cooldown_sec = 2.5` after a finisher. Disabled entirely when the `finisher_window_enabled` setting is off (Options → Gameplay → "Critical Finisher Window").
- **Window**: `finisher_window_sec = 1.1` real seconds at `finisher_slowmo_scale = 0.35`; frame hitches > 50 ms are credited back. Opening the window clears pre-crit buffered inputs (`_consume_buffer()`); only inputs pressed after the window opens trigger finishers:
  | Input | Finisher (`ATTACK_DEFS`) | Damage | Shape / effect |
  | :--- | :--- | :--- | :--- |
  | `light_attack` (LMB) | `fin_rend` "REND" | 4 × 28 (blade re-armed 4× across a 0.48 s active phase, `multi: 4`) | 170° arc, reach 2.9 |
  | `heavy_attack` (RMB) | `fin_sunder` "SUNDER" | 120 (`source_type = "fin_sunder"`) | 360° reach 3.6, knockback 13, `STUNNED` knockdown (`1.6 s`, `×1.35` dmg), 8 radial ground cracks, light pillar, double shockwave |
  | `dodge` (Shift) | `fin_phantom` "PHANTOM STEP" | 95 | Blinks 1.5 m behind the target (active-realm wall + `LAYER_PLAYER_BLOCKER` ray + downward floor check; skips blink if no solid floor), cyan afterimage + streak, camera swings round |
  | `dimension_shift` (Q, buffer `"mirror"`) | `fin_mirror_break` "MIRROR BREAK" | 3 × 40 (`multi: 3`) | 360° reach 3.4 AoE, knockback 10, staggers; cyan/amber glass-shard bursts each tick. **Does not shift realm** inside the window |
  | `landing_attack` (F, buffer `"plunge"`) | `fin_execution` "EXECUTION" | 150 (`source_type = "player_execution"`) | Leap-chop 120° reach 3.0, crack 5.5; pierces shields and executes any target left at ≤ 35 % HP (`execute: 0.35`, gated on `source_type == "player_execution"`) outright (crimson starburst) |
- Finishers run as `State.HEAVY_ATTACK`, grant pausable scaled-time i-frames for 80% of their duration (`_finisher_invuln_timer`, cleared on abort/cancel), register combo hits in `Hitbox3D` (`player_execution` and `fin_*`), and score `+150 finisher` (combo-multiplied, `ScoreManager.POINTS_FINISHER`).
- Signals: `finisher_window_opened(duration, options)`, `finisher_window_closed(chosen)`, `finisher_executed(name)`. VFX in `scripts/player/finisher_fx.gd`; HUD prompt `scripts/ui/finisher_prompt.gd` (`FinisherPrompt`, auto-added under `HUD/RootControl`): 5 diamond plates with keycaps, a draining timer bar, a rotating gold lock-on reticle on `PlayerController.get_finisher_target()` (shows "EXECUTABLE" at ≤ 35 % HP), and a plain-language tutorial line for the first 2 windows of a session. Squad subtitles hide while the window is open.

### 2.3 Authored Breakables (One-Week Deterministic Pattern)
Do NOT rely on runtime physics simulation for gameplay outcomes. Use authored `AnimationPlayer` animations + explicit single-tick `Area3D` / `ShapeCast` volumes + optional non-colliding `RigidBody3D` cosmetic rubble afterward. Each break event fires **at most once** (idempotent until section reset), and collider toggles use `set_deferred()` cleanly inside physics flushes.

| Breakable | Stage | Trigger | Outcome & Safety |
| :--- | :--- | :--- | :--- |
| **Cracked Central Pillar** | 02. Hall of Echoes `(0, 0, 20)` | Heavy attack (`RMB`) on glowing fracture point. | `0.6 s` warning telegraph (dust + fracture glow) -> falls along fixed **northward** fall zone (`2.5 m` radius). Deals **`150` dmg** to enemies (lethal to Skeleton & Phantom, awards **+250 Environmental Kill**) and **`40` dmg** to player if inside fall zone. |
| **Weak Stone Support** | 03. Collapsed Gallery `(0, 0, 51)` | Heavy attack (`RMB`) on fracture point. | Low stone barrier collapses cleanly (`0.0 s` warning, deferred colliders), uncovering the Bridge Anchor Switch alcove behind it. |
| **Central Mirror Plane** | 05. Execution Arena `X = 0` | Scripted at **Warden Phase 2 transition** (`complete_break_now()`). | `trigger_break()` and player landing slams explicitly reject `CENTRAL_MIRROR_PLANE`. Plays `<= 2.0 s` shatter sequence; dissolves Mirror split; merges realms; locks `Q`. |

---

## 3. Enemies & Boss Encounter (GDD Section 6)

### 3.1 Enemy Roster Overview
| Enemy | Count | Realm Affinity | HP | Damage | Core Counterplay |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Skeleton Guard** | 2 | `BOTH_STATEFUL` (was REALITY_ONLY) | `100` | `21` (melee) | Standard combat in Reality or bait into Cracked Pillar fall zone. |
| **Phantom Twin** | 2 | `BOTH_STATEFUL` — fights ONLY in the Mirror (2026-11-18): immune, harmless and translucent in Reality; filtered from target resolution via `is_hittable_now()` | `80` | `28` (lunge) | Shift to Mirror; dodge blue-telegraphed lunge; slay in Mirror (+200 Mirror Kill). |
| **Shielded Guard** | 1 | `BOTH_STATEFUL` | `250` | `28` (shield bash) | Frontal shield blocks light hits & absorbs heavy in Reality. Shift to Mirror: reflection is shieldless -> Heavy staggers & kills. |
| **The Warden (Boss)** | 1 | `BOTH_STATEFUL` -> Merged | `1,000` (shared) | `20` Cleave / `25` Lunge | Phase 1: Dodge in Reality, shift to Mirror during `1.4 s` recovery chest-rune opening. Phase 2 (`<=500 HP`): Realms merge, dodge faster chain & kill in Reality. |
| **Hollow Hexcaster** *(archetype)* | 1 | `both` | `70` | `12` (hex bolt, `11 m/s`) | Ranged caster on Skeleton_Warrior (purple tint, hand orb). Holds `7 m`, strafes, fires a dodgeable bolt (`0.8 s` wind-up, `Spellcast_Shoot`). Close the gap; flees at `30%` HP. |
| **Grave Brute** *(archetype)* | 1 | `both` | `260` | `24` (ground slam, `3.2 m` AoE) | Barbarian ×1.18, 2H axe. `1.05 s` wind-up with a growing red floor ring; slam hits player **and allies**, cracks the ground, broadcasts noise. No flinch on lights, knock-back `0.3`, never flees. Dodge out of the ring, punish the `1.3 s` recovery. |
| **Shade Stalker** *(archetype)* | 1 | `BOTH_STATEFUL` | `90` | `14` (dual stab; `×1.6` from behind) | Fast Skeleton_Rogue (blue tint). Blinks behind its target (`6 s` cooldown) before a token swing, evade `0.75`, flees at `35%`. Exists in both realms. |

### 3.2 Behavioral Details
- **Skeleton Guard** (`Hall of Echoes`):
  - Acquires player within `~22.0 m`, closes distance directly/via nav, visible melee wind-up (`21` scaled dmg), `~0.8 s` post-attack recovery.
  - Features 1-time `3.0 s` fall-down self-revive (`State.STUNNED`) at `50%` HP (`health_changed` emitted to update `FloatingHPBar`, preserved across knockdown/backstab post-hit hooks; bypassed by `"environmental"`, `"pit"`, `"player_execution"`, `"execution"`) before final death.
- **Phantom Twin** (`Hall of Echoes`):
  - `BOTH_STATEFUL`, translucent and harmless in `REALITY` (`can_attack_now() == _mirror_now()`, `is_hittable_now() == _mirror_now()`): circles without requesting attack tokens or freezing, cancels any windup/attack immediately when shifting to Reality, and lunges along its tracked `get_facing_direction()` (`28` scaled dmg, `~1.0 s` recovery) in `MIRROR` or merged realms.
  - Killing in Mirror awards base `+100` + `+200 Mirror Kill` (combo multiplied).
  - *Pacing cue*: Hall starts with 2 Skeletons in Reality; defeating 1st Skeleton pulses a subtle Mirror hint reminding player of Phantom Twins (never locks `Q`).
- **Shielded Guard** (`Collapsed Gallery`, after anchor):
  - Same world transform in both realms.
  - In **Reality**: raised frontal shield (`is_shield_raised() == false` when `STAGGER`, `STUNNED`, `MIRROR`, or merged) deflects light attacks cleanly (`0` chip + metallic spark) and mitigates heavy attacks without staggering (`player_execution` pierces block). Attacks via shoulder-pullback shield bash (`28` scaled dmg).
  - In **Mirror**: shield vanishes; vulnerable spectral torso can be staggered and burst down by Heavy (`60 dmg`) + Light combo.
  - Defeat opens Gallery exit gate (player must have already repaired Reality bridge via Anchor to pass safely if returning to Reality).
- **The Warden** (`Execution Arena`, Phase 1 & Phase 2):
  - **Shared 1,500 HP pool** (`_phase2_threshold() = 999`) across Reality and Mirror; Phase 1 incoming hits clamp to `maxi(1, health - _phase2_threshold())`, and Phase 2 caps single hits at `phase2_max_hit = 120`.
  - **Phase 1 (`1500 -> 1000 HP`)**:
    1. Armored in Reality (`phase1_reality_armor_cap = 5`) so shifting is rewarded.
    2. Pre-queues alternating **Cleave** (`2.8 m`, `28 dmg`) or **Lunge** (`5.0 m`, `35 dmg`, tracked `get_facing_direction()`) at the end of recovery / reset so chase distance always matches the upcoming move.
    3. Plays clear **`0.90 s` wind-up telegraph** visible in the active realm.
    4. Executes strike -> enters **`1.4 s` recovery window** where Mirror reflection exposes glowing chest rune (`is_chest_rune_exposed` clears cleanly whenever leaving `State.RECOVER`, including on heavy-punish `STAGGER`, preventing infinite Phase 1 stagger-locking).
    5. Player shifts to Mirror (`Q`) and punishes exposed echo (Heavy / Light combo) -> staggers Warden & drains shared HP -> returns to guarded loop. Must never soft-lock if player misses a window.
  - **Phase 2 Transition (`HP <= 999`)**:
    - Clears telegraph flash & attack token, ends active hitbox swing, transitions to `State.STAGGER` during `1.60 s` shatter sequence -> plays Mirror Plane shatter -> **one-way transition**.
    - HUD banner/chip changes to **`REALMS MERGED`**; `Q` is locked/disabled (`shift_locked = true`).
  - **Phase 2 (`500 -> 0 HP`)**:
    - Directly vulnerable in Reality to all player attacks (Light, Heavy, Landing). Uses faster cleave combos & shorter lunge recovery. *Implemented (Claude Pass C)*: wind-up `0.65 s`, recovery `0.85 s`, and every Cleave **chains** straight into a Lunge with a `0.45 s` (still red-telegraphed) wind-up, skipping recovery (`phase2_chain_windup`, `phase2_chain_enabled`). At `0 HP`: death animation, exit gate lifts, run timer stops, Results sequence begins.

### 3.3 Squad Tactics, Hit Reactions & Gore (`SquadCoordinator`, `EnemyAI`, `EnemyBase`)
- **Attack tokens**: max `2` simultaneous attackers (1 if squad < 3), `0.42 s` minimum gap between attack starts. Token priority = time waited (active waiters keep their first-request timestamp via `_last_wait_touch` heartbeats) + up to `+1.2 s` for standing behind the player (pincer). Released on recovery / stagger / death; ranged (`bolt`) enemies request tokens only inside `[preferred_range * 0.45, attack_range]`, and poise counters preserve held `WINDUP` tokens.
- **Holding ring**: non-token enemies circle at `attack_range + ring_margin (1.7)` with angular spacing (62°), drift toward the player's flank, back off if crowding, separation steering, random orbit flips; `_process_chase()` applies gravity and probes `_has_floor_ahead()` along with all active `EnemyAI` states.
- **Alert**: first spotter taunts `0.55 s` and alerts every idle ally in the same `encounter_id` or within `join_radius (22 m)` (`alert_radius = 38 m`); opening stagger/backstab/knockdown hits on an idle enemy still set target, clear `_reaggro_block`, and alert squadmates.
- **Evade**: uncommitted `CHASE`/`RECOVER` enemies (never `IDLE` with null target) within `3.4 m` in the player's front cone may side-step (`_evade_timer` decays in `CHASE`/`bolt` and clears on exiting `CHASE`).
- **Flinch & poise**: light hits flinch (`0.26 s`) unless ATTACK or past 50% of WINDUP (hyper-armour). After `max_flinch_chain` (2; Shielded 1) flinches → `1.6 s` poise; `70%` chance of an immediate fast counter-swing (gated on `can_attack_now()` and token ownership). Warden never flinches on lights. `_hit_flash()` validates overlays via `_is_overlay_still_valid()` so cleared windup telegraphs are never restored.
- **Enrage**: last survivor of a squad of ≥2 moves `1.25x`, winds up `0.8x`, recovers `0.7x`; `_peak_engaged` resets to `0` on `SquadCoordinator.reset()` and whenever active engagement drops to empty (`refresh_engaged_peak()`).
- **Every hit**: knock-back (`knockback_scale`: Warden `0.15`, Shielded `0.55`, Phantom `1.3`), hit-lean spring on `ModelRoot`, white flash overlay, directional blood spray + floor splat decals, wound drip below 55% HP. Spectral (Mirror-only) enemies bleed emissive cyan ichor. **WardenBoss, ShieldedGuard, and SkeletonGuard now feature distinct dark hostile armor materials with pulsing red glow emissions.**
- **Death**: `GoreFX.dismember()` splits the rig into per-bone physics gibs posed exactly as the killing frame (meshes grouped by dominant skin bone; helmets/weapons follow their bone attachment), blood fountain + pool, gib bleed trails; gibs fade after ~7 s (cap 80, decals cap 48).
- **Loadouts** (`CharacterLoadout`): Knight player = `1H_Sword + Badge_Shield`; Knight Shielded Guard = `1H_Sword + Rectangle_Shield`; Barbarian Warden = `2H_Axe`; Skeleton Warrior borrows Barbarian `1H_Axe` + Knight `Round_Shield`; Skeleton Rogue borrows Knight `1H_Sword` + offhand. Archetype enemies and allies take `keep_props` / `borrow_props` from their resources.

### 3.4 Threat & Aggro (2026-11-17 — replaces "always target the player")
- **Threat table** per enemy (`instance_id -> threat`) over the player and every `squad_ally`. Target = highest *score* (threat × `0.45` if the entity is already saturated by `max_enemies_per_target = 3` other enemies), re-evaluated every `0.3 s` with **hysteresis `1.15`** (a challenger must beat the current target by 15 %, so pursuit does not snap just because someone else chipped in). Lost / dead / out-of-range targets are dropped and the table re-evaluated; nothing left -> ALERT at the last known position.
- **Gains**: damage dealt × `damage_threat_mult 1.0`; proximity `7/s × (1 - d/4.5 m)` while aggroed; first sighting `+10`; squad call `+12`; knock-down source `+8`.
- **Decay**: `10 %/s` exponential (Shielded `6 %`, Brute `6 %`); entries under `0.25` are pruned.
- **Taunt** (`apply_taunt`): `+60` flat (`taunt_threat_bonus`) + **lock**. TAUNTED is a modifier: the enemy ignores the soft cap and never waits for an attack token. Taunts affect only the enemy taunted — the rest of its group keeps its own targets (area "take aggro" is an explicit ally order).
- **Taunt FIXATION** (2026-11-17, `taunt_fixation = true`): any real taunt (lock ≥ `3 s`: ally taunts, War Cry, Shield Wall, take aggro) pins the enemy on the taunter **with no expiry** — it ignores its home leash and its lose-sight range and chases forever. It ends only when the taunter is down / untargetable, another real taunt replaces it, `forget()` (Smoke Bomb) wipes it, or the taunter stays > `60 m` away for `5 s`. Short "nudge" taunts (< 3 s, the splash of an area taunt) never override or downgrade an existing fixation (same or different taunter). Taunted enemies cannot flee (`_should_flee()` checks `not is_taunted()`); a fleeing enemy that is taunted turns back to CHASE. Queries: `is_fixated()`, `get_taunter()`.
- **Backstab** (attacker in the rear arc, facing·to_attacker < −0.35): damage `×1.25`, threat `×1.8`, stagger `0.55 s` (Shielded `0.4`; skipped when `backstab_staggers == false` or mid-`ATTACK`), then a **turn-around** (snaps to face and targets the stabber with a `0.2 s` roar unless pinned on another taunter).
- **Knock-down** (`KNOCKDOWN_SOURCES`: `player_landing`, `fin_sunder`, `ally_charge`, `ally_nuke`, `ally_detonate`): STUNNED `1.6 s` (Lie_Down → Lie_Idle → Lie_StandUp), incoming damage `×1.35` while stunned; heavy hits do not cancel `STUNNED` into `STAGGER`, and heavy knockdown sources emit `state_changed`/`staggered` once. Warden is `knockdown_immune`.
- **Realm physics & archetype scaling**: `EnemyBase.evaluate_for_realm()` updates `collision_mask` via `RealmManager.update_actor_collision_mask()` (keeping `HexBolt` & blink rays realm-accurate); `EnemyAI.DAMAGE_SCALE = 1.4` applies once in `EnemyAI._ready()`; `ArchetypeEnemy._try_blink_behind()` checks horizontal wall/gate/blocker LoS + capsule clearance; slam rings track `get_facing_direction()` in world space.
- **States**: ALERT (walk to the noise / call, look around `4 s`, detection ×1.25), FLEEING (once per life below `flee_health_ratio`: Skeleton `0.15`, Phantom `0.25`, Hexcaster `0.30`, Stalker `0.35`, others `0`; runs `flee_duration` then turns and fights), RETURNING (leash: beyond `max_chase_distance` from home — default `22 m`, Warden `80`, Brute `18`, Hexcaster `20`, Stalker `24` — clears threat and walks home, `1.5 s` re-aggro block, snaps home after `14 s` stuck). IDLE roamers patrol within `patrol_radius` (roamers `1.6 m`, archetypes from data) with an edge probe.
- **Alert propagation**: spotter calls squad-mates in the same encounter or within `9 m` straight into CHASE; within `18 m` they come to investigate (ALERT). Ally detonations / brute slams `broadcast_noise` (`14–16 m`).
- **Overhead state glyph** (`StateIcon` Label3D, hidden within 4 m of the camera): `?` alert, `!` roar, `⚔` taunted, `✦ ✦` stunned, `!!` fleeing, `↩` returning.

### 3.5 Ally Squad — "Echoes" (2026-11-17)
| Ally (`res://data/allies/`) | Role | Rig | HP | Speed | Aggro r | Melee | Retreat ≤ | Abilities | TTS voice (Gemini / OpenAI) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `01_brannoc` Brannoc | vanguard | Barbarian ×1.04 (axe + round shield) | `190` | `5.4` | `8` | `20` / `1.1 s` | `25 %` | taunt, charge, bodyguard, revive | Algenib / onyx |
| `02_sera` Sera | skirmisher | Skeleton_Rogue (borrowed blades, cyan tint) | `120` | `6.6` | `9` | `16` / `0.75 s` | `35 %` | taunt, kite, lure, finisher, revive | Puck / nova |
| `03_ivo` Ivo | artillery | Knight ×0.98 (sword, violet tint) | `110` | `5.2` | `10` | `14` / `1.0 s` | `40 %` | nuke (`48` dmg, `3.8 m`, `1.3 s` channel), mine, revive | Iapetus / fable |
- **Spatial awareness (context steering, `SquadAlly._steer_toward_dir` / `_context_pick`)**: every `0.06 s` each ally scores 12 headings = interest (toward the goal, +0.15 keep-heading bias) − 1.6 × danger, where danger = waist-height wall ray within `1.0–2.6 m` look-ahead (speed-scaled), personal space from squad-mates `1.5 m` / player `1.8 m` (×1.4) / enemies `1.1 m` (the engaged target exempt within 2.5 m), the real camera→player sight line and a 2 m bubble around the camera (0.5), enemies winding up a strike that covers the step (0.85); ledges veto a heading. Heading is held between refreshes; speed eases with misalignment and danger, arrival eases over the last 1.5 m; a blocked final spot = stop, no jitter. Standing still also keeps personal space (allies 1.25 m, player 1.45 m) and steps off the camera line only toward open floor. Formation slots must have floor, line of sight to the player, 0.65 m wall clearance, no squad-mate within 1.2 m and must not block the camera — otherwise pulled in toward the player (cached 0.2 s).
- All allies: `damage_taken_mult 0.6`, out-of-combat regen (×3 while retreating; base rates `Brannoc 1.5`, `Sera 0.95`, `Ivo 0.88` -> `>= 125 s` full heal), formation wedge out of the camera line (`(-2.5,0.3)`, `(2.7,0.8)`, `(-2.2,2.4)`…), **Free Leash** (`SquadAlly.has_free_leash() == true` whenever `current` or any queued command is not passive `follow` / `ceasefire`): disables distance & elevation teleports (`_catch_up` only rescues true `PitKillZone` / `y < -20 m` void falls to `_last_safe_pos`, and `_update_stuck` performs local hop + `_unstick_nudge()`). Passive `follow`/`ceasefire` retain `FOLLOW_LEASH` (`19.5 m`, `150 m` camera-visible exemption) catch-up blink with world-layer LOS ray. Personalities only change voice & flavour lines (incl. banter every 50–95 s out of combat and complaints at repeated silly orders).
- **Priority ladder**: PANIC (`massacre`, `ceasefire`, `scatter`) > direct orders / MISSIONS > self-preservation at **critical** HP (< half the retreat threshold) > autonomous combat (follow + auto-engage, retreat below threshold) > idle. Equal-priority finite orders queue; stances replace stances; queued finite orders always run before a resumable stance; a preempted mission resumes afterwards.
- **Mission lock** (`bodyguard`, `kite`, `nuke`, `revive`, `peel`, combos): lower / equal orders queue (`"Mission first…"`), stray hits never retarget the ally; the lock ends on critical HP, a new panic order, `stop`, or the mission target dying.
- **Phased tactics**: approach → provoke (taunt, else dart-in poke) → confirm (`enemy.get_current_target() == ally` within `1.4 s`) → sustain loop. Failures are reported and fall back (3 failed provokes / `9 s` approach -> straight fight; combo partner still signalled).
- **Circle kite**: radius `5.5 m` around a centre that drifts toward the pack; re-path every `0.4 s` (blocked -> reverse and widen `+1 m` up to `8.5 m`, then recentre); re-poke after `1 s` of lost aggro; `ready` handshake only after threat is confirmed **and** `2.6 s` of running. A standalone kite ("bait it", "run in circles", "keep it busy") keeps going until the target dies or `duration` (default `45 s`). **Lure** (`lure_to` Vector3 or `lure: "player"`, "lure it to us"): the circle centre moves to that point at radius `3.2 m`, so the chaser is dragged into the squad; Bait and Ambush uses it, and when the ambush springs the bait turns and attacks.
- **Sneak attack** (`surround` with `side: "rear"`; "sneak attack it", "backstab", "get behind it"): works round on the side it is already on (wide, `3 m` off the enemy's flank) to the point behind the enemy's CURRENT facing, strikes only from the rear arc (backstab ×1.25 dmg + stagger), slips round again if the enemy turns, fights normally if targeted up close. Hammer and Anvil and Distract and Backstab use it.
- **Follow-through**: after Charge + Finish both halves keep fighting the target until it dies (max `10 s`); a kite+nuke "ready" signal is kept even if the nuker is briefly busy; a kiter whose payload was released while it was interrupted finishes instead of freezing (`sustain_after` capped at `3 s`).
- **Combos** (manager handshakes, scarcest specialist filled first): kite+nuke (`ready` → nuker channels on the cluster, `casting` → kiter clears out, `released`); charge+finish (charge `12.5 m/s`, `22` dmg + knock-down → `knocked` → finisher gets behind, `55` heavy → `finished`); lure+detonate (trapper plants a `3 m` mirror sigil off the player's flank → `planted` → lurer provokes and runs through it → detonate when a chaser is inside or after `15 s`, `≥50` dmg + knock-down). Downed / retreating > 4 s participant -> substitute by role with a voice line, else **solo** variant, else abort cleanly. Combos time out at `40 s`.
- **Bodyguard**: guard spot `1.7 m` from the ward toward the threat centroid every tick (not beside it); intercepts enemies within `6 m` of the ward (taunting ones on the ward), leash `8.5 m`; ward = player, ally, or `objective` (nearest switch / mechanism target); ward down -> "Standing by" and stand down.
- **One message = one batch** (`AllySquadManager.begin_batch / end_batch`, also wraps each LLM turn): several orders for the SAME ally run as a **chain** in order; stances in the middle of a chain (`follow`, `hold`, `position`, `rearguard`, `overwatch`, `retreat`) become timed steps that complete on arrival (or `step_sec` / `6 s` cap). Different allies get different chains from one sentence; "everyone else / the rest" = allies not named elsewhere; pronouns ("it", "him", "that one") reuse the enemy named earlier; repeated verbs for the same ally merge ("bait the brute and run in circles" = one kite). Old stances are superseded by a new chain; older missions keep their lock.
- **Movement / fun / talk orders** (2026-11-17): `position` (behind — staggered off the camera line —, front, left, right, close, far / "get away"), `rearguard` (`3.6 m` behind facing back, intercepts anything behind the player within `10 m`), `ranged` (holds `5.5–9.5 m`, bolts for `0.8×` melee every `1.35×` cooldown, backs off when engaged, keeps picking the nearest until clear), `circle` (laps round the player `5 s`), `face`, wait N s (`hold` + `step_sec`), emotes (wave, cheer, sit, bow, salute, spin, flex, laugh, clap, point, kneel, nod, shrug, backflip, lie down), `chat` small talk (greet / thanks / praise / joke / intro / opinion / mood / sing / story / … answered in character, no movement; an ally addressed with no order = chat, not "confused").
- **Auto-rally** (`AllySquadManager._tick_rally`, `rally_enabled`): player below `35 %` HP or an ally below `40 %` with an enemy on them (chasing them within `13 m`, or aggroed within `7 m`) → every other able ally (not on a panic order, revive or combo) cuts in with a `bodyguard` on them (ORDER priority, so a fresh player order still wins) and a call-out; ends when they are back above `55 %`, nothing is on them for `2.5 s`, or they go down; interrupted orders resume (hold keeps its spot); `4 s` cooldown per ward.
- **Other orders**: attack (selector / type / `ally:<Name>`'s target), split (left / right / centre lanes), take aggro (area taunt of everything on the player), peel, hit-and-run (in, strike, out `5.5 m`, `16 s`), hold, follow, retreat, nuke, taunt, revive, hunt (scares ambient wildlife — they have no HP), destroy (safe breakables only; never the boss mirror plane), interact (switches / chests), status, stop, auto-engage on/off, jump N (clamped `1–12`), dance, emote. Unknown verbs / nonsense -> a "confused" line, never a crash.
- **Signature skills** (`AllySkill` sub-resources; used automatically when their `auto_use` rule fires — max one per ally per 1.5 s, defensive-only under ceasefire — and on command; a commanded skill cuts in and the interrupted order resumes):

| Ally | Skill | Effect (data values) | CD | Auto rule |
| :--- | :--- | :--- | :--- | :--- |
| Brannoc | War Cry | taunt all within 7 m (3 s lock, +40 threat, shove), allies within 8 m +25 % damage for 6 s | 14 s | swarmed (≥3 aggroed near him or the player) |
| Brannoc | Shield Wall | self −70 % damage, allies within 4.5 m −50 %, taunts nearest 3, 6 s | 18 s | protect (a friend targeted by ≥2, or he is by ≥3) |
| Brannoc | Ground Breaker | 18 dmg + 1.6 s knock-down to all within 3.2 m | 12 s | cluster (≥2 aggroed within radius) |
| Sera | Shadowstep | blink behind an enemy ≤12 m, 38 heavy stab (backstab ×1.25) | 8 s | engaged |
| Sera | Fan of Blades | 14 dmg to up to 3 enemies within 9 m | 10 s | cluster |
| Sera | Smoke Bomb | every enemy within 5 m `forget()`s her; −50 % dmg 1 s | 16 s | self_chased_low (<50 % HP, chaser within 3.5 m) |
| Sera | Flurry | 5 × 9 dmg on one enemy | 9 s | stunned_target |
| Ivo | Mirror Barrage | 1.3 s channel, 48 dmg + knock-down on a 3.8 m circle (tracks the target) | 9 s | cluster (best cluster ≤12 m) |
| Ivo | Mending Light | heal ally / player 18 % max HP (≤14 m, manual/command only) | 12 s | never |
| Ivo | Mirror Ward | 40-point damage ward for 8 s on an ally or the player | 15 s | ally_pressed (targeted by ≥2) |
| Ivo | Chain Arc | 22 / 16 / 11 dmg bouncing between up to 3 enemies ≤5 m apart, 0.8 s stun each (only on landed damage; hops continue if earlier target dies) | 7 s | engaged |

- **Strategies** (`SquadStrategies.LIST`, 20): focus_fire, pincer (flanks at ±100°), surround (even ring), hammer_and_anvil, shield_wall, hold_the_line (line 3 m toward the threat, 2.2 m spacing), divide_and_conquer (distinct targets), tank_and_spank, pick_off_wounded, casters_first, protect_the_weak, bait_and_ambush (ambush springs when an aggroed enemy enters 4.5 m), guerrilla, crowd_control, overwatch (artillery hangs 6 m back and fires its ranged skills), escort, retreat_and_regroup, distract_and_backstab, kite_train, berserker_rush. Strategies replace current non-panic orders (never override `PANIC` orders and cancel overridden combos); roles fall back to `any`, so any ally count works.
- **Enemy Marking & Region Detection + Targeting**: Aiming (`T` / `MMB`, up to `180 m`) toggles up to `4` FIFO marks (`M1..M4`; `X` clears) in `WorldIntel`. Marking keeps that enemy tracked regardless of distance/facing and continuously detects all other active enemies inside an `18.0 m` radius around each mark (`10.0 s` combat-death zone linger). Orders go through `WorldIntel.resolve` — omitted targets & `"that one"` auto-prefer `M1` when marked, supporting `M1..M4`, `"marked"`, `"marked group/area/region"`, `"<desc> near M#"`, internal IDs (`E3`), descriptors, relations, and `is_camera_visible()` (`<= 140 m`). Dead players (`State.DEAD`) are excluded from heals, wards, and `_weakest_friend_name()`.
- **DOWNED**: at 0 HP; targetable = false, label "DOWN — revive". Downed allies keep both Reality & Mirror floor layers (`Q`-safe), rescue from pits/voids (`_process_downed`), and substitute/reject ordered `revive` (`10 s` unreachable timeout prevents `MISSION` soft-locks). Revive by the player (Interact within `2.6 m`, `50 %` HP) or by order (`2.2 s` channel, `45 %`). Player respawn regroups and fully heals the squad (`_rally` & `_rally_cooldown` cleared on `regroup(true)`).

---

## 4. Appendix A: Initial Tuning Sheet & Appendix B: Terminology

### 4.1 Appendix A — Baseline Numeric Values (Playtest & Tune Log Target)
| Parameter | Baseline Value | Tune Trigger Condition |
| :--- | :--- | :--- |
| **Combat Scales** | **+30% HP, +40% Dmg** | General difficulty tuning (2026-11-18). |
| Player Max Health | `100` | First-run deaths too frequent or trivial. |
| Player Run Speed | `4.5 m/s` (`450 cm/s`) | Traversal feels sluggish or uncontrollable on stones/bridge. |
| Dodge Duration / i-frames | `0.55 s` / `0.18 s` | Player cannot reliably dodge Warden Cleave/Lunge. |
| Light Combo Damage | `25 / 25 / 35` | Standard TTK too fast/slow for 10–15 min target. |
| Heavy / Landing Damage | `60` / `60` (`2.2 m` radius) | Heavy feels unrewarding or Landing slam dominates melee. |
| Shift Cooldown / Transition | `0.60 s` / `0.15–0.25 s` | Flicker spam vs sluggish feeling during combat weaving. |
| Combo Timeout | `4.0 s` (x2 @ 3, x3 @ 6) | Impossible to keep chain across short movement/shifts. |
| Skeleton HP / Dmg | `325` / `15` (`0.8 s` rec) | Basic duel lasts outside ~10–20s. |
| Phantom HP / Dmg | `260` / `20` (`1.0 s` rec) | Mirror combat feels identical or unfair. |
| Shielded Guard HP / Dmg | `812` / `20` | Encounter drags or Reality chip too easy to brute-force. |
| Warden HP / Recovery Window | `3250` / `1.4 s` | Boss <2 min or >6 min; Phase 1 opening too tight to shift+strike. |
| Pillar Fall Damage / Warning | `150` Enemy / `40` Player (`2.5 m` radius, `0.6 s` warn) | Enemies miss zone or player unfairly clipped. |

> **Enemy Tuning Additions (2026-11-18 / 2026-11-19):** Skeleton revive confirmed at 50% HP (once, bypassed by execution damage e.g. `player_execution`). Distinct enemy visuals (dark hostile armor, red emissions) implemented for WardenBoss, ShieldedGuard, and SkeletonGuard. Added enemy regeneration (passive) and distant-order tether logic to combat controller. WardenBoss retuned to 1500 Max HP with Phase 2 transition at 999 HP. Finishers lock facing and hit detection directly onto the finisher target. Ally personal space push tuned to 1.35m radius (1.5x scalar) preventing combat crowding.

> **Live code values (audited Claude Pass C, 2026-11-18)** — `_init()` of each enemy script: Skeleton `325 HP` (authored 100 * 3.25) `/ 15 dmg / 0.55 s windup / 0.80 s rec`; Phantom `260` (80 * 3.25) `/ 20 / 0.65 / 1.00`; Shielded Guard `812` (250 * 3.25) `/ 20 / 0.65 / 0.90`; Warden P1 Cleave `20` / Lunge `25`, windup `0.90`, recovery `1.40`, Max HP `3250`; P2 windup `0.65`, recovery `0.85`, chain windup `0.45`. Player (`player_controller.gd` export defaults; `player.tscn` doesn't override them) still uses dodge `0.48 s` / i-frames `0.24 s` and run speed `5.5`, which differ from the `0.55/0.18` and `4.5` baselines above — intentional Pass 5 feel tuning, not changed here.

> **Archetype & ally tuning (2026-11-17)** lives in data: `data/enemies/{hollow_hexcaster,grave_brute,shade_stalker}.tres` and `data/allies/0N_*.tres` (values in §3.1 / §3.5). Threat tuning = `EnemyAI` "Threat & Aggro" exports (§3.4).

### 4.2 Appendix B — Locked Glossary
- **Reality**: Warm physical limestone/amber state of the arena.
- **Mirror**: Cool spectral cobalt/moonlight counterpart state.
- **Realm Shift (`Q`)**: Instant toggle preserving player world transform.
- **Realm-Reactive Actor**: Node whose mesh, collision, and AI respond to Reality/Mirror via `RealmReactive`.
- **Mirror Kill**: Killing any enemy while `MIRROR` is active (`+200` bonus, combo-multiplied).
- **Echo / Squad Ally**: An AI companion (`SquadAlly`) — a champion the mirror preserved, fighting beside the player.
- **Threat**: Per-enemy aggro value per entity; the highest-threat entity is the enemy's target.
- **Environmental Kill**: Killing blow dealt by authored hazard such as Cracked Pillar (`+250` bonus, combo-multiplied).
- **Registered Geometry**: Reality & Mirror counterparts aligned to identical world-space landmarks.
