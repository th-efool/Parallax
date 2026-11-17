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
| **Finisher** | `+150` | Yes (`x1 / x2 / x3`) | Each critical-hit finisher executed (Rend / Sunder / Phantom Step — see `03` §2.2b). |
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

### 2.2 Required Screens (Implemented in `scripts/ui/`)
1. **Title Screen** (`scripts/ui/title_screen_controller.gd` — `TitleScreenController`): `PARALLAX` logo, tagline *"Same arena. Different rules."*, dismissible `<= 5.0s` opening quote card (*"They built a mirror to preserve champions. It learned to preserve their deaths."*), buttons: `Continue Saved Run` (auto-shown when `user://savegame.cfg` has an active run), `Start New Run`, `Leaderboard`, `Options & Controls`, `Quit`.
2. **Pause Menu (`Esc`)** (`scripts/ui/pause_menu_controller.gd` — `PauseMenuController`): `PROCESS_MODE_ALWAYS`, freezes `SceneTree.paused` and `RunState` timer; auto-builds interactive UI if empty; actions: `Resume`, `Save Checkpoint` (with `SaveStatusLabel` feedback), `Restart Section`, `Restart Run` *(confirm)*, `Options & Controls`, `Save & Main Menu` *(confirm + auto-save)*. Ignores `Esc` toggle while `OptionsScreen` or `LeaderboardScreen` subscreen is open on top.
3. **Tutorial Prompts** (`scripts/ui/hud_controller.gd` — `HUDController`): Compact inline prompt near action (`get_tutorial_prompt_text()` dynamically reflects live keybindings for `WASD`, `Q: Shift`, `E: Interact`, `F in Air: Landing Attack`) -> auto-dismisses on first successful execution (`mark_tutorial_completed()`).
4. **Death Overlay** (`scripts/ui/death_overlay_controller.gd` — `DeathOverlayController`): Brief `0.65s` non-blocking fade + automatic respawn at current section checkpoint (no extra confirmation clicks).
5. **Results Screen** (`scripts/ui/results_screen_controller.gd` — `ResultsScreenController`): Breakdown of Score, Time, Time Bonus, Rank (`S/A/B/C`), 3-letter Initials entry if Top 5 qualified -> `Submit`, `Leaderboard`, `Replay`, `Main Menu`.
6. **Leaderboard Screen** (`scripts/ui/leaderboard_screen_controller.gd` — `LeaderboardScreenController`): Top 5 table (`#`, Initials, Score, Time, Rank) + `Back`.
7. **Options & Settings Screen** (`scripts/ui/options_screen_controller.gd` — `OptionsScreenController`): `PROCESS_MODE_ALWAYS`, auto-builds a 4-tab interactive UI (`Display_Graphics`, `Sound`, `Controls`, `Gameplay_Save`) when empty:
   - **Display & Graphics Tab**: Screen Type (`Windowed`, `Borderless`, `Fullscreen`), Resolution (`1280x720`..`3840x2160`), VSync (`Disabled`, `Enabled`, `Adaptive`), Graphics Preset (`Low`, `Medium`, `High`, `Ultra`, `Custom`), 3D Anti-Aliasing (`Off`, `2x`, `4x`, `8x MSAA`), Shadow Quality (`Off`, `Low`, `Medium`, `High`), Bloom/Glow toggle, Atmospheric Fog toggle, Brightness/Exposure slider (`0.5..1.5`).
   - **Sound Tab**: Master, Music, and SFX volume sliders (`0..1`), Mute When Unfocused.
   - **Controls Tab**: Interactive key/mouse rebinding buttons (`BindBtn_<action>`) for all 11 gameplay actions with live `PRESS KEY / MOUSE...` listening state (`_input()`), `ConflictWarningLabel` displaying validation errors when a duplicate or reserved key (`ESC`) is pressed, and `Reset Controls to Default` button.
   - **Gameplay & Save Tab**: Mouse Sensitivity slider, Invert Look Y-Axis toggle, Camera FOV slider (`55..95°`), Camera Shake Intensity slider (`0..1`), Combat Hit-Stop toggle, `Clear Active Checkpoint Save (Confirm)`, and `Reset Local Top-5 Leaderboard (Confirm)`.
   - **Bottom Action Bar**: `Apply & Save`, `Restore All Defaults`, `Back`.

### 2.2b UI Kit — "The Cracked Mirror" (Phase 1 of UI overhaul, 2026-11-17)
- `scripts/ui/ui_theme.gd` (`UITheme`): palette consts, `display_font()` (Cinzel) / `flavor_font()` (Cormorant italic) / `body_font()` (Rajdhani). Drop OFL files named in `FONT_*_PATHS` into `assets/fonts/`; until then it falls back to system serif/sans. `UITheme.get_theme()` = shared Theme (sliders, tabs, scrollbars, LineEdit); `UITheme.apply(ctrl)`.
- `ui_frame.gd` (`UIFrame`): chamfered gold-keyline panel, drop-in `PanelContainer` (`pad_h`/`pad_v`, `accent`, `glow`). `ui_divider.gd` (`UIDivider`): rule with centre gem. `ui_fx.gd` (`UIFx`): `wire_button` (hover nudge + `ui_click`/`ui_confirm`), `pop`, `stagger_in`, `fade_in`, `shake`, `count_up`.
- `MenuStyle` keeps its old API but now builds `UIFrame` modals, angular buttons (left gold bar), display-font titles, plus `style_flavor`, `add_mirror_crack`, `add_atmosphere`.
- Shaders `assets/shaders/ui/`: `ui_mirror_crack` (amber|cyan seam, `realm_mix`), `ui_vignette_grain` (vignette, grain, embers), `ui_panel_shimmer` (gold sheen sweep; not yet used).
- HUD (Phase 3): bars/chips/interact plate are painted via each control's `draw` signal in `hud_controller.gd` (`_paint_bar`/`_paint_chip`/`_paint_plate`; `_wire_visuals()` applies fonts + hooks, works on generated or scene HUDs). Ghost-bar/flash/sweep state is animated in `_animate_visuals`; `ComboTimerBar` + `MergedLabel` added under existing clusters.
- Roadmap: Title (full-bleed) -> HUD -> Results -> Pause/Death -> Leaderboard -> Options.

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

> **Grand Journey lighting (2026-11-16)**: Reality = golden-hour HDRI sky (Kloppenheim 06), warm sun `(1.0, 0.78, 0.56)` @ 1.6 from heading `(-0.65, 0, 0.76)` at 20°, sunlit haze fog `(0.82, 0.66, 0.50)`. Mirror = procedural indigo night (stars, aurora, moon where the sun was), moonlight `(0.52, 0.70, 1.0)` @ 0.95, fog `(0.09, 0.15, 0.32)`, every stone surface turns cobalt slate with glowing rune cavities. Merged = violet midpoint. Graphics presets: volumetric fog only at shadow quality ≥ 2 (High/Ultra), SSAO at ≥ 1.

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

### 3.5 Dynamic Audio Mix, Focus & Cursor (Claude Pass C)
| Behaviour | Owner | Rule |
| :--- | :--- | :--- |
| **Bus balance** | `LeaderboardStore.apply_settings()` | User sliders: `Master 1.0`, `Music 0.85`, `SFX 0.90` (linear). Drone `MusicPlayer.volume_db` base `-3 dB` so SFX cut through. |
| **Combat ducking** | `AudioManager._update_dynamic_mix()` | While `EncounterDirector.current_encounter_id` is non-empty (Hall, Gallery guard, Warden), drone ducks a further **`-4 dB`** at `10 dB/s`; restores when the encounter clears or resets. Applied on the player's `volume_db`, never on the user's bus volume. |
| **Master low-pass** | `AudioManager` (`AudioEffectLowPassFilter` named `ParallaxDynamicLowPass` appended to `Master`) | Cutoff glides in log-space: **`700 Hz` while paused**, **`1400 Hz` at `0 < HP < 25`**, otherwise `20.5 kHz` with the effect **bypassed**. Runs on real time (unaffected by hit-stop); released on `_exit_tree`. |
| **Unfocused mute** (QA-A01) | `LeaderboardStore._notification()` | `NOTIFICATION_APPLICATION_FOCUS_OUT` + `mute_when_unfocused` -> mute `Master`; `FOCUS_IN` restores the saved `master_volume`. `apply_settings()` keeps the mute while still unfocused. `is_muted_by_focus()` for tests. |
| **Cursor capture** (QA-D01) | `MainController._update_mouse_mode()` via `SceneTree.process_frame` (works while paused; `Main` is the scene root so it must not use `PROCESS_MODE_ALWAYS`) | `MOUSE_MODE_CAPTURED` during active gameplay (window focused, tree not paused, no visible `title/pause/options/leaderboard/results` screen, player alive); `MOUSE_MODE_VISIBLE` otherwise. `PlayerController` also releases on menus and re-captures on click. Toggle with `manage_mouse_capture`. |

### 3.6 Audio Routing Contract (2026-11-17 overhaul — `scripts/core/audio_manager.gd`)
- **Buses**: `Master`, `Music`, `SFX`, `Ambience` (created at runtime if missing). Weather and fire/room tone go to `Ambience`.
- **Banks**: every folder `res://assets/audio/sfx/<group>/<bank>/` -> one `AudioStreamRandomizer` keyed `"<group>/<bank>"` (random no-repeat, pitch ×1.12 jitter, ×1.06 for `enemy`, ±2 dB). `play_sfx(cue, db_offset)` maps cues through `CUE_BANKS` (e.g. `sword_light` -> `player/sword_light`, `enemy_hit` -> `combat/hit_flesh`), falls back to the legacy procedural WAVs in `SFX_PATHS`, then to synth stand-ins. Per-cue trims live in `CUE_DB`. `play_at(cue, world_pos)` plays a one-shot 3D sound.
- **Music** (two players, equal-power crossfade `music_crossfade_sec = 2.5`, re-evaluated every 0.5 s): `ending` once the Warden is defeated (reset when his HP refills) > `boss` while `EncounterDirector.current_section == EXECUTION_ARENA` > `combat` while an encounter is active > `interior` at player `Z ≥ 44` > `explore`. Per-track trim in `MUSIC_TRIM`. The legacy drone is only the fallback.
- **Player**: footstep cadence = `clamp(1.75 / speed, 0.27, 0.46)` s; `footstep_wet` when `WeatherDirector.get_wetness() > 0.45`, `footstep_sand` at `Z < -40` (causeway), else `footstep` (stone); armour foley on every other step. Heavy swings add `attack_shout`; light combo step ≥ 3 adds one 50% of the time. Hard landings (> 7 m/s) get a loud step and foley. `player_died` -> `player/death`.
- **Enemies**: each `EnemyBase` gets a `Voice` `AudioStreamPlayer3D` (Warden: unit 9, range 70 m; others: unit 4, range 30 m). Kind = Warden / ShieldedGuard (`guard`) / PhantomTwin (`phantom`) / anything else (`skeleton`). `alerted` -> `attack` bark; `attack_telegraphed` -> `attack` (55%); `damaged` -> `hurt` (70%, Warden 45%) + impact layers (`hit_flesh` always, plus `hit_bone` for skeletons and `hit_metal` for guard/Warden); `died` -> `death` + 3D `body_fall`; Warden `boss_phase_changed` -> `warden_roar`. Idle growls every 5–11 s while active and visible.
- **Ambience**: `FireCrackle` 3D loop (range 14 m) attached to every `BrazierLight*`; `RoomTone` (cavern) fades in at `52 < Z < 104` (rampart, gallery and tower). Rain, wind and thunder volume follow `WeatherDirector` profiles.
- **Realm**: shifting to Mirror also plays `world/mirror_whisper`; the Mirror Plane shatter and realm merge add `world/glass_shatter`.

