# PARALLAX — Scoring, Leaderboard, HUD, Menus & Art/Audio Direction

> Encapsulates GDD Sections 8, 9, and 10.

---

## 1. Scoring, Combo & Rank Rules (GDD Section 8)

### 1.1 Score Event Awards
| Event | Base Points | Multiplied by Combo? | Award Rule |
| :--- | :--- | :--- | :--- |
| **Enemy Kill** | `+100` | Yes (`x1 / x2 / x3`) | Awarded once per standard enemy death (`Skeleton`, `Phantom`, `Shielded Guard`). |
| **Environmental Kill** | `+250` | Yes (`x1 / x2 / x3`) | Bonus when authored hazard (e.g., Cracked Pillar) deals the killing blow. |
| **Mirror Kill (Realm Trick)** | `+200` | Yes (`x1 / x2 / x3`) | Bonus when any enemy is killed while `current_realm == MIRROR`. |
| **No-Hit Encounter** | `+500` | **No** (flat) | Awarded once at encounter end if player took `0` damage during that encounter. |
| **Warden Defeat** | `+1,000` | **No** (flat) | One-time boss completion award at Warden HP `<= 0`. |
| **Completion Time Bonus** | `0` to `+1,000` | **No** (flat) | **`TimeBonus = max(0, 1000 - int(elapsed_seconds))`** (`400` at 10 min; `0` at 16m40s). |

### 1.2 Combo Multiplier Table
- `0–2` consecutive successful hits -> **`x1.0`**
- `3–5` consecutive successful hits -> **`x2.0`**
- `6+` consecutive successful hits -> **`x3.0`**
- **Timeout**: `4.0 s` without landing a hit (misses do NOT reset immediately or extend timer).
- **Reset on Hit**: Taking enemy or pillar damage resets combo to `x1`.
- **Shift Preserved**: Pressing `Q` does **not** break combo.

### 1.3 No-Hit Encounter Boundaries
Three combat encounters track separate no-hit flags (`begin_encounter()` when gate seals/combat starts -> `end_encounter()` when exit gate opens):
1. `Hall of Echoes`
2. `Shielded Guard` (far platform of Collapsed Gallery)
3. `The Warden` (Execution Arena)
*(Tutorial sections `Entry Vestibule` and `Mechanism Chamber` do NOT grant `+500` No-Hit awards.)*

### 1.4 Rank Thresholds & Local Top-5 Leaderboard
| Rank | Score Range |
| :--- | :--- |
| **S** | `5,000+` |
| **A** | `4,000 – 4,999` |
| **B** | `3,000 – 3,999` |
| **C** | `< 3,000` |

- **Storage**: Offline `ConfigFile` at `user://leaderboard.cfg` (no network/account). Settings saved in `user://settings.cfg`.
- **Fields per entry**: `initials` (max 3 uppercase chars), `score: int`, `time_sec: float`, `rank: String`, `timestamp: String`.
- **Sort order**: `score` descending -> tiebreak `time_sec` ascending -> tiebreak earlier date retained.
- **Submission rule**: Recorded **only** after defeating The Warden and reaching Results. Abandoned runs are not saved. Leaderboard reset allowed only via confirmation dialog inside Options menu.

---

## 2. Shared HUD, Menus & Feedback Contract (GDD Section 9)

### 2.1 Single Shared `HUD.tscn` Layout Rules
- Instantiate **one `HUD.tscn`** in `Main.tscn` across all 5 sections. Never rebuild separate HUDs per room.
- Keep anchors, typography, diamond/chamfered dark panels (`~75–85%` opacity, fine gold border `#C8A860`), bar heights, and spacing **identical** across Reality and Mirror. Only numeric values and the active realm highlight chip change.
- **Keep gameplay HUD free of decorative game title logos** (save `PARALLAX` logo for Title & Results screens).

| Anchor | Element | Visibility | Behavior |
| :--- | :--- | :--- | :--- |
| **Top-Left** | Emblem + Health bar + `100 / 100` numeric text + combo pips | Always | Decreases on damage with brief red hit flash; never color-only. |
| **Top-Center** | `REALITY` chip / swap icon / `MIRROR` chip + `Q` keycap | Always | Active chip illuminated (Amber `#E69938` vs Cobalt `#33B5FF`). Rejected shift pulses chip amber/red. Boss Phase 2 switches display to `REALMS MERGED`. |
| **Top-Right** | `SCORE 001250`, `COMBO x3`, `⏱ 02:34` elapsed timer | Always | Score ticks pop briefly; timer freezes when paused or on run completion. |
| **Bottom-Left** | Weapon diamond slot (Sword icon) | Always | Single sword weapon only (no weapon wheel). |
| **Bottom-Right** | Action diamonds: `LMB ATTACK`, `RMB HEAVY`, `SPACE DODGE`, `F LAND`, *(contextual `E INTERACT`)* | Always / `E` contextual | Dim `F` while grounded or `E` when out of range; never jump/relocate anchors. |
| **Bottom-Center** | `THE WARDEN` label + wide red Boss HP bar (`%` / fill) | Boss Only | Hidden outside Execution Arena; must not push/resize any other HUD widget. |

### 2.2 Required Screens
1. **Title Screen**: `PARALLAX` logo, tagline *"Same arena. Different rules."*, colosseum backdrop, buttons: `Start`, `Leaderboard`, `Options`, `Quit`.
2. **Pause Menu (`Esc`)**: `Resume`, `Restart Section`, `Restart Run` *(confirm)*, `Options`, `Main Menu` *(confirm)*.
3. **Tutorial Prompts**: Compact inline prompt near action (`WASD / Mouse`, `Q: Shift`, `E: Interact`, `F in Air: Landing Attack`) -> auto-dismisses on first successful execution.
4. **Death Overlay**: Brief fade + automatic respawn at current section checkpoint (no extra confirmation clicks).
5. **Results Screen**: Breakdown of Score, Time, Time Bonus, Rank (`S/A/B/C`), 3-letter Initials entry if Top 5 qualified -> `Submit`, `Leaderboard`, `Replay`, `Main Menu`.
6. **Leaderboard Screen**: Top 5 table (`#`, Initials, Score, Time, Rank, Date) + `Back`.
7. **Options Screen**: Master / Music / SFX volume sliders, Mouse Sensitivity, Invert Y toggle, Display Mode (Fullscreen / Windowed) & Resolution, `Restore Defaults`, `Reset Local Leaderboard` *(confirm)*, `Apply`, `Back`.

### 2.3 Required Player Feedback Cues
- **Shift Success**: `0.15–0.25 s` subtle screen-edge ripple + lighting color lerp + crisp glass-harmonic SFX.
- **Shift Rejected**: Short realm chip shake/red-amber pulse + low muted thud/rejection tone.
- **Enemy Hit**: Hit sparks, brief stagger/flash, punchy impact SFX, floating/ticking score increment (avoid nausea-inducing heavy camera shake).
- **Pillar Collapse**: `0.6 s` fracture orange/amber glow & falling dust -> crack SFX -> deep stone crash + subtle camera impulse -> `150` dmg hit check -> `+250 ENVIRONMENTAL KILL`.
- **No-Hit Encounter**: Toast `+500 NO-HIT ENCOUNTER` when encounter exit gate opens.
- **Boss Phase 2**: Mirror plane shatter VFX + audio sting + HUD banner `REALMS MERGED`.

---

## 3. Art, Animation, Audio & Accessibility Direction (GDD Section 10)

### 3.1 Palette & Lighting Contrast
| Category | Reality State | Mirror State |
| :--- | :--- | :--- |
| **Stone & Sky** | Warm charcoal/limestone `#9C8468`, dusty sunbeams, amber torches `#FF9933` | Deep blue-black slate `#141D2E`, cool moonlight/indigo fog `#335599`, crisp rim light |
| **Banners** | Crimson-red banners with gold Sun emblem | Midnight-blue banners with silver Crescent Moon emblem |
| **Emissives** | Restrained warm ember / pillar fracture glow only | Reserve bright Cyan-Cobalt emissive (`#33B5FF`) strictly for Mirror-only platforms, Phantom Twins, Weak Points & Spectral Bridge |
| **UI Accent** | Warm Gold/Amber `#E69938` | Electric Spectral Cyan `#33B5FF` |

### 3.2 Protagonist Visual Identity
- Dark-haired female warrior (high ponytail), ragged deep-red cape (primary color anchor in BOTH realms), dark leather & iron armor, steel broadsword. Never alter silhouette/costume across realms.

### 3.3 Minimum Animation Set per Actor
- **Player**: `Idle`, `Run`, `Jump`, `Fall`, `Land`, `Dodge`, `Light_1/2/3`, `Heavy`, `Landing_Attack`, `Hit`, `Death`, `Interact`.
- **Skeleton Guard**: `Idle`, `Chase`, `Windup`, `Attack`, `Recover`, `Hit`, `Death`.
- **Phantom Twin**: `Idle_Hover`, `Approach`, `Lunge_Windup`, `Lunge`, `Recover`, `Hit`, `Dissolve_Death`.
- **Shielded Guard**: `Idle`, `Shield_Guard`, `Bash_Windup`, `Bash_Attack`, `Recover`, `Exposed_Stagger`, `Hit`, `Death`.
- **The Warden**: `Idle`, `Cleave_Windup/Attack/Recover`, `Lunge_Windup/Attack/Recover`, `Stagger`, `Phase2_Chain`, `Death`.

### 3.4 Audio Checklist & Accessibility
- **Music**: 1 continuous dark orchestral/ambient track + subtle high-intensity stem/layer during Execution Arena boss fight.
- **SFX**: Distinct 2-part Reality/Mirror glass-harmonic shift cue, wind/arena drone, sword whooshes, flesh/bone/metal shield clangs, pillar crack warning + collapse boom, Warden telegraph stings, mirror shatter sting.
- **Accessibility**: Color-blind safety (text labels + distinct sun/moon icons everywhere), readable 1920x1080 & 1280x720 scaling, visible visual telegraphs paired with audio cues, sensitivity + Invert-Y + audio mix sliders.
